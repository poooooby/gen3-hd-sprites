-- Mountains read as the tileset builds them (Battle Scene: Overworld; src/scene/relief_solve.lua's
-- part): Emerald 3DS's voxel_terraces.py, the pass after the export that rebuilds the chosen
-- groups of maps terrace by terrace - whole levels, one tile a level. This file: how a group's
-- cells are read (their kinds off their pixels), the terraces and their levels, the level each
-- rock cell hangs from, the pieces (face, band, corner, top) settled together. Its continuations:
-- src/scene/relief_terraces_fit.lua (the pieces made to meet, ledges, hand marks, the solve) and
-- src/scene/relief_terraces_out.lua (the records and the merge into the relief).
--
-- Adapted from Emerald 3DS (3ds_port/scripts/voxel_terraces.py, by Zallax and contributors, CC
-- BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes here: written in
-- Lua over src/scene/relief_solve.lua's reading of the cartridge; every rule, constant and
-- tie-break the same (Python's sort orders, set orders and rounding reproduced), so the result is
-- the generator's byte for byte. The buildings' cells (their models' footprints, which the
-- generator reads off its buildings.bin) come in through opt.models.
--
-- Cells are keys (Solve.K); where Python sorts cells it sorts (x, y) tuples, x first (T.sortXY),
-- or by (y, x) where the generator says so (T.sortYX).

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local bit = require("bit")
local band, bor, rshift, lshift, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bnot
local byte, char = string.byte, string.char

return function(S)
  local Solve, Art = S.Solve, S.Art
  local K, KX, KY = Solve.K, Solve.KX, Solve.KY
  local C, SETS = Solve.C, Solve.SETS
  local LEVEL = C.LEVEL
  local N = 4
  local counter, mostCommon = Solve.counter, Solve.mostCommon
  local tick = S.tick
  -- (a tick every so many cells of a long loop: the pass is sliced in a coroutine)
  local tn = 0
  local function tickN()
    tn = tn + 1
    if tn % 256 == 0 then tick() end
  end
  local T = {}
  S.T = T
  T.tickN = tickN
  T.N, T.LEVEL = N, LEVEL

  -- ── constants ────────────────────────────────────────────────────────────────

  local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
  local ROCK_TOP, ROCK_RIM, ROCK_FACE, ROCK_FLECK, ROCK_ALL =
    Solve.ROCK_TOP, Solve.ROCK_RIM, Solve.ROCK_FACE, Solve.ROCK_FLECK, Solve.ROCK_ALL
  local TOP_COLOURS = {}
  for k in pairs(ROCK_TOP) do TOP_COLOURS[k] = true end
  for k in pairs(ROCK_RIM) do TOP_COLOURS[k] = true end
  local FACE_COLOURS, FLECK = ROCK_FACE, ROCK_FLECK
  local BAND_WEST = set({ 0x070, 0x073, 0x088, 0x06b, 0x080, 0x083, 0x068, 0x172, 0x175, 0x177, 0x17a })
  local BAND_EAST = set({ 0x072, 0x075, 0x0a2, 0x08a, 0x06d, 0x082, 0x084, 0x06a, 0x174, 0x176, 0x17c, 0x0a4 })
  local HEADS = { [0x068] = "W", [0x083] = "W", [0x080] = "W", [0x06a] = "E", [0x084] = "E", [0x082] = "E" }
  local HEADS_SORTED = { 0x068, 0x06a, 0x080, 0x082, 0x083, 0x084 }
  local ON_TOP = SETS.BOULDER
  local BOULDER_FOOT = set({ 0x09b, 0x09c })
  local BOULDER_HEAD = set({ 0x093, 0x094 })
  local LOOSE = set({ 0x0df, 0x0e0, 0x0e1, 0x0e2 })
  local CARVED_STEPS = set({ 0x0e8, 0x0e9, 0x0ea, 0x0eb })
  local UPPER_END = set({ 0x074, 0x089 })
  local LOWER_END = set({ 0x07d, 0x07b, 0x078, 0x092, 0x090 })
  local MOUNTAIN = {}
  for m = 0x064, 0x0bf do MOUNTAIN[m] = true end
  for m = 0x172, 0x192 do MOUNTAIN[m] = true end
  for _, m in ipairs({ 0x1a0, 0x1a8, 0x1b0, 0x1f0, 0x1f1 }) do MOUNTAIN[m] = true end
  for m in pairs(SETS.FACE_SOUTH) do MOUNTAIN[m] = true end
  for m in pairs(SETS.BOULDER) do MOUNTAIN[m] = true end
  for m in pairs(SETS.DIRT) do MOUNTAIN[m] = nil end
  local MOUNTAIN_SORTED = {}        -- sorted(MOUNTAIN), the General's (< 0x200)
  for m in pairs(MOUNTAIN) do if m < 0x200 then MOUNTAIN_SORTED[#MOUNTAIN_SORTED + 1] = m end end
  table.sort(MOUNTAIN_SORTED)
  local GROUND, TOP, ROCK, UNKNOWN = "G", "T", "R", "?"
  local WORLD = -1                  -- the level the world is counted from (a key no cell has)
  local MAX_FALL = 3 * 16
  local ANCHOR_MIN = 12
  local TWIN_MATCH, HEAD_MATCH = 0.85, 0.6
  T.BAND_WEST, T.BAND_EAST, T.HEADS, T.ON_TOP, T.BOULDER_FOOT, T.BOULDER_HEAD = BAND_WEST, BAND_EAST, HEADS, ON_TOP, BOULDER_FOOT, BOULDER_HEAD
  T.LOOSE, T.CARVED_STEPS, T.UPPER_END, T.LOWER_END, T.MOUNTAIN, T.MOUNTAIN_SORTED = LOOSE, CARVED_STEPS, UPPER_END, LOWER_END, MOUNTAIN, MOUNTAIN_SORTED
  T.GROUND, T.TOP, T.ROCK, T.UNKNOWN, T.WORLD = GROUND, TOP, ROCK, UNKNOWN, WORLD
  T.TOP_COLOURS, T.FACE_COLOURS = TOP_COLOURS, FACE_COLOURS
  local GENERAL = "general"
  T.GENERAL = GENERAL

  -- ── small helpers ────────────────────────────────────────────────────────────

  -- Python's (x, y) tuple order
  local function cmpXY(a, b)
    local ax, bx = a % 16384, b % 16384
    if ax ~= bx then return ax < bx end
    return a < b
  end
  T.cmpXY = cmpXY
  local function keysOf(tbl)
    local out = {}
    for k in pairs(tbl) do out[#out + 1] = k end
    return out
  end
  T.keysOf = keysOf
  local function sortXY(list) table.sort(list, cmpXY) return list end
  local function sortYX(list) table.sort(list) return list end
  T.sortXY, T.sortYX = sortXY, sortYX
  local function sortedXY(tbl) return sortXY(keysOf(tbl)) end
  local function sortedYX(tbl) return sortYX(keysOf(tbl)) end
  T.sortedXY, T.sortedYX = sortedXY, sortedYX
  local function count(tbl) local n = 0 for _ in pairs(tbl) do n = n + 1 end return n end
  T.count = count
  local function copyset(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
  T.copyset = copyset
  local tup2 = {}
  local function hashCell(k)
    tup2[1], tup2[2] = KX(k), KY(k)
    return Art.hashTuple(tup2, 2)
  end
  T.hashCell = hashCell
  --- list(set(cells)) as Python orders it
  local function pySetCells(list) return Art.setOrder(list, hashCell) end
  T.pySetCells = pySetCells
  local function four(k)
    local x, y = KX(k), KY(k)
    return K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1)
  end
  T.four = four
  local function pyround(x) return Art.round(x) end
  T.pyround = pyround

  -- a 5x5 grid: g[j][i]
  local function fill(v)
    local g = {}
    for j = 0, N do
      local row = {}
      for i = 0, N do row[i] = v end
      g[j] = row
    end
    return g
  end
  T.fill = fill
  local function gmax(g) local m = -math.huge for j = 0, N do for i = 0, N do if g[j][i] > m then m = g[j][i] end end end return m end
  local function gmin(g) local m = math.huge for j = 0, N do for i = 0, N do if g[j][i] < m then m = g[j][i] end end end return m end
  T.gmax, T.gmin = gmax, gmin
  local function lmax(l) local m = -math.huge for i = 0, #l do if l[i] ~= nil and l[i] > m then m = l[i] end end return m end
  local function lmin(l) local m = math.huge for i = 0, #l do if l[i] ~= nil and l[i] < m then m = l[i] end end return m end
  T.lmax, T.lmin = lmax, lmin
  --- the five heights along one edge, west to east / north to south (0..N)
  local function edge(grid, side)
    if side == "N" then return grid[0] end
    if side == "S" then return grid[N] end
    local out = {}
    local i = side == "W" and 0 or N
    for j = 0, N do out[j] = grid[j][i] end
    return out
  end
  T.edge = edge
  local function emax(e) local m = e[0] for i = 1, N do if e[i] > m then m = e[i] end end return m end
  local function emin(e) local m = e[0] for i = 1, N do if e[i] < m then m = e[i] end end return m end
  T.emax, T.emin = emax, emin
  local function level5(v) local e = {} for i = 0, N do e[i] = v end return e end
  T.level5 = level5
  local function gcopy(g) local o = {} for j = 0, N do local r = {} for i = 0, N do r[i] = g[j][i] end o[j] = r end return o end
  T.gcopy = gcopy

  --- a piece { kind, top }: equal?
  local function pieceEq(a, b)
    if a == nil or b == nil then return a == b end
    return a[1] == b[1] and a[2] == b[2]
  end
  T.pieceEq = pieceEq

  -- ── 1. cells ─────────────────────────────────────────────────────────────────

  -- caches keyed by the art (its drawing): what a tile's pixels say
  local classesOf = setmetatable({}, { __mode = "k" })
  local function cacheOf(store, art)
    local t = store[art]
    if not t then t = {}; store[art] = t end
    return t
  end
  --- 16 x 16 of 'T' (top or rim), 'F' (face) or 'G' (anything else) for metatile m: { s = the
  --- 256 classes as a string, T, F, G counts }. A fleck (a colour of both) goes with the most of
  --- its neighbours.
  local function pixelClasses(art, m)
    local known = cacheOf(classesOf, art)
    local hit = known[m]
    if hit then return hit end
    local img = art.cellImage(m)
    local cls = {}
    for k = 0, 255 do cls[k] = "G" end
    local flat = false
    if m >= 0x200 then
      flat = true
      local c0 = img[0]
      for k = 1, 255 do if img[k] ~= c0 then flat = false; break end end
    end
    if flat then
      if FACE_COLOURS[img[0]] then for k = 0, 255 do cls[k] = "T" end end
    else
      local flecks, isFleck = {}, {}
      for k = 0, 255 do
        local c = img[k]
        if TOP_COLOURS[c] then cls[k] = "T"
        elseif FACE_COLOURS[c] then cls[k] = "F"
        elseif FLECK[c] then flecks[#flecks + 1] = k; isFleck[k] = true end
      end
      for _, k in ipairs(flecks) do
        local x, y = k % 16, floor(k / 16)
        local votes = counter()
        for ny = max(0, y - 1), min(15, y + 1) do
          for nx = max(0, x - 1), min(15, x + 1) do
            local kk = ny * 16 + nx
            if not isFleck[kk] then votes.add(cls[kk]) end
          end
        end
        -- votes.pop("G"): the most of T and F; T when neither
        local best, bn
        for _, kk in ipairs(votes.order) do
          if kk ~= "G" and (not bn or votes.n[kk] > bn) then best, bn = kk, votes.n[kk] end
        end
        cls[k] = best or "T"
      end
    end
    local nT, nF, nG = 0, 0, 0
    for k = 0, 255 do
      local c = cls[k]
      if c == "T" then nT = nT + 1 elseif c == "F" then nF = nF + 1 else nG = nG + 1 end
    end
    local out = { s = table.concat(cls, "", 0, 255), T = nT, F = nF, G = nG }
    known[m] = out
    return out
  end
  T.pixelClasses = pixelClasses
  local function clsAt(cls, x, y) return byte(cls.s, y * 16 + x + 1) end
  local CT, CF, CG = byte("T"), byte("F"), byte("G")
  T.clsAt, T.CT, T.CF, T.CG = clsAt, CT, CF, CG
  -- counts over rows y0..y1 of class c
  local function clsCount(cls, c, y0, y1, x0, x1)
    local n = 0
    for y = y0, y1 do
      for x = x0 or 0, x1 or 15 do if byte(cls.s, y * 16 + x + 1) == c then n = n + 1 end end
    end
    return n
  end
  T.clsCount = clsCount

  local rimPixelsOf = setmetatable({}, { __mode = "k" })
  local function rimPixels(art, m)
    local known = cacheOf(rimPixelsOf, art)
    local v = known[m]
    if v == nil then
      local img = art.cellImage(m)
      v = 0
      for y = 0, 5 do for x = 0, 15 do if ROCK_RIM[img[y * 16 + x]] then v = v + 1 end end end
      known[m] = v
    end
    return v
  end
  T.rimPixels = rimPixels

  local function sameImage(a, b)
    for k = 0, 255 do if a[k] ~= b[k] then return false end end
    return true
  end
  T.sameImage = sameImage
  local function aliased(art) return art.alias ~= nil end
  T.aliased = aliased

  local twinsOf = setmetatable({}, { __mode = "k" })
  --- The General tileset's mountain tile a map's own tile is drawn as, or m itself.
  local function twin(art, m)
    if m < 0x200 then return m end
    local known = cacheOf(twinsOf, art)
    local hit = known[m]
    if hit then return hit end
    local mine = pixelClasses(art, m)
    local rockN = 256 - mine.G
    local best, score = m, 0.0
    local drawing = art.cellImage(m)
    local exact
    if art.primary == GENERAL then
      for _, r in ipairs(MOUNTAIN_SORTED) do
        if sameImage(art.cellImage(r), drawing) then exact = r; break end
      end
    end
    if exact then
      best, score = exact, 1.0
    elseif rockN >= 64 and art.primary == GENERAL then
      local far
      for _, r in ipairs(MOUNTAIN_SORTED) do
        local theirs = pixelClasses(art, r)
        local both, same = 0, 0
        local ts, ms = theirs.s, mine.s
        for k = 1, 256 do
          local a, b = byte(ts, k), byte(ms, k)
          if a ~= CG or b ~= CG then
            both = both + 1
            if a == b then same = same + 1 end
          end
        end
        local ratio = same / both
        if not (ratio < score or ratio < TWIN_MATCH) then
          local img2 = art.cellImage(r)
          local d = 0
          for k = 0, 255 do
            local p, q = drawing[k], img2[k]
            d = d + abs(floor(p / 65536) - floor(q / 65536)) + abs(floor(p / 256) % 256 - floor(q / 256) % 256)
              + abs(p % 256 - q % 256)
          end
          if ratio > score or d < far then best, score, far = r, ratio, d end
        end
      end
    end
    if best == m and aliased(art) then
      local faceN = mine.F
      for _, r in ipairs(HEADS_SORTED) do
        local cls = pixelClasses(art, r)
        local inter, uni = 0, 0
        for k = 1, 256 do
          local a, b = byte(mine.s, k) == CF, byte(cls.s, k) == CF
          if a and b then inter = inter + 1 end
          if a or b then uni = uni + 1 end
        end
        local same = inter / (uni > 0 and uni or 1)
        if same > score and same >= HEAD_MATCH then best, score = r, same end
      end
    end
    known[m] = best
    return best
  end
  T.twin = twin

  local copiesOf = setmetatable({}, { __mode = "k" })
  --- The General's mountain tile whose rock tile m draws pixel for pixel, or m.
  local function drawnCopy(art, m)
    if m >= 0x200 or MOUNTAIN[m] or art.primary ~= GENERAL then return m end
    local known = cacheOf(copiesOf, art)
    local hit = known[m]
    if hit then return hit end
    local function rock(t)
      local img, cls = art.cellImage(t), pixelClasses(art, t)
      local out, n = {}, 0
      for k = 0, 255 do
        if byte(cls.s, k + 1) ~= CG then out[k] = img[k]; n = n + 1 end
      end
      return out, n
    end
    local mine, n = rock(m)
    local result = m
    if n >= 64 then
      for _, r in ipairs(MOUNTAIN_SORTED) do
        local theirs, tn = rock(r)
        if tn == n then
          local same = true
          for k, v in pairs(mine) do if theirs[k] ~= v then same = false; break end end
          if same then result = r; break end
        end
      end
    end
    known[m] = result
    return result
  end
  T.drawnCopy = drawnCopy

  -- gr.terrace_art(lid): the alias reading of an ALIAS_TERRACES map, else layout_art
  local ALIAS_BOTH = {}
  for k in pairs(Art.ALIAS_LAYOUTS) do ALIAS_BOTH[k] = true end
  for k in pairs(Art.ALIAS_TERRACES) do ALIAS_BOTH[k] = true end
  local terraceArts = {}
  local function terraceArt(lid)
    if not Art.ALIAS_TERRACES[lid] then return S.layoutArt(lid) end
    local a = terraceArts[lid]
    if a then return a end
    local al = S.aliasOf(lid, Art.ALIAS_TERRACES)
    a = al and Art.aliasArt(S.vbArt(lid), al) or S.vbArt(lid)
    terraceArts[lid] = a
    return a
  end
  T.terraceArt = terraceArt
  function T.terraceOwnId(lid, m)
    local a = S.aliasOf(lid, ALIAS_BOTH)
    return a and a.back[m] or m
  end

  -- the group's cells read (Cells)
  local Cells = {}
  Cells.__index = Cells
  T.Cells = Cells

  local function layoutEntry(lid) return S.input.byName[lid] end
  T.layoutEntry = layoutEntry

  function T.newCells(members)
    local self = setmetatable({}, Cells)
    self.members = members
    self.id = members[1][1]
    self.arts, self.roles_of = {}, {}
    self.src = {}
    self.kind, self.kindOrder, self.band, self.rim = {}, {}, {}, {}
    self.ledges, self.keep, self.keepOrder = {}, {}, {}
    self.jumps = {}
    self.props, self.prop_of = {}, {}
    self.walked_tops = {}
    self.models = T.modelled(members)
    self._over_water = {}
    self._drawn_on = setmetatable({}, { __mode = "k" })
    local MB = S.input.behaviours
    local berry = MB.MB_BERRY_TREE_SOIL
    self.bridge_codes = {}
    for name, v in pairs(MB) do
      if name:sub(1, 14) == "MB_BRIDGE_OVER" then self.bridge_codes[v] = true end
    end
    self.bridges = {}
    local falls = MB.MB_WATERFALL
    self.falls = {}
    local puddle = MB.MB_PUDDLE
    self.puddles = {}
    self.mud = MB.MB_MUDDY_SLOPE
    for _, mem in ipairs(members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local art = terraceArt(lid)
      self.arts[lid] = art
      local roles = S.openRoles(lid)
      self.roles_of[lid] = roles
      local ledges = S.ledgeCells(roles)
      local props = S.propsIn(lid)
      for k, f in ipairs(T.findPropsSorted(lid)) do
        for _, c in ipairs(T.propCellsOf(f[1], f[2], f[3])) do
          self.prop_of[K(c[1] + ox, c[2] + oy)] = lid .. "|" .. (k - 1)
        end
      end
      for y = 0, art.h - 1 do
        for x = 0, art.w - 1 do
          tickN()
          local cell = K(x + ox, y + oy)
          if not self.src[cell] then
            self.src[cell] = { lid, x, y }
            local m = art.metatile(x, y)
            local lk = K(x, y)
            local ledge = ledges[lk]
            if ledge then
              self.ledges[cell] = true
              local dirs = {}
              for i, d in ipairs(ledge[3]) do dirs[i] = { d[1], d[2] } end
              self.jumps[cell] = dirs
            end
            local b = roles.behaviour(x, y)
            if self.bridge_codes[b] then self.bridges[cell] = true end
            if b == falls then self.falls[cell] = true end
            if b == puddle then self.puddles[cell] = true end
            if ledge or b == berry or SETS.DIRT[m] then
              if not self.keep[cell] then self.keepOrder[#self.keepOrder + 1] = cell end
              self.keep[cell] = true
            end
            self:_read(cell, art, roles, m, ledge ~= nil, props[lk] ~= nil)
            if self.keep[cell] and self.kind[cell] == ROCK then
              self.kind[cell] = GROUND
              self.band[cell] = nil
              self.rim[cell] = nil
            end
          end
        end
        tick()
      end
    end
    -- a walkway of treads across the water: a deck, level with the banks it joins
    self.lone_bridge = {}
    for _, cell in ipairs(sortedXY(self.kind)) do
      if self:role(cell) == "stair" and not self.bridges[cell] then
        local x, y = KX(cell), KY(cell)
        local reach, nreach = {}, 0
        for _, side in ipairs({ -1, 1 }) do
          for d = 1, 3 do
            local n = K(x + side * d, y)
            if self:water(n) then
              reach[side] = d
              nreach = nreach + 1
              break
            end
            local r = self.src[n] and self:role(n)
            if not self.src[n] or (r ~= "floor" and r ~= "stair") then break end
          end
        end
        if nreach == 2 then
          for _, side in ipairs({ -1, 1 }) do
            for k = 0, reach[side] - 1 do
              local n = K(x + side * k, y)
              self.bridges[n] = true
              self.kind[n] = GROUND
              self.band[n] = nil
            end
          end
        end
      end
    end
    for b in pairs(self.bridges) do
      local x, y = KX(b), KY(b)
      if not self.bridges[K(x - 1, y)] and not self.bridges[K(x + 1, y)] then self.lone_bridge[b] = true end
    end
    for b in pairs(self.lone_bridge) do self.bridges[b] = nil end
    self.cheeks = {}
    self.rough = {}
    -- the cheeks of stairs climbing a face
    for _, cell in ipairs(self.kindOrder) do
      local k = self.kind[cell]
      if k == GROUND and self:role(cell) ~= "floor" then
        local x, y = KX(cell), KY(cell)
        local beside = false
        for _, n in ipairs({ K(x - 1, y), K(x + 1, y) }) do
          if self.kind[n] == ROCK and self:is_stair(n) then beside = true end
        end
        if beside then
          local cls = pixelClasses(self:art(cell), self:metatile(cell))
          if cls.F + cls.T >= 0.4 * 256 then
            self.kind[cell] = ROCK
            self.cheeks[cell] = true
          end
        end
      end
    end
    -- a boulder drawn wide
    self.wide_boulder = {}
    for _, cell in ipairs(self.kindOrder) do
      if self:metatile(cell) == 0x093 then
        local x, y = KX(cell), KY(cell)
        local e = x + 1
        while self.src[K(e, y)] do
          local mm = self:metatile(K(e, y))
          if BOULDER_HEAD[mm] or BOULDER_FOOT[mm] then break end
          e = e + 1
        end
        local ends = { { K(e, y), 0x094 }, { K(x, y + 1), 0x09b }, { K(e, y + 1), 0x09c } }
        local bad = e == x + 1
        if not bad then
          for _, pr in ipairs(ends) do
            if not self.src[pr[1]] or self:metatile(pr[1]) ~= pr[2] then bad = true end
          end
        end
        if not bad then
          local allTop = true
          for i = x + 1, e - 1 do
            for _, j in ipairs({ y, y + 1 }) do
              local kk = self.kind[K(i, j)]
              if kk ~= TOP and kk ~= ROCK then allTop = false end
            end
          end
          if allTop then
            for i = x, e do
              for _, j in ipairs({ y, y + 1 }) do
                local cc = K(i, j)
                self.kind[cc] = TOP
                self.rim[cc] = nil
                self.wide_boulder[cc] = true
              end
            end
          end
        end
      end
    end
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for cell in pairs(self.src) do
      local x, y = KX(cell), KY(cell)
      minx, maxx, miny, maxy = min(minx, x), max(maxx, x), min(miny, y), max(maxy, y)
    end
    self.xs = { start = minx, stop = maxx + 1 }
    self.ys = { start = miny, stop = maxy + 1 }
    return self
  end

  function Cells:_read(cell, art, roles, m, ledge, prop)
    local s = self.src[cell]
    local lx, ly = s[2], s[3]
    local cls = pixelClasses(art, m)
    local function rockBeside()
      for _, nx in ipairs({ lx - 1, lx + 1 }) do
        if nx >= 0 and nx < art.w then
          local nc = pixelClasses(art, art.metatile(nx, ly))
          if nc.F + nc.T >= 128 then return true end
        end
      end
      return false
    end
    local own = m
    local warp = roles.warps[lx .. "," .. ly]
    if not (m >= 0x200 and warp) or rockBeside() then m = twin(art, m) end
    local t = cls.T / 256.0
    local f = cls.F / 256.0
    local role = roles.role_at(lx, ly)
    if role == "water" and roles.blocked(lx, ly) and drawnCopy(art, m) ~= m then
      m, role = drawnCopy(art, m), "cliff"
    end
    local isAl = aliased(art)
    local alien = isAl and m >= 0x200 and not MOUNTAIN[m]
    if isAl and own >= 0x200 and role == "floor" then
      alien = true
      if MOUNTAIN[m] and f < 0.08 and t >= 0.45 then
        self.walked_tops[cell] = true
      elseif f == 0 then
        local allT = true
        for x = 0, 15 do if byte(cls.s, x + 1) ~= CT then allT = false; break end end
        if allT then self.walked_tops[cell] = true end
      end
    end
    local tree = role == "tree" and not (MOUNTAIN[m] and t + f >= 0.25)
    if prop then self.props[cell] = true end
    local k
    local b = roles.behaviour(lx, ly)
    if tree or prop or LOOSE[m] then
      k = UNKNOWN
    elseif HEADS[m] and not ledge and ly + 1 < art.h and T.topTile(art, art.metatile(lx, ly + 1))
        and not (isAl and rimPixels(art, art.metatile(lx, ly + 1)) >= 3) then
      k = TOP
    elseif (BAND_WEST[m] or BAND_EAST[m]) and not ledge then
      k = ROCK
      self.band[cell] = BAND_WEST[m] and "W" or "E"
    elseif ledge or role == "water" or role == "ledge" or self.bridges[cell] then
      k = GROUND
    elseif (role == "stair" or b == self.mud or (role == "floor" and CARVED_STEPS[art.metatile(lx, ly)]))
        and T.inFace(art, lx, ly, false) then
      k = ROCK
    elseif role == "floor" and warp and T.inFace(art, lx, ly, true) then
      k = ROCK
    elseif role == "floor" and MOUNTAIN[m] and f >= 0.5 and not alien then
      k = warp and ROCK or TOP
    elseif role == "floor" and MOUNTAIN[m] and f < 0.08 and t >= 0.45 and not alien then
      k = TOP
    elseif role == "wall" and not MOUNTAIN[m] and t + f < 0.9 and clsCount(cls, CG, 0, 3) <= 4 then
      k = UNKNOWN
    elseif role == "floor" or role == "stair" or role == "signpost" or (not MOUNTAIN[m] and t + f < 0.9) or alien then
      k = GROUND
    elseif BOULDER_FOOT[m] and ly > 0 then
      local tw = twin(art, art.metatile(lx, ly - 1))
      if BAND_WEST[tw] or BAND_EAST[tw] then
        k = ROCK
      elseif ON_TOP[m] then
        k = TOP
      elseif t + f < 0.25 then
        k = GROUND
      elseif clsCount(cls, CF, 2, 15) < 0.08 * 256 and t >= 0.45 then
        k = TOP
      else
        k = ROCK
      end
    elseif ON_TOP[m] then
      k = TOP
    elseif t + f < 0.25 then
      k = GROUND
    elseif clsCount(cls, CF, 2, 15) < 0.08 * 256 and t >= 0.45 then
      k = TOP
    else
      k = ROCK
    end
    self.kind[cell] = k
    self.kindOrder[#self.kindOrder + 1] = cell
    if k == TOP or k == ROCK or (self.walked_tops[cell] and MOUNTAIN[m]) then
      local gTop = clsCount(cls, CG, 0, 3)
      if rimPixels(art, m) >= 3 or gTop >= 12 then self.rim[cell] = true end
    end
  end

  function Cells:art(cell) return self.arts[self.src[cell][1]] end
  function Cells:is_stair(cell)
    return self:role(cell) == "stair" or (self.kind[cell] == ROCK and CARVED_STEPS[self:metatile(cell)] == true)
  end
  function Cells:on_top(cell) return ON_TOP[self:metatile(cell)] == true and not self.wide_boulder[cell] end
  function Cells:at_edge(cell)
    local s = self.src[cell]
    local art = self.arts[s[1]]
    return s[2] == 0 or s[2] == art.w - 1 or s[3] == 0 or s[3] == art.h - 1
  end
  function Cells:metatile(cell)
    local s = self.src[cell]
    return self.arts[s[1]].metatile(s[2], s[3])
  end
  function Cells:role_id(cell)
    local s = self.src[cell]
    local art = self.arts[s[1]]
    return twin(art, art.metatile(s[2], s[3]))
  end
  function Cells:role(cell)
    if self.puddles[cell] then return "floor" end
    local s = self.src[cell]
    return self.roles_of[s[1]].role_at(s[2], s[3])
  end
  function Cells:_lower(cell)
    local art = self:art(cell)
    return art.cellImage(self:metatile(cell), true)
  end
  function Cells:water(cell)
    if not self.src[cell] then return false end
    if self:role(cell) == "water" or self.lone_bridge[cell] then return true end
    local v = self._over_water[cell]
    if v == nil then
      v = false
      if self:crown(cell) then
        local mine = self:_lower(cell)
        local a, b, c, d = four(cell)
        for _, n in ipairs({ a, b, c, d }) do
          if self.src[n] and self:role(n) == "water" and sameImage(mine, self:_lower(n)) then v = true; break end
        end
      end
      self._over_water[cell] = v
    end
    return v
  end
  function Cells:crown(cell)
    if not self.src[cell] then return false end
    local s = self.src[cell]
    local lid, x, y = s[1], s[2], s[3]
    local art, roles = self.arts[lid], self.roles_of[lid]
    if y + 1 >= art.h or roles.role_at(x, y) == "tree" or roles.role_at(x, y + 1) ~= "tree" then return false end
    local m = art.metatile(x, y)
    local hi, lo = art.cellImage(m), art.cellImage(m, true)
    local n = 0
    for k = 0, 255 do if hi[k] ~= lo[k] then n = n + 1 end end
    return n >= 64
  end
  function Cells:muddy(cell)
    if not self.src[cell] then return false end
    local s = self.src[cell]
    return self.mud ~= nil and self.roles_of[s[1]].behaviour(s[2], s[3]) == self.mud
  end
  function Cells:drawn_on(cell)
    local art = self:art(cell)
    local m = self:metatile(cell)
    local known = self._drawn_on[art]
    if not known then known = {}; self._drawn_on[art] = known end
    local v = known[m]
    if v == nil then
      local img = art.cellImage(m, true)
      local nT, nF = 0, 0
      for k = 0, 255 do
        if TOP_COLOURS[img[k]] then nT = nT + 1 elseif FACE_COLOURS[img[k]] then nF = nF + 1 end
      end
      v = nT >= 128 and "T" or nF >= 128 and "F" or "G"
      known[m] = v
    end
    return v
  end
  function Cells:tree_on_rock(cell)
    return self.kind[cell] == UNKNOWN and self:role(cell) == "tree" and self:drawn_on(cell) ~= "G"
  end
  function Cells:walked(cell)
    return self.src[cell] ~= nil and self:role(cell) == "floor" and not self.lone_bridge[cell]
  end
  function T.topTile(art, m)
    if not MOUNTAIN[twin(art, m)] then return false end
    local cls = pixelClasses(art, m)
    return cls.F < 0.08 * 256 and cls.T >= 0.45 * 256
  end
  function Cells:house(cell) return self.models[cell] ~= nil and self:role(cell) == "wall" end
  function T.inFace(art, x, y, both)
    local a, b
    for i, nx in ipairs({ x - 1, x + 1 }) do
      local ok = nx >= 0 and nx < art.w and pixelClasses(art, art.metatile(nx, y)).F >= 96
      if i == 1 then a = ok else b = ok end
    end
    if both then return a and b end
    return a or b
  end
  -- (a shallow copy: finish() takes the ledges a mark makes rock out of it)
  function Cells:copy()
    local o = setmetatable({}, Cells)
    for k, v in pairs(self) do o[k] = v end
    return o
  end

  -- voxel_props.find sorted by (name, sx, sy), and cells_of
  function T.findPropsSorted(lid)
    local found = S.findProps(lid)
    local list = {}
    for i, f in ipairs(found) do list[i] = f end
    table.sort(list, function(a, b)
      if a[1].name ~= b[1].name then return a[1].name < b[1].name end
      if a[2] ~= b[2] then return a[2] < b[2] end
      return a[3] < b[3]
    end)
    return list
  end
  function T.propCellsOf(obj, sx, sy)
    local out, seen = {}, {}
    for j, row in ipairs(obj.grid) do
      for i, t in ipairs(row) do
        if t then
          local x, y = floor((sx + i - 1) / 2), floor((sy + j - 1) / 2)
          local k = K(x, y)
          if not seen[k] then seen[k] = true; out[#out + 1] = { x, y } end
        end
      end
    end
    return out
  end

  --- {cell: true}: the cells a building's model owns (opt.models(lid) -> { [K(x, y)] = ... })
  function T.modelled(members)
    local out = {}
    local models = S.opt.models
    if not models then return out end
    for _, mem in ipairs(members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local own = models(lid)
      for k, v in pairs(own or {}) do
        local cell = K(KX(k) + ox, KY(k) + oy)
        if out[cell] == nil then out[cell] = v or true end
      end
    end
    return out
  end

  -- ── 2. terraces and their levels ──────────────────────────────────────────────

  local Offsets = {}
  Offsets.__index = Offsets
  function T.newOffsets() return setmetatable({ parent = {}, off = {} }, Offsets) end
  function Offsets:find(a)
    if self.parent[a] == nil then
      self.parent[a], self.off[a] = a, 0
      return a, 0
    end
    local path = {}
    while self.parent[a] ~= a do
      path[#path + 1] = a
      a = self.parent[a]
    end
    local root = a
    local total = 0
    for i = #path, 1, -1 do
      local p = path[i]
      total = total + self.off[p]
      self.off[p] = total
      self.parent[p] = root
    end
    return root, (#path > 0 and self.off[path[1]] or 0)
  end
  function Offsets:join(a, b, d)
    local ra, oa = self:find(a)
    local rb, ob = self:find(b)
    if ra == rb then return oa - ob == d end
    self.parent[rb] = ra
    self.off[rb] = oa - ob - d
    return true
  end

  --- runs: { { dir, hi, cells (list), lo } }
  function T.runsOf(c)
    local kind = c.kind
    local function flat(cell) local k = kind[cell] return k == TOP or k == GROUND end
    local function onTop(cell) return c:tree_on_rock(cell) and c:drawn_on(cell) == "T" end
    local runs = {}
    for x = c.xs.start, c.xs.stop - 1 do
      for y = c.ys.start, c.ys.stop - 1 do
        tickN()
        local nxt = K(x, y + 1)
        local hi = K(x, y)
        while onTop(hi) do hi = K(x, KY(hi) - 1) end
        if flat(hi) and kind[nxt] == ROCK and not c.band[nxt] and not c:water(hi) then
          local k = 1
          while kind[K(x, y + 1 + k)] == ROCK and not c.band[K(x, y + 1 + k)] do k = k + 1 end
          local stop = K(x, y + 1 + k)
          local cells = {}
          for i = 0, k - 1 do cells[#cells + 1] = K(x, y + 1 + i) end
          if flat(stop) and not c.rim[stop] then runs[#runs + 1] = { "S", hi, cells, stop } end
        end
      end
    end
    for y = c.ys.start, c.ys.stop - 1 do
      for x = c.xs.start, c.xs.stop - 1 do
        tickN()
        local nxt = K(x + 1, y)
        if flat(K(x, y)) and c.band[nxt] then
          local side = c.band[nxt]
          local k = 1
          while c.band[K(x + 1 + k, y)] == side do k = k + 1 end
          local stop = K(x + 1 + k, y)
          local cells = {}
          for i = 0, k - 1 do cells[#cells + 1] = K(x + 1 + i, y) end
          if flat(stop) then
            if side == "E" and not c:water(K(x, y)) then
              runs[#runs + 1] = { "E", K(x, y), cells, stop }
            elseif side == "W" and not c:water(stop) then
              local rev = {}
              for i = #cells, 1, -1 do rev[#rev + 1] = cells[i] end
              runs[#runs + 1] = { "W", stop, rev, K(x, y) }
            end
          end
        end
      end
    end
    return runs
  end

  --- {cell: terrace id} of the tops and grounds (comp, its keys' order compOrder), and the
  --- tree_ground set on c
  function T.terraces(c, runs)
    local uf, ufOrder = {}, {}
    local apart = {}
    local function apartAdd(a, b)
      local t = apart[a]
      if not t then t = {}; apart[a] = t end
      t[b] = true
    end
    for _, r in ipairs(runs) do
      tickN()
      apartAdd(r[2], r[4])
      apartAdd(r[4], r[2])
    end
    local members = {}
    local function find(a)
      if uf[a] == nil then uf[a] = a; ufOrder[#ufOrder + 1] = a end
      while uf[a] ~= a do
        uf[a] = uf[uf[a]]
        a = uf[a]
      end
      return a
    end
    local function join(a, b)
      local ra, rb = find(a), find(b)
      if ra == rb then return end
      local ma, mb = members[ra], members[rb]
      if ma then
        for m in pairs(ma) do
          for o in pairs(apart[m] or {}) do if find(o) == rb then return end end
        end
      end
      if mb then
        for m in pairs(mb) do
          for o in pairs(apart[m] or {}) do if find(o) == ra then return end end
        end
      end
      uf[rb] = ra
      if mb then
        local t = members[ra]
        if not t then t = {}; members[ra] = t end
        for m in pairs(mb) do t[m] = true end
        members[rb] = nil
      end
    end
    for cell in pairs(apart) do members[cell] = { [cell] = true } end
    local edges = {}
    for _, cell in ipairs(c.kindOrder) do
      local k = c.kind[cell]
      tickN()
      if k == TOP or k == GROUND or k == UNKNOWN then
        local x, y = KX(cell), KY(cell)
        find(cell)
        for _, n in ipairs({ K(x + 1, y), K(x, y + 1) }) do
          local nk = c.kind[n]
          local skip = false
          local south = KY(n) == y + 1
          if k == TOP then
            if nk ~= TOP or (south and c.rim[n]) then skip = true
            elseif c:on_top(cell) ~= c:on_top(n) then skip = true end
          elseif nk ~= GROUND and nk ~= UNKNOWN then
            skip = true
          elseif south and c.walked_tops[n] and c.rim[n] then
            skip = true
          end
          if not skip and (c:tree_on_rock(cell) or c:tree_on_rock(n))
              and (c:drawn_on(cell) == "G") ~= (c:drawn_on(n) == "G") then
            skip = true
          end
          if not skip then
            local ma, mb = c:metatile(cell), c:metatile(n)
            local wa, wb = c:water(cell), c:water(n)
            if c.falls[cell] and not c.falls[n] and south then
              skip = true
            else
              local rank
              if (wa and wb) or (k == GROUND and nk == GROUND and c:walked(cell) and c:walked(n)) then rank = 0
              elseif ma < 0x200 and mb < 0x200 then rank = 1
              else rank = 2 end
              if (c.walked_tops[cell] == true) ~= (c.walked_tops[n] == true) then rank = 3 end
              if wa ~= wb then rank = rank + 3 end
              edges[#edges + 1] = { rank, cell, n }
            end
          end
        end
      end
    end
    table.sort(edges, function(p, q)
      if p[1] ~= q[1] then return p[1] < q[1] end
      if p[2] ~= q[2] then return cmpXY(p[2], q[2]) end
      return cmpXY(p[3], q[3])
    end)
    for _, e in ipairs(edges) do tickN(); join(e[2], e[3]) end
    c.tree_ground = {}
    local comp, compOrder = {}, {}
    for _, cell in ipairs(ufOrder) do
      tickN()
      if c.kind[cell] == UNKNOWN then
        c.tree_ground[cell] = find(cell)
      else
        comp[cell] = find(cell)
        compOrder[#compOrder + 1] = cell
      end
    end
    return comp, compOrder
  end

  --- The levels down a run of rock cells: { out (0-based list), n }
  local function steps(c, cells, direction)
    local out, n = {}, 0
    for i, cell in ipairs(cells) do
      tickN()
      if direction == "S" and i > 1 and UPPER_END[c:role_id(cells[i - 1])] and LOWER_END[c:role_id(cell)]
          and out[i - 1] == n - 1 then
        out[i] = out[i - 1]
      else
        out[i] = n
        n = n + 1
      end
    end
    return out, n
  end
  T.steps = steps

  --- {terrace: level}, the votes that lost; blocksOut (optional) gets {terrace: root}
  function T.solveLevels(c, comp, compOrder, runs0, reference, meets, blocksOut)
    local runs = {}
    for _, r in ipairs(runs0) do
      if comp[r[2]] and comp[r[4]] and comp[r[2]] ~= comp[r[4]] then runs[#runs + 1] = r end
    end
    local vote, hidden = counter(), {}
    local vkey = {}
    local function vk(a, b, k)
      local key = a .. "|" .. b .. "|" .. k
      vkey[key] = { a, b, k }
      return key
    end
    for _, r in ipairs(runs) do
      local d, hi, cells, lo = r[1], r[2], r[3], r[4]
      local head = false
      if d ~= "S" then for _, cell in ipairs(cells) do if c.rim[cell] then head = true end end end
      local _, n = steps(c, cells, d)
      local key = vk(comp[hi], comp[lo], n)
      vote.add(key, head and 1 or 2)
      local h = d == "S" and ((c:role(lo) == "wall" and c:metatile(lo) >= 0x200)
        or c.kind[K(KX(lo), KY(lo) + 1)] == UNKNOWN)
      hidden[key] = (hidden[key] or 0) + (h and 1 or 0)
    end
    local lip = counter()
    local behind = {}
    for cell, t in pairs(c.tree_ground or {}) do behind[cell] = t end
    for cell, t in pairs(comp) do behind[cell] = t end
    for cell in pairs(c.rim) do
      local n = K(KX(cell), KY(cell) - 1)
      if comp[cell] and behind[n] and comp[cell] ~= behind[n] and c.src[n][1] == c.src[cell][1] then
        lip.add(vk(comp[cell], behind[n], 1))
      end
    end
    local off = T.newOffsets()
    local dropped = {}
    local size = {}
    local cellsOf, terraceOrder = {}, {}
    for _, cell in ipairs(compOrder) do
      local t = comp[cell]
      size[t] = (size[t] or 0) + 1
      local l = cellsOf[t]
      if not l then l = {}; cellsOf[t] = l; terraceOrder[#terraceOrder + 1] = t end
      l[#l + 1] = cell
    end
    local kindOf = {}
    for t, cells in pairs(cellsOf) do kindOf[t] = c.kind[cells[1]] end
    if reference ~= nil then
      local ts = sortXY(keysOf(cellsOf))
      for _, t in ipairs(ts) do
        local cells = cellsOf[t]
        if kindOf[t] == GROUND and #cells >= ANCHOR_MIN then
          local edgeCells = {}
          for _, cell in ipairs(cells) do
            if c:at_edge(cell) and reference[cell] ~= nil and (meets == nil or (meets[cell] and meets[cell][2])) then
              edgeCells[#edgeCells + 1] = cell
            end
          end
          local ok = #edgeCells >= 2
          if ok and meets ~= nil then
            local met, along = counter(), counter()
            for _, cell in ipairs(edgeCells) do met.add(meets[cell][1]) end
            for _, cell in ipairs(cells) do if meets[cell] then along.add(meets[cell][1]) end end
            local any = false
            for _, b in ipairs(met.order) do if 2 * met.n[b] >= (along.n[b] or 0) then any = true end end
            if not any then ok = false end
          end
          if ok then
            local got = counter()
            for _, cell in ipairs(cells) do
              if reference[cell] ~= nil and not c.keep[cell] then got.add(LEVEL * pyround(reference[cell] / LEVEL)) end
            end
            if #got.order > 0 then off:join(WORLD, t, -got.most()) end
          end
        end
      end
    end
    local function across(a, b) return c.src[a][1] ~= c.src[b][1] end
    local function weight(key, n)
      local k = vkey[key]
      local w = n * (across(k[1], k[2]) and 0.5 or 1.0)
      if hidden[key] * 2 >= n then w = w * 0.25 end
      return w
    end
    local items = {}
    for _, key in ipairs(vote.order) do items[#items + 1] = key end
    table.sort(items, function(p, q)
      local wp, wq = -weight(p, vote.n[p]), -weight(q, vote.n[q])
      if wp ~= wq then return wp < wq end
      local a, b = vkey[p], vkey[q]
      if a[3] ~= b[3] then return a[3] < b[3] end
      if a[1] ~= b[1] then return cmpXY(a[1], b[1]) end
      return cmpXY(a[2], b[2])
    end)
    for _, key in ipairs(items) do
      local k = vkey[key]
      if not off:join(k[1], k[2], k[3] * LEVEL) then dropped[#dropped + 1] = { k, vote.n[key] } end
    end
    local lips = {}
    for _, key in ipairs(lip.order) do lips[#lips + 1] = key end
    table.sort(lips, function(p, q)
      if lip.n[p] ~= lip.n[q] then return lip.n[p] > lip.n[q] end
      local a, b = vkey[p], vkey[q]
      if a[1] ~= b[1] then return cmpXY(a[1], b[1]) end
      if a[2] ~= b[2] then return cmpXY(a[2], b[2]) end
      return a[3] < b[3]
    end)
    for _, key in ipairs(lips) do
      local k = vkey[key]
      off:join(k[1], k[2], k[3] * LEVEL)
    end
    -- set(comp.values()), in Python's order
    local values = {}
    for i, cell in ipairs(compOrder) do values[i] = comp[cell] end
    local tset = pySetCells(values)
    local roots, rootOrder = {}, {}
    for _, t in ipairs(tset) do
      local r = off:find(t)
      local l = roots[r]
      if not l then l = {}; roots[r] = l; rootOrder[#rootOrder + 1] = r end
      l[#l + 1] = t
    end
    local level = {}
    local worldRoot = off:find(WORLD)
    for _, r in ipairs(rootOrder) do
      local mem = roots[r]
      if blocksOut ~= nil then for _, t in ipairs(mem) do blocksOut[t] = r end end
      local rel = {}
      for _, t in ipairs(mem) do
        local _, o = off:find(t)
        rel[t] = o
      end
      local grounds = {}
      for _, t in ipairs(mem) do if kindOf[t] == GROUND then grounds[#grounds + 1] = t end end
      local lift
      if r == worldRoot then
        local _, o = off:find(WORLD)
        lift = -o
      elseif reference ~= nil then
        local diffs = counter()
        for _, t in ipairs(#grounds > 0 and grounds or mem) do
          for _, cell in ipairs(cellsOf[t]) do
            if reference[cell] ~= nil and not c.keep[cell] then
              diffs.add(LEVEL * pyround((reference[cell] - rel[t]) / LEVEL))
            end
          end
        end
        if #diffs.order > 0 then
          local best, bn, ba
          for _, v in ipairs(diffs.order) do
            local n, a = diffs.n[v], -abs(v)
            if not best or n > bn or (n == bn and a > ba) then best, bn, ba = v, n, a end
          end
          lift = best
        end
      end
      if lift == nil then
        local pool = #grounds > 0 and grounds or mem
        local ref
        for _, t in ipairs(pool) do
          if not ref or size[t] > size[ref] or (size[t] == size[ref] and cmpXY(ref, t)) then ref = t end
        end
        lift = -rel[ref]
      end
      for _, t in ipairs(mem) do level[t] = rel[t] + lift end
    end
    return level, dropped
  end

  -- ── 3. the level each rock cell hangs from ───────────────────────────────────

  function T.upperLevels(c, comp, level, runs)
    local U = {}
    for _, r in ipairs(runs) do
      local side, hi, cells, lo = r[1], r[2], r[3], r[4]
      if comp[hi] and comp[lo] then
        local top, bottom = level[comp[hi]], level[comp[lo]]
        if top > bottom then
          local idx = steps(c, cells, side)
          for i, cell in ipairs(cells) do
            local u = max(top - LEVEL * idx[i], bottom + LEVEL)
            if U[cell] == nil or u > U[cell] then U[cell] = u end
          end
        end
      end
    end
    local crests = {}
    for y = c.ys.start, c.ys.stop - 1 do
      for x = c.xs.start, c.xs.stop - 1 do
        local cell = K(x, y)
        if comp[cell] and c.band[K(x + 1, y)] == "W" then
          local k = 1
          while c.band[K(x + 1 + k, y)] == "W" do k = k + 1 end
          if c.band[K(x + 1 + k, y)] == "E" then
            local j = 1
            while c.band[K(x + 1 + k + j, y)] == "E" do j = j + 1 end
            local stop = K(x + 1 + k + j, y)
            if comp[stop] then
              local loW, loE = level[comp[cell]], level[comp[stop]]
              local crest = max(loW + LEVEL * k, loE + LEVEL * j)
              for i = 0, k - 1 do
                local cc = K(x + 1 + i, y)
                if U[cc] == nil then U[cc] = crest - LEVEL * (k - 1 - i) end
                crests[cc] = true
              end
              for i = 0, j - 1 do
                local cc = K(x + 1 + k + i, y)
                if U[cc] == nil then U[cc] = crest - LEVEL * i end
                crests[cc] = true
              end
            end
          end
        end
      end
    end
    for y = c.ys.start, c.ys.stop - 1 do
      for x = c.xs.start, c.xs.stop - 1 do
        local cell = K(x, y)
        if comp[cell] then
          for _, ss in ipairs({ { "W", 1 }, { "E", -1 } }) do
            local side, step = ss[1], ss[2]
            local k, run = 1, {}
            while c.band[K(x + step * k, y)] == side do
              run[#run + 1] = K(x + step * k, y)
              k = k + 1
            end
            if #run > 0 and not c.src[K(x + step * k, y)] then
              for i, cell2 in ipairs(run) do
                if U[cell2] == nil then
                  U[cell2] = level[comp[cell]] + LEVEL * i
                  crests[cell2] = true
                end
              end
            end
          end
        end
      end
    end
    -- bands down a column are one band
    local bandOrder = {}
    for _, cell in ipairs(c.kindOrder) do if c.band[cell] then bandOrder[#bandOrder + 1] = cell end end
    local changed = true
    while changed do
      changed = false
      for _, cell in ipairs(bandOrder) do
        if U[cell] == nil then
          local side = c.band[cell]
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x, y - 1), K(x, y + 1) }) do
            if c.band[n] == side and U[n] ~= nil then
              U[cell] = U[n]
              changed = true
              break
            end
          end
        end
      end
    end
    local todo = {}
    for _, cell in ipairs(c.kindOrder) do
      if c.kind[cell] == ROCK and U[cell] == nil then todo[#todo + 1] = cell end
    end
    for _ = 1, 16 do
      local left = {}
      for _, cell in ipairs(todo) do
        local x, y = KX(cell), KY(cell)
        local side = c.band[cell]
        local high = side == "E" and K(x - 1, y) or side == "W" and K(x + 1, y) or K(x, y - 1)
        local under = (side or c.band[K(x, y - 1)]) and 0 or -LEVEL
        local tiers = { { { high, 0, under } },
                        { { K(x - 1, y), 0, 0 }, { K(x + 1, y), 0, 0 } },
                        { { K(x, y + 1), LEVEL, LEVEL } } }
        if side then
          tiers[2][3] = { K(x, y - 1), 0, 0 }
          tiers[2][4] = { K(x, y + 1), 0, 0 }
        end
        local got
        for _, tier in ipairs(tiers) do
          local best
          for _, e in ipairs(tier) do
            local n = e[1]
            local v
            if comp[n] then v = level[comp[n]] + e[2]
            elseif U[n] ~= nil then v = U[n] + e[3] end
            if v ~= nil and (best == nil or v > best) then best = v end
          end
          if best ~= nil then got = best; break end
        end
        if got == nil then left[#left + 1] = cell else U[cell] = got end
      end
      if #left == #todo then break end
      todo = left
    end
    for _, cell in ipairs(todo) do U[cell] = LEVEL end
    local counted = {}
    for _, r in ipairs(runs) do for _, cell in ipairs(r[3]) do counted[cell] = true end end
    for cell in pairs(crests) do counted[cell] = true end
    for _, cell in ipairs(c.kindOrder) do
      if c.kind[cell] == ROCK and not counted[cell] then
        local x, y = KX(cell), KY(cell)
        local lo, hi
        for dx = -2, 2 do
          for dy = -2, 2 do
            local n = K(x + dx, y + dy)
            if comp[n] then
              local v = level[comp[n]]
              if lo == nil or v < lo then lo = v end
              if hi == nil or v > hi then hi = v end
            end
          end
        end
        if lo ~= nil then U[cell] = max(lo, min(hi, U[cell])) end
      end
    end
    return U
  end

  function T.treeCard(c, cell) return T.TREE_CARDS[c:metatile(cell)] == true or T.smallTrunk(c, cell) end
  T.SMALL_TRUNKS = set({ 0x016, 0x017, 0x0C6, 0x0C7, 0x1F4, 0x1F5 })
  T.TREE_CARDS = set({ 0x016, 0x017, 0x0C6, 0x0C7, 0x1F4, 0x1F5, 0x1D4, 0x1D5, 0x1D6, 0x1D7, 0x1DC, 0x1DD, 0x1DE,
                       0x1DF, 0x1E4, 0x1E5, 0x1E6, 0x1E7, 0x1EC, 0x1ED, 0x1F2, 0x1F3, 0x1FC, 0x1FD, 0x01E, 0x01F,
                       0x026, 0x027, 0x036, 0x037 })
  T.OWN_TRUNKS = { dewford = set({ 0x23A, 0x243 }), fortree = set({ 0x253, 0x22A }), mauville = set({ 0x226 }),
                   lavaridge = set({ 0x218, 0x21A, 0x3B8, 0x203, 0x201 }), rustboro = set({ 0x307 }) }
  function T.smallTrunk(c, cell)
    local m = c:metatile(cell)
    if T.SMALL_TRUNKS[m] then return true end
    local own = T.OWN_TRUNKS[c.arts[c.src[cell][1]].secondary]
    return own ~= nil and own[m] == true
  end

  function T.unknownLevels(c, comp, level, U)
    local out = {}
    local seen = {}
    local function backs(cell, n)
      return n == K(KX(cell), KY(cell) + 1) and c.rim[n] == true and c.kind[n] == TOP
    end
    for _, start in ipairs(sortedXY(c.kind)) do
      if c.kind[start] == UNKNOWN and not seen[start] then
        tick()
        local patch, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          patch[#patch + 1] = cell
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
            if c.kind[n] == UNKNOWN and not seen[n] and c.prop_of[n] == c.prop_of[cell] then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local cand, wet, feet, behindL = {}, {}, {}, {}
        for _, cell in ipairs(patch) do
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
            if comp[n] and not backs(cell, n) then
              local w = c:water(n)
              local lst = w and wet or cand
              lst[#lst + 1] = level[comp[n]]
              if n ~= K(x, y + 1) and not w then behindL[#behindL + 1] = level[comp[n]] end
            end
          end
          local up = K(x, y - 1)
          if U[up] ~= nil then feet[#feet + 1] = U[up] - LEVEL end
        end
        local modelled = true
        for _, cell in ipairs(patch) do if not c.props[cell] then modelled = false end end
        if #cand > 0 and modelled then
          feet = {}
          if #behindL > 0 then cand = behindL end
        end
        local useWet = #wet > #cand + #feet
        local done = false
        if useWet and not modelled then
          local tops, ntops, topv = {}, 0, nil
          for _, cell in ipairs(patch) do
            local x, y = KX(cell), KY(cell)
            local run = {}
            while c.kind[K(x, y + 1 + #run)] == ROCK and not c.band[K(x, y + 1 + #run)] do
              run[#run + 1] = K(x, y + 1 + #run)
            end
            local foot = K(x, y + 1 + #run)
            if #run > 0 and comp[foot] and (c.kind[foot] == TOP or c.kind[foot] == GROUND) then
              local _, n = steps(c, run, "S")
              local v = level[comp[foot]] + LEVEL * n
              if not tops[v] then tops[v] = true; ntops = ntops + 1; topv = v end
            end
          end
          if ntops == 1 then
            for _, cell in ipairs(patch) do out[cell] = topv end
            done = true
          end
        end
        if not done then
          local ground = useWet and wet or cand
          local flr
          if #ground > 0 then flr = math.huge for _, v in ipairs(ground) do flr = min(flr, v) end end
          local allCards = true
          if #ground > 0 and not useWet then
            local lo, hi = math.huge, -math.huge
            for _, v in ipairs(ground) do lo, hi = min(lo, v), max(hi, v) end
            if hi - lo < 0.5 then
              for _, cell in ipairs(patch) do
                if not (T.treeCard(c, cell) and not T.smallTrunk(c, cell)) then allCards = false; break end
              end
              if allCards then
                for _, cell in ipairs(patch) do out[cell] = ground[1] end
                done = true
              end
            end
          end
        end
        if not done then
          local ground = useWet and wet or cand
          local flr
          if #ground > 0 then flr = math.huge for _, v in ipairs(ground) do flr = min(flr, v) end end
          local feet2 = {}
          for i, f in ipairs(feet) do feet2[i] = flr == nil and f or max(f, flr) end
          local cand2
          if useWet then cand2 = wet
          else
            cand2 = {}
            for _, v in ipairs(cand) do cand2[#cand2 + 1] = v end
            for _, v in ipairs(feet2) do cand2[#cand2 + 1] = v end
            if #cand2 == 0 then cand2 = wet end
          end
          local v = 0
          if #cand2 > 0 then v = math.huge for _, q in ipairs(cand2) do v = min(v, q) end end
          local own, ownOrder, spread = {}, {}, {}
          local smin, smax
          for _, cell in ipairs(patch) do
            local x, y = KX(cell), KY(cell)
            local inFace = c.kind[K(x - 1, y)] == ROCK and c.kind[K(x + 1, y)] == ROCK and c.kind[K(x, y + 1)] == UNKNOWN
            local top = not T.treeCard(c, cell) and c.src[K(x, y + 1)] ~= nil and T.smallTrunk(c, K(x, y + 1))
            local mine, behindV = {}, {}
            for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
              local skip = (inFace and n == K(x, y - 1)) or backs(cell, n)
              if not skip and comp[n] and c:water(n) == useWet then
                if top and n == K(x, y - 1) then behindV[#behindV + 1] = level[comp[n]]
                else mine[#mine + 1] = level[comp[n]] end
              end
            end
            local up = K(x, y - 1)
            if U[up] ~= nil and not c.band[up] and not (modelled and #mine > 0) then
              local f = U[up] - LEVEL
              mine[#mine + 1] = flr == nil and f or max(f, flr)
            end
            if #mine > 0 then
              local mv = math.huge
              for _, q in ipairs(mine) do mv = min(mv, q) end
              own[cell] = mv
              ownOrder[#ownOrder + 1] = cell
            end
            if #mine > 0 or #behindV > 0 then
              local sv = math.huge
              for _, q in ipairs(mine) do sv = min(sv, q) end
              for _, q in ipairs(behindV) do sv = min(sv, q) end
              spread[cell] = sv
              smin = smin == nil and sv or min(smin, sv)
              smax = smax == nil and sv or max(smax, sv)
            end
          end
          if smin == nil or smax - smin <= LEVEL + 0.5 then
            for _, cell in ipairs(patch) do out[cell] = v end
          else
            local dist, res = {}, {}
            for cell, lv in pairs(own) do dist[cell] = 0; res[cell] = lv end
            local front = ownOrder
            while #front > 0 do
              local nxt = {}
              for _, cell in ipairs(front) do
                local x, y = KX(cell), KY(cell)
                for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
                  if c.kind[n] == UNKNOWN and seen[n] then
                    local d = dist[cell] + 1
                    if dist[n] == nil then
                      dist[n] = d
                      res[n] = res[cell]
                      nxt[#nxt + 1] = n
                    elseif dist[n] == d then
                      res[n] = min(res[n], res[cell])
                    end
                  end
                end
              end
              front = nxt
            end
            local byRow = {}
            for i, cell in ipairs(patch) do byRow[i] = cell end
            local pos = {}
            for i, cell in ipairs(patch) do pos[cell] = i end
            table.sort(byRow, function(a, b)
              local ya, yb = KY(a), KY(b)
              if ya ~= yb then return ya > yb end
              return pos[a] < pos[b]
            end)
            for _, cell in ipairs(byRow) do
              local x, y = KX(cell), KY(cell)
              local below = K(x, y + 1)
              if not T.treeCard(c, cell) and res[below] ~= nil and T.smallTrunk(c, below) then res[cell] = res[below] end
            end
            for _, cell in ipairs(patch) do
              local r = res[cell]
              out[cell] = r == nil and v or r
            end
          end
        end
      end
    end
    return out
  end

  --- settle: in place in U
  function T.settle(c, U, flat, fixed)
    local function options(cell)
      if flat[cell] ~= nil then return { flat[cell] } end
      return { U[cell], U[cell] - LEVEL }
    end
    local function score(x, y)
      local n = 0
      for _, g in ipairs({ { x, y }, { x + 1, y }, { x, y + 1 }, { x + 1, y + 1 } }) do
        local gx, gy = g[1], g[2]
        local common
        for _, cl in ipairs({ K(gx - 1, gy - 1), K(gx, gy - 1), K(gx - 1, gy), K(gx, gy) }) do
          if c.kind[cl] then
            local o = options(cl)
            if common == nil then
              common = {}
              for _, v in ipairs(o) do common[v] = true end
            else
              local keep = {}
              for _, v in ipairs(o) do if common[v] then keep[v] = true end end
              common = keep
            end
          end
        end
        if common and next(common) then n = n + 1 end
      end
      return n
    end
    local rock = {}
    for cell, k in pairs(c.kind) do if k == ROCK and not c.band[cell] then rock[#rock + 1] = cell end end
    sortXY(rock)
    for _ = 1, 8 do
      local moved = 0
      for _, cell in ipairs(rock) do
        tickN()
        local here = U[cell]
        local x, y = KX(cell), KY(cell)
        local best, bestScore = here, score(x, y)
        for _, u in ipairs({ here + LEVEL, here - LEVEL }) do
          U[cell] = u
          local sc = score(x, y)
          local need = fixed[cell] and 2 or 1
          local held = false
          if u > here and not fixed[cell] then
            for _, n in ipairs({ K(x, y - 1), K(x - 1, y), K(x + 1, y) }) do
              if U[n] == u or flat[n] == u then held = true end
            end
          end
          if sc >= bestScore + need or (sc == bestScore and held) then best, bestScore = u, sc end
        end
        U[cell] = best
        if best ~= here then moved = moved + 1 end
      end
      tick()
      if moved == 0 then break end
    end
    return U
  end

  -- ── 4. corners ───────────────────────────────────────────────────────────────

  local NAMES = { [0] = "NW", "NE", "SW", "SE" }
  local function cornerPixelTop(c, cell, corner)
    local cls = pixelClasses(c:art(cell), c:metatile(cell))
    local x0 = (corner == "NW" or corner == "SW") and 0 or 13
    local y0 = (corner == "NW" or corner == "NE") and 0 or 13
    return clsCount(cls, CT, y0, y0 + 2, x0, x0 + 2) >= 5
  end
  local function defaultHigh(c, cell, k)
    local side = c.band[cell]
    local nm = NAMES[k]
    if side == "W" then return nm == "NE" or nm == "SE" end
    if side == "E" then return nm == "NW" or nm == "SW" end
    return nm == "NW" or nm == "NE"
  end

  --- {cell: {[0] NW, NE, SW, SE}}
  function T.corners(c, U, flat)
    local function options(cell)
      if flat[cell] ~= nil then return { flat[cell] } end
      return { U[cell], U[cell] - LEVEL }
    end
    local function resolve(cells)
      local common
      for _, e in ipairs(cells) do
        local o = e[3]
        if common == nil then
          common = {}
          for _, v in ipairs(o) do common[#common + 1] = v end
        else
          local keep = {}
          for _, v in ipairs(common) do
            for _, w in ipairs(o) do if w == v then keep[#keep + 1] = v; break end end
          end
          common = keep
        end
      end
      if common and #common == 1 then return common[1] end
      if common and #common > 0 then
        local votes, nv = {}, 0
        for _, e in ipairs(cells) do
          if flat[e[1]] == nil then
            local v = defaultHigh(c, e[1], e[2])
            if votes[v] == nil then votes[v] = true; nv = nv + 1 end
          end
        end
        local top
        if nv == 1 then
          top = votes[true] == true
        else
          top = false
          for _, e in ipairs(cells) do if cornerPixelTop(c, e[1], NAMES[e[2]]) then top = true; break end end
        end
        local mx, mn = common[1], common[1]
        for _, v in ipairs(common) do mx, mn = max(mx, v), min(mn, v) end
        return top and mx or mn
      end
      return nil
    end
    local out = {}
    for cell in pairs(c.kind) do out[cell] = {} end
    local around = { { -1, -1, 3 }, { 0, -1, 2 }, { -1, 0, 1 }, { 0, 0, 0 } }
    for gy = c.ys.start, c.ys.stop do
      tick()
      for gx = c.xs.start, c.xs.stop do
        local cells = {}
        for _, a in ipairs(around) do
          local cell = K(gx + a[1], gy + a[2])
          if c.kind[cell] then cells[#cells + 1] = { cell, a[3], options(cell) } end
        end
        if #cells > 0 then
          local lower, upper = {}, {}
          for _, e in ipairs(cells) do
            if e[2] == 0 or e[2] == 1 then lower[#lower + 1] = e else upper[#upper + 1] = e end
          end
          local rimLower = false
          for _, e in ipairs(lower) do if c.rim[e[1]] then rimLower = true end end
          local groups = rimLower and { lower, upper } or { cells }
          for _, group in ipairs(groups) do
            if #group > 0 then
              local v = resolve(group)
              local flats = {}
              for _, e in ipairs(group) do if flat[e[1]] ~= nil then flats[#flats + 1] = flat[e[1]] end end
              for _, e in ipairs(group) do
                local cell, k = e[1], e[2]
                if v ~= nil then out[cell][k] = v
                elseif flat[cell] ~= nil then out[cell][k] = flat[cell]
                elseif defaultHigh(c, cell, k) then out[cell][k] = U[cell]
                else
                  local low = U[cell] - LEVEL
                  local below
                  for _, f in ipairs(flats) do if f < low and (below == nil or f < below) then below = f end end
                  out[cell][k] = below ~= nil and max(below, U[cell] - MAX_FALL) or low
                end
              end
            end
          end
        end
      end
    end
    return out
  end

  -- ── 5. pieces ────────────────────────────────────────────────────────────────

  local CORNERS = { "cSE", "cSW", "vSE", "vSW" }
  local IS_CORNER = set(CORNERS)
  T.CORNERS, T.IS_CORNER = CORNERS, IS_CORNER
  local FIN, STEEP, FACE_SHARE, CORNER = 3.0, 0.4, 0.4, 0.3
  T.FIN, T.STEEP, T.CORNER = FIN, STEEP, CORNER

  function T.isFace(c, cell)
    if c.band[cell] then return false end
    if c.kind[cell] == ROCK and (c:is_stair(cell) or c:muddy(cell)) then return true end
    local cls = pixelClasses(c:art(cell), c:metatile(cell))
    return cls.F >= FACE_SHARE * 256
  end

  --- (kind, drop) of a piece's kind: "S:8" a face falling 8 pixels
  local function splitKind(kind)
    local i = kind:find(":", 1, true)
    if i then return kind:sub(1, i - 1), tonumber(kind:sub(i + 1)) end
    return kind, nil
  end
  T.splitKind = splitKind
  local function isBandKind(k) return k == "W" or k == "E" or k == "W2" or k == "E2" end
  T.isBandKind = isBandKind

  local gridMemo = {}
  --- 5 x 5 heights of a piece (cached: never written to)
  local function pieceGrid(kind, top)
    local mk = kind .. "|" .. top
    local g = gridMemo[mk]
    if g then return g end
    local k, drop = splitKind(kind)
    g = {}
    if drop ~= nil then
      if IS_CORNER[k] then
        local east = k:sub(3, 3) == "E"
        local convex = k:sub(1, 1) == "c"
        for j = 0, N do
          local row = {}
          for i = 0, N do
            local a = east and i or N - i
            local p = convex and max(a, j) or min(a, j)
            row[i] = top - drop / N * p
          end
          g[j] = row
        end
      elseif k == "S" then
        for j = 0, N do local row = {} for i = 0, N do row[i] = top - drop * j / N end g[j] = row end
      elseif k == "W" then
        for j = 0, N do local row = {} for i = 0, N do row[i] = top - drop + drop * i / N end g[j] = row end
      elseif k == "E" then
        for j = 0, N do local row = {} for i = 0, N do row[i] = top - drop * i / N end g[j] = row end
      else
        for j = 0, N do local row = {} for i = 0, N do row[i] = top end g[j] = row end
      end
    elseif IS_CORNER[k] then
      local east = k:sub(3, 3) == "E"
      local convex = k:sub(1, 1) == "c"
      for j = 0, N do
        local row = {}
        for i = 0, N do
          local a = east and i or N - i
          local p = convex and max(a, j) or min(a, j)
          row[i] = top - LEVEL / N * p
        end
        g[j] = row
      end
    elseif k == "S" then
      for j = 0, N do local row = {} for i = 0, N do row[i] = top - LEVEL * j / N end g[j] = row end
    elseif k == "W" or k == "W2" then
      local d = LEVEL * (k == "W2" and 2 or 1)
      for j = 0, N do local row = {} for i = 0, N do row[i] = top - d + d * i / N end g[j] = row end
    elseif k == "E" or k == "E2" then
      local d = LEVEL * (k == "E2" and 2 or 1)
      for j = 0, N do local row = {} for i = 0, N do row[i] = top - d * i / N end g[j] = row end
    else
      for j = 0, N do local row = {} for i = 0, N do row[i] = top end g[j] = row end
    end
    gridMemo[mk] = g
    return g
  end
  T.pieceGrid = pieceGrid
  local function pg(p) return pieceGrid(p[1], p[2]) end
  T.pg = pg
  local function footOf(piece)
    local kind, top = piece[1], piece[2]
    return (kind == "S" or IS_CORNER[kind]) and top - LEVEL or top
  end
  T.footOf = footOf

  --- {cell: {kind, top}}: one piece a cell
  function T.blocks(c, U, flat, kept)
    local out, pref = {}, {}
    for _, cell in ipairs(c.kindOrder) do
      if flat[cell] ~= nil then
        out[cell] = { "F", flat[cell] }
        local x, y = KX(cell), KY(cell)
        if BOULDER_HEAD[c:metatile(cell)] then
          for _, ns in ipairs({ { K(x + 1, y), "W" }, { K(x - 1, y), "E" } }) do
            local n = ns[1]
            if c.kind[n] == TOP and flat[n] == flat[cell] + LEVEL then out[cell] = { ns[2], flat[n] } end
          end
        end
      elseif c.band[cell] then
        local x, y = KX(cell), KY(cell)
        local side = c.band[cell]
        local hi, lo
        if side == "W" then hi, lo = K(x + 1, y), K(x - 1, y) else hi, lo = K(x - 1, y), K(x + 1, y) end
        if flat[hi] ~= nil and flat[lo] ~= nil and flat[hi] <= flat[lo] then
          out[cell] = { "F", flat[hi] }
        else
          pref[cell] = side
          out[cell] = { side, U[cell] }
        end
      else
        pref[cell] = T.isFace(c, cell) and "S" or "F"
        out[cell] = { pref[cell], U[cell] }
      end
    end
    local grid = {}
    for cell, p in pairs(out) do grid[cell] = pg(p) end
    kept = kept or {}
    for cell, g in pairs(kept) do grid[cell] = g end
    local trees = {}
    for cell, k in pairs(c.kind) do if k == UNKNOWN and c:role(cell) == "tree" then trees[cell] = true end end
    local free = {}
    for cell in pairs(out) do
      local k = c.kind[cell]
      if flat[cell] == nil and not c.keep[cell] and (k == ROCK or k == TOP) then free[#free + 1] = cell end
    end
    sortXY(free)
    local pit = 0.3
    local function step(p, q, back)
      local d = abs(p - q)
      if d < 0.5 then return 0.0 end
      local k = 1.0 + 0.5 * (d / LEVEL - 1.0)
      if back == nil then return 0.5 * k end
      return k * (q > p and back or 1.0)
    end
    local function kindAt(n, piece)
      if n == nil then return piece[1] end
      if out[n] and not kept[n] then return out[n][1] end
      return "F"
    end
    local DIRS = { { -1, 0, "W", "E", false }, { 1, 0, "E", "W", false }, { 0, -1, "N", "S", true }, { 0, 1, "S", "N", true } }
    local function cost(cell, g, piece)
      local x, y = KX(cell), KY(cell)
      local total = 0.0
      for _, d in ipairs(DIRS) do
        local n = K(x + d[1], y + d[2])
        local mine, theirs, ns = d[3], d[4], d[5]
        if grid[n] and not trees[n] then
          local a, b = edge(g, mine), edge(grid[n], theirs)
          if kept[n] then
            local over = false
            for i = 0, N do if b[i] - a[i] > 0.5 then over = true; break end end
            if over then total = total + 10.0 end
          end
          if mine == "W" or mine == "N" then a, b = b, a end
          local back
          if not ns then
            local west, east
            if mine == "W" then west, east = n, cell else west, east = cell, n end
            local kw = west ~= cell and kindAt(west, piece) or piece[1]
            local ke = east ~= cell and kindAt(east, piece) or piece[1]
            kw, ke = kw:sub(1, 1), ke:sub(1, 1)
            local mx1, mx2 = -math.huge, -math.huge
            for i = 0, N do mx1 = max(mx1, a[i] - b[i]); mx2 = max(mx2, b[i] - a[i]) end
            local fin = (kw == "W" and mx1 > 0.5) or (ke == "E" and mx2 > 0.5)
            if fin then total = total + FIN end
          else
            local north = mine == "N" and kindAt(n, piece) or piece[1]
            local south = mine == "N" and piece[1] or kindAt(n, piece)
            back = (north == "F" or (north ~= "S" and south == "F")) and 0.3 or pit
          end
          local s = 0.0
          for i = 0, N do s = s + step(a[i], b[i], back) end
          total = total + s / (N + 1)
        end
      end
      total = total + 0.25 * abs(piece[2] - U[cell]) / LEVEL
      if IS_CORNER[piece[1]] then total = total + CORNER
      elseif pref[cell] and piece[1]:sub(1, 1) ~= pref[cell] then total = total + 0.6
      elseif piece[1] == "W2" or piece[1] == "E2" then total = total + STEEP end
      return total
    end
    for _, stage in ipairs({ { 0.3, 10 }, { 1.0, 10 }, { 3.0, 10 }, { 10.0, 30 } }) do
      pit = stage[1]
      for _ = 1, stage[2] do
        local moved = 0
        for _, cell in ipairs(free) do
          local cur = out[cell]
          local kind, top = cur[1], cur[2]
          tickN()
          if not (c.band[cell] and kind == "F") then
            local kinds
            if c.band[cell] then kinds = { c.band[cell], c.band[cell] .. "2" }
            else kinds = { "F", "S", "cSE", "cSW", "vSE", "vSW" } end
            local tops, tset = {}, {}
            for _, k in ipairs({ -2, -1, 0, 1, 2 }) do
              local t = U[cell] + LEVEL * k
              if not tset[t] then tset[t] = true; tops[#tops + 1] = t end
            end
            if not tset[top] then tset[top] = true; tops[#tops + 1] = top end
            table.sort(tops)
            local best, bestCost = cur, cost(cell, grid[cell], cur)
            for _, k2 in ipairs(kinds) do
              for _, t in ipairs(tops) do
                if not (k2 == cur[1] and t == cur[2]) then
                  local piece = { k2, t }
                  local cc = cost(cell, pieceGrid(k2, t), piece)
                  if cc < bestCost - 1e-6 then best, bestCost = piece, cc end
                end
              end
            end
            if best ~= cur then
              out[cell] = best
              grid[cell] = pg(best)
              moved = moved + 1
            end
          end
        end
        tick()
        if moved == 0 then break end
      end
    end
    local byRow = keysOf(out)
    table.sort(byRow, function(a, b)
      local ya, yb = KY(a), KY(b)
      if ya ~= yb then return ya > yb end
      return cmpXY(a, b)
    end)
    -- (sorted(out, key=-y): a stable sort of the dict's keys; out's keys are c.kind's order)
    local pos = {}
    for i, cell in ipairs(c.kindOrder) do pos[cell] = i end
    table.sort(byRow, function(a, b)
      local ya, yb = KY(a), KY(b)
      if ya ~= yb then return ya > yb end
      return pos[a] < pos[b]
    end)
    for _, cell in ipairs(byRow) do
      local x, y = KX(cell), KY(cell)
      local s = K(x, y + 1)
      if BOULDER_HEAD[c:metatile(cell)] and flat[cell] ~= nil and c.band[s] and out[s] then
        local k1 = out[s][1]:sub(1, 1)
        if k1 == "W" or k1 == "E" then out[cell] = out[s] end
      end
    end
    return out
  end

  -- a band's column is drawn with its ends
  local BAND_HEAD = { E = set({ 0x074 }), W = set({ 0x089 }) }
  local BAND_FOOT = { E = set({ 0x07a, 0x07d, 0x092 }), W = set({ 0x07b, 0x078, 0x090 }) }
  T.BAND_HEAD, T.BAND_FOOT = BAND_HEAD, BAND_FOOT

  --- { { side, head or nil, cells, foot or nil } }
  function T.segments(c)
    local out = {}
    for _, cell in ipairs(sortedXY(c.band)) do
      local side = c.band[cell]
      local x, y = KX(cell), KY(cell)
      if c.band[K(x, y - 1)] ~= side then
        local cells = { cell }
        while c.band[K(x, KY(cells[#cells]) + 1)] == side do cells[#cells + 1] = K(x, KY(cells[#cells]) + 1) end
        local head, foot = K(x, y - 1), K(x, KY(cells[#cells]) + 1)
        if not (c.src[head] and c.kind[head] == ROCK and not c.band[head] and BAND_HEAD[side][c:role_id(head)]) then head = nil end
        if not (c.src[foot] and c.kind[foot] == ROCK and not c.band[foot] and BAND_FOOT[side][c:role_id(foot)]) then foot = nil end
        out[#out + 1] = { side, head, cells, foot }
      end
    end
    for _, cell in ipairs(sortedXY(c.kind)) do
      local x, y = KX(cell), KY(cell)
      if c.kind[cell] == ROCK and not c.band[cell] and c.src[K(x, y + 1)] then
        for _, side in ipairs({ "E", "W" }) do
          local foot = K(x, y + 1)
          local low = side == "E" and 1 or -1
          if BAND_HEAD[side][c:role_id(cell)] and c.kind[foot] == ROCK and not c.band[foot]
              and BAND_FOOT[side][c:role_id(foot)] then
            local ok = true
            for _, n in ipairs({ K(x + low, y), K(x + low, y + 1) }) do
              if not (c.src[n] and c.kind[n] ~= ROCK) then ok = false end
            end
            if ok then out[#out + 1] = { side, cell, {}, foot } end
          end
        end
      end
    end
    return out
  end

  --- the heights along the edge of n that faces a cell north ("N": n is north of it) or south
  function T.facingNs(c, pieces, flat, kept, n, mine)
    if kept[n] then return nil end
    if flat[n] ~= nil and c.kind[n] ~= ROCK then return level5(flat[n]) end
    local p = pieces[n]
    if p == nil then return nil end
    return edge(pg(p), mine == "N" and "S" or "N")
  end
  -- the edge of n facing a cell on its `side` ("W": n is west of it)
  function T.facingWe(c, pieces, flat, kept, n, side)
    if kept[n] then return nil end
    if flat[n] ~= nil and c.kind[n] ~= ROCK then return level5(flat[n]) end
    local p = pieces[n]
    if p == nil then return nil end
    return edge(pg(p), side == "W" and "E" or "W")
  end
  function T.eflat(e) return emax(e) - emin(e) <= 0.5 end
end
