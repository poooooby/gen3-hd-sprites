-- FireRed's (and LeafGreen's) building models (Battle Scene: Overworld): one reading of the
-- drawing per building type, WoobleView's own, by the method of Emerald 3DS's
-- voxel_building_specs.py (src/scene/models/specs.lua is its port; see LICENSE) - the drawing is
-- the truth: every model reproduces its drawing pixel for pixel at 45 degrees over its `exact`
-- rectangles and lays every texel one pixel (tests/model_check.lua proves both), and is found
-- wherever the map draws the same metatiles (src/scene/buildings.lua). Nothing here is the
-- cartridge's: rectangles, rows, heights and metatile ids.
--
-- The same fields as specs.lua's (name, layout, rect, ground, parts, match_rows, keep, owned, ...),
-- and `exact` = { { x0, y0, x1, y1[, behind] }, ... }: the drawing's rectangles the model must
-- reproduce exactly (outside them it is deeper than the drawing shows).
--
-- How FireRed draws a house, read off Pallet Town's (cells 5-9 x 3-7, 80 x 80 px; the same drawing
-- at 14-18 x 3-7):
--   row   8         the ridge's outline (grey), x 11-68
--   rows  9-39      the front slope, x 12-66: courses of 8 rows upward - six of tile, a lighter
--                   line, a darker one (rows 35/36, 27/28, 19/20; the topmost at 12/13)
--   x  0-11, 67-79  the hips, drawn as stripes (the courses seen end on), lit to the west, shaded
--                   to the east; their eaves step down and out to row 47
--   rows 40-43      the eave: a dark line, the red fascia, navy, grey
--   rows 44-47      the wall's top in the eave's shade
--   rows 48-79      the facade: siding, the windows and the door; the corner posts x 3-7 and 72-75
-- The house stands on its four blocked rows (z 16-80); its roof's front slope keeps its drawn
-- courses from the eave and carries them on up to its ridge, which is so higher than the drawn
-- ridge line (the hips, unjudged, are laid with the same courses).

return function(K, H)
  local Prism, Proj, Tile, Band, Strip, HipRoof = K.Prism, K.Proj, K.Tile, K.Band, K.Strip, K.HipRoof
  -- (Emerald 3DS's helpers, from specs.lua: flat_block - a flat-roofed block, its facade projected,
  -- its cornice, its top laid in courses from the front with the back parapet as a tail)
  H = H or {}
  local flat_block = H.flat_block

  local PITCH = 22.0

  -- a FireRed house (Pallet Town's), `w` pixels wide: walls x 1..w, the front at z 80, the back at
  -- z 16, their tops at y 36 (row 44 at the front); the roof's eave 2 px out, its fascia rows 40-43
  local function pallet_house(w)
    local front_z, back_z, overhang = 80, 16, 2
    local wall_top = 36
    local zf, zb = front_z + overhang, back_z - overhang
    local cols = { 12, w - 13 }
    local roof = HipRoof("roof", 0, w - 1, zf, zb, zf - 44, {
      fascia = Strip({ 40, 44 }, { wrap = cols }),
      slope = Strip({ 9, 40 }, { rep = { 19, 27 }, start = 23, wrap = cols }),
      teeth = { 8, 9 }, cap = { 8, 9 }, pitch = PITCH, run = 12,
      ridge_u = { 12, w - 12 }, end_tile = Tile(12, 8, 13, 9) })
    -- (the walls to row 48 the whole width; the shaded top above it, rows 44-47, only between the
    -- hips' eaves, which the drawing steps down over its corners: there the posts go on up)
    local body_top = 32
    local plaster = Tile(8, 48, 16, 80, { top = body_top })
    local post = Tile(3, 48, 8, 80, { top = body_top })
    local base = Prism("walls", 1, w,
      { { front_z, 0 }, { front_z, body_top }, { back_z, body_top }, { back_z, 0 } },
      { edges = { [0] = Proj(48, 80), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, body_top, plaster, front_z, { front = post, back = post, z1 = back_z }) } })
    local shade = Tile(8, 44, 16, 48, { top = wall_top })
    local top = Prism("wall_top", 8, w - 8,
      { { front_z, body_top }, { front_z, wall_top }, { back_z, wall_top }, { back_z, body_top } },
      { edges = { [0] = Proj(44, 48), [2] = shade }, skip = { 1, 3 }, west = false, east = false })
    local postTop = Tile(3, 48, 8, 52, { top = wall_top })
    local corners = {}
    for _, xs in ipairs({ { 1, 8 }, { w - 8, w } }) do
      corners[#corners + 1] = Prism("corner", xs[1], xs[2],
        { { front_z, body_top }, { front_z, wall_top }, { back_z, wall_top }, { back_z, body_top } },
        { edges = { [0] = postTop, [2] = postTop }, skip = { 1, 3 },
          caps = { Band(body_top, wall_top, shade, front_z, { z1 = back_z }) } })
    end
    return { base, top, corners[1], corners[2], roof }
  end

  -- Pallet Town's ground round its houses: the light path, its edges, the grass
  local PALLET_GROUND = { 0x296, 0x297, 0x295, 0x28E, 0x2BE, 0x2BF, 0x2C6, 0x2C7, 0x29E, 0x2A5, 0x011 }

  -- Professor Oak's lab (Pallet Town, cells 13-19 x 9-13, 112 x 80): a flat roof of 8 px panels
  -- (lines at rows 20, 28, 36; columns every 8 px from x 12), its back parapet rows 9-14 under the
  -- outline at row 8; the slab's front rows 40-46 (a dark line, two light, four grey); the facade
  -- from row 47 (its outline) down: brick, portholes, windows, the door. On the roof, x 80-103, a
  -- machine: its top rows 10-24, its front rows 25-35 with fins either side (x 80-82, 101-103),
  -- its outline at row 36, its shadow on the roof rows 37-39.
  local function oaks_lab()
    return flat_block(112, 80, { { 29, 40 }, { 21, 29 }, { 8, 15 } }, { 40, 47 }, 47,
      { unit = { 80, 104, 10, 25, 36 }, brick = { 8, 47, 16, 63 }, pilaster = { 0, 47, 8, 63 },
        rim = { 8, 40, 16, 47 } })
  end

  -- The Pokemon Center (the General tileset's, the same in every town: Cerulean's at 20-24 x 15-19,
  -- 80 x 80): a hipped red roof of 4 px tiles (a light line every 4 rows from row 16, a tile
  -- every 4 px from x 11), its outline row 10 and highlight row 11; its hips shaded columns x 1-6
  -- and 73-78; the eave's dark band rows 45-51; the Poke Ball sign over the eave and the wall's
  -- top, rows 46-63 x 24-55; the facade from row 52 down, its bottom corners cut away. It stands
  -- on its four blocked rows (z 16-80); the sign is a board just in front of the eave.
  local function pokemon_center()
    local front_z, back_z, overhang = 80, 16, 2
    local zf, zb = front_z + overhang, back_z - overhang
    local roof = HipRoof("roof", 0, 80, zf, zb, zf - 52, {
      fascia = Strip({ 45, 52 }, { wrap = { 9, 71 } }),
      slope = Strip({ 16, 45 }, { rep = { 16, 20 }, wrap = { 11, 71 } }),
      teeth = { 11, 12 }, cap = { 10, 11 }, pitch = PITCH, run = 7,
      ridge_u = { 7, 73 }, end_tile = Tile(7, 10, 8, 11) })
    local wall_top = 28
    local plaster = Tile(8, 64, 24, 72, { top = wall_top })
    local walls = Prism("walls", 2, 78,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(52, 80), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, wall_top, plaster, front_z, { z1 = back_z }) } })
    local zs = zf + 2
    local face = Tile(25, 56, 33, 64, { top = zs - 46 })
    local sign = Prism("sign", 24, 56,
      { { zs, zs - 64 }, { zs, zs - 46 }, { front_z, zs - 46 }, { front_z, zs - 64 } },
      { edges = { [0] = Proj(46, 64), [1] = Proj(), [3] = face }, skip = { 2 },
        caps = { Band(zs - 64, zs - 46, face, zs) } })
    return { walls, roof, sign }
  end

  -- The Poke Mart (the General's, every town: Cerulean's at 27-30 x 26-29, 64 x 64): a blue roof of
  -- 4 px tiles (lines every 4 rows from row 0, every 4 px from x 7) to its eave line at row 28,
  -- its hips x 1-6 and 57-62, darker toward the eave; a rounded white canopy over the door, rows
  -- 14-31 x 16-47; the facade rows 29-47 (the MART sign, the door, windows), the ground drawn
  -- below it: its front wall stands at z 48, its back at 16. The slope's drawn rows (0-27) are as
  -- many as its run and rise show at a pitch of 31 degrees: its ridge is the drawing's top.
  local function poke_mart()
    local front_z, back_z, overhang = 48, 16, 2
    local zf, zb = front_z + overhang, back_z - overhang
    local roof = HipRoof("roof", 0, 64, zf, zb, zf - 29, {
      fascia = Strip({ 28, 29 }, { wrap = { 4, 24 } }),
      slope = Strip({ 4, 28 }, { rep = { 0, 4 }, wrap = { 7, 55 } }),
      teeth = { 0, 1 }, cap = { 0, 1 }, pitch = 31.0, run = 7,
      ridge_u = { 7, 57 }, end_tile = Tile(7, 0, 8, 1) })
    local wall_top = 19
    local plaster = Tile(8, 40, 24, 47, { top = wall_top })
    local walls = Prism("walls", 1, 63,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(29, 48), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, wall_top, plaster, front_z, { z1 = back_z }) } })
    local zc = zf + 2
    local white = Tile(17, 22, 25, 28, { top = zc - 14 })
    local canopy = Prism("canopy", 16, 48,
      { { zc, zc - 32 }, { zc, zc - 14 }, { front_z, zc - 14 }, { front_z, zc - 32 } },
      { edges = { [0] = Proj(14, 32), [1] = Proj(), [3] = white }, skip = { 2 },
        caps = { Band(zc - 32, zc - 14, white, zc) } })
    return { walls, roof, canopy }
  end

  -- A gabled house (FireRed's Viridian and Pewter kind): its walls x 0..w, front z `front` (the
  -- facade's rows o.facade[1]..front projected), back z `back`; a roof whose eave (o.eave rows,
  -- projected) stands o.overhang (2) out, whose front slope lays o.slope rows from the eave up
  -- (o.rep courses on past them) to a ridge over the middle, as high as the drawn rows say (their
  -- count is the slope's run plus its rise at 45 degrees), the back slope the same; the gable ends
  -- and the back laid with o.side (a Tile). o.chimney = { x0, x1, top, front, foot }: a stack on
  -- the roof, its top drawn rows top..front, its face front..foot, standing where the slope is
  -- drawn at row `foot`.
  local function gable_house(w, front, back, o)
    local ov = o.overhang or 2
    local zf, zb = front + ov, back - ov
    local zm = (front + back) / 2
    local wall_top = front - o.facade
    local y0, ye = zf - o.eave[2], zf - o.eave[1]
    local n = o.slope[2] - o.slope[1]
    local yr = ye + n - (zf - zm)
    local side = o.side
    local walls = Prism("walls", 0, w,
      { { front, 0 }, { front, wall_top }, { back, wall_top }, { back, 0 } },
      { edges = { [0] = Proj(o.facade, front), [2] = side }, skip = { 1, 3 },
        caps = { Band(0, wall_top, side, front, { z1 = back }) } })
    local slope = Strip(o.slope, { rep = o.rep, start = o.start, wrap = o.wrap })
    local back_slope = Strip(o.slope, { rep = o.rep, start = o.start, wrap = o.wrap, fromEnd = true })
    local roof = Prism("roof", o.roof_x0 or 0, o.roof_x1 or w,
      { { zb, y0 }, { zf, y0 }, { zf, ye }, { zm, yr }, { zb, ye } },
      { edges = { [1] = Proj(o.eave[1], o.eave[2]), [2] = slope, [3] = back_slope, [4] = side }, skip = { 0 },
        caps = { Band(y0, yr + 1, side, zf, { z1 = zb }) } })
    local parts = { walls, roof }
    local c = o.chimney
    if c then
      local runz, rise = zf - zm, yr - ye
      local t = (zf - ye - c[5]) / (runz + rise)
      local zc, yc = zf - t * runz, ye + t * rise
      local ytop = zc - c[4]
      local zcb = zc - (c[4] - c[3])
      local brick = Tile(c[1], c[4], c[2], c[5], { top = ytop })
      parts[#parts + 1] = Prism("chimney", c[1], c[2],
        { { zcb, yc - 4 }, { zc, yc - 4 }, { zc, ytop }, { zcb, ytop } },
        { edges = { [1] = Proj(c[4], c[5]), [2] = Proj(c[3], c[4]), [3] = brick }, skip = { 0 },
          caps = { Band(yc - 4, ytop, brick, zc, { z1 = zcb }) } })
    end
    return parts
  end

  -- Viridian City's houses (24-28 x 8-11 and 24-28 x 15-18, 80 x 64; their tops drawn over the path
  -- above them, their facades told apart by the door): a gabled roof of green corrugations, lighter
  -- above a band at rows 16-19, rows 8-44; the eave's grey rows 45-47; the facade rows 48-63,
  -- standing on its three blocked rows (z 16-64). A chimney x 48-63: its top rows 8-10, its face
  -- rows 11-39, its foot where the roof is drawn at row 40.
  local function viridian_house()
    return gable_house(80, 64, 16, { facade = 48, eave = { 45, 48 }, slope = { 8, 45 },
      side = Tile(1, 48, 9, 61, { top = 16 }), chimney = { 48, 64, 8, 11, 40 } })
  end

  -- A FireRed gym (Viridian's at 33-38 x 6-10, 96 x 80): a hipped yellow roof, a line every second
  -- row and every 8 px from x 8, rows 5-40 under its rounded ridge (rows 1-4); its hips drawn as
  -- stripes (x 0-6, 89-95); the eave rows 41-46; the facade rows 47-70, its foot drawn at row 70
  -- (the front wall at z 71); an entrance porch x 42-69 standing forward to row 78 (the GYM sign,
  -- the door), its top the drawing's own where the eave is drawn behind it.
  local function gym(o)
    o = o or {}
    local w = o.w or 96
    local front, back, overhang = 71, 16, 2
    local zf, zb = front + overhang, back - overhang
    local roof = HipRoof("roof", 0, w, zf, zb, zf - 47, {
      fascia = Strip({ 41, 47 }, { wrap = { 8, w - 8 } }),
      slope = Strip({ 5, 41 }, { rep = { 6, 8 }, start = 7, wrap = { 8, w - 8 } }),
      teeth = { 3, 5 }, cap = { 1, 3 }, pitch = 15.0, run = 6,
      ridge_u = { 6, w - 6 }, end_tile = Tile(8, 1, 10, 3) })
    local wall_top = front - 47
    local side = Tile(8, 55, 24, 70, { top = wall_top })
    local walls = Prism("walls", 1, w - 1,
      { { front, 0 }, { front, wall_top }, { back, wall_top }, { back, 0 } },
      { edges = { [0] = Proj(47, front), [2] = side }, skip = { 1, 3 },
        caps = { Band(0, wall_top, side, front, { z1 = back }) } })
    local px0, px1, pz = o.porch_x0 or 42, o.porch_x1 or 69, o.porch_z or 79
    local ph = pz - 51
    local pside = Tile(px0, 62, px0 + 3, 78, { top = ph })
    local porch = Prism("porch", px0, px1,
      { { front - 2, 0 }, { pz, 0 }, { pz, ph }, { front - 2, ph } },
      { edges = { [1] = Proj(51, pz), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, ph + 1, pside, pz, { z1 = front - 2 }) } })
    return { walls, roof, porch }
  end

  -- Pewter City's houses (32-36 x 8-11 and 8-12 x 27-30, 80 x 64): a gabled grey roof, its ridge's
  -- light rows 10-19 above courses every 4 rows to row 43, the bargeboards drawn at x 0-3 and
  -- 76-79; the eave rows 44-47; the facade rows 48-62; on three blocked rows (z 16-64).
  local function pewter_house()
    return gable_house(80, 64, 16, { facade = 48, eave = { 44, 48 }, slope = { 10, 44 },
      side = Tile(8, 48, 16, 58, { top = 16 }) })
  end

  -- Pewter Museum (12-22 x 0-7, 176 x 128; only its own cells, the bushes before it the map's): its
  -- outline row 9; a broad top rows 10-47, flat as drawn (as many rows as it is deep); the
  -- clerestory's windows rows 48-55; the lower roof rows 56-67, sloping from the eave; the eave
  -- rows 68-71 and the facade rows 72-95, its foot at row 95 (the front at z 96); the side walls
  -- x 0-6 and 169-175, as tall as the facade and running back so that their tops are the white
  -- columns drawn down to row 68; the portico x 64-111 forward to z 116, its steps to z 124 (foot
  -- row 123), their tops the drawing's own. The back falls from the top's back edge to the map's
  -- top, laid with the roof's pink.
  local function pewter_museum()
    local front = 96
    local wall_top = front - 68
    local rlo, rhi = 7.6, 4.4               -- the lower roof: 12 rows at 30 degrees
    local zc, yc = front - rlo, wall_top + rhi
    local yt = yc + 8                       -- the clerestory: rows 48-55
    local zt = zc - 39                      -- the top: rows 10-47 (the outline row 9 its edge)
    local body = Prism("body", 6, 170,
      { { 0, 0 }, { front, 0 }, { front, wall_top }, { zc, yc }, { zc, yt }, { zt, yt }, { 0, 0 } },
      { edges = { [1] = Proj(68, front), [2] = Strip({ 56, 68 }, { wrap = { 7, 167 } }), [3] = Proj(48, 56),
                  [4] = Proj(9, 48), [5] = Strip({ 12, 28 }, { rep = { 12, 28 }, fromEnd = true }) }, skip = { 0, 6 } })
    local white = Tile(1, 30, 6, 46, { top = wall_top })
    local sides = {}
    for _, xs in ipairs({ { 0, 6 }, { 170, 176 } }) do
      sides[#sides + 1] = Prism("side", xs[1], xs[2],
        { { front - 59, 0 }, { front, 0 }, { front, wall_top }, { front - 59, wall_top } },
        { edges = { [1] = Proj(68, front), [2] = Proj(9, 68), [3] = white }, skip = { 0 },
          caps = { Band(0, wall_top + 1, white, front, { z1 = front - 59 }) } })
    end
    local stone = Tile(66, 96, 70, 110, { top = 44 })
    local portico = Prism("portico", 64, 112,
      { { front - 2, 0 }, { 116, 0 }, { 116, 44 }, { front - 2, 44 } },
      { edges = { [1] = Proj(72, 116), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, 45, stone, 116, { z1 = front - 2 }) } })
    local steps = Prism("steps", 64, 112,
      { { 114, 0 }, { 124, 0 }, { 124, 4 }, { 114, 4 } },
      { edges = { [1] = Proj(120, 124), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, 5, Tile(64, 120, 68, 124, { top = 4 }), 124, { z1 = 114 }) } })
    return { body, sides[1], sides[2], portico, steps }
  end

  -- its annex (23-27 x 1-4, 80 x 64): a flat top rows 1-43 (as deep as it is drawn), the facade
  -- rows 44-63 on the ground at z 64; the white wall x 64-71 its side's top, as the museum's
  local function pewter_annex()
    local front, wall_top = 64, 20
    local zt = front - 44
    local body = Prism("body", 0, 72,
      { { 16, 0 }, { front, 0 }, { front, wall_top }, { zt, wall_top }, { 16, 0 } },
      { edges = { [1] = Proj(44, front), [2] = Proj(0, 44), [3] = Strip({ 4, 16 }, { rep = { 4, 16 }, fromEnd = true }) },
        skip = { 0, 4 },
        caps = { Band(0, wall_top + 1, Tile(65, 20, 70, 36, { top = wall_top }), front, { z1 = 16 }) } })
    return { body }
  end

  local function ownedOf(cells)
    local o = {}
    for _, c in ipairs(cells) do o[c[1] .. "," .. c[2]] = true end
    return o
  end
  local museumCells = {}
  for j = 0, 5 do for i = 0, 10 do museumCells[#museumCells + 1] = { i, j } end end
  for j = 6, 7 do for i = 4, 6 do museumCells[#museumCells + 1] = { i, j } end end

  -- Cerulean City's houses, one kit at three widths (5, 6, 7 cells; 64 px tall): the roof's top in
  -- the cell row above its own (rows 8-15; above them whatever the map draws there - a fence, sand);
  -- its outline row 8, courses every 4 rows (lines at 11, 15 ... 39) down to the eave, the hips
  -- drawn x 0-10 and the last 11 columns; the eave rows 40-47 with the porch's posts, the facade
  -- rows 48-62, its foot row 63 (the front at z 64), on its three blocked rows. The slope's drawn
  -- rows are about as many as it is deep: a low pitch.
  local function cerulean_house(w)
    local front, back, overhang = 64, 16, 2
    local zf, zb = front + overhang, back - overhang
    local roof = HipRoof("roof", 0, w, zf, zb, zf - 40, {
      fascia = Strip({ 39, 40 }, { wrap = { 11, w - 11 } }),
      slope = Strip({ 12, 39 }, { rep = { 11, 15 }, start = 11, wrap = { 11, w - 11 } }),
      teeth = { 8, 9 }, cap = { 8, 9 }, pitch = 12.0, run = 11,
      ridge_u = { 11, w - 11 }, end_tile = Tile(11, 8, 12, 9) })
    local wall_top = front - 40
    local side = Tile(64, 48, 80, 62, { top = wall_top - 8 })
    local walls = Prism("walls", 1, w - 1,
      { { front, 0 }, { front, wall_top }, { back, wall_top }, { back, 0 } },
      { edges = { [0] = Proj(40, front), [2] = side }, skip = { 1, 3 },
        caps = { Band(0, wall_top, side, front, { z1 = back }) } })
    return { walls, roof }
  end
  local function ceruleanSpec(name, x, y, cells)
    local w = cells * 16
    return { name = name, layout = "LAYOUT_CERULEAN_CITY", rect = { x, y, cells, 4 },
      ground = { 0x0E4, 0x0D3, 0x0D4, 0x0D5, 0x0DB, 0x0DC, 0x0DD, 0x001, 0x004, 0x008, 0x009, 0x010, 0x011 },
      exact = { { 2, 40, w - 2, 63 }, { 11, 12, w - 11, 39 } },
      parts = function() return cerulean_house(w) end }
  end

  -- Cerulean's bike shop (12-15 x 23-29, 64 x 112): a flat glass roof in its frame, rows 8-55, as
  -- deep as it is drawn (z 48-96; behind it the building falls away steeper than the GBA's view);
  -- the facade rows 56-95 (its front at z 96); a striped awning rows 73-85 sloping out to its edge
  -- at row 86 (z 104), over the shop window; its two posts x 5-7 and 56-58 forward to row 99.
  local function bike_shop()
    local front, wall_top = 96, 40
    local zt = front - 48
    local grey = Tile(10, 57, 26, 63, { top = wall_top })
    local body = Prism("body", 0, 64,
      { { 16, 0 }, { front, 0 }, { front, wall_top }, { zt, wall_top }, { 16, 0 } },
      { edges = { [1] = Proj(56, front), [2] = Proj(8, 56), [3] = Strip({ 56, 63 }, { rep = { 56, 63 }, fromEnd = true }) },
        skip = { 0, 4 }, caps = { Band(0, wall_top + 1, grey, front, { z1 = 16 }) } })
    local stripes = Tile(8, 74, 16, 80, { top = 23 })
    local awning = Prism("awning", 4, 60,
      { { front, 22 }, { front + 8, 17 }, { front + 8, 18 }, { front, 23 } },
      { edges = { [1] = Proj(86, 87), [2] = Strip({ 73, 86 }) }, skip = { 0, 3 },
        caps = { Band(17, 24, stripes, front + 8, { z1 = front }) } })
    local posts = {}
    for _, xs in ipairs({ { 5, 8 }, { 56, 59 } }) do
      posts[#posts + 1] = Prism("post", xs[1], xs[2],
        { { front + 2, 0 }, { front + 4, 0 }, { front + 4, 18 }, { front + 2, 18 } },
        { edges = { [1] = Proj(86, 100), [2] = Proj() }, skip = { 0, 3 },
          caps = { Band(0, 19, Tile(xs[1], 88, xs[2], 96, { top = 18 }), front + 4, { z1 = front + 2 }) } })
    end
    return { body, awning, posts[1], posts[2] }
  end

  -- A flat-topped block (Lavender's houses, the annexes): its walls x x0..x1, the facade's rows
  -- `facade`..front projected (its foot at z `front`), its top flat and projected, as deep as its
  -- drawn rows `top`..facade, behind which it falls to its back (z `back`) steeper than the GBA's
  -- view, laid with the rows o.fall (a Strip's) - unseen from the drawing's angle.
  local function flat_top(x0, x1, front, back, top, facade, o)
    o = o or {}
    local wall_top = front - facade
    local zt = front - (facade - top)
    local side = o.side or Tile(x0 + 8, facade + 2, x0 + 16, facade + 12, { top = wall_top })
    local fall = o.fall or { top + 4, top + 12 }
    return Prism(o.name or "body", x0, x1,
      { { back, 0 }, { front, 0 }, { front, wall_top }, { zt, wall_top }, { back, 0 } },
      { edges = { [1] = Proj(facade, front), [2] = Proj(top, facade), [3] = Strip(fall, { rep = fall, fromEnd = true }) },
        skip = { 0, 4 }, caps = { Band(0, wall_top + 1, side, front, { z1 = back }) } })
  end

  -- Lavender's Pokemon Tower (15-21 x 0-6, 112 x 112): a base block x 0-111, its front rows 80-103
  -- (the door) on the ground at z 104, its top the light band rows 64-79 (y 24); on it the tower,
  -- an octagon: its front x 20-91 drawn rows 0-63 at z 88, its corners chamfered at 45 degrees
  -- (x 8-19, 92-103, their feet the diagonals at rows 52-63), rising past the map's top - its front
  -- carried on up with its storeys of windows (rows 8-39), its corners as plain boxes.
  local function pokemon_tower()
    local top = 200
    local base = Prism("base", 0, 112,
      { { 16, 0 }, { 104, 0 }, { 104, 24 }, { 16, 24 } },
      { edges = { [1] = Proj(80, 104), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, 25, Tile(1, 82, 7, 100, { top = 24 }), 104, { z1 = 16 }) } })
    local wall = Tile(32, 8, 48, 40, { top = top })
    local tower = Prism("tower", 20, 92,
      { { 40, 24 }, { 88, 24 }, { 88, top }, { 40, top } },
      { edges = { [1] = Strip({ 0, 64 }, { rep = { 8, 40 } }), [2] = Tile(40, 40, 56, 56), [3] = wall }, skip = { 0 },
        caps = { Band(24, top + 1, wall, 88, { z1 = 40 }) } })
    local corners = {}
    for _, xs in ipairs({ { 8, 20 }, { 92, 104 } }) do
      corners[#corners + 1] = Prism("corner", xs[1], xs[2],
        { { 52, 24 }, { 76, 24 }, { 76, top }, { 52, top } },
        { edges = { [1] = wall, [2] = Tile(40, 40, 52, 52), [3] = wall }, skip = { 0 },
          caps = { Band(24, top + 1, wall, 76, { z1 = 52 }) } })
    end
    local chamfers = K.Walls("chamfer_w", { { 8, 76 }, { 20, 88 } }, 24, 76)
    local chamfers_e = K.Walls("chamfer_e", { { 92, 88 }, { 104, 76 } }, 24, 76)
    return { base, tower, corners[1], corners[2], chamfers, chamfers_e }
  end

  -- Vermilion City's houses, one kit at 4 and 5 cells (64 px tall): a gabled roof of orange
  -- corrugations running down it, rows 8-41 (its lip rows 38-41); the eave's line row 42; the
  -- facade rows 43-61, its base rows 62-63 (the front at z 64); on three blocked rows. Their flower
  -- boxes, drawn in the row below, are the map's.
  local function vermilionSpec(name, x, y, cells)
    local w = cells * 16
    return { name = name, layout = "LAYOUT_VERMILION_CITY", rect = { x, y, cells, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x12B, 0x12C, 0x115, 0x1DF },
      exact = { { 0, 42, w, 64 }, { 1, 10, w - 1, 42 } },
      parts = function()
        return gable_house(w, 64, 16, { facade = 43, eave = { 42, 43 }, slope = { 8, 42 },
          side = Tile(3, 44, 10, 56, { top = 21 }) })
      end }
  end

  -- A board just in front of an eave (a sign, an emblem): x0..x1, the drawing's rows r0..r1
  -- projected at z `z` (its top the drawing's own), as deep as `depth`
  local function sign_board(name, x0, x1, z, r0, r1, depth)
    local yb, yt = z - r1, z - r0
    local face = Tile(x0 + 1, r1 - 6, x0 + 3, r1, { top = yt })
    return Prism(name, x0, x1,
      { { z - depth, yb }, { z, yb }, { z, yt }, { z - depth, yt } },
      { edges = { [1] = Proj(r0, r1), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(yb, yt + 1, face, z, { z1 = z - depth }) } })
  end

  -- Vermilion's Pokemon Fan Club (11-15 x 14-17, 80 x 64): a gabled roof of green corrugations rows
  -- 1-38; the eave rows 39-41; the facade rows 42-61 (its flower boxes drawn on it), the base rows
  -- 62-63; the club's round emblem over the eave and the door's top, rows 34-46 x 17-34, a board.
  local function fan_club()
    local parts = gable_house(80, 64, 16, { facade = 42, eave = { 39, 42 }, slope = { 1, 39 },
      side = Tile(3, 44, 10, 56, { top = 22 }) })
    parts[#parts + 1] = sign_board("emblem", 17, 35, 68, 34, 47, 4)
    return parts
  end

  -- Celadon City's blocks, one kit at 4, 5 and 7 cells and 3 to 8 tall: a flat roof of green tiles
  -- (its hatch drawn on it) from row 8, as deep as it is drawn; the roof's edge, then the eave 10
  -- rows into the cell row its eave tiles begin, the storeys below it down to the base (the front
  -- at the rect's foot). eaveCell: that cell row, counted from the rect's top.
  local CELADON_GROUND = { 0x001, 0x004, 0x008, 0x009, 0x010, 0x011, 0x165, 0x166, 0x167, 0x16E, 0x176, 0x00E,
                           0x00F, 0x0D3, 0x0D4, 0x0D5, 0x16D }
  local function celadonBlock(name, x, y, cells, rows, eaveCell)
    local w, front = cells * 16, rows * 16
    local r = eaveCell * 16 + 10
    return { name = name, layout = "LAYOUT_CELADON_CITY", rect = { x, y, cells, rows }, ground = CELADON_GROUND,
      exact = { { 0, r, w, front }, { 1, 9, w - 1, r } },
      parts = function() return { flat_top(0, w, front, 16, 8, r, { fall = { 16, 24 } }) } end }
  end

  -- Celadon's blue-roofed building (24-29 x 16-18, 96 x 48; the General's blue roof): a hipped roof,
  -- its front slope rows 1-23 x 12-82 (lines every 7 or 8 rows), its hips lit and shaded either
  -- side; the eave's dark band rows 24-26; the facade rows 27-45 (two pillars, windows), its base
  -- rows 46-47 (the front at z 48), on its two blocked rows. The slope's 23 rows over its depth:
  -- a pitch of 17.4 degrees.
  local function blue_hall()
    local front, back, overhang = 48, 16, 2
    local zf, zb = front + overhang, back - overhang
    local roof = HipRoof("roof", 0, 96, zf, zb, zf - 27, {
      fascia = Strip({ 24, 27 }, { wrap = { 12, 83 } }),
      slope = Strip({ 1, 24 }, { wrap = { 12, 83 } }),
      teeth = { 0, 1 }, cap = { 0, 1 }, pitch = 17.4, run = 11,
      ridge_u = { 12, 83 }, end_tile = Tile(12, 0, 13, 1) })
    local wall_top = front - 27
    local side = Tile(16, 32, 24, 41, { top = wall_top })
    local walls = Prism("walls", 1, 95,
      { { front, 0 }, { front, wall_top }, { back, wall_top }, { back, 0 } },
      { edges = { [0] = Proj(27, front), [2] = side }, skip = { 1, 3 },
        caps = { Band(0, wall_top, side, front, { z1 = back }) } })
    return { walls, roof }
  end

  -- Saffron City's houses, one kit at 4 and 5 cells, one storey or two (their tops drawn over the
  -- path behind them: only the lower rows must repeat): a hipped green roof, courses every 8 rows
  -- (lines at 20, 28, 36) down to row 39 from its ridge rows 8-13, its hips striped either side
  -- (x 0-11 lit, the last 13 shaded); the eave's band rows 40-47; the facade from row 48 to the
  -- foot (16 rows a storey), on its blocked rows. As Pallet's, the drawn slope is shorter than the
  -- roof is deep: its courses go on up.
  local function saffron_house(w, storeys)
    local front = 48 + 16 * storeys
    local back, overhang = 16, 2
    local zf, zb = front + overhang, back - overhang
    local cols = { 12, w - 13 }
    local roof = HipRoof("roof", 0, w, zf, zb, zf - 48, {
      fascia = Strip({ 40, 48 }, { wrap = cols }),
      slope = Strip({ 14, 40 }, { rep = { 20, 28 }, start = 26, wrap = cols }),
      teeth = { 10, 14 }, cap = { 8, 10 }, pitch = 10.0, run = 12,
      ridge_u = { 12, w - 12 }, end_tile = Tile(12, 8, 14, 10) })
    local wall_top = front - 48
    local side = Tile(2, 48, 8, 60, { top = wall_top })
    local walls = Prism("walls", 0, w,
      { { front, 0 }, { front, wall_top }, { back, wall_top }, { back, 0 } },
      { edges = { [0] = Proj(48, front), [2] = side }, skip = { 1, 3 },
        caps = { Band(0, wall_top, side, front, { z1 = back }) } })
    return { walls, roof }
  end
  local SAFFRON_GROUND = { 0x2E9, 0x2E3, 0x2E5, 0x2EC, 0x2F3, 0x2F4, 0x2F5, 0x2EB, 0x2ED, 0x2EA, 0x001, 0x008,
                           0x009, 0x010, 0x011 }
  local function saffronSpec(name, x, y, cells, storeys)
    local w, rows = cells * 16, 3 + storeys
    return { name = name, layout = "LAYOUT_SAFFRON_CITY", rect = { x, y, cells, rows }, match_rows = { 1, rows },
      ground = SAFFRON_GROUND,
      exact = { { 1, 48, w - 1, 48 + 16 * storeys - 2 }, { 12, 40, w - 12, 48 }, { 12, 14, w - 13, 40 } },
      parts = function() return saffron_house(w, storeys) end }
  end

  -- Cinnabar Island's (its own tileset)
  local CINNABAR_GROUND = { 0x0D9, 0x0DA, 0x008, 0x009, 0x010, 0x011, 0x0D0, 0x0D1, 0x0D2, 0x0E0, 0x0E1, 0x0E2,
                            0x0FF, 0x107, 0x12B, 0x12C }

  -- the Pokemon Mansion (5-11 x 0-3, 112 x 64, and its steps' row): its roof from the map's top
  -- edge, a mansard at 45 degrees (rows 0-23, its three dormers drawn on it) over the eave's bands
  -- rows 24-29; the outline row 30 and the two storeys below, the foot row 63 (the front at z 64),
  -- the roof 2 px wider than the walls (x 0-111; the walls 2-109); the porch x 40-71: its canopy's
  -- front rows 49-53 (y 17-22), its pillars x 40-47 and 64-71 forward to their plinths' foot, row 70 (z 71),
  -- the steps between them
  local function mansion()
    local front, wall_top = 64, 34
    local walls = Prism("walls", 2, 110, { { 0, 0 }, { front, 0 }, { front, wall_top }, { 0, wall_top } },
      { edges = { [1] = Proj(30, front) }, skip = { 0, 2, 3 },
        caps = { Band(0, wall_top + 1, Tile(8, 32, 16, 42, { top = wall_top }), front, { z1 = 0 }) } })
    local slate = Tile(4, 2, 16, 12, { top = 52 })
    local roof = Prism("roof", 0, 112,
      { { 0, wall_top }, { front, wall_top }, { front, 40 }, { 52, 52 }, { 20, 52 }, { 0, wall_top } },
      { edges = { [1] = Proj(24, 30), [2] = Proj(0, 24), [3] = slate,
                  [4] = Strip({ 4, 12 }, { rep = { 4, 12 }, fromEnd = true }) }, skip = { 0, 5 },
        caps = { Band(wall_top, 53, slate, front, { z1 = 0 }) } })
    local stone = Tile(41, 57, 46, 64, { top = 17 })
    local canopy = Prism("canopy", 40, 72, { { front, 17 }, { 71, 17 }, { 71, 22 }, { front, 22 } },
      { edges = { [1] = Proj(49, 54), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(17, 23, stone, 71, { z1 = front }) } })
    local parts = { walls, roof, canopy }
    for _, xs in ipairs({ { 40, 48 }, { 64, 72 } }) do
      parts[#parts + 1] = Prism("pillar", xs[1], xs[2], { { front, 0 }, { 71, 0 }, { 71, 17 }, { front, 17 } },
        { edges = { [1] = Proj(54, 71) }, skip = { 0, 2, 3 },
          caps = { Band(0, 18, stone, 71, { z1 = front }) } })
    end
    parts[#parts + 1] = Prism("steps", 48, 64, { { front, 0 }, { 71, 0 }, { 71, 2 }, { front, 2 } },
      { edges = { [1] = Proj(69, 71), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, 3, Tile(49, 64, 63, 66, { top = 2 }), 71, { z1 = front }) } })
    return parts
  end
  local mansionCells = {}
  for j = 0, 3 do for i = 0, 6 do mansionCells[#mansionCells + 1] = { i, j } end end
  for i = 2, 4 do mansionCells[#mansionCells + 1] = { i, 4 } end

  -- the Cinnabar Lab (5-11 x 6-10, 112 x 80): a white capsule lying east-west, read column by
  -- column off its outline - each run of columns its own slice, its top at the run's top row t and
  -- its foot at its bottom row b (the front at z b + 1), its profile the drawing's three bands in
  -- the body's proportions: a wall (rows 39-61 of the body's 2-61), a 45 degree shoulder (rows
  -- 18-38), a flat top (rows 2-17); the ends' columns step down as the capsule rounds off; the
  -- ribs (t 0, b 63) stand 2 px proud. Its entrance x 66-93 forward to row 68 (z 69).
  local LAB_RUNS = {
    { 0, 1, 17, 45 }, { 1, 2, 14, 49 }, { 2, 3, 12, 51 }, { 3, 4, 10, 53 }, { 4, 5, 9, 54 }, { 5, 6, 7, 56 },
    { 6, 7, 6, 57 }, { 7, 9, 5, 58 }, { 9, 10, 4, 59 }, { 10, 13, 3, 60 }, { 13, 16, 2, 61 }, { 16, 24, 0, 63 },
    { 24, 40, 2, 61 }, { 40, 48, 0, 63 }, { 48, 64, 0, 61 }, { 64, 72, 0, 63 }, { 72, 88, 2, 61 },
    { 88, 96, 0, 63 }, { 96, 99, 2, 61 }, { 99, 102, 3, 60 }, { 102, 103, 4, 59 }, { 103, 105, 5, 58 },
    { 105, 106, 6, 57 }, { 106, 107, 7, 56 }, { 107, 108, 9, 54 }, { 108, 109, 10, 53 }, { 109, 110, 12, 51 },
    { 110, 111, 14, 49 }, { 111, 112, 17, 45 } }
  local function cinnabar_lab()
    local back = 16
    local white = Tile(27, 18, 39, 21, { top = 40 })
    local fall = Strip({ 18, 21 }, { rep = { 18, 21 }, fromEnd = true })
    local parts = {}
    for _, r in ipairs(LAB_RUNS) do
      local t, zf = r[3], r[4] + 1
      local s = zf - t
      local h1, d = s * 23 / 60, s * 10.5 / 60
      local yt = h1 + d
      local zt = t + yt
      parts[#parts + 1] = Prism("shell", r[1], r[2],
        { { back, 0 }, { zf, 0 }, { zf, h1 }, { zf - d, yt }, { zt, yt }, { back, 0 } },
        { edges = { [1] = Proj(), [2] = Proj(), [3] = Proj(), [4] = fall }, skip = { 0, 5 },
          caps = { Band(0, yt + 1, white, zf, { z1 = back }) } })
    end
    parts[#parts + 1] = Prism("entrance", 66, 94, { { 60, 0 }, { 69, 0 }, { 69, 13 }, { 60, 13 } },
      { edges = { [1] = Proj(56, 69), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, 14, Tile(68, 59, 72, 64, { top = 13 }), 69, { z1 = 60 }) } })
    return parts
  end
  local labCells = {}
  for j = 0, 3 do for i = 0, 6 do labCells[#labCells + 1] = { i, j } end end
  labCells[#labCells + 1] = { 4, 4 }
  labCells[#labCells + 1] = { 5, 4 }

  -- Slabs read column by column off a drawing (trees, statues, a gable standing before a wall):
  -- runs { x0, x1, t, b }, a slab a run, its front at z b + 1 (its foot row b) projected, its top
  -- at the run's top row t, its back at z `zb`. The drawing shows only their fronts: behind the
  -- front's top edge each falls back at 45 degrees (the GBA's line of sight: edge on in its view,
  -- facing away from every lower camera), laid with the rows `fall` (a Strip's)
  local function slabs(name, runs, zb, side, fall, dx)
    local parts = {}
    dx = dx or 0
    local back = Strip(fall, { rep = fall })
    for _, r in ipairs(runs) do
      local zf = r[4] + 1
      local y = zf - r[3]
      local d = zf - zb
      parts[#parts + 1] = Prism(name, r[1] + dx, r[2] + dx, { { zb, 0 }, { zf, 0 }, { zf, y }, { zb, y - d } },
        { edges = { [1] = Proj(), [2] = back }, skip = { 0, 3 },
          caps = { Band(0, y + 1, side, zf, { z1 = zb }) } })
    end
    return parts
  end

  -- the statues of Indigo Plateau's court (8 and 14 x 9-10 and 12-13, 16 x 32; their bases drawn
  -- alike in two metatiles): read column by column, their feet row 31 (the front at z 32), 8 px deep
  local STATUE = { { 0, 1, 7 }, { 1, 2, 6 }, { 2, 3, 1 }, { 3, 5, 0 }, { 5, 6, 1 }, { 6, 10, 0 }, { 10, 11, 1 },
    { 11, 13, 0 }, { 13, 14, 1 }, { 14, 15, 6 }, { 15, 16, 7 } }
  for _, r in ipairs(STATUE) do r[4] = 31 end
  local function statue()
    return slabs("statue", STATUE, 24, Tile(2, 20, 14, 28, { top = 32 }), { 16, 20 })
  end

  -- the Pokemon League (Indigo Plateau, 6-16 x 0-6, 176 x 112, and its statues' feet): a flat
  -- corrugated top from the map's top edge to its outline, row 64; the facade below, its foot row
  -- 103 (the front at z 104); before it, standing on its last row, four trees (their outline read
  -- column by column: tips at row 77, feet at 111) and two statues (x 32-47, 128-143, rows 96-127,
  -- on the cell row below); the entrance's gable and wings x 64-111 forward to row 109 (z 110),
  -- their tops the gable's peak at row 65 and the wings' slopes from row 84.
  local LEAGUE_TREE = { { 0, 1, 88, 108 }, { 1, 2, 85, 109 }, { 2, 3, 81, 110 }, { 3, 6, 79, 111 },
    { 6, 7, 78, 111 }, { 7, 9, 77, 111 }, { 9, 10, 78, 111 }, { 10, 13, 79, 111 }, { 13, 14, 81, 110 },
    { 14, 15, 85, 109 }, { 15, 16, 88, 108 } }
  local LEAGUE_GABLE = { { 64, 65, 89 }, { 65, 66, 88 }, { 66, 68, 87 }, { 68, 70, 86 }, { 70, 72, 85 },
    { 72, 74, 84 }, { 74, 75, 72 }, { 75, 77, 71 }, { 77, 79, 70 }, { 79, 81, 69 }, { 81, 83, 68 },
    { 83, 85, 67 }, { 85, 87, 66 }, { 87, 89, 65 }, { 89, 91, 66 }, { 91, 93, 67 }, { 93, 95, 68 },
    { 95, 97, 69 }, { 97, 99, 70 }, { 99, 101, 71 }, { 101, 102, 72 }, { 102, 104, 84 }, { 104, 106, 85 },
    { 106, 108, 86 }, { 108, 110, 87 }, { 110, 111, 88 }, { 111, 112, 89 } }
  for _, r in ipairs(LEAGUE_GABLE) do r[4] = 109 end
  local function league()
    local parts = { flat_top(0, 176, 104, 0, 0, 64, { fall = { 4, 20 } }) }
    local leaf = Tile(22, 96, 26, 104, { top = 30 })
    for _, dx in ipairs({ 16, 48, 112, 144 }) do
      for _, p in ipairs(slabs("tree", LEAGUE_TREE, 104, leaf, { 96, 100 }, dx)) do parts[#parts + 1] = p end
    end
    local stone = Tile(34, 112, 46, 120, { top = 32 })
    for _, dx in ipairs({ 32, 128 }) do
      for _, p in ipairs(slabs("statue", { { 0, 16, 96, 127 } }, 120, stone, { 112, 116 }, dx)) do
        parts[#parts + 1] = p
      end
    end
    for _, p in ipairs(slabs("entrance", LEAGUE_GABLE, 104, Tile(66, 96, 72, 104, { top = 45 }), { 96, 100 })) do
      parts[#parts + 1] = p
    end
    return parts
  end
  local leagueCells = {}
  for j = 0, 6 do for i = 0, 10 do leagueCells[#leagueCells + 1] = { i, j } end end
  leagueCells[#leagueCells + 1] = { 2, 7 }
  leagueCells[#leagueCells + 1] = { 8, 7 }

  -- the Sevii Islands' (their three tilesets draw the same kits)
  local SEVII_GROUND = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0BE, 0x0C3, 0x0C4, 0x0C5, 0x0C6, 0x0C7, 0x0CB, 0x0CC,
                         0x0CD, 0x0CE, 0x0CF }

  -- One Island's Pokemon Network Center (11-17 x 0-5, 112 x 96): a Pokemon Center's hipped roof at
  -- seven cells - its outline row 10, its highlight row 11, the slope's light lines every 4 rows
  -- from row 16 and its tiles every 4 px from x 7 (the network's emblem drawn on it, rows 30-63),
  -- the hips x 0-6 and 105-111; the eave rows 64-68; the facade rows 69-93, its outline row 94
  -- (the front at z 95), its bottom corners cut away
  local function network_center()
    local front_z, back_z, overhang = 95, 16, 2
    local zf, zb = front_z + overhang, back_z - overhang
    local roof = HipRoof("roof", 0, 112, zf, zb, zf - 69, {
      fascia = Strip({ 64, 69 }, { wrap = { 7, 105 } }),
      slope = Strip({ 16, 64 }, { rep = { 16, 20 }, wrap = { 7, 105 } }),
      teeth = { 11, 12 }, cap = { 10, 11 }, pitch = PITCH, run = 7,
      ridge_u = { 7, 105 }, end_tile = Tile(7, 10, 8, 11) })
    local wall_top = front_z - 69
    local plaster = Tile(16, 84, 32, 88, { top = wall_top })
    local walls = Prism("walls", 2, 110,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(69, 95), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, wall_top, plaster, front_z, { z1 = back_z }) } })
    return { walls, roof }
  end

  -- the Sevii Islands' houses (One Island's at 18-22 x 6-9, 80 x 64; their tops drawn over whatever
  -- is behind them, so only the lower rows must repeat): a gabled roof, its pale top rows 8-19 and
  -- its purple corrugations down to row 43; the eave rows 44-45; the facade rows 46-61, its base
  -- rows 62-63 (the front at z 64)
  local function sevii_house()
    return gable_house(80, 64, 16, { facade = 46, eave = { 44, 46 }, slope = { 8, 44 },
      side = Tile(4, 48, 8, 56, { top = 18 }) })
  end

  -- their red-roofed house (Three Island's at 2-6 x 28-31, 80 x 64): the same, its pale top rows
  -- 8-19 (a fence drawn over it), its red corrugations to row 43; the eave rows 44-47; the facade
  -- rows 48-61, the base rows 62-63
  local function sevii_red_house()
    return gable_house(80, 64, 16, { facade = 48, eave = { 44, 48 }, slope = { 8, 44 },
      side = Tile(4, 49, 8, 56, { top = 16 }) })
  end

  -- the Sevii Islands' harbor (Two Island's at 8-12 x 9-13, 80 x 80, its cranes on the water either
  -- side the map's): a gabled roof of red corrugations from the rect's top down to row 41; the eave
  -- rows 42-47; the facade rows 48-70, its base row 71 (the front at z 72)
  local function harbor()
    return gable_house(80, 72, 8, { facade = 48, eave = { 42, 48 }, slope = { 0, 42 },
      side = Tile(4, 64, 14, 70, { top = 24 }) })
  end

  -- Bill's sea cottage (Route 25, 49-53 x 1-4, 80 x 64): a hipped green roof, its front slope rows
  -- 1-33 (as many as its run and rise show at 17.7 degrees: its ridge the drawing's top), the hips
  -- either side; the eave's yellow board rows 34-45; the facade rows 46-61 (the front at z 62); on
  -- the roof, x 57-72, Bill's machine: its top rows 1-13, its front rows 14-26, standing where the
  -- slope is drawn at row 27
  local function bills_cottage()
    local front_z, back_z, overhang = 62, 16, 2
    local zf, zb = front_z + overhang, back_z - overhang
    local roof = HipRoof("roof", 0, 80, zf, zb, zf - 46, {
      -- (the hips laid with the slope's plain columns, not the machine's, which hides the rest)
      fascia = Strip({ 34, 46 }, { wrap = { 15, 65 } }),
      slope = Strip({ 1, 34 }, { wrap = { 15, 57 } }),
      teeth = { 1, 2 }, cap = { 1, 2 }, pitch = 17.7, run = 15,
      ridge_u = { 15, 65 }, end_tile = Tile(20, 1, 21, 2) })
    local wall_top = front_z - 46
    local side = Tile(2, 48, 8, 60, { top = wall_top })
    local walls = Prism("walls", 1, 79,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(46, front_z), [2] = side }, skip = { 1, 3 },
        caps = { Band(0, wall_top, side, front_z, { z1 = back_z }) } })
    -- (the slope at row 27: a fifth of the way up its 25 run and 8 rise from the fascia's top)
    local t = (34 - 27) / 33
    local zc, yc = zf - t * 25, (zf - 34) + t * 8
    local ytop = zc - 14
    local zt = 1 + ytop
    local grey = Tile(60, 15, 66, 24, { top = ytop })
    local machine = Prism("machine", 57, 73, { { zt, yc - 4 }, { zc, yc - 4 }, { zc, ytop }, { zt, ytop } },
      { edges = { [1] = Proj(14, 27), [2] = Proj(1, 14), [3] = grey }, skip = { 0 },
        caps = { Band(yc - 4, ytop + 1, grey, zc, { z1 = zt }) } })
    return { walls, roof, machine }
  end

  -- the Power Plant (Route 10, 3-11 x 35-41, 144 x 112): an octagon read column by column off its
  -- outline - each run its own block, its roof's back edge at row t, the rim's front from row r,
  -- its foot at row b (the front at z b + 1): 48 high everywhere, so its roof is one level; its
  -- front corners step back at 45 degrees, its back ones as drawn. On the roof four stacks (x 14-33,
  -- 46-65, 78-97, 110-129), read the same way: their pedestals' flanks, their tubes' tops to row
  -- 11 (the map's row above keeps the stacks' tips: it is the cliff's), their fronts to their feet
  -- at row 38, where the roof is drawn (z 87).
  local PLANT = { { 0, 2, 6, 44, 90 }, { 2, 4, 5, 44, 91 }, { 4, 6, 4, 44, 92 }, { 6, 7, 3, 44, 93 },
    { 7, 8, 3, 45, 93 }, { 8, 9, 2, 45, 94 }, { 9, 10, 2, 46, 94 }, { 10, 11, 1, 46, 95 }, { 11, 12, 1, 47, 95 },
    { 12, 13, 0, 47, 95 }, { 13, 32, 0, 48, 95 }, { 32, 33, 0, 49, 96 }, { 33, 34, 0, 50, 97 }, { 34, 35, 0, 51, 98 },
    { 35, 36, 0, 52, 99 }, { 36, 37, 0, 53, 100 }, { 37, 38, 0, 54, 101 }, { 38, 39, 0, 55, 102 },
    { 39, 72, 0, 56, 103 } }
  for k = #PLANT, 1, -1 do
    local r = PLANT[k]
    PLANT[#PLANT + 1] = { 144 - r[2], 144 - r[1], r[3], r[4], r[5] }
  end
  local STACK = { { 0, 2, 16, 17 }, { 2, 3, 0, 11 }, { 3, 4, 0, 11 }, { 4, 16, 0, 11 }, { 16, 17, 0, 11 },
    { 17, 18, 0, 11 }, { 18, 20, 16, 17 } }
  local function power_plant()
    local parts = {}
    local wall = Tile(20, 60, 30, 70, { top = 48 })
    for _, r in ipairs(PLANT) do
      local zf = r[5] + 1
      local h = zf - r[4]
      local zb = r[3] + h
      parts[#parts + 1] = Prism("plant", r[1], r[2], { { zb, 0 }, { zf, 0 }, { zf, h }, { zb, h } },
        { edges = { [1] = Proj(), [2] = Proj() }, skip = { 0, 3 },
          caps = { Band(0, h + 1, wall, zf, { z1 = zb }) } })
    end
    local steel = Tile(18, 14, 30, 22, { top = 75 })
    for _, x0 in ipairs({ 14, 46, 78, 110 }) do
      for _, r in ipairs(STACK) do
        local zf, y0 = 87, 48
        local y = y0 + (39 - r[4])
        local zb = zf - (r[4] - r[3])
        parts[#parts + 1] = Prism("stack", x0 + r[1], x0 + r[2],
          { { zb, y0 - 2 }, { zf, y0 - 2 }, { zf, y }, { zb, y } },
          { edges = { [1] = Proj(), [2] = Proj() }, skip = { 0, 3 },
            caps = { Band(y0 - 2, y + 1, steel, zf, { z1 = zb }) } })
      end
    end
    return parts
  end
  local plantCells = {}
  for j = 0, 5 do for i = 0, 8 do plantCells[#plantCells + 1] = { i, j } end end
  for i = 2, 6 do plantCells[#plantCells + 1] = { i, 6 } end

  -- the Pokemon League's gate (Route 22, 4-12 x 0-5, 144 x 96, and its steps' row): the League's
  -- kit at nine cells - its corrugated top from the map's top edge to the outline row 56, the
  -- facade rows 57-93 (the front at z 94), four trees before it (tips at row 69, feet at 94-95) and
  -- the steps before the door, rows 94-110 (z 111)
  local GATE_TREE = { { 0, 1, 80, 94 }, { 1, 2, 77, 94 }, { 2, 3, 73, 95 }, { 3, 5, 71, 95 }, { 5, 6, 71, 94 },
    { 6, 7, 70, 95 }, { 7, 9, 69, 95 }, { 9, 10, 70, 95 }, { 10, 11, 71, 94 }, { 11, 13, 71, 95 },
    { 13, 14, 73, 95 }, { 14, 15, 77, 94 }, { 15, 16, 80, 94 } }
  local function league_gate()
    local parts = { flat_top(0, 144, 94, 0, 0, 56, { fall = { 4, 20 } }) }
    local leaf = Tile(22, 80, 26, 88, { top = 20 })
    for _, dx in ipairs({ 16, 32, 96, 112 }) do
      for _, p in ipairs(slabs("tree", GATE_TREE, 86, leaf, { 82, 86 }, dx)) do parts[#parts + 1] = p end
    end
    parts[#parts + 1] = Prism("steps", 50, 94, { { 92, 0 }, { 111, 0 }, { 111, 2 }, { 92, 2 } },
      { edges = { [1] = Proj(109, 111), [2] = Proj() }, skip = { 0, 3 },
        caps = { Band(0, 3, Tile(52, 104, 60, 108, { top = 2 }), 111, { z1 = 92 }) } })
    return parts
  end
  local leagueGateCells = {}
  for j = 0, 5 do for i = 0, 8 do leagueGateCells[#leagueGateCells + 1] = { i, j } end end
  for i = 3, 5 do leagueGateCells[#leagueGateCells + 1] = { i, 6 } end

  local specs = {
    { name = "pallet_house", layout = "LAYOUT_PALLET_TOWN", rect = { 5, 3, 5, 5 }, ground = PALLET_GROUND,
      exact = { { 1, 48, 80, 80 }, { 8, 44, 72, 48 }, { 12, 40, 67, 44 }, { 12, 9, 67, 40 } },
      parts = function() return pallet_house(80) end },
    { name = "oaks_lab", layout = "LAYOUT_PALLET_TOWN", rect = { 13, 9, 7, 5 }, ground = PALLET_GROUND,
      exact = { { 0, 47, 112, 80 }, { 0, 40, 112, 47 }, { 3, 17, 80, 40 }, { 104, 17, 108, 40 }, { 80, 25, 104, 36 } },
      parts = oaks_lab },
    { name = "pokemon_center", layout = "LAYOUT_CERULEAN_CITY", rect = { 20, 15, 5, 5 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0E4 },
      exact = { { 2, 64, 78, 74 }, { 8, 52, 72, 64 }, { 24, 46, 56, 64 }, { 9, 45, 71, 52 }, { 11, 16, 69, 45 } },
      parts = pokemon_center },
    { name = "poke_mart", layout = "LAYOUT_CERULEAN_CITY", rect = { 27, 26, 4, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0E4, 0x0D4, 0x0DC },
      exact = { { 1, 32, 63, 48 }, { 16, 14, 48, 32 }, { 7, 0, 55, 14 }, { 7, 14, 16, 20 }, { 48, 14, 55, 20 } },
      parts = poke_mart },
    { name = "viridian_house_a", layout = "LAYOUT_VIRIDIAN_CITY", rect = { 24, 8, 5, 4 },
      ground = { 0x176, 0x16E, 0x001, 0x008, 0x009, 0x010, 0x011 },
      exact = { { 0, 45, 80, 64 }, { 1, 9, 47, 45 }, { 65, 9, 79, 45 }, { 47, 40, 65, 45 }, { 48, 9, 64, 40 } },
      parts = viridian_house },
    { name = "viridian_house_b", layout = "LAYOUT_VIRIDIAN_CITY", rect = { 24, 15, 5, 4 },
      ground = { 0x176, 0x16E, 0x001, 0x008, 0x009, 0x010, 0x011 },
      exact = { { 0, 45, 80, 64 }, { 1, 9, 47, 45 }, { 65, 9, 79, 45 }, { 47, 40, 65, 45 }, { 48, 9, 64, 40 } },
      parts = viridian_house },
    { name = "viridian_gym", layout = "LAYOUT_VIRIDIAN_CITY", rect = { 33, 6, 6, 5 }, match_rows = { 1, 5 },
      ground = { 0x16E, 0x176, 0x16D, 0x001, 0x008, 0x009, 0x010, 0x011, 0x160 },
      exact = { { 3, 48, 42, 70 }, { 69, 48, 93, 70 }, { 42, 51, 69, 79 }, { 8, 41, 88, 47 }, { 8, 5, 88, 41 } },
      parts = gym },
    { name = "pewter_gym", layout = "LAYOUT_PEWTER_CITY", rect = { 12, 12, 7, 5 }, match_rows = { 1, 5 },
      ground = { 0x1C9, 0x009, 0x011, 0x0E6, 0x160, 0x001, 0x008, 0x010 },
      exact = { { 3, 48, 42, 70 }, { 69, 48, 109, 70 }, { 42, 51, 69, 79 }, { 8, 41, 104, 47 }, { 8, 5, 104, 41 } },
      parts = function() return gym({ w = 112 }) end },
    { name = "celadon_gym", layout = "LAYOUT_CELADON_CITY", rect = { 8, 26, 8, 5 }, match_rows = { 1, 5 },
      ground = { 0x176, 0x175, 0x16E, 0x160, 0x001, 0x008, 0x009, 0x010, 0x011 },
      exact = { { 3, 48, 42, 70 }, { 69, 48, 125, 70 }, { 42, 51, 69, 79 }, { 8, 41, 120, 47 }, { 8, 5, 120, 41 } },
      parts = function() return gym({ w = 128 }) end },
    { name = "pewter_house", layout = "LAYOUT_PEWTER_CITY", rect = { 32, 8, 5, 4 },
      ground = { 0x004, 0x008, 0x001, 0x1B8, 0x1C0, 0x009, 0x010, 0x011 },
      exact = { { 1, 44, 80, 63 }, { 0, 10, 80, 44 } },
      parts = pewter_house },
    { name = "pewter_museum", layout = "LAYOUT_PEWTER_CITY", rect = { 12, 0, 11, 8 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x087, 0x1B9 }, owned = ownedOf(museumCells),
      exact = { { 1, 72, 64, 96 }, { 112, 72, 175, 96 }, { 64, 72, 112, 124 }, { 7, 56, 167, 68 },
                { 15, 48, 161, 56 }, { 7, 10, 169, 48 }, { 1, 10, 6, 68 }, { 170, 10, 174, 68 } },
      parts = pewter_museum },
    { name = "pewter_annex", layout = "LAYOUT_PEWTER_CITY", rect = { 23, 1, 5, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011 },
      exact = { { 0, 44, 72, 64 }, { 0, 2, 72, 44 } },
      parts = pewter_annex },
    ceruleanSpec("cerulean_house_a", 8, 8, 7),
    ceruleanSpec("cerulean_house_b", 15, 8, 6),
    ceruleanSpec("cerulean_house_c", 28, 8, 7),
    ceruleanSpec("cerulean_house_d", 38, 7, 6),
    ceruleanSpec("cerulean_house_e", 13, 14, 7),
    ceruleanSpec("cerulean_house_f", 21, 25, 6),
    ceruleanSpec("cerulean_house_g", 31, 25, 5),
    { name = "bike_shop", layout = "LAYOUT_CERULEAN_CITY", rect = { 12, 23, 4, 7 },
      ground = { 0x0E4, 0x0D4, 0x001, 0x004, 0x008, 0x009, 0x010, 0x011 },
      exact = { { 0, 56, 64, 73 }, { 3, 9, 61, 11 }, { 1, 11, 63, 56 }, { 4, 73, 60, 87 }, { 8, 87, 56, 96 }, { 5, 86, 8, 99 }, { 56, 86, 59, 99 } },
      parts = bike_shop },
    -- Lavender Town's houses (8-12 x 8-11, 3-7 x 13-16, 8-12 x 13-16; two tops, one facade; 80 x
    -- 64): a flat purple top in its frame, rows 8-41; the eave rows 42-43; the facade rows 44-61,
    -- its base rows 62-63 (the front at z 64)
    { name = "lavender_house_a", layout = "LAYOUT_LAVENDER_TOWN", rect = { 8, 8, 5, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011 }, exact = { { 0, 42, 80, 64 }, { 1, 8, 79, 42 } },
      parts = function() return { flat_top(0, 80, 64, 16, 8, 42, { fall = { 16, 24 } }) } end },
    { name = "lavender_house_b", layout = "LAYOUT_LAVENDER_TOWN", rect = { 8, 13, 5, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011 }, exact = { { 0, 42, 80, 64 }, { 1, 8, 79, 42 } },
      parts = function() return { flat_top(0, 80, 64, 16, 8, 42, { fall = { 16, 24 } }) } end },
    { name = "pokemon_tower", layout = "LAYOUT_LAVENDER_TOWN", rect = { 15, 0, 7, 7 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x162, 0x163, 0x164 },
      exact = { { 1, 80, 111, 104 }, { 1, 64, 111, 80 }, { 20, 0, 92, 64 } },
      parts = pokemon_tower },
    vermilionSpec("vermilion_house_a", 8, 3, 5),
    vermilionSpec("vermilion_house_b", 18, 3, 4),
    vermilionSpec("vermilion_house_c", 25, 3, 5),
    vermilionSpec("vermilion_house_d", 18, 14, 4),
    vermilionSpec("vermilion_house_e", 27, 21, 4),
    { name = "fan_club", layout = "LAYOUT_VERMILION_CITY", rect = { 11, 14, 5, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x12B, 0x12C, 0x115, 0x287 },
      exact = { { 2, 39, 78, 62 }, { 1, 2, 79, 34 }, { 1, 34, 17, 39 }, { 35, 34, 79, 39 }, { 17, 34, 35, 47 } },
      parts = fan_club },
    celadonBlock("celadon_block_a", 4, 4, 5, 8, 3),
    celadonBlock("celadon_block_b", 18, 4, 7, 8, 3),
    celadonBlock("celadon_block_c", 27, 4, 7, 8, 3),
    celadonBlock("celadon_block_d", 34, 7, 4, 5, 2),
    celadonBlock("celadon_block_e", 38, 7, 4, 5, 2),
    celadonBlock("celadon_block_f", 42, 7, 4, 5, 2),
    celadonBlock("celadon_block_g", 44, 17, 4, 5, 2),
    celadonBlock("celadon_block_h", 48, 17, 4, 5, 2),
    celadonBlock("celadon_block_i", 4, 25, 4, 5, 2),
    celadonBlock("celadon_block_j", 36, 25, 4, 5, 2),
    celadonBlock("celadon_block_k", 48, 25, 4, 5, 2),
    celadonBlock("celadon_block_l", 20, 29, 4, 6, 2),
    celadonBlock("celadon_block_m", 20, 26, 4, 3, 2),
    -- the Celadon Dept. Store (9-17 x 5-15, 144 x 176): its flat grey top rows 0-57 (the rooftop's
    -- enclosure drawn on it), its cornice's bands rows 58-67 and the storeys of bay windows below,
    -- its foot row 160 (the front at z 161); its entrances' paths below are the map's
    { name = "celadon_dept_store", layout = "LAYOUT_CELADON_CITY", rect = { 9, 5, 9, 11 }, ground = CELADON_GROUND,
      exact = { { 4, 58, 140, 160 }, { 6, 1, 138, 58 } },
      parts = function() return { flat_top(0, 144, 161, 16, 0, 58, { fall = { 20, 40 } }) } end },
    { name = "blue_hall", layout = "LAYOUT_CELADON_CITY", rect = { 24, 16, 6, 3 }, ground = CELADON_GROUND,
      exact = { { 2, 27, 94, 46 }, { 12, 24, 83, 27 }, { 12, 1, 83, 24 } },
      parts = blue_hall },
    -- the Game Corner (31-37 x 16-21, 112 x 96): a flat cream top (its skylights) rows 24-65 behind
    -- its railing's posts; its brown edge rows 66-70 and the orange facade below, its foot row 95
    -- (the front at z 96); the entrance's arch x 40-71 forward to its pillars' foot, row 100
    { name = "game_corner", layout = "LAYOUT_CELADON_CITY", rect = { 31, 16, 7, 6 }, ground = CELADON_GROUND,
      exact = { { 2, 66, 40, 94 }, { 72, 66, 110, 94 }, { 6, 26, 106, 56 }, { 6, 56, 40, 66 }, { 72, 56, 106, 66 },
                { 40, 56, 72, 101 } },
      parts = function()
        local arch = Prism("arch", 40, 72, { { 94, 0 }, { 101, 0 }, { 101, 45 }, { 94, 45 } },
          { edges = { [1] = Proj(56, 101), [2] = Proj() }, skip = { 0, 3 },
            caps = { Band(0, 46, Tile(41, 88, 46, 98, { top = 45 }), 101, { z1 = 94 }) } })
        return { flat_top(0, 112, 96, 16, 24, 66, { fall = { 30, 40 } }), arch }
      end },
    -- the Prize Corner beside it (38-40 x 16-20, 48 x 80): the same, its top rows 24-49, its facade
    -- from row 50, its foot row 79 (the front at z 80)
    { name = "prize_corner", layout = "LAYOUT_CELADON_CITY", rect = { 38, 16, 3, 5 }, ground = CELADON_GROUND,
      exact = { { 1, 50, 47, 78 }, { 5, 26, 43, 50 } },
      parts = function() return { flat_top(0, 48, 80, 16, 24, 50, { fall = { 30, 40 } }) } end },
    -- Fuchsia City's houses (13-17, 18-22, 32-36, 37-41 x 28-31, 80 x 64; their tops drawn over
    -- what is behind them, so only the lower rows must repeat): a flat tiled top rows 8-41, the eave
    -- rows 42-43, the facade rows 44-61, its base rows 62-63 (the front at z 64)
    { name = "fuchsia_house", layout = "LAYOUT_FUCHSIA_CITY", rect = { 13, 28, 5, 4 }, match_rows = { 1, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0D3, 0x0D4, 0x0D5 },
      exact = { { 0, 42, 80, 64 }, { 1, 9, 79, 42 } },
      parts = function() return { flat_top(0, 80, 64, 16, 8, 42, { fall = { 16, 24 } }) } end },
    -- the Safari Zone's Warden's house (26-31 x 12-16, 96 x 80): a thatched top, flat as drawn, rows
    -- 8-55; the eave rows 56-59; the facade rows 60-77, its foot row 79 (the front at z 80)
    { name = "warden_house", layout = "LAYOUT_FUCHSIA_CITY", rect = { 26, 12, 6, 5 },
      ground = { 0x0BE, 0x0CE, 0x001, 0x008, 0x009, 0x010, 0x011, 0x0DB, 0x0DC, 0x0DD },
      exact = { { 1, 56, 95, 78 }, { 1, 9, 95, 56 } },
      parts = function() return { flat_top(0, 96, 80, 16, 8, 56, { fall = { 14, 22 } }) } end },
    -- the Safari Zone's gate (22-27 x 0-5, 96 x 96): its thatched top from the map's top edge to
    -- row 59, the eave rows 60-64, the facade rows 65-94 (the front at z 96)
    { name = "safari_gate", layout = "LAYOUT_FUCHSIA_CITY", rect = { 22, 0, 6, 6 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0DC },
      exact = { { 1, 60, 95, 95 }, { 1, 0, 95, 60 } },
      parts = function() return { flat_top(0, 96, 96, 0, 0, 60, { fall = { 14, 22 } }) } end },
    saffronSpec("saffron_house_a", 17, 10, 4, 2),
    saffronSpec("saffron_house_b", 21, 10, 4, 2),
    saffronSpec("saffron_house_c", 41, 34, 5, 2),
    saffronSpec("saffron_house_d", 22, 18, 4, 1),
    saffronSpec("saffron_house_e", 50, 8, 4, 1),
    saffronSpec("saffron_house_f", 19, 41, 4, 1),
    -- Saffron's yellow apartment blocks (19-23, 24-28, 38-42, 43-47 x 25-30, 80 x 96): a framed
    -- green top (its hatch drawn on it) rows 1-39; the parapet's yellow front rows 40-45 and the
    -- storeys below, its base rows 94-95 (the front at z 96); the fence below is the map's
    { name = "saffron_block", layout = "LAYOUT_SAFFRON_CITY", rect = { 19, 25, 5, 6 }, ground = SAFFRON_GROUND,
      exact = { { 1, 40, 79, 94 }, { 2, 2, 78, 40 } },
      parts = function() return { flat_top(0, 80, 96, 16, 1, 40, { fall = { 10, 30 } }) } end },
    -- Silph Co. (29-37 x 16-30, 144 x 240): its outline rows 8-11, its purple roof rows 12-78 (the
    -- glass vault drawn down its middle), its edge row 79; ten storeys of 16 rows below and the
    -- entrance, its base row 231 (the front at z 232)
    { name = "silph_co", layout = "LAYOUT_SAFFRON_CITY", rect = { 29, 16, 9, 15 }, ground = SAFFRON_GROUND,
      exact = { { 1, 79, 143, 230 }, { 2, 12, 142, 79 } },
      parts = function() return { flat_top(0, 144, 232, 16, 9, 79, { fall = { 20, 60 } }) } end },
    -- the Fighting Dojo (37-42 x 8-11, 96 x 64): a gabled roof, its ridge's band rows 10-17 above
    -- courses every 4 rows down to row 51; the facade rows 52-63 (the entrance's porch drawn in it)
    { name = "fighting_dojo", layout = "LAYOUT_SAFFRON_CITY", rect = { 37, 8, 6, 4 }, ground = SAFFRON_GROUND,
      exact = { { 1, 52, 95, 63 }, { 1, 19, 95, 50 } },
      parts = function()
        return gable_house(96, 64, 16, { facade = 52, eave = { 50, 52 }, slope = { 10, 50 },
          side = Tile(2, 54, 8, 62, { top = 12 }) })
      end },
    -- Saffron's gym: the General's (as Pewter's) with a corner of Saffron's own
    { name = "saffron_gym", layout = "LAYOUT_SAFFRON_CITY", rect = { 43, 8, 7, 5 }, match_rows = { 1, 5 },
      ground = SAFFRON_GROUND,
      exact = { { 3, 48, 42, 70 }, { 69, 48, 109, 70 }, { 42, 51, 69, 79 }, { 8, 41, 104, 47 }, { 8, 5, 104, 41 } },
      parts = function() return gym({ w = 112 }) end },
    -- the Route gatehouses (the General's: every gate of Kanto), 96 wide: a corrugated top, flat as
    -- drawn, rows 0-47; the eave and the band of windows from row 48, the facade below - the north-
    -- south gate's (Saffron's 32-37 x 47-52) with its recessed entrance, to row 95 (the front at z
    -- 96); the east-west gate's (2-7 x 24-28) to row 79 (z 80)
    { name = "gate_ns", layout = "LAYOUT_SAFFRON_CITY", rect = { 32, 47, 6, 6 }, ground = SAFFRON_GROUND,
      exact = { { 1, 48, 95, 95 }, { 1, 1, 95, 48 } },
      parts = function() return { flat_top(0, 96, 96, 0, 0, 48, { fall = { 4, 20 } }) } end },
    { name = "gate_ew", layout = "LAYOUT_SAFFRON_CITY", rect = { 2, 24, 6, 5 }, ground = SAFFRON_GROUND,
      exact = { { 1, 48, 95, 79 }, { 1, 1, 95, 48 } },
      parts = function() return { flat_top(0, 96, 80, 0, 0, 48, { fall = { 4, 20 } }) } end },
    { name = "pokemon_mansion", layout = "LAYOUT_CINNABAR_ISLAND", rect = { 5, 0, 7, 5 }, ground = CINNABAR_GROUND,
      owned = ownedOf(mansionCells),
      exact = { { 2, 30, 110, 64 }, { 0, 0, 112, 30 }, { 40, 49, 72, 70 } },
      parts = mansion },
    { name = "cinnabar_lab", layout = "LAYOUT_CINNABAR_ISLAND", rect = { 5, 6, 7, 5 }, ground = CINNABAR_GROUND,
      owned = ownedOf(labCells),
      exact = { { 16, 3, 96, 61 }, { 4, 12, 16, 54 }, { 96, 12, 108, 54 }, { 16, 0, 24, 63 }, { 40, 0, 48, 63 },
                { 64, 0, 72, 56 }, { 88, 0, 96, 56 }, { 68, 58, 92, 68 } },
      parts = cinnabar_lab },
    -- Cinnabar's gym: the General's (as Viridian's), its own corner beside the porch
    { name = "cinnabar_gym", layout = "LAYOUT_CINNABAR_ISLAND", rect = { 17, 0, 6, 5 }, match_rows = { 1, 5 },
      ground = CINNABAR_GROUND,
      exact = { { 3, 48, 42, 70 }, { 69, 48, 93, 70 }, { 42, 51, 69, 79 }, { 8, 41, 88, 47 }, { 8, 5, 88, 41 } },
      parts = gym },
    { name = "pokemon_league", layout = "LAYOUT_INDIGO_PLATEAU_EXTERIOR", rect = { 6, 0, 11, 8 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011 }, owned = ownedOf(leagueCells),
      exact = { { 2, 0, 174, 64 }, { 0, 64, 176, 77 }, { 0, 77, 16, 102 }, { 160, 77, 176, 102 },
                { 32, 77, 48, 128 }, { 128, 77, 144, 128 }, { 16, 77, 32, 108 }, { 48, 77, 64, 108 },
                { 112, 77, 128, 108 }, { 144, 77, 160, 108 }, { 64, 64, 112, 110 } },
      parts = league },
    { name = "league_statue", layout = "LAYOUT_INDIGO_PLATEAU_EXTERIOR", rect = { 8, 9, 1, 2 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011 }, exact = { { 0, 0, 16, 32 } }, parts = statue },
    { name = "network_center", layout = "LAYOUT_ONE_ISLAND", rect = { 11, 0, 7, 6 }, ground = SEVII_GROUND,
      exact = { { 8, 69, 104, 94 }, { 7, 64, 105, 69 }, { 7, 17, 105, 64 } },
      parts = network_center },
    -- (the Sevii kits stand in all three of the islands' tilesets, drawn alike: `anywhere`)
    { name = "sevii_house", layout = "LAYOUT_ONE_ISLAND", rect = { 18, 6, 5, 4 }, match_rows = { 1, 4 },
      ground = SEVII_GROUND, anywhere = true, exact = { { 1, 44, 79, 62 }, { 1, 9, 79, 44 } },
      parts = sevii_house },
    -- Two Island's shop (37-41 x 6-9, 80 x 64): a framed glass top, flat as drawn, rows 0-36 (drawn
    -- over the grass above it); the front's edge row 37 and the facade below (its canopy drawn on
    -- it), its base rows 62-63 (the front at z 64)
    { name = "sevii_red_house", layout = "LAYOUT_THREE_ISLAND", rect = { 2, 28, 5, 4 }, match_rows = { 1, 4 },
      ground = SEVII_GROUND, anywhere = true, exact = { { 1, 48, 79, 62 }, { 1, 44, 79, 48 }, { 1, 9, 79, 44 } },
      parts = sevii_red_house },
    -- Four Island's Day Care (11-14 x 10-13, 64 x 64): the Sevii house kit at four cells, its roof
    -- orange: the pale top rows 8-17, the corrugations to row 43; the eave rows 44-45; the facade
    -- rows 46-61, the base rows 62-63
    { name = "four_island_day_care", layout = "LAYOUT_FOUR_ISLAND", rect = { 11, 10, 4, 4 }, ground = SEVII_GROUND,
      exact = { { 1, 46, 63, 62 }, { 1, 44, 63, 46 }, { 2, 9, 63, 44 } },
      parts = function()
        return gable_house(64, 64, 16, { facade = 46, eave = { 44, 46 }, slope = { 8, 44 },
          side = Tile(18, 48, 22, 56, { top = 18 }) })
      end },
    -- the Resort Gorgeous house (38-42 x 5-8, 80 x 64): the Sevii kit in orange, a fence drawn over
    -- its top; its eave rows 42-45, its facade rows 46-61
    { name = "resort_house", layout = "LAYOUT_FIVE_ISLAND_RESORT_GORGEOUS", rect = { 38, 5, 5, 4 },
      match_rows = { 1, 4 }, ground = SEVII_GROUND,
      exact = { { 1, 46, 79, 62 }, { 1, 42, 79, 46 }, { 1, 9, 79, 42 } },
      parts = function()
        return gable_house(80, 64, 16, { facade = 46, eave = { 42, 46 }, slope = { 8, 42 },
          side = Tile(4, 48, 8, 56, { top = 18 }) })
      end },
    { name = "two_island_shop", layout = "LAYOUT_TWO_ISLAND", rect = { 37, 6, 5, 4 }, ground = SEVII_GROUND,
      exact = { { 1, 37, 79, 62 }, { 1, 1, 79, 37 } },
      parts = function() return { flat_top(0, 80, 64, 16, 0, 37, { fall = { 6, 20 } }) } end },
    -- (the harbor's last row, its base on the pier, drawn two ways: the four above must repeat)
    { name = "sevii_harbor", layout = "LAYOUT_TWO_ISLAND", rect = { 8, 9, 5, 5 }, ground = SEVII_GROUND,
      anywhere = true, match_rows = { 0, 4 },
      exact = { { 1, 48, 79, 71 }, { 1, 42, 79, 48 }, { 1, 1, 79, 42 } },
      parts = harbor },
    -- the General's gatehouse at other sizes: eight cells wide with a deeper top (Route 2's, by
    -- Viridian Forest, 2-9 x 13-18: its top's outline row 12, its eave from row 75, its windows to
    -- row 91, the front at z 92), and its passage gate with a shorter facade (Route 2's at 16-21 x
    -- 41-46: the top from row 12, the facade rows 59-94); their top rows drawn over what is behind
    { name = "gate_wide", layout = "LAYOUT_ROUTE_2", rect = { 2, 13, 8, 6 }, match_rows = { 1, 6 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0DB, 0x0DC, 0x0DD, 0x0C5, 0x0C6, 0x0C7, 0x0CD, 0x0CE, 0x0CF },
      exact = { { 1, 75, 127, 91 }, { 1, 13, 127, 75 } },
      parts = function() return { flat_top(0, 128, 92, 0, 12, 75, { fall = { 20, 36 } }) } end },
    { name = "gate_ns_b", layout = "LAYOUT_ROUTE_2", rect = { 16, 41, 6, 6 }, match_rows = { 1, 6 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0DB, 0x0DC, 0x0DD },
      exact = { { 1, 59, 95, 94 }, { 1, 13, 95, 59 } },
      parts = function() return { flat_top(0, 96, 95, 0, 12, 59, { fall = { 20, 36 } }) } end },
    -- and a small one, five cells (Route 12's, 12-16 x 16-19): its top from the rect's top edge to
    -- row 42, the eave and the facade rows 43-63 (the front at z 64)
    { name = "gate_small", layout = "LAYOUT_ROUTE_12", rect = { 12, 16, 5, 4 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x12B },
      exact = { { 1, 43, 79, 63 }, { 1, 1, 79, 43 } },
      parts = function() return { flat_top(0, 80, 64, 0, 0, 43, { fall = { 20, 36 } }) } end },
    -- Route 5's Day Care (21-25 x 21-25, 80 x 80): Pallet Town's house in orange
    { name = "route5_day_care", layout = "LAYOUT_ROUTE_5", rect = { 21, 21, 5, 5 },
      ground = { 0x010, 0x011, 0x008, 0x009, 0x0BD, 0x0BE, 0x0C5, 0x0C6, 0x0CD, 0x0CE },
      exact = { { 1, 48, 79, 77 }, { 8, 44, 72, 48 }, { 12, 40, 67, 44 }, { 12, 9, 67, 40 } },
      parts = function() return pallet_house(80) end },
    { name = "bills_cottage", layout = "LAYOUT_ROUTE_25", rect = { 49, 1, 5, 4 },
      ground = { 0x008, 0x009, 0x16A, 0x16B, 0x16C },
      exact = { { 2, 46, 78, 61 }, { 15, 34, 65, 46 }, { 15, 1, 57, 33 }, { 57, 1, 73, 26 } },
      parts = bills_cottage },
    -- the Cycling Road's gate (Route 16, 21-26 x 3-12, 96 x 160): the gatehouse kit stacked, two
    -- tops one behind the other and their eaves, flat as drawn, rows 0-138; the facade rows 139-154
    -- (the front at z 155)
    { name = "cycling_gate", layout = "LAYOUT_ROUTE_16", rect = { 21, 3, 6, 10 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0D4, 0x0DC, 0x0E4 },
      exact = { { 1, 139, 95, 154 }, { 1, 1, 95, 139 } },
      parts = function() return { flat_top(0, 96, 155, 0, 0, 139, { fall = { 20, 36 } }) } end },
    { name = "league_gate", layout = "LAYOUT_ROUTE_22", rect = { 4, 0, 9, 7 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011 }, owned = ownedOf(leagueGateCells),
      exact = { { 1, 0, 143, 56 }, { 0, 56, 144, 69 }, { 48, 56, 96, 94 }, { 0, 56, 16, 94 }, { 128, 56, 144, 94 },
                { 16, 69, 48, 94 }, { 96, 69, 128, 94 }, { 52, 94, 92, 110 } },
      parts = league_gate },
    { name = "power_plant", layout = "LAYOUT_ROUTE_10", rect = { 3, 35, 9, 7 },
      ground = { 0x001, 0x008, 0x009, 0x010, 0x011, 0x0D0, 0x0D1 }, owned = ownedOf(plantCells),
      exact = { { 39, 0, 105, 103 }, { 13, 0, 32, 95 }, { 112, 0, 131, 95 } },
      parts = power_plant },
  }
  specs.helpers = {}
  return specs
end
