-- A drawn group's shape (Battle Scene: Overworld; src/scene/relief_solve.lua's part): each cell a
-- footprint at its terrace's level or the rock between, hung from what it is drawn below - a
-- face from the cell north of it, a band from its high side, a corner from all round - falling a
-- level a tile; and a pier's planks run on into the water. Emerald 3DS's gen_voxel_relief.py
-- solve_drawn and pier_ends (by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE).

local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

return function(S)
  local Solve, Art = S.Solve, S.Art
  local C, SETS = Solve.C, Solve.SETS
  local K, KX, KY = Solve.K, Solve.KX, Solve.KY
  local LEVEL, STEP, PER_CELL = C.LEVEL, C.STEP, C.PER_CELL
  local FOOTPRINT = C.FOOTPRINT
  local FACE_SOUTH, SEA_CAPS, BOULDER = SETS.FACE_SOUTH, SETS.SEA_CAPS, SETS.BOULDER
  local tick = S.tick
  local grid2 = Solve.grid2

  --- { [lid] = lattice } of a group of maps drawn as one (a lattice: rows 0.., .n rows, .w points)
  function S.solveDrawn(name)
    if S.DRAWN_OUT[name] then return S.DRAWN_OUT[name] end
    local prep = S.drawnPrepare(name)
    local members, at, layouts, CW, CH = prep.members, prep.at, prep.layouts, prep.CW, prep.CH
    local side, flat = prep.side, prep.flat
    local stats, freeMid, faceLow = prep.stats, prep.freeMid, prep.faceLow
    local level = S.worldLevels().regions[name]
    local metatileAt = prep.metatileAt
    local cell = grid2(CW, CH)
    local function ridgeEnd(cx, cy)
      for _, dy in ipairs({ -1, 1 }) do
        if cy + dy >= 0 and cy + dy < CH and side[cy + dy][cx] ~= 0 then return true end
      end
      return false
    end
    local void = grid2(CW, CH, true)
    local thin, thinList = {}, {}
    local lfn, lfnList = {}, {}       -- level_from_neighbours
    local soil = grid2(CW, CH, false)
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local st = stats[cy][cx]
        if st ~= nil then
          local n, top, ground, counts = st[1], st[2], st[3], st[4]
          void[cy][cx] = false
          local m = metatileAt(cx, cy)
          local boulder = BOULDER[m or -1] == true
          repeat
            if SEA_CAPS[m or -1] then break end
            if boulder and ridgeEnd(cx, cy) then break end
            local f = flat[cy][cx]
            local footprint = top >= FOOTPRINT * n or ground >= FOOTPRINT * n
            if f == "bridge" or (f == "floor" and not footprint) then
              if not lfn[K(cx, cy)] then lfn[K(cx, cy)] = true; lfnList[#lfnList + 1] = K(cx, cy) end
              soil[cy][cx] = true
            elseif (f == "water" or f == "signpost") and not footprint then
              if #counts.order > 0 then
                cell[cy][cx] = level[Solve.mostCommon(counts.n, counts.order)]
              else
                if not lfn[K(cx, cy)] then lfn[K(cx, cy)] = true; lfnList[#lfnList + 1] = K(cx, cy) end
              end
              soil[cy][cx] = true
            elseif boulder or footprint then
              if #counts.order > 0 then
                cell[cy][cx] = level[Solve.mostCommon(counts.n, counts.order)]
                soil[cy][cx] = not boulder and top < FOOTPRINT * n
              elseif top >= FOOTPRINT * n then
                if not thin[K(cx, cy)] then thin[K(cx, cy)] = true; thinList[#thinList + 1] = K(cx, cy) end
              end
            end
          until true
        end
      end
    end
    -- the ledges between bands: counted across the bands, or taken from a ledge above or below
    -- (within a pass nothing found is read: the order the cells are visited in sets nothing)
    while next(thin) do
      local found, foundOrder = {}, {}
      for _, kk in ipairs(thinList) do
        if thin[kk] then
          local cx, cy = KX(kk), KY(kk)
          local got
          local acrossFound = false
          for _, dx in ipairs({ -1, 1 }) do
            local x, n = cx + dx, 0
            while x >= 0 and x < CW and side[cy][x] ~= 0 and cell[cy][x] == nil do
              n = n + side[cy][x] * dx
              x = x + dx
            end
            if x ~= cx + dx and x >= 0 and x < CW and cell[cy][x] ~= nil then
              got = cell[cy][x] - C.SIDE_RISE * n
              acrossFound = true
              break
            end
          end
          if not acrossFound then
            for _, dy in ipairs({ -1, 1 }) do
              local y = cy + dy
              if y >= 0 and y < CH and cell[y][cx] ~= nil and found[K(cx, y)] == nil then
                got = cell[y][cx]
                break
              end
            end
          end
          if got ~= nil then
            found[kk] = got
            foundOrder[#foundOrder + 1] = kk
          end
        end
      end
      if #foundOrder == 0 then break end
      for _, kk in ipairs(foundOrder) do
        cell[KY(kk)][KX(kk)] = found[kk]
        thin[kk] = nil
      end
    end
    -- a bridge, and a flat cell all in rock colours: its neighbours' commonest level
    while next(lfn) do
      local found, foundOrder = {}, {}
      for _, kk in ipairs(lfnList) do
        if lfn[kk] then
          local cx, cy = KX(kk), KY(kk)
          local got = Solve.counter()
          for _, p in ipairs({ { cx, cy - 1 }, { cx, cy + 1 }, { cx - 1, cy }, { cx + 1, cy } }) do
            local x, y = p[1], p[2]
            if x >= 0 and x < CW and y >= 0 and y < CH and cell[y][x] ~= nil and flat[y][x] ~= "water"
                and not lfn[K(x, y)] then
              got.add(cell[y][x])
            end
          end
          if #got.order > 0 then
            found[kk] = got.most()
            foundOrder[#foundOrder + 1] = kk
          end
        end
      end
      if #foundOrder == 0 then break end
      for _, kk in ipairs(foundOrder) do
        cell[KY(kk)][KX(kk)] = found[kk]
        lfn[kk] = nil
      end
    end
    -- every body of water at one level: the level most of it is at
    local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local seenWater = {}
    for cy0 = 0, CH - 1 do
      for cx0 = 0, CW - 1 do
        if flat[cy0][cx0] == "water" and not seenWater[K(cx0, cy0)] then
          local body, stack = {}, { { cx0, cy0 } }
          seenWater[K(cx0, cy0)] = true
          while #stack > 0 do
            local c = table.remove(stack)
            body[#body + 1] = c
            for _, d in ipairs(DIRS) do
              local qx, qy = c[1] + d[1], c[2] + d[2]
              if qx >= 0 and qx < CW and qy >= 0 and qy < CH and not seenWater[K(qx, qy)]
                  and (flat[qy][qx] == "water" or flat[qy][qx] == "bridge") then
                seenWater[K(qx, qy)] = true
                stack[#stack + 1] = { qx, qy }
              end
            end
          end
          local wb = {}
          for _, c in ipairs(body) do if flat[c[2]][c[1]] == "water" then wb[#wb + 1] = c end end
          local got = Solve.counter()
          for _, c in ipairs(wb) do if cell[c[2]][c[1]] ~= nil then got.add(cell[c[2]][c[1]]) end end
          if #got.order > 0 then
            local lv = got.most()
            for _, c in ipairs(wb) do
              cell[c[2]][c[1]] = lv
              soil[c[2]][c[1]] = true
            end
            -- a strip of shore walked to from nowhere else is at the water's level
            for _, c in ipairs(wb) do
              for _, d in ipairs(DIRS) do
                local qx, qy = c[1] + d[1], c[2] + d[2]
                if qx >= 0 and qx < CW and qy >= 0 and qy < CH and flat[qy][qx] == "floor" then
                  local strip, slist, stack2 = { [K(qx, qy)] = true }, { { qx, qy } }, { { qx, qy } }
                  while #stack2 > 0 and #slist <= C.SHORE_STRIP do
                    local e = table.remove(stack2)
                    for _, d2 in ipairs(DIRS) do
                      local rx, ry = e[1] + d2[1], e[2] + d2[2]
                      if rx >= 0 and rx < CW and ry >= 0 and ry < CH and not strip[K(rx, ry)]
                          and flat[ry][rx] == "floor" then
                        strip[K(rx, ry)] = true
                        slist[#slist + 1] = { rx, ry }
                        stack2[#stack2 + 1] = { rx, ry }
                      end
                    end
                  end
                  if #slist <= C.SHORE_STRIP then
                    for _, sc in ipairs(slist) do
                      cell[sc[2]][sc[1]] = lv
                      soil[sc[2]][sc[1]] = true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    -- a ridge's top between bands: a level over its foot for every band down to it
    local function rockEnd(x, cy)
      return x >= 0 and x < CW and cell[cy][x] == nil and side[cy][x] == 0 and not void[cy][x]
        and cy + 1 < CH and side[cy + 1][x] ~= 0
    end
    local function counted(x, cy, dx)
      local n = 0
      while x >= 0 and x < CW and side[cy][x] == -dx and cell[cy][x] == nil do
        n = n + 1
        x = x + dx
      end
      if n > 0 and x >= 0 and x < CW and cell[cy][x] ~= nil then return cell[cy][x] + LEVEL * n end
      if rockEnd(x, cy) then return "open" end
      return nil
    end
    for cy = CH - 1, 0, -1 do
      local cx = 0
      while cx < CW do
        if cell[cy][cx] == nil or soil[cy][cx] or side[cy][cx] ~= 0 then
          cx = cx + 1
        else
          local x0 = cx
          while cx < CW and cell[cy][cx] ~= nil and not soil[cy][cx] and side[cy][cx] == 0 do cx = cx + 1 end
          local west, east = counted(x0 - 1, cy, -1), counted(cx, cy, 1)
          if west == "open" and east == "open" then
            -- capped on both flanks: as high as the top it runs on into
            local v, ok = nil, cy + 1 < CH
            if ok then
              for x = x0, cx - 1 do
                local b = cell[cy + 1][x]
                if b == nil then ok = false; break end
                if v == nil then v = b elseif v ~= b then ok = false; break end
              end
            end
            west = ok and v or nil
            east = west
          end
          if west == "open" then west = east end
          if east == "open" then east = west end
          if west ~= nil and west == east and cx - x0 <= C.RIDGE_TOP then
            for x = x0, cx - 1 do cell[cy][x] = west end
          end
        end
      end
    end
    S.CELLS[name] = cell
    -- the rock, tile by tile
    local function tile(cx, cy)
      local m = metatileAt(cx, cy)
      if side[cy][cx] ~= 0 then return "band" end
      if FACE_SOUTH[m or -1] or freeMid[cy][cx] or flat[cy][cx] == "fall" or faceLow[K(cx, cy)] then return "face" end
      return "corner"
    end
    local crests = {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local s_ = side[cy][cx]
        if s_ ~= 0 and cell[cy][cx] == nil and not void[cy][cx] and cx + s_ >= 0 and cx + s_ < CW
            and side[cy][cx + s_] == -s_ and cell[cy][cx + s_] == nil then
          crests[K(cx, cy)] = true
        end
      end
    end
    local function hangsFrom(cx, cy)
      local t = tile(cx, cy)
      if t == "face" then return { { cx, cy - 1 } } end
      if t == "band" then
        if crests[K(cx, cy)] then return { { cx, cy - 1 } } end
        return { { cx + side[cy][cx], cy } }
      end
      local out = {}
      for dy = -1, 1 do for dx = -1, 1 do if dx ~= 0 or dy ~= 0 then out[#out + 1] = { cx + dx, cy + dy } end end end
      return out
    end
    local rock = {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        if cell[cy][cx] == nil and not void[cy][cx] then rock[#rock + 1] = { cx, cy } end
      end
    end
    local top = {}
    local function heightOf(x, y, ax, ay)
      if not (x >= 0 and x < CW and y >= 0 and y < CH) or void[y][x] then return nil end
      if cell[y][x] ~= nil then return cell[y][x] end
      local t = top[K(x, y)]
      if t == nil then return nil end
      if crests[K(x, y)] and not (ax == x - side[y][x] and ay == y) then return t end
      if ax and crests[K(ax, ay)] and ax == x and ay == y + 1 and side[y][x] ~= 0 then return t end
      return t - LEVEL
    end
    local function landing(cx, cy)
      local t_ = tile(cx, cy)
      if t_ == "corner" then
        local lo
        for _, p in ipairs(hangsFrom(cx, cy)) do
          local x, y = p[1], p[2]
          if x >= 0 and x < CW and y >= 0 and y < CH and cell[y][x] ~= nil then
            lo = lo == nil and cell[y][x] or min(lo, cell[y][x])
          end
        end
        return lo
      end
      local dx, dy
      if t_ == "face" then dx, dy = 0, 1 else dx, dy = -side[cy][cx], 0 end
      local x, y = cx + dx, cy + dy
      while x >= 0 and x < CW and y >= 0 and y < CH and not void[y][x] do
        if cell[y][x] ~= nil then return cell[y][x] end
        x, y = x + dx, y + dy
      end
      return nil
    end
    local floorOf = {}
    for _, c in ipairs(rock) do floorOf[K(c[1], c[2])] = landing(c[1], c[2]) end
    local crestList = {}
    for kk in pairs(crests) do crestList[#crestList + 1] = { KX(kk), KY(kk) } end
    table.sort(crestList, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    for _, c in ipairs(crestList) do
      local cx, cy = c[1], c[2]
      local s_, x, n = side[cy][cx], cx, 0
      while x >= 0 and x < CW and side[cy][x] == s_ and cell[cy][x] == nil do
        n = n + 1
        x = x - s_
      end
      if x >= 0 and x < CW and cell[cy][x] ~= nil then top[K(cx, cy)] = cell[cy][x] + LEVEL * n end
    end
    for _, c in ipairs(crestList) do
      local cx, cy = c[1], c[2]
      local o = K(cx + side[cy][cx], cy)
      local me = K(cx, cy)
      if top[me] ~= nil and top[o] ~= nil then
        local v = max(top[me], top[o])
        top[me], top[o] = v, v
      elseif top[o] ~= nil and crests[o] then
        top[me] = top[o]
      end
    end
    local changed = true
    while changed do
      changed = false
      for _, c in ipairs(rock) do
        local cx, cy = c[1], c[2]
        local got = {}
        for _, p in ipairs(hangsFrom(cx, cy)) do
          local v = heightOf(p[1], p[2], cx, cy)
          if v ~= nil then got[#got + 1] = v end
        end
        local s_ = side[cy][cx]
        if s_ ~= 0 and not crests[K(cx, cy)] and cx + s_ >= 0 and cx + s_ < CW and cell[cy][cx + s_] == nil
            and tile(cx + s_, cy) == "corner" then
          for _, y in ipairs({ cy - 1, cy + 1 }) do
            if y >= 0 and y < CH and side[y][cx] == s_ and top[K(cx, y)] ~= nil and not crests[K(cx, y)]
                and cell[y][cx] == nil then
              got[#got + 1] = top[K(cx, y)]
            end
          end
        end
        if #got > 0 then
          local v = got[1]
          for i = 2, #got do v = max(v, got[i]) end
          local fo = floorOf[K(cx, cy)]
          if fo ~= nil then v = max(v, fo) end
          local cur = top[K(cx, cy)]
          if cur == nil or v > cur then
            top[K(cx, cy)] = v
            changed = true
          end
        end
      end
      tick()
    end
    local kinds = {}
    for _, c in ipairs(rock) do kinds[K(c[1], c[2])] = tile(c[1], c[2]) end
    S.ROCK[name] = { top = top, kinds = kinds, kindOrder = rock, soil = soil, metatileAt = metatileAt }
    -- the lattice: footprints first
    local LW, LH = CW * PER_CELL + 1, CH * PER_CELL + 1
    local h, fixed = grid2(LW, LH), grid2(LW, LH, false)
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local lv = cell[cy][cx]
        if lv ~= nil then
          for j = cy * PER_CELL, (cy + 1) * PER_CELL do
            local hr, fr = h[j], fixed[j]
            for i = cx * PER_CELL, (cx + 1) * PER_CELL do
              if soil[cy][cx] then
                if not fr[i] or lv > hr[i] then hr[i] = lv end
                fr[i] = true
              elseif not fr[i] and (hr[i] == nil or lv > hr[i]) then
                hr[i] = lv
              end
            end
          end
        end
      end
    end
    -- each rock cell falls from what it hangs from, the edge it shares with it as that edge is
    local shapes, shapeList = {}, {}
    for _, c in ipairs(rock) do
      local cx, cy = c[1], c[2]
      local hi = top[K(cx, cy)]
      if hi ~= nil then
        local hf = hangsFrom(cx, cy)
        local rects = {}
        for _, p in ipairs(hf) do if heightOf(p[1], p[2], cx, cy) == hi then rects[#rects + 1] = p end end
        local flatOn = #rects == 0
        if flatOn then
          for _, p in ipairs(hf) do if heightOf(p[1], p[2], cx, cy) ~= nil then rects[#rects + 1] = p end end
        end
        if crests[K(cx, cy)] then rects = { { cx + side[cy][cx], cy } } end
        local t_ = tile(cx, cy)
        local below
        if t_ == "face" then below = { { cx, cy + 1 } }
        elseif t_ == "band" then below = { { cx - side[cy][cx], cy } }
        else
          below = {}
          for _, p in ipairs(hf) do
            local inR = false
            for _, q in ipairs(rects) do if q[1] == p[1] and q[2] == p[2] then inR = true end end
            if not inR then below[#below + 1] = p end
          end
        end
        local fl
        for _, p in ipairs(below) do
          local x, y = p[1], p[2]
          if x >= 0 and x < CW and y >= 0 and y < CH and cell[y][x] ~= nil and cell[y][x] <= hi then
            fl = fl == nil and cell[y][x] or min(fl, cell[y][x])
          end
        end
        fl = fl or hi - LEVEL
        local i0, j0 = cx * PER_CELL, cy * PER_CELL
        local function edge(e)
          local out = {}
          for k = 0, PER_CELL do
            if e == "N" then out[#out + 1] = { i0 + k, j0 }
            elseif e == "S" then out[#out + 1] = { i0 + k, j0 + PER_CELL }
            elseif e == "W" then out[#out + 1] = { i0, j0 + k }
            else out[#out + 1] = { i0 + PER_CELL, j0 + k } end
          end
          return out
        end
        local held
        if crests[K(cx, cy)] then
          held = {}
          for _, p in ipairs(edge(side[cy][cx] > 0 and "E" or "W")) do held[#held + 1] = { p, hi } end
        elseif flatOn then
          held = nil
        elseif t_ == "face" then
          held = {}
          for _, p in ipairs(edge("N")) do held[#held + 1] = { p } end
        elseif t_ == "band" then
          held = {}
          for _, p in ipairs(edge(side[cy][cx] > 0 and "E" or "W")) do held[#held + 1] = { p } end
        else
          held = {}
          local seen = {}
          for _, e in ipairs({ "N", "S", "W", "E" }) do
            for _, p in ipairs(edge(e)) do
              local kk = K(p[1], p[2])
              if not seen[kk] then seen[kk] = true; held[#held + 1] = { p } end
            end
          end
        end
        shapes[K(cx, cy)] = { hi, fl, rects, held }
        shapeList[#shapeList + 1] = { cx, cy }
      end
    end
    local function lay(cx, cy)
      local sh = shapes[K(cx, cy)]
      local hi, fl, rects, held = sh[1], sh[2], sh[3], sh[4]
      local moved = false
      local slope = (hi - fl) / 16.0
      local src
      if held ~= nil then
        src = {}
        for _, e in ipairs(held) do
          local p, v = e[1], e[2]
          if v == nil then v = h[p[2]][p[1]] end
          if v ~= nil and v >= fl then src[#src + 1] = { p[1] * STEP, p[2] * STEP, min(v, hi) } end
        end
        if #src == 0 then return false end
        if tile(cx, cy) == "band" then
          local mv = src[1][3]
          for i = 2, #src do mv = max(mv, src[i][3]) end
          slope = (min(hi, mv) - fl) / 16.0
        end
        slope = min(slope, 1.0)
      end
      for j = cy * PER_CELL, (cy + 1) * PER_CELL do
        local py = j * STEP
        for i = cx * PER_CELL, (cx + 1) * PER_CELL do
          if not fixed[j][i] then
            local px = i * STEP
            local v
            if held == nil then
              local d
              for _, r in ipairs(rects) do
                local x, y = r[1], r[2]
                local ax = max(x * 16 - px, 0, px - x * 16 - 16)
                local ay = max(y * 16 - py, 0, py - y * 16 - 16)
                local dd = sqrt(ax * ax + ay * ay)
                d = d == nil and dd or min(d, dd)
              end
              v = hi - (hi - fl) * min(1.0, d / 16.0)
            else
              local best
              for _, sv in ipairs(src) do
                local dx, dy = px - sv[1], py - sv[2]
                local w = sv[3] - slope * sqrt(dx * dx + dy * dy)
                best = best == nil and w or max(best, w)
              end
              v = max(fl, best)
            end
            if h[j][i] == nil or v > h[j][i] + 1e-6 then
              h[j][i] = v
              moved = true
            end
          end
        end
      end
      return moved
    end
    local order = {}
    for i, c in ipairs(shapeList) do order[i] = c end
    table.sort(order, function(a, b)
      local ha, hb = shapes[K(a[1], a[2])][1], shapes[K(b[1], b[2])][1]
      if ha ~= hb then return ha > hb end
      if a[2] ~= b[2] then return a[2] < b[2] end
      return a[1] < b[1]
    end)
    for _ = 1, 64 do
      local any = false
      for _, c in ipairs(order) do
        if lay(c[1], c[2]) then any = true end
      end
      tick()
      if not any then break end
    end
    -- each map's own level: the one most of its ground stands at
    local base = {}
    for _, lid in ipairs(members) do
      local L = layouts[lid]
      local ox, oy = at[lid][1], at[lid][2]
      local got = Solve.counter()
      for y = 0, L.h - 1 do
        for x = 0, L.w - 1 do
          if cell[oy + y][ox + x] ~= nil and soil[oy + y][ox + x] then got.add(cell[oy + y][ox + x]) end
        end
      end
      base[lid] = #got.order > 0 and got.most() or 0
    end
    for _, lid in ipairs(members) do
      local L = layouts[lid]
      local ox, oy = at[lid][1], at[lid][2]
      for j = oy * PER_CELL, (oy + L.h) * PER_CELL do
        for i = ox * PER_CELL, (ox + L.w) * PER_CELL do
          if h[j][i] == nil then h[j][i] = base[lid] + 0.0 end
        end
      end
    end
    for j = 0, LH - 1 do for i = 0, LW - 1 do if h[j][i] == nil then h[j][i] = 0.0 end end end
    -- every point of the drawing as far south as it is high
    local out = {}
    for _, lid in ipairs(members) do
      local L = layouts[lid]
      local ox, oy = at[lid][1], at[lid][2]
      local b = base[lid]
      local lat = { n = L.h * PER_CELL + 1, w = L.w * PER_CELL + 1 }
      for j = 0, L.h * PER_CELL do
        local row, src = {}, h[oy * PER_CELL + j]
        for i = 0, L.w * PER_CELL do row[i] = src[ox * PER_CELL + i] - b end
        lat[j] = row
      end
      out[lid] = lat
      if S.drawnGroup(lid, false) == name then
        S.BASE[lid] = b
        local copy = { n = lat.n, w = lat.w }
        for j = 0, lat.n - 1 do
          local r = {}
          for i = 0, lat.w - 1 do r[i] = lat[j][i] end
          copy[j] = r
        end
        S.SHIFT[lid] = copy
      end
    end
    S.DRAWN_OUT[name] = out
    return out
  end

  --- pier_ends: a pier's planks run on into the water cell at its end
  function S.pierEnds(group, lid, RL, h)
    if not S.PIER[group] then S.drawnCanvas(group) end
    local g = S.DRAWN_BY[group]
    local ox, oy = g.at[lid][1], g.at[lid][2]
    local function th(kk) return Art.hashTuple({ Solve.KX(kk), Solve.KY(kk) }, 2) end
    -- the canvas's pier cells in their set's order, this map's in theirs
    local mine = {}
    for _, kk in ipairs(Art.setOrder(S.PIER[group].seq, th)) do
      local x, y = KX(kk) - ox, KY(kk) - oy
      if x >= 0 and x < RL.w and y >= 0 and y < RL.h then mine[#mine + 1] = K(x, y) end
    end
    if #mine == 0 then return end
    local pier = {}
    for _, kk in ipairs(mine) do pier[kk] = true end
    local p = S.pairOf(RL.L)
    local shift = S.SHIFT[lid]
    for _, kk in ipairs(Art.setOrder(mine, th)) do
      local px, py = KX(kk), KY(kk)
      local lv = h[py * PER_CELL + PER_CELL / 2][px * PER_CELL + PER_CELL / 2]
      for _, dx in ipairs({ -1, 1 }) do
        local cx, cy = px + dx, py
        if not pier[K(cx, cy)] and cx >= 0 and cx < RL.w and RL.role_at(cx, cy) == "water" then
          local drawn = p.layerPixels(RL.metatile(cx, cy), 1)
          for j = 0, PER_CELL do
            for i = 0, PER_CELL do
              local x, y = i * STEP, j * STEP
              local hit = false
              for a = x - C.PIER_REACH, x + C.PIER_REACH - 1 do
                for b = y - C.PIER_REACH, y + C.PIER_REACH - 1 do
                  if a >= 0 and a < 16 and b >= 0 and b < 16 and drawn[b * 16 + a] then hit = true end
                end
              end
              if hit then
                h[cy * PER_CELL + j][cx * PER_CELL + i] = lv
                if shift then shift[cy * PER_CELL + j][cx * PER_CELL + i] = lv end
              end
            end
          end
        end
      end
    end
  end
end
