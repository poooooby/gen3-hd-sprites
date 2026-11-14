-- Driver (dev only): Route 110's Cycling Road (src/scene/models/bridge.lua) read in the game over
-- the player's own cartridge, every block's triangles written to SHOT_DIR/bridge.txt in the form
-- of the dump of Emerald 3DS's buildings.bin (one "P x y ground" a placement, then its triangles:
-- three points in pixels, the shade, the 5-bit colour at the centroid's texel), to diff, and the
-- time the read took.
--   BRIDGE_LAYOUT  the layout (default LAYOUT_ROUTE110)
-- With BRIDGE_RUNS=all (the whole-layout mode) it also writes SHOT_DIR/signs_<LAYOUT>.txt for each
-- layout of BRIDGE_FP_LAYOUTS: the signposts src/scene/signs.lua finds over that layout's own
-- cells, as the battle's build finds them (its sign step, over the layout alone: Emerald 3DS's
-- generator reads a layout alone), to diff with Emerald 3DS's signposts.bin:
--   L id name w h pair coll=<codes|engine|bits:N> middiff=N   (id: the cartridge's layout id,
--                                                              pret's layouts.json index + 1)
--   S x y MID ROWS HEAD HG G   one a sign: its cell, metatile, 16 rows of its silhouette ('%04x',
--                              row 0 the top, bit x pixel x from the left; joined by ','), its
--                              head's in the cell north ('-' for none), the head cell's ground
--                              and its own cell's (hex metatiles, '-' for none)
--   P x y                      each cell whose role (src/scene/roles.lua) is signpost
--   G y MID MID ...            the layout's metatiles, a row a line
--   BRIDGE_SIGNS=outdoor  every outdoor layout of the game instead (and with BRIDGE_SIGNS set the
--                         signs are written whatever BRIDGE_RUNS is); BRIDGE_SIGNS=A,B those
--   BRIDGE_SIGNS_ONLY=1   the signs alone (no bridge, decks or models)
-- Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/bridge_dump.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_bridge"
  local name = env("BRIDGE_LAYOUT") or "LAYOUT_ROUTE110"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._bridgeBlocks) then log("FAIL gen3-hd-sprites exports missing"); return end
  -- the signposts of whole layouts (see the header)
  local function writeSigns()
    -- the scene's locals (src/scene/init.lua: its sign step's inputs), found by name among the
    -- upvalues of its functions, nearest first
    local core
    for _, f in pairs(hd) do
      if type(f) == "function" then
        for i = 1, 255 do
          local n, v = debug.getupvalue(f, i)
          if not n then break end
          if n == "hd" and type(v) == "table" and v.scene then core = v; break end
        end
      end
      if core then break end
    end
    local Scene = core and core.scene
    if not Scene then log("FAIL signs: no scene"); return end
    local roots = { Scene.forBattle, Scene._layoutModels, Scene._findWhy }
    for _, f in pairs(Scene) do if type(f) == "function" then roots[#roots + 1] = f end end
    local function upvalue(want)
      local seen, queue, q = {}, {}, 1
      for _, f in ipairs(roots) do queue[#queue + 1] = { f, 0 } end
      while q <= #queue do
        local f, d = queue[q][1], queue[q][2]
        q = q + 1
        if not seen[f] then
          seen[f] = true
          for i = 1, 255 do
            local n, v = debug.getupvalue(f, i)
            if not n then break end
            if n == want and v ~= nil then return v end
            if type(v) == "function" and d < 2 then queue[#queue + 1] = { v, d + 1 } end
          end
        end
      end
    end
    local World, Signs, Cells = upvalue("World"), upvalue("Signs"), upvalue("Cells")
    local placeBuildings, signPosts, postKey = upvalue("placeBuildings"), upvalue("signPosts"), upvalue("postKey")
    local pixelSource = Scene._pixelSource
    local missing = {}
    for k, v in pairs({ World = World and World.layoutIds, Signs = Signs and Signs.find, Cells = Cells and Cells.build,
                        placeBuildings = placeBuildings, signPosts = signPosts, postKey = postKey,
                        pixelSource = pixelSource }) do
      if type(v) ~= "function" then missing[#missing + 1] = k end
    end
    if #missing > 0 then log("FAIL signs: not found " .. table.concat(missing, ",")); return end
    local NativeTileset = require("src.core.game3.tileset_native")
    local Map, Collision = require("src.core.game3.map"), require("src.core.game3.collision")
    local Runtime = require("src.core.game3.runtime")
    local okIS, IS = pcall(require, "src.core.game3.scripting.interaction_scripts")
    local okP, Perm = pcall(require, "src.core.CollPermissions")
    if not okP then okP, Perm = pcall(require, "src.world.gen2.Permissions") end
    local okMB, MB = pcall(require, "src.core.game3.mb")
    local game = Runtime._game
    local isWall = okP and Perm.isWall or function(c) return c == 0x07 or c == 0xff end
    local isWater = okP and Perm.isWater or function(c) return c == 0x29 end
    local doors = {}
    for _, n in ipairs({ "ANIMATED_DOOR", "PETALBURG_GYM_DOOR", "CLOSED_SOOTOPOLIS_DOOR" }) do
      local v = okMB and MB.id(n)
      if v then doors[v] = true end
    end
    local function hex(v) return v ~= nil and ("%03X"):format(v) or "-" end
    local function rowsText(r)
      local t = {}
      for y = 0, 15 do t[y + 1] = ("%04x"):format(math.floor(r[y] or 0)) end
      return table.concat(t, ",")
    end
    -- one layout: its own cells, in its own coordinates (the window is the layout)
    local function one(L)
      local W, H, g = L.w, L.h, L.grid
      local function raw(x, y)
        local i = (y * W + x) * 2 + 1
        return g:byte(i) + g:byte(i + 1) * 256
      end
      -- the engine's collision codes: an alternate's own (World's `codes`), else its map's layout;
      -- the blockdata's collision bits only where neither has one
      local codes, EL = L.codes, nil
      if not codes then
        for _, id in ipairs(L.maps or {}) do
          local ok, l = pcall(Map.ensureMidLayout, game, id, game and game.data and game.data.maps[id])
          if ok and type(l) == "table" and l.collAt then EL = l; break end
        end
      end
      local beh = okIS and IS.behaviors and IS.behaviors[L.pair] or {}
      local bitsUsed, midDiff = 0, 0
      local cenv = { indoor = not L.outdoor, walled = false, isWall = isWall, isWater = isWater,
                    isSurfable = Collision.isSurfable }
      -- (Hoenn: nothing stands as a cut-out, the build's env.stands)
      function cenv.stands() return false end
      local function inside(x, y) return x >= 0 and y >= 0 and x < W and y < H end
      function cenv.mid(x, y)
        if not inside(x, y) then return nil, nil end
        return raw(x, y) % 1024, L.pair
      end
      function cenv.cell(x, y)
        if not inside(x, y) then return nil end
        local m, c = raw(x, y) % 1024, nil
        if codes then
          c = codes[y * W + x]
        elseif EL then
          c = EL:collAt(x, y)
          if EL:midAt(x, y) ~= m then midDiff = midDiff + 1 end
        end
        if c == nil then
          bitsUsed = bitsUsed + 1
          c = math.floor(raw(x, y) / 1024) % 4 ~= 0 and 0x07 or 0x00
        end
        return c, beh[m]
      end
      local grid = Cells.build(cenv, 0, 0, W, H)
      -- the buildings first (their cells marked: cell.model), as the build stands them
      local okB, errB = pcall(placeBuildings, grid, NativeTileset, function(cx, cy) return nil, cx, cy, L.name, 0, 0 end)
      if not okB then log("signs " .. tostring(L.name) .. ": buildings error " .. tostring(errB)) end
      -- the sign step of init.lua's build
      -- (init.lua's own reader: Emerald's layers off the atlas blobs)
      local layersOf = Scene._signLayers(NativeTileset)
      local okPo, posts = pcall(signPosts, cenv)
      posts = okPo and posts or {}
      local windowPairs, byPrimary = {}, {}
      for j = 0, grid.h - 1 do
        for i = 0, grid.w - 1 do
          local p = grid.rows[j][i].pair
          if p and not windowPairs[p] then
            windowPairs[p] = true
            local primary = Signs.tilesets(p)
            if primary and not byPrimary[primary] then byPrimary[primary] = p end
          end
        end
      end
      local uppers = {}
      for _, f in pairs(posts) do
        local mid, pair = f[1], f[2]
        local via = mid < 512 and byPrimary[Signs.tilesets(pair) or ""] or (windowPairs[pair] and pair) or nil
        if via then
          local _, up = layersOf(mid, via)
          if up then uppers[Signs.upperKey(up)] = true end
        end
      end
      local roles = World.roles(L)
      local warps = {}
      for _, w in ipairs(L.warps or {}) do warps[w[1] .. "," .. w[2]] = true end
      local okS, found = pcall(Signs.find, grid, {
        isWall = cenv.isWall, stands = cenv.stands, layers = layersOf,
        signAt = function(cx, cy) return (L.signs or {})[cx .. "," .. cy] == true end,
        doorAt = function(cx, cy) return warps[cx .. "," .. cy] == true end,
        isHouseDoor = function(b) return doors[tonumber(b) or -1] == true end,
        postAt = function(mid, pair) return mid ~= nil and pair ~= nil and posts[postKey(mid, pair)] ~= nil end,
        postUpper = function(k) return uppers[k] == true end,
        mountainRock = true,
        signpostAt = roles and function(c) return roles.role(c.cx, c.cy) == "signpost" end or nil,
      })
      local coll = codes and "codes" or EL and "engine" or "bits"
      if bitsUsed > 0 then coll = coll .. ":bits" .. bitsUsed end
      local out = { ("L %d %s %d %d %s coll=%s middiff=%d"):format(L.id, tostring(L.name), W, H, tostring(L.pair), coll, midDiff) }
      if not okS then
        log("signs " .. tostring(L.name) .. ": error " .. tostring(found))
        out[#out + 1] = "E " .. tostring(found):gsub("%c", " ")
        found = {}
      end
      for _, s in ipairs(found) do
        out[#out + 1] = ("S %d %d %s %s %s %s %s"):format(s.cell.cx, s.cell.cy, hex(s.cell.mid), rowsText(s.rows),
          s.head and rowsText(s.head) or "-", s.head and hex(s.headGround) or "-", hex(s.ground))
      end
      local nRole = 0
      for y = 0, H - 1 do
        for x = 0, W - 1 do
          if roles and roles.role(x, y) == "signpost" then
            out[#out + 1] = ("P %d %d"):format(x, y)
            nRole = nRole + 1
          end
        end
      end
      for y = 0, H - 1 do
        local t = {}
        for x = 0, W - 1 do t[#t + 1] = ("%03X"):format(raw(x, y) % 1024) end
        out[#out + 1] = ("G %d %s"):format(y, table.concat(t, " "))
      end
      return out, #found, nRole
    end
    -- which layouts
    local which = env("BRIDGE_SIGNS")
    local list = {}
    if which == "outdoor" then
      for _, id in ipairs(World.layoutIds()) do
        local L = World.layout(id)
        if L and L.outdoor then list[#list + 1] = { L.name, L } end
      end
    else
      local names = (which and which ~= "1") and which
        or env("BRIDGE_FP_LAYOUTS") or "LAYOUT_RUSTBORO_CITY,LAYOUT_FORTREE_CITY,LAYOUT_SLATEPORT_CITY"
      for lname in names:gmatch("[^,]+") do list[#list + 1] = { lname, World.layout(lname) } end
    end
    local clock = love.timer.getTime
    local total, t0 = 0, clock()
    for _, e in ipairs(list) do
      local lname, L = e[1], e[2]
      if not (L and L.grid and L.pair) then
        log("signs " .. tostring(lname) .. ": no layout")
      else
        local tl = clock()
        local ok, out, n, nRole = xpcall(one, debug.traceback, L)
        if not ok then
          log("signs " .. lname .. ": DRIVER ERROR " .. tostring(out))
        else
          local f = io.open(dir .. "/signs_" .. lname .. ".txt", "w")
          if f then
            f:write(table.concat(out, "\n"), "\n")
            f:close()
          end
          total = total + n
          log(("signs %s (id %d): %d signs, %d signpost cells, %s; %.0f ms"):format(lname, L.id, n, nRole,
            out[1]:match("coll=%S+ middiff=%d+"), (clock() - tl) * 1000))
        end
      end
    end
    log(("signs: %d layouts, %d signs in %.1f s"):format(#list, total, clock() - t0))
  end
  if env("BRIDGE_SIGNS_ONLY") then
    writeSigns()
    return
  end
  -- (BRIDGE_WHY="LAYOUT,spec,x,y;...": why each stands or not, then nothing else)
  if env("BRIDGE_WHY") then
    local f = io.open(dir .. "/why.txt", "w")
    for item in env("BRIDGE_WHY"):gmatch("[^;]+") do
      local l, sp, x, y = item:match("([^,]+),([^,]+),(%-?%d+),(%-?%d+)")
      for _, line in ipairs(hd._findWhy(l, sp, tonumber(x), tonumber(y)) or { "?" }) do
        f:write(line, "\n")
      end
    end
    f:close()
    log("wrote why.txt")
    return
  end
  local clock = love.timer.getTime
  local t0 = clock()
  local ok, blocks, curbHeight, br = xpcall(hd._bridgeBlocks, debug.traceback, name)
  local t1 = clock()
  if not ok or not blocks then log("FAIL bridge read: " .. tostring(blocks)); return end
  log(("%s: %d blocks, %d faces, %d ramps, read in %.0f ms"):format(name, #blocks, #br.faces, #br.ramps, (t1 - t0) * 1000))
  -- the build as play runs it: a slice at a time (and the longest), then read back from the cache
  if hd._bridgeJob then
    local worst, n, tb = 0, 0, clock()
    local st = hd._bridgeJob(name, 0.004, true, 0.02)
    while st and st.running do
      local t = clock()
      st = hd._bridgeJob(name, 0.004)
      worst, n = math.max(worst, clock() - t), n + 1
    end
    log(("sliced build: %d slices, longest %.1f ms, %.0f ms in all; done %s, %s models, error %s"):format(n, worst * 1000,
      (clock() - tb) * 1000, tostring(st and st.done), tostring(st and st.models), tostring(st and st.error)))
    for _, g in ipairs(st and st.gaps or {}) do log("gap " .. g:gsub("%c%s*", " | ")) end
    local tc = clock()
    st = hd._bridgeJob(name, nil, "cache")
    log(("from the cache: %.0f ms; cached %s, %s models, error %s"):format((clock() - tc) * 1000, tostring(st.cached),
      tostring(st.models), tostring(st.error)))
  end
  -- a footprint as the dump of buildings.bin writes it: 16 rows of 4 hex digits, or "box"
  local function fpText(fp)
    if not fp then return "box" end
    local t = {}
    for z = 1, 16 do t[z] = ("%04x"):format(fp[z]) end
    return table.concat(t, ",")
  end
  local lines, placements = {}, {}
  for _, b in ipairs(blocks) do
    local mesh = hd._bridgeMesh(b, curbHeight)
    local tris = {}
    for _, t in ipairs(mesh.tris) do
      local pos = {}
      local cu, cv = 0, 0
      for k = 1, 3 do
        local p = t[k]
        pos[#pos + 1] = ("%.3f %.3f %.3f"):format(p[1], p[2], p[3])
        cu, cv = cu + p[4] / 3, cv + p[5] / 3
      end
      -- (a centroid on a texel's edge, nudged into the texel after it: the reference's 32-bit
      -- coordinates read either side of the edge)
      local function nudge(c) return math.abs(c - math.floor(c + 0.5)) < 0.01 and math.floor(c + 0.5) + 0.1 or c end
      local x, y = math.floor(nudge(cu)), math.floor(nudge(cv))
      local col = "-"
      if x >= 0 and x < b.art.w and y >= 0 and y < b.art.h then
        local o = (y * b.art.w + x) * 4
        local px = b.art.px
        local function c5(v) return math.floor(math.floor(v * 255 + 0.5) / 8) end
        col = ("%d,%d,%d,%d"):format(c5(px[o + 1]), c5(px[o + 2]), c5(px[o + 3]), px[o + 4] >= 0.5 and 1 or 0)
      end
      tris[#tris + 1] = ("%s %.2f %s %s uv=%.2f,%.2f"):format(table.concat(pos, " "), t.shade or 1, col,
        tostring(t.tag), cu, cv)
    end
    table.sort(tris)
    for _, p in ipairs(b.placed) do
      placements[#placements + 1] = { p[1], p[2], b.ground, tris, b }
    end
  end
  table.sort(placements, function(a, c) if a[2] ~= c[2] then return a[2] < c[2] end return a[1] < c[1] end)
  for _, pl in ipairs(placements) do
    lines[#lines + 1] = ("P %d %d %d %d"):format(pl[1], pl[2], pl[3], #pl[4] * 3)
    lines[#lines + 1] = ("F %s T %d"):format(fpText(pl[5].footprint), pl[5].top)
    for _, t in ipairs(pl[4]) do lines[#lines + 1] = "  " .. t end
  end
  local function write(file, out)
    local f = io.open(dir .. "/" .. file, "w")
    if not f then log("FAIL cannot write " .. file); return end
    f:write(table.concat(out, "\n"), "\n")
    f:close()
    log(("wrote %s (%d lines)"):format(file, #out))
  end
  write("bridge.txt", lines)
  -- the deck tables (the bridge's, Fortree's) and every model's footprints in some layouts
  for _, lname in ipairs({ "LAYOUT_ROUTE110", "LAYOUT_FORTREE_CITY" }) do
    local out = {}
    for _, d in ipairs(hd.sceneDecks(lname) or {}) do out[#out + 1] = ("D %d %d %d %d %d"):format(d[1], d[2], d[3], d[4], d[5]) end
    write("decks_" .. lname .. ".txt", out)
  end
  for lname in (env("BRIDGE_FP_LAYOUTS") or "LAYOUT_RUSTBORO_CITY,LAYOUT_FORTREE_CITY,LAYOUT_SLATEPORT_CITY"):gmatch("[^,]+") do
    local out = {}
    -- (BRIDGE_RUNS=1: the runs of hedges, fences and curbs too; BRIDGE_RUNS=all: everything the
    -- battle's window stands - kits, props, the bridge's blocks)
    local runs = env("BRIDGE_RUNS")
    for _, m in ipairs(hd._layoutModels(lname, runs == "all" and "all" or runs ~= nil) or {}) do
      local fps = {}
      for j = 0, m.h - 1 do
        for i = 0, m.w - 1 do fps[#fps + 1] = fpText(m.footprints[i .. "," .. j] or nil) end
      end
      -- (and its ground metatile and patch count, as the dump of buildings.bin has them)
      out[#out + 1] = ("P %d %d %dx%d %s %s %s"):format(m.x, m.y, m.w, m.h, m.name, tostring(m.ground or "-"),
        tostring(m.patches or "-"))
      out[#out + 1] = "F " .. table.concat(fps, " ")
      -- (how its ground was chosen: each candidate's scores, the ring's counts)
      if m.plan then
        local sc, rg = {}, {}
        for _, s in ipairs(m.plan.scores or {}) do sc[#sc + 1] = ("%03X:%d/%d"):format(s[1], s[2], s[3]) end
        for g, n in pairs(m.plan.ring or {}) do rg[#rg + 1] = ("%03X:%d"):format(g, n) end
        table.sort(rg)
        out[#out + 1] = "G " .. table.concat(sc, " ") .. " | ring " .. table.concat(rg, " ")
      end
      local tl = {}
      for _, t in ipairs(m.tris or {}) do
        local pos = {}
        for k = 1, 3 do pos[k] = ("%.3f %.3f %.3f"):format(t[k][1], t[k][2], t[k][3]) end
        tl[#tl + 1] = ("  %s %.2f -"):format(table.concat(pos, " "), t.shade or 1)
      end
      table.sort(tl)
      for _, l in ipairs(tl) do out[#out + 1] = l end
    end
    write("models_" .. lname .. ".txt", out)
  end
  -- (and the signposts of the same layouts, or BRIDGE_SIGNS's)
  if env("BRIDGE_RUNS") == "all" or env("BRIDGE_SIGNS") then writeSigns() end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_bridge"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
