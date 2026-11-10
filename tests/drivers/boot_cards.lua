-- Driver: the screens before the game starts, with Fill Screen. Boots a game and plays through
-- them with the buttons, screenshotting each: the intro movie, the title, the main menu, the
-- options (where the menu has them), the professor's speech and the naming screens. Run from the
-- engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/boot_cards.lua love .
-- HD_SIZE=WxH (default 1920x1080); POKEPORT_TOUCH=1 shows the touch controls. The driver quits
-- when the game would start, and never saves.

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_boot_cards"
  local w, h = (os.getenv("HD_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local b = game.boot
  if not b then log("FAIL boot phase not reached; phase:", game.phase); return end
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  local Boot = require("src.ui.game3.boot")
  local Naming = require("src.ui.game3.naming")
  local P = Boot.PHASE

  local n = 0
  local function shot(name)
    n = n + 1
    local st = hd.stats()
    log(("%02d %s: boot phase %s failed %s ui %s card %s"):format(n, name, tostring(b.phase),
      tostring(st.failed), tostring(st.uiScale), tostring(st.card)))
    U.shot(game, ("%s/%02d_%s.png"):format(dir, n, name))
  end
  local function waitPhase(pred, limit, press)
    for i = 1, limit do
      if pred() then return true end
      if press and i % 20 == 0 then U.tap(game, press) else U.wait(1) end
    end
    return pred() and true or false
  end

  -- the intro movie, along its length
  for i = 1, 9 do
    U.wait(220)
    if b.phase ~= P.INTRO then break end
    shot("intro" .. i)
  end
  local isTitle = function() return b.phase == P.TITLE or b.phase == P.TITLE_CRY or b.phase == P.TITLE_RESTART end
  log("title reached:", tostring(waitPhase(isTitle, 900, "start")))
  U.wait(420)
  shot("title")
  log("menu reached:", tostring(waitPhase(function() return b.phase == P.MENU end, 1500, "start")))
  U.wait(90)
  shot("menu")

  -- the options, on a menu that has them
  local menu = b.custom and b.custom.menu
  local function moveTo(id)
    if not (menu and menu.items) then return false end
    for _ = 1, 8 do
      if menu.items[menu.cursor] == id then return true end
      U.tap(game, "down")
      U.wait(12)
    end
    return false
  end
  if moveTo("OPTION") then
    U.tap(game, "a")
    U.wait(90)
    shot("option")
    U.tap(game, "b")
    U.wait(90)
    menu = b.custom and b.custom.menu
    for _ = 1, 8 do
      if not menu or menu.items[menu.cursor] == "NEW_GAME" then break end
      U.tap(game, "up")
      U.wait(12)
    end
  elseif not b.custom then
    -- FireRed/LeafGreen's menu: new game is the row after Continue
    if b.hasContinue then U.tap(game, "down"); U.wait(12) end
  end
  shot("menu_new_game")
  U.tap(game, "a")

  -- the speech: A through it, a shot along the way, each naming screen given a name
  local namings, lastShot, frames = 0, 0, 0
  while frames < 9000 and game.phase == "boot" do
    if Naming.isOpen() then
      U.wait(60)
      namings = namings + 1
      shot("naming" .. namings)
      U.tap(game, "a"); U.wait(10)
      U.tap(game, "start"); U.wait(10)
      U.tap(game, "a"); U.wait(40)
      frames = frames + 130
    else
      if frames - lastShot >= 300 then
        lastShot = frames
        shot("speech" .. math.floor(frames / 300))
      end
      U.tap(game, "a")
      U.wait(9)
      frames = frames + 10
    end
  end
  log("namings:", namings, "game phase:", tostring(game.phase))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_boot_cards"
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
