-- The rooms (Battle Scene: Overworld): how each room is cut into its walls and furniture, read by
-- src/scene/models/interiors.lua.
--
-- Shapes are in pixels of the room's drawing: rectangles { x0, y0, x1, y1 }, ellipses
-- { "ellipse", cx, cy, rx, ry } and polygons { { x, y }, ... }. `height` is the rows of a piece's
-- front, standing at its drawn foot; `base` lifts it onto another piece. The rooms come in the
-- order they are modelled: a piece is modelled in the first room that has it, and stands, as it
-- is, in every later room that draws it again.
--
-- Ported from Emerald 3DS's scripts/voxel_building_specs.py (its Interiors section; by Zallax and
-- contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), whose
-- comments explain how each room is read. Every number is theirs.

local function hexes(list)
  local out = {}
  for i, c in ipairs(list or {}) do out[i] = type(c) == "string" and tonumber(c, 16) or c end
  return out
end
local function cat(...)
  local out = {}
  for _, l in ipairs({ ... }) do
    for _, v in ipairs(l) do out[#out + 1] = v end
  end
  return out
end

--- A room's piece (voxel_building_specs.piece): o = { base, fill, leave, side, solid, back,
--- card, top, foot, walls, cells, against, claim, through, round, legs, run, plan, skip, when,
--- at, tiles, anim, ribbon, found, flat, variants, posts, squash, turn, alone }
local function piece(name, shape, height, o)
  o = o or {}
  return { name = name, shape = shape, height = height, base = o.base or 0, fill = o.fill,
           leave = hexes(o.leave), side = o.side, solid = o.solid, back = o.back, card = o.card or false,
           top = o.top, foot = o.foot, walls = o.walls or {}, cells = o.cells or {}, against = o.against,
           claim = o.claim or {}, through = o.through or false, round = o.round, legs = o.legs,
           run = o.run or {}, plan = o.plan, skip = o.skip or {}, when = o.when, at = o.at or {},
           tiles = o.tiles, anim = o.anim, ribbon = o.ribbon, found = o.found or false,
           flat = o.flat or false, variants = o.variants or false, posts = o.posts, squash = o.squash,
           turn = o.turn, alone = o.alone }
end

--- A chamfered corner (facet): a wall along its foot from a = { x, top, foot } to b, carrying the
--- side walls that run on from it, `height` tall.
local function facet(name, a, b, height, o)
  o = o or {}
  return { name = name, shape = { { { a[1], a[2] }, { b[1], b[2] }, { b[1], b[3] }, { a[1], a[3] } } },
           height = height, facet = { a, b }, walls = o.walls or {}, side = o.side, cells = o.cells or {},
           leave = {}, claim = {}, run = {}, skip = {}, at = {} }
end

-- ── the Pokemon Centers ─────────────────────────────────────────────────────

local WALL_COLOURS = { "f6b473", "de7b31", "ffe6b4" }   -- the Center's orange wall
-- the Center's floor and its shadows, and the counter's cream and trim
local CENTER_FLOOR = { "cdc58b", "eedea4", "ffffc5" }
local CENTER_COUNTER = { "ffffc5", "e6e6b4", "de9c62", "ffe6b4", "de7b31" }
-- a stretch of the Center's back wall, full height and one panel wide
local CENTER_WALL_SIDE = { 64, 0, 80, 32 }

-- the Center's walls, 32 px: the back one at row 32, in two, and its chamfered corners, from
-- which the side walls run on to where the floor ends at `front`
local function centerWalls(front)
  return {
    facet("corner_w", { 0, 15, 47 }, { 16, -1, 31 }, 32, { walls = { { { 0, front }, { 0, 47 } } },
      side = CENTER_WALL_SIDE, cells = { { 0, math.floor(front / 16) - 1 } } }),
    facet("corner_e", { 208, -1, 31 }, { 224, 15, 47 }, 32, { walls = { { { 224, 47 }, { 224, front } } },
      side = CENTER_WALL_SIDE, cells = { { 13, math.floor(front / 16) - 1 } } }),
    piece("wall_e", { { 128, 0, 208, 32 } }, 32, { fill = 16, side = CENTER_WALL_SIDE }),
    piece("wall", { { 16, 0, 128, 32 } }, 32, { fill = 16, side = CENTER_WALL_SIDE }),
  }
end

-- the Center's escalator from the side: a ramp between two glass balustrades, to z 96 and 120,
-- level east of x `flat`, climbing (`way` 1) or sinking (-1) west of it
local function centerEscalator(flat, way)
  local top = 7 + way * flat / 2.0
  local rail = { { 0, 0 }, { 32, 0 }, { 32, 7 }, { flat, 7 }, { 0, top } }
  local steps, front
  if way > 0 then
    rail = { { 0, flat / 2.0 - 0.5 }, { flat - 1, 0 }, { 32, 0 }, { 32, 7 }, { flat, 7 }, { 0, top } }
    steps = { { 0, flat / 2.0 }, { flat, 0 }, { 32, 0 }, { 32, 0.5 }, { flat, 0.5 }, { 0, flat / 2.0 + 0.5 } }
    front = 118
  else
    rail = { { 0, 0 }, { 32, 0 }, { 32, 7 }, { flat, 7 } }
    steps, front = { { 0, 0 }, { 32, 0 }, { 32, 0.5 }, { 0, 0.5 } }, 120
  end
  return { { "rail_n", rail, 94, 96 }, { "rail_s", rail, 118, 120 }, { "steps", steps, 96, front } }
end

-- the Center's counter in plan: a bar across the front, an arm back to the wall each end, its
-- front corners cut on the slant and its arms' back corners by a nick
local function centerCounterPlan(x0, x1, arm, zBack, zBar, zFront, cut, nick)
  cut, nick = cut or 3, nick or 1.2
  local a, b = x0 + arm, x1 - arm
  return { { x0 + cut, zFront }, { x1 - cut, zFront }, { x1, zFront - cut },
           { x1, zBack + nick }, { x1 - nick, zBack }, { b + nick, zBack }, { b, zBack + nick },
           { b, zBar }, { a, zBar }, { a, zBack + nick }, { a - nick, zBack },
           { x0 + nick, zBack }, { x0, zBack + nick }, { x0, zFront - cut } }
end

-- a stool of the Centers drawn in the 16 x 16 at (x0, y0): its cushion, its base and its foot
local function centerStool(x0, y0)
  local z = y0 + 16
  local cushion = { { x0 + 3.25, y0 + 8 }, { x0 + 12.75, y0 + 8 }, { x0 + 15, y0 + 10.25 }, { x0 + 15, z },
                    { x0 + 1, z }, { x0 + 1, y0 + 10.25 } }
  local base = { { x0 + 2, y0 + 9 }, { x0 + 14, y0 + 9 }, { x0 + 14, z }, { x0 + 2, z } }
  local foot = { { x0 + 4, y0 + 11 }, { x0 + 12, y0 + 11 }, { x0 + 12, z }, { x0 + 4, z } }
  return { { "cushion", cushion, 4, 6, { x0 + 3, x0 + 13, y0 + 12 } },
           { "base", base, 1, 4, { x0 + 5, x0 + 11, y0 + 15 } },
           { "foot", foot, 0, 1, { x0 + 4, x0 + 12, y0 + 16 } } }
end

-- the Center's glass table: its top a slab from y 1 to 5 on four feet a pixel tall
local function centerTable()
  local left = { { 183.5, 101 }, { 183, 101.5 }, { 181, 102.5 }, { 180, 103.5 }, { 179, 104.5 },
                 { 179, 105.5 }, { 178, 106.5 }, { 178, 125.5 }, { 179, 126 } }
  -- (the drawing is symmetric about x 192)
  local slab = {}
  for _, p in ipairs(left) do slab[#slab + 1] = p end
  for i = #left, 1, -1 do slab[#slab + 1] = { 384 - left[i][1], left[i][2] } end
  local function foot(x, z) return { { x, z }, { x + 2, z }, { x + 2, z + 2 }, { x, z + 2 } } end
  local out = { { "top", slab, 1, 5, { 185, 190, 125 } } }
  for n, p in ipairs({ { 180, 124 }, { 202, 124 }, { 180, 104 }, { 202, 104 } }) do
    out[#out + 1] = { "foot_" .. (n - 1), foot(p[1], p[2]), 0, 1, { 180, 182, 126 } }
  end
  return out
end

local POKEMON_CENTER_1F = cat({
  -- the Poke Balls on the counter's two arms: round, each as its drawn circle
  piece("ball_w", { { "ellipse", 73, 46, 6, 6 } }, 12, { base = 10, leave = CENTER_COUNTER, round = "ball" }),
  piece("ball_e", { { "ellipse", 151, 46, 6, 6 } }, 12, { base = 10, leave = CENTER_COUNTER, round = "ball" }),
  -- the counter: a bar across the front, an arm back to the wall each end, on its plan
  piece("counter", { { 65, 24, 79, 64 }, { 79, 25, 80, 64 }, { 144, 24, 159, 64 }, { 65, 45, 159, 64 } }, 10,
    { fill = "column", leave = { "de7b31", "cdc58b", "eedea4" }, side = { 108, 54, 116, 64 },
      plan = centerCounterPlan(65, 159, 15, 34, 55, 64) }),
  -- behind it the healing machine lies flat: its tray its top, its front the band over the counter
  piece("healer", { { 80, 14, 112, 45 } }, 14, { leave = WALL_COLOURS, foot = 54, against = 32, cells = { { 5, 3 } } }),
  -- the telephone: a box, its top the lid with the cross, and its dial in front of its west end
  piece("phone", { { 133, 25, 144, 41 }, { 128, 31, 133, 42 } }, 8, { leave = cat(WALL_COLOURS, CENTER_FLOOR),
    plan = { { "box", { { 133, 33 }, { 141.5, 33 }, { 144, 35.5 }, { 144, 41 }, { 133, 41 } }, 0, 8, { 135, 140, 41 } },
             { "dial", { { 128, 36 }, { 133, 36 }, { 133, 42 }, { 128, 42 } }, 0, 5, { 129, 130, 42 } } } }),
  -- the PC by the map, against the wall
  piece("pc", { { 160, 8, 176, 40 } }, 24, { leave = WALL_COLOURS, back = 32 }),
  piece("bookcase", { { 32, 14, 65, 42 } }, 18, { leave = WALL_COLOURS, back = 32 }),
  -- a card: the wall, the corner's shade and the floor round its pot left
  piece("plant", { { 14, 10, 34, 40 } }, 26, { card = true, through = true,
    leave = cat(WALL_COLOURS, CENTER_FLOOR, { "f6eebd", "bd5220", "949494" }) }),
  piece("stool_1", { { 16, 47, 32, 64 } }, 6, { leave = CENTER_FLOOR, plan = centerStool(16, 47) }),
  piece("stool_2", { { 32, 47, 48, 64 } }, 6, { leave = CENTER_FLOOR, plan = centerStool(32, 47) }),
  piece("stool_3", { { 160, 95, 176, 111 } }, 6, { leave = CENTER_FLOOR, plan = centerStool(160, 95) }),
  piece("stool_4", { { 160, 111, 176, 127 } }, 6, { leave = CENTER_FLOOR, plan = centerStool(160, 111) }),
  piece("stool_5", { { 176, 127, 192, 144 } }, 6, { leave = CENTER_FLOOR, plan = centerStool(176, 127) }),
  piece("stool_6", { { 192, 127, 208, 144 } }, 6, { leave = CENTER_FLOOR, plan = centerStool(192, 127) }),
  -- a glass top on four feet a row tall, under its edge
  piece("table", { { 176, 95, 208, 128 } }, 5, { leave = CENTER_FLOOR, plan = centerTable() }),
  -- up to the floor above, into the west wall
  piece("escalator", { { 0, 78, 34, 123 } }, 8, { leave = cat(CENTER_FLOOR, { "949494" }),
    run = centerEscalator(16, 1) }),
}, centerWalls(144))

-- a link terminal of the Center's 2F at x0: its head, a box from y 9 to 20, on its pedestal
local function centerTerminal(x0)
  local head = { { x0, 76 }, { x0 + 16, 76 }, { x0 + 16, 80 }, { x0, 80 } }
  local stand = { { x0 + 2, 77 }, { x0 + 14, 77 }, { x0 + 14, 80 }, { x0 + 2, 80 } }
  return { { "head", head, 9, 20, { x0 + 1, x0 + 2, 71 } },
           { "stand", stand, 0, 9, { x0 + 7, x0 + 8, 80 } } }
end

local POKEMON_CENTER_2F = cat({
  -- the link terminals (the first is the ground floor's PC, and stands here as it is), and the
  -- glass tubes behind them
  piece("terminal_2", { { 128, 56, 144, 81 } }, 20, { plan = centerTerminal(128) }),
  piece("terminal_3", { { 192, 56, 208, 81 } }, 20, { plan = centerTerminal(192) }),
  -- the gates between the counter's stretches: low, set back to its back
  piece("gate_1", { { 80, 46, 96, 58 } }, 6, { back = 48 }),
  piece("gate_2", { { 144, 46, 160, 58 } }, 6, { back = 48 }),
  piece("counter", { { 0, 40, 48, 63 }, { 64, 40, 80, 63 }, { 96, 40, 128, 63 }, { 160, 40, 192, 63 },
                     { 208, 40, 218, 63 } }, 9, { fill = 1, back = 48 }),
  -- glass tubes: as deep as they are wide, their sides the white of their glass, whole
  piece("tube_1", { { 48, 6, 64, 42 } }, 24, { leave = WALL_COLOURS, side = { 51, 16, 61, 36 }, solid = true }),
  piece("tube_2", { { 128, 6, 144, 56 } }, 33, { leave = WALL_COLOURS, side = { 131, 23, 141, 52 }, solid = true }),
  piece("tube_3", { { 192, 6, 208, 56 } }, 33, { leave = WALL_COLOURS, side = { 195, 23, 205, 52 }, solid = true }),
  -- cards, the floor round their pots left
  piece("plant_1", { { 80, 128, 96, 160 } }, 24, { card = true, leave = cat(CENTER_FLOOR, { "f6eebd" }) }),
  piece("plant_2", { { 96, 128, 112, 160 } }, 24, { card = true, leave = cat(CENTER_FLOOR, { "f6eebd" }) }),
  piece("plant_3", { { 144, 128, 160, 160 } }, 24, { card = true, leave = cat(CENTER_FLOOR, { "f6eebd" }) }),
  piece("plant_4", { { 160, 128, 176, 160 } }, 24, { card = true, leave = cat(CENTER_FLOOR, { "f6eebd" }) }),
  -- (the five stools along the front are the ground floor's, and stand here as they are)
  -- down to the floor below: its steps drawn sinking into the floor
  piece("escalator", { { 0, 86, 34, 122 } }, 8, { leave = cat(CENTER_FLOOR, { "949494" }),
    run = centerEscalator(14, -1) }),
}, centerWalls(160))

-- ── the Poke Mart ───────────────────────────────────────────────────────────

local MART_WALL = { "ffffff", "8bd5de", "d5ded5", "b4b4a4", "83b4b4" }
local MART_WALL_SIDE = { 32, 0, 48, 32 }

local MART = {
  -- the till on the glass counter's arm; the counter, an L from the wall
  piece("till", { { 32, 24, 48, 39 } }, 8, { base = 15, leave = MART_WALL }),
  piece("counter", { { 32, 24, 48, 80 }, { 0, 58, 48, 80 } }, 15, { fill = 1, back = 64, top = { 34, 56, 46, 70 } }),
  -- the shelves along the back wall, the plant, the three standing shelves
  piece("shelves_back", { { 96, 14, 160, 42 } }, 20, { leave = MART_WALL, back = 32, side = "plain" }),
  piece("plant", { { 160, 30, 172, 64 } }, 26, { leave = MART_WALL, card = true }),
  piece("shelf_1", { { 96, 62, 112, 111 } }, 14, { back = 64 }),
  piece("shelf_2", { { 112, 62, 128, 111 } }, 14, { back = 64 }),
  piece("shelf_3", { { 160, 54, 172, 111 } }, 14, { back = 64 }),
  -- the walls as the Center's: 7-px corners, the side walls run on from them
  facet("corner_w", { 0, 6, 40 }, { 7, -1, 33 }, 34, { walls = { { { 0, 128 }, { 0, 40 } } }, side = MART_WALL_SIDE,
    cells = { { 0, 7 } } }),
  facet("corner_e", { 169, -1, 33 }, { 176, 6, 40 }, 34, { walls = { { { 176, 40 }, { 176, 128 } } },
    side = MART_WALL_SIDE, cells = { { 10, 7 } } }),
  piece("wall", { { 7, 0, 169, 32 } }, 32, { fill = 16, side = MART_WALL_SIDE }),
}

-- the front corners the GBA leaves black: floor, not a hole in it
local CENTER_1F_OPEN = { { { 0, 126 }, { 18, 144 }, { 0, 144 } }, { { 224, 126 }, { 206, 144 }, { 224, 144 } } }
local CENTER_2F_OPEN = { { { 0, 142 }, { 18, 160 }, { 0, 160 } }, { { 224, 142 }, { 206, 160 }, { 224, 160 } } }
local MART_OPEN = { { { 0, 118 }, { 10, 128 }, { 0, 128 } }, { { 176, 118 }, { 166, 128 }, { 176, 128 } } }

-- (Python's tuple slices: the first n)
local function first(list, n)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i] end
  return out
end

--- Marks a room's shell (its walls, doorways' recesses, a maze's blocks) as its own (`alone`):
--- never stood in another room by its cells being drawn again.
local SHELL = { wall = true, side = true, stairwell = true, edge = true, block = true, partition = true,
                divider = true }
local function ownShell(pieces)
  for _, pc in ipairs(pieces) do
    if SHELL[pc.name:match("^([^_]*)")] then pc.alone = true end
  end
  return pieces
end

-- ── Littleroot's two houses ─────────────────────────────────────────────────

local HOUSE_WALL = { "d5d5b4", "b4b4a4", "ffffff" }          -- plaster, baseboard, trim
local HOUSE_FLOOR = { "b4a44a", "947329", "ac8b39", "cdc55a" }  -- the planks
local BLUE_RUG = { "6a94c5", "8bbdf6", "838394" }               -- and the chairs' shadows
local PINK_RUG = { "d57bac", "838394" }

-- a kitchen chair seen from the side: its back, a narrow slab, and its seat
local function houseChair(name, back, seat, leave)
  return { piece(name .. "_back", { back }, 9, { leave = leave, solid = true }),
           piece(name .. "_seat", { seat }, 5, { leave = leave, solid = true }) }
end

-- the sides and back of a doorway's recess, x0..x1 from the wall's face at `front` back to
-- `back`; `opening` the doorway's height; `crest` the row the wall's top is drawn on
local function stairwell(name, x0, x1, front, back, opening, side, crest)
  local low = math.min(opening, back - crest)
  local mid = crest + opening
  local walls
  if mid >= front or mid <= back then
    walls = { { { x0, front }, { x0, back }, low }, { { x1, back }, { x1, front }, low } }
  else
    walls = { { { x0, front }, { x0, mid }, opening }, { { x0, mid }, { x0, back }, low },
              { { x1, back }, { x1, mid }, low }, { { x1, mid }, { x1, front }, opening } }
  end
  walls[#walls + 1] = { { x0, back }, { x1, back }, low }
  return piece(name, {}, 32, { side = side, walls = walls })
end

-- Littleroot's television: the set, a box as deep as its drawn top, on its stand
local function houseTv()
  local plan = { { 67.5, 81 }, { 76.5, 81 }, { 78, 82.5 }, { 80, 83.5 }, { 80, 88 }, { 64, 88 }, { 64, 83.5 },
                 { 66, 82.5 } }
  return { { "set", plan, 8, 20, { 64, 66, 80 } }, { "stand", plan, 0, 8, { 71, 73, 88 } } }
end

local function brendan1f()
  local rug = BLUE_RUG
  return cat(houseChair("chair_nw", { 33, 96, 37, 112 }, { 37, 100, 47, 112 }, rug),
    houseChair("chair_sw", { 33, 112, 37, 128 }, { 37, 116, 47, 128 }, rug),
    houseChair("chair_ne", { 91, 96, 95, 112 }, { 81, 100, 91, 112 }, rug),
    houseChair("chair_se", { 91, 112, 95, 128 }, { 81, 116, 91, 128 }, rug), {
    piece("table", { { 50, 96, 78, 128 } }, 8, { leave = rug, solid = true }),
    piece("tv", { { 64, 61, 80, 88 } }, 20, { leave = HOUSE_FLOOR, plan = houseTv() }),
    piece("cabinet", { { 32, 65, 63, 88 } }, 9, { back = 72 }),
    piece("fridge", { { 0, 18, 16, 48 } }, 24, { leave = HOUSE_FLOOR, back = 42 }),
    -- a wire of a tap: the baseboard between its spokes is seen through it
    piece("tap", { { 22, 24, 29, 29 } }, 5, { base = 8, leave = first(HOUSE_WALL, 2), through = true }),
    piece("sink", { { 16, 29, 48, 41 }, { 17, 41, 47, 48 } }, 8, { back = 32, top = { 18, 38, 46, 39 } }),
    -- on two legs: the floor under it is the floor
    piece("dresser", { { 49, 19, 72, 48 } }, 23, { back = 42, leave = HOUSE_FLOOR }),
    stairwell("stairwell", 128, 144, 48, 29, 19, { 128, 29, 144, 34 }, 16),
    -- the back wall, a cell forward east of the step; the doorway cut out of it
    piece("wall_e", { { 112, 16, 113, 48 }, { 113, 16, 176, 29 }, { 113, 29, 128, 48 }, { 144, 29, 176, 48 } }, 32,
      { fill = 16, foot = 48, side = { 156, 16, 172, 48 }, walls = { { { 112, 32 }, { 112, 48 } } } }),
    piece("wall", { { 0, 0, 113, 32 }, { 113, 0, 117, 16 } }, 32, { fill = 16, foot = 32, side = { 72, 0, 80, 32 } }),
    piece("side_w", {}, 32, { side = { 72, 0, 80, 32 }, walls = { { { 0, 144 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 156, 16, 172, 48 }, walls = { { { 176, 48 }, { 176, 144 } } } }),
  })
end

local function may1f()
  local rug = PINK_RUG
  -- (the chairs' seats are Brendan's, pixel for pixel on another rug; their backs are drawn over
  -- the rug)
  local backs = {}
  for _, pc in ipairs(cat(houseChair("chair_nw", { 81, 96, 85, 112 }, { 85, 100, 95, 112 }, rug),
      houseChair("chair_sw", { 81, 112, 85, 128 }, { 85, 116, 95, 128 }, rug),
      houseChair("chair_ne", { 139, 96, 143, 112 }, { 129, 100, 139, 112 }, rug),
      houseChair("chair_se", { 139, 112, 143, 128 }, { 129, 116, 139, 128 }, rug))) do
    if pc.name:sub(-5) == "_back" then backs[#backs + 1] = pc end
  end
  return cat(backs, {
    piece("table", { { 98, 96, 126, 128 } }, 8, { leave = rug, solid = true }),
    piece("dresser", { { 105, 19, 128, 48 } }, 23, { back = 42, leave = HOUSE_FLOOR }),
    stairwell("stairwell", 32, 48, 48, 29, 19, { 32, 29, 48, 34 }, 16),
    piece("wall_w", { { 63, 16, 64, 48 }, { 0, 16, 63, 29 }, { 0, 29, 32, 48 }, { 48, 29, 63, 48 } }, 32,
      { fill = 16, foot = 48, side = { 4, 16, 20, 48 }, walls = { { { 64, 48 }, { 64, 32 } } } }),
    piece("wall", { { 63, 0, 176, 32 }, { 59, 0, 63, 16 } }, 32, { fill = 16, foot = 32, side = { 96, 0, 104, 32 } }),
    piece("side_w", {}, 32, { side = { 4, 16, 20, 48 }, walls = { { { 0, 144 }, { 0, 48 } } } }),
    piece("side_e", {}, 32, { side = { 96, 0, 104, 32 }, walls = { { { 176, 32 }, { 176, 144 } } } }),
  })
end

local function brendan2f()
  return {
    piece("chair_back", { { 1, 33, 5, 48 } }, 9, { leave = HOUSE_FLOOR, solid = true }),
    piece("chair_seat", { { 5, 36, 14, 48 } }, 5, { leave = HOUSE_FLOOR, solid = true }),
    piece("pc", { { 1, 9, 16, 30 } }, 16, { base = 9, leave = HOUSE_WALL, back = 32 }),
    piece("book", { { 18, 24, 30, 31 } }, 1, { base = 9 }),
    piece("desk", { { 0, 20, 32, 40 } }, 9, { leave = HOUSE_FLOOR, against = 32 }),
    piece("console", { { 51, 24, 64, 40 } }, 9, { leave = cat(HOUSE_WALL, HOUSE_FLOOR), back = 32 }),
    piece("pillow", { { 18, 66, 30, 71 } }, 3, { base = 7, leave = HOUSE_FLOOR }),
    piece("bed_head", { { 12, 62, 36, 70 } }, 7, { base = 7, leave = HOUSE_FLOOR, through = true }),
    piece("bed", { { 12, 70, 36, 93 } }, 7, { leave = HOUSE_FLOOR, solid = true, claim = { { 12, 70, 36, 72 } } }),
    stairwell("stairwell", 112, 128, 32, 13, 19, { 113, 14, 127, 26 }, 0),
    piece("wall", { { 0, 0, 112, 32 }, { 112, 0, 128, 13 }, { 128, 0, 144, 32 } }, 32,
      { fill = 16, foot = 32, side = { 96, 0, 104, 32 } }),
    piece("side_w", {}, 32, { side = { 96, 0, 104, 32 }, walls = { { { 0, 128 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 96, 0, 104, 32 }, walls = { { { 144, 32 }, { 144, 128 } } } }),
  }
end

local function may2f()
  return {
    piece("chair_back", { { 139, 33, 143, 48 } }, 9, { leave = HOUSE_FLOOR, solid = true }),
    piece("chair_seat", { { 130, 36, 139, 48 } }, 5, { leave = HOUSE_FLOOR, solid = true }),
    piece("pc", { { 128, 9, 143, 30 } }, 16, { base = 9, leave = HOUSE_WALL, back = 32 }),
    piece("book", { { 114, 24, 126, 31 } }, 1, { base = 9 }),
    piece("desk", { { 112, 20, 144, 40 } }, 9, { leave = HOUSE_FLOOR, against = 32 }),
    piece("console", { { 83, 24, 98, 40 } }, 9, { leave = cat(HOUSE_WALL, HOUSE_FLOOR), back = 32 }),
    piece("pillow", { { 114, 66, 126, 71 } }, 3, { base = 7, leave = HOUSE_FLOOR }),
    piece("bed_head", { { 108, 62, 132, 70 } }, 7, { base = 7, leave = HOUSE_FLOOR, through = true }),
    piece("bed", { { 108, 70, 132, 93 } }, 7, { leave = HOUSE_FLOOR, solid = true, claim = { { 108, 70, 132, 72 } } }),
    stairwell("stairwell", 16, 32, 32, 13, 19, { 17, 14, 31, 26 }, 0),
    piece("wall", { { 0, 0, 16, 32 }, { 16, 0, 32, 13 }, { 32, 0, 144, 32 } }, 32,
      { fill = 16, foot = 32, side = { 40, 0, 48, 32 } }),
    piece("side_w", {}, 32, { side = { 40, 0, 48, 32 }, walls = { { { 0, 128 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 40, 0, 48, 32 }, walls = { { { 144, 32 }, { 144, 128 } } } }),
  }
end

-- ── the two houses most of Hoenn lives in, and the one with a bed ──────────────

local GENERIC_WALL = { "d5d5b4", "b4b4a4", "ffffff", "629c8b" }   -- plaster, trim, baseboard
local GENERIC_FLOOR = { "ded552", "bdb431", "8b8b8b", "9c9410" }  -- the planks, their shade
local GENERIC_RUG = { "ffcd8b", "f6f6a4" }
local GENERIC_TABLE = { "fff683", "bdac52" }

-- the potted plant's outline, its crown's top-left at (x, y)
local function pottedPlant(x, y)
  return { { x, y, x + 16, y + 13 }, { x + 2, y + 13, x + 14, y + 14 }, { x + 3, y + 14, x + 13, y + 15 },
           { x + 5, y + 15, x + 11, y + 16 }, { x + 6, y + 16, x + 10, y + 18 }, { x + 4, y + 18, x + 12, y + 19 },
           { x + 3, y + 19, x + 13, y + 20 }, { x + 2, y + 20, x + 14, y + 30 }, { x + 4, y + 30, x + 12, y + 31 } }
end

local function house1()
  local rug = GENERIC_RUG
  return cat(houseChair("chair_n", { 74, 64, 78, 80 }, { 65, 68, 74, 80 }, rug),
    houseChair("chair_s", { 74, 80, 78, 96 }, { 65, 84, 74, 96 }, rug), {
    piece("teapot", { { 49, 72, 59, 80 } }, 5, { base = 11, leave = GENERIC_TABLE }),
    piece("table", { { 34, 64, 62, 97 } }, 11, { leave = rug, solid = true, fill = 1, foot = 97 }),
    piece("plant_se", pottedPlant(144, 113), 31, { leave = GENERIC_FLOOR, card = true }),
    piece("plant_1", pottedPlant(128, 17), 31, { leave = cat(GENERIC_WALL, GENERIC_FLOOR), card = true }),
    piece("plant_2", pottedPlant(144, 17), 31, { leave = cat(GENERIC_WALL, GENERIC_FLOOR), card = true }),
    piece("case", { { 0, 12, 32, 40 } }, 20, { leave = cat(GENERIC_WALL, GENERIC_FLOOR), back = 32 }),
    piece("drawers", { { 33, 11, 57, 39 } }, 21, { leave = cat(GENERIC_WALL, GENERIC_FLOOR), back = 32, side = "plain" }),
    piece("wall", { { 0, 0, 160, 32 } }, 32, { fill = 16, foot = 32, side = { 64, 0, 80, 32 } }),
    piece("side_w", {}, 32, { side = { 64, 0, 80, 32 }, walls = { { { 0, 144 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 64, 0, 80, 32 }, walls = { { { 160, 32 }, { 160, 144 } } } }),
  })
end

local function house2()
  local fl = GENERIC_FLOOR
  return cat(houseChair("chair_nw", { 66, 64, 70, 80 }, { 70, 68, 79, 80 }, fl),
    houseChair("chair_sw", { 66, 80, 70, 96 }, { 70, 84, 79, 96 }, fl),
    { piece("chair_ne_back", { { 122, 64, 126, 80 } }, 9, { leave = fl, solid = true }),
      piece("chair_se_back", { { 122, 80, 126, 96 } }, 9, { leave = fl, solid = true }) }, {
    piece("table", { { 82, 64, 110, 95 } }, 9, { leave = fl, solid = true }),
    piece("tv", { { 32, 13, 48, 39 } }, 19, { leave = cat(first(GENERIC_WALL, 3), fl), back = 32,
      top = { 36, 14, 46, 15 }, side = { { 32, 20, 34, 31 }, { 39, 31, 41, 39 } } }),
    piece("tap", { { 133, 16, 142, 25 } }, 8, { base = 8, leave = first(GENERIC_WALL, 2) }),
    piece("cupboard", { { 112, 17, 128, 40 } }, 16, { leave = cat(GENERIC_WALL, fl), back = 32 }),
    piece("sink", { { 128, 21, 160, 40 } }, 8, { leave = cat(GENERIC_WALL, fl), against = 32 }),
    piece("fridge", { { 160, 10, 176, 40 } }, 24, { leave = cat(GENERIC_WALL, fl), back = 32 }),
    piece("wall", { { 0, 0, 176, 32 } }, 32, { fill = 16, foot = 32, side = { 48, 0, 64, 32 } }),
    piece("side_w", {}, 32, { side = { 48, 0, 64, 32 }, walls = { { { 0, 128 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 48, 0, 64, 32 }, walls = { { { 176, 32 }, { 176, 128 } } } }),
  })
end

local function houseWithBed()
  local fl = GENERIC_FLOOR
  return {
    piece("table", { { 128, 64, 158, 95 } }, 9, { leave = fl, solid = true, side = "plain" }),
    piece("pillow", { { 10, 53, 22, 58 } }, 3, { base = 7, leave = fl }),
    piece("bed_head", { { 4, 48, 28, 56 } }, 7, { base = 7, leave = fl, through = true, side = "plain" }),
    piece("bed", { { 4, 56, 28, 80 } }, 7, { leave = fl, solid = true }),
    piece("chest", { { 16, 15, 32, 40 } }, 17, { leave = cat(GENERIC_WALL, fl), back = 32 }),
    piece("bookcase", { { 128, 10, 160, 39 } }, 21, { leave = cat(first(GENERIC_WALL, 3), fl), back = 32 }),
    piece("wall", { { 0, 0, 160, 32 } }, 32, { fill = 16, foot = 32, side = { 64, 0, 80, 32 } }),
    piece("side_w", {}, 32, { side = { 64, 0, 80, 32 }, walls = { { { 0, 128 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 64, 0, 80, 32 }, walls = { { { 160, 32 }, { 160, 128 } } } }),
  }
end

-- ── Petalburg's gym ───────────────────────────────────────────────────────────

-- its sliding doors (field_specials.c PetalburgGymSetDoorMetatiles): each one's top cell
local PETALBURG_GYM_DOORS = { { 1, 104 }, { 7, 104 }, { 1, 78 }, { 7, 78 }, { 1, 91 }, { 7, 91 }, { 7, 39 },
                              { 1, 52 }, { 7, 52 }, { 1, 65 }, { 7, 13 }, { 1, 26 } }
local PETALBURG_GYM_DOOR = 0x218          -- SlidingDoor_Frame0; its bottom 8 on
local PETALBURG_GYM_SIDE = { 16, 208, 48, 240 }

-- the door whose top cell is (x, y), a stretch of its wall, while the game has it at `frame`
local function petalburgDoor(x, y, frame)
  return piece(("wall_door_%d_%d_%d"):format(x, y, frame), { { x * 16, y * 16, x * 16 + 16, y * 16 + 32 } }, 32,
    { foot = y * 16 + 32, side = PETALBURG_GYM_SIDE, when = { x, y, PETALBURG_GYM_DOOR + frame } })
end

-- the room with every door at `frame`: { { x, y, metatile } }
local function petalburgDoorDraw(frame)
  local out = {}
  for _, d in ipairs(PETALBURG_GYM_DOORS) do
    out[#out + 1] = { d[1], d[2], PETALBURG_GYM_DOOR + frame }
    out[#out + 1] = { d[1], d[2] + 1, PETALBURG_GYM_DOOR + 8 + frame }
  end
  return out
end

-- nine rooms one under another, each a back wall with its sliding doors and a pair of side walls
local function petalburgGym()
  local side = PETALBURG_GYM_SIDE
  local out = {}
  for room = 0, 8 do
    local y = room * 13 * 16
    local doors = {}
    for _, d in ipairs(PETALBURG_GYM_DOORS) do
      if d[2] * 16 == y then doors[#doors + 1] = d[1] end
    end
    table.sort(doors)
    local rects, x = {}, 0
    for _, d in ipairs(doors) do
      if d * 16 > x then rects[#rects + 1] = { x, y, d * 16, y + 32 } end
      x = d * 16 + 16
    end
    rects[#rects + 1] = { x, y, 144, y + 32 }
    for _, d in ipairs(doors) do out[#out + 1] = petalburgDoor(d, y / 16, 0) end
    out[#out + 1] = piece("wall_" .. room, rects, 32, { fill = 16, foot = y + 32, side = side })
    local bottom = (room * 13 + 8) * 16
    local function beside(cx)
      local cells = {}
      for cy = y / 16, bottom / 16 - 1 do cells[#cells + 1] = { cx, cy } end
      return cells
    end
    out[#out + 1] = piece("side_w" .. room, {}, 32, { side = side, walls = { { { 0, bottom }, { 0, y + 32 } } },
      skip = beside(0) })
    out[#out + 1] = piece("side_e" .. room, {}, 32, { side = side, walls = { { { 144, y + 32 }, { 144, bottom } } },
      skip = beside(8) })
  end
  return out
end

local function petalburgGymDoors(frame)
  local out = {}
  for _, d in ipairs(PETALBURG_GYM_DOORS) do out[#out + 1] = petalburgDoor(d[1], d[2], frame) end
  return out
end

-- ── the other houses of the general indoor tileset: their walls alone ───────────

-- each: its layout, size in cells, floor, the wall's cell the sides are dressed with, side walls
local PLAIN_ROOMS = {
  { "LAYOUT_HOUSE3", 10, 8, 0x229, 1, true },
  { "LAYOUT_DEWFORD_TOWN_HALL", 17, 9, 0x223, 3, true },
  { "LAYOUT_HOUSE4", 10, 9, 0x229, 3, true },
  { "LAYOUT_LILYCOVE_CITY_HOUSE2", 8, 8, 0x229, 3, true },
  { "LAYOUT_VERDANTURF_TOWN_WANDAS_HOUSE", 17, 8, 0x223, 5, true },
  { "LAYOUT_PACIFIDLOG_TOWN_HOUSE1", 10, 9, 0x3A3, 4, true },
  { "LAYOUT_PACIFIDLOG_TOWN_HOUSE2", 10, 9, 0x3A3, 5, true },
  { "LAYOUT_RUSTBORO_CITY_HOUSE", 12, 9, 0x32C, 3, true },
  { "LAYOUT_RUSTBORO_CITY_HOUSE1", 13, 8, 0x32C, 4, true },
  { "LAYOUT_RUSTBORO_CITY_CUTTERS_HOUSE", 11, 9, 0x32C, 4, true },
  { "LAYOUT_FORTREE_CITY_HOUSE1", 8, 6, 0x3D9, 2, true },
  { "LAYOUT_FORTREE_CITY_HOUSE2", 8, 6, 0x3D9, 1, true },
  { "LAYOUT_ROUTE116_TUNNELERS_REST_HOUSE", 10, 9, 0x229, 3, true },
  { "LAYOUT_ROUTE110_TRICK_HOUSE_ENTRANCE", 12, 8, 0x229, 1, true },
  { "LAYOUT_FORTREE_CITY_DECORATION_SHOP", 8, 6, 0x3D9, 1, false },
  { "LAYOUT_SOOTOPOLIS_CITY_LOTAD_AND_SEEDOT_HOUSE", 8, 7, 0x3FE, 2, true },
  { "LAYOUT_SOOTOPOLIS_CITY_HOUSE1", 8, 7, 0x3FE, 1, true },
  { "LAYOUT_SOOTOPOLIS_CITY_HOUSE2", 8, 7, 0x3FE, 4, true },
  { "LAYOUT_SOOTOPOLIS_CITY_HOUSE3", 8, 7, 0x3FE, 3, true },
  { "LAYOUT_MOSSDEEP_CITY_STEVENS_HOUSE", 11, 8, 0x223, 3, true },
}

local function plainRoom(width, height, plainX, sides)
  local w, h = width * 16, height * 16
  local side = { plainX * 16, 0, plainX * 16 + 16, 32 }
  local pieces = { piece("wall", { { 0, 0, w, 32 } }, 32, { fill = 16, foot = 32, side = side }) }
  if sides then
    pieces[#pieces + 1] = piece("side_w", {}, 32, { side = side, walls = { { { 0, h }, { 0, 32 } } } })
    pieces[#pieces + 1] = piece("side_e", {}, 32, { side = side, walls = { { { w, 32 }, { w, h } } } })
  end
  return pieces
end

-- ── Mr. Briney's house ──────────────────────────────────────────────────────

local BRINEY_FLOOR = { "c5ffac", "a4cd6a", "83ac4a", "7b7b83", "6a8b31", "414a6a" }

local function brineyRoom()
  local fl = BRINEY_FLOOR
  local mat = {}
  for _, c in ipairs(fl) do if c ~= "414a6a" then mat[#mat + 1] = c end end
  local plaster = { "d5b483", "d5c54a" }
  local side = { 48, 0, 64, 32 }
  return {
    piece("table", { { 114, 67, 142, 95 } }, 7, { leave = mat, solid = true }),
    -- turned, their mouths open on top: belly, shoulder and neck as drawn
    piece("jar_s", { { 1, 65, 15, 79 } }, 7, { leave = mat, round = "lathe" }),
    piece("jar_w", { { 1, 49, 15, 63 } }, 7, { leave = mat, round = "lathe" }),
    piece("jar_e", { { 17, 49, 31, 63 } }, 7, { leave = mat, round = "lathe" }),
    piece("drawers", { { 17, 10, 40, 40 } }, 22, { leave = cat(plaster, { "947329" }, mat), back = 32 }),
    piece("chest", { { 128, 16, 144, 45 } }, 16, { leave = cat(plaster, mat), back = 32, side = "plain" }),
    piece("case", { { 144, 12, 176, 45 } }, 20, { leave = cat(plaster, mat), back = 32 }),
    piece("wall", { { 0, 0, 192, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 144 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 192, 32 }, { 192, 144 } } } }),
  }
end

-- ── rooms with a flight of stairs in the back wall ──────────────────────────────

local FLAT_FLOOR = { "d5d5b4", "f6f6a4", "b4b4a4", "8b8b8b", "ded552" }

-- each: its layout, size in cells, floor, the wall's cell the sides are dressed with, the
-- doorways' columns, and where a partition runs down from the back wall
local STAIR_ROOMS = {
  { "LAYOUT_RUSTBORO_CITY_FLAT1_1F", 14, 8, 0x32C, 5, { 2 } },
  { "LAYOUT_RUSTBORO_CITY_FLAT1_2F", 14, 8, 0x32C, 5, { 2 } },
  { "LAYOUT_RUSTBORO_CITY_FLAT2_1F", 14, 9, 0x32C, 1, { 3 }, 80 },
  { "LAYOUT_RUSTBORO_CITY_FLAT2_2F", 14, 9, 0x32C, 9, { 1, 3 }, 80 },
  { "LAYOUT_RUSTBORO_CITY_FLAT2_3F", 14, 9, 0x32C, 3, { 1 }, 64 },
  { "LAYOUT_LILYCOVE_CITY_COVE_LILY_MOTEL_1F", 12, 9, 0x229, 4, { 2 } },
  { "LAYOUT_LILYCOVE_CITY_COVE_LILY_MOTEL_2F", 12, 9, 0x229, 4, { 2 } },
  { "LAYOUT_ROUTE114_FOSSIL_MANIACS_HOUSE", 10, 8, 0x229, 2, { 4 } },
  { "LAYOUT_ROUTE110_TRICK_HOUSE_END", 12, 8, 0x229, 6, { 2, 10 } },
  { "LAYOUT_RUSTBORO_CITY_DEVON_CORP_2F", 19, 9, 0x380, 4, { 2, 14 } },
  { "LAYOUT_RUSTBORO_CITY_DEVON_CORP_3F", 19, 9, 0x380, 4, { 2 } },
}

local function stairRoom(width, height, plainX, doors, partition)
  local w, h = width * 16, height * 16
  local side = { plainX * 16, 0, plainX * 16 + 16, 32 }
  local wall, pieces, x = {}, {}, 0
  if partition then
    pieces[#pieces + 1] = piece("divider", { { 128, 90, 224, 127 } }, 27, { solid = true, leave = FLAT_FLOOR })
    pieces[#pieces + 1] = piece("partition", { { partition, 0, partition + 16, 127 } }, 29, { solid = true })
  end
  local sorted = {}
  for i, d in ipairs(doors) do sorted[i] = d end
  table.sort(sorted)
  for _, door in ipairs(sorted) do
    local d = door * 16
    wall[#wall + 1] = { x, 0, d, 32 }
    wall[#wall + 1] = { d, 0, d + 16, 13 }
    pieces[#pieces + 1] = stairwell("stairwell_" .. door, d, d + 16, 32, 13, 19, { d + 1, 14, d + 15, 26 }, 0)
    x = d + 16
  end
  wall[#wall + 1] = { x, 0, w, 32 }
  return cat(pieces, {
    piece("wall", wall, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, h }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { w, 32 }, { w, h } } } }),
  })
end

-- ── Rustboro's Pokemon school: its back wall from 8 rows down to its foot 36 rows down ──

local function schoolRoom()
  local side = { 176, 8, 192, 36 }
  return {
    piece("wall", { { 0, 8, 192, 36 } }, 28, { fill = 16, foot = 36, side = side }),
    piece("side_w", {}, 28, { side = side, walls = { { { 0, 176 }, { 0, 36 } } } }),
    piece("side_e", {}, 28, { side = side, walls = { { { 192, 36 }, { 192, 176 } } } }),
  }
end

-- ── the Pretty Petal flower shop ─────────────────────────────────────────────

local SHOP_FLOOR = { "eef6ff", "d5d5e6", "b4acb4" }
local SHOP_WALL = { "bdbd94", "e6e68b", "ffffbd", "629c62", "9cd59c", "4a7b41" }

local function flowerShopRoom()
  local fl = SHOP_FLOOR
  local side = { 48, 0, 64, 32 }
  local function planter(name, x, y0, y1)
    return piece(name, { { x, y0, x + 16, y1 } }, 10, { leave = fl, solid = true })
  end
  -- a low stand of slats on four legs, three potted plants in a row along it (cards)
  local function rack(name, x)
    local function plant(part, r, crown, foot)
      return piece(name .. "_" .. part, cat(crown, { { x + 2, r - 3, x + 14, r }, { x + 3, r, x + 13, r + 3 },
        { x + 4, r + 3, x + 12, r + 8 } }, foot), 16, { base = 8, leave = fl, card = true })
    end
    local function tips(r) return { { x + 3, r - 7, x + 4, r - 3 }, { x + 12, r - 7, x + 13, r - 3 } } end
    return {
      plant("plant_s", 111, tips(111), { { x + 6, 119, x + 10, 120 } }),
      plant("plant_c", 99, tips(99), {}),
      plant("plant_n", 87, { { x + 2, 80, x + 14, 84 } }, {}),
      piece(name, { { x, 87, x + 16, 128 } }, 8, { leave = fl, side = "plain", through = true }),
    }
  end
  -- a low table against the wall, cacti and plants on it, each its own card
  local function backTable(name, x)
    local function card(part, shape, leave)
      return piece(name .. "_" .. part, shape, 12, { base = 7, leave = leave or fl, card = true })
    end
    local white = { { x + 6, 27, x + 7, 28 }, { x + 11, 27, x + 12, 28 }, { x + 5, 28, x + 13, 29 },
                    { x + 3, 29, x + 15, 30 }, { x + 2, 30, x + 16, 33 }, { x + 3, 33, x + 15, 35 },
                    { x + 4, 35, x + 14, 37 }, { x + 5, 37, x + 13, 38 }, { x + 6, 38, x + 12, 39 },
                    { x + 7, 39, x + 11, 40 } }
    local red = { { x + 20, 27, x + 21, 28 }, { x + 25, 27, x + 26, 28 }, { x + 19, 28, x + 27, 29 },
                  { x + 17, 29, x + 29, 30 }, { x + 16, 30, x + 30, 33 }, { x + 17, 33, x + 29, 35 },
                  { x + 18, 35, x + 28, 37 }, { x + 19, 37, x + 27, 38 }, { x + 20, 38, x + 26, 39 },
                  { x + 21, 39, x + 25, 40 } }
    local out = { card("white", white), card("red", red) }
    for k = 0, 2 do
      out[#out + 1] = card("cactus_" .. (k + 1), { { x + 3 + 9 * k, 19, x + 11 + 9 * k, 29 } }, cat(fl, { "e6e68b" }))
    end
    out[#out + 1] = piece(name, { { x, 25, x + 32, 48 } }, 7, { leave = fl, back = 32, side = "plain" })
    return out
  end
  return cat({
    planter("planter_sw", 0, 112, 144),
    planter("planter_w", 80, 96, 128), planter("planter_c", 128, 96, 128),
    planter("planter_e1", 192, 80, 128), planter("planter_e2", 208, 80, 128),
  }, rack("rack_1", 96), rack("rack_2", 112), rack("rack_e", 224), {
    planter("planter_n1", 176, 48, 64), planter("planter_n2", 192, 48, 64),
    piece("shelf", { { 112, 24, 152, 56 } }, 18, { leave = cat(SHOP_WALL, fl), back = 42 }),
  }, backTable("table_w", 160), backTable("table_e", 192), {
    piece("wall", { { 0, 0, 240, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 144 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 240, 32 }, { 240, 144 } } } }),
  })
end

-- (x, y0, y1) runs of cells, y1 inclusive, as rectangles of pixels: neighbouring columns with the
-- same run in one (run_rects)
local function runRects(runs)
  local rows, keys = {}, {}
  for _, r in ipairs(runs) do
    local k = r[2] * 4096 + r[3]
    if not rows[k] then rows[k] = {}; keys[#keys + 1] = k end
    local l = rows[k]
    l[#l + 1] = r[1]
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local y0, y1 = math.floor(k / 4096), k % 4096
    local xs = rows[k]
    table.sort(xs)
    local start, prev = xs[1], xs[1]
    for i = 2, #xs + 1 do
      local x = xs[i]
      if x == nil or x ~= prev + 1 then
        out[#out + 1] = { start * 16, y0 * 16, (prev + 1) * 16, (y1 + 1) * 16 }
        start = x
      end
      if x ~= nil then prev = x end
    end
  end
  table.sort(out, function(a, b)
    for i = 1, 4 do if a[i] ~= b[i] then return a[i] < b[i] end end
    return false
  end)
  return out
end

-- ── Dewford's gym: a maze cut in rock two cells tall ───────────────────────────

local DEWFORD_GYM_RUNS = {
  { 1, 6, 9 }, { 1, 12, 14 }, { 1, 18, 27 }, { 2, 7, 8 }, { 2, 19, 20 }, { 2, 23, 27 }, { 3, 7, 9 },
  { 3, 11, 15 }, { 3, 17, 21 }, { 3, 24, 27 }, { 4, 7, 9 }, { 4, 11, 15 }, { 4, 17, 21 }, { 4, 26, 27 },
  { 5, 7, 13 }, { 5, 17, 21 }, { 6, 6, 13 }, { 6, 15, 21 }, { 7, 0, 4 }, { 7, 6, 7 }, { 7, 9, 12 },
  { 7, 15, 21 }, { 7, 26, 27 }, { 8, 0, 4 }, { 8, 6, 7 }, { 8, 9, 12 }, { 8, 15, 17 }, { 8, 23, 27 },
  { 9, 0, 4 }, { 9, 6, 7 }, { 9, 15, 20 }, { 9, 23, 27 }, { 10, 0, 2 }, { 10, 6, 7 }, { 10, 9, 13 },
  { 10, 16, 20 }, { 10, 23, 27 }, { 11, 0, 3 }, { 11, 6, 7 }, { 11, 9, 13 }, { 11, 23, 27 },
  { 12, 0, 4 }, { 12, 16, 18 }, { 12, 26, 27 }, { 13, 0, 5 }, { 13, 9, 18 }, { 13, 20, 21 },
  { 13, 23, 27 }, { 14, 0, 5 }, { 14, 7, 11 }, { 14, 13, 17 }, { 14, 20, 21 }, { 14, 23, 27 },
  { 15, 0, 2 }, { 15, 7, 11 }, { 15, 13, 17 }, { 15, 20, 21 }, { 15, 23, 27 }, { 16, 0, 8 },
  { 16, 19, 27 },
}
-- the floor's shadow (its shaded metatiles carry the lips of the blocks' tops too)
local DEWFORD_GYM_FLOOR = { "737352" }

local function dewfordGym()
  local side = { 128, 424, 144, 448 }   -- a stretch of the front wall's face
  local out = {
    -- the leader's alcove: the bookcases either side of the dais, against its back wall
    piece("shelf_w", { { 16, 32, 32, 64 } }, 24, { against = 48, side = { 19, 41, 29, 47 } }),
    piece("shelf_e", { { 96, 32, 112, 64 } }, 24, { against = 48, side = { 99, 41, 109, 47 } }),
    piece("block_alcove", { { 16, 0, 112, 48 } }, 24, { side = side }),
  }
  -- each drawn from 8 rows into the cell north of it; a run a single cell tall 4 px lower
  for _, r in ipairs(runRects(DEWFORD_GYM_RUNS)) do
    local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
    out[#out + 1] = piece(("block_%d_%d"):format(x0 / 16, y0 / 16), { { x0, y0 ~= 0 and y0 - 8 or 0, x1, y1 } },
      math.min(24, y1 - y0 - 4), { side = side, solid = true })
  end
  -- the rock down the west and east edges, in three stretches each
  for _, x in ipairs({ 0, 17 }) do
    for _, s in ipairs({ { 0, 10 }, { 10, 19 }, { 19, 28 } }) do
      local y0, y1 = s[1], s[2]
      out[#out + 1] = piece(("block_edge_%d_%d"):format(x, y0), { { x * 16, y0 * 16, x * 16 + 16, y1 * 16 } }, 24,
        { side = side, solid = true, back = y0 ~= 0 and y0 * 16 or nil,
          top = y0 ~= 0 and { x * 16, y0 * 16, x * 16 + 16, y0 * 16 + 24 } or nil })
    end
  end
  return out
end

-- ── Professor Birch's lab ──────────────────────────────────────────────────

local LAB_SHADOW = { "b4b4a4", "949494" }      -- the floor's shade, and its grid in it
local LAB_FLOOR = { "d5d5b4" }                 -- the floor itself, where it shows beside a stack

-- the machine under the lab's dome in plan: an octagon between the drawing's pixels
local function labMachine()
  local left = { { 160, 120.5 }, { 160, 113.5 }, { 161, 112.5 }, { 161, 111.5 }, { 165, 107.5 }, { 168, 106 } }
  local out = {}
  for _, p in ipairs(left) do out[#out + 1] = p end
  for i = #left, 1, -1 do out[#out + 1] = { 352 - left[i][1], left[i][2] } end
  out[#out + 1] = { 184.5, 128 }
  out[#out + 1] = { 167.5, 128 }
  return out
end

local function lab()
  local sh = LAB_SHADOW
  return {
    piece("plant_s", { { 48, 189, 64, 208 } }, 18, { card = true }),
    piece("chair_sw_back", { { 34, 160, 47, 167 } }, 7, { base = 4, leave = sh, solid = true }),
    piece("chair_sw_seat", { { 34, 167, 47, 176 } }, 4, { leave = sh, solid = true }),
    piece("books_sw1", { { 1, 160, 16, 176 } }, 9, { leave = cat(sh, LAB_FLOOR), back = 160 }),
    piece("books_sw2", { { 1, 176, 16, 192 } }, 9, { leave = cat(sh, LAB_FLOOR), back = 176 }),
    piece("pc_sw", { { 18, 145, 30, 160 } }, 8, { base = 8, solid = true }),
    piece("desk_sw", { { 16, 160, 32, 192 }, { 16, 148, 18, 160 }, { 30, 148, 32, 160 } }, 8, { leave = sh, back = 156 }),
    piece("plant_se", { { 192, 141, 208, 161 } }, 18, { card = true }),
    piece("boxes_se", { { 192, 164, 208, 192 } }, 20, { leave = sh, back = 176 }),
    piece("chair_se_back", { { 161, 160, 165, 176 } }, 9, { leave = sh, solid = true }),
    piece("chair_se_seat", { { 165, 164, 176, 176 } }, 5, { leave = sh, solid = true }),
    piece("pc_se", { { 178, 145, 190, 160 } }, 8, { base = 8, solid = true }),
    piece("desk_se", { { 176, 160, 192, 192 }, { 176, 148, 178, 160 }, { 190, 148, 192, 160 } }, 8, { leave = sh, back = 156 }),
    -- the machine, its round glass dome, the two canisters beside it
    piece("dome", { { "ellipse", 176, 103.5, 8.5, 7.5 } }, 5, { base = 10, round = "dome" }),
    piece("machine", { { 160, 95, 192, 128 } }, 10, { leave = sh, side = { 172, 118, 180, 128 }, plan = labMachine() }),
    piece("canisters", { { 192, 109, 208, 128 } }, 16, { leave = sh, back = 112 }),
    -- the two bookcases in the room, a box on each
    piece("box_w1", { { 8, 82, 23, 96 } }, 6, { base = 21, solid = true }),
    piece("box_w2", { { 40, 82, 55, 96 } }, 6, { base = 21, solid = true }),
    piece("bookcase_w1", { { 0, 85, 32, 128 } }, 21, { back = 96 }),
    piece("bookcase_w2", { { 32, 85, 64, 128 } }, 21, { back = 96 }),
    -- boxes and book stacks in the north-east corner
    piece("boxes_ne1", { { 144, 56, 160, 80 } }, 8, { leave = sh }),
    piece("boxes_ne2", { { 160, 52, 176, 80 } }, 18, { leave = sh, back = 64 }),
    piece("books_ne1", { { 177, 32, 193, 48 } }, 8, { leave = sh, back = 32 }),
    piece("books_ne2", { { 193, 32, 208, 48 } }, 8, { leave = sh, back = 32 }),
    piece("books_ne3", { { 193, 48, 205, 53 }, { 193, 53, 208, 64 } }, 8, { leave = cat(sh, LAB_FLOOR), back = 48 }),
    piece("chair_n_back", { { 75, 48, 79, 64 } }, 9, { leave = sh, solid = true }),
    piece("chair_n_seat", { { 64, 52, 75, 64 } }, 5, { leave = sh, solid = true }),
    piece("boxes_w", { { 0, 41, 16, 64 } }, 7, { leave = sh }),
    -- along the back wall
    piece("plant_nw", { { 32, 29, 48, 48 } }, 18, { card = true }),
    piece("computer", { { 49, 10, 72, 30 } }, 14, { base = 8, back = 32 }),
    piece("desk_pc", { { 48, 20, 80, 39 } }, 8, { leave = sh, against = 32 }),
    -- books lying on the desks
    piece("book_red", { { 117, 19, 127, 30 } }, 3, { base = 8, against = 32 }),
    piece("book_open", { { 131, 19, 147, 31 } }, 3, { base = 8, against = 32 }),
    piece("binder", { { 147, 17, 156, 30 } }, 5, { base = 8, against = 32 }),
    piece("desk_a", { { 96, 20, 128, 39 } }, 8, { leave = sh, against = 32 }),
    piece("desk_b", { { 128, 20, 160, 39 } }, 8, { leave = sh, against = 32 }),
    piece("bookcase_nw", { { 0, 8, 32, 40 } }, 21, { against = 32 }),
    piece("wall", { { 0, 0, 208, 32 } }, 32, { fill = 16, foot = 32, side = { 80, 0, 96, 32 } }),
    piece("side_w", {}, 32, { side = { 80, 0, 96, 32 }, walls = { { { 0, 208 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = { 80, 0, 96, 32 }, walls = { { { 208, 32 }, { 208, 208 } } } }),
  }
end

-- ── Rustboro's gym: low stone walls on a tiled floor ───────────────────────────

local GYM_WALL_SIDE = { 32, 7, 48, 32 }

-- a maze block: `rects` in cells, each drawn from 8 rows north of its cells to its foot
local function gymBlock(name, rects)
  local shape = {}
  for i, r in ipairs(rects) do shape[i] = { r[1] * 16, r[2] * 16 - 8, r[3] * 16, r[4] * 16 } end
  return piece(name, shape, 10, { side = { 56, 118, 72, 128 } })
end

-- a gym statue's outline, its cell's left edge at x: its pedestal's bottom corners rounded off
local function gymStatue(x)
  return { { x, 272, x + 16, 302 }, { x + 1, 302, x + 15, 303 }, { x + 2, 303, x + 14, 304 } }
end

local function rustboroGym()
  return {
    -- the statues by the door, a ball on a pedestal: every gym has them (the ball found by its
    -- own few pixels)
    piece("statue_w_ball", { { "ellipse", 40, 279, 7, 7 } }, 8, { base = 16, found = true }),
    piece("statue_w", gymStatue(32), 16, { back = 288 }),
    piece("statue_e_ball", { { "ellipse", 136, 279, 7, 7 } }, 8, { base = 16, found = true }),
    piece("statue_e", gymStatue(128), 16, { back = 288 }),
    gymBlock("block_sw", { { 2, 13, 4, 15 }, { 2, 15, 5, 16 } }),
    gymBlock("block_s", { { 6, 15, 8, 16 } }),
    gymBlock("block_w", { { 4, 9, 5, 11 }, { 2, 11, 5, 12 } }),
    gymBlock("block_c", { { 6, 9, 8, 11 } }),
    gymBlock("block_e_arm", { { 6, 12, 9, 13 }, { 7, 13, 9, 14 } }),
    gymBlock("block_e", { { 9, 6, 11, 16 } }),
    gymBlock("block_n", { { 3, 6, 9, 8 } }),
    gymBlock("block_west", { { 0, 6, 1, 16 } }),
    piece("wall_w", { { 0, 0, 16, 48 } }, 25, { fill = 16, foot = 48, side = GYM_WALL_SIDE }),
    piece("wall_e", { { 160, 0, 176, 48 } }, 25, { fill = 16, foot = 48, side = GYM_WALL_SIDE }),
    piece("wall", { { 16, 0, 160, 32 } }, 25, { fill = 16, foot = 32, side = GYM_WALL_SIDE }),
    piece("side_w", {}, 25, { side = GYM_WALL_SIDE, walls = { { { 0, 176 }, { 0, 48 } } } }),
    piece("side_w2", {}, 25, { side = GYM_WALL_SIDE, walls = { { { 0, 320 }, { 0, 176 } } } }),
    piece("side_e", {}, 25, { side = GYM_WALL_SIDE, walls = { { { 176, 48 }, { 176, 176 } } } }),
    piece("side_e2", {}, 25, { side = GYM_WALL_SIDE, walls = { { { 176, 176 }, { 176, 320 } } } }),
  }
end

-- Lavaridge's Center: a door to the hot spring in the back wall, a plant either side of it; the
-- rest is the other Centers', tile for tile, and the back wall east of the door too
local LAVARIDGE_CENTER_1F = {
  piece("plant_w", { { 14, 10, 34, 40 } }, 26, { leave = WALL_COLOURS }),
  piece("plant_e", { { 46, 10, 66, 40 } }, 26, { leave = WALL_COLOURS }),
}
for _, pc in ipairs(centerWalls(144)) do
  if pc.name ~= "wall_e" then LAVARIDGE_CENTER_1F[#LAVARIDGE_CENTER_1F + 1] = pc end
end

local ROOMS = {
  -- every town's Pokemon Center has this one ground floor
  { name = "pc1f", interior = { layout = "LAYOUT_POKEMON_CENTER_1F", ground = { 0x202 },
                                pieces = POKEMON_CENTER_1F, open = CENTER_1F_OPEN } },
  { name = "pc2f", interior = { layout = "LAYOUT_POKEMON_CENTER_2F", ground = { 0x202 },
                                pieces = POKEMON_CENTER_2F, open = CENTER_2F_OPEN } },
  -- every Poke Mart but the department store has this one room
  { name = "mart", interior = { layout = "LAYOUT_MART", ground = { 0x201 }, pieces = MART, open = MART_OPEN,
                                shade = { 0x202, 0x204, 0x206, 0x208, 0x20A } } },
  { name = "brendan_1f", interior = { layout = "LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", ground = { 0x201 },
                                      pieces = brendan1f() } },
  { name = "brendan_2f", interior = { layout = "LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", ground = { 0x201 },
                                      pieces = brendan2f() } },
  { name = "may_1f", interior = { layout = "LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_1F", ground = { 0x201 },
                                  pieces = may1f() } },
  { name = "may_2f", interior = { layout = "LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_2F", ground = { 0x201 },
                                  pieces = may2f() } },
  { name = "lab", interior = { layout = "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB", ground = { 0x202 },
                               pieces = lab() } },
}
-- after the starter: the boxes by the machine give way to a table; the rest is the lab's, tile
-- for tile, its back wall too; the side walls are its own
do
  local pieces = { piece("table", { { 128, 64, 176, 89 } }, 8, { leave = LAB_SHADOW, solid = true }) }
  for _, pc in ipairs(lab()) do
    if pc.name == "side_w" or pc.name == "side_e" then pieces[#pieces + 1] = pc end
  end
  ROOMS[#ROOMS + 1] = { name = "lab_table", interior = {
    layout = "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE", ground = { 0x202 }, pieces = pieces } }
end
local function add(name, layout, ground, pieces, o)
  o = o or {}
  ROOMS[#ROOMS + 1] = { name = name, interior = { layout = layout, ground = ground, pieces = pieces, open = o.open,
                                                  shade = o.shade, draw = o.draw, pit = o.pit } }
end
add("lavaridge_pc1f", "LAYOUT_LAVARIDGE_TOWN_POKEMON_CENTER_1F", { 0x202 }, LAVARIDGE_CENTER_1F,
  { open = CENTER_1F_OPEN })
-- Oldale's first house, and eight more maps'; its second, and eleven more; Petalburg's second
add("house1", "LAYOUT_HOUSE1", { 0x223 }, house1())
add("house2", "LAYOUT_HOUSE2", { 0x223 }, house2())
add("house_with_bed", "LAYOUT_HOUSE_WITH_BED", { 0x223 }, ownShell(houseWithBed()))
for _, r in ipairs(PLAIN_ROOMS) do
  add(r[1]:sub(8):lower(), r[1], { r[4] }, ownShell(plainRoom(r[2], r[3], r[5], r[6])))
end
-- Mr. Briney's house, by the dock on Route 104
add("briney_room", "LAYOUT_ROUTE104_MR_BRINEYS_HOUSE", { 0x229 }, ownShell(brineyRoom()))
for _, r in ipairs(STAIR_ROOMS) do
  add(r[1]:sub(8):lower(), r[1], { r[4] }, ownShell(stairRoom(r[2], r[3], r[5], r[6], r[7])))
end
add("school_room", "LAYOUT_RUSTBORO_CITY_POKEMON_SCHOOL", { 0x201 }, ownShell(schoolRoom()))
add("flower_shop_room", "LAYOUT_ROUTE104_PRETTY_PETAL_FLOWER_SHOP", { 0x201 }, ownShell(flowerShopRoom()))
-- Rustboro's gym before the other gyms: the statues every gym has by its door are modelled here
add("rustboro_gym", "LAYOUT_RUSTBORO_CITY_GYM", { 0x201 }, rustboroGym(),
  { shade = { 0x202, 0x203, 0x204, 0x216, 0x22f, 0x237 } })
add("dewford_gym", "LAYOUT_DEWFORD_TOWN_GYM", { 0x210 }, ownShell(dewfordGym()), { shade = DEWFORD_GYM_FLOOR })
local PETALBURG_SHADE = { 0x209, 0x212, 0x213, 0x214, 0x22A, 0x232, 0x216, 0x22C }
add("petalburg_gym", "LAYOUT_PETALBURG_CITY_GYM", { 0x201, 0x22B }, ownShell(petalburgGym()),
  { shade = PETALBURG_SHADE })
-- its doors at each frame of their sliding open
for frame = 1, 4 do
  add("petalburg_gym_door" .. frame, "LAYOUT_PETALBURG_CITY_GYM", { 0x201, 0x22B }, petalburgGymDoors(frame),
    { shade = PETALBURG_SHADE, draw = petalburgDoorDraw(frame) })
end

-- the rooms' layouts by pret's number (data/layouts/layouts.json's order), which is how the
-- game's data keys them: a layout many maps share is named for none of them
ROOMS.ids = {
  LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F = 54, LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F = 55,
  LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_1F = 56, LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_2F = 57,
  LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB = 58, LAYOUT_HOUSE1 = 59, LAYOUT_HOUSE2 = 60,
  LAYOUT_POKEMON_CENTER_1F = 61, LAYOUT_POKEMON_CENTER_2F = 62, LAYOUT_MART = 63, LAYOUT_HOUSE3 = 64,
  LAYOUT_DEWFORD_TOWN_GYM = 65, LAYOUT_DEWFORD_TOWN_HALL = 66, LAYOUT_HOUSE4 = 67,
  LAYOUT_LAVARIDGE_TOWN_POKEMON_CENTER_1F = 71, LAYOUT_LILYCOVE_CITY_HOUSE2 = 74,
  LAYOUT_VERDANTURF_TOWN_WANDAS_HOUSE = 76, LAYOUT_PACIFIDLOG_TOWN_HOUSE1 = 77, LAYOUT_PACIFIDLOG_TOWN_HOUSE2 = 78,
  LAYOUT_PETALBURG_CITY_GYM = 79, LAYOUT_HOUSE_WITH_BED = 80, LAYOUT_RUSTBORO_CITY_DEVON_CORP_2F = 93,
  LAYOUT_RUSTBORO_CITY_GYM = 94, LAYOUT_RUSTBORO_CITY_POKEMON_SCHOOL = 95, LAYOUT_RUSTBORO_CITY_HOUSE = 96,
  LAYOUT_RUSTBORO_CITY_HOUSE1 = 97, LAYOUT_RUSTBORO_CITY_CUTTERS_HOUSE = 98, LAYOUT_FORTREE_CITY_HOUSE1 = 99,
  LAYOUT_FORTREE_CITY_HOUSE2 = 101, LAYOUT_ROUTE104_MR_BRINEYS_HOUSE = 102,
  LAYOUT_ROUTE104_PRETTY_PETAL_FLOWER_SHOP = 117, LAYOUT_ROUTE114_FOSSIL_MANIACS_HOUSE = 119,
  LAYOUT_ROUTE116_TUNNELERS_REST_HOUSE = 122, LAYOUT_ROUTE110_TRICK_HOUSE_ENTRANCE = 244,
  LAYOUT_ROUTE110_TRICK_HOUSE_END = 245, LAYOUT_FORTREE_CITY_DECORATION_SHOP = 255,
  LAYOUT_RUSTBORO_CITY_DEVON_CORP_3F = 269, LAYOUT_RUSTBORO_CITY_FLAT2_1F = 294, LAYOUT_RUSTBORO_CITY_FLAT2_2F = 295,
  LAYOUT_RUSTBORO_CITY_FLAT2_3F = 296, LAYOUT_SOOTOPOLIS_CITY_LOTAD_AND_SEEDOT_HOUSE = 297,
  LAYOUT_LILYCOVE_CITY_COVE_LILY_MOTEL_1F = 299, LAYOUT_LILYCOVE_CITY_COVE_LILY_MOTEL_2F = 300,
  LAYOUT_SOOTOPOLIS_CITY_HOUSE1 = 307, LAYOUT_SOOTOPOLIS_CITY_HOUSE2 = 308, LAYOUT_SOOTOPOLIS_CITY_HOUSE3 = 309,
  LAYOUT_RUSTBORO_CITY_FLAT1_1F = 313, LAYOUT_RUSTBORO_CITY_FLAT1_2F = 314, LAYOUT_MOSSDEEP_CITY_STEVENS_HOUSE = 327,
  LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE = 432,
}
-- the layouts no map is drawn with, which a script swaps into the map of the room named
-- (setmaplayoutindex): the lab once the starter is chosen
ROOMS.swaps = {
  LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE = "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB",
}

return ROOMS
