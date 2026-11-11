-- Driver: the whole screens the start menu opens over the field, with Fill Screen. Boots a game,
-- gives the party a few Pokemon, opens the start menu and each of its screens through the menu's
-- own entries (the Pokedex, the party, the bag, the options, the mods, the trainer card) and
-- screenshots them, in each window size. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/field_screens.lua love .
-- HD_SIZES=WxH,WxH,... (default 1920x1080,540x1200); POKEPORT_TOUCH=1 shows the touch controls.

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_field_screens"
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
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local s = Runtime.getSession()
  for _, name in ipairs({ "SPECIES_WAILORD", "SPECIES_TORCHIC", "SPECIES_RAYQUAZA" }) do
    pcall(Party.giveMon, s, C:require("species", name), 30)
  end
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false
  end
  local Stack = require("src.ui.game3.stack")
  local StartMenu = require("src.ui.game3.start_menu")
  local Screens = require("src.ui.game3.screens")

  local function shot(name, label)
    local st = hd.stats()
    log(("%s %s: fullscreen %s screen passes %s composites %d flattened %d failed %s ui %s card %s"):format(
      name, label, tostring(Stack.fullscreen()), tostring(st.screenPasses), st.composites or 0,
      st.flattened or 0, tostring(st.failed), tostring(st.uiScale), tostring(st.card)))
    U.shot(game, ("%s/%s_%s.png"):format(dir, name, label))
  end

  -- the start menu's entry for `id` chosen as the player would; a screen the menu does not offer
  -- yet (no Pokedex on a new game) is opened the way the menu would open it
  local function open(id)
    if not StartMenu.isOpen() then
      StartMenu.show({ session = s, game = game })
      U.wait(20)
    end
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == id then
        StartMenu.cursor = i
        StartMenu.confirm()
        return "menu"
      end
    end
    if id == "pokedex" then
      Screens.get("pokedex", s).show(s.dex, { session = s })
    elseif id == "pokemon" then
      Screens.get("party", s).show(s.party, s.move_overlay, { session = s })
    elseif id == "bag" then
      Screens.get("bag", s).show(s.bag, { session = s, onClose = function() end })
    elseif id == "option" then
      Screens.get("option", s).show({ session = s })
    elseif id == "mods" then
      require("src.ui.game3.mod_manager").show({ game = game, session = s })
    elseif id == "trainer" then
      Screens.get("trainer_card", s).show({ session = s })
    end
    return "direct"
  end

  local function close()
    for _ = 1, 40 do
      if not Stack.fullscreen() then break end
      U.tap(game, "b")
      U.wait(12)
    end
    U.wait(30)
  end

  for i, sz in ipairs(sizes) do
    if i > 1 then
      love.window.setMode(sz[1], sz[2], { resizable = true, highdpi = true })
      U.wait(10)
    end
    local name = sz[1] .. "x" .. sz[2]
    shot(name, "field")
    for _, id in ipairs({ "pokedex", "pokemon", "bag", "option", "mods", "trainer" }) do
      local how = open(id)
      U.wait(120)
      log(name, id, "opened from", how)
      shot(name, id)
      close()
    end
    if StartMenu.isOpen() then StartMenu.close(true) end
    U.wait(20)
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_field_screens"
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
