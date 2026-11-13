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
function Buildings.find(grid, models)
  local byAnchor = {}
  for _, md in ipairs(models) do
    local a = md.core[1]
    local m = md.ref.template[a[2] * md.ref.w + a[1] + 1]
    byAnchor[m] = byAnchor[m] or {}
    table.insert(byAnchor[m], md)
  end
  local taken, found = {}, {}
  for j = 0, grid.h - 1 do
    local row = grid.rows[j]
    for i = 0, grid.w - 1 do
      local cell = row[i]
      local list = cell.mid and byAnchor[cell.mid]
      if list then
        for _, md in ipairs(list) do
          local a = md.core[1]
          local ox, oy = cell.cx - a[1], cell.cy - a[2]
          local ok = true
          for _, c in ipairs(md.core) do
            local o = grid.at(ox + c[1], oy + c[2])
            if not o or o.mid ~= md.ref.template[c[2] * md.ref.w + c[1] + 1] then ok = false; break end
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
  for _, g in ipairs(md.spec.ground or {}) do
    if has(g) then return g end
  end
  for m, n in pairs(count) do
    if n > bestN and has(m) then best, bestN = m, n end
  end
  return best
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
