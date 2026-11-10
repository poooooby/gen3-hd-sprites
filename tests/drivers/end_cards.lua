-- Driver: the screens a battle ends with, with Fill Screen. Boots a game, starts a wild battle,
-- opens each screen over it and screenshots it, in each window size: the Pokedex page of a new
-- catch, the caught Pokemon's scene, the nickname screen, the summary (as when forgetting a
-- move), evolution, the party and the bag. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/end_cards.lua love .
-- HD_SIZES=WxH,WxH,... (default 1920x1080,540x1200); POKEPORT_TOUCH=1 shows the touch controls.

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_end_cards"
  local sizes = {}
  for w, h in (os.getenv("HD_SIZES") or "1920x1080,540x1200"):gmatch("(%d+)x(%d+)") do
    sizes[#sizes + 1] = { tonumber(w), tonumber(h) }
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(sizes[1][1], sizes[1][2], { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local s = Runtime.getSession()
  local enemySpecies = C:require("species", "SPECIES_SCIZOR")
  if #s.party == 0 then pcall(Party.giveMon, s, C:require("species", "SPECIES_TORCHIC"), 30) end
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false
  end
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)

  local function shot(name, label)
    local st = hd.stats()
    log(("%s %s: phase %s composites %d flattened %d failed %s fill %s ui %s card %s"):format(name, label,
      tostring(Battle._phase), st.composites or 0, st.flattened or 0, tostring(st.failed), tostring(st.fill),
      tostring(st.uiScale), tostring(st.card)))
    U.shot(game, ("%s/%s_%s.png"):format(dir, name, label))
  end

  local function startBattle()
    local ok, err = pcall(function()
      local started = BattleBridge.startWild(Runtime._mod, game, { species = enemySpecies, level = 20 }, {})
      if not started then error("startWild refused") end
    end)
    if not ok then log("startWild failed:", tostring(err)); return false end
    local reached = false
    for _ = 1, 1500 do
      U.wait(1)
      local sn = bapi:snapshot()
      local p = sn and sn.prompt
      if p == "advance" then U.tap(game, "a"); U.wait(4)
      elseif p == "menu" then reached = true; break end
    end
    log("menu reached:", tostring(reached))
    return reached
  end

  -- the screens, over the running battle (which is never ended: the driver just quits)
  local function cards(name)
    U.wait(30)
    shot(name, "battle")
    local mon = s.party[1]

    -- the Pokedex page of a new catch
    if version == "firered" or version == "leafgreen" then
      local Pokedex = require("src.ui.game3.pokedex")
      Pokedex.showRegistration(enemySpecies, { session = s, onDone = function() end })
      U.wait(150)
      shot(name, "dex_page")
      if Pokedex.close then Pokedex.close() else Pokedex.open = false end
    else
      local Dex = require("src.ui.game3.rse.pokedex")
      Dex.showCaughtMon(enemySpecies, { session = s, personality = 1, otId = 1, otSecretId = 1, onDone = function() end })
      U.wait(150)
      shot(name, "dex_page")
      Dex.reset()
    end
    U.wait(10)

    -- the caught Pokemon's scene, after the page
    local frlg = version == "firered" or version == "leafgreen"
    local pic = Pokemon.frontPic(enemySpecies, nil, false, 1, "dex")
    Ui.beginCaughtDexScene({ family = frlg and "frlg" or "rse", personality = 1, otId = 1, otSecretId = 1,
      shiny = false, sprite = { img = pic.image, x = 120, y = frlg and 64 or 80 } })
    U.wait(60)
    shot(name, "caught_scene")
    Ui.clearCaughtDexScene()
    U.wait(5)

    -- the nickname screen
    local Naming = require("src.ui.game3.naming")
    Naming.open({ template = "CAUGHT_MON", maxLen = 10, species = enemySpecies, gender = 0, personality = 1,
      seed = "SCIZOR", title = Naming.monTitle(Pokemon.name(enemySpecies)), onDone = function() end })
    U.wait(90)
    shot(name, "naming")
    Naming.openFlag = false
    U.wait(5)

    -- the summary, as when forgetting a move
    local SummaryMenu = require("src.ui.game3.summary_menu")
    SummaryMenu.openMenu(s.party, 1)
    U.wait(90)
    shot(name, "summary")
    SummaryMenu.close()
    U.wait(10)

    -- evolution
    local Scene = require("src.ui.game3.evolution_scene")
    Scene.start(mon, C:require("species", "SPECIES_COMBUSKEN"), { canStop = false, onDone = function() end })
    U.wait(100)
    shot(name, "evolution")
    Scene.open = false
    U.wait(5)

    -- the party
    local PartyMenu = require("src.ui.game3.party_menu")
    PartyMenu.show(s.party, s.move_overlay, { mode = "battle", onSelect = function() end, onCancel = function() end })
    U.wait(60)
    shot(name, "party")
    PartyMenu.close()
    U.wait(5)

    -- the bag
    local BagMenu = require("src.ui.game3.bag_menu")
    BagMenu.show(s.bag, { mode = "battle", onSelect = function() end, onCancel = function() end })
    U.wait(60)
    shot(name, "bag")
    if BagMenu.close then BagMenu.close() end
    U.wait(5)
  end

  if not startBattle() then return end
  for i, sz in ipairs(sizes) do
    if i > 1 then
      love.window.setMode(sz[1], sz[2], { resizable = true, highdpi = true })
      U.wait(10)
    end
    cards(sz[1] .. "x" .. sz[2])
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_end_cards"
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
