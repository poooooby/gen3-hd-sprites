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

-- the top left of a shape's bounds (rectangles, ellipses, polygons), pixels
local function shapeTopLeft(shape)
  local x0, y0 = math.huge, math.huge
  for _, s in ipairs(shape) do
    if s[1] == "ellipse" then
      x0, y0 = math.min(x0, s[2] - s[4]), math.min(y0, s[3] - s[5])
    elseif type(s[1]) == "table" then
      for _, p in ipairs(s) do x0, y0 = math.min(x0, p[1]), math.min(y0, p[2]) end
    else
      x0, y0 = math.min(x0, s[1]), math.min(y0, s[2])
    end
  end
  return x0, y0
end

-- a piece drawn the same at more cells (`cells`: the cell each copy is drawn in, the first the
-- shape's own), each copy textured as drawn there. The copies stand by the cell their shape's
-- bounds start in (a shape drawn over the cell above starts a row up)
local function repeated(name, cells, height, o)
  o = o or {}
  local c0 = cells[1]
  local shape = o.shape or { { c0[1] * 16, c0[2] * 16, c0[1] * 16 + 16, c0[2] * 16 + 16 } }
  local x0, y0 = shapeTopLeft(shape)
  local dx, dy = math.floor(x0 / 16) - c0[1], math.floor(y0 / 16) - c0[2]
  local at = {}
  for i = 2, #cells do at[#at + 1] = { cells[i][1] + dx, cells[i][2] + dy } end
  o.at, o.variants = at, true
  return piece(name, shape, height, o)
end

-- the two statues by a gym's door (every gym has them, each drawn with its own tileset): at cell
-- columns xs, their pedestals in cell row `row` - each a figure (a card, 18 rows) on a pedestal 16
-- rows to its foot, as deep as it is tall
local function gymStatues(xs, row, leave)
  local out = {}
  local y = row * 16
  for i, cx in ipairs(xs) do
    local x, side = cx * 16, i == 1 and "w" or "e"
    out[#out + 1] = piece("statue_" .. side .. "_figure", { { x, y - 18, x + 16, y } }, 18,
      { base = 16, card = true, leave = leave })
    out[#out + 1] = piece("statue_" .. side, { { x, y, x + 16, y + 16 } }, 16, { back = y, leave = leave })
  end
  return out
end

-- Pewter's gym (13 x 16): the back wall's 32 rows from 16 to 48 under its teal top, its thick side
-- walls' tops down either side (as drawn), boulders on its sand (each drawing of them: on the sand,
-- on the stone, on the dirt strip, against the back row), the great boulder on its stone platform
-- and the two statues by the door. Its sand C5BD8B is the wallpaper's stripe too: the pieces are
-- bounded by their shapes.
local PEWTER_GROUND = { "c5bd8b", "a48b73", "836a52", "624a31" }
local function pewterGym()
  local out = {
    -- (each boulder its drawn ellipse in its cell: rows 2-14, a row lower on the stone and the
    -- back row, whose edges cross the cell's top)
    repeated("rock", { { 4, 5 }, { 8, 5 }, { 3, 7 }, { 9, 7 }, { 11, 8 }, { 11, 10 } }, 12,
      { shape = { { "ellipse", 72, 88.5, 7.5, 6.5 } } }),
    repeated("rock_stone", { { 5, 7 }, { 7, 7 }, { 4, 9 }, { 8, 9 } }, 12, { shape = { { "ellipse", 88, 121.5, 7.5, 6.5 } } }),
    repeated("rock_dirt", { { 1, 8 }, { 1, 10 } }, 12, { shape = { { "ellipse", 24, 136.5, 7.5, 6.5 } } }),
    repeated("rock_back", { { 5, 3 }, { 7, 3 } }, 12, { shape = { { "ellipse", 88, 57.5, 7.5, 6.5 } } }),
    piece("boulder", { { "ellipse", 104, 92, 16, 12 } }, 18, {}),
    piece("wall", { { 16, 0, 192, 48 } }, 32, { fill = 16, foot = 48 }),
  }
  for _, pc in ipairs(gymStatues({ 4, 8 }, 12, PEWTER_GROUND)) do out[#out + 1] = pc end
  return out
end

-- Vermilion's gym (11 x 21): the upper room's back wall (24 rows to 32 under its white top), its
-- two pillars by the mat; the wall across the room (its top rows 88-104, its front 24 rows to 128)
-- and the power units against it either side of the barrier (whose beams the switches swap in
-- and out: it stays as drawn); the fifteen trash cans in their rows
local VERMILION_FLOOR = { "dede94", "cdc57b", "bdb46a" }
local function vermilionGym()
  local cans = {}
  for _, y in ipairs({ 10, 12, 14 }) do
    for _, x in ipairs({ 1, 3, 5, 7, 9 }) do cans[#cans + 1] = { x, y } end
  end
  local out = {
    repeated("can", cans, 10, { leave = VERMILION_FLOOR }),
    piece("unit_w", { { 32, 104, 48, 136 } }, 24, { back = 128, leave = VERMILION_FLOOR }),
    piece("unit_e", { { 128, 104, 144, 136 } }, 24, { back = 128, leave = VERMILION_FLOOR }),
    piece("pillar_w", { { 48, 16, 64, 56 } }, 40, { back = 54, leave = VERMILION_FLOOR }),
    piece("pillar_e", { { 112, 16, 128, 56 } }, 40, { back = 54, leave = VERMILION_FLOOR }),
    piece("divider_w", { { 0, 88, 56, 128 } }, 24, { fill = 16, foot = 128 }),
    piece("divider_e", { { 120, 88, 176, 128 } }, 24, { fill = 16, foot = 128 }),
    piece("wall", { { 16, 0, 160, 32 } }, 24, { fill = 8, foot = 32 }),
  }
  for _, pc in ipairs(gymStatues({ 3, 7 }, 17, VERMILION_FLOOR)) do out[#out + 1] = pc end
  return out
end

-- Celadon's gym (13 x 20): the back wall (24 rows to 32 under its frame), the round bushes on the
-- grass - each a ball 16 px across drawn 6 px above its own cell, some over the next one down (each
-- textured as drawn) - and the statues on the sand by the door; the flowers stay as drawn
local CELADON_GRASS = { "41e6bd", "31bdac", "299c9c" }
local CELADON_SAND = { "decd62", "cdb46a", "e6de6a" }
local CELADON_BUSHES = {
  { 3, 3 }, { 4, 3 }, { 5, 3 }, { 6, 3 }, { 7, 3 }, { 8, 3 }, { 9, 3 }, { 1, 4 }, { 3, 4 }, { 4, 4 }, { 9, 4 },
  { 11, 4 }, { 9, 5 }, { 3, 6 }, { 3, 7 }, { 9, 7 }, { 3, 8 }, { 4, 8 }, { 5, 8 }, { 7, 8 }, { 8, 8 }, { 9, 8 },
  { 3, 9 }, { 4, 9 }, { 8, 9 }, { 9, 9 }, { 11, 10 }, { 1, 11 }, { 3, 13 }, { 4, 13 }, { 8, 13 }, { 9, 13 },
  { 3, 14 }, { 4, 14 }, { 8, 14 }, { 9, 14 },
}
local function celadonGym()
  local c0 = CELADON_BUSHES[1]
  local out = {
    repeated("bush", CELADON_BUSHES, 16, { round = "ball",
      shape = { { "ellipse", c0[1] * 16 + 8, c0[2] * 16 + 2, 8, 8 } } }),
    piece("wall", { { 16, 0, 192, 32 } }, 24, { fill = 8, foot = 32 }),
  }
  for _, pc in ipairs(gymStatues({ 4, 8 }, 16, CELADON_SAND)) do out[#out + 1] = pc end
  return out
end

-- Cerulean's gym (17 x 20): the back wall (33 rows to 48 under its 15-row top), the two ladders
-- standing over the pool's edge (cards: two posts and their rungs), the statues on the walkway;
-- the pool, its water and the walkways across it stay as drawn
local CERULEAN_FLOOR = { "bdcde6", "ffffff", "dee6f6", "9ccdf6", "629cee", "fff6d5", "f6e6b4" }
local function ceruleanGym()
  local out = {
    piece("ladder_w", { { 44, 72, 68, 90 } }, 18, { card = true, leave = CERULEAN_FLOOR }),
    piece("ladder_e", { { 204, 72, 228, 90 } }, 18, { card = true, leave = CERULEAN_FLOOR }),
    piece("wall", { { 16, 0, 256, 48 } }, 33, { fill = 15, foot = 48 }),
  }
  for _, pc in ipairs(gymStatues({ 6, 10 }, 17, CERULEAN_FLOOR)) do out[#out + 1] = pc end
  return out
end

-- Fuchsia's gym (15 x 23): its walls are invisible (drawn as floor: as drawn); the back wall, 32
-- rows of yellow panels and green posts, and the statues
local FUCHSIA_FLOOR = { "eeb4a4", "cda49c", "c59c94", "ffdec5", "ffeeee" }
local function fuchsiaGym()
  local out = { piece("wall", { { 0, 0, 240, 32 } }, 32, { foot = 32 }) }
  for _, pc in ipairs(gymStatues({ 4, 10 }, 19, FUCHSIA_FLOOR)) do out[#out + 1] = pc end
  return out
end

-- a maze wall of a gym: its cells (a group of the layout's blocked cells, read off the drawing),
-- each drawn from `above` rows north of its cell to its foot, `height` rows of front
local function gymBlock(name, cells, height, above, side, leave)
  local shape = {}
  for i, c in ipairs(cells) do shape[i] = { c[1] * 16, c[2] * 16 - above, c[1] * 16 + 16, c[2] * 16 + 16 } end
  return piece(name, shape, height, { side = side, leave = leave })
end

-- Viridian's gym (20 x 24): a maze of low walls, each a grey top from 4 rows above its cells over
-- 13 rows of brown front; the back wall (23 rows to 32 under its 9-row top); the statues. The
-- spinning arrows stay as drawn
local VIRIDIAN_FLOOR = { "8bbdb4", "b4ded5", "6a9c94" }
local VIRIDIAN_SIDE = { 32, 147, 48, 160 }
local VIRIDIAN_WALLS = {
  { { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 }, { 0, 7 }, { 0, 8 }, { 1, 8 }, { 2, 8 }, { 3, 8 }, { 4, 8 }, { 5, 8 },
    { 0, 9 }, { 1, 9 }, { 2, 9 }, { 3, 9 }, { 4, 9 }, { 5, 9 }, { 5, 10 }, { 5, 11 }, { 5, 12 }, { 5, 13 } },
  { { 4, 2 }, { 4, 3 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 4, 5 }, { 5, 5 }, { 6, 5 } },
  { { 8, 4 }, { 9, 4 }, { 8, 5 }, { 9, 5 }, { 8, 6 }, { 7, 7 }, { 8, 7 }, { 9, 7 }, { 7, 8 }, { 8, 8 }, { 9, 8 }, { 10, 8 },
    { 11, 8 }, { 12, 8 }, { 13, 8 }, { 14, 8 }, { 7, 9 }, { 9, 9 }, { 10, 9 }, { 11, 9 }, { 12, 9 }, { 13, 9 }, { 14, 9 },
    { 7, 10 }, { 7, 11 }, { 7, 12 }, { 7, 13 }, { 7, 14 }, { 5, 15 }, { 6, 15 }, { 7, 15 }, { 8, 15 }, { 9, 15 }, { 10, 15 },
    { 11, 15 }, { 12, 15 }, { 13, 15 }, { 5, 16 }, { 6, 16 }, { 7, 16 }, { 8, 16 }, { 9, 16 }, { 10, 16 }, { 11, 16 },
    { 12, 16 }, { 13, 16 } },
  { { 11, 4 }, { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 11, 5 }, { 12, 5 }, { 13, 5 }, { 14, 5 },
    { 15, 5 }, { 16, 5 }, { 17, 5 }, { 11, 6 }, { 17, 6 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 17, 10 }, { 17, 11 }, { 17, 12 },
    { 17, 13 }, { 17, 14 } },
  { { 14, 11 }, { 15, 11 }, { 14, 12 }, { 15, 12 }, { 15, 13 }, { 15, 14 } },
  { { 2, 12 }, { 3, 12 }, { 2, 13 }, { 3, 13 }, { 2, 14 }, { 3, 14 }, { 2, 15 }, { 3, 15 }, { 2, 16 }, { 3, 16 }, { 2, 17 },
    { 3, 17 }, { 2, 18 }, { 3, 18 }, { 2, 19 }, { 3, 19 }, { 4, 19 }, { 5, 19 }, { 6, 19 }, { 7, 19 }, { 8, 19 }, { 9, 19 },
    { 10, 19 }, { 11, 19 }, { 12, 19 }, { 13, 19 }, { 2, 20 }, { 3, 20 }, { 4, 20 }, { 5, 20 }, { 6, 20 }, { 7, 20 },
    { 8, 20 }, { 9, 20 }, { 10, 20 }, { 11, 20 }, { 12, 20 }, { 13, 20 } },
}
local function viridianGym()
  local out = { piece("wall", { { 0, 0, 320, 32 } }, 23, { fill = 9, foot = 32 }) }
  for i, cells in ipairs(VIRIDIAN_WALLS) do
    out[#out + 1] = gymBlock("block_" .. i, cells, 13, 4, VIRIDIAN_SIDE, VIRIDIAN_FLOOR)
  end
  for _, pc in ipairs(gymStatues({ 15, 19 }, 20, VIRIDIAN_FLOOR)) do out[#out + 1] = pc end
  return out
end

-- Saffron's gym (29 x 25): nine rooms in three rows, each row's back wall 26 rows to its foot under
-- a 6-row top (at 32, 160, 288); the statues. The partitions between the rooms (a white rail each
-- side of a dark channel, capped where they meet the next row's wall), the glass tubes on the
-- walls and the warp pads stay as drawn
local SAFFRON_FLOOR = { "9cace6", "8394c5", "6a7bac" }
local function saffronGym()
  local out = {}
  for r = 0, 2 do
    out[#out + 1] = piece("wall_" .. (r + 1), { { 0, r * 128, 464, r * 128 + 32 } }, 26, { fill = 6, foot = r * 128 + 32 })
  end
  for _, pc in ipairs(gymStatues({ 12, 16 }, 20, SAFFRON_FLOOR)) do out[#out + 1] = pc end
  return out
end

-- Cinnabar's gym (30 x 25): nine rooms whose walls are green-topped blocks (their tops from 3 rows
-- above their cells, 17 rows of grey front); the back wall (24 rows to 32 under its 8-row top); a
-- quiz machine in each room (two cells wide, 20 rows of front under 12 of top); the statues. The
-- doors the quizzes open, the tube down the middle and the carpets stay as drawn
local CINNABAR_FLOOR = { "d5ac5a", "ac835a", "947352", "e6b45a", "6a5a52" }
local CINNABAR_SIDE = { 48, 143, 64, 160 }
local CINNABAR_WALLS = {
  { { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 }, { 0, 7 }, { 0, 8 }, { 1, 8 }, { 2, 8 }, { 3, 8 }, { 4, 8 }, {
    0, 9 }, { 1, 9 }, { 2, 9 }, { 3, 9 }, { 4, 9 }, { 0, 10 }, { 0, 11 }, { 0, 12 }, { 0, 13 }, { 0, 14 }, { 0, 15
    }, { 0, 16 }, { 1, 16 }, { 2, 16 }, { 3, 16 }, { 4, 16 }, { 0, 17 }, { 1, 17 }, { 2, 17 }, { 3, 17 }, { 4, 17 },
    { 0, 18 }, { 0, 19 }, { 0, 20 }, { 0, 21 }, { 0, 22 }, { 0, 23 } },
  { { 29, 2 }, { 29, 3 }, { 29, 4 }, { 29, 5 }, { 29, 6 }, { 29, 7 }, { 28, 8 }, { 29, 8 }, { 28, 9 }, { 29, 9 }, {
    29, 10 }, { 29, 11 }, { 29, 12 }, { 29, 13 }, { 29, 14 }, { 29, 15 }, { 29, 16 }, { 29, 17 }, { 29, 18 }, { 29,
    19 }, { 29, 20 }, { 29, 21 }, { 29, 22 }, { 29, 23 } },
  { { 21, 5 }, { 21, 6 }, { 21, 7 }, { 19, 8 }, { 20, 8 }, { 21, 8 }, { 22, 8 }, { 23, 8 }, { 24, 8 }, { 25, 8 }, {
    19, 9 }, { 20, 9 }, { 21, 9 }, { 22, 9 }, { 23, 9 }, { 24, 9 }, { 25, 9 }, { 21, 10 }, { 21, 11 }, { 21, 12 }, {
    21, 13 }, { 21, 14 }, { 22, 14 }, { 23, 14 }, { 24, 14 }, { 25, 14 }, { 19, 15 }, { 20, 15 }, { 21, 15 }, { 22,
    15 }, { 23, 15 }, { 24, 15 }, { 25, 15 }, { 19, 16 }, { 20, 16 }, { 21, 16 }, { 21, 17 }, { 21, 18 }, { 21, 19
    }, { 21, 20 }, { 21, 21 }, { 21, 22 }, { 21, 23 } },
  { { 10, 7 }, { 7, 8 }, { 8, 8 }, { 9, 8 }, { 10, 8 }, { 7, 9 }, { 8, 9 }, { 9, 9 } },
  { { 12, 7 }, { 12, 8 }, { 13, 8 }, { 14, 8 }, { 15, 8 }, { 16, 8 }, { 13, 9 }, { 14, 9 }, { 15, 9 }, { 16, 9 } },
  { { 12, 14 }, { 12, 15 }, { 13, 15 }, { 14, 15 }, { 15, 15 }, { 16, 15 }, { 13, 16 }, { 14, 16 }, { 15, 16 }, {
    16, 16 } },
  { { 10, 15 }, { 7, 16 }, { 8, 16 }, { 9, 16 }, { 10, 16 }, { 7, 17 }, { 8, 17 }, { 9, 17 } },
  { { 10, 21 } },
  { { 12, 21 } },
}
local CINNABAR_QUIZ = { { 1, 2 }, { 8, 2 }, { 15, 2 }, { 1, 10 }, { 13, 10 }, { 22, 10 }, { 1, 17 }, { 13, 17 } }
local function cinnabarGym()
  local out = { piece("wall", { { 0, 0, 480, 32 } }, 24, { fill = 8, foot = 32 }) }
  local q = CINNABAR_QUIZ[1]
  out[#out + 1] = repeated("quiz", CINNABAR_QUIZ, 20, { back = q[2] * 16 + 4, leave = CINNABAR_FLOOR,
    shape = { { q[1] * 16, q[2] * 16 - 16, q[1] * 16 + 32, q[2] * 16 + 16 } } })
  for i, cells in ipairs(CINNABAR_WALLS) do
    out[#out + 1] = gymBlock("block_" .. i, cells, 17, 3, CINNABAR_SIDE, CINNABAR_FLOOR)
  end
  for _, pc in ipairs(gymStatues({ 23, 27 }, 20, CINNABAR_FLOOR)) do out[#out + 1] = pc end
  return out
end

local ROOMS = {
  { name = "fr_pc1f", interior = { layout = "LAYOUT_CELADON_CITY_POKEMON_CENTER_1F", ground = { 0x281 },
                                   pieces = CENTER_1F, open = CENTER_OPEN } },
  { name = "fr_pc2f", interior = { layout = "LAYOUT_CELADON_CITY_POKEMON_CENTER_2F", ground = { 0x281 },
                                   pieces = CENTER_2F, open = CENTER_OPEN } },
  { name = "fr_mart", interior = { layout = "LAYOUT_CERULEAN_CITY_MART", ground = { 0x281 }, pieces = MART,
                                   open = MART_OPEN } },
  { name = "fr_pewter_gym", interior = { layout = "LAYOUT_PEWTER_CITY_GYM", ground = { 0x294 }, pieces = pewterGym() } },
  { name = "fr_vermilion_gym", interior = { layout = "LAYOUT_VERMILION_CITY_GYM", ground = { 0x281 }, pieces = vermilionGym() } },
  { name = "fr_celadon_gym", interior = { layout = "LAYOUT_CELADON_CITY_GYM", ground = { 0x281 }, pieces = celadonGym() } },
  { name = "fr_cerulean_gym", interior = { layout = "LAYOUT_CERULEAN_CITY_GYM", ground = { 0x281 }, pieces = ceruleanGym() } },
  { name = "fr_fuchsia_gym", interior = { layout = "LAYOUT_FUCHSIA_CITY_GYM", ground = { 0x281 }, pieces = fuchsiaGym() } },
  { name = "fr_viridian_gym", interior = { layout = "LAYOUT_VIRIDIAN_CITY_GYM", ground = { 0x281 }, pieces = viridianGym() } },
  { name = "fr_saffron_gym", interior = { layout = "LAYOUT_SAFFRON_CITY_GYM", ground = { 0x281 }, pieces = saffronGym() } },
  { name = "fr_cinnabar_gym", interior = { layout = "LAYOUT_CINNABAR_ISLAND_GYM", ground = { 0x281 }, pieces = cinnabarGym() } },
}

ROOMS.ids = {}
ROOMS.swaps = {}

return ROOMS
