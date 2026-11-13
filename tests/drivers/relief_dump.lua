-- Driver (dev only): the relief solver (src/scene/relief_solve.lua) run in the game over Emerald's
-- own layouts, as the scene will run it (sliced through a coroutine, a few ms a frame), its
-- export written as relief.bin bytes to SHOT_DIR/relief_export.bin to `cmp` against Emerald 3DS's
-- gen_voxel_relief.py export, with the time each phase took and the longest slice.
--   RELIEF_TIES  a JSON file { group: [[a, b, d], ...] } of voxel_terraces.region_ties for Route
--                111's groups (until voxel_terraces is ported: Emerald 3DS's own, read locally)
--   RELIEF_SLICE milliseconds a frame (default 4; 0: all at once)
-- Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/relief_dump.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_relief"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local root = "mods/gen3-hd-sprites/src/scene/"
  local function mod(n) return dofile(root .. n .. ".lua") end
  local Art, Input, Solve, Roles, Relief = mod("relief_art"), mod("relief_input"), mod("relief_solve"), mod("roles"), mod("relief")
  local WorldMaps = mod("world_maps")({ Solve = Solve, Art = Art, Input = Input, Roles = Roles,
    parts = { mod("relief_drawn"), mod("relief_shape"), mod("relief_cuts"), mod("relief_world") } })
  local ties
  if env("RELIEF_TIES") then
    local f = io.open(env("RELIEF_TIES"))
    if f then
      ties = require("src.link.Json").decode(f:read("*a"))
      f:close()
    end
  end
  local clock = love.timer.getTime
  local slice = (tonumber(env("RELIEF_SLICE") or "4") or 4) / 1000
  local phases, t0, tp = {}, clock(), clock()
  local worst, sliceStart, frames, ticks = 0, clock(), 0, 0
  local co = coroutine.create(function()
    return WorldMaps.solve({
      regionTies = ties and function(g) return ties[g] end or nil,
      tick = function()
        ticks = ticks + 1
        if slice > 0 and clock() - sliceStart >= slice then coroutine.yield() end
      end,
      phase = function(name)
        local t = clock()
        phases[#phases + 1] = string.format("%s %.0f ms", name, (t - tp) * 1000)
        tp = t
      end,
    })
  end)
  local model, why
  while true do
    sliceStart = clock()
    local ok, a, b = coroutine.resume(co)
    local spent = clock() - sliceStart
    if spent > worst then worst = spent end
    frames = frames + 1
    if not ok then
      log("SOLVE ERROR:", tostring(a))
      log(debug.traceback(co))
      return
    end
    if coroutine.status(co) == "dead" then
      model, why = a, b
      break
    end
    if slice > 0 then U.wait(1) end
  end
  local total = clock() - t0
  if not model then
    log("FAIL", tostring(why))
    return
  end
  local n = 0
  for _ in pairs(model.layouts) do n = n + 1 end
  local bytes = Relief.encode(model)
  local f = io.open(dir .. "/relief_export.bin", "wb")
  if f then f:write(bytes); f:close() end
  log(string.format("relief: %d layouts, %d variants, %d bytes; %.1f s over %d frames (%d ticks), longest slice %.0f ms; %s",
    n, model.nVariants, #bytes, total, frames, ticks, worst * 1000, table.concat(phases, ", ")))
  log(string.format("heap %.0f MB", collectgarbage("count") / 1024))
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_relief"
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
