-- The scene's light (Battle Scene: Overworld) by the map's weather: the colour grade's sun and
-- shade tints, the distance haze, and the strengths of the sun dapples, rays, bloom and motes.
--
-- Ported from Emerald 3DS's src/voxel/ctr_voxel.c (the VoxelLight struct, BaseLightFor,
-- LightMix, FogLight, SetGrade) and src/voxel/voxel_world.c (VoxelWorld_Weather,
-- _WeatherAmount, _FogDensity, _Lightning), by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds (see LICENSE). Every number is theirs. Not ported:
-- their day/night cycle's tint and moonlight (LightFor; their "day_night" setting, off unless
-- the player turns it on), so the light is BaseLightFor's.
--
-- The grade (their voxel.v.pica): a vertex's shade picks how sunlit it is,
-- t = clamp((shade - 0.62) / 0.38, 0, 1), and its colour is shade * lerp(shade tint, sun tint, t):
-- cool in shadow, warm in sun. The haze starts a little beyond the player and grows towards the
-- top of the screen, relative to the eye's distance from the target, so a camera framed from
-- further away hazes the same share of the screen: at view depth d,
-- clamp((d - eye * start) / (eye * ramp), 0, 1) * haze.

local Light = {}

-- VOXEL_GRADE_SHADE_LOW: at or below, fully the shadow tint
Light.SHADE_LOW = 0.62
-- VOXEL_GRADE_SATURATION: each 5-bit channel pushed away from the colour's luma (voxel_grade.c)
Light.SATURATION = 1.30
-- VOXEL_TREE_BRIGHTNESS and the tree art's crowns it brightens (BrightenCrowns: x, y, w, h)
Light.TREE_BRIGHTNESS = 1.12
Light.CROWNS = { { 0, 0, 32, 36 }, { 32, 32, 16, 32 }, { 64, 0, 16, 32 }, { 0, 64, 128, 32 } }
-- VOXEL_HAZE_START / _RAMP (x the eye-to-target distance), _MAX, _COLOUR (0xFFFAE6D2, ABGR)
Light.HAZE_START, Light.HAZE_RAMP, Light.HAZE_MAX = 1.05, 0.60, 0.14
Light.HAZE_COLOUR = { 0xD2 / 255, 0xE6 / 255, 0xFA / 255 }

-- pokeemerald's weather ids (include/constants/weather.h)
local W = {
  SUNNY_CLOUDS = 1, SUNNY = 2, RAIN = 3, SNOW = 4, RAIN_THUNDERSTORM = 5, FOG_HORIZONTAL = 6,
  VOLCANIC_ASH = 7, SANDSTORM = 8, FOG_DIAGONAL = 9, UNDERWATER = 10, SHADE = 11, DROUGHT = 12,
  DOWNPOUR = 13, UNDERWATER_BUBBLES = 14,
}
Light.WEATHER = W
local MAX_RAIN_SPRITES = 24

local CLASS = {
  [W.SUNNY] = "sun", [W.DROUGHT] = "sun",
  [W.RAIN] = "rain", [W.RAIN_THUNDERSTORM] = "rain", [W.DOWNPOUR] = "rain",
  [W.FOG_HORIZONTAL] = "fog", [W.FOG_DIAGONAL] = "fog", [W.UNDERWATER] = "fog", [W.UNDERWATER_BUBBLES] = "fog",
  [W.SNOW] = "particles", [W.VOLCANIC_ASH] = "ash", [W.SANDSTORM] = "sand",
  [W.SHADE] = "shade", [W.SUNNY_CLOUDS] = "shade",
}

--- VoxelWorld_Weather: the class of a weather id ("clear" for none and the rest).
function Light.class(weather) return CLASS[weather] or "clear" end

--- VoxelWorld_WeatherAmount over the game's weather state (gWeatherPtr's fields): how far rain,
--- ash or a sandstorm has come in, 0..1.
function Light.amount(S)
  local w = S and S.currWeather
  if w == W.RAIN or w == W.RAIN_THUNDERSTORM or w == W.DOWNPOUR then
    return (S.curRainSpriteIndex or 0) / MAX_RAIN_SPRITES
  elseif w == W.VOLCANIC_ASH then
    if not S.ashSpritesCreated then return 0 end
  elseif w == W.SANDSTORM then
    if not S.sandstormSpritesCreated then return 0 end
  else
    return 0
  end
  return math.min((S.currBlendEVA or 0) / 16, 1)
end

--- VoxelWorld_Lightning: a thunderstorm's bolt, 0..1 (its colour map 19, the storm's own 3).
function Light.lightning(S)
  local i = S and S.colorMapIndex or 0
  if not S or S.currWeather ~= W.RAIN_THUNDERSTORM or i <= 3 then return 0 end
  return i >= 19 and 1 or (i - 3) / 16
end

--- VoxelWorld_FogDensity: the fog's own blend (its sprites come in at EVA 12), 0..1.
function Light.fogDensity(S)
  if not (S and (S.fogHSpritesCreated or S.fogDSpritesCreated)) then return 0 end
  return math.min((S.currBlendEVA or 0) / 12, 1)
end

local SCALARS = { "haze", "dappleLow", "dappleHigh", "rays", "bloom", "motes", "start", "ramp" }
local COLOURS = { "sun", "shade", "rgb" }

local function copy(l)
  local out = {}
  for _, k in ipairs(SCALARS) do out[k] = l[k] end
  for _, k in ipairs(COLOURS) do out[k] = { l[k][1], l[k][2], l[k][3] } end
  return out
end

--- LightMix: a to b by t, every field.
function Light.mix(a, b, t)
  local out = copy(a)
  for _, k in ipairs(SCALARS) do out[k] = a[k] + (b[k] - a[k]) * t end
  for _, k in ipairs(COLOURS) do
    for i = 1, 3 do out[k][i] = a[k][i] + (b[k][i] - a[k][i]) * t end
  end
  return out
end

--- FogLight: the game's fog, a pale veil outdoors, cold and dim under the ground with the
--- distance sinking into a blue-black; come in with the fog's own blend.
function Light.fog(clear, cave, density)
  local fog = copy(clear)
  if cave then
    fog.sun, fog.shade = { 0.76, 0.80, 0.88 }, { 0.58, 0.64, 0.78 }
    fog.haze, fog.dappleLow, fog.dappleHigh = 0.86, 1.0, 1.0
    fog.rgb, fog.start, fog.ramp = { 0.10, 0.12, 0.17 }, 0.86, 0.55
    fog.rays, fog.bloom, fog.motes = 0, 0, 0
  else
    -- fog glows: more bloom, and no dust or rays to see in it
    fog.sun = { 0.95, 0.98, 1.00 }
    fog.haze, fog.dappleLow, fog.dappleHigh = 0.70, 0.95, 1.02
    fog.rays, fog.bloom, fog.motes = 0, 0.18, 0
    fog.rgb, fog.start, fog.ramp = { 0.80, 0.83, 0.87 }, 0.80, 0.65
  end
  return Light.mix(clear, fog, density)
end

--- BaseLightFor. o = { indoor (MAP_TYPE_INDOOR or SECRET_BASE: the grade is the identity, no
--- haze, dapples, rays, bloom or motes), weather (the game's current weather id), state (its
--- weather state, for the amounts), cave (MAP_TYPE_UNDERGROUND) }. Returns { sun, shade, rgb
--- (the haze's colour), haze, start, ramp, dappleLow, dappleHigh, rays, bloom, motes }.
function Light.light(o)
  local light = { sun = { 1.00, 0.99, 0.95 }, shade = { 0.93, 0.97, 1.05 }, haze = Light.HAZE_MAX,
                  dappleLow = 0.96, dappleHigh = 1.04, rays = 0.11, bloom = 0.07, motes = 0.85,
                  rgb = { Light.HAZE_COLOUR[1], Light.HAZE_COLOUR[2], Light.HAZE_COLOUR[3] },
                  start = Light.HAZE_START, ramp = Light.HAZE_RAMP }
  if o.indoor then
    light.sun, light.shade = { 1, 1, 1 }, { 1, 1, 1 }
    light.haze, light.dappleLow, light.dappleHigh = 0, 1, 1
    light.rays, light.bloom, light.motes = 0, 0, 0
    return light
  end
  local S = o.state
  local class = Light.class(o.weather)
  if class == "sun" then
    light.sun = { 1.04, 1.01, 0.93 }
    light.haze, light.dappleLow, light.dappleHigh = 0.12, 0.94, 1.07
    light.rays, light.bloom, light.motes = 0.14, 0.10, 1.00
  elseif class == "rain" then
    -- overcast: no sun to break into patches, rays or glinting dust; the air grey with rain,
    -- the distance goes sooner, colder; a bolt lights the world cold white for a moment
    light.sun, light.shade = { 0.81, 0.88, 0.98 }, { 0.82, 0.89, 1.00 }
    light.dappleLow, light.dappleHigh = 1.0, 1.0
    light.rays, light.bloom, light.motes = 0, 0.08, 0
    light.rgb = { 0.62, 0.68, 0.76 }
    light.haze = 0.30 + 0.18 * Light.amount(S)
    light.start = 0.85
    local bolt = Light.lightning(S)
    for c = 1, 3 do
      light.sun[c] = light.sun[c] + (1.55 - light.sun[c]) * bolt
      light.shade[c] = light.shade[c] + (1.45 - light.shade[c]) * bolt
      light.rgb[c] = light.rgb[c] + (0.92 - light.rgb[c]) * bolt
    end
    light.bloom = light.bloom + 0.30 * bolt
  elseif class == "sand" then
    -- a sandstorm: the sun a warm smudge, the shadows filled with the dust's own glow, and the
    -- distance gone into ochre
    local sand = copy(light)
    sand.sun, sand.shade = { 1.04, 0.93, 0.76 }, { 0.96, 0.86, 0.72 }
    sand.haze, sand.rgb, sand.start, sand.ramp = 0.72, { 0.86, 0.70, 0.48 }, 0.55, 0.95
    sand.dappleLow, sand.dappleHigh = 1.0, 1.0
    sand.rays, sand.bloom, sand.motes = 0, 0.16, 0
    light = Light.mix(light, sand, Light.amount(S))
  elseif class == "ash" then
    -- under the volcano's plume: a dim, warm grey light, no hard sun to cast dapples, the far
    -- slopes lost in ash
    local ash = copy(light)
    ash.sun, ash.shade = { 0.90, 0.87, 0.84 }, { 0.80, 0.80, 0.83 }
    ash.haze, ash.rgb, ash.start, ash.ramp = 0.50, { 0.66, 0.63, 0.61 }, 0.75, 0.90
    ash.dappleLow, ash.dappleHigh = 0.96, 1.01
    ash.rays, ash.bloom, ash.motes = 0, 0.10, 0
    light = Light.mix(light, ash, Light.amount(S))
  elseif class == "fog" then
    light = Light.fog(light, o.cave, Light.fogDensity(S))
  elseif class == "particles" then
    -- the weather's own snow fills the air instead
    light.sun = { 0.93, 0.92, 0.88 }
    light.haze, light.dappleLow, light.dappleHigh = 0.36, 0.92, 1.03
    light.rays, light.bloom, light.motes = 0, 0.12, 0
  elseif class == "shade" then
    light.sun = { 0.92, 0.95, 0.98 }
    light.haze, light.dappleLow, light.dappleHigh = 0.25, 0.92, 1.03
    light.rays, light.bloom, light.motes = 0, 0.12, 0.40
  end
  return light
end

--- SetGrade's fog for an eye that far from its target (tiles, along the line of sight): the
--- render's { start, end, max } in view depth.
function Light.range(light, eye)
  local s = eye * light.start
  return { s, s + eye * light.ramp, light.haze }
end

--- One 8-bit channel (the engine's 5-bit colour, c5 * 255 / 31) graded: voxel_grade.c's Channel.
local function channel(v)
  local c = math.floor(v + 0.5)
  return c < 0 and 0 or c > 31 and 31 or c
end

--- VoxelGrade_Init's table for a colour of 5-bit channels: each pushed from its luma by
--- SATURATION, rounded, clamped. Returns r5, g5, b5.
function Light.saturate5(r, g, b)
  local y = 0.299 * r + 0.587 * g + 0.114 * b
  local s = Light.SATURATION
  return channel(y + (r - y) * s), channel(y + (g - y) * s), channel(y + (b - y) * s)
end

--- The tree art graded as their tree texture loads: every texel saturated, then the crowns
--- brightened (VoxelGrade_Brighten). data: love ImageData of the 128x128 art, changed in place.
function Light.gradeTrees(data)
  local w, h = data:getDimensions()
  local function c5(v) return math.floor(v * 31 + 0.5) end
  local inCrown = {}
  for _, r in ipairs(Light.CROWNS) do
    for y = r[2], math.min(h, r[2] + r[4]) - 1 do
      for x = r[1], math.min(w, r[1] + r[3]) - 1 do inCrown[y * w + x] = true end
    end
  end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      local R, G, B = Light.saturate5(c5(r), c5(g), c5(b))
      if inCrown[y * w + x] then
        local f = Light.TREE_BRIGHTNESS
        R, G, B = channel(R * f), channel(G * f), channel(B * f)
      end
      data:setPixel(x, y, R / 31, G / 31, B / 31, a)
    end
  end
  return data
end

-- ── the sun dapples (ctr_voxel.c MakeDapple, DappleFrame, DappleUniforms) ──
-- Soft patches of light and shade, as under broken cloud, drifting slowly the way the shadows
-- fall: one small tileable pattern laid over the world from above along the sun, a point first
-- slid along the sun by its height (a roof and the ground beside it take the patch the same light
-- passed through), multiplied into the lit texel from dappleLow (pattern 0) to dappleHigh (1).

Light.DAPPLE_DIM = 128
Light.DAPPLE_PERIOD = 24       -- tiles along the pattern before it repeats
Light.DAPPLE_STRETCH = 0.70    -- across it: patches lie along the sun
Light.DAPPLE_DRIFT = 0.25      -- tiles per second

local bit = require("bit")
local TWO32 = 4294967296
-- a 32-bit product, wrapped, of two numbers 0 .. 2^32 - 1
local function mul32(a, b)
  local alo, ahi = a % 65536, math.floor(a / 65536) % 65536
  return (alo * b + ((ahi * b) % 65536) * 65536) % TWO32
end
local function u32(n) return n % TWO32 end
local function xorShift(h, s) return u32(bit.bxor(bit.tobit(h), bit.rshift(bit.tobit(h), s))) end

--- DappleLattice: a lattice point's value, repeating every `period` cells.
function Light.dappleLattice(x, y, period, seed)
  local h = u32(mul32(x % period, 374761393) + mul32(y % period, 668265263) + mul32(seed, 2246822519))
  h = mul32(xorShift(h, 13), 1274126177)
  h = xorShift(h, 16)
  return (h % 65536) / 65535
end

local function quintic(t) return t * t * t * (t * (t * 6 - 15) + 10) end
local function dappleNoise(u, v, period, seed)
  local x, y = math.floor(u), math.floor(v)
  local fx, fy = quintic(u - x), quintic(v - y)
  local L = Light.dappleLattice
  local a, b = L(x, y, period, seed), L(x + 1, y, period, seed)
  local c, d = L(x, y + 1, period, seed), L(x + 1, y + 1, period, seed)
  local top, bottom = a + (b - a) * fx, c + (d - c) * fx
  return top + (bottom - top) * fy
end

--- MakeDapple: the pattern's 128x128 values 0..255 (three octaves of tileable noise, then a
--- soft threshold: broad patches with ragged, blurred edges, a little more light than shade).
--- set(x, y, value).
function Light.makeDapple(set)
  local octaves = { { 3, 1.0 }, { 6, 0.5 }, { 12, 0.2 } }
  local D = Light.DAPPLE_DIM
  for y = 0, D - 1 do
    for x = 0, D - 1 do
      local n, total = 0, 0
      for o, oc in ipairs(octaves) do
        local scale = oc[1] / D
        n = n + oc[2] * dappleNoise(x * scale, y * scale, oc[1], o)
        total = total + oc[2]
      end
      local t = (n / total - 0.40) / 0.20
      t = t < 0 and 0 or t > 1 and 1 or t
      set(x, y, math.floor(t * t * (3 - 2 * t) * 255 + 0.5))
    end
  end
end

--- DappleFrame and DappleUniforms for a mesh whose point (x, y, z) stands at (x + ox, y + oy,
--- z + oz) in the world, `seconds` into the drift: the pattern's coordinates as two planes,
--- u = U[1] x + U[2] y + U[3] z + U[4] (and V), U[4] and V[4] wrapped to a tile of the pattern.
function Light.dapplePlanes(sun, seconds, ox, oy, oz)
  local DX, DZ = sun.dx, sun.dz
  local len = math.sqrt(DX * DX + DZ * DZ)
  local c, s = DX / len, DZ / len
  local su, sv = 1 / Light.DAPPLE_PERIOD, 1 / (Light.DAPPLE_PERIOD * Light.DAPPLE_STRETCH)
  local drift = (seconds * Light.DAPPLE_DRIFT) % Light.DAPPLE_PERIOD
  local U = { c * su, (c * DX + s * DZ) * su, s * su }
  local V = { -s * sv, (c * DZ - s * DX) * sv, c * sv }
  local u0 = U[1] * ox + U[2] * oy + U[3] * oz - drift * su
  local v0 = V[1] * ox + V[2] * oy + V[3] * oz
  U[4], V[4] = u0 - math.floor(u0), v0 - math.floor(v0)
  return U, V
end

return Light
