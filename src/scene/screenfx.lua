-- The battle scene as a shot (Battle Scene: Overworld): the diorama's tilt-shift blur, and the
-- entrance's effects while the camera flies in from the field - a zoom blur and speed lines as
-- fast as it travels, a dark indigo vignette as high as it climbs, a white flash where it lands,
-- and cinema bars framing it.
--
-- The blur, zoom blur, lines, vignette and flash are the world's, under the battle's own
-- picture: drawn into the world's canvas after it. The bars are over everything, the battlers
-- and the text box too.
--
-- Ported from Emerald 3DS's src/3ds_video.c (VoxelDiorama, DioramaTap, BattleIntroZoomTap,
-- BattleIntroBlur, BattleIntroAtmosphere, BattleIntroFlash, BattleIntroBars) and
-- src/voxel/ctr_voxel.c (BattleCamera's intro values), by Zallax and contributors, CC BY-NC-SA
-- 4.0, https://github.com/ZallaxDev/emerald-3ds (see LICENSE). Every number is theirs, measured
-- on their 400 x 240 screen, which is the world's canvas here (its height their 240 rows). Changes:
-- in LOVE; the taps sample a copy of the world at their screen's size (each tap is a 2x2 average
-- of their pixels, half a pixel off either way); the zoom blur is about the camera's target where
-- it lands on the canvas; the lines and the vignette stop on the text box's line, or run to the
-- canvas's foot when the world shows beside the text box (as theirs does round the HD box).

local ScreenFx = {}

local floor, max, min, exp, sin, pi = math.floor, math.max, math.min, math.exp, math.sin, math.pi

ScreenFx.GAME_H = 240                    -- their screen's rows (CTR_GAME_HEIGHT)
ScreenFx.DIORAMA_TOP = 100               -- rows blurred at the top
ScreenFx.DIORAMA_BOTTOM = 56             -- ... and at the bottom
-- each band's two taps: { offset (their pixels), alpha at the edge }
ScreenFx.DIORAMA_TAPS = { top = { { 0.5, 0.67 }, { -0.5, 0.50 } }, bottom = { { 0.5, 0.60 }, { -0.5, 0.45 } } }

ScreenFx.BARS_IN = 18                    -- frames the cinema bars take to close in
ScreenFx.BAR = 22                        -- each cinema bar, closed
ScreenFx.BAR_EDGE = 10                   -- its soft edge
ScreenFx.STREAKS = 12
ScreenFx.STREAK_COLOUR = { 225 / 255, 236 / 255, 255 / 255 }
ScreenFx.VIGNETTE_COLOUR = { 8 / 255, 6 / 255, 34 / 255 }
ScreenFx.VIGNETTE_BAND, ScreenFx.VIGNETTE_SIDE = 64, 96
ScreenFx.FLASH_COLOUR = { 255 / 255, 250 / 255, 235 / 255 }

local function clamp01(t) return t < 0 and 0 or t > 1 and 1 or t end
local function smooth(t) t = clamp01(t); return t * t * (3 - 2 * t) end

--- BattleCamera's intro values at glide progress u (0..1), `frames` since the battle began, the
--- share `travel` of the glide the flight: { flight (the crane's arc), speed (smootherstep's
--- slope over its peak), impact (the landing), bars, time }.
function ScreenFx.intro(u, frames, travel)
  local p = clamp01(u / travel)
  local q = clamp01((u - travel) / (1 - travel))
  local inside = p > 0 and p < 1
  return {
    flight = inside and sin(p * pi) or 0,
    speed = inside and 16 * p * p * (1 - p) * (1 - p) or 0,
    impact = (q > 0 and q < 1) and exp(-5 * q) * (1 - q) or 0,
    bars = smooth(frames / ScreenFx.BARS_IN) * (1 - smooth((q - 0.35) / 0.65)),
    time = frames,
  }
end

-- a canvas of ours, kept between frames
local canvases = {}
local function canvasOf(G, key, w, h)
  local c = canvases[key]
  if not c or c:getWidth() ~= w or c:getHeight() ~= h then
    if c and c.release then pcall(c.release, c) end
    c = G.newCanvas(w, h, { dpiscale = 1 })
    c:setFilter("linear", "linear")
    canvases[key] = c
  end
  return c
end

--- The world's picture in `target` (w x h) at their screen's size: its height their 240 rows
--- (halved, a 2x2 average each step, while twice that or more, then scaled the rest of the way).
--- Returns the copy, or nil.
function ScreenFx.copy(G, target, w, h)
  local th = ScreenFx.GAME_H
  local tw = max(1, floor(w * th / h + 0.5))
  G.setDepthMode("always", false)
  G.setShader()
  G.setBlendMode("replace", "premultiplied")
  G.setColor(1, 1, 1, 1)
  local cur, cw, ch, k = target, w, h, 0
  while ch >= 2 * th do
    local nw, nh = max(1, floor(cw / 2)), max(1, floor(ch / 2))
    k = k + 1
    local c = canvasOf(G, "half" .. k, nw, nh)
    G.setCanvas(c)
    G.draw(cur, 0, 0, 0, nw / cw, nh / ch)
    cur, cw, ch = c, nw, nh
  end
  local out = canvasOf(G, "copy", tw, th)
  G.setCanvas(out)
  G.draw(cur, 0, 0, 0, tw / cw, th / ch)
  return out
end

-- a band of the copy drawn over the canvas half a pixel off, its alpha from `edge` at one end
-- of the band to none at the other
local tapMesh
local function tap(G, copy, w, h, y0, y1, d, aTop, aBottom)
  local cw, ch = copy:getWidth(), copy:getHeight()
  local du, dv = d / cw, d / ch
  local v0, v1 = y0 / h + dv, y1 / h + dv
  local verts = {
    { 0, y0, du, v0, 1, 1, 1, aTop }, { w, y0, 1 + du, v0, 1, 1, 1, aTop },
    { w, y1, 1 + du, v1, 1, 1, 1, aBottom }, { 0, y1, du, v1, 1, 1, 1, aBottom },
  }
  if not tapMesh then
    tapMesh = G.newMesh(verts, "fan", "stream")
  else
    tapMesh:setVertices(verts)
  end
  tapMesh:setTexture(copy)
  G.draw(tapMesh)
end

--- VoxelDiorama: the tilt-shift of a miniature. The camera looks north, so the top of the picture
--- is the distance and the bottom the nearest ground; both are blurred, most at the edge and not at
--- all by the focus band round the battle. Over `target`, from `copy` (ScreenFx.copy), at
--- `strength` (0..1).
function ScreenFx.diorama(G, target, copy, w, h, strength)
  if not copy or strength <= 0.005 then return end
  local k = h / ScreenFx.GAME_H
  G.setCanvas(target)
  G.setDepthMode("always", false)
  G.setShader()
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  local top, bottom = ScreenFx.DIORAMA_TOP * k, h - ScreenFx.DIORAMA_BOTTOM * k
  for _, t in ipairs(ScreenFx.DIORAMA_TAPS.top) do tap(G, copy, w, h, 0, top, t[1], t[2] * strength, 0) end
  for _, t in ipairs(ScreenFx.DIORAMA_TAPS.bottom) do tap(G, copy, w, h, bottom, h, t[1], 0, t[2] * strength) end
end

--- BattleIntroBlur: the zoom blur, two see-through copies of the world magnified about the
--- camera's target (cx, cy on the canvas), as strong as the flight is fast.
function ScreenFx.zoomBlur(G, target, copy, w, h, cx, cy, speed)
  if not copy or speed < 0.04 then return end
  G.setCanvas(target)
  G.setDepthMode("always", false)
  G.setShader()
  G.setBlendMode("alpha", "alphamultiply")
  local sx, sy = w / copy:getWidth(), h / copy:getHeight()
  for _, t in ipairs({ { 1 + 0.035 * speed, 0.50 * speed }, { 1 + 0.080 * speed, 0.32 * speed } }) do
    local scale = t[1]
    G.setColor(1, 1, 1, t[2])
    G.draw(copy, cx - cx * scale, cy - cy * scale, 0, sx * scale, sy * scale)
  end
  G.setColor(1, 1, 1, 1)
end

local bit = require("bit")
local function u32(n) return n % 4294967296 end
local function mul32(a, b)
  local alo, ahi = a % 65536, floor(a / 65536) % 65536
  return (alo * b + ((ahi * b) % 65536) * 65536) % 4294967296
end
local function shr(h, s) return floor(h / 2 ^ s) end

-- a rectangle with a colour at each corner: top left, top right, bottom left, bottom right
local rectMesh
local function rect(G, x, y, w, h, tl, tr, bl, br)
  local verts = {
    { x, y, 0, 0, tl[1], tl[2], tl[3], tl[4] }, { x + w, y, 0, 0, tr[1], tr[2], tr[3], tr[4] },
    { x + w, y + h, 0, 0, br[1], br[2], br[3], br[4] }, { x, y + h, 0, 0, bl[1], bl[2], bl[3], bl[4] },
  }
  if not rectMesh then
    rectMesh = G.newMesh(verts, "fan", "stream")
  else
    rectMesh:setVertices(verts)
  end
  G.draw(rectMesh)
end

--- The speed lines, their place each frame: { x, y, length, thickness, alpha } in their pixels,
--- for a screen `width` wide whose world stops at `bottom`.
function ScreenFx.streaks(intro, width, bottom)
  local out = {}
  if intro.speed <= 0.04 then return out end
  for i = 0, ScreenFx.STREAKS - 1 do
    local h = u32(mul32(i + 1, 2654435761))
    local y = 6 + (shr(h, 8) % max(1, floor(bottom - 12)))
    local length = 70 + shr(h, 16) % 110
    local pace = 26 + shr(h, 20) % 18
    local x = width - math.fmod(intro.time * pace + h % 400, width + length)
    local alpha = intro.speed * (0.35 + 0.35 * (shr(h, 4) % 4) / 3)
    -- none across the middle band, where the battlers stand
    if math.abs(y - bottom * 0.55) < 24 then y = y < bottom * 0.55 and y - 24 or y + 24 end
    out[#out + 1] = { x, y, length, (floor(h / 16) % 2 == 1) and 2 or 1, alpha }
  end
  return out
end

--- BattleIntroAtmosphere: the speed lines racing right to left, and the vignette, over the world
--- in `target` (w x h); `floorY` the text box's line on the canvas, `low` how far down the
--- vignette reaches.
function ScreenFx.atmosphere(G, target, w, h, intro, floorY, low)
  local k = h / ScreenFx.GAME_H
  local width, bottom = w / k, floorY / k
  local shade = max(0.60 * intro.flight, 0.30 * intro.bars)
  if intro.speed <= 0.04 and shade <= 0.01 then return end
  G.setCanvas(target)
  G.setDepthMode("always", false)
  G.setShader()
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  local c = ScreenFx.STREAK_COLOUR
  for _, s in ipairs(ScreenFx.streaks(intro, width, bottom)) do
    local head, tail = { c[1], c[2], c[3], floor(s[5] * 255) / 255 }, { c[1], c[2], c[3], 0 }
    rect(G, s[1] * k, s[2] * k, s[3] * k, s[4] * k, head, tail, head, tail)
  end
  if shade > 0.01 then
    local v = ScreenFx.VIGNETTE_COLOUR
    local dark = { v[1], v[2], v[3], floor(min(shade, 1) * 230) / 255 }
    local none = { v[1], v[2], v[3], 0 }
    local band, side = ScreenFx.VIGNETTE_BAND * k, ScreenFx.VIGNETTE_SIDE * k
    rect(G, 0, 0, w, band, dark, dark, none, none)
    rect(G, 0, low - band, w, band, none, none, dark, dark)
    rect(G, 0, 0, side, low, dark, none, dark, none)
    rect(G, w - side, 0, side, low, none, dark, none, dark)
  end
end

--- BattleIntroFlash: the landing's flash, over everything of the world.
function ScreenFx.flash(G, target, w, h, impact)
  if impact <= 0.01 then return end
  local c = ScreenFx.FLASH_COLOUR
  G.setCanvas(target)
  G.setDepthMode("always", false)
  G.setShader()
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(c[1], c[2], c[3], floor(min(impact, 1) * 170) / 255)
  G.rectangle("fill", 0, 0, w, h)
  G.setColor(1, 1, 1, 1)
end

--- BattleIntroBars: the cinema bars, over everything on the screen in the rectangle x, y, w, h
--- (the view the battle fills), `bars` closed (0..1). Draws with G as it is set up.
function ScreenFx.bars(G, x, y, w, h, bars)
  if bars <= 0.01 then return end
  local k = h / ScreenFx.GAME_H
  local bar, edge = ScreenFx.BAR * bars * k, ScreenFx.BAR_EDGE * bars * k
  local black, none = { 0, 0, 0, 1 }, { 0, 0, 0, 0 }
  G.setShader()
  G.setBlendMode("alpha", "alphamultiply")
  G.setColor(1, 1, 1, 1)
  rect(G, x, y, w, bar, black, black, black, black)
  rect(G, x, y + bar, w, edge, black, black, none, none)
  rect(G, x, y + h - bar, w, bar, black, black, black, black)
  rect(G, x, y + h - bar - edge, w, edge, none, none, black, black)
end

return ScreenFx
