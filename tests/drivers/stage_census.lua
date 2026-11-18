-- Driver: where the Battle Scene stands its battles (src/scene/stage.lua), map by map. For each
-- map in CENSUS_MAPS (comma separated; default a round of Hoenn's towns, routes and caves) it
-- builds the scene at anchors CENSUS_STEP cells apart (default 16) and, for every cell near each
-- anchor a wild battle could start on, runs the stage search twice on that scene's cells: by its
-- score alone (as it was) and with the strict check (Stage.tier: both feet on level ground they
-- could stand on, nothing between them). Logs how often each choice is fair, why not, how far the
-- strict one moves, and spots of each case (MAP:x:y, for scene_battle.lua's SCENE_SPOTS). Run
-- from the engine root:
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/stage_census.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local DEFAULT = table.concat({
  "EM_ROUTE101", "EM_ROUTE102", "EM_ROUTE103", "EM_ROUTE104", "EM_ROUTE110", "EM_ROUTE111", "EM_ROUTE112",
  "EM_ROUTE113", "EM_ROUTE114", "EM_ROUTE115", "EM_ROUTE116", "EM_ROUTE117", "EM_ROUTE118", "EM_ROUTE119",
  "EM_ROUTE120", "EM_ROUTE121", "EM_ROUTE123", "EM_RUSTBORO_CITY", "EM_FALLARBOR_TOWN", "EM_FORTREE_CITY",
  "EM_LILYCOVE_CITY", "EM_MAUVILLE_CITY", "EM_SLATEPORT_CITY", "EM_PETALBURG_CITY", "EM_VERDANTURF_TOWN",
  "EM_LAVARIDGE_TOWN", "EM_MOSSDEEP_CITY", "EM_PETALBURG_WOODS", "EM_GRANITE_CAVE_1F", "EM_METEOR_FALLS_1F_1R",
  "EM_JAGGED_PASS", "EM_MT_CHIMNEY", "EM_VICTORY_ROAD_1F", "EM_SAFARI_ZONE_SOUTH",
}, ",")

local function body(game, log)
  local U = require("tests.drivers.util")
  love.window.setMode(960, 640, { resizable = true })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Runtime = require("src.core.game3.runtime")
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  hd.setScene(true)
  local ws = hd._workshop and hd._workshop()
  if not (ws and ws.forBattle) then log("FAIL no workshop forBattle"); return end
  -- CENSUS_RELIEF=1: the relief built first (as the frame hook builds it in play)
  if env("CENSUS_RELIEF") and hd._reliefStep then
    local st, why
    for _ = 1, 200000 do
      st, why = hd._reliefStep()
      if st ~= "running" and st ~= "idle" then break end
      U.wait(1)
    end
    log("relief:", tostring(st), tostring(why))
  end
  local Camera = ws.Camera
  local Stage = dofile("mods/gen3-hd-sprites/src/scene/stage.lua")
  local strictTier = Stage.tier
  -- CENSUS_FAR=n: the rings searched that far out (Stage.FAR)
  Stage.FAR = tonumber(env("CENSUS_FAR") or "") or Stage.FAR
  -- how near the camera the edge of the scene's window shows (tiles from the eye; nil: not within
  -- 48, where the haze is thickest): the canvas cast onto the target's ground, every 12 pixels
  local function edgeAt(grid, b)
    local pose = Camera.pose(b.tx, b.tz + b.ty, nil, nil, b.ty)
    local ex, _, ez = Camera.basis(pose)
    local near
    for v = 0, Camera.H, 12 do
      for u = 0, Camera.W, 12 do
        local x, z = Camera.ground(pose, u, v, b.ty)
        if x then
          local d = math.sqrt((x - ex) ^ 2 + (z - ez) ^ 2)
          if d < 48 and not grid.at(math.floor(x), math.floor(z - b.ty)) and (not near or d < near) then near = d end
        end
      end
    end
    return near
  end
  local STAND = { grass = true, sand = true, floor = true, water = true }
  local step = tonumber(env("CENSUS_STEP") or "") or 16
  local half = math.floor(step / 2)
  local total = { n = 0, oldFair = 0, newFair = 0, newTier1 = 0, newTier0 = 0, fixed = 0, moved = 0,
                  oldWhy = {}, newWhy = {}, ms = 0, builds = 0, failed = 0 }
  local samples = { fixed = {}, still = {}, worse = {}, edge = {} }
  local perMap = {}
  local function add(list, s, mapId)
    local k = tostring(list) .. (mapId or "")
    perMap[k] = (perMap[k] or 0) + 1
    if perMap[k] <= 4 and #list < 400 then list[#list + 1] = s end
  end
  -- a cell's flags (for the samples)
  local function flags(c)
    if not c then return "nil" end
    return ("%s coll %s beh %s top %s up %s slope %s lift %.2f model %s border %s"):format(c.kind, tostring(c.coll),
      tostring(c.beh), tostring(c.top), tostring(c.up), tostring(c.slope), c.liftT or 0, tostring(c.model ~= nil),
      tostring(c.border ~= nil))
  end
  local function stand(x, y, facing)
    local sess = Runtime.getSession()
    if sess then sess.x, sess.y = x, y end
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY, Player.facing, Player.moving, Player.surfing = x, y, facing or "down", false, false
  end
  -- CENSUS_DUMP=MAP:x:y[,...]: no census; the cells round each spot, with the old (lower case) and
  -- the strict (upper case) choice: p/P the player's Pokemon's feet, e/E the foe's, c/C the camera
  -- over the ground, Y the player. Ground: . floor, " grass, : sand, ~ water, # blocked, blank void;
  -- what stands: M a model over half a tile tall, m a lower one, T a card; / a slope. And each
  -- cell's height, in half tiles from the player's ground.
  if env("CENSUS_DUMP") then
    for spot in env("CENSUS_DUMP"):gmatch("[^,]+") do
      local mapId, sx, sy = spot:match("([^:]+):(%d+):(%d+)")
      local x, y = tonumber(sx), tonumber(sy)
      pcall(Map.load, nil, game, mapId, { x = x, y = y, facing = "down" })
      stand(x, y)
      local scene = ws.forBattle({}, nil, nil)
      local grid = scene and scene.grid
      if not grid then log(spot, "no scene") else
        local c0 = grid.at(x, y)
        local want = { player = c0.kind, enemy = c0.kind }
        local opts = { player = { cx = x, cy = y }, want = want, feet = ws.FEET, sprites = ws.SPRITES, void = scene.walled or scene.indoor }
        Stage.tier = function() return 0 end
        local old = Stage.search(Camera, grid, opts)
        Stage.tier = strictTier
        local new = Stage.search(Camera, grid, opts)
        local marks = {}
        local function mark(b, lower)
          local function put(px, pz, ch) marks[math.floor(px) .. "," .. math.floor(pz)] = lower and ch:lower() or ch end
          put(b.feet.player[1], b.feet.player[2], "P")
          put(b.feet.enemy[1], b.feet.enemy[2], "E")
          local ex, _, ez = Camera.basis(Camera.pose(b.tx, b.tz + b.ty, nil, nil, b.ty))
          put(ex, ez - b.ty, "C")
        end
        mark(old, true)
        mark(new, false)
        marks[x .. "," .. y] = "Y"
        local ot, owhy, oc = strictTier(Camera, grid, old.tx, old.tz, old.ty, { old.feet.player[1] - old.tx,
            old.feet.player[2] - old.tz, old.feet.enemy[1] - old.tx, old.feet.enemy[2] - old.tz }, want, ws.SPRITES)
        log(("%s: old score %.1f moved %.1f (strict tier %s %s%s); new tier %d %s score %.1f moved %.1f"):format(spot, old.score,
          old.moved, tostring(ot), tostring(owhy), oc and (" at " .. oc.cx .. "," .. oc.cy .. ": " .. flags(oc)) or "",
          new.tier, tostring(new.why), new.score, new.moved))
        -- CENSUS_RAYS=1: the strict choice's sprite boxes, ray by ray (# blocked, . clear), and
        -- the cells blocking or standing in front of the player's Pokemon
        if env("CENSUS_RAYS") then
          local rayClear
          for i = 1, 60 do
            local n, f = debug.getupvalue(Stage.tier, i)
            if not n then break end
            if n == "seen" then
              for k = 1, 60 do
                local n2, f2 = debug.getupvalue(f, k)
                if not n2 then break end
                if n2 == "rayClear" then rayClear = f2 end
              end
            end
          end
          local pose = Camera.pose(new.tx, new.tz + new.ty, nil, nil, new.ty)
          for _, side in ipairs({ "player", "enemy" }) do
            local r, ft = ws.SPRITES[side], new.feet[side]
            local _, _, depth = Camera.view(pose, ft[1], new.ty, ft[2] + new.ty)
            log(("%s box %d,%d-%d,%d feet %.2f,%.2f depth %.2f"):format(side, r[1], r[2], r[3], r[4], ft[1], ft[2], depth or -1))
            local hits = {}
            for v = r[2], r[4], 4 do
              local row = {}
              for u = r[1], r[3], 4 do
                local ok, c = rayClear(Camera, grid, pose, u, v, depth, new.ty)
                row[#row + 1] = ok and "." or "#"
                if c then hits[c.cx .. "," .. c.cy] = c end
              end
              log(("  v%3d %s"):format(v, table.concat(row)))
            end
            for k, c in pairs(hits) do log("  hit", k, flags(c), "treeFoot", tostring(c.treeFoot)) end
          end
          local pf = new.feet.player
          for cy = math.floor(pf[2]), math.floor(pf[2]) + 4 do
            local a = {}
            for cx = math.floor(pf[1]) - 3, math.floor(pf[1]) + 3 do
              local c = grid.at(cx, cy)
              a[#a + 1] = c and ("%s%s%.1f"):format(c.treeFoot and "F" or "-", c.model and "m" or "-", c.top or 0) or "nil"
            end
            log(("  row %d: %s"):format(cy, table.concat(a, " ")))
          end
        end
        local G = { floor = ".", grass = '"', sand = ":", water = "~", blocked = "#", void = " " }
        for cy = y - 14, y + 9 do
          local a, h = {}, {}
          for cx = x - 14, x + 14 do
            local c = grid.at(cx, cy)
            local ch = c and G[c.kind] or "?"
            if c and c.up then ch = "T" elseif c and (c.top or 0) > 0.5 then ch = "M"
            elseif c and c.model then ch = "m" elseif c and c.slope then ch = "/" end
            a[#a + 1] = marks[cx .. "," .. cy] or ch
            local lv = c and c.liftT and math.floor(c.liftT * 2 + 0.5) or 0
            h[#h + 1] = lv == 0 and "." or (lv > 9 and "+" or (lv < 0 and "-" or tostring(lv)))
          end
          log(("%4d %s   %s"):format(cy, table.concat(a), table.concat(h)))
        end
      end
    end
    log("census done")
    return
  end
  for mapId in (env("CENSUS_MAPS") or DEFAULT):gmatch("[^,]+") do
    local okL = pcall(Map.load, nil, game, mapId, { x = 5, y = 5, facing = "down" })
    local def = okL and Map.currentDef()
    local L = def and def.midLayout
    if not L then
      log("map", mapId, "not loaded")
    else
      local W, H = L.width, L.height
      local m = { n = 0, oldFair = 0, newFair = 0, fixed = 0 }
      for ay = half, H - 1, step do
        for ax = half, W - 1, step do
          local sess = Runtime.getSession()
          if sess then sess.x, sess.y = ax, ay end
          Player.cellX, Player.cellY, Player.px, Player.py = ax, ay, ax * 16, ay * 16
          Player.targetX, Player.targetY, Player.facing, Player.moving, Player.surfing = ax, ay, "down", false, false
          local t0 = love.timer.getTime()
          local scene = ws.forBattle({}, nil, nil)
          total.ms, total.builds = total.ms + (love.timer.getTime() - t0) * 1000, total.builds + 1
          local grid = scene and scene.grid
          if not grid then total.failed = total.failed + 1 end
          if grid then
            for py = ay - half, ay + half - 1 do
              for px = ax - half, ax + half - 1 do
                local c = grid.at(px, py)
                if c and px >= 0 and py >= 0 and px < W and py < H then
                  m.cells = (m.cells or 0) + 1
                  local k = c.kind .. "/" .. tostring(c.coll)
                  m.kinds = m.kinds or {}
                  m.kinds[k] = (m.kinds[k] or 0) + 1
                end
                if c and STAND[c.kind] and not c.border and px >= 0 and py >= 0 and px < W and py < H then
                  local want = { player = c.kind, enemy = c.kind }
                  local opts = { player = { cx = px, cy = py }, want = want, feet = ws.FEET, sprites = ws.SPRITES,
                                 void = scene.walled or scene.indoor }
                  Stage.tier = function() return 0 end
                  local old = Stage.search(Camera, grid, opts)
                  Stage.tier = strictTier
                  local new = Stage.search(Camera, grid, opts)
                  if old and new then
                    local ot, owhy = strictTier(Camera, grid, old.tx, old.tz, old.ty, { old.feet.player[1] - old.tx,
                      old.feet.player[2] - old.tz, old.feet.enemy[1] - old.tx, old.feet.enemy[2] - old.tz }, want, ws.SPRITES)
                    local spot = ("%s:%d:%d"):format(mapId, px, py)
                    total.n, m.n = total.n + 1, m.n + 1
                    if ot == 3 then
                      total.oldFair, m.oldFair = total.oldFair + 1, m.oldFair + 1
                    else
                      total.oldWhy[owhy] = (total.oldWhy[owhy] or 0) + 1
                    end
                    if new.tier == 3 then
                      total.newFair, m.newFair = total.newFair + 1, m.newFair + 1
                    else
                      total.newTiers = total.newTiers or {}
                      total.newTiers[new.tier] = (total.newTiers[new.tier] or 0) + 1
                      total.newWhy[new.why] = (total.newWhy[new.why] or 0) + 1
                      local f = new.why == "enemy" and new.feet.enemy or new.feet.player
                      add(samples.still, spot .. " (" .. tostring(new.why) .. "; here " .. flags(c) .. "; foot " ..
                        flags(grid.at(math.floor(f[1]), math.floor(f[2]))) .. ("; ground %.2f)"):format(new.ty), mapId)
                    end
                    if ot < 3 and new.tier == 3 then
                      total.fixed, m.fixed = total.fixed + 1, m.fixed + 1
                      add(samples.fixed, ("%s (%s; moved %.1f -> %.1f)"):format(spot, owhy, old.moved, new.moved), mapId)
                    end
                    if new.tier < ot then add(samples.worse, spot, mapId) end
                    total.moved = total.moved + new.moved
                    local mk = math.min(12, math.floor(new.moved + 0.5))
                    total.movedBy = total.movedBy or {}
                    total.movedBy[mk] = (total.movedBy[mk] or 0) + 1
                    if not scene.walled then
                      local eo, en = edgeAt(grid, old), edgeAt(grid, new)
                      total.edges = total.edges or { old = 0, new = 0, newNear = 0 }
                      if eo then total.edges.old = total.edges.old + 1 end
                      if en then
                        total.edges.new = total.edges.new + 1
                        if en < 30 then total.edges.newNear = total.edges.newNear + 1 end
                        if not eo then add(samples.edge, ("%s (moved %.1f, edge %.0f tiles off)"):format(spot, new.moved, en), mapId) end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
      log(("map %-24s %5d spots: fair before %5.1f%%, after %5.1f%% (%d fixed)"):format(mapId, m.n,
        m.n > 0 and 100 * m.oldFair / m.n or 0, m.n > 0 and 100 * m.newFair / m.n or 0, m.fixed))
      if m.n < (m.cells or 0) / 10 then
        local ks = {}
        for k, v in pairs(m.kinds or {}) do ks[#ks + 1] = k .. " " .. v end
        table.sort(ks)
        log("  (few spots: cells by kind/collision " .. table.concat(ks, ", ") .. ")")
      end
    end
  end
  local function whys(t)
    local out = {}
    for k, v in pairs(t) do out[#out + 1] = k .. " " .. v end
    table.sort(out)
    return table.concat(out, ", ")
  end
  local n = math.max(1, total.n)
  log(("TOTAL %d spots (%d scenes, %d not built, %.0f ms each): fair before %.1f%% (unfair: %s)"):format(total.n,
    total.builds, total.failed, total.ms / math.max(1, total.builds), 100 * total.oldFair / n, whys(total.oldWhy)))
  local nt = total.newTiers or {}
  log(("TOTAL after: fair %.1f%%, tier 2 %.1f%%, tier 1 %.1f%%, tier 0 %.1f%% (%s); %d fixed; moved %.2f tiles on average"):format(
    100 * total.newFair / n, 100 * (nt[2] or 0) / n, 100 * (nt[1] or 0) / n, 100 * (nt[0] or 0) / n, whys(total.newWhy),
    total.fixed, total.moved / n))
  local mb = {}
  for k = 0, 12 do mb[#mb + 1] = k .. ":" .. ((total.movedBy or {})[k] or 0) end
  log("moved (tiles:spots) " .. table.concat(mb, " "))
  local e = total.edges or { old = 0, new = 0, newNear = 0 }
  log(("window edge on screen (outdoors, within 48 tiles): old %d, new %d (%d within 30)"):format(e.old, e.new, e.newNear))
  for _, k in ipairs({ "fixed", "still", "worse", "edge" }) do
    for _, s in ipairs(samples[k]) do log(k, s) end
  end
  log("census done")
end

return function(game)
  local dir = env("SHOT_DIR") or "."
  local logFile = io.open(dir .. "/census.log", "w")
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
