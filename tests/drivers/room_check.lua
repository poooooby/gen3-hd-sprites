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
--   ROOM_PROBE  pixels "x,y;x,y": every face covering them is logged (piece, tag, depth, uv)
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
  local pass, judged = 0, 0
  for _, r in ipairs(rooms) do
    if (not want or want[r.name]) and r.pieces then
      judged = judged + 1
      if env("ROOM_VERBOSE") then
        for _, pc in ipairs(r.pieces) do
          if pc.name:find(env("ROOM_VERBOSE"), 1, true) or not pc.name:find(r.name, 1, true) then
            local pl = {}
            for _, p in ipairs(pc.placed or {}) do pl[#pl + 1] = tostring(p[1]) .. "@" .. p[2] .. "," .. p[3] end
            local ru = {}
            for _, p in ipairs(pc.reused_at or {}) do ru[#ru + 1] = tostring(p[1]) .. "@" .. tostring(p[2]) .. "," .. tostring(p[3]) end
            log(("    piece %s layout %s rect %s,%s placed %s reused %s found %s"):format(pc.name, tostring(pc.layout),
              tostring(pc.rect and pc.rect[1]), tostring(pc.rect and pc.rect[2]), table.concat(pl, " "),
              table.concat(ru, " "), tostring(pc.found)))
          end
        end
      end
      local probe
      if env("ROOM_PROBE") then
        local A = hd._roomLayout(r.layout)
        probe = { log = log }
        for x, y in env("ROOM_PROBE"):gmatch("(%d+),(%d+)") do probe[tonumber(y) * A.w * 16 + tonumber(x)] = true end
      end
      local res, why = Check.room(hd, rooms, r, log, probe)
      if not res then log(("%-24s %s"):format(r.name, why))
      else
        if res.ok then pass = pass + 1 end
        log(("%-24s %s  %d pieces  wrong %d (%.1f%% of %d covered) missing %d  stretched %d  (over %d)%s"):format(r.name,
          res.ok and "OK  " or "FAIL", res.pieces, res.wrong, 100 * res.wrong / math.max(1, res.judged), res.judged,
          res.missing, #res.stretched, res.over, r.error and ("  error " .. tostring(r.error)) or ""))
        if env("ROOM_VERBOSE") then
          local l = {}
          for k, v in pairs(res.placed) do l[#l + 1] = k .. (v > 1 and ("x" .. v) or "") end
          table.sort(l)
          log("    placed: " .. table.concat(l, " "))
        end
        if not res.ok then
          local names = {}
          for name, n in pairs(res.byPiece) do
            names[#names + 1] = ("%s w%d m%d @%d,%d-%d,%d"):format(name, n.wrong, n.missing, n.x0, n.y0, n.x1, n.y1)
          end
          table.sort(names)
          if #names > 0 then log("    " .. table.concat(names, ", ")) end
          if #res.stretched > 0 then log("    stretched: " .. table.concat(res.stretched, ", ")) end
        end
        -- the sheet: drawing | the room at 45 degrees (the floor flat where nothing stands) | marks
        Check.writePPM(("%s/room_%s.ppm"):format(dir, r.name), res.sheet)
      end
    end
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
