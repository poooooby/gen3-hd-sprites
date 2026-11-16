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
--
-- Ours too: a strict check ranks the targets before their score does (Stage.tier). A target is
-- fair (tier 3) when each side's feet stand on a cell it could stand on in the game - in the map,
-- not a wall, nothing standing there, level and at the target's own height (else the sprite would
-- float over a drop or sink into a rise) and the battle's kind of ground (water for a water
-- battle, dry ground else) - when the camera sees both sides (no model, card, tree or rock, as the
-- occlusion score stands them, across its line to either sprite's middle or lower quarter: so it
-- never stands in a building either) and when nothing stands, and no ground rises, on
-- the line between the two. Tier 2: both feet fair and seen, something between them; tier 1: both
-- feet fair, the view blocked; tier 0: not. The best-scoring target of the highest tier wins, so
-- the soft weights below only choose among the fair ones, and a spot with no fair target within
-- REACH keeps the best it has.

local Stage = {}

Stage.REACH = 6
-- (tiles: how far out the rings go when no target within REACH is fair, and how far from the
-- camera a ring's target must show only the window's cells)
Stage.FAR = 12
Stage.VIEW = 30
-- a best score below this: no stage fits (the battle keeps its wallpaper)
Stage.FLOOR = -40

local W = {
  void = -60, tall = -16, blocked = -6, waterWanted = 8, waterUnwanted = -12, waterMissing = -8,
  kind = 4, slope = -4, lift = -3,
  nVoid = -3, nTall = -1, nKind = 0.5, nWater = -0.8, nSlope = -0.4,
  occlude = -24, voidLow = -1.2, voidHigh = -0.5, sight = -6,
  distance = -0.5,
}
Stage.WEIGHTS = W
-- (tiles: how far a foot's ground may lie off the target's, and ground between the two may rise)
Stage.LEVEL = 0.25
-- (tiles: the step along the line between the feet)
Stage.STEP = 0.2

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

-- whether a side's feet may stand on cell c: as Stage.tier says
local function footFair(c, want, groundT)
  if not c or c.kind == "void" or c.kind == "blocked" or tall(c) or c.slope then return false end
  if (want == "water") ~= (c.kind == "water") then return false end
  if c.border and c.kind ~= "water" then return false end
  return math.abs((c.liftT or 0) - groundT) <= Stage.LEVEL
end

-- whether anything stands, or the ground rises, on the line from (ax, az) to (bx, bz) (map
-- cells, continuous), the cells at either end left out
local function lineClear(grid, ax, az, bx, bz, groundT, a, b)
  local dx, dz = bx - ax, bz - az
  local n = math.max(1, math.ceil(sqrt(dx * dx + dz * dz) / Stage.STEP))
  local last
  for i = 0, n do
    local c = grid.at(floor(ax + dx * i / n), floor(az + dz * i / n))
    if c ~= last and c ~= a and c ~= b then
      if not c or c.kind == "void" or c.kind == "blocked" or tall(c) then return false end
      if (c.liftT or 0) > groundT + Stage.LEVEL then return false end
    end
    last = c
  end
  return true
end

-- what stands on cell c as the view meets it, as the occlusion score reads it: a card on the
-- cell's southern edge (or its run's), lifted with the cell - y0, y1, z - or nil. A model, a sign
-- or a border as tall as it stands; a card of an upright run; a tree at its foot row (a tree built
-- off its drawing stands there, its crown over its trunk); rock stood taller than the ground
-- `footT`, at its depths, and other ground a level up at its front
local function cardOf(c, footT)
  local dy = c.dy or 0
  local top = c.top or 0
  if c.model or c.sign or c.border then
    if top > 0 then return dy, dy + top, c.cy + 1 + dy end
  elseif c.up then
    return c.up + dy, c.up + 1 + dy, (c.base or c.cy) + 1 + dy
  elseif c.treeFoot and top > 0 then
    return dy, dy + top, c.cy + 1 + dy
  elseif c.s and (c.liftT or 0) > footT + 0.5 then
    return footT, c.liftT, c.cy + 1 + (c.depthT or c.liftT)
  elseif (c.liftT or 0) > footT + 0.5 then
    -- (ground a level or more up: its front, as far south as it is high)
    return footT, c.liftT, c.cy + 1 + (c.dy or c.liftT)
  end
end

-- how far north (lo, at most 0) and south (hi, at least 0) of their rows the window's cells stand
-- (lifted ground and what stands on it), in tiles, from the target's height up; kept on the grid
local function liftRange(grid)
  if grid.stageLift then return grid.stageLift[1], grid.stageLift[2] end
  local lo, hi = 0, 0
  for j = 0, (grid.h or 0) - 1 do
    local row = grid.rows and grid.rows[j]
    for i = 0, (grid.w or 0) - 1 do
      local c = row and row[i]
      if c then
        local z = max(c.dy or 0, c.liftT or 0, c.depthT or 0)
        if z > hi then hi = z end
        z = min(c.dy or 0, c.liftT or 0)
        if z < lo then lo = z end
      end
    end
  end
  grid.stageLift = { lo, hi }
  return lo, hi
end

-- whether the camera at `pose` sees canvas point (u, v) as far as view depth `depth` (where the
-- sprite stands, on ground `footT`): no card stands across the line between (cardOf). Returns
-- false and the cell in the way
local function rayClear(Camera, grid, pose, u, v, depth, footT)
  local ex, ey, ez, rx, rz, ux, uy, uz, fx, fy, fz = Camera.basis(pose)
  local ka, kb = (u - Camera.CX) / Camera.F, -(v - Camera.CY) / Camera.F
  -- (a step of 1 along this ray is a step of 1 in view depth)
  local dx, dy, dz = rx * ka + ux * kb + fx, uy * kb + fy, rz * ka + uz * kb + fz
  if dz >= -1e-6 then return true end
  local ty = pose.ty or 0
  local tFar = depth - 0.3
  -- (every cell whose card could stand across the line: the rows it passes, widened by how far
  -- south a cell of the window stands at most, and north)
  local lo, hi = liftRange(grid)
  local zNear, zFar = ez + dz * Camera.NEAR, ez + dz * tFar
  local xNear, xFar = ex + dx * Camera.NEAR, ex + dx * tFar
  for cy = floor(zFar - ty - hi) - 1, floor(zNear - ty - lo) + 1 do
    for cx = floor(min(xNear, xFar)) - 1, floor(max(xNear, xFar)) + 1 do
      local c = grid.at(cx, cy)
      if c and c.kind ~= "void" then
        local y0, y1, zc = cardOf(c, footT)
        if zc then
          local t = (zc - ez) / dz
          if t > Camera.NEAR and t < tFar then
            local x, y = ex + dx * t, ey + dy * t
            if x >= cx and x <= cx + 1 and y >= y0 and y <= y1 then return false, c end
          end
        end
      end
    end
  end
  return true
end

-- whether the camera sees a side's sprite (canvas rect r) standing at foot (x, z): its middle
-- and a quarter up from its bottom
local function seen(Camera, grid, pose, r, x, z)
  local ty = pose.ty or 0
  local _, _, depth = Camera.view(pose, x, ty, z + ty)
  if not depth or depth <= Camera.NEAR then return false end
  local u = (r[1] + r[3]) / 2
  local ok, c = rayClear(Camera, grid, pose, u, (r[2] + r[4]) / 2, depth, ty)
  if not ok then return false, c end
  return rayClear(Camera, grid, pose, u, r[4] - (r[4] - r[2]) / 4, depth, ty)
end

-- whether what the camera at `pose` shows lies inside the window of cells, as far as `reach`
-- tiles from the eye: the canvas's corners (and a margin either side, for a wider screen) cast
-- onto the target's ground
-- (canvas pixels across, and down as a share of its height)
local CORNERS = { { -40, 1 }, { 280, 1 }, { -40, 0 }, { 280, 0 }, { 120, 1 } }
local function inWindow(Camera, grid, pose, reach)
  local ex, _, ez = Camera.basis(pose)
  local ty = pose.ty or 0
  for _, k in ipairs(CORNERS) do
    local x, z = Camera.ground(pose, k[1], k[2] * Camera.H, ty)
    if x then
      local d = sqrt((x - ex) ^ 2 + (z - ez) ^ 2)
      if d > reach then x, z = ex + (x - ex) * reach / d, ez + (z - ez) * reach / d end
      if not grid.at(floor(x), floor(z - ty)) then return false end
    end
  end
  return true
end

--- How fair target (tx, tz) is, its ground at groundT, the feet `off` = { px, pz, ex, ez } from
--- it, the sprites' canvas rects `sprites` ({ player = {u0, v0, u1, v1}, enemy = ... }; without
--- them the view is not checked): 3 both sides stand on fair ground, seen, nothing between them;
--- 2 seen, something between them; 1 stand fair; 0 not. And why not (for the stats): "player",
--- "enemy" (that side's feet), "view" (and the cell in the way) or "between".
function Stage.tier(Camera, grid, tx, tz, groundT, off, want, sprites)
  want = want or {}
  local px, pz, ex, ez = off[1], off[2], off[3], off[4]
  local a = grid.at(floor(tx + px), floor(tz + pz))
  if not footFair(a, want.player, groundT) then return 0, "player" end
  local b = grid.at(floor(tx + ex), floor(tz + ez))
  if not footFair(b, want.enemy, groundT) then return 0, "enemy" end
  if sprites then
    local pose = Camera.pose(tx, tz + groundT, nil, nil, groundT)
    local okP, cp = seen(Camera, grid, pose, sprites.player, tx + px, tz + pz)
    if not okP then return 1, "view", cp end
    local okE, ce = seen(Camera, grid, pose, sprites.enemy, tx + ex, tz + ez)
    if not okE then return 1, "view", ce end
  end
  if not lineClear(grid, tx + px, tz + pz, tx + ex, tz + ez, groundT, a, b) then return 2, "between" end
  return 3
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
  local fc = grid.at(foot.cx, foot.cy)
  local footT = fc and fc.liftT or 0
  for cy = foot.cy + 1, foot.cy + 7 do
    for cx = foot.cx - 5, foot.cx + 5 do
      local c = grid.at(cx, cy)
      local y0, y1, z
      local dy = c and c.dy or 0
      if c and (c.model or c.sign or c.border) then
        -- a model: as tall as it stands over the cell, from the cell's southern edge
        if (c.top or 0) > 0 then y0, y1, z = 0, c.top, cy + 1 end
      elseif c and c.up then
        y0, y1, z = c.up, c.up + 1, c.base + 1
      elseif c and c.s and (c.liftT or 0) > footT + 0.5 then
        -- rock stood taller than drawn (a cave's: its drawing stands back at its depths, cell.depthT)
        y0, y1, z, dy = footT, c.liftT, cy + 1 + (c.depthT or c.liftT), 0
      end
      if z then
        -- (lifted with its cell: a point h up stands h south)
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

-- how many cells of rock stood taller than drawn (a cave's: cell.s, its drawing at its depths)
-- rise over the camera's line of sight to the target, between the two: the rock would fill the view
local function sightBlocked(Camera, grid, pose)
  local ex, ey, ez = Camera.basis(pose)
  if ez <= pose.tz + 0.5 then return 0 end
  local n = 0
  for cy = floor(pose.tz), floor(ez) do
    for cx = floor(pose.tx) - 2, floor(pose.tx) + 2 do
      local c = grid.at(cx, cy)
      if c and c.s and c.liftT then
        local z = cy + 0.5 + (c.depthT or c.liftT)
        if z > pose.tz and z < ez then
          local yr = pose.ty + (ey - pose.ty) * (z - pose.tz) / (ez - pose.tz)
          if c.liftT > yr then n = n + 1 end
        end
      end
    end
  end
  return n
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
--- Returns { tx, tz, ty, score, tier, why, moved, feet = { player = {x, z}, enemy = {x, z} } }
--- (tier and why: Stage.tier's, 3 fair; moved: tiles from the target that stands the player's Pokemon on
--- the player's cell) (the target and where
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
  local off = { px, pz, ex, ez }
  local best
  -- one target, dx, dz tiles off; `fair`: only a fair one (tier 3) may become the best
  local function consider(dx, dz, fair)
    local tx, tz = t0x + dx, t0z + dz
    local tc = grid.at(floor(tx), floor(tz))
    local groundT = tc and tc.liftT or 0
    local tier, why = Stage.tier(Camera, grid, tx, tz, groundT, off, want, opts.sprites)
    if fair and tier < 3 then return end
    -- (that far out, the view may reach past the window of cells: only a target it does not)
    if fair and not inWindow(Camera, grid, Camera.pose(tx, tz + groundT, nil, nil, groundT), Stage.VIEW) then return end
    local pf = { cx = floor(tx + px), cy = floor(tz + pz) }
    local ef = { cx = floor(tx + ex), cy = floor(tz + ez) }
    local s = W.distance * sqrt(dx * dx + dz * dz)
    s = s + footScore(grid.at(pf.cx, pf.cy), want.player, groundT)
      + footScore(grid.at(ef.cx, ef.cy), want.enemy, groundT)
    s = s + neighbourScore(grid, pf.cx, pf.cy, want.player) + neighbourScore(grid, ef.cx, ef.cy, want.enemy)
    -- (what is left only takes away: a target already behind the best is not looked at closely)
    if not best or tier > best.tier or (tier == best.tier and s > best.score) then
      local pose = Camera.pose(tx, tz + groundT, nil, nil, groundT)
      if opts.sprites then
        s = s + W.occlude * occlusion(Camera, grid, pose, pf, opts.sprites.player)
        s = s + W.occlude * occlusion(Camera, grid, pose, ef, opts.sprites.enemy)
      end
      if opts.void then s = s + voidOnScreen(Camera, grid, pose, tx, tz) end
      s = s + W.sight * sightBlocked(Camera, grid, pose)
      if not best or tier > best.tier or (tier == best.tier and s > best.score) then
        best = { tx = tx, tz = tz, ty = groundT, score = s, tier = tier, why = why,
                 moved = sqrt(dx * dx + dz * dz),
                 feet = { player = { tx + px, tz + pz }, enemy = { tx + ex, tz + ez } } }
      end
    end
  end
  for dz = -Stage.REACH, Stage.REACH do
    for dx = -Stage.REACH, Stage.REACH do consider(dx, dz) end
  end
  -- nothing fair that near: ring by ring further out, the nearest ring with a fair target
  local r = Stage.REACH
  while best and best.tier < 3 and r < Stage.FAR do
    r = r + 1
    for d = -r, r do
      consider(d, -r, true); consider(d, r, true)
      if d > -r and d < r then consider(-r, d, true); consider(r, d, true) end
    end
  end
  return best
end

return Stage
