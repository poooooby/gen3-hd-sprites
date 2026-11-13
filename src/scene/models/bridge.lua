-- Route 110's Seaside Cycling Road (Battle Scene: Overworld): a deck on piers, read off its own
-- drawing.
--
-- The cartridge says the road is a bridge: its deck is elevation 4 over the elevation-3 land and the
-- elevation-1 sea, and where a path or the sea passes under it the cells are elevation 15. A
-- height field cannot hold that (a cell has one height), so the road is modelled, cell by cell,
-- with open space under it.
--
-- An Emerald drawing is what an orthographic camera at 45 degrees sees: a point (X, Y, Z) - pixels,
-- X east, Y up, Z south - lands on the art at u = X, v = Z - Y. The road is drawn with its deck (two
-- light colours in stripes, ringed by a dark outline), its rails (13 rows standing on the deck's
-- edge: north of the road over its outline, south of it on the road's last rows; west and east a
-- strip seen from above), its front under the south rail (the kerb, the girder, and every few
-- cells a pier, a truss down to the water) and its ramps down to the land at the gatehouses. Every
-- pixel is placed by that rule: the road at the deck's height DECK, the south rail, girder and
-- piers on one upright face at the deck's south edge, the north rail on one at its north edge, the
-- side rails as their tops over the deck's sides. A ramp falls in a slot cut through the deck's
-- south edge, its sides walls from the ground to the deck. A corner drawn as a staircase of pixels
-- is a wall at 45 degrees, or built square where the drawing rounds the rail. The sides the drawing
-- never shows are dressed with the south front's own rail and girder. Whatever of a cell's drawing
-- is not the bridge's and not the plain ground laid under it is laid on that ground as drawn (a
-- ground patch). A lawn's curb that runs on under a span stands under the deck as the curb
-- component builds it.
--
-- Ported from Emerald 3DS's scripts/voxel_bridge.py (by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE): the same reading, faces, merges and
-- blocks. Not ported: its deck table (what lifts a walker up on the road: the battle scene has no
-- walkers), the cast shadows' footprints and its checks against the drawing.
--
--   Bridge.read(io, conf, tick) -> the bridge of a layout, its faces built (br.faces)
--   Bridge.blocks(br, name, tick) -> { { name, cell = {x, y}, ground, art, faces, curbs, patch,
--                                        top, placed = { {x, y} } } }, one model per cell drawn
--                                        alike
-- io = { w, h, metatile(x, y), subtiles(m, layer) (relief_art's), cellImage(m), elevation(x, y),
--        blocked(x, y), role(x, y), curb = { tiles = set, fill = set, ground = m, height } }.
-- Colours are packed 0xRRGGBB numbers.

return function(K)
  local floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
  local remove = table.remove
  local Bridge = {}

  -- The bridges modelled, by layout: the elevation their deck is walked at, the one of the cells
  -- walked both over and under, and `apart`: cell rectangles drawn against the road that are not
  -- of it (the gatehouses and the Trick House, modelled on their own)
  Bridge.BRIDGES = {
    LAYOUT_ROUTE110 = { deck = 4, both = 15, apart = { { 14, 12, 6, 5 }, { 15, 84, 6, 5 }, { 9, 61, 5, 6 } } },
  }

  local DECK = 40         -- px: the deck's road over the ground
  local RAIL = 13         -- px: the rails' height over the deck (the drawing's)
  local NORTH_RAIL = 14   -- px: the north rail's, drawn without the front's top highlight
  local GIRDER = 18       -- px: kerb and girder under the deck's south edge, and as deep down its
                          -- other sides
  local SLAB = 4          -- px: the deck's own thickness between its girders
  local RAMP_RUN = 56     -- px: what a ramp runs south while it falls DECK
  local SIDE = 10         -- px: the most a side rail's strip is wide
  local RAMP_SIDE = 16    -- px: a ramp's rails, drawn coming down beside it
  local INSET = 0.25      -- px: a face the drawing never shows, behind the one it meets
  local BEHIND = 1.0      -- px: the deck under the south rail, and its underside, short of the front
  local LINE = 0x62627b                               -- the outline round the deck
  local ROAD = { [0xbdcde6] = true, [0xdee6ee] = true }
  local SHADE = 0x9cb4de                              -- the road's shading, and the rails' too
  local ZONE = 4          -- cells round the deck searched for its parts
  local FLANK_ROWS = RAIL + GIRDER
  local ROAD_ROWS = 19
  local NUM_PRIMARY = 512
  Bridge.DECK = DECK

  -- ── keys ───────────────────────────────────────────────────────────────────

  -- a pixel (u, v), a cell (x, y)
  local PAD, ST = 512, 8192
  local function P(u, v) return (v + PAD) * ST + u + PAD end
  local function PU(k) return k % ST - PAD end
  local function PV(k) return floor(k / ST) - PAD end
  local function C(x, y) return (y + 64) * 4096 + x + 64 end
  local function CX(k) return k % 4096 - 64 end
  local function CY(k) return floor(k / 4096) - 64 end
  local function trunc(x) return x >= 0 and floor(x) or ceil(x) end
  -- Python's round (half to even)
  local function pyround(x)
    local f = floor(x)
    local d = x - f
    if d > 0.5 then return f + 1 end
    if d < 0.5 then return f end
    return (f % 2 == 0) and f or f + 1
  end
  local function green(c)
    local r, g, b = floor(c / 65536), floor(c / 256) % 256, c % 256
    return g > r + 16 and g > b + 16
  end

  --- Consecutive runs of sorted integers: { { first, last } }.
  local function runs(values)
    local out = {}
    for _, v in ipairs(values) do
      local last = out[#out]
      if last and v == last[2] + 1 then last[2] = v else out[#out + 1] = { v, v } end
    end
    return out
  end
  Bridge.runs = runs

  --- [a, b) cut where a cell of the map ends: { { a, e } }.
  local function split(a, b, size)
    size = size or 16
    local out = {}
    while a < b do
      local e = min(b, (floor(a / size) + 1) * size)
      out[#out + 1] = { a, e }
      a = e
    end
    return out
  end
  Bridge.split = split

  local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
  end

  -- pixel keys in (u, v) order, as Python sorts (u, v) tuples
  local function uvLess(a, b)
    local ua, ub = PU(a), PU(b)
    if ua ~= ub then return ua < ub end
    return PV(a) < PV(b)
  end

  --- u -> its v's in a set of pixels, sorted; and the u's, sorted. (tick: called now and then)
  local function columns(set, tick)
    local cols, us = {}, {}
    local n = 0
    for p in pairs(set) do
      n = n + 1
      if tick and n % 4096 == 0 then tick("columns of") end
      local u = PU(p)
      local c = cols[u]
      if not c then c = {}; cols[u] = c; us[#us + 1] = u end
      c[#c + 1] = PV(p)
    end
    table.sort(us)
    for i, u in ipairs(us) do
      table.sort(cols[u])
      if tick and i % 64 == 0 then tick("columns sorted") end
    end
    return cols, us
  end
  --- v -> its u's, sorted; and the v's, sorted.
  local function rowsOf(set, tick)
    local rows, vs = {}, {}
    local n = 0
    for p in pairs(set) do
      n = n + 1
      if tick and n % 4096 == 0 then tick("rows of") end
      local v = PV(p)
      local r = rows[v]
      if not r then r = {}; rows[v] = r; vs[#vs + 1] = v end
      r[#r + 1] = PU(p)
    end
    table.sort(vs)
    for i, v in ipairs(vs) do
      table.sort(rows[v])
      if tick and i % 64 == 0 then tick("rows sorted") end
    end
    return rows, vs
  end

  --- The value nearest `z` in a list (the first of the nearest), or nil.
  local function nearest(list, z)
    local best, bd
    for _, w in ipairs(list or {}) do
      local d = abs(w - z)
      if not bd or d < bd then best, bd = w, d end
    end
    return best
  end

  --- Python's Counter(values).most_common(1): the commonest value (the first seen of a tie) and
  --- its count; values may be false (Python's None).
  local function commonest(values)
    local n, order = {}, {}
    for _, v in ipairs(values) do
      if n[v] == nil then n[v] = 0; order[#order + 1] = v end
      n[v] = n[v] + 1
    end
    local best, bn = nil, -1
    for _, v in ipairs(order) do
      if n[v] > bn then best, bn = v, n[v] end
    end
    return best, bn
  end

  -- ── the drawing ────────────────────────────────────────────────────────────

  local BR = {}
  BR.__index = BR

  --- The cells within r of the deck: { [C(x, y)] = true }.
  function BR:near(r)
    self._near = self._near or {}
    local s = self._near[r]
    if s then return s end
    s = {}
    for _, c in ipairs(self.deckList) do
      local x, y = CX(c), CY(c)
      for dy = -r, r do
        for dx = -r, r do s[C(x + dx, y + dy)] = true end
      end
    end
    self._near[r] = s
    return s
  end

  -- whether a metatile draws anything on its upper layer
  function BR:upperDrawn(m)
    local hit = self._upper[m]
    if hit ~= nil then return hit end
    hit = false
    local high = self.io.subtiles(m, 1)
    for q = 0, 3 do
      local blk = high[q]
      for k = 0, 63 do
        local i = blk[64 + k]
        if i and i ~= 0 then hit = true; break end
      end
      if hit then break end
    end
    self._upper[m] = hit
    return hit
  end

  -- a metatile's lower-layer block q as a key (its 64 colours)
  function BR:blockKey(m, q)
    local key = m * 4 + q
    local hit = self._blocks[key]
    if hit then return hit end
    local blk = self.io.subtiles(m, 0)[q]
    local t = {}
    for k = 0, 63 do t[k + 1] = blk[k] or -1 end
    hit = table.concat(t, ",")
    self._blocks[key] = hit
    return hit
  end
  -- its 64 colours as a set
  function BR:blockColours(m, q)
    local blk = self.io.subtiles(m, 0)[q]
    local out = {}
    for k = 0, 63 do if blk[k] then out[blk[k]] = true end end
    return out
  end

  --- { metatile = true } of the layout's plain ground: drawn away from the road with nothing on
  --- its upper layer; its order, counts and which are water kept.
  function BR:plainGrounds()
    if self._plain then return self._plain, self._plainOrder end
    local io = self.io
    local out, order = {}, {}
    self.counts, self.water = {}, {}
    local far = self:near(ZONE + 1)
    for y = 0, self.h - 1 do
      for x = 0, self.w - 1 do
        if not far[C(x, y)] then
          local m = io.metatile(x, y)
          if not self:upperDrawn(m) and not (io.blocked(x, y) and io.role(x, y) ~= "water") then
            if not out[m] then out[m] = true; order[#order + 1] = m end
            self.counts[m] = (self.counts[m] or 0) + 1
            if io.role(x, y) == "water" then self.water[m] = true end
          end
        end
      end
    end
    self._plain, self._plainOrder = out, order
    return out, order
  end

  --- The plain ground of the primary tileset drawn anywhere (the shadowed water by the road too),
  --- for what lies under the road's cells: its order.
  function BR:plainAnywhere()
    if self._anywhere then return self._anywhere, self._anywhereOrder end
    local plain, porder = self:plainGrounds()
    local io = self.io
    local out, order = {}, {}
    for _, m in ipairs(porder) do out[m] = true; order[#order + 1] = m end
    for y = 0, self.h - 1 do
      for x = 0, self.w - 1 do
        local m = io.metatile(x, y)
        if not (out[m] or m >= NUM_PRIMARY or self.deck[C(x, y)]) and not self:upperDrawn(m) then
          local role = io.role(x, y)
          if role == "water" or role == "floor" then
            out[m] = true
            order[#order + 1] = m
            if role == "water" then self.water[m] = true end
          end
        end
      end
    end
    self._anywhere, self._anywhereOrder = out, order
    return out, order
  end

  --- Rows where a curb (the curb component's stones, a lawn's edge) goes on under the deck: a run
  --- of at most 8 cells, a deck's among them, between two cells of the same curb tile.
  --- self.curbs { { y, x0, x1, tile } }; self.curbPx { [P] = colour } of the stones drawn in
  --- those cells, joined to the stones either side.
  function BR:readCurbs(tick)
    tick = tick or function() end
    local io = self.io
    local spec = io.curb
    local tiles = {}
    for t in pairs(spec.tiles) do if not (spec.fill and spec.fill[t]) then tiles[t] = true end end
    local lawn = io.cellImage(spec.ground)
    self.curbs, self.curbPx = {}, {}
    for y = 0, self.h - 1 do
      tick("curbs")
      local x = 0
      while x < self.w do
        local t = io.metatile(x, y)
        local x1 = x + 1
        while x1 < self.w and not tiles[io.metatile(x1, y)] do x1 = x1 + 1 end
        local ok = tiles[t] and x1 < self.w and io.metatile(x1, y) == t and x1 - x - 1 >= 1 and x1 - x - 1 <= 8
        if ok then
          ok = false
          for c = x + 1, x1 - 1 do if self.deck[C(c, y)] then ok = true end end
        end
        if not ok then
          x = tiles[t] and x1 or x + 1
        else
          local tile = io.cellImage(t)
          local same = {}
          for c = x + 1, x1 - 1 do
            local drawn = io.cellImage(io.metatile(c, y))
            for j = 0, 15 do
              for i = 0, 15 do
                local k = j * 16 + i
                if tile[k] ~= lawn[k] and drawn[k] == tile[k] then same[P(c * 16 + i, y * 16 + j)] = drawn[k] end
              end
            end
          end
          -- joined to the stones beside the run
          local todo, seen = {}, {}
          for p in pairs(same) do
            local u = PU(p)
            if u == (x + 1) * 16 or u == x1 * 16 - 1 then todo[#todo + 1] = p end
          end
          while #todo > 0 do
            local p = remove(todo)
            if not seen[p] then
              seen[p] = true
              for _, q in ipairs({ p + 1, p - 1, p + ST, p - ST }) do
                if same[q] and not seen[q] then todo[#todo + 1] = q end
              end
            end
          end
          for p in pairs(seen) do self.curbPx[p] = same[p] end
          self.curbs[#self.curbs + 1] = { y, x + 1, x1, t }
          x = x1
        end
      end
    end
  end

  --- Curb tile t's stones alone: an art (16 x 16, kernel floats) clear where it draws the lawn.
  function BR:curbStones(t)
    local io = self.io
    local tile, lawn = io.cellImage(t), io.cellImage(io.curb.ground)
    local art = { w = 16, h = 16, px = {} }
    for k = 0, 255 do
      local o = k * 4
      local c = tile[k]
      if c == lawn[k] then
        art.px[o + 1], art.px[o + 2], art.px[o + 3], art.px[o + 4] = 0, 0, 0, 0
      else
        art.px[o + 1], art.px[o + 2], art.px[o + 3], art.px[o + 4] =
          floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255, 1
      end
    end
    return art
  end

  function BR:readDrawing(tick)
    local io, W, H = self.io, self.w, self.h
    -- (a tick every 2048 steps of the loops over the whole drawing)
    local nstep = 0
    local function step(label)
      nstep = nstep + 1
      if nstep % 2048 == 0 then tick(label) end
    end
    -- the ground: the blocks of the plain ground drawn away from the road
    local ground = {}
    local _, porder = self:plainGrounds()
    for _, m in ipairs(porder) do
      for q = 0, 3 do ground[self:blockKey(m, q)] = true end
    end
    tick("ground")
    -- and the colours seen through the rails and round the piers: those of the commonest plain
    -- water and plain land
    local freq = { water = { n = {}, order = {} }, floor = { n = {}, order = {} } }
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local m = io.metatile(x, y)
        local f = not self.deck[C(x, y)] and freq[io.role(x, y)]
        if f and not self:upperDrawn(m) then
          if not f.n[m] then f.n[m] = 0; f.order[#f.order + 1] = m end
          f.n[m] = f.n[m] + 1
        end
      end
    end
    local groundColours = {}
    for _, role in ipairs({ "water", "floor" }) do
      local f = freq[role]
      local list = {}
      for i, m in ipairs(f.order) do list[i] = { m, f.n[m], i } end
      table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[3] < b[3] end)
      for i = 1, min(2, #list) do
        for q = 0, 3 do
          for c in pairs(self:blockColours(list[i][1], q)) do groundColours[c] = true end
        end
      end
    end
    self.groundColours = groundColours
    tick("colours")
    local zone = self:near(ZONE)
    local px = {}
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if zone[C(x, y)] then
          local m = io.metatile(x, y)
          local low, high = io.subtiles(m, 0), io.subtiles(m, 1)
          for q = 0, 3 do
            local isGround = ground[self:blockKey(m, q)]
            local lo, hi = low[q], high[q]
            local bx, by = x * 16 + (q % 2) * 8, y * 16 + floor(q / 2) * 8
            for k = 0, 63 do
              local p = P(bx + k % 8, by + floor(k / 8))
              local i1 = hi[64 + k]
              if i1 and i1 ~= 0 then px[p] = hi[k]
              elseif not isGround then px[p] = lo[k] end
            end
          end
        end
      end
      tick("zone row")
    end
    -- a lawn's curb going on under the deck: its stones are not the bridge's
    self:readCurbs(tick)
    for p in pairs(self.curbPx) do if px[p] ~= nil then px[p] = false end end
    -- the road: its light colours flooded from the deck cells' middles
    local road, todo = {}, {}
    for _, c in ipairs(self.deckList) do
      local p = P(CX(c) * 16 + 8, CY(c) * 16 + 8)
      if ROAD[px[p]] then todo[#todo + 1] = p end
    end
    while #todo > 0 do
      local p = remove(todo)
      if not road[p] then
        road[p] = true
        for _, q in ipairs({ p + 1, p - 1, p + ST, p - ST }) do
          if not road[q] and ROAD[px[q]] then todo[#todo + 1] = q end
        end
      end
      step("road flood")
    end
    tick("road")
    -- a signpost standing on the deck: the deck goes on under it, laid with the plain road where
    -- the sign is drawn
    self.underSign, self.signCells = {}, {}
    local deck = self.deck
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if io.role(x, y) == "signpost" and ((deck[C(x - 1, y)] and deck[C(x + 1, y)])
            or (deck[C(x, y - 1)] and deck[C(x, y + 1)])) then
          self.signCells[C(x, y)] = true
          for j = 0, 15 do
            for i = 0, 15 do
              local p = P(x * 16 + i, y * 16 + j)
              road[p] = true
              local c = px[p]
              if not (ROAD[c] or c == SHADE) then
                self.underSign[p] = true
                px[p] = false
              end
            end
          end
        end
      end
    end
    -- its shading by the rails, a third colour, in stripes between its own (and between the road
    -- and the outline at a rail's foot)
    for _ = 1, 2 do
      local more = {}
      for p, c in pairs(px) do
        step("stripes")
        if c == SHADE and not road[p] and ((road[p + 1] and road[p - 1]) or (road[p + ST] and road[p - ST])
            or (road[p + 1] and px[p - 1] == LINE) or (road[p - 1] and px[p + 1] == LINE)) then
          more[#more + 1] = p
        end
      end
      for _, p in ipairs(more) do road[p] = true end
    end
    -- a rail's post or bar drawn in the road's colours beside it is not road
    local thin = {}
    for p in pairs(road) do
      if (not road[p + 1] and not road[p - 1]) or (not road[p + ST] and not road[p - ST]) then thin[#thin + 1] = p end
      step("thin")
    end
    for _, p in ipairs(thin) do road[p] = nil end
    tick("stripes")
    -- a block of the road drawn like the ground is still road: holes the flood went round
    local u0, u1, v0, v1
    for p in pairs(road) do
      local u, v = PU(p), PV(p)
      u0, u1 = u0 and min(u0, u) or u, u1 and max(u1, u) or u
      v0, v1 = v0 and min(v0, v) or v, v1 and max(v1, v) or v
    end
    local outside = {}
    todo = {}
    for v = v0 - 1, v1 + 1 do todo[#todo + 1] = P(u0 - 1, v) end
    while #todo > 0 do
      local p = remove(todo)
      local u, v = PU(p), PV(p)
      if not (outside[p] or road[p] or u < u0 - 1 or u > u1 + 1 or v < v0 - 1 or v > v1 + 1) then
        outside[p] = true
        todo[#todo + 1], todo[#todo + 2], todo[#todo + 3], todo[#todo + 4] = p + 1, p - 1, p + ST, p - ST
      end
      step("outside")
    end
    for v = v0, v1 do
      for u = u0, u1 do
        local p = P(u, v)
        if not road[p] and not outside[p] then
          road[p] = true
          if px[p] == nil then px[p] = false end
        end
      end
      tick("holes row")
    end
    outside = nil
    tick("holes")
    -- its colours: those drawn on the deck's cells and on the cells under its south side - not a
    -- tree's by it, nor a gatehouse's roof
    local palette = {}
    local NOT = { tree = true, wall = true, signpost = true }
    for _, c in ipairs(self.deckList) do
      local x, y = CX(c), CY(c)
      for dy = 0, 4 do
        local cy = y + dy
        if not (dy > 0 and (deck[C(x, cy)] or cy >= H or NOT[io.role(x, cy)])) then
          for j = 0, 15 do
            for i = 0, 15 do
              local rgb = px[P(x * 16 + i, cy * 16 + j)]
              if rgb and not groundColours[rgb] and not green(rgb) then palette[rgb] = true end
            end
          end
        end
      end
    end
    -- and the road's own tileset: a shore or a fence of the primary tileset beside a pier is drawn
    -- in the piers' browns and greys
    local houses, primary = self.apart, {}
    for c in pairs(zone) do
      local x, y = CX(c), CY(c)
      if x >= 0 and x < W and y >= 0 and y < H and io.metatile(x, y) < NUM_PRIMARY then primary[c] = true end
    end
    for p, c in pairs(px) do
      step("palette filter")
      local cell = C(floor(PU(p) / 16), floor(PV(p) / 16))
      if (not palette[c] or houses[cell] or primary[cell]) and not road[p] then px[p] = false end
    end
    tick("palette")
    -- the bridge: what is drawn touching the road, less the colours of the ground seen through
    -- its rails and round its piers
    local keep = {}
    todo = {}
    for p in pairs(road) do todo[#todo + 1] = p end
    while #todo > 0 do
      local p = remove(todo)
      if not keep[p] then
        keep[p] = true
        for _, q in ipairs({ p + 1, p - 1, p + ST, p - ST }) do
          local c = px[q]
          if not keep[q] and c and (road[q] or not groundColours[c]) then todo[#todo + 1] = q end
        end
      end
      step("keep flood")
    end
    self.road = road
    self.pixels, self.art = {}, {}
    for p in pairs(keep) do
      local c = px[p]
      if c then self.pixels[p], self.art[p] = c, c end
      step("pixels")
    end
    tick("keep")
    self:readRamps(tick)
    tick("ramps")
    self:readStrips(tick)
    tick("ramps+strips")
  end

  --- Runs of road that end on the land, not on a rail: a ramp, from the row its stripes turn
  --- across to its foot. self.ramps { { s0, s1, top, foot } }; self.ramp { [P(u, a)] = b }.
  function BR:readRamps(tick)
    local cols, us = columns(self.road, tick)
    self.ramp = {}
    local byFoot, footOrder = {}, {}
    for _, u in ipairs(us) do
      for _, r in ipairs(runs(cols[u])) do
        local a, b = r[1], r[2]
        local q = P(u, b + 1)
        if not (self.pixels[q] and not self.road[q]) then
          self.ramp[P(u, a)] = b
          if not byFoot[b] then byFoot[b] = {}; footOrder[#footOrder + 1] = b end
          byFoot[b][#byFoot[b] + 1] = u
        end
      end
    end
    -- where the stripes turn across: a ramp is a road's width, and its foot is on walkable land
    self.ramps = {}
    local io, road, art = self.io, self.road, self.art
    for _, foot in ipairs(footOrder) do
      local fus = byFoot[foot]
      table.sort(fus)
      for _, r in ipairs(runs(fus)) do
        local s0, s1 = r[1], r[2] + 1
        local fx, fy = floor(floor((s0 + s1) / 2) / 16), floor((foot + 1) / 16)
        if not (s1 - s0 < 16 or fy >= self.h or io.blocked(fx, fy) or io.role(fx, fy) == "water") then
          local function allRoad(v)
            for u = s0 + 2, s1 - 3 do if not road[P(u, v)] then return false end end
            return true
          end
          -- the road's stripes run down every row; the ramp's every other row is one colour across
          local function across(v)
            if not allRoad(v) then return false end
            local c0
            for u = s0 + 2, s1 - 3 do
              local c = art[P(u, v)] or 0
              if c0 == nil then c0 = c elseif c ~= c0 then return false end
            end
            return true
          end
          local top = foot
          while allRoad(top - 1) and (across(top - 1) or across(top - 2)) do top = top - 1 end
          self.ramps[#self.ramps + 1] = { s0, s1, top, foot + 1 }
        end
      end
    end
    -- a ramp's own columns only: the rest of the runs ending on nothing are a deck's edges
    local kept = {}
    for k, b in pairs(self.ramp) do
      if self:rampAt(PU(k), b) then kept[k] = b end
    end
    self.ramp = kept
  end

  -- ── heights ────────────────────────────────────────────────────────────────

  --- The ramp column u comes down by, near row v.
  function BR:rampAt(u, v)
    for _, r in ipairs(self.ramps) do
      if r[1] <= u and u < r[2] and self.rampHead(r) - 64 <= v and v < r[4] + 64 then return r end
    end
    return nil
  end

  --- The rows of a ramp's side columns built by cornerRamp.
  function BR.cornerRows(r) return r[3] - 16, r[4] end

  --- The art row a ramp begins falling at: RAMP_RUN + DECK rows over its drawn foot.
  function BR.rampHead(r) return min(r[3], r[4] - RAMP_RUN - DECK) end

  --- (z, h) of a ramp's surface where its art row v is laid.
  function BR:rampPoint(r, v)
    local head, foot = self.rampHead(r), r[4]
    local s = min(1.0, max(0.0, (v - head) / (foot - head)))
    return head + DECK + s * (foot - head - DECK), DECK * (1.0 - s)
  end

  --- The side rails' strips, every pixel of them (voxel_bridge _strips).
  function BR:readStrips(tick)
    tick = tick or function() end
    local rows, vs = rowsOf(self.road, tick)
    tick("strip rows")
    local straight, skeys = {}, {}
    for _, v in ipairs(vs) do
      for _, r in ipairs(runs(rows[v])) do
        for _, e in ipairs({ { -1, r[1] }, { 1, r[2] } }) do
          local key = e[2] * 4 + e[1] + 1
          if not straight[key] then straight[key] = { step = e[1], edge = e[2], vs = {} }; skeys[#skeys + 1] = key end
          local l = straight[key].vs
          l[#l + 1] = v
        end
      end
    end
    table.sort(skeys)
    self.stripPx, self.chamferCols, self.headRows = {}, {}, {}
    self.feet, self.innerHeads, self.stripCols = {}, {}, {}
    self.headRowKeys = {}
    local pixels, road = self.pixels, self.road
    for ki, key in ipairs(skeys) do
      if ki % 16 == 0 then tick("strips read") end
      local st = straight[key]
      local step, edge = st.step, st.edge
      for _, r in ipairs(runs(st.vs)) do
        local v0, v1 = r[1], r[2]
        local skip = v1 - v0 < 7
        if not skip then
          for _, rp in ipairs(self.ramps) do
            if rp[1] - RAMP_SIDE <= edge and edge < rp[2] + RAMP_SIDE and rp[3] - 16 <= v1 and v0 < rp[4] then skip = true end
          end
        end
        if not skip then
          local cols = self:stripColumns(edge, step, v0, v1)
          if #cols < 6 and v1 - v0 >= 16 then
            -- a pier's head drawn over the strip's foot hides its columns there: read from its
            -- first cell's worth of rows
            local first = self:stripColumns(edge, step, v0, v0 + 15)
            if #first >= 6 then cols = first end
          end
          local side = step > 0 and "e" or "w"
          local head, outer, nhead, nouter = {}, {}, 0, 0
          for v = v0, v1 do self.stripCols[side .. ":" .. edge .. ":" .. v] = cols end
          self.stripColsList = self.stripColsList or {}
          self.stripColsList[#self.stripColsList + 1] = { side, edge, v0, v1, cols }
          for _, c in ipairs(cols) do
            for v = v0, v1 do if pixels[P(c, v)] then self.stripPx[P(c, v)] = true end end
            -- up to the road over it, when there is one near (an inner corner), or to the end of
            -- the drawing (an outer one)
            local w = v0 - 1
            while pixels[P(c, w)] and not road[P(c, w)] and w > v0 - RAIL - GIRDER - 8 do w = w - 1 end
            if road[P(c, w)] then
              for v = w + 1, v0 - 1 do self.stripPx[P(c, v)] = true end
              head[c] = w + 1
              nhead = nhead + 1
            elseif not pixels[P(c, w)] then
              outer[c] = w + 1
              nouter = nouter + 1
            end
          end
          -- and down from its last row, where the front turns into it at an outer corner
          local foot, nfoot = {}, 0
          for _, c in ipairs(cols) do
            local w = v1 + 1
            while pixels[P(c, w)] and not road[P(c, w)] and w < v1 + RAIL + GIRDER + 16 do w = w + 1 end
            if not pixels[P(c, w)] and not road[P(c, w)] and w > v1 + 1 then
              foot[c] = { v1 + 1, w }
              nfoot = nfoot + 1
            end
          end
          if #cols >= 6 and nfoot >= #cols - 1 then
            self.feet[#self.feet + 1] = { side = side, edge = edge, last = v1, foot = foot, cols = cols }
          end
          local minHead, minOuter
          for _, w in pairs(head) do minHead = minHead and min(minHead, w) or w end
          for _, w in pairs(outer) do minOuter = minOuter and min(minOuter, w) or w end
          if #cols > 0 and nhead == #cols and minHead < v0 then
            self:chamferHead(step, cols, head, v0)
            if #cols >= 6 then
              local lo, hi = cols[1], cols[1]
              for _, c in ipairs(cols) do lo, hi = min(lo, c), max(hi, c) end
              self.innerHeads[#self.innerHeads + 1] = { side = side, s0 = lo, s1 = hi + 1, v0 = v0, head = head }
            end
          elseif #cols >= 6 and nouter == #cols and minOuter < v0 then
            for c, w in pairs(outer) do
              for v = w, v0 - 1 do self.stripPx[P(c, v)] = true end
            end
            for v = minOuter, v0 - 1 do
              local hk = side .. ":" .. v
              if not self.headRows[hk] then
                self.headRows[hk] = {}
                self.headRowKeys[#self.headRowKeys + 1] = { side, v }
              end
              local cs = {}
              for _, c in ipairs(cols) do if outer[c] <= v then cs[#cs + 1] = c end end
              local l = self.headRows[hk]
              l[#l + 1] = cs
            end
          end
        end
      end
    end
  end

  --- The columns out from a road's edge drawn one colour down rows [v0, v1] (most of them), to
  --- the strip's outer outline.
  function BR:stripColumns(edge, step, v0, v1)
    local cols = {}
    for k = 1, SIDE do
      local c = edge + step * k
      local drawn = {}
      for v = v0, v1 do drawn[#drawn + 1] = self.pixels[P(c, v)] or false end
      local top, n = commonest(drawn)
      if top == false or n < 0.6 * #drawn then break end
      cols[#cols + 1] = c
      if k >= 6 and top == LINE then break end
    end
    return cols
  end

  --- An inner corner: the strip's head cut square to the chamfer that turns the front into it,
  --- at 45 degrees from the strip's outer side.
  function BR:chamferHead(step, cols, head, v0)
    local outer = cols[1]
    for _, c in ipairs(cols) do
      if step > 0 then outer = max(outer, c) else outer = min(outer, c) end
    end
    local r0
    for _, c in ipairs(cols) do
      local t = head[c] - abs(c - outer)
      r0 = r0 and min(r0, t) or t
    end
    for _, c in ipairs(cols) do
      for v = r0 + abs(c - outer), head[c] - 1 do
        local p = P(c, v)
        if self.road[p] and self.pixels[p] then
          self.road[p] = nil
          self.stripPx[p] = true
        end
      end
    end
    for _, c in ipairs(cols) do
      self.chamferCols[P(c, r0 + abs(c - outer))] = { r0 - step * (c - outer - 0.5), r0 - step * (c + 1 - outer - 0.5) }
    end
  end

  function BR:besideRamp(u, v)
    for _, r in ipairs(self.ramps) do
      if r[1] - RAMP_SIDE <= u and u < r[2] + RAMP_SIDE and r[3] <= v and v < r[4] then return true end
    end
    return false
  end

  -- ── geometry ───────────────────────────────────────────────────────────────

  local function face(pts, uvs, tag, at) return { pts = pts, uvs = uvs, tag = tag, at = at } end
  local function cellOf(at) return floor(trunc(at[1]) / 16), floor(trunc(at[2]) / 16) end
  local function endsWith(s, e) return s:sub(-#e) == e end
  local function startsWith(s, b) return s:sub(1, #b) == b end
  local function copyPts(pts)
    local out = {}
    for i, p in ipairs(pts) do out[i] = { p[1], p[2], p[3] } end
    return out
  end
  -- (x, z - y) of each point: the projection's uvs
  local function projUV(pts)
    local out = {}
    for i, p in ipairs(pts) do out[i] = { p[1], p[3] - p[2] } end
    return out
  end
  local function rep(at, n)
    local out = {}
    for i = 1, n do out[i] = { at[1], at[2] } end
    return out
  end

  --- Every face as { pts, uvs, tag, at }: points (x, y, z) in pixels of the map, uvs in pixels of
  --- its art, `at` the art pixel it is filed under (voxel_bridge Bridge.quads).
  function BR:quads(tick)
    local out = {}
    local road, pix, art = self.road, self.pixels, self.art
    local cols, us = columns(road, tick)
    tick("road columns")
    local claimed = {}
    for p in pairs(road) do claimed[p] = true end
    tick("claimed")
    self.patchPx = {}
    -- the curb's stones drawn in the deck's cells: the curb laid under the bridge draws them
    for p, rgb in pairs(self.curbPx) do
      art[p] = rgb
      claimed[p] = true
    end

    -- pixel p laid on the ground as drawn: a patch of the placement's ground
    local function lay(p, rgb)
      if rgb == nil then
        rgb = art[p]
        pix[p] = nil
        art[p] = nil
      end
      self.patchPx[p] = rgb
      claimed[p] = true
    end
    -- an opaque texel of the cell `at` is in: nearest down its column, else anywhere in the cell
    local function texel(at)
      local u, v = at[1], at[2]
      local c0, r0 = floor(u / 16) * 16, floor(v / 16) * 16
      for w = v, r0 + 15 do if pix[P(u, w)] then return { u, w } end end
      for w = r0, v - 1 do if pix[P(u, w)] then return { u, w } end end
      for j = r0, r0 + 15 do
        for i = c0, c0 + 15 do if pix[P(i, j)] then return { i, j } end end
      end
      return at
    end
    -- the cell's darkest texel: the girder's shade, for what is under the deck
    local function darkest(at)
      local c0, r0 = floor(trunc(at[1]) / 16) * 16, floor(trunc(at[2]) / 16) * 16
      local best, bs
      for j = r0, r0 + 15 do
        for i = c0, c0 + 15 do
          local c = pix[P(i, j)]
          if c then
            local s = floor(c / 65536) + floor(c / 256) % 256 + c % 256
            -- (ties: the least (i, j), as Python's min over (sum, (i, j)))
            if not bs or s < bs or (s == bs and (i < best[1] or (i == best[1] and j < best[2]))) then
              best, bs = { i, j }, s
            end
          end
        end
      end
      return best or texel(at)
    end
    local function put(pts, uvs, tag, at)
      if endsWith(tag, "~clamp") then
        -- never seen at 45 degrees: one texel of its own cell
        local t
        if startsWith(tag, "deck.under") or startsWith(tag, "deck.girder") then t = darkest(at) else t = texel(at) end
        uvs = rep({ t[1] + 0.5, t[2] + 0.5 }, #pts)
      end
      out[#out + 1] = face(pts, uvs, tag, at)
    end
    self._put = put
    -- art rows [v0, v1) of column u on the face standing at z - or z = { left, right }, a
    -- diagonal wall; a row whose middle the wall would stand at the ground or under it is laid on
    -- the ground
    local function upright(u, z, v0, v1, tag)
      local zl, zr
      if type(z) == "table" then zl, zr = z[1], z[2] else zl, zr = z, z end
      local ground = {}
      for v = v0, v1 - 1 do
        if (zl + zr) / 2.0 - (v + 0.5) <= 1e-6 then ground[#ground + 1] = v end
      end
      if #ground > 0 then v1 = min(v1, ground[1]) end
      for _, v in ipairs(ground) do
        if pix[P(u, v)] then lay(P(u, v)) end
      end
      for _, s in ipairs(split(v0, v1)) do
        local a, b = s[1], s[2]
        put({ { u, zl - b, zl }, { u + 1, zr - b, zr }, { u + 1, zr - a, zr }, { u, zl - a, zl } },
          { { u, b }, { u + 1, b }, { u + 1, a }, { u, a } }, tag, { u, a })
      end
    end
    self._upright, self._texel = upright, texel

    -- the depth each column's south and north edge stands at, before any face is laid
    local south, north = {}, {}
    for _, u in ipairs(us) do
      for _, r in ipairs(runs(cols[u])) do
        local a, b = r[1], r[2]
        north[u] = north[u] or {}
        north[u][#north[u] + 1] = a + DECK
        local kerb = b + 1 + RAIL
        for v = b + 1, b + RAIL + 4 do
          if pix[P(u, v)] == LINE then kerb = v; break end
        end
        south[u] = south[u] or {}
        south[u][#south[u] + 1] = kerb + DECK
      end
    end
    self._south, self._north = south, north
    -- (left, right) depths of column u's edge at z, met halfway with its neighbours' where they
    -- step by at most 2 pixels
    local function sides(edges, u, z)
      local res = {}
      for i, nb in ipairs({ u - 1, u + 1 }) do
        local best, bd
        for _, w in ipairs(edges[nb] or {}) do
          local d = abs(w - z)
          if d <= 2 and (not bd or d < bd) then best, bd = w, d end
        end
        res[i] = best and (z + best) / 2.0 or z
      end
      return res[1], res[2]
    end
    self._sides = sides

    for ui, u in ipairs(us) do
      for _, r in ipairs(runs(cols[u])) do
        local a, b = r[1], r[2] + 1
        local ramp = self:rampAt(u, b - 1)
        local sloped = self.ramp[P(u, a)] ~= nil and ramp ~= nil
        local flat = sloped and max(a, self.rampHead(ramp)) or b
        -- the deck's road, flat (the plain road under a signpost)
        for _, s in ipairs(split(a, flat)) do
          local plainV, signV = {}, {}
          for v = s[1], s[2] - 1 do
            if self.underSign[P(u, v)] then signV[#signV + 1] = v else plainV[#plainV + 1] = v end
          end
          for _, rr in ipairs(runs(plainV)) do
            local p, q = rr[1], rr[2] + 1
            put({ { u, DECK, p + DECK }, { u + 1, DECK, p + DECK }, { u + 1, DECK, q + DECK }, { u, DECK, q + DECK } },
              { { u, p }, { u + 1, p }, { u + 1, q }, { u, q } }, "deck.top", { u, p })
          end
          for _, rr in ipairs(runs(signV)) do
            local p, q = rr[1], rr[2]
            local pts = { { u, DECK, p + DECK }, { u + 1, DECK, p + DECK }, { u + 1, DECK, q + 1 + DECK }, { u, DECK, q + 1 + DECK } }
            put(pts, projUV(pts), "deck.top_under_sign~depth~road", { u, p })
          end
        end
        -- north: the rail over the road, standing on its edge
        local n0 = a
        while pix[P(u, n0 - 1)] and not claimed[P(u, n0 - 1)] and a - n0 < RAIL + SIDE do n0 = n0 - 1 end
        local zn = a + DECK
        local znl, znr = sides(north, u, zn)
        if n0 < a then
          upright(u, { znl, znr }, n0, a, "deck.rail_n")
          for v = n0, a - 1 do claimed[P(u, v)] = true end
        end
        -- the girder under it, which the drawing never shows
        put({ { u + 1, DECK - GIRDER, znr }, { u, DECK - GIRDER, znl }, { u, DECK, znl }, { u + 1, DECK, znr } },
          rep({ u, a }, 4), "deck.flank_girdern_n~depth", { u, a })
        local zs, zsl, zsr
        if sloped then
          -- the ramp: its rows from its head in the deck down to its foot
          for _, s in ipairs(split(flat, b)) do
            local p, q = s[1], s[2]
            local zp, hp = self:rampPoint(ramp, p)
            local zq, hq = self:rampPoint(ramp, q)
            put({ { u, hp, zp }, { u + 1, hp, zp }, { u + 1, hq, zq }, { u, hq, zq } },
              { { u, p }, { u + 1, p }, { u + 1, q }, { u, q } }, "deck.ramp~proj", { u, p })
          end
          zs = flat + DECK
          zsl, zsr = zs, zs
        else
          -- south: the rail, the kerb, the girder and the piers, one face standing on the deck's
          -- edge; the kerb is the outline a rail's height under the road
          local kerb = b + RAIL
          for v = b, b + RAIL + 3 do
            if pix[P(u, v)] == LINE then kerb = v; break end
          end
          zs = kerb + DECK
          zsl, zsr = sides(south, u, zs)
          -- down to the piers' feet; not a ramp's side rails, nor a span's side rail going on south
          local mine = {}
          for v = b, zs - 1 do
            local p = P(u, v)
            if pix[p] and not claimed[p] and not self:besideRamp(u, v) and not self.stripPx[p] then mine[#mine + 1] = v end
          end
          if #mine == 0 then
            -- no front under this column: the road meets a span's side rail going on south
            kerb = b + RAIL
            zs = kerb + DECK
            zsl, zsr = zs, zs
            local ch = self.chamferCols[P(u, b)]
            if ch then zsl, zsr = ch[1] + RAIL + DECK, ch[2] + RAIL + DECK end
          end
          for _, rr in ipairs(runs(mine)) do upright(u, { zsl, zsr }, rr[1], rr[2] + 1, "deck.front") end
          for _, v in ipairs(mine) do claimed[P(u, v)] = true end
          -- the road goes on under the rail to the edge (laid with the plain road)
          for _, s in ipairs(split(b, kerb)) do
            local p, q = s[1], s[2]
            local far1, far2
            if q < kerb then far1, far2 = q + DECK, q + DECK else far1, far2 = zsl - BEHIND, zsr - BEHIND end
            local pts = { { u, DECK, p + DECK }, { u + 1, DECK, p + DECK }, { u + 1, DECK, far2 }, { u, DECK, far1 } }
            put(pts, projUV(pts), "deck.top_under_rail~depth~road", { u, p })
          end
        end
        -- the slab's underside, cell by cell of the rows over it, from the north edge to the south
        local low = DECK - SLAB
        for _, s in ipairs(split(a, zs - DECK)) do
          local p, q = s[1], s[2]
          local n1, n2, f1, f2
          if p == a then n1, n2 = znl, znr else n1, n2 = p + DECK, p + DECK end
          if q == zs - DECK then f1, f2 = zsl - BEHIND, zsr - BEHIND else f1, f2 = q + DECK, q + DECK end
          put({ { u, low, f1 }, { u + 1, low, f2 }, { u + 1, low, n2 }, { u, low, n1 } },
            { { u, p }, { u + 1, p }, { u + 1, p + 1 }, { u, p + 1 } }, "deck.under~depth~clamp", { u, p })
        end
      end
      if ui % 16 == 0 then tick("columns") end
    end
    tick("columns done")

    -- west and east: the side rails' strips, seen from above at their top; the rail's two faces
    -- and the girder under it dressed with the south front's own rail and girder
    local rows, rvs = rowsOf(road, tick)
    local function flank(kind, facing, x, y0, y1, z0, z1, at)
      local xa, xb
      if type(x) == "table" then xa, xb = x[1], x[2] else xa, xb = x, x end
      local d = facing == "w" and INSET or -INSET
      xa, xb = xa + d, xb + d
      y0, y1 = y0 - INSET, y1 - INSET
      put({ { xa, y0, z0 }, { xb, y0, z1 }, { xb, y1, z1 }, { xa, y1, z0 } }, rep(at, 4),
        "deck.flank_" .. kind .. "_" .. facing .. "~depth", at)
    end
    self._flank = flank

    -- an outer corner's chamfer: the front turned at 45 degrees from the deck's south edge to the
    -- strip's outer side, the strip's last rows cut along it
    local cuts = {}
    for i, ft in ipairs(self.feet) do
      local side, edge, last, foot = ft.side, ft.edge, ft.last, ft.foot
      local fronts = south[edge]
      if fronts and #fronts > 0 then
        local zs = nearest(fronts, last + 1 + RAIL + DECK)
        local zl0, zr0 = sides(south, edge, zs)
        local zEdge = side == "w" and zl0 or zr0
        local bottom = 0.0
        local fcols = sortedKeys(foot)
        for _, c in ipairs(fcols) do
          local a, b = foot[c][1], foot[c][2]
          local k = abs(edge - c)
          local zl, zr
          if side == "w" then zl, zr = zEdge - k, zEdge - k + 1 else zl, zr = zEdge - k + 1, zEdge - k end
          local first = ceil((zl + zr) / 2.0 - DECK - RAIL - 0.5)
          local rws = {}
          for v = min(first, a), b - 1 do
            if v >= first and pix[P(c, v)] and not claimed[P(c, v)] then rws[#rws + 1] = v end
          end
          for _, rr in ipairs(runs(rws)) do upright(c, { zl, zr }, rr[1], rr[2] + 1, "deck.front") end
          for _, v in ipairs(rws) do claimed[P(c, v)] = true end
          if #rws > 0 then bottom = max(bottom, max(zl, zr) - rws[#rws] - 1) end
        end
        if side == "w" then
          cuts[i] = { -1.0, zEdge - edge, bottom, fcols[1] - SIDE, edge, zEdge }
        else
          cuts[i] = { 1.0, zEdge + edge + 1, bottom, edge + 1, fcols[#fcols] + 1 + SIDE, zEdge }
        end
      end
    end
    -- the strips row by row, gathered first - { s0, s1, inner side's x, outer side's x, art pixel }
    -- by (side, row) - and laid once every row's are known
    local strips = {}
    local function addStrip(side, v, e)
      local k = side .. ":" .. v
      strips[k] = strips[k] or {}
      local l = strips[k]
      l[#l + 1] = e
    end
    -- the heads of the strips at an outer corner: drawn up to the chamfer that turns them into the
    -- north rail, away from the road
    local hkeys = {}
    for _, hk in ipairs(self.headRowKeys) do hkeys[#hkeys + 1] = hk end
    table.sort(hkeys, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    for _, hk in ipairs(hkeys) do
      local side, v = hk[1], hk[2]
      for _, cs in ipairs(self.headRows[side .. ":" .. v]) do
        local strip = {}
        for _, c in ipairs(cs) do if pix[P(c, v)] and not claimed[P(c, v)] then strip[#strip + 1] = c end end
        if #strip > 0 then
          for _, c in ipairs(strip) do claimed[P(c, v)] = true end
          local s0, s1 = strip[1], strip[1]
          for _, c in ipairs(strip) do s0, s1 = min(s0, c), max(s1, c) end
          s1 = s1 + 1
          if side == "w" then addStrip(side, v, { s0, s1, s1, s0, { strip[1], v } })
          else addStrip(side, v, { s0, s1, s0, s1, { strip[1], v } }) end
        end
      end
    end
    for vi, v in ipairs(rvs) do
      if vi % 64 == 0 then tick("strips gather") end
      for _, rr in ipairs(runs(rows[v])) do
        local l, r = rr[1], rr[2] + 1
        for _, sd in ipairs({ { "w", l, -1 }, { "e", r - 1, 1 } }) do
          local side, edge, step = sd[1], sd[2], sd[3]
          local outDir = side
          local xi = side == "w" and l or r
          local ramp
          for _, rp in ipairs(self.ramps) do
            if rp[1] - RAMP_SIDE <= edge and edge < rp[2] + RAMP_SIDE and rp[3] <= v and v < rp[4] then ramp = rp; break end
          end
          if ramp then
            -- the rails drawn coming down beside it are the slot's walls: claimed, not drawn
            for k = 1, RAMP_SIDE do
              local p = P(edge + step * k, v)
              if pix[p] then claimed[p] = true end
            end
          else
            -- the strip, through what of the ground shows in it - its own columns beside a span
            local cs = self.stripCols[side .. ":" .. edge .. ":" .. v]
            if not cs then
              cs = {}
              for k = 1, SIDE do cs[k] = edge + step * k end
            end
            local strip = {}
            for _, c in ipairs(cs) do if pix[P(c, v)] and not claimed[P(c, v)] then strip[#strip + 1] = c end end
            -- and on out over the strip's own pixels
            while #strip > 0 do
              local ext = strip[1]
              for _, c in ipairs(strip) do
                if side == "w" then ext = min(ext, c) else ext = max(ext, c) end
              end
              local c = ext + step
              local p = P(c, v)
              if abs(c - edge) > SIDE or not self.stripPx[p] or not pix[p] or claimed[p] then break end
              strip[#strip + 1] = c
            end
            if #strip == 0 then
              -- no rail drawn here (a chamfer's, standing on the front or the north edge): the
              -- deck's side
              flank("girder", outDir, xi, DECK - GIRDER, DECK, v + DECK, v + DECK + 1, { edge, v })
            else
              for _, c in ipairs(strip) do claimed[P(c, v)] = true end
              local s0, s1 = strip[1], strip[1]
              for _, c in ipairs(strip) do s0, s1 = min(s0, c), max(s1, c) end
              s1 = s1 + 1
              addStrip(side, v, { s0, s1, xi, side == "w" and s0 or s1, { strip[1], v } })
            end
          end
        end
      end
    end
    -- side k (3 inner, 4 outer) of a strip's row at x, at the row's top and foot: halfway to the
    -- rows over and under it where they step by a pixel the same way
    local function smooth(side, v, x, k)
      local near = {}
      for i, nv in ipairs({ v - 1, v + 1 }) do
        local got
        for _, e in ipairs(strips[side .. ":" .. nv] or {}) do
          if abs(e[k] - x) <= 1 then got = e[k]; break end
        end
        near[i] = got and got - x or 0
      end
      local up, down = near[1], -near[2]
      if up * down < 0 then up, down = 0, 0 end
      return { x + up / 2.0, x - down / 2.0 }
    end
    local h, top = DECK, DECK + RAIL
    local skeys = sortedKeys(strips)
    for si, sk in ipairs(skeys) do
      if si % 64 == 0 then tick("strip faces") end
      local side, v = sk:match("^(%a):(-?%d+)$")
      v = tonumber(v)
      local outDir, inDir = side, side == "w" and "e" or "w"
      local zt, zt1 = v + top, v + top + 1
      for _, e in ipairs(strips[sk]) do
        local s0, s1, xi, xo, at = e[1], e[2], e[3], e[4], e[5]
        local inner, outer = smooth(side, v, xi, 3), smooth(side, v, xo, 4)
        local touching = xi == (side == "w" and s1 or s0)
        local west, east
        if side == "w" then west, east = outer, touching and inner or { s1, s1 }
        else west, east = touching and inner or { s0, s0 }, outer end
        for _, s in ipairs(split(s0, s1)) do
          local c0, c1 = s[1], s[2]
          local cell = floor(c0 / 16) * 16
          local xw = c0 == s0 and { min(cell + 16, max(cell, west[1])), min(cell + 16, max(cell, west[2])) } or { c0, c0 }
          local xe = c1 == s1 and { min(cell + 16, max(cell, east[1])), min(cell + 16, max(cell, east[2])) } or { c1, c1 }
          local pts = { { xw[1], top, zt }, { xe[1], top, zt }, { xe[2], top, zt1 }, { xw[2], top, zt1 } }
          put(pts, projUV(pts), "deck.rail_side", { c0, v })
        end
        flank("rail", outDir, outer, h, top, zt, zt1, at)
        flank("rail", inDir, inner, h, top, zt, zt1, at)
        flank("girder", outDir, outer, h - GIRDER, h, zt, zt1, at)
        flank("under", inDir, inner, h - GIRDER, h - SLAB, zt, zt1, at)
        local quad = { { inner[1], h - GIRDER, zt }, { outer[1], h - GIRDER, zt }, { outer[2], h - GIRDER, zt1 }, { inner[2], h - GIRDER, zt1 } }
        if side == "w" then quad = { quad[4], quad[3], quad[2], quad[1] } end
        put(quad, rep(at, 4), "deck.under~depth~clamp", at)
      end
    end
    tick("strips")
    -- whatever else of it is drawn, touching what is placed: the piers beside a span or the
    -- deck's end, drawn beside the road
    local function byDeck(p)
      local u, v = PU(p), PV(p)
      for k = -16, 16 do if road[P(u + k, v)] then return true end end
      for k = 1, DECK + RAIL + GIRDER + 7 do if road[P(u, v - k)] then return true end end
      return false
    end
    local left = {}
    local nl = 0
    for p in pairs(pix) do
      if not claimed[p] and byDeck(p) then left[p] = true end
      nl = nl + 1
      if nl % 2048 == 0 then tick("left") end
    end
    local keep, todo = {}, {}
    for p in pairs(left) do
      local u, v = PU(p), PV(p)
      local touch = false
      for i = -1, 1 do
        for j = -1, 1 do if claimed[P(u + i, v + j)] then touch = true end end
      end
      if touch then todo[#todo + 1] = p end
    end
    while #todo > 0 do
      local p = remove(todo)
      if not keep[p] then
        keep[p] = true
        local u, v = PU(p), PV(p)
        for i = -1, 1 do
          for j = -1, 1 do
            local q = P(u + i, v + j)
            if (left[q] or (j == 1 and pix[q] and not claimed[q])) and not keep[q] then todo[#todo + 1] = q end
          end
        end
      end
    end
    -- what is not the road's in the cells the road's models stand on: laid on the ground as drawn;
    -- elsewhere the map paints it
    local owned = {}
    for p in pairs(pix) do
      if claimed[p] or keep[p] then owned[C(floor(PU(p) / 16), floor(PV(p) / 16))] = true end
    end
    local rest0 = {}
    for p in pairs(pix) do if not claimed[p] and not keep[p] then rest0[#rest0 + 1] = p end end
    for _, p in ipairs(rest0) do
      if not owned[C(floor(PU(p) / 16), floor(PV(p) / 16))] then
        pix[p], art[p] = nil, nil
      else
        lay(p)
      end
    end
    tick("rest laid")
    -- and what those cells draw that is no part of the bridge, in the colours it is not read in:
    -- the map lays its plain ground there, so whatever of the drawing that ground does not show is
    -- laid on it too
    local io = self.io
    local crossed = {}
    for _, cb in ipairs(self.curbs) do
      for x = cb[2], cb[3] - 1 do crossed[C(x, cb[1])] = true end
    end
    local cellsL = {}
    for c in pairs(owned) do if not self.signCells[c] then cellsL[#cellsL + 1] = c end end
    for c in pairs(crossed) do if not owned[c] and not self.signCells[c] then cellsL[#cellsL + 1] = c end end
    table.sort(cellsL, function(a, b)
      local xa, xb = CX(a), CX(b)
      if xa ~= xb then return xa < xb end
      return CY(a) < CY(b)
    end)
    for n, c in ipairs(cellsL) do
      local x, y = CX(c), CY(c)
      local drawn = io.cellImage(io.metatile(x, y))
      local plain = io.cellImage(self:groundFor(x, y))
      for j = 0, 15 do
        for i = 0, 15 do
          local p = P(x * 16 + i, y * 16 + j)
          local a, b = drawn[j * 16 + i], plain[j * 16 + i]
          if not (claimed[p] or pix[p] or (floor(a / 524288) == floor(b / 524288)
              and floor(a / 2048) % 32 == floor(b / 2048) % 32 and floor(a / 8) % 32 == floor(b / 8) % 32)) then
            lay(p, a)
          end
        end
      end
      if n % 32 == 0 then tick("patch cells") end
    end
    local rest = {}
    for p in pairs(pix) do if not claimed[p] then rest[p] = true end end
    for ci, comp in ipairs(self.components(rest)) do
      if ci % 16 == 0 then tick("components") end
      local u0, u1, v0, v1
      for _, p in ipairs(comp) do
        local u, v = PU(p), PV(p)
        u0, u1 = u0 and min(u0, u) or u, u1 and max(u1, u) or u
        v0, v1 = v0 and min(v0, v) or v, v1 and max(v1, v) or v
      end
      local width, height = u1 - u0 + 1, v1 - v0 + 1
      if width >= 4 and width <= 12 and height >= 20 then
        self:pier(comp, put, upright)
      else
        local cc = {}
        for _, p in ipairs(comp) do cc[p] = true end
        local ccols, cus = columns(cc)
        for _, u in ipairs(cus) do
          for _, rr in ipairs(runs(ccols[u])) do
            local a, b = rr[1], rr[2]
            local railTop = b - a < RAIL - 3
            if railTop then
              for v = a, b do
                local hit = false
                for k = -16, 16 do if road[P(u + k, v)] then hit = true; break end end
                if not hit then railTop = false; break end
              end
            end
            if railTop then
              -- a chamfer's rail, past the strip beside the road: its top, not a post in the water
              for v = a, b do
                local t = DECK + RAIL
                put({ { u, t, v + t }, { u + 1, t, v + t }, { u + 1, t, v + t + 1 }, { u, t, v + t + 1 } },
                  { { u, v }, { u + 1, v }, { u + 1, v + 1 }, { u, v + 1 } }, "deck.rail_side", { u, v })
              end
            else
              -- anything else (a truss's foot): upright on the ground at the foot of its column
              upright(u, b + 1, a, b + 1, "deck.post")
            end
          end
        end
      end
    end
    tick("posts")
    self.cornerRegions, self.unmerged = {}, {}
    local generic = {}
    for _, f in ipairs(out) do generic[f] = true end
    for _, ramp in ipairs(self.ramps) do self:cornerRamp(ramp, out, south); tick("ramp corner") end
    for _, hd in ipairs(self:heads()) do self:northCorner(hd, out, strips, north); tick("north corner") end
    for _, ft in ipairs(self:feetNorth()) do self:innerNorthCorner(ft, out, north); tick("inner north corner") end
    for _, hd in ipairs(self.innerHeads) do self:southCorner(hd, out, south, generic); tick("south corner") end
    local cutList = {}
    for i, ft in ipairs(self.feet) do
      if not self:southOuterCorner(ft, out, south, generic) and cuts[i] then cutList[#cutList + 1] = cuts[i] end
      tick("south outer corner")
    end
    tick("corners")
    local faces = Bridge.merge(out, tick)
    for _, f in ipairs(self.unmerged) do faces[#faces + 1] = f end
    tick("merge")
    return Bridge.cutCorners(Bridge.tileFlanks(faces, tick), cutList, tick)
  end

  --- The 8-connected pieces of a set of pixels, each sorted in (u, v) order.
  function BR.components(pixels)
    local keys = {}
    for p in pairs(pixels) do keys[#keys + 1] = p end
    table.sort(keys, uvLess)
    local seen, out = {}, {}
    for _, p in ipairs(keys) do
      if not seen[p] then
        seen[p] = true
        local todo, comp = { p }, {}
        while #todo > 0 do
          local q = remove(todo)
          comp[#comp + 1] = q
          local u, v = PU(q), PV(q)
          for i = -1, 1 do
            for j = -1, 1 do
              local r = P(u + i, v + j)
              if pixels[r] and not seen[r] then seen[r] = true; todo[#todo + 1] = r end
            end
          end
        end
        table.sort(comp, uvLess)
        out[#out + 1] = comp
      end
    end
    return out
  end

  --- A pier drawn beside the road: a box standing in the water, as deep as it is wide.
  function BR:pier(comp, put, upright)
    local cols = {}
    local u0, u1, zf
    for _, p in ipairs(comp) do
      local u, v = PU(p), PV(p)
      cols[u] = cols[u] or {}
      local c = cols[u]
      c[#c + 1] = v
      u0, u1 = u0 and min(u0, u) or u, u1 and max(u1, u + 1) or u + 1
      zf = zf and max(zf, v + 1) or v + 1
    end
    local depth = u1 - u0
    local function span(u)
      local vs = cols[u]
      if not vs then return nil end
      local lo, hi = vs[1], vs[1]
      for _, v in ipairs(vs) do lo, hi = min(lo, v), max(hi, v) end
      local cap = min(lo + depth, hi + 1)
      return zf - (hi + 1), zf - cap
    end
    for u = u0, u1 - 1 do
      local vs = cols[u]
      if vs then
        table.sort(vs)
        local tc = vs[1]
        local foot, top = span(u)
        local cap = zf - top
        for _, s in ipairs(split(tc, cap)) do
          local p, q = s[1], s[2]
          put({ { u, top, p + top }, { u + 1, top, p + top }, { u + 1, top, q + top }, { u, top, q + top } },
            { { u, p }, { u + 1, p }, { u + 1, q }, { u, q } }, "deck.pier_top", { u, p })
        end
        local front = {}
        for _, v in ipairs(vs) do if v >= cap then front[#front + 1] = v end end
        for _, rr in ipairs(runs(front)) do upright(u, zf, rr[1], rr[2] + 1, "deck.pier") end
        for _, nb in ipairs({ { u - 1, u, "w" }, { u + 1, u + 1, "e" } }) do
          local of, ot = span(nb[1])
          local parts
          if of == nil then parts = { { foot, top } }
          else parts = { { foot, min(top, of) }, { max(foot, ot), top } } end
          for _, pr in ipairs(parts) do
            local y0, y1 = pr[1], pr[2]
            if y1 - y0 >= 1e-6 then
              local z0, z1, x = zf - depth, zf, nb[2]
              put({ { x, y0, z0 }, { x, y0, z1 }, { x, y1, z1 }, { x, y1, z0 } }, rep({ u, tc }, 4),
                "deck.pier_side_" .. nb[3] .. "~depth~clamp", { u, tc })
            end
          end
        end
      end
    end
  end

  --- Every face filed under an art pixel in columns [xa, xb) and rows [r0, r1) taken out.
  local function filterOut(out, keepIf)
    local j = 0
    for i = 1, #out do
      local f = out[i]
      if keepIf(f) then j = j + 1; out[j] = f end
    end
    for i = #out, j + 1, -1 do out[i] = nil end
  end

  --- A ramp's corners with the deck and its slot through it, square.
  function BR:cornerRamp(ramp, out, south)
    local put = self._put
    local u0, u1, top, foot = ramp[1], ramp[2], ramp[3], ramp[4]
    local r0, r1 = self.cornerRows(ramp)
    local sidesL = { { u0 - RAMP_SIDE, u0, u0 - RAMP_SIDE - 1, "e" }, { u1, u1 + RAMP_SIDE, u1 + RAMP_SIDE, "w" } }
    local colsS = {}
    for _, s in ipairs(sidesL) do for u = s[1], s[2] - 1 do colsS[u] = true end end
    filterOut(out, function(f)
      local au, av = trunc(f.at[1]), trunc(f.at[2])
      return not (colsS[au] and r0 <= av and av < r1)
    end)
    for _, s in ipairs(sidesL) do self.cornerRegions[#self.cornerRegions + 1] = { s[1], s[2], r0, r1 } end
    local head = self.rampHead(ramp)
    for _, s in ipairs(sidesL) do
      local xa, xb, nb, inner = s[1], s[2], s[3], s[4]
      local fronts = south[nb]
      local zf = (fronts and #fronts > 0) and nearest(fronts, top + DECK) or top + DECK
      local xi = inner == "e" and xb or xa
      local xo = inner == "e" and xa or xb
      local other = inner == "e" and "w" or "e"
      local at = { xa, r0 }
      self:layRoad(xa, xb, r0 + DECK, zf - BEHIND)
      local low = DECK - SLAB
      put({ { xa, low, zf - BEHIND }, { xb, low, zf - BEHIND }, { xb, low, r0 + DECK }, { xa, low, r0 + DECK } },
        rep(at, 4), "deck.under~depth~clamp", at)
      put({ { xa, DECK - GIRDER, zf }, { xb, DECK - GIRDER, zf }, { xb, DECK + RAIL, zf }, { xa, DECK + RAIL, zf } },
        rep(at, 4), "deck.flank_rail_s~depth", at)
      local d = inner == "e" and -INSET or INSET
      for _, sp in ipairs(split(head, foot)) do
        local p, q = sp[1], sp[2]
        local z0, h0 = self:rampPoint(ramp, p)
        local z1, h1 = self:rampPoint(ramp, q)
        if z0 >= zf then break end
        if z1 > zf then
          h1 = h0 + (h1 - h0) * (zf - z0) / (z1 - z0)
          z1 = zf
        end
        local wat = { xa, p }
        put({ { xi + d, h0, z0 }, { xi + d, h1, z1 }, { xi + d, DECK, z1 }, { xi + d, DECK, z0 } },
          rep(wat, 4), "deck.flank_girder_" .. inner .. "~depth", wat)
        put({ { xo, 0.0, z0 }, { xo, 0.0, z1 }, { xo, low, z1 }, { xo, low, z0 } },
          rep(wat, 4), "deck.flank_girder_" .. other .. "~depth", wat)
        put({ { xa, DECK - INSET, z0 }, { xb, DECK - INSET, z0 }, { xb, DECK - INSET, z1 }, { xa, DECK - INSET, z1 } },
          rep(wat, 4), "deck.slot_top~depth~clamp", wat)
      end
      put({ { xa, 0.0, zf }, { xb, 0.0, zf }, { xb, DECK - GIRDER, zf }, { xa, DECK - GIRDER, zf } },
        rep(at, 4), "deck.flank_girder_s~depth", at)
      -- past the front, the ramp's last pixels between two low faces
      for _, sp in ipairs(split(head, foot)) do
        local p, q = sp[1], sp[2]
        local z0, h0 = self:rampPoint(ramp, p)
        local z1, h1 = self:rampPoint(ramp, q)
        if z1 > zf then
          if z0 < zf then
            h0 = h0 + (h1 - h0) * (zf - z0) / (z1 - z0)
            z0 = zf
          end
          if h0 >= 1e-3 then
            put({ { xi, 0.0, z0 }, { xi, 0.0, z1 }, { xi, h1, z1 }, { xi, h0, z0 } },
              rep({ xa, p }, 4), "deck.flank_girder_" .. other .. "~depth", { xa, p })
          end
        end
      end
    end
  end

  --- The north rail walked from column `start` by `step`: the depth it settles at and how many
  --- columns in it first stays there four columns running. (nil, 0) when there is no rail.
  local function straightOf(north, start, step, near)
    local ds = {}
    for k = 0, 47 do
      local best, bd
      for _, z in ipairs(north[start + step * k] or {}) do
        local d = abs(z - near)
        if d <= RAIL + SIDE and (not bd or d < bd) then best, bd = z, d end
      end
      ds[k + 1] = best or false
    end
    local vals = {}
    for _, d in ipairs(ds) do if d then vals[#vals + 1] = d end end
    if #vals == 0 then return nil, 0 end
    local zn = commonest(vals)
    local k0 = RAMP_SIDE
    for k = 0, #ds - 4 do
      if ds[k + 1] == zn and ds[k + 2] == zn and ds[k + 3] == zn and ds[k + 4] == zn then k0 = k; break end
    end
    return zn, max(k0, RAMP_SIDE)
  end

  --- The deck's road laid over x [xa, xb), z [z0, z1) in pieces a cell each.
  function BR:layRoad(xa, xb, z0, z1)
    local put = self._put
    local v0, v1 = z0 - DECK, z1 - DECK
    for _, s in ipairs(split(floor(xa), ceil(xb))) do
      local a, b = max(s[1], xa), min(s[2], xb)
      for _, t in ipairs(split(floor(v0), ceil(v1))) do
        local p, q = max(t[1], v0), min(t[2], v1)
        if not (b - a < 1e-6 or q - p < 1e-6) then
          local pts = { { a, DECK, p + DECK }, { b, DECK, p + DECK }, { b, DECK, q + DECK }, { a, DECK, q + DECK } }
          put(pts, projUV(pts), "deck.top_under_rail~depth~road", { trunc(a), trunc(p) })
        end
      end
    end
  end

  --- A corner's columns [xa, xb) for rows [r0, r1), its strip at [s0, s1), cut short of the
  --- corners already built beside it.
  function BR:clearOf(xa, xb, r0, r1, s0, s1)
    for _, cr in ipairs(self.cornerRegions) do
      local a, b, q0, q1 = cr[1], cr[2], cr[3], cr[4]
      if q0 < r1 and r0 < q1 and a < xb and xa < b then
        if b <= s0 then xa = max(xa, b)
        elseif a >= s1 then xb = min(xb, a) end
      end
    end
    return xa, xb
  end

  --- The deck's outer corners on its north side: { side, first row, first full-width row }.
  function BR:heads()
    local out = {}
    for _, side in ipairs({ "w", "e" }) do
      local vs = {}
      for _, hk in ipairs(self.headRowKeys) do if hk[1] == side then vs[#vs + 1] = hk[2] end end
      table.sort(vs)
      for _, r in ipairs(runs(vs)) do out[#out + 1] = { side, r[1], r[2] + 1 } end
    end
    return out
  end

  -- the strip's faces from z0 to z1 (its top laid apart, one texel a column)
  local function stripOn(self, out, side, s0, s1, z0, z1, texRow, at, quadUnder)
    local put, flank = self._put, self._flank
    local top, low = DECK + RAIL, DECK - SLAB
    local n = #out
    for c = s0, s1 - 1 do
      put({ { c, top, z0 }, { c + 1, top, z0 }, { c + 1, top, z1 }, { c, top, z1 } },
        rep({ c, texRow }, 4), "deck.rail_side~depth~clamp", { c, texRow })
    end
    for i = n + 1, #out do self.unmerged[#self.unmerged + 1] = out[i]; out[i] = nil end
    local xo, xi
    if side == "w" then xo, xi = s0, s1 else xo, xi = s1, s0 end
    local outDir, inDir = side, side == "w" and "e" or "w"
    flank("rail", outDir, xo, DECK, top, z0, z1, at)
    flank("girder", outDir, xo, DECK - GIRDER, DECK, z0, z1, at)
    flank("rail", inDir, xi, DECK, top, z0, z1, at)
    flank("under", inDir, xi, DECK - GIRDER, low, z0, z1, at)
    if quadUnder then
      local quad = { { xi, DECK - GIRDER, z0 }, { xo, DECK - GIRDER, z0 }, { xo, DECK - GIRDER, z1 }, { xi, DECK - GIRDER, z1 } }
      if side == "w" then quad = { quad[4], quad[3], quad[2], quad[1] } end
      put(quad, rep(at, 4), "deck.under~depth~clamp", at)
    end
  end

  --- An outer corner on the deck's north side, square.
  function BR:northCorner(hd, out, strips, north)
    local put, flank = self._put, self._flank
    local side, vFull = hd[1], hd[3]
    local e
    local heads = self.headRows[side .. ":" .. (vFull - 1)] or {}
    for _, en in ipairs(strips[side .. ":" .. vFull] or {}) do
      local hit = false
      for _, cs in ipairs(heads) do
        for _, c in ipairs(cs) do if en[1] <= c and c < en[2] then hit = true end end
      end
      if hit then e = en; break end
    end
    if not e then return end
    local s0, s1, xi, xo = e[1], e[2], e[3], e[4]
    local zn, k, xa, xb
    if side == "e" then
      zn, k = straightOf(north, s0 - 1, -1, vFull + DECK)
      xa, xb = s0 - k, s1
    else
      zn, k = straightOf(north, s1, 1, vFull + DECK)
      xa, xb = s0, s1 + k
    end
    if zn == nil then return end
    local r0, r1 = trunc(zn) - DECK - RAIL - SIDE, (floor((vFull + 15) / 16) + 1) * 16
    xa, xb = self:clearOf(xa, xb, r0, r1, s0, s1)
    local ra, rb
    if side == "e" then ra, rb = xa, s0 else ra, rb = s1, xb end
    self.cornerRegions[#self.cornerRegions + 1] = { xa, xb, r0, r1 }
    filterOut(out, function(f)
      local au, av = trunc(f.at[1]), trunc(f.at[2])
      local lim = (s0 <= au and au < s1) and vFull or r1
      return not (xa <= au and au < xb and r0 <= av and av < lim)
    end)
    local top, low, zr = DECK + RAIL, DECK - SLAB, r1 + DECK
    local at = { ra, r1 - 1 }
    self:layRoad(ra, rb, zn + BEHIND, zr)
    put({ { ra, low, zr }, { rb, low, zr }, { rb, low, zn }, { ra, low, zn } }, rep(at, 4), "deck.under~depth~clamp", at)
    put({ { xa, DECK, zn }, { xb, DECK, zn }, { xb, DECK + NORTH_RAIL, zn }, { xa, DECK + NORTH_RAIL, zn } },
      rep(at, 4), "deck.flank_railn_s~depth", at)
    put({ { xb, DECK - GIRDER, zn }, { xa, DECK - GIRDER, zn }, { xa, DECK, zn }, { xb, DECK, zn } },
      rep(at, 4), "deck.flank_girdern_n~depth", at)
    local zt = vFull + top
    local n = #out
    for c = s0, s1 - 1 do
      put({ { c, top, zn }, { c + 1, top, zn }, { c + 1, top, zt }, { c, top, zt } },
        rep({ c, vFull }, 4), "deck.rail_side~depth~clamp", { c, vFull })
    end
    for i = n + 1, #out do self.unmerged[#self.unmerged + 1] = out[i]; out[i] = nil end
    local outDir, inDir = side, side == "w" and "e" or "w"
    flank("rail", outDir, xo, DECK, top, zn, zt, at)
    flank("girder", outDir, xo, DECK - GIRDER, DECK, zn, zt, at)
    flank("rail", inDir, xi, DECK, top, zn, zt, at)
    flank("under", inDir, xi, DECK - GIRDER, low, zn, zt, at)
  end

  --- The deck's inner corners on its north side: { side, s0, s1, last row, the road's first row
  --- past it }.
  function BR:feetNorth()
    local out = {}
    local list = {}
    for _, sc in ipairs(self.stripColsList or {}) do list[#list + 1] = sc end
    -- (the runs of rows of each (side, edge), as Python's sorted dict of them)
    local byKey, keys = {}, {}
    for _, sc in ipairs(list) do
      local key = sc[1] .. ":" .. sc[2]
      if not byKey[key] then byKey[key] = { side = sc[1], edge = sc[2], vs = {} }; keys[#keys + 1] = key end
      for v = sc[3], sc[4] do byKey[key].vs[v] = true end
    end
    table.sort(keys, function(a, b)
      local ka, kb = byKey[a], byKey[b]
      if ka.side ~= kb.side then return ka.side < kb.side end
      return ka.edge < kb.edge
    end)
    for _, key in ipairs(keys) do
      local kk = byKey[key]
      for _, r in ipairs(runs(sortedKeys(kk.vs))) do
        local a, b = r[1], r[2]
        local cols = self.stripCols[kk.side .. ":" .. kk.edge .. ":" .. floor((a + b) / 2)]
        if not (b - a < 15 or not cols or #cols == 0) then
          local lo, hi = cols[1], cols[1]
          for _, c in ipairs(cols) do lo, hi = min(lo, c), max(hi, c) end
          local outer = kk.side == "w" and lo or hi
          for v = b + 1, b + RAIL + SIDE + 7 do
            if self.road[P(outer, v)] then
              out[#out + 1] = { kk.side, lo, hi + 1, b, v }
              break
            end
          end
        end
      end
    end
    return out
  end

  --- An inner corner on the deck's north side, square.
  function BR:innerNorthCorner(ft, out, north)
    local put = self._put
    local side, s0, s1, hit = ft[1], ft[2], ft[3], ft[5]
    local zn, k, xa, xb
    if side == "w" then
      zn, k = straightOf(north, s0 - 1, -1, hit + DECK)
      xa, xb = s0 - k, s1
    else
      zn, k = straightOf(north, s1, 1, hit + DECK)
      xa, xb = s0, s1 + k
    end
    if zn == nil then return end
    local r0, r1 = min(trunc(zn) - DECK, hit) - RAIL - SIDE - 16, (floor((hit + 15) / 16) + 1) * 16
    xa, xb = self:clearOf(xa, xb, r0, r1, s0, s1)
    self.cornerRegions[#self.cornerRegions + 1] = { xa, xb, r0, r1 }
    filterOut(out, function(f)
      local au, av = trunc(f.at[1]), trunc(f.at[2])
      return not (xa <= au and au < xb and r0 <= av and av < r1)
    end)
    local top, low, zr = DECK + RAIL, DECK - SLAB, r1 + DECK
    local at = { xa, r1 - 1 }
    self:layRoad(xa, xb, zn + BEHIND, zr)
    put({ { xa, low, zr }, { xb, low, zr }, { xb, low, zn }, { xa, low, zn } }, rep(at, 4), "deck.under~depth~clamp", at)
    put({ { xa, DECK, zn }, { xb, DECK, zn }, { xb, DECK + NORTH_RAIL, zn }, { xa, DECK + NORTH_RAIL, zn } },
      rep(at, 4), "deck.flank_railn_s~depth", at)
    put({ { xb, DECK - GIRDER, zn }, { xa, DECK - GIRDER, zn }, { xa, DECK, zn }, { xb, DECK, zn } },
      rep(at, 4), "deck.flank_girdern_n~depth", at)
    local z0 = r0 + top
    if zn > z0 then stripOn(self, out, side, s0, s1, z0, zn, r0 - 1, { s0, r0 - 1 }, false) end
  end

  --- The front's rail and girder straight on at depth zf over x [xa, xb).
  function BR:front(xa, xb, zf, at)
    self._put({ { xa, DECK - GIRDER, zf }, { xb, DECK - GIRDER, zf }, { xb, DECK + RAIL, zf }, { xa, DECK + RAIL, zf } },
      rep(at, 4), "deck.flank_rail_s~depth", at)
  end

  -- where each column's drawn road ends over a corner, from row `start`
  local function roadEnds(road, fa, fb, start)
    local ends, any = {}, false
    for u = fa, fb - 1 do
      local v = start
      if road[P(u, v)] then
        while road[P(u, v)] do v = v + 1 end
        ends[u] = v
        any = true
      end
    end
    return ends, any
  end
  -- the last drawn row of the generic build's fronts over a corner
  local function drawnRows(out, generic, xa, xb, r0, rEnd)
    local list = {}
    for _, f in ipairs(out) do
      if generic[f] and f.tag == "deck.front" then
        local au, av = trunc(f.at[1]), trunc(f.at[2])
        if xa <= au and au < xb and r0 <= av and av < rEnd then
          local m
          for _, t in ipairs(f.uvs) do m = m and max(m, t[2]) or t[2] end
          list[#list + 1] = m
        end
      end
    end
    return list
  end

  --- An inner corner on the deck's south side, square.
  function BR:southCorner(hd, out, south, generic)
    local put = self._put
    local side, s0, s1, v0, heads = hd.side, hd.s0, hd.s1, hd.v0, hd.head
    local near = (side == "w" and heads[s0] or heads[s1 - 1]) + RAIL + DECK
    local zf, k, xa, xb
    if side == "w" then
      zf, k = straightOf(south, s0 - 1, -1, near)
      xa, xb = s0 - k, s1
    else
      zf, k = straightOf(south, s1, 1, near)
      xa, xb = s0, s1 + k
    end
    if zf == nil then return end
    local ends, any = roadEnds(self.road, xa, xb, trunc(zf) - DECK - RAIL - SIDE)
    if not any then return end
    local emin
    for _, v in pairs(ends) do emin = emin and min(emin, v) or v end
    local r0 = floor(emin / 16) * 16
    local drawn = drawnRows(out, generic, xa, xb, r0, trunc(zf) - DECK + GIRDER + 8)
    local m = v0 + 1
    for _, d in ipairs(drawn) do m = max(m, d) end
    local r1 = floor((m + 15) / 16) * 16
    for _, cr in ipairs(self.cornerRegions) do
      if cr[1] < s1 and s0 < cr[2] and r0 < cr[3] then r1 = min(r1, cr[3]) end
    end
    xa, xb = self:clearOf(xa, xb, r0, r1, s0, s1)
    self.cornerRegions[#self.cornerRegions + 1] = { xa, xb, r0, r1 }
    filterOut(out, function(f)
      if not generic[f] or f.tag == "deck.top" then return true end
      local au, av = trunc(f.at[1]), trunc(f.at[2])
      return not (xa <= au and au < xb and r0 <= av and av < r1)
    end)
    local top, low = DECK + RAIL, DECK - SLAB
    local fa, fb
    if side == "w" then fa, fb = xa, s0 else fa, fb = s1, xb end
    local at = { side == "w" and fa or fb - 1, r0 }
    for _, u in ipairs(sortedKeys(ends)) do
      local b = ends[u]
      if xa <= u and u < xb and b + DECK < zf - BEHIND then self:layRoad(u, u + 1, b + DECK, zf - BEHIND) end
    end
    for _, s in ipairs(split(xa, xb)) do
      local a, b = s[1], s[2]
      put({ { a, low, zf - BEHIND }, { b, low, zf - BEHIND }, { b, low, r0 + DECK }, { a, low, r0 + DECK } },
        rep({ a, r0 }, 4), "deck.under~depth~clamp", { a, r0 })
    end
    self:front(fa, fb, zf, at)
    put({ { s0, DECK - GIRDER, zf }, { s1, DECK - GIRDER, zf }, { s1, top, zf }, { s0, top, zf } },
      rep(at, 4), "deck.flank_rail_s~depth", at)
    stripOn(self, out, side, s0, s1, zf, r1 + top, v0, { s0, v0 }, true)
  end

  --- An outer corner on the deck's south side, square (false when there is no straight front
  --- beside it: its chamfer stays).
  function BR:southOuterCorner(ft, out, south, generic)
    local put = self._put
    local side, edge, last, rowsF, cols = ft.side, ft.edge, ft.last, ft.foot, sortedKeys(ft.foot)
    local near = last + 1 + RAIL + DECK
    local s0, s1, zf, k, xa, xb
    if side == "w" then
      s0, s1 = cols[1], edge
      zf, k = straightOf(south, edge, 1, near)
      xa, xb = s0, edge + k
    else
      s0, s1 = edge + 1, cols[#cols] + 1
      zf, k = straightOf(south, edge, -1, near)
      xa, xb = edge + 1 - k, s1
    end
    if zf == nil then return false end
    local fa, fb
    if side == "w" then fa, fb = s1, xb else fa, fb = xa, s0 end
    local ends, any = roadEnds(self.road, fa, fb, min(last, trunc(zf) - DECK - RAIL - SIDE))
    if not any then return false end
    local emin
    for _, v in pairs(ends) do emin = emin and min(emin, v) or v end
    local r0 = floor(emin / 16) * 16
    local drawn = drawnRows(out, generic, xa, xb, r0, trunc(zf) - DECK + GIRDER + 8)
    local m
    for _, d in ipairs(drawn) do m = m and max(m, d) or d end
    for _, c in ipairs(cols) do m = m and max(m, rowsF[c][2]) or rowsF[c][2] end
    local r1 = floor((m + 15) / 16) * 16
    xa, xb = self:clearOf(xa, xb, r0, r1, s0, s1)
    fa, fb = max(fa, xa), min(fb, xb)
    self.cornerRegions[#self.cornerRegions + 1] = { xa, xb, r0, r1 }
    filterOut(out, function(f)
      if not generic[f] or f.tag == "deck.top" then return true end
      local au, av = trunc(f.at[1]), trunc(f.at[2])
      return not (xa <= au and au < xb and r0 <= av and av < r1)
    end)
    local top, low = DECK + RAIL, DECK - SLAB
    local at = { edge, r0 }
    for _, u in ipairs(sortedKeys(ends)) do
      local b = ends[u]
      if fa <= u and u < fb and b + DECK < zf - BEHIND then self:layRoad(u, u + 1, b + DECK, zf - BEHIND) end
    end
    for _, s in ipairs(split(fa, fb)) do
      local a, b = s[1], s[2]
      put({ { a, low, zf - BEHIND }, { b, low, zf - BEHIND }, { b, low, r0 + DECK }, { a, low, r0 + DECK } },
        rep({ a, r0 }, 4), "deck.under~depth~clamp", { a, r0 })
    end
    self:front(xa, xb, zf, at)
    local z0 = r0 + top
    if zf > z0 then stripOn(self, out, side, s0, s1, z0, zf, r0 - 1, { s0, r0 - 1 }, true) end
    return true
  end

  -- ── merging, dressing, cutting ───────────────────────────────────────────────

  local function r6(x) return ("%.6f"):format(x) end
  local function projected(tag) return not tag:find("~", 1, true) end

  --- Faces that go on from the one beside them, as one (voxel_bridge _merge).
  function Bridge.merge(faces, tick)
    tick = tick or function() end
    local cols, colKeys, rws, rowKeys, out = {}, {}, {}, {}, {}
    for n, f in ipairs(faces) do
      if n % 256 == 0 then tick("merge faces") end
      local pts, tag = f.pts, f.tag
      local xs, zs = {}, {}
      for _, p in ipairs(pts) do xs[p[1]] = true; zs[p[3]] = true end
      xs, zs = sortedKeys(xs), sortedKeys(zs)
      local cx, cy = cellOf(f.at)
      if #xs == 2 and xs[2] - xs[1] == 1 then
        local u = xs[1]
        local edge = {}
        for i, p in ipairs(pts) do edge[i] = p[1] - u end
        local key = tag .. "|" .. cx .. "," .. cy .. "|" .. table.concat(edge, ",")
        if not cols[key] then cols[key] = { tag = tag, edge = edge, items = {} }; colKeys[#colKeys + 1] = key end
        local l = cols[key].items
        l[#l + 1] = { u, f }
      elseif #zs == 2 and not endsWith(tag, "~proj") then
        local edge = {}
        for i, p in ipairs(pts) do edge[i] = p[3] == zs[2] and 1 or 0 end
        local dz = zs[2] - zs[1]
        local key = tag .. "|" .. cx .. "," .. cy .. "|" .. table.concat(edge, ",") .. "|" .. r6(dz)
        if not rws[key] then rws[key] = { tag = tag, edge = edge, dz = tonumber(r6(dz)), items = {} }; rowKeys[#rowKeys + 1] = key end
        local l = rws[key].items
        l[#l + 1] = { zs[1], f }
      else
        out[#out + 1] = f
      end
    end

    -- every corner of the run on a line, at most a pixel a step
    local function fits(run, others)
      local n = #run
      if n < 2 then return true end
      local first, last = others(run[1]), others(run[n])
      for i = 1, #first do
        local slope = (last[i] - first[i]) / (n - 1)
        if abs(slope) > 1 + 1e-6 then return false end
        local slack = abs(slope) > 1e-6 and 1 + 1e-6 or 1e-6
        for k, it in ipairs(run) do
          if abs(others(it)[i] - (first[i] + slope * (k - 1))) > slack then return false end
        end
      end
      return true
    end
    local function runsOf(items, along, others, step)
      local done, run = {}, { items[1] }
      for i = 2, #items do
        local it = items[i]
        local prev = run[#run]
        local cand = {}
        for j, r in ipairs(run) do cand[j] = r end
        cand[#cand + 1] = it
        if abs(along(it) - along(prev) - step(prev)) < 1e-6 and fits(cand, others) then
          run[#run + 1] = it
        else
          done[#done + 1] = run
          run = { it }
        end
      end
      done[#done + 1] = run
      return done
    end
    -- columns of one drawn face side by side: the same rows, each starting where the last ends,
    -- on one plane
    local function exactRuns(items)
      local done, run, step = {}, { items[1] }, nil
      local function corners(it, dx)
        local m, n = {}, 0
        local pts, uvs = it[2].pts, it[2].uvs
        for i, p in ipairs(pts) do
          if abs(p[1] - it[1] - dx) < 1e-9 then m[r6(uvs[i][2])] = p; n = n + 1 end
        end
        return m
      end
      local function sameKeys(a, b)
        for k in pairs(a) do if not b[k] then return false end end
        for k in pairs(b) do if not a[k] then return false end end
        return true
      end
      local function steps(e, w)
        local ks = {}
        for k in pairs(e) do ks[#ks + 1] = k end
        table.sort(ks, function(a, b) return tonumber(a) < tonumber(b) end)
        local t = {}
        for i, r in ipairs(ks) do t[i] = r6(e[r][3] - w[r][3]) end
        return table.concat(t, ",")
      end
      for i = 2, #items do
        local it = items[i]
        local prev = run[#run]
        local pw, pe, iw, ie = corners(prev, 0), corners(prev, 1), corners(it, 0), corners(it, 1)
        local joined = it[1] == prev[1] + 1 and sameKeys(pe, iw)
        if joined then
          for r, p in pairs(pe) do
            if abs(p[2] - iw[r][2]) >= 1e-6 or abs(p[3] - iw[r][3]) >= 1e-6 then joined = false end
          end
        end
        local d = sameKeys(ie, iw) and steps(ie, iw) or nil
        local dp = sameKeys(pe, pw) and steps(pe, pw) or nil
        if joined and d ~= nil and d == dp and (step == nil or d == step) then
          run[#run + 1] = it
          step = d
        else
          done[#done + 1] = run
          run, step = { it }, nil
        end
      end
      done[#done + 1] = run
      return done
    end
    local function byFirst(a, b) return a[1] < b[1] end
    local function stableSort(items)
      for i, it in ipairs(items) do it.ord = i end
      table.sort(items, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a.ord < b.ord
      end)
    end

    for n, key in ipairs(colKeys) do
      if n % 8 == 0 then tick("merge columns") end
      local grp = cols[key]
      local tag, edge, items = grp.tag, grp.edge, grp.items
      stableSort(items)
      if projected(tag) then
        -- a drawn face: merged only where it stays exact
        local byRows, rkeys = {}, {}
        for _, it in ipairs(items) do
          local set = {}
          for _, t in ipairs(it[2].uvs) do set[r6(t[2])] = tonumber(r6(t[2])) end
          local vals = {}
          for _, v in pairs(set) do vals[#vals + 1] = v end
          table.sort(vals)
          local rk = table.concat(vals, ",")
          if not byRows[rk] then byRows[rk] = {}; rkeys[#rkeys + 1] = rk end
          local l = byRows[rk]
          l[#l + 1] = it
        end
        for _, rk in ipairs(rkeys) do
          for _, run in ipairs(exactRuns(byRows[rk])) do
            local first, last = run[1][2], run[#run][2]
            local pts = {}
            for i, e in ipairs(edge) do
              local src = e ~= 0 and last or first
              local p = src.pts[i]
              pts[i] = { p[1], p[2], p[3] }
            end
            local uvs = {}
            for i, p in ipairs(pts) do uvs[i] = { p[1], first.uvs[i][2] } end
            local slanted = false
            for i = 1, #edge do
              if abs(first.pts[i][3] - last.pts[i][3]) > 1e-6 then slanted = true end
            end
            for i = 1, #first.pts - 1 do
              if abs(first.pts[i][3] - first.pts[i + 1][3]) > 1e-6 then slanted = true end
            end
            out[#out + 1] = face(pts, uvs, slanted and (tag .. "~proj") or tag, first.at)
          end
        end
      else
        local flat = function(it)
          local t = {}
          for _, p in ipairs(it[2].pts) do t[#t + 1] = p[2]; t[#t + 1] = p[3] end
          return t
        end
        local found
        if endsWith(tag, "~road") then
          -- the road under a rail meets the drawn road's staircase edge to edge: merged only
          -- where nothing steps
          found = {}
          local function same(a, b)
            for i = 1, #a do if a[i] ~= b[i] then return false end end
            return #a == #b
          end
          for _, it in ipairs(items) do
            local lastRun = found[#found]
            if lastRun and it[1] == lastRun[#lastRun][1] + 1 and same(flat(it), flat(lastRun[#lastRun])) then
              lastRun[#lastRun + 1] = it
            else
              found[#found + 1] = { it }
            end
          end
        else
          found = runsOf(items, function(it) return it[1] end, flat, function() return 1 end)
        end
        for _, run in ipairs(found) do
          local n = #run
          local u0 = run[1][1]
          local first, last = run[1][2], run[n][2]
          local pts = {}
          for i, e in ipairs(edge) do
            local y0, z0 = first.pts[i][2], first.pts[i][3]
            local dy = n > 1 and (last.pts[i][2] - y0) / (n - 1) or 0.0
            local dz = n > 1 and (last.pts[i][3] - z0) / (n - 1) or 0.0
            local k = e ~= 0 and (n - 0.5) or -0.5
            if dy == 0 and dz == 0 then k = 0.0 end
            pts[i] = { u0 + (e ~= 0 and n or 0), max(0.0, y0 + dy * k), z0 + dz * k }
          end
          local slant = false
          for i = 1, #edge do
            if abs(first.pts[i][3] - last.pts[i][3]) > 1e-6 then slant = true end
          end
          local uvs
          local skip = false
          if endsWith(tag, "~clamp") then
            uvs = first.uvs
          elseif endsWith(tag, "~road") then
            uvs = projUV(pts)
          else
            local moved = false
            if n > 1 then
              for i = 1, #first.pts do
                if abs(first.pts[i][2] - last.pts[i][2]) > 1e-6 then moved = true end
              end
            end
            if moved then
              -- a ramp's columns: as they are
              for _, it in ipairs(run) do out[#out + 1] = it[2] end
              skip = true
            else
              uvs = {}
              for i, e in ipairs(edge) do uvs[i] = { u0 + (e ~= 0 and n or 0), first.uvs[i][2] } end
            end
          end
          if not skip then out[#out + 1] = face(pts, uvs, tag, first.at) end
        end
      end
    end
    for n, key in ipairs(rowKeys) do
      if n % 4 == 0 then tick("merge rows") end
      local grp = rws[key]
      local tag, edge, dz, items = grp.tag, grp.edge, grp.dz, grp.items
      stableSort(items)
      local flat = function(it)
        local t = {}
        for _, p in ipairs(it[2].pts) do t[#t + 1] = p[1]; t[#t + 1] = p[2] end
        return t
      end
      local function same(a, b)
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return #a == #b
      end
      if projected(tag) then
        -- a drawn face: rows merged only where they are the same width in the same place
        local done, run = {}, { items[1] }
        for i = 2, #items do
          local it = items[i]
          if abs(it[1] - run[#run][1] - dz) < 1e-6 and same(flat(it), flat(run[#run])) then
            run[#run + 1] = it
          else
            done[#done + 1] = run
            run = { it }
          end
        end
        done[#done + 1] = run
        for _, rn in ipairs(done) do
          local first = rn[1][2]
          local z0, z1 = rn[1][1], rn[#rn][1] + dz
          local pts = {}
          for i, p in ipairs(first.pts) do pts[i] = { p[1], p[2], edge[i] ~= 0 and z1 or z0 } end
          out[#out + 1] = face(pts, projUV(pts), tag, first.at)
        end
      else
        for _, rn in ipairs(runsOf(items, function(it) return it[1] end, flat, function() return dz end)) do
          local n = #rn
          local z0 = rn[1][1]
          local first, last = rn[1][2], rn[n][2]
          -- rows already cut across (a strip's head): end to end
          local farX, nearX = {}, {}
          for i, e in ipairs(edge) do
            if e ~= 0 then farX[first.pts[i][1]] = true else nearX[first.pts[i][1]] = true end
          end
          local differ = false
          for x in pairs(farX) do if not nearX[x] then differ = true end end
          for x in pairs(nearX) do if not farX[x] then differ = true end end
          if differ then
            local pts = {}
            for i, e in ipairs(edge) do
              local p = (e ~= 0 and last or first).pts[i]
              pts[i] = { p[1], p[2], p[3] }
            end
            out[#out + 1] = face(pts, first.uvs, tag, first.at)
          else
            local pts = {}
            for i, e in ipairs(edge) do
              local x0, y0 = first.pts[i][1], first.pts[i][2]
              local dx = n > 1 and (last.pts[i][1] - x0) / (n - 1) or 0.0
              local dy = n > 1 and (last.pts[i][2] - y0) / (n - 1) or 0.0
              local k = e ~= 0 and (n - 0.5) or -0.5
              if dx == 0 and dy == 0 then k = 0.0 end
              pts[i] = { x0 + dx * k, y0 + dy * k, z0 + (e ~= 0 and n * dz or 0) }
            end
            local name, uvs = tag, nil
            if projected(tag) then
              uvs = projUV(pts)
              for i = 1, #edge do
                if abs(first.pts[i][1] - last.pts[i][1]) > 1e-6 then name = tag .. "~proj" end
              end
            else
              uvs = first.uvs
            end
            out[#out + 1] = face(pts, uvs, name, first.at)
          end
        end
      end
    end
    return out
  end

  --- The polygon (and its uvs) where plane(point) <= 0.
  local function clipPoly(pts, uvs, plane)
    local side, mx = {}, -math.huge
    for i, p in ipairs(pts) do side[i] = plane(p); mx = max(mx, side[i]) end
    if mx <= 1e-6 then return pts, uvs end
    local kp, kt = {}, {}
    local n = #pts
    for i = 1, n do
      local j = i % n + 1
      if side[i] <= 1e-6 then kp[#kp + 1] = pts[i]; kt[#kt + 1] = uvs[i] end
      if (side[i] <= 1e-6) ~= (side[j] <= 1e-6) then
        local t = side[i] / (side[i] - side[j])
        local a, b = pts[i], pts[j]
        kp[#kp + 1] = { a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2]), a[3] + t * (b[3] - a[3]) }
        local ua, ub = uvs[i], uvs[j]
        kt[#kt + 1] = { ua[1] + t * (ub[1] - ua[1]), ua[2] + t * (ub[2] - ua[2]) }
      end
    end
    return kp, kt
  end

  --- The deck's sides under its rails, cut at an outer corner by the chamfer's plane.
  function Bridge.cutCorners(faces, cuts, tick)
    tick = tick or function() end
    local out = {}
    for n, f in ipairs(faces) do
      if n % 256 == 0 then tick("cut corners") end
      local pts, uvs, tag = f.pts, f.uvs, f.tag
      local base = tag:match("^[^~]*")
      if not (startsWith(base, "deck.flank_") or startsWith(base, "deck.under")) then
        out[#out + 1] = f
      else
        local xmin, xmax = math.huge, -math.huge
        for _, p in ipairs(pts) do xmin, xmax = min(xmin, p[1]), max(xmax, p[1]) end
        for _, cut in ipairs(cuts) do
          local sx, c, y, x0, x1, z = cut[1], cut[2], cut[3], cut[4], cut[5], cut[6]
          local zmin = math.huge
          for _, p in ipairs(pts) do zmin = min(zmin, p[3]) end
          if not (xmin < x0 - 1e-6 or xmax > x1 + 1e-6 or zmin > z + 1e-6) then
            if #pts >= 3 then pts, uvs = clipPoly(pts, uvs, function(p) return p[3] + sx * p[1] - (c - 1.0) end) end
            if #pts >= 3 then pts, uvs = clipPoly(pts, uvs, function(p) return p[3] + sx * p[1] - p[2] - (c - y) end) end
            if #pts < 3 then break end
          end
        end
        if #pts >= 3 then out[#out + 1] = face(pts, uvs, tag, f.at) end
      end
    end
    return out
  end

  --- The deck's sides laid with the flank one texel a pixel: a face cut where the flank's 16
  --- columns repeat along it and where its rows do down it; uvs the flank's own pixels.
  function Bridge.tileFlanks(faces, tick)
    tick = tick or function() end
    local out = {}
    local offset = { rail = 0.0, railn = 1.0, wall = 0.0, girder = RAIL, girdern = RAIL + 2, under = RAIL + SLAB }
    for n, f in ipairs(faces) do
      if n % 128 == 0 then tick("tile flanks") end
      local pts, tag = f.pts, f.tag
      if not startsWith(tag, "deck.flank_") or endsWith(tag, "~clamp") then
        out[#out + 1] = f
      else
        local kind = tag:sub(#"deck.flank_" + 1):match("^[^_]*")
        local zset, nz = {}, 0
        for _, p in ipairs(pts) do if not zset[p[3]] then zset[p[3]] = true; nz = nz + 1 end end
        local k = nz == 2 and 3 or 1
        local wset = {}
        for _, p in ipairs(pts) do wset[p[k]] = true end
        local ends = {}
        for _, w in ipairs(sortedKeys(wset)) do
          local here = {}
          for _, p in ipairs(pts) do if p[k] == w then here[#here + 1] = p end end
          local lo, hi = math.huge, -math.huge
          for _, p in ipairs(here) do lo, hi = min(lo, p[2]), max(hi, p[2]) end
          ends[#ends + 1] = { here[1][1], here[1][3], lo, hi }
        end
        local xa, za, ba, ta = ends[1][1], ends[1][2], ends[1][3], ends[1][4]
        local xb, zb, bb, tb = ends[2][1], ends[2][2], ends[2][3], ends[2][4]
        local length = math.sqrt((xb - xa) ^ 2 + (zb - za) ^ 2)
        local shift = k == 1 and (xa - floor(xa / 16.0) * 16.0) or 0.0
        local ra, rb = ta + offset[kind], tb + offset[kind]
        local poly = { { 0.0, ra - ta }, { length, rb - tb }, { length, rb - bb }, { 0.0, ra - ba } }
        local dmax = -math.huge
        for _, q in ipairs(poly) do dmax = max(dmax, q[2]) end
        local bands = { { 0.0, RAIL, 0.0 } }
        local kk = 0
        while RAIL + kk * GIRDER < dmax do
          bands[#bands + 1] = { RAIL + kk * GIRDER, RAIL + (kk + 1) * GIRDER, kk * GIRDER }
          kk = kk + 1
        end
        local sheared = abs(rb - ra) > 1e-6
        for _, bd in ipairs(bands) do
          local d0, d1, back = bd[1], bd[2], bd[3]
          for t = 0, floor((length + shift) / 16) do
            local s0, s1 = max(0.0, 16.0 * t - shift), min(length, 16.0 * t + 16 - shift)
            if s1 - s0 >= 1e-6 then
              local piece = poly
              for _, cl in ipairs({ { 1, s0, true }, { 1, s1, false }, { 2, d0, true }, { 2, d1, false } }) do
                if #piece >= 3 then piece = K.clip(piece, cl[1], cl[2], cl[3]) end
              end
              if #piece >= 3 then
                local world, fuv = {}, {}
                for i, q in ipairs(piece) do
                  local ss, dd = q[1], q[2]
                  local fr = length ~= 0 and ss / length or 0.0
                  local ref = ra + (rb - ra) * fr
                  world[i] = { xa + (xb - xa) * fr, ref - dd, za + (zb - za) * fr }
                  fuv[i] = { ss - (16.0 * t - shift), dd - back }
                end
                out[#out + 1] = face(world, fuv, sheared and (tag .. "~proj") or tag, f.at)
              end
            end
          end
        end
      end
    end
    return out
  end

  -- ── what the models need besides the faces ───────────────────────────────────

  --- The cells the road is drawn on, and those of the signposts and curbs on it.
  function BR:drawnCells()
    local out = {}
    for p in pairs(self.pixels) do out[C(floor(PU(p) / 16), floor(PV(p) / 16))] = true end
    for c in pairs(self.signCells) do out[c] = true end
    for _, cb in ipairs(self.curbs) do
      for x = cb[2], cb[3] - 1 do out[C(x, cb[1])] = true end
    end
    return out
  end

  --- The metatile laid flat under the model in cell (x, y): the plain ground whose colours the
  --- cell's lower layer shows most, or for a cell drawn all road, the open water or the path it
  --- spans.
  function BR:groundFor(x, y)
    local io = self.io
    local cands, order = self:plainAnywhere()
    self._candColours = self._candColours or {}
    local subs = io.subtiles(io.metatile(x, y), 0)
    local low = {}
    for q = 0, 3 do
      local blk = subs[q]
      for k = 0, 63 do
        local u, v = x * 16 + (q % 2) * 8 + k % 8, y * 16 + floor(q / 2) * 8 + floor(k / 8)
        if not self.pixels[P(u, v)] then low[#low + 1] = blk[k] end
      end
    end
    local best, bs, bc
    for _, m in ipairs(order) do
      local cols = self._candColours[m]
      if not cols then
        cols = {}
        for q = 0, 3 do for c in pairs(self:blockColours(m, q)) do cols[c] = true end end
        self._candColours[m] = cols
      end
      local s = 0
      for _, c in ipairs(low) do if cols[c] then s = s + 1 end end
      local cnt = self.counts[m] or 0
      if not bs or s > bs or (s == bs and cnt > bc) then best, bs, bc = m, s, cnt end
    end
    if bs >= 32 then return best end
    local function commonestOf(list)
      local b, bn
      for _, m in ipairs(list) do
        local cnt = self.counts[m] or 0
        if not bn or cnt > bn then b, bn = m, cnt end
      end
      return b
    end
    -- drawn all road: what the row goes on with either side of it, the nearest plain ground
    for d = 1, self.w - 1 do
      for _, xx in ipairs({ x - d, x + d }) do
        if xx >= 0 and xx < self.w then
          self._drawn = self._drawn or self:drawnCells()
          local role = io.role(xx, y)
          if not self._drawn[C(xx, y)] and (role == "water" or role == "floor") then
            local water = role == "water"
            local pick = {}
            for _, m in ipairs(order) do if (self.water[m] == true) == water then pick[#pick + 1] = m end end
            return commonestOf(#pick > 0 and pick or order)
          end
        end
      end
    end
    return commonestOf(order)
  end

  --- The south front's rail and girder, 16 columns of it with no pier: what dresses the deck's
  --- other sides. { [y * 16 + x] = colour or nil } (16 x FLANK_ROWS).
  function BR:flankSample()
    if self._flankSample then return self._flankSample end
    local cols, us = columns(self.road)
    local clean = {}
    for _, u in ipairs(us) do
      for _, r in ipairs(runs(cols[u])) do
        local b = r[2]
        local kerb
        for v = b + 1, b + RAIL + 4 do
          if self.pixels[P(u, v)] == LINE then kerb = v; break end
        end
        if kerb and kerb - (b + 1) == RAIL then
          local full = true
          for v = kerb, kerb + GIRDER - 1 do if not self.pixels[P(u, v)] then full = false end end
          if full and not self.pixels[P(u, kerb + GIRDER)] then clean[u] = kerb end
        end
      end
    end
    local found
    for _, u0 in ipairs(sortedKeys(clean)) do
      if u0 % 16 == 0 then
        local ok = true
        for i = 0, 15 do if clean[u0 + i] ~= clean[u0] then ok = false end end
        if ok then found = { u0, clean[u0] }; break end
      end
    end
    if not found then error("no stretch of the front to dress the deck's sides with") end
    local out = {}
    for y = 0, FLANK_ROWS - 1 do
      for x = 0, 15 do out[y * 16 + x] = self.art[P(found[1] + x, found[2] - RAIL + y)] end
    end
    self._flankSample = out
    return out
  end

  --- The plain road: the cell drawn most often all road, framed by its own repeat (16 x ROAD_ROWS).
  function BR:roadSample()
    if self._roadSample then return self._roadSample end
    local seen, order, cellOfKey = {}, {}, {}
    for _, c in ipairs(self.deckList) do
      local x, y = CX(c), CY(c)
      local all = true
      for j = 0, 15 do
        for i = 0, 15 do
          local p = P(x * 16 + i, y * 16 + j)
          if not (self.pixels[p] and self.road[p]) then all = false; break end
        end
        if not all then break end
      end
      if all then
        local t = {}
        for j = 0, 15 do for i = 0, 15 do t[#t + 1] = self.art[P(x * 16 + i, y * 16 + j)] or -1 end end
        local key = table.concat(t, ",")
        if not seen[key] then seen[key] = 0; order[#order + 1] = key; cellOfKey[key] = { x, y } end
        seen[key] = seen[key] + 1
      end
    end
    local best, bn
    for _, k in ipairs(order) do if not bn or seen[k] > bn then best, bn = k, seen[k] end end
    if not best then error("no cell of plain road") end
    local x, y = cellOfKey[best][1], cellOfKey[best][2]
    local out = {}
    for r = 0, ROAD_ROWS - 1 do
      local j = r % 16
      for i = 0, 15 do out[r * 16 + i] = self.art[P(x * 16 + i, y * 16 + j)] end
    end
    self._roadSample = out
    return out
  end

  --- {cell: the tallest point over it, at most the deck's road}: the deck stands DECK pixels south
  --- of where it is drawn, so its cells' own rectangles would not tell it.
  local function worldTops(faces, w, h, tick)
    local tops = {}
    for n, f in ipairs(faces) do
      local pts = f.pts
      local ymax, x0, x1, z0, z1 = -math.huge, math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(pts) do
        ymax = max(ymax, p[2])
        x0, x1, z0, z1 = min(x0, p[1]), max(x1, p[1]), min(z0, p[3]), max(z1, p[3])
      end
      if ymax >= 1.0 then
        for cz = floor(z0 / 16), floor(z1 / 16) do
          for cx = floor(x0 / 16), floor(x1 / 16) do
            if cx >= 0 and cx < w and cz >= 0 and cz < h then
              local piece = pts
              for _, cl in ipairs({ { 1, cx * 16, true }, { 1, cx * 16 + 16, false }, { 3, cz * 16, true }, { 3, cz * 16 + 16, false } }) do
                if #piece >= 3 then piece = K.clip(piece, cl[1], cl[2], cl[3]) end
              end
              if #piece >= 3 then
                local ym = -math.huge
                for _, p in ipairs(piece) do ym = max(ym, p[2]) end
                local c = C(cx, cz)
                tops[c] = max(tops[c] or 0.0, min(DECK, ym))
              end
            end
          end
        end
      end
      if n % 512 == 0 then tick("tops") end
    end
    return tops
  end

  -- ── reading and blocks ───────────────────────────────────────────────────────

  function Bridge.read(io, conf, tick)
    tick = tick or function() end
    local br = setmetatable({ io = io, w = io.w, h = io.h, conf = conf, _upper = {}, _blocks = {} }, BR)
    br.apart = {}
    for _, r in ipairs(conf.apart or {}) do
      for j = 0, r[4] - 1 do
        for i = 0, r[3] - 1 do br.apart[C(r[1] + i, r[2] + j)] = true end
      end
    end
    br.deck, br.deckList = {}, {}
    for y = 0, io.h - 1 do
      for x = 0, io.w - 1 do
        local e = io.elevation(x, y)
        if e == conf.deck or e == conf.both then
          br.deck[C(x, y)] = true
          br.deckList[#br.deckList + 1] = C(x, y)
        end
      end
    end
    br:readDrawing(tick)
    br.faces = br:quads(tick)
    return br
  end

  -- a colour as kernel floats
  local function put4(px, o, c)
    if c == nil then
      px[o + 1], px[o + 2], px[o + 3], px[o + 4] = 0, 0, 0, 0
    else
      px[o + 1], px[o + 2], px[o + 3], px[o + 4] = floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255, 1
    end
  end

  --- An 8-column tile of the stones' own front for the faces the drawing never shows.
  local function frontTile(art, height)
    local W, H = art.w, art.h
    local ends = {}
    for u = 0, W - 1 do
      local e
      for v = H - 1, 0, -1 do
        if art.px[(v * W + u) * 4 + 4] >= 0.5 then e = v + 1; break end
      end
      local full = e ~= nil and e >= height
      if full then
        for v = e - height, e - 1 do if art.px[(v * W + u) * 4 + 4] < 0.5 then full = false end end
      end
      ends[u] = full and e or false
    end
    for _, width in ipairs({ 8, 6, 4 }) do
      local best
      for u = 0, W - width do
        local e = ends[u]
        if e then
          local ok = true
          for k = 0, width - 1 do if ends[u + k] ~= e then ok = false end end
          if ok and (not best or e > best[2]) then best = { u, e } end
        end
      end
      if best then return K.Tile(best[1], best[2] - height, best[1] + width, best[2]) end
    end
    return K.Tile(0, 0, 1, 1)
  end

  --- One model per cell of the road and the ground under it, found once: a cell drawn and built
  --- like another is the same model, placed at both (voxel_bridge block_specs, BLOCK 1).
  function Bridge.blocks(br, name, tick)
    tick = tick or function() end
    local io = br.io
    local faces = br.faces
    local curbOf = {}
    for _, cb in ipairs(br.curbs) do
      for x = cb[2], cb[3] - 1 do curbOf[C(x, cb[1])] = cb[4] end
    end
    local flank = br:flankSample()
    tick("flank sample")
    local drawn = br:drawnCells()
    tick("drawn cells")
    local ground, gorder = {}, {}
    local dkeys = sortedKeys(drawn)
    for n, c in ipairs(dkeys) do
      ground[c] = br:groundFor(CX(c), CY(c))
      gorder[#gorder + 1] = c
      if n % 32 == 0 then tick("grounds") end
    end
    tick("grounds")
    local tops = worldTops(faces, br.w, br.h, tick)
    local patchOf = {}
    for p, rgb in pairs(br.patchPx) do
      local c = C(floor(PU(p) / 16), floor(PV(p) / 16))
      patchOf[c] = patchOf[c] or {}
      patchOf[c][p] = rgb
    end
    -- the plain water or ground the deck stands over, south of where it is drawn: the model's too
    local plain = br:plainGrounds()
    for _, c in ipairs(sortedKeys(tops)) do
      if not ground[c] and tops[c] > 0 and plain[io.metatile(CX(c), CY(c))] then
        ground[c] = io.metatile(CX(c), CY(c))
        gorder[#gorder + 1] = c
      end
    end
    local groups = {}
    for _, f in ipairs(faces) do
      local cx, cy = cellOf(f.at)
      local cell = C(cx, cy)
      if not ground[cell] then
        local best, bd
        for _, g in ipairs(gorder) do
          local d = abs(CX(g) - cx) + abs(CY(g) - cy)
          if not bd or d < bd then best, bd = g, d end
        end
        cell = best
      end
      groups[cell] = groups[cell] or {}
      local l = groups[cell]
      l[#l + 1] = f
    end
    tick("groups")
    local out, seen = {}, {}
    local art = br.art
    table.sort(gorder, function(a, b)
      local xa, xb = CX(a), CX(b)
      if xa ~= xb then return xa < xb end
      return CY(a) < CY(b)
    end)
    for n, cell in ipairs(gorder) do
      local x0, y0, g = CX(cell), CY(cell), ground[cell]
      local mine = groups[cell] or {}
      local dressed, paved = false, false
      for _, f in ipairs(mine) do
        if startsWith(f.tag, "deck.flank_") and not endsWith(f.tag, "~clamp") then dressed = true end
        if endsWith(f.tag, "~road") then paved = true end
      end
      local flankAt = 17
      local roadAt = flankAt + (dressed and FLANK_ROWS + 1 or 0)
      local curbT = curbOf[cell]
      local curbAt = roadAt + (paved and ROAD_ROWS or 0)
      local H = curbAt + (curbT and 16 or 0)
      local cols = {}
      for j = 0, 15 do
        for i = 0, 15 do cols[j * 16 + i] = art[P(x0 * 16 + i, y0 * 16 + j)] end
      end
      for i = 0, 15 do cols[16 * 16 + i] = cols[15 * 16 + i] end
      if dressed then
        for y = 0, FLANK_ROWS - 1 do
          for i = 0, 15 do cols[(flankAt + y) * 16 + i] = flank[y * 16 + i] end
        end
        for i = 0, 15 do cols[(flankAt + FLANK_ROWS) * 16 + i] = flank[(FLANK_ROWS - 1) * 16 + i] end
      end
      if paved then
        local rs = br:roadSample()
        for y = 0, ROAD_ROWS - 1 do
          for i = 0, 15 do cols[(roadAt + y) * 16 + i] = rs[y * 16 + i] end
        end
      end
      local stones
      if curbT then
        stones = br:curbStones(curbT)
        for k = 0, 255 do
          local o = k * 4
          if stones.px[o + 4] > 0 then
            cols[(curbAt + floor(k / 16)) * 16 + k % 16] = floor(stones.px[o + 1] * 255 + 0.5) * 65536
              + floor(stones.px[o + 2] * 255 + 0.5) * 256 + floor(stones.px[o + 3] * 255 + 0.5)
          end
        end
      end
      local local_ = {}
      for _, f in ipairs(mine) do
        local uvs = {}
        if startsWith(f.tag, "deck.flank_") and not endsWith(f.tag, "~clamp") then
          for i, t in ipairs(f.uvs) do uvs[i] = { t[1], flankAt + t[2] } end
        elseif endsWith(f.tag, "~road") then
          local cu, cv = floor(trunc(f.at[1]) / 16) * 16, floor(trunc(f.at[2]) / 16) * 16
          for i, t in ipairs(f.uvs) do uvs[i] = { t[1] - cu, roadAt + 1 + t[2] - cv } end
        else
          for i, t in ipairs(f.uvs) do uvs[i] = { t[1] - x0 * 16, t[2] - y0 * 16 } end
        end
        local pts = {}
        for i, p in ipairs(f.pts) do pts[i] = { p[1] - x0 * 16, p[2], p[3] - y0 * 16 } end
        local_[#local_ + 1] = { pts = pts, uvs = uvs, tag = f.tag }
      end
      local top = pyround(tops[cell] or 0.0)
      local patch
      if patchOf[cell] then
        patch = {}
        for p, rgb in pairs(patchOf[cell]) do patch[(PV(p) - y0 * 16) * 16 + PU(p) - x0 * 16] = rgb end
      end
      -- (a cell drawn and built like another is the same model)
      local sig = {}
      for k = 0, H * 16 - 1 do sig[#sig + 1] = cols[k] or "" end
      sig[#sig + 1] = "|" .. g .. "|" .. top .. "|" .. tostring(curbT)
      if patch then for k = 0, 255 do sig[#sig + 1] = patch[k] or "" end end
      for _, f in ipairs(local_) do
        sig[#sig + 1] = f.tag
        for i, p in ipairs(f.pts) do
          sig[#sig + 1] = ("%.3f %.3f %.3f %.3f %.3f"):format(p[1], p[2], p[3], f.uvs[i][1], f.uvs[i][2])
        end
      end
      local key = table.concat(sig, ",")
      local blk = seen[key]
      if blk then
        blk.placed[#blk.placed + 1] = { x0, y0 }
      else
        local px = {}
        for k = 0, H * 16 - 1 do put4(px, k * 4, cols[k]) end
        blk = { name = ("%s_%d_%d"):format(name, x0, y0), cell = { x0, y0 }, ground = g, top = top,
                art = { w = 16, h = H, px = px }, faces = local_, patch = patch, placed = { { x0, y0 } } }
        if curbT then blk.curb = { stones = stones, band = curbAt, dx = 0, dz = 0 } end
        seen[key] = blk
        out[#out + 1] = blk
      end
      if n % 16 == 0 then tick("blocks") end
    end
    return out
  end

  --- A block's triangles (the kernel's mesh): its faces shaded as voxel_bridge Faces does, and a
  --- curb going on under the deck as the curb component builds it.
  function Bridge.mesh(blk, curbHeight)
    local mesh = K.mesh()
    for _, f in ipairs(blk.faces) do
      local tag = f.tag
      local shade = K.SHADE_ART
      if startsWith(tag, "deck.flank_") and not endsWith(tag, "~clamp") then
        local rest = tag:sub(#"deck.flank_" + 1)
        local facing = rest:match("^[^_]*_(.)")
        shade = (facing == "w" and K.SHADE_WEST) or (facing == "e" and K.SHADE_EAST) or (facing == "n" and K.SHADE_BACK)
          or K.SHADE_ART
      elseif startsWith(tag, "deck.pier_side_") then
        shade = tag:sub(#"deck.pier_side_" + 1, #"deck.pier_side_" + 1) == "w" and K.SHADE_WEST or K.SHADE_EAST
      elseif startsWith(tag, "deck.girder_n") or startsWith(tag, "deck.under") then
        shade = K.SHADE_BACK
      end
      local pts = {}
      for i, p in ipairs(f.pts) do pts[i] = { p[1], p[2], p[3], f.uvs[i][1], f.uvs[i][2] } end
      mesh:poly(pts, shade, "deck." .. tag)
    end
    local cb = blk.curb
    if cb then
      local tmp = K.mesh()
      K.Relief("curb", cb.stones, curbHeight, frontTile(cb.stones, curbHeight)):emit(tmp)
      for _, t in ipairs(tmp.tris) do
        local tri = {}
        for i = 1, 3 do
          local p = t[i]
          tri[i] = { p[1] + cb.dx, p[2], p[3] + cb.dz, p[4] + cb.dx, p[5] + cb.band }
        end
        mesh:tri(tri[1], tri[2], tri[3], t.shade, "deck." .. tostring(t.tag))
      end
    end
    return mesh
  end

  Bridge._BR = BR
  Bridge.P, Bridge.PU, Bridge.PV, Bridge.C, Bridge.CX, Bridge.CY = P, PU, PV, C, CX, CY
  return Bridge
end
