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
-- the ground is interpolated perspective-correct. Distance fades into a haze colour.

local Render = {}

Render.CARD_SHADE = 0.82
Render.BORDER_COURSES = 2   -- how tall the border round the map stands (Emerald 3DS's two courses)
Render.SHADE = { south = 0.60, north = 0.50, west = 0.65, east = 0.55 }
Render.UV_INSET = 0.02      -- texels kept off a tile's edge (no neighbour bleeding at an angle)
Render.FLAT_MARK = 0.5      -- the vertex alpha of a standing cell's ground copy
Render.HIDE_AT = 2          -- the rise past which those copies are gone (above 1: never; a wide
                            -- block of trees is not wholly covered by its cards)

local SHADER = [[
varying float vDepth;
#ifdef VERTEX
uniform mat4 uView;
uniform vec4 uProj;
uniform vec2 uDepth;
uniform float uRise;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 q = vertex_position;
  q.y *= uRise;
  vec4 c = uView * q;
  float w = c.z;
  vDepth = w;
  vec4 p = transform_projection * vec4(uProj.x * c.x + uProj.y * w, -uProj.z * c.y + uProj.w * w, 0.0, w);
  p.z = uDepth.x * w + uDepth.y;
  return p;
}
#endif
#ifdef PIXEL
uniform vec3 uHaze;
uniform vec3 uFog;
uniform float uHideFlat;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  // (a standing cell's own ground copy, marked by its alpha: gone once the cards stand)
  if (color.a < 0.75 && uHideFlat > 0.5) discard;
  vec4 t = Texel(tex, tc);
  if (t.a < 0.5) discard;
  float f = clamp((vDepth - uFog.x) / (uFog.y - uFog.x), 0.0, 1.0) * uFog.z;
  return vec4(mix(t.rgb * color.rgb, uHaze, f), 1.0);
}
#endif
]]

Render.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
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
function Render.vertices(grid, tiles, ox, oz, trees, buildings)
  local out = { lower = {}, upper = {}, trees = {}, models = {} }
  local function list(layer, image)
    local l = out[layer][image]
    if not l then
      l = {}
      out[layer][image] = l
    end
    return l
  end
  local function put(layer, image, q, a, b, c, d, shade, alpha)
    if not (image and q) then return end
    local iw, ih = image:getDimensions()
    local u0, v0, u1, v1 = uvOf(q, iw, ih)
    quad(list(layer, image), a, b, c, d, u0, v0, u1, v1, shade, alpha)
  end
  local Trees = trees and trees.Trees
  local timg = trees and trees.image
  local dim, e = Trees and Trees.DIM or 1, Render.UV_INSET
  -- a tree's quad (corners in map cells, uvs in atlas texels), lifted with its cell (`lift`) and
  -- as far south (`shift`: a border tree's is its belt's, VoxelTree_EmitBorder)
  local lift, shift = 0, 0
  local function putTree(a, b, c, d, u0, v0, u1, v1)
    local function rel(p) return { p[1] - ox, p[2] + lift, p[3] - oz + shift } end
    quad(list("trees", timg), rel(a), rel(b), rel(c), rel(d),
      (u0 + e) / dim, (v0 + e) / dim, (u1 - e) / dim, (v1 - e) / dim, 1, 1)
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
        for _, k in ipairs({ 1, 2, 3, 1, 3, 4 }) do
          local v = p[k]
          l[#l + 1] = { v[1], v[2], v[3], u0 + (u1 - u0) * v[4], v0 + (v1 - v0) * v[5], shade, shade, shade, 1 }
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
  local function skirts(cell, t, mid)
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
                faceUV(t, mid, { Q(xa, fh[k], fz[k], along[k], fA), Q(xb, fh[k + 1], fz[k + 1], along[k + 1], fB),
                                 Q(xb, belt, y + bz, along[k + 1], 0), Q(xa, belt, y + bz, along[k], 0) }, SH.south)
              else
                local za, zb = y + along[k] + bz, y + along[k + 1] + bz
                if d == 2 then
                  faceUV(t, mid, { Q(x, belt, zb, 0, along[k + 1]), Q(x, belt, za, 0, along[k]),
                                   Q(x, fh[k], fz[k], fA, along[k]), Q(x, fh[k + 1], fz[k + 1], fB, along[k + 1]) },
                    SH.east)
                else
                  faceUV(t, mid, { Q(x + 1, belt, za, 1, along[k]), Q(x + 1, belt, zb, 1, along[k + 1]),
                                   Q(x + 1, fh[k + 1], fz[k + 1], 1 - fB, along[k + 1]),
                                   Q(x + 1, fh[k], fz[k], 1 - fA, along[k]) }, SH.west)
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
            faceUV(t, mid, { Q(xa, hA, zA, k / LAST, 1), Q(xb, hB, zB, (k + 1) / LAST, 1),
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
        if not treeGround and not cell.lifted then
          put("lower", t.image, t.quad(slot), a, b, c, d, 1, flat)
          put("upper", t.overImage, t.overQuad(slot), a, b, c, d, 1, flat)
        end
        if cell.border then block(cell, t, part) end
        if part then
          Trees.emit(putTree, sec, cell.mid, cell.cx, cell.cy, part, function(x, y)
            local o = grid.at(x, y)
            if not o or o.pair ~= cell.pair then return false end
            return Trees.part(sec, o.mid)
          end)
        end
        if card then
          -- standing on the run's southern edge, `up` tiles high
          local z, y0 = cell.base + 1 - oz + dy, cell.up + dy
          local ca, cb = { x0, y0 + 1, z }, { x1, y0 + 1, z }
          local cc, cd = { x1, y0, z }, { x0, y0, z }
          local s = Render.CARD_SHADE
          put("lower", t.image, t.quad(slot), ca, cb, cc, cd, s)
          put("upper", t.overImage, t.overQuad(slot), ca, cb, cc, cd, s)
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
      buildings.Buildings.emit(pl, ox, oz, function(v)
        v[2], v[3] = v[2] + pdy, v[3] + pdy
        l[#l + 1] = v
      end)
    end
    if pl.ground then
      local w, h = md.ref.w, md.ref.h
      local gl = list("lower", pl.ground)
      for j = 0, h - 1 do
        for i = 0, w - 1 do
          local cell = grid.at(pl.cx + i, pl.cy + j)
          if cell and cell.model == pl then
            local cdy = cell.dy or 0
            local x0, z0 = pl.cx + i - ox, pl.cy + j - oz + cdy
            quad(gl, { x0, cdy, z0 }, { x0 + 1, cdy, z0 }, { x0 + 1, cdy, z0 + 1 }, { x0, cdy, z0 + 1 },
              (i + e / 16) / w, (j + e / 16) / h, (i + 1 - e / 16) / w, (j + 1 - e / 16) / h, 1, 1)
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
---   haze { r, g, b }, fog { start, end, max }
function Render.draw(G, Camera, scene, pose, proj, depth, rise, haze, fog, w, h)
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
  G.clear(haze[1], haze[2], haze[3], 1, false, 1)
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
  sh:send("uFog", fog)
  sh:send("uHideFlat", (rise or 1) > Render.HIDE_AT and 1 or 0)
  for _, m in ipairs(scene.meshes) do G.draw(m.mesh) end
  G.pop()
  return target
end

return Render
