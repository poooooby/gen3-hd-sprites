-- Driver (dev only): Route 110's Cycling Road (src/scene/models/bridge.lua) read in the game over
-- the player's own cartridge, every block's triangles written to SHOT_DIR/bridge.txt in the form
-- of the dump of Emerald 3DS's buildings.bin (one "P x y ground" a placement, then its triangles:
-- three points in pixels, the shade, the 5-bit colour at the centroid's texel), to diff, and the
-- time the read took.
--   BRIDGE_LAYOUT  the layout (default LAYOUT_ROUTE110)
-- Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/bridge_dump.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_bridge"
  local name = env("BRIDGE_LAYOUT") or "LAYOUT_ROUTE110"
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
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._bridgeBlocks) then log("FAIL gen3-hd-sprites exports missing"); return end
  local clock = love.timer.getTime
  local t0 = clock()
  local ok, blocks, curbHeight, br = xpcall(hd._bridgeBlocks, debug.traceback, name)
  local t1 = clock()
  if not ok or not blocks then log("FAIL bridge read: " .. tostring(blocks)); return end
  log(("%s: %d blocks, %d faces, %d ramps, read in %.0f ms"):format(name, #blocks, #br.faces, #br.ramps, (t1 - t0) * 1000))
  -- the build as play runs it: a slice at a time (and the longest), then read back from the cache
  if hd._bridgeJob then
    local worst, n, tb = 0, 0, clock()
    local st = hd._bridgeJob(name, 0.004, true, 0.02)
    while st and st.running do
      local t = clock()
      st = hd._bridgeJob(name, 0.004)
      worst, n = math.max(worst, clock() - t), n + 1
    end
    log(("sliced build: %d slices, longest %.1f ms, %.0f ms in all; done %s, %s models, error %s"):format(n, worst * 1000,
      (clock() - tb) * 1000, tostring(st and st.done), tostring(st and st.models), tostring(st and st.error)))
    for _, g in ipairs(st and st.gaps or {}) do log("gap " .. g:gsub("%c%s*", " | ")) end
    local tc = clock()
    st = hd._bridgeJob(name, nil, "cache")
    log(("from the cache: %.0f ms; cached %s, %s models, error %s"):format((clock() - tc) * 1000, tostring(st.cached),
      tostring(st.models), tostring(st.error)))
  end
  local f = io.open(dir .. "/bridge.txt", "w")
  if f then
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    log("wrote " .. dir .. "/bridge.txt (" .. #placements .. " placements)")
  else
    log("FAIL cannot write " .. dir .. "/bridge.txt")
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_bridge"
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
