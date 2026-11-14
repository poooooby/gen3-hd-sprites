-- Buildings in the battle scene (Battle Scene: Overworld): the models of src/scene/models/specs.lua
-- found on the map around the battle, their art composed from the game's own tilesets.
--
-- A spec names a reference copy of its building: a layout and a rectangle of cells. Its template
-- is the metatiles there (read from the game's own copy of that map), its art the drawing of
-- those cells with the ground made transparent (a quarter of a cell is ground when its lower
-- layer is a ground metatile's; with ground_px, a pixel equal to a ground metatile's at the same
-- place is too). Wherever the map draws the same metatiles over the template's core cells - the
-- match rows, the cells its drawing has pixels in - the building stands: its mesh placed with the
-- rectangle's top-left cell, its cells' own ground laid flat under it (the placement's ground
-- metatile, or, where the map paints something else than the template, the map's own drawing
-- wherever the model draws nothing), and nothing else of those cells stands up.
--
-- Adapted from Emerald 3DS (scripts/gen_voxel_buildings.py: build_models, find_placements,
-- LayoutArt.building_art; by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes here: done in the game for the
-- window around the battle, from the engine's atlases; the template must match exactly (no
-- look-alike metatiles); a placement's ground is the commonest spec ground round it.

local Buildings = {}

Buildings.TILE = 16

local floor, max, min = math.floor, math.max, math.min

local function primaryOf(pair)
  return type(pair) == "string" and (pair:match("^(.-)__") or pair) or nil
end
Buildings.primaryOf = primaryOf

local function owns(spec, i, j)
  return Buildings.owns(spec, i, j)
end
--- Whether a spec owns cell (i, j) of its rectangle (all of it, or its `owned` cells).
function Buildings.owns(spec, i, j)
  return not spec.owned or spec.owned[i .. "," .. j] == true
end

--- The spec's reference: { template = { mids, row major, 1-based }, pair, w, h } or false.
--- ctx.layout(layoutId) -> { mid = function(x, y), pair } or nil
function Buildings.reference(spec, ctx)
  if spec._ref ~= nil then return spec._ref end
  spec._ref = false
  local L = ctx.layout(spec.layout)
  if not L then return false end
  local x, y, w, h = spec.rect[1], spec.rect[2], spec.rect[3], spec.rect[4]
  local t = {}
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local m = L.mid(x + i, y + j)
      if m == nil then return false end
      t[j * w + i + 1] = m
    end
  end
  spec._ref = { template = t, pair = L.pair, w = w, h = h }
  return spec._ref
end

-- a pixel source's colour as a key (exact: both sides read the same atlas bytes)
local function key3(r, g, b)
  return floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5)
end

--- The spec's drawing, ground transparent: { w, h (pixels), px = { r, g, b, a, ... } } or nil.
--- src.under(mid, x, y) / src.over(mid, x, y) -> r, g, b, a (0..1) of a metatile's lower and
--- upper layers in the reference's tileset pair, or nil when it has no such metatile.
function Buildings.art(spec, ref, src)
  local w, h = ref.w, ref.h
  local W, H = w * 16, h * 16
  -- the ground's lower-layer quarters, and pixels
  local quarters, grounds = {}, {}
  for _, g in ipairs(spec.ground or {}) do
    if src.under(g, 0, 0) ~= nil then
      local pix = {}
      for q = 0, 3 do
        local parts = {}
        for k = 0, 63 do
          local lx, ly = (q % 2) * 8 + k % 8, floor(q / 2) * 8 + floor(k / 8)
          local r, gg, b = src.under(g, lx, ly)
          local c = key3(r, gg, b)
          parts[k + 1] = c
          pix[ly * 16 + lx] = c
        end
        quarters[table.concat(parts, ",")] = true
      end
      grounds[#grounds + 1] = pix
    end
  end
  local px = {}
  for i = 1, W * H * 4 do px[i] = 0 end
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      if owns(spec, cx, cy) then
        local m = ref.template[cy * w + cx + 1]
        if src.under(m, 0, 0) ~= nil then
          for q = 0, 3 do
            local parts = {}
            for k = 0, 63 do
              local lx, ly = (q % 2) * 8 + k % 8, floor(q / 2) * 8 + floor(k / 8)
              local r, g, b = src.under(m, lx, ly)
              parts[k + 1] = key3(r, g, b)
            end
            local isGround = quarters[table.concat(parts, ",")] == true
            for k = 0, 63 do
              local lx, ly = (q % 2) * 8 + k % 8, floor(q / 2) * 8 + floor(k / 8)
              local X, Y = cx * 16 + lx, cy * 16 + ly
              local o = (Y * W + X) * 4
              local r1, g1, b1, a1 = src.over(m, lx, ly)
              if a1 and a1 > 0.5 then
                px[o + 1], px[o + 2], px[o + 3], px[o + 4] = r1, g1, b1, 1
              elseif not isGround then
                local r0, g0, b0 = src.under(m, lx, ly)
                local keep = true
                if spec.ground_px then
                  local c = parts[k + 1]
                  for _, gp in ipairs(grounds) do
                    if gp[ly * 16 + lx] == c then keep = false; break end
                  end
                end
                if keep then px[o + 1], px[o + 2], px[o + 3], px[o + 4] = r0, g0, b0, 1 end
              end
            end
          end
        end
      end
    end
  end
  if spec.ground_rgb then
    -- colours the building never has: the ground painted in its own cells (a parasol's shadow on
    -- the sand), compared as the game stores them (5 bits a channel)
    local set = {}
    for _, c in ipairs(spec.ground_rgb) do
      set[floor(c[1] * 31 / 255 + 0.5) * 1024 + floor(c[2] * 31 / 255 + 0.5) * 32 + floor(c[3] * 31 / 255 + 0.5)] = true
    end
    for i = 0, W * H - 1 do
      local o = i * 4
      if px[o + 4] >= 0.5 and set[floor(px[o + 1] * 31 + 0.5) * 1024 + floor(px[o + 2] * 31 + 0.5) * 32
          + floor(px[o + 3] * 31 + 0.5)] then
        px[o + 1], px[o + 2], px[o + 3], px[o + 4] = 0, 0, 0, 0
      end
    end
  end
  if spec.keep then
    for Y = 0, H - 1 do
      for X = 0, W - 1 do
        local inside = false
        for _, r in ipairs(spec.keep) do
          if X >= r[1] and X < r[3] and Y >= r[2] and Y < r[4] then inside = true; break end
        end
        if not inside then px[(Y * W + X) * 4 + 4] = 0 end
      end
    end
  end
  return { w = W, h = H, px = px }
end

--- The cells (i, j; 0-based) that must repeat for the building to stand: the owned cells of the
--- match rows that its drawing has pixels in (all of them if none has).
function Buildings.core(spec, ref, art)
  local r0, r1 = 0, ref.h
  if spec.match_rows then r0, r1 = spec.match_rows[1], spec.match_rows[2] end
  local core, all = {}, {}
  for j = r0, r1 - 1 do
    for i = 0, ref.w - 1 do
      if owns(spec, i, j) then
        all[#all + 1] = { i, j }
        local drawn = false
        if art then
          for y = 0, 15 do
            for x = 0, 15 do
              if art.px[((j * 16 + y) * art.w + i * 16 + x) * 4 + 4] >= 0.5 then drawn = true; break end
            end
            if drawn then break end
          end
        else
          drawn = true
        end
        if drawn then core[#core + 1] = { i, j } end
      end
    end
  end
  return #core > 0 and core or all
end

--- Where the specs' buildings stand in a grid (src/scene/cells.lua). models: { { spec, ref,
--- core, primaryOnly } } (prepared by Buildings.prepare). Returns placements { model, cx, cy }
--- (the rectangle's top-left map cell), the first found keeping its cells.
--- alike(md, cell, i, j) (optional): whether the cell's metatile, another than the template's,
--- draws the pixels the model owns in its cell (i, j) - the same building in a town's own tiles
--- (Rustboro's Center and Mart on its paving). Not asked of the anchor cell.
--- A spec with `owned` cells stands only where it was drawn, or at its `repeat_at` places (its
--- map's own cells { x, y }; Fortree's houses): at(cx, cy) -> the cell's place in its map (the
--- grid's own cells if nil).
function Buildings.find(grid, models, alike, at)
  local byAnchor = {}
  for _, md in ipairs(models) do
    local a = md.core[1]
    local m = md.ref.template[a[2] * md.ref.w + a[1] + 1]
    byAnchor[m] = byAnchor[m] or {}
    table.insert(byAnchor[m], md)
  end
  -- the look-alike check, once per model, cell of it, metatile and pair
  local memo = {}
  local function matches(md, o, i, j)
    local want = md.ref.template[j * md.ref.w + i + 1]
    if o.mid == want then return true end
    if not alike or md.spec.owned or not o.mid then return false end
    local m1 = memo[md]
    if not m1 then m1 = {}; memo[md] = m1 end
    local m2 = m1[j * 64 + i]
    if not m2 then m2 = {}; m1[j * 64 + i] = m2 end
    local m3 = m2[o.pair or false]
    if not m3 then m3 = {}; m2[o.pair or false] = m3 end
    local r = m3[o.mid]
    if r == nil then
      r = alike(md, o, i, j) == true
      m3[o.mid] = r
    end
    return r
  end
  local taken, found = {}, {}
  for j = 0, grid.h - 1 do
    local row = grid.rows[j]
    for i = 0, grid.w - 1 do
      local cell = row[i]
      -- (the anchor, the first core cell, must be the template's own metatile)
      local list = cell.mid and byAnchor[cell.mid]
      if list then
        for _, md in ipairs(list) do
          local a = md.core[1]
          local ox, oy = cell.cx - a[1], cell.cy - a[2]
          local ok = true
          if md.spec.owned then
            local lx, ly = ox, oy
            if at then
              local ax, ay = at(cell.cx, cell.cy)
              lx, ly = ax and ax - a[1], ay and ay - a[2]
            end
            ok = false
            for _, p in ipairs(md.spec.repeat_at or { md.spec.rect }) do
              if p[1] == lx and p[2] == ly then ok = true end
            end
          end
          for _, c in ipairs(md.core) do
            local o = grid.at(ox + c[1], oy + c[2])
            if not o or not matches(md, o, c[1], c[2]) then ok = false; break end
            if md.primaryOnly then
              if primaryOf(o.pair) ~= primaryOf(md.ref.pair) then ok = false; break end
            elseif o.pair ~= md.ref.pair then
              ok = false; break
            end
          end
          if ok then
            for jj = 0, md.ref.h - 1 do
              for ii = 0, md.ref.w - 1 do
                if owns(md.spec, ii, jj) and taken[(ox + ii) .. "," .. (oy + jj)] then ok = false end
              end
            end
          end
          if ok then
            for jj = 0, md.ref.h - 1 do
              for ii = 0, md.ref.w - 1 do
                if owns(md.spec, ii, jj) then taken[(ox + ii) .. "," .. (oy + jj)] = true end
              end
            end
            found[#found + 1] = { model = md, cx = ox, cy = oy }
          end
        end
      end
    end
  end
  return found
end

--- The kits' buildings in a grid: { spec (a spec of its own: name, rect, ground, parts), cx, cy,
--- meta } for each block whose corner, top row, end and foot the map draws (kit specs:
--- src/scene/models/specs.lua's kits). secondaryOf(pair) -> the pair's secondary tileset's name.
function Buildings.kits(grid, kits, secondaryOf)
  local out = {}
  for _, kit in ipairs(kits or {}) do
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.mid == kit.corner and not c.model and secondaryOf(c.pair) == kit.secondary then
          local x, y = c.cx, c.cy
          local x2 = x + 1
          local function m(cx, cy) local o = grid.at(cx, cy); return o and o.pair == c.pair and o.mid end
          while m(x2, y) and kit.top[m(x2, y)] do x2 = x2 + 1 end
          if m(x2, y) and kit.finish[m(x2, y)] then
            local y2 = y + 1
            while m(x, y2) and m(x, y2) ~= kit.foot do y2 = y2 + 1 end
            if m(x, y2) == kit.foot then
              local w, h = x2 - x + 1, y2 - y + 1
              local unit = false
              for k = x, x2 do if m(k, y) == 0x222 then unit = true end end
              unit = unit and m(x2, y) == 0x223
              local meta = { unit = unit }
              local W, H = w * 16, h * 16
              out[#out + 1] = { cx = x, cy = y, meta = meta, spec = {
                name = kit.name, rect = { x, y, w, h }, ground = kit.ground,
                parts = function() return kit.parts(W, H, meta) end } }
            end
          end
        end
      end
    end
  end
  return out
end

--- The metatile a placement's ground is laid with: of the spec's grounds, the commonest in the
--- ring of cells round it (else the first the pair has; else the ring's commonest).
--- has(mid) -> the placement's tileset pair draws it.
function Buildings.groundOf(grid, pl, has)
  local md = pl.model
  local w, h = md.ref.w, md.ref.h
  local count = {}
  for y = pl.cy - 1, pl.cy + h do
    for x = pl.cx - 1, pl.cx + w do
      if x < pl.cx or y < pl.cy or x >= pl.cx + w or y >= pl.cy + h then
        local c = grid.at(x, y)
        if c and c.mid and c.kind ~= "water" and c.kind ~= "void" then count[c.mid] = (count[c.mid] or 0) + 1 end
      end
    end
  end
  local best, bestN = nil, 0
  for _, g in ipairs(md.spec.ground or {}) do
    if (count[g] or 0) > bestN then best, bestN = g, count[g] end
  end
  if best then return best end
  -- none of its own grounds round it (Rustboro's paving): the open ground the map lays round it
  local open = {}
  for y = pl.cy - 1, pl.cy + h do
    for x = pl.cx - 1, pl.cx + w do
      if x < pl.cx or y < pl.cy or x >= pl.cx + w or y >= pl.cy + h then
        local c = grid.at(x, y)
        if c and c.mid and c.kind ~= "blocked" and c.kind ~= "water" and c.kind ~= "void" and has(c.mid) then
          open[c.mid] = (open[c.mid] or 0) + 1
        end
      end
    end
  end
  for m, n in pairs(open) do
    if n > bestN or (n == bestN and best and m < best) then best, bestN = m, n end
  end
  if best then return best end
  for _, g in ipairs(md.spec.ground or {}) do
    if has(g) then return g end
  end
  return nil
end

-- ── the ground under a placement (gen_voxel_buildings.find_placements, placement_ground,
-- patched_cells, placement_patches) ──

local EPS = 1e-6

-- Sutherland-Hodgman against one axis-aligned half plane (voxel_building.clip)
local function clip(poly, axis, value, keepGreater)
  local out, n = {}, #poly
  local function inside(p)
    if keepGreater then return p[axis] >= value - EPS end
    return p[axis] <= value + EPS
  end
  for k = 1, n do
    local a, b = poly[k], poly[k % n + 1]
    local ina, inb = inside(a), inside(b)
    if ina then out[#out + 1] = a end
    if ina ~= inb then
      local t = (value - a[axis]) / (b[axis] - a[axis])
      out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
    end
  end
  return out
end

--- The model's tallest point over each cell, in pixels (_cell_heights): { [j * w + i] = y }, each
--- triangle clipped to the cell (a face on the cell's edge, with no plan area in it, counts not).
function Buildings.cellHeights(md)
  if md.cellHeights then return md.cellHeights end
  local w, h = md.ref.w, md.ref.h
  local tops = {}
  for k = 0, w * h - 1 do tops[k] = 0 end
  for _, t in ipairs(md.tris) do
    local pts = { { t[1][1], t[1][2], t[1][3] }, { t[2][1], t[2][2], t[2][3] }, { t[3][1], t[3][2], t[3][3] } }
    local x0 = min(pts[1][1], pts[2][1], pts[3][1]) - 2 * EPS
    local x1 = max(pts[1][1], pts[2][1], pts[3][1]) + 2 * EPS
    local z0 = min(pts[1][3], pts[2][3], pts[3][3]) - 2 * EPS
    local z1 = max(pts[1][3], pts[2][3], pts[3][3]) + 2 * EPS
    for cy = 0, h - 1 do
      if not (z1 < cy * 16 or z0 > cy * 16 + 16) then
        for cx = 0, w - 1 do
          if not (x1 < cx * 16 or x0 > cx * 16 + 16) then
            local piece = clip(pts, 1, cx * 16, true)
            if #piece >= 3 then piece = clip(piece, 1, cx * 16 + 16, false) end
            if #piece >= 3 then piece = clip(piece, 3, cy * 16, true) end
            if #piece >= 3 then piece = clip(piece, 3, cy * 16 + 16, false) end
            if #piece >= 3 then
              local area, top = 0, 0
              for k = 1, #piece do
                local a, b = piece[k], piece[k % #piece + 1]
                area = area + a[1] * b[3] - b[1] * a[3]
                top = max(top, a[2])
              end
              if math.abs(area) / 2 > 1e-6 then
                local key = cy * w + cx
                tops[key] = max(tops[key], top)
              end
            end
          end
        end
      end
    end
  end
  md.cellHeights = tops
  return tops
end

--- The texels of a model's texture that draw something (Emerald 3DS's model.art: the drawing, or
--- the texture of its own a spec's parts_art gives it, its band grown round the drawing):
--- { w, h, [Y * w + X] = true }. Off the texture's image data where the model keeps it.
function Buildings.texCover(md)
  if md.texCover then return md.texCover end
  local data, art = md._data, md.art
  local out
  if data and data.getPixel then
    local w, h = data:getWidth(), data:getHeight()
    out = { w = w, h = h }
    for Y = 0, h - 1 do
      for X = 0, w - 1 do
        local _, _, _, a = data:getPixel(X, Y)
        if a >= 0.5 then out[Y * w + X] = true end
      end
    end
  else
    local w, h, px = art.w, art.h, art.px
    out = { w = w, h = h }
    for k = 0, w * h - 1 do
      if px[k * 4 + 4] >= 0.5 then out[k] = true end
    end
  end
  md.texCover = out
  return out
end

--- Whether the model's texture draws texel (X, Y).
function Buildings.drawn(md, X, Y)
  local t = Buildings.texCover(md)
  return X >= 0 and Y >= 0 and X < t.w and Y < t.h and t[Y * t.w + X] == true
end

--- Cell (i, j) of a model as a mask: true where its texture has nothing (_exposed), which the
--- map's own drawing shows there; nil if the texture fills the cell.
function Buildings.exposed(md, i, j)
  md.exposedCells = md.exposedCells or {}
  local key = j * 256 + i
  local mask = md.exposedCells[key]
  if mask ~= nil then return mask or nil end
  mask = false
  for y = 0, 15 do
    for x = 0, 15 do
      if not Buildings.drawn(md, i * 16 + x, j * 16 + y) then
        mask = mask or {}
        mask[y * 16 + x] = true
      end
    end
  end
  md.exposedCells[key] = mask
  return mask or nil
end

--- The model in the GBA's projection (x, z - y), as the set of its texture's pixels where its faces
--- draw an opaque texel, whatever the drawing has there (_covered: a roof behind its drawn outline
--- hides the ground at its corners). { [Y * texture width + X] = true }
function Buildings.covered(md)
  if md.coveredPx then return md.coveredPx end
  local tex = Buildings.texCover(md)
  local W, H = tex.w, tex.h
  local out = {}
  local floor, ceil = math.floor, math.ceil
  for _, t in ipairs(md.tris) do
    local p0, p1, p2 = t[1], t[2], t[3]
    local x0, y0, x1, y1, x2, y2 = p0[1], p0[3] - p0[2], p1[1], p1[3] - p1[2], p2[1], p2[3] - p2[2]
    local area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    if math.abs(area) >= 1e-9 then
      local inv = 1 / area
      for py = max(0, floor(min(y0, y1, y2))), min(H - 1, ceil(max(y0, y1, y2))) do
        local cy = py + 0.5
        for px = max(0, floor(min(x0, x1, x2))), min(W - 1, ceil(max(x0, x1, x2))) do
          local idx = py * W + px
          if not out[idx] then
            local cx = px + 0.5
            local a = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) * inv
            local b = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) * inv
            local c = 1 - a - b
            if a >= -1e-7 and b >= -1e-7 and c >= -1e-7 then
              local tu = floor(a * p0[4] + b * p1[4] + c * p2[4])
              local tv = floor(a * p0[5] + b * p1[5] + c * p2[5])
              if tu >= 0 and tv >= 0 and tu < W and tv < H and tex[tv * W + tu] then
                out[idx] = true
              end
            end
          end
        end
      end
    end
  end
  md.coveredPx = out
  return out
end

-- what shows of the ground in a model's cell with no patch over it, in the GBA's view: where the
-- model draws nothing and no face of it stands in front (_bare); nil if nothing
local function bareMask(md, i, j)
  local mask = Buildings.exposed(md, i, j)
  if not mask then return nil end
  local cov, W = Buildings.covered(md), Buildings.texCover(md).w
  local out
  for k in pairs(mask) do
    local x, y = k % 16, (k - k % 16) / 16
    if not cov[(j * 16 + y) * W + i * 16 + x] then
      out = out or {}
      out[k] = true
    end
  end
  return out
end

-- a mask's pixels on its edge: next to one it leaves out (of the eight round it), or on the cell's
-- border (_edge)
local function edgeOf(mask)
  local out = {}
  for k in pairs(mask) do
    local x, y = k % 16, (k - k % 16) / 16
    local edge = x == 0 or y == 0 or x == 15 or y == 15
    for dy = -1, 1 do
      for dx = -1, 1 do
        if not edge and not mask[(y + dy) * 16 + x + dx] then edge = true end
      end
    end
    if edge then out[k] = true end
  end
  return out
end

-- how many of the mask's pixels two cells (256 colours each) draw the same (_drawn_alike)
local function drawnAlike(a, b, mask)
  local n = 0
  for k in pairs(mask) do
    if a[k] == b[k] then n = n + 1 end
  end
  return n
end

--- The ground under one placement, as Emerald 3DS lays it: { ground = the metatile laid under the
--- model, patched = { [j * w + i] = true } (cells the map's own paint is laid over where the model
--- draws nothing), chosen = { [j * w + i] = metatile } (cells laid with a ground of the spec's
--- choosing, whole) }.
--- m, the placement's map: { id (its layout, LAYOUT_X), w, h, block(x, y) (its u16 cells, collision
--- in bits 10-11), px, py (the rectangle's top-left cell in it), painted, seamless ({ [metatile] =
--- true }: those it paints, those it paints beside themselves across and down), water(metatile),
--- groundWater (a spec ground is water in the reference's tilesets), rgb(metatile) (256 colours),
--- odd (whether the template is to be checked: not for a run of hedges, its own cells), refP (the
--- reference layout's tilesets as pret composes them: World.pretArt) }.
--- With relief_bare, also bare = { [j * w + i] = quarters }: the cells of its rectangle it stands
--- over nothing of (a Sootopolis house's roof drawn over the terrace face behind it) are no patch's;
--- the relief goes on there, drawn with the cell's metatile less the quarters of the reference's
--- upper layer that draw something (bit 2 * row + column; gen_voxel_buildings.bare_quarters).
---
--- Cells the map paints otherwise than the template (`odd`; all of them with patch_own or for what
--- is drawn on the upper layer, and the spec's patch_cells too) get the map's paint where nothing
--- of the model stands over them (all of them with those flags); cell_ground and cell_ground_at
--- lay a ground of the spec's choosing. The ground: of the metatiles the map paints round it (not
--- water, for what stands on land) and the spec's own grounds the map paints (those of them that
--- tile, if any), the one that draws most of what shows of the ground in the model's cells in the
--- GBA's view, then most of the patches' edges and the ring round it; ground_fixed (true: its first
--- ground; or by layout) overrides it if the map paints it.
function Buildings.groundPlan(md, m)
  local spec = md.spec
  local w, h = md.ref.w, md.ref.h
  local template = md.ref.template
  local px, py = m.px, m.py
  local function at(i, j)
    local x, y = px + i, py + j
    if x < 0 or y < 0 or x >= m.w or y >= m.h then return nil end
    return m.block(x, y)
  end
  local owned, odd = {}, {}
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      if owns(spec, i, j) then
        local k = j * w + i
        owned[k] = true
        local b = at(i, j)
        if m.odd and template and b and b % 1024 ~= template[k + 1] then odd[k] = true end
      end
    end
  end
  local tops = Buildings.cellHeights(md)
  local bare = {}
  if spec.relief_bare then
    for k in pairs(owned) do
      -- (Python rounds the height: none is half a pixel or less)
      if tops[k] <= 0.5 then
        local q, P, tm = 0, m.refP, template and template[k + 1]
        if P and tm and P.entries(tm) then
          local sub = P.subtiles(tm, 1)
          for qq = 0, 3 do
            local blk = sub[qq]
            for t = 0, 63 do
              local idx = blk[64 + t]
              if idx and idx ~= 0 then q = q + 2 ^ qq; break end
            end
          end
        end
        bare[k] = q
      end
    end
  end
  local patchAll = false
  if spec.patch_cells then
    for _, c in ipairs(spec.patch_cells) do
      local k = c[2] * w + c[1]
      if owned[k] and not bare[k] then odd[k] = true end
    end
    patchAll = true
  end
  if spec.patch_own or spec.relief_upper then
    for k in pairs(owned) do odd[k] = true end
    patchAll = true
  end
  local chosen = {}
  for _, c in ipairs(spec.cell_ground or {}) do chosen[c[2] * w + c[1]] = c[3] end
  for _, a in ipairs(spec.cell_ground_at or {}) do
    if a[1] == m.id and a[2] == px and a[3] == py then
      for _, c in ipairs(a[4]) do chosen[c[2] * w + c[1]] = c[3] end
    end
  end
  for k in pairs(chosen) do odd[k] = true end
  local patched = {}
  for k in pairs(odd) do
    if not chosen[k] and not bare[k] and (tops[k] <= 0.5 or patchAll) then patched[k] = true end
  end

  -- the ring of cells round it the map lays open ground in (no collision)
  local ring, any = {}, false
  for y = -1, h do
    for x = -1, w do
      if x < 0 or y < 0 or x >= w or y >= h then
        local b = at(x, y)
        if b and math.floor(b / 1024) % 4 == 0 then
          ring[b % 1024] = (ring[b % 1024] or 0) + 1
          any = true
        end
      end
    end
  end
  -- what stands on land stands on land: not the sea along a pier's edge, unless a ground of the
  -- spec's is water (a boat, the Trick House by its pond)
  if any and not m.groundWater then
    local land, anyLand = {}, false
    for g, n in pairs(ring) do
      if not m.water(g) then land[g] = n; anyLand = true end
    end
    if anyLand then ring = land end
  end
  local cand = {}
  for g in pairs(ring) do cand[g] = true end
  for _, g in ipairs(spec.ground or {}) do
    if m.painted[g] then cand[g] = true end
  end
  local tiling = {}
  for g in pairs(cand) do
    if m.seamless[g] then tiling[g] = true end
  end
  if next(tiling) then cand = tiling end
  local list = {}
  for g in pairs(cand) do list[#list + 1] = g end
  table.sort(list)
  local ground, scores = nil, {}
  if #list < 2 then
    ground = list[1] or (spec.ground or {})[1]
  else
    local bare, edges = {}, {}
    for j = 0, h - 1 do
      for i = 0, w - 1 do
        local k = j * w + i
        if owned[k] and not chosen[k] and Buildings.exposed(md, i, j) then
          local b = at(i, j)
          local rgb = b and m.rgb(b % 1024)
          if rgb then
            if patched[k] then
              edges[#edges + 1] = { rgb, edgeOf(Buildings.exposed(md, i, j)) }
            else
              local mask = bareMask(md, i, j)
              if mask then bare[#bare + 1] = { rgb, mask } end
            end
          end
        end
      end
    end
    local best, b1, b2
    for _, g in ipairs(list) do
      local tile = m.rgb(g)
      local s1, s2 = 0, 16 * (ring[g] or 0)
      if tile then
        for _, e in ipairs(bare) do s1 = s1 + drawnAlike(e[1], tile, e[2]) end
        for _, e in ipairs(edges) do s2 = s2 + drawnAlike(e[1], tile, e[2]) end
      end
      scores[#scores + 1] = { g, s1, s2 }
      if not best or s1 > b1 or (s1 == b1 and s2 > b2) then best, b1, b2 = g, s1, s2 end
    end
    ground = best
  end
  -- the spec's own ground whatever is round it (a boat moored by a pier floats on the sea), or one
  -- of its own in one map (a tent on its lawn) - if the map paints it
  local fixed = spec.ground_fixed
  if type(fixed) == "table" then
    fixed = fixed[m.id]
  elseif fixed == true then
    fixed = (spec.ground or {})[1]
    -- (a run's block with a secondary tileset's metatiles stands on that tileset's own ground)
    if spec.component then
      for k in pairs(owned) do
        local b = at(k % w, (k - k % w) / w)
        if b and b % 1024 >= 512 then fixed = nil end
      end
    end
  else
    fixed = nil
  end
  if fixed and m.painted[fixed] then ground = fixed end
  return { ground = ground, patched = patched, chosen = chosen, bare = bare, scores = scores, ring = ring }
end

--- How tall the model stands over each of its cells, in tiles: { [i .. "," .. j] = top } (the
--- highest vertex over the cell, a vertex on an edge counted in the cell inside it and one past
--- the rectangle in its nearest cell; a face crossing a cell without a vertex in it is not
--- counted).
function Buildings.tops(md)
  if md.tops then return md.tops end
  local tops = {}
  local w, h = md.ref.w, md.ref.h
  for _, t in ipairs(md.tris) do
    for k = 1, 3 do
      local p = t[k]
      local i = min(max(floor((p[1] - 1e-3) / 16), 0), w - 1)
      local j = min(max(floor((p[3] - 1e-3) / 16), 0), h - 1)
      local key = i .. "," .. j
      tops[key] = max(tops[key] or 0, p[2] / 16)
    end
  end
  md.tops = tops
  return tops
end

--- Each cell's footprint as the sun sees it (gen_voxel_buildings.cell_footprints), for an overworld
--- that casts shadows: { [i .. "," .. j] = 16 rows (1-based) of 16 bits, bit x of row z set where
--- the model stands over that pixel of the cell's plan (any triangle with plan area, a pixel above
--- the ground), or false for a cell it covers whole or not at all (a box, as its top gives it) }.
--- A model may bring its own (md.footprints: the Cycling Road's, worked out in the world).
function Buildings.footprints(md)
  if md.footprints then return md.footprints end
  local w, h = md.ref.w, md.ref.h
  local grid = {}
  for _, t in ipairs(md.tris) do
    local a, b, c = t[1], t[2], t[3]
    if max(a[2], b[2], c[2]) >= 1.0 then
      local ax, az, bx, bz, cx, cz = a[1], a[3], b[1], b[3], c[1], c[3]
      local area = (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
      if math.abs(area) >= 1e-6 then
        local x0 = max(0, floor(min(ax, bx, cx)))
        local x1 = min(w * 16, math.ceil(max(ax, bx, cx)))
        local z0 = max(0, floor(min(az, bz, cz)))
        local z1 = min(h * 16, math.ceil(max(az, bz, cz)))
        for pz = z0, z1 - 1 do
          for px = x0, x1 - 1 do
            local qx, qz = px + 0.5, pz + 0.5
            local d1 = (bx - ax) * (qz - az) - (bz - az) * (qx - ax)
            local d2 = (cx - bx) * (qz - bz) - (cz - bz) * (qx - bx)
            local d3 = (ax - cx) * (qz - cz) - (az - cz) * (qx - cx)
            if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0) then
              grid[pz * 4096 + px] = true
            end
          end
        end
      end
    end
  end
  local out = {}
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local rows, n = {}, 0
      for z = 0, 15 do
        local r = 0
        for x = 0, 15 do
          if grid[(j * 16 + z) * 4096 + i * 16 + x] then r = r + 2 ^ x; n = n + 1 end
        end
        rows[z + 1] = r
      end
      out[i .. "," .. j] = (n > 0 and n < 240) and rows or false
    end
  end
  md.footprints = out
  return out
end

--- A placement's triangles into vertex lists: put(list key, vertex) where a vertex is
--- { x, y, z, u, v, r, g, b, a } in tiles relative to (ox, oz), uvs 0..1 of the model's art.
function Buildings.emit(pl, ox, oz, add)
  local md = pl.model
  -- (a texture may carry more than the drawing: a fence's ground band and side strip)
  local W, H = md.texW or md.ref.w * 16, md.texH or md.ref.h * 16
  local bx, bz = pl.cx - ox, pl.cy - oz
  for _, t in ipairs(md.tris) do
    local s = t.shade or 1
    for k = 1, 3 do
      local p = t[k]
      add({ bx + p[1] / 16, p[2] / 16, bz + p[3] / 16, p[4] / W, p[5] / H, s, s, s, 1 })
    end
  end
end

return Buildings
