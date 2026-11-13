-- Where the battle stands (Battle Scene: Overworld): the camera's target on the ground, chosen
-- once per battle so both Pokemon stand on open ground of the kind the battle is fought on,
-- nothing tall stands in front of either, and as little of the screen as can be is outside the
-- map.
--
-- The battle's sprites never move: the camera is placed so the world meets them. Each side's feet
-- (a canvas point) are cast onto the ground through the stage pose, which gives where its feet
-- stand relative to the target; then targets within REACH tiles of the one that puts the
-- player's Pokemon on the player's own cell are scored and the best is kept.
--
-- The search and its weights are adapted from Emerald 3DS's battle stage search
-- (3ds_port/src/voxel/voxel_battle.c, by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE), its current version with the relief: a
-- foot on a slope (rock, stairs) and a foot at another height than the target's ground cost, and
-- the camera aims at the target's ground as high as it is (src/scene/relief.lua). Changes here:
-- one camera model for the search and the drawing, tall cells from the upright runs
-- (src/scene/cells.lua) and the buildings' models (src/scene/buildings.lua: how tall each stands
-- over its cells), and no time slicing. A cell's height (cell.liftT, tiles) and slope (cell.slope)
-- come from init.lua's relief placement.

local Stage = {}

Stage.REACH = 6
-- a best score below this: no stage fits (the battle keeps its wallpaper)
Stage.FLOOR = -40

local W = {
  void = -60, tall = -16, blocked = -6, waterWanted = 8, waterUnwanted = -12, waterMissing = -8,
  kind = 4, slope = -4, lift = -3,
  nVoid = -3, nTall = -1, nKind = 0.5, nWater = -0.8, nSlope = -0.4,
  occlude = -24, voidLow = -1.2, voidHigh = -0.5,
  distance = -0.5,
}
Stage.WEIGHTS = W

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min

-- something stands on the cell: an upright run's card, or a model over half a tile tall
local function tall(c) return c.up or (c.top or 0) > 0.5 end

local function footScore(c, want, groundT)
  if not c or c.kind == "void" then return W.void end
  local s = 0
  if tall(c) then s = s + W.tall end
  if want == "water" then
    s = s + (c.kind == "water" and W.waterWanted or W.waterMissing)
  else
    if c.kind == "water" then s = s + W.waterUnwanted
    elseif c.kind == "blocked" then s = s + W.blocked end
    if want and c.kind == want then s = s + W.kind end
  end
  if c.slope then s = s + W.slope end
  return s + W.lift * math.abs((c.liftT or 0) - groundT)
end

local function neighbourScore(grid, cx, cy, want)
  local s = 0
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local c = grid.at(cx + dx, cy + dy)
        if not c or c.kind == "void" then
          s = s + W.nVoid
        elseif tall(c) then
          s = s + W.nTall
        end
        if c and c.kind ~= "void" then
          if want and c.kind == want then s = s + W.nKind
          elseif (c.kind == "water") ~= (want == "water") then s = s + W.nWater end
          if c.slope then s = s + W.nSlope end
        end
      end
    end
  end
  return s
end

-- the share of rect r (u0, v0, u1, v1) that the screen rect a..b covers
local function overlap(r, au, av, bu, bv)
  local w = min(r[3], bu) - max(r[1], au)
  local h = min(r[4], bv) - max(r[2], av)
  if w <= 0 or h <= 0 then return 0 end
  return (w * h) / ((r[3] - r[1]) * (r[4] - r[2]))
end

-- how much of a side's sprite the cards standing in front of its feet cover (0..1)
local function occlusion(Camera, grid, pose, foot, rect)
  local share = 0
  for cy = foot.cy + 1, foot.cy + 7 do
    for cx = foot.cx - 5, foot.cx + 5 do
      local c = grid.at(cx, cy)
      local y0, y1, z
      if c and (c.model or c.sign) then
        -- a model: as tall as it stands over the cell, from the cell's southern edge
        if (c.top or 0) > 0 then y0, y1, z = 0, c.top, cy + 1 end
      elseif c and c.up then
        y0, y1, z = c.up, c.up + 1, c.base + 1
      end
      if z then
        -- (lifted with its cell: a point h up stands h south)
        local dy = c.dy or 0
        y0, y1, z = y0 + dy, y1 + dy, z + dy
        local u0, v0 = Camera.project(pose, cx, y1, z)
        local u1, v1 = Camera.project(pose, cx + 1, y0, z)
        if u0 and u1 then
          share = share + overlap(rect, min(u0, u1), min(v0, v1), max(u0, u1), max(v0, v1))
          if share >= 1 then return 1 end
        end
      end
    end
  end
  return share
end

-- the void on the screen around a target
local function voidOnScreen(Camera, grid, pose, tx, tz)
  local s = 0
  local bx, bz = floor(tx), floor(tz)
  for cy = bz - 10, bz + 4 do
    for cx = bx - 10, bx + 10 do
      local c = grid.at(cx, cy)
      if not c or c.kind == "void" then
        local u, v = Camera.project(pose, cx + 0.5, 0, cy + 0.5)
        if u and u >= 0 and u <= Camera.W and v >= 0 and v <= Camera.H then
          s = s + (v > Camera.CY and W.voidLow or W.voidHigh)
        end
      end
    end
  end
  return s
end

--- Search. opts:
---   player = { cx, cy }          the player's cell
---   want = { player = kind|nil, enemy = kind|nil }
---   feet = { player = { u, v }, enemy = { u, v } }       canvas points
---   sprites = { player = { u0, v0, u1, v1 }, enemy = {...} }   canvas rects
---   void = true                  the window has void cells (indoors): count them on screen
--- Returns { tx, tz, ty, score, feet = { player = {x, z}, enemy = {x, z} } } (the target and where
--- each side's feet stand, in map cells; ty the target's ground height, tiles: the camera aims at
--- (tx, ty, tz + ty)), or nil when the feet cannot be cast.
function Stage.search(Camera, grid, opts)
  local rest = Camera.pose(0, 0)
  local px, pz = Camera.ground(rest, opts.feet.player[1], opts.feet.player[2])
  local ex, ez = Camera.ground(rest, opts.feet.enemy[1], opts.feet.enemy[2])
  if not (px and ex) then return nil end
  local want = opts.want or {}
  -- the target that stands the player's Pokemon on the player's own cell
  local t0x, t0z = opts.player.cx + 0.5 - px, opts.player.cy + 0.5 - pz
  local best
  for dz = -Stage.REACH, Stage.REACH do
    for dx = -Stage.REACH, Stage.REACH do
      local tx, tz = t0x + dx, t0z + dz
      local pf = { cx = floor(tx + px), cy = floor(tz + pz) }
      local ef = { cx = floor(tx + ex), cy = floor(tz + ez) }
      local s = W.distance * sqrt(dx * dx + dz * dz)
      local tc = grid.at(floor(tx), floor(tz))
      local groundT = tc and tc.liftT or 0
      s = s + footScore(grid.at(pf.cx, pf.cy), want.player, groundT)
        + footScore(grid.at(ef.cx, ef.cy), want.enemy, groundT)
      s = s + neighbourScore(grid, pf.cx, pf.cy, want.player) + neighbourScore(grid, ef.cx, ef.cy, want.enemy)
      -- (what is left only takes away: a target already behind the best is not looked at closely)
      if not best or s > best.score then
        local pose = Camera.pose(tx, tz + groundT, nil, nil, groundT)
        if opts.sprites then
          s = s + W.occlude * occlusion(Camera, grid, pose, pf, opts.sprites.player)
          s = s + W.occlude * occlusion(Camera, grid, pose, ef, opts.sprites.enemy)
        end
        if opts.void then s = s + voidOnScreen(Camera, grid, pose, tx, tz) end
        if not best or s > best.score then
          best = { tx = tx, tz = tz, ty = groundT, score = s,
                   feet = { player = { tx + px, tz + pz }, enemy = { tx + ex, tz + ez } } }
        end
      end
    end
  end
  return best
end

return Stage
