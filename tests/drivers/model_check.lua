-- Driver (dev only): the proofs of building models against their drawing (tests/model_check.lua:
-- Emerald 3DS's ortho_check and density_check), in the game over the player's own cartridge.
--   MODEL_CHECK   spec names, comma separated, or a prefix ending in '*' ("pallet_*"); default
--                 every spec of the game
--   SHOT_DIR      where each <name>_ortho.ppm sheet goes (drawing | render | differences, 3x)
-- Logs one line a spec: wrong / missing / extra pixels over its exact rectangles (spec.exact, or
-- the whole drawing) and the faces that stretch a texel. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/model_check.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_models"
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._sceneModel) then log("FAIL gen3-hd-sprites exports missing"); return end
  local Check = dofile("mods/gen3-hd-sprites/tests/model_check.lua")
  local names = {}
  local want = env("MODEL_CHECK")
  for _, n in ipairs(hd._sceneSpecNames()) do
    local ok = want == nil
    for w in (want or ""):gmatch("[^,]+") do
      if w:sub(-1) == "*" and n:sub(1, #w - 1) == w:sub(1, -2) or n == w then ok = true end
    end
    if ok then names[#names + 1] = n end
  end
  log(("%d specs"):format(#names))
  -- MODEL_EXACT="x0,y0,x1,y1[,b];..." overrides the spec's exact rectangles (dev)
  local function exactOf()
    local e = env("MODEL_EXACT")
    if not e then return nil end
    local out = {}
    for r in e:gmatch("[^;]+") do
      local t = {}
      for n in r:gmatch("[^,]+") do t[#t + 1] = tonumber(n) or (n == "b") end
      out[#out + 1] = t
    end
    return out
  end
  local pass = 0
  for _, name in ipairs(names) do
    local res = Check.building(hd, name, exactOf())
    if not res then
      log(("%-28s no model (%s)"):format(name, tostring(hd.stats and hd.stats().sceneBuildingError)))
    else
      local bad = res.stretched
      if env("MODEL_VERBOSE") then
        local where, n = {}, 0
        for idx, c in pairs(res.marks) do
          n = n + 1
          if n <= 12 then where[#where + 1] = ("%s@%d,%d"):format(c == 0xFF0000 and "w" or c == 0xFF00FF and "m" or "x",
            idx % res.W - res.M, math.floor(idx / res.W) - res.M) end
        end
        if #where > 0 then log("    " .. table.concat(where, " ")) end
        for i = 1, math.min(6, #bad) do
          log(("    stretched %s along %.3f down %.3f shear %.3f"):format(tostring(bad[i][1]), bad[i][2], bad[i][3], bad[i][4]))
        end
      end
      if res.ok then pass = pass + 1 end
      log(("%-28s %s  wrong %d missing %d extra %d  stretched faces %d%s"):format(name, res.ok and "OK  " or "FAIL",
        res.wrong, res.missing, res.extra, #bad, #bad > 0 and (" (" .. tostring(bad[1][1]) .. ")") or ""))
      Check.writePPM(("%s/%s_ortho.ppm"):format(dir, name), res.sheet)
    end
  end
  log(("%d of %d pass"):format(pass, #names))
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_models"
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
