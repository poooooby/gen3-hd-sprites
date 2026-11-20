-- Driver: WoobleDex's Gen 9 Move Animation Project animations (its NdxEss task) in the 3D world's
-- battles: boots Emerald, stands a wild battle on a map with Battle Scene on, plays each move from
-- the player's side and the foe's, and screenshots every few frames, logging the camera and the
-- kinds of layer the animation opened (stats().screen / edge / wide). Needs national_dex_gen3 in
-- mods/. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/ess_scene.lua love .
-- HD_SIZE=WxH (default 1920x1080); HD_SPOT=MAP[:x:y] (default Route 101's middle);
-- HD_PLAYER / HD_ENEMY=SPECIES_X (default Blaziken / Swampert); MOVES=SURF,SEED_FLARE (WoobleDex's
-- names); SIDES=p,e (default both); SHOT_EVERY=n (default 6; 0 none); HD_SCENE=off: the classic backgrounds;
-- COVER=1: each move's coverage, every 6 frames against the battle before it (the view's outer 8% a
-- side and its middle 30%, between its 15% and 70% rows): "boxed" when the middle changed and the
-- sides did not (a background stopped at the canvas's box).

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_ess"
  local every = tonumber(os.getenv("SHOT_EVERY") or "") or 6
  local sw, sh = (os.getenv("HD_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(sw), tonumber(sh), { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  -- the spot: the walkable land cell nearest x, y (the map's middle without them)
  local mapId, px, py = (os.getenv("HD_SPOT") or "EM_ROUTE101"):match("^([%w_]+):?(%d*):?(%d*)$")
  px, py = tonumber(px), tonumber(py)
  pcall(Map.load, nil, game, mapId, { x = px or 0, y = py or 0, facing = "down" })
  local def = Map.currentDef()
  local L = def and def.midLayout
  local W, H = L and L.width or 0, L and L.height or 0
  local sx, sy = px or math.floor(W / 2), py or math.floor(H / 2)
  local function land(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return false end
    local okW, walk = pcall(Collision.isWalkable, x, y)
    if not (okW and walk) then return false end
    local okB, beh = pcall(Collision.behavior, x, y)
    return not (okB and Collision.isSurfable(beh))
  end
  px, py = sx, sy
  for r = 0, 40 do
    local hit
    for dy = -r, r do
      for dx = -r, r do
        if not hit and math.max(math.abs(dx), math.abs(dy)) == r and land(sx + dx, sy + dy) then hit = { sx + dx, sy + dy } end
      end
    end
    if hit then px, py = hit[1], hit[2]; break end
  end
  U.wait(30)
  -- (a new game's intro may still load the moving truck: on the spot until it is so)
  for _ = 1, 5 do
    local d0 = Map.currentDef()
    if not (d0 and (d0.id or d0.name) == mapId) then pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "down" }) end
    local s0 = Runtime.getSession()
    if s0 then s0.x, s0.y = px, py end
    Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
    Player.targetX, Player.targetY = px, py
    U.wait(20)
  end
  log(("spot %s at %d,%d"):format(mapId, px, py))

  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  hd.setScene(os.getenv("HD_SCENE") ~= "off")
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false
  end
  local root = "mods/national_dex_gen3/"
  local okE, ess = pcall(dofile, root .. "data/ess_anims.lua")
  if not okE then log("FAIL WoobleDex's animations missing: " .. tostring(ess)); return end
  local byId = {}
  for _, r in ipairs(dofile(root .. "data/moves.lua")) do byId[r.id] = r end

  s.party = {}
  local mine = os.getenv("HD_PLAYER") or "SPECIES_BLAZIKEN"
  Party.giveMon(s, C.species.byName[mine], 50, (mine:gsub("^SPECIES_", "")))
  local foe = os.getenv("HD_ENEMY") or "SPECIES_SWAMPERT"
  local started, why = BattleBridge.startWild(Runtime._mod, game, { species = C.species.byName[foe], level = 50 }, { fade = false })
  if not started then log("FAIL wild battle: " .. tostring(why)); return end
  local ready = false
  for _ = 1, 6000 do
    if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  if not ready then log("FAIL battle did not reach the action menu"); return end
  U.wait(90)
  -- COVER=1: the mean change (0-255) in the view's sides and middle against a baseline picture
  local cover = os.getenv("COVER") == "1"
  local baseline, pending = nil, nil
  local function regions(img)
    local w, h = img:getDimensions()
    local y0, y1 = math.floor(h * 0.15), math.floor(h * 0.70)
    local function mean(xa, xb)
      local sum, n = 0, 0
      for y = y0, y1, 8 do
        for x = xa, xb, 8 do
          local r, g, b = img:getPixel(x, y)
          local r0, g0, b0 = baseline:getPixel(x, y)
          sum = sum + math.abs(r - r0) + math.abs(g - g0) + math.abs(b - b0)
          n = n + 3
        end
      end
      return n > 0 and sum / n * 255 or 0
    end
    local side = (mean(0, math.floor(w * 0.08)) + mean(math.floor(w * 0.92), w - 1)) / 2
    return side, mean(math.floor(w * 0.35), math.floor(w * 0.65))
  end
  local function grab(fn) love.graphics.captureScreenshot(function(img) fn(img) end) end
  if cover then
    grab(function(img) baseline = img end)
    U.wait(2)
  end
  local v0 = hd.stats()
  log(("battle ready: scene %s zoom %.3f fill %s"):format(tostring(v0.scene), v0.zoom or -1, tostring(v0.fill)))
  U.shot(game, dir .. "/_ready.png")
  do
    local sum, worst = 0, 0
    for _ = 1, 60 do
      local t0 = love.timer.getTime()
      U.wait(1)
      local dt = love.timer.getTime() - t0
      sum, worst = sum + dt, math.max(worst, dt)
    end
    log(("idle: frame ms avg %.2f worst %.2f"):format(sum / 60 * 1000, worst * 1000))
  end

  local list = {}
  for id in (os.getenv("MOVES") or "SPACIAL_REND,SPRINGTIDE_STORM,SEED_FLARE,SHADOW_FORCE,SURF,SPECTRAL_THIEF,STEAM_ERUPTION"):gmatch("[%w_]+") do
    list[#list + 1] = id
  end
  local sides = os.getenv("SIDES") or "p,e"
  local function restore()
    for _, side in ipairs({ "player", "enemy" }) do
      local p = Anim.present(side)
      if p then
        p.visible = true
        p.ox, p.oy, p.sx, p.sy, p.rotation = 0, 0, 1, 1, 0
        p.invisible = nil
      end
    end
  end
  local function play(id, foeSide)
    local info = ess.moves[id]
    local num = (byId[id] and byId[id].index) or (info and info.num)
    if not num then log("FAIL " .. id .. " is not a move the pack animates"); return end
    local tag = id .. (foeSide and "_e" or "_p")
    local st0 = hd.stats()
    local e0, w0, s0, r0, f0 = st0.edge or 0, st0.wide or 0, st0.screen or 0, st0.row or 0, st0.free or 0
    local ok, err = pcall(Anim.launchMove, num, { attackerSide = foeSide and "enemy" or "player",
      targetSide = foeSide and "player" or "enemy", isReversed = foeSide,
      moveTurn = info and info.turns and 1 or 0 })
    if not ok then log("FAIL launch " .. tag .. ": " .. tostring(err)); return end
    local n, ticks, saw = 0, 0, false
    local sum, worst, timed = 0, 0, 0
    local boxed, covered, peak = 0, 0, 0
    while Anim.busy() and ticks < 1500 do
      if cover and baseline and ticks % 6 == 0 then
        grab(function(img)
          local side, mid = regions(img)
          if mid > peak then peak = mid end
          if mid > 30 and side < 6 then boxed = boxed + 1 end
          if side >= 6 then covered = covered + 1 end
        end)
      end
      local shooting = every > 0 and ticks % every == 0
      if shooting then
        n = n + 1
        U.shot(game, ("%s/%s_%02d.png"):format(dir, tag, n))
      end
      local t0 = love.timer.getTime()
      U.wait(1)
      local dt = love.timer.getTime() - t0
      if not shooting then sum, worst, timed = sum + dt, math.max(worst, dt), timed + 1 end
      ticks = ticks + 1
      for i = 1, AnimTasks.MAX do
        local t = AnimTasks._pool[i]
        if t.active and t.name == "NdxEss" then saw = true end
      end
    end
    local v = hd.stats()
    if cover then
      U.wait(2)
      log(("%s: cover boxed %d covered %d peak %.0f"):format(tag, boxed, covered, peak))
    end
    log(("%s: frame ms avg %.2f worst %.2f"):format(tag, timed > 0 and sum / timed * 1000 or -1, worst * 1000))
    log(("%s: NdxEss %s ticks %d shots %d edge %d wide %d screen %d row %d free %d zoom %.3f failed %s sceneError %s"):format(tag,
      tostring(saw), ticks, n, (v.edge or 0) - e0, (v.wide or 0) - w0, (v.screen or 0) - s0, (v.row or 0) - r0, (v.free or 0) - f0, v.zoom or -1,
      tostring(v.failed), tostring(v.sceneError)))
    restore()
    U.wait(20)
  end
  for _, id in ipairs(list) do
    for side in sides:gmatch("[pe]") do play(id, side == "e") end
  end
  log("DONE")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_ess"
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
