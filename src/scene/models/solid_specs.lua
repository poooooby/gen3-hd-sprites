-- Building models of round things (Battle Scene: Overworld): the specs whose parts are read off
-- the drawing with solids (src/scene/models/solids.lua) - the battle tents, boats, parasols,
-- Sootopolis's houses, the Pokemon League, the Battle Dome and Pike, the Space Center...
--
-- Same spec format as src/scene/models/specs.lua, plus:
--   lod = { step, cell, tol }   the least steps of every HeightSolid built for it
--   ground_rgb = { { r, g, b }... }   colours the building never has (the ground painted round it)
--   clip_art = true   every triangle cut to the drawing's box
--   parts_art(art, ctx): ctx.layoutArt(layout, x, y, w, h, ground) -> another drawing (the
--   reference copy of something else), or nil
--
-- Ported from Emerald 3DS's scripts/voxel_building_specs.py (by Zallax and contributors, CC BY-NC-SA
-- 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), whose docstrings explain how each
-- drawing is read. Every number is theirs.

return function(K, specs)
  local h = specs.helpers
  local flat_block, ProjLathe, GRASS, gridCells = h.flat_block, h.ProjLathe, h.GRASS, h.gridCells
  local unpack = unpack or table.unpack
  local Volume, HeightSolid, ownBands, withRing, Grown = K.Volume, K.HeightSolid, K.ownBands, K.withRing, K.Grown
  local PlanPrism, PlanPyramid, Tile, octagon = K.PlanPrism, K.PlanPyramid, K.Tile, K.octagon
  local ProjSection, ProjHull, ProjCanopy = K.ProjSection, K.ProjHull, K.ProjCanopy
  local abs = math.abs
  local floor, min, max, sqrt, sin, cos, tan, rad, pi = math.floor, math.min, math.max, math.sqrt,
    math.sin, math.cos, math.tan, math.rad, math.pi
  local SHADE_ART, SHADE_WEST, SHADE_EAST = K.SHADE_ART, K.SHADE_WEST, K.SHADE_EAST

  -- ── drawings ──────────────────────────────────────────────────────────────

  local function key5(r, g, b) return floor(r * 31 + 0.5) * 1024 + floor(g * 31 + 0.5) * 32 + floor(b * 31 + 0.5) end
  local function rgbSet(list)
    local s = {}
    for _, c in ipairs(list) do s[key5(c[1] / 255, c[2] / 255, c[3] / 255)] = true end
    return s
  end
  local function drawn(art, u, v) return art.px[(v * art.w + u) * 4 + 4] >= 0.5 end
  local function rgbIn(art, u, v, set)
    local o = (v * art.w + u) * 4
    return set[key5(art.px[o + 1], art.px[o + 2], art.px[o + 3])] == true
  end
  local function clearPx(art, u, v)
    local o = (v * art.w + u) * 4
    art.px[o + 1], art.px[o + 2], art.px[o + 3], art.px[o + 4] = 0, 0, 0, 0
  end
  -- every drawn pixel of these colours made clear
  local function clearRgb(art, set)
    for v = 0, art.h - 1 do
      for u = 0, art.w - 1 do
        if drawn(art, u, v) and rgbIn(art, u, v, set) then clearPx(art, u, v) end
      end
    end
    return art
  end
  local function blank(w, hh)
    local px = {}
    for i = 1, w * hh * 4 do px[i] = 0 end
    return { w = w, h = hh, px = px }
  end
  local function copyArt(art)
    local px = {}
    for i = 1, #art.px do px[i] = art.px[i] end
    return { w = art.w, h = art.h, px = px }
  end
  -- src's rectangle [x0, x1) x [y0, y1) pasted into dst at (x, y)
  local function paste(dst, src, x, y, x0, y0, x1, y1)
    x0, y0, x1, y1 = x0 or 0, y0 or 0, x1 or src.w, y1 or src.h
    for v = y0, y1 - 1 do
      for u = x0, x1 - 1 do
        local du, dv = x + u - x0, y + v - y0
        if du >= 0 and du < dst.w and dv >= 0 and dv < dst.h then
          local s, d = (v * src.w + u) * 4, (dv * dst.w + du) * 4
          for c = 1, 4 do dst.px[d + c] = src.px[s + c] end
        end
      end
    end
  end
  local function grownAll(parts, H)
    local out = {}
    for i, p in ipairs(parts) do out[i] = Grown(p, 2 * H) end
    return out
  end
  -- own_bands' parts for names, each the pixels own(u, v) calls its own
  local function bandsOf(own, names)
    local parts = {}
    for i, n in ipairs(names) do parts[i] = { n, function(u, v) return own(u, v) == n end } end
    return parts
  end

  -- ── battle tents ──────────────────────────────────────────────────────────

  --- the point of the drawing's (u, v) where its 45-degree ray enters `vol`, `sink` further down
  local function onRay(vol, u, v, sink, tmax)
    tmax = tmax or 96.0
    local t = tmax
    while t >= 0 and not vol:inside(u, t, v + t) do t = t - 0.25 end
    if t >= 0 then
      local f = t - sink
      return { u, f, v + f }
    end
    local function top(z)
      local y = tmax
      while y >= 0 and not vol:inside(u, y, z) do y = y - 0.25 end
      return y
    end
    local bestD, bestT
    for k = 0, floor(tmax * 2) - 1 do
      local tt = k * 0.5
      local y = top(v + tt)
      if y >= 0 and (bestD == nil or tt - y < bestD) then bestD, bestT = tt - y, tt end
    end
    return { u, bestT, v + bestT }
  end

  --- a box standing out of a building's front (a door): its facade upright from `y1` to the ground
  --- at zf, its top back to zb, its sides the facade's own edge columns
  local function Porch(name, x0, x1, zf, zb, y1, side_w)
    return { name = name, emit = function(_, mesh)
      mesh:poly({ { x0, 0, zf, x0, zf }, { x1, 0, zf, x1, zf }, { x1, y1, zf, x1, zf - y1 },
                  { x0, y1, zf, x0, zf - y1 } }, SHADE_ART, name .. ".front")
      mesh:poly({ { x0, y1, zf, x0, zf - y1 }, { x1, y1, zf, x1, zf - y1 },
                  { x1, y1, zb, x1, zb - y1 }, { x0, y1, zb, x0, zb - y1 } }, SHADE_ART, name .. ".top")
      local d = zf - zb
      local k = min(1.0, side_w / d)
      mesh:poly({ { x0, 0, zb, x0 + d * k, zf }, { x0, 0, zf, x0, zf }, { x0, y1, zf, x0, zf - y1 },
                  { x0, y1, zb, x0 + d * k, zf - y1 } }, SHADE_WEST, name .. ".west~proj")
      mesh:poly({ { x1, 0, zf, x1, zf }, { x1, 0, zb, x1 - d * k, zf }, { x1, y1, zb, x1 - d * k, zf - y1 },
                  { x1, y1, zf, x1, zf - y1 } }, SHADE_EAST, name .. ".east~proj")
    end }
  end

  local TENT_BODY = { 40, 48, 33, 31, 30, 3.5 }
  local TENT_CROWN = { 40, 48, 17, 8, 14, 4.5, 24, 32 }
  -- the arms' axes: { u, v, radius, y } (y false: laid on the dome)
  local TENT_OUTER = { { 40, 9, 3.5, false }, { 32, 5, 4, false }, { 24, 7, 4.5, false }, { 16, 14, 5.5, false },
    { 9, 24, 6.5, 20 }, { 6, 36, 6.5, 14 }, { 6, 50, 6.5, 9 }, { 6, 66, 6, 3 } }
  local TENT_INNER = { { 32, 28, 5, false }, { 32, 36, 6, false }, { 31, 46, 5.5, false } }

  local function battle_tent(art)
    local tex = withRing(art, {})
    local body = Volume():dome(unpack(TENT_BODY))
    local vol = Volume():dome(unpack(TENT_BODY))
    vol:drum(unpack(TENT_CROWN))
    for _, mirror in ipairs({ false, true }) do
      local function f(u) if mirror then return 80 - u end return u end
      for _, arm in ipairs({ TENT_OUTER, TENT_INNER }) do
        local pts = {}
        for i, a in ipairs(arm) do
          local u, v, r, y = a[1], a[2], a[3], a[4]
          local p = y and { f(u), y, v + y } or onRay(body, f(u), v, 0.4 * r)
          pts[i] = { p[1], p[2], p[3], r }
        end
        vol:tube(pts)
      end
    end
    local function door(u, v) return u >= 19 and u < 60 and v >= 48 and v < 80 end
    return { HeightSolid("tent", tex, art.h, vol, { step = 2, mask = door, mirror_z = 48, lean = 2.0 }),
             Porch("door", 19, 60, 80, 73, 25, 6) }, tex
  end

  -- a tent drawn in a town's own shades: the town's drawing round it cleared by Slateport's outline
  local function battle_tent_elsewhere(art, ctx)
    local ref = ctx and ctx.layoutArt and ctx.layoutArt("LAYOUT_SLATEPORT_CITY", 8, 8, 5, 5, { GRASS })
    if not ref then error("no reference tent") end
    art = copyArt(art)
    for v = 0, 79 do
      for u = 0, 79 do
        if not drawn(ref, u, v) then clearPx(art, u, v) end
      end
    end
    return battle_tent(art)
  end

  -- ── boats ─────────────────────────────────────────────────────────────────

  local BOAT_Z = 35
  local BOAT_SAILS = { { { 27, 33 }, { 9, 12 }, { 27, 12 } }, { { 32, 32 }, { 44, 11 }, { 32, 11 } } }
  local BOAT_MAST = { 27.5, 31.5, 8, 33 }

  -- a polygon's corners pushed d out from its middle
  local function grownPoly(poly, d)
    local cx, cy = 0, 0
    for _, p in ipairs(poly) do cx, cy = cx + p[1], cy + p[2] end
    cx, cy = cx / #poly, cy / #poly
    local out = {}
    for i, p in ipairs(poly) do
      local dx, dy = p[1] - cx, p[2] - cy
      local k = K.hypot(dx, dy)
      if k == 0 then k = 1.0 end
      out[i] = { p[1] + dx / k * d, p[2] + dy / k * d }
    end
    return out
  end

  -- a boat's sails and mast, flat cards in its keel's plane
  local function SailCards(name, zs)
    local x0, x1, y0, y1 = BOAT_MAST[1], BOAT_MAST[2], BOAT_MAST[3], BOAT_MAST[4]
    local polys = {}
    for i, poly in ipairs(BOAT_SAILS) do polys[i] = grownPoly(poly, 1.5) end
    polys[#polys + 1] = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
    return { name = name, emit = function(_, mesh)
      for _, z in ipairs(zs) do
        for _, poly in ipairs(polys) do
          local q = {}
          for k, p in ipairs(poly) do q[k] = { p[1], p[2], z, p[1], z - p[2] } end
          mesh:poly(q, 1.0, name .. "~proj")
        end
      end
    end }
  end

  local function sailboat(boats, keel)
    boats, keel = boats or { 0 }, keel or 0.0
    return function()
      local zs, parts = {}, {}
      for i, dv in ipairs(boats) do zs[i] = BOAT_Z + dv + keel end
      for _, z in ipairs(zs) do
        parts[#parts + 1] = ProjHull("boat", 24.5, z, 24.5, 5.5, -2, 8, 3.0, 6, { keel = 0, seg = 24 })
      end
      parts[#parts + 1] = SailCards("sail", zs)
      return parts
    end
  end

  local function rowboat()
    return { ProjHull("rowboat", 24, 22.5, 22.8, 8.5, 0, 15, 2.3, 2, {
      inner = { 23.5, 22.5, 19.5, 6.5, 8 }, boxes = { { 36, 40, 8, 14, 15, 30 }, { 33, 45, 0, 4, 25, 31 } } }) }
  end

  -- ── Route 109's beach ─────────────────────────────────────────────────────

  local PARASOL_SHADOW = { { 205, 156, 82 }, { 213, 180, 106 }, { 222, 205, 131 } }

  local function parasol(art)
    local H = art.h
    local tex = withRing(art, {})
    local function own(u, v)
      if not drawn(art, u, v) then return nil end
      return v <= 31 and "canopy" or "pole"
    end
    local band
    tex, band = ownBands(tex, H, bandsOf(own, { "canopy", "pole" }))
    for v = 0, H - 1 do
      for u = 0, art.w - 1 do
        local o = own(u, v)
        if o ~= "canopy" then clearPx(tex, u, v + band.canopy * H) end
        if v == 39 and o ~= "pole" then clearPx(tex, u, v + band.pole * H) end
      end
    end
    return { ProjCanopy("canopy", 16, 38.5, 16.2, 19.25, 25.25, { front = 3.5, y_under = 20.5,
               offset = band.canopy * H, seg = 24 }),
             ProjLathe("pole", 16, 38.5, { { 0, 2 }, { 21, 2 } }, { seg = 8, offset = band.pole * H }) }, tex
  end

  local function sun_lounger(art)
    local H = art.h
    local tex = withRing(art, {})
    local a = rad(40)
    local t, L = 1.2, 7.5
    local hz, top = 24.5, 5.0
    local ez, ey = hz - L * cos(a), top + L * sin(a)
    local nz, ny = sin(a), cos(a)
    local seat = top - 2
    local k = (top - t * ny - seat) / sin(a)
    local frame = { { 39, seat }, { 39, top }, { hz, top }, { ez, ey }, { ez - t * nz, ey - t * ny },
                    { hz - t * nz + k * cos(a), seat } }
    local function under_back(z) return top - t * ny + (hz - t * nz - z) * tan(a) end
    local parts = { ProjSection("frame", frame, 1, 14, { grown = 2 * H }) }
    for _, x in ipairs({ { 1, 5 }, { 10, 14 } }) do
      parts[#parts + 1] = ProjSection("leg", { { 36.5, 0 }, { 38, 0 }, { 38, seat }, { 36.5, seat } }, x[1], x[2],
        { grown = 2 * H })
    end
    for _, x in ipairs({ { 2, 3.5 }, { 11.5, 13 } }) do
      parts[#parts + 1] = ProjSection("strut", { { 20.5, 0 }, { 21.5, 0 }, { 21.5, under_back(21.5) },
        { 20.5, under_back(20.5) } }, x[1], x[2], { uv = { 1.5, 20.5 } })
    end
    return parts, tex
  end

  local function beach_mat(art)
    local H = art.h
    local r, y0 = 2.5, 2.0
    local zc = 9 + y0 + r * sqrt(2)
    local sec = { { 37, 0 }, { 37, y0 } }
    for k = 0, 8 do sec[#sec + 1] = { zc + r * cos(pi * k / 8), y0 + r * sin(pi * k / 8) } end
    sec[#sec + 1] = { zc - r, 0 }
    return { ProjSection("mat", sec, 0, 16, { grown = 2 * H, graze = 0.6 }) }, withRing(art, {})
  end

  local function abandoned_ship(art)
    local tex = withRing(art, {})
    local vol = Volume():slab(44, 34, 43, 10, -1, 8, 4.0)
    vol:box(22, 61, 0, 15, 25, 44)
    vol:box(61, 75, 0, 11, 23, 44)
    vol:box(29, 51, 0, 2, 47, 56)
    vol:slab(45, 45.2, 43, 3.2, 0, 0.3, 8.0)
    return { HeightSolid("wreck", tex, art.h, vol, { depth = { 0.0, 64.0 }, step = 1, mirror_z = 34 }) }, tex
  end

  -- ── Mauville's Game Corner ────────────────────────────────────────────────

  local function game_corner(art)
    local tex = withRing(art, {})
    local W = art.w
    local px = tex.px
    local function set(x, v, sx, sv)
      local d, s = (v * W + x) * 4, (sv * W + sx) * 4
      for c = 1, 4 do px[d + c] = px[s + c] end
    end
    for x = 0, W - 1 do
      if x < 8 or x >= W - 8 then
        for v = 0, 7 do set(x, v, x, v + 8) end
      end
    end
    for x = 0, W - 1 do
      if px[x * 4 + 4] < 0.5 then set(x, 0, 8, 0) end
    end
    local parts = flat_block(112, 64, { { 3, 26 }, { 8, 16 }, { 0, 3 } }, { 26, 32 }, 32,
      { brick = { 8, 40, 16, 56 }, rim = { 16, 26, 24, 32 } })
    local function portal(u, v) return u >= 40 and u < 72 and v >= 32 and v < 72 end
    parts[#parts + 1] = HeightSolid("portal", tex, art.h,
      Volume():profile({ { 64, 0 }, { 72, 0 }, { 72, 40 }, { 64, 32 } }, 40, 72),
      { depth = { 0.0, 80.0 }, step = 2, mirror_z = 68, mask = function(u, v) return not portal(u, v) end,
        side = { 40, 48, 72 } })
    return parts, tex
  end

  -- ── small round things ────────────────────────────────────────────────────

  local function small_round(name, volume, o)
    o = o or {}
    local depth = o.depth or 16.0
    return function(art)
      local tex = withRing(art, {})
      return { HeightSolid(name, tex, art.h, volume, { depth = { 0.0, depth }, step = o.step or 1,
        mirror_z = depth / 2, cell = o.cell or 2, tol = o.tol or 1, hang = o.hang, side = o.side,
        open_top = o.open_top }) }, tex
    end
  end

  local function flower_box(art)
    local H = art.h
    return grownAll({ PlanPrism("box", { { 0, 8 }, { 16, 8 }, { 16, 32 }, { 0, 32 } }, 0, 8, { 2, 12, 32 }) }, H),
      withRing(art, {})
  end

  -- ── Pacifidlog ────────────────────────────────────────────────────────────

  local HUT_THATCH = rgbSet({ { 180, 189, 123 }, { 222, 230, 164 }, { 90, 98, 41 }, { 156, 164, 98 }, { 131, 139, 74 } })

  local function pacifidlog_hut(art)
    local tex = withRing(art, {})
    local H = art.h
    local function own(u, v)
      if not drawn(art, u, v) then return nil end
      return (v < 37 or rgbIn(art, u, v, HUT_THATCH)) and "thatch" or "wall"
    end
    local band
    tex, band = ownBands(tex, H, bandsOf(own, { "thatch", "wall" }))
    local L = 21.0
    local function other(n)
      return function(u, v)
        local o = own(u, v)
        return o ~= nil and o ~= n
      end
    end
    local wall = Volume():slab(24, 52.5, 21, 11, 0, 20.5, 8.0)
    local thatch = Volume():lathe(24, 51 - L, { { 0, 25.5 }, { 3, 25.5 }, { 4, 24 }, { 16, 2.5 }, { 17.5, 0 } }, 0.54)
      :lathe(24, 51 - L, { { 13, 3.5 }, { 19, 3.5 }, { 21, 7 }, { 28, 7 }, { 31, 4 }, { 33, 0 } })
    local parts = {}
    for _, it in ipairs({ { "wall", wall, 0.0 }, { "thatch", thatch, L } }) do
      local name, vol, lift = it[1], it[2], it[3]
      parts[#parts + 1] = HeightSolid("hut_" .. name, tex, H, vol, { depth = { 0.0, H }, step = 1,
        mirror_z = 51 - lift, cell = 2, band = band[name], lift = lift,
        side = name == "wall" and { 4, 10 } or nil,
        mask = name == "wall" and other(name) or nil,
        behind = name == "thatch" and other(name) or nil })
    end
    return parts, tex
  end

  -- ── Sootopolis ────────────────────────────────────────────────────────────

  local SOOTOPOLIS_ROCK = rgbSet({ { 205, 205, 189 }, { 222, 222, 213 }, { 246, 246, 238 }, { 148, 148, 123 },
    { 172, 172, 156 }, { 131, 131, 139 } })
  local CRATER_ROCK = rgbSet({ { 189, 148, 139 }, { 222, 180, 164 }, { 156, 115, 115 }, { 238, 213, 205 } })
  local SOOTOPOLIS_GROUND = { 0x2D9, 0x2E1, 0x2E2, 0x2D3, 0x2DA }
  local SPIRE_PLAN = { { 13, 39 }, { 35, 39 }, { 44, 50 }, { 44, 65 }, { 37, 73 }, { 11, 73 }, { 4, 65 }, { 4, 50 } }
  local SPIRE_APEX = { 24, 48, 56 }

  local function spire_parts(gate_side)
    local base
    if gate_side == nil then
      base = { PlanPrism("base", octagon(0, 48, 40, 79, 8), 0, 22, { 9, 16, 79 }) }
    else
      local side = gate_side
      local whole = { { 8, 40 }, { 40, 40 }, { 48, 48 }, { 48, 71 }, { 40, 79 }, { 40, 80 }, { 8, 80 }, { 8, 79 },
                      { 0, 71 }, { 0, 48 } }
      local notched = {}
      for i = 1, 6 do notched[#notched + 1] = whole[i] end
      for _, p in ipairs({ { 32, 80 }, { 32, 76 }, { 16, 76 }, { 16, 80 } }) do notched[#notched + 1] = p end
      for i = 7, #whole do notched[#notched + 1] = whole[i] end
      base = { PlanPrism("base", notched, 0, 17, side, { open_top = true }),
               PlanPrism("lintel", whole, 17, 22, side),
               PlanPrism("step", { { 16, 76 }, { 32, 76 }, { 32, 80 }, { 16, 80 } }, 0, 1, side) }
    end
    base[#base + 1] = PlanPyramid("spire", SPIRE_PLAN, 22, SPIRE_APEX)
    return base
  end

  local function sootopolis_spire(art)
    local H = clearRgb(art, SOOTOPOLIS_ROCK).h
    return grownAll(spire_parts(), H), withRing(art, {})
  end

  local function sootopolis_spire_gate(art, ctx)
    local H = clearRgb(art, SOOTOPOLIS_ROCK).h
    local window = ctx and ctx.layoutArt and ctx.layoutArt("LAYOUT_SOOTOPOLIS_CITY", 22, 1, 3, 5, SOOTOPOLIS_GROUND)
    if not window then error("no reference spire house") end
    clearRgb(window, SOOTOPOLIS_ROCK)
    local tex = withRing(art, {})
    local out = blank(tex.w, tex.h + 24)
    paste(out, tex, 0, 0)
    paste(out, window, 0, 3 * H, 9, 57, 16, 80)
    return grownAll(spire_parts({ 0, 7, H + 23 }), H), out
  end

  local function sootopolis_flat_house(gate)
    return function(art)
      local H = clearRgb(art, SOOTOPOLIS_ROCK).h
      local parts
      if not gate then
        parts = { PlanPrism("house", { { 0, 33 }, { 48, 33 }, { 48, 64 }, { 0, 64 } }, 0, 33, { 8, 15, 64 }),
                  PlanPrism("roof", { { 5, 42 }, { 43, 42 }, { 43, 62 }, { 5, 62 } }, 33, 37, { 8, 15, 64 }) }
      else
        parts = { PlanPrism("house", { { 0, 29 }, { 48, 29 }, { 48, 60 }, { 0, 60 } }, 0, 29, { 3, 6, 60 }),
                  PlanPrism("roof", { { 5, 38 }, { 43, 38 }, { 43, 58 }, { 5, 58 } }, 29, 33, { 3, 6, 60 }),
                  PlanPrism("frame", { { 9, 60 }, { 39, 60 }, { 39, 62 }, { 9, 62 } }, 0, 22, { 12, 15, 62 }),
                  PlanPrism("bay", { { 16, 60 }, { 32, 60 }, { 32, 64 }, { 16, 64 } }, 0, 29, { 3, 6, 64 }),
                  PlanPrism("plinth", { { 0, 60 }, { 48, 60 }, { 48, 64 }, { 0, 64 } }, 0, 1, { 3, 6, 64 }) }
      end
      return grownAll(parts, H), withRing(art, {})
    end
  end

  local function sootopolis_posts(art)
    clearRgb(art, CRATER_ROCK)
    local H = art.h
    local parts = {}
    for _, z in ipairs({ 0, 16 }) do
      for _, x in ipairs({ 0, 8 }) do
        parts[#parts + 1] = PlanPrism("post", { { x, z + 8 }, { x + 8, z + 8 }, { x + 8, z + 16 }, { x, z + 16 } }, 0, 8,
          { x + 1, x + 7, z + 16 })
      end
    end
    return grownAll(parts, H), withRing(art, {})
  end

  -- the Cave of Origin's doorway: its whole drawing (the cliff's rows too), less the rock round the
  -- frame and the cliff inside it
  local function cave_origin(_, ctx)
    local ground = { 0x071 }
    for _, g in ipairs(SOOTOPOLIS_GROUND) do ground[#ground + 1] = g end
    local art = ctx and ctx.layoutArt and ctx.layoutArt("LAYOUT_SOOTOPOLIS_CITY", 29, 15, 5, 4, ground)
    if not art then error("no reference doorway") end
    clearRgb(art, SOOTOPOLIS_ROCK)
    for v = 0, art.h - 1 do
      for u = 0, art.w - 1 do
        if (drawn(art, u, v) and rgbIn(art, u, v, CRATER_ROCK)) or (u >= 16 and u < 64 and v >= 9 and v < 32) then
          clearPx(art, u, v)
        end
      end
    end
    local H = art.h
    local side = { 11, 15, 62 }
    local top, beam = 25, 18
    local parts = { PlanPrism("lintel", { { 9, 32 }, { 71, 32 }, { 71, 34 }, { 9, 34 } }, top, 32, side),
                    PlanPrism("front", { { 9, 57 }, { 71, 57 }, { 71, 62 }, { 9, 62 } }, beam, top, side) }
    for _, x in ipairs({ { 9, 16 }, { 64, 71 } }) do
      parts[#parts + 1] = PlanPrism("beam", { { x[1], 34 }, { x[2], 34 }, { x[2], 57 }, { x[1], 57 } }, beam, top, side)
      parts[#parts + 1] = PlanPrism("leg", { { x[1], 57 }, { x[2], 57 }, { x[2], 62 }, { x[1], 62 } }, 0, beam, side)
    end
    return grownAll(parts, H), withRing(art, {})
  end

  -- ── Ever Grande's Pokemon League ──────────────────────────────────────────

  local LEAGUE_FACADE = rgbSet({ { 238, 156, 90 }, { 246, 197, 123 }, { 164, 90, 49 }, { 205, 115, 41 } })

  local function pokemon_league(art)
    local H = art.h
    for v = 0, H - 1 do
      for u = 0, art.w - 1 do
        if (u < 16 and v > 80 + u) or (u >= 160 and v > 80 + (175 - u)) then
          if v < 96 then clearPx(art, u, v) end
        end
      end
    end
    local tex = withRing(art, {})
    local function own(u, v)
      if not drawn(art, u, v) then return nil end
      if v >= 96 and (u < 48 or u >= 128) then return "bush" end
      if u >= 48 and u < 128 and v >= 47 and v < 77 and not rgbIn(art, u, v, LEAGUE_FACADE) then return "canopy" end
      if v >= 94 and u >= 40 and u < 136 then return "dais" end
      return "block"
    end
    local band
    tex, band = ownBands(tex, H, bandsOf(own, { "block", "canopy", "dais", "bush" }))
    local function other(n)
      return function(u, v)
        local o = own(u, v)
        return o ~= nil and o ~= n
      end
    end
    local L = 35.0
    local COLS = { { 51, 61 }, { 63, 74 }, { 102, 113 }, { 115, 125 } }
    local columns = Volume()
    for _, cx in ipairs({ 56, 68, 108, 120 }) do columns:lathe(cx, 96, { { 0, 5.5 }, { L + 1, 5.5 } }, 0.55) end
    local canopy = Volume():slab(88, 96 - L, 41, 16, 0, 13.5, 2.0)
    local dais = Volume():slab(88, 96, 46, 28.5, 0, 3.5, 2.0)
    dais:hollow("box", 0, 176, -1, 10, 0, 97.5)
    local bush = Volume()
    for _, cx in ipairs({ 24, 40, 136, 152 }) do
      for _, vb in ipairs({ 111, 127 }) do bush:dome(cx, vb - 6, 8, 6.5, 8.5) end
    end
    local parts = { Grown(PlanPrism("league_block", { { 16, 24 }, { 160, 24 }, { 176, 40 }, { 176, 80 }, { 160, 96 },
      { 16, 96 }, { 0, 80 }, { 0, 40 } }, 0, 160, { 24, 40, 96 }, { top = Tile(100, 20, 116, 30) }), 2 * H) }
    local function column(u, v)
      if not (v >= 76 and v < 94) then return false end
      for _, c in ipairs(COLS) do
        if u >= c[1] and u < c[2] then return own(u, v) == "block" end
      end
      return false
    end
    parts[#parts + 1] = HeightSolid("league_columns", tex, H, columns, { depth = { 0.0, H }, step = 1,
      mirror_z = 96.0, cell = 2, band = band.block,
      mask = function(u, v) local o = own(u, v) return o == "canopy" or o == "dais" end,
      behind = function(u, v) local o = own(u, v) return (o == "block" or o == "bush") and not column(u, v) end })
    for _, it in ipairs({ { "canopy", canopy, L, 61.0, 1, 2 }, { "dais", dais, 0.0, 96.0, 2, 4 },
                          { "bush", bush, 0.0, 110.0, 1, 2 } }) do
      local name = it[1]
      parts[#parts + 1] = HeightSolid("league_" .. name, tex, H, it[2], { depth = { 0.0, H }, step = it[5],
        mirror_z = it[4], cell = it[6], band = band[name], lift = it[3],
        mask = name ~= "canopy" and other(name) or nil,
        behind = name == "canopy" and other(name) or nil })
    end
    return parts, tex
  end

  -- ── the Battle Frontier ───────────────────────────────────────────────────

  local DOME_BOXES = { { 24, 184, 24, 170, 216 }, { 40, 168, 48, 160, 200 }, { 80, 128, 30, 196, 224 } }

  local function battle_dome(art)
    local tex = withRing(art, {})
    local H = art.h
    local cx, cz, rx, rz, hh = 104.0, 146.0, 98.0, 70.0, 92.0
    local vol = Volume():dome(cx, cz, rx, rz, hh, 2.6)
    for _, x in ipairs({ 72.0, 88.0, 104.0, 120.0, 136.0 }) do
      local pts = {}
      for z = floor(cz - 60), floor(cz + 61) - 1, 15 do
        local q = 1.0 - ((z - cz) / rz) ^ 2 - ((x - cx) / rx) ^ 2
        pts[#pts + 1] = { x, hh * sqrt(max(0.0, q)) + 2.0, z }
      end
      vol:tube(pts, 8.5, 16)
    end
    vol:hollow("box", 20, 188, -1, 24, 168, 230)
    vol:hollow("box", 36, 172, -1, 48, 158, 230)
    local function boxed(u, v)
      for _, b in ipairs(DOME_BOXES) do
        if u >= b[1] and u < b[2] and v >= b[4] - b[3] and v < b[5] then return true end
      end
      return false
    end
    local parts = {}
    for _, b in ipairs(DOME_BOXES) do
      local x0, x1, bh, z0, z1 = b[1], b[2], b[3], b[4], b[5]
      parts[#parts + 1] = Grown(PlanPrism("dome_box", { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } }, 0, bh,
        { x0 + 4, x0 + 12, z1 }), 2 * H)
    end
    parts[#parts + 1] = HeightSolid("dome_shell", tex, H, vol, { depth = { 0.0, H }, step = 2, mirror_z = cz,
      side = { 40, 48, 150 }, cell = 4, mask = function(u, v) return drawn(art, u, v) and boxed(u, v) end })
    return parts, tex
  end

  local PIKE_TAIL_ROWS, PIKE_TAIL_Z = 74, 132
  local function pike_tail(u, v) return v < 59 or (u >= 60 and v < PIKE_TAIL_ROWS) end

  local function battle_pike_volume()
    local vol = Volume()
    vol:dome(40, 150, 32, 60, 86, 3.0)
    vol:dome(40, 176, 34, 32, 56, 3.0)
    for _, d in ipairs({ { 8, 104, 30 }, { 72, 104, 30 }, { 9, 128, 26 }, { 71, 128, 26 }, { 9, 152, 26 },
                         { 71, 152, 26 } }) do
      vol:dome(d[1], d[2], 9, 12, d[3])
    end
    return vol
  end

  -- a flat thing standing up across the plan: a card at depth z facing the view, its drawing read
  -- `voff` rows down, back to back
  local function Blade(name, u0, u1, z, y0, y1, voff)
    return { name = name, emit = function(_, mesh)
      local quad = { { u0, y0 }, { u1, y0 }, { u1, y1 }, { u0, y1 } }
      local front, back = {}, {}
      for k, p in ipairs(quad) do front[k] = { p[1], p[2], z, p[1], z - p[2] + voff } end
      for k = 1, 4 do back[k] = front[5 - k] end
      mesh:poly(front, SHADE_ART, name .. ".card")
      mesh:poly(back, SHADE_ART, name .. ".card")
    end }
  end

  local function battle_pike(art)
    local H, W = art.h, art.w
    local tex = withRing(art, {})
    local band
    tex, band = ownBands(tex, H, { { "body", function(u, v) return not pike_tail(u, v) end } })
    local out = blank(W, tex.h + PIKE_TAIL_ROWS)
    paste(out, tex, 0, 0)
    local umin, umax, top = math.huge, -math.huge, math.huge
    for v = 0, PIKE_TAIL_ROWS - 1 do
      for u = 0, W - 1 do
        if drawn(art, u, v) and pike_tail(u, v) then
          paste(out, art, u, tex.h + v, u, v, u + 1, v + 1)
          umin, umax, top = min(umin, u), max(umax, u), min(top, v)
        end
      end
    end
    local body = HeightSolid("pike", out, H, battle_pike_volume(), { depth = { 0.0, 208.0 }, step = 2,
      mirror_z = 150.0, cell = 2, tol = 1, mask = pike_tail, band = band.body, side = { 30, 36, 112 } })
    local blade = Blade("pike_tail", umin, umax + 1, PIKE_TAIL_Z, PIKE_TAIL_Z - PIKE_TAIL_ROWS, PIKE_TAIL_Z - top, tex.h)
    return { body, blade }, out
  end

  -- ── Mossdeep's Space Center ───────────────────────────────────────────────

  -- whether the 45-degree ray through pixel (u, v) meets the volume
  local function silhouette(vol, u, v, depth)
    for z = floor(v), floor(v) + depth - 1 do
      if vol:inside(u + 0.5, z - v - 0.5, z) then return true end
    end
    return false
  end

  local function space_center(art)
    local tex = withRing(art, {})
    local H = art.h
    local L = 83.0
    local domes = Volume():dome(36, 202.5 - L, 20, 16.5, 16.5):dome(104, 201 - L, 19, 14.5, 14.5, 3.0)
      :dome(134, 218 - L, 7, 5.5, 5.5)
    local roofish = {}
    local function on_roof(u, v)
      local key = v * 4096 + u
      local r = roofish[key]
      if r == nil then
        r = v >= 96 and silhouette(domes, u, v, 160)
        roofish[key] = r
      end
      return r
    end
    local TOWERS = { { 15, 33 }, { 95, 113 } }
    local function own(u, v)
      if v >= 96 then return on_roof(u, v) and "domes" or "block" end
      if ((u >= 32 and u < 48) or (u >= 80 and u < 96)) and v < 50 then return v < 30 and "arm_hi" or "arm_lo" end
      for _, t in ipairs(TOWERS) do if u >= t[1] and u < t[2] then return "tower" end end
      return "pad"
    end
    local band
    tex, band = ownBands(tex, H, bandsOf(own, { "domes", "pad", "arm_hi", "arm_lo" }))
    local parts = { Grown(PlanPrism("space_block", { { 8, 179 }, { 136, 179 }, { 144, 187 }, { 144, 224 }, { 0, 224 },
      { 0, 187 } }, 0, 83, { 2, 8, 224 }), 2 * H) }
    for _, t in ipairs(TOWERS) do
      local a, b = t[1], t[2]
      parts[#parts + 1] = Grown(PlanPrism("space_tower", { { a, 82 }, { b, 82 }, { b, 96 }, { a, 96 } }, 0, 96,
        { a + 2, a + 6, 96 }, { top = Tile(a + 2, 2, a + 6, 6) }), 2 * H)
    end
    local pad = Volume():lathe(64, 84, { { 0, 13 }, { 12, 10 }, { 16, 8.5 }, { 58, 8.5 }, { 66, 5 }, { 74, 1 }, { 75, 0 } })
      :box(50, 78, 0, 12, 80, 97):box(32, 49, 0, 33, 84, 96)
    local arm = Volume():box(31, 49, 0, 5, 0, 60):box(79, 97, 0, 5, 0, 60)
    for _, it in ipairs({ { "domes", domes, 201.0 - L, 1, 2, L }, { "pad", pad, 89.0, 1, 2, 0.0 },
                          { "arm_hi", arm, 11.0, 1, 4, 77.0 }, { "arm_lo", arm, 43.0, 1, 4, 46.0 } }) do
      local name = it[1]
      local function other(u, v) return drawn(art, u, v) and own(u, v) ~= name end
      parts[#parts + 1] = HeightSolid("space_" .. name, tex, H, it[2], { depth = { 0.0, H }, step = it[4],
        mirror_z = it[3], cell = it[5], tol = 1, band = band[name], lift = it[6],
        mask = name ~= "domes" and other or nil, behind = name == "domes" and other or nil })
    end
    return parts, tex
  end

  -- The stone lantern in Slateport's square (art 32x64, its foot at v 63): a turned thing on a
  -- plan 0.7 as deep as wide (the GBA draws its rings as flat ellipses) - a bell for a base with
  -- the keyhole, a neck, a drum with its windows, a capped top. The profile is fitted to the
  -- drawing's outline row by row; the cubes are carved to it. Stood half a cell north of where it
  -- is drawn, in the middle of its lawn. A low-poly lathe (32 sides) with its texture baked off
  -- the true-cube model: its faces turned to the GBA's view read the drawing itself.
  local LANTERN = { { 0, 12.5 }, { 2, 14 }, { 5, 16 }, { 7, 16 }, { 8, 14 }, { 10, 14 }, { 11, 12 }, { 13, 10 },
                    { 21, 10 }, { 22, 12.5 }, { 24, 14 }, { 26, 16 }, { 30, 16 }, { 32, 14 }, { 33, 12 },
                    { 41, 12 }, { 42, 9.5 }, { 44, 8 }, { 45, 6.5 }, { 45.5, 0 } }
  local LANTERN_Z, LANTERN_SQUASH, LANTERN_BACK = 55.3, 0.7, 8
  local function lantern(art)
    local W, H = art.w, art.h
    local function isDrawn(u, v) return u >= 0 and u < W and v >= 0 and v < H and drawn(art, u, v) end
    local cubes = K.VoxelLathe("lantern", art, isDrawn, 16.0, LANTERN_Z, LANTERN, LANTERN_SQUASH, 64,
      function(y) return y >= 33.0 and 4.0 or 2.0 end)
    local baked = K.BakedLathe("lantern", cubes, 32, -LANTERN_BACK)
    return { baked }, baked.texture()
  end

  -- Rustboro's fountain (48 x 48), as its drawing tells it: the basin's outer wall 5 px (the
  -- plan below its foot, the outline drawn round it); the rim's top at that height, in to the
  -- pool's edge; the pool's water 2 px lower; the dish in the middle, its top 5 px over the water,
  -- its edge 2 px, on a stem the dish hides; the grey under it its shadow on the water; the jet
  -- standing on the dish, rows 8-16 - the only thing that moves.
  local FOUNTAIN_FOOT = { { 11, 7 }, { 37, 7 }, { 47, 17 }, { 47, 34 }, { 35, 46 }, { 13, 46 }, { 1, 34 }, { 1, 17 } }
  local FOUNTAIN_POOL = { { 15, 10 }, { 33, 10 }, { 40, 17 }, { 40, 32 }, { 32, 40 }, { 16, 40 }, { 8, 32 }, { 8, 17 } }
  local FOUNTAIN_RIM, FOUNTAIN_WATER, FOUNTAIN_DISH = 5, 3, 8
  local DISH_AT, DISH_R, DISH_EDGE, STEM_R = { 24.0, 25.0 }, { 9.0, 6.0 }, 2, { 3.0, 2.2 }
  -- the jet: columns 19-28 of rows 8-16, drawn with Rustboro's animated upper-layer tiles
  local JET_COLUMNS, JET_ROWS = { 19, 29 }, { 8, 17 }
  local JET_BAND = 48       -- the texture's row the jet's first row is laid on

  --- A flat ring at height `y` between two plan polygons of as many corners (a basin's rim), or
  --- with `inner` nil the whole of `outer` (its water). Projected: the drawing at 45 degrees.
  local function PlanRing(name, outer, inner, y)
    return { name = name, emit = function(_, mesh)
      local function pt(p) return { p[1], y, p[2], p[1], p[2] - y } end
      if not inner then
        local poly = {}
        for i, p in ipairs(outer) do poly[i] = pt(p) end
        mesh:poly(poly, SHADE_ART, name .. "~proj")
        return
      end
      for k = 1, #outer do
        local k1 = k % #outer + 1
        mesh:poly({ pt(outer[k]), pt(outer[k1]), pt(inner[k1]), pt(inner[k]) }, SHADE_ART, name .. "~proj")
      end
    end }
  end

  --- A flat ellipse at height `y` of one colour, the drawing's texel `texel`: a dish's shadow
  --- under the dish (the water there, projected, would read the dish's own pixels).
  local function Shade(name, cx, cz, rx, rz, y, texel, sides)
    sides = sides or 24
    return { name = name, emit = function(_, mesh)
      local u, v = texel[1] + 0.5, texel[2] + 0.5
      local ring = {}
      for k = 0, sides - 1 do
        ring[k + 1] = { cx + rx * cos(2 * pi * k / sides), y, cz + rz * sin(2 * pi * k / sides), u, v }
      end
      mesh:poly(ring, SHADE_ART, name .. "~behind~clamp")
    end }
  end

  --- The fountain's jet: a card standing across the dish at depth `z`, from the dish's top `y0`
  --- up, over the drawing's columns, each point reading the pixel it covers at 45 degrees moved
  --- down `band` rows to where the jet is laid alone.
  local function Jet(name, columns, z, y0, band)
    local y1 = z - JET_ROWS[1]
    assert(abs((z - JET_ROWS[2]) - y0) < 1e-6, name .. ": the card's foot is not the dish's top")
    return { name = name, emit = function(_, mesh)
      local x0, x1 = columns[1], columns[2]
      local quad = { { x0, y0, z }, { x1, y0, z }, { x1, y1, z }, { x0, y1, z } }
      local pts = {}
      for i, p in ipairs(quad) do pts[i] = { p[1], p[2], p[3], p[1], p[3] - p[2] + band } end
      mesh:poly(pts, SHADE_ART, name .. "~live")
    end }
  end

  --- The fountain in 3D, and its texture: the drawing with the jet taken out of it (the pool and
  --- the dish as they lie behind it), and the jet alone on a band below, read by a card standing
  --- on the dish. The jet's two frames come from the game's own tile animation.
  local function fountain(art, ctx)
    local W = art.w
    -- the jet's pixels in each frame
    local frames = { [0] = {}, [1] = {} }
    local cellsF = {}
    for y = JET_ROWS[1], JET_ROWS[2] - 1 do
      for x = JET_COLUMNS[1], JET_COLUMNS[2] - 1 do
        local cx, cy = floor(x / 16), floor(y / 16)
        local key = cx .. "," .. cy
        if cellsF[key] == nil then cellsF[key] = (ctx.animFrames and ctx.animFrames(cx, cy)) or false end
        local fr = cellsF[key]
        if not (fr and fr[0] and fr[1]) then error("rustboro_fountain: the jet's cell " .. key .. " does not move", 0) end
        for f = 0, 1 do
          local r, g, b = fr[f](x % 16, y % 16)
          if not r then error(("rustboro_fountain: the jet's pixel %d,%d is clear in frame %d"):format(x, y, f), 0) end
          frames[f][y * W + x] = { r, g, b }
        end
      end
    end
    local function same(a, b) return key5(a[1], a[2], a[3]) == key5(b[1], b[2], b[3]) end
    -- what lies behind the jet: above the dish the pool's own lines; on the dish its water,
    -- wherever the two frames differ or draw the jet's white and blue (down its middle)
    local jet = {}
    for f = 0, 1 do
      for _, x in ipairs({ 23, 24 }) do
        for y = 9, JET_ROWS[2] - 1 do
          local c = frames[f][y * W + x]
          jet[key5(c[1], c[2], c[3])] = true
        end
      end
    end
    local dishWater = frames[0][11 * W + 21]
    local rows = JET_ROWS[2] - JET_ROWS[1]
    local tex = blank(W, JET_BAND + rows)
    paste(tex, art, 0, 0, 0, 0, art.w, art.h)
    local tp = tex.px
    -- the band's texels in each frame (the game redraws them: `live`)
    local texels = {}
    for y = JET_ROWS[1], JET_ROWS[2] - 1 do
      for x = JET_COLUMNS[1], JET_COLUMNS[2] - 1 do
        local a, b = frames[0][y * W + x], frames[1][y * W + x]
        local bg
        if y < 11 then
          bg = frames[0][y * W + JET_COLUMNS[1]]
        else
          bg = (same(a, b) and not jet[key5(a[1], a[2], a[3])]) and a or dishWater
        end
        local o = (y * W + x) * 4
        tp[o + 1], tp[o + 2], tp[o + 3], tp[o + 4] = bg[1], bg[2], bg[3], 1
        local d = ((JET_BAND + y - JET_ROWS[1]) * W + x) * 4
        if not same(a, bg) then
          tp[d + 1], tp[d + 2], tp[d + 3], tp[d + 4] = a[1], a[2], a[3], 1
        end
        local t = #texels
        texels[t + 1], texels[t + 2] = x, JET_BAND + y - JET_ROWS[1]
        for f = 0, 1 do
          local c = frames[f][y * W + x]
          local o2 = t + 3 + 4 * f
          if same(c, bg) then
            texels[o2], texels[o2 + 1], texels[o2 + 2], texels[o2 + 3] = 0, 0, 0, 0
          else
            texels[o2], texels[o2 + 1], texels[o2 + 2], texels[o2 + 3] = c[1], c[2], c[3], 1
          end
        end
      end
    end
    local parts = {
      PlanPrism("basin", FOUNTAIN_FOOT, 0, FOUNTAIN_RIM, { 14, 34, 46 }, { open_top = true }),
      PlanRing("rim", FOUNTAIN_FOOT, FOUNTAIN_POOL, FOUNTAIN_RIM),
      PlanPrism("pool", FOUNTAIN_POOL, FOUNTAIN_WATER, FOUNTAIN_RIM, { 16, 32, 7 }, { open_top = true, inward = true }),
      PlanRing("water", FOUNTAIN_POOL, nil, FOUNTAIN_WATER),
      K.Cylinder("dish", DISH_AT[1], DISH_AT[2], DISH_R[1], DISH_R[2], FOUNTAIN_DISH - DISH_EDGE, FOUNTAIN_DISH,
        Tile(21, 23, 27, 25), { sides = 24 }),
      K.Cylinder("stem", DISH_AT[1], DISH_AT[2], STEM_R[1], STEM_R[2], FOUNTAIN_WATER, FOUNTAIN_DISH - DISH_EDGE,
        Tile(18, 25, 30, 28), { sides = 12, proj = false }),
      -- under the dish, a little over the water: inside what the dish hides at 45 degrees, its
      -- shadow's grey
      Shade("dish_shadow", DISH_AT[1], DISH_AT[2] - (FOUNTAIN_DISH - FOUNTAIN_WATER) + 1.25,
        DISH_R[1] - 0.5, DISH_R[2] + 0.5, FOUNTAIN_WATER + 0.25, { 24, 25 }),
      Jet("jet", JET_COLUMNS, DISH_AT[2], FOUNTAIN_DISH, JET_BAND - JET_ROWS[1]),
    }
    return parts, tex, { cell = { floor(JET_COLUMNS[1] / 16), floor(JET_ROWS[1] / 16) }, frames = 2, texels = texels }
  end

  -- ── the specs ─────────────────────────────────────────────────────────────

  local SOOTO_GROUND = SOOTOPOLIS_GROUND
  local CAVE_OWNED = {}
  for j = 2, 3 do for i = 0, 4 do CAVE_OWNED[i .. "," .. j] = true end end

  local list = {
    { name = "battle_tent", layout = "LAYOUT_SLATEPORT_CITY", rect = { 8, 8, 5, 5 }, ground = { GRASS }, ground_px = true,
      ground_fixed = { LAYOUT_SLATEPORT_CITY = GRASS }, patch_own = true,
      match_rows = { 1, 5 }, lod = { 6, 6, 3 }, parts_art = battle_tent },
    { name = "sailboat", layout = "LAYOUT_SLATEPORT_CITY", rect = { 34, 44, 3, 3 }, ground = { 0x170 }, ground_px = true,
      ground_fixed = true,
      clip_art = true, parts_art = sailboat() },
    { name = "sailboat_cut", layout = "LAYOUT_SLATEPORT_CITY", rect = { 36, 37, 3, 2 }, ground = { 0x170 }, ground_px = true,
      ground_fixed = true,
      clip_art = true, parts_art = sailboat({ 0 }, -6) },
    { name = "sailboat_pair", layout = "LAYOUT_SLATEPORT_CITY", rect = { 33, 35, 3, 4 }, ground = { 0x170 }, ground_px = true,
      ground_fixed = true, patch_cells = gridCells({ 0, 1, 2 }, { 0 }),
      clip_art = true, keep = { { 0, 8, 48, 64 } }, parts_art = sailboat({ 8, 24 }) },
    { name = "rowboat", layout = "LAYOUT_SLATEPORT_CITY", rect = { 21, 35, 3, 2 }, ground = { GRASS }, ground_px = true,
      clip_art = true, parts_art = rowboat },
    { name = "parasol", layout = "LAYOUT_ROUTE109", rect = { 9, 6, 2, 3 }, ground = { 0x124 }, ground_px = true,
      ground_rgb = PARASOL_SHADOW, parts_art = parasol },
    { name = "parasol_blue", layout = "LAYOUT_ROUTE109", rect = { 18, 4, 2, 3 }, ground = { 0x124 }, ground_px = true,
      ground_rgb = PARASOL_SHADOW, parts_art = parasol },
    { name = "parasol_green", layout = "LAYOUT_ROUTE109", rect = { 13, 14, 2, 3 }, ground = { 0x124 }, ground_px = true,
      ground_rgb = PARASOL_SHADOW, parts_art = parasol },
    { name = "sun_lounger", layout = "LAYOUT_ROUTE109", rect = { 17, 8, 1, 3 }, ground = { 0x124 }, ground_px = true,
      parts_art = sun_lounger },
    { name = "beach_mat", layout = "LAYOUT_ROUTE109", rect = { 9, 9, 1, 3 }, ground = { 0x124 }, ground_px = true,
      parts_art = beach_mat },
    { name = "abandoned_ship", layout = "LAYOUT_ROUTE108", rect = { 27, 3, 6, 4 },
      patch_cells = gridCells({ 0, 1, 2, 3, 4, 5 }, { 3 }),
      ground = { 0x19E, 0x194, 0x1BE, 0x1BD, 0x1A3, 0x1A4, 0x170 }, ground_px = true,
      keep = { { 0, 0, 80, 64 }, { 80, 19, 96, 64 } }, parts_art = abandoned_ship },
    { name = "game_corner", layout = "LAYOUT_MAUVILLE_CITY", rect = { 5, 10, 7, 5 }, ground = { GRASS, 0x004 },
      keep = { { 0, 0, 112, 64 }, { 40, 64, 48, 72 }, { 64, 64, 72, 72 } }, parts_art = game_corner },
    { name = "battle_tent_verdanturf", layout = "LAYOUT_VERDANTURF_TOWN", rect = { 1, 3, 5, 5 }, ground = { GRASS },
      relief_bare = true,
      ground_px = true, lod = { 6, 6, 3 }, parts_art = battle_tent_elsewhere },
    { name = "verdanturf_flower_box", layout = "LAYOUT_VERDANTURF_TOWN", rect = { 0, 15, 1, 2 },
      ground = { GRASS, 0x204, 0x205 }, ground_px = true, parts_art = flower_box },
    { name = "sand_bath", layout = "LAYOUT_LAVARIDGE_TOWN", rect = { 3, 8, 1, 2 }, ground = { 0x2A8 }, ground_px = true,
      parts_art = small_round("sand_bath", Volume():dome(8, 20, 7.5, 7, 7), { depth = 32.0 }) },
    { name = "pacifidlog_hut", layout = "LAYOUT_PACIFIDLOG_TOWN", rect = { 1, 9, 3, 4 }, ground = { 0x221, 0x170 },
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3 }),
      ground_px = true, lod = { 4, 4, 2 }, keep = { { 0, 0, 48, 35 }, { 2, 35, 46, 37 }, { 3, 37, 45, 64 } },
      parts_art = pacifidlog_hut },
    { name = "sootopolis_spire_house", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 22, 1, 3, 5 }, ground = SOOTO_GROUND,
      relief_bare = true,
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3, 4 }),
      ground_px = true, parts_art = sootopolis_spire },
    { name = "sootopolis_house", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 2, 6, 3, 4 }, ground = SOOTO_GROUND,
      relief_bare = true,
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3 }),
      ground_px = true, parts_art = sootopolis_flat_house(false) },
    { name = "sootopolis_house_window", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 30, 1, 3, 4 }, ground = SOOTO_GROUND,
      relief_bare = true,
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3 }),
      ground_px = true, parts_art = sootopolis_flat_house(false) },
    { name = "sootopolis_gate_house", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 47, 22, 3, 4 }, ground = SOOTO_GROUND,
      relief_bare = true,
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3 }),
      ground_px = true, parts_art = sootopolis_flat_house(true) },
    { name = "sootopolis_spire_house_door", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 53, 15, 3, 5 },
      relief_bare = true,
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3, 4 }),
      ground = SOOTO_GROUND, ground_px = true, parts_art = sootopolis_spire },
    { name = "sootopolis_spire_house_gate", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 43, 13, 3, 5 },
      relief_bare = true,
      patch_cells = gridCells({ 0, 1, 2 }, { 0, 1, 2, 3, 4 }),
      ground = SOOTO_GROUND, ground_px = true, parts_art = sootopolis_spire_gate },
    { name = "sootopolis_posts", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 30, 19, 1, 2 }, ground = { 0x071 },
      ground_px = true, parts_art = sootopolis_posts },
    { name = "cave_origin", layout = "LAYOUT_SOOTOPOLIS_CITY", rect = { 29, 15, 5, 4 }, ground = { 0x071 },
      patch_cells = gridCells({ 0, 1, 2, 3, 4 }, { 2, 3 }),
      ground_px = true, owned = CAVE_OWNED, parts_art = cave_origin },
    { name = "cave_origin_legends", layout = "LAYOUT_SOOTOPOLIS_CITY_LEGENDS_BATTLE", rect = { 29, 15, 5, 4 },
      ground = { 0x071 }, ground_px = true, owned = CAVE_OWNED, parts_art = cave_origin },
    { name = "pokemon_league", layout = "LAYOUT_EVER_GRANDE_CITY", rect = { 13, 0, 11, 8 },
      ground = { GRASS, 0x222, 0x221, 0x270, 0x271, 0x272 }, ground_px = true, lod = { 6, 6, 3 },
      parts_art = pokemon_league },
    { name = "ever_grande_bush", layout = "LAYOUT_EVER_GRANDE_CITY", rect = { 14, 8, 1, 1 }, ground = { GRASS, 0x222, 0x221 },
      ground_px = true, lod = { 6, 6, 3 }, parts_art = small_round("bush", Volume():dome(8, 9, 8, 6.5, 8.5)) },
    { name = "ever_grande_bush_shade", layout = "LAYOUT_EVER_GRANDE_CITY", rect = { 21, 8, 1, 1 },
      ground = { 0x221, 0x222, GRASS }, ground_px = true, lod = { 6, 6, 3 },
      parts_art = small_round("bush", Volume():dome(8, 9, 8, 6.5, 8.5)) },
    { name = "battle_dome", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 13, 4, 13, 14 },
      ground = { GRASS, 0x268, 0x269, 0x26A, 0x26B, 0x270, 0x271, 0x272, 0x273, 0x003 }, ground_px = true, lod = { 8, 8, 3 },
      keep = { { 0, 0, 208, 64 }, { 16, 64, 192, 80 }, { 8, 80, 200, 208 }, { 16, 208, 192, 224 } },
      parts_art = battle_dome },
    { name = "battle_pike", layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", rect = { 40, 17, 5, 13 },
      ground = { GRASS, 0x204, 0x017, 0x004, 0x003 }, ground_px = true, lod = { 8, 8, 3 },
      keep = { { 16, 0, 80, 208 }, { 0, 36, 16, 208 } }, parts_art = battle_pike },
    { name = "rustboro_fountain", layout = "LAYOUT_RUSTBORO_CITY", rect = { 27, 38, 3, 3 }, ground = { 0x2BB, 0x2C3, GRASS },
      parts_art = fountain },
    { name = "slateport_lantern", layout = "LAYOUT_SLATEPORT_CITY", rect = { 32, 51, 2, 4 }, ground = { GRASS, 0x202 },
      cell_ground = { { 0, 0, 0x34C }, { 1, 0, 0x34C } },
      ground_px = true, keep = { { 4, 8, 28, 15 }, { 0, 15, 32, 64 } }, parts_art = lantern },
    { name = "space_center", layout = "LAYOUT_MOSSDEEP_CITY", rect = { 60, 2, 9, 14 }, ground = { 0x170, GRASS, 0x002, 0x004 },
      patch_cells = gridCells({ 0, 1, 2, 3, 4, 5, 6, 7, 8 }, { 0, 1, 2, 3, 4, 5 }),
      ground_px = true, lod = { 4, 4, 2 }, parts_art = space_center },
  }
  for _, sp in ipairs(list) do specs[#specs + 1] = sp end
  return list
end
