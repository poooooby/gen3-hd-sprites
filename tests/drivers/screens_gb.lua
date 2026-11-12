-- Driver: Fill Screen on Red / Blue / Yellow's whole screens. Boots to the intro movie, then
-- the title, the main menu, Oak's speech and the naming screen (a new game), then in the field
-- the START menu (an overlay: not a whole screen), the Pokedex, the party and the options; a
-- still of each with Fill Screen on and off, logging WoobleView's screen passes and cards.
-- SCREEN_SIZE (default 1920x1080) sets the window, SCREEN_COLORS the colour mode (PaletteFX).
-- Run from an engine root with the mod installed:
--   SHOT_DIR=<dir> POKEPORT_VERSION=red POKEPORT_GAME=red \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/screens_gb.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = dofile("tests/drivers/util.lua")
  local dir = env("SHOT_DIR") or "/tmp/hd_screens_gb"
  local exports = game.mods and game.mods.exports or {}
  local hd = exports["gen3-hd-sprites"]
  if not hd then
    log("WoobleView not loaded: the game's own drawing")
    hd = { stats = function() return {} end, setFill = function() end, isActive = function() return false end }
  end
  local w, h = (env("SCREEN_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
  local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
  if okP and env("SCREEN_COLORS") then PaletteFX.mode = env("SCREEN_COLORS") end
  log(("WoobleView active %s, colour mode %s"):format(tostring(hd.isActive()),
    tostring(okP and PaletteFX.mode)))

  -- the top state's name: its screen id, else the module its class came from
  local function top()
    local names = {}
    for name, m in pairs(package.loaded) do
      if type(m) == "table" and (name:match("^src%.ui%.") or name:match("^src%.world%.")) then names[m] = name end
    end
    local t = game.stack:top()
    if t == nil then return "nil" end
    if t == game.overworld then return "overworld" end
    local mt = getmetatable(t)
    return t.screenId or (mt and (names[mt] or names[mt.__index])) or tostring(t)
  end
  -- press `btn` until the top state changes (at most n times)
  local function pressUntilChange(btn, n)
    local was = game.stack:top()
    for _ = 1, n or 30 do
      U.tap(game, btn)
      U.wait(8)
      if game.stack:top() ~= was then return true end
    end
    return false
  end
  local function stat(k) return tostring(hd.stats()[k]) end
  local function shots(name)
    for _, on in ipairs({ true, false }) do
      hd.setFill(on)
      U.wait(2)
      U.still(game, ("%s/%s_%s.png"):format(dir, name, on and "fill" or "plain"))
    end
    hd.setFill(true)
    log(("%s (%s): screenPasses %s card %s composites %s failed %s"):format(name, top(),
      stat("screenPasses"), stat("card"), stat("composites"), stat("failed")))
  end

  U.wait(40)
  shots("1_intro")
  -- the shooting star, then the fight (OG RED redraws their sprites over the blit)
  U.wait(200)
  shots("1b_intro")
  U.wait(240)
  shots("1c_intro")
  pressUntilChange("start", 60)
  U.wait(90)
  shots("2_title")
  pressUntilChange("a", 60)
  U.wait(20)
  shots("3_main_menu")
  U.tap(game, "a")
  U.wait(120)
  shots("4_oak")
  local named = false
  for _ = 1, 2000 do
    U.tap(game, "a")
    U.wait(2)
    local t = game.stack:top()
    if not named and t and tostring(top()):find("Naming") then
      U.wait(20)
      shots("5_naming")
      named = true
    end
    if game.overworld and t == game.overworld then break end
  end
  U.wait(120)
  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 15), Pokemon.new(game.data, "ONIX", 12) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = true
  shots("6_field")
  log("field top: " .. top())
  -- each START menu entry in turn (POKEDEX when there is one, POKEMON, ITEM, the player's card,
  -- SAVE, OPTION), from the field each time
  for i = 1, 6 do
    if not pressUntilChange("start", 20) then log("no START menu"); break end
    U.wait(20)
    if i == 1 then shots("7_start_menu") end
    for _ = 2, i do U.tap(game, "down"); U.wait(6) end
    if pressUntilChange("a", 3) then
      U.wait(40)
      shots(("%d_menu%d"):format(7 + i, i))
    end
    for _ = 1, 20 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "b")
      U.wait(10)
    end
    if game.stack:top() ~= game.overworld then log("stuck at " .. top()); break end
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_screens_gb"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
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
