-- Driver: WoobleView's first-run prompt in Emerald. Boots a new game, stands the player on Route
-- 101 and waits for the question (WoobleView's flag file must be gone from its cache, and Battle
-- Scene on CLASSIC); then answers it (FIRST_RUN_ANSWERS, default "a,a": turn on, build now),
-- shooting each step and the progress bar every FIRST_RUN_EVERY frames (default 240) until the
-- prompt closes. FIRST_RUN_CLEAR=1 clears the 3D cache first. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/first_run.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_first_run"
  love.window.setMode(1920, 1080, { resizable = true, highdpi = true })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local Map = require("src.core.game3.map")
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Stack = require("src.ui.game3.stack")
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  if env("FIRST_RUN_CLEAR") and hd._cacheClear then log("cache cleared:", tostring(hd._cacheClear())) end
  -- FIRST_RUN_RESET=1: as a first run again (the flag file gone, Battle Scene on CLASSIC)
  if env("FIRST_RUN_RESET") then
    os.remove("mod_cache/gen3-hd-sprites/state/first_run_asked")
    loader.modOptions["gen3-hd-sprites"] = loader.modOptions["gen3-hd-sprites"] or {}
    loader.modOptions["gen3-hd-sprites"].battle_scene = "classic"
  end
  pcall(Map.load, nil, game, "EM_ROUTE101", { x = 10, y = 10, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = 10, 10 end
  Player.cellX, Player.cellY, Player.px, Player.py = 10, 10, 160, 160
  local function up()
    local top = Stack.top and Stack.top()
    return top ~= nil and top.id == "woobleview_prompt"
  end
  -- (a driver's frames skip core.update: the prompt ticked by hand)
  local function wait(n)
    for _ = 1, n do
      if hd._promptTick then hd._promptTick(1 / 60) end
      U.wait(1)
    end
  end
  local function opt(k) return tostring(loader.modOptions["gen3-hd-sprites"] and loader.modOptions["gen3-hd-sprites"][k]) end
  local waited = 0
  while not up() and waited < 600 do wait(1); waited = waited + 1 end
  if not up() then
    log("FAIL no prompt after", waited, "frames:", hd._promptWhy and hd._promptWhy() or "?")
    return
  end
  log("prompt up after", waited, "frames")
  wait(20)
  U.shot(game, dir .. "/1_ask3d.png")
  local step = 1
  for answer in (env("FIRST_RUN_ANSWERS") or "a,a"):gmatch("[^,]+") do
    U.tap(game, answer)
    wait(20)
    step = step + 1
    U.shot(game, ("%s/%d_after_%s.png"):format(dir, step, answer))
    log("answered", answer, "battle_scene", opt("battle_scene"), "prompt up", tostring(up()))
    if not up() then break end
  end
  local every, t0, n = tonumber(env("FIRST_RUN_EVERY") or "240"), love.timer.getTime(), 0
  while up() and n < 200 do
    wait(every)
    n = n + 1
    U.shot(game, ("%s/build_%03d.png"):format(dir, n))
    log(("build %.0f s: up %s"):format(love.timer.getTime() - t0, tostring(up())))
  end
  log(("prompt closed after %.0f s; battle_scene %s scene_build %s; relief %s"):format(love.timer.getTime() - t0,
    opt("battle_scene"), opt("scene_build"), tostring(hd.stats and hd.stats().sceneReliefRun)))
  wait(30)
  U.shot(game, dir .. "/9_after.png")
  -- FIRST_RUN_ACTIONS=1: Clear 3D Cache and Build 3D Cache pressed, as the options pane sets them
  if env("FIRST_RUN_ACTIONS") then
    local function press(key)
      loader.modOptions["gen3-hd-sprites"][key] = "go"
      loader.events:emit("mod.options_changed", { mod = "gen3-hd-sprites", key = key, value = "go" })
    end
    press("scene_clear")
    wait(30)
    U.shot(game, dir .. "/a_cleared.png")
    log("after clear: scene_clear", opt("scene_clear"), "relief file",
      tostring(io.open("mod_cache/gen3-hd-sprites/relief/v1/emerald-0c3fad9f.bin", "rb") ~= nil))
    wait(150)
    press("scene_build")
    wait(240)
    U.shot(game, dir .. "/b_building.png")
    log("build pressed: prompt up", tostring(up()), "scene_build", opt("scene_build"))
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_first_run"
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
