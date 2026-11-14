-- Driver: Battle Scene (OVERWORLD) in a Gen 3 game. Boots a new game, then for each spot in
-- SCENE_SPOTS (MAP:x:y:facing, comma separated; default two Emerald spots: Route 101's grass and
-- Littleroot Town by the houses) stands the player there, starts a wild battle and shoots the
-- entrance glide (SCENE_FRAMES, default 2,20,40,60,80,100,130), the settled battle with Fill
-- Screen on and off, and the same battle with the scene off (CLASSIC). SCENE_SIZE (default
-- 1920x1080) is the window; SCENE_FOE a species constant (default SPECIES_WURMPLE); SCENE_LOOK
-- (dx:dz:pitch:dist, comma separated) more shots with the camera aimed that far from the player,
-- pitched that many degrees, that many tiles away. Logs
-- WoobleView's scene stats. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/scene_battle.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_scene"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local w, h = (env("SCENE_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Version = require("src.core.game3.constants")
  local game3 = env("POKEPORT_GAME") or "emerald"
  local C = Version.of(game3)
  local Party = require("src.core.game3.party")
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  -- SCENE_SELFTEST=1: the renderer on a synthetic 9x9 field with one 2-tall card, in this engine
  if env("SCENE_SELFTEST") then
    local Camera = dofile("mods/gen3-hd-sprites/src/scene/camera.lua")
    local Render = dofile("mods/gen3-hd-sprites/src/scene/render.lua")
    local G = love.graphics
    local img = G.newCanvas(32, 16)
    G.push("all"); G.setCanvas(img); G.clear(0, 1, 0, 1)
    G.setColor(0, 0, 1, 1); G.rectangle("fill", 16, 0, 16, 16); G.pop()
    local gq, cq = G.newQuad(0, 0, 16, 16, 32, 16), G.newQuad(16, 0, 16, 16, 32, 16)
    local grid = { w = 9, h = 9, rows = {} }
    for j = 0, 8 do
      grid.rows[j] = {}
      for i = 0, 8 do grid.rows[j][i] = { cx = i, cy = j, kind = "floor", pair = "p", mid = 0 } end
    end
    grid.rows[3][4].up, grid.rows[3][4].base, grid.rows[3][4].mid = 1, 4, 1
    grid.rows[4][4].up, grid.rows[4][4].base, grid.rows[4][4].mid = 0, 4, 1
    local tiles = function() return { image = img, slot = function(m) return m end,
      quad = function(sl) return sl == 1 and cq or gq end, overQuad = function() return nil end } end
    local scene = { meshes = Render.meshes(G, Render.vertices(grid, tiles, 0, 0)), ox = 0, oz = 0 }
    local proj, depth = Camera.screenProjection(0, 0, 4, 4)
    local c = Render.draw(G, Camera, scene, Camera.pose(4.5, 5.5), proj, depth, 1, { 0.5, 0.5, 0.5 }, { 100, 200, 0 }, 960, 640)
    log("selftest canvas", tostring(c), "shaderError", tostring(Render.shaderError))
    if c then
      local fd = c:newImageData():encode("png")
      local f = io.open(dir .. "/selftest.png", "wb")
      if f then f:write(fd:getString()); f:close() end
    end
  end
  hd.setScene(true)
  -- (dev: Emerald 3DS's relief.bin, read locally, to check the relief renderer)
  local reliefPath = os.getenv("WOOBLE_RELIEF_BIN")
  if reliefPath and hd._sceneRelief then
    local f = io.open(reliefPath, "rb")
    if f then
      log("relief file:", tostring(hd._sceneRelief(f:read("*a"))))
      f:close()
    end
  end
  -- RELIEF_BUILD=1: build the relief in the background first (as the frame hook does in play),
  -- a slice a frame, and log its phases
  if env("RELIEF_BUILD") and hd._reliefStep then
    local t0, st, why, phases = love.timer.getTime(), nil, nil, nil
    local worstStep, longSteps = 0, 0
    for _ = 1, 200000 do
      local ts = love.timer.getTime()
      st, why, phases = hd._reliefStep(tonumber(env("RELIEF_WATCH") or ""))
      local spent = love.timer.getTime() - ts
      worstStep = math.max(worstStep, spent)
      if spent > 0.05 then longSteps = longSteps + 1 end
      if st ~= "running" and st ~= "idle" then break end
      U.wait(1)
    end
    log(("relief build: longest slice %.0f ms, %d slices over 50 ms"):format(worstStep * 1000, longSteps))
    -- RELIEF_WATCH=seconds: the stretches without a tick longer than that, where they ended
    local run = hd.scene and hd.scene.reliefRun
    if run and run.gaps then
      table.sort(run.gaps, function(a, b) return a[1] > b[1] end)
      for i = 1, math.min(12, #run.gaps) do
        local g = run.gaps[i]
        local where = g[2]:gsub("%c%s*", " | ")
        log(("gap %4.0f ms heap %4.0f MB after %s at%s"):format(g[1], g[3], g[4], where:sub(1, 700)))
      end
    end
    log(("relief build: %s (%s) in %.1f s: %s"):format(tostring(st), tostring(why), love.timer.getTime() - t0,
      table.concat(phases or {}, ", ")))
  end
  -- SCENE_WARM=1: warm each spot's map's models first, as the map hook does in play; SCENE_WARM=all:
  -- every spec (Scene Cache's first-map warm-up), once
  local warmAhead = env("SCENE_WARM") ~= nil
  if env("SCENE_WARM") == "all" and hd._sceneWarm then
    local tw = love.timer.getTime()
    local n = hd._sceneWarm("all")
    log(("warmed all: %s models in %.0f ms (%s)"):format(tostring(n), (love.timer.getTime() - tw) * 1000,
      tostring(hd.stats().sceneModels)))
  end
  -- SCENE_PROBE=<spec name>: that model's parts and their bounds (pixels of its drawing)
  if env("SCENE_PROBE") and hd._sceneModelArt then
    for i, r in ipairs(hd._sceneModelArt(env("SCENE_PROBE")) or {}) do log(("art %3d %s"):format(i - 1, r)) end
  end
  -- SCENE_GROUND_OLD=1: the ground under buildings laid by the old rule (before-and-after shots)
  if env("SCENE_GROUND_OLD") and hd._sceneGroundPlan then hd._sceneGroundPlan(false) end
  -- SCENE_PROBE_PNG=name[,name...]: each model's art saved as SHOT_DIR/art_<name>.png
  for name in (env("SCENE_PROBE_PNG") or ""):gmatch("[^,]+") do
    local art = hd._sceneModelArtRaw and hd._sceneModelArtRaw(name)
    if art then
      local data = love.image.newImageData(art.w, art.h)
      for y = 0, art.h - 1 do
        for x = 0, art.w - 1 do
          local o = (y * art.w + x) * 4
          data:setPixel(x, y, art.px[o + 1], art.px[o + 2], art.px[o + 3], art.px[o + 4])
        end
      end
      local f = io.open(("%s/art_%s.png"):format(env("SHOT_DIR") or "/tmp/hd_scene", name), "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
    end
  end
  if env("SCENE_PIXELS") and hd._scenePixel then
    -- SCENE_PIXELS=pair:mid:x:y,... (mid in hex)
    for spec in env("SCENE_PIXELS"):gmatch("[^,]+") do
      local pair, mid, x, y = spec:match("([^:]+):(%x+):(%d+):(%d+)")
      local r0, g0, b0, a0, r1, g1, b1, a1 = hd._scenePixel(pair, tonumber(mid, 16), tonumber(x), tonumber(y))
      log(("pixel %s %s (%s,%s): under %s %s %s a%s | over %s %s %s a%s"):format(pair, mid, x, y,
        r0 and math.floor(r0 * 255) or "-", g0 and math.floor(g0 * 255) or "-", b0 and math.floor(b0 * 255) or "-", tostring(a0),
        r1 and math.floor(r1 * 255) or "-", g1 and math.floor(g1 * 255) or "-", b1 and math.floor(b1 * 255) or "-", tostring(a1)))
    end
  end
  if env("SCENE_PROBE") and hd._sceneModelBounds then
    for _, b in ipairs(hd._sceneModelBounds(env("SCENE_PROBE")) or {}) do
      log(("probe %-18s %5d tris  x %6.1f..%-6.1f y %6.1f..%-6.1f z %6.1f..%-6.1f"):format(b.tag, b.n, b[1], b[4], b[2], b[5], b[3], b[6]))
    end
  end
  log("hd active:", hd.isActive(), "fit:", hd.fitEnabled(), "fill:", hd.fillEnabled(), "scene:", hd.sceneEnabled())
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local frames = {}
  for n in (env("SCENE_FRAMES") or "2,20,40,60,80,100,130"):gmatch("%d+") do frames[#frames + 1] = tonumber(n) end
  local function stat(k) return tostring(hd.stats()[k]) end
  local spots = env("SCENE_SPOTS") or "EM_ROUTE101:10:10:down,EM_LITTLEROOT_TOWN:14:12:down"
  for spot in spots:gmatch("[^,]+") do
    local mapId, sx, sy, facing = spot:match("([^:]+):(%d+):(%d+):?(%a*)")
    local px, py = tonumber(sx), tonumber(sy)
    facing = facing ~= "" and facing or "down"
    pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = facing })
    local s = Runtime.getSession()
    if s then s.x, s.y = px, py end
    Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
    Player.targetX, Player.targetY, Player.facing = px, py, facing
    if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
    -- SCENE_WEATHER=id: that weather set as a script sets it (setweather, doweather), given time
    -- to come in
    if env("SCENE_WEATHER") then
      local Weather = require("src.core.game3.weather")
      Weather.set(tonumber(env("SCENE_WEATHER")))
      Weather.doWeather()
      U.wait(200)
    end
    U.wait(40)
    U.shot(game, ("%s/%s_field.png"):format(dir, mapId))
    -- SCENE_DUMP=1: the collision codes and behaviours around the player (to read what stands up)
    if env("SCENE_DUMP") then
      local def = Map.currentDef()
      local L = def and def.midLayout
      local Collision = require("src.core.game3.collision")
      local okP, Perm = pcall(require, "src.world.gen2.Permissions")
      log("pair", tostring(L and L.pair), "def.pair", tostring(def and def.pair), "kind", tostring(def and def.kind),
        "primary", tostring(def and def.primaryTileset), "secondary", tostring(def and def.secondaryTileset))
      for y = py - 8, py + 4 do
        local mids = {}
        for x = px - 9, px + 9 do
          local m = L and x >= 0 and y >= 0 and x < L.width and y < L.height and L:midAt(x, y)
          mids[#mids + 1] = m and ("%03x"):format(m) or "---"
        end
        log(("m%3d %s"):format(y, table.concat(mids, " ")))
      end
      for y = py - 8, py + 4 do
        local cells = {}
        for x = px - 9, px + 9 do
          local c = L and x >= 0 and y >= 0 and x < L.width and y < L.height and L:collAt(x, y)
          local b = c and Collision.behaviorOn(def, x, y)
          local wall = c and okP and Perm.isWall(c)
          cells[#cells + 1] = c and ("%02x/%02x%s"):format(c, b or 0, wall and "W" or " ") or "  ---  "
        end
        log(("y%3d %s"):format(y, table.concat(cells, " ")))
      end
    end
    hd.setScene(true)
    if warmAhead and hd._sceneWarm then
      local tw = love.timer.getTime()
      local n = hd._sceneWarm(mapId)
      log(("%s warmed %s models in %.0f ms"):format(mapId, tostring(n), (love.timer.getTime() - tw) * 1000))
    end
    local ok, err = BattleBridge.startWild(Runtime._mod, game,
      { species = C:require("species", env("SCENE_FOE") or "SPECIES_WURMPLE"), level = 3 }, { fade = false })
    if not ok then log("FAIL startWild", tostring(err)); return end
    local fi = 1
    for f = 1, 200 do
      if frames[fi] and f >= frames[fi] then
        U.shot(game, ("%s/%s_glide_%03d.png"):format(dir, mapId, f))
        fi = fi + 1
      end
      U.wait(1)
    end
    waitFor(function()
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
      return Ui._mode == "menu" and not Anim.busy()
    end, 3000)
    U.wait(30)
    for _, fill in ipairs({ true, false }) do
      hd.setFill(fill)
      U.wait(6)
      U.shot(game, ("%s/%s_scene_%s.png"):format(dir, mapId, fill and "fill" or "nofill"))
    end
    -- SCENE_TILEANIM=1: whether the field's tile animation runs on in the battle (its banks'
    -- frames, a second apart)
    if env("SCENE_TILEANIM") then
      local TA = require("src.core.game3.tileset_anim")
      local function frames()
        local st = TA._rse
        return st and ("primary %s secondary %s"):format(tostring(st.primary), tostring(st.secondary)) or "no timers"
      end
      local a = frames()
      U.wait(60)
      local b = frames()
      log(("%s tile animation in battle: %s (%s)"):format(mapId, a == b and "still" or "running", b:sub(1, 200)))
    end
    -- SCENE_ANIM=NAME: a general battle animation played over the settled battle (e.g.
    -- SANDSTORM_CONTINUES), shot at frames 20, 50 and 80 of it
    if env("SCENE_ANIM") then
      hd.setFill(true)
      local AnimSeq = require("src.core.game3.battle.anim_seq")
      local okA, errA = pcall(AnimSeq.beginEvents, { { kind = "anim", anim = "general", name = env("SCENE_ANIM"),
        attacker = "player", target = "enemy" } }, function() end)
      if not okA then log("FAIL anim", tostring(errA)) end
      for f = 1, 80 do
        -- (the battle's menu does not advance a sequence: ticked here)
        pcall(AnimSeq.update)
        U.wait(1)
        if f == 20 or f == 50 or f == 80 then
          U.shot(game, ("%s/%s_anim_%03d.png"):format(dir, mapId, f))
        end
      end
      log(("%s anim %s: sand picture %s"):format(mapId, env("SCENE_ANIM"), stat("sceneSandPicture")))
    end
    -- SCENE_LOOK=dx:dz:pitch:dist[,...]: the settled camera aimed that far from the player too
    local looks = 0
    for look in (env("SCENE_LOOK") or ""):gmatch("[^,]+") do
      -- dx:dz:pitch:dist[:yaw] (yaw: degrees the view turns east of north)
      local dx, dz, pitch, dist, yaw = look:match("(-?[%d.]+):(-?[%d.]+):([%d.]+):([%d.]+):?(-?[%d.]*)")
      if dx and hd._sceneLook(px + tonumber(dx), py + tonumber(dz), tonumber(pitch), tonumber(dist), tonumber(yaw)) then
        looks = looks + 1
        U.wait(4)
        U.shot(game, ("%s/%s_look%d.png"):format(dir, mapId, looks))
        local data = hd._sceneShot(1440, 960)
        if data then
          local f = io.open(("%s/%s_look%d_scene.png"):format(dir, mapId, looks), "wb")
          if f then f:write(data:encode("png"):getString()); f:close() end
        end
      end
    end
    hd.setFill(true)
    log(("%s (%d,%d): scene %s score %s cards %s progress %s world %s error %s composites %s failed %s"):format(
      mapId, px, py, stat("scene"), stat("sceneScore"), stat("sceneCards"), stat("sceneProgress"), stat("world"),
      stat("sceneError"), stat("composites"), stat("failed")))
    log(("%s buildings: %s (error %s)"):format(mapId, stat("sceneBuildings"), stat("sceneBuildingError")))
    log(("%s signs: %s (error %s)"):format(mapId, stat("sceneSigns"), stat("sceneSignError")))
    log(("%s relief: %s (error %s; build %s); models %s"):format(mapId, stat("sceneRelief"), stat("sceneReliefError"),
      stat("sceneReliefRun"), stat("sceneModels")))
    log(("%s live models: %s"):format(mapId, stat("sceneLive")))
    log(("%s bridge: %s (error %s)"):format(mapId, stat("sceneBridge"), stat("sceneBridgeError")))
    log(("%s swapped layouts: %s (error %s)"):format(mapId, stat("sceneSwaps"), stat("sceneSwapError")))
    log(("%s haze: %s"):format(mapId, stat("sceneHaze")))
    log(("%s weather: %s"):format(mapId, stat("sceneWeather")))
    log(("%s trees: %s"):format(mapId, stat("sceneTrees")))
    log(("%s runs: %s (built in %s ms: %s)"):format(mapId, stat("sceneRuns"), stat("sceneMs"), stat("scenePhases")))
    hd.setScene(false)
    U.wait(6)
    U.shot(game, ("%s/%s_classic.png"):format(dir, mapId))
    hd.setScene(true)
    if Battle.abort then pcall(Battle.abort) end
    waitFor(function() return not Battle.isActive() end, 600)
    U.wait(30)
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_scene"
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
