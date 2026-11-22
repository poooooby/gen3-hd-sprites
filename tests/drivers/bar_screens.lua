-- Driver: the battle bar where the game shows its battle text box - a wild battle's command and
-- move menus, a catch (its "Gotcha", the Pokedex page after it, the nickname prompt) and an
-- evolution (its "is evolving" and its congratulations) - a shot of each. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/bar_screens.lua love .
-- HD_SIZE=WxH (1920x1080); HD_FILL=off; HD_BAR=off (Battle Text Box off: the game's own box).

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_bar_screens"
  local sw, sh = (os.getenv("HD_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(sw), tonumber(sh), { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(60)
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local fr = version == "firered" or version == "leafgreen"
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local mapId, px, py = fr and "FR_ROUTE_1" or "EM_ROUTE101", 10, fr and 20 or 10
  for _ = 1, 4 do
    pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "down" })
    local s0 = Runtime.getSession()
    if s0 then s0.x, s0.y = px, py end
    Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
    Player.targetX, Player.targetY = px, py
    U.wait(20)
  end
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Evolution = require("src.core.game3.evolution")
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  local C = require("src.core.game3.constants").of(version)
  local loader = game.mods
  local hd = loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites missing") return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  hd.setFit(true)
  hd.setFill(os.getenv("HD_FILL") ~= "off")
  hd.setScene(os.getenv("HD_SCENE") == "on")
  if os.getenv("HD_BAR") == "off" and hd.setBar then hd.setBar(false) end
  local n = 0
  local function shot(name)
    n = n + 1
    log("shot", name, U.shot(game, ("%s/%02d_%s.png"):format(dir, n, name)) and "ok" or "MISSING")
  end

  local s = Runtime.getSession()
  s.party = {}
  local starter = C.species.byName[fr and "SPECIES_CHARMANDER" or "SPECIES_TORCHIC"]
  Party.giveMon(s, starter, 16)
  local master = C.items.byName.ITEM_MASTER_BALL
  Bag.add(s.bag, master, 1)
  local target = C.species.byName[fr and "SPECIES_PIDGEY" or "SPECIES_WURMPLE"]
  if not Bridge.startWild(Runtime._mod, game, { species = target, level = 3 }, { fade = false }) then
    log("FAIL wild battle") return
  end
  for _ = 1, 600 do if Battle.isActive() then break end U.wait(1) end
  local function atCommand() return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" end
  for _ = 1, 3000 do
    if atCommand() then break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") U.wait(8) else U.wait(1) end
  end
  U.wait(30)
  shot("b1_menu")
  U.tap(game, "a")
  for _ = 1, 60 do if Ui._mode == "moves" then break end U.wait(1) end
  U.wait(20)
  shot("b2_moves")
  U.tap(game, "b")
  for _ = 1, 60 do if Ui._mode == "menu" then break end U.wait(1) end
  U.wait(10)
  -- the catch: a Master Ball
  Ui._pendingCommand = { kind = "bag", itemId = master, user = "player" }
  Ui._mode = "none"
  local seen = {}
  for frame = 1, 9000 do
    if not Battle.isActive() then break end
    local page = Message.isOpen() and Message.currentPage and Message.currentPage() or ""
    if page:find("Gotcha", 1, true) and not seen.gotcha then
      seen.gotcha = true
      U.wait(30)
      shot("c1_gotcha")
    elseif Ui._caughtDexScene and not seen.dex then
      seen.dex = true
      U.wait(60)
      shot("c2_dex_scene")
    elseif Choice.isOpen and Choice.isOpen() then
      if not seen.choice then
        seen.choice = true
        U.wait(20)
        shot("c3_nickname")
      end
      U.tap(game, "b")
      U.wait(10)
    elseif (Message.isOpen() and Message.isWaiting and Message.isWaiting() or Battle._phase == "pokedex_reg")
        and frame % 20 == 0 then
      if Battle._phase == "pokedex_reg" and not seen.reg then
        seen.reg = true
        U.wait(30)
        shot("c2b_pokedex_reg")
      end
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  for _ = 1, 600 do if not Battle.isActive() then break end U.wait(1) end
  U.wait(60)
  -- the evolution
  local mon = s.party[1]
  local pending = Evolution.pending(s.party, { [1] = true, 1 }, s)
  local entry = pending and pending[1]
  local into = entry and (entry.toSpecies or entry.target)
  if not into then log("FAIL no evolution due") return end
  EvolutionScene.start(mon, into, { session = s, canStop = true })
  local taken = {}
  local want = { intro_msg = "e1_is_evolving", cycle = "e2_cycle", congrats = "e3_congrats" }
  for _ = 1, 4000 do
    local st = EvolutionScene._state
    if want[st] and not taken[st] then
      taken[st] = true
      U.wait(st == "cycle" and 60 or 20)
      shot(want[st])
    end
    if not EvolutionScene.isOpen() then break end
    if st == "congrats" or st == "done" or st == "learn" then U.tap(game, "a") U.wait(10) else U.wait(1) end
  end
  log("done")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "."
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
