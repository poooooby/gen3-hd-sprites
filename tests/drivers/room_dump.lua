-- Driver (dev only): the rooms (src/scene/models/interiors.lua) read in the game over the player's
-- own cartridge, in order up to ROOM, and every piece standing in each room's layout written to
-- SHOT_DIR/room_<layout>.txt in the form of the dump of Emerald 3DS's buildings.bin (one
-- "P x y ground model nverts 0 wxh" a placement, then its triangles: three points in pixels, the
-- shade, the 5-bit colour at the centroid's texel), to diff; and the time each room took.
--   ROOM  the last room read (default "mart")
-- Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/room_dump.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_rooms"
  local upto = env("ROOM") or "mart"
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
  if not (hd and hd._rooms) then log("FAIL gen3-hd-sprites exports missing"); return end
  local clock = love.timer.getTime
  if env("ROOM_CACHE") and hd._roomsJob then
    -- the rooms' job as play runs it: a slice at a time (and the longest), the cache written at
    -- its end; then read back from the cache
    local worst, n, tb = 0, 0, clock()
    local st = hd._roomsJob(0.004, "build", tonumber(env("ROOM_WATCH") or "") or nil)
    local readyAt
    while st and st.co do
      local t = clock()
      st = hd._roomsJob(0.004)
      worst, n = math.max(worst, clock() - t), n + 1
      if st.ready and not readyAt then readyAt = clock() - tb end
    end
    log(("rooms job: %d slices, longest %.1f ms, ready after %.0f ms, done after %.0f ms; %d pieces, error %s %s"):format(
      n, worst * 1000, (readyAt or 0) * 1000, (clock() - tb) * 1000, #(st.pieces or {}), tostring(st.error),
      table.concat(st.errors or {}, "; ")))
    for _, g in ipairs(st and st.gaps or {}) do log("gap " .. g) end
    local tc = clock()
    st = hd._roomsJob(nil, true)
    log(("from the cache: %.0f ms; cached %s, %d pieces"):format((clock() - tc) * 1000, tostring(st.cached),
      #(st.pieces or {})))
    return
  end
  local t0 = clock()
  local everywhere
  if env("ROOM_EVERY") and hd._roomsJob then
    -- the whole job as play runs it, to the end of its reuse in the rooms nobody modelled: the
    -- pieces stood there are dumped too (their layouts "#<number>")
    local st = hd._roomsJob(nil, "build")
    everywhere = st
  end
  local ok, rooms = xpcall(hd._rooms, debug.traceback, upto)
  if not ok or not rooms then log("FAIL rooms: " .. tostring(rooms)); return end
  log(("%d rooms read in %.0f ms"):format(#rooms, (clock() - t0) * 1000))
  -- every piece's model, and where it stands: { layout = { { x, y, ground, piece, model } } }
  local byLayout, order = {}, {}
  local function at(layout, x, y, ground, pc, md)
    if not byLayout[layout] then byLayout[layout] = {}; order[#order + 1] = layout end
    local l = byLayout[layout]
    l[#l + 1] = { x, y, ground, pc, md }
  end
  for _, r in ipairs(rooms) do
    if r.error then log(("FAIL %s: %s"):format(r.name, r.error)) end
    log(("%s (%s): %d pieces"):format(r.name, r.layout, r.pieces and #r.pieces or 0))
    for _, pc in ipairs(r.pieces or {}) do
      local okB, md = xpcall(hd._roomBuild, debug.traceback, pc)
      if not okB then
        log(("FAIL build %s: %s"):format(pc.name, tostring(md)))
      else
        if pc.placed then
          for _, p in ipairs(pc.placed) do at(p[1], p[2], p[3], p[4], pc, md) end
        else
          at(pc.layout, pc.rect[1], pc.rect[2], pc.ground[1], pc, md)
        end
        for _, p in ipairs(pc.reused_at or {}) do at(p[1], p[2], p[3], p[4] or -1, pc, md) end
        if pc.bare_at then
          local okT, twin = xpcall(hd._roomBuild, debug.traceback, pc, true)
          if okT then
            for _, p in ipairs(pc.bare_at) do at(p[1], p[2], p[3], -1, pc, twin) end
          else
            log(("FAIL bare %s: %s"):format(pc.name, tostring(twin)))
          end
        end
      end
    end
  end
  for _, pc in ipairs(everywhere and everywhere.pieces or {}) do
    local needs = false
    for _, p in ipairs(pc.reused_at or {}) do if tostring(p[1]):sub(1, 1) == "#" then needs = true end end
    for _, p in ipairs(pc.bare_at or {}) do if tostring(p[1]):sub(1, 1) == "#" then needs = true end end
    if needs then
      local okB, md = xpcall(hd._roomBuild, debug.traceback, pc)
      for _, p in ipairs(pc.reused_at or {}) do
        if okB and tostring(p[1]):sub(1, 1) == "#" then at(p[1], p[2], p[3], p[4] or -1, pc, md) end
      end
      if pc.bare_at then
        local okT, twin = xpcall(hd._roomBuild, debug.traceback, pc, true)
        for _, p in ipairs(pc.bare_at) do
          if okT and tostring(p[1]):sub(1, 1) == "#" then at(p[1], p[2], p[3], -1, pc, twin) end
        end
      end
    end
  end
  local function c5(v) return math.floor(math.floor(v * 255 + 0.5) / 8) end
  for _, layout in ipairs(order) do
    local lines = {}
    local list = byLayout[layout]
    table.sort(list, function(a, b)
      if a[2] ~= b[2] then return a[2] < b[2] end
      if a[1] ~= b[1] then return a[1] < b[1] end
      return a[4].name < b[4].name
    end)
    for _, pl in ipairs(list) do
      local pc, md = pl[4], pl[5]
      local tex = md.tex
      local tris = {}
      for _, t in ipairs(md.tris) do
        local pos = {}
        local cu, cv = 0, 0
        for k = 1, 3 do
          local p = t[k]
          pos[#pos + 1] = ("%.3f %.3f %.3f"):format(p[1], p[2], p[3])
          cu, cv = cu + p[4] / 3, cv + p[5] / 3
        end
        local function nudge(c) return math.abs(c - math.floor(c + 0.5)) < 0.01 and math.floor(c + 0.5) + 0.1 or c end
        local x, y = math.floor(nudge(cu)), math.floor(nudge(cv))
        local col = "-"
        if x >= 0 and x < tex.w and y >= 0 and y < tex.h then
          local o = (y * tex.w + x) * 4
          local px = tex.px
          col = ("%d,%d,%d,%d"):format(c5(px[o + 1]), c5(px[o + 2]), c5(px[o + 3]), px[o + 4] >= 0.5 and 1 or 0)
        end
        tris[#tris + 1] = ("%s %.2f %s %s uv=%.2f,%.2f"):format(table.concat(pos, " "), t.shade or 1, col,
          tostring(t.tag), cu, cv)
      end
      table.sort(tris)
      lines[#lines + 1] = ("P %d %d %d %s %d 0 %dx%d"):format(pl[1], pl[2], pl[3], pc.name, #tris * 3, pc.rect[3],
        pc.rect[4])
      for _, t in ipairs(tris) do lines[#lines + 1] = "  " .. t end
    end
    local f = io.open(dir .. "/room_" .. layout .. ".txt", "w")
    if f then
      f:write(table.concat(lines, "\n"), "\n")
      f:close()
      log(("wrote room_%s.txt (%d placements)"):format(layout, #list))
    else
      log("FAIL cannot write room_" .. layout)
    end
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_rooms"
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
