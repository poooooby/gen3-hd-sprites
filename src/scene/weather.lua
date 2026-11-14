-- The weather in the battle scene (Battle Scene: Overworld): the rain's streaks, the sandstorm's
-- grains and the volcanic ash's flakes falling through the world at their own depth (a roof hides
-- the rain behind it, near drops are larger and faster than far ones, the distance haze swallows
-- the far ones), and the game's fog as two banks of drifting mist lying over the ground, one at
-- the knees and one at the chest - the sandstorm's dust sweeping along on the same two sheets.
-- Drawn into the world's own canvas after the world, depth tested and never written, so the
-- battle's Pokemon stay over them (the world is the battle's background, as in Emerald 3DS).
--
-- Ported from Emerald 3DS's src/voxel/ctr_voxel.c (MakeFog, DrawBanks, MakeWeather, DrawWeather,
-- WeatherOffset and the weather kinds) and src/voxel/voxel_weather.v.pica, by Zallax and
-- contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds (see LICENSE). Every
-- number is theirs. Changes: in LOVE (the particles' program as a GLSL shader, the coverage
-- texture as RGBA); the frame is the scene's meshes' own, so the patterns are anchored to it.

local Weather = {}

local floor, sqrt = math.floor, math.sqrt

local function rgb(r, g, b) return { r / 255, g / 255, b / 255 } end

-- the fog's banks
Weather.FOG_DIM = 128
Weather.FOG_GRID = 8           -- cells along each side of a sheet
Weather.FOG_REACH = 32         -- tiles from the sheet's centre to its side
Weather.FOG_FADE = 0.55        -- ... share of that reach at which it starts to thin
-- { period (tiles the pattern covers before it repeats), height (tiles above the ground),
--   driftX, driftZ (tiles per second), strength (the most the bank covers, at full fog) }
Weather.FOG_BANKS = {
  { period = 12, height = 0.30, driftX = -0.55, driftZ = 0.00, strength = 0.58 },
  { period = 7, height = 1.10, driftX = -0.85, driftZ = -0.25, strength = 0.34 },
}
-- the sandstorm's dust on the same two sheets (their periods are the sheets' own): low and
-- thick, swept along by the wind
Weather.SAND_BANKS = {
  { period = 12, height = 0.35, driftX = -5.20, driftZ = 0.55, strength = 0.50 },
  { period = 7, height = 1.30, driftX = -7.80, driftZ = 0.25, strength = 0.30 },
}
Weather.FOG_COLOUR = rgb(0xE6, 0xEB, 0xF2)
Weather.CAVE_FOG_COLOUR = rgb(0x9E, 0xAB, 0xBF)
Weather.SAND_COLOUR = rgb(0xE0, 0xBE, 0x88)

-- the particles
Weather.STREAKS = 768
Weather.FLAKES = 512
Weather.GROUPS = 3
Weather.FLAKE_RIM = 0.35       -- a flake's corners against its middle: soft, with a body to it
Weather.SOUTH = 1.0            -- the box's south side, tiles north of the camera's eye
-- how sharply a particle fades in from the box's sides (x 1/2 the box): across, north to
-- south, top and bottom
Weather.EDGE, Weather.EDGE_ALONG, Weather.TOP = 8.0, 24.0, 6.0
-- gone this near the lens, whole from LENS + RAMP tiles away: no streak smeared over the picture
Weather.LENS, Weather.LENS_RAMP = 1.5, 1.6

-- { box (tiles: across, up, north to south), low (the box's bottom over the ground), colour,
--   alpha (the most a particle is seen), groups: { velocity (tiles per second), width (a
--   streak's, or a flake's size), length (a streak's; 0: a flake), alpha (x the weather's) } }
Weather.KINDS = {
  -- cold and silver: long fast streaks in front, finer and slower ones behind them, the wind
  -- leaning them all the same way
  rain = { box = { 24, 8.5, 28 }, low = -3.0, colour = rgb(0xDE, 0xE8, 0xF4), alpha = 0.62, groups = {
    { velocity = { -1.6, -13.0, 0.5 }, width = 0.034, length = 0.95, alpha = 1.00 },
    { velocity = { -1.3, -11.0, 0.4 }, width = 0.028, length = 0.75, alpha = 0.85 },
    { velocity = { -0.9, -8.5, 0.3 }, width = 0.020, length = 0.45, alpha = 0.60 },
  } },
  -- fine grains blown along the ground in long low gusts, warm
  sand = { box = { 24, 5.0, 28 }, low = -1.5, colour = rgb(0xE6, 0xB8, 0x7E), alpha = 0.55, groups = {
    { velocity = { -13.0, -0.6, 1.0 }, width = 0.030, length = 1.10, alpha = 1.00 },
    { velocity = { -17.0, -0.3, 0.6 }, width = 0.024, length = 1.60, alpha = 0.75 },
    { velocity = { -9.5, 0.4, 1.6 }, width = 0.040, length = 0.60, alpha = 0.85 },
  } },
  -- soft pale flakes drifting down, each layer on its own breeze; large and light enough to
  -- read against the grey ground
  ash = { box = { 24, 8.0, 28 }, low = -2.0, colour = rgb(0xEA, 0xE6, 0xE2), alpha = 1.00, groups = {
    { velocity = { -0.50, -0.75, 0.15 }, width = 0.120, length = 0, alpha = 1.00 },
    { velocity = { -0.25, -1.00, -0.12 }, width = 0.100, length = 0, alpha = 0.95 },
    { velocity = { -0.80, -0.55, 0.30 }, width = 0.145, length = 0, alpha = 0.85 },
  } },
}

--- MakeFog's coverage, 128 x 128: wisps rather than a wash - four octaves of the dapples' noise
--- (`noise(u, v, period, seed)`, src/scene/light.lua), thresholded so that clear gaps open
--- between the banks. set(x, y, value 0..255).
function Weather.makeFog(noise, set)
  local octaves = { { 4, 1.0 }, { 8, 0.55 }, { 16, 0.30 }, { 32, 0.12 } }
  local D = Weather.FOG_DIM
  for y = 0, D - 1 do
    for x = 0, D - 1 do
      local n, total = 0, 0
      for o, oc in ipairs(octaves) do
        local scale = oc[1] / D
        -- (their seeds 11 .. 14, o counting from 0)
        n = n + oc[2] * noise(x * scale, y * scale, oc[1], o + 10)
        total = total + oc[2]
      end
      local t = (n / total - 0.32) / 0.40
      t = t < 0 and 0 or t > 1 and 1 or t
      set(x, y, floor(t * t * (3 - 2 * t) * 255 + 0.5))
    end
  end
end

--- A bank's sheet: a grid round its own centre, the pattern in tiles (repeating every `period`),
--- the coverage at each vertex falling to nothing towards the rim so the sheet has no edge to
--- see. A list of { x, 0, z, u, v, 1, 1, 1, coverage }.
function Weather.sheet(period)
  local reach, grid = Weather.FOG_REACH, Weather.FOG_GRID
  local cell = 2 * reach / grid
  local corners = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 0 }, { 1, 1 }, { 0, 1 } }
  local out = {}
  for gz = 0, grid - 1 do
    for gx = 0, grid - 1 do
      for _, k in ipairs(corners) do
        local x = -reach + (gx + k[1]) * cell
        local z = -reach + (gz + k[2]) * cell
        local r = sqrt(x * x + z * z) / reach
        local edge = (1 - r) / (1 - Weather.FOG_FADE)
        edge = edge < 0 and 0 or edge > 1 and 1 or edge
        out[#out + 1] = { x, 0, z, x / period, z / period, 1, 1, 1, edge * edge * (3 - 2 * edge) }
      end
    end
  end
  return out
end

--- MakeWeather's particles: each at a fixed place in its box (0..1 each way) with its alpha, and
--- its corner in the two vectors `across` and `along` (1/64 of them). A streak runs from its head
--- (along 0), where it is brightest, back up its fall to a tail that is gone (along 38..64); a
--- flake is a fan of four triangles, bright in the middle and fainter at its corners. `random`
--- is MoteRandom (src/scene/sunfx.lua). A list of { x, y, z, alpha, across, along }.
function Weather.particles(random, flakes)
  local out = {}
  local function corner(across, along, place, alpha)
    out[#out + 1] = { place[1], place[2], place[3], alpha, across / 64, along / 64 }
  end
  -- (their places are stored in 1/32768 of the box, alphas in 1/16384)
  local function fraction(f) return floor(f * 32767) / 32768 end
  local function shade(a) return floor(a * 16384) / 16384 end
  if not flakes then
    for i = 0, Weather.STREAKS - 1 do
      local place = { fraction(random(i, 21)), fraction(random(i, 22)), fraction(random(i, 23)) }
      local half = 44 + floor(random(i, 24) * 20)
      local tail = 38 + floor(random(i, 25) * 26)
      local alpha = shade(0.55 + 0.45 * random(i, 26))
      corner(-half, 0, place, alpha)
      corner(half, 0, place, alpha)
      corner(half, tail, place, 0)
      corner(-half, 0, place, alpha)
      corner(half, tail, place, 0)
      corner(-half, tail, place, 0)
    end
  else
    local fan = { { { 0, 1 }, { 1, 0 } }, { { 1, 0 }, { 0, -1 } }, { { 0, -1 }, { -1, 0 } }, { { -1, 0 }, { 0, 1 } } }
    for i = 0, Weather.FLAKES - 1 do
      local place = { fraction(random(i, 31)), fraction(random(i, 32)), fraction(random(i, 33)) }
      local size = 40 + floor(random(i, 34) * 24)
      local alpha = 0.70 + 0.30 * random(i, 35)
      local rim = shade(alpha * Weather.FLAKE_RIM)
      alpha = shade(alpha)
      for k = 1, 4 do
        corner(0, 0, place, alpha)
        corner(fan[k][1][1] * size, fan[k][1][2] * size, place, rim)
        corner(fan[k][2][1] * size, fan[k][2][2] * size, place, rim)
      end
    end
  end
  return out
end

--- WeatherOffset: where in the box a group's particles are this frame, as a share of it wrapped
--- to [0, 1): the world's drift since a fixed time, less the box's own corner.
function Weather.offset(seconds, velocity, corner, size)
  local f = (seconds * velocity - corner) / size
  return f - floor(f)
end

local function normalise(v)
  local l = sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if l > 0.0001 then v[1], v[2], v[3] = v[1] / l, v[2] / l, v[3] / l end
  return v
end

--- A group's two vectors: a streak's across its fall as the camera sees it (`forward`, the view's
--- direction) and back up its fall; a flake's the view's right and up (`right`, `up`).
function Weather.vectors(group, forward, right, up)
  local w = group.width
  if group.length > 0 then
    local v = group.velocity
    local back = normalise({ -v[1], -v[2], -v[3] })
    local across = normalise({ back[2] * forward[3] - back[3] * forward[2],
                               back[3] * forward[1] - back[1] * forward[3],
                               back[1] * forward[2] - back[2] * forward[1] })
    return { across[1] * w, across[2] * w, across[3] * w },
           { back[1] * group.length, back[2] * group.length, back[3] * group.length }
  end
  return { right[1] * w, right[2] * w, right[3] * w }, { up[1] * w, up[2] * w, up[3] * w }
end

-- the view's projection, as the world's (src/scene/render.lua) and the haze from view depth
local PROJECT = [[
uniform mat4 uView;
uniform vec4 uProj;
uniform vec2 uDepth;
uniform vec3 uFog;
vec4 project(mat4 tp, vec4 c) {
  float w = c.z;
  vec4 p = tp * vec4(uProj.x * c.x + uProj.y * w, -uProj.z * c.y + uProj.w * w, 0.0, w);
  p.z = uDepth.x * w + uDepth.y;
  return p;
}
float hazeAt(float d) { return clamp((d - uFog.x) / max(uFog.y - uFog.x, 0.0001), 0.0, 1.0) * uFog.z; }
]]

-- DrawBanks: the bank's colour, coverage = texture x the vertex's x the bank's strength, the far
-- banks sunk into the haze as the ground under them is
local BANKS = [[
varying float vHaze;
#ifdef VERTEX
]] .. PROJECT .. [[
uniform vec3 uOffset;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 c = uView * vec4(vertex_position.xyz + uOffset, 1.0);
  vHaze = hazeAt(c.z);
  return project(transform_projection, c);
}
#endif
#ifdef PIXEL
uniform float uStrength;
uniform vec3 uColour;
uniform vec3 uHaze;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(mix(uColour, uHaze, vHaze), Texel(tex, tc).a * color.a * uStrength);
}
#endif
]]

-- voxel_weather.v.pica: every particle moved by one offset a draw and wrapped back into the box,
-- thinning towards the box's sides, right in front of the lens and into the haze
local PARTICLES = [[
varying float vHaze;
varying float vAlpha;
#ifdef VERTEX
]] .. PROJECT .. [[
uniform vec4 uBoxOffset;   // xyz: the offset, wrapped; w: the fade along the view
uniform vec4 uBoxSize;     // xyz: the box; w: the fade across
uniform vec4 uBoxBase;     // xyz: its corner; w: the fade up and down
uniform vec4 uAcross;      // xyz: the corner's first vector; w: the lens's reach
uniform vec4 uAlong;       // xyz: the second; w: 1 / the lens's ramp
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 p = fract(vertex_position.xyz + uBoxOffset.xyz);
  vec3 side = 0.5 - abs(p - 0.5);
  float fade = min(min(uBoxSize.w * side.x, uBoxOffset.w * side.z), uBoxBase.w * side.y);
  fade = min(1.0, fade);
  vec3 w = uBoxBase.xyz + p * uBoxSize.xyz + uAcross.xyz * VertexTexCoord.x + uAlong.xyz * VertexTexCoord.y;
  vec4 c = uView * vec4(w, 1.0);
  float lens = clamp((c.z - uAcross.w) * uAlong.w, 0.0, 1.0);
  vHaze = hazeAt(c.z);
  vAlpha = vertex_position.w * fade * lens * (1.0 - vHaze);
  return project(transform_projection, c);
}
#endif
#ifdef PIXEL
uniform float uStrength;
uniform vec3 uColour;
uniform vec3 uHaze;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(mix(uColour, uHaze, vHaze), vAlpha * uStrength);
}
#endif
]]

local shaders = {}
local function shader(G, key, src)
  if shaders[key] == nil then
    local ok, sh = pcall(G.newShader, src)
    shaders[key] = ok and sh or false
    if not ok then Weather.shaderError = tostring(sh) end
  end
  return shaders[key] or nil
end

local FORMAT_BANK = { { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "float", 4 } }
local FORMAT_PARTICLE = { { "VertexPosition", "float", 4 }, { "VertexTexCoord", "float", 2 } }

local made = {}
local function fogImage(G)
  if made.fog == nil then
    made.fog = false
    if Weather.noise and love and love.image then
      local D = Weather.FOG_DIM
      local data = love.image.newImageData(D, D)
      Weather.makeFog(Weather.noise, function(x, y, v) data:setPixel(x, y, 1, 1, 1, v / 255) end)
      local im = G.newImage(data)
      im:setFilter("linear", "linear")
      im:setWrap("repeat", "repeat")
      made.fog = im
    end
  end
  return made.fog or nil
end
local function sheetMesh(G, bank)
  local key = "sheet" .. bank
  if made[key] == nil then
    local ok, mesh = pcall(G.newMesh, FORMAT_BANK, Weather.sheet(Weather.FOG_BANKS[bank].period), "triangles", "static")
    made[key] = ok and mesh or false
  end
  return made[key] or nil
end
local function particleMesh(G, flakes)
  local key = flakes and "flakes" or "streaks"
  if made[key] == nil and Weather.random then
    local ok, mesh = pcall(G.newMesh, FORMAT_PARTICLE, Weather.particles(Weather.random, flakes), "triangles", "static")
    made[key] = ok and mesh or false
  end
  return made[key] or nil
end

local function common(sh, o)
  sh:send("uView", "row", o.view)
  sh:send("uProj", o.proj)
  sh:send("uDepth", o.depth)
  sh:send("uFog", o.fog)
  sh:send("uHaze", o.haze)
end

--- DrawBanks: the two sheets of `banks` (FOG_BANKS or SAND_BANKS) in `colour`, at `density`
--- (0..1). Each is centred on the camera's target, moved in whole repeats of its pattern plus
--- the drift, so the mist stays put on the ground and only the wind moves it.
--- o = { pose (the meshes' frame), view, proj, depth, fog, haze, seconds }.
function Weather.banks(G, o, banks, colour, density)
  local sh = shader(G, "banks", BANKS)
  local tex = fogImage(G)
  if not (sh and tex) or density <= 0 then return end
  G.setShader(sh)
  common(sh, o)
  sh:send("uColour", colour)
  G.setDepthMode("lequal", false)
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  local p, seconds = o.pose, o.seconds or 0
  for i, bank in ipairs(banks) do
    local mesh = sheetMesh(G, i)
    if mesh then
      local period = bank.period
      local dx = math.fmod(seconds * bank.driftX, period)
      local dz = math.fmod(seconds * bank.driftZ, period)
      sh:send("uOffset", { floor(p.tx / period) * period + dx, (p.ty or 0) + bank.height,
                           floor(p.tz / period) * period + dz })
      sh:send("uStrength", bank.strength * density)
      mesh:setTexture(tex)
      G.draw(mesh)
    end
  end
end

--- DrawWeather: `class` ("rain", "sand" or "ash") at `amount` (0..1: how many of each group are
--- drawn follows the game's weather as it comes and goes), `flash` a lightning bolt (0..1, the
--- rain lit up with it). o = { pose, view, proj, depth, fog, haze, seconds, eye { x, y, z },
--- forward, right, up (the view's vectors) }.
function Weather.draw(G, o, class, amount, flash)
  local kind = Weather.KINDS[class]
  if not kind or amount <= 0 then return end
  local sh = shader(G, "particles", PARTICLES)
  local flakes = class == "ash"
  local mesh = particleMesh(G, flakes)
  if not (sh and mesh) then return end
  flash = class == "rain" and flash or 0
  local count = flakes and Weather.FLAKES or Weather.STREAKS
  local per = flakes and 12 or 6
  local group = floor(count / Weather.GROUPS)
  local seconds = (o.seconds or 0) % 86400
  local p = o.pose
  local box = kind.box
  local corner = { p.tx - box[1] * 0.5, (p.ty or 0) + kind.low, o.eye[3] - Weather.SOUTH - box[3] }
  local alpha = kind.alpha * (1 + 0.5 * flash)
  G.setShader(sh)
  common(sh, o)
  sh:send("uColour", flash > 0 and { 1, 1, 1 } or kind.colour)
  sh:send("uBoxSize", { box[1], box[2], box[3], Weather.EDGE })
  sh:send("uBoxBase", { corner[1], corner[2], corner[3], Weather.TOP })
  G.setDepthMode("lequal", false)
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  for g, w in ipairs(kind.groups) do
    local shown = math.min(group, floor(group * amount + 0.5))
    local strength = alpha * w.alpha
    if shown > 0 and strength > 0 then
      local across, along = Weather.vectors(w, o.forward, o.right, o.up)
      sh:send("uAcross", { across[1], across[2], across[3], Weather.LENS })
      sh:send("uAlong", { along[1], along[2], along[3], 1 / Weather.LENS_RAMP })
      sh:send("uBoxOffset", { Weather.offset(seconds, w.velocity[1], corner[1], box[1]),
                              Weather.offset(seconds, w.velocity[2], corner[2], box[2]),
                              Weather.offset(seconds, w.velocity[3], corner[3], box[3]), Weather.EDGE_ALONG })
      sh:send("uStrength", math.min(strength, 1))
      mesh:setDrawRange((g - 1) * group * per + 1, shown * per)
      G.draw(mesh)
    end
  end
  mesh:setDrawRange()
end

return Weather
