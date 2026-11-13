-- Round things read off their own drawing (Battle Scene: Overworld): the building kernel's
-- solids. A Volume is a rough shape (a dome, a drum, a tube...), HeightSolid cuts it to its
-- drawing column by column so that at 45 degrees it is the drawing pixel for pixel, and the Proj*
-- parts are smooth surfaces with the drawing projected on them (a boat's hull, a parasol's canopy,
-- a sun lounger's frame), its transparency cutting their outline.
--
-- Ported from Emerald 3DS's scripts/voxel_building.py (by Zallax and contributors, CC BY-NC-SA
-- 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE): Volume, HeightSolid, own_bands,
-- ProjSection, ProjHull, ProjCanopy, catmull, and for the rooms' furniture ProjDome, ProjLathe,
-- ProjRun, Ribbon and gen_voxel_buildings.py's ViewHull, with the same arithmetic, so a model built here
-- is the generator's triangle for triangle.

return function(K)

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local sin, cos, atan2, pi = math.sin, math.cos, math.atan2, math.pi
local SHADE_ART, SHADE_BACK, SHADE_EAST, SHADE_WEST = K.SHADE_ART, K.SHADE_BACK, K.SHADE_EAST, K.SHADE_WEST
local INF = math.huge

local function drawnAt(art, u, v) return art.px[(v * art.w + u) * 4 + 4] >= 0.5 end

local function cross(a, b, c)
  local e1x, e1y, e1z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local e2x, e2y, e2z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
  return e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
end

-- a triangle wound to face `normal` (PlanPrism._tri)
local function triFacing(mesh, a, b, c, nx, ny, nz, shade, tag)
  local x, y, z = cross(a, b, c)
  if x * nx + y * ny + z * nz < 0 then b, c = c, b end
  mesh:tri(a, b, c, shade, tag)
end

local function inPoly(poly, x, y)
  local inside, n = false, #poly
  for i = 1, n do
    local a, b = poly[i], poly[i % n + 1]
    if (a[2] > y) ~= (b[2] > y) and x < a[1] + (y - a[2]) * (b[1] - a[1]) / (b[2] - a[2]) then
      inside = not inside
    end
  end
  return inside
end
K.inPoly = inPoly

--- n + 1 points along a Catmull-Rom curve through pts (any dimension).
function K.catmull(pts, n)
  local P = { pts[1] }
  for i = 1, #pts do P[#P + 1] = pts[i] end
  P[#P + 1] = pts[#pts]
  local out = {}
  for k = 0, n do
    local s = (#pts - 1) * k / n
    local i = min(floor(s), #pts - 2)
    local t = s - i
    local p0, p1, p2, p3 = P[i + 1], P[i + 2], P[i + 3], P[i + 4]
    local q = {}
    for d = 1, #p1 do
      q[d] = 0.5 * ((2 * p1[d]) + (-p0[d] + p2[d]) * t
                    + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * t * t
                    + (-p0[d] + 3 * p1[d] - 3 * p2[d] + p3[d]) * t ^ 3)
    end
    out[#out + 1] = q
  end
  return out
end

-- ── Volume: a rough solid a drawing is laid on ─────────────────────────────

local Volume = {}
Volume.__index = Volume

function K.Volume() return setmetatable({ shapes = {}, holes = {} }, Volume) end

local function add(self, f)
  self.shapes[#self.shapes + 1] = f
  return self
end

--- A dome on a superellipse plan, its sections half ellipses.
function Volume:dome(cx, cz, rx, rz, h, p, y0)
  p, y0 = p or 2.0, y0 or 0.0
  local top = y0 + h
  return add(self, function(x, y, z)
    -- outside its box it is outside the dome (exactly: a term past 1 alone puts it outside)
    if y < y0 or y > top then return false end
    local dx, dz = abs(x - cx), abs(z - cz)
    if dx > rx or dz > rz then return false end
    local q = (dx / rx) ^ p + (dz / rz) ^ p
    return q ^ (2.0 / p) + ((y - y0) / h) ^ 2 <= 1.0
  end)
end

--- An upright drum, a frustum on ellipses.
function Volume:drum(cx, cz, rx0, rz0, rx1, rz1, y0, y1)
  return add(self, function(x, y, z)
    if not (y0 <= y and y <= y1) then return false end
    local k = (y - y0) / (y1 - y0)
    local rx, rz = rx0 + (rx1 - rx0) * k, rz0 + (rz1 - rz0) * k
    return ((x - cx) / rx) ^ 2 + ((z - cz) / rz) ^ 2 <= 1.0
  end)
end

--- A tube along a curve through pts: { x, y, z } with `radius`, or { x, y, z, radius }.
function Volume:tube(pts, radius, n)
  n = n or 48
  local src = {}
  for i, p in ipairs(pts) do src[i] = #p == 3 and { p[1], p[2], p[3], radius } or p end
  local path = K.catmull(src, n)
  local segs = {}
  for i = 1, n do segs[i] = { path[i], path[i + 1] } end
  local lo, hi = {}, {}
  for d = 1, 3 do
    local l, h = INF, -INF
    for _, s in ipairs(segs) do
      local a, b = s[1], s[2]
      local r = max(a[4], b[4])
      l = min(l, min(a[d], b[d]) - r)
      h = max(h, max(a[d], b[d]) + r)
    end
    lo[d], hi[d] = l, h
  end
  return add(self, function(x, y, z)
    local q = { x, y, z }
    for d = 1, 3 do if q[d] < lo[d] or q[d] > hi[d] then return false end end
    for _, s in ipairs(segs) do
      local a, b = s[1], s[2]
      local d1, d2, d3 = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local dd = d1 * d1 + d2 * d2 + d3 * d3
      if dd == 0 then dd = 1e-9 end
      local t = max(0.0, min(1.0, ((x - a[1]) * d1 + (y - a[2]) * d2 + (z - a[3]) * d3) / dd))
      local r = a[4] + (b[4] - a[4]) * t
      local ex, ey, ez = x - a[1] - d1 * t, y - a[2] - d2 * t, z - a[3] - d3 * t
      if ex * ex + ey * ey + ez * ez <= r * r then return true end
    end
    return false
  end)
end

--- An upright prism on a superellipse plan; its top rises `sheer` to the ends along x, its
--- bottom `keel`.
function Volume:slab(cx, cz, rx, rz, y0, y1, p, sheer, keel)
  p, sheer, keel = p or 2.0, sheer or 0.0, keel or 0.0
  return add(self, function(x, y, z)
    local k = (x - cx) / rx
    return y0 + keel * k ^ 4 <= y and y <= y1 + sheer * k * k
      and abs(k) ^ p + (abs(z - cz) / rz) ^ p <= 1.0
  end)
end

--- An upright plate between z0 and z1, its outline `poly` in (x, y).
function Volume:plate(poly, z0, z1)
  return add(self, function(x, y, z)
    if not (z0 <= z and z <= z1) then return false end
    return inPoly(poly, x, y)
  end)
end

--- A turned thing: `profile` lists (y, radius) up it; its plan an ellipse `squash` as deep as wide.
function Volume:lathe(cx, cz, profile, squash)
  squash = squash or 1.0
  local ys = {}
  for i, p in ipairs(profile) do ys[i] = p[1] end
  return add(self, function(x, y, z)
    if not (ys[1] <= y and y <= ys[#ys]) then return false end
    local k = 1
    for i = 1, #ys do if ys[i] <= y then k = i end end
    local r
    if k == #ys then r = profile[k][2]
    else
      local ya, ra, yb, rb = profile[k][1], profile[k][2], profile[k + 1][1], profile[k + 1][2]
      r = ra + (rb - ra) * (y - ya) / (yb - ya)
    end
    if r <= 0 then return false end
    return ((x - cx) / r) ^ 2 + ((z - cz) / (squash * r)) ^ 2 <= 1.0
  end)
end

--- A prism across x from x0 to x1, its section `poly` in (z, y).
function Volume:profile(poly, x0, x1)
  return add(self, function(x, y, z)
    if not (x0 <= x and x <= x1) then return false end
    return inPoly(poly, z, y)
  end)
end

--- A pyramid on a regular polygon, its plan squashed to rx by rz, standing at y0, `h` high.
function Volume:pyramid(cx, cz, rx, rz, y0, h, sides)
  sides = sides or 6
  return add(self, function(x, y, z)
    if not (y0 <= y and y <= y0 + h) then return false end
    local k = 1.0 - (y - y0) / h
    local dx, dz = (x - cx) / (rx * k + 1e-9), (z - cz) / (rz * k + 1e-9)
    local ang = atan2(dz, dx)
    local sector = 2 * pi / sides
    local a = (ang % sector) - sector / 2
    return sqrt(dx * dx + dz * dz) * cos(a) <= cos(sector / 2)
  end)
end

--- An upright prism on a plan polygon (x, z).
function Volume:prism(plan, y0, y1)
  return add(self, function(x, y, z)
    if not (y0 <= y and y <= y1) then return false end
    return inPoly(plan, x, z)
  end)
end

--- A hipped roof over the rectangle, from its eaves at y0 rising `rise` per pixel in from every
--- side (to `ymax` at most).
function Volume:hip(x0, x1, z0, z1, y0, rise, ymax)
  return add(self, function(x, y, z)
    if not (x0 <= x and x <= x1 and z0 <= z and z <= z1) or y < y0 then return false end
    local top = y0 + rise * min(x - x0, x1 - x, z - z0, z1 - z)
    if ymax then top = min(top, ymax) end
    return y <= top
  end)
end

function Volume:box(x0, x1, y0, y1, z0, z1)
  return add(self, function(x, y, z)
    return x0 <= x and x <= x1 and y0 <= y and y <= y1 and z0 <= z and z <= z1
  end)
end

--- Takes a shape out: `method` is one of these methods' names, given its own arguments.
function Volume:hollow(method, ...)
  local n = #self.shapes
  self[method](self, ...)
  for i = n + 1, #self.shapes do
    self.holes[#self.holes + 1] = self.shapes[i]
    self.shapes[i] = nil
  end
  return self
end

function Volume:inside(x, y, z)
  local hit = false
  for _, f in ipairs(self.shapes) do if f(x, y, z) then hit = true break end end
  if not hit then return false end
  for _, f in ipairs(self.holes) do if f(x, y, z) then return false end end
  return true
end

--- A texture of withRing with one more band per part: the drawing grown out of that part's own
--- pixels only (`parts`: list of { name, test(u, v) }), so a part's hidden faces never take
--- another part's colours. Returns the texture and each part's band index.
function K.ownBands(tex, rows, parts)
  local W = tex.w
  local out = { w = W, h = rows * (3 + #parts), px = {} }
  local px = out.px
  for i = 1, W * out.h * 4 do px[i] = 0 end
  for i = 1, #tex.px do px[i] = tex.px[i] end
  local index = {}
  for k, part in ipairs(parts) do
    local name, mine = part[1], part[2]
    local art = { w = W, h = rows, px = {} }
    for i = 1, W * rows * 4 do art.px[i] = 0 end
    for v = 0, rows - 1 do
      for u = 0, W - 1 do
        local o = (v * W + u) * 4
        if tex.px[o + 4] >= 0.5 and mine(u, v) then
          for c = 1, 4 do art.px[o + c] = tex.px[o + c] end
        end
      end
    end
    local grown = K.withRing(art, {})
    local base = (2 + k) * rows
    for v = 0, rows - 1 do
      for u = 0, W - 1 do
        local s, d = ((v + 2 * rows) * W + u) * 4, ((v + base) * W + u) * 4
        for c = 1, 4 do px[d + c] = grown.px[s + c] end
      end
    end
    index[name] = 2 + k
  end
  return out, index
end

-- ── HeightSolid: a drawn round thing as a height field over its plan ──────────

-- the steps a spec asks of every HeightSolid built for it (its "lod": step, cell, tol)
K.HEIGHTSOLID_LOD = nil

local HS = {}
HS.__index = HS

--- A drawn round thing as a height field over its plan, exact at 45 degrees and closed: `volume`
--- gives its shape, the drawing (`art`, its first `rows` rows; the texture of withRing) cuts it
--- column by column. o = { step, depth = { z0, z1 }, mask(u, v), tmax, mirror_z, lift, band, cell,
--- tol, behind(u, v), hang = { u... }, side, open_top, lean }.
function K.HeightSolid(name, art, rows, volume, o)
  o = o or {}
  local self = setmetatable({}, HS)
  local step, cell, tol = o.step or 2, o.cell or 2, o.tol or 1
  local lod = K.HEIGHTSOLID_LOD
  if lod then
    step = max(step, lod[1])
    cell, tol = max(cell, lod[2]), max(tol, lod[3])
  end
  self.lift, self.cell, self.tol = o.lift or 0.0, cell, tol
  self.lean = o.lean
  self.open_top = o.open_top or false
  self.side = o.side
  self.hang = {}
  for _, u in ipairs(o.hang or {}) do self.hang[u] = true end
  self.behind = o.behind or function() return false end
  self.name, self.art, self.rows, self.vol = name, art, rows, volume
  self.step, self.depth, self.tmax, self.mirror_z = step, o.depth or { 0.0, 80.0 }, o.tmax or 96.0, o.mirror_z
  self.mask = o.mask or function() return false end
  self.band = (o.band or 2) * rows
  return self
end

function HS:_top(x, z)
  local vol = self.vol
  local y = self.tmax
  while y >= 0 and not vol:inside(x, y, z) do y = y - 1.0 end
  if y < 0 then return 0.0 end
  local lo, hi = y, y + 1.0
  for _ = 1, 7 do
    local m = (lo + hi) / 2
    if vol:inside(x, m, z) then lo = m else hi = m end
  end
  return lo
end

-- per pixel column: { first drawn row (or -1e9), foot row or nil, first own row }
function HS:_runs()
  local W, H, art = self.art.w, self.rows, self.art
  local runs = {}
  for u = 0, W - 1 do
    local own = {}
    for y = 0, H - 1 do
      if drawnAt(art, u, y) and not self.mask(u, y) and not self.behind(u, y) then own[#own + 1] = y end
    end
    if #own > 0 then
      local first, last = own[1], own[#own]
      local top = first - 1 >= 0 and drawnAt(art, u, first - 1) and self.mask(u, first - 1)
      local foot = self.hang[u] or (last + 1 < H and drawnAt(art, u, last + 1) and self.mask(u, last + 1))
      if self.open_top and first == 0 then top = true end
      runs[u] = { top and -1e9 or first, (not foot) and (last + 1) or nil, first }
    end
  end
  return runs
end

-- one edge of a cell, the volume cut to its columns' drawing: nil where the volume is not there
function HS:_edge(col0, zs, vt, vf)
  local n = #zs
  local col = {}
  for j = 1, n do col[j] = col0[j] end
  if vf then
    for j = 1, n do if zs[j] > vf then col[j] = 0.0 end end
  end
  vt = vt - 0.5
  local any = false
  for j = 1, n do
    local h = col[j]
    col[j] = h > 0 and max(0.0, min(h, zs[j] - vt)) or 0.0
    if col[j] > 0 then any = true end
  end
  if not any then return nil end
  if vf then
    local last
    for j = 1, n do if col[j] > 0 then last = j end end
    local cl = col[last]
    for j = 1, n do if zs[last] < zs[j] and zs[j] <= vf then col[j] = cl end end
  end
  local function shortOf()
    local m = INF
    for j = 1, n do if col[j] > 0 then m = min(m, zs[j] - col[j]) end end
    return m - vt
  end
  local short = shortOf()
  if short > 0.01 and vt > -1e8 then
    local first
    for j = 1, n do if col[j] > 0 then first = j break end end
    local h0 = col[first]
    if zs[first] - (vt + h0) <= 6.0 then
      for j = 1, n do
        if vt + h0 - 1e-6 <= zs[j] and zs[j] < zs[first] then col[j] = h0 end
      end
    end
    short = shortOf()
    if short > 0.01 then
      for j = 1, n do col[j] = col[j] > 0 and min(zs[j] - vt, col[j] + short) or 0.0 end
    end
  end
  return col
end

--- The plan's cells { x0, x1, edgeA, edgeB }, and the depths zs they are sampled at.
function HS:cells()
  local W, st = self.art.w, self.step
  local runs = self:_runs()
  local z0, z1 = self.depth[1], self.depth[2]
  local inner = {}
  for j = 0, floor((z1 - z0) / st) do inner[#inner + 1] = z0 + j * st end
  local zs = { z0 - 1e-3 }
  for _, z in ipairs(inner) do zs[#zs + 1] = z end
  zs[#zs + 1] = z1 + 1e-3
  local n = #zs
  local cache = {}
  local function profile(x)
    local p = cache[x]
    if not p then
      p = { 0.0 }
      for _, z in ipairs(inner) do p[#p + 1] = self:_top(x, z) end
      p[#p + 1] = 0.0
      cache[x] = p
    end
    return p
  end
  local tol = self.tol
  local out, spans = {}, {}
  local u = 0
  while u < W do
    local w = 1
    if u + 1 < W and runs[u] and runs[u + 1] then
      local a, b = runs[u], runs[u + 1]
      if abs(a[1] - b[1]) <= tol and (a[2] == nil) == (b[2] == nil)
          and (a[2] == nil or abs(a[2] - b[2]) <= tol) then
        w = 2
        while w < self.cell and runs[u + w] and abs(runs[u + w][1] - a[1]) <= tol
            and (runs[u + w][2] == nil) == (a[2] == nil)
            and (a[2] == nil or abs(runs[u + w][2] - a[2]) <= tol) do
          w = w + 1
        end
      end
    end
    local cols = {}
    for k = u, u + w - 1 do if runs[k] then cols[#cols + 1] = runs[k] end end
    if #cols > 0 then
      local vt, nfeet, vf = INF, 0, -INF
      for _, c in ipairs(cols) do
        vt = min(vt, c[1])
        if c[2] then nfeet, vf = nfeet + 1, max(vf, c[2]) end
      end
      if nfeet ~= #cols then vf = nil end
      local edges = { self:_edge(profile(u), zs, vt, vf), self:_edge(profile(u + w), zs, vt, vf) }
      if edges[1] == nil and edges[2] == nil then
        -- drawn, but the volume is not there: a sliver a pixel thick standing at the foot
        local first, endv = INF, vf
        for _, c in ipairs(cols) do first = min(first, c[3]) end
        if not endv then
          endv = -INF
          for _, c in ipairs(cols) do endv = max(endv, c[2] or c[3] + 1) end
        end
        local e = {}
        for j = 1, n do e[j] = (endv - 1.0 <= zs[j] and zs[j] <= endv) and (endv - first) or 0.0 end
        edges = { e, e }
      end
      if edges[1] == nil then edges[1] = edges[2] end
      if edges[2] == nil then edges[2] = edges[1] end
      if vt > -1e8 then
        -- the middle of the cell must reach the drawn top too
        local lo = vt - 0.5
        local a, b = {}, {}
        for j = 1, n do a[j], b[j] = edges[1][j], edges[2][j] end
        local mv, mk = nil, nil
        for j = 1, n do
          if a[j] > 0 or b[j] > 0 then
            local m = zs[j] - (a[j] + b[j]) / 2.0
            if mv == nil or m < mv then mv, mk = m, j end
          end
        end
        if mv and mv > lo + 0.01 then
          if zs[mk] - lo - max(a[mk], b[mk]) <= 6.0 then
            a[mk] = max(a[mk], zs[mk] - lo)
            b[mk] = max(b[mk], zs[mk] - lo)
            edges = { a, b }
          end
        end
      end
      out[#out + 1] = { u, u + w, edges[1], edges[2] }
      spans[u] = { vt, vf }
    end
    u = u + w
  end
  if self.lean then out = self:_leaned(zs, out, spans) end
  return zs, out
end

function HS:_leaned(zs, cells, spans)
  local s = self.lean
  local n = #zs
  local ends = {}
  for j = 1, n do
    local lo, hi = INF, -INF
    for _, c in ipairs(cells) do
      if c[3][j] > 0 then lo, hi = min(lo, c[1]), max(hi, c[1]) end
      if c[4][j] > 0 then lo, hi = min(lo, c[2]), max(hi, c[2]) end
    end
    ends[j] = lo <= hi and { lo, hi } or false
  end
  local out = {}
  for _, c in ipairs(cells) do
    local x0, x1, a, b = c[1], c[2], c[3], c[4]
    local sp = spans[x0]
    local vt, vf = sp[1], sp[2]
    local na, nb = {}, {}
    for _, item in ipairs({ { a, na, x0 }, { b, nb, x1 } }) do
      local col, new, x = item[1], item[2], item[3]
      local leaned = false
      for j = 1, n do
        local h = col[j]
        if h > 0 and ends[j] then
          local lo, hi = ends[j][1], ends[j][2]
          local cap = min(max(0.25, s * (x - lo)), max(0.25, s * (hi - x)))
          if cap < h then h, leaned = cap, true end
        end
        new[j] = h
      end
      if leaned and vt > -1e8 then
        local foot = vf
        if not foot then
          foot = -INF
          for j = 1, n do if new[j] > 0 then foot = max(foot, zs[j]) end end
        end
        for j = 1, n do
          if vt - 0.5 <= zs[j] and zs[j] <= foot and new[j] <= 0 then new[j] = 0.25 end
        end
      end
    end
    out[#out + 1] = { x0, x1, na, nb }
  end
  return out
end

-- whether the drawing's pixel at (u, v) is someone else's
function HS:_theirs(u, v)
  local W = self.art.w
  u = min(W - 1, max(0, u >= 0 and floor(u) or -floor(-u)))
  v = min(self.rows - 1, max(0, v >= 0 and floor(v) or -floor(-v)))
  return drawnAt(self.art, u, v) and self.mask(u, v)
end

-- a texel for a step's wall: in a drawn column, within its drawn rows
function HS:_held(u, v, x)
  local spans = self._spans
  if not spans or next(spans) == nil then return u, v end
  local W = self.art.w
  local k = floor(min(W - 1, max(0, u)))
  if not spans[k] then
    local way = x > u and 1 or -1
    while k >= 0 and k < W and not spans[k] do k = k + way end
    if not spans[k] then return u, v end
    u = k + 0.5
  end
  local a, b = spans[k][1], spans[k][2]
  return u, min(max(v, a + 0.5), b - 0.5)
end

local function lifted(mesh, L)
  return { tri = function(_, a, b, c, shade, tag)
    local q = {}
    for k, p in ipairs({ a, b, c }) do q[k] = { p[1], p[2] + L, p[3] + L, p[4], p[5] } end
    mesh:tri(q[1], q[2], q[3], shade, tag)
  end }
end

function HS:_floor(mesh, zs, cells)
  local W = self.art.w
  for _, c in ipairs(cells) do
    local x0, x1, ca, cb = c[1], c[2], c[3], c[4]
    for j = 1, #zs - 1 do
      if ca[j] > 0 or cb[j] > 0 or ca[j + 1] > 0 or cb[j + 1] > 0 then
        local q = {}
        for k, p in ipairs({ { x0, zs[j] }, { x0, zs[j + 1] }, { x1, zs[j + 1] }, { x1, zs[j] } }) do
          local x, z = p[1], p[2]
          q[k] = { x, 0.0, z, min(W - 1e-3, max(0.0, x)), min(self.rows - 1e-3, max(0.0, z)) + self.band }
        end
        for _, t in ipairs({ { q[1], q[2], q[3] }, { q[1], q[3], q[4] } }) do
          local a, b, cc = t[1], t[2], t[3]
          local _, ny = cross(a, b, cc)
          if ny > 0 then b, cc = cc, b end
          mesh:tri(a, b, cc, SHADE_BACK, self.name .. ".under~behind~proj")
        end
      end
    end
  end
end

function HS:_wall(mesh, zs, x, top, bottom, tex, side, outer)
  if outer == nil then outer = true end
  local shade = side > 0 and SHADE_EAST or SHADE_WEST
  local n = #zs
  local lmin, lmax
  for j = 1, n do
    if top[j] - bottom[j] >= 0.05 then
      lmin = lmin or j
      lmax = j
    end
  end
  if not lmin then return end
  local tag = self.name .. ".wall~behind~proj"
  local function emitQuad(q)
    for _, t in ipairs({ { q[1], q[2], q[3] }, { q[1], q[3], q[4] } }) do
      local a, b, c = t[1], t[2], t[3]
      local nx, ny, nz = cross(a, b, c)
      if nx * nx + ny * ny + nz * nz >= 1e-12 then
        if nx * side < 0 then b, c = c, b end
        mesh:tri(a, b, c, shade, tag)
      end
    end
  end
  local deep = zs[lmax] - zs[lmin]
  if self.side == nil or not outer or deep <= 6.0 then
    if deep <= 6.0 then shade = SHADE_ART end
    local zf = zs[lmax]
    local W = self.art.w
    local way = side
    if outer then
      local e = x + side * deep
      if not (0.0 <= e and e <= W) then way = -side end
    end
    for j = 1, n - 1 do
      if not (top[j] - bottom[j] < 0.05 and top[j + 1] - bottom[j + 1] < 0.05) then
        local pts = { { x, bottom[j], zs[j] }, { x, bottom[j + 1], zs[j + 1] },
                      { x, top[j + 1], zs[j + 1] }, { x, top[j], zs[j] } }
        local q = {}
        for k, p in ipairs(pts) do
          local hu, hv = self:_held(x + way * (zf - p[3]) - 0.5 * way, p[3] - p[2], x)
          local tu, tv = tex(x, hu, hv)
          q[k] = { p[1], p[2], p[3], tu, tv }
        end
        emitQuad(q)
      end
    end
    return
  end
  local zf = zs[lmax]
  local P, vfoot, u_at
  if #self.side == 3 then
    local u0, u1, foot = self.side[1], self.side[2], self.side[3]
    P, vfoot = u1 - u0, foot
    u_at = function(k) if side < 0 then return u0 + k end return u1 - 1e-3 - k end
  else
    local a, b = self.side[1], self.side[2]
    P, vfoot = b - a, zf
    u_at = function(k) if side < 0 then return x + a + k end return x - 1e-3 - a - k end
  end
  local function lerp(arr, j, g) return arr[j] + (arr[j + 1] - arr[j]) * g end
  for j = 1, n - 1 do
    if not (top[j] - bottom[j] < 0.05 and top[j + 1] - bottom[j + 1] < 0.05) then
      local za, zb = zs[j], zs[j + 1]
      local cuts, seen = { za }, { [za] = true }
      if not seen[zb] then cuts[#cuts + 1], seen[zb] = zb, true end
      local k = floor((zf - zb) / P) + 1
      while k * P < zf - za - 1e-6 do
        local c = zf - k * P
        if not seen[c] then cuts[#cuts + 1], seen[c] = c, true end
        k = k + 1
      end
      table.sort(cuts)
      for i = 1, #cuts - 1 do
        local c0, c1 = cuts[i], cuts[i + 1]
        local g0, g1 = (c0 - za) / (zb - za), (c1 - za) / (zb - za)
        local base = floor((zf - (c0 + c1) / 2.0) / P) * P
        local pts = { { x, lerp(bottom, j, g0), c0 }, { x, lerp(bottom, j, g1), c1 },
                      { x, lerp(top, j, g1), c1 }, { x, lerp(top, j, g0), c0 } }
        local q = {}
        for kk, p in ipairs(pts) do
          local tu, tv = tex(x, u_at(min(P - 1e-3, max(0.0, zf - p[3] - base))), vfoot - p[2])
          q[kk] = { p[1], p[2], p[3], tu, tv }
        end
        emitQuad(q)
      end
    end
  end
end

function HS:emit(mesh)
  if self.lift ~= 0 then mesh = lifted(mesh, self.lift) end
  local zs, cells = self:cells()
  self.grid = { zs, cells }
  if self.lift ~= 0 then self:_floor(mesh, zs, cells) end
  local n = #zs
  local W, rows, art = self.art.w, self.rows, self.art
  local zc = self.mirror_z
  local spans = {}
  for u = 0, W - 1 do
    local a, b
    for r = 0, rows - 1 do
      if drawnAt(art, u, r) and not self.mask(u, r) and not self.behind(u, r) then
        a = a or r
        b = r + 1
      end
    end
    if a then spans[u] = { a, b } end
  end
  self._spans = spans
  local dz = zs[2] - zs[1]

  local function visible(col, j)
    local h, z = col[j], zs[j]
    if h <= 0 then return false end
    for k = j + 1, n do
      if not (col[k] < h + (zs[k] - z) - 1e-6) then return false end
    end
    return true
  end

  local function mirrored(col, x, h, z)
    if zc == nil then return z - h end
    local zm = min(zs[n], max(zs[1], 2 * zc - z))
    local j = min(n - 2, floor((zm - zs[1]) / dz))      -- 0-based, as the generator has it
    local g = (zm - zs[j + 1]) / dz
    local v = zm - (col[j + 1] * (1 - g) + col[j + 2] * g)
    local u = min(W - 1, max(0, x >= 0 and floor(x) or -floor(-x)))
    v = min(v, rows - 1.0)
    while v > 0 and self.mask(u, v >= 0 and floor(v) or -floor(-v)) do v = v - 1.0 end
    local span = spans[u]
    if span then v = min(max(v, span[1] + 0.5), span[2] - 0.5) end
    return v
  end

  local band = self.band
  local function tex(_, u_in, v)
    return min(W - 1e-3, max(0.0, u_in)), min(rows - 1e-3, max(0.0, v)) + band
  end

  local tagFront, tagBack = self.name .. "~proj", self.name .. ".back~behind~proj"
  local R2 = sqrt(2.0)
  for _, c in ipairs(cells) do
    local x0, x1, ca, cb = c[1], c[2], c[3], c[4]
    local va, vb = {}, {}
    for j = 1, n do va[j], vb[j] = visible(ca, j), visible(cb, j) end
    for j = 1, n - 1 do
      if ca[j] > 0 or cb[j] > 0 or cb[j + 1] > 0 or ca[j + 1] > 0 then
        local pts = { { x0, ca[j], zs[j] }, { x1, cb[j], zs[j] }, { x1, cb[j + 1], zs[j + 1] },
                      { x0, ca[j + 1], zs[j + 1] } }
        local cols = { ca, cb, cb, ca }
        local front = va[j] or vb[j] or va[j + 1] or vb[j + 1]
        local qb = {}
        for k, p in ipairs(pts) do
          local tu, tv = tex(p[1], p[1], mirrored(cols[k], p[1], p[2], p[3]))
          qb[k] = { p[1], p[2], p[3], tu, tv }
        end
        local q
        if front then
          q = {}
          for k, p in ipairs(pts) do q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
          local uc, vc = 0, 0
          for _, p in ipairs(pts) do uc, vc = uc + p[1], vc + (p[3] - p[2]) end
          uc, vc = uc / 4.0, vc / 4.0
          local all = self:_theirs(uc, vc)
          if all then
            for _, p in ipairs(pts) do
              if not self:_theirs(0.75 * p[1] + 0.25 * uc, 0.75 * (p[3] - p[2]) + 0.25 * vc) then
                all = false
                break
              end
            end
          end
          if all then
            for k, p in ipairs(pts) do
              local tu, tv = tex(p[1], p[1], p[3] - p[2])
              q[k] = { p[1], p[2], p[3], tu, tv }
            end
          end
        else
          q = qb
        end
        for _, k3 in ipairs({ { 1, 2, 3 }, { 1, 3, 4 } }) do
          local t1, t2, t3 = q[k3[1]], q[k3[2]], q[k3[3]]
          local edgeOn = false
          if front then
            local lo, hi = INF, -INF
            for _, k in ipairs(k3) do
              local d = pts[k][3] - pts[k][2]
              lo, hi = min(lo, d), max(hi, d)
            end
            if hi - lo < 0.25 then
              t1, t2, t3 = qb[k3[1]], qb[k3[2]], qb[k3[3]]
              edgeOn = true
            end
          end
          local nx, ny, nz = cross(t1, t2, t3)
          local L = sqrt(nx * nx + ny * ny + nz * nz)
          if L >= 1e-9 then
            if ny < 0 then
              t2, t3 = t3, t2
              nx, ny, nz = -nx, -ny, -nz
            end
            if front and not edgeOn then
              mesh:tri(t1, t2, t3, SHADE_ART, tagFront)
            else
              local f = (ny + nz) / (L * R2)
              local s = SHADE_BACK + (SHADE_ART - SHADE_BACK) * max(0.0, min(1.0, 0.5 + 0.5 * f))
              mesh:tri(t1, t2, t3, s, tagBack)
            end
          end
        end
      end
    end
  end
  -- upright walls: between cells whose heights part, and at the ends
  local flat = {}
  for j = 1, n do flat[j] = 0.0 end
  local nc = #cells
  for k = 0, nc do
    local left = k > 0 and cells[k] or nil
    local right = k < nc and cells[k + 1] or nil
    if left and right and left[2] ~= right[1] then
      self:_wall(mesh, zs, left[2], left[4], flat, tex, 1)
      self:_wall(mesh, zs, right[1], right[3], flat, tex, -1)
    elseif left == nil and right ~= nil then
      self:_wall(mesh, zs, right[1], right[3], flat, tex, -1)
    elseif right == nil and left ~= nil then
      self:_wall(mesh, zs, left[2], left[4], flat, tex, 1)
    elseif left and right then
      local lo = {}
      for j = 1, n do lo[j] = min(left[4][j], right[3][j]) end
      self:_wall(mesh, zs, left[2], left[4], lo, tex, 1, false)
      self:_wall(mesh, zs, right[1], right[3], lo, tex, -1, false)
    end
  end
end

--- Every triangle of a mesh cut to its texture's opaque box, a hair inside (spec "clip_art"): a
--- shape laid with its drawing projected may stand past the drawing, where the texel beside it is
--- another thing's. A triangle's uv is affine in its position, so the cut is exact.
function K.clipToArt(mesh, art)
  local u0, v0, u1, v1 = INF, INF, -INF, -INF
  for v = 0, art.h - 1 do
    for u = 0, art.w - 1 do
      if art.px[(v * art.w + u) * 4 + 4] >= 0.5 then
        u0, v0, u1, v1 = min(u0, u), min(v0, v), max(u1, u + 1), max(v1, v + 1)
      end
    end
  end
  if u0 == INF then return end
  local e = 1.0 / 64
  u0, v0, u1, v1 = u0 + e, v0 + e, u1 - e, v1 - e
  local out = {}
  for _, t in ipairs(mesh.tris) do
    local a, b, c = t[1], t[2], t[3]
    if min(a[4], b[4], c[4]) >= u0 and min(a[5], b[5], c[5]) >= v0
        and max(a[4], b[4], c[4]) <= u1 and max(a[5], b[5], c[5]) <= v1 then
      out[#out + 1] = t
    else
      local poly = { a, b, c }
      for _, cut in ipairs({ { 4, u0, true }, { 4, u1, false }, { 5, v0, true }, { 5, v1, false } }) do
        if #poly >= 3 then poly = K.clip(poly, cut[1], cut[2], cut[3]) end
      end
      for k = 2, #poly - 1 do
        out[#out + 1] = { poly[1], poly[k], poly[k + 1], shade = t.shade, tag = t.tag }
      end
    end
  end
  mesh.tris = out
end

-- ── Smooth surfaces with the drawing projected ─────────────────────────────

--- A thing whose side outline (`section`, (z, y) points) runs across from x0 to x1 (a sun
--- lounger's frame, a mat), every face with its drawing projected; the ends read it `grown` rows
--- down; with `uv` every face takes that one texel; a face the view grazes (cosine under `graze`)
--- reads the grown band too.
function K.ProjSection(name, section, x0, x1, o)
  o = o or {}
  return { name = name, sec = section, x0 = x0, x1 = x1, grown = o.grown or 0.0, uv = o.uv,
           graze = o.graze or 0.0, emit = function(self, mesh)
    local sec, x0_, x1_ = self.sec, self.x0, self.x1
    local n = #sec
    local area = 0
    for i = 1, n do
      local a, b = sec[i], sec[i % n + 1]
      area = area + a[1] * b[2] - b[1] * a[2]
    end
    local function P(x, y, z, cut)
      if self.uv then return { x, y, z, self.uv[1], self.uv[2] } end
      return { x, y, z, x, z - y + (cut and 0.0 or self.grown) }
    end
    for i = 1, n do
      local za, ya, zb, yb = sec[i][1], sec[i][2], sec[i % n + 1][1], sec[i % n + 1][2]
      local L = K.hypot(zb - za, yb - ya)
      if L >= 1e-6 then
        local nz, ny = (yb - ya) / L, -(zb - za) / L
        if area < 0 then nz, ny = -nz, -ny end
        local seen = ny + nz > 1e-6
        local cut = not seen or (ny + nz) / sqrt(2) >= self.graze
        local q = { P(x0_, ya, za, cut), P(x1_, ya, za, cut), P(x1_, yb, zb, cut), P(x0_, yb, zb, cut) }
        local shade = seen and SHADE_ART or SHADE_BACK
        local tag = self.name .. (seen and "~proj" or ".back~behind~proj")
        triFacing(mesh, q[1], q[2], q[3], 0.0, ny, nz, shade, tag)
        triFacing(mesh, q[1], q[3], q[4], 0.0, ny, nz, shade, tag)
      end
    end
    local tris = K.triangulate(sec)
    for _, e in ipairs({ { x0_, -1.0, x0_ + 0.01 }, { x1_, 1.0, x1_ - 0.01 } }) do
      local x, nx, xs = e[1], e[2], e[3]
      for _, t in ipairs(tris) do
        local tri = {}
        for k = 1, 3 do
          local p = sec[t[k]]
          local pt = P(xs, p[2], p[1], false)
          tri[k] = { x, pt[2], pt[3], pt[4], pt[5] }
        end
        triFacing(mesh, tri[1], tri[2], tri[3], nx, 0.0, 0.0, nx > 0 and SHADE_EAST or SHADE_WEST,
          self.name .. ".end~behind~proj")
      end
    end
  end }
end

--- An open boat as smooth surfaces, its drawing projected on all of them: the outside upright on
--- a superellipse plan from y0 (rising `keel` to the ends) to the gunwale at y1 (rising `sheer`);
--- o.inner = { cx, cz, rx, rz, floor } (open; else decked), o.boxes = { { x0, x1, y0, y1, z0, z1 } }.
function K.ProjHull(name, cx, cz, rx, rz, y0, y1, p, sheer, o)
  o = o or {}
  return { name = name, cx = cx, cz = cz, rx = rx, rz = rz, y0 = y0, y1 = y1, p = p, sheer = sheer,
           inner = o.inner, boxes = o.boxes or {}, seg = o.seg or 32, keel = o.keel or 0.0,
           emit = function(self, mesh)
    local seg = self.seg
    local function ring(rcx, rcz, rrx, rrz)
      local out = {}
      local k = 2.0 / self.p
      for i = 0, seg - 1 do
        local a = 2 * pi * i / seg
        local c, s = cos(a), sin(a)
        out[#out + 1] = { rcx + rrx * (c < 0 and -1 or 1) * abs(c) ^ k,
                          rcz + rrz * (s < 0 and -1 or 1) * abs(s) ^ k }
      end
      return out
    end
    local function gunwale(x)
      local k = (x - self.cx) / self.rx
      return self.y1 + self.sheer * k * k
    end
    local function bottom(x)
      local k = (x - self.cx) / self.rx
      return self.y0 + self.keel * k ^ 4
    end
    local tag = self.name .. "~proj"
    local function P(x, y, z) return { x, y, z, x, z - y } end
    local outer = ring(self.cx, self.cz, self.rx, self.rz)
    for i = 1, seg do
      local A, B = outer[i], outer[i % seg + 1]
      mesh:poly({ P(A[1], bottom(A[1]), A[2]), P(B[1], bottom(B[1]), B[2]),
                  P(B[1], gunwale(B[1]), B[2]), P(A[1], gunwale(A[1]), A[2]) }, 1.0, tag)
    end
    local base = {}
    for i, A in ipairs(outer) do base[i] = P(A[1], bottom(A[1]), A[2]) end
    mesh:poly(base, 1.0, tag)
    if not self.inner then
      local mid = P(self.cx, self.y1, self.cz)
      for i = 1, seg do
        local A, B = outer[i], outer[i % seg + 1]
        mesh:tri(mid, P(B[1], gunwale(B[1]), B[2]), P(A[1], gunwale(A[1]), A[2]), 1.0, tag)
      end
    else
      local icx, icz, irx, irz, fl = self.inner[1], self.inner[2], self.inner[3], self.inner[4], self.inner[5]
      local inner = ring(icx, icz, irx, irz)
      for i = 1, seg do
        local A, B = outer[i], outer[i % seg + 1]
        local IA, IB = inner[i], inner[i % seg + 1]
        local ga, gb = gunwale(A[1]), gunwale(B[1])
        local ha, hb = gunwale(IA[1]), gunwale(IB[1])
        mesh:poly({ P(A[1], ga, A[2]), P(B[1], gb, B[2]), P(IB[1], hb, IB[2]), P(IA[1], ha, IA[2]) }, 1.0, tag)
        mesh:poly({ P(IA[1], ha, IA[2]), P(IB[1], hb, IB[2]), P(IB[1], fl, IB[2]), P(IA[1], fl, IA[2]) }, 1.0, tag)
      end
      local fpoly = {}
      for i, A in ipairs(inner) do fpoly[i] = P(A[1], fl, A[2]) end
      mesh:poly(fpoly, 1.0, tag)
    end
    for _, b in ipairs(self.boxes) do
      local x0, x1, by0, by1, z0, z1 = b[1], b[2], b[3], b[4], b[5], b[6]
      for _, quad in ipairs({
        { { x0, by1, z1 }, { x1, by1, z1 }, { x1, by1, z0 }, { x0, by1, z0 } },
        { { x0, by0, z1 }, { x1, by0, z1 }, { x1, by1, z1 }, { x0, by1, z1 } },
        { { x0, by0, z0 }, { x1, by0, z0 }, { x1, by1, z0 }, { x0, by1, z0 } },
        { { x0, by0, z0 }, { x0, by0, z1 }, { x0, by1, z1 }, { x0, by1, z0 } },
        { { x1, by0, z0 }, { x1, by0, z1 }, { x1, by1, z1 }, { x1, by1, z0 } } }) do
        local q = {}
        for k, pt in ipairs(quad) do q[k] = P(pt[1], pt[2], pt[3]) end
        mesh:poly(q, 1.0, tag)
      end
    end
  end }
end

--- A parasol's canopy: a shallow cone on a round plan from its rim (radius `r` at `y_rim`, the
--- front half lifted `front`) up to its crown (`y_top`), the drawing projected from `offset` rows
--- down; underneath a flatter cone up to the pole at `y_under`, darker.
function K.ProjCanopy(name, cx, cz, r, y_rim, y_top, o)
  o = o or {}
  return { name = name, emit = function(_, mesh)
    local seg = o.seg or 16
    local front, offset = o.front or 0.0, o.offset or 0.0
    local y_under = o.y_under or (y_rim + 1.0)
    local R = r / cos(pi / seg)
    local function P(x, y, z) return { x, y, z, x, z - y + offset } end
    local rim = {}
    for i = 0, seg - 1 do
      local a = 2 * pi * i / seg
      local s = sin(a)
      rim[#rim + 1] = P(cx + R * cos(a), y_rim + front * max(0.0, s) ^ 2, cz + R * s)
    end
    local top, under = P(cx, y_top, cz), P(cx, y_under, cz)
    for i = 1, seg do
      local a, b = rim[i], rim[i % seg + 1]
      mesh:tri(b, a, top, SHADE_ART, name .. "~proj")
      mesh:tri(a, b, under, SHADE_BACK, name .. ".under~behind~proj")
    end
  end }
end

-- ── Mound: a rounded thing (a rock in the sea) lifted pixel by pixel off its drawing ──

--- Every point (u, v) of the drawing goes to (u, h, v + h), which the GBA's 45 degrees see as
--- that same point whatever h is: h is only how round it is. Each column of the drawing is a cut
--- through a dome: an ellipse half `rise` times as tall as it is deep, standing on the water, its
--- foot where the column's drawing ends and its top as far up as the column is drawn. Behind the
--- grazing point the ellipse goes on down to the water: the back, laid with the texels in front
--- of it (the grown band), closed at both ends. `step`: the lattice in pixels across the columns.
--- `ring` (a set of keyRGB colours): what the drawing puts round its foot on the water (foam, a
--- shadow), laid flat on the water from the band below `rows` that holds it alone (K.withRing).
--- `art` the texture K.withRing makes.
function K.Mound(name, art, o)
  o = o or {}
  local rise, step, backSteps = o.rise or 1.0, o.step or 4, o.back_steps or 3
  local rows = o.rows or art.h
  local ring = o.ring or {}
  local W = art.w
  local apx = art.px
  local foam = K.ringPixels({ w = W, h = rows, px = apx }, ring)
  local function bodyAt(u, v)
    return apx[(v * W + u) * 4 + 4] >= 0.5 and not foam[v * W + u]
  end
  local backBand = art.h >= 3 * rows and 2 * rows or 0
  local hasRing = next(ring) ~= nil

  local function spans()
    local runs = {}
    for u = 0, W - 1 do
      local a, b
      for v = 0, rows - 1 do
        if bodyAt(u, v) then
          if not a then a = v end
          b = v
        end
      end
      runs[u] = a and { a, b + 1 } or false
    end
    local u0, u1
    for u = 0, W - 1 do
      if runs[u] then
        if not u0 then u0 = u end
        u1 = u + 1
      end
    end
    if not u0 then return {} end
    for u = u0, u1 - 1 do
      if not runs[u] then runs[u] = runs[u - 1] end   -- a gap down the middle: bridged
    end
    local lines = { { u0, runs[u0][1], runs[u0][2] } }
    for u = u0, u1 - 1 do lines[#lines + 1] = { u + 0.5, runs[u][1], runs[u][2] } end
    lines[#lines + 1] = { u1, runs[u1 - 1][1], runs[u1 - 1][2] }
    local function straight(i, j)
      local xa, ta, fa = lines[i][1], lines[i][2], lines[i][3]
      local xb, tb, fb = lines[j][1], lines[j][2], lines[j][3]
      for k = i + 1, j - 1 do
        local x, t, f = lines[k][1], lines[k][2], lines[k][3]
        local g = (x - xa) / (xb - xa)
        if abs(ta + (tb - ta) * g - t) > 0.5 or abs(fa + (fb - fa) * g - f) > 0.5 then return false end
      end
      return true
    end
    local keep, i = { 1 }, 1
    while i < #lines do
      local j = i + 1
      while j + 1 <= #lines and lines[j + 1][1] - lines[i][1] <= step and straight(i, j + 1) do j = j + 1 end
      keep[#keep + 1] = j
      i = j
    end
    local out = {}
    for n, k in ipairs(keep) do out[n] = lines[k] end
    return out
  end

  local function tri(mesh, a, b, c, shade, tag, outward)
    local nx, ny, nz = cross(a, b, c)
    if nx * nx + ny * ny + nz * nz < 1e-12 then return end
    if not outward then
      -- drawn: it faces the 45-degree view
      if ny + nz < 0 then b, c = c, b end
    else
      local gx = (a[1] + b[1] + c[1]) / 3.0 - outward[1]
      local gy = (a[2] + b[2] + c[2]) / 3.0 - outward[2]
      local gz = (a[3] + b[3] + c[3]) / 3.0 - outward[3]
      if nx * gx + ny * gy + nz * gz < 0 then b, c = c, b end
    end
    mesh:tri(a, b, c, shade, tag)
  end
  local function quad(mesh, p, q, r, s, shade, tag, outward)
    tri(mesh, p, q, r, shade, tag, outward)
    tri(mesh, p, r, s, shade, tag, outward)
  end
  local function behind(p) return { p[1], p[2], p[3], p[4], p[5] + backBand } end

  return { name = name, emit = function(_, mesh)
    local k = rise
    local sp = spans()
    if #sp == 0 then return end
    local widest = 0
    for _, s in ipairs(sp) do widest = max(widest, s[3] - s[2]) end
    local n = max(4, math.ceil(widest / step))
    local cols = {}
    for _, s in ipairs(sp) do
      local x, vt, vb = s[1], s[2], s[3]
      local L = vb - vt
      local a = L / (1.0 + sqrt(1.0 + k * k))
      local b = k * a
      local zc = vb - a
      local front = {}
      for i = 0, n do
        local v = vt + L * i / n
        -- ((v + t - zc) / a)^2 + (t / b)^2 = 1, the root nearest the eye
        local A = 1.0 / (a * a) + 1.0 / (b * b)
        local B = 2.0 * (v - zc) / (a * a)
        local C = (v - zc) ^ 2 / (a * a) - 1.0
        local disc = max(0.0, B * B - 4 * A * C)
        local t = max(0.0, (-B + sqrt(disc)) / (2 * A))
        front[#front + 1] = { x, t, v + t, x, v }
      end
      local back = {}
      local th0 = pi - atan2(b, a)
      for i = 1, backSteps do
        local th = th0 + (pi - th0) * i / backSteps
        local z, y = zc + a * cos(th), b * sin(th)
        if i == backSteps then y = 0.0 end
        back[#back + 1] = { x, y, z, x, min(vb - 1e-3, max(vt, z - y)) + backBand }
      end
      cols[#cols + 1] = { front, back, zc }
    end
    for c = 1, #cols - 1 do
      local fa, ba, za = cols[c][1], cols[c][2], cols[c][3]
      local fb, bb, zb = cols[c + 1][1], cols[c + 1][2], cols[c + 1][3]
      for i = 1, n do
        quad(mesh, fa[i], fb[i], fb[i + 1], fa[i + 1], SHADE_ART, name .. "~proj")
      end
      local ra, rb = { behind(fa[1]) }, { behind(fb[1]) }
      for _, p in ipairs(ba) do ra[#ra + 1] = p end
      for _, p in ipairs(bb) do rb[#rb + 1] = p end
      local centre = { (fa[1][1] + fb[1][1]) / 2.0, 0.0, (za + zb) / 2.0 }
      for i = 1, #ra - 1 do
        quad(mesh, ra[i], rb[i], rb[i + 1], ra[i + 1], K.SHADE_WOUND, name .. ".back~behind~proj", centre)
      end
    end
    -- the ring round its foot, flat on the water
    if hasRing then
      local x0, y0, x1, y1
      for v = rows, min(art.h, 2 * rows) - 1 do
        for u = 0, W - 1 do
          if apx[(v * W + u) * 4 + 4] > 0 then
            local r = v - rows
            x0, x1 = x0 and min(x0, u) or u, x1 and max(x1, u + 1) or u + 1
            y0, y1 = y0 and min(y0, r) or r, y1 and max(y1, r + 1) or r + 1
          end
        end
      end
      if x0 then
        local e = 0.05
        local q = {}
        for i, c in ipairs({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }) do
          q[i] = { c[1], e, c[2] + e, c[1], c[2] + rows }
        end
        quad(mesh, q[1], q[2], q[3], q[4], SHADE_ART, name .. ".ring~proj")
      end
    end
    -- the two ends, closed by the column's own cut
    for _, e in ipairs({ { cols[1], -1 }, { cols[#cols], 1 } }) do
      local front, back, zc = e[1][1], e[1][2], e[1][3]
      local rg = {}
      for i = #front, 1, -1 do rg[#rg + 1] = behind(front[i]) end
      for _, p in ipairs(back) do rg[#rg + 1] = p end
      if #rg >= 3 then
        local centre = { rg[1][1] - e[2], 0.0, zc }
        for i = 2, #rg - 1 do
          tri(mesh, rg[1], rg[i], rg[i + 1], K.SHADE_WOUND, name .. ".end~behind~proj", centre)
        end
      end
    end
  end }
end

-- ── VoxelLathe / BakedLathe: a turned thing (Slateport's stone lantern) ───────

local VX_TOP, VX_SOUTH, VX_WEST, VX_EAST = 0, 1, 3, 4
local VX_SPREAD = 0.5

-- Python's round(): halves to even
local function pyRound(x)
  local f = floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 elseif d < 0.5 then return f end
  return f % 2 == 0 and f or f + 1
end
local function trunc(x) return x >= 0 and floor(x) or -floor(-x) end
local function copysign(a, b) return (b < 0 or (b == 0 and 1 / b < 0)) and -abs(a) or abs(a) end

--- A drawn round thing as true 1-pixel cubes: the volume a lathe (`profile` of { y, radius }, its
--- plan an ellipse `squash` times as deep as wide, `power(y)` for a squarer plan), voxelized,
--- then carved until the GBA's 45-degree view of its cubes is the drawing exactly (a cube showing
--- an undrawn pixel goes, a drawn pixel nothing shows gets a cube resting on the solid). Only its
--- cubes and colours are used here: BakedLathe bakes its texture off them. `drawn(u, v)`: the
--- pixel is this thing's.
function K.VoxelLathe(name, art, drawnFn, cx, cz, profile, squash, ymax, power)
  local self = { name = name, art = art, drawn = drawnFn, cx = cx, cz = cz, profile = profile,
                 squash = squash, W = art.w, H = art.h, ymax = ymax or 64,
                 power = power or function() return 2.0 end }
  local W, H, YM = self.W, self.H, self.ymax
  local SI, SJ = W + 8, YM + 8
  local function ck(i, j, k) return ((k + 4) * SJ + (j + 4)) * SI + (i + 4) end
  local function unck(c)
    local i = c % SI
    local r = (c - i) / SI
    local j = r % SJ
    return i - 4, j - 4, (r - j) / SJ - 4
  end
  local PO = 512
  local function pk(u, v) return (v + PO) * 1024 + u end
  self.ck = ck

  function self.radius(y)
    local p = profile
    if y < p[1][1] or y > p[#p][1] then return 0.0 end
    for n = 1, #p - 1 do
      local ya, ra, yb, rb = p[n][1], p[n][2], p[n + 1][1], p[n + 1][2]
      if ya <= y and y <= yb then
        if yb == ya then return ra end
        return ra + (rb - ra) * (y - ya) / (yb - ya)
      end
    end
    return 0.0
  end
  local radius, powerOf = self.radius, self.power
  function self.inside(x, y, z)
    local r = radius(y)
    if not (r > 0) then return false end
    local p = powerOf(y)
    return abs((x - cx) / r) ^ p + abs((z - cz) / (squash * r)) ^ p <= 1.0
  end
  local px = art.px
  function self.px(u, v)
    u = min(W - 1, max(0, trunc(u)))
    v = min(H - 1, max(0, trunc(v)))
    local o = (v * W + u) * 4
    return px[o + 1], px[o + 2], px[o + 3]
  end

  -- pixel -> { key, cube, face } the 45-degree view sees there
  local function facesOf(occ)
    local seen = {}
    for c in pairs(occ) do
      local i, j, k = unck(c)
      if not occ[ck(i, j + 1, k)] then
        local p, key = pk(i, k - j - 1), j + 1.0
        local s = seen[p]
        if not s or s[1] < key then seen[p] = { key, c, VX_TOP } end
      end
      if not occ[ck(i, j, k + 1)] then
        local p, key = pk(i, k - j), j + 0.5
        local s = seen[p]
        if not s or s[1] < key then seen[p] = { key, c, VX_SOUTH } end
      end
    end
    return seen
  end

  local D, Dlist = {}, {}
  for v = 0, H - 1 do
    for u = 0, W - 1 do
      if drawnFn(u, v) then D[pk(u, v)] = true; Dlist[#Dlist + 1] = { u, v } end
    end
  end
  local zmax = H + YM
  local occ = {}
  for j = 0, YM - 1 do
    if radius(j + 0.5) > 0 then
      for k = 0, zmax - 1 do
        for i = 0, W - 1 do
          if self.inside(i + 0.5, j + 0.5, k + 0.5) then occ[ck(i, j, k)] = true end
        end
      end
    end
  end
  -- carve: a cube showing an undrawn pixel goes; new ones show behind
  while true do
    local seen = facesOf(occ)
    local bad = {}
    local any = false
    for p, s in pairs(seen) do
      if not D[p] then bad[s[2]] = true; any = true end
    end
    if not any then break end
    for c in pairs(bad) do occ[c] = nil end
  end
  -- fill: a drawn pixel nothing shows gets a cube, as high as it can stand touching the solid,
  -- showing nothing undrawn (what the view sees only ever grows by the new cube's own faces: a
  -- face it hides is covered by one further up the same ray)
  for _ = 1, 8 do
    local seen = facesOf(occ)
    local missing = {}
    for _, d in ipairs(Dlist) do if not seen[pk(d[1], d[2])] then missing[#missing + 1] = d end end
    if #missing == 0 then break end
    -- (Dlist is in (v, u) order already)
    for _, m in ipairs(missing) do
      local u, v = m[1], m[2]
      if not seen[pk(u, v)] then
        local best, bestA, bestB
        for j = 0, YM - 1 do
          for t = 0, 1 do
            local i, jj, k = u, j, v + j + t
            local c = ck(i, jj, k)
            if not occ[c] and k >= 0 then
              if occ[ck(i - 1, jj, k)] or occ[ck(i + 1, jj, k)] or occ[ck(i, jj - 1, k)] or occ[ck(i, jj + 1, k)]
                or occ[ck(i, jj, k - 1)] or occ[ck(i, jj, k + 1)] then
                local topP = not occ[ck(i, jj + 1, k)] and pk(i, k - jj - 1) or nil
                local southP = not occ[ck(i, jj, k + 1)] and pk(i, k - jj) or nil
                local want = pk(u, v)
                if (topP == want or southP == want) and (not topP or D[topP]) and (not southP or D[southP]) then
                  local a = ((occ[ck(i, jj - 1, k)] or jj == 0) and 0 or 1)
                  if best == nil or a < bestA or (a == bestA and jj < bestB) then
                    best, bestA, bestB = c, a, jj
                  end
                end
              end
            end
          end
        end
        if best then
          occ[best] = true
          local i, jj, k = unck(best)
          if not occ[ck(i, jj + 1, k)] then seen[pk(i, k - jj - 1)] = true end
          if not occ[ck(i, jj, k + 1)] then seen[pk(i, k - jj)] = true end
        end
      end
    end
  end
  self.occ = occ
  local seen = facesOf(occ)
  -- (a speck drawn over a clear pixel: no cube can show it; the baked lathe never reads those)
  self.visible = {}
  for p, s in pairs(seen) do
    local u = p % 1024
    self.visible[s[2] * 8 + s[3]] = { u, (p - u) / 1024 - PO }
  end
  return setmetatable(self, { __index = K.VoxelLatheMethods })
end

K.VoxelLatheMethods = {}
local VL = K.VoxelLatheMethods

--- The drawn pixel nearest (u, v) along its row, then its column.
function VL:nearestDrawn(u, v)
  u, v = pyRound(u), pyRound(v)
  for d = 0, 39 do
    for _, ab in ipairs({ { u - d, v }, { u + d, v }, { u, v - d }, { u, v + d } }) do
      local a, b = ab[1], ab[2]
      if a >= 0 and a < self.W and b >= 0 and b < self.H and self.drawn(a, b) then
        local o = (b * self.W + a) * 4
        return self.art.px[o + 1], self.art.px[o + 2], self.art.px[o + 3]
      end
    end
  end
  return 128 / 255, 128 / 255, 128 / 255
end

--- A cube face's colour: the pixel the view sees it as; a step's side its face's; the back the
--- front opposite it; elsewhere the ring of its height turned round the axis.
function VL:colour(i, j, k, f)
  local c = self.ck(i, j, k)
  local vis = self.visible[c * 8 + f]
  if vis then return self.px(vis[1], vis[2]) end
  if f == VX_WEST or f == VX_EAST then
    vis = self.visible[c * 8 + VX_SOUTH]
    if vis then return self.px(vis[1], vis[2]) end
  end
  local x, y, z = i + 0.5, j + 0.5, k + 0.5
  if f == VX_TOP or f == VX_SOUTH or f == 2 then
    local zm = 2 * self.cz - z
    local km = floor(zm)
    local v = f == VX_TOP and km - j - 1 or km - j
    if self.drawn(i, v) then return self.px(i, v) end
  end
  local th = atan2(x - self.cx, (z - self.cz) / self.squash)
  if abs(th) > pi / 2 then th = copysign(pi - abs(th), th) end
  local r = self.radius(y)
  if r == 0 then r = 1.0 end
  local v = self.cz + self.squash * r - y
  local vi = trunc(v)
  local lo, hi
  for u = 0, self.W - 1 do
    if self.drawn(u, vi) then
      if not lo then lo = u end
      hi = u
    end
  end
  if lo then
    local l, h2 = lo + 1.5, hi - 0.5
    local u = (l + h2) / 2 + (h2 - l) / 2 * VX_SPREAD * th / (pi / 2)
    return self:nearestDrawn(u, v)
  end
  return self:nearestDrawn(x, v)
end

local function area3(a, b, c)
  local e1x, e1y, e1z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local e2x, e2y, e2z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
  return e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
end

--- A turned thing as a game draws a prop: a low-poly lathe (`sides` round, a ring at each point
--- of the profile) with its texture baked off the true-cube model (`cubes`, a VoxelLathe), every
--- texel the colour of the cube face under it, the drawing's where the GBA's view sees it. u runs
--- round it by angle (the back the seam), v up the profile by its slant length. `shift_z`: stood
--- that far north of where it is drawn. :texture() gives the drawing with the baked band under it.
function K.BakedLathe(name, cubes, sides, shift_z)
  local self = { name = name, cubes = cubes, sides = sides or 24, shift_z = shift_z or 0.0 }
  local vl = cubes
  local rings = {}
  for n, pr in ipairs(vl.profile) do rings[n] = { pr[1] + 0.0, pr[2] + 0.0 } end
  local vs = { 0.0 }
  for n = 1, #rings - 1 do
    local y0, r0, y1, r1 = rings[n][1], rings[n][2], rings[n + 1][1], rings[n + 1][2]
    vs[n + 1] = vs[n] + sqrt((y1 - y0) ^ 2 + (r1 - r0) ^ 2)
  end
  local rmax = 0
  for _, rg in ipairs(rings) do rmax = max(rmax, rg[2]) end
  local a, b = rmax, rmax * vl.squash
  self.ulen = math.ceil(pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b))))
  self.rings, self.vs, self.v0 = rings, vs, vl.H
  local FACING = 0.45

  -- the ring's point at angle th (0 the front, south)
  local function point(ring, th)
    local y, r = rings[ring + 1][1], rings[ring + 1][2]
    local p = vl.power(y)
    local c, s_ = cos(th), sin(th)
    local e = 2.0 / p
    local px_ = copysign(abs(s_) ^ e, s_)
    local pz = copysign(abs(c) ^ e, c)
    return { vl.cx + r * px_, y, vl.cz + vl.squash * r * pz }
  end
  local function theta(k) return -pi + 2.0 * pi * k / self.sides end
  -- whether the GBA's 45-degree view sees the surface at pt: nothing of the solid up its ray
  local function seenAt(x, y, z)
    local t = 0.75
    while t < 80.0 do
      if vl.inside(x, y + t, z + t) then return false end
      t = t + 0.5
    end
    return true
  end
  local function drawnPx(x, y, z)
    local u, v = floor(x), floor(z - y)
    if vl.drawn(u, v) then return vl.px(u, v) end
  end
  local function colourAt(pt, nrm)
    local x, y, z = pt[1], pt[2], pt[3]
    local zm = 2 * vl.cz - z
    if nrm[2] > 0.7 and z < vl.cz then
      -- a top's back half: the front half opposite it (its far edge is drawn as an outline)
      if seenAt(x, y, zm) then
        local r, g, b2 = drawnPx(x, y, zm)
        if r then return r, g, b2 end
      end
    end
    if seenAt(x, y, z) then
      local r, g, b2 = drawnPx(x, y, z)
      if r then return r, g, b2 end
    end
    if seenAt(x, y, zm) then
      local r, g, b2 = drawnPx(x, y, zm)
      if r then return r, g, b2 end
    end
    local ci, cj, ckk = floor(x - nrm[1] * 0.5), floor(y - nrm[2] * 0.5), floor(z - nrm[3] * 0.5)
    local face = nrm[1] > 0 and VX_EAST or VX_WEST
    if abs(nrm[2]) > max(abs(nrm[1]), abs(nrm[3])) then face = VX_TOP end
    return vl:colour(ci, cj, ckk, face)
  end

  function self.texture()
    local W = max(vl.W, self.ulen)
    local V = math.ceil(vs[#vs]) + 1
    local H = vl.H
    local tex = { w = W, h = H + V, px = {} }
    local tp = tex.px
    for i = 1, W * (H + V) * 4 do tp[i] = 0 end
    local ap = vl.art.px
    for y = 0, H - 1 do
      for x = 0, vl.W - 1 do
        local s, d = (y * vl.W + x) * 4, (y * W + x) * 4
        for c = 1, 4 do tp[d + c] = ap[s + c] end
      end
    end
    local n = #rings
    for iv = 0, V - 1 do
      local sv = iv + 0.5
      local j = 0
      while j < n - 2 and vs[j + 2] < sv do j = j + 1 end
      local g = min(1.0, max(0.0, (sv - vs[j + 1]) / max(1e-6, vs[j + 2] - vs[j + 1])))
      for iu = 0, self.ulen - 1 do
        local th = -pi + 2.0 * pi * (iu + 0.5) / self.ulen
        local A, B = point(j, th), point(j + 1, th)
        local pt = { A[1] + (B[1] - A[1]) * g, A[2] + (B[2] - A[2]) * g, A[3] + (B[3] - A[3]) * g }
        local e = 1e-3
        local t1, t2 = point(j, th + e), point(j + 1, th + e)
        local tg = { (t1[1] - A[1]) * (1 - g) + (t2[1] - B[1]) * g, (t1[2] - A[2]) * (1 - g) + (t2[2] - B[2]) * g,
                     (t1[3] - A[3]) * (1 - g) + (t2[3] - B[3]) * g }
        local up = { B[1] - A[1], B[2] - A[2], B[3] - A[3] }
        local nn = { tg[2] * up[3] - tg[3] * up[2], tg[3] * up[1] - tg[1] * up[3], tg[1] * up[2] - tg[2] * up[1] }
        local L = sqrt(nn[1] ^ 2 + nn[2] ^ 2 + nn[3] ^ 2)
        if L == 0 then L = 1.0 end
        nn[1], nn[2], nn[3] = nn[1] / L, nn[2] / L, nn[3] / L
        local ox, oz = pt[1] - vl.cx, pt[3] - vl.cz
        if nn[1] * ox + nn[3] * oz < 0 or (abs(ox) + abs(oz) < 1e-6 and nn[2] < 0) then
          nn[1], nn[2], nn[3] = -nn[1], -nn[2], -nn[3]
        end
        local r, gg, bb = colourAt(pt, nn)
        local d = ((H + iv) * W + iu) * 4
        tp[d + 1], tp[d + 2], tp[d + 3], tp[d + 4] = r, gg, bb, 1
      end
    end
    return tex
  end

  function self.emit(_, mesh)
    local n = #rings
    local dz = self.shift_z
    for j = 0, n - 2 do
      for k = 0, self.sides - 1 do
        local t0, t1 = theta(k), theta(k + 1)
        local u0, u1 = self.ulen * k / self.sides, self.ulen * (k + 1) / self.sides
        local va, vb = self.v0 + vs[j + 1], self.v0 + vs[j + 2]
        local p0, p1, p2, p3 = point(j, t0), point(j, t1), point(j + 1, t1), point(j + 1, t0)
        p0[4], p0[5], p1[4], p1[5] = u0, va, u1, va
        p2[4], p2[5], p3[4], p3[5] = u1, vb, u0, vb
        for _, tri in ipairs({ { p0, p1, p2 }, { p0, p2, p3 } }) do
          local ax, ay, az = area3(tri[1], tri[2], tri[3])
          if ax * ax + ay * ay + az * az >= 1e-9 then
            local mx = (tri[1][1] + tri[2][1] + tri[3][1]) / 3.0
            local mz = (tri[1][3] + tri[2][3] + tri[3][3]) / 3.0
            local ox, oz = mx - vl.cx, mz - vl.cz
            if ax * ox + az * oz < 0 or (ay < 0 and abs(ax) + abs(az) < 1e-9) then
              tri = { tri[1], tri[3], tri[2] }
              ax, ay, az = -ax, -ay, -az
            end
            local shade = (ay + az >= 0) and SHADE_ART or SHADE_BACK
            local L = sqrt(ax * ax + ay * ay + az * az)
            local facing = (ay + az) / (L * sqrt(2.0))
            local topBack = ay / L > 0.7 and mz < vl.cz
            local out = {}
            if facing > FACING and not topBack and seenAt(tri[1][1], tri[1][2], tri[1][3])
              and seenAt(tri[2][1], tri[2][2], tri[2][3]) and seenAt(tri[3][1], tri[3][2], tri[3][3]) then
              -- turned to the GBA's view: the drawing itself, projected
              for m = 1, 3 do
                local p = tri[m]
                out[m] = { p[1], p[2], p[3] + dz, p[1], p[3] - p[2] }
              end
              mesh:tri(out[1], out[2], out[3], shade, self.name .. ".front~proj")
            else
              for m = 1, 3 do
                local p = tri[m]
                out[m] = { p[1], p[2], p[3] + dz, p[4], p[5] }
              end
              mesh:tri(out[1], out[2], out[3], shade, self.name .. ".baked~clamp")
            end
          end
        end
      end
    end
  end
  return self
end

-- ── Round and run things for the rooms' furniture (gen_voxel_buildings.interior_specs) ──────

--- A small round thing as a smooth dome over an ellipse, its drawing projected (u = x,
--- v = z - y): `seg` points round, `rings` up, the base ring at y0, the crown h above it.
function K.ProjDome(name, cx, cz, rx, rz, h, y0, seg, rings)
  y0, seg, rings = y0 or 0, seg or 12, rings or 3
  return { name = name, emit = function(_, mesh)
    local function pt(k, i)
      local phi = (pi / 2) * k / rings
      local a = 2 * pi * i / seg
      local r = cos(phi)
      local x = cx + rx * r * cos(a)
      local z = cz + rz * r * sin(a)
      local y = y0 + h * sin(phi)
      return { x, y, z, x, z - y }
    end
    local tag = name .. "~proj"
    for k = 0, rings - 1 do
      for i = 0, seg - 1 do
        local a, b = pt(k, i), pt(k, i + 1)
        local c, d = pt(k + 1, i + 1), pt(k + 1, i)
        if k == rings - 1 then
          mesh:tri(a, b, c, 1.0, tag)
        else
          mesh:poly({ a, b, c, d }, 1.0, tag)
        end
      end
    end
  end }
end

--- A small turned thing as a smooth surface of revolution on an elliptical plan, its drawing
--- projected: `profile` { { y, radius } } from the foot up, the plan `squash` as deep as wide, a
--- lid on the top ring (a radius of 0 at either end: a pole); `seg` points round; `offset` the
--- texture's rows read that far down.
function K.ProjLathe(name, cx, cz, profile, squash, seg, offset)
  squash, seg, offset = squash or 1.0, seg or 12, offset or 0.0
  return { name = name, emit = function(_, mesh)
    -- (the polygon round each ring circumscribes it: the drawing's outline stays covered)
    local grow = 1.0 / cos(pi / seg)
    local function ring(y, r)
      r = r * grow
      local out = {}
      for i = 0, seg - 1 do
        local a = 2 * pi * i / seg
        local x = cx + r * cos(a)
        local z = cz + r * squash * sin(a)
        out[i + 1] = { x, y, z, x, z - y + offset }
      end
      return out
    end
    local tag = name .. "~proj"
    local rings = {}
    for j, p in ipairs(profile) do rings[j] = ring(p[1], p[2]) end
    local n = seg
    for j = 1, #rings - 1 do
      local lo, hi = rings[j], rings[j + 1]
      for i = 1, n do
        local i2 = i % n + 1
        local quad = { lo[i], lo[i2], hi[i2], hi[i] }
        if profile[j + 1][2] < 1e-6 then
          mesh:tri(quad[1], quad[2], quad[3], 1.0, tag)
        elseif profile[j][2] < 1e-6 then
          -- (a pole at the foot: one triangle a side)
          mesh:tri(quad[1], quad[3], quad[4], 1.0, tag)
        else
          mesh:poly(quad, 1.0, tag)
        end
      end
    end
    if profile[#profile][2] > 1e-6 then mesh:poly(rings[#rings], 1.0, tag) end
  end }
end

--- A thing whose outline seen from the side (`section`: { x, y }, x across, y up) runs back from
--- z0 to z1 - an escalator's ramp and balustrades - every face with its drawing projected; the
--- back, the underside and the ends (an end reading the drawing's column just inside it) darker,
--- a face lying on the floor left out.
function K.ProjRun(name, section, z0, z1)
  return { name = name, emit = function(_, mesh)
    local sec = section
    local n = #sec
    local area = 0
    for i = 1, n do
      local a, b = sec[i], sec[i % n + 1]
      area = area + (a[1] * b[2] - b[1] * a[2])
    end
    local function P(x, y, z, u) return { x, y, z, u == nil and x or u, z - y } end
    for i = 1, n do
      local xa, ya = sec[i][1], sec[i][2]
      local xb, yb = sec[i % n + 1][1], sec[i % n + 1][2]
      local L = sqrt((xb - xa) ^ 2 + (yb - ya) ^ 2)
      if L >= 1e-6 then
        -- the outward normal: right of a->b for a section wound counter-clockwise
        local nx, ny = (yb - ya) / L, -(xb - xa) / L
        if area < 0 then nx, ny = -nx, -ny end
        if not (ny < -0.5 and max(ya, yb) <= 1e-6) then
          local shade, tag, u
          if ny > 1e-6 then
            shade, tag = SHADE_ART, name .. "~proj"
          elseif ny < -1e-6 then
            shade, tag = SHADE_BACK, name .. ".under~behind~proj"
          else
            shade = nx > 0 and SHADE_EAST or SHADE_WEST
            tag, u = name .. ".end~behind~proj", xa - 0.5 * (nx > 0 and 1 or -1)
          end
          local q = { P(xa, ya, z0, u), P(xb, yb, z0, u), P(xb, yb, z1, u), P(xa, ya, z1, u) }
          triFacing(mesh, q[1], q[2], q[3], nx, ny, 0.0, shade, tag)
          triFacing(mesh, q[1], q[3], q[4], nx, ny, 0.0, shade, tag)
        end
      end
    end
    for _, end_ in ipairs({ { z1, 1.0 }, { z0, -1.0 } }) do
      local z, nz = end_[1], end_[2]
      local shade = nz > 0 and SHADE_ART or SHADE_BACK
      local tag = name .. (nz > 0 and "~proj" or ".back~behind~proj")
      for _, t in ipairs(K.triangulate(sec)) do
        local a, b, c = sec[t[1]], sec[t[2]], sec[t[3]]
        triFacing(mesh, P(a[1], a[2], z), P(b[1], b[2], z), P(c[1], c[2], z), 0.0, 0.0, nz, shade, tag)
      end
    end
  end }
end

--- A strip running back across the plan from (za, ya) to (zb, yb), u0 to u1 wide, its drawing
--- projected (a beam of light from one post to the next); `voff` the rows below the model's
--- drawing where its own pixels are.
function K.Ribbon(name, u0, u1, za, ya, zb, yb, voff)
  voff = voff or 0
  return { name = name, emit = function(_, mesh)
    -- (wound as a card is: its lower edge on the screen first)
    local lo, hi
    if zb - yb > za - ya then lo, hi = { zb, yb }, { za, ya } else lo, hi = { za, ya }, { zb, yb } end
    local quad = { { u0, lo[2], lo[1] }, { u1, lo[2], lo[1] }, { u1, hi[2], hi[1] }, { u0, hi[2], hi[1] } }
    local q = {}
    for k, p in ipairs(quad) do q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] + voff } end
    mesh:poly(q, SHADE_ART, name .. ".ribbon~proj")
  end }
end

--- The 45-degree view of a part's polygons, emitted into it as into a mesh: whether a point of
--- the drawing is under one of them (gen_voxel_buildings.ViewHull).
function K.viewHull()
  local tris = {}
  local hull = {}
  function hull:tri(a, b, c)
    tris[#tris + 1] = { a[1], a[3] - a[2], b[1], b[3] - b[2], c[1], c[3] - c[2] }
  end
  function hull:poly(pts)
    for k = 2, #pts - 1 do self:tri(pts[1], pts[k], pts[k + 1]) end
  end
  function hull.covers(u, v)
    for _, t in ipairs(tris) do
      local ax, ay, bx, by, cx, cy = t[1], t[2], t[3], t[4], t[5], t[6]
      local d1 = (bx - ax) * (v - ay) - (by - ay) * (u - ax)
      local d2 = (cx - bx) * (v - by) - (cy - by) * (u - bx)
      local d3 = (ax - cx) * (v - cy) - (ay - cy) * (u - cx)
      if not ((d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9) and (d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9)) then
        return true
      end
    end
    return false
  end
  return hull
end

end
