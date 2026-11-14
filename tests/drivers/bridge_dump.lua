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
  -- a footprint as the dump of buildings.bin writes it: 16 rows of 4 hex digits, or "box"
  local function fpText(fp)
    if not fp then return "box" end
    local t = {}
    for z = 1, 16 do t[z] = ("%04x"):format(fp[z]) end
    return table.concat(t, ",")
  end
  local lines, placements = {}, {}
  for _, b in ipairs(blocks) do
    local mesh = hd._bridgeMesh(b, curbHeight)
    local tris = {}
    for _, t in ipairs(mesh.tris) do
      local pos = {}
      local cu, cv = 0, 0
      for k = 1, 3 do
        local p = t[k]
        pos[#pos + 1] = ("%.3f %.3f %.3f"):format(p[1], p[2], p[3])
        cu, cv = cu + p[4] / 3, cv + p[5] / 3
      end
      -- (a centroid on a texel's edge, nudged into the texel after it: the reference's 32-bit
      -- coordinates read either side of the edge)
      local function nudge(c) return math.abs(c - math.floor(c + 0.5)) < 0.01 and math.floor(c + 0.5) + 0.1 or c end
      local x, y = math.floor(nudge(cu)), math.floor(nudge(cv))
      local col = "-"
      if x >= 0 and x < b.art.w and y >= 0 and y < b.art.h then
        local o = (y * b.art.w + x) * 4
        local px = b.art.px
        local function c5(v) return math.floor(math.floor(v * 255 + 0.5) / 8) end
        col = ("%d,%d,%d,%d"):format(c5(px[o + 1]), c5(px[o + 2]), c5(px[o + 3]), px[o + 4] >= 0.5 and 1 or 0)
      end
      tris[#tris + 1] = ("%s %.2f %s %s uv=%.2f,%.2f"):format(table.concat(pos, " "), t.shade or 1, col,
        tostring(t.tag), cu, cv)
    end
    table.sort(tris)
    for _, p in ipairs(b.placed) do
      placements[#placements + 1] = { p[1], p[2], b.ground, tris, b }
    end
  end
  table.sort(placements, function(a, c) if a[2] ~= c[2] then return a[2] < c[2] end return a[1] < c[1] end)
  for _, pl in ipairs(placements) do
    lines[#lines + 1] = ("P %d %d %d %d"):format(pl[1], pl[2], pl[3], #pl[4] * 3)
    lines[#lines + 1] = ("F %s T %d"):format(fpText(pl[5].footprint), pl[5].top)
    for _, t in ipairs(pl[4]) do lines[#lines + 1] = "  " .. t end
  end
  local function write(file, out)
    local f = io.open(dir .. "/" .. file, "w")
    if not f then log("FAIL cannot write " .. file); return end
    f:write(table.concat(out, "\n"), "\n")
    f:close()
    log(("wrote %s (%d lines)"):format(file, #out))
  end
  write("bridge.txt", lines)
  -- the deck tables (the bridge's, Fortree's) and every model's footprints in some layouts
  for _, lname in ipairs({ "LAYOUT_ROUTE110", "LAYOUT_FORTREE_CITY" }) do
    local out = {}
    for _, d in ipairs(hd.sceneDecks(lname) or {}) do out[#out + 1] = ("D %d %d %d %d %d"):format(d[1], d[2], d[3], d[4], d[5]) end
    write("decks_" .. lname .. ".txt", out)
  end
  for lname in (env("BRIDGE_FP_LAYOUTS") or "LAYOUT_RUSTBORO_CITY,LAYOUT_FORTREE_CITY,LAYOUT_SLATEPORT_CITY"):gmatch("[^,]+") do
    local out = {}
    -- (BRIDGE_RUNS=1: the runs of hedges, fences and curbs too)
    for _, m in ipairs(hd._layoutModels(lname, env("BRIDGE_RUNS") ~= nil) or {}) do
      local fps = {}
      for j = 0, m.h - 1 do
        for i = 0, m.w - 1 do fps[#fps + 1] = fpText(m.footprints[i .. "," .. j] or nil) end
      end
      -- (and its ground metatile and patch count, as the dump of buildings.bin has them)
      out[#out + 1] = ("P %d %d %dx%d %s %s %s"):format(m.x, m.y, m.w, m.h, m.name, tostring(m.ground or "-"),
        tostring(m.patches or "-"))
      out[#out + 1] = "F " .. table.concat(fps, " ")
      -- (how its ground was chosen: each candidate's scores, the ring's counts)
      if m.plan then
        local sc, rg = {}, {}
        for _, s in ipairs(m.plan.scores or {}) do sc[#sc + 1] = ("%03X:%d/%d"):format(s[1], s[2], s[3]) end
        for g, n in pairs(m.plan.ring or {}) do rg[#rg + 1] = ("%03X:%d"):format(g, n) end
        table.sort(rg)
        out[#out + 1] = "G " .. table.concat(sc, " ") .. " | ring " .. table.concat(rg, " ")
      end
      local tl = {}
      for _, t in ipairs(m.tris or {}) do
        local pos = {}
        for k = 1, 3 do pos[k] = ("%.3f %.3f %.3f"):format(t[k][1], t[k][2], t[k][3]) end
        tl[#tl + 1] = ("  %s %.2f -"):format(table.concat(pos, " "), t.shade or 1)
      end
      table.sort(tl)
      for _, l in ipairs(tl) do out[#out + 1] = l end
    end
    write("models_" .. lname .. ".txt", out)
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
