-- FireRed's (and LeafGreen's) rooms (Battle Scene: Overworld): how each room is cut into its walls
-- and furniture, read by src/scene/models/interiors.lua, in the format of interior_specs.lua.
--
-- WoobleView's own reading of FireRed's rooms, by Emerald 3DS's method (each piece a shape of the
-- room's drawing, its front `height` rows standing at its drawn foot; a piece modelled once stands
-- in every later room that draws it). Every number here is read off FireRed's own drawing:
-- pixels, colours (to leave the wall and floor round a piece) and metatile ids only. Each room is
-- checked by tests/drivers/room_check.lua against its drawing.

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

--- A room's piece (the fields interior_specs.lua's piece takes; see interiors.lua)
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

--- A chamfered corner: a wall along its foot from a = { x, top, foot } to b, carrying the side
--- walls that run on from it, `height` tall.
local function facet(name, a, b, height, o)
  o = o or {}
  return { name = name, shape = { { { a[1], a[2] }, { b[1], b[2] }, { b[1], b[3] }, { a[1], a[3] } } },
           height = height, facet = { a, b }, walls = o.walls or {}, side = o.side, cells = o.cells or {},
           leave = {}, claim = {}, run = {}, skip = {}, at = {} }
end

-- ── the Pokemon Center ──────────────────────────────────────────────────────
-- Every town's Center is drawn with Celadon's layout, 15 x 10 (240 x 160 px):
--   * the back wall: rows 0-31 (its top line C5BDD5, white, the wallpaper F6EEA4 with its orange
--     E68B62 bands and trim, the skirting 83838B / 52526A), from x 16 to 224;
--   * the corners: cut on the diagonal, 35 rows tall, their top at 13 - x and foot at 48 - x
--     (west; the east mirrors it), the side walls running on from them to the floor's end at 144,
--     its own corners open from row 128;
--   * the floor: E6DE9C, F6F6CD, EEEEAC, C5B48B, D5CD9C (metatile 0x281).
local CENTER_WALL = { "c5bdd5", "ffffff", "f6eea4", "e68b62", "83838b", "52526a", "bd624a", "e6bd73" }
local CENTER_FLOOR = { "e6de9c", "f6f6cd", "eeeeac", "c5b48b", "d5cd9c" }
-- the counter's red top and its lip
local CENTER_COUNTER = { "ff8373", "cd5241" }
-- a stretch of the back wall with nothing on it, full height (the wallpaper's trim repeats every
-- 48 px: the plain stretch between two is 4 px wide)
local CENTER_WALL_SIDE = { 140, 0, 144, 32 }
local CENTER_FRONT = 144

local function centerWalls(front)
  return {
    facet("corner_w", { 0, 13, 48 }, { 16, -3, 32 }, 35, { walls = { { { 0, front }, { 0, 48 } } },
      side = CENTER_WALL_SIDE, cells = { { 0, math.floor(front / 16) - 1 } } }),
    facet("corner_e", { 224, -3, 32 }, { 240, 13, 48 }, 35, { walls = { { { 240, 48 }, { 240, front } } },
      side = CENTER_WALL_SIDE, cells = { { 14, math.floor(front / 16) - 1 } } }),
    piece("wall", { { 16, 0, 224, 32 } }, 32, { fill = 16, side = CENTER_WALL_SIDE }),
  }
end
-- the floor's two front corners, cut away
local CENTER_OPEN = { { { 0, 128 }, { 16, 144 }, { 0, 144 } }, { { 240, 128 }, { 224, 144 }, { 240, 144 } } }

-- the counter in plan: a bar across the front (from zBar), an arm back to the wall each end
local function counterPlan(x0, x1, arm, zBack, zBar, zFront)
  local a, b = x0 + arm, x1 - arm
  return { { x0, zFront }, { x1, zFront }, { x1, zBack }, { b, zBack }, { b, zBar }, { a, zBar }, { a, zBack },
           { x0, zBack } }
end

local CENTER_1F = {
  -- the flowers in their pots on the counter's two arms: cards, the counter round them left
  piece("flowers_w", { { 66, 36, 80, 53 } }, 13, { base = 9, card = true, leave = CENTER_COUNTER }),
  piece("flowers_e", { { 163, 36, 177, 53 } }, 13, { base = 9, card = true, leave = CENTER_COUNTER }),
  -- the counter: its arms back to the wall at row 24, its bar from row 44, its top red to row 54,
  -- the lip and the grey plinth below it nine rows to the floor at 64
  piece("counter", { { 64, 24, 80, 64 }, { 162, 24, 178, 64 }, { 64, 44, 178, 64 } }, 9,
    { fill = "column", leave = CENTER_FLOOR, plan = counterPlan(64, 178, 16, 24, 44, 64) }),
  -- behind it the healing machine: its glass dome over its base, the cross on its front
  piece("healer", { { 80, 14, 113, 45 } }, 14, { leave = CENTER_WALL, foot = 54, against = 32 }),
  -- on the counter's back, the keypad and the box with the cross
  piece("device", { { 144, 24, 162, 45 } }, 8, { leave = cat(CENTER_WALL, CENTER_COUNTER) }),
  -- the PC by the map, against the wall
  piece("pc", { { 174, 8, 192, 48 } }, 24, { leave = cat(CENTER_WALL, CENTER_FLOOR), back = 32 }),
  piece("bookcase", { { 34, 10, 66, 48 } }, 20, { leave = cat(CENTER_WALL, CENTER_FLOOR), back = 32 }),
  -- a card: the wall and the floor round its pot left
  piece("plant", { { 16, 10, 32, 42 } }, 26, { card = true, through = true, leave = cat(CENTER_WALL, CENTER_FLOOR) }),
  piece("stool_1", { { 176, 80, 192, 96 } }, 5, { leave = CENTER_FLOOR }),
  piece("stool_2", { { 192, 80, 208, 96 } }, 5, { leave = CENTER_FLOOR }),
  piece("stool_3", { { 224, 96, 240, 112 } }, 5, { leave = CENTER_FLOOR }),
  piece("stool_4", { { 224, 112, 240, 128 } }, 5, { leave = CENTER_FLOOR }),
  -- the glass table on its four feet
  piece("table", { { 176, 96, 208, 128 } }, 5, { leave = CENTER_FLOOR }),
}
for _, pc in ipairs(centerWalls(CENTER_FRONT)) do CENTER_1F[#CENTER_1F + 1] = pc end

-- the Center's upper floor (the Cable Club): the counter in stretches 10 px deep (its top rows
-- 44-54, its front nine rows to 64), its two grey gates low and set back, the link terminals on their pedestals with their tubes down from the wall, the white
-- columns, a chair against the east wall, the plants by the stairs (its stools are the ground
-- floor's, and stand here as they are)
local CENTER_2F = {
  piece("counter", { { 0, 44, 48, 64 }, { 64, 44, 80, 64 }, { 96, 44, 128, 64 }, { 160, 44, 192, 64 } }, 9,
    { fill = 1, back = 53, leave = CENTER_FLOOR }),
  piece("gate_1", { { 80, 48, 96, 62 } }, 4, { back = 52, leave = CENTER_FLOOR }),
  piece("gate_2", { { 144, 48, 160, 62 } }, 4, { back = 52, leave = CENTER_FLOOR }),
  -- the terminals hang from their tubes: upright cards, as thin things stand
  piece("terminal_1", { { 48, 8, 64, 72 } }, 64, { card = true, leave = cat(CENTER_WALL, CENTER_FLOOR) }),
  piece("terminal_2", { { 128, 18, 144, 68 } }, 50, { card = true, leave = cat(CENTER_WALL, CENTER_FLOOR) }),
  piece("terminal_3", { { 192, 18, 208, 68 } }, 50, { card = true, leave = cat(CENTER_WALL, CENTER_FLOOR) }),
  piece("column", { { 208, 8, 224, 64 } }, 52, { leave = cat(CENTER_WALL, CENTER_FLOOR), solid = true }),
  piece("chair", { { 224, 80, 240, 112 } }, 12, { leave = cat(CENTER_WALL, CENTER_FLOOR) }),
  piece("plant_1", { { 48, 112, 64, 144 } }, 24, { card = true, leave = CENTER_FLOOR }),
  piece("plant_2", { { 208, 110, 224, 144 } }, 24, { card = true, leave = CENTER_FLOOR }),
}
for _, pc in ipairs(centerWalls(CENTER_FRONT)) do CENTER_2F[#CENTER_2F + 1] = pc end

-- ── the Poke Mart ───────────────────────────────────────────────────────────
-- Every town's Mart is drawn with Cerulean's layout, 11 x 9 (176 x 144 px): its back wall rows
-- 0-31 (B4B4A4 and white over a green band, the yellow F6EE94 wall, the blue skirting), its cut
-- corners as the Center's (35 rows, their top at 13 - x), the floor (blue, metatile 0x281) ending
-- at 128, its corners open from 112. Glass cases hang on the back wall (as drawn on it).
local MART_WALL = { "b4b4a4", "ffffff", "a4ffb4", "6ac56a", "7b7b7b", "d5c56a", "f6ee94", "accdf6", "52526a",
                    "5294c5" }
local MART_FLOOR = { "6aa4ee", "4a8be6", "9ccdff", "3983cd", "2962bd" }
-- (the back wall is furnished end to end: its plain column at x 16)
local MART_WALL_SIDE = { 16, 0, 17, 32 }
local MART_FRONT = 128
local MART_OPEN = { { { 0, 112 }, { 16, 128 }, { 0, 128 } }, { { 176, 112 }, { 160, 128 }, { 176, 128 } } }

local MART = {
  -- the clerk's counter, back to the wall: its blue top from row 24 (the till on it at its back),
  -- its grey front eight rows to 80
  piece("till", { { 48, 20, 64, 80 } }, 8, { back = 32, leave = cat(MART_WALL, MART_FLOOR) }),
  -- the glass counter: its glass top rows 60-70, its front nine rows to 80; the boxes on its end
  piece("counter", { { 0, 60, 48, 80 } }, 9, { back = 69, leave = MART_FLOOR }),
  piece("boxes", { { 0, 48, 18, 64 } }, 8, { base = 9, leave = cat(MART_FLOOR, MART_WALL) }),
  -- the low glass case by the door: as the counter, its top rows 92-102, its front nine to 112
  piece("case", { { 16, 92, 48, 112 } }, 9, { back = 101, leave = MART_FLOOR }),
  -- the two fridges against the wall: their fronts 23 rows
  piece("fridges", { { 112, 9, 160, 38 } }, 23, { back = 32, leave = cat(MART_WALL, MART_FLOOR) }),
  -- the gondolas: tall shelves, three rows of cap over 48 of shelves to the floor at 112
  piece("gondola", { { 112, 61, 144, 112 } }, 48, { back = 109, leave = MART_FLOOR }),
  piece("gondola_e", { { 160, 61, 176, 112 } }, 48, { back = 109, leave = cat(MART_FLOOR, MART_WALL) }),
  -- a card: its leaves are the wall's greens, so only the wall's other colours and the floor are left
  piece("plant", { { 16, 20, 34, 44 } }, 22, { card = true, through = true,
    leave = cat(MART_FLOOR, { "b4b4a4", "ffffff", "7b7b7b", "d5c56a", "f6ee94", "accdf6", "52526a", "5294c5" }) }),
  facet("corner_w", { 0, 13, 48 }, { 16, -3, 32 }, 35, { walls = { { { 0, MART_FRONT }, { 0, 48 } } },
    side = MART_WALL_SIDE, cells = { { 0, math.floor(MART_FRONT / 16) - 1 } } }),
  facet("corner_e", { 160, -3, 32 }, { 176, 13, 48 }, 35, { walls = { { { 176, 48 }, { 176, MART_FRONT } } },
    side = MART_WALL_SIDE, cells = { { 10, math.floor(MART_FRONT / 16) - 1 } } }),
  piece("wall", { { 16, 0, 160, 32 } }, 32, { fill = 16, side = MART_WALL_SIDE }),
}

-- ── the gyms ────────────────────────────────────────────────────────────────

-- a piece drawn the same at more cells (`cells`, its top left cell first), each copy textured as
-- drawn there
local function repeated(name, cells, height, o)
  o = o or {}
  local c0 = cells[1]
  local at = {}
  for i = 2, #cells do at[#at + 1] = { cells[i][1], cells[i][2] } end
  o.at, o.variants = at, true
  return piece(name, o.shape or { { c0[1] * 16, c0[2] * 16, c0[1] * 16 + 16, c0[2] * 16 + 16 } }, height, o)
end

-- Pewter's gym (13 x 16): the back wall's 32 rows from 16 to 48 under its teal top, its thick side
-- walls' tops down either side (as drawn), boulders on its sand (each drawing of them: on the sand,
-- on the stone, on the dirt strip, against the back row), the great boulder on its stone platform
-- and the two statues by the door. Its sand C5BD8B is the wallpaper's stripe too: the pieces are
-- bounded by their shapes.
local PEWTER_GROUND = { "c5bd8b", "a48b73", "836a52", "624a31" }
local function pewterGym()
  return {
    -- (each boulder its drawn ellipse in its cell: rows 2-14, a row lower on the stone and the
    -- back row, whose edges cross the cell's top)
    repeated("rock", { { 4, 5 }, { 8, 5 }, { 3, 7 }, { 9, 7 }, { 11, 8 }, { 11, 10 } }, 12,
      { shape = { { "ellipse", 72, 88.5, 7.5, 6.5 } } }),
    repeated("rock_stone", { { 5, 7 }, { 7, 7 }, { 4, 9 }, { 8, 9 } }, 12, { shape = { { "ellipse", 88, 121.5, 7.5, 6.5 } } }),
    repeated("rock_dirt", { { 1, 8 }, { 1, 10 } }, 12, { shape = { { "ellipse", 24, 136.5, 7.5, 6.5 } } }),
    repeated("rock_back", { { 5, 3 }, { 7, 3 } }, 12, { shape = { { "ellipse", 88, 57.5, 7.5, 6.5 } } }),
    piece("boulder", { { "ellipse", 104, 92, 16, 12 } }, 18, {}),
    -- each statue: its figure a card on its pedestal, the pedestal 16 rows to its foot at 208
    piece("statue_w_figure", { { 64, 174, 80, 192 } }, 18, { base = 16, card = true, leave = PEWTER_GROUND }),
    piece("statue_w", { { 64, 192, 80, 208 } }, 16, { back = 192, leave = PEWTER_GROUND }),
    piece("statue_e_figure", { { 128, 174, 144, 192 } }, 18, { base = 16, card = true, leave = PEWTER_GROUND }),
    piece("statue_e", { { 128, 192, 144, 208 } }, 16, { back = 192, leave = PEWTER_GROUND }),
    piece("wall", { { 16, 0, 192, 48 } }, 32, { fill = 16, foot = 48 }),
  }
end

local ROOMS = {
  { name = "fr_pc1f", interior = { layout = "LAYOUT_CELADON_CITY_POKEMON_CENTER_1F", ground = { 0x281 },
                                   pieces = CENTER_1F, open = CENTER_OPEN } },
  { name = "fr_pc2f", interior = { layout = "LAYOUT_CELADON_CITY_POKEMON_CENTER_2F", ground = { 0x281 },
                                   pieces = CENTER_2F, open = CENTER_OPEN } },
  { name = "fr_mart", interior = { layout = "LAYOUT_CERULEAN_CITY_MART", ground = { 0x281 }, pieces = MART,
                                   open = MART_OPEN } },
  { name = "fr_pewter_gym", interior = { layout = "LAYOUT_PEWTER_CITY_GYM", ground = { 0x294 }, pieces = pewterGym() } },
}

ROOMS.ids = {}
ROOMS.swaps = {}

return ROOMS
