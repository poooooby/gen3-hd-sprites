-- The Battle Camera (Battle Scene: Overworld): the 3D battle's view turned by the player.
--
-- Each battler stands on a fixed point of the world's ground (its anchor): where its feet stand on
-- the battle canvas at rest (Scene.FEET; a double battle's spots, spread) cast onto the stage's
-- ground through the settled pose (s.to). The player turns the whole rig - target and eye -
-- about the upright through the middle of the two sides' anchors (yaw, YAW_MAX either way) and
-- tilts it (pitch, PITCH_MIN..PITCH_MAX below the horizon) with the right stick or a right-mouse
-- drag, and zooms it in and out with the mouse wheel or the left stick's up and down (main.lua
-- takes the left stick's up and down off the game's menus meanwhile: the D-pad works them); it stays where it is left (R3, or a right
-- double-click, brings it back; each battle starts at rest). Each frame every anchor is projected through the turned pose: its canvas point and
-- how much nearer it stands than at rest (r). The battlers are drawn about that point at r times
-- their size (src/hd.lua's composite), their shadows under it, the move animations aimed there
-- (src/gen3.lua shiftCoords). At rest every one of those is exactly what it was without it.
--
-- Kept in view: the camera pulls back (dolly, up to DOLLY_MAX times its distance) until both
-- sides' boxes lie inside the view; a turn that would have one battler cover too much of
-- another (OVERLAP), or a tree, a wall or a model stand in front of most of one (src/scene/
-- stage.lua's ray checks), goes no further; what stands in front of less of one is drawn over it
-- (src/hd.lua, by the world's depth: f.d, each anchor's view depth this frame). Zoomed in, it comes no nearer than keeps KEEP of each battler's
-- box in view.

local Orbit = {}

local rad, sin, cos, exp, abs = math.rad, math.sin, math.cos, math.exp, math.abs
local min, max = math.min, math.max

Orbit.YAW_MAX = rad(45)                    -- how far it turns either way from the battle's view
Orbit.PITCH_MIN, Orbit.PITCH_MAX = rad(10), rad(75)   -- how low and how high it looks down from
Orbit.RATE = rad(90)                       -- radians a second at the stick's full tilt
Orbit.DEADZONE = 0.2                       -- the stick's travel that does nothing
Orbit.MOUSE = rad(0.3)                     -- radians a window pixel of a right-mouse drag
Orbit.EASE = 12                            -- how fast the view follows (1/s)
Orbit.DOLLY_MAX = 2.2                      -- the farthest it pulls back, times the battle's distance
Orbit.DOLLY_EASE = 5                       -- how fast it pulls back and in (1/s)
Orbit.OVERLAP = 0.35                       -- the share of a battler's box a nearer one may cover
Orbit.VIEW = { 0, 0, 240, 112 }            -- the canvas over the text box both sides stay inside
Orbit.DOUBLE_CLICK = 0.35                  -- seconds between a right double-click's presses
Orbit.ZOOM_MIN, Orbit.ZOOM_MAX = 0.6, 2    -- the wheel's reach: times the distance that keeps them in view
Orbit.ZOOM_STEP = 0.9                      -- each notch of the wheel in (out: its inverse)
Orbit.KEEP = 0.6                           -- zoomed in, the share of each battler's box kept in view
Orbit.FAR = 3.2                            -- the farthest the camera ever stands, times the battle's distance
Orbit.ZOOM_RATE = 0.9                      -- the left stick's zoom at full tilt (log of the zoom a second)
Orbit.SNAP = 1e-4                          -- radians (and dolly) close enough to rest to be at it

-- set by the scene (src/scene/init.lua): the camera, the stage's ray checks, the canvas's feet
-- points and sprite boxes
Orbit.Camera, Orbit.Stage, Orbit.FEET, Orbit.SPRITES = nil, nil, nil, nil
-- the Battle Camera option (main.lua)
Orbit.enabled = false

-- (the right stick, read by Orbit.readPad: overridden by the tests; the pads kept, listed again
-- only when their count changes - getJoysticks makes a table each call)
local padList, padCount = {}, -1
local function readPad()
  local J = love and love.joystick
  if not (J and J.getJoysticks and J.getJoystickCount) then return 0, 0, false end
  local n = J.getJoystickCount()
  if n ~= padCount then
    local ok, pads = pcall(J.getJoysticks)
    padList = ok and type(pads) == "table" and pads or {}
    padCount = n
  end
  local x, y, down, ly = 0, 0, false, 0
  for i = 1, #padList do
    local j = padList[i]
    if j:isConnected() and j:isGamepad() then
      local ax, ay = j:getGamepadAxis("rightx") or 0, j:getGamepadAxis("righty") or 0
      if ax * ax + ay * ay > x * x + y * y then x, y = ax, ay end
      if j:isGamepadDown("rightstick") then down = true end
      local lv = j:getGamepadAxis("lefty") or 0
      if abs(lv) > abs(ly) then ly = lv end
    end
  end
  return x, y, down, ly
end
Orbit.readPad = readPad

-- the mouse: a right-button drag's travel since the last frame, a double-click's recentre, and
-- the wheel's notches
local mouse = { dx = 0, dy = 0, drag = false, last = -1, recentre = false, wheel = 0 }
Orbit._mouse = mouse
-- the stick's R3 as it was last frame (its press recentres once)
local r3Was = false

local function dead(v)
  local a = abs(v)
  if a <= Orbit.DEADZONE then return 0 end
  return (v > 0 and 1 or -1) * (a - Orbit.DEADZONE) / (1 - Orbit.DEADZONE)
end

--- The scene's look (made on first ask): the angles wanted and as shown, the dolly, the
--- anchors (feet[key]: side, u0, v0 its rest canvas foot; x, z its ground; u, v, r as projected
--- this frame) and the turned pose. Each scene is one battle's: a new battle starts at rest.
function Orbit.look(s)
  local L = s.look
  if L then return L end
  local p0 = s.to and s.to.pitch or (Orbit.Camera and Orbit.Camera.STAGE_PITCH) or rad(30)
  L = {
    yaw = 0, pitch = p0, eyaw = 0, epitch = p0, m = 1, em = 1, p0 = p0, zoom = 1, ezoom = 1,
    feet = {}, frame = 0, t = nil, on = false, flat = 1, double = false,
    pose = {}, test = {}, mid = { 0, 0 }, uv = { player = { 0, 0 }, enemy = { 0, 0 } },
  }
  s.look = L
  return L
end

--- A battler's rest foot on the canvas this frame (key: "enemy" / "player", or a double
--- battle's id 0..3; side its side): its anchor cast onto the stage's ground. `virtual`: a
--- double battle's sides' singles feet, which only set the middle (no battler stands there).
function Orbit.foot(s, key, side, u, v, virtual)
  local L = Orbit.look(s)
  local f = L.feet[key]
  if not f then
    f = { side = side, r = 1 }
    L.feet[key] = f
  end
  local C, to = Orbit.Camera, s.to
  if f.u0 ~= u or f.v0 ~= v or f.x == nil then
    local ty = to.ty or 0
    local x, z = C.ground(to, u, v, ty)
    f.x, f.z = x, z
    f.u0, f.v0 = u, v
    f.d0 = nil
    if x then
      local _, _, d = C.view(to, x, ty, z)
      f.d0 = d
    end
  end
  f.side, f.virtual, f.frame = side, virtual == true, L.frame + 1
  if f.u == nil then f.u, f.v = u, v end
  return f
end

-- the rig turned by yaw and tilted to pitch, its distance times m, into out
local function rig(s, L, yaw, pitch, m, out)
  local to = s.to
  local mx, mz = L.mid[1], L.mid[2]
  -- (the target turned about the middle: T + (R - I)(T - M), exactly T at yaw 0)
  local c, sn = cos(yaw), sin(yaw)
  local dx, dz = to.tx - mx, to.tz - mz
  local tx = to.tx + (dx * c + dz * sn - dx)
  local tz = to.tz + (-dx * sn + dz * c - dz)
  return Orbit.Camera.pose(tx, tz, pitch, to.dist * m, to.ty, yaw, out)
end

-- (whether anchor f is a battler's, given this frame)
local function real(L, f)
  return f.frame == L.frame and f.x ~= nil and not f.virtual
end

-- a battler's box at rest (canvas): its body as last drawn (src/hd.lua's composite keeps it on
-- its anchor, f.body), else its side's sprite box moved to its foot
local function restBox(f)
  local b = f.body
  if b and f.bodyFrame and f.frame - f.bodyFrame <= 3 then return b[1], b[2], b[3], b[4] end
  local F, B = Orbit.FEET[f.side], Orbit.SPRITES[f.side]
  local du, dv = f.u0 - F[1], f.v0 - F[2]
  return B[1] + du, B[2] + dv, B[3] + du, B[4] + dv
end

-- a battler's box projected (its tu, tv, tr)
local function testBox(f)
  local x0, y0, x1, y1 = restBox(f)
  local r = f.tr
  return f.tu + (x0 - f.u0) * r, f.tv + (y0 - f.v0) * r, f.tu + (x1 - f.u0) * r, f.tv + (y1 - f.v0) * r
end

-- each anchor given this frame projected through pose: into its own fields (u, v, r) when keep,
-- else into its tu, tv, tr; false when one falls behind the camera
local function project(L, pose, ty, keep)
  local C = Orbit.Camera
  for _, f in pairs(L.feet) do
    if f.frame == L.frame and f.x then
      local u, v, d = C.project(pose, f.x, ty, f.z)
      if not u then return false end
      local r = (f.d0 and d > 0) and f.d0 / d or 1
      if keep then f.u, f.v, f.r, f.d = u, v, r, d else f.tu, f.tv, f.tr = u, v, r end
    end
  end
  return true
end

-- the share of box a that box b covers
local function covered(a0, b0, a1, b1, c0, d0, c1, d1)
  local w = min(a1, c1) - max(a0, c0)
  local h = min(b1, d1) - max(b0, d0)
  if w <= 0 or h <= 0 then return 0 end
  return (w * h) / max(1e-6, (a1 - a0) * (b1 - b0))
end

-- whether every battler's box, projected (tu, tv, tr), lies inside the view (the canvas over the
-- text box), or no further out of it than the battler already stood at rest; with `share`, only
-- that much of each box
local function inside(L, share)
  local V = Orbit.VIEW
  for _, f in pairs(L.feet) do
    if real(L, f) then
      local x0, y0, x1, y1 = restBox(f)
      local a0, b0, a1, b1 = min(V[1], x0) - 0.5, min(V[2], y0) - 0.5, max(V[3], x1) + 0.5, max(V[4], y1) + 0.5
      local u0, v0, u1, v1 = testBox(f)
      if share then
        if covered(u0, v0, u1, v1, a0, b0, a1, b1) < share then return false end
      elseif u0 < a0 or v0 < b0 or u1 > a1 or v1 > b1 then
        return false
      end
    end
  end
  return true
end

-- (Orbit.fit's pose, kept)
local function fits(s, L, yaw, pitch, m, share)
  rig(s, L, yaw, pitch, m, L.test)
  return project(L, L.test, s.to.ty or 0, false) and inside(L, share)
end

--- The dolly (times the battle's distance, 1..DOLLY_MAX) that keeps every battler's box in view
--- with the rig at yaw and pitch.
function Orbit.fit(s, yaw, pitch)
  local L = Orbit.look(s)
  if fits(s, L, yaw, pitch, 1) then return 1 end
  if not fits(s, L, yaw, pitch, Orbit.DOLLY_MAX) then return Orbit.DOLLY_MAX end
  local lo, hi = 1, Orbit.DOLLY_MAX
  for _ = 1, 12 do
    local m = (lo + hi) / 2
    if fits(s, L, yaw, pitch, m) then hi = m else lo = m end
  end
  return hi
end

--- The camera's distance (times the battle's) with the rig at yaw and pitch zoomed by `zoom`
--- (the wheel's: 1 none, less nearer): the distance that keeps every battler in view (Orbit.fit)
--- times it, no farther than FAR, and zoomed in no nearer than keeps KEEP of each one's box in
--- view.
function Orbit.dolly(s, yaw, pitch, zoom)
  local m = Orbit.fit(s, yaw, pitch)
  zoom = zoom or 1
  if zoom >= 1 then return min(m * zoom, max(m, Orbit.FAR)) end
  local L = Orbit.look(s)
  local want = m * zoom
  if fits(s, L, yaw, pitch, want, Orbit.KEEP) then return want end
  local lo, hi = want, m
  for _ = 1, 12 do
    local mid = (lo + hi) / 2
    if fits(s, L, yaw, pitch, mid, Orbit.KEEP) then hi = mid else lo = mid end
  end
  return hi
end

--- How badly the rig at yaw and pitch, zoomed by `zoom`, shows the battlers (0: well): how far a
--- nearer battler of the other side covers more of a farther one's box than OVERLAP, plus one
--- for each battler a tree, a wall or a model hides most of.
function Orbit.badness(s, yaw, pitch, zoom)
  local L = Orbit.look(s)
  local m = Orbit.dolly(s, yaw, pitch, zoom)
  local pose = L.test
  rig(s, L, yaw, pitch, m, pose)
  local ty = s.to.ty or 0
  if not project(L, pose, ty, false) then return math.huge end
  local bad = 0
  for _, a in pairs(L.feet) do
    if real(L, a) then
      local au0, av0, au1, av1 = testBox(a)
      for _, b in pairs(L.feet) do
        if b ~= a and real(L, b) and b.side ~= a.side and b.tr > a.tr then
          local share = covered(au0, av0, au1, av1, testBox(b))
          if share > Orbit.OVERLAP then bad = bad + (share - Orbit.OVERLAP) end
        end
      end
    end
  end
  -- (and nothing standing in front of most of one: the stage's own ray checks)
  local St, grid = Orbit.Stage, s.grid
  if St and St.hidden and grid then
    local rect = L.rect
    if not rect then
      rect = { 0, 0, 0, 0 }
      L.rect = rect
    end
    for _, f in pairs(L.feet) do
      if real(L, f) then
        rect[1], rect[2], rect[3], rect[4] = testBox(f)
        local ok, hid = pcall(St.hidden, Orbit.Camera, grid, pose, rect, f.x, f.z - ty)
        if ok and hid then bad = bad + 1 end
      end
    end
  end
  return bad
end

--- Bring the view back to rest (the battle's own), unzoomed.
function Orbit.recentre(s)
  local L = Orbit.look(s)
  L.yaw, L.pitch, L.zoom = 0, L.p0, 1
end

-- (when a 3D battle last let the camera turn: the pointer is ours only while one is shown)
Orbit.lastLive = nil

--- A pointer event (the engine's input.pointer) at time now: a right-button drag turns the view,
--- a right double-click recentres, while a 3D battle is shown with the camera on. True when it is
--- ours (not handed on).
function Orbit.pointer(ev, now)
  if type(ev) ~= "table" or ev.source ~= "mouse" then return false end
  local live = Orbit.lastLive ~= nil and now ~= nil and now - Orbit.lastLive <= 0.25
  if ev.phase == "pressed" and ev.button == 2 then
    if not live then return false end
    mouse.drag = true
    if now and now - mouse.last <= Orbit.DOUBLE_CLICK then
      mouse.recentre, mouse.last = true, -1
    else
      mouse.last = now or -1
    end
    return true
  elseif ev.phase == "moved" and mouse.drag then
    if live then mouse.dx, mouse.dy = mouse.dx + (ev.dx or 0), mouse.dy + (ev.dy or 0) end
    return true
  elseif (ev.phase == "released" or ev.phase == "cancelled") and mouse.drag and (ev.button == 2 or ev.button == nil) then
    mouse.drag = false
    return true
  end
  return false
end

--- Whether a 3D battle is shown with the camera on at time now (the mouse and the left stick
--- are the camera's).
function Orbit.liveAt(now)
  return Orbit.lastLive ~= nil and now ~= nil and now - Orbit.lastLive <= 0.25
end

-- (the left stick's default up and down, taken off the game's menus while the camera has them)
local heldSticks = { tbl = nil }
local STICK_KEYS = { "leftstick_up", "leftstick_down", "lsup", "lsdown" }

--- While `live` (a 3D battle shown with the camera on), the left stick's up and down zoom the
--- view: its default up and down (the engine's input.effectiveStickBindings) are taken off the
--- game's menus - the D-pad works them - and given back once it is not. A stick the player bound
--- in CONTROLS is the player's own (padBindings): left alone. A press already made is released
--- by its source as ever. (main.lua, each update)
function Orbit.gateSticks(input, live)
  local t = type(input) == "table" and input.effectiveStickBindings
  if live and type(t) == "table" then
    if heldSticks.tbl ~= t then
      heldSticks.tbl = t
      for _, k in ipairs(STICK_KEYS) do heldSticks[k], t[k] = t[k], nil end
    end
  elseif heldSticks.tbl then
    if heldSticks.tbl == t then
      for _, k in ipairs(STICK_KEYS) do t[k] = heldSticks[k] end
    end
    heldSticks.tbl = nil
  end
end

--- The mouse wheel (the engine's input.wheel) at time now, dy its notches (up: in): zooms the
--- view while a 3D battle is shown with the camera on. True when it is ours (the window's own
--- zoom is left alone).
function Orbit.wheel(dy, now)
  local live = Orbit.lastLive ~= nil and now ~= nil and now - Orbit.lastLive <= 0.25
  if not (live and type(dy) == "number") then return false end
  mouse.wheel = mouse.wheel + dy
  return true
end

-- the input since the last frame: yaw and pitch to turn by, the wheel's notches, and whether to
-- recentre
local function input(dt)
  local x, y, down, ly = (Orbit.readPad or readPad)()
  local re = down and not r3Was
  r3Was = down
  local dyaw = dead(x or 0) * Orbit.RATE * dt + mouse.dx * Orbit.MOUSE
  -- (pushed up, the view looks up: the camera lowers)
  local dpitch = dead(y or 0) * Orbit.RATE * dt + mouse.dy * Orbit.MOUSE
  -- (the wheel's notches, up: in; and the left stick, up: in, as notches of the wheel)
  local notches = mouse.wheel - dead(ly or 0) * Orbit.ZOOM_RATE * dt / math.log(1 / Orbit.ZOOM_STEP)
  mouse.dx, mouse.dy, mouse.wheel = 0, 0, 0
  if mouse.recentre then re, mouse.recentre = true, false end
  return dyaw, dpitch, notches, re
end

local function clampYaw(y) return max(-Orbit.YAW_MAX, min(Orbit.YAW_MAX, y)) end
local function clampPitch(p) return max(Orbit.PITCH_MIN, min(Orbit.PITCH_MAX, p)) end

local function ease(cur, want, k)
  local v = cur + (want - cur) * k
  if abs(want - v) < Orbit.SNAP then return want end
  return v
end

--- This frame's look on scene s (once a frame, before the battle draws; its anchors given by
--- Orbit.foot first). `allowed`: the camera may turn (its option on, the battlers drawn by a
--- sprite mod, the entrance over). Returns the look; look.on when it is away from rest.
function Orbit.step(s, now, allowed)
  local L = Orbit.look(s)
  L.frame = L.frame + 1
  local dt = L.t and min(max(now - L.t, 0), 0.1) or 0
  L.t = now
  -- (the middle of the two sides: the singles' anchors, there in a double battle too)
  local fe, fp = L.feet.enemy, L.feet.player
  local mid = fe and fp and fe.x and fp.x and fe.frame == L.frame and fp.frame == L.frame
  if mid then L.mid[1], L.mid[2] = (fe.x + fp.x) / 2, (fe.z + fp.z) / 2 end
  local live = allowed and Orbit.enabled and Orbit.Camera ~= nil and mid and true or false
  if live then
    local dyaw, dpitch, notches, re = input(dt)
    if re then
      Orbit.recentre(s)
    else
      if dyaw ~= 0 or dpitch ~= 0 then
        local y1, p1 = clampYaw(L.yaw + dyaw), clampPitch(L.pitch + dpitch)
        local z = L.zoom
        local now0 = Orbit.badness(s, L.yaw, L.pitch, z)
        -- (the whole move, else the turn alone, else the tilt alone: whichever shows them no worse)
        if Orbit.badness(s, y1, p1, z) <= max(0, now0) then
          L.yaw, L.pitch = y1, p1
        elseif y1 ~= L.yaw and Orbit.badness(s, y1, L.pitch, z) <= max(0, now0) then
          L.yaw = y1
        elseif p1 ~= L.pitch and Orbit.badness(s, L.yaw, p1, z) <= max(0, now0) then
          L.pitch = p1
        end
      end
      if notches ~= 0 then
        local z1 = max(Orbit.ZOOM_MIN, min(Orbit.ZOOM_MAX, L.zoom * Orbit.ZOOM_STEP ^ notches))
        -- (zoomed in only as far as it takes: notches past where the battlers would leave the view
        -- are not saved up)
        if z1 < 1 then z1 = max(z1, Orbit.dolly(s, L.yaw, L.pitch, z1) / Orbit.fit(s, L.yaw, L.pitch)) end
        if Orbit.badness(s, L.yaw, L.pitch, z1) <= max(0, Orbit.badness(s, L.yaw, L.pitch, L.zoom)) then
          L.zoom = z1
        end
      end
    end
  else
    -- (off: back to rest at once)
    L.yaw, L.pitch, L.eyaw, L.epitch, L.em, L.m = 0, L.p0, 0, L.p0, 1, 1
    L.zoom, L.ezoom = 1, 1
    mouse.dx, mouse.dy, mouse.recentre, mouse.wheel = 0, 0, false, 0
  end
  local k = 1 - exp(-Orbit.EASE * dt)
  L.eyaw, L.epitch, L.ezoom = ease(L.eyaw, L.yaw, k), ease(L.epitch, L.pitch, k), ease(L.ezoom, L.zoom, k)
  local rest = L.eyaw == 0 and L.epitch == L.p0 and L.ezoom == 1
  L.m = rest and 1 or Orbit.dolly(s, L.eyaw, L.epitch, L.ezoom)
  L.em = ease(L.em, L.m, 1 - exp(-Orbit.DOLLY_EASE * dt))
  L.on = not (rest and L.em == 1)
  L.live = live
  if live then Orbit.lastLive = now end
  local ty = s.to.ty or 0
  if L.on then
    rig(s, L, L.eyaw, L.epitch, L.em, L.pose)
    project(L, L.pose, ty, true)
    L.flat = sin(L.epitch) / sin(L.p0)
  else
    -- (at rest: exactly as without it)
    Orbit.Camera.pose(s.to.tx, s.to.tz, s.to.pitch, s.to.dist, s.to.ty, s.to.yaw, L.pose)
    for _, f in pairs(L.feet) do f.u, f.v, f.r, f.d = f.u0, f.v0, 1, f.d0 end
    L.flat = 1
  end
  -- (the two sides' feet on the canvas this frame: the terrain's glow, src/scene/render.lua)
  if fe and fe.u then L.uv.enemy[1], L.uv.enemy[2] = fe.u, fe.v end
  if fp and fp.u then L.uv.player[1], L.uv.player[2] = fp.u, fp.v end
  return L
end

--- A canvas point (x, y) of a battler resting at foot f, where the turned view puts it.
function Orbit.place(f, x, y)
  return f.u + (x - f.u0) * f.r, f.v + (y - f.v0) * f.r
end

return Orbit
