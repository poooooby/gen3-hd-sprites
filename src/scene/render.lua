-- Drawing the battle scene (Battle Scene: Overworld): the cell window (src/scene/cells.lua) as
-- meshes, built once per battle, drawn each frame at window resolution through the camera
-- (src/scene/camera.lua).
--
-- Every cell lies on the ground with its metatile (both of the tileset's layers, the lower then
-- the upper); each upright run's cells also stand as cards on the run's southern edge, a little
-- darker, as the sun is behind the camera. A standing cell's ground copy shows while the cards
-- rise with the glide (`rise`: their heights are scaled by it, like a pop-up book), so from
-- above the map looks as the field did; once they stand it is gone (the cards hide the ground
-- behind them).
--
-- The vertex shader puts a point on the screen as the camera puts it on the canvas: a screen
-- pixel times the depth is linear in the view coordinates, so it goes through LOVE's own
-- projection (which knows whether it draws to a canvas or the window) with the depth as w, and
-- the ground is interpolated perspective-correct. Emerald 3DS's grade (src/scene/light.lua): a
-- vertex's shade picks its tint between the light's shade and sun tints, every texel's 5-bit
-- colour is saturated, and distance fades into the haze colour.

local Render = {}

Render.CARD_SHADE = 0.82
Render.SHADE_LOW = 0.62     -- Emerald 3DS's VOXEL_GRADE_SHADE_LOW (src/scene/light.lua)
Render.SATURATION = 1.30    -- and VOXEL_GRADE_SATURATION
Render.BORDER_COURSES = 2   -- how tall the border round the map stands (Emerald 3DS's two courses)
Render.SHADE = { south = 0.60, north = 0.50, west = 0.65, east = 0.55 }
Render.UV_INSET = 0.02      -- texels kept off a tile's edge (no neighbour bleeding at an angle)
-- a counter's or a machine's block (Emerald 3DS's voxel_mesh_builder.c: ShapeHeight's COUNTER,
-- EmitFurniture's stand and top, SHADE_* and SOLID_*)
Render.COUNTER_HEIGHT = 0.70
Render.TV_STAND, Render.TV_TOP = 0.3, 1.0
Render.FACE_SHADE = { top = 1.00, south = 0.60, north = 0.50, west = 0.65, east = 0.55 }
Render.SOLID_SHADE = { lit = 1.00, front = 0.94, back = 0.88, side = 0.91 }
Render.FLAT_MARK = 0.5      -- the vertex alpha of a standing cell's ground copy
-- WoobleView's own (not Emerald 3DS's): land past every map fades into the sky from FADE[1] to
-- FADE[2] tiles past the nearest map cell, so a mountain's rim (Mt Chimney's) carried on as the
-- border does not stand as ridges out to the horizon; the maps themselves never fade
Render.BORDER_FADE = { 0, 3 }
Render.HIDE_AT = 2          -- the rise past which those copies are gone (above 1: never; a wide
                            -- block of trees is not wholly covered by its cards)

local SHADER = [[
varying float vDepth;
varying vec3 vTint;
varying vec2 vDapple;
varying float vFade;
#ifdef VERTEX
uniform mat4 uView;
uniform vec4 uProj;
uniform vec2 uDepth;
uniform float uRise;
uniform vec3 uSunTint;
uniform vec3 uShadeTint;
uniform vec2 uGrade;
uniform vec4 uDappleU;
uniform vec4 uDappleV;
attribute float VertexFade;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vFade = VertexFade;
  vec4 q = vertex_position;
  q.y *= uRise;
  // (the sun dapples' pattern, laid from above along the sun: src/scene/light.lua)
  vDapple = vec2(dot(uDappleU.xyz, q.xyz) + uDappleU.w, dot(uDappleV.xyz, q.xyz) + uDappleV.w);
  vec4 c = uView * q;
  float w = c.z;
  vDepth = w;
  // (Emerald 3DS's grade, voxel.v.pica: how sunlit the vertex is picks its tint, cool in
  // shadow, warm in sun; the shade rides in the vertex colour)
  float shade = VertexColor.r;
  float t = clamp(shade * uGrade.x + uGrade.y, 0.0, 1.0);
  vTint = shade * (uShadeTint + (uSunTint - uShadeTint) * t);
  vec4 p = transform_projection * vec4(uProj.x * c.x + uProj.y * w, -uProj.z * c.y + uProj.w * w, 0.0, w);
  p.z = uDepth.x * w + uDepth.y;
  return p;
}
#endif
#ifdef PIXEL
uniform vec3 uHaze;
uniform vec3 uFog;
uniform float uHideFlat;
uniform float uSaturation;
uniform Image uDapple;
uniform vec3 uDappleRange;
uniform vec3 uSky;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  // (a standing cell's own ground copy, marked by its alpha: gone once the cards stand)
  if (color.a < 0.75 && uHideFlat > 0.5) discard;
  vec4 t = Texel(tex, tc);
  if (t.a < 0.5) discard;
  vec3 rgb = t.rgb;
  if (uSaturation > 0.0) {
    // (voxel_grade.c: each 5-bit channel pushed from the colour's luma, rounded, clamped)
    vec3 c5 = floor(rgb * 31.0 + 0.5);
    float y = dot(c5, vec3(0.299, 0.587, 0.114));
    rgb = clamp(floor(y + (c5 - y) * uSaturation + 0.5), 0.0, 31.0) / 31.0;
  }
  vec3 lit = rgb * vTint;
  if (uDappleRange.z > 0.5) lit *= mix(uDappleRange.x, uDappleRange.y, Texel(uDapple, vDapple).r);
  float f = clamp((vDepth - uFog.x) / (uFog.y - uFog.x), 0.0, 1.0) * uFog.z;
  return vec4(mix(mix(lit, uHaze, f), uSky, vFade), 1.0);
}
#endif
]]

Render.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
  { "VertexFade", "float", 1 },
}

-- one quad (two triangles) into a vertex list: corners a (top left of the texture), b (top
-- right), c (bottom right), d (bottom left), each { x, y, z }; uv rect u0, v0, u1, v1
local function quad(list, a, b, c, d, u0, v0, u1, v1, shade, alpha)
  local function vtx(p, u, v)
    list[#list + 1] = { p[1], p[2], p[3], u, v, shade, shade, shade, alpha or 1 }
  end
  vtx(a, u0, v0); vtx(b, u1, v0); vtx(c, u1, v1)
  vtx(a, u0, v0); vtx(c, u1, v1); vtx(d, u0, v1)
end

-- the uv rect of an atlas quad, kept inset
local function uvOf(q, iw, ih)
  local x, y, w, h = q:getViewport()
  local e = Render.UV_INSET
  return (x + e) / iw, (y + e) / ih, (x + w - e) / iw, (y + h - e) / ih
end

--- The vertex lists for a grid: { lower = { [image] = { vertices... } }, upper = {...},
--- trees = {...} } (the tileset's two layers, then the trees' art), in tiles relative to (ox, oz).
--- tiles(pair) -> { image, overImage, slot(mid), quad(slot), overQuad(slot) } or nil.
--- trees (optional) = { Trees = src/scene/trees.lua, image = its atlas, outdoor = the battle's
--- map is outdoors }: the General tileset's trees stand as their models (src/scene/trees.lua).
--- buildings (optional) = { Buildings = src/scene/buildings.lua, placements = { { model (with
--- .image, its art), cx, cy, ground = image of its cells' ground } } }: each stands as its model
--- (src/scene/buildings.lua); the cells it covers (cell.model) lay its ground and nothing else.
--- light (optional) = { L = a src/scene/lighting.lua lighting, H = how far the mesh's frame lies
--- under Emerald 3DS's world, in height and rows }: every face lit by the sun as theirs is.
function Render.vertices(grid, tiles, ox, oz, trees, buildings, light)
  local out = { lower = {}, upper = {}, trees = {}, models = {} }
  local LT = light and light.L
  local OFF = light and { ox, light.H, oz + light.H }
  -- a quad (corners { x, y, z }, uv rect) lit as `kind` says (src/scene/lighting.lua face4), or as
  -- it is without light
  local function litQuad(l, a, b, c, d, u0, v0, u1, v1, shade, alpha, kind)
    if not (LT and kind) then
      quad(l, a, b, c, d, u0, v0, u1, v1, shade, alpha)
      return
    end
    local function V(p, u, v) return { p[1], p[2], p[3], u, v, shade, alpha or 1 } end
    local function emit(p, q, r)
      for _, v in ipairs({ p, q, r }) do
        local s = v[6] > 1 and 1 or v[6]
        l[#l + 1] = { v[1], v[2], v[3], v[4], v[5], s, s, s, v[7] }
      end
    end
    kind.off = OFF
    LT.face4(emit, kind, V(a, u0, v0), V(b, u1, v0), V(c, u1, v1), V(d, u0, v1), 4)
  end
  out.lit = LT ~= nil
  local marks   -- (a fading border cell's lists, and where its vertices start in each)
  local function list(layer, image)
    local l = out[layer][image]
    if not l then
      l = {}
      out[layer][image] = l
    end
    if marks and (layer == "lower" or layer == "upper") and not marks[l] then marks[l] = #l end
    return l
  end
  -- how far past the nearest map cell each border cell is (tiles, centre to centre), for the
  -- border's fade (Render.BORDER_FADE)
  local fadeField
  do
    local edges, any = {}, false
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.border then any = true
        elseif c.kind ~= "void" then
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local o = grid.at(c.cx + d[1], c.cy + d[2])
            if o and o.border then edges[#edges + 1] = c; break end
          end
        end
      end
    end
    if any and #edges > 0 then
      fadeField = {}
      for j = 0, grid.h - 1 do
        for i = 0, grid.w - 1 do
          local c = grid.rows[j][i]
          if c.border then
            local best = math.huge
            for _, e in ipairs(edges) do
              local dx, dz = c.cx - e.cx, c.cy - e.cy
              local d = dx * dx + dz * dz
              if d < best then best = d end
            end
            fadeField[c.cy * 65536 + c.cx] = math.sqrt(best)
          end
        end
      end
    end
  end
  local function fadeOf(v)
    -- (the vertex's cell, its height taken off the row it is drawn on: a point h up stands h
    -- south), the field read between the cell centres round it
    local X, Z = v[1] + ox - 0.5, v[3] + oz - v[2] - 0.5
    local x0, z0 = math.floor(X), math.floor(Z)
    local fx, fz = X - x0, Z - z0
    -- (a map cell is 0; past the window's edge, its edge's)
    local function at(x, z)
      local c = grid.at(x, z)
      if not c then
        local cx = x < grid.x0 and grid.x0 or x > grid.x0 + grid.w - 1 and grid.x0 + grid.w - 1 or x
        local cz = z < grid.y0 and grid.y0 or z > grid.y0 + grid.h - 1 and grid.y0 + grid.h - 1 or z
        return fadeField[cz * 65536 + cx] or 0
      end
      return fadeField[z * 65536 + x] or 0
    end
    local d = (at(x0, z0) * (1 - fx) + at(x0 + 1, z0) * fx) * (1 - fz)
      + (at(x0, z0 + 1) * (1 - fx) + at(x0 + 1, z0 + 1) * fx) * fz
    local a, b = Render.BORDER_FADE[1], Render.BORDER_FADE[2]
    local t = (d - a) / (b - a)
    t = t < 0 and 0 or t > 1 and 1 or t
    return t * t * (3 - 2 * t)
  end
  local function put(layer, image, q, a, b, c, d, shade, alpha, kind)
    if not (image and q) then return end
    local iw, ih = image:getDimensions()
    local u0, v0, u1, v1 = uvOf(q, iw, ih)
    litQuad(list(layer, image), a, b, c, d, u0, v0, u1, v1, shade, alpha, kind)
  end
  -- a counter or a machine no model covers (cell.furniture, src/scene/init.lua), stood up from
  -- its own drawing as Emerald 3DS's EmitTile stands it (voxel_mesh_builder.c): a counter a block
  -- COUNTER_HEIGHT high, its drawing on its top and on each side facing a cell of another shape
  -- (not the void); a machine a television - a grey stand, a black body, its drawing the screen
  -- facing south. Shades as theirs (SHADE_*, SOLID_*). Returns true when it stood the cell up.
  local solids = buildings and buildings.solids
  local function shapeAt(x, y)
    local o = grid.at(x, y)
    if not o or o.kind == "void" then return "void" end
    return o.furniture or "flat"
  end
  local function standFurniture(cell, t, slot, x0, z0, dy)
    local what = cell.furniture
    if not what or cell.model or cell.lifted or cell.border then return false end
    local x1, z1 = x0 + 1, z0 + 1
    local function art(a, b, c, d, shade, normal)
      local kind = { normal = normal }
      put("lower", t.image, t.quad(slot), a, b, c, d, shade, nil, kind)
      put("upper", t.overImage, t.overQuad(slot), a, b, c, d, shade, nil, { normal = normal })
    end
    if what == "counter" then
      local h = dy + Render.COUNTER_HEIGHT
      art({ x0, h, z0 }, { x1, h, z0 }, { x1, h, z1 }, { x0, h, z1 }, Render.FACE_SHADE.top, { 0, 1, 0 })
      local cx, cy = cell.cx, cell.cy
      local function open(dx, dz)
        local s = shapeAt(cx + dx, cy + dz)
        return s ~= "void" and s ~= "counter"
      end
      if open(0, 1) then
        art({ x0, h, z1 }, { x1, h, z1 }, { x1, dy, z1 }, { x0, dy, z1 }, Render.FACE_SHADE.south, { 0, 0, 1 })
      end
      if open(0, -1) then
        art({ x1, h, z0 }, { x0, h, z0 }, { x0, dy, z0 }, { x1, dy, z0 }, Render.FACE_SHADE.north, { 0, 0, -1 })
      end
      if open(-1, 0) then
        art({ x0, h, z0 }, { x0, h, z1 }, { x0, dy, z1 }, { x0, dy, z0 }, Render.FACE_SHADE.west, { -1, 0, 0 })
      end
      if open(1, 0) then
        art({ x1, h, z1 }, { x1, h, z0 }, { x1, dy, z0 }, { x1, dy, z1 }, Render.FACE_SHADE.east, { 1, 0, 0 })
      end
      return true
    end
    -- a television: EmitSolidBox's faces (no bottom), then the screen
    if not solids then return false end
    local function box(q, bx0, bz0, bx1, bz1, y0, y1)
      local ax0, ax1, az0, az1 = x0 + bx0, x0 + bx1, z0 + bz0, z0 + bz1
      local Y0, Y1 = dy + y0, dy + y1
      local S = Render.SOLID_SHADE
      put("models", solids.image, q, { ax0, Y1, az0 }, { ax1, Y1, az0 }, { ax1, Y1, az1 }, { ax0, Y1, az1 }, S.lit, nil,
        { normal = { 0, 1, 0 } })
      put("models", solids.image, q, { ax0, Y1, az1 }, { ax1, Y1, az1 }, { ax1, Y0, az1 }, { ax0, Y0, az1 }, S.front, nil,
        { normal = { 0, 0, 1 } })
      put("models", solids.image, q, { ax1, Y1, az0 }, { ax0, Y1, az0 }, { ax0, Y0, az0 }, { ax1, Y0, az0 }, S.back, nil,
        { normal = { 0, 0, -1 } })
      put("models", solids.image, q, { ax0, Y1, az0 }, { ax0, Y1, az1 }, { ax0, Y0, az1 }, { ax0, Y0, az0 }, S.side, nil,
        { normal = { -1, 0, 0 } })
      put("models", solids.image, q, { ax1, Y1, az1 }, { ax1, Y1, az0 }, { ax1, Y0, az0 }, { ax1, Y0, az1 }, S.side, nil,
        { normal = { 1, 0, 0 } })
    end
    local stand, top = Render.TV_STAND, Render.TV_TOP
    box(solids.grey, 0, 0, 1, 1, 0, stand)
    box(solids.black, 0, 0.3, 1, 0.8, stand, top)
    local zs = z0 + 0.79
    art({ x0, dy + top, zs }, { x1, dy + top, zs }, { x1, dy + stand, zs }, { x0, dy + stand, zs },
      Render.FACE_SHADE.south, { 0, 0, 1 })
    return true
  end
  local Trees = trees and trees.Trees
  local timg = trees and trees.image
  local dim, e = Trees and Trees.DIM or 1, Render.UV_INSET
  -- a tree's quad (corners in map cells, uvs in atlas texels), lifted with its cell (`lift`) and
  -- as far south (`shift`: a border tree's is its belt's, VoxelTree_EmitBorder)
  local lift, shift = 0, 0
  local function putTree(a, b, c, d, u0, v0, u1, v1, what)
    local function rel(p) return { p[1] - ox, p[2] + lift, p[3] - oz + shift } end
    -- (lit: a crown's card as the rounded crown it stands for, voxel_tree.c; its ground as ground)
    litQuad(list("trees", timg), rel(a), rel(b), rel(c), rel(d),
      (u0 + e) / dim, (v0 + e) / dim, (u1 - e) / dim, (v1 - e) / dim, 1, 1,
      what == "card" and { rounded = true } or { refine = true, lift = lift })
  end
  -- the border round the battle map (Emerald 3DS's belt, voxel_mesh_builder.c VoxelMesh_EmitBorder,
  -- EmitBorderSteps, EmitBorderNorth): each cell past every map (cell.border, src/scene/init.lua:
  -- its metatiles, level, shift, courses) is drawn in Emerald 3DS's frame - heights and rows over
  -- the battle map's base (`b.base`), so its bands and rows fall where theirs do - and put in ours:
  --   water lies flat at its level, its shift rows south, and shows no faces;
  --   land stands `courses` of the block at its level: its top read from the row its courses rise
  --     over, its faces only where it meets the map or water beside it; steps down to a lower
  --     belt cell beside it, and a north wall up from the lower row behind (that row's top run on
  --     to it, capped down the courses beside the map);
  --   a belt laid as its map's drawing (`drawn`) stands that many rows south, its top its own
  --     drawing, and shows no faces (the map's own close every step);
  --   a tree's cell is the tree's (src/scene/trees.lua), its steps still drawn.
  local C = Render.BORDER_COURSES
  local SH = Render.SHADE
  local function borderAt(x, y)
    local o = grid.at(x, y)
    return o and o.border or nil
  end
  local function inMap(x, y)
    local o = grid.at(x, y)
    return o ~= nil and not o.border
  end
  -- a quad of metatile m, both layers: p = four { x, y, z, fu, fv } (fu, fv: fractions of the
  -- tile), drawn as triangles 1 2 3 and 1 3 4
  local function faceUV(t, m, p, shade)
    local slot = m and t.slot(m)
    if not slot then return end
    for layer = 1, 2 do
      local image = layer == 1 and t.image or t.overImage
      local q = image and (layer == 1 and t.quad(slot) or t.overQuad(slot))
      if q then
        local iw, ih = image:getDimensions()
        local u0, v0, u1, v1 = uvOf(q, iw, ih)
        local l = list(layer == 1 and "lower" or "upper", image)
        if LT then
          local function V(v) return { v[1], v[2], v[3], u0 + (u1 - u0) * v[4], v0 + (v1 - v0) * v[5], shade, 1 } end
          local function emit(a, b, c)
            for _, v in ipairs({ a, b, c }) do
              local s = v[6] > 1 and 1 or v[6]
              l[#l + 1] = { v[1], v[2], v[3], v[4], v[5], s, s, s, v[7] }
            end
          end
          LT.face4(emit, { off = OFF }, V(p[1]), V(p[2]), V(p[3]), V(p[4]), 4)
        else
          for _, k in ipairs({ 1, 2, 3, 1, 3, 4 }) do
            local v = p[k]
            l[#l + 1] = { v[1], v[2], v[3], u0 + (u1 - u0) * v[4], v0 + (v1 - v0) * v[5], shade, shade, shade, 1 }
          end
        end
      end
    end
  end
  local function block(cell, t, part)
    local b = cell.border
    local base, x, y = b.base or 0, cell.cx, cell.cy
    -- a point of Emerald 3DS's frame, in ours
    local function P(px, h, pz, fu, fv) return { px - ox, h + base, pz - oz + base, fu, fv } end
    local function top(m, wx, wz, h)
      faceUV(t, m, { P(wx, h, wz, 0, 0), P(wx + 1, h, wz, 1, 0), P(wx + 1, h, wz + 1, 1, 1), P(wx, h, wz + 1, 0, 1) }, 1)
    end
    local function south(m, wx, wz, yb, yt)
      faceUV(t, m, { P(wx, yb, wz + 1, 0, 1), P(wx + 1, yb, wz + 1, 1, 1), P(wx + 1, yt, wz + 1, 1, 0),
                     P(wx, yt, wz + 1, 0, 0) }, SH.south)
    end
    local function east(m, wx, wz, yb, yt)
      faceUV(t, m, { P(wx + 1, yb, wz + 1, 0, 1), P(wx + 1, yb, wz, 1, 1), P(wx + 1, yt, wz, 1, 0),
                     P(wx + 1, yt, wz + 1, 0, 0) }, SH.east)
    end
    local function west(m, wx, wz, yb, yt)
      faceUV(t, m, { P(wx, yb, wz, 0, 1), P(wx, yb, wz + 1, 1, 1), P(wx, yt, wz + 1, 1, 0),
                     P(wx, yt, wz, 0, 0) }, SH.west)
    end
    local level, shift = b.level - base, b.shift - base
    if b.water then
      top(b.mid, x, y + shift, level)
      return
    end
    if b.steps then
      -- the faces over a lower belt cell beside it (EmitBorderSteps)
      for d, dir in ipairs({ { 0, 1 }, { 1, 0 }, { -1, 0 } }) do
        local o = borderAt(x + dir[1], y + dir[2])
        local other = o and o.level - base
        if other and other < level - 0.05 then
          local f = d == 1 and south or d == 2 and east or west
          f(b.mid, x, y + shift, other, level)
        end
      end
      -- the north wall up from the row behind (EmitBorderNorth)
      local n = borderAt(x, y - 1)
      if n then
        local low = n.water and n.level - base or n.level - base + C
        local hi = level + C
        local za, zb = y + n.shift - base, y + shift
        if hi - low >= 1 / 16 and zb > za then
          local band = math.floor(low)
          while band < hi do
            local h0, h1 = math.max(low, band), math.min(hi, band + 1)
            if h1 > h0 then
              local va, vb = 1 - (h0 - band), 1 - (h1 - band)
              faceUV(t, b.mid, { P(x + 1, h0, zb, 0, va), P(x, h0, zb, 1, va), P(x, h1, zb, 1, vb),
                                 P(x + 1, h1, zb, 0, vb) }, SH.north)
            end
            band = band + 1
          end
          local row = math.floor(za)
          while row < zb do
            local p0, p1 = math.max(za, row), math.min(zb, row + 1)
            if p1 > p0 then
              faceUV(t, b.mid, { P(x, low, p0, 0, p0 - row), P(x + 1, low, p0, 1, p0 - row),
                                 P(x + 1, low, p1, 1, p1 - row), P(x, low, p1, 0, p1 - row) }, 1)
            end
            row = row + 1
          end
          if inMap(x - 1, y) then
            faceUV(t, b.mid, { P(x, low - C, zb, 1, 1), P(x, low - C, za, 0, 1), P(x, low, za, 0, 0),
                               P(x, low, zb, 1, 0) }, 1)
          end
          if inMap(x + 1, y) then
            faceUV(t, b.mid, { P(x + 1, low - C, za, 0, 1), P(x + 1, low - C, zb, 1, 1),
                               P(x + 1, low, zb, 1, 0), P(x + 1, low, za, 0, 0) }, 1)
          end
        end
      end
    end
    if part then return end
    local drawn = b.drawn or 0
    local courses = b.courses or C
    local wz = y + drawn + shift
    -- (a standing cell beside a flat one of water shows its face too)
    local function open(dx, dy)
      local o = grid.at(x + dx, y + dy)
      return o ~= nil and (not o.border or o.border.water)
    end
    local s, e, w = open(0, 1), open(1, 0), open(-1, 0)
    -- laid as drawn, its top is its own drawing; stood where it is tiled, the row its courses
    -- rise over
    top(drawn > 0 and b.mid or (b.mids[courses - 1] or b.mid), x, wz, courses + level)
    if drawn > 0 or not (s or e or w) then return end
    for h = 0, courses - 1 do
      local m = b.mids[h] or b.mid
      local yb, yt = h + level, h + 1 + level
      if s then south(m, x, wz, yb, yt) end
      if e then east(m, x, wz, yb, yt) end
      if w then west(m, x, wz, yb, yt) end
    end
  end

  -- where a map's edge meets the belt (Emerald 3DS's EmitSeamSkirt, its two belt cases): north,
  -- west or east of a map's edge cell, a belt standing over the edge as the cell draws it is
  -- closed by a wall of the cell's own drawing, point by point of its lattice, from the edge up
  -- to the belt (a lowered sea, a wood under the belt); south of it a belt of trees has the cell's
  -- drawing run on, from its south edge to the belt, under the crowns. Not round a belt laid as
  -- the drawing, nor in a room.
  local SIDE = 5
  local LAST = SIDE - 1
  -- (Emerald 3DS's d: 0 north, 1 south, 2 west, 3 east)
  local SEAM_DIRS = { [0] = { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
  -- a cell's ground along one edge, point by point of its lattice (voxel_mesh_builder.c SeamEdge):
  -- heights in pixels over its map's base, and how far south each point stands (tiles, from the
  -- edge's own row or column: a point h up stands h south). West, east and south a cell with a cut
  -- record and a wall stands on its foot (the rock over it closes those sides down to it); `stands`
  -- has a bit a stretch of the north edge a wall may stand on (cell.northStands, src/scene/init.lua)
  local function seamEdge(c, d, wantStands)
    local g, cut = c.g, c.g and c.cut
    local onFoot = cut ~= nil and d ~= 0 and cut.wall ~= nil
    local h, z = {}, {}
    for k = 0, LAST do
      local i = d == 0 and k or d == 1 and LAST * SIDE + k or k * SIDE + (d == 2 and 0 or LAST)
      h[k] = onFoot and cut.foot or (g and g[i] or 0)
      z[k] = h[k] / 16
    end
    local stands = 15
    if wantStands and d == 0 and c.northStands then stands = c.northStands end
    return h, z, stands
  end
  -- (counted for the dev driver: out.skirts, quads by case)
  out.skirts = { belt = 0, gap = 0, seam = 0, cells = {} }
  local skirtAt
  local function skirtUV(kind, ...)
    local k = out.skirts
    k[kind] = k[kind] + 1
    local tag = skirtAt .. ":" .. kind
    if #k.cells < 12 and k.cells[#k.cells] ~= tag then k.cells[#k.cells + 1] = tag end
    faceUV(...)
  end
  local function skirts(cell, t, mid)
    skirtAt = cell.cx .. "," .. cell.cy
    local g, lift = cell.g, cell.mapLift or cell.dy or 0
    local x, y = cell.cx, cell.cy
    local function Q(px, h, pz, fu, fv) return { px - ox, h, pz - oz, fu, fv } end
    for d, dir in ipairs({ { 0, -1 }, { -1, 0 }, { 1, 0 } }) do
      local o = borderAt(x + dir[1], y + dir[2])
      if o and (o.drawn or 0) == 0 then
        local belt, bz = o.level, o.base or 0
        local fh, fz, along = {}, {}, {}
        local lowest = belt
        for k = 0, LAST do
          local i = d == 1 and k or k * SIDE + (d == 2 and 0 or LAST)
          local h = (g and g[i] or 0) / 16
          along[k] = k / LAST
          fh[k] = lift + h
          fz[k] = y + (d == 1 and 0 or along[k]) + lift + h
          if fh[k] < lowest then lowest = fh[k] end
        end
        if lowest < belt - 0.05 then
          for k = 0, LAST - 1 do
            local hA, hB = belt - fh[k], belt - fh[k + 1]
            local fA, fB = math.min(hA, 1), math.min(hB, 1)
            if hA > 0.05 or hB > 0.05 then
              if d == 1 then
                local xa, xb = x + along[k], x + along[k + 1]
                skirtUV("belt", t, mid, { Q(xa, fh[k], fz[k], along[k], fA), Q(xb, fh[k + 1], fz[k + 1], along[k + 1], fB),
                                 Q(xb, belt, y + bz, along[k + 1], 0), Q(xa, belt, y + bz, along[k], 0) }, SH.south)
              else
                local za, zb = y + along[k] + bz, y + along[k + 1] + bz
                if d == 2 then
                  skirtUV("belt", t, mid, { Q(x, belt, zb, 0, along[k + 1]), Q(x, belt, za, 0, along[k]),
                                   Q(x, fh[k], fz[k], fA, along[k]), Q(x, fh[k + 1], fz[k + 1], fB, along[k + 1]) },
                    SH.east)
                else
                  skirtUV("belt", t, mid, { Q(x + 1, belt, za, 1, along[k]), Q(x + 1, belt, zb, 1, along[k + 1]),
                                   Q(x + 1, fh[k + 1], fz[k + 1], 1 - fB, along[k + 1]),
                                   Q(x + 1, fh[k], fz[k], 1 - fA, along[k]) }, SH.west)
                end
              end
            end
          end
        end
      end
    end
    -- where two maps meet at different levels (the rest of EmitSeamSkirt): both edges point by point
    -- of the lattice, theirs over our map's base. South, should their edge still lie rows south of
    -- ours, the edge cell's drawing goes on to it, a row of the drawing a row of the gap (never
    -- stretched); then wherever ours stands over theirs, a wall of the cell's drawing from their
    -- edge up to ours (from where the ground now ends, south). In our map's frame (heights in
    -- pixels over its base, rows as its builder lays them), then put in ours (`Q2`).
    local m = cell.rmap
    if m then
      local function Q2(px, h, pz, fu, fv) return { px - ox, h + lift, pz - oz + lift, fu, fv } end
      local southGap = 0
      for d = 0, 3 do
        local dir = SEAM_DIRS[d]
        local o = grid.at(x + dir[1], y + dir[2])
        if o and o.rmap and o.rmap ~= m and not o.border then
          local rebase = ((o.mapLift or 0) - lift) * 16
          local ourH, ourZ, stands = seamEdge(cell, d, true)
          local theirH = seamEdge(o, d == 0 and 1 or d == 1 and 0 or d == 2 and 3 or 2, false)
          local any = false
          for k = 0, LAST do
            theirH[k] = theirH[k] + rebase
            if ourH[k] - theirH[k] > 0.8 then any = true end
          end
          if d == 1 then
            local og = o.g
            local hA, zA, hB, zB = {}, {}, {}, {}
            local gap, meets = 0, true
            for k = 0, LAST do
              hA[k] = g and g[LAST * SIDE + k] or 0
              zA[k] = y + 1 + hA[k] / 16
              local th = og and og[k] or 0
              hB[k] = th + rebase
              zB[k] = y + 1 + (th + rebase) / 16
              if zB[k] - zA[k] > gap then gap = zB[k] - zA[k] end
              if math.abs(hB[k] - hA[k]) > 1 then meets = false end
            end
            -- (a map with an ease meets it with no gap: VoxelRelief_Stretch)
            if gap > 0.02 and meets and not ((m.L and m.L.ease or 0) ~= 0 and (m.L.easeRows or 0) ~= 0) then
              local rows = math.ceil(gap - 0.02)
              local vb = math.min(gap / rows, 1)
              for s = 0, rows - 1 do
                local f0, f1 = s / rows, (s + 1) / rows
                for k = 0, LAST - 1 do
                  local function H(i, f) return (hA[i] + (hB[i] - hA[i]) * f) / 16 end
                  local function Z(i, f) return zA[i] + (zB[i] - zA[i]) * f end
                  local xa, xb = x + k / LAST, x + (k + 1) / LAST
                  skirtUV("gap", t, mid, { Q2(xa, H(k, f0), Z(k, f0), k / LAST, 0), Q2(xb, H(k + 1, f0), Z(k + 1, f0), (k + 1) / LAST, 0),
                                   Q2(xb, H(k + 1, f1), Z(k + 1, f1), (k + 1) / LAST, vb),
                                   Q2(xa, H(k, f1), Z(k, f1), k / LAST, vb) }, 1)
                end
              end
              southGap = gap
            end
          end
          if any then
            for k = 0, LAST - 1 do
              local ta, tb = ourH[k] / 16, ourH[k + 1] / 16
              local la, lb = math.min(theirH[k], ourH[k]) / 16, math.min(theirH[k + 1], ourH[k + 1]) / 16
              local fa, fb = math.min(1, ta - la), math.min(1, tb - lb)
              local ka, kb = k / LAST, (k + 1) / LAST
              if not ((ta - la <= 0.05 and tb - lb <= 0.05) or math.floor(stands / 2 ^ k) % 2 == 0) then
                if d == 0 then
                  local za, zb = y + ourZ[k], y + ourZ[k + 1]
                  skirtUV("seam", t, mid, { Q2(x + kb, tb, zb, kb, 0), Q2(x + ka, ta, za, ka, 0), Q2(x + ka, la, za, ka, fa),
                                   Q2(x + kb, lb, zb, kb, fb) }, SH.north)
                elseif d == 1 then
                  local za, zb = y + 1 + ourZ[k] + southGap, y + 1 + ourZ[k + 1] + southGap
                  skirtUV("seam", t, mid, { Q2(x + ka, ta, za, ka, 1), Q2(x + kb, tb, zb, kb, 1), Q2(x + kb, lb, zb, kb, 1 - fb),
                                   Q2(x + ka, la, za, ka, 1 - fa) }, SH.south)
                else
                  local za, zb = y + ka + ourZ[k], y + kb + ourZ[k + 1]
                  if d == 2 then
                    skirtUV("seam", t, mid, { Q2(x, ta, za, 0, ka), Q2(x, tb, zb, 0, kb), Q2(x, lb, zb, fb, kb),
                                     Q2(x, la, za, fa, ka) }, SH.west)
                  else
                    skirtUV("seam", t, mid, { Q2(x + 1, tb, zb, 1, kb), Q2(x + 1, ta, za, 1, ka), Q2(x + 1, la, za, 1 - fa, ka),
                                     Q2(x + 1, lb, zb, 1 - fb, kb) }, SH.east)
                  end
                end
              end
            end
          end
        end
      end
    end
    -- south: a belt of trees
    local o = grid.at(x, y + 1)
    local b = o and o.border
    if g and b and (b.drawn or 0) == 0 and Trees and timg and trees.outdoor then
      local sec, general = Trees.tilesets(o.pair)
      if general and Trees.part(sec, o.mid) then
        local belt, bz = b.level, y + 1 + (b.base or 0)
        local first = LAST * SIDE
        for k = 0, LAST - 1 do
          local hA, hB = lift + g[first + k] / 16, lift + g[first + k + 1] / 16
          if not (belt - hA < 1 and belt - hB < 1) then
            local zA, zB = y + 1 + hA, y + 1 + hB
            local xa, xb = x + k / LAST, x + (k + 1) / LAST
            skirtUV("belt", t, mid, { Q(xa, hA, zA, k / LAST, 1), Q(xb, hB, zB, (k + 1) / LAST, 1),
                             Q(xb, belt, bz, (k + 1) / LAST, 0), Q(xa, belt, bz, k / LAST, 0) }, 1)
          end
        end
      end
    end
  end
  for j = 0, grid.h - 1 do
    for i = 0, grid.w - 1 do
      local cell = grid.rows[j][i]
      local t = not cell.border and cell.kind ~= "void" and cell.pair and tiles(cell.pair) or nil
      if t then
        local mid = cell.mid
        if Trees and timg and trees.outdoor then
          local sec, general = Trees.tilesets(cell.pair)
          if general then mid = Trees.groundMetatile(sec, mid) end
        end
        skirts(cell, t, mid)
      end
    end
  end

  for j = 0, grid.h - 1 do
    local row = grid.rows[j]
    for i = 0, grid.w - 1 do
      local cell = row[i]
      local t = cell.kind ~= "void" and cell.pair and not cell.model and tiles(cell.pair) or nil
      if t then
        local mid = cell.mid
        local sec, general, part
        if Trees and timg and trees.outdoor then
          sec, general = Trees.tilesets(cell.pair)
          if general then
            part = Trees.part(sec, mid)
            mid = Trees.groundMetatile(sec, mid)
          end
        end
        -- (a sign's cell, and a lamp's head's, lay the ground round them: src/scene/signs.lua)
        local slot = t.slot(cell.groundMid or mid)
        -- (land past every map fades into the sky with its distance from the maps)
        -- (a tree's cell keeps its tree whole: a belt of trees never fades)
        if fadeField and cell.border and not cell.border.water and not part then marks = {} end
        -- (lifted with its map and its relief: a point h up stands h south, src/scene/relief.lua)
        local dy = cell.dy or 0
        lift = dy
        shift = cell.border and cell.border.shift or dy
        local x0, z0 = cell.cx - ox, cell.cy - oz + dy
        local x1, z1 = x0 + 1, z0 + 1
        -- on the ground: north-west corner first (the tile's top left). A standing cell's ground
        -- copy is marked (alpha 0.5): it shows only while the cards rise
        local a, b, c, d = { x0, dy, z0 }, { x1, dy, z0 }, { x1, dy, z1 }, { x0, dy, z1 }
        -- (a tree's cell lays the tree's own ground, unless it stands in water the ground lays)
        local treeGround = part and Trees.laysGround(sec, cell.mid)
        -- what stands as a card: a blocked cell no model covers (a tree's, a crown's over it)
        local card = cell.up and not part and mid == cell.mid
        local flat = card and Render.FLAT_MARK or 1
        -- (a lifted cell's ground is its relief's: src/scene/relief.lua, but a tree's)
        -- (a counter or a machine stands up instead of lying as ground)
        local stood = not treeGround and standFurniture(cell, t, slot, x0, z0, dy)
        if not treeGround and not cell.lifted and not stood then
          -- (lit as ground: refined where a shadow's edge crosses it, not past every map)
          local kind = { refine = not cell.border, lift = dy }
          put("lower", t.image, t.quad(slot), a, b, c, d, 1, flat, kind)
          put("upper", t.overImage, t.overQuad(slot), a, b, c, d, 1, flat, { refine = not cell.border, lift = dy })
        end
        if cell.border then block(cell, t, part) end
        if marks then
          for l, start in pairs(marks) do
            for k = start + 1, #l do l[k][10] = fadeOf(l[k]) end
          end
          marks = nil
        end
        if part then
          -- (against rock it stands up steeper; on a band's rock or a one-level slope the relief
          -- lays its ground: src/scene/init.lua, src/scene/relief.lua treeStep)
          Trees.emit(putTree, sec, cell.mid, cell.cx, cell.cy, part, function(x, y)
            local o = grid.at(x, y)
            if not o or o.pair ~= cell.pair then return false end
            return Trees.part(sec, o.mid)
          end, { rock = cell.treeRock, noGround = cell.treeGround ~= nil })
        end
        if card then
          -- standing on the run's southern edge, `up` tiles high
          local z, y0 = cell.base + 1 - oz + dy, cell.up + dy
          local ca, cb = { x0, y0 + 1, z }, { x1, y0 + 1, z }
          local cc, cd = { x1, y0, z }, { x0, y0, z }
          local s = Render.CARD_SHADE
          -- (lit as the south face it shows)
          put("lower", t.image, t.quad(slot), ca, cb, cc, cd, s, nil, { normal = { 0, 0, 1 } })
          put("upper", t.overImage, t.overQuad(slot), ca, cb, cc, cd, s, nil, { normal = { 0, 0, 1 } })
        end
      end
    end
  end
  -- the buildings: their models, and their cells' ground (one quad a cell, from the placement's
  -- ground image)
  for _, pl in ipairs(buildings and buildings.placements or {}) do
    local md = pl.model
    -- (lifted as the cell it stands on: src/scene/relief.lua)
    local pdy = pl.dy or 0
    if md.image then
      local l = list("models", md.image)
      -- (lit: each triangle's drawn shade gives way to the sun's facing of its outside, no cast
      -- shadow; voxel_lighting.c ModelTri)
      local tri = {}
      buildings.Buildings.emit(pl, ox, oz, function(v)
        v[2], v[3] = v[2] + pdy, v[3] + pdy
        if LT then
          tri[#tri + 1] = v
          if #tri == 3 then
            local s = LT.modelShade(tri[1], tri[2], tri[3], tri[1][6])
            for k = 1, 3 do
              tri[k][6], tri[k][7], tri[k][8] = s, s, s
              l[#l + 1] = tri[k]
            end
            tri = {}
          end
        else
          l[#l + 1] = v
        end
      end)
    end
    if pl.ground then
      local w, h = md.ref.w, md.ref.h
      local gl = list("lower", pl.ground)
      for j = 0, h - 1 do
        for i = 0, w - 1 do
          local cell = grid.at(pl.cx + i, pl.cy + j)
          if cell and cell.model == pl and not cell.reliefDrawn then
            local cdy = cell.dy or 0
            local x0, z0 = pl.cx + i - ox, pl.cy + j - oz + cdy
            litQuad(gl, { x0, cdy, z0 }, { x0 + 1, cdy, z0 }, { x0 + 1, cdy, z0 + 1 }, { x0, cdy, z0 + 1 },
              (i + e / 16) / w, (j + e / 16) / h, (i + 1 - e / 16) / w, (j + 1 - e / 16) / h, 1, 1,
              { refine = true, lift = cdy })
          end
        end
      end
    end
  end
  return out
end

--- Make the scene's meshes (G: love.graphics). Returns a list of meshes, the lower layer's
--- first (the upper layer's art lies over it at the same depth), or nil.
function Render.meshes(G, lists)
  local meshes = {}
  for _, layer in ipairs({ "lower", "upper", "trees", "models" }) do
    for image, list in pairs(lists[layer] or {}) do
      if #list > 0 then
        for _, v in ipairs(list) do if not v[10] then v[10] = 0 end end
        local ok, mesh = pcall(G.newMesh, Render.FORMAT, list, "triangles", "static")
        if not ok then return nil end
        mesh:setTexture(image)
        meshes[#meshes + 1] = { mesh = mesh, image = image, layer = layer }
      end
    end
  end
  return meshes
end

local shader       -- nil: not made yet; false: this device cannot make it
function Render.shader(G)
  if shader == nil then
    local ok, sh = pcall(G.newShader, SHADER)
    shader = ok and sh or false
    Render.shaderError = not ok and tostring(sh) or nil
  end
  return shader or nil
end

local target, targetW, targetH
--- Draw the scene into a canvas of ours w x h (screen pixels) and return it, or nil.
---   scene.meshes (Render.meshes), scene.ox, scene.oz (the meshes' origin, in map cells)
---   pose (Camera.pose, in map cells), proj/depth (Camera.screenProjection), rise (0..1)
---   haze { r, g, b } (what the distance fades to), fog { start, end, max } (view depth, tiles),
---   sky { r, g, b } (behind the world; the haze when not given), light (src/scene/light.lua:
---   its sun and shade tints and the texture grade; nil: neither, the shade alone)
function Render.draw(G, Camera, scene, pose, proj, depth, rise, haze, fog, w, h, sky, light)
  local sh = Render.shader(G)
  if not (sh and scene.meshes) then return nil end
  w, h = math.max(1, math.ceil(w)), math.max(1, math.ceil(h))
  if not target or targetW ~= w or targetH ~= h then
    if target and target.release then pcall(target.release, target) end
    target = G.newCanvas(w, h, { dpiscale = 1 })
    target:setFilter("linear", "linear")
    targetW, targetH = w, h
  end
  local p = Camera.pose(pose.tx - scene.ox, pose.tz - scene.oz, pose.pitch, pose.dist, pose.ty, pose.yaw)
  G.push("all")
  G.setCanvas({ target, depth = true })
  G.origin()
  G.setScissor()
  sky = sky or haze
  G.clear(sky[1], sky[2], sky[3], 1, false, 1)
  G.setDepthMode("lequal", true)
  -- (cards face the camera, the ground faces up: neither may be culled)
  if G.setMeshCullMode then G.setMeshCullMode("none") end
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  G.setShader(sh)
  sh:send("uView", "row", Camera.viewRows(p))
  sh:send("uProj", proj)
  sh:send("uDepth", depth)
  sh:send("uRise", math.max(0.001, rise or 1))
  sh:send("uHaze", haze)
  sh:send("uSky", sky)
  sh:send("uFog", fog)
  sh:send("uHideFlat", (rise or 1) > Render.HIDE_AT and 1 or 0)
  sh:send("uSunTint", light and light.sun or { 1, 1, 1 })
  sh:send("uShadeTint", light and light.shade or { 1, 1, 1 })
  local low = Render.SHADE_LOW
  sh:send("uGrade", { 1 / (1 - low), -low / (1 - low) })
  -- the sun dapples (src/scene/light.lua: off where their light has none to speak of)
  local dap = light and light.dappleImage and light.dappleHigh - light.dappleLow > 0.01
  if dap then
    sh:send("uDapple", light.dappleImage)
    sh:send("uDappleU", light.dappleU)
    sh:send("uDappleV", light.dappleV)
  end
  sh:send("uDappleRange", { light and light.dappleLow or 1, light and light.dappleHigh or 1, dap and 1 or 0 })
  local sat = light and Render.SATURATION or 0
  local sent
  for _, m in ipairs(scene.meshes) do
    -- (the trees' art is graded as it loads, src/scene/light.lua gradeTrees)
    local want = m.layer == "trees" and 0 or sat
    if want ~= sent then sh:send("uSaturation", want); sent = want end
    G.draw(m.mesh)
  end
  if light then Render.after(G, Camera, target, p, proj, depth, haze, fog, w, h, light) end
  G.pop()
  return target
end

--- After the world, in Emerald 3DS's order (CtrVoxel_Draw, then RenderBattleWorld): the fog's
--- banks and the sand's dust lying in the scene, the light in the air, the rain, sand or ash
--- (src/scene/weather.lua, src/scene/sunfx.lua); then the picture's finish - the diorama's blur,
--- the entrance's zoom blur, the bloom, the speed lines and vignette, the landing's flash
--- (src/scene/screenfx.lua). `light` also carries the frame's weather (weather, weatherAmount,
--- lightning, fogDensity, cave), `intro` (ScreenFx.intro), `diorama` (the blur's strength) and
--- `introLow` (true: the vignette runs to the canvas's foot).
function Render.after(G, Camera, target, p, proj, depth, haze, fog, w, h, light)
  local ex, ey, ez, rx, rz, ux, uy, uz, fx, fy, fz = Camera.basis(p)
  local o = { light = light, Camera = Camera, pose = p, view = Camera.viewRows(p), proj = proj, depth = depth,
    sun = light.sunDir or { dx = 0.85, dz = 0.55 }, seconds = light.seconds or 0, w = w, h = h,
    fog = fog, haze = haze, eye = { ex, ey, ez }, forward = { fx, fy, fz }, right = { rx, 0, rz },
    up = { ux, uy, uz } }
  local W, S, F = Render.Weather, Render.SunFx, Render.ScreenFx
  if W then
    local fogAmount = light.fogDensity or 0
    if fogAmount > 0 then
      pcall(W.banks, G, o, W.FOG_BANKS, light.cave and W.CAVE_FOG_COLOUR or W.FOG_COLOUR, fogAmount)
    end
    -- (the sand's dust is the fog's sheets, sweeping along the ground)
    if light.weather == "sand" and (light.weatherAmount or 0) > 0 then
      pcall(W.banks, G, o, W.SAND_BANKS, W.SAND_COLOUR, light.weatherAmount)
    end
  end
  if S then pcall(S.air, G, target, o) end
  if W and (light.weatherAmount or 0) > 0 then
    pcall(W.draw, G, o, light.weather, light.weatherAmount, light.lightning or 0)
  end
  -- the finish: the bloom taken from the world as it stands, the blurs laid over it, then the
  -- bloom added
  local intro = light.intro
  local impact = intro and intro.impact or light.impact or 0
  local bloom = S and S.bloomStrength(light, impact) or 0
  local okB, glow = false, nil
  if S then okB, glow = pcall(S.bloomPrepare, G, target, w, h, bloom) end
  if F then
    local blur = light.diorama or 0
    local speed = intro and intro.speed or 0
    if blur > 0.005 or speed >= 0.04 then
      local okC, copy = pcall(F.copy, G, target, w, h)
      if okC and copy then
        pcall(F.diorama, G, target, copy, w, h, blur)
        -- (about the camera's target: the canvas's middle, where the battle's sprites stand)
        pcall(F.zoomBlur, G, target, copy, w, h, proj[2], proj[4], speed)
      end
    end
  end
  if S and okB and glow then pcall(S.bloomCompose, G, target, w, h, glow, bloom) end
  if F and intro then
    -- (the text box's line, GBA row 112, on the canvas)
    local floorY = proj[4] + 32 * proj[3] / Camera.F
    pcall(F.atmosphere, G, target, w, h, intro, floorY, light.introLow and h or floorY)
    pcall(F.flash, G, target, w, h, intro.impact)
  end
end

return Render
