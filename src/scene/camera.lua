-- The battle scene's camera (Battle Scene: Overworld), in the battle canvas's own pixels.
--
-- The world is in tiles: x east, y up, z south; a cell (cx, cy) of the map covers x in
-- [cx, cx + 1], z in [cy, cy + 1], its ground at y = 0. The camera looks north (yaw 0), pitched
-- down by `pitch` (radians below the horizon), from `dist` tiles back along its view ray from
-- the target (tx, tz) on the ground. Its picture at rest is the 240x160 battle canvas: a
-- vertical field of view of 35 degrees over the canvas's 160 rows, the target on the canvas's
-- centre. So a point of the world lands on a canvas pixel exactly as the battle's sprites do,
-- and whatever mapping puts the canvas on the screen (Battle Fit's zoom, Fill Screen) puts the
-- world there with it.
--
-- The stage pose (pitch 30 degrees, 7 tiles back, 35 degree field of view) and the shape of the
-- entrance glide are adapted from Emerald 3DS by Zallax and contributors (CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds); see LICENSE. Its field-of-view zoom is left out
-- here: the battle's sprites are drawn for one fixed lens.

local Camera = {}

local rad = math.rad
local sin, cos, tan, exp, pi = math.sin, math.cos, math.tan, math.exp, math.pi

Camera.FOV = rad(35)
Camera.W, Camera.H = 240, 160
Camera.CX, Camera.CY = 120, 80
-- the focal length in canvas pixels
Camera.F = (Camera.H / 2) / tan(Camera.FOV / 2)
Camera.NEAR, Camera.FAR = 0.25, 120

-- the battle's pose: where the stage search aims it
Camera.STAGE_PITCH, Camera.STAGE_DIST = rad(30), 7
-- the field's pose: straight down over the player, as far up as shows the field's 10 rows of
-- tiles on the canvas's 160 (the glide starts from what the field showed)
Camera.FIELD_PITCH = rad(90)
Camera.FIELD_DIST = 5 / tan(Camera.FOV / 2)

--- A pose: { tx, tz, pitch, dist, ty } (ty: the target's height, 0 when not given; on lifted
--- ground its tz is as far south again, src/scene/relief.lua).
function Camera.pose(tx, tz, pitch, dist, ty)
  return { tx = tx, tz = tz, pitch = pitch or Camera.STAGE_PITCH, dist = dist or Camera.STAGE_DIST, ty = ty or 0 }
end

--- The eye, and the view's up and forward vectors (right is always east, (1, 0, 0)).
function Camera.basis(p)
  local s, c = sin(p.pitch), cos(p.pitch)
  local ex, ey, ez = p.tx, (p.ty or 0) + p.dist * s, p.tz + p.dist * c
  -- up (0, c, -s), forward (0, -s, -c)
  return ex, ey, ez, c, -s, -s, -c
end

--- The camera's coordinates of a world point: right, up, depth (along the view).
function Camera.view(p, x, y, z)
  local ex, ey, ez, uy, uz, fy, fz = Camera.basis(p)
  local dx, dy, dz = x - ex, y - ey, z - ez
  return dx, dy * uy + dz * uz, dy * fy + dz * fz
end

--- A world point on the canvas: u, v (pixels) and its depth; nil when behind the camera.
function Camera.project(p, x, y, z)
  local xc, yc, zc = Camera.view(p, x, y, z)
  if zc <= Camera.NEAR then return nil end
  return Camera.CX + Camera.F * xc / zc, Camera.CY - Camera.F * yc / zc, zc
end

--- Where the ray through canvas pixel (u, v) meets the ground (y = h, default 0): x, z; nil when
--- it never does (at or above the horizon).
function Camera.ground(p, u, v, h)
  local ex, ey, ez, uy, uz, fy, fz = Camera.basis(p)
  local a, b = (u - Camera.CX) / Camera.F, -(v - Camera.CY) / Camera.F
  -- direction: right * a + up * b + forward
  local dx, dy, dz = a, uy * b + fy, uz * b + fz
  if dy >= -1e-6 then return nil end
  local t = ((h or 0) - ey) / dy
  return ex + dx * t, ez + dz * t
end

--- The view matrix as four rows (world point -> right, up, depth, 1), for a shader.
function Camera.viewRows(p)
  local ex, ey, ez, uy, uz, fy, fz = Camera.basis(p)
  return {
    { 1, 0, 0, -ex },
    { 0, uy, uz, -(ey * uy + ez * uz) },
    { 0, fy, fz, -(ey * fy + ez * fz) },
    { 0, 0, 0, 1 },
  }
end

--- The shader's projection for a screen rectangle: the canvas-space rectangle starting at
--- (u0, v0) drawn kx, ky screen pixels to a canvas pixel. Returns { kx * F, kx * (CX - u0),
--- ky * F, ky * (CY - v0) } (a screen pixel times depth is linear in the view coordinates, so
--- the GPU interpolates the ground perspective-correct), and the depth's a, b (clip z = a * depth
--- + b, depth NEAR..FAR to -1..1).
function Camera.screenProjection(u0, v0, kx, ky)
  local F, n, f = Camera.F, Camera.NEAR, Camera.FAR
  return { kx * F, kx * (Camera.CX - u0), ky * F, ky * (Camera.CY - v0) },
         { (f + n) / (f - n), -2 * f * n / (f - n) }
end

local function lerp(a, b, t) return a + (b - a) * t end
local function smoother(t) return t * t * t * (t * (t * 6 - 15) + 10) end

Camera.TRAVEL = 0.78        -- the share of the glide that travels; the rest lands
Camera.CRANE = rad(16)      -- the arc the pitch rises by on the way
Camera.PITCH_MAX = rad(89)

--- The entrance glide at progress t (0..1): from the field's pose to the stage's. It travels the
--- first 78% (smootherstep, the pitch rising on an arc), then lands: a push in and out and a
--- small settling quake.
function Camera.glide(from, to, t)
  t = math.max(0, math.min(1, t or 1))
  if t >= 1 then return Camera.pose(to.tx, to.tz, to.pitch, to.dist, to.ty) end
  if t < Camera.TRAVEL then
    local q = smoother(t / Camera.TRAVEL)
    local pitch = lerp(from.pitch, to.pitch, q) + Camera.CRANE * sin(pi * q)
    -- (the arc never tips past straight down, nor below where the glide started)
    return Camera.pose(lerp(from.tx, to.tx, q), lerp(from.tz, to.tz, q),
      math.min(math.max(Camera.PITCH_MAX, from.pitch), pitch), lerp(from.dist, to.dist, q),
      lerp(from.ty or 0, to.ty or 0, q))
  end
  local q = (t - Camera.TRAVEL) / (1 - Camera.TRAVEL)
  local dist = to.dist * (1 - 0.16 * exp(-6 * q) * sin(3 * pi * q))
  local quake = 0.07 * exp(-7 * q)
  return Camera.pose(to.tx + quake * sin(q * 37), to.tz + quake * cos(q * 29), to.pitch, dist, to.ty)
end

return Camera
