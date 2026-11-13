-- A drawn map's cells as the export writes them (Battle Scene: Overworld; src/scene/relief_solve.lua's
-- part): its cut tiles (a cell of rock drawn over the ground behind it: the background cleared,
-- the ground found that runs on under it), every cell's own grid where it is not the shared
-- lattice's, the ground run on behind a rim, and the cliff walls. Emerald 3DS's gen_voxel_relief.py
-- _cut_mask, _lifted, cut_cells, plain_ground, _plain_tile, _plain_background, _behind, rim_cells,
-- spread and cell_shapes, with voxel_sign_mask.py's cutout_mask (by Zallax and contributors, CC
-- BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE).

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local bit = require("bit")
local band, rshift, lshift, bnot = bit.band, bit.rshift, bit.lshift, bit.bnot

return function(S)
  local Solve, Art = S.Solve, S.Art
  local C, SETS = Solve.C, Solve.SETS
  local K, KX, KY = Solve.K, Solve.KX, Solve.KY
  local LEVEL, STEP, P = C.LEVEL, C.STEP, C.PER_CELL
  local CUT_LIFT, CUT_PIXELS, SPREAD, NO_FACE, GOES_ON = C.CUT_LIFT, C.CUT_PIXELS, C.SPREAD, C.NO_FACE, C.GOES_ON
  local ROCK_ALL, ROCK_TOP, ROCK_RIM = Solve.ROCK_ALL, Solve.ROCK_TOP, Solve.ROCK_RIM
  local DIRT, WRAP_GROUPS = SETS.DIRT, SETS.WRAP_GROUPS
  local cellGrid, gridEq, gridCopy, gmax, gmin = Solve.cellGrid, Solve.gridEq, Solve.gridCopy, Solve.gmax, Solve.gmin
  local tick = S.tick

  local function rgbOf(c) return floor(c / 65536), floor(c / 256) % 256, c % 256 end
  local function dist3(a, b)
    local r1, g1, b1 = rgbOf(a)
    local r2, g2, b2 = rgbOf(b)
    return abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
  end

  -- voxel_sign_mask.cutout_mask: rows of bits, the pixels not reachable from the border through
  -- empty ones (solid: { [y * 16 + x] = true })
  local function cutoutMask(solid)
    local outside = {}
    local queue, qi = {}, 1
    for y = 0, 15 do
      for x = 0, 15 do
        if x == 0 or x == 15 or y == 0 or y == 15 then queue[#queue + 1] = y * 16 + x end
      end
    end
    while qi <= #queue do
      local p = queue[qi]
      qi = qi + 1
      if not outside[p] and not solid[p] then
        outside[p] = true
        local x, y = p % 16, floor(p / 16)
        if x + 1 < 16 then queue[#queue + 1] = p + 1 end
        if x > 0 then queue[#queue + 1] = p - 1 end
        if y + 1 < 16 then queue[#queue + 1] = p + 16 end
        if y > 0 then queue[#queue + 1] = p - 16 end
      end
    end
    local rows = {}
    for y = 0, 15 do
      local r = 0
      for x = 0, 15 do if not outside[y * 16 + x] then r = r + lshift(1, x) end end
      rows[y] = r
    end
    return rows
  end

  --- _cut_mask: rows of bits, 1 where cell (x, y) draws the ground behind its rock; nil where
  --- nothing beside it is flat ground. rockCells: a set of keys.
  local function cutMask(art, RL, x, y, rockCells)
    local ground, any = {}, false
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < RL.w and ny >= 0 and ny < RL.h and not rockCells[K(nx, ny)] then
          local img = art.cellImage(art.metatile(nx, ny))
          for k = 0, 255 do
            local c = img[k]
            if not ROCK_ALL[c] then ground[c] = true; any = true end
          end
        end
      end
    end
    if not any then return nil end
    local img = art.cellImage(art.metatile(x, y))
    local opaque = {}
    for k = 0, 255 do if not ground[img[k]] then opaque[k] = true end end
    local rows = cutoutMask(opaque)
    local out = {}
    for j = 0, 15 do out[j] = band(bnot(rows[j]), 0xFFFF) end
    return out
  end
  S.cutMask = cutMask

  local function anyBits(mask)
    for j = 0, 15 do if mask[j] ~= 0 then return true end end
    return false
  end
  local function bitOf(mask, i, j) return band(rshift(mask[j], i), 1) ~= 0 end

  --- _lifted: how many pixels of the background the lattice lifts off its foot, and the foot
  local function lifted(g, mask)
    local foot = gmin(g)
    local n = 0
    for j = 0, 15 do
      for i = 0, 15 do
        if bitOf(mask, i, j) then
          local fx, fy = (i + 0.5) / STEP, (j + 0.5) / STEP
          local a, b = min(floor(fx), P - 1), min(floor(fy), P - 1)
          local tx, ty = fx - a, fy - b
          local v = ((g[b][a] * (1 - tx) + g[b][a + 1] * tx) * (1 - ty)
                     + (g[b + 1][a] * (1 - tx) + g[b + 1][a + 1] * tx) * ty)
          if v - foot > CUT_LIFT then n = n + 1 end
        end
      end
    end
    return n, foot
  end

  local function rockKeys(group, lid)
    local g = S.DRAWN_BY[group]
    local ox, oy = g.at[lid][1], g.at[lid][2]
    local rock, list = {}, {}
    for _, c in ipairs(S.ROCK[group].kindOrder) do
      local k = K(c[1] - ox, c[2] - oy)
      rock[k] = true
      list[#list + 1] = { c[1] - ox, c[2] - oy }
    end
    return rock, list, ox, oy
  end

  -- ── plain ground ─────────────────────────────────────────────────────────────
  local plainMemo = setmetatable({}, { __mode = "k" })
  local function main(art, m)
    local known = plainMemo[art]
    if not known then known = {}; plainMemo[art] = known end
    local hit = known[m]
    if hit then return hit[1], hit[2], hit[3] end
    local img = art.cellImage(m)
    local px = {}
    for k = 0, 255 do px[k + 1] = img[k] end
    local c = Art.commonest(px, Art.hashRGB)
    local count, foreign = 0, 0
    for _, p in ipairs(px) do
      if p == c then count = count + 1 end
      if dist3(p, c) > 150 then foreign = foreign + 1 end
    end
    known[m] = { c, count, foreign }
    tick()      -- (a new tile's commonest colour costs a set's order: the first scan pays for many)
    return c, count, foreign
  end
  local SIDE_PIXELS = {
    N = function(i, j) return j < 6 end, S = function(i, j) return j >= 10 end,
    E = function(i, j) return i >= 10 end, W = function(i, j) return i < 6 end,
  }

  --- plain_ground(art, layout, content, x, y, side, kind, half)
  local function plainGround(art, RL, content, x, y, side, kind, half)
    local m0 = art.metatile(x, y)
    local forced = kind ~= nil
    if not forced then
      if side == nil then
        kind = main(art, m0)
      else
        local img = art.cellImage(m0)
        local part = {}
        local f = SIDE_PIXELS[side]
        for j = 0, 15 do for i = 0, 15 do if f(i, j) then part[#part + 1] = img[j * 16 + i] end end end
        kind = Art.commonest(part, Art.hashRGB)
      end
    end
    local best, bk1, bk2, bk3
    for dy = -24, 24 do
      for dx = -24, 24 do
        local cx, cy = x + dx, y + dy
        if not content[K(cx, cy)] and cx >= 0 and cx < RL.w and cy >= 0 and cy < RL.h then
          local m = art.metatile(cx, cy)
          local c, count, foreign = main(art, m)
          if c == kind and not (half and 2 * count < 256) then
            local k1, k2, k3 = foreign, -count, abs(dx) + abs(dy)
            if best == nil or k1 < bk1 or (k1 == bk1 and (k2 < bk2 or (k2 == bk2 and k3 < bk3))) then
              best, bk1, bk2, bk3 = m, k1, k2, k3
            end
          end
        end
      end
    end
    if best ~= nil then return best end
    if forced then return nil end
    return art.metatile(x, y)
  end
  S.plainGround = plainGround

  local plainTileMemo = setmetatable({}, { __mode = "k" })
  local function plainTile(art, m)
    local known = plainTileMemo[art]
    if not known then known = {}; plainTileMemo[art] = known end
    if known[m] == nil then
      local img = art.cellImage(m)
      local n = 0
      for k = 0, 255 do if ROCK_ALL[img[k]] then n = n + 1 end end
      known[m] = n < floor(256 / 10)
    end
    return known[m]
  end

  function S.plainBackground(art, m, mask, ground)
    local img = art.cellImage(m)
    local gimg = art.cellImage(ground)
    local gp = {}
    for k = 0, 255 do gp[k + 1] = gimg[k] end
    local gc = Art.commonest(gp, Art.hashRGB)
    local bg = {}
    for j = 0, 15 do for i = 0, 15 do if bitOf(mask, i, j) then bg[#bg + 1] = img[j * 16 + i] end end end
    if #bg < 8 then return false end
    local near = 0
    for _, p in ipairs(bg) do if dist3(p, gc) <= 150 then near = near + 1 end end
    return near >= 0.9 * #bg
  end

  --- _behind: the ground a cut tile is drawn over, as a metatile
  local function behind(art, RL, x, y, rock, mask, half, content)
    content = content or rock
    if mask ~= nil then
      local img = art.cellImage(art.metatile(x, y))
      local bg = {}
      for j = 0, 15 do for i = 0, 15 do if bitOf(mask, i, j) then bg[#bg + 1] = img[j * 16 + i] end end end
      if #bg >= 8 then
        local kind = Art.commonest(bg, Art.hashRGB)
        for _, t in ipairs({ { 0, -1, "S" }, { -1, 0, "E" }, { 1, 0, "W" }, { 0, 0, nil }, { 0, 1, nil } }) do
          local dx, dy, side = t[1], t[2], t[3]
          local nx, ny = x + dx, y + dy
          if (nx >= 0 and nx < RL.w and ny >= 0 and ny < RL.h and not rock[K(nx, ny)]) or (dx == 0 and dy == 0) then
            local m = plainGround(art, RL, content, nx, ny, side, kind, half)
            if m ~= nil then return m end
          end
        end
      end
    end
    for _, t in ipairs({ { 0, -1, "S" }, { -1, 0, "E" }, { 1, 0, "W" }, { 0, 1, nil } }) do
      local nx, ny = x + t[1], y + t[2]
      if nx >= 0 and nx < RL.w and ny >= 0 and ny < RL.h and not rock[K(nx, ny)] then
        return plainGround(art, RL, rock, nx, ny, t[3], nil, half)
      end
    end
    return nil
  end
  S.behind = behind

  --- cut_cells: { { x, y, metatile, mask, foot, ground behind } } of a drawn layout's cut cells
  function S.cutCells(lid, RL, h)
    local group = S.drawnGroup(lid)
    if group == nil or not S.ROCK[group] then return {} end
    local rock, rockList = rockKeys(group, lid)
    local art = S.layoutArt(lid)
    local out = {}
    local ledges = S.ledgeCells(RL)
    local cand = {}
    for _, c in ipairs(rockList) do
      if not ledges[K(c[1], c[2])] then cand[#cand + 1] = c end
    end
    table.sort(cand, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    for _, c in ipairs(cand) do
      local x, y = c[1], c[2]
      tick()
      if x >= 0 and x < RL.w and y >= 0 and y < RL.h then
        local mask = cutMask(art, RL, x, y, rock)
        if mask ~= nil and anyBits(mask) then
          local n, foot = lifted(cellGrid(h, x, y), mask)
          if n >= CUT_PIXELS then
            out[#out + 1] = { x, y, art.metatile(x, y), mask, foot, behind(art, RL, x, y, rock, mask) }
          end
        end
      end
    end
    tick()
    return out
  end

  --- rim_cells: ({ [key] = grid }, { { x, y, foot, ground } } sorted)
  local function rimCells(lid, RL, h, cut, base)
    local group = S.drawnGroup(lid)
    if group == nil or not S.ROCK[group] then return {}, {} end
    local rockInfo = S.ROCK[group]
    local rock, rockList, ox, oy = rockKeys(group, lid)
    local kinds, soil = rockInfo.kinds, rockInfo.soil
    local levels = S.CELLS[group]
    local W, Hh = RL.w, RL.h
    local content, contentList = {}, {}
    for _, c in ipairs(rockList) do
      local k = K(c[1], c[2])
      if not content[k] then content[k] = true; contentList[#contentList + 1] = c end
    end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if levels[oy + y][ox + x] ~= nil and not soil[oy + y][ox + x] and not content[K(x, y)] then
          content[K(x, y)] = true
          contentList[#contentList + 1] = { x, y }
        end
      end
    end
    local art = S.layoutArt(lid)
    local taken, cutBehind = {}, {}
    for _, c in ipairs(cut) do
      taken[K(c[1], c[2])] = true
      if c[6] ~= nil then cutBehind[K(c[1], c[2])] = c[6] end
    end
    local ledges = S.ledgeCells(RL)
    local grids, fills, fillOrder = {}, {}, {}
    local rockH = base or h
    local function level(x, y)
      local g = cellGrid(rockH, x, y)
      local corner = kinds[K(ox + x, oy + y)] == "corner"
      for j = corner and P - 1 or 0, 0, -1 do
        for i = 0, P do g[j][i] = max(g[j][i], g[j + 1][i]) end
      end
      if not gridEq(g, cellGrid(h, x, y)) then grids[K(x, y)] = g end
    end
    local sorted_ = {}
    for i, c in ipairs(contentList) do sorted_[i] = c end
    table.sort(sorted_, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    for n_, c in ipairs(sorted_) do
      local x, y = c[1], c[2]
      if n_ % 16 == 0 then tick() end
      if x >= 0 and x < W and y >= 1 and y < Hh and not content[K(x, y - 1)] then
        local g = cellGrid(rockH, x, y)
        local bh = cellGrid(h, x, y - 1)
        local foot = gmax(bh)
        if not (gmin(bh) < foot - 0.5) then
          local below = y + 1 < Hh and cellGrid(rockH, x, y + 1) or g
          local top = max(gmax(g), gmax(below))
          if WRAP_GROUPS[group] then
            local lo, hi = math.huge, -math.huge
            for j = 1, P - 1 do for i = 0, P do lo, hi = min(lo, g[j][i]), max(hi, g[j][i]) end end
            if hi - lo <= 1.0 then top = hi end
          end
          if not (top <= foot + 0.5) then
            level(x, y)
            if grids[K(x, y)] then
              local ground
              if ledges[K(x, y)] then
                ground = plainGround(art, RL, content, x, y, "N")
              else
                ground = cutBehind[K(x, y)]
                if ground == nil or ground == 0 then ground = plainGround(art, RL, content, x, y - 1, "S") end
              end
              for k = 0, ceil((top - foot) / LEVEL) - 1 do
                local fx, fy = x, y + k
                if not (fy >= 0 and fy < Hh) then break end
                if WRAP_GROUPS[group] and k > 0 then
                  local prev = cellGrid(rockH, x, y + k - 1)
                  local lo = math.huge
                  for j = 1, P do for i = 0, P do lo = min(lo, prev[j][i]) end end
                  if lo > foot + 0.5 then break end
                end
                local fk = K(fx, fy)
                if not taken[fk] then
                  local cur = fills[fk]
                  if cur == nil or foot < cur[1] then
                    if cur == nil then fillOrder[#fillOrder + 1] = { fx, fy, fk } end
                    fills[fk] = { foot, ground }
                  end
                end
              end
            end
          end
        end
      end
    end
    table.sort(fillOrder, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    local list = {}
    for _, f in ipairs(fillOrder) do list[#list + 1] = { f[1], f[2], fills[f[3]][1], fills[f[3]][2] } end
    return grids, list
  end

  --- spread: the lattice with every fall of the rock spread evenly where it must
  local function spread(h, content, W, Hh)
    local o = { n = h.n, w = h.w }
    for j = 0, h.n - 1 do
      local r = {}
      for i = 0, h.w - 1 do r[i] = h[j][i] end
      o[j] = r
    end
    h = o
    local function rock(a, b) return content[K(floor(a / P), floor(b / P))] end
    local function even(points)
      local vals = {}
      for k, p in ipairs(points) do vals[k] = h[p[2]][p[1]] end
      local steps = {}
      for k = 1, #vals - 1 do steps[k] = vals[k + 1] - vals[k] end
      if #steps == 0 then return end
      local m = 0
      for _, d in ipairs(steps) do m = max(m, abs(d)) end
      if m <= STEP + 0.01 then return end
      local n = #steps
      if abs(vals[#vals] - vals[1]) / n > STEP * SPREAD + 0.01 then return end
      for k = 2, #points - 1 do
        local p = points[k]
        h[p[2]][p[1]] = vals[1] + (vals[#vals] - vals[1]) * (k - 1) / n
      end
    end
    for i = 1, W * P - 1 do
      local run = {}
      if i % 16 == 0 then tick() end
      for j = 0, Hh * P - 1 do
        local inside = (rock(i - 1, j) or rock(i, j)) and 0 < j and j < Hh * P
        local fall = h[j + 1][i] < h[j][i] - 0.01
        if inside and fall then
          if #run == 0 then run[1] = { i, j } end
          run[#run + 1] = { i, j + 1 }
        else
          if #run > 2 then even(run) end
          run = {}
        end
      end
      if #run > 2 then even(run) end
    end
    for j = 1, Hh * P - 1 do
      if j % 16 == 0 then tick() end
      for _, sign in ipairs({ 1, -1 }) do
        local run = {}
        for i = 0, W * P - 1 do
          local inside = (rock(i, j - 1) or rock(i, j)) and 0 < i and i < W * P
          local d = (h[j][i + 1] - h[j][i]) * sign
          if inside and d < -0.01 then
            if #run == 0 then run[1] = { i, j } end
            run[#run + 1] = { i + 1, j }
          else
            if #run > 2 then even(run) end
            run = {}
          end
        end
        if #run > 2 then even(run) end
      end
    end
    return h
  end

  --- cell_shapes: ({ [key] = grid }, fills { { x, y, foot, ground[, flag] } }, walls { [key] =
  --- { face, sides } }, wallOrder)
  function S.cellShapes(lid, RL, h, cut)
    local group = S.drawnGroup(lid)
    if group == nil or not S.ROCK[group] then
      local grids, fills = rimCells(lid, RL, h, cut)
      return grids, fills, {}, {}
    end
    local rockInfo = S.ROCK[group]
    local _, rockList, ox, oy = rockKeys(group, lid)
    local kinds, soil = rockInfo.kinds, rockInfo.soil
    local levels = S.CELLS[group]
    local W, Hh = RL.w, RL.h
    local content, contentList = {}, {}
    for _, c in ipairs(rockList) do
      if c[1] >= 0 and c[1] < W and c[2] >= 0 and c[2] < Hh and not content[K(c[1], c[2])] then
        content[K(c[1], c[2])] = true
        contentList[#contentList + 1] = c
      end
    end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if levels[oy + y][ox + x] ~= nil and not soil[oy + y][ox + x] and not content[K(x, y)] then
          content[K(x, y)] = true
          contentList[#contentList + 1] = { x, y }
        end
      end
    end
    local sortedContent = {}
    for i, c in ipairs(contentList) do sortedContent[i] = c end
    table.sort(sortedContent, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    local rockH = spread(h, content, W, Hh)
    local grids, fills = rimCells(lid, RL, h, cut, rockH)
    tick()
    for _, c in ipairs(contentList) do
      local k = K(c[1], c[2])
      if not grids[k] then
        local rg = cellGrid(rockH, c[1], c[2])
        if not gridEq(rg, cellGrid(h, c[1], c[2])) then grids[k] = rg end
      end
    end
    local art = S.layoutArt(lid)
    local keepOut = {}
    for k in pairs(S.ledgeCells(RL)) do keepOut[k] = true end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if DIRT[art.metatile(x, y)] or RL.behaviour(x, y) == S.BERRY then keepOut[K(x, y)] = true end
      end
    end
    local rockCells = {}
    for k in pairs(content) do if not keepOut[k] then rockCells[k] = true end end
    local function rockPoint(cx, cy, i, j)
      if not keepOut[K(cx, cy)] then return true end
      local X, Y = cx * P + i, cy * P + j
      local xs = { floor((X - 1) / P), floor(X / P) }
      local ys = { floor((Y - 1) / P), floor(Y / P) }
      for _, a in ipairs(xs) do
        for _, b in ipairs(ys) do
          if rockCells[K(a, b)] then return true end
        end
      end
      return false
    end
    local function grid(cx, cy) return grids[K(cx, cy)] or cellGrid(h, cx, cy) end
    local function inside(cx, cy) return cx >= 0 and cx < W and cy >= 0 and cy < Hh end
    -- the rock to its edge in its own shape, beside lower ground
    tick()
    for _, c in ipairs(sortedContent) do
      local g = gridCopy(grid(c[1], c[2]))
      for _, t in ipairs({ { -1, 0, 1, 2 }, { 1, P, P - 1, P - 2 } }) do
        local dx, e, a, b = t[1], t[2], t[3], t[4]
        local nx, ny = c[1] + dx, c[2]
        if inside(nx, ny) and not content[K(nx, ny)] then
          for j = 0, P do
            local v = min(g[j][a], 2 * g[j][a] - g[j][b])
            if v >= g[j][e] + STEP then g[j][e] = v end
          end
        end
      end
      if not gridEq(g, grid(c[1], c[2])) then grids[K(c[1], c[2])] = g end
    end
    -- a cut tile's clear background is no rock
    local masks, maskOrder = {}, {}
    for _, c in ipairs(cut) do
      local k = K(c[1], c[2])
      if masks[k] == nil then maskOrder[#maskOrder + 1] = { c[1], c[2], k } end
      masks[k] = c[4]
    end
    local function clearQuad(mask, a, b)
      for j = b * STEP, b * STEP + STEP - 1 do
        for i = a * STEP, a * STEP + STEP - 1 do
          if not bitOf(mask, i, j) then return false end
        end
      end
      return true
    end
    for _, mo in ipairs(maskOrder) do
      local cx, cy, mask = mo[1], mo[2], masks[mo[3]]
      local g = gridCopy(grid(cx, cy))
      for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
        local dx, dy = d[1], d[2]
        local nx, ny = cx + dx, cy + dy
        if inside(nx, ny) and not content[K(nx, ny)] then
          local o = grid(nx, ny)
          for k = 0, P do
            local i, j, oi, oj
            if dx ~= 0 then
              i, j = (dx < 0 and 0 or P), k
              oi, oj = (dx < 0 and P or 0), k
            else
              i, j, oi, oj = k, P, k, 0
            end
            local all = true
            for _, a in ipairs({ i - 1, i }) do
              for _, b in ipairs({ j - 1, j }) do
                if a >= 0 and a < P and b >= 0 and b < P and not clearQuad(mask, a, b) then all = false end
              end
            end
            if all then g[j][i] = min(g[j][i], o[oj][oi]) end
          end
        end
      end
      if not gridEq(g, grid(cx, cy)) then grids[K(cx, cy)] = g end
    end
    -- the ground level to its edge
    for y = 0, Hh - 1 do
      tick()
      for x = 0, W - 1 do
        if not content[K(x, y)] then
          local g = gridCopy(grid(x, y))
          local lo, hi = math.huge, -math.huge
          for j = 1, P - 1 do for i = 1, P - 1 do lo, hi = min(lo, g[j][i]), max(hi, g[j][i]) end end
          if not (hi - lo > 0.5) then
            for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
              local dx, dy = d[1], d[2]
              local nx, ny = x + dx, y + dy
              if inside(nx, ny) and content[K(nx, ny)] then
                for k = 0, P do
                  if dx == -1 then g[k][0] = g[k][1]
                  elseif dx == 1 then g[k][P] = g[k][P - 1]
                  elseif dy == -1 then g[0][k] = g[1][k]
                  else g[P][k] = g[P - 1][k] end
                end
              end
            end
            if not gridEq(g, grid(x, y)) then grids[K(x, y)] = g end
          end
        end
      end
    end
    local function drawn(cx, cy, a, b)
      local m = masks[K(cx, cy)]
      return m == nil or not clearQuad(m, a, b)
    end
    local function seam(cx, cy, i, j)
      local X, Y = cx * P + i, cy * P + j
      return X == 0 or X == W * P or Y == 0 or Y == Hh * P
    end
    local T = STEP * SPREAD
    local function far(a, b) return abs(a - b) > LEVEL + 0.01 end
    local function follow(cx, cy)
      local g = gridCopy(grid(cx, cy))
      for j = 0, P do
        for _, en in ipairs({ { 0, 1 }, { P, P - 1 } }) do
          local e, n = en[1], en[2]
          if not seam(cx, cy, e, j) and rockPoint(cx, cy, e, j) and drawn(cx, cy, min(e, n), min(j, P - 1))
              and far(g[j][e], g[j][n]) then
            g[j][e] = min(max(g[j][e], g[j][n] - T), g[j][n] + T)
          end
        end
      end
      for i = 0, P do
        if not seam(cx, cy, i, 0) and rockPoint(cx, cy, i, 0) and drawn(cx, cy, min(i, P - 1), 0) and far(g[0][i], g[1][i]) then
          g[0][i] = min(max(g[0][i], g[1][i]), g[1][i] + T)
        end
        if not seam(cx, cy, i, P) and rockPoint(cx, cy, i, P) and drawn(cx, cy, min(i, P - 1), P - 1)
            and far(g[P][i], g[P - 1][i]) then
          g[P][i] = min(max(g[P][i], g[P - 1][i] - T), g[P - 1][i])
        end
      end
      if not gridEq(g, grid(cx, cy)) then grids[K(cx, cy)] = g end
    end
    local function settle(cx, cy)
      local g = gridCopy(grid(cx, cy))
      local function free(p) return not seam(cx, cy, p[1], p[2]) and rockPoint(cx, cy, p[1], p[2]) end
      local moved = true
      while moved do
        moved = false
        for b_ = 0, P - 1 do
          for a_ = 0, P - 1 do
            if drawn(cx, cy, a_, b_) then
              for _, t in ipairs({ { { a_, b_ }, { a_ + 1, b_ }, "u" }, { { a_, b_ + 1 }, { a_ + 1, b_ + 1 }, "u" },
                                   { { a_, b_ }, { a_, b_ + 1 }, "v" }, { { a_ + 1, b_ }, { a_ + 1, b_ + 1 }, "v" } }) do
                local p0, p1, d = t[1], t[2], t[3]
                local h0, h1 = g[p0[2]][p0[1]], g[p1[2]][p1[1]]
                if d == "u" then
                  if h1 < h0 - T - 0.01 and free(p1) then
                    g[p1[2]][p1[1]] = h0 - T
                    moved = true
                  elseif h0 < h1 - T - 0.01 and free(p0) then
                    g[p0[2]][p0[1]] = h1 - T
                    moved = true
                  end
                else
                  if h1 > h0 + 0.01 and free(p0) then
                    g[p0[2]][p0[1]] = h1
                    moved = true
                  elseif h1 < h0 - T - 0.01 and free(p1) then
                    g[p1[2]][p1[1]] = h0 - T
                    moved = true
                  end
                end
              end
            end
          end
        end
      end
      if not gridEq(g, grid(cx, cy)) then
        grids[K(cx, cy)] = g
        return true
      end
      return false
    end
    local shared, sharedOrder = {}, {}
    for _, c in ipairs(contentList) do
      for j = 0, P do
        for _, i in ipairs({ 0, P }) do
          local key = (c[1] * P + i) * 1000000 + c[2] * 1000 + j
          local l = shared[key]
          if not l then l = {}; shared[key] = l; sharedOrder[#sharedOrder + 1] = key end
          l[#l + 1] = { c[1], c[2], i, j }
        end
      end
    end
    for n_, c in ipairs(sortedContent) do
      follow(c[1], c[2])
      if n_ % 64 == 0 then tick() end
    end
    -- a top's back is the edge it shares with the rock north of it
    for _, c in ipairs(sortedContent) do
      local cx, cy = c[1], c[2]
      local sx, sy = cx, cy + 1
      if content[K(sx, sy)] and not keepOut[K(cx, cy)] and not keepOut[K(sx, sy)] then
        local topRow = grid(sx, sy)[0]
        local g = gridCopy(grid(cx, cy))
        local lo, hi = math.huge, -math.huge
        for j = 1, P - 1 do for i = 0, P do lo, hi = min(lo, g[j][i]), max(hi, g[j][i]) end end
        local terrace = WRAP_GROUPS[group] and hi - lo <= 0.5 and not kinds[K(ox + cx, oy + cy)]
          and not kinds[K(ox + sx, oy + sy)]
        local mt = -math.huge
        for i = 0, P do mt = max(mt, topRow[i]) end
        local nTop = 0
        for i = 0, P do if topRow[i] >= mt - 0.5 then nTop = nTop + 1 end end
        if not (nTop < 3 and not terrace) then
          local rise = {}
          local mr = -math.huge
          for i = 0, P do rise[i] = g[P][i] - g[P - 1][i]; mr = max(mr, rise[i]) end
          if not (mr <= STEP + 0.01) then
            for i = 0, P do
              if rise[i] > 0.01 and not seam(cx, cy, i, P) then g[P][i] = g[P - 1][i] end
            end
            if not gridEq(g, grid(cx, cy)) then grids[K(cx, cy)] = g end
          end
        end
      end
    end
    for _ = 1, 64 do
      local changed = false
      for n_, c in ipairs(sortedContent) do
        if settle(c[1], c[2]) then changed = true end
        if n_ % 32 == 0 then tick() end
      end
      for _, key in ipairs(sharedOrder) do
        local users = shared[key]
        if #users >= 2 then
          local top, low = -math.huge, math.huge
          for _, u in ipairs(users) do
            local v = grid(u[1], u[2])[u[4]][u[3]]
            top, low = max(top, v), min(low, v)
          end
          if not (top - low > STEP + 0.01) then
            for _, u in ipairs(users) do
              if grid(u[1], u[2])[u[4]][u[3]] < top then
                local g = gridCopy(grid(u[1], u[2]))
                g[u[4]][u[3]] = top
                grids[K(u[1], u[2])] = g
                changed = true
              end
            end
          end
        end
      end
      tick()
      if not changed then break end
    end
    -- a flank is as steep as it is drawn
    local FLANK = 40
    local bgmask = {}
    for _, c in ipairs(contentList) do
      local k = K(c[1], c[2])
      local m = masks[k]
      if m == nil then m = cutMask(art, RL, c[1], c[2], content) end
      bgmask[k] = m or false
    end
    local plainCache, pixCache = {}, {}
    local groundCache, crossedCache = {}, {}
    local function plainOf(cx, cy)
      local k = K(cx, cy)
      local v = plainCache[k]
      if v == nil then
        v = gmax(grid(cx, cy)) <= 0.5
        plainCache[k] = v
      end
      return v
    end
    local function isGround(X, Y)
      local key = K(X, Y)
      local v = groundCache[key]
      if v ~= nil then return v end
      local cx, cy = floor(X / 16), floor(Y / 16)
      if not inside(cx, cy) or Y < 0 or X < 0 then
        v = false
      elseif content[K(cx, cy)] then
        local m = bgmask[K(cx, cy)]
        v = m and bitOf(m, X % 16, Y % 16) or false
      else
        v = plainOf(cx, cy)
      end
      groundCache[key] = v
      return v
    end
    local function isLight(X, Y)
      local cx, cy = floor(X / 16), floor(Y / 16)
      local k = K(cx, cy)
      local img = pixCache[k]
      if not img then
        img = art.cellImage(art.metatile(cx, cy))
        pixCache[k] = img
      end
      local c = img[(Y % 16) * 16 + X % 16]
      return ROCK_TOP[c] or ROCK_RIM[c] or false
    end
    local groundRows, besideRows = {}, {}
    local NW = W * 16
    local function groundRow(Y)
      local row = groundRows[Y]
      if row then return row end
      row = {}
      local cy = floor(Y / 16)
      for cx = 0, W - 1 do
        local base_ = cx * 16
        if Y < 0 or not inside(cx, cy) then
          for x = 0, 15 do row[base_ + x] = false end
        elseif content[K(cx, cy)] then
          local m = bgmask[K(cx, cy)]
          local bits = m and m[Y % 16] or 0
          for x = 0, 15 do row[base_ + x] = band(rshift(bits, x), 1) ~= 0 end
        else
          local v = plainOf(cx, cy)
          for x = 0, 15 do row[base_ + x] = v end
        end
      end
      groundRows[Y] = row
      return row
    end
    local function besideRow(Y)
      local near = besideRows[Y]
      if near then return near[1], near[2] end
      local rows = { groundRow(Y), groundRow(Y - 2), groundRow(Y + 2), groundRow(Y - 5), groundRow(Y + 5) }
      local west, east = {}, {}
      local last = -1
      for x = 0, NW - 1 do
        local all = true
        for _, r in ipairs(rows) do if not r[x] then all = false; break end end
        if all then last = x end
        west[x] = last
      end
      last = NW
      for x = NW - 1, 0, -1 do
        if west[x] == x then last = x end
        east[x] = last
      end
      besideRows[Y] = { west, east }
      return west, east
    end
    local function crossed(X, Y)
      local key = K(X, Y)
      local v = crossedCache[key]
      if v ~= nil then return v or nil end
      local best
      local west, east = besideRow(Y)
      for _, sign in ipairs({ -1, 1 }) do
        local xg
        if sign < 0 then
          if X >= 1 then
            local w = west[min(X - 1, NW - 1)]
            if 0 <= w and w >= X - 1 - FLANK then xg = w end
          end
        elseif X < NW and east[X] < NW and east[X] <= X + FLANK then
          xg = east[X]
        end
        if xg ~= nil then
          local x0 = xg + (sign < 0 and 1 or -1)
          local width = 0
          while width < FLANK and x0 + sign * width >= 0 and x0 + sign * width < NW
              and not isGround(x0 + sign * width, Y) and not isLight(x0 + sign * width, Y) do
            width = width + 1
          end
          width = max(width, 1)
          local farPx = sign < 0 and (X - x0) or (x0 + 1 - X)
          local frac = min(1.0, max(0.0, farPx / width))
          best = best == nil and frac or min(best, frac)
        end
      end
      crossedCache[key] = best == nil and false or best
      return best
    end
    local flankFrac = {}
    for n_, c in ipairs(contentList) do
      if n_ % 8 == 0 then tick() end
      for j = 0, P do
        for i = 0, P do
          if not seam(c[1], c[2], i, j) and rockPoint(c[1], c[2], i, j) then
            local X, Y = c[1] * 16 + i * STEP, c[2] * 16 + j * STEP
            local around = { crossed(X, Y - 2), crossed(X, Y - 1), crossed(X, Y), crossed(X, Y + 1) }
            local n = 0
            for k = 1, 4 do if around[k] ~= nil then n = n + 1 end end
            if n >= 3 then
              local d = {}
              if around[2] ~= nil then d[#d + 1] = around[2] end
              if around[3] ~= nil then d[#d + 1] = around[3] end
              if #d > 0 then flankFrac[(K(c[1], c[2]) * 8 + i) * 8 + j] = Art.fsum(d) / #d end
            end
          end
        end
      end
    end
    for _, c in ipairs(sortedContent) do
      local g = gridCopy(grid(c[1], c[2]))
      for j = 0, P do
        for i = 0, P do
          local f = flankFrac[(K(c[1], c[2]) * 8 + i) * 8 + j]
          if f ~= nil and f < 1.0 and g[j][i] > 0 then g[j][i] = g[j][i] * f end
        end
      end
      if not gridEq(g, grid(c[1], c[2])) then grids[K(c[1], c[2])] = g end
    end
    tick()
    -- what a cut tile clears is not there
    local function rockQuad(mask, a, b)
      for j = b * STEP, b * STEP + STEP - 1 do
        for i = a * STEP, a * STEP + STEP - 1 do
          if bitOf(mask, i, j) then return false end
        end
      end
      return true
    end
    for _, mo in ipairs(maskOrder) do
      local cx, cy, k = mo[1], mo[2], mo[3]
      local mask = masks[k]
      if content[k] and mask ~= nil and not keepOut[k] then
        local g0 = grid(cx, cy)
        local g = gridCopy(g0)
        local function quads(i, j)
          local out = {}
          for _, a in ipairs({ i - 1, i }) do
            for _, b in ipairs({ j - 1, j }) do
              if a >= 0 and a < P and b >= 0 and b < P then out[#out + 1] = { a, b } end
            end
          end
          return out
        end
        local whole, bare = {}, {}
        for j = 0, P do
          for i = 0, P do
            local allRock, allClear = true, true
            for _, q in ipairs(quads(i, j)) do
              if not rockQuad(mask, q[1], q[2]) then allRock = false end
              if not clearQuad(mask, q[1], q[2]) then allClear = false end
            end
            if allRock then whole[j * 8 + i] = true end
            if allClear then bare[j * 8 + i] = true end
          end
        end
        local lo, hi = gmin(g0), gmax(g0)
        if not (hi - lo < LEVEL - 0.5) then
          for j = P - 1, 0, -1 do
            for i = 0, P do
              if not whole[j * 8 + i] and not seam(cx, cy, i, j)
                  and not ((i == 0 and content[K(cx - 1, cy)]) or (i == P and content[K(cx + 1, cy)])) then
                local v
                if not bare[(j + 1) * 8 + i] then
                  v = g[j + 1][i]
                else
                  local best
                  for _, d in ipairs({ -1, 1 }) do
                    local side = {}
                    local k_ = i + d
                    while (d < 0 and k_ > -1) or (d > 0 and k_ < P + 1) do
                      if whole[j * 8 + k_] then side[#side + 1] = k_ end
                      k_ = k_ + d
                    end
                    if #side > 0 then
                      local k1 = side[1]
                      local slope = 0.0
                      if #side > 1 then
                        slope = max(-T, min(T, (g0[j][k1] - g0[j][side[2]]) / (k1 - side[2])))
                      end
                      if best == nil or abs(k1 - i) < best[1] then best = { abs(k1 - i), g0[j][k1] + slope * (i - k1) } end
                    end
                  end
                  if best ~= nil then v = best[2] end
                end
                if v ~= nil then g[j][i] = max(lo, min(hi, v)) end
              end
            end
          end
          if not gridEq(g, g0) then grids[k] = g end
        end
      end
    end
    -- the ground behind runs on too, where what is north of a cell is rock lower than its edge
    local taken, cutGround = {}, {}
    for _, c in ipairs(cut) do
      taken[K(c[1], c[2])] = true
      if c[6] ~= nil then cutGround[K(c[1], c[2])] = c[6] end
    end
    local have = {}
    for _, f in ipairs(fills) do have[K(f[1], f[2])] = true end
    for n_, c in ipairs(sortedContent) do
      local cx, cy = c[1], c[2]
      local nx, ny = cx, cy - 1
      if n_ % 8 == 0 then tick() end
      if content[K(nx, ny)] and inside(nx, ny) and not taken[K(cx, cy)] then
        local g, o = grid(cx, cy), grid(nx, ny)
        local foot = gmin(o)
        if WRAP_GROUPS[group] and not content[K(nx, ny - 1)] then
          foot = math.huge
          for j = 1, P do for i = 0, P do foot = min(foot, o[j][i]) end end
        end
        local mt = -math.huge
        for i = 0, P do mt = max(mt, g[0][i]) end
        if not (mt <= foot + 0.5) then
          local near
          for _, d in ipairs((function()
            local list = {}
            for a = -3, 3 do
              for b = -3, 3 do
                local qx, qy = nx + a, ny + b
                if inside(qx, qy) and not content[K(qx, qy)] then list[#list + 1] = { abs(a) + abs(b), qx, qy } end
              end
            end
            table.sort(list, function(p, q)
              if p[1] ~= q[1] then return p[1] < q[1] end
              if p[2] ~= q[2] then return p[2] < q[2] end
              return p[3] < q[3]
            end)
            return list
          end)()) do
            near = near or d
          end
          if near then
            local ground = cutGround[K(nx, ny)]
            if ground == nil then ground = plainGround(art, RL, content, near[2], near[3]) end
            local top = gmax(g)
            local level_ = gmax(g) - gmin(g) <= 1.0 and not keepOut[K(cx, cy)] and not keepOut[K(nx, ny)]
            local goesOn = false
            if level_ then
              local same = true
              for j = 0, P do for i = 0, P do if abs(o[j][i] - o[P][i]) > 1.0 then same = false end end end
              goesOn = same or (WRAP_GROUPS[group] and gmax(o) <= gmin(g) - LEVEL / 2)
            end
            local behindN = level_ and cutGround[K(nx, ny)] or nil
            if behindN ~= nil and not plainTile(art, behindN) then behindN = nil end
            for k = 0, ceil((top - foot) / LEVEL) - 1 do
              local fx, fy = cx, cy + k
              local fk = K(fx, fy)
              if inside(fx, fy) and not taken[fk] and not have[fk] then
                if gmin(grid(fx, fy)) < foot - 0.5 then break end
                if k == 0 and goesOn then
                  local under = cutGround[K(nx, ny)]
                  fills[#fills + 1] = { fx, fy, foot, (under ~= nil and plainTile(art, under)) and under or nil, GOES_ON }
                  have[fk] = true
                elseif behindN ~= nil then
                  fills[#fills + 1] = { fx, fy, foot, behindN }
                  have[fk] = true
                else
                  fills[#fills + 1] = { fx, fy, foot, art.metatile(fx, fy) }
                  have[fk] = true
                end
              end
            end
          end
        end
      end
    end
    -- the cliffs: wherever a cell's west, east or south edge stands over its neighbour's
    local faces = Solve.counter()
    for _, c in ipairs(rockInfo.kindOrder) do
      if kinds[K(c[1], c[2])] == "face" and inside(c[1] - ox, c[2] - oy) then
        faces.add(art.metatile(c[1] - ox, c[2] - oy))
      end
    end
    local face = #faces.order > 0 and faces.most() or NO_FACE
    local walls, wallOrder = {}, {}
    local function edgeRock(x, y)
      local mask = cutMask(art, RL, x, y, content)
      if mask == nil then return 0xFF end
      local bits = 0
      for k = 0, 3 do
        for j = 4 * k, 4 * k + 3 do
          if band(mask[j], 1) == 0 and band(bits, lshift(1, k)) == 0 then bits = bits + lshift(1, k) end
          if band(rshift(mask[j], 15), 1) == 0 and band(bits, lshift(1, 4 + k)) == 0 then bits = bits + lshift(1, 4 + k) end
        end
      end
      return bits
    end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if content[K(x, y)] then
          local g = grid(x, y)
          for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
            local dx, dy = d[1], d[2]
            local nx, ny = x + dx, y + dy
            if inside(nx, ny) then
              local o = grid(nx, ny)
              local gap = -math.huge
              for k = 0, P do
                local v
                if dx < 0 then v = g[k][0] - o[k][P]
                elseif dx > 0 then v = g[k][P] - o[k][0]
                else v = g[P][k] - o[0][k] end
                gap = max(gap, v)
              end
              if gap > 0.5 then
                if walls[K(x, y)] == nil then wallOrder[#wallOrder + 1] = K(x, y) end
                walls[K(x, y)] = { face, edgeRock(x, y) }
              end
            end
          end
        end
      end
    end
    if S.aliasOf(lid) then
      for k in pairs(keepOut) do
        grids[k] = nil
        if walls[k] then walls[k] = nil end
      end
      local kept = {}
      for _, f in ipairs(fills) do if not keepOut[K(f[1], f[2])] then kept[#kept + 1] = f end end
      fills = kept
      local wo = {}
      for _, k in ipairs(wallOrder) do if walls[k] then wo[#wo + 1] = k end end
      wallOrder = wo
    end
    tick()
    return grids, fills, walls, wallOrder
  end
end
