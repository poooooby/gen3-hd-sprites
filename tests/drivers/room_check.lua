-- Driver (dev only): the proof of each room's pieces against the room's drawing, in the game over
-- the player's own cartridge. Every piece standing in a room (src/scene/models/interiors.lua) is
-- rendered in the GBA's projection with the others, the nearer over the farther
-- (tests/model_check.lua Check.render), and judged against the room as drawn:
--   wrong    a pixel a piece covers in a colour the drawing doesn't have there;
--   missing  a pixel a piece owns (cut out of the drawing for it) that nothing covers;
--   over     (not a fault) a pixel a piece covers that another owns: a top rising over what is
--            drawn behind it, as Emerald 3DS's rooms stand.
-- Each piece's faces are checked for stretched texels too (Check.density). The rest of the room is
-- its floor, drawn flat as it is.
--   ROOM_CHECK  room names (the specs' `name`), comma separated; default every room of the game
--   SHOT_DIR    where each room_<name>.ppm sheet goes (drawing | the room at 45 degrees | marks)
-- Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/room_check.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_rooms"
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._rooms and hd._roomLayout) then log("FAIL gen3-hd-sprites exports missing"); return end
  local Check = dofile("mods/gen3-hd-sprites/tests/model_check.lua")
  local want
  for n in (env("ROOM_CHECK") or ""):gmatch("[^,]+") do want = want or {}; want[n] = true end
  local okR, rooms = xpcall(hd._rooms, debug.traceback, nil)
  if not okR or not rooms then log("FAIL rooms: " .. tostring(rooms)); return end
  local function colourOf(px, w, x, y)
    local o = (y * w + x) * 4
    if (px[o + 4] or 0) < 0.5 then return nil end
    return math.floor(px[o + 1] * 255 + 0.5) * 65536 + math.floor(px[o + 2] * 255 + 0.5) * 256
      + math.floor(px[o + 3] * 255 + 0.5)
  end
  local pass, judged = 0, 0
  for _, r in ipairs(rooms) do
    if (not want or want[r.name]) and r.pieces then
      judged = judged + 1
      local A = hd._roomLayout(r.layout)
      if not A then log(("%-24s no layout %s"):format(r.name, tostring(r.layout))); goto continue end
      local W, H = A.w * 16, A.h * 16
      local function drawn(x, y)
        if x < 0 or y < 0 or x >= W or y >= H then return nil end
        local img = A.cellImage(A.metatile(math.floor(x / 16), math.floor(y / 16)))
        return img[(y % 16) * 16 + x % 16]
      end
      -- every piece standing in this room, where it stands
      local meshes, stretched = {}, {}
      for _, pc in ipairs(r.pieces) do
        local at = {}
        if pc.placed then
          for _, p in ipairs(pc.placed) do if p[1] == r.layout then at[#at + 1] = { p[2], p[3] } end end
        elseif pc.layout == r.layout then
          at[#at + 1] = { pc.rect[1], pc.rect[2] }
        end
        for _, p in ipairs(pc.reused_at or {}) do if p[1] == r.layout then at[#at + 1] = { p[2], p[3] } end end
        if #at > 0 then
          local okB, md = xpcall(hd._roomBuild, debug.traceback, pc)
          if not okB then
            log(("  FAIL build %s: %s"):format(pc.name, tostring(md)))
          else
            local tex = md.tex
            local bad = Check.density({ tris = md.tris })
            if #bad > 0 then stretched[#stretched + 1] = ("%s (%d, %s)"):format(pc.name, #bad, tostring(bad[1][1])) end
            for _, p in ipairs(at) do
              meshes[#meshes + 1] = { tris = md.tris, ox = p[1] * 16, oy = p[2] * 16, piece = pc,
                at = function(u, v)
                  if u < 0 or v < 0 or u >= tex.w or v >= tex.h then return nil end
                  return colourOf(tex.px, tex.w, u, v)
                end }
            end
          end
        end
      end
      local color, owner = Check.render(meshes, W, H)
      -- judged: what the pieces cover, against the drawing; what they own, covered
      local wrong, missing, marks = 0, 0, {}
      local byPiece = {}
      local function note(k, what)
        local m = meshes[k]
        local name = m and m.piece.name or "?"
        byPiece[name] = byPiece[name] or { wrong = 0, missing = 0 }
        byPiece[name][what] = byPiece[name][what] + 1
      end
      -- (a pixel the covering piece doesn't own - a top rising over what is drawn behind it, at
      -- 45 degrees as in Emerald 3DS's rooms - is counted apart: over)
      local over = 0
      for idx, c in pairs(color) do
        local x, y = idx % W, math.floor(idx / W)
        if c ~= drawn(x, y) then
          local m = meshes[owner[idx]]
          local own = m and m.piece.own
          if own and not own[(y - m.oy) * 4096 + (x - m.ox)] then
            over = over + 1; marks[idx] = 0xFFC000
          else
            wrong = wrong + 1; marks[idx] = 0xFF0000; note(owner[idx], "wrong")
          end
        end
      end
      local owned = 0
      for k, m in ipairs(meshes) do
        local own = m.piece.own
        if own then
          for key in pairs(own) do
            owned = owned + 1
            local u, v = key % 4096, math.floor(key / 4096)
            local x, y = m.ox + u, m.oy + v
            if x >= 0 and y >= 0 and x < W and y < H and color[y * W + x] == nil then
              missing = missing + 1; marks[y * W + x] = 0xFF00FF; note(k, "missing")
            end
          end
        end
      end
      local ok = wrong == 0 and missing == 0 and #stretched == 0
      if ok then pass = pass + 1 end
      local covered = 0
      for _ in pairs(color) do covered = covered + 1 end
      log(("%-24s %s  %d pieces  wrong %d (%.1f%% of %d covered) missing %d  stretched %d  (over %d)%s"):format(r.name,
        ok and "OK  " or "FAIL", #meshes, wrong, 100 * wrong / math.max(1, covered), covered, missing, #stretched, over, r.error and ("  error " .. tostring(r.error)) or ""))
      if not ok then
        local names = {}
        for name, n in pairs(byPiece) do names[#names + 1] = ("%s w%d m%d"):format(name, n.wrong, n.missing) end
        table.sort(names)
        if #names > 0 then log("    " .. table.concat(names, ", ")) end
        if #stretched > 0 then log("    stretched: " .. table.concat(stretched, ", ")) end
      end
      -- the sheet: drawing | the room at 45 degrees (the floor flat where nothing stands) | marks
      local f = io.open(("%s/room_%s.ppm"):format(dir, r.name), "wb")
      if f then
        f:write(("P6\n%d %d\n255\n"):format(W * 3, H))
        local row = {}
        for y = 0, H - 1 do
          for panel = 0, 2 do
            for x = 0, W - 1 do
              local idx = y * W + x
              local c
              if panel == 0 then c = drawn(x, y) or 0
              elseif panel == 1 then c = color[idx] or drawn(x, y) or 0
              else
                local g = color[idx] or drawn(x, y) or 0
                c = marks[idx] or (math.floor(math.floor(g / 65536) / 3) * 65536 + math.floor(math.floor(g / 256) % 256 / 3) * 256
                  + math.floor(g % 256 / 3))
              end
              row[#row + 1] = string.char(math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256)
            end
          end
        end
        f:write(table.concat(row))
        f:close()
      end
    end
    ::continue::
  end
  log(("%d of %d rooms pass"):format(pass, judged))
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
