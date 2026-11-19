-- Driver: a single trainer battle in the 3D world, fought to its end: boots Emerald, starts
-- Roxanne's battle with the foes swapped for HD_FOES (level 3), the player's one Pokemon
-- (HD_PLAYER, level 100) Tackling each in turn, and logs the camera every few frames (zoom, its
-- target, the trainer shown, each battler out) with a shot at each change (the trainer's intro,
-- each send-out, each faint, the trainer's last words) and once settled after it. Run from the
-- engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/trainer_battle.lua love .
-- HD_SIZE=WxH (default 1920x1080); HD_SPOT=MAP[:x:y] (default Route 101's middle);
-- HD_PLAYER=SPECIES_X (default Pikachu); HD_FOES=SPECIES_A,SPECIES_B (default Wailord, Pikachu);
-- HD_REALSIZES=off: 3D Sizing off.

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_trainer"
  local sw, sh = (os.getenv("HD_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  sw, sh = tonumber(sw), tonumber(sh)
  love.window.setMode(sw, sh, { resizable = true, highdpi = true, vsync = 0 })
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
  log(("spot %s at %d,%d (%s)"):format(mapId, px, py, tostring(Map.currentDef() and Map.currentDef().id)))

  local Party = require("src.core.game3.party")
  local Trainers = require("src.core.game3.scripting.trainers")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local Anim = require("src.core.game3.battle.anim")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  hd.setScene(true)
  if os.getenv("HD_REALSIZES") == "off" and hd.setRealSizes then hd.setRealSizes(false) end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false
  end
  s.party = {}
  local mine = os.getenv("HD_PLAYER") or "SPECIES_PIKACHU"
  Party.giveMon(s, C.species.byName[mine], 100, (mine:gsub("^SPECIES_", "")))
  local tackle = C.moves and C.moves.byName and C.moves.byName.MOVE_TACKLE
  local lead = s.party[1]
  if tackle and lead then
    lead.moves = lead.moves or {}
    lead.moves[1] = tackle
    lead.pp = lead.pp or {}
    lead.pp[1] = 35
  end
  local foe = Trainers.foeFromId(C.trainers.byName.TRAINER_ROXANNE_1)
  local tmpl = foe.party[1]
  foe.party = {}
  for name in (os.getenv("HD_FOES") or "SPECIES_WAILORD,SPECIES_PIKACHU"):gmatch("[%w_]+") do
    local m = {}
    for k, v in pairs(tmpl) do m[k] = v end
    m.species, m.level = C.species.byName[name], 3
    foe.party[#foe.party + 1] = m
  end
  foe.species, foe.level = foe.party[1].species, 3
  foe.doubleBattle = false
  local ok, err = pcall(function()
    local started, why = BattleBridge.start(Runtime._mod, game, foe, {})
    if not started then error(tostring(why)) end
  end)
  if not ok then log("FAIL start:", tostring(err)); return end

  local bapi = BattleAPI.new(game)
  local intent = 0
  local core = hd._core and hd._core()
  local function state()
    local stage = Anim._stage
    local tr = stage and stage.trainer and stage.trainer.enemy
    local p0, p1 = rawget(Anim._present, 0), rawget(Anim._present, 1)
    return (tr and tr.visible) and "T" or "-", (p1 and p1.visible) and "E" or "-", (p0 and p0.visible) and "P" or "-"
  end
  local last, settleAt, shots, sawBattle = nil, nil, 0, false
  local function shot(tag)
    shots = shots + 1
    if shots <= 40 then U.shot(game, ("%s/%02d_%s.png"):format(dir, shots, tag)) end
  end
  for frame = 1, 9000 do
    U.wait(1)
    local st = Battle._st
    if st then sawBattle = true elseif sawBattle then log(("frame %d: battle over"):format(frame)); break end
    local t, e, p = state()
    local key = t .. e .. p
    local v = hd.stats()
    local sn = bapi:snapshot()
    local prompt = sn and sn.prompt
    if frame % 6 == 0 or key ~= last then
      log(("f%04d %s phase %s prompt %s zoom %.3f target %.3f box %s enemy %s"):format(frame, key, tostring(Battle._phase),
        tostring(prompt), v.zoom or -1, v.zoomTarget or -1, tostring(core and core.fit and core.fit.boxBottom),
        tostring(sn and sn.enemy and sn.enemy.species)))
    end
    if key ~= last then
      shot(key:gsub("%-", "_") .. "_at")
      settleAt = frame + 60
      last = key
    elseif settleAt and frame == settleAt then
      shot(key:gsub("%-", "_") .. "_settled")
      settleAt = nil
    end
    if prompt == "advance" then
      U.tap(game, "a")
    elseif prompt == "menu" and sn then
      intent = intent + 1
      bapi:submit({ id = intent, revision = sn.revision, kind = "menu", choice = "fight" })
    elseif prompt == "moves" and sn then
      intent = intent + 1
      bapi:submit({ id = intent, revision = sn.revision, kind = "move", slot = 1 })
    elseif prompt ~= nil and prompt ~= "advance" and frame % 20 == 0 then
      log("prompt", tostring(prompt), "-> B")
      U.tap(game, "b")
    end
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_trainer"
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
