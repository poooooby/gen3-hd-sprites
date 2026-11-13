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

-- the rooms from the contest stage on (a function of their own: a chunk holds 200 locals)
local function laterRooms()

-- ── the contest stage ─────────────────────────────────────────────────────────

local STAGE_FLOOR = { "94acb4", "738383", "838b83", "bddec5" }   -- the dotted floor, its channel, the green

-- the cushions round the green: the back row, the two sides, the front row either side of the stairs
local STAGE_CUSHIONS = {}
for x = 49, 177, 16 do STAGE_CUSHIONS[#STAGE_CUSHIONS + 1] = { x, 48, x + 14, 55 } end
for y = 57, 121, 16 do
  for _, x in ipairs({ 49, 185 }) do STAGE_CUSHIONS[#STAGE_CUSHIONS + 1] = { x, y, x + 5, y + 13 } end
end
for _, x in ipairs({ 49, 65, 81, 145, 161, 177 }) do STAGE_CUSHIONS[#STAGE_CUSHIONS + 1] = { x, 136, x + 14, 143 } end

local function contestStage()
  local cushions = {}
  for i, r in ipairs(STAGE_CUSHIONS) do cushions[i] = { r, i } end
  -- (front first: by their foot, then west to east; Python's sort is stable)
  table.sort(cushions, function(a, b)
    if a[1][4] ~= b[1][4] then return a[1][4] > b[1][4] end
    if a[1][1] ~= b[1][1] then return a[1][1] < b[1][1] end
    return a[2] < b[2]
  end)
  local out = {}
  for i, c in ipairs(cushions) do out[i] = piece("cushion_" .. (i - 1), { c[1] }, 4, { leave = STAGE_FLOOR }) end
  out[#out + 1] = piece("case", { { 144, 73, 160, 88 } }, 8, { leave = STAGE_FLOOR })
  out[#out + 1] = piece("wall", { { 0, 0, 240, 16 } }, 16, { fill = 16, foot = 16, side = { 0, 0, 16, 16 } })
  return out
end

-- ── Lilycove's contest lobby and hall ───────────────────────────────────────────

local LOBBY_FLOOR = { "f6b49c", "d5ac7b", "cd9c7b", "b48b5a", "c55231" }
local LOBBY_WALL_SIDE = { 16, 3, 32, 32 }
local LOBBY_CURTAIN = { "cd295a", "de6a52" }

local function contestLobby()
  local out = {}
  for _, b in ipairs({ { 368, 144 }, { 432, 144 }, { 368, 80 }, { 432, 80 } }) do
    out[#out + 1] = piece(("blender_%d_%d"):format(b[1], b[2]), { { b[1], b[2], b[1] + 16, b[2] + 15 } }, 8,
      { leave = LOBBY_FLOOR })
  end
  return cat(out, {
    -- the counter, a U in plan, in three: the lobby's script opens and closes the flaps beside its arms
    piece("counter_w", { { 176, 25, 192, 62 } }, 10, { leave = cat(LOBBY_FLOOR, LOBBY_CURTAIN),
      plan = { { 176, 36.2 }, { 177.2, 35 }, { 190.8, 35 }, { 192, 36.2 }, { 192, 63 }, { 176, 63 } } }),
    piece("counter", { { 208, 44, 272, 62 } }, 10, { leave = cat(LOBBY_FLOOR, LOBBY_CURTAIN),
      plan = { { 208, 54 }, { 272, 54 }, { 272, 63 }, { 208, 63 } } }),
    piece("counter_e", { { 288, 25, 304, 62 } }, 10, { leave = cat(LOBBY_FLOOR, LOBBY_CURTAIN),
      plan = { { 288, 36.2 }, { 289.2, 35 }, { 302.8, 35 }, { 304, 36.2 }, { 304, 63 }, { 288, 63 } } }),
    piece("terminal", { { 304, 8, 320, 39 } }, 24, { back = 32 }),
    piece("wall", { { 0, 3, 496, 32 } }, 29, { fill = 16, foot = 32, side = LOBBY_WALL_SIDE }),
    piece("side_w", {}, 29, { side = LOBBY_WALL_SIDE, walls = { { { 0, 192 }, { 0, 32 } } } }),
    piece("side_e", {}, 29, { side = LOBBY_WALL_SIDE, walls = { { { 496, 32 }, { 496, 192 } } } }),
  })
end

local HALL_FLOOR = { "f6b49c", "d5ac7b" }
local HALL_WALL_SIDE = { 176, 4, 192, 64 }
local HALL_PALMS = { { 8, 9 }, { 42, 9 }, { 2, 11 }, { 5, 11 }, { 45, 11 }, { 48, 11 },
                     { 3, 32 }, { 7, 32 }, { 11, 32 }, { 39, 32 }, { 43, 32 }, { 47, 32 } }

local function lilycoveContestRoom()
  local side = HALL_WALL_SIDE
  local palms = {}
  for i, c in ipairs(HALL_PALMS) do palms[i] = c end
  table.sort(palms, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[1] < b[1]
  end)
  local out = {}
  for _, c in ipairs(palms) do
    out[#out + 1] = piece(("palm_%d_%d"):format(c[1], c[2]), { { c[1] * 16, c[2] * 16 - 16, c[1] * 16 + 16, c[2] * 16 + 14 } },
      31, { leave = HALL_FLOOR, card = true })
  end
  return cat(out, {
    piece("wall_ow", { { 0, 68, 80, 128 } }, 60, { fill = 16, foot = 128, side = side }),
    piece("wall_oe", { { 736, 68, 816, 128 } }, 60, { fill = 16, foot = 128, side = side }),
    piece("wall_ww", { { 80, 36, 160, 96 } }, 60, { fill = 16, foot = 96, side = side }),
    piece("wall_we", { { 656, 36, 736, 96 } }, 60, { fill = 16, foot = 96, side = side }),
    piece("wall_e", { { 408, 4, 656, 64 } }, 60, { fill = 16, foot = 64, side = side }),
    piece("wall", { { 160, 4, 408, 64 } }, 60, { fill = 16, foot = 64, side = side }),
    piece("side_step_ow", {}, 60, { side = side, walls = { { { 80, 128 }, { 80, 96 } } } }),
    piece("side_step_ww", {}, 60, { side = side, walls = { { { 160, 96 }, { 160, 64 } } } }),
    piece("side_step_we", {}, 60, { side = side, walls = { { { 656, 64 }, { 656, 96 } } } }),
    piece("side_step_oe", {}, 60, { side = side, walls = { { { 736, 96 }, { 736, 128 } } } }),
    piece("side_w", {}, 60, { side = side, walls = { { { 0, 528 }, { 0, 128 } } } }),
    piece("side_e", {}, 60, { side = side, walls = { { { 816, 128 }, { 816, 528 } } } }),
  })
end

-- ── Lilycove's Department Store ─────────────────────────────────────────────────

local DEPT_1F_FLOOR = { "cd8320", "ac5a20", "e69c39", "f6c539" }
local DEPT_WALL = { "d5ded5", "b4b4a4", "ffa47b", "cd947b" }
local DEPT_WALL_SIDE = { 64, 0, 80, 32 }

local function deptShell(out)
  out[#out + 1] = piece("wall", { { 0, 0, 288, 32 } }, 32, { fill = 16, foot = 32, side = DEPT_WALL_SIDE })
  out[#out + 1] = piece("side_w", {}, 32, { side = DEPT_WALL_SIDE, walls = { { { 0, 128 }, { 0, 32 } } } })
  out[#out + 1] = piece("side_e", {}, 32, { side = DEPT_WALL_SIDE, walls = { { { 288, 32 }, { 288, 128 } } } })
  return out
end

local function deptStore1f()
  return deptShell({
    piece("planter_s", { { 0, 105, 31, 127 } }, 9),
    piece("planter_n", { { 0, 73, 31, 95 } }, 9),
    piece("pc_w", { { 98, 37, 112, 52 } }, 8, { base = 10, solid = true, leave = { "cdffd5" } }),
    piece("pc_e", { { 178, 25, 191, 39 } }, 8, { base = 10, solid = true }),
    piece("counter", { { 96, 24, 112, 63 }, { 176, 24, 192, 63 }, { 96, 44, 192, 63 } }, 10,
      { leave = cat(DEPT_1F_FLOOR, DEPT_WALL),
        plan = { { 96, 34 }, { 112, 34 }, { 112, 54 }, { 176, 54 }, { 176, 34 }, { 192, 34 }, { 192, 64 }, { 96, 64 } } }),
  })
end

local DEPT_GREEN_FLOOR = { "a4eebd", "ffffff", "cdffd5", "b4b4a4", "9cd57b", "d5ded5", "b4de8b" }

local function deptStore2f()
  return deptShell({
    piece("counter", { { 96, 76, 112, 127 }, { 176, 76, 192, 127 }, { 112, 77, 176, 95 } }, 10,
      { leave = DEPT_GREEN_FLOOR,
        plan = { { 96, 86 }, { 112, 86 }, { 112, 87 }, { 176, 87 }, { 176, 86 }, { 192, 86 }, { 192, 128 },
                 { 176, 128 }, { 176, 96 }, { 112, 96 }, { 112, 128 }, { 96, 128 } } }),
  })
end

local function deptStore3f()
  return deptShell({
    piece("counter", { { 96, 24, 112, 63 }, { 176, 24, 192, 63 }, { 112, 45, 176, 63 } }, 10,
      { leave = DEPT_GREEN_FLOOR,
        plan = { { 96, 34 }, { 112, 34 }, { 112, 55 }, { 176, 55 }, { 176, 34 }, { 192, 34 }, { 192, 64 }, { 96, 64 } } }),
  })
end

local DEPT_4F_SHELVES = { 16, 32, 208, 224, 240, 256 }

local function deptStore4f()
  local out = {}
  for _, x in ipairs(DEPT_4F_SHELVES) do
    out[#out + 1] = piece("shelf_" .. x, { { x, 80, x + 16, 111 } }, 17, { back = 80, leave = DEPT_GREEN_FLOOR })
  end
  out[#out + 1] = piece("counter", { { 96, 76, 112, 127 }, { 160, 76, 176, 127 }, { 112, 77, 160, 95 } }, 10,
    { leave = DEPT_GREEN_FLOOR,
      plan = { { 96, 86 }, { 112, 86 }, { 112, 87 }, { 160, 87 }, { 160, 86 }, { 176, 86 }, { 176, 128 },
               { 160, 128 }, { 160, 96 }, { 112, 96 }, { 112, 128 }, { 96, 128 } } })
  return deptShell(out)
end

local DEPT_5F_FLOOR = { "ffffcd", "dedea4", "ffc5ac", "cdffcd", "acdeb4", "e6a483", "bdbd83" }

local function deptStore5f()
  return deptShell({
    piece("counter_e", { { 224, 76, 240, 127 }, { 240, 77, 288, 95 } }, 10, { leave = DEPT_5F_FLOOR,
      plan = { { 224, 86 }, { 240, 86 }, { 240, 87 }, { 288, 87 }, { 288, 96 }, { 240, 96 }, { 240, 128 }, { 224, 128 } } }),
    piece("counter", { { 80, 24, 96, 63 }, { 176, 24, 192, 63 }, { 96, 45, 176, 63 } }, 10, { leave = DEPT_5F_FLOOR,
      plan = { { 80, 34 }, { 96, 34 }, { 96, 55 }, { 176, 55 }, { 176, 34 }, { 192, 34 }, { 192, 64 }, { 80, 64 } } }),
  })
end

local DEPT_ELEVATOR_SIDE = { 0, 8, 8, 48 }

local function deptStoreElevator()
  return {
    piece("wall", { { 0, 8, 80, 48 } }, 40, { fill = 16, foot = 48, side = DEPT_ELEVATOR_SIDE }),
    piece("side_w", {}, 40, { side = DEPT_ELEVATOR_SIDE, walls = { { { 0, 96 }, { 0, 48 } } } }),
    piece("side_e", {}, 40, { side = DEPT_ELEVATOR_SIDE, walls = { { { 80, 48 }, { 80, 96 } } } }),
  }
end

local ROOF_FLOOR = { "b4b4a4", "d5ded5", "b4de8b", "9cd57b", "8b8b8b" }
local ROOF_LEDGE = { "cdeef6", "dee6ee", "bdcde6", "83838b", "62627b", "ffffff", "9cb4de" }
local ROOF_BARS = { 48, 8, 64, 19 }

local function deptStoreRooftop()
  local rail = cat(ROOF_FLOOR, ROOF_LEDGE)
  return {
    piece("rail_s", { { 16, 104, 272, 119 } }, 11, { through = true, leave = rail }),
    piece("bench_w", { { 80, 83, 112, 95 } }, 6, { leave = ROOF_FLOOR }),
    piece("bench_e", { { 144, 83, 176, 95 } }, 6, { leave = ROOF_FLOOR }),
    piece("chair_s", { { 256, 84, 272, 95 } }, 8, { leave = ROOF_FLOOR }),
    piece("chair_n", { { 256, 68, 272, 79 } }, 8, { leave = ROOF_FLOOR }),
    piece("planter_s", { { 16, 73, 48, 95 } }, 11, { leave = ROOF_FLOOR }),
    piece("planter_n", { { 16, 41, 48, 63 } }, 11, { leave = ROOF_FLOOR }),
    piece("rail_e", { { 270, 40, 280, 119 } }, 10, { through = true, leave = rail, side = ROOF_BARS }),
    piece("rail_w", { { 8, 8, 17, 119 } }, 10, { through = true, leave = rail, side = ROOF_BARS }),
    piece("housing", { { 192, 17, 240, 63 } }, 35, { back = 52, leave = ROOF_FLOOR }),
    piece("vending", { { 144, 0, 176, 31 } }, 24, { leave = cat(ROOF_FLOOR, ROOF_LEDGE) }),
    piece("rail_ne_e", { { 244, 40, 276, 51 } }, 10, { through = true, leave = rail }),
    piece("rail_ne_s", { { 240, 11, 248, 39 } }, 10, { through = true, leave = rail, side = ROOF_BARS }),
    piece("rail_n", { { 16, 8, 244, 19 } }, 10, { through = true, leave = rail }),
  }
end

-- ── Lilycove's museum ───────────────────────────────────────────────────────

local MUSEUM_1F_FLOOR = { "e6e68b", "ffffcd", "cdb462", "decd73", "7b6229" }
local MUSEUM_WALL_SIDE = { 64, 80, 80, 112 }
local MUSEUM_RING_NW = { { 16, 170 }, { 17, 170 }, { 17, 168 }, { 18, 168 }, { 18, 167 }, { 19, 167 }, { 19, 166 },
                         { 20, 166 }, { 20, 165 }, { 22, 165 }, { 22, 164 } }
local MUSEUM_RING_NE = { { 106, 164 }, { 106, 165 }, { 108, 165 }, { 108, 166 }, { 109, 166 }, { 109, 167 },
                         { 110, 167 }, { 110, 168 }, { 111, 168 }, { 111, 170 }, { 112, 170 } }

local function museum1f()
  local side = MUSEUM_WALL_SIDE
  return {
    piece("statue_r_ball", { { "ellipse", 296, 181.5, 6, 5.5 } }, 8, { base = 4, round = "ball" }),
    piece("statue_r", { { 288, 176, 304, 192 } }, 4, { leave = MUSEUM_1F_FLOOR, fill = "column" }),
    piece("statue_h", { { 240, 176, 256, 195 } }, 19, { base = 6, round = "lathe", leave = MUSEUM_1F_FLOOR }),
    piece("statue_h_base", { { 240, 195, 256, 208 } }, 6),
    piece("tablet", { { 256, 113, 304, 136 } }, 7, { base = 6, leave = { "ffffcd" } }),
    piece("case", { { 240, 110, 320, 160 } }, 6),
    piece("counter_w", { { 16, 158, 64, 176 }, { 16, 176, 32, 224 }, { 32, 206, 64, 224 } }, 6,
      { plan = cat(MUSEUM_RING_NW, { { 64, 164 }, { 64, 176 }, { 32, 176 }, { 32, 212 }, { 64, 212 }, { 64, 224 }, { 16, 224 } }) }),
    piece("counter_e", { { 64, 158, 112, 176 }, { 96, 176, 112, 224 }, { 64, 206, 96, 224 } }, 6,
      { plan = cat({ { 64, 164 } }, MUSEUM_RING_NE, { { 112, 224 }, { 64, 224 }, { 64, 212 }, { 96, 212 }, { 96, 176 }, { 64, 176 } }) }),
    piece("partition_s", { { 144, 72, 160, 144 } }, 32, { fill = 16, foot = 144, side = side,
      walls = { { { 144, 112 }, { 144, 144 } }, { { 160, 144 }, { 160, 104 } } } }),
    piece("partition", { { 0, 72, 144, 112 } }, 32, { fill = 16, foot = 112, side = side }),
    piece("wall_c", { { 208, 0, 224, 80 } }, 32, { fill = 16, foot = 80, side = side,
      walls = { { { 208, 32 }, { 208, 80 } }, { { 224, 80 }, { 224, 32 } } } }),
    piece("wall", { { 0, 0, 208, 32 }, { 224, 0, 336, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 224 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 336, 32 }, { 336, 224 } } } }),
  }
end

local MUSEUM_2F_FLOOR = { "e6e6e6", "9c9c9c", "d5d5d5", "c5c5c5", "b4b4b4", "7b7b7b" }
local MUSEUM_2F_WALL_SIDE = { 96, 0, 112, 32 }

local function museum2f()
  local side = MUSEUM_2F_WALL_SIDE
  return {
    piece("statue_e", { { 240, 16, 256, 35 } }, 19, { base = 6, round = "lathe", leave = MUSEUM_2F_FLOOR }),
    piece("statue_e_base", { { 240, 35, 256, 48 } }, 6),
    piece("wall_w", { { 0, 0, 64, 48 } }, 32, { fill = 16, foot = 48, side = side, walls = { { { 64, 48 }, { 64, 32 } } } }),
    piece("wall_e", { { 288, 0, 352, 48 } }, 32, { fill = 16, foot = 48, side = side, walls = { { { 288, 32 }, { 288, 48 } } } }),
    piece("wall", { { 64, 0, 288, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 208 }, { 0, 48 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 352, 48 }, { 352, 208 } } } }),
  }
end

-- ── the Trainer Fan Club, Lanette's house, the Day Care, the Seashore House ─────────

local FAN_CLUB_WALL_SIDE = { 48, 0, 64, 32 }

local function trainerFanClub()
  local side = FAN_CLUB_WALL_SIDE
  return {
    piece("table_w", { { 66, 144, 94, 177 } }, 11, { leave = GENERIC_RUG, solid = true, fill = 1, foot = 177 }),
    piece("partition_w", { { 0, 107, 47, 137 } }, 26, { fill = 16, foot = 144, side = side,
      walls = { { { 47, 144 }, { 47, 118 } } } }),
    piece("partition_e", { { 145, 107, 192, 144 } }, 26, { fill = 16, foot = 144, side = side,
      walls = { { { 145, 118 }, { 145, 144 } } } }),
    piece("wall", { { 0, 0, 192, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 224 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 192, 32 }, { 192, 224 } } } }),
  }
end

local LANETTE_WALL_SIDE = { 64, 0, 80, 32 }

local function lanettesHouse()
  local side = LANETTE_WALL_SIDE
  return {
    piece("box_e", { { 112, 82, 127, 96 } }, 6, { leave = cat(LAB_SHADOW, LAB_FLOOR) }),
    piece("box_sw", { { 16, 114, 31, 128 } }, 6, { leave = cat(LAB_SHADOW, LAB_FLOOR) }),
    piece("desks_e", { { 96, 64, 128, 78 }, { 96, 52, 98, 64 }, { 110, 52, 114, 64 }, { 126, 52, 128, 64 } }, 8,
      { leave = LAB_SHADOW, back = 60 }),
    piece("wall", { { 0, 0, 176, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 128 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 176, 32 }, { 176, 128 } } } }),
  }
end

local DAY_CARE_FLOOR = { "6283e6", "7b9cff", "4a6ad5", "4162a4", "838383", "8b8b8b" }
local DAY_CARE_GRASS = { "a4c562", "bde673", "6aa439" }
local DAY_CARE_PAINT = { "bdd5ee", "9cacde", "dee6ee", "ffffff" }
local DAY_CARE_WALL = cat(DAY_CARE_PAINT, { "e6c56a", "d5a44a", "a48341" })
local DAY_CARE_WALL_SIDE = { 132, 0, 148, 32 }

local function dayCare()
  local side = DAY_CARE_WALL_SIDE
  return {
    piece("plant_n", { { 0, 82, 16, 111 } }, 28, { leave = DAY_CARE_FLOOR, card = true }),
    piece("plant_s", { { 0, 114, 16, 143 } }, 28, { leave = DAY_CARE_FLOOR, card = true }),
    piece("table", { { 160, 82, 192, 111 } }, 5, { leave = DAY_CARE_GRASS, solid = true, side = { 164, 84, 188, 100 } }),
    piece("fence", { { 96, 128, 192, 144 } }, 15, { through = true, leave = cat(DAY_CARE_FLOOR, DAY_CARE_GRASS) }),
    piece("gatepost", { { 96, 112, 105, 128 } }, 15, { leave = DAY_CARE_FLOOR }),
    piece("pc", { { 160, 8, 176, 40 } }, 24, { leave = DAY_CARE_WALL, back = 32 }),
    piece("crate_w", { { 80, 23, 96, 48 } }, 7, { leave = DAY_CARE_PAINT, against = 32 }),
    piece("crate_e", { { 96, 22, 112, 48 } }, 7, { leave = DAY_CARE_PAINT, against = 32 }),
    piece("counter", { { 0, 44, 80, 63 }, { 64, 24, 80, 44 } }, 6, { leave = DAY_CARE_FLOOR, against = 32,
      plan = { { 0, 50 }, { 64, 50 }, { 64, 32 }, { 80, 32 }, { 80, 56 }, { 73, 63 }, { 0, 63 } } }),
    piece("wall", { { 0, 0, 192, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 144 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 192, 32 }, { 192, 144 } } } }),
  }
end

local SEASHORE_FLOOR = { "c5cd94", "e6e6b4", "f6f6cd", "7bc5b4", "52ac94", "b4deff", "b4b48b" }
local SEASHORE_WALL = { "e6c562", "ffe67b", "bd9c4a", "83838b", "7bc5b4" }
local SEASHORE_WALL_SIDE = { 48, 0, 58, 32 }

local function seashoreHouse()
  local out = {}
  for _, rw in ipairs({ { "n", 64 }, { "m", 96 }, { "s", 128 } }) do
    local row, y = rw[1], rw[2]
    local spans = { { "w", 0, 32 } }
    if row ~= "s" then
      spans[#spans + 1] = { "cw", 48, 96 }
      spans[#spans + 1] = { "ce", 128, 176 }
    end
    spans[#spans + 1] = { "e", 208, 240 }
    for _, s in ipairs(spans) do
      out[#out + 1] = piece(("table_%s%s"):format(row, s[1]), { { s[2], y, s[3], y + 17 } }, 8,
        { leave = SEASHORE_FLOOR, solid = true })
    end
  end
  local side = SEASHORE_WALL_SIDE
  return cat(out, {
    piece("machine", { { 112, 16, 128, 44 } }, 24, { back = 32, leave = cat(SEASHORE_WALL, SEASHORE_FLOOR) }),
    piece("fridge_w", { { 16, 14, 48, 46 } }, 21, { back = 32, leave = cat(SEASHORE_WALL, SEASHORE_FLOOR) }),
    piece("fridge_e", { { 192, 14, 224, 46 } }, 21, { back = 32, leave = cat(SEASHORE_WALL, SEASHORE_FLOOR) }),
    piece("wall", { { 0, 0, 240, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 160 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 240, 32 }, { 240, 160 } } } }),
  })
end

-- ── Devon Corporation's lobby ───────────────────────────────────────────────

local DEVON_FLOOR = { "cd837b", "deaca4", "bd6252" }
local DEVON_WALL = { "835a31", "e69c62", "6a7b41", "839473", "9c9c9c", "acb494" }
local DEVON_WALL_SIDE = { 0, 52, 12, 80 }

local function devonCorp1f()
  local side = DEVON_WALL_SIDE
  return {
    piece("case_w", { { 48, 22, 64, 48 } }, 26, { round = "lathe", leave = cat(DEVON_FLOOR, DEVON_WALL) }),
    piece("case_e", { { 128, 22, 144, 48 } }, 26, { round = "lathe", leave = cat(DEVON_FLOOR, DEVON_WALL) }),
    piece("desk", { { 48, 62, 128, 80 } }, 8, { leave = DEVON_FLOOR, solid = true }),
    piece("wall_rww", { { 44, 0, 48, 80 } }, 28, { fill = 16, foot = 80, side = side, walls = { { { 48, 80 }, { 48, 32 } } } }),
    piece("wall_rwe", { { 144, 0, 148, 80 } }, 28, { fill = 16, foot = 80, side = side, walls = { { { 144, 32 }, { 144, 80 } } } }),
    piece("wall_rew", { { 204, 0, 208, 80 } }, 28, { fill = 16, foot = 80, side = side, walls = { { { 208, 80 }, { 208, 32 } } } }),
    piece("wall_ree", { { 256, 0, 260, 80 } }, 28, { fill = 16, foot = 80, side = side, walls = { { { 256, 32 }, { 256, 80 } } } }),
    piece("wall_rw", { { 48, 0, 144, 32 } }, 28, { fill = 16, foot = 32, side = side }),
    piece("wall_re", { { 208, 0, 256, 32 } }, 28, { fill = 16, foot = 32, side = side }),
    piece("wall_w", { { 0, 48, 44, 80 } }, 28, { fill = 16, foot = 80, side = side }),
    piece("wall_c", { { 148, 48, 204, 80 } }, 28, { fill = 16, foot = 80, side = side }),
    piece("wall_e", { { 260, 48, 304, 80 } }, 28, { fill = 16, foot = 80, side = side }),
    piece("side_w", {}, 28, { side = side, walls = { { { 0, 144 }, { 0, 80 } } } }),
    piece("side_e", {}, 28, { side = side, walls = { { { 304, 80 }, { 304, 144 } } } }),
  }
end

-- ── the Battle Tents ───────────────────────────────────────────────────────

local TENT_FLOOR = { "b4acf6", "cdd5ff", "9c83ee" }
local TENT_WALL_SIDE = { 64, 0, 80, 32 }
local TENT_COUNTER_INNER = { { 48, 78 }, { 49, 78 }, { 49, 80 }, { 50, 80 }, { 50, 81 }, { 51, 81 }, { 51, 82 },
                             { 54, 82 }, { 54, 83 } }

local function tentLobby()
  local side = TENT_WALL_SIDE
  local mirror = {}
  for i = #TENT_COUNTER_INNER, 1, -1 do mirror[#mirror + 1] = { 208 - TENT_COUNTER_INNER[i][1], TENT_COUNTER_INNER[i][2] } end
  return {
    piece("machine", { { 176, 56, 192, 88 } }, 24, { leave = TENT_FLOOR }),
    piece("counter_w", { { 32, 29, 64, 48 }, { 32, 48, 48, 96 }, { 48, 76, 96, 96 } }, 6, { leave = TENT_FLOOR,
      plan = cat({ { 32, 35 }, { 64, 35 }, { 64, 48 }, { 48, 48 } }, TENT_COUNTER_INNER,
        { { 95, 83 }, { 95, 84 }, { 96, 84 }, { 96, 96 }, { 32, 96 } }) }),
    piece("counter_e", { { 144, 29, 176, 48 }, { 160, 48, 176, 96 }, { 112, 76, 160, 96 } }, 6, { leave = TENT_FLOOR,
      plan = cat({ { 144, 35 }, { 176, 35 }, { 176, 96 }, { 112, 96 }, { 112, 84 }, { 113, 84 }, { 113, 83 } }, mirror,
        { { 160, 48 }, { 144, 48 } }) }),
    piece("wall_cw", { { 0, 0, 16, 80 } }, 32, { fill = 16, foot = 80, side = side, leave = TENT_FLOOR,
      walls = { { { 16, 80 }, { 16, 32 } } } }),
    piece("wall_ce", { { 192, 0, 208, 80 } }, 32, { fill = 16, foot = 80, side = side, leave = TENT_FLOOR,
      walls = { { { 192, 32 }, { 192, 80 } } } }),
    piece("wall", { { 16, 0, 192, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 160 }, { 0, 80 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 208, 80 }, { 208, 160 } } } }),
  }
end

local function tentRoom(w, h)
  local side = TENT_WALL_SIDE
  return {
    piece("wall", { { 0, 0, w, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, h }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { w, 32 }, { w, h } } } }),
  }
end

-- ── Slateport's Fan Club, the Harbor, Stern's Shipyard ─────────────────────────────

local SLATEPORT_FAN_FLOOR = { "ded58b", "f6eeb4", "c5bd7b" }
local SLATEPORT_FAN_RUG = { "ee836a", "cd6a6a", "ffcd94" }
local SLATEPORT_FAN_WALL = { "e6d583", "f6eecd", "9c9c8b", "a49441", "d5a46a", "000000" }
local SLATEPORT_FAN_SIDE = { 64, 8, 80, 40 }

local function slateportFanClub()
  local side = SLATEPORT_FAN_SIDE
  local wallFloor = cat(SLATEPORT_FAN_WALL, SLATEPORT_FAN_FLOOR)
  return {
    piece("plant_sw", { { 0, 150, 16, 176 } }, 26, { card = true, leave = SLATEPORT_FAN_FLOOR }),
    piece("plant_se", { { 208, 150, 224, 176 } }, 26, { card = true, leave = SLATEPORT_FAN_FLOOR }),
    piece("table", { { 80, 94, 144, 128 } }, 10, { leave = SLATEPORT_FAN_RUG, solid = true }),
    piece("plant_w", { { 48, 20, 64, 47 } }, 27, { card = true, leave = wallFloor }),
    piece("plant_e", { { 160, 20, 176, 47 } }, 27, { card = true, leave = wallFloor }),
    piece("pillar_w", { { 32, 8, 48, 45 } }, 32, { leave = SLATEPORT_FAN_FLOOR, back = 40 }),
    piece("pillar_e", { { 176, 8, 192, 45 } }, 32, { leave = SLATEPORT_FAN_FLOOR, back = 40 }),
    piece("bookcase_w", { { 0, 26, 32, 47 } }, 12, { leave = wallFloor, against = 40, side = { 6, 28, 22, 34 } }),
    piece("bookcase_e", { { 192, 17, 224, 46 } }, 18, { leave = wallFloor, against = 40, side = { 194, 19, 206, 25 } }),
    piece("wall", { { 0, 8, 224, 40 } }, 32, { fill = 16, foot = 40, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 176 }, { 0, 40 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 224, 40 }, { 224, 176 } } } }),
  }
end

local HARBOR_SEE = { "8bb4ac", "a4cdbd", "9c8b94", "628b83", "739c8b", "62627b", "526ad5", "6a83d5",
                     "29418b", "39529c", "acb494", "839473", "6a7b41", "dedec5" }
local HARBOR_BARS = { 180, 67, 212, 74 }
local HARBOR_WALL_SIDE = { 64, 0, 80, 64 }

local function harbor()
  local see = HARBOR_SEE
  return {
    piece("crate_c", { { 352, 192, 383, 239 } }, 14, { leave = see }),
    piece("crate_b", { { 320, 176, 351, 207 } }, 14, { leave = see }),
    piece("crate_a", { { 289, 160, 319, 207 } }, 14, { leave = see }),
    piece("rail_v", { { 272, 176, 280, 240 } }, 15, { through = true, leave = see, side = HARBOR_BARS }),
    piece("rail_s", { { 48, 160, 112, 176 }, { 144, 160, 288, 176 }, { 320, 160, 384, 176 } }, 15,
      { through = true, leave = see }),
    piece("rail_w", { { 48, 80, 56, 160 } }, 15, { through = true, leave = see, side = HARBOR_BARS }),
    piece("rail_n", { { 48, 64, 384, 80 } }, 15, { through = true, leave = see }),
    piece("wall", { { 0, 0, 384, 64 } }, 56, { fill = 16, foot = 64, side = HARBOR_WALL_SIDE }),
    piece("side_w", {}, 56, { side = HARBOR_WALL_SIDE, walls = { { { 0, 240 }, { 0, 64 } } } }),
    piece("side_e", {}, 56, { side = HARBOR_WALL_SIDE, walls = { { { 384, 64 }, { 384, 240 } } } }),
  }
end

local SHIPYARD_FLOOR = { "739c8b", "62627b", "628b83", "8bb4ac", "a4cdbd", "9c8b94", "acb494", "839473",
                         "6a7b41", "dedec5" }
local SHIPYARD_WALL = { "dedede", "ffffff", "8b94a4", "6a7b7b" }
local SHIPYARD_WALL_SIDE = { 64, 0, 80, 32 }

local function shipyard1f()
  local fl, side = SHIPYARD_FLOOR, SHIPYARD_WALL_SIDE
  return {
    piece("sub_nose", { { 192, 136, 224, 157 } }, 12, { leave = fl }),
    piece("capsule", { { 176, 72, 240, 136 } }, 40, { leave = fl }),
    piece("robot", { { 144, 72, 176, 120 } }, 24, { leave = fl }),
    piece("girder_n", { { 112, 64, 128, 112 } }, 44, { leave = fl }),
    piece("pillar_e", { { 240, 56, 256, 99 } }, 29, { leave = fl }),
    piece("wall_enc", { { 112, 60, 240, 96 } }, 27, { fill = 16, foot = 96, side = side }),
    piece("consoles", { { 128, 16, 176, 40 } }, 17, { back = 32, leave = fl, side = { 129, 17, 143, 21 } }),
    piece("pilaster", { { 192, 0, 208, 35 } }, 35, { back = 32, leave = fl }),
    piece("girder_w", { { 160, 144, 176, 207 } }, 59, { leave = fl }),
    piece("girder_e", { { 224, 160, 240, 207 } }, 43, { leave = fl }),
    piece("boards_sw", { { 112, 176, 160, 240 } }, 32, { leave = fl }),
    piece("boards_se", { { 288, 176, 336, 225 } }, 32, { leave = fl }),
    piece("boards_ne", { { 304, 48, 336, 113 } }, 40, { leave = fl }),
    piece("table", { { 64, 96, 96, 128 } }, 6, { leave = fl, solid = true }),
    piece("desk_n", { { 0, 66, 32, 97 } }, 10, { leave = fl, solid = true, side = { 18, 78, 30, 88 } }),
    piece("desk_m", { { 0, 114, 32, 145 } }, 10, { leave = fl, solid = true, side = { 18, 126, 30, 136 } }),
    piece("desk_s", { { 0, 162, 32, 193 } }, 10, { leave = fl, solid = true, side = { 18, 174, 30, 184 } }),
    piece("model_ship", { { 3, 24, 30, 38 } }, 10, { base = 8, leave = { SHIPYARD_WALL[3], SHIPYARD_WALL[4] } }),
    piece("desk_ship", { { 0, 37, 32, 48 } }, 8, { back = 32 }),
    piece("partition_n", { { 96, 0, 112, 146 } }, 28, { fill = 16, foot = 146, side = side, against = 32,
      walls = { { { 96, 32 }, { 96, 146 } }, { { 112, 146 }, { 112, 32 } } } }),
    piece("partition_s", { { 96, 169, 112, 240 } }, 28, { fill = 16, foot = 268, side = side,
      walls = { { { 96, 197 }, { 96, 268 } }, { { 112, 268 }, { 112, 197 } } } }),
    piece("wall", { { 0, 0, 336, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 240 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 336, 32 }, { 336, 240 } } } }),
  }
end

local SHIPYARD_PIT = { { 136, 96, 248, 192 } }

local function shipyard2f()
  local side, fl = SHIPYARD_WALL_SIDE, SHIPYARD_FLOOR
  local function desk(name, x, y)
    return piece(name, { { x, y + 10, x + 32, y + 33 } }, 10, { leave = fl, solid = true,
      side = { x + 18, y + 14, x + 30, y + 24 } })
  end
  return {
    piece("bin", { { 113, 176, 127, 192 } }, 15, { round = "lathe", leave = fl }),
    desk("desk_nw", 0, 64), desk("desk_m", 32, 112), desk("desk_s", 32, 160),
    piece("rail_s", { { 128, 192, 256, 208 } }, 15, { through = true, leave = fl }),
    piece("rail_e", { { 248, 96, 256, 192 } }, 15, { through = true, leave = fl, side = HARBOR_BARS }),
    piece("rail_w", { { 128, 160, 136, 192 } }, 15, { through = true, leave = fl, side = HARBOR_BARS }),
    piece("rail_n", { { 128, 80, 256, 96 } }, 15, { through = true, leave = fl }),
    piece("wall", { { 0, 0, 272, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 240 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 272, 32 }, { 272, 240 } } } }),
  }
end

-- a room's shell: its back wall standing on `foot`, drawn from `top`, and its side walls
local function roomShell(w, h, foot, side, top)
  foot, top = foot or 32, top or 0
  side = side or { 64, top, 80, foot }
  return {
    piece("wall", { { 0, top, w, foot } }, foot - top, { fill = 16, foot = foot, side = side }),
    piece("side_w", {}, foot - top, { side = side, walls = { { { 0, h }, { 0, foot } } } }),
    piece("side_e", {}, foot - top, { side = side, walls = { { { w, foot }, { w, h } } } }),
  }
end

-- ── the Shop tileset's mint counters, the Weather Institute, the Safari Zone ─────────

local MINT_SHOP_FLOOR = { "e69c39", "f6c539", "f6e673", "cd8320", "ac5a20" }

local function herbShop()
  return cat({
    piece("counter", { { 0, 44, 96, 63 }, { 80, 28, 96, 44 } }, 7, { leave = MINT_SHOP_FLOOR,
      plan = { { 0, 52 }, { 80, 52 }, { 80, 35 }, { 96, 35 }, { 96, 63 }, { 0, 63 } } }),
  }, roomShell(176, 128))
end

local function cyclingGate()
  return cat({
    piece("counter", { { 80, 28, 96, 63 }, { 160, 28, 176, 63 }, { 96, 44, 160, 63 } }, 7, { leave = MINT_SHOP_FLOOR,
      plan = { { 80, 35 }, { 96, 35 }, { 96, 51 }, { 160, 51 }, { 160, 35 }, { 176, 35 }, { 176, 63 }, { 80, 63 } } }),
  }, roomShell(240, 96))
end

local function safariRestHouse()
  return cat({
    piece("table", { { 49, 79, 79, 112 } }, 8, { leave = { "ded552", "bdb431", "8b8b8b" }, solid = true }),
  }, roomShell(160, 144, 64, nil, 32))
end

local INSTITUTE_SIDE = { 176, 133, 192, 160 }
local INSTITUTE_FLOOR = { "d5d5d5", "acacb4", "9c9ca4", "7b7b83" }

-- a desk a column wide under one of the lab's computers (found again at cell (x, y) // 16)
local function instituteDesk(name, x, y)
  return piece(name, { { x, y + 20, x + 16, y + 49 }, { x, y + 4, x + 2, y + 20 }, { x + 14, y + 4, x + 16, y + 20 } }, 8,
    { leave = INSTITUTE_FLOOR, back = y + 12 })
end

local function institute1f()
  local side = INSTITUTE_SIDE
  local out = {
    piece("machine", { { 4, 32, 28, 62 } }, 17, { leave = INSTITUTE_FLOOR }),
    piece("bookcases", { { 128, 16, 192, 48 } }, 20, { leave = INSTITUTE_FLOOR, against = 32 }),
  }
  for _, x in ipairs({ 176, 192, 256, 272 }) do out[#out + 1] = instituteDesk("desk_" .. x, x, 64) end
  return cat(out, {
    piece("partition_ww", { { 48, 0, 64, 99 } }, 29, { fill = 16, foot = 99, side = side, against = 32,
      walls = { { { 48, 32 }, { 48, 99 } }, { { 64, 99 }, { 64, 32 } } } }),
    piece("partition_we", { { 112, 0, 128, 99 } }, 29, { fill = 16, foot = 99, side = side, against = 32,
      walls = { { { 112, 32 }, { 112, 99 } }, { { 128, 99 }, { 128, 32 } } } }),
    piece("partition_post_w", { { 48, 121, 64, 163 } }, 29, { fill = 16, foot = 163, side = side,
      walls = { { { 48, 134 }, { 48, 163 } }, { { 64, 163 }, { 64, 134 } } } }),
    piece("partition_post_e", { { 112, 121, 128, 163 } }, 29, { fill = 16, foot = 163, side = side,
      walls = { { { 112, 134 }, { 112, 163 } }, { { 128, 163 }, { 128, 134 } } } }),
    piece("partition_s_w", { { 0, 124, 48, 160 } }, 28, { fill = 16, foot = 160, side = side }),
    piece("partition_s_e", { { 128, 124, 320, 160 } }, 28, { fill = 16, foot = 160, side = side }),
  }, roomShell(320, 208))
end

local function institute2f()
  local side = INSTITUTE_SIDE
  local out = {}
  for _, y in ipairs({ 48, 128 }) do out[#out + 1] = instituteDesk("desk_16_" .. y, 16, y) end
  return cat(out, {
    piece("bookcase_e", { { 208, 16, 240, 48 } }, 20, { leave = INSTITUTE_FLOOR, against = 32 }),
    piece("partition_n", { { 64, 0, 80, 99 } }, 29, { fill = 16, foot = 99, side = side, against = 32,
      walls = { { { 64, 32 }, { 64, 99 } }, { { 80, 99 }, { 80, 32 } } } }),
    piece("partition_s", { { 64, 112, 80, 176 } }, 29, { fill = 16, foot = 205, side = side,
      walls = { { { 64, 141 }, { 64, 205 } }, { { 80, 205 }, { 80, 141 } } } }),
  }, roomShell(320, 176))
end

local function safariEntrance()
  local side = { 64, 0, 80, 32 }
  return {
    piece("counter_e", { { 256, 104, 272, 191 }, { 272, 104, 288, 127 }, { 272, 168, 288, 191 } }, 7,
      { leave = MINT_SHOP_FLOOR,
        plan = { { 256, 111 }, { 288, 111 }, { 288, 127 }, { 272, 127 }, { 272, 175 }, { 288, 175 }, { 288, 191 }, { 256, 191 } } }),
    piece("wall", { { 0, 0, 288, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 95 }, { 0, 32 } } } }),
    piece("side_void", {}, 32, { side = side, walls = { { { 192, 224 }, { 192, 96 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 288, 32 }, { 288, 224 } } } }),
  }
end

local CABLE_SEE = { "d5d539", "62627b" }

local function cableCarStation()
  local function rail(name, shape, side)
    return piece(name, shape, 15, { through = true, leave = CABLE_SEE, side = side })
  end
  return cat({
    piece("machine", { { 192, 112, 208, 144 } }, 16, { leave = { "d5d539" } }),
    rail("rail_gap_w", { { 88, 88, 96, 120 } }, HARBOR_BARS),
    rail("rail_gap_e", { { 112, 88, 120, 120 } }, HARBOR_BARS),
    rail("rail_near_w", { { 0, 104, 88, 120 } }),
    rail("rail_near_e", { { 120, 104, 208, 120 } }),
    rail("rail_far_w", { { 0, 72, 96, 88 } }),
    rail("rail_far_e", { { 112, 72, 208, 88 } }),
  }, roomShell(208, 192))
end

-- ── Mauville's Bike Shop and Game Corner, Mossdeep's, the Mystery Events House ──────────

local BIKE_FLOOR = { "acbdac", "83948b", "d5ded5", "cdcdcd" }
local BIKE_WALL = { "eeeede", "cdcdb4", "acac8b", "947b6a", "000000" }

local function bikeShop()
  local fl = BIKE_FLOOR
  local side = { 60, 4, 76, 32 }
  local bikes = {}
  for k, y in ipairs({ 40, 56, 72, 88, 104, 120 }) do
    bikes[#bikes + 1] = piece("bike_w" .. (k - 1), { { 0, y, 26, y + 16 } }, 16, { card = true, leave = fl })
  end
  for k, r in ipairs({ { 86, 104 }, { 104, 120 }, { 120, 144 } }) do
    bikes[#bikes + 1] = piece("bike_e" .. (k - 1), { { 162, r[1], 192, r[2] } }, r[2] - r[1], { card = true, leave = fl })
  end
  return cat(bikes, {
    piece("printer", { { 32, 26, 48, 38 } }, 8, { base = 10, leave = BIKE_WALL }),
    piece("counter", { { 32, 38, 48, 69 }, { 48, 46, 80, 69 } }, 10, { leave = fl,
      plan = { { 32, 48 }, { 48, 48 }, { 48, 56 }, { 79, 56 }, { 79, 57 }, { 80, 57 }, { 80, 69 }, { 32, 69 } } }),
    piece("box", { { 80, 46, 96, 63 } }, 7, { leave = fl }),
    piece("stand_w", { { 96, 60, 128, 88 } }, 8, { leave = fl }),
    piece("stand_e", { { 160, 60, 192, 80 } }, 8, { leave = fl }),
    piece("desk_w", { { 112, 20, 144, 41 } }, 9, { leave = cat(fl, BIKE_WALL), solid = true, against = 32 }),
    piece("desk_e", { { 160, 20, 192, 41 } }, 9, { leave = cat(fl, BIKE_WALL), solid = true, against = 32 }),
    piece("shelf", { { 0, 11, 32, 46 } }, 25, { leave = fl, against = 32, side = { 4, 12, 28, 19 } }),
    piece("partition", { { 96, 4, 104, 60 } }, 28, { fill = 16, foot = 88, side = side, against = 32,
      walls = { { { 96, 32 }, { 96, 88 } }, { { 104, 88 }, { 104, 32 } } } }),
  }, roomShell(192, 144, nil, side, 4))
end

local GAME_CORNER_FLOOR = { "d55231", "f65252", "a44a41", "ac625a" }
local GAME_CORNER_WALL = { "31839c", "62accd", "bdcde6", "eee6f6", "cdcdc5", "7b7b8b", "ffffff" }

local function mauvilleGameCorner()
  local fl = GAME_CORNER_FLOOR
  local side = { 200, 0, 216, 32 }
  local plants = {}
  for k, x in ipairs({ 80, 96, 112 }) do
    plants[#plants + 1] = piece("plant_" .. (k - 1), { { x, 20, x + 16, 47 } }, 27,
      { card = true, leave = cat(fl, GAME_CORNER_WALL) })
  end
  return cat(plants, {
    piece("bin_w", { { 33, 30, 47, 48 } }, 17, { round = "lathe", leave = cat(fl, GAME_CORNER_WALL) }),
    piece("bin_e", { { 337, 65, 351, 80 } }, 15, { round = "lathe", leave = fl }),
    piece("arcade", { { 0, 18, 32, 48 } }, 14, { leave = cat(fl, GAME_CORNER_WALL), against = 32, side = { 2, 19, 14, 26 } }),
    piece("slots_w", { { 32, 80, 64, 160 } }, 10, { leave = fl, solid = true, side = { 35, 93, 36, 100 } }),
    piece("slots_e", { { 112, 80, 144, 160 } }, 10, { leave = fl, solid = true, side = { 115, 93, 116, 100 } }),
    piece("roulette_w", { { 224, 96, 256, 141 } }, 7, { leave = fl, solid = true }),
    piece("roulette_e", { { 288, 96, 320, 141 } }, 7, { leave = fl, solid = true }),
    piece("counter", { { 144, 27, 150, 28 }, { 144, 28, 151, 29 }, { 144, 29, 152, 30 },
                       { 250, 27, 256, 28 }, { 249, 28, 256, 29 }, { 248, 29, 256, 30 },
                       { 144, 30, 159, 73 }, { 241, 30, 256, 73 }, { 159, 45, 241, 73 } }, 13, { leave = fl,
      plan = { { 144, 40 }, { 150, 40 }, { 150, 41 }, { 151, 41 }, { 151, 42 }, { 152, 42 }, { 152, 43 },
               { 159, 43 }, { 159, 58 }, { 241, 58 }, { 241, 43 }, { 248, 43 }, { 248, 42 }, { 249, 42 },
               { 249, 41 }, { 250, 41 }, { 250, 40 }, { 256, 40 }, { 256, 65 }, { 249, 72 }, { 151, 72 },
               { 144, 65 } } }),
    piece("wall_e", { { 288, 0, 352, 48 } }, 30, { fill = 16, foot = 48, side = side, walls = { { { 288, 32 }, { 288, 48 } } } }),
    piece("wall", { { 0, 0, 288, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 176 }, { 0, 32 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 352, 48 }, { 352, 176 } } } }),
  })
end

local MOSSDEEP_GC_FLOOR = { "eecda4", "d5b473", "bda462", "7b839c" }
local EVENTS_FLOOR = { "8b8b8b", "b4b4a4", "73738b" }

local function mossdeepGameCorner1f()
  local fl = MOSSDEEP_GC_FLOOR
  local out = {}
  for _, x in ipairs({ 57, 73, 98, 114 }) do
    out[#out + 1] = piece("post_" .. x, { { x, 15, x + 6, 34 } }, 16, { leave = fl, against = 31 })
  end
  for _, t in ipairs({ { "w", 32 }, { "e", 112 } }) do
    out[#out + 1] = piece("table_" .. t[1], { { t[2], 93, t[2] + 32, 128 } }, 8, { leave = fl, solid = true })
  end
  return cat(out, {
    piece("counter_w", { { 32, 21, 48, 45 }, { 32, 45, 80, 62 } }, 6, { leave = fl, against = 31,
      plan = { { 32, 31 }, { 48, 31 }, { 48, 51 }, { 80, 51 }, { 80, 62 }, { 32, 62 } } }),
    piece("counter_e", { { 128, 21, 144, 45 }, { 96, 45, 144, 62 } }, 6, { leave = fl, against = 31,
      plan = { { 96, 51 }, { 128, 51 }, { 128, 31 }, { 144, 31 }, { 144, 62 }, { 96, 62 } } }),
  }, roomShell(192, 160, 31))
end

local function mysteryEventsHouse1f()
  return cat({
    piece("table", { { 114, 64, 142, 91 } }, 4, { leave = EVENTS_FLOOR, solid = true }),
  }, roomShell(176, 128))
end

-- ── the Pokemon League ──────────────────────────────────────────────────────

local E4_WALL_SIDE = { 32, 16, 48, 32 }

local function eliteFourRoom(floor)
  local side = E4_WALL_SIDE
  return {
    piece("pillar_w", { { 0, 68, 26, 147 } }, 69, { leave = floor }),
    piece("pillar_e", { { 182, 68, 208, 147 } }, 69, { leave = floor }),
    piece("wall", { { 0, 0, 208, 32 } }, 32, { fill = 16, foot = 32, side = side }),
    piece("wall_front_w", { { 0, 172, 80, 224 } }, 32, { fill = 16, foot = 224 }),
    piece("wall_front_e", { { 128, 172, 208, 224 } }, 32, { fill = 16, foot = 224 }),
    piece("side_w", {}, 32, { side = side, walls = { { { 0, 204 }, { 0, 48 } } } }),
    piece("side_e", {}, 32, { side = side, walls = { { { 208, 48 }, { 208, 204 } } } }),
  }
end

local LEAGUE_WALL_SIDE = { 112, 0, 128, 32 }
local LEAGUE_1F_OPEN = { { { 0, 174 }, { 18, 192 }, { 0, 192 } }, { { 304, 174 }, { 286, 192 }, { 304, 192 } } }
local LEAGUE_COUNTER_LEAVE = { "cdc58b", "eedea4", "de7b31", "f6b473", "bd5220" }

local function league1f()
  local side = LEAGUE_WALL_SIDE
  return {
    piece("counter_w", { { 0, 45, 95, 63 }, { 80, 25, 95, 45 } }, 7, { leave = LEAGUE_COUNTER_LEAVE,
      plan = { { 0, 52 }, { 80, 52 }, { 80, 32 }, { 95, 32 }, { 95, 61 }, { 93, 63 }, { 0, 63 } } }),
    piece("counter_e", { { 225, 45, 304, 63 }, { 225, 25, 240, 45 } }, 7, { leave = LEAGUE_COUNTER_LEAVE,
      plan = { { 225, 32 }, { 240, 32 }, { 240, 52 }, { 304, 52 }, { 304, 63 }, { 227, 63 }, { 225, 61 } } }),
    facet("corner_w", { 0, 15, 47 }, { 16, -1, 31 }, 32, { walls = { { { 0, 174 }, { 0, 47 } } }, side = side,
      cells = { { 0, 10 } } }),
    facet("corner_e", { 288, -1, 31 }, { 304, 15, 47 }, 32, { walls = { { { 304, 47 }, { 304, 174 } } }, side = side,
      cells = { { 18, 10 } } }),
    piece("wall_e", { { 160, 0, 288, 32 } }, 32, { fill = 16, side = side }),
    piece("wall", { { 16, 0, 160, 32 } }, 32, { fill = 16, side = side }),
  }
end

local LEAGUE_HALL_SIDE = { 16, 16, 32, 48 }

local function leagueHall(h, rail)
  rail = rail or 80
  local side = LEAGUE_HALL_SIDE
  local back = rail ~= 80 and rail or nil
  return {
    piece("rail_w", { { 51, rail, 64, h } }, 16, { back = back }),
    piece("rail_e", { { 112, rail, 125, h } }, 16, { back = back }),
    piece("wall", { { 0, 0, 176, 48 } }, 48, { fill = 16, foot = 48, side = side }),
    piece("side_w", {}, 48, { side = side, walls = { { { 0, h }, { 0, 48 } } } }),
    piece("side_e", {}, 48, { side = side, walls = { { { 176, 48 }, { 176, h } } } }),
  }
end

local HOF_FLOOR = { "524ab4", "524a62", "31394a" }
local HOF_WALL_SIDE = { 54, 0, 60, 29 }

local function hallOfFame()
  local side = HOF_WALL_SIDE
  local cw, ce = { { 1, 2 } }, { { 13, 2 } }
  for y = 2, 15 do cw[#cw + 1] = { 0, y }; ce[#ce + 1] = { 14, y } end
  return {
    piece("machine", { { 98, 56, 142, 88 } }, 29, { leave = HOF_FLOOR }),
    piece("wall_c", { { 88, 0, 152, 51 } }, 51, { fill = 16, foot = 51, side = side }),
    piece("wall_w", { { 16, 0, 88, 29 } }, 29, { fill = 16, foot = 29, side = side }),
    piece("wall_e", { { 152, 0, 224, 29 } }, 29, { fill = 16, foot = 29, side = side }),
    piece("side_w", {}, 29, { side = side, walls = { { { 16, 256 }, { 16, 29 } } }, cells = cw }),
    piece("side_e", {}, 29, { side = side, walls = { { { 224, 29 }, { 224, 256 } } }, cells = ce }),
  }
end

-- ── cells and runs ──────────────────────────────────────────────────────────

local function cellsRects(cells)
  local out = {}
  for i, c in ipairs(cells) do out[i] = { c[1] * 16, c[2] * 16, c[1] * 16 + 16, c[2] * 16 + 16 } end
  return out
end

-- cells from (x, y0, y1) runs, y1 inclusive
local function cellRuns(runs)
  local out = {}
  for _, r in ipairs(runs) do
    for y = r[2], r[3] do out[#out + 1] = { r[1], y } end
  end
  return out
end

-- cells as (x, y0, y1) runs down each column, y1 inclusive
local function runsOf(cells)
  local byX, xs = {}, {}
  for _, c in ipairs(cells) do
    if not byX[c[1]] then byX[c[1]] = {}; xs[#xs + 1] = c[1] end
    local l = byX[c[1]]
    l[#l + 1] = c[2]
  end
  table.sort(xs)
  local out = {}
  for _, x in ipairs(xs) do
    local ys = byX[x]
    table.sort(ys)
    local start, prev = ys[1], ys[1]
    for i = 2, #ys + 1 do
      local y = ys[i]
      if y == nil or y ~= prev + 1 then
        out[#out + 1] = { x, start, prev }
        start = y
      end
      if y ~= nil then prev = y end
    end
  end
  return out
end

-- a piece for each of runRects(runs), named by its corner; a run a single cell tall 4 px lower
-- (but for `whole`); o.side(x0, y0, x1, y1) its side, o.per(x0, y0, x1, y1) more of its options;
-- the rest of o the pieces' options
local function rectPieces(prefix, runs, height, o)
  o = o or {}
  local out = {}
  for _, r in ipairs(runRects(runs)) do
    local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
    local opts = {}
    for k, v in pairs(o) do
      if k ~= "side" and k ~= "per" and k ~= "whole" then opts[k] = v end
    end
    for k, v in pairs(o.per and o.per(x0, y0, x1, y1) or {}) do opts[k] = v end
    local h = opts.height or height
    opts.height = nil
    opts.side = o.side and o.side(x0, y0, x1, y1) or nil
    out[#out + 1] = piece(("%s_%d_%d"):format(prefix, x0 / 16, y0 / 16), { { x0, y0, x1, y1 } },
      o.whole and h or math.min(h, y1 - y0 - 4), opts)
  end
  return out
end

-- ── Lavaridge's gym ─────────────────────────────────────────────────────────

local LAVARIDGE_GYM_SIDE = { 16, 8, 32, 24 }
local LAVARIDGE_GYM_1F_RUNS = {
  { 0, 0, 1 }, { 0, 7, 8 }, { 1, 0, 1 }, { 1, 7, 8 }, { 2, 0, 1 }, { 2, 7, 8 }, { 3, 0, 1 }, { 3, 7, 8 },
  { 4, 0, 1 }, { 4, 7, 16 }, { 5, 0, 1 }, { 5, 7, 8 }, { 6, 0, 8 }, { 7, 0, 1 }, { 7, 7, 18 }, { 8, 0, 1 },
  { 8, 7, 8 }, { 9, 0, 1 }, { 9, 7, 8 }, { 10, 0, 1 }, { 10, 7, 13 }, { 11, 0, 8 }, { 12, 0, 1 },
  { 12, 7, 8 }, { 13, 0, 1 }, { 13, 7, 8 }, { 14, 0, 1 }, { 14, 7, 8 }, { 15, 0, 1 }, { 15, 7, 8 },
  { 16, 0, 13 },
}
local LAVARIDGE_GYM_B1F_RUNS = {
  { 0, 0, 1 }, { 0, 4, 5 }, { 1, 0, 1 }, { 1, 4, 5 }, { 2, 0, 1 }, { 2, 4, 5 }, { 3, 0, 1 }, { 3, 4, 5 },
  { 4, 0, 2 }, { 4, 4, 15 }, { 5, 0, 1 }, { 5, 4, 5 }, { 6, 0, 1 }, { 6, 4, 5 }, { 7, 0, 1 }, { 7, 4, 15 },
  { 8, 0, 1 }, { 8, 4, 5 }, { 9, 0, 1 }, { 9, 4, 18 }, { 10, 0, 2 }, { 10, 4, 5 }, { 11, 0, 1 },
  { 11, 4, 5 }, { 12, 0, 1 }, { 12, 4, 5 }, { 13, 0, 1 }, { 13, 4, 16 }, { 14, 0, 1 }, { 14, 4, 5 },
  { 15, 0, 1 }, { 15, 4, 5 }, { 16, 0, 1 }, { 16, 4, 5 },
}
local LAVARIDGE_GYM_1F_SIDES = { { { { 0, 304 }, { 0, 32 } }, {} },
                                 { { { 272, 224 }, { 272, 304 } }, { { 16, 14 }, { 16, 15 } } } }
local LAVARIDGE_GYM_B1F_SIDES = { { { { 0, 304 }, { 0, 32 } }, {} }, { { { 272, 32 }, { 272, 304 } }, {} } }
local LAVARIDGE_GYM_1F_CURBS = { { 11, 16, 13 }, { 5, 7, 15 } }
local LAVARIDGE_GYM_B1F_CURBS = { { 0, 4, 12 }, { 5, 7, 11 }, { 10, 13, 10 }, { 14, 17, 10 }, { 10, 13, 15 } }
local LAVARIDGE_GYM_FLOOR = { "a47b62", "c59c7b", "e6c594", "835a4a", "624a41" }

local function lavaridgeGym(runs, curbs, sides)
  local side = LAVARIDGE_GYM_SIDE
  local out = {}
  for _, c in ipairs(curbs) do
    out[#out + 1] = piece(("block_curb_%d_%d"):format(c[1], c[3]), { { c[1] * 16, c[3] * 16 + 8, c[2] * 16, c[3] * 16 + 16 } }, 7,
      { leave = LAVARIDGE_GYM_FLOOR })
  end
  out = cat(out, rectPieces("block", runs, 16, { side = function() return side end, solid = true }))
  for n, s in ipairs(sides) do
    out[#out + 1] = piece("side_" .. (n - 1), {}, 16, { side = side, walls = { s[1] }, skip = s[2] })
  end
  return out
end

-- ── Mossdeep's gym: islands in the dark ───────────────────────────────────────────

local MOSSDEEP_GYM_FLOOR = { "9c9cac", "bdb4c5", "ded5de", "000000" }

local function mossdeepGym()
  local fl = MOSSDEEP_GYM_FLOOR
  local islands = {
    { "nw", cellRuns({ { 4, 2, 3 }, { 5, 1, 3 }, { 6, 2, 2 }, { 7, 1, 3 }, { 8, 2, 3 }, { 9, 2, 7 }, { 10, 1, 7 }, { 11, 1, 2 }, { 12, 1, 4 } }) },
    { "ne", cellRuns({ { 21, 4, 5 }, { 22, 4, 6 }, { 23, 5, 6 }, { 24, 5, 6 }, { 25, 5, 6 } }) },
    { "w", cellRuns({ { 1, 18, 20 }, { 2, 18, 19 }, { 3, 18, 19 }, { 4, 18, 19 }, { 5, 18, 19 }, { 6, 16, 19 }, { 7, 16, 17 }, { 8, 16, 17 }, { 9, 16, 17 } }) },
    { "sw", cellRuns({ { 1, 27, 28 }, { 2, 26, 28 }, { 3, 26, 27 }, { 4, 26, 28 }, { 5, 27, 28 }, { 6, 27, 30 }, { 7, 28, 29 }, { 8, 28, 31 }, { 9, 30, 31 } }) },
    { "s", cellRuns({ { 11, 31, 32 }, { 12, 30, 32 }, { 13, 30, 31 } }) },
    { "se", cellRuns({ { 15, 32, 33 }, { 16, 32, 33 }, { 17, 32, 33 }, { 18, 32, 33 }, { 19, 32, 33 }, { 20, 31, 33 }, { 21, 30, 32 }, { 22, 29, 31 }, { 23, 29, 30 } }) },
    { "e", cellRuns({ { 20, 20, 23 }, { 21, 20, 21 }, { 22, 18, 21 }, { 23, 19, 19 }, { 24, 18, 21 }, { 25, 20, 21 } }) },
  }
  local out = {}
  for _, isl in ipairs(islands) do
    out = cat(out, rectPieces("walls_" .. isl[1], runsOf(isl[2]), 24, { leave = fl,
      side = function(x0, y0, x1, y1) return { x0 + 4, y1 - 16, x0 + 10, y1 - 10 } end }))
  end
  for _, c in ipairs({ { 5, 7 }, { 8, 7 }, { 8, 8 }, { 3, 21 }, { 7, 19 }, { 9, 19 } }) do
    out[#out + 1] = piece(("box_%d_%d"):format(c[1], c[2]), cellsRects({ c }), 8, { leave = fl, solid = true })
  end
  out[#out + 1] = piece("sofa", cellsRects({ { 22, 7 }, { 23, 7 }, { 24, 7 }, { 25, 7 }, { 22, 8 }, { 25, 8 } }), 12, { leave = fl })
  return out
end

-- ── Fortree's gym: green columns on a grass floor ───────────────────────────────────

local FORTREE_GYM_FLOOR = { "b4bd5a", "dede8b", "f6f6bd" }
local FORTREE_GYM_COLUMNS_A = {
  { 0, 24 }, { 1, 11 }, { 1, 12 }, { 1, 15 }, { 1, 16 }, { 1, 17 }, { 1, 18 }, { 1, 19 }, { 1, 20 }, { 1, 21 },
  { 1, 22 }, { 1, 23 }, { 1, 24 }, { 2, 9 }, { 2, 10 }, { 2, 11 }, { 2, 12 }, { 2, 15 }, { 2, 16 }, { 2, 22 },
  { 2, 23 }, { 2, 24 }, { 3, 7 }, { 3, 9 }, { 3, 10 }, { 3, 13 }, { 3, 14 }, { 3, 15 }, { 3, 16 }, { 3, 23 },
  { 3, 24 }, { 4, 6 }, { 4, 7 }, { 4, 9 }, { 4, 10 }, { 4, 13 }, { 4, 24 }, { 5, 10 }, { 5, 11 }, { 5, 12 },
  { 5, 13 }, { 5, 14 }, { 5, 15 }, { 5, 21 }, { 5, 24 }, { 6, 2 }, { 6, 3 }, { 6, 5 }, { 6, 6 }, { 6, 12 },
  { 6, 13 }, { 6, 14 }, { 6, 15 }, { 6, 20 }, { 6, 21 }, { 6, 24 }, { 7, 2 }, { 7, 3 }, { 7, 5 }, { 7, 6 },
  { 7, 11 }, { 7, 20 }, { 7, 24 }, { 8, 2 }, { 8, 3 }, { 8, 5 }, { 8, 6 }, { 8, 7 }, { 8, 8 }, { 8, 11 },
  { 8, 20 }, { 8, 23 }, { 8, 24 }, { 9, 2 }, { 9, 3 }, { 9, 5 }, { 9, 6 }, { 9, 7 }, { 9, 20 }, { 9, 23 },
  { 9, 24 }, { 10, 2 }, { 10, 5 }, { 10, 6 }, { 10, 7 }, { 10, 8 }, { 10, 11 }, { 10, 12 }, { 10, 13 },
  { 10, 14 }, { 10, 15 }, { 10, 16 }, { 10, 17 }, { 10, 18 }, { 10, 19 }, { 10, 20 }, { 10, 21 }, { 10, 23 },
  { 10, 24 }, { 11, 5 }, { 11, 6 }, { 11, 7 }, { 11, 10 }, { 11, 13 }, { 11, 16 }, { 11, 19 }, { 11, 20 },
  { 11, 23 }, { 11, 24 }, { 12, 5 }, { 12, 6 }, { 12, 7 }, { 12, 8 }, { 12, 9 }, { 12, 10 }, { 12, 11 },
  { 12, 12 }, { 12, 13 }, { 12, 14 }, { 12, 15 }, { 12, 16 }, { 12, 17 }, { 12, 18 }, { 12, 19 }, { 12, 20 },
  { 12, 23 }, { 12, 24 }, { 13, 24 }, { 14, 24 }, { 17, 24 }, { 19, 24 },
}
local FORTREE_GYM_COLUMNS_B = {
  { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 }, { 0, 7 }, { 0, 8 }, { 0, 9 }, { 0, 10 }, { 0, 11 }, { 0, 12 }, { 0, 13 },
  { 0, 14 }, { 0, 15 }, { 0, 16 }, { 0, 17 }, { 0, 18 }, { 0, 19 }, { 0, 20 }, { 0, 21 }, { 0, 22 }, { 0, 23 },
  { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 }, { 1, 14 }, { 2, 14 }, { 3, 12 }, { 4, 12 }, { 6, 11 }, { 11, 9 }, { 11, 12 },
  { 11, 15 }, { 11, 18 }, { 18, 3 }, { 18, 4 }, { 18, 5 }, { 18, 6 }, { 18, 7 }, { 18, 8 }, { 18, 9 }, { 18, 10 },
  { 18, 11 }, { 18, 12 }, { 18, 13 }, { 18, 14 }, { 18, 15 }, { 18, 16 }, { 18, 17 }, { 18, 18 }, { 18, 19 },
  { 18, 20 }, { 18, 21 }, { 18, 22 }, { 18, 23 }, { 18, 24 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 }, { 19, 8 },
  { 19, 9 }, { 19, 10 }, { 19, 11 }, { 19, 12 }, { 19, 13 }, { 19, 14 }, { 19, 15 }, { 19, 16 }, { 19, 17 },
  { 19, 18 }, { 19, 19 }, { 19, 20 }, { 19, 21 }, { 19, 22 }, { 19, 23 },
}
local FORTREE_GYM_SMALL = { { 3, 3, 7 }, { 3, 18, 18 }, { 5, 19, 21 }, { 6, 17, 17 }, { 6, 19, 21 }, { 7, 19, 20 },
                            { 8, 13, 13 }, { 8, 17, 20 }, { 9, 15, 20 } }

local function fortreeGym()
  local fl = cat(FORTREE_GYM_FLOOR, { "7b839c" })
  -- a column `height` tall drawn whole at `ref`, standing again at every one of `cells`, each
  -- textured as drawn there; a copy stands by the cell its top is in
  local function columns(name, cells, ref, height)
    local top = -height
    local dy = math.floor(top / 16)
    local seen, at = {}, {}
    for _, c in ipairs(cells) do
      local k = c[1] * 4096 + c[2]
      if not seen[k] and not (c[1] == ref[1] and c[2] == ref[2]) then seen[k] = true; at[#at + 1] = { c[1], c[2] } end
    end
    table.sort(at, function(a, b)
      if a[1] ~= b[1] then return a[1] < b[1] end
      return a[2] < b[2]
    end)
    for i, c in ipairs(at) do at[i] = { c[1], c[2] + dy } end
    local rx, ry = ref[1], ref[2]
    return piece(name, { { rx * 16, ry * 16 + top, rx * 16 + 16, ry * 16 + 16 } }, height,
      { round = "lathe", squash = 1.0, turn = { 8, 1 }, leave = fl, variants = true, at = at })
  end
  local out = { columns("column", FORTREE_GYM_COLUMNS_A, { 7, 11 }, 6),
                columns("column_tall", FORTREE_GYM_COLUMNS_B, { 18, 24 }, 14) }
  for _, s in ipairs(FORTREE_GYM_SMALL) do
    out[#out + 1] = piece(("small_%d_%d"):format(s[1], s[2]), { { s[1] * 16, s[2] * 16, s[1] * 16 + 16, s[3] * 16 + 16 } }, 5,
      { round = "lathe", posts = { 8, 8 }, turn = { 6, 1 }, leave = fl })
  end
  for _, y in ipairs({ 6, 12, 17 }) do
    out[#out + 1] = piece("rail_" .. y, { { 208, y * 16, 288, y * 16 + 16 } }, 4, { leave = fl, solid = true })
  end
  out[#out + 1] = piece("wall", { { 0, 0, 320, 32 } }, 32, { fill = 16, foot = 32, side = { 32, 0, 48, 32 } })
  return out
end

-- ── Sootopolis's gym ────────────────────────────────────────────────────────

local SOOTOPOLIS_GYM_ICE = { "5abdd5", "83cdde", "acdee6", "d5eeee" }
local SOOTOPOLIS_GYM_1F_WALLS = {
  { { 0, 0, 25 }, { 1, 0, 11 }, { 1, 18, 20 }, { 2, 0, 11 }, { 2, 18, 20 } },
  { { 3, 0, 1 }, { 3, 4, 5 }, { 3, 10, 15 }, { 3, 18, 25 }, { 4, 0, 2 }, { 4, 4, 5 }, { 4, 10, 15 },
    { 4, 18, 25 }, { 5, 0, 2 }, { 5, 4, 5 }, { 5, 10, 11 }, { 5, 15, 21 } },
  { { 6, 0, 1 }, { 6, 4, 5 }, { 6, 10, 11 }, { 6, 15, 21 }, { 7, 0, 1 }, { 7, 4, 5 }, { 7, 10, 11 },
    { 7, 15, 16 }, { 7, 20, 21 }, { 8, 0, 1 } },
  { { 9, 0, 1 }, { 9, 4, 5 }, { 9, 10, 11 }, { 9, 15, 16 }, { 9, 20, 21 }, { 10, 0, 1 }, { 10, 4, 5 },
    { 10, 10, 11 }, { 10, 15, 21 }, { 11, 0, 2 }, { 11, 4, 5 }, { 11, 10, 11 }, { 11, 15, 21 } },
  { { 12, 0, 2 }, { 12, 4, 5 }, { 12, 10, 15 }, { 12, 18, 25 }, { 13, 0, 1 }, { 13, 4, 5 }, { 13, 10, 15 },
    { 13, 18, 25 }, { 14, 0, 11 }, { 14, 18, 20 } },
  { { 15, 0, 11 }, { 15, 18, 20 }, { 16, 2, 3 }, { 16, 9, 11 }, { 16, 14, 15 }, { 16, 18, 20 } },
}
local SOOTOPOLIS_GYM_ROCKS = { { 4, 8 }, { 6, 13 }, { 7, 8 }, { 9, 7 }, { 9, 19 }, { 10, 13 }, { 11, 9 }, { 12, 7 } }
local SOOTOPOLIS_GYM_B1F_WALLS = {
  { { 0, 4, 11 }, { 0, 14, 16 }, { 0, 18, 20 }, { 1, 4, 11 }, { 1, 14, 16 }, { 1, 18, 20 }, { 2, 4, 5 },
    { 2, 10, 16 }, { 2, 18, 20 } },
  { { 3, 4, 5 }, { 3, 10, 16 }, { 3, 18, 25 }, { 4, 4, 5 }, { 4, 10, 11 }, { 4, 15, 25 }, { 5, 4, 5 },
    { 5, 10, 11 }, { 5, 15, 16 }, { 5, 19, 21 } },
  { { 6, 4, 5 }, { 6, 10, 11 }, { 6, 15, 21 }, { 7, 4, 5 }, { 7, 10, 11 }, { 7, 15, 16 }, { 7, 20, 21 },
    { 8, 4, 5 } },
  { { 9, 4, 5 }, { 9, 10, 11 }, { 9, 15, 16 }, { 9, 20, 21 }, { 10, 4, 5 }, { 10, 10, 11 }, { 10, 15, 21 },
    { 11, 4, 5 }, { 11, 10, 11 }, { 11, 15, 16 }, { 11, 19, 20 } },
  { { 12, 4, 5 }, { 12, 10, 11 }, { 12, 15, 25 }, { 13, 4, 5 }, { 13, 10, 16 }, { 13, 18, 25 },
    { 14, 4, 5 }, { 14, 10, 16 }, { 14, 18, 20 } },
  { { 15, 4, 11 }, { 15, 14, 16 }, { 15, 18, 20 }, { 16, 4, 11 }, { 16, 14, 16 }, { 16, 18, 20 } },
}
local SOOTOPOLIS_GYM_1F_TIERS = { 4, 10, 15, 20 }
local SOOTOPOLIS_GYM_B1F_TIERS = { 10, 15, 20 }

-- `per` for a tier's walls: a wall rising from one tier to the next leaves its top's row to the
-- map; a run whose foot is a tier's first row stands a level taller
local function tierTops(tiers)
  local isTier = {}
  for _, t in ipairs(tiers) do isTier[t] = true end
  return function(x0, y0, x1, y1)
    local out = {}
    if isTier[math.floor(y0 / 16)] and y1 - y0 > 16 then
      out.skip = {}
      for x = x0 / 16, x1 / 16 - 1 do out.skip[#out.skip + 1] = { x, y0 / 16 } end
    end
    if isTier[math.floor(y1 / 16) - 1] and y1 - y0 > 16 then out.height = 32 end
    return out
  end
end

-- (x, y0, y1) runs cut before each of `rows`
local function cutRuns(runs, rows)
  local sorted = {}
  for i, r in ipairs(rows) do sorted[i] = r end
  table.sort(sorted)
  local out = {}
  for _, run in ipairs(runs) do
    local x, y0, y1 = run[1], run[2], run[3]
    for _, r in ipairs(sorted) do
      if y0 < r and r < y1 then
        out[#out + 1] = { x, y0, r - 1 }
        y0 = r
      end
    end
    out[#out + 1] = { x, y0, y1 }
  end
  return out
end

local function flatRuns(groups)
  local out = {}
  for _, g in ipairs(groups) do
    for _, r in ipairs(g) do out[#out + 1] = r end
  end
  return out
end

local function sootopolisGym1f()
  local walls = rectPieces("walls", cutRuns(flatRuns(SOOTOPOLIS_GYM_1F_WALLS), SOOTOPOLIS_GYM_1F_TIERS), 16,
    { leave = SOOTOPOLIS_GYM_ICE, whole = true, per = tierTops(SOOTOPOLIS_GYM_1F_TIERS) })
  for _, c in ipairs(SOOTOPOLIS_GYM_ROCKS) do
    walls[#walls + 1] = piece(("rock_%d_%d"):format(c[1], c[2]), cellsRects({ c }), 10, { leave = SOOTOPOLIS_GYM_ICE })
  end
  return walls
end

local function sootopolisGymB1f()
  return rectPieces("wall", cutRuns(flatRuns(SOOTOPOLIS_GYM_B1F_WALLS), SOOTOPOLIS_GYM_B1F_TIERS), 16,
    { leave = { "acdee6", "d5eeee", "ffffff", "000000" }, solid = true,
      side = function() return "cell" end, whole = true, per = tierTops(SOOTOPOLIS_GYM_B1F_TIERS) })
end

-- ── the Battle Frontier's lobbies ───────────────────────────────────────────────

-- (layout, width, height, the back wall's foot, floor)
local FRONTIER_LOBBIES = {
  arena = { "LAYOUT_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY", 256, 208, 48, 0x202 },
  dome = { "LAYOUT_BATTLE_FRONTIER_BATTLE_DOME_LOBBY", 368, 272, 80, 0x340 },
  factory = { "LAYOUT_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY", 304, 192, 80, 0x201 },
  palace = { "LAYOUT_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY", 400, 192, 80, 0x201 },
  pike = { "LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY", 176, 208, 64, 0x2c2 },
  pyramid = { "LAYOUT_BATTLE_FRONTIER_BATTLE_PYRAMID_LOBBY", 240, 288, 80, 0x20b },
  tower = { "LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY", 400, 160, 32, 0x200 },
}

local function frontierTowerLobby()
  local out = {}
  for _, c in ipairs({ 4, 8, 12, 16 }) do
    local x = c * 16
    out[#out + 1] = piece("divider_" .. c, { { x, 22, x + 16, 68 } }, 10)
    out[#out + 1] = piece("terminal_" .. c, { { x, 68, x + 16, 96 } }, 18)
    out[#out + 1] = piece(("counter_%d_e"):format(c), { { x + 16, 76, x + 32, 96 } }, 10)
    if c > 4 then out[#out + 1] = piece(("counter_%d_w"):format(c), { { x - 16, 76, x, 96 } }, 10) end
  end
  out[#out + 1] = piece("divider_20", { { 320, 22, 336, 96 } }, 10)
  out[#out + 1] = piece("counter_20_w", { { 304, 76, 320, 96 } }, 10)
  return out
end

local DOME_FLOOR = { "8bcdac", "9ceecd", "7bac8b" }
local DOME_ARM_TOP = { 134, 132, 130, 128, 126, 124, 122, 120, 114, 113, 112, 112, 112, 112, 112, 112, 112,
                       112, 112, 112, 112, 112, 113, 114 }

local function domeCounterArm()
  local plan = { { 32, 176 } }
  for i, top in ipairs(DOME_ARM_TOP) do
    local i0 = i - 1
    for _, pt in ipairs({ { 32 + i0, top + 6 }, { 33 + i0, top + 6 } }) do
      local last, prev = plan[#plan], plan[#plan - 1]
      if #plan > 1 and last[2] == pt[2] and pt[2] == prev[2] then
        plan[#plan] = pt
      elseif not (pt[1] == last[1] and pt[2] == last[2]) then
        plan[#plan + 1] = pt
      end
    end
  end
  return cat(plan, { { 56, 166 }, { 64, 166 }, { 64, 176 } })
end

local function frontierDomeLobby()
  local function ropes(name, x0, y0, y1)
    return piece(name, { { x0, y0, x0 + 32, y1 } }, y1 - y0, { card = true, leave = DOME_FLOOR })
  end
  local arm = domeCounterArm()
  local mirrored = {}
  for i = #arm, 1, -1 do mirrored[#mirrored + 1] = { 368 - arm[i][1], arm[i][2] } end
  return {
    piece("terminal_w", { { 64, 148, 80, 176 } }, 22),
    piece("terminal_red", { { 112, 148, 128, 176 } }, 22),
    piece("monitor", { { 232, 144, 264, 176 } }, 24),
    piece("terminal_e", { { 288, 148, 304, 176 } }, 22),
    piece("counter_w", { { 32, 112, 64, 176 } }, 6, { leave = DOME_FLOOR, plan = arm }),
    piece("counter_e", { { 304, 112, 336, 176 } }, 6, { leave = DOME_FLOOR, plan = mirrored }),
    piece("counter_mid_w1", { { 96, 148, 112, 176 } }, 6, { leave = DOME_FLOOR }),
    piece("counter_mid_w2", { { 128, 148, 144, 176 } }, 6, { leave = DOME_FLOOR }),
    piece("counter_mid_e1", { { 224, 148, 232, 176 } }, 6, { leave = DOME_FLOOR }),
    piece("counter_mid_e2", { { 264, 148, 272, 176 } }, 6, { leave = DOME_FLOOR }),
    ropes("ropes_w", 0, 158, 176),
    ropes("ropes_mw1", 144, 126, 144),
    ropes("ropes_mw2", 144, 158, 176),
    ropes("ropes_me1", 192, 126, 144),
    ropes("ropes_me2", 192, 158, 176),
    ropes("ropes_e", 336, 158, 176),
  }
end

local function frontierFactoryLobby()
  return {
    piece("divider_2", { { 32, 72, 48, 100 } }, 10),
    piece("terminal_2", { { 32, 100, 48, 128 } }, 18),
    piece("counter_3", { { 48, 108, 64, 128 } }, 10),
    piece("counter_5", { { 80, 108, 112, 128 } }, 10),
    piece("divider_7", { { 112, 72, 128, 128 } }, 10),
    piece("divider_11", { { 176, 72, 192, 128 } }, 10),
    piece("counter_12", { { 192, 108, 224, 128 } }, 10),
    piece("counter_15", { { 240, 108, 256, 128 } }, 10),
    piece("divider_16", { { 256, 72, 272, 100 } }, 10),
    piece("terminal_16", { { 256, 100, 272, 128 } }, 18),
    piece("bin_15", { { 240, 166, 256, 192 } }, 16),
    piece("bin_17", { { 272, 166, 288, 192 } }, 16),
  }
end

local PALACE_FLOOR = { "a46283", "bd8ba4", "944162" }

local function frontierPalaceLobby()
  local out = {}
  for _, s in ipairs({ { "w", 0 }, { "e", 224 } }) do
    local side, dx = s[1], s[2]
    out[#out + 1] = piece("terminal_" .. side, { { 32 + dx, 108, 48 + dx, 136 } }, 28, { card = true, leave = PALACE_FLOOR })
    out[#out + 1] = piece(("table_%s1"):format(side), { { 32 + dx, 80, 56 + dx, 118 } }, 6, { leave = PALACE_FLOOR })
    out[#out + 1] = piece(("table_%s2"):format(side), { { 56 + dx, 96, 80 + dx, 118 } }, 6, { leave = PALACE_FLOOR })
    out[#out + 1] = piece(("table_%s3"):format(side), { { 96 + dx, 96, 120 + dx, 118 } }, 6, { leave = PALACE_FLOOR })
    out[#out + 1] = piece(("table_%s4"):format(side), { { 120 + dx, 80, 144 + dx, 118 } }, 6, { leave = PALACE_FLOOR })
  end
  return out
end

local PIKE_CURTAIN = { "c50000", "ff0000", "7b3100", "523131", "ff9462" }
local PIKE_FLOOR = { "7b6a31", "a48b31", "cdac31" }

local function frontierPikeLobby()
  local out = { piece("terminal", { { 128, 44, 144, 72 } }, 28, { card = true, leave = cat(PIKE_CURTAIN, PIKE_FLOOR) }) }
  for _, c in ipairs({ { 3, 4 }, { 7, 4 }, { 4, 5 }, { 6, 5 }, { 1, 7 }, { 9, 7 }, { 0, 8 }, { 3, 8 }, { 7, 8 }, { 10, 8 },
                       { 1, 10 }, { 9, 10 }, { 3, 12 }, { 7, 12 } }) do
    out[#out + 1] = piece(("pillar_%d_%d"):format(c[1], c[2]), { { c[1] * 16, c[2] * 16 - 15, c[1] * 16 + 16, c[2] * 16 + 16 } }, 21)
  end
  return out
end

local function frontierArenaLobby()
  return {
    piece("terminal", { { 80, 128, 96, 160 } }, 24),
    piece("television", { { 0, 92, 48, 128 } }, 28),
    piece("plant_12", { { 192, 96, 208, 128 } }, 24),
    piece("plant_14", { { 224, 96, 240, 128 } }, 24),
    piece("plant_sw", { { 0, 160, 16, 192 } }, 24),
    piece("shelf_e", { { 240, 96, 256, 208 } }, 16),
  }
end

local function frontierPyramidLobby()
  return {
    piece("pillar_w", { { 32, 0, 48, 104 } }, 80),
    piece("pillar_e", { { 192, 0, 208, 104 } }, 80),
    piece("brazier_w", { { 64, 72, 80, 96 } }, 20),
    piece("brazier_e", { { 160, 72, 176, 96 } }, 20),
  }
end

local FRONTIER_LOBBY_PIECES = { arena = frontierArenaLobby, dome = frontierDomeLobby, factory = frontierFactoryLobby,
                                palace = frontierPalaceLobby, pike = frontierPikeLobby, pyramid = frontierPyramidLobby,
                                tower = frontierTowerLobby }
local FRONTIER_LOBBY_SIDES = { factory = { 96, 0, 112, 80 }, palace = { 128, 0, 144, 80 }, tower = { 112, 0, 128, 32 } }

local function frontierLobby(name)
  local l = FRONTIER_LOBBIES[name]
  local own = FRONTIER_LOBBY_PIECES[name]
  return cat(own and own() or {}, roomShell(l[2], l[3], l[4], FRONTIER_LOBBY_SIDES[name]))
end

-- a room's two bottom corner cells the GBA leaves black, as `open`
local function frontCorners(w, h)
  return { { { 0, h - 16 }, { 16, h - 16 }, { 16, h }, { 0, h } },
           { { w - 16, h - 16 }, { w, h - 16 }, { w, h }, { w - 16, h } } }
end

-- the contest stage: its pieces stand on every stage drawn again, in the five coloured halls and
-- three times in Lilycove's
add("contest_stage", "LAYOUT_CONTEST_HALL", { 0x271, 0x225 }, ownShell(contestStage()))
add("contest_lobby", "LAYOUT_LILYCOVE_CITY_CONTEST_LOBBY", { 0x260 }, ownShell(contestLobby()))
add("lilycove_contest_room", "LAYOUT_LILYCOVE_CITY_CONTEST_HALL", { 0x260 }, ownShell(lilycoveContestRoom()))
add("dept_store_1f", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_1F", { 0x268 }, ownShell(deptStore1f()))
add("dept_store_2f", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_2F", { 0x201 }, ownShell(deptStore2f()))
add("dept_store_3f", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_3F", { 0x201 }, ownShell(deptStore3f()))
add("dept_store_4f", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_4F", { 0x201 }, ownShell(deptStore4f()))
add("dept_store_5f", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_5F", { 0x2f2 }, ownShell(deptStore5f()))
add("dept_store_elevator", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_ELEVATOR", { 0x265 }, ownShell(deptStoreElevator()))
add("dept_store_rooftop", "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_ROOFTOP", { 0x24a }, deptStoreRooftop())
add("museum_1f", "LAYOUT_LILYCOVE_CITY_LILYCOVE_MUSEUM_1F", { 0x202 }, ownShell(museum1f()))
add("museum_2f", "LAYOUT_LILYCOVE_CITY_LILYCOVE_MUSEUM_2F", { 0x268 }, ownShell(museum2f()))
add("trainer_fan_club", "LAYOUT_LILYCOVE_CITY_POKEMON_TRAINER_FAN_CLUB", { 0x223 }, ownShell(trainerFanClub()))
add("lanettes_house", "LAYOUT_ROUTE114_LANETTES_HOUSE", { 0x202 }, ownShell(lanettesHouse()))
add("day_care", "LAYOUT_ROUTE117_POKEMON_DAY_CARE", { 0x201 }, ownShell(dayCare()))
add("seashore_house", "LAYOUT_ROUTE109_SEASHORE_HOUSE", { 0x225 }, ownShell(seashoreHouse()))
add("devon_corp_1f", "LAYOUT_RUSTBORO_CITY_DEVON_CORP_1F", { 0x380 }, ownShell(devonCorp1f()))
-- the Battle Tents (Slateport, Verdanturf, Fallarbor)
add("tent_lobby", "LAYOUT_BATTLE_TENT_LOBBY", { 0x210 }, ownShell(tentLobby()))
add("tent_corridor", "LAYOUT_BATTLE_TENT_CORRIDOR", { 0x23b }, ownShell(tentRoom(80, 128)))
add("tent_battle_room", "LAYOUT_BATTLE_TENT_BATTLE_ROOM", { 0x210 }, ownShell(tentRoom(160, 144)))
add("verdanturf_tent_battle_room", "LAYOUT_VERDANTURF_TOWN_BATTLE_TENT_BATTLE_ROOM", { 0x1 }, ownShell(tentRoom(208, 144)))
add("slateport_fan_club", "LAYOUT_SLATEPORT_CITY_POKEMON_FAN_CLUB", { 0x201 }, ownShell(slateportFanClub()))
add("harbor", "LAYOUT_HARBOR", { 0x202 }, ownShell(harbor()))
add("shipyard_1f", "LAYOUT_SLATEPORT_CITY_STERNS_SHIPYARD_1F", { 0x229 }, ownShell(shipyard1f()))
add("shipyard_2f", "LAYOUT_SLATEPORT_CITY_STERNS_SHIPYARD_2F", { 0x202 }, ownShell(shipyard2f()), { pit = SHIPYARD_PIT })
add("herb_shop", "LAYOUT_LAVARIDGE_TOWN_HERB_SHOP", { 0x268 }, ownShell(herbShop()))
add("cycling_gate_room", "LAYOUT_ROUTE110_SEASIDE_CYCLING_ROAD_ENTRANCE", { 0x268 }, ownShell(cyclingGate()))
add("safari_rest_house", "LAYOUT_SAFARI_ZONE_REST_HOUSE", { 0x223 }, ownShell(safariRestHouse()))
add("institute_1f", "LAYOUT_ROUTE119_WEATHER_INSTITUTE_1F", { 0x252 }, ownShell(institute1f()))
add("institute_2f", "LAYOUT_ROUTE119_WEATHER_INSTITUTE_2F", { 0x252 }, ownShell(institute2f()))
add("safari_entrance", "LAYOUT_ROUTE121_SAFARI_ZONE_ENTRANCE", { 0x268 }, ownShell(safariEntrance()))
add("cable_car_room", "LAYOUT_CABLE_CAR_STATION", { 0x2f0 }, ownShell(cableCarStation()))
add("bike_shop", "LAYOUT_MAUVILLE_CITY_BIKE_SHOP", { 0x23f }, ownShell(bikeShop()))
add("game_corner_room", "LAYOUT_MAUVILLE_CITY_GAME_CORNER", { 0x202 }, ownShell(mauvilleGameCorner()))
add("mossdeep_game_corner_1f", "LAYOUT_MOSSDEEP_CITY_GAME_CORNER_1F", { 0x20a }, ownShell(mossdeepGameCorner1f()))
add("mossdeep_game_corner_b1f", "LAYOUT_MOSSDEEP_CITY_GAME_CORNER_B1F", { 0x223 }, ownShell(roomShell(192, 144, 31)))
add("mystery_events_house_1f", "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F", { 0x235 }, ownShell(mysteryEventsHouse1f()))
-- while a Frontier trainer visits, the map's script opens the stairs down (setmaplayoutindex)
add("mystery_events_house_1f_open", "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F_STAIRS_UNBLOCKED", { 0x235 },
  ownShell(roomShell(176, 128)))
add("mystery_events_house_b1f", "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_B1F", { 0x235 }, ownShell(roomShell(192, 144, 31)))
add("sidneys_room", "LAYOUT_EVER_GRANDE_CITY_SIDNEYS_ROOM", { 0x22c }, ownShell(eliteFourRoom({ "c59462", "cda473" })))
add("phoebes_room", "LAYOUT_EVER_GRANDE_CITY_PHOEBES_ROOM", { 0x25c }, ownShell(eliteFourRoom({ "a47bac", "b48bbd" })))
add("glacias_room", "LAYOUT_EVER_GRANDE_CITY_GLACIAS_ROOM", { 0x28c }, ownShell(eliteFourRoom({ "bdc5ff", "cdd5ff" })))
add("drakes_room", "LAYOUT_EVER_GRANDE_CITY_DRAKES_ROOM", { 0x2bc }, ownShell(eliteFourRoom({ "e67341", "ff7341" })))
add("league_1f", "LAYOUT_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F", { 0x240 }, ownShell(league1f()), { open = LEAGUE_1F_OPEN })
-- the four halls between the Elite Four's rooms
add("league_hall", "LAYOUT_EVER_GRANDE_CITY_SHORT_HALL", { 0x2d1 }, ownShell(leagueHall(208)))
add("league_hall4", "LAYOUT_EVER_GRANDE_CITY_HALL4", { 0x2d1 }, ownShell(leagueHall(544, 208)))
add("hall_of_fame", "LAYOUT_EVER_GRANDE_CITY_HALL_OF_FAME", { 0x2f6 }, ownShell(hallOfFame()))
-- Mauville's gym: the blocks either side of the corridor, the back wall, the coils (one drawn
-- whole standing for the others) and the puzzle's beams, each standing only while its cell holds
-- its lit metatile, its texels the electric gates' tiles (tileset_anims.c, secondary 144-159)
local MAUVILLE_GYM_SIDE = { 0, 120, 16, 142 }
local MAUVILLE_GYM_FLOOR = { "f6f6ac", "cdcd83", "f6e641", "ffff10", "b4b483", "dec541" }
local MAUVILLE_GYM_COILS = { { 0, 10 }, { 6, 13 }, { 9, 10 }, { 3, 7 }, { 3, 6 }, { 6, 6 }, { 3, 5 }, { 6, 5 } }
local MAUVILLE_GYM_POLE_TOP = { 0x251, 0x250 }     -- PoleTop_Off, PoleTop_On
local MAUVILLE_GYM_BEAM_TILES = { 512 + 144, 512 + 159 }
local MAUVILLE_GYM_GREEN_H, MAUVILLE_GYM_RED_H = 0x220, 0x222
local MAUVILLE_GYM_GREEN_V, MAUVILLE_GYM_RED_V = 0x248, 0x249
-- the barriers' other state (MauvilleCity_Gym_EventScript_SetAltBarriers)
local MAUVILLE_GYM_ALT = {
  { 3, 11, 0x241 }, { 3, 12, 0x249 }, { 3, 13, 0x250 },
  { 4, 10, 0x222 }, { 5, 10, 0x223 }, { 4, 11, 0x22A }, { 5, 11, 0x22B },
  { 7, 10, 0x222 }, { 8, 10, 0x223 }, { 7, 11, 0x22A }, { 8, 11, 0x22B },
  { 4, 13, 0x230 }, { 5, 13, 0x231 }, { 4, 14, 0x238 }, { 5, 14, 0x239 },
  { 1, 10, 0x230 }, { 2, 10, 0x231 }, { 1, 11, 0x238 }, { 2, 11, 0x239 },
  { 6, 8, 0x242 }, { 6, 9, 0x21A }, { 6, 10, 0x251 },
  { 4, 6, 0x230 }, { 5, 6, 0x231 }, { 4, 7, 0x238 }, { 5, 7, 0x239 },
}

-- the horizontal beam whose top-left cell is (x, y): a sheet standing at its foot
local function mauvilleBeam(x, y, lit)
  return piece(("beam_%d_%d"):format(x, y), { { x * 16, y * 16, x * 16 + 32, y * 16 + 32 } }, 16,
    { card = true, tiles = MAUVILLE_GYM_BEAM_TILES, anim = true, when = { x, y, lit } })
end

-- the vertical beam from the coil whose foot is cell (x, y) down to the head of the next: a strip
local function mauvilleBeamDown(x, y, lit)
  local za, zb = y * 16 + 16, y * 16 + 57
  return piece(("beam_%d_%d"):format(x, y), { { x * 16, y * 16, x * 16 + 16, y * 16 + 32 } }, 1,
    { tiles = MAUVILLE_GYM_BEAM_TILES, anim = true, when = { x, y + 1, lit },
      ribbon = { { za, za - y * 16 }, { zb, zb - y * 16 - 32 } }, skip = { { x, y } } })
end

-- the coil whose head is cell (x, y), as the drawing has it (while that cell holds `head`)
local function mauvilleCoil(x, y, head)
  return piece(("coil_%d_%d"):format(x, y), { { x * 16, y * 16 + 3, x * 16 + 16, y * 16 + 32 } }, 22,
    { round = "lathe", leave = MAUVILLE_GYM_FLOOR, when = head and { x, y, head } or nil })
end

local function mauvilleGym()
  local side = MAUVILLE_GYM_SIDE
  local c0 = MAUVILLE_GYM_COILS[1]
  local copies = {}
  for i = 2, #MAUVILLE_GYM_COILS do copies[#copies + 1] = MAUVILLE_GYM_COILS[i] end
  return {
    mauvilleBeam(4, 13, MAUVILLE_GYM_GREEN_H),
    mauvilleBeam(1, 10, MAUVILLE_GYM_GREEN_H),
    mauvilleBeam(4, 6, MAUVILLE_GYM_GREEN_H),
    mauvilleBeamDown(6, 8, MAUVILLE_GYM_GREEN_V),
    piece("coil", { { c0[1] * 16, c0[2] * 16 + 3, c0[1] * 16 + 16, c0[2] * 16 + 32 } }, 22,
      { round = "lathe", leave = MAUVILLE_GYM_FLOOR, at = copies }),
    mauvilleCoil(3, 10),
    mauvilleCoil(6, 10, MAUVILLE_GYM_POLE_TOP[2]),
    mauvilleCoil(3, 13, MAUVILLE_GYM_POLE_TOP[1]),
    piece("block_w", { { 0, 0, 48, 144 } }, 24, { side = side, solid = true }),
    piece("block_e", { { 112, 0, 160, 128 } }, 24, { side = side, solid = true }),
    piece("block_se", { { 112, 200, 160, 240 } }, 24, { side = side, solid = true }),
    -- the dark either side of the entrance hall: its top is its drawing as drawn
    piece("block_hall_w", { { 0, 272, 32, 336 } }, 24, { side = side, flat = true, walls = { { { 32, 336 }, { 32, 272 } } } }),
    piece("block_hall_e", { { 128, 272, 160, 336 } }, 24, { side = side, flat = true, walls = { { { 128, 272 }, { 128, 336 } } } }),
    piece("wall", { { 48, 0, 112, 31 } }, 31, { fill = 16, foot = 31, side = side }),
    piece("side_w", {}, 24, { side = side, walls = { { { 0, 272 }, { 0, 144 } } }, skip = { { 0, 15 } } }),
    piece("side_e", {}, 24, { side = side, walls = { { { 160, 128 }, { 160, 272 } } } }),
  }
end

-- the red beams, lit in the barriers' other state, and the two coils as it draws them
local function mauvilleGymAlt()
  return {
    mauvilleBeam(4, 10, MAUVILLE_GYM_RED_H),
    mauvilleBeam(7, 10, MAUVILLE_GYM_RED_H),
    mauvilleBeamDown(3, 11, MAUVILLE_GYM_RED_V),
    mauvilleCoil(6, 10, MAUVILLE_GYM_POLE_TOP[1]),
    mauvilleCoil(3, 13, MAUVILLE_GYM_POLE_TOP[2]),
    mauvilleCoil(6, 7),
  }
end

add("mauville_gym", "LAYOUT_MAUVILLE_CITY_GYM", { 0x20a }, ownShell(mauvilleGym()))
-- its red beams, read off the room in the barriers' other state
add("mauville_gym_alt", "LAYOUT_MAUVILLE_CITY_GYM", { 0x20a }, mauvilleGymAlt(), { draw = MAUVILLE_GYM_ALT })
add("mossdeep_gym", "LAYOUT_MOSSDEEP_CITY_GYM", { 0x20a }, ownShell(mossdeepGym()))
add("fortree_gym", "LAYOUT_FORTREE_CITY_GYM", { 0x202 }, ownShell(fortreeGym()))
add("lavaridge_gym_1f", "LAYOUT_LAVARIDGE_TOWN_GYM_1F", { 0x208 },
  ownShell(lavaridgeGym(LAVARIDGE_GYM_1F_RUNS, LAVARIDGE_GYM_1F_CURBS, LAVARIDGE_GYM_1F_SIDES)), { shade = { "624a41" } })
add("lavaridge_gym_b1f", "LAYOUT_LAVARIDGE_TOWN_GYM_B1F", { 0x208 },
  ownShell(lavaridgeGym(LAVARIDGE_GYM_B1F_RUNS, LAVARIDGE_GYM_B1F_CURBS, LAVARIDGE_GYM_B1F_SIDES)), { shade = { "624a41" } })
add("sootopolis_gym_1f", "LAYOUT_SOOTOPOLIS_CITY_GYM_1F", { 0x20d }, ownShell(sootopolisGym1f()))
add("sootopolis_gym_b1f", "LAYOUT_SOOTOPOLIS_CITY_GYM_B1F", { 0x211 }, ownShell(sootopolisGymB1f()))
add("scotts_house", "LAYOUT_BATTLE_FRONTIER_SCOTTS_HOUSE", { 0x3c9 }, ownShell(roomShell(96, 128)),
  { open = frontCorners(96, 128) })
-- the lounges: two and seven of them
add("frontier_lounge1", "LAYOUT_BATTLE_FRONTIER_LOUNGE1", { 0x3c8 }, ownShell(roomShell(208, 128)),
  { open = frontCorners(208, 128) })
add("frontier_lounge2", "LAYOUT_BATTLE_FRONTIER_LOUNGE2", { 0x3c8 }, ownShell(roomShell(144, 160)),
  { open = frontCorners(144, 160) })
-- the Battle Frontier's lobbies
for _, k in ipairs({ "arena", "dome", "factory", "palace", "pike", "pyramid", "tower" }) do
  add("frontier_" .. k .. "_lobby", FRONTIER_LOBBIES[k][1], { FRONTIER_LOBBIES[k][5] }, ownShell(frontierLobby(k)))
end
add("treasure_house", "LAYOUT_ROUTE124_DIVING_TREASURE_HUNTERS_HOUSE", { 0x223 }, ownShell(roomShell(160, 144)))
-- the coloured stages: the same room, its stairs and emblem in the contest's colour (drawn flat);
-- the cushions and the case stand as reused, the back wall is laid again
for _, kind in ipairs({ "beauty", "cool", "cute", "smart", "tough" }) do
  local stage = contestStage()
  add("contest_stage_" .. kind, "LAYOUT_CONTEST_HALL_" .. kind:upper(), { 0x271, 0x225 }, ownShell({ stage[#stage] }))
end

end
laterRooms()

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
  LAYOUT_CONTEST_HALL = 225, LAYOUT_LILYCOVE_CITY_CONTEST_LOBBY = 105, LAYOUT_LILYCOVE_CITY_CONTEST_HALL = 106,
  LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_1F = 257, LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_2F = 258,
  LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_3F = 259, LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_4F = 260,
  LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_5F = 261, LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_ROOFTOP = 262,
  LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_ELEVATOR = 273, LAYOUT_LILYCOVE_CITY_LILYCOVE_MUSEUM_1F = 103,
  LAYOUT_LILYCOVE_CITY_LILYCOVE_MUSEUM_2F = 104, LAYOUT_LILYCOVE_CITY_POKEMON_TRAINER_FAN_CLUB = 107,
  LAYOUT_ROUTE114_LANETTES_HOUSE = 121, LAYOUT_ROUTE117_POKEMON_DAY_CARE = 123, LAYOUT_ROUTE109_SEASHORE_HOUSE = 243,
  LAYOUT_RUSTBORO_CITY_DEVON_CORP_1F = 92, LAYOUT_BATTLE_TENT_LOBBY = 384, LAYOUT_BATTLE_TENT_CORRIDOR = 385,
  LAYOUT_BATTLE_TENT_BATTLE_ROOM = 386, LAYOUT_VERDANTURF_TOWN_BATTLE_TENT_BATTLE_ROOM = 387,
  LAYOUT_SLATEPORT_CITY_POKEMON_FAN_CLUB = 85, LAYOUT_HARBOR = 88, LAYOUT_SLATEPORT_CITY_STERNS_SHIPYARD_1F = 81,
  LAYOUT_SLATEPORT_CITY_STERNS_SHIPYARD_2F = 82, LAYOUT_LAVARIDGE_TOWN_HERB_SHOP = 68,
  LAYOUT_ROUTE110_SEASIDE_CYCLING_ROAD_ENTRANCE = 256, LAYOUT_SAFARI_ZONE_REST_HOUSE = 329,
  LAYOUT_ROUTE119_WEATHER_INSTITUTE_1F = 271, LAYOUT_ROUTE119_WEATHER_INSTITUTE_2F = 272,
  LAYOUT_ROUTE121_SAFARI_ZONE_ENTRANCE = 124, LAYOUT_CABLE_CAR_STATION = 118, LAYOUT_MAUVILLE_CITY_BIKE_SHOP = 90,
  LAYOUT_MAUVILLE_CITY_GAME_CORNER = 91, LAYOUT_MOSSDEEP_CITY_GAME_CORNER_1F = 305,
  LAYOUT_MOSSDEEP_CITY_GAME_CORNER_B1F = 306, LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F = 439,
  LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_B1F = 440,
  LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F_STAIRS_UNBLOCKED = 441,
  LAYOUT_EVER_GRANDE_CITY_SIDNEYS_ROOM = 111, LAYOUT_EVER_GRANDE_CITY_PHOEBES_ROOM = 112,
  LAYOUT_EVER_GRANDE_CITY_GLACIAS_ROOM = 113, LAYOUT_EVER_GRANDE_CITY_DRAKES_ROOM = 114,
  LAYOUT_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F = 270, LAYOUT_EVER_GRANDE_CITY_SHORT_HALL = 116,
  LAYOUT_EVER_GRANDE_CITY_HALL4 = 315, LAYOUT_EVER_GRANDE_CITY_HALL_OF_FAME = 298, LAYOUT_MAUVILLE_CITY_GYM = 89,
  LAYOUT_MOSSDEEP_CITY_GYM = 108, LAYOUT_FORTREE_CITY_GYM = 100, LAYOUT_LAVARIDGE_TOWN_GYM_1F = 69,
  LAYOUT_LAVARIDGE_TOWN_GYM_B1F = 70, LAYOUT_SOOTOPOLIS_CITY_GYM_1F = 109, LAYOUT_SOOTOPOLIS_CITY_GYM_B1F = 110,
  LAYOUT_BATTLE_FRONTIER_SCOTTS_HOUSE = 430, LAYOUT_BATTLE_FRONTIER_LOUNGE1 = 397, LAYOUT_BATTLE_FRONTIER_LOUNGE2 = 429,
  LAYOUT_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY = 354, LAYOUT_BATTLE_FRONTIER_BATTLE_DOME_LOBBY = 332,
  LAYOUT_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY = 346, LAYOUT_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY = 342,
  LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY = 349, LAYOUT_BATTLE_FRONTIER_BATTLE_PYRAMID_LOBBY = 360,
  LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY = 264, LAYOUT_ROUTE124_DIVING_TREASURE_HUNTERS_HOUSE = 301,
  LAYOUT_CONTEST_HALL_BEAUTY = 232, LAYOUT_CONTEST_HALL_TOUGH = 233, LAYOUT_CONTEST_HALL_COOL = 234,
  LAYOUT_CONTEST_HALL_SMART = 235, LAYOUT_CONTEST_HALL_CUTE = 236,
}
-- the layouts no map is drawn with, which a script swaps into the map of the room named
-- (setmaplayoutindex): the lab once the starter is chosen
ROOMS.swaps = {
  LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE = "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB",
  LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F_STAIRS_UNBLOCKED = "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F",
}

return ROOMS
