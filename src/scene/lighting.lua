-- The sun on the battle scene (Battle Scene: Overworld): each vertex's light baked into its shade
-- as the meshes are built - the face's turn to the sun, the shadow cast on it, and a little
-- contact darkening at the foot of what stands close.
--
-- Ported from Emerald 3DS's src/voxel/voxel_lighting.c (by Zallax and contributors, CC BY-NC-SA
-- 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), whose comments explain each rule.
-- Every number is theirs. Changes: rewritten in Lua; the casters are read from the battle's own
-- cell window through an adapter (src/scene/init.lua) instead of their world; a ray marches every
-- one of its points up to the casters' ceiling (their "reference march": their cell skips and
-- block bounds only spare points and change no answer); no eased rows (Standing is the point
-- itself: the ease stretch is not ported); the sun is theirs by default, NW, full strength
-- (their day/night clock moves it only with their "day_night" setting, off by default).
--
-- World frame: x east, z south (a cell's row), y up, in tiles; a point h up a lifted cell is drawn
-- h rows south of where it stands (the relief's frame, src/scene/relief.lua).

local Lighting = {}

Lighting.AMBIENT = 0.70        -- VOXEL_AMBIENT: a cast shadow, and a face turned from the sun
Lighting.SUN = { dx = 0.85, dz = 0.55, strength = 1.0 }
Lighting.REACH = 8             -- VOXEL_LIGHT_REACH: tiles of rise; a quarter tile a step
Lighting.CROWN_TOP = 1.62
Lighting.SURFACE_BIAS = 0.06
-- the models' drawn shades (voxel_building.py): which side of a triangle is its outside
Lighting.MODEL_SHADE = { WEST = 0.80, EAST = 0.72, BACK = 0.66, WOUND = 0.90 }

local floor, sqrt, abs = math.floor, math.sqrt, math.abs

local function Tile(n) return floor(n) end

--- A lighting for one build. o = {
---   cell(tx, tz) -> { base, lift, shift, top, bottom, crownPart, surface, sign, mask } (their
---     LightCell: heights over the cell's map base, tiles; crownPart a tree part 0..3, 4 a small
---     tree, or -1; mask 16 rows of 16 bits, bit x of row z, a model's footprint),
---   surfaceAt(x, z) -> the drawn relief's height there over its base (VoxelRelief_SurfaceAt),
---   signOccludes(tx, tz, x, y, z) -> whether a sign's drawing stops the point (y over base),
---   ceiling -> no caster stands higher (world height): a ray past it is lit,
---   sun (optional) = { dx, dz, strength } }
function Lighting.new(o)
  local sun = o.sun or Lighting.SUN
  local DX, DZ, strength = sun.dx, sun.dz, sun.strength
  local ambient = 1 - (1 - Lighting.AMBIENT) * strength
  local ceiling = o.ceiling or 1000
  local L = { ambient = ambient, rays = 0 }

  -- ── casters ──
  local cells = {}
  local function Cell(x, z)
    local k = z * 65536 + x
    local c = cells[k]
    if c then return c end
    c = o.cell(x, z) or {}
    c.x, c.z = x, z
    c.base, c.lift, c.shift, c.top = c.base or 0, c.lift or 0, c.shift or 0, c.top or 0
    c.bottom = c.bottom or 0
    c.crownPart = c.crownPart or -1
    cells[k] = c
    return c
  end
  L.cell = Cell

  local function CellOccludes(cell, x, y, z)
    y = y - cell.base
    if cell.top <= y or (cell.top <= 0 and not cell.surface) then return false end
    if cell.surface then
      if y < cell.bottom - Lighting.SURFACE_BIAS then return true end
      return y < o.surfaceAt(x, z) - Lighting.SURFACE_BIAS
    end
    if cell.mask then
      local px, pz = floor((x - cell.x) * 16), floor((z - cell.z) * 16)
      px = px < 0 and 0 or px > 15 and 15 or px
      pz = pz < 0 and 0 or pz > 15 and 15 or pz
      return floor((cell.mask[pz + 1] or 0) / 2 ^ px) % 2 == 1
    end
    if cell.sign then return o.signOccludes(cell.x, cell.z, x, y, z) end
    if cell.crownPart == 4 then
      local dx = (x - (cell.x + 0.5)) / 0.48
      local dz = (z - (cell.z + 0.35)) / 0.55
      local dy = (y - 0.80) / 0.62
      return dx * dx + dz * dz + dy * dy < 1
    end
    if cell.crownPart >= 0 then
      local crownX = (cell.x - cell.crownPart % 2) + 1
      local crownZ = (cell.z - floor(cell.crownPart / 2)) + 0.65
      local dx = (x - crownX) / 0.95
      local dz = (z - crownZ) / 0.65
      local dy = (y - 0.95) / 0.67
      return dx * dx + dz * dz + dy * dy < 1
    end
    return true
  end

  -- what stands where the point is drawn: a lifted cell's tree, model or sign is drawn as far
  -- south and as high as the cell is lifted, and looked for there
  local function ObjectAt(tx, x, y, z)
    local cell = Cell(tx, Tile(z))
    if cell.shift == 0 then return CellOccludes(cell, x, y - cell.lift, z) end
    if cell.surface and CellOccludes(cell, x, y, z) then return true end
    local c2 = Cell(tx, Tile(z - cell.shift))
    if c2.surface or c2.shift == 0 then return false end
    return CellOccludes(c2, x, y - c2.lift, z - c2.shift)
  end
  local function Occludes(x, y, z) return ObjectAt(Tile(x), x, y, z) end
  L.occludes = Occludes

  --- Does the sun reach the world point (x, y, z)? A quarter tile of rise a step, a little bias
  --- off the surface, every point up to the reach or the casters' ceiling.
  local function Lit(x, y, z)
    if strength == 0 then return true end
    L.rays = L.rays + 1
    for step = 1, Lighting.REACH * 4 do
      local rise = step * 0.25
      local ry = y + rise + 0.08
      if ry >= ceiling then break end
      local rx, rz = x - DX * rise, z - DZ * rise
      if ObjectAt(Tile(rx), rx, ry, rz) then return false end
    end
    return true
  end
  L.lit = Lit

  -- a little darkening at the foot of what stands beside the point (not on roofs and crowns)
  local function Contact(x, y, z)
    if y - Cell(Tile(x), Tile(z)).base > 0.41 then return 1 end
    local covered = 0
    if Occludes(x - 0.28, y + 0.3, z) then covered = covered + 1 end
    if Occludes(x + 0.28, y + 0.3, z) then covered = covered + 1 end
    if Occludes(x, y + 0.3, z - 0.28) then covered = covered + 1 end
    if Occludes(x, y + 0.3, z + 0.28) then covered = covered + 1 end
    return 1 - 0.035 * covered
  end

  -- samples, kept by their exact point (a bucket a 4096th of a tile)
  local samples = {}
  local function keyOf(x, y, z)
    return floor(x * 4096 + 0.5) .. "," .. floor(y * 4096 + 0.5) .. "," .. floor(z * 4096 + 0.5)
  end
  local function FindSample(x, y, z)
    local k = keyOf(x, y, z)
    local s = samples[k]
    if not s then
      s = { contact = Contact(x, y, z), rayCast = false }
      samples[k] = s
    end
    return s
  end
  local function CachedSample(x, y, z)
    local s = FindSample(x, y, z)
    if not s.rayCast then
      s.lit = Lit(x, y, z)
      s.rayCast = true
    end
    return s
  end
  local function CachedContact(x, y, z)
    if y - Cell(Tile(x), Tile(z)).base > 0.41 then return 1 end
    return FindSample(x, y, z).contact
  end
  L.cachedSample, L.cachedContact, L.findSample = CachedSample, CachedContact, FindSample

  --- VoxelLighting_Sample: the light a point gets, lit or not, with its contact.
  function L.sample(x, y, z)
    local s = CachedSample(x, y, z)
    return (s.lit and 1 or ambient) * s.contact
  end

  --- VoxelLighting_Face: n . sun over up . sun, the sun unnormalised at (-DX, 1, -DZ): level
  --- ground 1, a west wall 0.85, a north one 0.55, south and east the ambient.
  local function Face(nx, ny, nz)
    local length = sqrt(nx * nx + ny * ny + nz * nz)
    if length <= 0 then return 1 end
    local facing = (ny - DX * nx - DZ * nz) / length
    if facing <= 0 then return ambient end
    if facing >= 1 then return 1 end
    return ambient + (1 - ambient) * facing
  end
  L.face = Face

  -- ── faces ──
  -- A vertex is { x, y, z, u, v, shade, alpha } in the mesh's frame; `off` = { ox, oy, oz } puts it
  -- in the world (x + ox, y + oy, z + oz). emit(a, b, c) writes a triangle.

  local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
             a[4] + (b[4] - a[4]) * t, a[5] + (b[5] - a[5]) * t, a[6] + (b[6] - a[6]) * t, a[7] }
  end
  local function copyV(v) return { v[1], v[2], v[3], v[4], v[5], v[6], v[7] } end

  -- RawQuad: cut along the diagonal whose ends are lit most alike, on a flat parallelogram whose
  -- texture is one too (either cut the same surface and picture)
  local function rawQuad(emit, a, b, c, d)
    if abs(a[6] - c[6]) > abs(b[6] - d[6])
        and abs(a[1] + c[1] - b[1] - d[1]) < 0.001 and abs(a[2] + c[2] - b[2] - d[2]) < 0.001
        and abs(a[3] + c[3] - b[3] - d[3]) < 0.001
        and abs(a[4] + c[4] - b[4] - d[4]) < 0.0001 and abs(a[5] + c[5] - b[5] - d[5]) < 0.0001 then
      emit(a, b, d); emit(b, c, d)
      return
    end
    emit(a, b, c); emit(a, c, d)
  end
  local function emitPolygon(emit, out, count)
    if count == 4 then rawQuad(emit, out[1], out[2], out[3], out[4]) else emit(out[1], out[2], out[3]) end
  end

  --- LightFace: a quad a b c d (count 4) or the triangle a b c (count 3) lit and emitted. kind = {
  ---   off = { ox, oy, oz }, lift (a vertex's height in the mesh at its cell's own ground: the
  ---   refine's test is of the height over it), refine (level ground about a cell across: a 3x3 of half-tile samples,
  ---   four quads where a shadow's edge crosses it), rounded (a crown's card: lit as a rounded
  ---   crown), constant (an object lit as a whole: one sample, times the face term while it is
  ---   in the sun), vertexFace (a relief lattice's quad: each corner's shade is its face term) }
  function L.face4(emit, kind, a, b, c, d, count)
    count = count or 4
    d = d or c
    local ox, oy, oz = kind.off[1], kind.off[2], kind.off[3]
    local function W(v) return v[1] + ox, v[2] + oy, v[3] + oz end
    local points = { a, b, c, d }
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if kind.vertexFace and not kind.constant and not kind.rounded then
      -- LightVertexFaces: each corner brings its own face term in its shade
      local out = {}
      for i = 1, count do
        local v = copyV(points[i])
        local face = v[6]
        local px, py, pz = W(v)
        if face <= ambient + 0.001 then
          v[6] = ambient * CachedContact(px, py, pz)
        else
          local s = CachedSample(px, py, pz)
          v[6] = (s.lit and face or ambient) * s.contact
        end
        out[i] = v
      end
      emitPolygon(emit, out, count)
      return
    end
    if kind.normal then nx, ny, nz = kind.normal[1], kind.normal[2], kind.normal[3] end
    if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
    if kind.rounded then
      local length = sqrt(nx * nx + ny * ny + nz * nz)
      if length > 0 then nx, ny, nz = nx / length, ny / length + 1, nz / length end
    end
    local face = Face(nx, ny, nz)
    local out = { copyV(a), copyV(b), copyV(c), copyV(d) }
    if kind.constant then
      local light = kind.constant > ambient + 0.01 and kind.constant * face or kind.constant
      for i = 1, 4 do out[i][6] = out[i][6] * light end
      emitPolygon(emit, out, count)
      return
    end
    if kind.rounded then
      for i = 1, 4 do
        local s = CachedSample(W(points[i]))
        out[i][6] = out[i][6] * (s.lit and face or ambient) * s.contact
      end
      emitPolygon(emit, out, count)
      return
    end
    local ly = kind.lift or 0
    if kind.refine and a[2] == b[2] and a[2] == c[2] and a[2] == d[2] and (a[2] - ly <= 0.41 or kind.artShaded)
        and abs(a[1] - c[1]) >= 0.99 and abs(a[3] - c[3]) >= 0.99
        and abs(a[1] - c[1]) <= 1.01 and abs(a[3] - c[3]) <= 1.01 then
      local grid, lo, hi = {}, 1, 0
      for row = 0, 2 do
        for col = 0, 2 do
          local t, s = col * 0.5, row * 0.5
          local v = mix(mix(a, b, t), mix(d, c, t), s)
          local light = L.sample(W(v))
          if light < lo then lo = light end
          if light > hi then hi = light end
          v[6] = v[6] * light
          grid[row * 3 + col + 1] = v
        end
      end
      if hi - lo > 0.02 then
        for row = 0, 1 do
          for col = 0, 1 do
            local i = row * 3 + col + 1
            rawQuad(emit, grid[i], grid[i + 1], grid[i + 4], grid[i + 3])
          end
        end
      else
        rawQuad(emit, grid[1], grid[3], grid[9], grid[7])
      end
      return
    end
    -- LightPolygon: each corner's cast shadow; a face turned from the sun casts no ray
    local sunward = face > ambient
    for i = 1, count do
      local px, py, pz = W(points[i])
      if not sunward then
        out[i][6] = out[i][6] * ambient * CachedContact(px, py, pz)
      else
        local s = CachedSample(px, py, pz)
        out[i][6] = out[i][6] * (s.lit and face or ambient) * s.contact
      end
    end
    emitPolygon(emit, out, count)
  end

  --- VoxelLighting_ModelShade: a model triangle's light, its drawn shade telling which side is its
  --- outside and the sun then how lit that side is (no cast shadow on a model).
  function L.modelShade(a, b, c, drawnShade)
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local S = Lighting.MODEL_SHADE
    local flip
    if abs(drawnShade - S.WOUND) < 0.02 then flip = false
    elseif abs(drawnShade - S.WEST) < 0.02 then flip = nx > 0
    elseif abs(drawnShade - S.EAST) < 0.02 then flip = nx < 0
    elseif abs(drawnShade - S.BACK) < 0.02 then flip = ny + nz > 0
    else flip = ny + nz < 0 end
    if flip then nx, ny, nz = -nx, -ny, -nz end
    return Face(nx, ny, nz)
  end

  --- VoxelLighting_Lattice: a relief cell's SIDE x SIDE lattice (world points { x, y, z, face }),
  --- its shadows read ahead: rays at the half-tile points, the points between taking their
  --- answer where their neighbours agree and they lie on their line.
  function L.lattice(pts, SIDE)
    if strength == 0 then return end
    local LAST = SIDE - 1
    local lit = {}
    for k = 0, SIDE * SIDE - 1 do lit[k] = -1 end
    for c = 0, LAST, 2 do
      for a = 0, LAST, 2 do
        local k = c * SIDE + a
        local p = pts[k]
        if p[4] > ambient + 0.001 then lit[k] = CachedSample(p[1], p[2], p[3]).lit and 1 or 0 end
      end
    end
    local function infer(a, c)
      local k = c * SIDE + a
      local from = {}
      if a % 2 == 1 and c % 2 == 1 then
        from = { k - SIDE - 1, k - SIDE + 1, k + SIDE - 1, k + SIDE + 1 }
      elseif a % 2 == 1 then
        from = { k - 1, k + 1 }
      else
        from = { k - SIDE, k + SIDE }
      end
      local my, mz = 0, 0
      for _, f in ipairs(from) do
        if lit[f] < 0 or lit[f] ~= lit[from[1]] then return -1 end
        my, mz = my + pts[f][2], mz + pts[f][3]
      end
      if abs(my / #from - pts[k][2]) > 0.02 or abs(mz / #from - pts[k][3]) > 0.02 then return -1 end
      return lit[from[1]]
    end
    for c = 0, LAST do
      for a = 0, LAST do
        local k = c * SIDE + a
        if (a % 2 == 1 or c % 2 == 1) and pts[k][4] > ambient + 0.001 then
          local v = infer(a, c)
          if v >= 0 then
            local s = FindSample(pts[k][1], pts[k][2], pts[k][3])
            if not s.rayCast then
              s.lit = v ~= 0
              s.rayCast = true
            end
          end
        end
      end
    end
  end

  --- VoxelLighting_LatticeShades: the light each lattice point gets, as a vertex-face quad's
  --- corners get it (the same samples).
  function L.latticeShades(pts, SIDE)
    local shade = {}
    for k = 0, SIDE * SIDE - 1 do
      local p = pts[k]
      if p[4] <= ambient + 0.001 then
        shade[k] = ambient * CachedContact(p[1], p[2], p[3])
      else
        local s = CachedSample(p[1], p[2], p[3])
        shade[k] = (s.lit and p[4] or ambient) * s.contact
      end
    end
    return shade
  end

  return L
end

-- ── the drawn relief's surface, as the sun sees it (voxel_relief.c BuildSurface / SurfaceAt /
-- SurfaceTop) ──

Lighting.SURFACE_SPAN = 6      -- rows past a map's last a table keeps, at the least
Lighting.SURFACE_WALL = 8      -- pixels between two points: a wall, not a slope (half a level)

--- A layout's surface table: each column of its drawing walked down its rows runs south through
--- the world as v + d (a point d = base + h pixels deep, as far south as it stands high), the
--- height at every lattice row it passes read between the two points either side. l = { w, h
--- (cells), base (pixels), heights(x, y) -> the cell's 25 lattice heights (0-based) or nil }.
--- Returns { w, rows, unit, v = { [k * w + i] = units }, top (tiles) }.
function Lighting.buildSurface(l, SIDE)
  local n = SIDE - 1
  local step = 16 / n
  local w = l.w * n + 1
  local span = Lighting.SURFACE_SPAN
  local most, deepest = 0, l.base
  local cache = {}
  local function cellH(x, y)
    local key = y * 4096 + x
    local g = cache[key]
    if g == nil then g = l.heights(x, y) or false; cache[key] = g end
    return g or nil
  end
  for y = 0, l.h - 1 do
    for x = 0, l.w - 1 do
      local g = cellH(x, y)
      if g then
        for k = 0, SIDE * SIDE - 1 do
          local v = g[k] or 0
          if abs(v) > most then most = abs(v) end
          if l.base + v > deepest then deepest = l.base + v end
        end
      end
    end
  end
  if deepest > 0 and floor((deepest + 15) / 16) + 1 > span then span = floor((deepest + 15) / 16) + 1 end
  local unit = most > 254 and 4 or 2
  local rows = (l.h + span) * n + 1
  local v, top = {}, 0
  local function point(i, j)
    local x, y = floor(i / n), floor(j / n)
    if x >= l.w then x = l.w - 1 end
    if y >= l.h then y = l.h - 1 end
    local a, b = i - x * n, j - y * n
    local g = cellH(x, y)
    local hh = g and g[b * SIDE + a] or 0
    return hh, l.base + hh
  end
  for i = 0, w - 1 do
    local h0, d0 = point(i, 0)
    local k = 0
    for j = 1, l.h * n do
      local z0 = (j - 1) * step + d0
      local h1, d1 = point(i, j)
      local z1 = j * step + d1
      while k < rows and k * step <= z1 do
        local t = z1 > z0 and (k * step - z0) / (z1 - z0) or 1
        if t < 0 then t = 0 end
        if h1 - h0 >= Lighting.SURFACE_WALL then t = (k + 1) * step > z1 and 1 or 0 end
        local val = floor(h0 + (h1 - h0) * t + 0.5)
        if h0 + (h1 - h0) * t + 0.5 < 0 and val ~= h0 + (h1 - h0) * t + 0.5 then
          -- (C's int cast truncates toward zero)
          val = val + 1
        end
        local u = unit
        local q
        if val >= 0 then q = floor((val + u / 2) / u) else q = -floor((u / 2 - val) / u) end
        v[k * w + i] = q
        if val > top then top = val end
        k = k + 1
      end
      h0, d0 = h1, d1
    end
  end
  return { w = w, rows = rows, unit = unit, v = v, top = top / 16 }
end

local function surfacePoint(s, i, k)
  if i < 0 or k < 0 or i >= s.w or k >= s.rows then return 0 end
  return s.unit * (s.v[k * s.w + i] or 0)
end

--- VoxelRelief_SurfaceAt over one map's table: fx, fz the point in the map's own cells (lifted
--- `liftPx` pixels: a lift moves the drawing south too). Tiles over its base.
function Lighting.surfaceAt(s, fx, fz, SIDE, liftPx)
  local n = SIDE - 1
  fx = fx * n
  fz = fz * n - (liftPx or 0) / 4
  local i, k = floor(fx), floor(fz)
  fx, fz = fx - i, fz - k
  return ((surfacePoint(s, i, k) * (1 - fx) + surfacePoint(s, i + 1, k) * fx) * (1 - fz)
    + (surfacePoint(s, i, k + 1) * (1 - fx) + surfacePoint(s, i + 1, k + 1) * fx) * fz) / 16
end

--- VoxelRelief_SurfaceTop: the highest and lowest of the table over cell (x, y) of the map,
--- tiles. Returns top, bottom.
function Lighting.surfaceTop(s, x, y, SIDE, liftPx)
  local n = SIDE - 1
  local top, low = 0, 1000
  local lf = floor((liftPx or 0) / 4)
  if (liftPx or 0) < 0 and lf ~= (liftPx or 0) / 4 then lf = lf + 1 end
  for k = y * n - lf, y * n + n - lf do
    for i = x * n, x * n + n do
      local val = surfacePoint(s, i, k)
      if val > top then top = val end
      if val < low then low = val end
    end
  end
  return top / 16, low / 16
end

return Lighting
