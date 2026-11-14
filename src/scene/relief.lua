-- Relief (Battle Scene: Overworld): terrain read off the drawing - cliffs, their stairs, rocks
-- at sea - and how a lifted cell is drawn.
--
-- The GBA draws the world in a 45-degree oblique view: a point (X, Y, Z) of it lands on the art
-- at u = X, v = Z - Y. So a height h for every point of the art places it at (u, h, v + h), and
-- for ANY h the GBA's view of the result is the drawing itself. A lifted cell holds its heights
-- on a 4-pixel lattice (5 x 5 points, pixels over its map's base); each point stands at
--   (x + a / 4, h / 16, y + c / 4 + h / 16)   (tiles)
-- and everything standing on the cell (a tree, a sign, a building) is lifted with it.
--
-- A cut tile is a cell of rock drawn over the ground behind it (the sea round a ridge's end): its
-- whole drawing lies flat at its foot, and its relief shows the rock alone, the background
-- cleared (a variant of the tile, its background pixels' bits set in `rows`). A cell may have
-- cliffs (`wall`: the metatile its south face is drawn with): wherever its west, east or south
-- edge stands over its neighbour's, a wall closes the step; a top's back, seen from above past a
-- rim, is closed by a wall straight up and the ground behind run on to it.
--
-- Adapted from Emerald 3DS (3ds_port/src/voxel/voxel_relief.c and the relief parts of
-- voxel_mesh_builder.c, voxel_atlas.c; by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes here: written in Lua for LOVE,
-- no lighting (the drawing's own light only, and the side shades), vertices handed to the
-- caller's builder.
--
-- Plain Lua. A relief is { layouts = { [layout id] = L }, variants = { [k] = { layout, metatile,
-- rows } } }, L = { id, base, w, h, drawn, belt, ease, easeRows, faceTile, cells = { [y * w + x]
-- = heights (0..24) }, cuts = { [y * w + x] = { variant, foot, ground, wall, sides } } }.

local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs

local Relief = {}

local SIDE, N = 5, 4
Relief.SIDE = SIDE
Relief.NO_VARIANT = 0xFFFF
Relief.NO_FACE = 0xFFFE
Relief.GOES_ON = lshift(2, 8)
Relief.BLOCK_WALLS = lshift(4, 8)
Relief.THIN_DECK = lshift(8, 8)
Relief.FACE_TOP = lshift(16, 8)
Relief.GOES_ON_FACE = lshift(32, 8)
Relief.GOES_ON_SOUTH = lshift(64, 8)
Relief.CANOPY = lshift(128, 8)
Relief.DECK_EDGE = 4 / 16
Relief.NORTH_FACE_MIN = 18     -- pixels: a level, and the fill's two under it

local SHADE_TOP, SHADE_SOUTH, SHADE_NORTH, SHADE_WEST, SHADE_EAST = 1.00, 0.60, 0.50, 0.65, 0.55
Relief.SHADES = { top = SHADE_TOP, south = SHADE_SOUTH, north = SHADE_NORTH, west = SHADE_WEST, east = SHADE_EAST }

-- ── the file ─────────────────────────────────────────────────────────────────

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function s16(s, o)
  local v = u16(s, o)
  return v >= 0x8000 and v - 0x10000 or v
end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

--- The rows a south seam's ease is spread over: six a level, at most half the map.
function Relief.easeRows(L)
  return min(floor((6 * 8 * L.ease + 15) / 16), floor(L.h / 2))
end

-- A relief as a model, losslessly (voxel_relief_fixes.py's parse and pack): { layouts = { [id] =
-- { w, h, flags (DRAWN, UNIT2), base, belt, ease, level, cells = { [y * w + x] = heights (0..24,
-- pixels) } } }, variants = { [k] = { layout, metatile, rows } } (k from 0; nVariants of them),
-- cuts = { [layout * 65536 + x * 256 + y] = { variant, foot, ground, wall, sides, flags } },
-- edges = { { layout, edge, flags, first, last, top, m0, m1, m2, m3 } } }.
Relief.DRAWN, Relief.UNIT2 = 0x8000, 0x4000
local LEVEL_BIT, WIDE_BIT, HEIGHT_MASK = 0x8000, 0x4000, 0x03FF

--- Read a relief.bin ("VXL4", Emerald 3DS's format) into a model, or nil and why.
function Relief.decode(s, tick)
  if type(s) ~= "string" or #s < 16 or s:sub(1, 4) ~= "VXL4" or u16(s, 6) ~= SIDE then
    return nil, "not a relief file"
  end
  local M = { layouts = {}, variants = {}, nVariants = 0, cuts = {}, edges = {} }
  local at
  for i = 0, u16(s, 4) - 1 do
    local row = 8 + 14 * i
    local id, count, w, h = u16(s, row), u16(s, row + 2), u16(s, row + 4), u16(s, row + 6)
    local off, base = u32(s, row + 8), s16(s, row + 12)
    local wide = band(w, WIDE_BIT) ~= 0
    local unit = band(h, Relief.UNIT2) ~= 0 and 2 or 1
    local t = { w = band(w, HEIGHT_MASK), h = band(h, HEIGHT_MASK), flags = band(h, Relief.DRAWN + Relief.UNIT2),
                base = base, belt = band(rshift(h, 10), 15), ease = band(rshift(w, 10), 15),
                level = band(w, LEVEL_BIT) ~= 0, cells = {} }
    local stride = wide and 52 or 27
    for c = 0, count - 1 do
      if tick and c % 256 == 0 then tick() end
      local o = off + c * stride
      local x, y = s:byte(o + 1), s:byte(o + 2)
      local g = {}
      for k = 0, 24 do
        if wide then
          g[k] = s16(s, o + 2 + 2 * k)
        else
          local b = s:byte(o + 3 + k)
          g[k] = (b >= 128 and b - 256 or b) * unit
        end
      end
      t.cells[y * t.w + x] = g
    end
    M.layouts[id] = t
  end
  if s:sub(-4) == "CUTS" then
    at = u32(s, #s - 8)
    local nv, nc = u16(s, at), u16(s, at + 2)
    at = at + 4
    for k = 0, nv - 1 do
      local rows = {}
      for j = 0, 15 do rows[j] = u16(s, at + 4 + 2 * j) end
      M.variants[k] = { layout = u16(s, at), metatile = u16(s, at + 2), rows = rows }
      at = at + 36
    end
    M.nVariants = nv
    for _ = 1, nc do
      local lay, x, y = u16(s, at), s:byte(at + 3), s:byte(at + 4)
      M.cuts[lay * 65536 + x * 256 + y] = { u16(s, at + 4), s16(s, at + 6), u16(s, at + 8), u16(s, at + 10),
                                            s:byte(at + 13), s:byte(at + 14) }
      at = at + 14
    end
    if s:sub(at + 1, at + 4) == "EDGE" then
      local n = u16(s, at + 4)
      at = at + 8
      for _ = 1, n do
        M.edges[#M.edges + 1] = { u16(s, at), s:byte(at + 3), s:byte(at + 4), s16(s, at + 4), s16(s, at + 6),
                                  s16(s, at + 8), u16(s, at + 10), u16(s, at + 12), u16(s, at + 14), u16(s, at + 16) }
        at = at + 18
      end
    end
  end
  return M
end

-- Python's round(): half to even
local function pyround(x)
  local f = floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 elseif d < 0.5 then return f end
  return f % 2 == 0 and f or f + 1
end
Relief.pyround = pyround

local function p16(v) v = v % 65536; return string.char(v % 256, floor(v / 256)) end
local function p32(v) return p16(v % 65536) .. p16(floor(v / 65536)) end

--- A model as relief.bin's bytes (voxel_relief_fixes.pack). eases = { [layout id] = ease, 8 px
--- units } (seam_eases: pack recomputes every map's), nil for none; tick (optional) is called now
--- and then (the build runs sliced in a coroutine).
function Relief.encode(M, eases, tick)
  local ids = {}
  for id in pairs(M.layouts) do ids[#ids + 1] = id end
  table.sort(ids)
  local tables = {}
  for _, lid in ipairs(ids) do
    local t = M.layouts[lid]
    t.ease = eases and eases[lid] or 0
    if t.ease ~= 0 then
      for y = t.h - min(floor(t.h / 2), floor((6 * 8 * t.ease + 15) / 16)), t.h - 1 do
        for x = 0, t.w - 1 do
          if not t.cells[y * t.w + x] then
            local g = {}
            for k = 0, 24 do g[k] = 0 end
            t.cells[y * t.w + x] = g
          end
        end
      end
    end
    if next(t.cells) ~= nil or t.base ~= 0 or (t.belt or 0) ~= 0 then
      local flags = t.flags or 0
      local lo, hi
      for _, g in pairs(t.cells) do
        for k = 0, 24 do
          local v = g[k]
          if not lo or v < lo then lo = v end
          if not hi or v > hi then hi = v end
        end
      end
      if lo and band(flags, Relief.UNIT2) == 0 and (hi > 127 or lo < -128) then flags = bor(flags, Relief.UNIT2) end
      local unit = band(flags, Relief.UNIT2) ~= 0 and 2 or 1
      local wide = lo ~= nil and (hi > 254 or lo < -256)
      if wide then
        flags = band(flags, bit.bnot(Relief.UNIT2))
        unit = 1
      end
      tables[#tables + 1] = { lid, t, flags, unit, wide }
    end
  end
  local head = "VXL4" .. p16(#tables) .. p16(SIDE)
  local offset = #head + 14 * #tables
  local idx, body, blen = {}, {}, 0
  for _, e in ipairs(tables) do
    local lid, t, flags, unit, wide = e[1], e[2], e[3], e[4], e[5]
    local keys = {}
    for k in pairs(t.cells) do keys[#keys + 1] = k end
    table.sort(keys)          -- (y * w + x: row by row, x within y)
    idx[#idx + 1] = p16(lid) .. p16(#keys)
      .. p16(t.w + (t.level and LEVEL_BIT or 0) + (wide and WIDE_BIT or 0) + lshift(t.ease or 0, 10))
      .. p16(t.h + flags + lshift(t.belt or 0, 10)) .. p32(offset + blen) .. p16(t.base)
    for ki, k in ipairs(keys) do
      if tick and ki % 256 == 0 then tick() end
      local g = t.cells[k]
      local parts = { string.char(k % t.w, floor(k / t.w)) }
      for i = 0, 24 do
        if wide then
          parts[#parts + 1] = p16(max(-32768, min(32767, pyround(g[i]))))
        else
          local v = max(-128, min(127, pyround(g[i] / unit)))
          parts[#parts + 1] = string.char(v % 256)
        end
      end
      local c = table.concat(parts)
      body[#body + 1] = c
      blen = blen + #c
    end
  end
  local blob = head .. table.concat(idx) .. table.concat(body)
  local nv = M.nVariants or 0
  local ckeys = {}
  for k in pairs(M.cuts) do ckeys[#ckeys + 1] = k end
  table.sort(ckeys)
  local tab = { p16(nv), p16(#ckeys) }
  for k = 0, nv - 1 do
    local v = M.variants[k]
    local r = { p16(v.layout), p16(v.metatile) }
    for j = 0, 15 do r[#r + 1] = p16(v.rows[j]) end
    tab[#tab + 1] = table.concat(r)
  end
  for _, key in ipairs(ckeys) do
    local c = M.cuts[key]
    tab[#tab + 1] = p16(floor(key / 65536)) .. string.char(floor(key / 256) % 256, key % 256) .. p16(c[1])
      .. p16(c[2]) .. p16(c[3]) .. p16(c[4]) .. string.char(c[5], c[6])
  end
  if M.edges and #M.edges > 0 then
    tab[#tab + 1] = "EDGE" .. p16(#M.edges) .. p16(0)
    for _, e in ipairs(M.edges) do
      tab[#tab + 1] = p16(e[1]) .. string.char(e[2], e[3]) .. p16(e[4]) .. p16(e[5]) .. p16(e[6]) .. p16(e[7])
        .. p16(e[8]) .. p16(e[9]) .. p16(e[10])
    end
  end
  return blob .. table.concat(tab) .. p32(#blob) .. "CUTS"
end

--- A model as the renderer reads it: { layouts = { [id] = { id, base, w, h, drawn, belt, ease,
--- easeRows, faceTile, cells, cuts = { [y * w + x] = { variant, foot, ground, wall, sides } } } },
--- variants, edges } (ground and wall nil for none; sides with the record's flags in bits 8-15;
--- edges: the hand marks' edge fills, as Relief.read gives them).
function Relief.view(M)
  local layouts = {}
  for id, t in pairs(M.layouts) do
    local L = { id = id, base = t.base, w = t.w, h = t.h, drawn = band(t.flags or 0, Relief.DRAWN) ~= 0,
                belt = t.belt or 0, ease = t.ease or 0, cells = t.cells, cuts = {} }
    L.easeRows = Relief.easeRows(L)
    layouts[id] = L
  end
  local keys = {}
  for k in pairs(M.cuts) do keys[#keys + 1] = k end
  table.sort(keys)
  local walls = {}
  for _, key in ipairs(keys) do
    local c = M.cuts[key]
    local lay, x, y = floor(key / 65536), floor(key / 256) % 256, key % 256
    local L = layouts[lay]
    if L then
      L.cuts[y * L.w + x] = { variant = c[1], foot = c[2], ground = c[3] ~= 0xFFFF and c[3] or nil,
                              wall = c[4] ~= 0xFFFF and c[4] or nil, sides = c[5] + c[6] * 256 }
      local wall = c[4]
      if wall < 0xFFFE then
        local t = walls[lay]
        if not t then t = { order = {}, n = {} }; walls[lay] = t end
        if not t.n[wall] and #t.order < 8 then t.order[#t.order + 1] = wall; t.n[wall] = 0 end
        if t.n[wall] then t.n[wall] = t.n[wall] + 1 end
      end
    end
  end
  for lay, t in pairs(walls) do
    local best
    for _, w in ipairs(t.order) do if not best or t.n[w] > t.n[best] then best = w end end
    layouts[lay].faceTile = best
  end
  return { layouts = layouts, variants = M.variants, edges = M.edges or {} }
end

--- The edge fill past a map's edge at cell (lx, ly) of it (outside it), as Emerald 3DS's
--- VoxelRelief_EdgeFillAt finds it: { metatile, water, hasTop, top (pixels over the map's base) },
--- or nil. Which of the stretch's four metatiles: phased from the map's corner as the game's
--- border block is; past a corner, the west or east edge's first, then the north or south one's.
function Relief.edgeFillAt(edges, layoutId, w, h, lx, ly)
  if not edges or #edges == 0 or w <= 0 or h <= 0 then return nil end
  local cx = lx < 0 and 0 or lx >= w and w - 1 or lx
  local cy = ly < 0 and 0 or ly >= h and h - 1 or ly
  local index = band(lx, 1) + 2 * band(ly, 1)
  local function fill(edge, along)
    for _, e in ipairs(edges) do
      if e[1] == layoutId and e[2] == edge and (e[4] < 0 or (along >= e[4] and along <= e[5])) then
        return { metatile = e[7 + index], water = band(rshift(e[3], 4 + index), 1) ~= 0,
                 hasTop = band(e[3], 2) ~= 0, top = e[6] }
      end
    end
  end
  return lx < 0 and fill(1, cy) or lx >= w and fill(2, cy) or ly < 0 and fill(4, cx)
    or ly >= h and fill(8, cx) or nil
end

--- Read a relief.bin for the renderer (Relief.view of its model), or nil and why.
function Relief.parse(s)
  local M, err = Relief.decode(s)
  if not M then return nil, err end
  return Relief.view(M)
end

--- True when the lattice is not level: rock or stairs.
function Relief.isSlope(g)
  if not g then return false end
  for i = 1, 24 do if g[i] ~= g[0] then return true end end
  return false
end

--- Height (pixels over the base) at the centre of a cell's lattice.
function Relief.centre(g) return g and g[2 * SIDE + 2] or 0 end

--- Height (pixels) at a point of the cell, (fx, fz) in 0..1, on its lattice.
function Relief.sample(g, fx, fz)
  if not g then return 0 end
  fx, fz = fx * N, fz * N
  local i, j = min(floor(fx), N - 1), min(floor(fz), N - 1)
  fx, fz = fx - i, fz - j
  local a = g[j * SIDE + i] * (1 - fx) + g[j * SIDE + i + 1] * fx
  local b = g[(j + 1) * SIDE + i] * (1 - fx) + g[(j + 1) * SIDE + i + 1] * fx
  return a * (1 - fz) + b * fz
end

--- The step a seam asks (pixels to add to b's lift for its edge to meet a's as a stands): every
--- cell along the seam compares the edge both maps share, base and relief, the mean of its lattice
--- points to the nearest 4 pixels; the commonest difference where three cells in four agree on it,
--- else 0. a, b = { L (or nil: no relief), x, y (its corner), w, h }.
function Relief.seamStep(a, b)
  if not a.L and not b.L then return 0 end
  local from, to, ax, ay, bx, by, dx, dy, ai, aj, bi, bj, di, dj
  if a.x + a.w == b.x or b.x + b.w == a.x then
    local east = a.x + a.w == b.x
    from, to = max(a.y, b.y), min(a.y + a.h, b.y + b.h)
    ax, bx = east and a.x + a.w - 1 or a.x, east and b.x or b.x + b.w - 1
    ay, by = from, from
    dx, dy = 0, 1
    ai, bi, aj, bj, di, dj = east and N or 0, east and 0 or N, 0, 0, 0, 1
  elseif a.y + a.h == b.y or b.y + b.h == a.y then
    local south = a.y + a.h == b.y
    from, to = max(a.x, b.x), min(a.x + a.w, b.x + b.w)
    ay, by = south and a.y + a.h - 1 or a.y, south and b.y or b.y + b.h - 1
    ax, bx = from, from
    dx, dy = 1, 0
    aj, bj, ai, bi, di, dj = south and N or 0, south and 0 or N, 0, 0, 1, 0
  else
    return 0
  end
  local function cellOf(m, wx, wy)
    if not m.L then return nil end
    local lx, ly = wx - m.x, wy - m.y
    if lx < 0 or ly < 0 or lx >= m.L.w or ly >= m.L.h then return nil end
    return m.L.cells[ly * m.L.w + lx]
  end
  local diff, n = {}, 0
  for c = from, to - 1 do
    if n >= 256 then break end
    local ga = cellOf(a, ax + dx * (c - from), ay + dy * (c - from))
    local gb = cellOf(b, bx + dx * (c - from), by + dy * (c - from))
    local sum = 0
    for p = 0, SIDE - 1 do
      local ka = (aj + dj * p) * SIDE + ai + di * p
      local kb = (bj + dj * p) * SIDE + bi + di * p
      sum = sum + (a.L and a.L.base or 0) + (ga and ga[ka] or 0) - (b.L and b.L.base or 0) - (gb and gb[kb] or 0)
    end
    n = n + 1
    diff[n] = floor(sum / (4 * SIDE) + 0.5) * 4
  end
  local best, step = 0, 0
  for i = 1, n do
    local count = 0
    for j = 1, n do if diff[j] == diff[i] then count = count + 1 end end
    if count > best then best, step = count, diff[i] end
  end
  return (n ~= 0 and 4 * best >= 3 * n) and step or 0
end

-- ── cut tiles ────────────────────────────────────────────────────────────────

local CUT_DIR = { [0] = { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
local function bg(rows, i, j) return band(rshift(rows[j], i), 1) ~= 0 end

-- the rock's eight sides (its hull: a*i + b*j <= c over its pixels), and whether it is that hull
local function cutHull(rows)
  local c, rock = {}, 0
  for k = 0, 7 do c[k] = -32768 end
  for j = 0, 15 do
    for i = 0, 15 do
      if not bg(rows, i, j) then
        rock = rock + 1
        for k = 0, 7 do
          local v = CUT_DIR[k][1] * i + CUT_DIR[k][2] * j
          if v > c[k] then c[k] = v end
        end
      end
    end
  end
  if rock == 0 or rock == 256 then return c, false end
  for j = 0, 15 do
    for i = 0, 15 do
      local inside = true
      for k = 0, 7 do
        if CUT_DIR[k][1] * i + CUT_DIR[k][2] * j > c[k] then inside = false; break end
      end
      if inside == bg(rows, i, j) then return c, false end
    end
  end
  return c, true
end

--- A cut tile whose rock is a polygon with 45-degree sides is cut along them: { count, a, b, c }
--- (sides a*X + b*Y <= c over the tile's pixels, through the outer corners of the rock's pixels).
function Relief.cutDiagonals(rows)
  local out = { count = 0, a = {}, b = {}, c = {} }
  if not rows then return out end
  local c, ok = cutHull(rows)
  if not ok then return out end
  for k = 4, 7 do
    local a, b = CUT_DIR[k][1], CUT_DIR[k][2]
    local corner = a * (a > 0 and c[3] or -c[2]) + b * (b > 0 and c[1] or -c[0])
    if c[k] < corner then
      out.count = out.count + 1
      out.a[out.count], out.b[out.count] = a, b
      out.c[out.count] = c[k] + (a > 0 and 1 or 0) + (b > 0 and 1 or 0)
    end
  end
  return out
end

-- does the polygon of sides c take in part of pixel (i, j)?
local function cutTakes(c, i, j)
  for k = 0, 7 do
    local a, b = CUT_DIR[k][1], CUT_DIR[k][2]
    local least = a * (a > 0 and i or i + 1) + b * (b > 0 and j or j + 1)
    if least >= c[k] + (a > 0 and 1 or 0) + (b > 0 and 1 or 0) then return false end
  end
  return true
end

--- The texels a cut tile leaves clear: its background, less the halves of background pixels its
--- straight diagonals take in. rows[0..15] -> clear[0..15].
function Relief.cutClear(rows)
  local clear = {}
  for j = 0, 15 do clear[j] = rows[j] end
  local d = Relief.cutDiagonals(rows)
  if d.count == 0 then return clear end
  local c = cutHull(rows)
  -- a side a pixel long where a 45-degree side ends at the tile's edge is the staircase's last step
  for k = 0, 3 do
    if not (c[k] >= ((CUT_DIR[k][1] + CUT_DIR[k][2] > 0) and 15 or 0)) then
      c[k] = c[k] + 1
      local gained = 0
      for j = 0, 15 do
        if gained > 1 then break end
        for i = 0, 15 do
          if bg({ [j] = clear[j] }, i, j) and CUT_DIR[k][1] * i + CUT_DIR[k][2] * j == c[k] and cutTakes(c, i, j) then
            gained = gained + 1
          end
        end
      end
      if gained ~= 1 then c[k] = c[k] - 1 end
    end
  end
  for j = 0, 15 do
    for i = 0, 15 do
      if band(rshift(clear[j], i), 1) ~= 0 and cutTakes(c, i, j) then
        clear[j] = band(clear[j], bit.bnot(lshift(1, i)))
      end
    end
  end
  return clear
end

local AROUND = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
--- A background pixel the clear keeps drawn shows the rock beside it: the index (y * 16 + x) of
--- that rock pixel, or nil.
function Relief.cutFringe(rows, clear, x, y)
  if not bg(rows, x, y) or band(rshift(clear[y], x), 1) ~= 0 then return nil end
  for _, d in ipairs(AROUND) do
    local nx, ny = x + d[1], y + d[2]
    if nx >= 0 and nx <= 15 and ny >= 0 and ny <= 15 and not bg(rows, nx, ny) then return ny * 16 + nx end
  end
  return nil
end

--- A cut tile's texture, pixel by pixel: pixel(x, y) -> the metatile's composite colour { r, g, b }
--- or nil; returns { [y * 16 + x] = colour } of what it draws (cleared background left out, the
--- polygon's edge pixels in the colour of the rock beside them).
function Relief.cutTexture(rows, pixel)
  local clear = Relief.cutClear(rows)
  local out = {}
  for y = 0, 15 do
    for x = 0, 15 do
      if band(rshift(clear[y], x), 1) == 0 then
        local from = Relief.cutFringe(rows, clear, x, y)
        out[y * 16 + x] = from and pixel(from % 16, floor(from / 16)) or pixel(x, y)
      end
    end
  end
  return out
end

-- ── the builder ──────────────────────────────────────────────────────────────
--
-- B = {
--   quad(a, b, c, d), tri(a, b, c)   vertices { x, y, z, u, v, shade } in tiles and atlas uvs; the
--                                    builder's lift and shift (B.lift, B.shift) are added here
--   cell(x, y) -> heights of a cell of the same map, or nil
--   cut(x, y) -> its cut record, or nil
--   variant(k) -> the cut variant k ({ rows }), or nil
--   faceTile                           the map's commonest cliff wall, or nil
--   tileUV(x, y) -> u0, v0, u1, v1   the cell's own drawing (or nil)
--   metatileUV(m), cutUV(k)          a metatile's drawing (the map's own id), a cut variant's
--   sign(x, y) -> the metatile a sign's cell lays (its ground) or nil
--   headGround(x, y) -> the metatile under a sign's head in this cell, or nil
--   modelTop(x, y) -> the top (tiles) of a model whose cell this is, or nil
--   bare(x, y) -> u0, v0, u1, v1   a relief_bare model's bare cell: the cell less its quarters
--   standing(x, y, lift, shift)      what stands on the cell (a sign), placed at that lift
-- }

local function vtx(x, y, z, u, v, shade) return { x, y, z, u, v, shade } end

local function put(B, a, b, c, d)
  local L, S = B.lift or 0, B.shift or 0
  local function m(p) return { p[1], p[2] + L, p[3] + S, p[4], p[5], p[6] } end
  if d then B.quad(m(a), m(b), m(c), m(d)) else B.tri(m(a), m(b), m(c)) end
end

local function lerp(p, q, t)
  return { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t,
           p[4] + (q[4] - p[4]) * t, p[5] + (q[5] - p[5]) * t, p[6] + (q[6] - p[6]) * t }
end

-- a triangle of the cell (pixels px), cut by the diagonals: a fan of quads, an odd triangle left
local function cutTri(B, v0, v1, v2, px, cut)
  local poly, pp = { v0, v1, v2 }, { px[1], px[2], px[3] }
  for k = 1, cut.count do
    if #poly == 0 then break end
    local np, npp = {}, {}
    local n = #poly
    for i = 1, n do
      local j = i % n + 1
      local di = cut.a[k] * pp[i][1] + cut.b[k] * pp[i][2] - cut.c[k]
      local dj = cut.a[k] * pp[j][1] + cut.b[k] * pp[j][2] - cut.c[k]
      if di <= 0 then
        np[#np + 1] = poly[i]
        npp[#npp + 1] = pp[i]
      end
      if (di < 0 and dj > 0) or (di > 0 and dj < 0) then
        local t = di / (di - dj)
        np[#np + 1] = lerp(poly[i], poly[j], t)
        npp[#npp + 1] = { pp[i][1] + (pp[j][1] - pp[i][1]) * t, pp[i][2] + (pp[j][2] - pp[i][2]) * t }
      end
    end
    poly, pp = np, npp
  end
  local n = #poly
  local i = 2
  while i + 1 <= n do
    if i + 2 <= n then put(B, poly[1], poly[i], poly[i + 1], poly[i + 2])
    else put(B, poly[1], poly[i], poly[i + 1]) end
    i = i + 2
  end
end

-- a quad of the cell (pixels px), as two triangles each cut by the diagonals; whole when none
-- reaches it
local function cutQuad(B, p0, p1, p2, p3, px, cut)
  local inside, outside = true, false
  for k = 1, cut.count do
    local n = 0
    for i = 1, 4 do
      if cut.a[k] * px[i][1] + cut.b[k] * px[i][2] <= cut.c[k] then n = n + 1 end
    end
    inside = inside and n == 4
    outside = outside or n == 0
  end
  if outside then return end
  if inside then
    put(B, p0, p1, p2, p3)
    return
  end
  cutTri(B, p0, p1, p2, { px[1], px[2], px[3] }, cut)
  cutTri(B, p0, p2, p3, { px[1], px[3], px[4] }, cut)
end

-- does the lattice quad (i, j) lie on `fl` (pixels) or under it?
local function onFloor(g, i, j, fl)
  return g[j * SIDE + i] <= fl and g[j * SIDE + i + 1] <= fl and g[(j + 1) * SIDE + i] <= fl
    and g[(j + 1) * SIDE + i + 1] <= fl
end

-- how many pixels of the 4x4 block (i, j) of a cut tile are rock
local function cutRockPixels(rows, i, j)
  local rock = 0
  for py = 4 * j, 4 * j + 3 do
    for px = 4 * i, 4 * i + 3 do
      if not bg(rows, px, py) then rock = rock + 1 end
    end
  end
  return rock
end

-- a cut tile's flat layer at its foot: where a block of the drawing has rock in it (lifted), the
-- plain ground behind it (gnd); where all background, the tile's own drawing
local function cutGround(B, x, y, u0, v0, u1, v1, rows, gnd, g, fl)
  local lo, hi = fl, -32768
  if g then
    for k = 0, 24 do
      if g[k] < lo then lo = g[k] end
      if g[k] > hi then hi = g[k] end
    end
  end
  local mountain = g ~= nil and hi - lo >= 16
  for j = 0, N - 1 do
    for i = 0, N - 1 do
      local xa, xb = x + i / N, x + (i + 1) / N
      local za, zb = y + j / N, y + (j + 1) / N
      local ua, ub, va, vb
      local rock = rows and cutRockPixels(rows, i, j) or 0
      if rows and gnd and rock > 0 and (rock < 12 or (mountain and not onFloor(g, i, j, fl))) then
        ua, ub = gnd[1] + (gnd[3] - gnd[1]) * i / N, gnd[1] + (gnd[3] - gnd[1]) * (i + 1) / N
        va, vb = gnd[2] + (gnd[4] - gnd[2]) * j / N, gnd[2] + (gnd[4] - gnd[2]) * (j + 1) / N
      else
        ua, ub = u0 + (u1 - u0) * i / N, u0 + (u1 - u0) * (i + 1) / N
        va, vb = v0 + (v1 - v0) * j / N, v0 + (v1 - v0) * (j + 1) / N
      end
      put(B, vtx(xa, 0, za, ua, va, SHADE_TOP), vtx(xb, 0, za, ub, va, SHADE_TOP),
        vtx(xb, 0, zb, ub, vb, SHADE_TOP), vtx(xa, 0, zb, ua, vb, SHADE_TOP))
    end
  end
end

-- ground run on under cell (x, y) at the builder's lift, two pixels past it (not past a side where
-- the cell beyond falls away below it)
local function runOn(B, x, y, u0, v0, u1, v1)
  local SIDES = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
  local m, level = 2 / 16, (B.lift or 0) * 16
  local pad = {}
  for k = 1, 4 do
    pad[k] = m
    local g = B.cell(x + SIDES[k][1], y + SIDES[k][2])
    local low = 0
    if g then
      low = 32767
      for t = 0, SIDE - 1 do
        local edge, inn
        if k <= 2 then
          local a = k == 1 and SIDE - 1 or 0
          edge = t * SIDE + a
          inn = t * SIDE + (k == 1 and a - 1 or a + 1)
        else
          local c = k == 3 and SIDE - 1 or 0
          edge = c * SIDE + t
          inn = (k == 3 and c - 1 or c + 1) * SIDE + t
        end
        if g[edge] < low then low = g[edge] end
        if (g[edge] + g[inn]) * 0.5 < low then low = (g[edge] + g[inn]) * 0.5 end
      end
    end
    if low < level - 0.01 then pad[k] = 0 end
  end
  put(B, vtx(x - pad[1], 0, y - pad[3], u0, v0, SHADE_TOP), vtx(x + 1 + pad[2], 0, y - pad[3], u1, v0, SHADE_TOP),
    vtx(x + 1 + pad[2], 0, y + 1 + pad[4], u1, v1, SHADE_TOP), vtx(x - pad[1], 0, y + 1 + pad[4], u0, v1, SHADE_TOP))
end

local function groundRunOn(B, x, y, foot, u0, v0, u1, v1)
  B.lift = foot - (2 + 0.125 * ((x + y) % 2)) / 16
  B.shift = B.lift
  runOn(B, x, y, u0, v0, u1, v1)
  B.lift, B.shift = 0, 0
end

-- does the lattice rectangle from (a0, c0), wa by wc, lie on one plane? (whole pixels: exact)
local function spanFlat(v, a0, c0, wa, wc)
  local k0 = c0 * SIDE + a0
  local du, dv = v[k0 + wa] - v[k0], v[k0 + wc * SIDE] - v[k0]
  for c = 0, wc do
    for a = 0, wa do
      if wa * wc * v[k0 + c * SIDE + a] ~= wa * wc * v[k0] + a * wc * du + c * wa * dv then return false end
    end
  end
  return true
end

local function reliefSpan(B, x, y, g, s, u0, v0, u1, v1, i0, j0, wa, wc, flr, fl, rows, cut)
  local di, dj = { 0, 1, 1, 0 }, { 0, 0, 1, 1 }
  local p, px = {}, {}
  local raise = 0
  local one = wa == 1 and wc == 1
  if one and flr and onFloor(g, i0, j0, fl) then
    -- the flat layer under rock is plain ground: rock on the foot is drawn half a pixel over it
    local rock = rows and cutRockPixels(rows, i0, j0) or 0
    if rock == 0 or rock >= 12 then return end
    raise = 0.5 / 16
  end
  for k = 1, 4 do
    local a, c = i0 + di[k] * wa, j0 + dj[k] * wc
    local at = c * SIDE + a
    p[k] = vtx(x + a / N, g[at] / 16 + raise, y + c / N + s[at] / 16, u0 + (u1 - u0) * a / N, v0 + (v1 - v0) * c / N,
      SHADE_TOP)
    px[k] = { 16 * a / N, 16 * c / N }
  end
  -- split along the crease: a mountain's corner is two planes meeting on a diagonal of the cell
  if one and g[j0 * SIDE + i0] == g[(j0 + 1) * SIDE + i0 + 1] and g[j0 * SIDE + i0 + 1] ~= g[(j0 + 1) * SIDE + i0] then
    cutQuad(B, p[2], p[3], p[4], p[1], { px[2], px[3], px[4], px[1] }, cut)
  else
    cutQuad(B, p[1], p[2], p[3], p[4], px, cut)
  end
end

local SPANS = { { 4, 4 }, { 4, 2 }, { 2, 4 }, { 2, 2 }, { 4, 1 }, { 1, 4 }, { 2, 1 }, { 1, 2 }, { 1, 1 } }

--- A cell's drawing (uv rect u0..v1) laid on its relief g (heights) and s (depths: the same).
--- flr: leave out the quads lying on fl (pixels), the flat layer's already; rows: a cut tile's
--- background bits.
function Relief.reliefUV(B, x, y, g, s, u0, v0, u1, v1, flr, fl, rows)
  local cut = Relief.cutDiagonals(rows)
  if not Relief.isSlope(g) and not Relief.isSlope(s) then
    local h, d = g[0] / 16, s[0] / 16
    cutQuad(B, vtx(x, h, y + d, u0, v0, SHADE_TOP), vtx(x + 1, h, y + d, u1, v0, SHADE_TOP),
      vtx(x + 1, h, y + 1 + d, u1, v1, SHADE_TOP), vtx(x, h, y + 1 + d, u0, v1, SHADE_TOP),
      { { 0, 0 }, { 16, 0 }, { 16, 16 }, { 0, 16 } }, cut)
    return
  end
  -- a rectangle of the lattice that is one plane and uncut is one quad: largest first
  local drawn = {}
  for _, sp in ipairs(SPANS) do
    local wa, wc = sp[1], sp[2]
    local one = wa == 1 and wc == 1
    if one or cut.count == 0 then
      for j0 = 0, N - 1, wc do
        for i0 = 0, N - 1, wa do
          local taken = false
          for j = j0, j0 + wc - 1 do
            for i = i0, i0 + wa - 1 do if drawn[j * N + i] then taken = true end end
          end
          if not taken then
            local merge = one
            if not one and spanFlat(g, i0, j0, wa, wc) and spanFlat(s, i0, j0, wa, wc) then
              merge = true
              for j = j0, j0 + wc - 1 do
                for i = i0, i0 + wa - 1 do
                  if flr and onFloor(g, i, j, fl) then merge = false end
                end
              end
            end
            if merge then
              for j = j0, j0 + wc - 1 do
                for i = i0, i0 + wa - 1 do drawn[j * N + i] = true end
              end
              reliefSpan(B, x, y, g, s, u0, v0, u1, v1, i0, j0, wa, wc, flr, fl, rows, cut)
            end
          end
        end
      end
    end
  end
end

-- ── cliff walls ──────────────────────────────────────────────────────────────

-- whether a back stands as a wall straight up: the cell north (same map) a level and two pixels
-- lower somewhere along the edge
local function northFaceStands(B, x, y, g)
  if not B.sameMap(x, y - 1) then return false end
  local o = B.cell(x, y - 1)
  for k = 0, N do
    if g[k] - (o and o[N * SIDE + k] or 0) >= Relief.NORTH_FACE_MIN then return true end
  end
  return false
end

-- a step between two stretches of a back's wall: the rock's side at x, from za to zb, bot..top px
local function wallStep(B, x, za, zb, bot, top, west, u0, v0, u1, v1)
  local h0 = bot
  while h0 < top do
    local nextLevel = floor(h0 / 16 + 1) * 16
    local h1, base = min(top, nextLevel), floor(h0 / 16) * 16
    local va, vb = v1 + (v0 - v1) * (h0 - base) / 16, v1 + (v0 - v1) * (h1 - base) / 16
    local ua = u0 + (u1 - u0) * (za - floor(za))
    local ub = ua + (u1 - u0) * min(1, zb - za)
    if west then
      put(B, vtx(x, h0 / 16, za, ua, va, SHADE_WEST), vtx(x, h0 / 16, zb, ub, va, SHADE_WEST),
        vtx(x, h1 / 16, zb, ub, vb, SHADE_WEST), vtx(x, h1 / 16, za, ua, vb, SHADE_WEST))
    else
      put(B, vtx(x, h0 / 16, zb, ub, va, SHADE_EAST), vtx(x, h0 / 16, za, ua, va, SHADE_EAST),
        vtx(x, h1 / 16, za, ua, vb, SHADE_EAST), vtx(x, h1 / 16, zb, ub, vb, SHADE_EAST))
    end
    h0 = nextLevel
  end
end

-- the part of a wall polygon at or under (sign 1) or at or over (sign -1) `limit`, in height (or z)
local function clipWall(poly, limit, sign, onZ)
  local out = {}
  local n = #poly
  for i = 1, n do
    local a, c = poly[i], poly[i % n + 1]
    local da = sign * ((onZ and a[3] or a[2]) - limit)
    local dc = sign * ((onZ and c[3] or c[2]) - limit)
    if da <= 0 then out[#out + 1] = a end
    if (da < 0 and dc > 0) or (da > 0 and dc < 0) then
      local t = da / (da - dc)
      out[#out + 1] = { a[1] + (c[1] - a[1]) * t, a[2] + (c[2] - a[2]) * t, a[3] + (c[3] - a[3]) * t,
                        a[4] + (c[4] - a[4]) * t, a[5] + (c[5] - a[5]) * t, a[6] }
    end
  end
  return out
end

local function wallFan(B, p)
  local n = #p
  local i = 2
  while i + 1 <= n do
    put(B, p[1], p[i], p[i + 1], p[(i + 2 <= n) and i + 2 or i + 1])
    i = i + 2
  end
end

-- a wall standing more than a level, cut in bands of a level down from `top`, each band the tile
-- again; a west or east one (`across` 1 or -1) takes u from where it stands, a tile a cell of z
local function wallBands(B, p, top, v0, v1, across, u0, u1)
  local lo = min(min(p[1][2], p[2][2]), min(p[3][2], p[4][2]))
  local band_ = top
  while band_ > lo + 1 / 64 do
    local under = clipWall(p, band_, 1, false)
    local piece = clipWall(under, band_ - 1, -1, false)
    if #piece >= 3 then
      for i = 1, #piece do
        local q = piece[i]
        piece[i] = { q[1], q[2], q[3], q[4], v0 + (v1 - v0) * (band_ - q[2]), q[6] }
      end
      if across == 0 then
        wallFan(B, piece)
      else
        local zlo, zhi = piece[1][3], piece[1][3]
        for i = 2, #piece do
          zlo, zhi = min(zlo, piece[i][3]), max(zhi, piece[i][3])
        end
        local cellZ = floor(zlo)
        while cellZ < zhi do
          local south = clipWall(piece, cellZ + 1, 1, true)
          local tile = clipWall(south, cellZ, -1, true)
          if #tile >= 3 then
            for i = 1, #tile do
              local q = tile[i]
              local u = across > 0 and u0 + (u1 - u0) * (q[3] - cellZ) or u1 - (u1 - u0) * (q[3] - cellZ)
              tile[i] = { q[1], q[2], q[3], u, q[5], q[6] }
            end
            wallFan(B, tile)
          end
          cellZ = cellZ + 1
        end
      end
    end
    band_ = band_ - 1
  end
end

local LEVEL = {}
for k = 0, 24 do LEVEL[k] = 0 end

--- A cell's cliff walls: where its west, east or south edge stands over its neighbour's.
function Relief.cliffWalls(B, x, y, g, s, wall, art, artY, sides, backed)
  local f0, g0, f1, g1
  local face = false
  if wall ~= Relief.NO_FACE then
    f0, g0, f1, g1 = B.metatileUV(wall)
    face = f0 ~= nil
  end
  local o0, p0, o1, p1
  if art then o0, p0, o1, p1 = art[1], art[2], art[3], art[4]
  else o0, p0, o1, p1 = B.tileUV(x, artY) end
  local own = o0 ~= nil
  local blockWalls = face and band(sides, Relief.BLOCK_WALLS) ~= 0
  local walled = backed and northFaceStands(B, x, y, g)
  local R = SIDE
  for d = 0, 2 do
    local nx = x + (d == 0 and -1 or d == 1 and 1 or 0)
    local ny = y + (d == 2 and 1 or 0)
    local skip = (d == 2) and not face or (d < 2 and not (own or blockWalls))
    if not skip then
      local o, os
      if B.sameMap(nx, ny) then
        o = B.cell(nx, ny)
        os = o
      end
      if not o then o, os = LEVEL, LEVEL end
      if d < 2 and band(sides, Relief.THIN_DECK) == 0 and o ~= LEVEL then
        local nc = B.cut(nx, ny)
        if nc and band(nc.sides, Relief.THIN_DECK) ~= 0 then
          local under = {}
          for i = 0, 24 do under[i] = floor(nc.foot + 0.5) end
          o = under
        end
      end
      -- a wall the same all along the edge and more than a level tall: one piece the edge long
      local st = 1
      if (d == 2 and face or (d < 2 and blockWalls)) and band(sides, Relief.THIN_DECK) == 0 then
        local a0 = d == 0 and 0 or d == 1 and N or N * R
        local c0 = d == 0 and N or 0
        local along = d == 2 and 1 or R
        local same = g[a0] - o[c0] > 16
        local k = 1
        while k <= N and same do
          same = g[a0 + k * along] == g[a0] and o[c0 + k * along] == o[c0] and s[a0 + k * along] == s[a0]
            and os[c0 + k * along] == os[c0]
          k = k + 1
        end
        if same then st = N end
      end
      local k = 0
      while k < N do
        local ia, ib, ic, id
        if d == 0 then
          ia, ib, ic, id = k * R, (k + st) * R, k * R + N, (k + st) * R + N
        elseif d == 1 then
          ia, ib, ic, id = k * R + N, (k + st) * R + N, k * R, (k + st) * R
        else
          ia, ib, ic, id = N * R + k, N * R + k + st, k, k + st
        end
        local hang = not (g[ia] - o[ic] <= 0 and g[ib] - o[id] <= 0)
        -- the edge column's pixels the tile clears are ground beside the rock: no wall on them
        if hang and d < 2 and not blockWalls and band(rshift(sides, (d == 0 and 0 or 4) + k), 1) == 0 then
          hang = false
        end
        if hang then
          local ta, tb = g[ia] / 16, g[ib] / 16
          local ba = (g[ia] > o[ic] and o[ic] or g[ia]) / 16
          local bb = (g[ib] > o[id] and o[id] or g[ib]) / 16
          if band(sides, Relief.THIN_DECK) ~= 0 then
            ba = max(ba, ta - Relief.DECK_EDGE)
            bb = max(bb, tb - Relief.DECK_EDGE)
          end
          if d == 2 then
            local ua, ub = f0 + (f1 - f0) * k / N, f0 + (f1 - f0) * (k + st) / N
            local dva, dvb = (g1 - g0) * min(1, ta - ba), (g1 - g0) * min(1, tb - bb)
            local xa, xb = x + k / N, x + (k + st) / N
            local za, zb = y + 1 + s[ia] / 16, y + 1 + s[ib] / 16
            local zc, zd = y + 1 + os[ic] / 16, y + 1 + os[id] / 16
            if ta - ba > 1 or tb - bb > 1 then
              wallBands(B, { vtx(xa, ta, za, ua, g0, SHADE_SOUTH), vtx(xb, tb, zb, ub, g0, SHADE_SOUTH),
                             vtx(xb, bb, zd, ub, g0, SHADE_SOUTH), vtx(xa, ba, zc, ua, g0, SHADE_SOUTH) },
                max(ta, tb), g0, g1, 0, 0, 0)
            else
              put(B, vtx(xa, ta, za, ua, g0, SHADE_SOUTH), vtx(xb, tb, zb, ub, g0, SHADE_SOUTH),
                vtx(xb, bb, zd, ub, g0 + dvb, SHADE_SOUTH), vtx(xa, ba, zc, ua, g0 + dva, SHADE_SOUTH))
            end
          else
            local xe = d == 0 and x or x + 1
            local za = y + k / N + s[ia] / 16
            local zb = y + (k + st) / N + s[ib] / 16
            local zc = y + k / N + os[ic] / 16
            local zd = y + (k + st) / N + os[id] / 16
            if walled then
              local wz = y + (d == 0 and max(s[0], s[1]) or max(s[N - 1], s[N])) / 16
              za, zb, zc, zd = max(za, wz), max(zb, wz), max(zc, wz), max(zd, wz)
            end
            if blockWalls then
              local shade = d == 0 and SHADE_WEST or SHADE_EAST
              local zm = floor((za + zb + zc + zd) * 0.25)
              local yt = ceil(max(ta, tb) - 0.01)
              local function wu(z)
                local t = min(1, max(0, z - zm))
                return d == 0 and f0 + (f1 - f0) * t or f1 - (f1 - f0) * t
              end
              local function wv(h) return g0 + (g1 - g0) * min(1, max(0, yt - h)) end
              if yt - min(ba, bb) > 1 then
                local p = { vtx(xe, ta, za, 0, 0, shade), vtx(xe, tb, zb, 0, 0, shade),
                            vtx(xe, bb, zd, 0, 0, shade), vtx(xe, ba, zc, 0, 0, shade) }
                local q = { p[2], p[1], p[4], p[3] }
                wallBands(B, d == 0 and p or q, yt, g0, g1, d == 0 and 1 or -1, f0, f1)
              elseif d == 0 then
                put(B, vtx(xe, ta, za, wu(za), wv(ta), shade), vtx(xe, tb, zb, wu(zb), wv(tb), shade),
                  vtx(xe, bb, zd, wu(zd), wv(bb), shade), vtx(xe, ba, zc, wu(zc), wv(ba), shade))
              else
                put(B, vtx(xe, tb, zb, wu(zb), wv(tb), shade), vtx(xe, ta, za, wu(za), wv(ta), shade),
                  vtx(xe, ba, zc, wu(zc), wv(ba), shade), vtx(xe, bb, zd, wu(zd), wv(bb), shade))
              end
            else
              -- the edge column of the drawing, half a pixel in, lit as the drawing
              local ue = d == 0 and o0 + (o1 - o0) / 32 or o1 - (o1 - o0) / 32
              local va, vb = p0 + (p1 - p0) * k / N, p0 + (p1 - p0) * (k + st) / N
              if d == 0 then
                put(B, vtx(xe, ta, za, ue, va, SHADE_TOP), vtx(xe, tb, zb, ue, vb, SHADE_TOP),
                  vtx(xe, bb, zd, ue, vb, SHADE_TOP), vtx(xe, ba, zc, ue, va, SHADE_TOP))
              else
                put(B, vtx(xe, tb, zb, ue, vb, SHADE_TOP), vtx(xe, ta, za, ue, va, SHADE_TOP),
                  vtx(xe, ba, zc, ue, va, SHADE_TOP), vtx(xe, bb, zd, ue, vb, SHADE_TOP))
              end
            end
          end
        end
        k = k + st
      end
    end
  end
end

--- A back's north side, seen from above past a rim: the wall straight up (wallTile, a tile a
--- level) and the ground behind (groundTile) run flat from the north cell's edge to its foot.
function Relief.northFace(B, x, y, g, s, wallTile, groundTile)
  if not northFaceStands(B, x, y, g) then return end
  local o = B.cell(x, y - 1) or LEVEL
  local os = o
  local lo, hi = 32767, -32768
  for k = 0, N do
    lo = min(lo, o[N * SIDE + k])
    hi = max(hi, g[k])
  end
  local u0, v0, u1, v1, gu0, gv0, gu1, gv1
  if wallTile then u0, v0, u1, v1 = B.metatileUV(wallTile) end
  if groundTile then gu0, gv0, gu1, gv1 = B.metatileUV(groundTile) end
  local standing, ground = u0 ~= nil, gu0 ~= nil
  if not standing and not ground then return end
  for k = 0, N - 1 do
    local xs = { x + k / N, x + (k + 1) / N }
    local bot = { o[N * SIDE + k], o[N * SIDE + k + 1] }
    local top = { g[k], g[k + 1] }
    local zb = { y + os[N * SIDE + k] / 16, y + os[N * SIDE + k + 1] / 16 }
    local zt = { y + s[k] / 16, y + s[k + 1] / 16 }
    local ua, ub
    if standing then ua, ub = u1 - (u1 - u0) * k / N, u1 - (u1 - u0) * (k + 1) / N end
    for e = 1, 2 do if top[e] < bot[e] then top[e] = bot[e] end end
    local zmax = max(zt[1], zt[2])
    zt[1], zt[2] = zmax, zmax
    if standing and k + 1 < N then
      local zn = y + max(s[k + 1], s[k + 2]) / 16
      if abs(zn - zt[2]) > 0.001 then
        wallStep(B, xs[2], min(zn, zt[2]), max(zn, zt[2]), o[N * SIDE + k + 1],
          g[k + 1] > o[N * SIDE + k + 1] and g[k + 1] or o[N * SIDE + k + 1], zn < zt[2], u0, v0, u1, v1)
      end
    end
    if standing then
      local b16 = lo
      while b16 < hi do
        local h = { {}, {} }
        local any = false
        for e = 1, 2 do
          h[e][1] = max(bot[e], b16)
          h[e][2] = min(top[e], b16 + 16)
          if h[e][2] < h[e][1] then h[e][2] = h[e][1] end
          any = any or h[e][2] > h[e][1]
        end
        if any then
          local function nv(hh) return v1 + (v0 - v1) * (hh - b16) / 16 end
          put(B, vtx(xs[2], h[2][1] / 16, zt[2], ub, nv(h[2][1]), SHADE_NORTH),
            vtx(xs[1], h[1][1] / 16, zt[1], ua, nv(h[1][1]), SHADE_NORTH),
            vtx(xs[1], h[1][2] / 16, zt[1], ua, nv(h[1][2]), SHADE_NORTH),
            vtx(xs[2], h[2][2] / 16, zt[2], ub, nv(h[2][2]), SHADE_NORTH))
        end
        b16 = b16 + 16
      end
    end
    if ground then
      bot[1], bot[2] = bot[1] - 1, bot[2] - 1
      local za, zz = min(zb[1], zb[2]), max(zt[1], zt[2])
      local row = floor(za)
      while row < zz do
        local p, hh = { {}, {} }, {}
        local any = false
        for e = 1, 2 do
          p[e][1] = max(zb[e], row)
          p[e][2] = min(zt[e], row + 1)
          if p[e][2] < p[e][1] then p[e][2] = p[e][1] end
          any = any or p[e][2] > p[e][1]
          hh[e] = bot[e] / 16
        end
        if any then
          local function gv(zz_) return gv0 + (gv1 - gv0) * (zz_ - row) end
          local ga, gb = gu0 + (gu1 - gu0) * k / N, gu0 + (gu1 - gu0) * (k + 1) / N
          put(B, vtx(xs[1], hh[1], p[1][1], ga, gv(p[1][1]), SHADE_TOP),
            vtx(xs[2], hh[2], p[2][1], gb, gv(p[2][1]), SHADE_TOP),
            vtx(xs[2], hh[2], p[2][2], gb, gv(p[2][2]), SHADE_TOP),
            vtx(xs[1], hh[1], p[1][2], ga, gv(p[1][2]), SHADE_TOP))
        end
        row = row + 1
      end
    end
  end
end

-- where a cut tile's ground runs on under the rock beside it
local CUT_FILL = { { 0, 1 }, { -1, 1 }, { 1, 1 }, { -1, 0 }, { 1, 0 } }

--- A tree's cell where a wood climbs a step: the lower ground run on under it, its walls.
function Relief.treeStep(B, x, y)
  local g = B.cell(x, y)
  if not g then return end
  local c = B.cut(x, y)
  if not c then return end
  if c.variant == Relief.NO_VARIANT and c.ground then
    local u0, v0, u1, v1 = B.metatileUV(c.ground)
    if u0 then groundRunOn(B, x, y, c.foot / 16, u0, v0, u1, v1) end
  end
  local onRock = band(c.sides, Relief.FACE_TOP) ~= 0 and c.wall and c.wall ~= Relief.NO_FACE
  if onRock then
    local u0, v0, u1, v1 = B.metatileUV(c.wall)
    if u0 then Relief.reliefUV(B, x, y, g, g, u0, v0, u1, v1, false, 0, nil) end
  end
  if c.wall then Relief.cliffWalls(B, x, y, g, g, c.wall, nil, y, c.sides, false) end
end

--- A lifted cell (heights g), as the ground pass draws it: its drawing on its relief, a cut tile's
--- flat layer and the ground run on under it, its cliff walls and its back. Returns true when it
--- drew the cell (false: the cell is a model's, laid flat by the caller at Relief.centre).
function Relief.emitCell(B, x, y, g)
  B.lift, B.shift = 0, 0
  -- a building's cells are its model's: not under a model lower than a level on a face a level tall
  local top = B.modelTop and B.modelTop(x, y)
  if top then
    local lo, hi = g[0], g[0]
    for i = 1, 24 do lo, hi = min(lo, g[i]), max(hi, g[i]) end
    if not (top > 0 and top < 1 and hi - lo == 16) then return false end
  end
  local signGround = B.sign and B.sign(x, y)
  local sign = signGround ~= nil
  local c = (not sign) and B.cut(x, y) or nil
  local cut = c and c.variant or nil
  local foot, ground, wall, sides = c and c.foot / 16 or 0, c and c.ground, c and c.wall, c and c.sides or 0xFF
  local back = (c and band(sides, bor(Relief.GOES_ON, Relief.GOES_ON_SOUTH, Relief.THIN_DECK, Relief.CANOPY)) == 0)
    and ground or nil
  local backWall = wall
  local backStands = cut == Relief.NO_VARIANT
  local art                     -- { u0, v0, u1, v1 } of the drawing laid, nil: the cell's own
  local cutRows
  if sign then
    local u0, v0, u1, v1 = B.metatileUV(signGround)
    if u0 then art = { u0, v0, u1, v1 } end
  elseif not c and B.headGround then
    local hg = B.headGround(x, y)
    if hg then
      local u0, v0, u1, v1 = B.metatileUV(hg)
      if u0 then art = { u0, v0, u1, v1 } end
    end
  end
  -- a model's cell it stands over nothing of, its drawing on the face behind (a relief_bare
  -- house's roof): the cell's drawing less the model's quarters (VoxelBuildings_BareVariant)
  if B.bare then
    local u0, v0, u1, v1 = B.bare(x, y)
    if u0 then art = { u0, v0, u1, v1 } end
  end
  -- a canopy cleared: its variant on its relief over a plate of the ground under the crown
  local canopy, plate
  if c and cut ~= Relief.NO_VARIANT and band(sides, Relief.CANOPY) ~= 0 then
    local u0, v0, u1, v1 = B.cutUV(cut)
    if u0 then canopy = { u0, v0, u1, v1 } end
    if canopy and wall then
      local a0, b0, a1, b1 = B.metatileUV(wall)
      if a0 then plate = { a0, b0, a1, b1 } end
    end
    wall = nil
    cut = Relief.NO_VARIANT
  end
  if cut == Relief.NO_VARIANT then
    -- the ground behind a terrace's rim run on under the cell; the flank north of it (or south: a
    -- deck over a band) going on under it, a row on and a pixel down
    local from = band(sides, Relief.GOES_ON_SOUTH) ~= 0 and y + 1 or y - 1
    local north = B.sameMap(x, from) and B.cell(x, from) or nil
    if band(sides, bor(Relief.GOES_ON, Relief.GOES_ON_SOUTH)) ~= 0 and north then
      local nart, nrows
      local nc = B.cut(x, from)
      if band(sides, Relief.GOES_ON_FACE) ~= 0 and wall then
        local a0, b0, a1, b1 = B.metatileUV(wall)
        if a0 then nart = { a0, b0, a1, b1 } end
      elseif nc and nc.variant ~= Relief.NO_VARIANT then
        local a0, b0, a1, b1 = B.cutUV(nc.variant)
        if a0 then
          nart = { a0, b0, a1, b1 }
          local v = B.variant(nc.variant)
          nrows = v and v.rows
        end
      end
      B.lift = -1 / 16
      B.shift = B.lift
      local a = nart or { B.tileUV(x, from) }
      if a[1] then Relief.reliefUV(B, x, y, north, north, a[1], a[2], a[3], a[4], false, 0, nrows) end
      B.lift, B.shift = 0, 0
    end
    if band(sides, Relief.GOES_ON_FACE) ~= 0 then wall = nil end
    if ground then
      local u0, v0, u1, v1 = B.metatileUV(ground)
      if u0 then groundRunOn(B, x, y, foot, u0, v0, u1, v1) end
    end
    cut = nil
  elseif cut then
    local u0, v0, u1, v1 = B.cutUV(cut)
    if u0 and B.tileUV(x, y) then art = { u0, v0, u1, v1 } else cut = nil end
  end
  if cut then
    B.lift, B.shift = foot, foot
    -- its flat layer: the ground behind where the drawing has rock, the drawing elsewhere
    local o0, p0, o1, p1 = B.tileUV(x, y)
    local v = B.variant(cut)
    local gu0, gv0, gu1, gv1
    if ground then gu0, gv0, gu1, gv1 = B.metatileUV(ground) end
    if ground and v and gu0 then
      cutRows = v.rows
      cutGround(B, x, y, o0, p0, o1, p1, cutRows, { gu0, gv0, gu1, gv1 }, g, floor(foot * 16 + 0.5))
    else
      cutRows = nil
      cutGround(B, x, y, o0, p0, o1, p1, nil, nil, g, 0)
    end
    -- and the ground behind run on under the rock beside it, a pixel under its own level
    if gu0 then
      for k, f in ipairs(CUT_FILL) do
        local nx, ny = x + f[1], y + f[2]
        local n = B.sameMap(nx, ny) and B.cell(nx, ny) or nil
        local nt = -32768
        if n then for i = 0, 24 do nt = max(nt, n[i]) end end
        if n and nt > floor(foot * 16 + 0.5) then
          local nu0, nv0, nu1, nv1 = gu0, gv0, gu1, gv1
          local ncut = B.cut(nx, ny)
          if ncut and ncut.ground then
            local a0, b0, a1, b1 = B.metatileUV(ncut.ground)
            if a0 then nu0, nv0, nu1, nv1 = a0, b0, a1, b1 end
          end
          B.lift = foot - (1 + 0.125 * (k - 1)) / 16
          B.shift = B.lift
          runOn(B, nx, ny, nu0, nv0, nu1, nv1)
        end
      end
    end
    B.lift, B.shift = 0, 0
  end
  -- a tree's cell on the rock: the rock's face, not the leaves
  if not art and band(sides, Relief.FACE_TOP) ~= 0 and wall and wall ~= Relief.NO_FACE then
    local u0, v0, u1, v1 = B.metatileUV(wall)
    if u0 then art = { u0, v0, u1, v1 } end
  end
  if canopy then
    if plate then
      B.lift, B.shift = -1 / 16, 0
      Relief.reliefUV(B, x, y, g, g, plate[1], plate[2], plate[3], plate[4], false, 0, nil)
      B.lift, B.shift = 0, 0
    end
    art = canopy
  end
  local artY = sign and y + 1 or y
  local a = art or { B.tileUV(x, artY) }
  if a[1] then
    Relief.reliefUV(B, x, y, g, g, a[1], a[2], a[3], a[4], cut ~= nil, floor(foot * 16 + 0.5), cutRows)
  end
  if wall then Relief.cliffWalls(B, x, y, g, g, wall, art, artY, sides, back ~= nil and backStands) end
  if back then
    local faceT = (backWall and backWall < Relief.NO_FACE) and backWall or B.faceTile
    Relief.northFace(B, x, y, g, g, backStands and (faceT or back) or nil, back)
  end
  -- what stands on it: on a slope, at the ground under a sign's board (three quarters down)
  if B.standing then
    if Relief.isSlope(g) then
      local under = 3 * SIDE + 2
      B.standing(x, y, g[under] / 16, g[under] / 16)
    else
      B.standing(x, y, g[2 * SIDE + 2] / 16, g[2 * SIDE + 2] / 16)
    end
  end
  return true
end

return Relief
