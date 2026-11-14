-- Caves read as their tilesets build them (Battle Scene: Overworld): a cave's rock walls, ridges
-- and raised floors stand, counted as Emerald 3DS counts its mountains (docs/VOXEL_MOUNTAINS.md:
-- whole levels, one tile a level), from a table of the cave tileset's pieces.
--
-- The GBA draws a cave as it draws a mountain: a block of rock is its top, and below the top its
-- south face, one tile a level; its west and east sides are bands, a slope one tile across a
-- level; its north side faces away and is never drawn (the top's rim meets the ground behind).
-- Each piece is a shape over its cell, in levels over the cell's own base: flat 0; a face 1 at its
-- north edge to 0 at its south; a west side 0 at its west edge to 1 at its east, an east side the
-- other way; a face's end where a side turns into it (the lower of the two), an inside corner
-- where a face meets a side (the higher). Two neighbours stand at levels that join their shared
-- edge wherever both draw the same profile there (the drawing runs on); where the profiles part,
-- the edge is a step and a wall closes it (Relief.cliffWalls). A rim's north edge is always a
-- step: the top's back, closed by a wall straight up with the ground behind run on under it
-- (Relief.northFace). The levels are counted cell to cell from the cave's floor, level 0: no
-- heights are solved, none guessed.
--
-- WoobleView's own (no Emerald 3DS code: they leave their caves flat but Rusturf Tunnel, which
-- their hand marks give a belt). The pieces are a game's data (src/scene/games/<game>.lua,
-- `caves`): ids and roles only.
--
-- Caves.apply(model, input, C, tick) adds the caves to a relief model (src/scene/relief.lua's):
--   C = { layouts = { prefix, ... } (the layouts read as caves, by name), face (the metatile
--         whose drawing closes a step), ground (the floor's), stand (tiles a level the rock stands:
--         1 or none, as drawn; more, taller), sheer (its sides sheer walls, not ramps a tile across:
--         Caves.standing), pieces = { [metatile] = kind },
--         groups = { { layouts, pieces }, ... } (a tileset's own pieces, over the shared ones) }
--   kind: "F" a face; "W" / "E" a side falling west / east; "SW" / "SE" a face's end, the side
--         falling west / east; "FE" / "FW" an inside corner, the rock north and west / east;
--         "N" / "NW" / "NE" a rim (flat, its north edge / and its west or east edge a step); "TW" /
--         "TE" a top whose west / east edge is a step (a thin wall's, its side sheer); "void" the
--         dark past the rock; "HW" / "HE" a side's head (the rim's corner over a west / east side,
--         falling as it does, its north edge a step)
-- Caves.read(L, C) -> { [y * w + x] = level } and the shapes, for one layout (tests, probes).

local Caves = {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local SIDE, N, LEVEL = 5, 4, 16
local NO = 0xFFFF
local BLOCK_WALLS = 4
local DRAWN = 0x8000

-- each kind's shape: its height (levels over its base) at lattice point (i across, j down, 0-4)
local function face(i, j) return 1 - j / N end
local function west(i, j) return i / N end
local function east(i, j) return 1 - i / N end
local SHAPES = {
  F = face, W = west, E = east,
  SW = function(i, j) return min(face(i, j), west(i, j)) end,
  SE = function(i, j) return min(face(i, j), east(i, j)) end,
  FE = function(i, j) return max(face(i, j), east(i, j)) end,
  FW = function(i, j) return max(face(i, j), west(i, j)) end,
  -- a side's head: the rim's corner over a side, falling as the side does
  HW = west, HE = east,
}
local function flat() return 0 end
-- the edges a kind always steps at
local BREAKS = { N = { n = true }, NW = { n = true, w = true }, NE = { n = true, e = true },
                 TW = { w = true }, TE = { e = true }, HW = { n = true }, HE = { n = true } }
Caves.SHAPES, Caves.BREAKS = SHAPES, BREAKS

--- Whether the layout `name` is read as a cave.
function Caves.covers(C, name)
  for _, p in ipairs(C.layouts or {}) do
    if name:sub(1, #p) == p then return true end
  end
  return false
end

--- The pieces read in the layout `name`: the shared ones and its groups'.
function Caves.piecesFor(C, name)
  local out = {}
  for m, k in pairs(C.pieces or {}) do out[m] = k end
  for _, g in ipairs(C.groups or {}) do
    if Caves.covers(g, name) then for m, k in pairs(g.pieces) do out[m] = k end end
  end
  return out
end

--- One layout's levels: { [y * w + x] = level (the cell's base, levels) }, kinds { [y * w + x] =
--- kind or nil }, and the constraints that disagreed (a list of { x, y, side }). tick: optional,
--- called every row.
function Caves.read(L, C, tick)
  local w, h = L.w, L.h
  local pieces = Caves.piecesFor(C, L.name)
  local kinds = {}
  for i = 0, w * h - 1 do kinds[i] = pieces[L.blocks[i] % 1024] end
  local function shapeOf(k) return k and SHAPES[k] or flat end
  -- (the profile of a cell's edge: "e" its east edge top to bottom, "s" its south edge west to east...)
  local memo = {}
  local function profile(k, side)
    local key = (k or "") .. side
    if memo[key] then return memo[key] end
    local f, p = shapeOf(k), {}
    memo[key] = p
    for t = 0, N do
      if side == "e" then p[t] = f(N, t)
      elseif side == "w" then p[t] = f(0, t)
      elseif side == "s" then p[t] = f(t, N)
      else p[t] = f(t, 0) end
    end
    return p
  end
  -- the levels: union-find with offsets (level(c) = level(parent) + off)
  local parent, off = {}, {}
  for i = 0, w * h - 1 do parent[i], off[i] = i, 0 end
  local function find(i)
    local p = parent[i]
    if p == i then return i, 0 end
    local r, o = find(p)
    parent[i], off[i] = r, off[i] + o
    return r, off[i]
  end
  local conflicts = {}
  -- (a joins b: level(b) = level(a) + d)
  local function join(a, b, d, x, y, side)
    local ra, oa = find(a)
    local rb, ob = find(b)
    if ra == rb then
      if abs(ob - oa - d) > 1e-6 then conflicts[#conflicts + 1] = { x, y, side } end
      return
    end
    -- level(rb) = level(ra) + oa + d - ob
    parent[rb], off[rb] = ra, oa + d - ob
  end
  local function breaks(k, side)
    if k == "void" then return true end
    local b = k and BREAKS[k]
    return b and b[side] or false
  end
  local queued = { [0] = {}, [1] = {}, [2] = {} }
  for y = 0, h - 1 do
    if tick then tick() end
    for x = 0, w - 1 do
      local a = y * w + x
      local ka = kinds[a]
      -- east and south neighbours
      for _, nb in ipairs({ { x + 1, y, "e", "w" }, { x, y + 1, "s", "n" } }) do
        local nx, ny = nb[1], nb[2]
        if nx < w and ny < h then
          local b = ny * w + nx
          local kb = kinds[b]
          if not (breaks(ka, nb[3]) or breaks(kb, nb[4])) then
            local pa, pb = profile(ka, nb[3]), profile(kb, nb[4])
            local d, same = pa[0] - pb[0], true
            for t = 1, N do if abs(pa[t] - pb[t] - d) > 1e-6 then same = false; break end end
            if same then
              -- (by trust: the floor first, flat beside flat; then a piece beside the flat; then two pieces)
              local rank = (ka == nil and 1 or 0) + (kb == nil and 1 or 0)
              local q = queued[rank]
              q[#q + 1] = { a, b, d, x, y, nb[3] }
            end
          end
        end
      end
    end
  end
  for rank = 2, 0, -1 do
    for _, j in ipairs(queued[rank]) do join(j[1], j[2], j[3], j[4], j[5], j[6]) end
  end
  -- each part counted from its floor: the level most of its flat cells stand at is 0
  local counts = {}
  for i = 0, w * h - 1 do
    local r, o = find(i)
    if not kinds[i] then
      local t = counts[r]
      if not t then t = {}; counts[r] = t end
      t[o] = (t[o] or 0) + 1
    end
  end
  local zero = {}
  for r, t in pairs(counts) do
    local best, bn
    for o, n in pairs(t) do if not bn or n > bn or (n == bn and o < best) then best, bn = o, n end end
    zero[r] = best
  end
  local levels = {}
  for i = 0, w * h - 1 do
    local r, o = find(i)
    levels[i] = o - (zero[r] or 0)
  end
  -- the void (the dark past a cave's rock) stands as high as the rock it meets, spread through it
  local queue, head = {}, 1
  for i = 0, w * h - 1 do
    if kinds[i] == "void" then levels[i] = nil end
  end
  for i = 0, w * h - 1 do
    if kinds[i] == "void" then
      local x, y = i % w, floor(i / w)
      local top
      for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local nx, ny = x + d[1], y + d[2]
        local j = ny * w + nx
        if nx >= 0 and ny >= 0 and nx < w and ny < h and kinds[j] ~= "void" then
          local f, hi = SHAPES[kinds[j]] or flat, 0
          for t = 0, N do for s = 0, N do hi = max(hi, f(s, t)) end end
          local v = levels[j] + hi
          if not top or v > top then top = v end
        end
      end
      if top then levels[i] = top; queue[#queue + 1] = i end
    end
  end
  while head <= #queue do
    local i = queue[head]
    head = head + 1
    local x, y = i % w, floor(i / w)
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local nx, ny = x + d[1], y + d[2]
      local j = ny * w + nx
      if nx >= 0 and ny >= 0 and nx < w and ny < h and kinds[j] == "void" and levels[j] == nil then
        levels[j] = levels[i]
        queue[#queue + 1] = j
      end
    end
  end
  for i = 0, w * h - 1 do levels[i] = levels[i] or 0 end
  return levels, kinds, conflicts
end

--- The cell's lattice (pixels): its base and its kind's shape, as drawn.
function Caves.lattice(level, kind)
  local f = kind and SHAPES[kind] or flat
  local g = {}
  for j = 0, N do
    for i = 0, N do g[j * SIDE + i] = floor((level + f(i, j)) * LEVEL + 0.5) end
  end
  return g
end

-- the kinds a face is part of (a face, its ends, its inside corners) and the sides
local FACED = { F = true, SW = true, SE = true, FE = true, FW = true }
local SIDES = { W = true, E = true }

--- The cell's heights (pixels) standing `stand` tiles a level (C.stand; 1 or none: as drawn), its
--- sides sheer (C.sheer; neither: the lattice, as drawn).
--- Its drawing keeps its place (its depths: Caves.depths), and the rock stands taller under it:
--- a face's drawing a tile tall at the top of its wall (the wall below it closed by the face's
--- drawing a course a tile, Relief.cliffWalls), a face's end and inside corner as the face (their
--- side's step closed by a wall); a side a top, sheer at its outer edge; every top, rim and floor
--- `stand` tiles a level.
function Caves.standing(level, kind, stand, sheer)
  if (not stand or stand == 1) and not sheer then return Caves.lattice(level, kind) end
  stand = stand or 1
  local f = kind and SHAPES[kind] or flat
  local g = {}
  for j = 0, N do
    for i = 0, N do
      local v
      if FACED[kind] then v = stand * level + stand - 1 + face(i, j)
      elseif SIDES[kind] then v = stand * (level + 1)
      else v = stand * level end
      g[j * SIDE + i] = floor(v * LEVEL + 0.5)
    end
  end
  return g
end

--- The cell's depths (pixels: where each point of its drawing stands, Relief.DEPTHS) for heights
--- standing `stand` tiles a level: as drawn (Caves.lattice), but a side stands back with the top
--- it is the edge of (its top flat, its outer edge sheer) and a face's end or inside corner as its
--- face does (straight down its rows), so the rock's tops meet with no gap between them.
function Caves.depths(level, kind, stand, sheer)
  if (not stand or stand == 1) and not sheer then return Caves.lattice(level, kind) end
  local g = {}
  for j = 0, N do
    for i = 0, N do
      local v
      if FACED[kind] then v = level + face(i, j)
      elseif SIDES[kind] then v = level + 1
      else v = level end
      g[j * SIDE + i] = floor(v * LEVEL + 0.5)
    end
  end
  return g
end

--- The caves of `input` (src/scene/relief_input.lua's) added to `model`. Returns how many.
function Caves.apply(model, input, C, tick)
  local n = 0
  local ids = {}
  for id, L in pairs(input.layouts) do
    if Caves.covers(C, L.name) and not model.layouts[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local L = input.layouts[id]
    local w, h = L.w, L.h
    local levels, kinds = Caves.read(L, C, tick)
    -- (heights standing as C.stand says; depths where the drawing puts each point)
    local grids, depths = {}, {}
    for i = 0, w * h - 1 do
      grids[i] = Caves.standing(levels[i], kinds[i], C.stand, C.sheer)
      depths[i] = Caves.depths(levels[i], kinds[i], C.stand, C.sheer)
    end
    local cells = {}
    model.depths = model.depths or {}
    for i = 0, w * h - 1 do
      local g, s = grids[i], depths[i]
      local apart = false
      for k = 0, SIDE * SIDE - 1 do
        if g[k] ~= 0 or s[k] ~= 0 then cells[i] = g end
        if g[k] ~= s[k] then apart = true end
      end
      if apart then model.depths[id * 65536 + (i % w) * 256 + floor(i / w)] = s end
    end
    -- the records: a wall wherever a cell's west, east or south edge stands over its neighbour's;
    -- a rim's back, the ground behind run on under it
    for y = 0, h - 1 do
      if tick then tick() end
      for x = 0, w - 1 do
        local i = y * w + x
        local g = grids[i]
        local wall = false
        for _, d in ipairs({ { x - 1, y, "w" }, { x + 1, y, "e" }, { x, y + 1, "s" } }) do
          local nx, ny = d[1], d[2]
          if nx >= 0 and ny >= 0 and nx < w and ny < h then
            local o = grids[ny * w + nx]
            for t = 0, N do
              local a, b
              if d[3] == "w" then a, b = g[t * SIDE], o[t * SIDE + N]
              elseif d[3] == "e" then a, b = g[t * SIDE + N], o[t * SIDE]
              else a, b = g[N * SIDE + t], o[t] end
              if a - b > 0.5 then wall = true; break end
            end
          end
        end
        local back, foot = nil, 0
        local br = kinds[i] and BREAKS[kinds[i]]
        if br and br.n and y > 0 then
          local o = grids[i - w]
          local lo = math.huge
          for t = 0, N do lo = min(lo, o[N * SIDE + t]) end
          local hi = -math.huge
          for t = 0, N do hi = max(hi, g[t]) end
          if hi - lo >= LEVEL then
            back, foot = L.blocks[i - w] % 1024, lo
            if kinds[i - w] then back = C.ground end
          end
        end
        if wall or back then
          model.cuts[id * 65536 + x * 256 + y] = { NO, foot, back or NO, C.face or NO, wall and 0xFF or 0,
                                                   wall and BLOCK_WALLS or 0 }
          cells[i] = cells[i] or g
        end
      end
    end
    if next(cells) then
      model.layouts[id] = { w = w, h = h, flags = DRAWN, base = 0, belt = 0, ease = 0, level = false, cells = cells }
      n = n + 1
    end
    if tick then tick() end
  end
  return n
end

return Caves
