-- Driver (dev only): every cell's role (src/scene/roles.lua) of Emerald layouts, read off the
-- game's own data, printed as Emerald 3DS's `python voxel_cells.py LAYOUT_X` prints them, to diff
-- against it. ROLES_LAYOUTS: layout names, comma separated (LAYOUT_X is the map EM_X). Writes
-- SHOT_DIR/roles_<LAYOUT>.txt and logs timings and how pret's collision bits and the engine's
-- walls compare. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald ROLES_LAYOUTS=LAYOUT_ROUTE104 \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/roles_dump.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_roles"
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
  local clock = love.timer.getTime
  local Roles = dofile("mods/gen3-hd-sprites/src/scene/roles.lua")
  local Runtime = require("src.core.game3.runtime")
  local Dataset = require("src.core.game3.dataset")
  local Rse = require("src.core.game3.rse")
  local NativePack = require("src.import.gba.native_pack")
  local CachePaths = require("src.core.game3.cache_paths")
  local Json = require("src.link.Json")
  local Constants = require("src.core.game3.constants")
  local IS = require("src.core.game3.scripting.interaction_scripts")
  local Perm = require("src.core.CollPermissions")
  local Map = require("src.core.game3.map")
  local cache = Dataset.cache()
  local game3 = Runtime._game
  local maps = game3 and game3.data and game3.data.maps
  if not maps then log("FAIL no maps"); return end
  -- Emerald's behaviour names, as the ids the engine's tables hold (src/core/game3/mb.lua: the
  -- unified ids - FireRed's value where FireRed has the behaviour, 0x100 + Emerald's otherwise)
  local MB = require("src.core.game3.mb")
  local behaviours = {}
  for name in pairs(Constants.of("emerald").metatile_behaviors.byName) do
    if type(name) == "string" and name:match("^MB_") then behaviours[name] = MB.id(name) end
  end

  -- a pair's art, off its atlas blobs
  local arts = {}
  local function artOf(pair)
    local a = arts[pair]
    if a then return a end
    local root = (CachePaths.NATIVE_ROOT or "data/generated/gba/native") .. "/" .. pair
    local function blob(name)
      local b = cache:read(root .. "/" .. name)
      return b and { blob = b, index = Roles.blobIndex(b) } or nil
    end
    local under, over, middle = blob("mids.idx"), blob("mids_over.idx"), blob("mids_mid.idx")
    local pals = Roles.palettes(NativePack.decodePalettes(cache:read(root .. "/palettes.bin")))
    local layers, cells = {}, {}
    a = {
      pixels = function(m, layer)
        local l = layers[m]
        if not l then
          local lo, up = Roles.blobPixels(under, over, middle, pals, m)
          l = { lo, up }
          layers[m] = l
        end
        return l[layer + 1]
      end,
      cell = function(m)
        local c = cells[m]
        if not c then
          c = Roles.blobCell(under, over, middle, pals, m)
          cells[m] = c
        end
        return c
      end,
    }
    arts[pair] = a
    return a
  end

  -- every Emerald map by its slot, its header and events; layouts by id, their maps' events joined
  local layouts, byName = {}, {}
  for id, def in pairs(maps) do
    if type(id) == "string" and id:match("^EM_") then
      local g, n = Rse.mapGroupNum(id)
      local slot = g and (g .. "_" .. n)
      local rawH = slot and cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
      local h = rawH and Json.decode(rawH)
      if h and h.layoutId then
        local L = layouts[h.layoutId]
        if not L then
          local grid = cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/grid.bin")
          L = { layoutId = h.layoutId, w = h.width, h = h.height, grid = grid, pair = def.pair,
                warps = {}, signs = {}, outdoor = false, maps = {}, def = def }
          layouts[h.layoutId] = L
        end
        L.maps[#L.maps + 1] = id
        L.outdoor = L.outdoor or Dataset.isOutdoorMapType(h.mapType)
        local rawE = cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/events.json")
        local e = rawE and Json.decode(rawE) or {}
        for _, w in ipairs(e.warps or {}) do L.warps[#L.warps + 1] = { w.x, w.y } end
        for _, b in ipairs(e.bgEvents or {}) do
          if b.type == "sign" then L.signs[b.x .. "," .. b.y] = true end
        end
        byName["LAYOUT_" .. id:gsub("^EM_", "")] = L
      end
    end
  end
  -- an adapter over one layout
  local function adapter(L, name)
    local grid, W = L.grid, L.w
    local function cellAt(x, y)
      local i = (y * W + x) * 2 + 1
      return grid:byte(i) + grid:byte(i + 1) * 256
    end
    local p, s = Roles.pairTilesets(L.pair)
    local art = artOf(L.pair)
    local beh = IS.behaviors[L.pair] or {}
    return {
      id = name, w = L.w, h = L.h, outdoor = L.outdoor, warps = L.warps, signs = L.signs,
      primary = p, secondary = s,
      metatile = function(x, y) return cellAt(x, y) % 1024 end,
      blocked = function(x, y) return math.floor(cellAt(x, y) / 1024) % 4 ~= 0 end,
      behaviour = function(x, y) return beh[cellAt(x, y) % 1024] or 0 end,
      pixels = art.pixels, cell = art.cell,
    }
  end

  -- the game's posts: every outdoor layout's sign events open on three sides
  local t0 = clock()
  local all = {}
  for _, L in pairs(layouts) do
    if L.outdoor and next(L.signs) and L.grid and L.pair then all[#all + 1] = adapter(L, "") end
  end
  local posts, postDrawings = Roles.posts(all)
  local np, nd = 0, 0
  for _ in pairs(posts) do np = np + 1 end
  for _ in pairs(postDrawings) do nd = nd + 1 end
  log(string.format("posts %d drawings %d from %d layouts in %.0f ms", np, nd, #all, (clock() - t0) * 1000))
  do
    local keys = {}
    for k in pairs(posts) do keys[#keys + 1] = k end
    table.sort(keys)
    local f = io.open(dir .. "/posts.txt", "w")
    if f then f:write(table.concat(keys, "\n"), "\n"); f:close() end
  end
  local refL = byName.LAYOUT_ROUTE116
  local reference = refL and adapter(refL, "LAYOUT_ROUTE116") or nil

  local want = env("ROLES_LAYOUTS") or "LAYOUT_ROUTE104"
  for name in want:gmatch("[^,]+") do
    local L = byName[name]
    if not L or not L.grid then
      log(name, "MISSING")
    else
      local A = adapter(L, name)
      local t1 = clock()
      local r = Roles.new(A, { behaviours = behaviours, posts = posts, postDrawings = postDrawings,
                               reference = reference })
      local lines = Roles.letters(r, A.w, A.h)
      local ms = (clock() - t1) * 1000
      local f = io.open(dir .. "/roles_" .. name .. ".txt", "w")
      if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
      -- pret's collision bits against the engine's walls
      local mis, kinds = 0, {}
      local ok, layout = pcall(Map.ensureMidLayout, game3, L.maps[1], maps[L.maps[1]])
      if ok and layout then
        for y = 0, A.h - 1 do
          for x = 0, A.w - 1 do
            local wall = Perm.isWall(layout:collAt(x, y)) == true
            if A.blocked(x, y) ~= wall then
              mis = mis + 1
              local k = string.format("bits %s wall %s coll 0x%02X beh %s", tostring(A.blocked(x, y)), tostring(wall),
                layout:collAt(x, y) or -1, tostring(MB.nameOf(A.behaviour(x, y))))
              kinds[k] = (kinds[k] or 0) + 1
            end
          end
        end
      end
      local _, _, colour = Roles.aliasOf(A, reference)
      local nc = 0
      local pairsOut = {}
      for a, b in pairs(colour or {}) do
        nc = nc + 1
        pairsOut[#pairsOut + 1] = string.format("%06X=%06X", a < 0 and 0xFFFFFF or a, b < 0 and 0xFFFFFF or b)
      end
      table.sort(pairsOut)
      if nc > 0 then
        local f = io.open(dir .. "/alias_" .. name .. ".txt", "w")
        if f then f:write(table.concat(pairsOut, "\n"), "\n"); f:close() end
      end
      for k, n in pairs(kinds) do log("   ", n, k) end
      log(string.format("%s (%s, %s) %dx%d roles in %.1f ms; blocked vs engine walls: %d differ; alias colours %d",
        name, L.maps[1], tostring(L.pair), A.w, A.h, ms, mis, nc))
    end
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_roles"
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
