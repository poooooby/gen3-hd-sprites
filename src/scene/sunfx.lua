-- The light in the air over the battle scene (Battle Scene: Overworld): faint sun rays from the
-- top left, sunlit dust drifting in the air, and bloom - the brightest parts glowing softly into
-- their surroundings, and a burst of it as the camera lands. Drawn into the world's own canvas
-- after the world, so the battle's Pokemon stay over them, as in Emerald 3DS's battle (the world
-- is the battle's background there too).
--
-- Ported from Emerald 3DS's src/voxel/ctr_voxel.c (MakeRays, DrawRays, DrawMotes, MoteRandom,
-- the battle intro's impact) and src/3ds_video.c (VoxelBloomPrepare, VoxelBloomCompose), by Zallax
-- and contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds (see LICENSE). Every
-- number is theirs. Changes: in LOVE; the rays laid over the world's canvas (their screen, 400 x
-- 240, the units their pattern and falloff are measured in); the bloom's quarter-size picture
-- made by halving the canvas until it is near their 400 wide, then the quarter with the
-- threshold, so a large window averages as their screen does.

local SunFx = {}

SunFx.GAME_W, SunFx.GAME_H = 400, 240       -- CTR_GAME_WIDTH x HEIGHT

SunFx.RAY_COLS, SunFx.RAY_ROWS = 8, 5
SunFx.RAY_REACH = 0.65        -- of the screen's diagonal, from the corner
SunFx.RAY_ANGLE = 35          -- degrees off vertical, leaning right
SunFx.RAY_ACROSS = 260        -- pixels across the rays per pattern period
SunFx.RAY_ALONG = 4000        -- ... and along them
SunFx.RAY_DRIFT = 0.012       -- pattern periods per second, across
SunFx.RAY_COLOUR = { 255 / 255, 240 / 255, 208 / 255 }

SunFx.MOTES = 32
SunFx.MOTE_HALF_X, SunFx.MOTE_HALF_Z = 11, 9   -- tiles each side of the camera's target
SunFx.MOTE_LOW, SunFx.MOTE_HIGH = 0.3, 2.6       -- tiles above the ground
SunFx.MOTE_SIZE = 0.10        -- tiles from the middle to a corner
SunFx.MOTE_WIND = 0.35        -- tiles per second, the way the shadows fall
SunFx.MOTE_COLOUR = { 255 / 255, 244 / 255, 216 / 255 }

SunFx.BLOOM_THRESHOLD = 0.85
SunFx.LANDING_BLOOM = 0.7     -- the landing's burst, at its height

local floor, sqrt, sin, cos, rad, exp = math.floor, math.sqrt, math.sin, math.cos, math.rad, math.exp

--- RayStrength: the rays' strength at (x, y) of the screen, 0..1 each way with y up: strongest in
--- the top left corner, gone before the far one.
function SunFx.rayStrength(x, y)
  local dx, dy = x * SunFx.GAME_W, (1 - y) * SunFx.GAME_H
  local diagonal = sqrt(SunFx.GAME_W * SunFx.GAME_W + SunFx.GAME_H * SunFx.GAME_H)
  local s = 1 - sqrt(dx * dx + dy * dy) / (diagonal * SunFx.RAY_REACH)
  return s <= 0 and 0 or s * s
end

--- The battle intro's landing (CtrVoxel_BattleIntro's impact) at glide progress u, the share
--- `travel` of it the flight.
function SunFx.impact(u, travel)
  local q = (u - travel) / (1 - travel)
  q = q < 0 and 0 or q > 1 and 1 or q
  return (q > 0 and q < 1) and exp(-5 * q) * (1 - q) or 0
end

local MOTE_MOD = 4294967296
local bit = require("bit")
local function mul32(a, b)
  local alo, ahi = a % 65536, floor(a / 65536) % 65536
  return (alo * b + ((ahi * b) % 65536) * 65536) % MOTE_MOD
end
local function u32(n) return n % MOTE_MOD end
--- MoteRandom: a fixed pseudo-random number in 0..1 for mote i.
function SunFx.moteRandom(i, salt)
  local h = u32(bit.bxor(bit.tobit(mul32(i, 2654435761)), bit.tobit(mul32(salt, 2246822519))))
  h = mul32(u32(bit.bxor(bit.tobit(h), bit.rshift(bit.tobit(h), 15))), 2246822519)
  h = u32(bit.bxor(bit.tobit(h), bit.rshift(bit.tobit(h), 13)))
  return (h % 65536) / 65535
end

local function wrap(value, size) return value - floor(value / size) * size end

local RAYS = [[
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) { return transform_projection * vertex_position; }
#endif
#ifdef PIXEL
uniform Image uDapple;
uniform float uStrength;
uniform float uDrift;
uniform vec3 uColour;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float a = (1.0 - Texel(uDapple, tc + vec2(uDrift, 0.0)).r) * color.a * uStrength;
  return vec4(uColour, a);
}
#endif
]]

local MOTES = [[
#ifdef VERTEX
uniform mat4 uView;
uniform vec4 uProj;
uniform vec2 uDepth;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 c = uView * vertex_position;
  float w = c.z;
  vec4 p = transform_projection * vec4(uProj.x * c.x + uProj.y * w, -uProj.z * c.y + uProj.w * w, 0.0, w);
  p.z = uDepth.x * w + uDepth.y;
  return p;
}
#endif
#ifdef PIXEL
uniform float uStrength;
uniform vec3 uColour;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) { return vec4(uColour, color.a * uStrength); }
#endif
]]

local THRESHOLD = [[
uniform float uThreshold;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec3 c = Texel(tex, tc).rgb;
  return vec4(clamp((c - uThreshold) * 4.0, 0.0, 1.0), 1.0);
}
]]

local shaders = {}
local function shader(G, key, src)
  if shaders[key] == nil then
    local ok, sh = pcall(G.newShader, src)
    shaders[key] = ok and sh or false
  end
  return shaders[key] or nil
end

-- the rays' mesh over the screen (MakeRays): cells with no light left out
local rayMesh, rayW, rayH
local function rays(G, dapple, strength, seconds, w, h)
  local sh = shader(G, "rays", RAYS)
  if not (sh and dapple) or strength <= 0 then return end
  if not rayMesh or rayW ~= w or rayH ~= h then
    local angle = rad(SunFx.RAY_ANGLE)
    local along, across = { sin(angle), -cos(angle) }, { cos(angle), sin(angle) }
    local verts = {}
    local corner = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 0 }, { 1, 1 }, { 0, 1 } }
    for row = 0, SunFx.RAY_ROWS - 1 do
      for col = 0, SunFx.RAY_COLS - 1 do
        local x0, x1 = col / SunFx.RAY_COLS, (col + 1) / SunFx.RAY_COLS
        local y0, y1 = row / SunFx.RAY_ROWS, (row + 1) / SunFx.RAY_ROWS
        local S = SunFx.rayStrength
        if not (S(x0, y0) <= 0 and S(x1, y0) <= 0 and S(x0, y1) <= 0 and S(x1, y1) <= 0) then
          for _, k in ipairs(corner) do
            local x, y = k[1] == 1 and x1 or x0, k[2] == 1 and y1 or y0
            local px, py = x * SunFx.GAME_W, y * SunFx.GAME_H
            local u = (across[1] * px + across[2] * py) / SunFx.RAY_ACROSS
            local v = (along[1] * px + along[2] * py) / SunFx.RAY_ALONG
            verts[#verts + 1] = { x * w, (1 - y) * h, u, v, 1, 1, 1, S(x, y) }
          end
        end
      end
    end
    rayMesh = #verts > 0 and G.newMesh(verts, "triangles", "static") or false
    rayW, rayH = w, h
  end
  if not rayMesh then return end
  rayMesh:setTexture(dapple)
  G.setShader(sh)
  sh:send("uDapple", dapple)
  sh:send("uStrength", strength)
  -- (the pattern drifts across the rays)
  sh:send("uDrift", (seconds * SunFx.RAY_DRIFT) % 1)
  sh:send("uColour", SunFx.RAY_COLOUR)
  G.setDepthMode("always", false)
  G.setBlendMode("add", "alphamultiply")
  G.draw(rayMesh)
end

-- the sunlit dust (DrawMotes): soft diamonds turned to the camera, in a wrapped box round its target
local moteMesh
local function motes(G, Camera, p, view, proj, depth, strength, sun, seconds)
  local sh = shader(G, "motes", MOTES)
  if not sh or strength <= 0 then return end
  seconds = seconds % 3600
  local len = sqrt(sun.dx * sun.dx + sun.dz * sun.dz)
  local windX, windZ = sun.dx / len * SunFx.MOTE_WIND, sun.dz / len * SunFx.MOTE_WIND
  local _, _, _, rx, rz, ux, uy, uz = Camera.basis(p)
  local S = SunFx.MOTE_SIZE
  rx, rz, ux, uy, uz = rx * S, rz * S, ux * S, uy * S, uz * S
  local ox, oz = floor(p.tx), floor(p.tz)
  local verts = {}
  local R = SunFx.moteRandom
  for i = 0, SunFx.MOTES - 1 do
    local phase = R(i, 1) * 6.2832
    local wx = R(i, 2) * 64 + seconds * windX * (0.6 + 0.8 * R(i, 3))
    local wz = R(i, 4) * 64 + seconds * windZ * (0.6 + 0.8 * R(i, 3))
    local x = ox + wrap(wx - ox + SunFx.MOTE_HALF_X, 2 * SunFx.MOTE_HALF_X) - SunFx.MOTE_HALF_X
    local z = oz + wrap(wz - oz + SunFx.MOTE_HALF_Z, 2 * SunFx.MOTE_HALF_Z) - SunFx.MOTE_HALF_Z
    local y = (p.ty or 0) + SunFx.MOTE_LOW + (SunFx.MOTE_HIGH - SunFx.MOTE_LOW) * R(i, 5) + 0.15 * sin(seconds * 0.7 + phase)
    local glint = 0.55 + 0.45 * sin(seconds * (1.1 + R(i, 6)) + phase * 2)
    local c = { x, y, z, 0, 0, 1, 1, 1, glint }
    local up = { x + ux, y + uy, z + uz, 0, 0, 1, 1, 1, 0 }
    local right = { x + rx, y, z + rz, 0, 0, 1, 1, 1, 0 }
    local down = { x - ux, y - uy, z - uz, 0, 0, 1, 1, 1, 0 }
    local left = { x - rx, y, z - rz, 0, 0, 1, 1, 1, 0 }
    for _, v in ipairs({ c, up, right, c, right, down, c, down, left, c, left, up }) do verts[#verts + 1] = v end
  end
  local fmt = { { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "float", 4 } }
  if not moteMesh then
    moteMesh = G.newMesh(fmt, verts, "triangles", "stream")
  else
    moteMesh:setVertices(verts)
  end
  G.setShader(sh)
  sh:send("uView", "row", view)
  sh:send("uProj", proj)
  sh:send("uDepth", depth)
  sh:send("uStrength", strength)
  sh:send("uColour", SunFx.MOTE_COLOUR)
  G.setDepthMode("lequal", false)
  G.setBlendMode("add", "alphamultiply")
  G.draw(moteMesh)
end

-- the bloom (VoxelBloomPrepare / Compose): the picture at a quarter of their screen, keeping only
-- what is brighter than the threshold, stretched back over it and added
local chain = {}
local function canvasOf(G, k, w, h)
  local c = chain[k]
  if not c or c:getWidth() ~= w or c:getHeight() ~= h then
    if c and c.release then pcall(c.release, c) end
    c = G.newCanvas(w, h, { dpiscale = 1 })
    c:setFilter("linear", "linear")
    chain[k] = c
  end
  return c
end
--- VoxelBloomPrepare: what of the picture in `target` is brighter than the threshold, at a
--- quarter of their screen (a canvas of ours), or nil when there is no bloom to add.
function SunFx.bloomPrepare(G, target, w, h, strength)
  local th = shader(G, "threshold", THRESHOLD)
  if not th or strength <= 0.005 then return nil end
  G.setDepthMode("always", false)
  G.setShader()
  G.setBlendMode("replace", "premultiplied")
  G.setColor(1, 1, 1, 1)
  -- halved until the picture is no wider than their screen's 400 (each step a 2x2 average)
  local cur, cw, ch, k = target, w, h, 0
  while cw > SunFx.GAME_W do
    local nw, nh = math.max(1, floor(cw / 2)), math.max(1, floor(ch / 2))
    k = k + 1
    local c = canvasOf(G, k, nw, nh)
    G.setCanvas(c)
    G.draw(cur, 0, 0, 0, nw / cw, nh / ch)
    cur, cw, ch = c, nw, nh
  end
  -- the quarter of their screen, the threshold kept
  local bw = floor(SunFx.GAME_W / 4)
  local bh = math.max(1, floor(bw * h / w + 0.5))
  local small = canvasOf(G, "bloom", bw, bh)
  G.setCanvas(small)
  G.setShader(th)
  th:send("uThreshold", SunFx.BLOOM_THRESHOLD)
  G.draw(cur, 0, 0, 0, bw / cw, bh / ch)
  G.setShader()
  return small
end

--- VoxelBloomCompose: the prepared glow stretched back over the picture in `target`, added.
function SunFx.bloomCompose(G, target, w, h, small, strength)
  if not small or strength <= 0.005 then return end
  local bw, bh = small:getWidth(), small:getHeight()
  G.setDepthMode("always", false)
  G.setShader()
  G.setCanvas(target)
  G.setBlendMode("add", "alphamultiply")
  G.setColor(1, 1, 1, strength)
  G.draw(small, 0, 0, 0, w / bw, h / bh)
  G.setColor(1, 1, 1, 1)
end

--- After the world is drawn into `target` (its depth still bound): the motes and the rays into
--- it. o = { light (src/scene/light.lua: rays, motes strengths, dappleImage), Camera, pose (the
--- mesh's frame), view, proj, depth, sun, seconds, w, h }.
function SunFx.air(G, target, o)
  local light = o.light
  if not light then return end
  local seconds = o.seconds or 0
  motes(G, o.Camera, o.pose, o.view, o.proj, o.depth, light.motes or 0, o.sun, seconds)
  rays(G, light.dappleImage, light.rays or 0, seconds, o.w, o.h)
end

--- This frame's bloom: the light's own, and the landing's burst dying away with its flash
--- (`impact`, 0..1).
function SunFx.bloomStrength(light, impact)
  local b = (light and light.bloom or 0) + SunFx.LANDING_BLOOM * (impact or 0)
  return b > 1 and 1 or b
end

--- The air, then the bloom over the picture (with nothing between them).
function SunFx.draw(G, target, o)
  if not o.light then return end
  SunFx.air(G, target, o)
  local b = SunFx.bloomStrength(o.light, o.impact)
  SunFx.bloomCompose(G, target, o.w, o.h, SunFx.bloomPrepare(G, target, o.w, o.h, b), b)
end

return SunFx
