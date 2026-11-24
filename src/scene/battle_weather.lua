-- The battle's own weather and terrain in the battle scene (WoobleView's own, not Emerald 3DS's).
-- A battle's weather can differ from the route's: Rain Dance, Drought, Sunny Day, Sandstorm,
-- Hail, and other mods' moves (Galar Rising's Max Moves). While a battle is up, its weather is
-- shown in the world over the field's: rain and the sandstorm as the field's own (their ids
-- through src/scene/light.lua and src/scene/weather.lua), the sun as a harsher, warmer light
-- than the route's (Light.battle) and hail as ice falling heavier and slower than rain
-- (Weather.KINDS.hail). WoobleDex's terrains (its exports.battle.terrainOf) glow on the ground
-- under and between the battlers in their colour, breathing slowly, ringed by a deeper rim so the
-- patch reads on any ground (src/scene/render.lua), and shed motes that rise from it and fade
-- (BW.motes: leaves, sparks, puffs of mist, rings).
--
-- Each comes in and goes out over FADE seconds; a new weather waits for the old one to go. Kept
-- on the scene (s.battleWx), started afresh for each battle's state.

local BW = {}

BW.FADE = 1.2                -- seconds to come in or go
-- the engine's kinds (src/core/game3/battle/rules.lua Rules.weather.kind) -> the scene's
BW.KIND = { RAIN = "rain", SUN = "sun", SAND = "sand", HAIL = "hail" }
-- WoobleDex's terrains: the glow's colour; its rim's, deeper, the patch's outline against any
-- ground (a green patch on a green route); how far the glow lifts the ground toward its colour
-- (a pale colour little, or it only whitens); and the motes it sheds (BW.MOTES)
BW.TERRAIN = {
  ELECTRIC = { 1.00, 0.88, 0.22, rim = { 0.95, 0.50, 0.04 }, lift = 0.28, motes = "sparks" },
  GRASSY = { 0.36, 0.92, 0.38, rim = { 0.03, 0.30, 0.07 }, lift = 0.30, motes = "leaves" },
  MISTY = { 1.00, 0.62, 0.86, rim = { 0.84, 0.18, 0.54 }, lift = 0.10, motes = "puffs" },
  PSYCHIC = { 0.80, 0.42, 1.00, rim = { 0.40, 0.08, 0.70 }, lift = 0.28, motes = "rings" },
}
BW.RIM_AT = 0.9              -- the rim's middle, a share of the glow's reach
BW.RIM_WIDTH = 0.07          -- ... its half width
BW.TERRAIN_STRENGTH = 1.0    -- the glow at its full
BW.BREATH = 3.2              -- seconds a breath of the glow takes
BW.BREATH_DEPTH = 0.22       -- how far it dims and brightens with it
BW.TERRAIN_RADIUS = 1.9      -- tiles from the line between the battlers' feet to the glow's edge

-- The motes each terrain sheds, rising from its patch: how many; a life's seconds; how high one
-- rises in it and its size (tiles); how far it sways; its spin (turns a life); how much it grows
-- over its life; flicker (a spark's: bursting up, then slowing, and flickering); the share of the
-- glow's reach they start within; its colours (each mote somewhere from the first to the second);
-- how strong; added (bright) or laid over; and how it stands - "face" (to the camera), "up"
-- (upright across the view, a streak) or "flat" (lying level as it rises).
BW.MOTES = {
  leaves = { count = 44, life = 2.8, rise = 1.5, size = 0.10, sway = 0.22, spin = 1.2, grow = 0, flicker = 0,
             reach = 0.85, colour = { 0.66, 0.98, 0.42 }, colour2 = { 0.10, 0.52, 0.14 }, alpha = 1.0,
             add = false, stand = "face" },
  sparks = { count = 40, life = 0.9, rise = 1.4, size = 0.11, sway = 0.05, spin = 0, grow = 0, flicker = 1,
             reach = 0.85, colour = { 1.00, 1.00, 0.86 }, colour2 = { 1.00, 0.86, 0.20 }, alpha = 1.0,
             add = false, stand = "up" },
  puffs = { count = 26, life = 3.6, rise = 1.0, size = 0.28, sway = 0.16, spin = 0.1, grow = 0.9, flicker = 0,
            reach = 0.8, colour = { 1.00, 0.95, 0.98 }, colour2 = { 1.00, 0.70, 0.88 }, alpha = 0.9,
            add = false, stand = "face" },
  rings = { count = 12, life = 2.4, rise = 1.2, size = 0.20, sway = 0, spin = 0, grow = 1.2, flicker = 0,
            reach = 0.75, colour = { 0.80, 0.48, 1.00 }, colour2 = { 1.00, 0.52, 0.92 }, alpha = 0.95,
            add = false, stand = "flat" },
}

-- set by the scene (src/scene/init.lua): its require (pcall'd, nil for a missing module), and
-- WoobleDex's terrain reader (main.lua; nil without WoobleDex)
BW.req = nil
BW.terrainOf = nil

-- one weather's (or terrain's) way in and out: the kind shown and how far it is in, toward the
-- kind wanted
local function ease(cur, a, want, dt)
  local step = dt / BW.FADE
  if want ~= cur then
    if not cur or a <= 0 then return want, want and math.min(step, 1) or 0 end
    a = a - step
    if a <= 0 then return want, 0 end
    return cur, a
  end
  if cur then return cur, math.min(1, a + step) end
  return nil, 0
end
BW.ease = ease

--- The battle's weather and terrain kinds as they stand ("rain" / "sun" / "sand" / "hail" or nil,
--- "ELECTRIC" ... or nil), and its state table (nil outside a battle).
function BW.read()
  local req = BW.req
  if not req then return nil, nil, nil end
  local B = req("src.core.game3.battle")
  if type(B) ~= "table" then return nil, nil, nil end
  local okA, active = pcall(function() return B.isActive and B.isActive() end)
  if not (okA and active) then return nil, nil, nil end
  local okS, st = pcall(function() return type(B.getState) == "function" and B.getState() or B._st end)
  st = okS and type(st) == "table" and st or nil
  if not st then return nil, nil, nil end
  local wk, tk
  local R = req("src.core.game3.battle.rules")
  local okK, k = pcall(function() return R and R.weather and R.weather.kind(st.weather) end)
  if okK and k then wk = BW.KIND[k] end
  if BW.terrainOf then
    local okT, t = pcall(BW.terrainOf, st)
    if okT and BW.TERRAIN[t] then tk = t end
  end
  return wk, tk, st
end

--- This frame's battle weather and terrain on scene s, eased: weather kind, its amount (0..1),
--- the terrain's colour (nil for none) and its amount.
function BW.frame(s, now)
  local wk, tk, st = BW.read()
  local keep = s.battleWx
  if not keep then
    keep = { wa = 0, ta = 0 }
    s.battleWx = keep
  end
  if keep.st ~= st and st ~= nil then
    keep.st, keep.wk, keep.wa, keep.tk, keep.ta, keep.t = st, nil, 0, nil, 0, now
  end
  local dt = math.min(math.max(now - (keep.t or now), 0), 0.1)
  keep.t = now
  keep.wk, keep.wa = ease(keep.wk, keep.wa, wk, dt)
  keep.tk, keep.ta = ease(keep.tk, keep.ta, tk, dt)
  return keep.wk, keep.wa, keep.tk and BW.TERRAIN[keep.tk] or nil, keep.ta
end

--- The terrain's glow this moment: its amount times the strength, breathing.
function BW.glow(amount, seconds)
  if not amount or amount <= 0 then return 0 end
  local breath = 1 - BW.BREATH_DEPTH + BW.BREATH_DEPTH * math.sin((seconds or 0) * 2 * math.pi / BW.BREATH)
  return amount * BW.TERRAIN_STRENGTH * breath
end

-- ---------------------------------------------------------------------------------------------
-- The terrain's motes. One static mesh per kind, made once: each mote's corners carry its seeds
-- (where in the patch, its phase in its life, its shade) and its shape; the shader moves them,
-- each life starting from a new spot of the patch, so nothing is made a frame.

local function hash01(i, salt)
  local x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
  return x - math.floor(x)
end

-- each kind's shape: triangles of { x, y, alpha } corners, in units of its size
local function fan(n, r, inner, outer)
  local out = {}
  for k = 0, n - 1 do
    local a0, a1 = k / n * 2 * math.pi, (k + 1) / n * 2 * math.pi
    out[#out + 1] = { 0, 0, inner }
    out[#out + 1] = { math.cos(a0) * r, math.sin(a0) * r, outer }
    out[#out + 1] = { math.cos(a1) * r, math.sin(a1) * r, outer }
  end
  return out
end
local function band(out, n, r0, a0, r1, a1)
  for k = 0, n - 1 do
    local t0, t1 = k / n * 2 * math.pi, (k + 1) / n * 2 * math.pi
    local c0, s0, c1, s1 = math.cos(t0), math.sin(t0), math.cos(t1), math.sin(t1)
    local p, q = { c0 * r0, s0 * r0, a0 }, { c1 * r0, s1 * r0, a0 }
    local P, Q = { c0 * r1, s0 * r1, a1 }, { c1 * r1, s1 * r1, a1 }
    out[#out + 1] = p; out[#out + 1] = P; out[#out + 1] = Q
    out[#out + 1] = p; out[#out + 1] = Q; out[#out + 1] = q
  end
  return out
end
BW.SHAPES = {
  -- (a leaf: a long diamond)
  leaves = { { 0, 1, 1 }, { 0.42, 0, 1 }, { 0, -1, 1 }, { 0, 1, 1 }, { 0, -1, 1 }, { -0.42, 0, 1 } },
  -- (a spark: a bright head, its tail fading below it)
  sparks = { { 0, 1, 1 }, { 0.22, 0.45, 1 }, { 0, -1.5, 0 }, { 0, 1, 1 }, { 0, -1.5, 0 }, { -0.22, 0.45, 1 } },
  -- (a puff: round and soft)
  puffs = fan(10, 1, 1, 0),
  -- (a ring: soft on both its sides)
  rings = band(band({}, 16, 0.6, 0, 0.8, 1), 16, 0.8, 1, 1.0, 0),
}

--- A kind's mesh's vertices: per mote and corner { seed x, seed y, phase, shade, corner x,
--- corner y, 1, 1, 1, the corner's alpha }.
function BW.moteVerts(name)
  local kind, shape = BW.MOTES[name], BW.SHAPES[name]
  if not (kind and shape) then return nil end
  local out = {}
  for i = 1, kind.count do
    local sx, sy = hash01(i, 1), hash01(i, 2)
    -- (their lives spread evenly, each a little off its place)
    local phase = ((i - 1) + 0.5 * hash01(i, 3)) / kind.count
    local shade = hash01(i, 4)
    for _, c in ipairs(shape) do
      out[#out + 1] = { sx, sy, phase, shade, c[1], c[2], 1, 1, 1, c[3] }
    end
  end
  return out
end

-- the world's projection (src/scene/render.lua, src/scene/weather.lua) and the motes on it: each
-- life a new spot of the patch (round the line between the battlers' feet), rising and fading
local MOTES_GLSL = [[
varying float vHaze;
varying float vAlpha;
varying float vShade;
#ifdef VERTEX
uniform mat4 uView;
uniform vec4 uProj;
uniform vec2 uDepth;
uniform vec3 uFog;
uniform vec4 uSeg;     // the line between the battlers' feet: one's xz, the other's
uniform vec4 uAt;      // the ground's height, the glow's reach, the time (s), the glow
uniform vec4 uLife;    // a life's seconds, how high it rises, its size, its sway
uniform vec4 uStyle;   // spin (turns a life), growth, flicker, the share of the reach it starts in
uniform vec3 uAxisX;   // the shape's two axes as it stands
uniform vec3 uAxisY;
float hash(float a, float b) { return fract(sin(a * 127.1 + b * 311.7) * 43758.5453); }
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  float t = uAt.z / uLife.x + vertex_position.z;
  float cyc = floor(t);
  float k = t - cyc;
  float h1 = hash(vertex_position.x, cyc), h2 = hash(vertex_position.y, cyc + 17.0);
  float h3 = hash(vertex_position.x + vertex_position.y, cyc + 41.0);
  vec2 a = uSeg.xy, ab = uSeg.zw - uSeg.xy;
  float len = length(ab);
  vec2 dir = len > 0.0001 ? ab / len : vec2(1.0, 0.0);
  vec2 side = vec2(-dir.y, dir.x);
  float ang = h2 * 6.2831853;
  vec2 xz = a + ab * h1 + (dir * cos(ang) + side * sin(ang)) * (uAt.y * uStyle.w * sqrt(h3));
  xz += side * sin(k * 8.17 + h2 * 6.2831853) * uLife.w;
  float rise = uLife.y * mix(k, 1.0 - (1.0 - k) * (1.0 - k), uStyle.z);
  float spin = uStyle.x > 0.0 ? (h3 + k * uStyle.x) * 6.2831853 : 0.0;
  vec2 c = VertexTexCoord.xy;
  float cs = cos(spin), sn = sin(spin);
  c = vec2(c.x * cs - c.y * sn, c.x * sn + c.y * cs);
  float size = uLife.z * (0.75 + 0.5 * h1) * (1.0 + uStyle.y * k);
  vec3 w = vec3(xz.x, uAt.x + 0.06 + rise, xz.y) + (uAxisX * c.x + uAxisY * c.y) * size;
  vec4 cv = uView * vec4(w, 1.0);
  vHaze = clamp((cv.z - uFog.x) / max(uFog.y - uFog.x, 0.0001), 0.0, 1.0) * uFog.z;
  float fade = smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.55, 1.0, k));
  float flicker = mix(1.0, 0.45 + 0.55 * step(0.5, fract(k * 9.0 + h2 * 5.0)), uStyle.z);
  vAlpha = fade * flicker * uAt.w * (1.0 - vHaze);
  vShade = vertex_position.w;
  float wz = cv.z;
  vec4 p = transform_projection * vec4(uProj.x * cv.x + uProj.y * wz, -uProj.z * cv.y + uProj.w * wz, 0.0, wz);
  p.z = uDepth.x * wz + uDepth.y;
  return p;
}
#endif
#ifdef PIXEL
uniform vec3 uColour;
uniform vec3 uColour2;
uniform vec3 uHaze;
uniform float uStrength;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(mix(mix(uColour, uColour2, vShade), uHaze, vHaze), vAlpha * color.a * uStrength);
}
#endif
]]
BW.MOTES_GLSL = MOTES_GLSL

local FORMAT_MOTE = { { "VertexPosition", "float", 4 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "float", 4 } }
local moteMade = {}
local function moteShader(G)
  if moteMade.shader == nil then
    local ok, sh = pcall(G.newShader, MOTES_GLSL)
    moteMade.shader = ok and sh or false
    if not ok then BW.moteError = tostring(sh) end
  end
  return moteMade.shader or nil
end
local function moteMesh(G, name)
  if moteMade[name] == nil then
    local verts = BW.moteVerts(name)
    local ok, mesh = false, nil
    if verts then ok, mesh = pcall(G.newMesh, FORMAT_MOTE, verts, "triangles", "static") end
    moteMade[name] = ok and mesh or false
    if not ok and mesh then BW.moteError = tostring(mesh) end
  end
  return moteMade[name] or nil
end

-- (the uniforms, kept: the shader copies what it is sent)
local uSeg, uAt, uLife, uStyle = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
local uAxisX, uAxisY = { 0, 0, 0 }, { 0, 0, 0 }

--- The terrain's motes rising from its glow, drawn into the world (src/scene/render.lua's
--- Render.after, after the weather): `terrain` a BW.TERRAIN entry, `seg` the line between the
--- battlers' feet on the ground ({ x, z, x, z }), `at` { ground height, the glow's reach },
--- `glow` the glow this frame (BW.glow: faded in and out, breathing). o = { view, proj, depth,
--- fog, haze, seconds, right, up } (Weather.draw's). True when drawn.
function BW.motes(G, o, terrain, seg, at, glow)
  local name = terrain and terrain.motes
  local kind = name and BW.MOTES[name]
  if not kind or not glow or glow <= 0 then return false end
  local sh, mesh = moteShader(G), moteMesh(G, name)
  if not (sh and mesh) then return false end
  G.setShader(sh)
  sh:send("uView", "row", o.view)
  sh:send("uProj", o.proj)
  sh:send("uDepth", o.depth)
  sh:send("uFog", o.fog)
  sh:send("uHaze", o.haze)
  uSeg[1], uSeg[2], uSeg[3], uSeg[4] = seg[1], seg[2], seg[3], seg[4]
  -- (the time wrapped at a whole number of lives: each mote's life runs on unbroken)
  local span = kind.life * 256
  uAt[1], uAt[2], uAt[3], uAt[4] = at[1] or 0, at[2] or BW.TERRAIN_RADIUS, (o.seconds or 0) % span, math.min(glow, 1)
  uLife[1], uLife[2], uLife[3], uLife[4] = kind.life, kind.rise, kind.size, kind.sway
  uStyle[1], uStyle[2], uStyle[3], uStyle[4] = kind.spin, kind.grow, kind.flicker, kind.reach
  local r, u = o.right, o.up
  if kind.stand == "flat" then
    uAxisX[1], uAxisX[2], uAxisX[3], uAxisY[1], uAxisY[2], uAxisY[3] = 1, 0, 0, 0, 0, 1
  elseif kind.stand == "up" then
    uAxisX[1], uAxisX[2], uAxisX[3], uAxisY[1], uAxisY[2], uAxisY[3] = r[1], r[2], r[3], 0, 1, 0
  else
    uAxisX[1], uAxisX[2], uAxisX[3], uAxisY[1], uAxisY[2], uAxisY[3] = r[1], r[2], r[3], u[1], u[2], u[3]
  end
  sh:send("uSeg", uSeg)
  sh:send("uAt", uAt)
  sh:send("uLife", uLife)
  sh:send("uStyle", uStyle)
  sh:send("uAxisX", uAxisX)
  sh:send("uAxisY", uAxisY)
  sh:send("uColour", kind.colour)
  sh:send("uColour2", kind.colour2)
  sh:send("uStrength", kind.alpha)
  G.setDepthMode("lequal", false)
  G.setBlendMode(kind.add and "add" or "alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  G.draw(mesh)
  G.setBlendMode("alpha", "alphamultiply")
  BW.lastMotes = name
  return true
end

-- (the field weather state the battle's rain or sand is read as: kept, filled each frame)
local wxState = {}

--- The field weather id and state the battle's weather `kind` at `amount` is drawn as, over the
--- field's own (weather, state); Light: src/scene/light.lua. The field's rain or sand of the same
--- kind is kept as it is (a thunderstorm's bolts too), its amount at least the battle's. The sun
--- and hail clear the field's weather: their light is Light.battle's, hail's ice Weather's.
function BW.fieldFor(kind, amount, weather, state, Light)
  local W = Light.WEATHER
  local fieldClass = Light.class(weather)
  local S = wxState
  for k in pairs(S) do S[k] = nil end
  if kind == "rain" then
    local a = math.max(amount, fieldClass == "rain" and Light.amount(state) or 0)
    local id = fieldClass == "rain" and weather or W.RAIN
    S.currWeather, S.curRainSpriteIndex, S.currBlendEVA = id, a * 24, 16
    S.colorMapIndex = fieldClass == "rain" and state and state.colorMapIndex or nil
    return id, S
  elseif kind == "sand" then
    local a = math.max(amount, fieldClass == "sand" and Light.amount(state) or 0)
    S.currWeather, S.sandstormSpritesCreated, S.currBlendEVA = W.SANDSTORM, true, a * 16
    return W.SANDSTORM, S
  elseif kind == "sun" then
    S.currWeather = W.SUNNY
    return W.SUNNY, S
  end
  -- hail: nothing of the field's
  return nil, nil
end

return BW
