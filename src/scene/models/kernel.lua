-- The building kernel (Battle Scene: Overworld): buildings rebuilt in 3D from their own drawing.
--
-- An Emerald building is drawn in a fixed oblique projection: a wall seen face on and the ground
-- straight from above, both at one pixel per pixel, which is what an orthographic camera pitched
-- at 45 degrees sees. A point (X, Y, Z) of a model - X east, Y up, Z south, in pixels from the
-- top-left corner of its cells - lands on its drawing at u = X, v = Z - Y. So the drawing is the
-- model seen from one direction: every face the drawing shows takes it projected, and what the
-- drawing never shows (sides, backs, the depth it lacks) is dressed from the same art, laid in
-- courses at one texel per pixel (Strip, Tile), never stretched.
--
-- A mesh is a list of triangles; a vertex is { x, y, z, u, v } (pixels, art pixels) and each
-- triangle carries a shade (the faces the drawing never lit are darker) and a tag ("~behind": a
-- face the 45-degree view never sees, as the generator tags it).
--
-- Ported from Emerald 3DS's scripts/voxel_building.py (by Zallax and contributors, CC BY-NC-SA
-- 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE): the same primitives and the same
-- arithmetic, run in the game on its own tilesets instead of offline. Left out: the proofs
-- (ortho_check, density_check), the preview rasteriser, Mound and the lathes. The solids read off
-- a drawing (Volume, HeightSolid, the Proj* surfaces) are in solids.lua - see DEVELOPMENT.md.

local K = {}

local EPS = 1e-6
local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local sin, cos, tan, rad, pi = math.sin, math.cos, math.tan, math.rad, math.pi
K.EPS = EPS

K.SHADE_ART = 1.0
K.SHADE_WEST = 0.80
K.SHADE_EAST = 0.72
K.SHADE_BACK = 0.66
K.SHADE_WOUND = 0.90

local function hypot(a, b) return sqrt(a * a + b * b) end
K.hypot = hypot

local function unit(v)
  local n = sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  return { v[1] / n, v[2] / n, v[3] / n }
end
K.unit = unit

-- ── Mesh ──────────────────────────────────────────────────────────────────

local Mesh = {}
Mesh.__index = Mesh
function K.mesh() return setmetatable({ tris = {} }, Mesh) end
-- a, b, c: { x, y, z, u, v }
function Mesh:tri(a, b, c, shade, tag)
  self.tris[#self.tris + 1] = { a, b, c, shade = shade, tag = tag }
end
function Mesh:poly(pts, shade, tag)
  for i = 2, #pts - 1 do self:tri(pts[1], pts[i], pts[i + 1], shade, tag) end
end

local function copy(p)
  local o = {}
  for i = 1, #p do o[i] = p[i] end
  return o
end

-- with u, v appended
local function withUV(p, u, v)
  local o = copy(p)
  o[#o + 1] = u
  o[#o + 1] = v
  return o
end

-- ── Geometry kernel ───────────────────────────────────────────────────────

--- Sutherland-Hodgman against one axis-aligned half plane (axis: 1-based index into each
--- point). Every other coordinate is interpolated, so the texture coordinates stay exact.
function K.clip(poly, axis, value, keepGreater)
  local out = {}
  local n = #poly
  for i = 1, n do
    local a, b = poly[i], poly[i % n + 1]
    local ina, inb
    if keepGreater then
      ina, inb = a[axis] >= value - EPS, b[axis] >= value - EPS
    else
      ina, inb = a[axis] <= value + EPS, b[axis] <= value + EPS
    end
    if ina then out[#out + 1] = a end
    if ina ~= inb then
      local t = (value - a[axis]) / (b[axis] - a[axis])
      local p = {}
      for k = 1, #a do p[k] = a[k] + (b[k] - a[k]) * t end
      out[#out + 1] = p
    end
  end
  return out
end
local clip = K.clip

local function area2(poly)
  local s, n = 0, #poly
  for i = 1, n do
    local a, b = poly[i], poly[i % n + 1]
    s = s + a[1] * b[2] - b[1] * a[2]
  end
  return s
end
K.area2 = area2

--- Ear clipping for a simple polygon of 2D points, either winding: index triples (1-based).
function K.triangulate(poly)
  local pts = {}
  for i = 1, #poly do pts[i] = i end
  local sign = area2(poly) > 0 and 1 or -1
  local tris = {}
  local function cross(o, a, b)
    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
  end
  local guard = 0
  while #pts > 3 and guard < 10000 do
    guard = guard + 1
    local cut = false
    for k = 1, #pts do
      local i0 = pts[(k - 2) % #pts + 1]
      local i1 = pts[k]
      local i2 = pts[k % #pts + 1]
      local a, b, c = poly[i0], poly[i1], poly[i2]
      if cross(a, b, c) * sign > EPS then
        local inside = false
        for _, j in ipairs(pts) do
          if j ~= i0 and j ~= i1 and j ~= i2 then
            local p = poly[j]
            if cross(a, b, p) * sign > EPS and cross(b, c, p) * sign > EPS and cross(c, a, p) * sign > EPS then
              inside = true
              break
            end
          end
        end
        if not inside then
          tris[#tris + 1] = { i0, i1, i2 }
          table.remove(pts, k)
          cut = true
          break
        end
      end
    end
    if not cut then break end
  end
  if #pts == 3 then tris[#tris + 1] = { pts[1], pts[2], pts[3] } end
  return tris
end

-- ── Texture mappings ──────────────────────────────────────────────────────

--- The GBA projection: u = X, v = Z - Y, its rows clamped to [lo, hi) (rows outside are another
--- surface's: a face reaching into them is hidden at 45 degrees and holds its nearest row).
function K.Proj(lo, hi) return { kind = "proj", lo = lo, hi = hi } end
local PROJ = K.Proj()

--- An art rectangle repeated at one texel per pixel. s runs along the face, t down from `top`.
function K.Tile(u0, v0, u1, v1, o)
  o = o or {}
  return { kind = "tile", rect = { u0, v0, u1, v1 }, s0 = o.s0 or 0, top = o.top, flip = o.flip or false }
end

--- A cap material over the heights [y0, y1): `tile` repeated along Z from z0 (southern edge
--- first); `front` / `back` an extra strip at either end (a facade's corner post).
function K.Band(y0, y1, tile, z0, o)
  o = o or {}
  return { y0 = y0, y1 = y1, tile = tile, z0 = z0, front = o.front, back = o.back,
           length = o.z1 and (z0 - o.z1) or 1e9 }
end

--- Split a planar polygon of (s, t) points into pieces that each sit in one repeat of the tile;
--- each piece's points get (u, v) appended. Within one piece the mapping is a translation.
function K.tilePieces(poly2d, tile)
  local u0, v0, u1, v1 = tile.rect[1], tile.rect[2], tile.rect[3], tile.rect[4]
  local pw, ph = u1 - u0, v1 - v0
  local smin, smax, tmin, tmax = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(poly2d) do
    smin, smax = min(smin, p[1]), max(smax, p[1])
    tmin, tmax = min(tmin, p[2]), max(tmax, p[2])
  end
  local out = {}
  if pw <= 0 or ph <= 0 then return out end
  local i0 = floor((smin - tile.s0) / pw + EPS)
  local i1 = ceil((smax - tile.s0) / pw - EPS)
  local j0 = floor(tmin / ph + EPS)
  local j1 = ceil(tmax / ph - EPS)
  for i = i0, i1 - 1 do
    for j = j0, j1 - 1 do
      local sa, sb = tile.s0 + i * pw, tile.s0 + (i + 1) * pw
      local ta, tb = j * ph, (j + 1) * ph
      local piece = clip(poly2d, 1, sa, true)
      if #piece >= 3 then piece = clip(piece, 1, sb, false) end
      if #piece >= 3 then piece = clip(piece, 2, ta, true) end
      if #piece >= 3 then piece = clip(piece, 2, tb, false) end
      if #piece >= 3 then
        local res = {}
        for k, p in ipairs(piece) do
          local fs = p[1] - sa
          if tile.flip then fs = pw - fs end
          res[k] = withUV(p, u0 + fs, v0 + (p[2] - ta))
        end
        out[#out + 1] = res
      end
    end
  end
  return out
end
local tilePieces = K.tilePieces

-- ── Faces laid in courses ─────────────────────────────────────────────────

local Strip = {}
Strip.__index = Strip

--- Tile courses laid up a face from its eave, one texel per GBA pixel: the drawn eave rows
--- `fixed` = { a, b } (bottom row at the eave), then rows [c, d) of `repeat` laid on upwards from
--- row `start` (default d - 1), so the pattern carries on where the fixed rows end; with no
--- repeat the last fixed row is held. `wrap` = { lo, hi }: u sampled from those columns only,
--- cyclically; `offset` shifts u. `tail`: rows laid at the far end (a flat roof's back parapet);
--- `repeatOffset`: u shift for the repeated courses and the tail only.
function K.Strip(fixed, o)
  o = o or {}
  local s = setmetatable({ fixed = fixed, rep = o.rep, wrap = o.wrap, offset = o.offset or 0,
    fromEnd = o.fromEnd or false, tail = o.tail, repeatOffset = o.repeatOffset }, Strip)
  if o.rep and o.start == nil then s.start = o.rep[2] - 1 else s.start = o.start end
  return s
end

--- (t0, t1, v at t0, constant) runs along the face, in texels.
function Strip:segments(total)
  if self.tail then
    local ta, tb = self.tail[1], self.tail[2]
    local length = tb - ta
    if total > length + (self.fixed[2] - self.fixed[1]) then
      local body = K.Strip(self.fixed, { rep = self.rep, start = self.start })
      local out = body:segments(total - length)
      out[#out + 1] = { total - length, total, tb, false }
      return out
    end
  end
  local a, b = self.fixed[1], self.fixed[2]
  local out = {}
  local t = 0
  if b > a then
    out[#out + 1] = { 0, min(total, b - a), b, false }
    t = b - a
  end
  if t >= total - EPS then return out end
  if not self.rep then
    out[#out + 1] = { t, total, a + 0.5, true }
    return out
  end
  local c, d = self.rep[1], self.rep[2]
  local first = self.start + 1 - c
  out[#out + 1] = { t, min(total, t + first), self.start + 1, false }
  t = t + first
  local guard = 0
  while t < total - EPS and guard < 4096 do
    guard = guard + 1
    out[#out + 1] = { t, min(total, t + (d - c)), d, false }
    t = t + (d - c)
  end
  return out
end

--- (s0, s1, du) spans: u = s + du inside each.
function Strip:uPieces(s0, s1)
  if not self.wrap then return { { s0, s1, self.offset } } end
  local lo, hi = self.wrap[1], self.wrap[2]
  local period = hi - lo
  local out = {}
  local k = floor((s0 - lo) / period + EPS)
  local guard = 0
  while lo + k * period < s1 - EPS and guard < 4096 do
    guard = guard + 1
    local a, b = max(s0, lo + k * period), min(s1, lo + (k + 1) * period)
    if b > a + EPS then out[#out + 1] = { a, b, -k * period } end
    k = k + 1
  end
  return out
end

--- A planar convex face textured by a Strip: `sdir` the unit direction along the eave (u follows
--- it), `tdir` the unit direction up the face from the eave line through `origin` (v runs
--- against it).
function K.stripFace(mesh, pts, origin, sdir, tdir, strip, shade, tag)
  local dens = abs(tdir[2]) + hypot(tdir[1], tdir[3])
  local loc = {}
  local tmax, smin, smax = -math.huge, math.huge, -math.huge
  for i, p in ipairs(pts) do
    local d1, d2, d3 = p[1] - origin[1], p[2] - origin[2], p[3] - origin[3]
    local s = d1 * sdir[1] + d2 * sdir[2] + d3 * sdir[3]
    local t = (d1 * tdir[1] + d2 * tdir[2] + d3 * tdir[3]) * dens
    loc[i] = { s, t, p[1], p[2], p[3] }
    tmax, smin, smax = max(tmax, t), min(smin, s), max(smax, s)
  end
  local fixedLen = strip.fixed[2] - strip.fixed[1]
  for _, seg in ipairs(strip:segments(tmax)) do
    local t0, t1, v0, const = seg[1], seg[2], seg[3], seg[4]
    for _, up in ipairs(strip:uPieces(smin, smax)) do
      local s0, s1, du = up[1], up[2], up[3]
      if strip.repeatOffset ~= nil and t0 >= fixedLen - EPS then du = strip.repeatOffset end
      local piece = clip(loc, 2, t0, true)
      if #piece >= 3 then piece = clip(piece, 2, t1, false) end
      if #piece >= 3 then piece = clip(piece, 1, s0, true) end
      if #piece >= 3 then piece = clip(piece, 1, s1, false) end
      if #piece >= 3 then
        local out = {}
        for k, q in ipairs(piece) do
          local v = const and v0 or (v0 - (q[2] - t0))
          out[k] = { q[3], q[4], q[5], q[1] + du, v }
        end
        mesh:poly(out, shade, tag)
      end
    end
  end
end
local stripFace = K.stripFace

-- ── Prism ─────────────────────────────────────────────────────────────────

local function edgeNormal(a, b)
  local dz, dy = b[1] - a[1], b[2] - a[2]
  local l = hypot(dz, dy)
  return dy / l, -dz / l
end

local function emitCapPiece(mesh, piece, band, x, side, shade, tag)
  local top = band.tile.top == nil and band.y1 or band.tile.top
  local strips = {}
  local sFront = 0
  if band.front then
    local fw = band.front.rect[3] - band.front.rect[1]
    strips[#strips + 1] = { band.front, 0, fw }
    sFront = fw
  end
  local sBack, bw = 1e9, 0
  if band.back then
    bw = band.back.rect[3] - band.back.rect[1]
    sBack = band.length - bw
  end
  strips[#strips + 1] = { band.tile, sFront, sBack }
  if band.back then strips[#strips + 1] = { band.back, sBack, sBack + bw } end
  for _, st in ipairs(strips) do
    local tile, sa, sb = st[1], st[2], st[3]
    local pts = {}
    for k, p in ipairs(piece) do pts[k] = { band.z0 - p[1], top - p[2] } end
    pts = clip(pts, 1, sa, true)
    if #pts >= 3 then pts = clip(pts, 1, sb, false) end
    if #pts >= 3 then
      local r = tile.rect
      local shifted = K.Tile(r[1], r[2], r[3], r[4], { s0 = sa, flip = (tile.flip ~= (side == "w")) })
      for _, sub in ipairs(tilePieces(pts, shifted)) do
        local out = {}
        for k, q in ipairs(sub) do out[k] = { x, top - q[2], band.z0 - q[1], q[3], q[4] } end
        mesh:poly(out, shade, tag)
      end
    end
  end
end

local function emitPrism(pr, mesh)
  local poly = pr.poly
  if area2(poly) <= 0 then error(pr.name .. ": polygon must be counter-clockwise (+Z right, +Y up)") end
  local n = #poly
  local x0, x1 = pr.x0, pr.x1
  for i = 0, n - 1 do
    if not pr.skip[i] then
      local a, b = poly[i + 1], poly[(i + 1) % n + 1]
      local nz, ny = edgeNormal(a, b)
      local mat = pr.edges[i]
      local facing = nz + ny     -- dot with the GBA view direction (0, 1, 1)
      local skipIt = false
      if mat == nil then
        if ny < -0.5 or facing <= EPS then skipIt = true else mat = PROJ end
      end
      if not skipIt then
        local shade = facing > EPS and K.SHADE_ART or K.SHADE_BACK
        local tag = pr.name .. ".e" .. i
        if mat.kind == "proj" then
          -- split where the projected row crosses a clamp: each piece exactly projected or one row
          local cuts = { 0, 1 }
          local va, vb = a[1] - a[2], b[1] - b[2]
          for _, lim in ipairs({ mat.lo or false, mat.hi or false }) do
            if lim and abs(vb - va) > EPS then
              local t = (lim - va) / (vb - va)
              if t > EPS and t < 1 - EPS then cuts[#cuts + 1] = t end
            end
          end
          table.sort(cuts)
          for k = 1, #cuts - 1 do
            local ta, tb = cuts[k], cuts[k + 1]
            local pa = { a[1] + (b[1] - a[1]) * ta, a[2] + (b[2] - a[2]) * ta }
            local pb = { a[1] + (b[1] - a[1]) * tb, a[2] + (b[2] - a[2]) * tb }
            local midV = (pa[1] - pa[2] + pb[1] - pb[2]) / 2
            local clampLo = mat.lo ~= nil and midV < mat.lo
            local clampHi = mat.hi ~= nil and midV > mat.hi
            local quad = {}
            for q, xp in ipairs({ { x0, pa }, { x1, pa }, { x1, pb }, { x0, pb } }) do
              local x, p = xp[1], xp[2]
              local u, v
              if clampLo then u, v = x, mat.lo + 0.5
              elseif clampHi then u, v = x, mat.hi - 0.5
              else u, v = x, p[1] - p[2] end
              quad[q] = { x, p[2], p[1], u, v }
            end
            mesh:poly(quad, shade, tag)
          end
        elseif getmetatable(mat) == Strip then
          local start, finish = a, b
          if mat.fromEnd then start, finish = b, a end
          local tdir = unit({ 0, finish[2] - start[2], finish[1] - start[1] })
          local pts = { { x0, a[2], a[1] }, { x1, a[2], a[1] }, { x1, b[2], b[1] }, { x0, b[2], b[1] } }
          stripFace(mesh, pts, { 0, start[2], start[1] }, { 1, 0, 0 }, tdir, mat, shade, tag)
        elseif mat.kind == "tile" then
          -- s along X, t down the edge from its upper end
          local length = hypot(b[1] - a[1], b[2] - a[2])
          local upper, lower = a, b
          if a[2] < b[2] then upper, lower = b, a end
          local face = { { x0, 0 }, { x1, 0 }, { x1, length }, { x0, length } }
          for _, piece in ipairs(tilePieces(face, mat)) do
            local pts = {}
            for k, q in ipairs(piece) do
              local f = length > EPS and q[2] / length or 0
              pts[k] = { q[1], upper[2] + (lower[2] - upper[2]) * f, upper[1] + (lower[1] - upper[1]) * f, q[3], q[4] }
            end
            mesh:poly(pts, shade, tag)
          end
        end
      end
    end
  end
  if not pr.caps then return end
  local tris = K.triangulate(poly)
  for _, sd in ipairs({ { "w", x0, K.SHADE_WEST, pr.west }, { "e", x1, K.SHADE_EAST, pr.east } }) do
    if sd[4] then
      for _, band in ipairs(pr.caps) do
        for _, tri in ipairs(tris) do
          local piece = { poly[tri[1]], poly[tri[2]], poly[tri[3]] }
          piece = clip(piece, 2, band.y0, true)
          if #piece >= 3 then piece = clip(piece, 2, band.y1, false) end
          if #piece >= 3 then
            emitCapPiece(mesh, piece, band, sd[2], sd[1], sd[3], pr.name .. ".cap" .. sd[1])
          end
        end
      end
    end
  end
end

--- A (Z, Y) polygon extruded over [x0, x1]. `poly` counter-clockwise seen from the west (+Z right,
--- +Y up); `edges` maps an edge index (0-based, point i to i + 1) to its material (Proj, Strip,
--- Tile; absent: Proj when it faces the GBA camera); `caps` the bands both ends are tiled with.
function K.Prism(name, x0, x1, poly, o)
  o = o or {}
  local skip = {}
  for _, i in ipairs(o.skip or {}) do skip[i] = true end
  return { name = name, x0 = x0, x1 = x1, poly = poly, edges = o.edges or {}, caps = o.caps,
           west = o.west ~= false, east = o.east ~= false, skip = skip, emit = emitPrism }
end

-- ── Roofs ─────────────────────────────────────────────────────────────────

local function hipEmit(self, mesh)
  local x0, x1, zf, zb, y0, ye = self.x0, self.x1, self.zf, self.zb, self.y0, self.ye
  local xa, xb = x0 + self.run, x1 - self.run
  local zr, zq, yr, yt = self.z_rf, self.z_rb, self.yr, self.yt
  local n = self.name
  local up = { 0, 1, 0 }
  local fas, sl = self.fascia, self.slope
  stripFace(mesh, { { x0, y0, zf }, { x1, y0, zf }, { x1, ye, zf }, { x0, ye, zf } },
    { 0, y0, zf }, { 1, 0, 0 }, up, fas, K.SHADE_ART, n .. ".fascia_s")
  stripFace(mesh, { { x1, y0, zb }, { x0, y0, zb }, { x0, ye, zb }, { x1, ye, zb } },
    { 0, y0, zb }, { 1, 0, 0 }, up, fas, K.SHADE_BACK, n .. ".fascia_n")
  stripFace(mesh, { { x0, y0, zb }, { x0, y0, zf }, { x0, ye, zf }, { x0, ye, zb } },
    { x0, y0, 0 }, { 0, 0, 1 }, up, fas, K.SHADE_WEST, n .. ".fascia_w")
  stripFace(mesh, { { x1, y0, zf }, { x1, y0, zb }, { x1, ye, zb }, { x1, ye, zf } },
    { x1, y0, 0 }, { 0, 0, 1 }, up, fas, K.SHADE_EAST, n .. ".fascia_e")
  local tS = unit({ 0, self.rise, -(zf - zr) })
  local tN = unit({ 0, self.rise, (zf - zr) })
  local tW = unit({ self.run, self.rise, 0 })
  local tE = unit({ -self.run, self.rise, 0 })
  stripFace(mesh, { { x0, ye, zf }, { x1, ye, zf }, { xb, yr, zr }, { xa, yr, zr } },
    { 0, ye, zf }, { 1, 0, 0 }, tS, sl, K.SHADE_ART, n .. ".slope_s")
  stripFace(mesh, { { x1, ye, zb }, { x0, ye, zb }, { xa, yr, zq }, { xb, yr, zq } },
    { 0, ye, zb }, { 1, 0, 0 }, tN, sl, K.SHADE_BACK, n .. ".slope_n")
  stripFace(mesh, { { x0, ye, zb }, { x0, ye, zf }, { xa, yr, zr }, { xa, yr, zq } },
    { x0, ye, 0 }, { 0, 0, 1 }, tW, sl, K.SHADE_WEST, n .. ".hip_w")
  stripFace(mesh, { { x1, ye, zf }, { x1, ye, zb }, { xb, yr, zq }, { xb, yr, zr } },
    { x1, ye, 0 }, { 0, 0, 1 }, tE, sl, K.SHADE_EAST, n .. ".hip_e")
  if not self.ridge then return end
  -- the ridge: teeth to the south, cap on top, ends over the hips; each half takes its own end of
  -- the drawn ridge (both end ornaments stay), unless something stands on it (ridgeWrap)
  local lo, hi = self.ridge_u[1], self.ridge_u[2]
  local mid = (xa + xb) / 2
  local spans
  if self.ridgeWrap then spans = { { xa, xb, nil } }
  else spans = { { xa, mid, lo - xa }, { mid, xb, hi - xb } } end
  for _, sp in ipairs(spans) do
    local sa, sb, off = sp[1], sp[2], sp[3]
    local teeth, cap
    if off == nil then
      teeth, cap = K.Strip(self.teeth, { wrap = self.ridgeWrap }), K.Strip(self.cap, { wrap = self.ridgeWrap })
    else
      teeth, cap = K.Strip(self.teeth, { offset = off }), K.Strip(self.cap, { offset = off })
    end
    stripFace(mesh, { { sa, yr, zr }, { sb, yr, zr }, { sb, yt, zr }, { sa, yt, zr } },
      { 0, yr, zr }, { 1, 0, 0 }, up, teeth, K.SHADE_ART, n .. ".teeth")
    stripFace(mesh, { { sa, yt, zr }, { sb, yt, zr }, { sb, yt, zq }, { sa, yt, zq } },
      { 0, yt, zr }, { 1, 0, 0 }, { 0, 0, -1 }, cap, K.SHADE_ART, n .. ".cap")
  end
  local r = self.end_tile.rect
  local u0, v0 = r[1], r[2]
  local w, h = zr - zq, yt - yr
  for _, e in ipairs({ { xa, K.SHADE_WEST, false }, { xb, K.SHADE_EAST, true } }) do
    local x, shade, flip = e[1], e[2], e[3]
    local pts = { { x, yr, zq }, { x, yr, zr }, { x, yt, zr }, { x, yt, zq } }
    local us = { u0, u0 + w, u0 + w, u0 }
    if flip then for k = 1, 4 do us[k] = u0 + w - (us[k] - u0) end end
    local vs = { v0 + h, v0 + h, v0, v0 }
    local q = {}
    for k = 1, 4 do q[k] = { pts[k][1], pts[k][2], pts[k][3], us[k], vs[k] } end
    mesh:poly(q, shade, n .. ".ridge_end")
  end
end

--- A hipped roof with its ridge along X: the eave round at y0 plus the fascia, front and back
--- rising at `pitch`, the hips `run` pixels in; every side tiled with the drawn courses.
--- o = { fascia, slope (Strips), teeth, cap ({ a, b } rows), pitch, run, ridge_u, end_tile,
---       ridge (default true), ridgeWrap }
function K.HipRoof(name, x0, x1, zf, zb, y0, o)
  local r = { name = name, x0 = x0, x1 = x1, zf = zf, zb = zb, y0 = y0, fascia = o.fascia,
    slope = o.slope, teeth = o.teeth, cap = o.cap, pitch = o.pitch, run = o.run, ridge_u = o.ridge_u,
    end_tile = o.end_tile, ridge = o.ridge ~= false, ridgeWrap = o.ridgeWrap, emit = hipEmit }
  r.ye = y0 + (o.fascia.fixed[2] - o.fascia.fixed[1])
  local cd = o.cap[2] - o.cap[1]
  r.z_rf = (zf + zb) / 2 + cd / 2
  r.z_rb = r.z_rf - cd
  r.rise = tan(rad(o.pitch)) * (zf - r.z_rf)
  r.yr = r.ye + r.rise
  r.yt = r.yr + (o.teeth[2] - o.teeth[1])
  return r
end

--- (z, y) of a hip roof's front slope `texels` art rows above its eave.
function K.slopePoint(roof, texels)
  local run = roof.zf - roof.z_rf
  local length = hypot(run, roof.rise)
  local t = texels / ((roof.rise + run) / length)
  return roof.zf - t * run / length, roof.ye + t * roof.rise / length
end

-- outward normal of plan edge p -> q, for a plan listed clockwise on screen (+X right, +Z down)
local function planNormal(p, q)
  local dx, dz = q[1] - p[1], q[2] - p[2]
  local n = hypot(dx, dz)
  return -dz / n, dx / n
end

--- The convex plan polygon moved inwards by d on every edge.
function K.insetPlan(plan, d)
  local lines = {}
  local count = #plan
  for i = 1, count do
    local p, q = plan[i], plan[i % count + 1]
    local nx, nz = planNormal(p, q)
    lines[i] = { { p[1] - nx * d, p[2] - nz * d }, { q[1] - p[1], q[2] - p[2] } }
  end
  local out = {}
  for i = 1, count do
    local l1, l2 = lines[(i - 2) % count + 1], lines[i]
    local p1, d1, p2, d2 = l1[1], l1[2], l2[1], l2[2]
    local den = d1[1] * d2[2] - d1[2] * d2[1]
    local t = ((p2[1] - p1[1]) * d2[2] - (p2[2] - p1[2]) * d2[1]) / den
    out[i] = { p1[1] + d1[1] * t, p1[2] + d1[2] * t }
  end
  return out
end

local function projPoly(mesh, quad, shade, tag)
  local q = {}
  for k, p in ipairs(quad) do q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
  mesh:poly(q, shade, tag)
end
K.projPoly = projPoly

local function frustumEmit(self, mesh)
  local plan, n = self.plan, self.name
  -- the walls go a pixel under the ground: the drawing outlines its plinth a pixel outside
  local y0, y1 = -1, self.wall_top
  local y2 = y1 + self.band_rise
  local top = K.insetPlan(plan, self.band_rise)
  local count = #plan
  for i = 1, count do
    local p, q = plan[i], plan[i % count + 1]
    local pi_, qi = top[i], top[i % count + 1]
    local nx, nz = planNormal(p, q)
    local drawn = nz > 0.1
    local shade = drawn and K.SHADE_ART or (nx < -0.3 and K.SHADE_WEST or nx > 0.3 and K.SHADE_EAST or K.SHADE_BACK)
    local wall = { { p[1], y0, p[2] }, { q[1], y0, q[2] }, { q[1], y1, q[2] }, { p[1], y1, p[2] } }
    local band = { { p[1], y1, p[2] }, { q[1], y1, q[2] }, { qi[1], y2, qi[2] }, { pi_[1], y2, pi_[2] } }
    local sdir = unit({ q[1] - p[1], 0, q[2] - p[2] })
    if drawn then
      projPoly(mesh, wall, K.SHADE_ART, n .. ".wall")
      projPoly(mesh, band, K.SHADE_ART, n .. ".band")
    else
      stripFace(mesh, wall, { p[1], y0, p[2] }, sdir, { 0, 1, 0 }, self.wall_side, shade, n .. ".wall")
      stripFace(mesh, band, { p[1], y1, p[2] }, sdir, unit({ -nx, 1, -nz }), self.band_side, shade, n .. ".band")
    end
  end
  local zfront = -math.huge
  for _, p in ipairs(top) do zfront = max(zfront, p[2]) end
  local face = {}
  for k = #top, 1, -1 do face[#face + 1] = { top[k][1], y2, top[k][2] } end
  stripFace(mesh, face, { 0, y2, zfront }, { 1, 0, 0 }, { 0, 0, -1 }, self.top, K.SHADE_ART, n .. ".top")
end

--- Walls on a convex plan (x, z; clockwise on screen), a roof band sloping in `band_rise`, and a
--- flat top laid from its front edge back (the octagonal Pokemon Center and Mart).
function K.Frustum(name, plan, o)
  return { name = name, plan = plan, wall_top = o.wall_top, wall_side = o.wall_side,
           band_rise = o.band_rise, band_side = o.band_side, top = o.top, emit = frustumEmit }
end

local function vaultEmit(self, mesh)
  local zf, zb, y0, n = self.zf, self.zb, self.y0, self.name
  local pts = self.profile
  for i = 1, #pts - 1 do
    local xa, ha, xb, hb = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
    projPoly(mesh, { { xa, y0 + ha, zf }, { xb, y0 + hb, zf }, { xb, y0 + hb, zb }, { xa, y0 + ha, zb } },
      K.SHADE_ART, n .. ".top")
    if ha > 0 or hb > 0 then
      local front = { { xa, y0, zf }, { xb, y0, zf }, { xb, y0 + hb, zf }, { xa, y0 + ha, zf } }
      local q = {}
      for k, p in ipairs(front) do q[k] = { p[1], p[2], p[3], p[1], zf - p[2] } end
      mesh:poly(q, K.SHADE_ART, n .. ".front")
      local back = { { xb, y0, zb }, { xa, y0, zb }, { xa, y0 + ha, zb }, { xb, y0 + hb, zb } }
      q = {}
      for k, p in ipairs(back) do q[k] = { p[1], p[2], p[3], p[1], zf - p[2] } end
      mesh:poly(q, K.SHADE_BACK, n .. ".back")
    end
  end
end

--- A barrel vault on a flat top, its axis front to back: `profile` the arch's (x, height)
--- points read off the drawn front arch, from zf back to zb at y0.
function K.Vault(name, profile, zf, zb, y0)
  return { name = name, profile = profile, zf = zf, zb = zb, y0 = y0, emit = vaultEmit }
end

local function wallsEmit(self, mesh)
  for i = 1, #self.plan - 1 do
    local p, q = self.plan[i], self.plan[i + 1]
    projPoly(mesh, { { p[1], self.y0, p[2] }, { q[1], self.y0, q[2] }, { q[1], self.y1, q[2] }, { p[1], self.y1, p[2] } },
      K.SHADE_ART, self.name .. ".wall")
  end
end

--- Upright walls along an open plan polyline (x, z), the drawing projected (a chamfered porch).
function K.Walls(name, plan, y0, y1)
  return { name = name, plan = plan, y0 = y0, y1 = y1, emit = wallsEmit }
end

local function cylinderEmit(self, mesh)
  local ring = {}
  for k = 0, self.sides - 1 do
    ring[k + 1] = { self.cx + self.rx * cos(2 * pi * k / self.sides), self.cz + self.rz * sin(2 * pi * k / self.sides) }
  end
  local y0, y1 = self.y0, self.y1
  local top = {}
  for k, p in ipairs(ring) do top[k] = { p[1], y1, p[2], p[1], p[2] - y1 } end
  mesh:poly(top, K.SHADE_ART, self.name .. ".top")
  local r = self.back_tile.rect
  local u0, u1, v1 = r[1], r[3], r[4]
  for k = 0, self.sides - 1 do
    local a, b = ring[k + 1], ring[(k + 1) % self.sides + 1]
    local xa, za, xb, zb = a[1], a[2], b[1], b[2]
    local nx, nz = zb - za, -(xb - xa)
    if nx * ((xa + xb) / 2 - self.cx) + nz * ((za + zb) / 2 - self.cz) < 0 then nx, nz = -nx, -nz end
    nz = nz / hypot(nx, nz)
    local quad = { { xa, y0, za }, { xb, y0, zb }, { xb, y1, zb }, { xa, y1, za } }
    if nz > 0.2 and self.proj then
      projPoly(mesh, quad, K.SHADE_ART, self.name .. ".side")
    else
      local w = hypot(xb - xa, zb - za)
      local ua = u0 + (k * 3) % max(1, floor(u1 - u0 - w))
      local vs = { v1, v1, v1 - (y1 - y0), v1 - (y1 - y0) }
      local us = { ua, ua + w, ua + w, ua }
      local q = {}
      for i = 1, 4 do q[i] = { quad[i][1], quad[i][2], quad[i][3], us[i], vs[i] } end
      mesh:poly(q, nz < 0 and K.SHADE_BACK or (nx > 0 and K.SHADE_EAST or K.SHADE_WEST), self.name .. ".side")
    end
  end
end

--- A short upright cylinder of elliptical footprint (a vent): its top and the side facing the
--- camera projected, the far side and flanks a tile of the drawn near side.
function K.Cylinder(name, cx, cz, rx, rz, y0, y1, backTile, o)
  o = o or {}
  return { name = name, cx = cx, cz = cz, rx = rx, rz = rz, y0 = y0, y1 = y1, back_tile = backTile,
           sides = o.sides or 16, proj = o.proj ~= false, emit = cylinderEmit }
end

local function plainWallEmit(self, mesh)
  local xa, za, xb, zb = self.a[1], self.a[2], self.b[1], self.b[2]
  local length = hypot(xb - xa, zb - za)
  local dx, dz = (xb - xa) / length, (zb - za) / length
  local face = { { 0, 0 }, { length, 0 }, { length, self.y1 - self.y0 }, { 0, self.y1 - self.y0 } }
  for _, piece in ipairs(tilePieces(face, self.tile)) do
    local pts = {}
    for k, q in ipairs(piece) do pts[k] = { xa + dx * q[1], self.y1 - q[2], za + dz * q[1], q[3], q[4] } end
    mesh:poly(pts, K.SHADE_WEST, self.name .. ".plain")
  end
end

--- A wall the drawing never shows, dressed with `tile` at one texel per pixel, from a to b (x, z)
--- with its top row at y1.
function K.PlainWall(name, a, b, y0, y1, tile)
  return { name = name, a = a, b = b, y0 = y0, y1 = y1, tile = tile, emit = plainWallEmit }
end

-- ── Plan solids ───────────────────────────────────────────────────────────

local function planPrismEmit(self, mesh)
  local pl = self.plan
  local n = #pl
  local area = area2(pl)
  local y0, y1 = self.y0, self.y1
  local u0, u1, foot = self.side[1], self.side[2], self.side[3]
  -- a wall taller than the drawing above its foot: the strip's rows repeat up it
  local tile = K.Tile(u0, max(0, foot - (y1 - y0)), u1, foot)
  local cx, cz = 0, 0
  for _, p in ipairs(pl) do cx, cz = cx + p[1], cz + p[2] end
  cx, cz = cx / n, cz / n
  local k_ = self.shrink
  local up = {}
  for i, p in ipairs(pl) do up[i] = { cx + (p[1] - cx) * k_, cz + (p[2] - cz) * k_ } end
  local function at(i, s_, y)
    local A, B = pl[i], pl[i % n + 1]
    local TA, TB = up[i], up[i % n + 1]
    local L = hypot(B[1] - A[1], B[2] - A[2])
    local g, f = s_ / L, (y - y0) / (y1 - y0)
    local fx, fz = A[1] + (B[1] - A[1]) * g, A[2] + (B[2] - A[2]) * g
    local hx, hz = TA[1] + (TB[1] - TA[1]) * g, TA[2] + (TB[2] - TA[2]) * g
    return fx + (hx - fx) * f, y, fz + (hz - fz) * f
  end
  for i = 1, n do
    local A, B = pl[i], pl[i % n + 1]
    local xa, za, xb, zb = A[1], A[2], B[1], B[2]
    local L = hypot(xb - xa, zb - za)
    if L >= 1e-6 then
      local nx, nz = (zb - za) / L, -(xb - xa) / L
      if (area < 0) ~= self.inward then nx, nz = -nx, -nz end
      if nz > 0.02 and abs(nx) < 0.995 then
        local U1, U0 = up[i % n + 1], up[i]
        projPoly(mesh, { { xa, y0, za }, { xb, y0, zb }, { U1[1], y1, U1[2] }, { U0[1], y1, U0[2] } },
          K.SHADE_ART, self.name)
      else
        local ph = tile.rect[4] - tile.rect[2]
        local off = (-(y1 - y0)) % ph
        local face = { { 0, off }, { L, off }, { L, off + y1 - y0 }, { 0, off + y1 - y0 } }
        local shade = nx > 0.3 and K.SHADE_EAST or nx < -0.3 and K.SHADE_WEST or K.SHADE_BACK
        for _, piece in ipairs(tilePieces(face, tile)) do
          local pts = {}
          for k, q in ipairs(piece) do
            local x, y, z = at(i, q[1], y1 - (q[2] - off))
            pts[k] = { x, y, z, q[3], q[4] }
          end
          mesh:poly(pts, shade, self.name .. ".side~behind")
        end
      end
    end
  end
  if self.open_top then return end
  -- a convex top is a fan; a U's is cut into ears
  local convexPos, convexNeg = true, true
  for i = 1, n do
    local a, b, c = up[i], up[i % n + 1], up[(i + 1) % n + 1]
    local t = (b[1] - a[1]) * (c[2] - b[2]) - (b[2] - a[2]) * (c[1] - b[1])
    if t < -EPS then convexPos = false end
    if t > EPS then convexNeg = false end
  end
  local fan
  if convexPos or convexNeg then
    fan = {}
    for k = 2, n - 1 do fan[#fan + 1] = { 1, k, k + 1 } end
  else
    fan = K.triangulate(up)
  end
  if self.top then
    for _, t3 in ipairs(fan) do
      local tri = { up[t3[1]], up[t3[2]], up[t3[3]] }
      for _, piece in ipairs(tilePieces(tri, self.top)) do
        local pts = {}
        for k, q in ipairs(piece) do pts[k] = { q[1], y1, q[2], q[3], q[4] } end
        mesh:poly(pts, K.SHADE_ART, self.name .. ".roof~behind")
      end
    end
    return
  end
  for _, t3 in ipairs(fan) do
    local q = {}
    for k = 1, 3 do
      local p = up[t3[k]]
      q[k] = { p[1], y1, p[2], p[1], p[2] - y1 }
    end
    mesh:tri(q[1], q[2], q[3], K.SHADE_ART, self.name .. ".top")
  end
end

--- An upright prism on a plan polygon (x, z) from y0 to y1: a face the 45-degree view sees takes
--- the drawing projected; a side or back the drawing never shows is dressed with `side` =
--- { u0, u1, foot } (columns u0-u1 of a straight stretch of the facade standing on row `foot`).
--- o = { top = Tile (a roof the drawing does not show), shrink, open_top, inward }
function K.PlanPrism(name, plan, y0, y1, side, o)
  o = o or {}
  return { name = name, plan = plan, y0 = y0, y1 = y1, side = side, top = o.top, shrink = o.shrink or 1,
           open_top = o.open_top or false, inward = o.inward or false, emit = planPrismEmit }
end

local function cross3(a, b, c)
  local e1 = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
  local e2 = { c[1] - a[1], c[2] - a[2], c[3] - a[3] }
  return { e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1] }
end

local function planPyramidEmit(self, mesh)
  local ax, ay, az = self.apex[1], self.apex[2], self.apex[3]
  local pl, y0 = self.plan, self.y0
  local n = #pl
  local cx, cz = 0, 0
  for _, p in ipairs(pl) do cx, cz = cx + p[1], cz + p[2] end
  cx, cz = cx / n, cz / n
  for i = 1, n do
    local A, B = pl[i], pl[i % n + 1]
    local a, b, c = { A[1], y0, A[2] }, { B[1], y0, B[2] }, { ax, ay, az }
    local nrm = cross3(a, b, c)
    local mx, mz = (A[1] + B[1]) / 2 - cx, (A[2] + B[2]) / 2 - cz
    if nrm[1] * mx + nrm[3] * mz < 0 then
      b, c = c, b
      nrm = { -nrm[1], -nrm[2], -nrm[3] }
    end
    if nrm[2] + nrm[3] > 1e-6 then
      local q = {}
      for k, p in ipairs({ a, b, c }) do q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
      mesh:tri(q[1], q[2], q[3], K.SHADE_ART, self.name)
    else
      local q = {}
      for k, p in ipairs({ a, b, c }) do q[k] = { p[1], p[2], p[3], p[1], 2 * az - p[3] - p[2] } end
      mesh:tri(q[1], q[2], q[3], K.SHADE_BACK, self.name .. ".back~behind")
    end
  end
end

--- A pyramid of flat faces over a plan (x, z) at y0, its apex (x, y, z).
function K.PlanPyramid(name, plan, y0, apex)
  return { name = name, plan = plan, y0 = y0, apex = apex, emit = planPyramidEmit }
end

local function platePrismEmit(self, mesh)
  local pl, z0, z1 = self.poly, self.z0, self.z1
  local n = #pl
  local area = area2(pl)
  local u0, u1, foot = self.side[1], self.side[2], self.side[3]
  local ytop = -math.huge
  for _, p in ipairs(pl) do ytop = max(ytop, p[2]) end
  local front = {}
  for k, p in ipairs(pl) do front[k] = { p[1], p[2], z1, p[1], z1 - p[2] } end
  mesh:poly(front, K.SHADE_ART, self.name)
  local tile = K.Tile(u0, foot - ytop, u1, foot)
  for i = 1, n do
    local A, B = pl[i], pl[i % n + 1]
    local xa, ya, xb, yb = A[1], A[2], B[1], B[2]
    local L = hypot(xb - xa, yb - ya)
    if L >= 1e-6 then
      local nx, ny = (yb - ya) / L, -(xb - xa) / L
      if area < 0 then nx, ny = -nx, -ny end
      if ny > 0.05 then
        projPoly(mesh, { { xa, ya, z1 }, { xb, yb, z1 }, { xb, yb, z0 }, { xa, ya, z0 } }, K.SHADE_ART, self.name)
      elseif ny >= -0.5 then
        local shade = nx > 0 and K.SHADE_EAST or K.SHADE_WEST
        local ylo, yhi = min(ya, yb), max(ya, yb)
        local face = { { 0, ytop - yhi }, { z1 - z0, ytop - yhi }, { z1 - z0, ytop - ylo }, { 0, ytop - ylo } }
        for _, piece in ipairs(tilePieces(face, tile)) do
          local pts = {}
          for k, q in ipairs(piece) do pts[k] = { xa, ytop - q[2], z1 - q[1], q[3], q[4] } end
          mesh:poly(pts, shade, self.name .. ".side~behind")
        end
      end
    end
  end
  for k = 2, n - 1 do
    local tri = { pl[1], pl[k], pl[k + 1] }
    local flat = {}
    for j, p in ipairs(tri) do flat[j] = { p[1], ytop - p[2] } end
    for _, piece in ipairs(tilePieces(flat, tile)) do
      local pts = {}
      for j, q in ipairs(piece) do pts[j] = { q[1], ytop - q[2], z0, q[3], q[4] } end
      mesh:poly(pts, K.SHADE_BACK, self.name .. ".back~behind")
    end
  end
end

--- A block whose front is a polygon (x, y), run back from z1 to z0; faces turned up or south take
--- the drawing projected, upright ends and the back `side` = { u0, u1, foot }.
function K.PlatePrism(name, poly, z0, z1, side)
  return { name = name, poly = poly, z0 = z0, z1 = z1, side = side, emit = platePrismEmit }
end

local function sectionPrismEmit(self, mesh)
  local sec, x0, x1 = self.sec, self.x0, self.x1
  local n = #sec
  local area = area2(sec)
  local u0, u1, foot = self.side[1], self.side[2], self.side[3]
  local ytop, zf, zr, yr = -math.huge, -math.huge, 0, -math.huge
  for _, p in ipairs(sec) do
    ytop, zf = max(ytop, p[2]), max(zf, p[1])
    if p[2] > yr then zr, yr = p[1], p[2] end
  end
  local tile = K.Tile(u0, foot - ytop, u1, foot)
  for i = 1, n do
    local A, B = sec[i], sec[i % n + 1]
    local za, ya, zb, yb = A[1], A[2], B[1], B[2]
    local L = hypot(zb - za, yb - ya)
    if L >= 1e-6 then
      local nz, ny = (yb - ya) / L, -(zb - za) / L
      if area < 0 then nz, ny = -nz, -ny end
      local q = { { x0, ya, za }, { x1, ya, za }, { x1, yb, zb }, { x0, yb, zb } }
      if nz < -0.05 and ny > 0.05 then
        local o = {}
        for k, p in ipairs(q) do o[k] = { p[1], p[2], p[3], p[1], 2 * zr - p[3] - p[2] } end
        mesh:poly(o, K.SHADE_BACK, self.name .. ".back~behind")
      elseif ny + nz > 0.05 then
        projPoly(mesh, q, K.SHADE_ART, self.name)
      elseif ny > -0.5 then
        local face = { { x0, ytop - ya }, { x1, ytop - ya }, { x1, ytop - yb }, { x0, ytop - yb } }
        for _, piece in ipairs(tilePieces(face, tile)) do
          local pts = {}
          for k, t in ipairs(piece) do
            local yy = ytop - t[2]
            local zz = abs(yb - ya) > 1e-6 and (za + (zb - za) * (yy - ya) / (yb - ya)) or za
            pts[k] = { t[1], yy, zz, t[3], t[4] }
          end
          mesh:poly(pts, K.SHADE_BACK, self.name .. ".back~behind")
        end
      end
    end
  end
  for _, e in ipairs({ { x0, K.SHADE_WEST }, { x1, K.SHADE_EAST } }) do
    for k = 2, n - 1 do
      local tri = { sec[1], sec[k], sec[k + 1] }
      local flat = {}
      for j, p in ipairs(tri) do flat[j] = { zf - p[1], ytop - p[2] } end
      for _, piece in ipairs(tilePieces(flat, tile)) do
        local pts = {}
        for j, q in ipairs(piece) do pts[j] = { e[1], ytop - q[2], zf - q[1], q[3], q[4] } end
        mesh:poly(pts, e[2], self.name .. ".side~behind")
      end
    end
  end
end

--- A block whose section (z, y) runs across from x0 to x1; faces turned up or south projected,
--- north slopes the front mirrored about the ridge, the rest `side` = { u0, u1, foot }.
function K.SectionPrism(name, section, x0, x1, side)
  return { name = name, sec = section, x0 = x0, x1 = x1, side = side, emit = sectionPrismEmit }
end

local function planHipEmit(self, mesh)
  local x0, x1, z0, z1, ye = self.x0, self.x1, self.z0, self.z1, self.ye
  local rx0, rx1, rz, ry = self.rx0, self.rx1, self.rz, self.ry
  local a, b, c, d = { x0, ye, z1 }, { x1, ye, z1 }, { x1, ye, z0 }, { x0, ye, z0 }
  local r0, r1 = { rx0, ry, rz }, { rx1, ry, rz }
  local faces = { { a, b, r1, r0 }, { c, d, r0, r1 }, { d, a, r0 }, { b, c, r1 } }
  local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
  for _, f in ipairs(faces) do
    local nrm = cross3(f[1], f[2], f[#f])
    local mx, mz = 0, 0
    for _, p in ipairs(f) do mx, mz = mx + p[1], mz + p[3] end
    mx, mz = mx / #f - cx, mz / #f - cz
    if nrm[2] < 0 or (nrm[2] == 0 and nrm[1] * mx + nrm[3] * mz < 0) then nrm = { -nrm[1], -nrm[2], -nrm[3] } end
    local q = {}
    if nrm[2] + nrm[3] > 1e-6 then
      for k, p in ipairs(f) do q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
      mesh:poly(q, K.SHADE_ART, self.name)
    else
      for k, p in ipairs(f) do q[k] = { p[1], p[2], p[3], p[1], 2 * rz - p[3] - p[2] } end
      mesh:poly(q, K.SHADE_BACK, self.name .. ".back~behind")
    end
  end
end

--- A hipped roof of four flat faces over the eave rectangle x0-x1, z0-z1 at ye, its ridge from
--- rx0 to rx1 at (rz, ry): seen faces projected, the others mirrored about the ridge.
function K.PlanHip(name, x0, x1, z0, z1, ye, rx0, rx1, rz, ry)
  return { name = name, x0 = x0, x1 = x1, z0 = z0, z1 = z1, ye = ye, rx0 = rx0, rx1 = rx1, rz = rz, ry = ry,
           emit = planHipEmit }
end

--- A vertical wall along a line of the plan, its drawing projected: a and b its foot's ends (x, z),
--- ha and hb its heights there.
function K.Facet(name, a, b, ha, hb)
  return { name = name, emit = function(_, mesh)
    projPoly(mesh, { { a[1], -1, a[2] }, { b[1], -1, b[2] }, { b[1], hb, b[2] }, { a[1], ha, a[2] } },
      K.SHADE_ART, name .. ".facet")
  end }
end

--- A part moved along Y and Z, its texture with it.
function K.Moved(part, dy, dz)
  return { name = part.name, emit = function(_, mesh)
    local inner = K.mesh()
    part:emit(inner)
    for _, t in ipairs(inner.tris) do
      local o = {}
      for k = 1, 3 do
        local p = t[k]
        o[k] = { p[1], p[2] + (dy or 0), p[3] + (dz or 0), p[4], p[5] }
      end
      mesh:tri(o[1], o[2], o[3], t.shade, t.tag)
    end
  end }
end

--- A part standing on another: moved by (0, base, base), which keeps its place in the drawing.
function K.Lifted(part, base)
  return K.Moved(part, base, base)
end

-- ── Relief: a solid read column by column off its own drawing ───────────────

-- an art image: { w, h, px = { r, g, b, a, ... } } (0..1, row major)
local function alphaAt(art, u, v) return art.px[(v * art.w + u) * 4 + 4] end
K.alphaAt = alphaAt

-- parts of span (a, b) not covered by any of `others`
local function subtract(a, b, others)
  local out = { { a, b } }
  for _, o in ipairs(others) do
    local c, d = o[1], o[2]
    local nxt = {}
    for _, s in ipairs(out) do
      if d <= s[1] or c >= s[2] then nxt[#nxt + 1] = s
      else
        if c > s[1] then nxt[#nxt + 1] = { s[1], c } end
        if d < s[2] then nxt[#nxt + 1] = { d, s[2] } end
      end
    end
    out = nxt
  end
  local r = {}
  for _, s in ipairs(out) do if s[2] - s[1] > 1e-6 then r[#r + 1] = s end end
  return r
end

local function runsEqual(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then return false end end
  return true
end

local function reliefRuns(self)
  local art = self.art
  local W, H = art.w, art.h
  if self.flank_tile then H = self.flank_tile.rect[2] end
  local cols = {}
  for u = 0, W - 1 do
    local runs, v = {}, 0
    while v < H do
      if alphaAt(art, u, v) >= 0.5 then
        local v0 = v
        while v < H and alphaAt(art, u, v) >= 0.5 do v = v + 1 end
        runs[#runs + 1] = { v0, v }
      else
        v = v + 1
      end
    end
    if self.hull > 0 and #runs > 0 then
      local merged = { runs[1] }
      for k = 2, #runs do
        local last = merged[#merged]
        if runs[k][1] - last[2] <= self.hull then merged[#merged] = { last[1], runs[k][2] }
        else merged[#merged + 1] = runs[k] end
      end
      runs = merged
    end
    cols[u] = runs
  end
  if self.bridge > 0 then
    for u = 1, W - 2 do
      if #cols[u] == 0 then
        local left, right
        for k = u - 1, math.max(0, u - self.bridge), -1 do if #cols[k] > 0 then left = cols[k]; break end end
        for k = u + 1, math.min(W - 1, u + self.bridge) do if #cols[k] > 0 then right = cols[k]; break end end
        if left and right and runsEqual(left, right) then
          local c = {}
          for i, r in ipairs(left) do c[i] = { r[1], r[2] } end
          cols[u] = c
        end
      end
    end
  end
  if self.foot then
    for u = 0, W - 1 do
      local runs = cols[u]
      if #runs > 0 then cols[u] = { { runs[1][1], max(self.foot, runs[#runs][2]) } } end
    end
  end
  if self.seam then
    local rows, openN = self.seam[1], self.seam[3]
    for u = 0, W - 1 do
      local keep = {}
      for _, r in ipairs(cols[u]) do
        if r[1] < rows and not (openN[u] and r[1] == 0 and r[2] - r[1] <= self.height) then keep[#keep + 1] = r end
      end
      cols[u] = keep
    end
  end
  return cols, W
end

local function reliefTile(self, mesh, quad, origin, sdir, top, shade, tag, tile)
  local r = (tile or self.side).rect
  local t = K.Tile(r[1], r[2], r[3], r[4])
  local pts = {}
  for k, p in ipairs(quad) do
    local s = (p[1] - origin[1]) * sdir[1] + (p[3] - origin[2]) * sdir[2]
    pts[k] = { s, top - p[2], p[1], p[2], p[3] }
  end
  for _, piece in ipairs(tilePieces(pts, t)) do
    local o = {}
    for k, q in ipairs(piece) do o[k] = { q[3], q[4], q[5], q[6], q[7] } end
    mesh:poly(o, shade, tag)
  end
end

local function reliefEmit(self, mesh)
  local H, n = self.height, self.name
  local cols, W = reliefRuns(self)
  local function drawn(runs)
    local out = {}
    for k, r in ipairs(runs) do
      local va, vb = r[1], r[2]
      if vb - va - H > 0 then out[k] = { va + H, vb, H, va } else out[k] = { vb, vb, vb - va, va } end
    end
    return out
  end
  local function solid(runs)
    local out = {}
    for k, d in ipairs(drawn(runs)) do
      local z0, z1, top = d[1], d[2], d[3]
      if self.back ~= nil and top == H and self.back < z0 then z0 = self.back
      elseif self.against and top == H and z0 < self.back and self.back < z1 then z0 = self.back end
      out[k] = { z0, z1, top }
    end
    return out
  end
  local skirt = self.skirt
  local u = 0
  while u < W do
    local u1 = u + 1
    while u1 < W and runsEqual(cols[u1], cols[u]) do u1 = u1 + 1 end
    local sol, dr = solid(cols[u]), drawn(cols[u])
    for k = 1, #sol do
      local z0, z1, top = sol[k][1], sol[k][2], sol[k][3]
      local zd, va = dr[k][1], dr[k][4]
      local x0, x1 = u, u1
      local zt = max(zd, z0)
      if z1 > zt then
        projPoly(mesh, { { x0, top, zt }, { x1, top, zt }, { x1, top, z1 }, { x0, top, z1 } }, K.SHADE_ART, n .. ".top")
      end
      if zd > z0 and self.top_tile then
        local face = { { x0, 0 }, { x1, 0 }, { x1, zd - z0 }, { x0, zd - z0 } }
        for _, piece in ipairs(tilePieces(face, self.top_tile)) do
          local o = {}
          for j, q in ipairs(piece) do o[j] = { q[1], top, zd - q[2], q[3], q[4] } end
          mesh:poly(o, K.SHADE_ART, n .. ".top")
        end
      elseif zd > z0 then
        local rows = z1 - zd
        local first = rows >= 2 and va + 1 or va
        local course = max(1, rows - (first - va))
        local edge = (rows >= 2 and zd - z0 > 1) and 1 or 0
        local far = zd
        local guard = 0
        while far > z0 + edge + 1e-6 and guard < 10000 do
          guard = guard + 1
          local near
          near, far = far, max(z0 + edge, far - course)
          local va0 = first + (course - (near - far))
          local q = {}
          for j, p in ipairs({ { x0, top, far }, { x1, top, far }, { x1, top, near }, { x0, top, near } }) do
            q[j] = { p[1], p[2], p[3], p[1], va0 + (p[3] - far) }
          end
          mesh:poly(q, K.SHADE_ART, n .. ".top")
        end
        if edge > 0 then
          local q = {}
          for j, p in ipairs({ { x0, top, z0 }, { x1, top, z0 }, { x1, top, z0 + 1 }, { x0, top, z0 + 1 } }) do
            q[j] = { p[1], p[2], p[3], p[1], va + (p[3] - z0) }
          end
          mesh:poly(q, K.SHADE_ART, n .. ".top")
        end
      end
      local seamS = self.seam ~= nil and self.seam[2][u] and z1 >= self.seam[1] + H - 1e-6
      local seamN = self.seam ~= nil and self.seam[3][u] and va == 0
      local low = -skirt
      if not seamS then
        projPoly(mesh, { { x0, low, z1 }, { x1, low, z1 }, { x1, top, z1 }, { x0, top, z1 } }, K.SHADE_ART, n .. ".front")
      end
      if z1 > z0 and not seamN then
        local back = { { x1, low, z0 }, { x0, low, z0 }, { x0, top, z0 }, { x1, top, z0 } }
        if self.see_through then
          local q = {}
          for j, p in ipairs(back) do q[j] = { p[1], p[2], p[3], p[1], z1 - p[2] } end
          mesh:poly(q, K.SHADE_BACK, n .. ".back")
        elseif self.hull > 0 or (self.foot and not self.solid) or (self.proj_back and self.back == nil) then
          projPoly(mesh, back, K.SHADE_BACK, n .. ".back")
        else
          reliefTile(self, mesh, back, { x1, z0 }, { -1, 0 }, top, K.SHADE_BACK, n .. ".back")
        end
      end
    end
    u = u1
  end
  local function covered(pieces)
    local o = {}
    for _, p in ipairs(pieces) do if p[2] > p[1] then o[#o + 1] = p end end
    return o
  end
  local low = -skirt
  for uu = 0, W do
    local left = uu > 0 and covered(solid(cols[uu - 1])) or {}
    local right = uu < W and covered(solid(cols[uu])) or {}
    for _, side in ipairs({ { left, right, 1 }, { right, left, -1 } }) do
      local pieces, others, facing = side[1], side[2], side[3]
      for _, pc in ipairs(pieces) do
        local a, b, t = pc[1], pc[2], pc[3]
        local occl = {}
        for _, o in ipairs(others) do if o[3] >= t then occl[#occl + 1] = { o[1], o[2] } end end
        for _, span in ipairs(subtract(a, b, occl)) do
          local za, zb = span[1], span[2]
          local x = uu
          local edge = (uu == 0 and self.seam_x[1]) or (uu == W and self.seam_x[2]) or nil
          local skipIt = false
          if edge then
            local all = true
            local r = floor(za / 16)
            while r * 16 < zb do
              if not edge[r] then all = false; break end
              r = r + 1
            end
            if all then skipIt = true end
          end
          if not skipIt then
            if self.flank_tile and zb - za >= 16 then
              if facing > 0 then
                local k = uu
                local function spans(kk)
                  for _, o in ipairs(covered(solid(cols[kk - 1]))) do
                    if o[1] <= za + 1e-6 and o[2] >= zb - 1e-6 and o[3] >= t then return true end
                  end
                  return false
                end
                while k > 0 and spans(k) do k = k - 1 end
                x = (k + uu) / 2
                reliefTile(self, mesh, { { x, low, zb }, { x, low, za }, { x, t, za }, { x, t, zb } },
                  { x, 0 }, { 0, 1 }, t, K.SHADE_EAST, n .. ".flank", self.flank_tile)
              end
            elseif self.hull > 0 or (self.foot and not self.solid) then
              local col = min(max(uu - (facing > 0 and 1 or 0), 0), W - 1) + 0.5
              local q = {}
              for j, p in ipairs({ { x, low, za }, { x, low, zb }, { x, t, zb }, { x, t, za } }) do
                q[j] = { p[1], p[2], p[3], col, p[3] - p[2] }
              end
              mesh:poly(q, facing > 0 and K.SHADE_EAST or K.SHADE_WEST, n .. ".flank")
            elseif facing > 0 then
              reliefTile(self, mesh, { { x, low, zb }, { x, low, za }, { x, t, za }, { x, t, zb } },
                { x, zb }, { 0, -1 }, t, K.SHADE_EAST, n .. ".flank")
            else
              reliefTile(self, mesh, { { x, low, za }, { x, low, zb }, { x, t, zb }, { x, t, za } },
                { x, za }, { 0, 1 }, t, K.SHADE_WEST, n .. ".flank")
            end
          end
        end
      end
    end
  end
end

--- A solid read column by column off its own drawing (hedges, walls, railings): in every pixel
--- column a run of the drawing is the object's top and, at its south end, its front `height`
--- rows tall; the faces the drawing never shows take `side`, a tile of its own front.
--- o = { hull, bridge (railings: gaps closed down a column, across columns), foot, solid, back,
---       top_tile, against, seam = { rows, openS, openN }, flank_tile, seam_x = { west, east },
---       proj_back, skirt (default 1), see_through }
function K.Relief(name, art, height, side, o)
  o = o or {}
  return { name = name, art = art, height = height, side = side, hull = o.hull or 0, bridge = o.bridge or 0,
           foot = o.foot, solid = o.solid or (o.back ~= nil), back = o.back, top_tile = o.top_tile,
           against = o.against, seam = o.seam, flank_tile = o.flank_tile, seam_x = o.seam_x or { {}, {} },
           proj_back = o.proj_back, skirt = o.skirt or 1, see_through = o.see_through, emit = reliefEmit }
end

--- What a model paints flat on the ground in its cells: a quad per cell (or per box of it), half a
--- pixel up and lifted along the line of sight, its texture `v_offset` rows down the art.
function K.Decal(name, cells, vOffset, lift, boxes)
  lift = lift or 0.5
  boxes = boxes or {}
  return { name = name, emit = function(_, mesh)
    for _, c in ipairs(cells) do
      local i, j = c[1], c[2]
      local b = boxes[i .. "," .. j] or { 0, 0, 16, 16 }
      local x0, z0, x1, z1 = i * 16 + b[1], j * 16 + b[2], i * 16 + b[3], j * 16 + b[4]
      local q = {}
      for k, p in ipairs({ { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } }) do
        q[k] = { p[1], lift, p[2] + lift, p[1], p[2] + vOffset }
      end
      mesh:poly(q, K.SHADE_ART, name .. ".decal")
    end
  end }
end

-- ── Parts read off the art ────────────────────────────────────────────────

local function keyRGB(r, g, b) return floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5) end

--- The pixels of the ring's colours (keys, set) at a thing's foot: in each column, below its
--- lowest pixel of another colour.
function K.ringPixels(art, ring)
  local out = {}
  for x = 0, art.w - 1 do
    local foot = -1
    for y = 0, art.h - 1 do
      local o = (y * art.w + x) * 4
      if art.px[o + 4] >= 0.5 and not ring[keyRGB(art.px[o + 1], art.px[o + 2], art.px[o + 3])] then foot = y end
    end
    for y = foot + 1, art.h - 1 do
      local o = (y * art.w + x) * 4
      if art.px[o + 4] >= 0.5 and ring[keyRGB(art.px[o + 1], art.px[o + 2], art.px[o + 3])] then out[y * art.w + x] = true end
    end
  end
  return out
end

--- The texture of a part read off its art, three bands of the drawing's size: the drawing without
--- its ring; its ring alone; and the drawing grown past its outline with its own edge colours,
--- which the faces no drawing shows are laid with, so no texel they read is a hole.
function K.withRing(art, ring)
  ring = ring or {}
  local W, H = art.w, art.h
  local out = { w = W, h = H * 3, px = {} }
  for i = 1, W * H * 3 * 4 do out.px[i] = 0 end
  local foam = K.ringPixels(art, ring)
  local grown, order = {}, {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local o = (y * W + x) * 4
      if art.px[o + 4] >= 0.5 then
        local idx = y * W + x
        local dy = foam[idx] and H or 0
        local d = ((y + dy) * W + x) * 4
        for k = 1, 4 do out.px[d + k] = art.px[o + k] end
        if not foam[idx] then
          grown[idx] = { art.px[o + 1], art.px[o + 2], art.px[o + 3] }
          order[#order + 1] = idx
        end
      end
    end
  end
  local count = #order
  local edge = order
  while #edge > 0 and count < W * H do
    local nxt = {}
    for _, idx in ipairs(edge) do
      local x, y = idx % W, floor(idx / W)
      for _, n in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
        local i, j = n[1], n[2]
        if i >= 0 and i < W and j >= 0 and j < H then
          local nid = j * W + i
          if not grown[nid] then
            grown[nid] = grown[idx]
            count = count + 1
            nxt[#nxt + 1] = nid
          end
        end
      end
    end
    edge = nxt
  end
  for idx, c in pairs(grown) do
    local x, y = idx % W, floor(idx / W)
    local d = ((y + 2 * H) * W + x) * 4
    out.px[d + 1], out.px[d + 2], out.px[d + 3], out.px[d + 4] = c[1], c[2], c[3], 1
  end
  return out
end

--- A flat-faced part whose hidden faces ("~behind") read the texture `offset` rows down: the
--- drawing's grown band (withRing).
function K.Grown(part, offset)
  return { name = part.name, emit = function(_, mesh)
    local tmp = K.mesh()
    part:emit(tmp)
    for _, t in ipairs(tmp.tris) do
      local a, b, c = t[1], t[2], t[3]
      if t.tag and t.tag:find("~behind", 1, true) then
        a = { a[1], a[2], a[3], a[4], a[5] + offset }
        b = { b[1], b[2], b[3], b[4], b[5] + offset }
        c = { c[1], c[2], c[3], c[4], c[5] + offset }
      end
      mesh:tri(a, b, c, t.shade, t.tag)
    end
  end }
end

--- A thing of leaves (a potted plant, bicycles) as a card at its foot facing the GBA camera, its
--- drawing projected. `art` the piece's own image; `foot` the row it stands on; `voff` the rows
--- below the model's drawing where the card's pixels are; `base` lifted onto what it stands on;
--- `span` = { u0, u1, v0 } its extent where the art's own pixels are not all of it.
function K.Card(name, art, foot, voff, base, span)
  voff, base = voff or 0, base or 0
  return { name = name, emit = function(_, mesh)
    local u0, u1, v0
    if span then
      u0, u1, v0 = span[1], span[2], span[3]
    else
      local cmin, cmax, rmin = math.huge, -math.huge, math.huge
      for v = 0, art.h - 1 do
        for u = 0, art.w - 1 do
          if art.px[(v * art.w + u) * 4 + 4] >= 0.5 then
            cmin, cmax, rmin = min(cmin, u), max(cmax, u), min(rmin, v)
          end
        end
      end
      if cmin == math.huge then return end
      u0, u1, v0 = cmin, cmax + 1, rmin
    end
    local f, b = foot, base
    local h = f - v0
    local q = {}
    for k, p in ipairs({ { u0, b - 1, f + b }, { u1, b - 1, f + b }, { u1, b + h, f + b }, { u0, b + h, f + b } }) do
      q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] + voff }
    end
    mesh:poly(q, K.SHADE_ART, name .. ".card")
  end }
end

--- A superellipse plan polygon (x, z), its corners rounded.
function K.roundedPlan(cx, cz, rx, rz, p, n)
  p, n = p or 4, n or 32
  local pts = {}
  for k = 0, n - 1 do
    local t = 2 * pi * k / n
    local c, s_ = cos(t), sin(t)
    local sc = c < 0 and -1 or 1
    local ss = s_ < 0 and -1 or 1
    pts[#pts + 1] = { cx + rx * sc * abs(c) ^ (2 / p), cz + rz * ss * abs(s_) ^ (2 / p) }
  end
  return pts
end

--- A plan polygon (x, z): the rectangle with its corners cut `cut`.
function K.octagon(x0, x1, z0, z1, cut)
  return { { x0 + cut, z0 }, { x1 - cut, z0 }, { x1, z0 + cut }, { x1, z1 - cut }, { x1 - cut, z1 },
           { x0 + cut, z1 }, { x0, z1 - cut }, { x0, z0 + cut } }
end

--- A spec's flat-faced parts on the drawing with its grown band: parts_art(art) -> parts, texture.
function K.flat(make)
  return function(art)
    local tex = K.withRing(art, {})
    local parts = {}
    for i, p in ipairs(make(art)) do parts[i] = K.Grown(p, 2 * art.h) end
    return parts, tex
  end
end

-- ── Model ─────────────────────────────────────────────────────────────────

--- A model's mesh from its parts.
function K.build(parts)
  local mesh = K.mesh()
  for _, p in ipairs(parts) do p:emit(mesh) end
  return mesh
end

return K
