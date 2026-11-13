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
  local Post = mod("relief_post")
  local WorldMaps = mod("world_maps")({ Solve = Solve, Art = Art, Input = Input, Roles = Roles,
    parts = { mod("relief_drawn"), mod("relief_shape"), mod("relief_cuts"), mod("relief_world") },
    json = function(text) return (Post.json(text)) end })
  local ties
  if env("RELIEF_TIES") then
    local f = io.open(env("RELIEF_TIES"))
    if f then
      ties = (Post.json(f:read("*a")))
      f:close()
    end
  end
  local clock = love.timer.getTime
  local slice = (tonumber(env("RELIEF_SLICE") or "4") or 4) / 1000
  local phases, t0, tp = {}, clock(), clock()
  local worst, sliceStart, frames, ticks = 0, clock(), 0, 0
  -- (RELIEF_GC=pause:stepmul: the collector's pacing during the build, to compare)
  if env("RELIEF_GC") then
    local p, m = env("RELIEF_GC"):match("(%d+):(%d+)")
    collectgarbage("setpause", tonumber(p))
    collectgarbage("setstepmul", tonumber(m))
    log("gc pause " .. p .. " stepmul " .. m)
  end
  local gaps = env("RELIEF_GAPS") and {} or nil
  local lastTick, lastKb
  local co = coroutine.create(function()
    -- (RELIEF_FULL=1: the terraces too, their parts joined to the solve; no building cells, so the
    -- bytes differ from the scene's build where a wall stands in a model's corner - for timing)
    local full = env("RELIEF_FULL") ~= nil
    local fixes, order
    if full then
      local fh = io.open("mods/gen3-hd-sprites/assets/scene/relief_fixes.json", "rb")
      fixes, order = Post.json(fh and fh:read("*a") or "{}")
      if fh then fh:close() end
    end
    local function finish(model, S)
      -- (RELIEF_BIG=1: the solve state's tables over 100k entries, by path - what the collector
      -- traverses in one step)
      if env("RELIEF_BIG") and S then
        local seen, found = {}, {}
        local walk
        local tables, byPre = 0, {}
        local function visitFn(f, path, depth)
          if seen[f] or depth > 8 then return end
          seen[f] = true
          for i = 1, 200 do
            local name, v = debug.getupvalue(f, i)
            if not name then break end
            if type(v) == "table" then walk(v, path .. "^" .. name, depth + 1)
            elseif type(v) == "function" then visitFn(v, path .. "^" .. name, depth + 1) end
          end
        end
        function walk(t, path, depth)
          if seen[t] or depth > 8 then return end
          seen[t] = true
          local n = 0
          for _ in pairs(t) do n = n + 1 end
          tables = tables + 1
          local pre = path:match("^([^%.%^]*[%.%^][^%.%^]*[%.%^][^%.%^]*[%.%^]?[^%.%^]*)") or path
          byPre[pre] = (byPre[pre] or 0) + 1
          if n > 20000 then found[#found + 1] = { n, path } end
          local i = 0
          for k, v in pairs(t) do
            i = i + 1
            if i > 3000 then break end
            if type(v) == "table" then walk(v, path .. "." .. tostring(k), depth + 1)
            elseif type(v) == "function" then visitFn(v, path .. "." .. tostring(k), depth + 1) end
          end
        end
        walk(S, "S", 0)
        log("walked " .. tables .. " tables")
        local pl = {}
        for k, v in pairs(byPre) do pl[#pl + 1] = { v, k } end
        table.sort(pl, function(a, b) return a[1] > b[1] end)
        for i = 1, math.min(20, #pl) do log(string.format("tables %8d under %s", pl[i][1], pl[i][2])) end
        table.sort(found, function(a, b) return a[1] > b[1] end)
        for i = 1, math.min(30, #found) do log(string.format("big %9d %s", found[i][1], found[i][2])) end
      end
      if full and model and S and S.T then
        S.T.apply(model)
        phases[#phases + 1] = string.format("terraces %.0f ms", (clock() - tp) * 1000)
        tp = clock()
      end
      return model, S
    end
    return finish(WorldMaps.solve({
      parts = full and { mod("relief_terraces"), mod("relief_terraces_fit"), mod("relief_terraces_out") } or nil,
      fixes = fixes, fixesOrder = order, jsonNull = Post.NULL, Relief = Relief,
      regionTies = (not full and ties) and function(g) return ties[g] end or nil,
      tick = function()
        ticks = ticks + 1
        -- (RELIEF_GAPS=1: every gap between two ticks over 30 ms, where it ended and what the
        -- heap did across it - a drop is a collection finishing)
        if gaps then
          local t, kb = clock(), collectgarbage("count")
          if lastTick and t - lastTick > 0.03 then
            local info = debug.getinfo(2, "Sl")
            gaps[#gaps + 1] = { (t - lastTick) * 1000, (info and info.short_src or "?") .. ":" .. (info and info.currentline or 0),
                                (kb - lastKb) / 1024, phases[#phases] or "-" }
          end
          lastTick, lastKb = t, kb
        end
        if slice > 0 and clock() - sliceStart >= slice then
          coroutine.yield()
          if gaps then lastTick, lastKb = clock(), collectgarbage("count") end
        end
      end,
      phase = function(name)
        local t = clock()
        phases[#phases + 1] = string.format("%s %.0f ms", name, (t - tp) * 1000)
        tp = t
      end,
    }))
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
  if gaps then
    table.sort(gaps, function(a, b) return a[1] > b[1] end)
    for i = 1, math.min(40, #gaps) do
      local g = gaps[i]
      log(string.format("gap %4.0f ms  heap %+6.0f MB  at %s  (after phase %s)", g[1], g[3], g[2], g[4]))
    end
    log(#gaps .. " gaps over 30 ms")
  end
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
