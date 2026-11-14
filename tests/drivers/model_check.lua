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
  local function colourOf(px, w, x, y)
    local o = (y * w + x) * 4
    if (px[o + 4] or 0) < 0.5 then return nil end
    return math.floor(px[o + 1] * 255 + 0.5) * 65536 + math.floor(px[o + 2] * 255 + 0.5) * 256
      + math.floor(px[o + 3] * 255 + 0.5)
  end
  -- MODEL_EXACT="x0,y0,x1,y1[,b];..." overrides the spec's exact rectangles (dev)
  local function exactOf(spec)
    local e = env("MODEL_EXACT")
    if not e then return spec.exact end
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
    local md = hd._sceneModel(name)
    if not md then
      log(("%-28s no model (%s)"):format(name, tostring(hd.stats and hd.stats().sceneBuildingError)))
    else
      local art, tex = md.art, md.tex or md.art
      -- the render textured with the model's own texture, judged against its drawing
      local texArt = { w = tex.w, h = tex.h, at = function(x, y) return colourOf(tex.px, tex.w, x, y) end }
      local mesh = { tris = md.tris }
      local refArt = { w = art.w, h = art.h, at = function(x, y) return colourOf(art.px, art.w, x, y) end }
      -- (render with the texture; compare with the drawing: the texture's own size may differ)
      local wrong, missing, extra, img = Check.ortho(mesh, setmetatable({ w = art.w, h = art.h },
        { __index = function(_, k) if k == "at" then return function(x, y)
          return x < tex.w and y < tex.h and texArt.at(x, y) or nil end end end }), exactOf(md.spec), 32)
      -- judge against the drawing (ortho compares with the art it rendered from: redo the marks)
      local W, M = img.w, img.margin
      wrong, missing, extra = 0, 0, 0
      local marks = {}
      for _, rg in ipairs(exactOf(md.spec) or { { 0, 0, art.w, art.h } }) do
        for y = rg[2], rg[4] - 1 do
          for x = rg[1], rg[3] - 1 do
            local want_ = refArt.at(x, y)
            local idx = (y + M) * W + x + M
            local got = img.color[idx]
            if want_ then
              if got == nil then missing = missing + 1; marks[idx] = 0xFF00FF
              elseif got ~= want_ then wrong = wrong + 1; marks[idx] = 0xFF0000 end
            elseif got ~= nil and not rg[5] then
              extra = extra + 1; marks[idx] = 0x00FFFF
            end
          end
        end
      end
      local bad = Check.density(mesh)
      if env("MODEL_VERBOSE") then
        local where, n = {}, 0
        for idx, c in pairs(marks) do
          n = n + 1
          if n <= 12 then where[#where + 1] = ("%s@%d,%d"):format(c == 0xFF0000 and "w" or c == 0xFF00FF and "m" or "x",
            idx % W - M, math.floor(idx / W) - M) end
        end
        if #where > 0 then log("    " .. table.concat(where, " ")) end
        for i = 1, math.min(6, #bad) do
          log(("    stretched %s along %.3f down %.3f shear %.3f"):format(tostring(bad[i][1]), bad[i][2], bad[i][3], bad[i][4]))
        end
      end
      local ok = wrong == 0 and missing == 0 and extra == 0 and #bad == 0
      if ok then pass = pass + 1 end
      log(("%-28s %s  wrong %d missing %d extra %d  stretched faces %d%s"):format(name, ok and "OK  " or "FAIL",
        wrong, missing, extra, #bad, #bad > 0 and (" (" .. tostring(bad[1][1]) .. ")") or ""))
      -- the sheet: drawing | render | differences
      local H = img.h
      local SW = W * 3
      local f = io.open(("%s/%s_ortho.ppm"):format(dir, name), "wb")
      if f then
        f:write(("P6\n%d %d\n255\n"):format(SW, H))
        local row = {}
        for y = 0, H - 1 do
          for panel = 0, 2 do
            for x = 0, W - 1 do
              local c
              local ax, ay = x - M, y - M
              if panel == 0 then
                c = ax >= 0 and ay >= 0 and ax < art.w and ay < art.h and refArt.at(ax, ay) or 0
              elseif panel == 1 then
                c = img.color[y * W + x] or 0
              else
                local g = img.color[y * W + x] or 0
                c = marks[y * W + x] or (math.floor(math.floor(g / 65536) / 3) * 65536 + math.floor(math.floor(g / 256) % 256 / 3) * 256
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
