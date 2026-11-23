-- The battle's own weather and terrain in the battle scene (WoobleView's own, not Emerald 3DS's).
-- A battle's weather can differ from the route's: Rain Dance, Drought, Sunny Day, Sandstorm,
-- Hail, and other mods' moves (Galar Rising's Max Moves). While a battle is up, its weather is
-- shown in the world over the field's: rain and the sandstorm as the field's own (their ids
-- through src/scene/light.lua and src/scene/weather.lua), the sun as a harsher, warmer light
-- than the route's (Light.battle) and hail as ice falling heavier and slower than rain
-- (Weather.KINDS.hail). WoobleDex's terrains (its exports.battle.terrainOf) glow on the ground
-- under and between the battlers in their colour, breathing slowly (src/scene/render.lua).
--
-- Each comes in and goes out over FADE seconds; a new weather waits for the old one to go. Kept
-- on the scene (s.battleWx), started afresh for each battle's state.

local BW = {}

BW.FADE = 1.2                -- seconds to come in or go
-- the engine's kinds (src/core/game3/battle/rules.lua Rules.weather.kind) -> the scene's
BW.KIND = { RAIN = "rain", SUN = "sun", SAND = "sand", HAIL = "hail" }
-- WoobleDex's terrains and their colours
BW.TERRAIN = {
  ELECTRIC = { 1.00, 0.88, 0.22 },
  GRASSY = { 0.36, 0.92, 0.38 },
  MISTY = { 1.00, 0.62, 0.86 },
  PSYCHIC = { 0.80, 0.42, 1.00 },
}
BW.TERRAIN_STRENGTH = 1.0    -- the glow at its full
BW.BREATH = 3.2              -- seconds a breath of the glow takes
BW.BREATH_DEPTH = 0.22       -- how far it dims and brightens with it
BW.TERRAIN_RADIUS = 1.9      -- tiles from the line between the battlers' feet to the glow's edge

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
