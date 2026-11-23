-- The scene's light (Battle Scene: Overworld) by the map's weather: the colour grade's sun and
-- shade tints, the distance haze, and the strengths of the sun dapples, rays, bloom and motes.
--
-- Ported from Emerald 3DS's src/voxel/ctr_voxel.c (the VoxelLight struct, BaseLightFor,
-- LightMix, FogLight, SetGrade) and src/voxel/voxel_world.c (VoxelWorld_Weather,
-- _WeatherAmount, _FogDensity, _Lightning), by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds (see LICENSE). Every number is theirs. Their day-night
-- cycle (3ds_daynight.c CtrDayNight_At / _Moonlight, ctr_voxel.c LightFor) is ported too
-- (Light.cycle, Light.dayNight), by the game's clock or WoobleDex's (src/clock.lua); not its
-- windows' and lamps' glow, nor the sun's path through the day.
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

-- WoobleView's own (not Emerald 3DS's): a battle's sun (Sunny Day, Drought, a Max Flare) is a
-- harsh, warm glare, brighter than a sunny route's; its hail a cold grey under the clouds, the
-- distance whitened by the ice (src/scene/battle_weather.lua)
Light.BATTLE = {
  sun = { sun = { 1.24, 1.07, 0.80 }, shade = { 1.04, 0.97, 0.86 }, rgb = { 1.00, 0.86, 0.64 }, haze = 0.26,
          start = 0.95, ramp = 0.60, dappleLow = 0.88, dappleHigh = 1.16, rays = 0.30, bloom = 0.26, motes = 1.00 },
  hail = { sun = { 0.84, 0.90, 1.00 }, shade = { 0.80, 0.88, 1.02 }, rgb = { 0.80, 0.86, 0.94 }, haze = 0.40,
           start = 0.80, ramp = 0.80, dappleLow = 1.00, dappleHigh = 1.00, rays = 0, bloom = 0.10, motes = 0 },
}

--- The battle's sun or hail laid over `light` by `amount` (0..1), in place.
function Light.battle(light, kind, amount)
  local b = Light.BATTLE[kind]
  if not (b and light and amount and amount > 0) then return light end
  local t = math.min(amount, 1)
  for _, k in ipairs(SCALARS) do light[k] = light[k] + (b[k] - light[k]) * t end
  for _, k in ipairs(COLOURS) do
    local c = light[k]
    for i = 1, 3 do c[i] = c[i] + (b[k][i] - c[i]) * t end
  end
  return light
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
-- (a light's own fields: the rest - the frame's, src/scene/init.lua - cleared from a kept table)
local BASE = { sun = true, shade = true, rgb = true, haze = true, dappleLow = true, dappleHigh = true, rays = true,
               bloom = true, motes = true, start = true, ramp = true }
-- a colour set in place (t), or a new one
local function set3(t, a, b, c)
  if not t then return { a, b, c } end
  t[1], t[2], t[3] = a, b, c
  return t
end

--- (out: a table of the caller's, kept between frames, filled instead of a new one - its
--- colours too; the weathers mixed from two lights, sand, ash and fog, return a new one)
function Light.light(o, out)
  local light = out or {}
  if out then
    for k in pairs(out) do if not BASE[k] then out[k] = nil end end
  end
  light.sun = set3(light.sun, 1.00, 0.99, 0.95)
  light.shade = set3(light.shade, 0.93, 0.97, 1.05)
  light.rgb = set3(light.rgb, Light.HAZE_COLOUR[1], Light.HAZE_COLOUR[2], Light.HAZE_COLOUR[3])
  light.haze, light.dappleLow, light.dappleHigh = Light.HAZE_MAX, 0.96, 1.04
  light.rays, light.bloom, light.motes = 0.11, 0.07, 0.85
  light.start, light.ramp = Light.HAZE_START, Light.HAZE_RAMP
  if o.indoor then
    light.sun, light.shade = set3(light.sun, 1, 1, 1), set3(light.shade, 1, 1, 1)
    light.haze, light.dappleLow, light.dappleHigh = 0, 1, 1
    light.rays, light.bloom, light.motes = 0, 0, 0
    return light
  end
  local S = o.state
  local class = Light.class(o.weather)
  if class == "sun" then
    light.sun = set3(light.sun, 1.04, 1.01, 0.93)
    light.haze, light.dappleLow, light.dappleHigh = 0.12, 0.94, 1.07
    light.rays, light.bloom, light.motes = 0.14, 0.10, 1.00
  elseif class == "rain" then
    -- overcast: no sun to break into patches, rays or glinting dust; the air grey with rain,
    -- the distance goes sooner, colder; a bolt lights the world cold white for a moment
    light.sun, light.shade = set3(light.sun, 0.81, 0.88, 0.98), set3(light.shade, 0.82, 0.89, 1.00)
    light.dappleLow, light.dappleHigh = 1.0, 1.0
    light.rays, light.bloom, light.motes = 0, 0.08, 0
    light.rgb = set3(light.rgb, 0.62, 0.68, 0.76)
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
    light.sun = set3(light.sun, 0.93, 0.92, 0.88)
    light.haze, light.dappleLow, light.dappleHigh = 0.36, 0.92, 1.03
    light.rays, light.bloom, light.motes = 0, 0.12, 0
  elseif class == "shade" then
    light.sun = set3(light.sun, 0.92, 0.95, 0.98)
    light.haze, light.dappleLow, light.dappleHigh = 0.25, 0.92, 1.03
    light.rays, light.bloom, light.motes = 0, 0.12, 0.40
  end
  return light
end

-- Emerald 3DS's day-night cycle (3ds_port/src/3ds_daynight.c CtrDayNight_At): by the minute of
-- the day, the light's tint, how much daylight there is (the sun's dapples, rays and motes) and
-- how much glow (night: the moonlight). Between two keys the smoothstep of the way across.
Light.CYCLE = {
  { 0, { 0.66, 0.74, 0.92 }, 0.00, 1.00 },
  { 120, { 0.66, 0.74, 0.92 }, 0.00, 1.00 },
  { 240, { 0.96, 0.94, 0.88 }, 0.75, 0.00 },
  { 480, { 0.96, 0.94, 0.88 }, 0.75, 0.00 },
  { 600, { 1.00, 1.00, 1.00 }, 1.00, 0.00 },
  { 900, { 1.00, 1.00, 1.00 }, 1.00, 0.00 },
  { 1020, { 1.00, 0.80, 0.65 }, 0.35, 0.25 },
  { 1080, { 1.00, 0.80, 0.65 }, 0.35, 0.25 },
  { 1200, { 0.66, 0.74, 0.92 }, 0.00, 1.00 },
  { 1440, { 0.66, 0.74, 0.92 }, 0.00, 1.00 },
}
-- CtrDayNight_Moonlight: its colour, and its amount (MOON x glow^2)
Light.MOON_RGB = { 70 / 255, 92 / 255, 136 / 255 }
Light.MOON = 0.06

--- CtrDayNight_At: the cycle at a minute of the day (0-1440): { rgb, daylight, glow } (out: a
--- kept table filled instead).
function Light.cycle(minute, out)
  local K = Light.CYCLE
  local m = (tonumber(minute) or 720) % 1440
  out = out or {}
  for i = 2, #K do
    if m < K[i][1] then
      local a, b = K[i - 1], K[i]
      local t = (m - a[1]) / (b[1] - a[1])
      t = t * t * (3 - 2 * t)
      out.rgb = set3(out.rgb, a[2][1] + (b[2][1] - a[2][1]) * t, a[2][2] + (b[2][2] - a[2][2]) * t,
                     a[2][3] + (b[2][3] - a[2][3]) * t)
      out.daylight, out.glow = a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
      return out
    end
  end
  out.rgb = set3(out.rgb, K[1][2][1], K[1][2][2], K[1][2][3])
  out.daylight, out.glow = K[1][3], K[1][4]
  return out
end

--- CtrDayNight_Moonlight (no fade): how much moonlight the cycle has, 0..0.06.
function Light.moon(cycle)
  local g = cycle and cycle.glow or 0
  return Light.MOON * g * g
end

--- LightFor: the light (Light.light's, outdoors) at that time of day: its sun and shade tinted by
--- the cycle and dimmed by the moonlight's share, the haze tinted and turned towards the
--- moonlight, the sun's rays, motes and dapples by the daylight. Sets light.moon { r, g, b }:
--- the moonlight added to everything lit (their texture environment's multiply-add). Returns
--- the light.
function Light.dayNight(light, cycle)
  local moon = Light.moon(cycle)
  local rgb = cycle.rgb
  for c = 1, 3 do
    light.sun[c] = light.sun[c] * rgb[c] * (1 - moon)
    light.shade[c] = light.shade[c] * rgb[c] * (1 - moon)
    local h = light.rgb[c] * rgb[c]
    light.rgb[c] = h + (Light.MOON_RGB[c] - h) * moon
  end
  light.rays = light.rays * cycle.daylight
  light.motes = light.motes * cycle.daylight
  light.dappleLow = 1 + (light.dappleLow - 1) * cycle.daylight
  light.dappleHigh = 1 + (light.dappleHigh - 1) * cycle.daylight
  light.moon = set3(light.moon, Light.MOON_RGB[1] * moon, Light.MOON_RGB[2] * moon, Light.MOON_RGB[3] * moon)
  light.cycle = cycle
  return light
end

--- The sky behind the world at that time of day: the backdrop's colour as the haze is tinted
--- (out: a kept table filled instead, never `sky` itself).
function Light.sky(sky, cycle, out)
  local moon = Light.moon(cycle)
  out = out or {}
  for c = 1, 3 do
    local h = sky[c] * cycle.rgb[c]
    out[c] = h + (Light.MOON_RGB[c] - h) * moon
  end
  return out
end

--- SetGrade's fog for an eye that far from its target (tiles, along the line of sight): the
--- render's { start, end, max } in view depth (out: a kept table filled instead).
function Light.range(light, eye, out)
  local s = eye * light.start
  return set3(out, s, s + eye * light.ramp, light.haze)
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
--- brightened (VoxelGrade_Brighten). data: love ImageData of the 128x128 art, changed in place;
--- crowns: the art's crowns ({ x, y, w, h }; default Light.CROWNS, the 128x128 art's).
function Light.gradeTrees(data, crowns)
  local w, h = data:getDimensions()
  local function c5(v) return math.floor(v * 31 + 0.5) end
  local inCrown = {}
  for _, r in ipairs(crowns or Light.CROWNS) do
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
--- DappleNoise: tileable value noise at (u, v), repeating every `period` lattice cells (the
--- fog's banks are made of it too, src/scene/weather.lua).
Light.dappleNoise = dappleNoise

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
--- (U, V: kept tables filled instead)
function Light.dapplePlanes(sun, seconds, ox, oy, oz, U, V)
  local DX, DZ = sun.dx, sun.dz
  local len = math.sqrt(DX * DX + DZ * DZ)
  local c, s = DX / len, DZ / len
  local su, sv = 1 / Light.DAPPLE_PERIOD, 1 / (Light.DAPPLE_PERIOD * Light.DAPPLE_STRETCH)
  local drift = (seconds * Light.DAPPLE_DRIFT) % Light.DAPPLE_PERIOD
  U = set3(U, c * su, (c * DX + s * DZ) * su, s * su)
  V = set3(V, -s * sv, (c * DZ - s * DX) * sv, c * sv)
  local u0 = U[1] * ox + U[2] * oy + U[3] * oz - drift * su
  local v0 = V[1] * ox + V[2] * oy + V[3] * oz
  U[4], V[4] = u0 - math.floor(u0), v0 - math.floor(v0)
  return U, V
end

return Light
