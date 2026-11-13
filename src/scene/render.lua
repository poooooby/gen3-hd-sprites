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
  -- a tree's quad (corners in map cells, uvs in atlas texels)
  local function putTree(a, b, c, d, u0, v0, u1, v1)
    local function rel(p) return { p[1] - ox, p[2], p[3] - oz } end
    quad(list("trees", timg), rel(a), rel(b), rel(c), rel(d),
      (u0 + e) / dim, (v0 + e) / dim, (u1 - e) / dim, (v1 - e) / dim, 1, 1)
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
        local slot = t.slot(mid)
        local x0, z0 = cell.cx - ox, cell.cy - oz
        local x1, z1 = x0 + 1, z0 + 1
        -- on the ground: north-west corner first (the tile's top left). A standing cell's ground
        -- copy is marked (alpha 0.5): it shows only while the cards rise
        local a, b, c, d = { x0, 0, z0 }, { x1, 0, z0 }, { x1, 0, z1 }, { x0, 0, z1 }
        -- (a tree's cell lays the tree's own ground, unless it stands in water the ground lays)
        local treeGround = part and Trees.laysGround(sec, cell.mid)
        -- what stands as a card: a blocked cell no model covers (a tree's, a crown's over it)
        local card = cell.up and not part and mid == cell.mid
        local flat = card and Render.FLAT_MARK or 1
        if not treeGround then
          put("lower", t.image, t.quad(slot), a, b, c, d, 1, flat)
          put("upper", t.overImage, t.overQuad(slot), a, b, c, d, 1, flat)
        end
        if part then
          Trees.emit(putTree, sec, cell.mid, cell.cx, cell.cy, part, function(x, y)
            local o = grid.at(x, y)
            if not o or o.pair ~= cell.pair then return false end
            return Trees.part(sec, o.mid)
          end)
        end
        if card then
          -- standing on the run's southern edge, `up` tiles high
          local z, y0 = cell.base + 1 - oz, cell.up
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
    if md.image then
      local l = list("models", md.image)
      buildings.Buildings.emit(pl, ox, oz, function(v) l[#l + 1] = v end)
    end
    if pl.ground then
      local w, h = md.ref.w, md.ref.h
      local gl = list("lower", pl.ground)
      for j = 0, h - 1 do
        for i = 0, w - 1 do
          local cell = grid.at(pl.cx + i, pl.cy + j)
          if cell and cell.model == pl then
            local x0, z0 = pl.cx + i - ox, pl.cy + j - oz
            quad(gl, { x0, 0, z0 }, { x0 + 1, 0, z0 }, { x0 + 1, 0, z0 + 1 }, { x0, 0, z0 + 1 },
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
  local p = Camera.pose(pose.tx - scene.ox, pose.tz - scene.oz, pose.pitch, pose.dist)
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
