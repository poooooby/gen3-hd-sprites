-- Driver: the Battle Camera (src/scene/orbit.lua) in a Gen 3 game. Boots a new game, stands the
-- player at CAM_SPOT (MAP:x:y:facing; default Route 101's grass), starts a wild battle with Battle
-- Scene on OVERWORLD (CAM_FOE vs CAM_MON, species constants; default Tropius vs Aggron), lit at
-- noon, and once it settles shoots it with the view turned to each of CAM (yaw:pitch in degrees,
-- comma separated; default 0:30,-45:30,45:30,0:10,0:75,-30:55), then a held right stick swept to
-- each side (stick_left, stick_right: how far it went), then a move at CAM_MOVE_YAW (default -30)
-- shot through its animation (CAM_MOVE_FRAMES, default 10,25,40,55), the zoom (the wheel each way,
-- the left stick each way, and whether the left stick's up and down are off the menus meanwhile),
-- and the camera's option off.
-- CAM_DOUBLE=1: a double trainer battle instead (Gina & Mia; the player's Swampert and
-- Blaziken), its four battlers turned with the view. CAM_DYNAMAX=1 (Galar Rising installed): a
-- Gym Leader's battle (CAM_LEADER, default Flannery), the player's Charizard (Gigantamax Factor)
-- Dynamaxed on the first turn, then the shots with the giant on the field. Logs the look at each shot. Run from the
-- engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/battle_camera.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_camera"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(1920, 1080, { resizable = true, highdpi = true })
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
  local C = Version.of(env("POKEPORT_GAME") or "emerald")
  local Party = require("src.core.game3.party")
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  local core = hd._core()
  local Scene = core.scene
  local Orbit = Scene and Scene.Orbit
  if not Orbit then log("FAIL no Battle Camera (src/scene/orbit.lua)"); return end
  Scene.timeOverride = 720
  local function speciesOf(name)
    local ok, v = pcall(C.require, C, "species", name)
    if ok and v then return v end
    error("no species " .. name)
  end
  local spot = env("CAM_SPOT") or "EM_ROUTE101:10:10:down"
  local mapId, sx, sy, facing = spot:match("([^:]+):(%d+):(%d+):?(%a*)")
  local px, py = tonumber(sx), tonumber(sy)
  facing = facing ~= "" and facing or "down"
  pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = facing })
  local s = Runtime.getSession()
  if s then s.x, s.y = px, py end
  Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
  Player.targetX, Player.targetY, Player.facing = px, py, facing
  local double = env("CAM_DOUBLE") ~= nil
  local dynamax = env("CAM_DYNAMAX") ~= nil
  local MR = dynamax and game.mods.exports and game.mods.exports.max_raids
  local Tt = MR and MR._test
  local Dm = Tt and Tt.dmax
  if dynamax and not (Dm and Dm.installed) then log("FAIL Galar Rising's Dynamax not installed"); return end
  if s and dynamax then
    s.party = {}
    Party.giveMon(s, speciesOf("SPECIES_CHARIZARD"), 50)
    local zard = s.party[1]
    local function mv(name) return C.require(C, "moves", name) end
    zard.moves = { mv("MOVE_FLAMETHROWER"), mv("MOVE_SLASH"), mv("MOVE_GROWL"), mv("MOVE_WING_ATTACK") }
    zard.pp, zard.maxPp = { 15, 20, 40, 35 }, { 15, 20, 40, 35 }
    local dx = game.mods.exports.national_dex_gen3 and game.mods.exports.national_dex_gen3.dynamax
    if dx then dx.setLevel(zard, 10); dx.setFactor(zard, true) end
    require("src.core.game3.bag").add(s.bag, Tt.band.index, 1)
    Tt.dmaxMode("league")
  elseif s and double then
    s.party = {}
    for _, name in ipairs({ "SPECIES_SWAMPERT", "SPECIES_BLAZIKEN", "SPECIES_SCEPTILE" }) do
      Party.giveMon(s, speciesOf(name), 45)
    end
  elseif s and #(s.party or {}) == 0 then
    Party.giveMon(s, speciesOf(env("CAM_MON") or "SPECIES_AGGRON"), 40)
  end
  U.wait(40)
  hd.setScene(true)
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local ok, err
  if dynamax then
    local Trainers = require("src.core.game3.scripting.trainers")
    local tid = C.require(C, "trainers", env("CAM_LEADER") or "TRAINER_FLANNERY_1")
    ok, err = BattleBridge.start(Runtime._mod, game, Trainers.foeFromId(tid), { wild = false, trainerId = tid })
  elseif double then
    local Trainers = require("src.core.game3.scripting.trainers")
    local foe = Trainers.foeFromId(C.require(C, "trainers", "TRAINER_GINA_AND_MIA_1"))
    foe.doubleBattle = true
    ok, err = BattleBridge.start(Runtime._mod, game, foe, { double = true })
  else
    ok, err = BattleBridge.startWild(Runtime._mod, game,
      { species = speciesOf(env("CAM_FOE") or "SPECIES_TROPIUS"), level = 30 }, { fade = false })
  end
  if not ok then log("FAIL start", tostring(err)); return end
  waitFor(function()
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
    return Ui._mode == "menu" and not Anim.busy()
  end, 3000)
  U.wait(30)
  if dynamax then
    -- (her Pokemon sturdy, so the battle lasts; FIGHT, R for Dynamax, the first Max Move)
    local st = Battle.getState()
    for _, m in ipairs(st.foeParty or {}) do m.maxHp, m.hp = 999, 999 end
    if st.enemy and st.enemy.mon then st.enemy.mon.maxHp, st.enemy.mon.hp = 999, 999 end
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "r")
    U.wait(10)
    log("Dynamax picked:", tostring(Dm.sel[0]))
    U.tap(game, "a")
    local grown = waitFor(function()
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
      local v = Dm.vis[0]
      return v ~= nil and (v.k or 1) > 1.45 and Battle._phase == "command" and Ui._mode == "menu" and not Anim.busy()
    end, 6000)
    log("giant on the field:", tostring(grown), "drawn x", tostring(Dm.vis[0] and Dm.vis[0].k))
    U.wait(30)
  end
  local sc = Scene.current(Battle._st)
  if not sc then log("FAIL no scene:", tostring(hd.stats().scene), tostring(hd.stats().sceneError)); return end
  -- (the real right stick once: no controller here, nothing pushed)
  local okR, rx, ry, r3 = pcall(Orbit.readPad)
  log("the right stick as read:", tostring(okR), tostring(rx), tostring(ry), tostring(r3))
  local pad = { x = 0, y = 0, down = false, ly = 0 }
  Orbit.readPad = function() return pad.x, pad.y, pad.down, pad.ly end
  local function look()
    local L = sc.look
    if not L then return "no look" end
    local e, p = L.feet.enemy, L.feet.player
    if L.double then e, p = L.feet[1] or e, L.feet[0] or p end
    return ("yaw %.1f pitch %.1f dolly %.2f on %s | enemy %.0f,%.0f r %.2f | player %.0f,%.0f r %.2f | error %s"):format(
      math.deg(L.eyaw), math.deg(L.epitch), L.em, tostring(L.on), e and e.u or -1, e and e.v or -1, e and e.r or 0,
      p and p.u or -1, p and p.v or -1, p and p.r or 0, tostring(hd.stats().lookError))
      .. (" | bodies %s %s | badness %.2f"):format(e and e.body and table.concat(e.body, ",") or "-",
        p and p.body and table.concat(p.body, ",") or "-", Orbit.badness(sc, L.yaw, L.pitch))
  end
  local function turn(yaw, pitch)
    local L = Orbit.look(sc)
    L.yaw, L.pitch = math.rad(yaw), math.rad(pitch)
    U.wait(90)
  end
  -- CAM_OCC_BIAS: how far in front of a battler's feet the world must stand to draw over it
  if env("CAM_OCC_BIAS") then core.OCC_BIAS = tonumber(env("CAM_OCC_BIAS")) end
  local shots = 0
  for c in (env("CAM") or "0:30,-45:30,45:30,0:10,0:75,-30:55"):gmatch("[^,]+") do
    local yaw, pitch = c:match("(-?[%d.]+):(-?[%d.]+)")
    turn(tonumber(yaw), tonumber(pitch))
    shots = shots + 1
    local name = ("cam%02d_%s_%s"):format(shots, yaw, pitch):gsub("-", "m")
    U.shot(game, ("%s/%s.png"):format(dir, name))
    log(name, look(), "| occluded", tostring(hd.stats().occluded), "error", tostring(hd.stats().occError))
  end
  turn(0, 30)
  -- the stick held: as far as it lets the view go each way
  for _, side in ipairs({ { "left", -1 }, { "right", 1 } }) do
    pad.x = side[2]
    U.wait(150)
    pad.x = 0
    U.wait(30)
    U.shot(game, ("%s/stick_%s.png"):format(dir, side[1]))
    log("stick_" .. side[1], look())
    pad.down = true
    U.wait(2)
    pad.down = false
    U.wait(60)
  end
  log("after R3", look())
  -- the zoom: the wheel, then the left stick
  local sticks = game.input and game.input.effectiveStickBindings
  log("left stick up/down on the menus meanwhile:", tostring(sticks and sticks.leftstick_up),
    tostring(sticks and sticks.leftstick_down), "left/right:", tostring(sticks and sticks.leftstick_left))
  for _, z in ipairs({ { "wheel_out", -1, 6 }, { "wheel_in", 1, 14 } }) do
    for _ = 1, z[3] do
      Orbit.wheel(z[2], love.timer.getTime())
      U.wait(2)
    end
    U.wait(60)
    U.shot(game, ("%s/%s.png"):format(dir, z[1]))
    log(z[1], look())
  end
  pad.down = true
  U.wait(2)
  pad.down = false
  U.wait(60)
  for _, z in ipairs({ { "lstick_out", 1 }, { "lstick_in", -1 } }) do
    pad.ly = z[2]
    U.wait(90)
    pad.ly = 0
    U.wait(30)
    U.shot(game, ("%s/%s.png"):format(dir, z[1]))
    log(z[1], look())
  end
  pad.down = true
  U.wait(2)
  pad.down = false
  U.wait(60)
  -- a move with the view turned (CAM_MOVE, default MOVE_EMBER: the player's at the foe, then the
  -- foe's at the player): its effects land on the battlers where they stand
  turn(tonumber(env("CAM_MOVE_YAW") or "-30"), 30)
  local frames = {}
  for n in (env("CAM_MOVE_FRAMES") or "10,25,40,55"):gmatch("%d+") do frames[tonumber(n)] = true end
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local moveName = env("CAM_MOVE") or "MOVE_EMBER"
  local okM, moveId = pcall(C.require, C, "moves", moveName)
  if not okM then log("FAIL no move", moveName, tostring(moveId)) end
  for _, who in ipairs({ { "player", "enemy" }, { "enemy", "player" } }) do
    if okM then
      local okA, errA = pcall(AnimSeq.beginEvents, { { kind = "move", moveId = moveId, attacker = who[1], target = who[2] } },
        function() end)
      if not okA then log("FAIL move anim", tostring(errA)) end
      for f = 1, 90 do
        pcall(AnimSeq.update)
        U.wait(1)
        if frames[f] then U.shot(game, ("%s/move_%s_%03d.png"):format(dir, who[1], f)) end
      end
      U.wait(30)
    end
  end
  log("after the move", look())
  -- the option off: the battle's own view at once
  Orbit.enabled = false
  U.wait(10)
  U.shot(game, ("%s/option_off.png"):format(dir))
  log("option off", look())
  log("left stick up/down on the menus again:", tostring(sticks and sticks.leftstick_up),
    tostring(sticks and sticks.leftstick_down))
  Orbit.enabled = true
  Orbit.readPad = nil
  if Battle.abort then pcall(Battle.abort) end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_camera"
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
