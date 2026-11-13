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

local ROOMS = {
  -- every town's Pokemon Center has this one ground floor
  { name = "pc1f", interior = { layout = "LAYOUT_POKEMON_CENTER_1F", ground = { 0x202 },
                                pieces = POKEMON_CENTER_1F, open = CENTER_1F_OPEN } },
  { name = "pc2f", interior = { layout = "LAYOUT_POKEMON_CENTER_2F", ground = { 0x202 },
                                pieces = POKEMON_CENTER_2F, open = CENTER_2F_OPEN } },
  -- every Poke Mart but the department store has this one room
  { name = "mart", interior = { layout = "LAYOUT_MART", ground = { 0x201 }, pieces = MART, open = MART_OPEN,
                                shade = { 0x202, 0x204, 0x206, 0x208, 0x20A } } },
}

-- a layout many maps share (pret names it for none of them), found by one map that uses it
ROOMS.maps = {
  LAYOUT_POKEMON_CENTER_1F = "EM_OLDALE_TOWN_POKEMON_CENTER_1F",
  LAYOUT_POKEMON_CENTER_2F = "EM_OLDALE_TOWN_POKEMON_CENTER_2F",
  LAYOUT_MART = "EM_OLDALE_TOWN_MART",
}

return ROOMS
