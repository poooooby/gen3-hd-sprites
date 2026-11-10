-- Driver: a double battle with Fill Screen, against foes of each size: boots a game, starts one
-- double trainer battle, reaches the menu, then swaps the foes' species in place and screenshots
-- each pair. Never ends the battle. One window size a run: resizing mid-battle loses the sprites.
-- Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/doubles_battle.lua love .
-- HD_SIZE=WxH (default 1920x1080); POKEPORT_TOUCH=1 shows the touch controls.

local PAIRS = {
  { "small", "SPECIES_SEEDOT", "SPECIES_LOTAD" },
  { "mid", "SPECIES_SCIZOR", "SPECIES_ABSOL" },
  { "big", "SPECIES_WAILORD", "SPECIES_STEELIX" },
  { "tall", "SPECIES_DRAGONITE", "SPECIES_RAYQUAZA" },
}

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_doubles"
  local sw, sh = (os.getenv("HD_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  sw, sh = tonumber(sw), tonumber(sh)
  love.window.setMode(sw, sh, { resizable = true, highdpi = true })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Trainers = require("src.core.game3.scripting.trainers")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false
  end
  s.party = {}
  Party.giveMon(s, C.species.byName.SPECIES_SWAMPERT, 45, "SWAMPERT")
  Party.giveMon(s, C.species.byName.SPECIES_BLAZIKEN, 45, "BLAZIKEN")
  Party.giveMon(s, C.species.byName.SPECIES_SCEPTILE, 45, "SCEPTILE")
  local foe = Trainers.foeFromId(C.trainers.byName.TRAINER_GINA_AND_MIA_1)
  foe.doubleBattle = true
  local ok, err = pcall(function()
    local started, why = BattleBridge.start(Runtime._mod, game, foe, { double = true })
    if not started then error(tostring(why)) end
  end)
  if not ok then log("FAIL start:", tostring(err)); return end
  local bapi = BattleAPI.new(game)
  local reached = false
  for _ = 1, 2400 do
    U.wait(1)
    local sn = bapi:snapshot()
    local p = sn and sn.prompt
    if p == "advance" then U.tap(game, "a"); U.wait(4)
    elseif p == "menu" then reached = true; break end
  end
  log("menu reached:", tostring(reached), "double:", tostring(Battle._st and Battle._st.double))
  local st = Battle._st
  for _, pair in ipairs(PAIRS) do
    for slot, key in pairs({ [1] = pair[2], [3] = pair[3] }) do
      local b = st.battlers[slot]
      b.species, b.mon.species = C.species.byName[key], C.species.byName[key]
    end
    U.wait(120)
    local v = hd.stats()
    local name = ("%dx%d_%s"):format(sw, sh, pair[1])
    log(("%s: fill %s ui %s zoom %s target %s lift %s shiftE %s shiftP %s failed %s"):format(name, tostring(v.fill),
      tostring(v.uiScale), tostring(v.zoom), tostring(v.zoomTarget), tostring(v.lift), tostring(v.shiftEnemy),
      tostring(v.shiftPlayer), tostring(v.failed)) .. " up " .. tostring(v.sceneUp) .. " topDy " .. tostring(v.uiTopDy))
    U.shot(game, ("%s/%s.png"):format(dir, name))
  end

  -- HD_ATTACK=1: a move from each of the player's two, shots through the turn (the last foes)
  if os.getenv("HD_ATTACK") then
    local AnimCoords = require("src.core.game3.battle.anim_coords")
    for _ = 1, 2 do
      for _ = 1, 3 do U.tap(game, "a"); U.wait(25) end
    end
    for i = 1, 40 do
      U.wait(8)
      local v, d1 = hd.stats(), AnimCoords.DOUBLES[1]
      log(("attack%02d: phase %s zoom %s shiftE %s shiftP %s foe x %s"):format(i, tostring(Battle._phase),
        tostring(v.zoom), tostring(v.shiftEnemy), tostring(v.shiftPlayer), tostring(d1.x)))
      U.shot(game, ("%s/attack_%02d.png"):format(dir, i))
    end
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_doubles"
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
