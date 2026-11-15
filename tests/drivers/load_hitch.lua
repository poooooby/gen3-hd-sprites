-- Driver: what WoobleView's 3D does in the frames after a save opens, the 3D cache already built.
-- Battle Scene on OVERWORLD, a new game stood on HITCH_SPOT (MAP:x:y, default Littleroot), then
-- the frame hook's work - the relief's start (its cache read), the models warmed one a frame, the
-- old cache's pruning, the prompt - run by hand frame by frame (a driver's frames skip
-- core.update) and timed, each frame's work and the slowest by what it was. HITCH_NOJIT=1 turns
-- LuaJIT's compiler off first, as LOVE runs on Android. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/load_hitch.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function upvalue(f, want)
  for i = 1, 200 do
    local name, v = debug.getupvalue(f, i)
    if not name then return nil end
    if name == want then return v end
  end
end

local function body(game, log)
  local U = require("tests.drivers.util")
  if env("HITCH_NOJIT") and jit then jit.off(); jit.flush(); log("jit off") end
  love.window.setMode(1280, 720, { resizable = true, vsync = 0 })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local loader = game.mods
  local hdx = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hdx then log("FAIL gen3-hd-sprites exports missing"); return end
  local hd = upvalue(hdx._sceneWarm, "hd")
  local Scene = hd and hd.scene
  local run = Scene and Scene.reliefRun
  if not (Scene and run) then log("FAIL no scene / relief run"); return end
  loader.modOptions["gen3-hd-sprites"] = loader.modOptions["gen3-hd-sprites"] or {}
  loader.modOptions["gen3-hd-sprites"].battle_scene = "overworld"
  loader.events:emit("mod.options_changed", { mod = "gen3-hd-sprites", key = "battle_scene", value = "overworld" })
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  log("scene enabled", tostring(Scene.enabled), "cacheModels", tostring(Scene.cacheModels))
  local clock = love.timer.getTime
  local t0 = clock()
  -- (the map.entered handler's own time: each map's warm, the first one loading the world)
  for _, name in ipairs({ "warm", "warmAll" }) do
    local f = Scene[name]
    Scene[name] = function(...)
      local a = clock()
      local r = { f(...) }
      log(("Scene.%s(%s) %.1f ms"):format(name, tostring((...)), (clock() - a) * 1000))
      return unpack(r)
    end
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local Map = require("src.core.game3.map")
  local spotMap, sx, sy = (env("HITCH_SPOT") or "EM_LITTLEROOT_TOWN:10:10"):match("([^:]+):(%d+):(%d+)")
  local tl = clock()
  pcall(Map.load, nil, game, spotMap, { x = tonumber(sx), y = tonumber(sy), facing = "down" })
  log(("map load %.0f ms"):format((clock() - tl) * 1000))
  local queue = upvalue(Scene.warmStep, "warmQueue")
  log("warm queue after the map's load:", queue and #queue or "?")
  if queue and #queue == 0 then
    -- (the map.entered handler, as main.lua runs it)
    local tq = clock()
    if Scene.cacheModels then Scene.warmAll() end
    Scene.warm(spotMap)
    log(("queued by hand: %d (%.1f ms)"):format(#queue, (clock() - tq) * 1000))
  end
  local function label(item)
    if type(item) == "table" and item.all ~= nil then item = item.all end
    if type(item) == "function" then return "posts/roles" end
    if type(item) == "table" and item.rooms then return "rooms" end
    if type(item) == "table" and item.bridge then return "bridge " .. item.bridge end
    if type(item) == "table" and item.name then return "model " .. item.name end
    return "-"
  end
  -- (each model's time by its parts: the reference, the drawing's art, the cache read, the
  -- chunk's load, the image)
  local parts = {}
  local function timed(name, f)
    return function(...)
      local a = clock()
      local r = { f(...) }
      local p = parts[name] or { n = 0, ms = 0 }
      parts[name] = p
      p.n, p.ms = p.n + 1, p.ms + (clock() - a) * 1000
      return unpack(r)
    end
  end
  local ready = upvalue(Scene.warmStep, "ready")
  local Buildings = ready and upvalue(ready, "Buildings")
  if Buildings then
    Buildings.reference = timed("reference", Buildings.reference)
    Buildings.art = timed("art", Buildings.art)
  end
  if Scene.modelCache then Scene.modelCache.read = timed("cache read", Scene.modelCache.read) end
  local realLoad = load
  load = timed("load chunk", realLoad)
  love.image.newImageData = timed("newImageData", love.image.newImageData)
  love.graphics.newImage = timed("newImage", love.graphics.newImage)
  if Scene.modelCache and Scene.modelCache.exists then
    local te = clock()
    local hits = 0
    for i = 1, 100 do if Scene.modelCache.exists(i % 2 == 0 and "pokemon_center.lua" or "nothing_here.lua") then hits = hits + 1 end end
    log(("100 cache exists: %.1f ms (%d hits)"):format((clock() - te) * 1000, hits))
    te = clock()
    for _ = 1, 20 do Scene.modelCache.read("pokemon_center.lua") end
    log(("20 cache reads: %.1f ms"):format((clock() - te) * 1000))
  end
  -- the relief's start: the fingerprint, the cache read, the decode and parse
  local ts = clock()
  run.start()
  local st, how = run.state()
  log(("relief start %.0f ms -> %s %s"):format((clock() - ts) * 1000, tostring(st), tostring(how)))
  local frames, total, slow8, slow16, slow33 = {}, 0, 0, 0, 0
  local kinds = {}
  local n = 0
  while n < 20000 do
    local item = queue and queue[1]
    local q0, m0, kb0 = queue and #queue or 0, Scene.modelsFromCache, collectgarbage("count")
    local f0 = clock()
    Scene.warmStep()
    if hdx._reliefPrune then hdx._reliefPrune(8) end
    run.step()
    if hdx._promptTick then hdx._promptTick(1 / 60) end
    local ms = (clock() - f0) * 1000
    n = n + 1
    total = total + ms
    local lb = label(item)
    lb = ("%s (items %d, cached models read %d, heap %+.0f KB)"):format(lb, q0 - (queue and #queue or 0),
      Scene.modelsFromCache - m0, collectgarbage("count") - kb0)
    frames[#frames + 1] = { ms = ms, label = lb }
    local kind = lb:match("^(%S+)")
    local k = kinds[kind] or { n = 0, ms = 0, max = 0 }
    kinds[kind] = k
    k.n, k.ms, k.max = k.n + 1, k.ms + ms, math.max(k.max, ms)
    if ms > 8 then slow8 = slow8 + 1 end
    if ms > 16.7 then slow16 = slow16 + 1 end
    if ms > 33 then slow33 = slow33 + 1 end
    if not (queue and queue[1]) and run.state() ~= "running" then break end
    U.wait(1)
  end
  log(("%d frames with work, %.0f ms in all; over 8 ms: %d, over 16.7 ms: %d, over 33 ms: %d"):format(
    n, total, slow8, slow16, slow33))
  for kind, k in pairs(kinds) do
    log(("  %-12s %4d frames, %7.0f ms, mean %.1f ms, max %.1f ms"):format(kind, k.n, k.ms, k.ms / k.n, k.max))
  end
  table.sort(frames, function(a, b) return a.ms > b.ms end)
  for i = 1, math.min(25, #frames) do log(("  slow %2d: %6.1f ms %s"):format(i, frames[i].ms, frames[i].label)) end
  log("models from cache", tostring(Scene.modelsFromCache), "built", tostring(Scene.modelsBuilt))
  load = realLoad
  for name, p in pairs(parts) do log(("  part %-13s %5d calls %7.0f ms"):format(name, p.n, p.ms)) end
  log(("whole run %.1f s"):format(clock() - t0))
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_hitch"
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
