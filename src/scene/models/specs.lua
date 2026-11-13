-- Building models (Battle Scene: Overworld): one reading of the drawing per building type.
--
-- Each spec names where a reference copy of the building stands (a layout and a cell rectangle),
-- the metatiles of the ground round it, and the parts that rebuild it (src/scene/models/kernel.lua).
-- Row and column numbers are pixels of the reference rectangle's drawing (u = X, v = Z - Y); the
-- building is found wherever the map draws the same metatiles (src/scene/buildings.lua).
--
-- Ported from Emerald 3DS's scripts/voxel_building_specs.py (by Zallax and contributors, CC BY-NC-SA
-- 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), whose docstrings explain how each
-- drawing is read. Every number is theirs.
--
--   name, layout, rect = { x, y, w, h }, ground = { metatiles }, parts = function() -> parts
--   match_rows = { first, end }   only those rows (0-based, end exclusive) must repeat cell for cell
--   keep = { { u0, v0, u1, v1 }, ... }   only these rectangles of the drawing are the model's
--   owned = { [i .. "," .. j] = true }   only these cells of the rectangle are the model's
--   ground_px = true   ground is told apart pixel by pixel (the ground painted into its blocks)
--   parts_art = function(art) -> parts, texture   parts read off the drawing (a texture of its
--                own: the drawing with its grown band, K.flat), instead of parts

return function(K)
  local Prism, Proj, Tile, Band, Strip, HipRoof = K.Prism, K.Proj, K.Tile, K.Band, K.Strip, K.HipRoof
  local Walls, Frustum, Vault, Cylinder = K.Walls, K.Frustum, K.Vault, K.Cylinder
  local tan, rad = math.tan, math.rad

  local GRASS = 0x001
  local PITCH = 22.0
  local ROOF_COLUMNS = { 12, 68 }

  local function littleroot_house(plaster_x)
    local px0, px1 = plaster_x, plaster_x + 8
    local front_z, back_z = 80, 16
    local overhang = 2
    local lower = HipRoof("roof_lo", 0, 82, front_z + overhang, back_z - overhang, 28, {
      fascia = Strip({ 52, 54 }, { wrap = ROOF_COLUMNS }),
      slope = Strip({ 45, 52 }, { rep = { 16, 20 }, start = 16, wrap = ROOF_COLUMNS }),
      teeth = { 25, 32 }, cap = { 17, 25 }, pitch = PITCH, run = 7,
      ridge_u = { 0, 80 }, end_tile = Tile(0, 25, 8, 32) })
    local z_wall, y_base = K.slopePoint(lower, 7)
    local zf_hi = z_wall + overhang
    local y0_hi = zf_hi - 38
    local zb_hi = (lower.zf + lower.zb) - zf_hi
    local upper = HipRoof("roof_hi", 8, 72, zf_hi, zb_hi, y0_hi, {
      fascia = Strip({ 36, 38 }, { wrap = ROOF_COLUMNS }),
      slope = Strip({ 32, 36 }, { rep = { 16, 32 }, wrap = ROOF_COLUMNS }),
      teeth = { 9, 16 }, cap = { 1, 9 }, pitch = PITCH, run = 6,
      ridge_u = { 8, 72 }, end_tile = Tile(12, 9, 20, 16) })
    local storey_back = zb_hi + overhang
    local post = Tile(10, 38, 14, 45, { top = y0_hi })
    local storey = Prism("storey", 10, 70,
      { { z_wall, 28 }, { z_wall, y0_hi }, { storey_back, y0_hi }, { storey_back, 28 } },
      { edges = { [0] = Proj(38, 45), [2] = Tile(20, 38, 28, 45, { top = y0_hi }) }, skip = { 1, 3 },
        caps = { Band(-64, 200, Tile(20, 38, 28, 45, { top = y0_hi }), z_wall, { front = post, back = post, z1 = storey_back }) } })
    local wall_top = 28
    local corner = Tile(2, 54, 8, 80, { top = 26 })
    local base = Prism("ground_floor", 2, 80,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(54, 80), [2] = Tile(px0, 54, px1, 80, { top = 26 }) }, skip = { 1, 3 },
        caps = { Band(0, 26, Tile(px0, 54, px1, 80, { top = 26 }), front_z, { front = corner, back = corner, z1 = back_z }),
                 Band(26, wall_top + 1, Tile(px0, 54, px1, 55, { top = wall_top }), front_z) } })
    return { base, lower, storey, upper }
  end

  local function littleroot_lab()
    local front_z, back_z = 80, 16
    local overhang = 2
    local lab_columns = { 8, 104 }
    local roof = HipRoof("roof", 0, 114, front_z + overhang, back_z - overhang, 29, {
      fascia = Strip({ 50, 53 }, { wrap = lab_columns }),
      slope = Strip({ 46, 50 }, { rep = { 34, 46 }, wrap = lab_columns }),
      teeth = { 10, 15 }, cap = { 1, 10 }, pitch = 18.0, run = 6,
      ridge_u = { 0, 112 }, end_tile = Tile(48, 10, 57, 15), ridgeWrap = { 48, 104 } })
    local zbox, ybox = K.slopePoint(roof, 50 - 32)
    local ytop = zbox - 25
    local grey = Tile(20, 25, 40, 32, { top = ytop })
    local box = Prism("vent_box", 16, 48,
      { { zbox, ybox - 6 }, { zbox, ytop }, { zbox - 10, ytop }, { zbox - 10, ybox - 6 } },
      { edges = { [0] = Proj(25, 32), [2] = grey }, skip = { 3 }, caps = { Band(-64, 200, grey, zbox) } })
    local cowl = Cylinder("vent_cowl", 32, zbox - 10, 12, 9, ytop - 4, ytop + 4, Tile(24, 16, 40, 25))
    local wall_top = 29
    local post = Tile(2, 53, 8, 80, { top = 27 })
    local plaster = Tile(8, 53, 16, 80, { top = 27 })
    local base = Prism("ground_floor", 2, 112,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(53, 80), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, 27, plaster, front_z, { front = post, back = post, z1 = back_z }),
                 Band(27, wall_top + 1, Tile(8, 53, 16, 54, { top = wall_top }), front_z) } })
    return { base, roof, box, cowl }
  end

  local CENTER_ARCH = { { 16, 0 }, { 16.5, 1 }, { 17.5, 2 }, { 18.5, 3 }, { 19.5, 4 }, { 20.5, 4 },
    { 21.5, 5 }, { 22.5, 6 }, { 23.5, 6 }, { 24.5, 7 }, { 26.5, 7 }, { 27.5, 8 },
    { 36.5, 8 }, { 37.5, 7 }, { 39.5, 7 }, { 40.5, 6 }, { 41.5, 6 }, { 42.5, 5 },
    { 43.5, 4 }, { 44.5, 4 }, { 45.5, 3 }, { 46.5, 2 }, { 47.5, 1 }, { 48, 0 } }

  local function center_or_mart(rib_repeat, crown)
    local front, back = 64, 16
    local plan = { { 7, front }, { 57, front }, { 64, front - 7 }, { 64, back + 8 },
                   { 56, back }, { 8, back }, { 0, back + 8 }, { 0, front - 7 } }
    local parts = { Frustum("body", plan, {
      wall_top = 26,
      wall_side = Strip({ 38, 64 }, { wrap = { 8, 16 } }),
      band_rise = 7,
      band_side = Strip({ 24, 38 }, { wrap = { 8, 16 } }),
      top = Strip({ 9, 24 }, { rep = rib_repeat, wrap = { 8, 56 } }) }) }
    if crown then parts[#parts + 1] = Vault("crown", CENTER_ARCH, 57, 41, 33) end
    return parts
  end

  local function oldale_house()
    local front_z, back_z = 64, 16
    local overhang = 2
    local columns = { 8, 56 }
    local roof = HipRoof("roof", 0, 64, front_z + overhang, back_z - overhang, 30, {
      fascia = Strip({ 34, 36 }, { wrap = columns }),
      slope = Strip({ 30, 34 }, { rep = { 14, 30 }, wrap = columns }),
      teeth = { 10, 14 }, cap = { 0, 10 }, pitch = 22.0, run = 6,
      ridge_u = { 0, 64 }, end_tile = Tile(8, 10, 18, 14) })
    local wall_top = 30
    local post = Tile(2, 36, 9, 64, { top = 28 })
    local plaster = Tile(9, 36, 15, 64, { top = 28 })
    local base = Prism("ground_floor", 2, 64,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(36, 64), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, 28, plaster, front_z, { front = post, back = post, z1 = back_z }),
                 Band(28, wall_top + 1, Tile(9, 36, 15, 37, { top = wall_top }), front_z) } })
    return { base, roof }
  end

  local function briney_house()
    local front_z, back_z = 64, 16
    local overhang = 2
    local columns = { 8, 72 }
    local roof = HipRoof("roof", 0, 80, front_z + overhang, back_z - overhang, 27, {
      fascia = Strip({ 36, 39 }, { wrap = columns }),
      slope = Strip({ 16, 36 }, { rep = { 16, 24 }, wrap = columns }),
      teeth = { 9, 16 }, cap = { 0, 9 }, pitch = 22.0, run = 6,
      ridge_u = { 0, 80 }, end_tile = Tile(8, 9, 18, 16) })
    local floor_top, wall_top = 16, 27
    local post = Tile(1, 48, 8, 64, { top = floor_top })
    local reed = Tile(8, 48, 18, 64, { top = floor_top })
    local lattice = Tile(8, 39, 16, 48, { top = 25 })
    local lattice_end = Tile(0, 39, 3, 48, { top = 25 })
    local ground_floor = Prism("ground_floor", 1, 80,
      { { front_z, 0 }, { front_z, floor_top }, { back_z, floor_top }, { back_z, 0 } },
      { edges = { [0] = Proj(48, 64), [2] = reed }, skip = { 1, 3 },
        caps = { Band(0, floor_top, reed, front_z, { front = post, back = post, z1 = back_z }) } })
    local upper = Prism("lattice", 0, 80,
      { { front_z, floor_top }, { front_z, wall_top }, { back_z, wall_top }, { back_z, floor_top } },
      { edges = { [0] = Proj(39, 48), [2] = lattice }, skip = { 1, 3 },
        caps = { Band(floor_top, wall_top + 1, lattice, front_z, { front = lattice_end, back = lattice_end, z1 = back_z }) } })
    return { ground_floor, upper, roof }
  end

  local function flower_shop()
    local front, back = 64, 16
    local wall = 64 - 38
    local top = wall + (38 - 28)
    local post = Tile(1, 38, 6, 64, { top = wall })
    local siding = Tile(72, 40, 80, 48, { top = wall - 2 })
    local rim = Tile(9, 28, 17, 38, { top = top })
    local body = Prism("ground_floor", 1, 95,
      { { front, 0 }, { front, wall }, { back, wall }, { back, 0 } },
      { edges = { [0] = Proj(38, 64), [2] = siding }, skip = { 1, 3 },
        caps = { Band(0, wall, siding, front, { front = post, back = post, z1 = back }) } })
    local roof = Prism("roof", 0, 96,
      { { front, wall }, { front, top }, { back, top }, { back, wall } },
      { edges = { [0] = Proj(28, 38), [1] = Strip({ 4, 28 }, { rep = { 20, 28 }, tail = { 0, 4 } }), [2] = rim },
        skip = { 3 }, caps = { Band(wall, top + 1, rim, front) } })
    return { body, roof }
  end

  local function kit_house(width)
    local front_z, back_z = 64, 16
    local overhang = 2
    local columns = { 8, width - 8 }
    local roof = HipRoof("roof", 0, width, front_z + overhang, back_z - overhang, 28, {
      fascia = Strip({ 35, 38 }, { wrap = columns }),
      slope = Strip({ 32, 35 }, { rep = { 16, 32 }, wrap = columns }),
      teeth = { 10, 16 }, cap = { 0, 10 }, pitch = 22.0, run = 6,
      ridge_u = { 0, width }, end_tile = Tile(8, 10, 18, 16) })
    local wall_top = 28
    local post = Tile(2, 38, 8, 64, { top = 26 })
    local boards = Tile(9, 38, 15, 64, { top = 26 })
    local base = Prism("ground_floor", 2, width - 2,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(38, 64), [2] = boards }, skip = { 1, 3 },
        caps = { Band(0, 26, boards, front_z, { front = post, back = post, z1 = back_z }),
                 Band(26, wall_top + 1, Tile(9, 38, 15, 39, { top = wall_top }), front_z) } })
    return { base, roof }
  end

  local function kit_house_keep(width)
    return { { 0, 0, width, 38 }, { 2, 38, width - 2, 64 } }
  end

  local function dewford_house(width)
    local front, back, wall = 64, 16, 28
    local columns = { 8, width - 8 }
    local roof = HipRoof("roof", 0, width, front + 2, back - 2, wall, {
      fascia = Strip({ 35, 38 }, { wrap = columns }),
      slope = Strip({ 32, 35 }, { rep = { 16, 32 }, wrap = columns }),
      teeth = { 9, 16 }, cap = { 0, 9 }, pitch = PITCH, run = 6,
      ridge_u = { 0, width }, end_tile = Tile(16, 9, 25, 16), ridgeWrap = { 16, width - 8 } })
    local plaster = Tile(9, 38, 15, 64, { top = 26 })
    local post = Tile(2, 38, 8, 64, { top = 26 })
    local body = Prism("ground_floor", 2, width - 2,
      { { front, 0 }, { front, wall }, { back, wall }, { back, 0 } },
      { edges = { [0] = Proj(38, 64), [2] = plaster }, skip = { 1, 3 },
        caps = { Band(0, 26, plaster, front, { front = post, back = post, z1 = back }),
                 Band(26, wall + 1, Tile(9, 38, 15, 39, { top = wall }), front) } })
    return { body, roof }
  end

  local function gym()
    local front, porch, back = 72, 80, 2
    local wall_top, roof_top = 27, 31
    local panel = Tile(72, 45, 88, 72, { top = wall_top })
    local corner = Tile(88, 45, 94, 72, { top = wall_top })
    local lip = Tile(8, 41, 16, 45, { top = roof_top })
    local body = Prism("body", 2, 94,
      { { front, -1 }, { front, wall_top }, { back, wall_top }, { back, -1 } },
      { edges = { [0] = Proj(45, 72), [2] = panel }, skip = { 1, 3 },
        caps = { Band(-1, wall_top, panel, front, { front = corner, back = corner, z1 = back }) } })
    local roof = Prism("roof", 0, 96,
      { { front, wall_top }, { front, roof_top }, { back, roof_top }, { back, wall_top } },
      { edges = { [0] = Proj(41, 45), [1] = Strip({ 5, 41 }, { rep = { 5, 7 } }), [2] = lip },
        skip = { 3 }, caps = { Band(wall_top, roof_top + 1, lip, front) } })
    local porch_roof = Prism("porch_roof", 40, 72,
      { { porch, wall_top }, { porch, roof_top }, { front, roof_top }, { front, wall_top } },
      { edges = { [0] = Proj(49, 54) }, skip = { 2, 3 }, caps = { Band(wall_top, roof_top + 1, lip, porch) } })
    local porch_walls = Walls("porch", { { 40, front }, { 48, porch }, { 64, porch }, { 72, front } }, -1, wall_top)
    return { body, roof, porch_roof, porch_walls }
  end

  local function flat_block(width, height, roof, cornice, facade_top, o)
    o = o or {}
    local x0 = o.x0 or 0
    local x1 = o.x1 or width
    local front, back = height, 16
    local wall = height - facade_top
    local c0, c1 = cornice[1], cornice[2]
    local top = wall + (c1 - c0)
    local fixed, rep, tail = roof[1], roof[2], roof[3]
    local b = o.brick or { 8, facade_top, 16, facade_top + 16 }
    local brick = Tile(b[1], b[2], b[3], b[4], { top = wall })
    local pl = o.pilaster or { x0, facade_top, x0 + 8, facade_top + 16 }
    local pilaster = Tile(pl[1], pl[2], pl[3], pl[4], { top = wall })
    local r = o.rim or { 8, c0, 16, c1 }
    local rim = Tile(r[1], r[2], r[3], r[4], { top = top })
    local body = Prism("body", x0, x1,
      { { front, -1 }, { front, wall }, { back, wall }, { back, -1 } },
      { edges = { [0] = Proj(facade_top, height), [2] = brick }, skip = { 1, 3 },
        caps = { Band(-1, wall, brick, front, { front = pilaster, back = pilaster, z1 = back }) } })
    local parts = { body }
    local function slab(name, a, bb, offset)
      return Prism(name, a, bb,
        { { front, wall }, { front, top }, { back, top }, { back, wall } },
        { edges = { [0] = Proj(c0, c1),
                    [1] = Strip(fixed, { rep = rep, tail = tail, repeatOffset = (offset and offset ~= 0) and offset or nil }),
                    [2] = rim },
          skip = { 3 }, caps = { Band(wall, top + 1, rim, front) },
          west = (a == x0), east = (bb == x1) })
    end
    if not o.unit then
      parts[#parts + 1] = slab("roof", x0, x1)
    else
      local ux0, ux1, t0, t1, t2 = o.unit[1], o.unit[2], o.unit[3], o.unit[4], o.unit[5]
      parts[#parts + 1] = slab("roof_w", x0, ux0)
      parts[#parts + 1] = slab("roof_u", ux0, ux1, 8 - ux0)
      parts[#parts + 1] = slab("roof_e", ux1, x1)
      local zu = t2 + top
      local side = Tile(ux0 + 8, t1, ux0 + 16, t2, { top = top + (t2 - t1) })
      parts[#parts + 1] = Prism("unit", ux0, ux1,
        { { zu, top - 1 }, { zu, top + (t2 - t1) }, { zu - (t1 - t0), top + (t2 - t1) }, { zu - (t1 - t0), top - 1 } },
        { edges = { [0] = Proj(t1, t2), [1] = Proj(t0, t1), [2] = side }, skip = { 3 },
          caps = { Band(top - 1, top + (t2 - t1) + 1, side, zu) } })
    end
    return parts
  end

  local function flat_part(name, x0, x1, front, back, roof, cornice, facade_top, brick, rim, west, east)
    if west == nil then west = true end
    if east == nil then east = true end
    local wall = front - facade_top
    local c0, c1 = cornice[1], cornice[2]
    local top = wall + (c1 - c0)
    local fixed, rep, tail = roof[1], roof[2], roof[3]
    local brick_t = Tile(brick[1], brick[2], brick[3], brick[4], { top = wall })
    local rim_t = Tile(rim[1], rim[2], rim[3], rim[4], { top = top })
    local body = Prism(name, x0, x1,
      { { front, 0 }, { front, wall }, { back, wall }, { back, 0 } },
      { edges = { [0] = Proj(facade_top, front), [2] = brick_t }, skip = { 1, 3 },
        caps = { Band(0, wall, brick_t, front) }, west = west, east = east })
    local slab = Prism(name .. "_roof", x0, x1,
      { { front, wall }, { front, top }, { back, top }, { back, wall } },
      { edges = { [0] = Proj(c0, c1), [1] = Strip(fixed, { rep = rep, tail = tail }), [2] = rim_t },
        skip = { 3 }, caps = { Band(wall, top + 1, rim_t, front) }, west = west, east = east })
    return { body, slab }
  end

  local function concat(a, b)
    local o = {}
    for _, p in ipairs(a) do o[#o + 1] = p end
    for _, p in ipairs(b) do o[#o + 1] = p end
    return o
  end

  local function devon()
    local wing_roof = { { 8, 32 }, { 8, 10 }, { 2, 8 } }
    local parts = {}
    parts = concat(parts, flat_part("wing_w", 0, 48, 128, 0, wing_roof, { 32, 40 }, 40,
      { 8, 40, 48, 72 }, { 8, 32, 48, 40 }, true, false))
    parts = concat(parts, flat_part("wing_e", 112, 160, 128, 0, wing_roof, { 32, 40 }, 40,
      { 112, 40, 152, 72 }, { 112, 32, 152, 40 }, false, true))
    parts = concat(parts, flat_part("tower", 48, 112, 144, 0, { { 9, 40 }, { 9, 17 }, { 0, 9 } }, { 40, 56 }, 56,
      { 48, 56, 56, 88 }, { 56, 40, 64, 56 }))
    return parts
  end

  local function safari_canopy(z, v)
    local y1 = z + 3 - v
    return Prism("canopy", 24, 56, { { z, y1 - 4 }, { z + 3, y1 - 4 }, { z + 3, y1 }, { z, y1 } },
      { edges = { [1] = Proj(v, v + 4), [2] = Proj(v - 3, v) }, skip = { 0, 3 },
        caps = { Band(y1 - 4, y1 + 1, Tile(24, v, 28, v + 4, { top = y1 }), z + 3) } })
  end

  local function safari_gate()
    local parts = flat_block(80, 96, { { 2, 56 }, { 2, 10 }, nil }, { 56, 63 }, 63,
      { brick = { 4, 63, 8, 96 }, pilaster = { 0, 63, 4, 96 } })
    parts[#parts + 1] = safari_canopy(96, 76)
    return parts
  end

  local SAFARI_ROOF = { { 7, 40 }, { 7, 15 }, { 0, 7 } }
  local function safari_wing(x0, x1, brick, rim, west, east)
    return flat_part("wing", x0, x1, 80, 0, SAFARI_ROOF, { 40, 47 }, 47, brick, rim, west, east)
  end
  local function safari_south()
    local parts = safari_wing(0, 160, { 72, 47, 88, 80 }, { 72, 40, 88, 47 }, true, false)
    parts[#parts + 1] = safari_canopy(80, 60)
    return parts
  end
  local function safari_southeast()
    local brick = Tile(8, 47, 16, 80, { top = 33 })
    local fixed, rep, tail = SAFARI_ROOF[1], SAFARI_ROOF[2], SAFARI_ROOF[3]
    local wing = Prism("east_wing", 16, 96, { { 176, 0 }, { 176, 40 }, { 0, 40 }, { 0, 0 } },
      { edges = { [0] = Proj(), [1] = Strip({ fixed[1], 136 }, { rep = rep, tail = tail }), [2] = brick },
        skip = { 3 }, caps = { Band(0, 41, brick, 176) } })
    local parts = safari_wing(0, 16, { 8, 47, 16, 80 }, { 8, 40, 16, 47 }, false, false)
    parts[#parts + 1] = wing
    return parts
  end

  -- ── a HipRoof with no hips: gables at its ends (the Trick House) ──
  local function GableRoof(name, x0, x1, zf, zb, y0, o)
    o.run = 0
    local roof = HipRoof(name, x0, x1, zf, zb, y0, o)
    local hipEmit = roof.emit
    roof.gable, roof.front, roof.pieces = o.gable, o.front, o.pieces
    roof.emit = function(self, mesh)
      local tmp = K.mesh()
      hipEmit(self, tmp)
      local function dropped(tag)
        if tag:sub(-6) == ".hip_w" or tag:sub(-6) == ".hip_e" then return true end
        if self.front and tag:sub(-9) == ".fascia_s" then return true end
        if self.pieces and (tag:sub(-8) == ".slope_s" or tag:sub(-8) == ".slope_n") then return true end
        return false
      end
      for _, t in ipairs(tmp.tris) do
        if not dropped(t.tag) then mesh:tri(t[1], t[2], t[3], t.shade, t.tag) end
      end
      local ye, zr, zq, yr = self.ye, self.z_rf, self.z_rb, self.yr
      local X0, X1, ZF, ZB, Y0 = self.x0, self.x1, self.zf, self.zb, self.y0
      if self.front then
        K.stripFace(mesh, { { X0, Y0, ZF }, { X1, Y0, ZF }, { X1, ye, ZF }, { X0, ye, ZF } },
          { 0, Y0, ZF }, { 1, 0, 0 }, { 0, 1, 0 }, self.front, K.SHADE_ART, self.name .. ".fascia_s")
      end
      for _, pc in ipairs(self.pieces or {}) do
        local xa, xb, sl = pc[1], pc[2], pc[3]
        local tS = K.unit({ 0, self.rise, -(ZF - zr) })
        local tN = K.unit({ 0, self.rise, ZF - zr })
        K.stripFace(mesh, { { xa, ye, ZF }, { xb, ye, ZF }, { xb, yr, zr }, { xa, yr, zr } },
          { 0, ye, ZF }, { 1, 0, 0 }, tS, sl, K.SHADE_ART, self.name .. ".slope_s")
        K.stripFace(mesh, { { xb, ye, ZB }, { xa, ye, ZB }, { xa, yr, zq }, { xb, yr, zq } },
          { 0, ye, ZB }, { 1, 0, 0 }, tN, sl, K.SHADE_BACK, self.name .. ".slope_n")
      end
      for _, t in ipairs(tmp.tris) do
        if t.tag:sub(-6) == ".teeth" then
          local b = {}
          for k = 1, 3 do b[k] = { t[k][1], t[k][2], zq, t[k][4], t[k][5] } end
          mesh:tri(b[1], b[2], b[3], K.SHADE_BACK, self.name .. ".teeth_n")
        end
      end
      local sec = { { ZB, ye }, { ZF, ye }, { zr, yr }, { zq, yr } }
      for _, e in ipairs({ { X0, K.SHADE_WEST }, { X1, K.SHADE_EAST } }) do
        for k = 2, #sec - 1 do
          local tri = { sec[1], sec[k], sec[k + 1] }
          local flat = {}
          for j, p in ipairs(tri) do flat[j] = { ZF - p[1], yr - p[2] } end
          for _, piece in ipairs(K.tilePieces(flat, self.gable)) do
            local pts = {}
            for j, q in ipairs(piece) do pts[j] = { e[1], yr - q[2], ZF - q[1], q[3], q[4] } end
            mesh:poly(pts, e[2], self.name .. ".gable")
          end
        end
      end
    end
    return roof
  end

  local TRICK_LOW_PITCH = 15.0
  local function trick_house()
    local front_z, back_z, overhang, inset = 96, 16, 2, 16
    local stone = Tile(3, 72, 8, 96)
    local upper_stone = Tile(32, 56, 40, 63)
    local zf_lo, zb_lo = front_z + overhang, back_z - overhang
    local slope_lo = Strip({ 30, 64 }, { rep = { 32, 40 } })
    local flutes = Strip({ 30, 64 }, { rep = { 32, 40 }, wrap = { 2, 10 } })
    local roof_lo = GableRoof("roof_lo", 0, 80, zf_lo, zb_lo, zf_lo - 72, {
      fascia = Strip({ 64, 72 }, { wrap = { 2, 10 } }), front = Strip({ 64, 72 }), slope = slope_lo,
      pieces = { { 0, 16, slope_lo }, { 16, 64, flutes }, { 64, 80, slope_lo } },
      teeth = { 24, 30 }, cap = { 16, 24 }, pitch = TRICK_LOW_PITCH, ridge_u = { 0, 16 },
      end_tile = Tile(2, 24, 10, 30), ridgeWrap = { 2, 10 }, gable = stone })
    local z_front, z_back = zf_lo - inset, zb_lo + inset
    local y_base = roof_lo.ye + inset * tan(rad(TRICK_LOW_PITCH))
    local y_top = y_base + 13
    local roof_hi = GableRoof("roof_hi", 16, 64, z_front + overhang, z_back - overhang, y_top, {
      fascia = Strip({ 48, 53 }, { wrap = { 18, 58 } }), front = Strip({ 48, 53 }),
      slope = Strip({ 14, 48 }, { rep = { 16, 24 } }),
      teeth = { 8, 14 }, cap = { 0, 8 }, pitch = PITCH, ridge_u = { 16, 64 },
      end_tile = Tile(18, 8, 26, 14), ridgeWrap = { 18, 58 }, gable = upper_stone })
    local us = upper_stone.rect
    local wall_hi = Tile(us[1], us[2], us[3], us[4], { top = y_top })
    local storey = Prism("storey", 18, 62,
      { { z_front, y_base }, { z_front, y_top }, { z_back, y_top }, { z_back, y_base } },
      { edges = { [0] = Tile(18, 53, 62, 64, { s0 = 18 }), [2] = wall_hi }, skip = { 1, 3 },
        caps = { Band(-64, 200, wall_hi, z_front, { front = wall_hi, back = wall_hi, z1 = z_back }) } })
    local wall_top = roof_lo.y0
    local sr = stone.rect
    local wall = Tile(sr[1], sr[2], sr[3], sr[4], { top = wall_top })
    local base = Prism("ground_floor", 2, 79.9,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(70, 96), [2] = wall }, skip = { 1, 3 },
        caps = { Band(0, wall_top, wall, front_z, { front = wall, back = wall, z1 = back_z }) } })
    return { base, roof_lo, storey, roof_hi }
  end

  local function two_storey_house(width, front_z, lo, hi, upper_x, storey, pent, facade, side, band)
    local back_z, overhang = 16, 2
    local roof_lo = HipRoof("roof_lo", 0, width, front_z + overhang, back_z - overhang,
      front_z + overhang - lo.fascia[2], {
        fascia = Strip(lo.fascia, { wrap = lo.fascia_wrap }),
        slope = Strip(lo.slope, { rep = lo.course, wrap = lo.wrap }),
        teeth = lo.teeth, cap = lo.cap, pitch = PITCH, run = 8,
        ridge_u = { 0, 16 }, end_tile = Tile(lo.wrap[1], lo.teeth[1], lo.wrap[1] + 8, lo.teeth[2]),
        ridgeWrap = lo.ridge_wrap })
    local z_wall, y_base = K.slopePoint(roof_lo, pent)
    local zf_hi = z_wall + overhang
    local y0_hi = zf_hi - hi.fascia[2]
    local zb_hi = (roof_lo.zf + roof_lo.zb) - zf_hi
    local roof_hi = HipRoof("roof_hi", upper_x[1], upper_x[2], zf_hi, zb_hi, y0_hi, {
      fascia = Strip(hi.fascia, { wrap = hi.fascia_wrap }),
      slope = Strip(hi.slope, { rep = hi.course, wrap = hi.wrap }),
      teeth = hi.teeth, cap = hi.cap, pitch = PITCH, run = 6,
      ridge_u = upper_x, end_tile = Tile(hi.wrap[1], hi.teeth[1], hi.wrap[1] + 8, hi.teeth[2]),
      ridgeWrap = hi.ridge_wrap })
    local storey_back = zb_hi + overhang
    local wall_hi = Tile(band[1], storey[1], band[2], storey[2], { top = y0_hi })
    local upper_storey = Prism("storey", upper_x[1] + 1, upper_x[2] - 1,
      { { z_wall, y_base }, { z_wall, y0_hi }, { storey_back, y0_hi }, { storey_back, y_base } },
      { edges = { [0] = Proj(storey[1], storey[2]), [2] = wall_hi }, skip = { 1, 3 },
        caps = { Band(-64, 200, wall_hi, z_wall, { front = wall_hi, back = wall_hi, z1 = storey_back }) } })
    local wall_top = roof_lo.y0
    local wall = Tile(side[1], facade[1], side[2], facade[2], { top = wall_top - 2 })
    local base = Prism("ground_floor", 2, width - 2,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(facade[1], facade[2]), [2] = wall }, skip = { 1, 3 },
        caps = { Band(0, wall_top - 2, wall, front_z, { front = wall, back = wall, z1 = back_z }),
                 Band(wall_top - 2, wall_top + 1, Tile(side[1], facade[1], side[2], facade[1] + 1, { top = wall_top }), front_z) } })
    return { base, roof_lo, upper_storey, roof_hi }
  end

  local function lilycove_motel()
    return two_storey_house(96, 80,
      { cap = { 16, 25 }, teeth = { 25, 31 }, slope = { 31, 50 }, course = { 32, 40 }, fascia = { 50, 56 },
        wrap = { 18, 58 }, fascia_wrap = { 18, 58 }, ridge_wrap = { 2, 10 } },
      { cap = { 0, 9 }, teeth = { 9, 16 }, slope = { 16, 35 }, course = { 16, 24 }, fascia = { 35, 40 },
        wrap = { 18, 58 }, fascia_wrap = { 18, 58 }, ridge_wrap = { 22, 62 } },
      { 17, 80 }, { 40, 46 }, 4, { 56, 80 }, { 3, 6 }, { 30, 38 })
  end

  local function pink_house(width, x0)
    x0 = x0 or 1
    local front_z, back_z = 64, 16
    local overhang = 2
    local roof = HipRoof("roof", 0, width, front_z + overhang, back_z - overhang, 28, {
      fascia = Strip({ 32, 38 }, { wrap = { 10, 18 } }),
      slope = Strip({ 14, 32 }, { rep = { 16, 24 }, wrap = { 2, 10 } }),
      teeth = { 8, 14 }, cap = { 0, 8 }, pitch = 22.0, run = 6,
      ridge_u = { 0, width }, end_tile = Tile(10, 8, 18, 14), ridgeWrap = { 9, 17 } })
    local wall_top = 28
    local post = Tile(x0 + 1, 38, x0 + 6, 64, { top = 26 })
    local base = Prism("ground_floor", x0, width - 1,
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(38, 64), [2] = post }, skip = { 1, 3 },
        caps = { Band(0, 26, post, front_z, { front = post, back = post, z1 = back_z }),
                 Band(26, wall_top + 1, Tile(x0 + 1, 38, x0 + 6, 39, { top = wall_top }), front_z) } })
    return { base, roof }
  end

  local function pitched_house(width, cap, teeth, slope, course, fascia, foot, wrap, ridge_wrap, wall, o)
    o = o or {}
    local inset, overhang, back_z, x0, run = o.inset or 2, o.overhang or 2, o.back_z or 16, o.x0 or 0, o.run or 6
    local front_z = foot
    local y0 = front_z + overhang - fascia[2]
    local roof = HipRoof("roof", x0, x0 + width, front_z + overhang, back_z - overhang, y0, {
      fascia = Strip(fascia, { wrap = wrap }),
      slope = Strip(slope, { rep = course, wrap = wrap }),
      teeth = teeth, cap = cap, pitch = 22.0, run = run,
      ridge_u = { x0, x0 + width }, end_tile = Tile(wrap[1], teeth[1], wrap[1] + 8, teeth[2]),
      ridgeWrap = ridge_wrap })
    local wall_top = y0
    local boards = Tile(wall[1], fascia[2], wall[2], foot, { top = wall_top - 4 })
    local base = Prism("ground_floor", x0 + inset, x0 + (inset == 2 and (width - inset + 1) or (width - inset)),
      { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
      { edges = { [0] = Proj(fascia[2], foot), [2] = boards }, skip = { 1, 3 },
        caps = { Band(0, wall_top - 4, boards, front_z, { front = boards, back = boards, z1 = back_z }),
                 Band(wall_top - 4, wall_top + 1, Tile(wall[1], fascia[2], wall[2], fascia[2] + 1, { top = wall_top }), front_z) } })
    return { base, roof }
  end

  local function verdanturf_house(width)
    return pitched_house(width, { 0, 7 }, { 7, 14 }, { 14, 37 }, { 19, 27 }, { 37, 40 }, 62, { 10, 18 }, { 9, 17 }, { 3, 7 })
  end
  local function mossdeep_house_parts(width)
    return pitched_house(width, { 0, 5 }, { 5, 8 }, { 8, 33 }, { 19, 33 }, { 33, 37 }, 62, { 12, 28 }, { 12, 28 }, { 2, 8 })
  end
  local function lilycove_house(width)
    return pitched_house(width, { 0, 8 }, { 8, 12 }, { 12, 35 }, { 14, 22 }, { 35, 40 }, 63, { 14, 22 }, { 10, 18 }, { 5, 8 })
  end
  local function fallarbor_house(width)
    return pitched_house(width, { 0, 9 }, { 9, 13 }, { 13, 35 }, { 19, 27 }, { 35, 39 }, 62, { 10, 18 }, { 9, 17 }, { 3, 7 })
  end

  -- ── the second reading: awnings, stalls, mansard roofs, posts, porches ──

  local clip, projPoly, stripFace, unit = K.clip, K.projPoly, K.stripFace, K.unit
  local SHADE_ART, SHADE_BACK, SHADE_WEST, SHADE_EAST = K.SHADE_ART, K.SHADE_BACK, K.SHADE_WEST, K.SHADE_EAST
  local function sgn(a) return a > 0 and 1 or a < 0 and -1 or 0 end
  local function projv(pts)
    local o = {}
    for k, p in ipairs(pts) do o[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
    return o
  end
  local function reversed(t)
    local o = {}
    for k = #t, 1, -1 do o[#o + 1] = t[k] end
    return o
  end

  -- a cloth roof on posts that people walk under (Awning): lifted along the line of sight
  local function awningRoof(self, mesh, zf, yt, zb)
    local top = Strip({ self.top_v + 2, self.valance_v }, { rep = self.rep, tail = { self.top_v, self.top_v + 2 } })
    local x0, x1 = self.x0, self.x1
    stripFace(mesh, { { x0, yt, zf }, { x1, yt, zf }, { x1, yt, zb }, { x0, yt, zb } },
      { 0, yt, zf }, { 1, 0, 0 }, { 0, 0, -1 }, top, SHADE_ART, self.name .. ".top")
  end
  local function awningEmit(self, mesh)
    local n, x0, x1, l = self.name, self.x0, self.x1, self.lift
    local zf = self.foot_v + l
    local yt = zf - self.valance_v
    local yb = zf - self.post_v
    local zb = self.back
    local up = { 0, 1, 0 }
    self:roof(mesh, zf, yt, zb)
    local val = Strip({ self.valance_v, self.post_v })
    local flank = Strip({ self.valance_v, self.post_v }, { offset = x0 + 1 - zb })
    local sides = {
      { { { x0, yb, zf }, { x1, yb, zf }, { x1, yt, zf }, { x0, yt, zf } }, { 0, yb, zf }, { 1, 0, 0 }, SHADE_ART, val },
      { { { x1, yb, zb }, { x0, yb, zb }, { x0, yt, zb }, { x1, yt, zb } }, { 0, yb, zb }, { 1, 0, 0 }, SHADE_BACK, val },
      { { { x0, yb, zb }, { x0, yb, zf }, { x0, yt, zf }, { x0, yt, zb } }, { x0, yb, 0 }, { 0, 0, 1 }, SHADE_WEST, flank },
      { { { x1, yb, zf }, { x1, yb, zb }, { x1, yt, zb }, { x1, yt, zf } }, { x1, yb, 0 }, { 0, 0, 1 }, SHADE_EAST, flank },
    }
    local cx, cz = (x0 + x1) / 2, (zf + zb) / 2
    for _, sd in ipairs(sides) do
      local quad, origin, sdir, shade, v = sd[1], sd[2], sd[3], sd[4], sd[5]
      stripFace(mesh, quad, origin, sdir, up, v, shade, n .. ".valance")
      local inner = {}
      for _, p in ipairs(reversed(quad)) do
        local x, y, z = p[1], p[2], p[3]
        inner[#inner + 1] = { x + 0.25 * sgn(cx - x) * (sdir[3] ~= 0 and 1 or 0), y,
                              z + 0.25 * sgn(cz - z) * (sdir[1] ~= 0 and 1 or 0) }
      end
      local o = inner[#inner]
      stripFace(mesh, inner, { sdir[1] ~= 0 and origin[1] or o[1], origin[2], sdir[3] ~= 0 and origin[3] or o[3] },
        sdir, up, v, SHADE_BACK, n .. ".valance_in")
    end
    for _, ps in ipairs(self.posts) do
      local pa, pb = ps[1], ps[2]
      for _, z in ipairs({ zf, zb + (pb - pa) }) do
        stripFace(mesh, { { pa, 0, z }, { pb, 0, z }, { pb, yb, z }, { pa, yb, z } },
          { 0, 0, z }, { 1, 0, 0 }, up, Strip(self.foot, { rep = self.shaft }), SHADE_ART, n .. ".post")
      end
    end
  end
  local function Awning(name, x0, x1, o)
    return { name = name, x0 = x0, x1 = x1, top_v = o.top_v, valance_v = o.valance_v, post_v = o.post_v,
             foot_v = o.foot_v, back = o.back, lift = o.lift, rep = o.rep, posts = o.posts, shaft = o.shaft,
             foot = o.foot, roof = awningRoof, emit = awningEmit }
  end

  -- a market stall: an awning whose roof is hipped (Tent)
  local function tentRoof(self, mesh, zf, ye, zb)
    local n, x0, x1 = self.name, self.x0, self.x1
    local xa, xb, r0, r1 = self.ridge[1], self.ridge[2], self.ridge[3], self.ridge[4]
    local rows = self.valance_v - r1
    local t = tan(rad(self.pitch))
    local run = rows / (1 + t)
    local zr, yr = zf - run, ye + run * t
    local zq = zr - (r1 - r0)
    local function proj(pts, lo, hi)
      local o = {}
      for k, p in ipairs(pts) do o[k] = { p[1], p[2], p[3], p[1], math.min(math.max(p[3] - p[2], lo), hi) } end
      return o
    end
    local function fill(pts, rect)
      local o = {}
      for k, p in ipairs(pts) do
        o[k] = { p[1], p[2], p[3], math.min(math.max(p[1], rect[1]), rect[3]), math.min(math.max(p[3] - p[2], rect[2]), rect[4]) }
      end
      return o
    end
    mesh:poly(proj({ { x0, ye, zf }, { x1, ye, zf }, { xb, yr, zr }, { xa, yr, zr } }, r1, self.valance_v), SHADE_ART, n .. ".slope_s")
    mesh:poly(proj({ { xa, yr, zr }, { xb, yr, zr }, { xb, yr, zq }, { xa, yr, zq } }, r0, r1), SHADE_ART, n .. ".ridge")
    local back, west, east = self.fills[1], self.fills[2], self.fills[3]
    mesh:poly(fill({ { xa, yr, zq }, { xb, yr, zq }, { x1, ye, zb }, { x0, ye, zb } }, back), SHADE_ART, n .. ".slope_n")
    for _, hr in ipairs({ { { { x0, ye, zb }, { x0, ye, zf }, { xa, yr, zr }, { xa, yr, zq } }, west },
                          { { { x1, ye, zf }, { x1, ye, zb }, { xb, yr, zq }, { xb, yr, zr } }, east } }) do
      local pts = projv(hr[1])
      local nearP = clip(pts, 5, r1, true)
      local farP = clip(pts, 5, r1, false)
      if #nearP >= 3 then
        local o = {}
        for k, q in ipairs(nearP) do o[k] = { q[1], q[2], q[3], q[4], math.min(q[5], self.valance_v) } end
        mesh:poly(o, SHADE_ART, n .. ".hip")
      end
      if #farP >= 3 then
        local p3 = {}
        for k, q in ipairs(farP) do p3[k] = { q[1], q[2], q[3] } end
        mesh:poly(fill(p3, hr[2]), SHADE_ART, n .. ".hip")
      end
    end
  end
  local function Tent(name, x0, x1, o)
    local t = Awning(name, x0, x1, o)
    t.ridge, t.pitch, t.fills, t.roof = o.ridge, o.pitch, o.fills, tentRoof
    return t
  end

  -- a face projected between `rows`; beyond them its edge row held
  local function projRows(mesh, pts, rows, tag, shade)
    shade = shade or SHADE_ART
    local lo, hi = rows[1], rows[2]
    local poly = projv(pts)
    for _, ph in ipairs({ { clip(poly, 5, lo, false), lo }, { clip(poly, 5, hi, true), hi } }) do
      if #ph[1] >= 3 then
        local o = {}
        for k, q in ipairs(ph[1]) do o[k] = { q[1], q[2], q[3], q[4], ph[2] } end
        mesh:poly(o, shade, tag)
      end
    end
    local mid = clip(clip(poly, 5, lo, true), 5, hi, false)
    if #mid >= 3 then mesh:poly(mid, shade, tag) end
  end

  -- a hipped roof with a flat deck
  local function Mansard(name, x0, x1, zf, zb, ye, o)
    return { name = name, emit = function(_, mesh)
      local xa, xb = x0 + o.side, x1 - o.side
      local za, zq, yt = zf - o.run, zb + o.run, ye + o.rise
      projRows(mesh, { { x0, ye, zf }, { x1, ye, zf }, { xb, yt, za }, { xa, yt, za } }, o.front_rows, name .. ".slope_s")
      projRows(mesh, { { x0, ye, zb }, { x0, ye, zf }, { xa, yt, za }, { xa, yt, zq } }, o.hip_rows, name .. ".hip_w")
      projRows(mesh, { { x1, ye, zf }, { x1, ye, zb }, { xb, yt, zq }, { xb, yt, za } }, o.hip_rows, name .. ".hip_e")
      stripFace(mesh, { { x1, ye, zb }, { x0, ye, zb }, { xa, yt, zq }, { xb, yt, zq } },
        { 0, ye, zb }, { 1, 0, 0 }, unit({ 0, o.rise, o.run }), o.back, SHADE_BACK, name .. ".slope_n")
      stripFace(mesh, { { xa, yt, za }, { xb, yt, za }, { xb, yt, zq }, { xa, yt, zq } },
        { 0, yt, za }, { 1, 0, 0 }, { 0, 0, -1 }, o.deck, SHADE_ART, name .. ".deck")
    end }
  end

  -- square posts standing in front of a wall
  local function Posts(name, posts, z0, z1, y1, last)
    return { name = name, emit = function(_, mesh)
      local top = z1 - y1
      local out = mesh
      if last then
        local l = last - 0.5
        out = { poly = function(_, pts, shade, tag)
          local o = {}
          for k, p in ipairs(pts) do o[k] = { p[1], p[2], p[3], p[4], math.min(p[5], l) } end
          mesh:poly(o, shade, tag)
        end }
      end
      for _, ab in ipairs(posts) do
        local a, b = ab[1], ab[2]
        out:poly({ { a, -1, z1, a, z1 + 1 }, { b, -1, z1, b, z1 + 1 }, { b, y1, z1, b, top }, { a, y1, z1, a, top } }, SHADE_ART, name)
        out:poly({ { b, -1, z0, b, z1 + 1 }, { a, -1, z0, a, z1 + 1 }, { a, y1, z0, a, top }, { b, y1, z0, b, top } }, SHADE_BACK, name)
        out:poly({ { a, -1, z0, b, z1 + 1 }, { a, -1, z1, a, z1 + 1 }, { a, y1, z1, a, top }, { a, y1, z0, b, top } }, SHADE_WEST, name)
        out:poly({ { b, -1, z1, b, z1 + 1 }, { b, -1, z0, a, z1 + 1 }, { b, y1, z0, a, top }, { b, y1, z1, b, top } }, SHADE_EAST, name)
        out:poly({ { a, y1, z1, a, top }, { b, y1, z1, b, top }, { b, y1, z0, b, top + 1 }, { a, y1, z0, a, top + 1 } }, SHADE_ART, name)
      end
    end }
  end

  -- a porch roof over a door, on two posts
  local function Canopy(name, x0, x1, zw, zf, y0, y1, o)
    return { name = name, emit = function(_, mesh)
      local cx, cz = o.chamfer[1], o.chamfer[2]
      local iu, iv = o.inside[1], o.inside[2]
      mesh:poly(projv(reversed({ { x0 + cx, y1, zw }, { x1 - cx, y1, zw }, { x1, y1, zw + cz }, { x1, y1, zf },
        { x0, y1, zf }, { x0, y1, zw + cz } })), SHADE_ART, name .. ".top")
      local edge = { { x0, y0 } }
      for _, p in ipairs(o.arch) do edge[#edge + 1] = p end
      edge[#edge + 1] = { x1, y0 }
      for k = 1, #edge - 1 do
        local xa, ya, xb, yb = edge[k][1], edge[k][2], edge[k + 1][1], edge[k + 1][2]
        if xb - xa > 1e-6 then
          mesh:poly(projv({ { xa, ya, zf }, { xb, yb, zf }, { xb, y1, zf }, { xa, y1, zf } }), SHADE_ART, name .. ".front")
        end
        mesh:poly({ { xa, ya, zw, iu, iv }, { xb, yb, zw, iu, iv }, { xb, yb, zf, iu, iv }, { xa, ya, zf, iu, iv } }, SHADE_BACK, name .. ".under")
      end
      local zc = zw + cz
      for _, e in ipairs({ { x0, x0 + cx, 1, SHADE_WEST }, { x1, x1 - cx, -1, SHADE_EAST } }) do
        local x, xc, inward, shade = e[1], e[2], e[3], e[4]
        local q = {}
        for k, p in ipairs({ { x, y0, zf }, { x, y0, zc }, { x, y1, zc }, { x, y1, zf } }) do
          q[k] = { p[1], p[2], p[3], x + inward * (zf - p[3]) * 0.5, zf - p[2] }
        end
        mesh:poly(q, shade, name .. ".end")
        mesh:poly(projv({ { x, y0, zc }, { xc, y0, zw }, { xc, y1, zw }, { x, y1, zc } }), shade, name .. ".end")
      end
      local pa, pb, qa, qb = o.posts[1][1], o.posts[1][2], o.posts[2][1], o.posts[2][2]
      local wa, wb = o.skin[1], o.skin[2]
      for _, s in ipairs({ { pa, pb, wa }, { qa, qb, wb } }) do
        local q = {}
        for k, p in ipairs({ { s[1], -1 }, { s[2], -1 }, { s[2], y0 }, { s[1], y0 } }) do
          q[k] = { p[1], p[2], zw + 0.25, s[3], zw - math.max(p[2], 0) }
        end
        mesh:poly(q, SHADE_ART, name .. ".skin")
      end
      local sill = zw + 0.25 - o.sill
      for k = 1, #o.arch - 1 do
        local xa, ya, xb, yb = o.arch[k][1], o.arch[k][2], o.arch[k + 1][1], o.arch[k + 1][2]
        if xb - xa > 1e-6 then
          mesh:poly({ { xa, sill, zw + 0.25, iu, iv }, { xb, sill, zw + 0.25, iu, iv },
            { xb, yb, zw + 0.25, iu, iv }, { xa, ya, zw + 0.25, iu, iv } }, SHADE_ART, name .. ".door")
        end
      end
      local last = o.last - 0.5
      for _, ab in ipairs(o.posts) do
        local q = {}
        for k, p in ipairs({ { ab[1], -1 }, { ab[2], -1 }, { ab[2], y0 }, { ab[1], y0 } }) do
          q[k] = { p[1], p[2], zf, p[1], math.min(zf - p[2], last) }
        end
        mesh:poly(q, SHADE_ART, name .. ".post")
      end
    end }
  end

  -- a flat roof slab on columns
  local function FlatSlab(name, x0, x1, zf, zb, y0, y1, o)
    return { name = name, emit = function(_, mesh)
      local a, b = o.front[1], o.front[2]
      local za = zf - (b - a)
      local zt = zb + (o.tail[2] - o.tail[1])
      local function lay(xa, xb, z0, z1, strip, tag)
        stripFace(mesh, { { xa, y1, z0 }, { xb, y1, z0 }, { xb, y1, z1 }, { xa, y1, z1 } },
          { 0, y1, z0 }, { 1, 0, 0 }, { 0, 0, -1 }, strip, SHADE_ART, name .. tag)
      end
      lay(x0, x1, zf, za, Strip(o.front), ".top")
      local rows, wrap = o.fill[1], o.fill[2]
      local r = o.rim
      lay(x0, x0 + r, za, zt, Strip(rows, { rep = rows }), ".top")
      lay(x0 + r, x1 - r, za, zt, Strip(rows, { rep = rows, wrap = wrap }), ".top")
      lay(x1 - r, x1, za, zt, Strip(rows, { rep = rows }), ".top")
      lay(x0, x1, zt, zb, Strip(o.tail), ".top")
      mesh:poly(projv({ { x0, y0, zf }, { x1, y0, zf }, { x1, y1, zf }, { x0, y1, zf } }), SHADE_ART, name .. ".front")
      for _, ab in ipairs({ { { x0, zf }, { x0, zb } }, { { x1, zb }, { x1, zf } }, { { x0, zb }, { x1, zb } } }) do
        K.PlainWall(name .. ".edge", ab[1], ab[2], y0, y1, o.edge):emit(mesh)
      end
    end }
  end

  -- a flat polygon at height h, projected, and its sides
  local function ReliefTop(poly, h)
    return { name = "fountain", emit = function(_, mesh)
      local top = {}
      for k = #poly, 1, -1 do top[#top + 1] = { poly[k][1], h, poly[k][2], poly[k][1], poly[k][2] - h } end
      mesh:poly(top, 1.0, "fountain.top")
      local n = #poly
      for i = 2, n - 2 do
        local A, B = poly[i + 1], poly[(i + 1) % n + 1]
        mesh:poly(projv({ { A[1], -1, A[2] }, { B[1], -1, B[2] }, { B[1], h, B[2] }, { A[1], h, A[2] } }), 0.7, "fountain.side")
      end
    end }
  end

  -- a smooth dome over an ellipse, its drawing projected (a bush)
  local function ProjDome(name, cx, cz, rx, rz, h, o)
    o = o or {}
    local y0, seg, rings = o.y0 or 0, o.seg or 12, o.rings or 3
    return { name = name, emit = function(_, mesh)
      local function pt(k, i)
        local phi = (math.pi / 2) * k / rings
        local a = 2 * math.pi * i / seg
        local r = math.cos(phi)
        local x = cx + rx * r * math.cos(a)
        local z = cz + rz * r * math.sin(a)
        local y = y0 + h * math.sin(phi)
        return { x, y, z, x, z - y }
      end
      for k = 0, rings - 1 do
        for i = 0, seg - 1 do
          local a, b, c, d = pt(k, i), pt(k, i + 1), pt(k + 1, i + 1), pt(k + 1, i)
          if k == rings - 1 then mesh:tri(a, b, c, 1.0, name) else mesh:poly({ a, b, c, d }, 1.0, name) end
        end
      end
    end }
  end

  -- a smooth surface of revolution on an elliptical plan, its drawing projected (a bollard)
  local function ProjLathe(name, cx, cz, profile, o)
    o = o or {}
    local squash, seg, offset = o.squash or 1, o.seg or 12, o.offset or 0
    return { name = name, emit = function(_, mesh)
      local grow = 1 / math.cos(math.pi / seg)
      local function ring(y, r)
        r = r * grow
        local out = {}
        for i = 0, seg - 1 do
          local a = 2 * math.pi * i / seg
          local x = cx + r * math.cos(a)
          local z = cz + r * squash * math.sin(a)
          out[i + 1] = { x, y, z, x, z - y + offset }
        end
        return out
      end
      local rings = {}
      for j, p in ipairs(profile) do rings[j] = ring(p[1], p[2]) end
      for j = 1, #rings - 1 do
        local lo, hi = rings[j], rings[j + 1]
        for i = 1, seg do
          local i2 = i % seg + 1
          local quad = { lo[i], lo[i2], hi[i2], hi[i] }
          if profile[j + 1][2] < 1e-6 then mesh:tri(quad[1], quad[2], quad[3], 1.0, name)
          elseif profile[j][2] < 1e-6 then mesh:tri(quad[1], quad[3], quad[4], 1.0, name)
          else mesh:poly(quad, 1.0, name) end
        end
      end
      if profile[#profile][2] > 1e-6 then mesh:poly(rings[#rings], 1.0, name) end
    end }
  end

  local function fan_club()
    local zf, zb, ye = 80, 16, 26
    local roof = Mansard("roof", 0, 80, zf, zb, ye, { side = 14, run = 7, rise = 7,
      front_rows = { 40, 54 }, hip_rows = { 16, 54 },
      deck = Strip({ 12, 40 }, { rep = { 12, 16 }, tail = { 8, 12 } }),
      back = Strip({ 12, 16 }, { rep = { 12, 16 } }) })
    local walls = Walls("facade", { { 0, 73 }, { 7, 80 }, { 73, 80 }, { 80, 73 } }, -1, ye)
    local pilaster = Tile(8, 55, 16, 79)
    local arch = { { 33, 14 }, { 33, 15 }, { 35, 15 }, { 35, 16 }, { 37, 16 }, { 37, 17 }, { 39, 17 }, { 39, 18 },
      { 41, 18 }, { 41, 17 }, { 43, 17 }, { 43, 16 }, { 45, 16 }, { 45, 15 }, { 47, 15 }, { 47, 14 } }
    local porch = Canopy("porch", 28, 52, 80, 87, 14, 24, { arch = arch, chamfer = { 3, 2 },
      posts = { { 29, 33 }, { 47, 51 } }, inside = { 40.5, 74.5 }, last = 87, skin = { 27.5, 53.5 }, sill = 77 })
    return { roof, walls, porch,
      K.PlainWall("side_w", { 0, 73 }, { 0, zb }, -1, ye, pilaster),
      K.PlainWall("side_e", { 80, zb }, { 80, 73 }, -1, ye, pilaster),
      K.PlainWall("back", { 0, zb }, { 80, zb }, -1, ye, pilaster) }
  end

  local function museum()
    local zf, zb, ye = 96, 32, 38
    local roof = Mansard("roof", 0, 112, zf, zb, ye, { side = 8, run = 5, rise = 5,
      front_rows = { 48, 58 }, hip_rows = { 4, 58 },
      deck = Strip({ 4, 48 }, { rep = { 20, 28 }, tail = { 2, 4 } }),
      back = Strip({ 20, 28 }, { rep = { 20, 28 } }) })
    local walls = Walls("facade", { { 0, zf }, { 112, zf } }, -1, ye)
    local side = Tile(8, 62, 24, 96)
    return { roof, walls,
      K.PlainWall("side_w", { 0, zf }, { 0, zb }, -1, ye, side),
      K.PlainWall("side_e", { 112, zb }, { 112, zf }, -1, ye, side),
      K.PlainWall("back", { 0, zb }, { 112, zb }, -1, ye, side) }
  end

  local function contest_hall()
    local zf, zb = 88, 16
    local roof = FlatSlab("roof", 0, 96, zf, zb, 32, 40, { front = { 16, 48 }, fill = { { 24, 32 }, { 8, 40 } },
      rim = 8, tail = { 8, 16 }, edge = Tile(40, 48, 56, 56) })
    local walls = Walls("facade", { { 0, 73 }, { 7, 80 }, { 89, 80 }, { 96, 73 } }, -1, 32)
    local side = Tile(16, 56, 24, 80)
    local columns = Posts("columns", { { 8, 16 }, { 24, 32 }, { 64, 72 }, { 80, 88 } }, 80, zf, 32)
    local steps = ReliefTop({ { 32, 80 }, { 64, 80 }, { 64, 88 }, { 32, 88 } }, 0.5)
    return { roof, walls, columns, steps,
      K.PlainWall("side_w", { 0, 73 }, { 0, zb }, -1, 32, side),
      K.PlainWall("side_e", { 96, zb }, { 96, 73 }, -1, 32, side),
      K.PlainWall("back", { 0, zb }, { 96, zb }, -1, 32, side) }
  end

  local SHIPYARD_BACK_PITCH = 20.0
  local function shipyard()
    local front, back, wall = 112, 16, 40
    local ye = 48
    local run = 48 / (1 + tan(rad(20.0)))
    local zr, yr = front - run, ye + run * tan(rad(20.0))
    local yb = yr - (zr - back) * tan(rad(SHIPYARD_BACK_PITCH))
    local post = Tile(0, 72, 5, 112, { top = wall })
    local boards = Tile(8, 72, 30, 112, { top = wall })
    local gable = Tile(8, 72, 30, 112)
    local body = Prism("ground_floor", 0, 128,
      { { back, 0 }, { front, 0 }, { front, ye }, { zr, yr }, { back, yb } },
      { edges = { [1] = Proj(), [4] = boards }, skip = { 0, 2, 3 },
        caps = { Band(0, wall, boards, front, { front = post, back = post, z1 = back }),
                 Band(wall, yr + 1, gable, front, { z1 = back }) } })
    local roof = { name = "roof", emit = function(_, mesh)
      local x0, x1 = 0, 128
      mesh:poly(projv({ { x0, ye, front }, { x1, ye, front }, { x1, yr, zr }, { x0, yr, zr } }), SHADE_ART, "roof.slope_s")
      local bk = projv({ { x0, yr, zr }, { x1, yr, zr }, { x1, yb, back }, { x0, yb, back } })
      local slats, finish = 4.0, back - yb
      local nearP = clip(bk, 5, slats, true)
      local rest = clip(bk, 5, slats, false)
      local mid = #rest >= 3 and clip(rest, 5, finish + 3, true) or {}
      local edge = #rest >= 3 and clip(rest, 5, finish + 3, false) or {}
      if #nearP >= 3 then mesh:poly(nearP, SHADE_ART, "roof.slope_n") end
      if #mid >= 3 then
        local o = {}
        for k, q in ipairs(mid) do o[k] = { q[1], q[2], q[3], q[4], slats + 1.5 } end
        mesh:poly(o, SHADE_ART, "roof.slope_n")
      end
      if #edge >= 3 then
        local o = {}
        for k, q in ipairs(edge) do o[k] = { q[1], q[2], q[3], q[4], q[5] - finish + 1 } end
        mesh:poly(o, SHADE_ART, "roof.slope_n")
      end
    end }
    return { body, roof }
  end

  local function stall(x1, ridge_e, fills)
    return Tent("stall", 8, x1, { top_v = 1, valance_v = 25, post_v = 29, foot_v = 47, back = 12, lift = 12,
      posts = { { 8, 14 }, { x1 - 6, x1 } }, shaft = { 34, 44 }, foot = { 44, 47 },
      ridge = { 22.5, ridge_e, 9, 11 }, pitch = 30.0, fills = fills })
  end
  local function stall_keep(x1)
    return { { 8, 1, x1, 29 }, { 8, 29, 14, 47 }, { x1 - 6, 29, x1, 47 } }
  end

  local BOLLARD = { { 0, 6.5 }, { 2, 6 }, { 5, 6 }, { 6, 5.5 }, { 7, 7 }, { 8.5, 7 }, { 9, 4 }, { 11, 0 } }

  local function cells(list)
    local o = {}
    for _, c in ipairs(list) do o[c[1] .. "," .. c[2]] = true end
    return o
  end
  local southeastOwned = {}
  for j = 0, 4 do southeastOwned[#southeastOwned + 1] = { 0, j } end
  for i = 1, 5 do for j = 0, 10 do southeastOwned[#southeastOwned + 1] = { i, j } end end

  local function flatGate(width, x1)
    return function() return flat_block(width, 80, { { 10, 32 }, { 10, 18 }, { 0, 10 } }, { 32, 40 }, 40, { x0 = 1, x1 = x1 }) end
  end

  local function stone_block(width, height)
    return flat_block(width, height, { { 7, 39 }, { 7, 11 }, { 0, 7 } }, { 39, 48 }, 48)
  end
  local function olive_block(width, height, meta)
    local unit = meta.unit and { width - 24, width - 4, 1, 16, 31 } or nil
    return flat_block(width, height, { { 8, 40 }, { 8, 16 }, { 0, 8 } }, { 40, 48 }, 48, { unit = unit })
  end

  local specs = {
    { name = "littleroot_house_w", layout = "LAYOUT_LITTLEROOT_TOWN", rect = { 2, 4, 5, 5 }, ground = { GRASS },
      parts = function() return littleroot_house(8) end },
    { name = "littleroot_house_e", layout = "LAYOUT_LITTLEROOT_TOWN", rect = { 13, 4, 5, 5 }, ground = { GRASS },
      parts = function() return littleroot_house(64) end },
    { name = "littleroot_lab", layout = "LAYOUT_LITTLEROOT_TOWN", rect = { 3, 12, 7, 5 }, ground = { GRASS },
      parts = littleroot_lab },
    { name = "pokemon_center", layout = "LAYOUT_PETALBURG_CITY", rect = { 19, 13, 4, 4 }, match_rows = { 1, 4 },
      ground = { GRASS }, parts = function() return center_or_mart({ 9, 16 }, true) end },
    { name = "poke_mart", layout = "LAYOUT_MAUVILLE_CITY", rect = { 22, 11, 4, 4 }, match_rows = { 1, 4 },
      ground = { GRASS }, parts = function() return center_or_mart({ 12, 16 }) end },
    { name = "oldale_house", layout = "LAYOUT_OLDALE_TOWN", rect = { 4, 4, 4, 4 }, ground = { GRASS },
      parts = oldale_house },
    { name = "dewford_house", layout = "LAYOUT_DEWFORD_TOWN", rect = { 16, 11, 4, 4 }, match_rows = { 1, 4 },
      ground = { 0x124 }, parts = function() return dewford_house(64) end },
    { name = "dewford_hall", layout = "LAYOUT_DEWFORD_TOWN", rect = { 1, 0, 5, 4 }, ground = { 0x124 },
      parts = function() return dewford_house(80) end },
    { name = "dewford_gym_exterior", layout = "LAYOUT_DEWFORD_TOWN", rect = { 5, 13, 6, 5 }, ground = { 0x124 },
      parts = gym },
    { name = "briney_house", layout = "LAYOUT_ROUTE104", rect = { 15, 47, 5, 4 }, ground = { GRASS },
      parts = briney_house },
    { name = "flower_shop", layout = "LAYOUT_ROUTE104", rect = { 3, 15, 6, 4 }, ground = { GRASS, 0x206, 0x207 },
      parts = flower_shop },
    { name = "kit_house_4", layout = "LAYOUT_PETALBURG_CITY", rect = { 9, 16, 4, 4 }, ground = { GRASS },
      parts = function() return kit_house(64) end },
    { name = "kit_house_5", layout = "LAYOUT_PETALBURG_CITY", rect = { 5, 2, 5, 4 }, ground = { GRASS },
      parts = function() return kit_house(80) end },
    { name = "slateport_house_4", layout = "LAYOUT_SLATEPORT_CITY", rect = { 4, 16, 4, 4 }, ground = { GRASS },
      keep = kit_house_keep(64), parts = function() return kit_house(64) end },
    { name = "slateport_house_5", layout = "LAYOUT_ROUTE109", rect = { 10, 2, 5, 4 }, ground = { 0x124 },
      parts = function() return kit_house(80) end },
    { name = "slateport_house_6", layout = "LAYOUT_SLATEPORT_CITY", rect = { 24, 41, 6, 4 }, ground = { 0x202 },
      keep = kit_house_keep(96), parts = function() return kit_house(96) end },
    { name = "trick_house", layout = "LAYOUT_ROUTE110", rect = { 9, 61, 5, 6 }, ground = { GRASS, 0x171, 0x179, 0x190 },
      parts = trick_house },
    { name = "cycling_gate", layout = "LAYOUT_ROUTE110", rect = { 14, 12, 6, 5 }, ground = { GRASS, 0x149 },
      parts = flatGate(96, 95) },
    { name = "pink_house_4", layout = "LAYOUT_MAUVILLE_CITY", rect = { 18, 11, 4, 4 }, ground = { GRASS, 0x004 },
      parts = function() return pink_house(64) end },
    { name = "pink_house_4w", layout = "LAYOUT_ROUTE118", rect = { 0, 14, 4, 4 }, ground = { GRASS, 0x004 },
      parts = function() return pink_house(64) end },
    { name = "pink_house_5", layout = "LAYOUT_MAUVILLE_CITY", rect = { 34, 2, 5, 4 }, ground = { GRASS, 0x004 },
      parts = function() return pink_house(80) end },
    { name = "pink_house_5b", layout = "LAYOUT_MAUVILLE_CITY", rect = { 31, 11, 5, 4 }, ground = { GRASS, 0x004 },
      parts = function() return pink_house(80, 2) end },
    { name = "cycling_gate_4", layout = "LAYOUT_MAUVILLE_CITY", rect = { 36, 11, 4, 5 }, ground = { GRASS, 0x00E },
      parts = flatGate(64, 63) },
    { name = "verdanturf_house_4", layout = "LAYOUT_VERDANTURF_TOWN", rect = { 0, 11, 4, 4 }, ground = { GRASS, 0x204, 0x205 },
      parts = function() return verdanturf_house(64) end },
    { name = "verdanturf_house_5", layout = "LAYOUT_VERDANTURF_TOWN", rect = { 8, 11, 5, 4 }, ground = { GRASS, 0x204, 0x205 },
      parts = function() return verdanturf_house(80) end },
    { name = "fallarbor_house_4", layout = "LAYOUT_FALLARBOR_TOWN", rect = { 0, 3, 4, 4 }, ground = { 0x279, 0x269 },
      parts = function() return fallarbor_house(64) end },
    { name = "glass_workshop", layout = "LAYOUT_ROUTE113", rect = { 32, 2, 4, 4 }, ground = { 0x218, 0x26D, 0x26E, 0x20C, 0x20D },
      parts = function() return fallarbor_house(64) end },
    { name = "fossil_maniac_house", layout = "LAYOUT_ROUTE114", rect = { 28, 2, 4, 4 }, ground = { 0x279, 0x269 },
      parts = function() return fallarbor_house(64) end },
    { name = "cycling_gate_5", layout = "LAYOUT_ROUTE111", rect = { 11, 109, 5, 5 }, ground = { GRASS, 0x149 },
      parts = flatGate(80, 79) },
    { name = "lilycove_house_4", layout = "LAYOUT_LILYCOVE_CITY", rect = { 35, 3, 4, 4 },
      ground = { GRASS, 0x1D4, 0x1D5, 0x1DC, 0x1DD, 0x1E4, 0x1E5, 0x1E6, 0x1E7 }, match_rows = { 2, 4 },
      parts = function() return lilycove_house(64) end },
    { name = "lilycove_house_5", layout = "LAYOUT_LILYCOVE_CITY", rect = { 37, 11, 5, 4 }, ground = { GRASS, 0x004 },
      match_rows = { 2, 4 }, parts = function() return lilycove_house(80) end },
    { name = "safari_gate", layout = "LAYOUT_ROUTE121", rect = { 35, 0, 5, 6 }, ground = { GRASS, 0x004 },
      parts = safari_gate },
    { name = "safari_south_wing", layout = "LAYOUT_SAFARI_ZONE_SOUTH", rect = { 30, 29, 10, 5 }, ground = { GRASS, 0x004 },
      parts = safari_south },
    { name = "safari_southeast_wing", layout = "LAYOUT_SAFARI_ZONE_SOUTHEAST", rect = { 0, 29, 6, 11 },
      owned = cells(southeastOwned), ground = { GRASS, 0x004 }, parts = safari_southeast },
    { name = "lilycove_motel", layout = "LAYOUT_LILYCOVE_CITY", rect = { 36, 20, 6, 5 }, ground = { GRASS, 0x004, 0x233 },
      parts = lilycove_motel },
    { name = "mossdeep_house", layout = "LAYOUT_MOSSDEEP_CITY", rect = { 18, 7, 4, 4 }, ground = { GRASS, 0x004, 0x002 },
      parts = function() return mossdeep_house_parts(64) end },
    { name = "mossdeep_house_b", layout = "LAYOUT_MOSSDEEP_CITY", rect = { 27, 6, 4, 4 }, ground = { GRASS, 0x004, 0x002 },
      match_rows = { 1, 4 }, parts = function() return mossdeep_house_parts(64) end },
    { name = "mossdeep_house_wide", layout = "LAYOUT_MOSSDEEP_CITY", rect = { 35, 20, 5, 5 },
      ground = { GRASS, 0x004, 0x120, 0x121, 0x129 }, ground_px = true,
      parts = function() return pitched_house(80, { 8, 14 }, { 14, 21 }, { 21, 48 }, { 22, 38 }, { 48, 53 }, 79,
        { 22, 38 }, { 22, 38 }, { 1, 7 }) end },
    { name = "battle_arena", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 35, 23, 9, 7 },
      ground = { 0x286, 0x285, 0x170, 0x189 }, ground_px = true,
      parts = function() return pitched_house(144, { 0, 4 }, { 4, 8 }, { 8, 64 }, { 8, 16 }, { 64, 69 }, 112,
        { 18, 26 }, { 18, 26 }, { 16, 32 }, { inset = 8, overhang = 2, back_z = 32 }) end },
    { name = "battle_palace_wing", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 40, 50, 3, 6 },
      ground = { 0x004, 0x017, 0x00E, 0x0C6, 0x003 }, ground_px = true, keep = { { 0, 8, 48, 80 } },
      parts = function() return pitched_house(48, { 8, 16 }, { 16, 20 }, { 20, 46 }, { 23, 31 }, { 46, 48 }, 80,
        { 16, 24 }, { 16, 24 }, { 2, 8 }, { inset = 2, overhang = 2, back_z = 40 }) end },
    { name = "gym", layout = "LAYOUT_PETALBURG_CITY", rect = { 12, 4, 6, 5 }, match_rows = { 0, 4 }, ground = { GRASS },
      parts = gym },
    { name = "gym_rustboro", layout = "LAYOUT_RUSTBORO_CITY", rect = { 24, 15, 6, 5 }, ground = { 0x2BB, 0x2C3, GRASS },
      parts = gym },
    { name = "devon_corporation", layout = "LAYOUT_RUSTBORO_CITY", rect = { 7, 7, 10, 9 }, ground = { 0x2BB, 0x2C3, GRASS },
      parts = devon },
    { name = "slateport_awning", layout = "LAYOUT_SLATEPORT_CITY", rect = { 16, 7, 5, 3 }, match_rows = { 0, 2 },
      ground = { GRASS }, ground_px = true,
      parts = function() return { Awning("awning", 8, 72, { top_v = 1, valance_v = 24, post_v = 32, foot_v = 47,
        back = 0, lift = 12, rep = { 3, 11 }, posts = { { 8, 14 }, { 66, 72 } }, shaft = { 34, 43 }, foot = { 43, 47 } }) } end },
    { name = "fan_club", layout = "LAYOUT_SLATEPORT_CITY", rect = { 2, 22, 5, 6 }, ground = { GRASS, 0x209, 0x218, 0x219 },
      keep = { { 0, 0, 80, 80 }, { 29, 80, 33, 96 }, { 47, 80, 51, 96 } }, parts = fan_club },
    { name = "museum", layout = "LAYOUT_SLATEPORT_CITY", rect = { 25, 7, 7, 6 }, ground = { GRASS },
      keep = { { 6, 2, 106, 3 }, { 5, 3, 107, 4 }, { 4, 4, 108, 5 }, { 3, 5, 109, 6 }, { 2, 6, 110, 7 },
               { 1, 7, 111, 8 }, { 0, 8, 112, 96 } }, parts = museum },
    { name = "contest_hall", layout = "LAYOUT_SLATEPORT_CITY", rect = { 28, 22, 6, 6 }, ground = { GRASS },
      keep = { { 0, 9, 96, 96 } }, parts = contest_hall },
    { name = "slateport_bush", layout = "LAYOUT_SLATEPORT_CITY", rect = { 7, 10, 1, 1 }, ground = { GRASS }, ground_px = true,
      keep = { { 6, 1, 10, 2 }, { 4, 2, 12, 3 }, { 3, 3, 13, 4 }, { 2, 4, 14, 6 }, { 1, 6, 14, 10 },
               { 2, 10, 14, 12 }, { 3, 12, 13, 14 }, { 5, 14, 11, 15 } },
      parts = function() return { ProjDome("bush", 7.5, 8.6, 7.6, 7.0, 8.0) } end },
    { name = "slateport_bollard", layout = "LAYOUT_SLATEPORT_CITY", rect = { 33, 34, 1, 1 }, ground = { 0x202 }, ground_px = true,
      parts = function() return { ProjLathe("bollard", 8, 11.5, BOLLARD, { squash = 0.5, seg = 10 }) } end },
    { name = "shipyard", layout = "LAYOUT_SLATEPORT_CITY", rect = { 24, 32, 8, 7 }, ground = { 0x202, GRASS },
      keep = { { 0, 1, 128, 112 } }, parts = shipyard },
    { name = "slateport_stall", layout = "LAYOUT_SLATEPORT_CITY", rect = { 2, 41, 5, 3 }, ground = { 0x211, 0x285 },
      ground_px = true, keep = stall_keep(72),
      parts = function() return { stall(72, 57.5, { { 24, 3, 55, 8 }, { 9, 12, 12, 20 }, { 60, 12, 69, 20 } }) } end },
    { name = "slateport_stall_e", layout = "LAYOUT_SLATEPORT_CITY", rect = { 10, 41, 4, 3 }, ground = { 0x211, 0x285 },
      ground_px = true, keep = stall_keep(56),
      parts = function() return { stall(56, 41.5, { { 24, 3, 39, 8 }, { 9, 12, 12, 20 }, { 44, 12, 53, 20 } }) } end },
  }

  -- ── the third reading: parts read off the drawing (parts_art(art) -> parts, texture) ──

  local PlanPrism, PlanPyramid, PlatePrism, SectionPrism, PlanHip = K.PlanPrism, K.PlanPyramid, K.PlatePrism,
    K.SectionPrism, K.PlanHip
  local rounded, octagon, flat, Card = K.roundedPlan, K.octagon, K.flat, K.Card

  local function battle_factory()
    local side = { 100, 108, 144 }
    local parts = { PlanPrism("mid", octagon(87, 153, 101, 144, 8), 0, 101, side),
                    PlanPrism("fence", { { 0, 60 }, { 8, 60 }, { 8, 144 }, { 0, 144 } }, 0, 14, { 0, 8, 144 }) }
    for _, t in ipairs({ { 8, 64, 8 }, { 176, 232, 8 }, { 60, 92, 6 }, { 148, 180, 6 } }) do
      parts[#parts + 1] = PlanPrism("tower", octagon(t[1], t[2], 96, 136, t[3]), 0, 80, side)
    end
    parts[#parts + 1] = PlanPrism("fence", { { 232, 60 }, { 240, 60 }, { 240, 144 }, { 232, 144 } }, 0, 14, { 232, 240, 144 })
    return parts
  end

  local function battle_pyramid()
    local parts = {}
    for i = 0, 12 do
      parts[#parts + 1] = PlanPrism("tier", { { 8 + 8 * i, 56 + 4 * i }, { 232 - 8 * i, 56 + 4 * i },
        { 232 - 8 * i, 160 - 4 * i }, { 8 + 8 * i, 160 - 4 * i } }, 8 * i, 8 * i + 8, { 60, 76, 160 - 4 * i })
    end
    parts[#parts + 1] = PlanPrism("steps", { { 100, 160 }, { 140, 160 }, { 140, 176 }, { 100, 176 } }, 0, 4, { 104, 112, 176 })
    parts[#parts + 1] = PlanPrism("portico", { { 40, 140 }, { 200, 140 }, { 200, 160 }, { 40, 160 } }, 0, 20, { 60, 76, 160 })
    parts[#parts + 1] = PlanPrism("gate", { { 104, 120 }, { 136, 120 }, { 136, 160 }, { 104, 160 } }, 0, 40, { 60, 76, 160 })
    return parts
  end

  -- drops the Battle Frontier sand's loose specks from a drawing
  local function sand_specks(make)
    local specks = {}
    for _, c in ipairs({ { 238, 230, 164 }, { 213, 180, 106 } }) do
      specks[math.floor(c[1] * 31 / 255 + 0.5) * 1024 + math.floor(c[2] * 31 / 255 + 0.5) * 32 + math.floor(c[3] * 31 / 255 + 0.5)] = true
    end
    return function(art)
      for i = 0, art.w * art.h - 1 do
        local o = i * 4
        if art.px[o + 4] >= 0.5 then
          local k = math.floor(art.px[o + 1] * 31 + 0.5) * 1024 + math.floor(art.px[o + 2] * 31 + 0.5) * 32
            + math.floor(art.px[o + 3] * 31 + 0.5)
          if specks[k] then art.px[o + 1], art.px[o + 2], art.px[o + 3], art.px[o + 4] = 0, 0, 0, 0 end
        end
      end
      return make(art)
    end
  end

  local HALL_FRONT, HALL_HIGH = 80, 38
  local HALL_VAULT = { { { 40, 38 }, { 72, 38 }, { 71, 39 }, { 70, 41 }, { 69, 42 }, { 67, 44 }, { 66, 45 }, { 46, 45 },
    { 44, 43 }, { 42, 41 } } }
  local HALL_VAULT_PORCH = { HALL_VAULT[1], { { 38, 38 }, { 74, 38 }, { 74, 40 }, { 38, 40 } } }
  local HALL_KEEP = { { 38, 9, 74, 16 }, { 0, 16, 112, 80 } }
  local function frontier_hall(art, gate, vault)
    vault = vault or HALL_VAULT
    local side = { 14, 20, HALL_FRONT }
    local back = HALL_FRONT - 26
    local parts = {}
    local whole = rounded(56, (back + HALL_FRONT) / 2, 56, 13, 12.0, 48)
    if not gate then
      parts[1] = PlanPrism("hall", whole, 0, HALL_HIGH, side)
    else
      local function cut(clamp)
        local pts = {}
        for k, p in ipairs(whole) do pts[k] = { clamp(p[1], p[2]) } end
        local out = {}
        for k, p in ipairs(pts) do
          local prev = pts[(k - 2) % #pts + 1]
          if not (p[1] == prev[1] and p[2] == prev[2]) then out[#out + 1] = p end
        end
        return out
      end
      parts[1] = PlanPrism("hall", cut(function(x, z) return math.min(x, 40), z end), 0, HALL_HIGH, side)
      parts[2] = PlanPrism("hall", cut(function(x, z) return math.max(x, 72), z end), 0, HALL_HIGH, side)
      parts[3] = PlanPrism("lintel", { { 40, back }, { 72, back }, { 72, HALL_FRONT }, { 40, HALL_FRONT } }, 24, HALL_HIGH, side)
    end
    for _, poly in ipairs(vault) do
      parts[#parts + 1] = PlatePrism("vault", poly, back, HALL_FRONT, { 40, 46, HALL_FRONT })
    end
    return parts, art
  end

  local ARCH_FRONT, ARCH_DEPTH, ARCH_PILLAR = 80, 12, 44
  local function frontier_arch(art)
    local W = art.w
    local side = { 2, 6, ARCH_FRONT }
    local back = ARCH_FRONT - ARCH_DEPTH
    local parts = {}
    for _, x0 in ipairs({ 0, W - 16 }) do
      parts[#parts + 1] = PlanPrism("pillar", { { x0, back }, { x0 + 16, back }, { x0 + 16, ARCH_FRONT }, { x0, ARCH_FRONT } },
        0, ARCH_PILLAR, side)
    end
    local band = {}
    for u = 8, W - 7, 2 do
      local rows = {}
      local rmin = math.huge
      for _, x in ipairs({ u - 1, u }) do
        for v = 0, ARCH_FRONT - 1 do
          if art.px[(v * art.w + x) * 4 + 4] >= 0.5 then rows[#rows + 1] = v; rmin = math.min(rmin, v) end
        end
      end
      local finish = -math.huge
      for _, v in ipairs(rows) do if v < rmin + 40 then finish = math.max(finish, v) end end
      band[u] = { back - rmin, math.max(0, ARCH_FRONT - finish - 1) }
    end
    for u = 8, W - 9, 2 do
      local ta, ba, tb, bb = band[u][1], band[u][2], band[u + 2][1], band[u + 2][2]
      parts[#parts + 1] = PlatePrism("arch", { { u, ba }, { u + 2, bb }, { u + 2, tb }, { u, ta } }, back, ARCH_FRONT, side)
    end
    return parts
  end

  local function cozmo_house(art)
    local parts = pitched_house(64, { 16, 25 }, { 25, 29 }, { 29, 51 }, { 35, 43 }, { 51, 55 }, 78, { 10, 18 }, { 9, 17 }, { 3, 7 })
    local roof = parts[2]
    local mast = { w = art.w, h = art.h, px = {} }
    for v = 0, art.h - 1 do
      for u = 0, art.w - 1 do
        local o = (v * art.w + u) * 4
        local inside = u >= 32 and u < 57 and v >= 2 and v < 32
        for k = 1, 4 do mast.px[o + k] = inside and art.px[o + k] or 0 end
      end
    end
    local t = tan(rad(roof.pitch))
    local z = (32 + roof.ye + roof.zf * t) / (1 + t)
    parts[#parts + 1] = Card("antenna", mast, z)
    return parts, art
  end

  local mirage = function()
    local parts = {
      PlanPrism("base", rounded(24, 80, 25.0, 16.6, 3.5, 40), 0, 24, { 2, 8, 96 }),
      PlanPrism("mid", rounded(24, 80, 23.6, 14.4, 2.0, 40), 24, 47, { 2, 8, 72 }),
      PlanPrism("top", rounded(24, 80, 18.4, 11.0, 2.0, 40), 47, 72, { 8, 14, 49 }, { shrink = 1.0 }),
    }
    local ks = { 0.97, 0.91, 0.84, 0.76, 0.68, 0.61, 0.55 }
    for i, y in ipairs({ 72, 74, 76, 78, 80, 82, 84 }) do
      parts[#parts + 1] = PlanPrism("crown", rounded(24, 80, 18.4 * ks[i], 11.0 * ks[i], 2.0, 40), y, y + 2, { 8, 14, 49 })
    end
    parts[#parts + 1] = PlanPyramid("tip", rounded(24, 80, 10.1, 6.05, 2.0, 24), 86, { 24, 92, 80 })
    return parts
  end

  local function hall(o) return function(art) return frontier_hall(art, o and o.gate, o and o.vault) end end
  local HALL_OWNED = {}
  for j = 1, 4 do for i = 0, 6 do HALL_OWNED[i .. "," .. j] = true end end
  for i = 2, 4 do HALL_OWNED[i .. ",0"] = true end
  local FRONTIER_HOUSE_GROUND = { 0x001, 0x170, 0x005, 0x0E0, 0x002, 0x007, 0x101 }

  local artSpecs = {
    { name = "parked_bikes", layout = "LAYOUT_MAUVILLE_CITY", rect = { 26, 3, 3, 1 }, ground = { GRASS, 0x004 },
      ground_px = true, parts_art = function(art) return { Card("bikes", art, 15) } end },
    { name = "fallarbor_cozmo_house", layout = "LAYOUT_FALLARBOR_TOWN", rect = { 5, 13, 4, 5 }, ground = { 0x279 },
      parts_art = cozmo_house },
    { name = "mirage_tower", layout = "LAYOUT_ROUTE111", rect = { 18, 53, 3, 6 }, ground = { 0x251, 0x259, 0x121, 0x25A },
      parts_art = flat(mirage) },
    { name = "cable_car_station", layout = "LAYOUT_ROUTE112", rect = { 27, 23, 5, 5 }, ground = { 0x271, 0x210, 0x218, 0x21A },
      parts_art = flat(function() return { PlatePrism("station", { { 0, 0 }, { 0, 34 }, { 56, 34 }, { 80.5, 9.5 }, { 80.5, 0 } },
        34, 80, { 2, 10, 80 }) } end) },
    { name = "cable_car_station_top", layout = "LAYOUT_MT_CHIMNEY", rect = { 14, 32, 6, 5 }, ground = { 0x271 },
      parts_art = flat(function() return { PlatePrism("station", { { 96, 0 }, { 96, 34 }, { 40, 34 }, { 8.5, 2.5 }, { 8.5, 0 } },
        34, 80, { 86, 94, 80 }) } end) },
    { name = "trainer_hill_entrance", layout = "LAYOUT_ROUTE111", rect = { 29, 106, 5, 6 },
      ground = { 0x070, 0x073, 0x071, 0x07B, 0x075, 0x089 }, keep = { { 0, 0, 80, 82 } },
      parts_art = flat(function() return {
        PlanPrism("hill", { { 0, 36 }, { 80, 36 }, { 80, 82 }, { 0, 82 } }, 0, 36, { 2, 10, 82 }),
        PlanPyramid("lantern", { { 57, 56 }, { 48.5, 66 }, { 31.5, 66 }, { 23, 56 }, { 31.5, 46 }, { 48.5, 46 } }, 36, { 40, 48, 56 }) } end) },
    { name = "department_store", layout = "LAYOUT_LILYCOVE_CITY", rect = { 23, 0, 9, 7 }, ground = { GRASS, 0x233, 0x22B },
      parts_art = flat(function() return { PlanPrism("store", { { 0, 48 }, { 144, 48 }, { 144, 112 }, { 0, 112 } }, 0, 112,
        { 2, 10, 112 }, { top = Tile(4, 4, 20, 20) }) } end) },
    { name = "lilycove_museum", layout = "LAYOUT_LILYCOVE_CITY", rect = { 7, 1, 10, 6 }, ground = { GRASS, 0x002, 0x208, 0x207, 0x004 },
      parts_art = flat(function() return {
        PlanPrism("museum", { { 0, 52 }, { 160, 52 }, { 160, 96 }, { 0, 96 } }, 0, 44, { 2, 10, 96 }),
        PlanPrism("museum_hall", { { 40, 60 }, { 120, 60 }, { 120, 94 }, { 40, 94 } }, 0, 68, { 42, 50, 94 }) } end) },
    { name = "lilycove_contest_hall", layout = "LAYOUT_LILYCOVE_CITY", rect = { 20, 18, 7, 7 },
      ground = { GRASS, 0x233, 0x22B, 0x23B }, ground_px = true,
      parts_art = flat(function() return { PlanPrism("hall", { { 8, 38 }, { 104, 38 }, { 112, 46 }, { 112, 104 }, { 104, 112 },
        { 8, 112 }, { 0, 104 }, { 0, 46 } }, 0, 30, { 16, 40, 112 }) } end) },
    { name = "lilycove_harbor", layout = "LAYOUT_LILYCOVE_CITY", rect = { 9, 27, 7, 6 }, ground = { GRASS, 0x233, 0x22B, 0x23B },
      parts_art = flat(function() return { SectionPrism("harbor", { { 96, 0 }, { 96, 34 }, { 98, 36 }, { 98, 44 }, { 56, 55 },
        { 14, 44 }, { 14, 36 }, { 16, 34 }, { 16, 0 } }, 0, 112, { 2, 10, 96 }) } end) },
    { name = "battle_factory", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 4, 30, 15, 9 },
      ground = { 0x189, 0x170, 0x172, 0x19A, 0x198, 0x180, 0x181, 0x05E }, ground_px = true,
      keep = { { 0, 4, 232, 144 }, { 88, 0, 152, 4 }, { 232, 44, 240, 144 } }, parts_art = flat(battle_factory) },
    { name = "frontier_house", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 43, 2, 3, 4 },
      ground = FRONTIER_HOUSE_GROUND, ground_px = true,
      parts_art = flat(function() return { PlanPrism("house", rounded(24, 49.5, 24.6, 14.2, 10.0), 0, 36, { 10, 18, 63 }) } end) },
    { name = "frontier_house_glass", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 52, 41, 3, 4 },
      ground = FRONTIER_HOUSE_GROUND, ground_px = true, match_rows = { 1, 4 },
      parts_art = flat(function() return { PlanPrism("house", rounded(24, 49.5, 24.6, 14.2, 10.0), 0, 36, { 20, 28, 63 }) } end) },
    { name = "frontier_house_long", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 44, 41, 6, 4 },
      ground = FRONTIER_HOUSE_GROUND, ground_px = true,
      parts_art = flat(function() return { PlanPrism("house", rounded(48, 49.5, 48.6, 14.2, 14.0, 48), 0, 36, { 10, 18, 63 }) } end) },
    { name = "frontier_hall", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 7, 24, 7, 5 },
      ground = { 0x001, 0x079, 0x0C7, 0x016, 0x3B6 }, ground_px = true, owned = HALL_OWNED, keep = HALL_KEEP,
      parts_art = hall() },
    { name = "frontier_hall_porch", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 32, 8, 7, 5 },
      ground = { 0x0C6, 0x0A9, 0x00F, 0x001 }, ground_px = true, owned = HALL_OWNED, keep = HALL_KEEP,
      parts_art = hall({ vault = HALL_VAULT_PORCH }) },
    { name = "frontier_hall_gate", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 23, 61, 7, 5 },
      ground = { 0x05E, 0x05D, 0x055, 0x170 }, ground_px = true, owned = HALL_OWNED,
      keep = { HALL_KEEP[1], { 0, 16, 112, 56 }, { 0, 56, 40, 80 }, { 72, 56, 112, 80 } },
      parts_art = hall({ gate = true }) },
    { name = "frontier_arch", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 24, 46, 5, 5 },
      ground = { 0x05E, 0x05D, 0x05F }, ground_px = true,
      parts_art = function(art) return flat(function() return frontier_arch(art) end)(art) end },
    { name = "battle_tower", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 8, 0, 17, 16 },
      ground = { 0x001, 0x201, 0x203, 0x202 }, ground_px = true,
      keep = { { 0, 0, 272, 248 }, { 0, 248, 100, 256 }, { 172, 248, 272, 256 } },
      parts_art = flat(function() return {
        PlanPrism("wing", { { 0, 136 }, { 46, 136 }, { 46, 248 }, { 0, 248 } }, 0, 320, { 20, 40, 248 }, { top = Tile(20, 0, 40, 16) }),
        PlanPrism("wing", { { 226, 136 }, { 272, 136 }, { 272, 248 }, { 226, 248 } }, 0, 320, { 232, 252, 248 }, { top = Tile(20, 0, 40, 16) }),
        PlanPrism("shaft", { { 46, 136 }, { 226, 136 }, { 226, 232 }, { 46, 232 } }, 0, 320, { 60, 76, 196 }, { top = Tile(20, 0, 40, 16) }),
        PlanPrism("lobby", { { 46, 232 }, { 226, 232 }, { 226, 248 }, { 46, 248 } }, 0, 36, { 60, 76, 248 }) } end) },
    { name = "battle_pyramid", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 51, 5, 15, 11 },
      ground = { 0x121, 0x129, 0x120, 0x128, 0x001, 0x003 }, ground_px = true,
      keep = { { 0, 0, 240, 32 }, { 16, 32, 224, 48 }, { 8, 48, 232, 160 }, { 16, 160, 224, 176 } },
      parts_art = sand_specks(flat(battle_pyramid)) },
    { name = "battle_arena_gate", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 36, 36, 7, 4 },
      ground = { 0x0C6, 0x001, 0x003, 0x00E, 0x1D9, 0x1D8, 0x1DA }, ground_px = true,
      parts_art = flat(function() return {
        PlanPrism("gate", { { 0, 36 }, { 32, 36 }, { 32, 64 }, { 0, 64 } }, 0, 36, { 10, 20, 64 }),
        PlanPrism("gate", { { 80, 36 }, { 112, 36 }, { 112, 64 }, { 80, 64 } }, 0, 36, { 90, 100, 64 }),
        PlanPrism("lintel", { { 32, 36 }, { 80, 36 }, { 80, 64 }, { 32, 64 } }, 24, 36, { 40, 48, 64 }) } end) },
    { name = "battle_palace", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST", rect = { 43, 49, 5, 8 },
      ground = { 0x004, 0x017, 0x00E, 0x0C6, 0x003 }, ground_px = true, keep = { { 0, 16, 80, 96 }, { 8, 96, 72, 128 } },
      parts_art = flat(function() return {
        PlanPrism("hall", { { 0, 40 }, { 80, 40 }, { 80, 104 }, { 0, 104 } }, 0, 18, { 72, 78, 104 }),
        PlanPrism("eave", { { -2, 34 }, { 82, 34 }, { 82, 106 }, { -2, 106 } }, 18, 20, { 72, 78, 106 }),
        PlanHip("hall_roof", -2, 82, 34, 106, 20, 23, 57, 71, 47),
        PlanPrism("porch", { { 18, 88 }, { 62, 88 }, { 62, 128 }, { 18, 128 } }, 0, 42, { 20, 26, 128 }),
        PlanPrism("plinth", { { 8, 116 }, { 18, 116 }, { 18, 128 }, { 8, 128 } }, 0, 32, { 10, 16, 128 }),
        PlanPrism("plinth", { { 62, 116 }, { 72, 116 }, { 72, 128 }, { 62, 128 } }, 0, 32, { 64, 70, 128 }),
        PlanPrism("porch_eave", { { 14, 90 }, { 66, 90 }, { 66, 130 }, { 14, 130 } }, 42, 44, { 20, 26, 130 }),
        PlanHip("porch_roof", 14, 66, 90, 130, 44, 31, 49, 111, 55) } end) },
  }

  -- kits: buildings of one kit, any size, found by their top-left corner, their top row, its end
  -- and the corner column's foot (Rustboro's stone and olive blocks), each modelled from its own
  -- drawing. parts(width, height, meta) in pixels; meta.unit: a ventilation unit on the roof
  specs.kits = {
    { name = "rustboro_stone", secondary = "rustboro", corner = 0x224, top = { [0x225] = true }, finish = { [0x226] = true },
      foot = 0x21c, ground = { 0x2BB, 0x2C3, GRASS }, parts = stone_block },
    { name = "rustboro_olive", secondary = "rustboro", corner = 0x220, top = { [0x221] = true, [0x222] = true },
      finish = { [0x223] = true, [0x23F] = true }, foot = 0x240, ground = { 0x2BB, 0x2C3, GRASS }, parts = olive_block },
  }
  for _, sp in ipairs(artSpecs) do specs[#specs + 1] = sp end
  return specs
end
