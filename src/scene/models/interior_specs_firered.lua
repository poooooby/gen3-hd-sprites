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
-- rows to its foot, as deep as it is tall (or `deep` rows, under a shorter figure)
local function gymStatues(xs, row, leave, deep)
  local out = {}
  local y = row * 16
  for i, cx in ipairs(xs) do
    local x, side = cx * 16, i == 1 and "w" or "e"
    out[#out + 1] = piece("statue_" .. side .. "_figure", { { x, y - 18, x + 16, y } }, 18,
      { base = 16, card = true, leave = leave })
    out[#out + 1] = piece("statue_" .. side, { { x, y, x + 16, y + 16 } }, 16,
      { back = y + 16 - (deep or 16), leave = leave })
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

-- ── the Pokemon League ──────────────────────────────────────────────────────

-- Lorelei's, Bruno's and Agatha's rooms (13 x 13, each in its own colours): the wooden back wall
-- (32 rows to 48 under its 16-row top) with the door, the wall across the south either side of the
-- way out (its top 160-176, its face to 208), the side walls between, and three pillars down each
-- side (ice, stone, torches) at x 32 and 160: the first against the back wall (40-72), the next
-- two 38 rows each to 112 and 160, each 30 rows of front under 8 of top
local E4_WALL_SIDE = { 136, 16, 152, 48 }
local function eliteFourRoom(floor)
  local out = {}
  for _, x in ipairs({ 32, 160 }) do
    local side = x < 100 and "w" or "e"
    out[#out + 1] = piece("pillar_" .. side .. "1", { { x, 40, x + 16, 72 } }, 30, { back = 70, leave = floor })
    out[#out + 1] = repeated("pillar_" .. side, { { x / 16, 4 }, { x / 16, 7 } }, 30,
      { back = 104, leave = floor, shape = { { x, 74, x + 16, 112 } } })
  end
  local more = {
    piece("wall", { { 0, 0, 208, 48 } }, 32, { fill = 16, foot = 48, side = E4_WALL_SIDE }),
    piece("wall_front_w", { { 0, 160, 88, 208 } }, 32, { fill = 16, foot = 208 }),
    piece("wall_front_e", { { 120, 160, 208, 208 } }, 32, { fill = 16, foot = 208 }),
    piece("side_w", {}, 32, { side = E4_WALL_SIDE, walls = { { { 0, 192 }, { 0, 48 } } } }),
    piece("side_e", {}, 32, { side = E4_WALL_SIDE, walls = { { { 208, 48 }, { 208, 192 } } } }),
  }
  for _, pc in ipairs(more) do out[#out + 1] = pc end
  return out
end

-- Lance's room (28 x 24): his battle room is the others' plan 48 rows lower (its back wall to 96,
-- its south wall either side of the one-cell way out, 208-256), its pillars dragon horns: each a
-- horn (a card) standing on its pedestal (16 rows to its foot), the first against the back wall;
-- the halls beyond stay as drawn
local LANCE_FLOOR = { "398b8b", "52a4a4", "6abdbd" }
local function lancesRoom()
  local out = {}
  for _, x in ipairs({ 32, 160 }) do
    local side = x < 100 and "w" or "e"
    out[#out + 1] = piece("horn_" .. side .. "1", { { x, 96, x + 16, 120 } }, 20, { back = 116, leave = LANCE_FLOOR })
    out[#out + 1] = repeated("horn_" .. side, { { x / 16, 7 }, { x / 16, 10 } }, 24,
      { base = 16, card = true, leave = LANCE_FLOOR, shape = { { x, 118, x + 16, 142 } } })
    out[#out + 1] = repeated("pedestal_" .. side, { { x / 16, 8 }, { x / 16, 11 } }, 16,
      { back = 156, leave = LANCE_FLOOR, shape = { { x, 140, x + 16, 160 } } })
  end
  local more = {
    piece("wall", { { 0, 48, 208, 96 } }, 32, { fill = 16, foot = 96, side = E4_WALL_SIDE }),
    piece("wall_front_w", { { 0, 208, 96, 256 } }, 32, { fill = 16, foot = 256 }),
    piece("wall_front_e", { { 112, 208, 240, 256 } }, 32, { fill = 16, foot = 256 }),
    piece("side_w", {}, 32, { side = E4_WALL_SIDE, walls = { { { 0, 240 }, { 0, 96 } } } }),
    piece("side_e", {}, 32, { side = E4_WALL_SIDE, walls = { { { 208, 96 }, { 208, 208 } } } }),
  }
  for _, pc in ipairs(more) do out[#out + 1] = pc end
  return out
end

-- the Champion's room (13 x 20): an octagon - its tall purple back wall (55 rows to 61 under a
-- 6-row rim) with the doorway and its steps, its corners cut on the diagonal 32 px wide (their top
-- at 37 - x), and four lantern posts; the stepped seats and the way out stay as drawn
local CHAMPION_FLOOR = { "a4c5c5", "e6d59c", "83a4a4", "fff69c", "deeeee" }
local function championsRoom()
  return {
    repeated("post", { { 1, 4 }, { 10, 4 }, { 1, 11 }, { 10, 11 } }, 20,
      { back = 92, leave = CHAMPION_FLOOR, shape = { { 24, 72, 40, 96 } } }),
    facet("corner_w", { 0, 37, 92 }, { 32, 6, 61 }, 55),
    facet("corner_e", { 176, 6, 61 }, { 208, 37, 92 }, 55),
    piece("wall", { { 32, 0, 176, 61 } }, 55, { fill = 6, foot = 61 }),
  }
end

-- ── Silph Co. ───────────────────────────────────────────────────────────────
-- Its offices are walled by bands two rows deep (beige over a purple trim, a white edge along the
-- top: the wall's top), read off each floor's drawing: the blocked cells drawn at least half in the
-- band's colours, in runs two rows deep (a plant's crown over a band leaves the wall whole behind
-- it). Each band { first column, last column, top row } stands 30 rows to its foot under its edge.
-- The partitions seen from above and the dark between the rooms stay as drawn. Its furniture is
-- modelled on 2F, and stands as it is on every floor (and in the Rocket Hideout's) that draws it.
local SILPH_BANDS = {
  ["1F"] = { { 30, 33, 0 }, { 0, 29, 2 }, { 34, 35, 2 } },
  ["2F"] = { { 26, 32, 0 }, { 0, 10, 2 }, { 13, 25, 2 }, { 33, 35, 2 }, { 0, 4, 8 }, { 7, 28, 8 }, { 31, 35, 8 }, { 28, 35, 13 }, { 0, 4, 15 }, { 7, 11, 15 }, { 26, 27, 15 } },
  ["3F"] = { { 26, 32, 0 }, { 0, 25, 2 }, { 33, 35, 2 }, { 0, 8, 8 }, { 11, 19, 8 }, { 28, 35, 8 }, { 9, 10, 10 }, { 20, 21, 10 }, { 26, 27, 10 }, { 32, 33, 12 }, { 0, 21, 16 }, { 26, 35, 16 } },
  ["4F"] = { { 26, 32, 0 }, { 0, 8, 2 }, { 11, 18, 2 }, { 21, 25, 2 }, { 33, 35, 2 }, { 26, 28, 9 }, { 31, 35, 9 }, { 11, 13, 11 }, { 16, 18, 11 }, { 29, 31, 13 }, { 0, 2, 16 }, { 5, 13, 16 }, { 16, 20, 16 }, { 29, 31, 17 } },
  ["5F"] = { { 26, 32, 0 }, { 0, 6, 2 }, { 9, 25, 2 }, { 33, 35, 2 }, { 7, 8, 7 }, { 20, 27, 7 }, { 30, 32, 7 }, { 13, 17, 9 }, { 18, 19, 11 }, { 0, 6, 13 }, { 7, 8, 16 }, { 11, 34, 18 } },
  ["6F"] = { { 12, 15, 0 }, { 25, 28, 0 }, { 0, 4, 2 }, { 7, 11, 2 }, { 16, 24, 2 }, { 29, 30, 2 }, { 5, 6, 5 }, { 13, 21, 6 }, { 24, 26, 6 }, { 0, 4, 10 }, { 5, 6, 13 }, { 11, 15, 15 }, { 18, 28, 15 } },
  ["7F"] = { { 17, 20, 0 }, { 26, 29, 0 }, { 0, 5, 2 }, { 21, 25, 2 }, { 15, 16, 4 }, { 22, 23, 7 }, { 26, 30, 7 }, { 8, 10, 8 }, { 13, 14, 8 }, { 0, 5, 10 }, { 22, 24, 13 }, { 27, 30, 13 }, { 6, 16, 16 } },
  ["8F"] = { { 14, 17, 0 }, { 27, 30, 0 }, { 0, 4, 2 }, { 7, 11, 2 }, { 18, 26, 2 }, { 19, 30, 6 }, { 5, 6, 8 }, { 9, 11, 8 }, { 0, 6, 14 }, { 9, 13, 14 }, { 17, 23, 14 }, { 26, 30, 14 } },
  ["9F"] = { { 14, 20, 0 }, { 0, 11, 2 }, { 21, 30, 2 }, { 4, 11, 6 }, { 18, 20, 6 }, { 23, 26, 6 }, { 2, 3, 8 }, { 18, 20, 12 }, { 23, 27, 12 }, { 0, 3, 14 }, { 7, 8, 14 }, { 12, 13, 14 }, { 28, 29, 15 } },
  ["10F"] = { { 4, 10, 0 }, { 0, 3, 2 }, { 11, 16, 2 }, { 9, 11, 6 }, { 14, 16, 6 }, { 0, 2, 11 }, { 5, 6, 11 }, { 9, 11, 11 }, { 14, 16, 11 } },
  ["11F"] = { { 5, 9, 0 }, { 0, 2, 2 }, { 10, 16, 2 }, { 5, 12, 6 }, { 3, 4, 16 }, { 7, 12, 16 } },
}
local SILPH_FLOOR = { "83bdc5", "acdee6", "6a9ca4" }
local SILPH_WALL = { "d5d5b4", "ffffff", "b473a4", "7b7b7b", "b4b4a4", "eeb4de", "9494a4", "52526a" }
local function silphFloor(f, more)
  local out = {}
  for i, b in ipairs(SILPH_BANDS[f]) do
    out[#out + 1] = piece("wall_" .. i, { { b[1] * 16, b[3] * 16, b[2] * 16 + 16, b[3] * 16 + 32 } }, 30,
      { fill = 2, foot = b[3] * 16 + 32 })
  end
  for _, pc in ipairs(more or {}) do table.insert(out, 1, pc) end
  return out
end
-- 2F's furniture: the potted plants against the walls (cards, two cells), the desks (a grey top
-- 27 rows deep over 8 rows of front and legs), their stools, the computer tables
local SILPH_2F = {
  repeated("plant", { { 0, 3 }, { 1, 3 }, { 2, 3 }, { 14, 3 }, { 15, 3 }, { 17, 9 }, { 18, 9 }, { 19, 9 }, { 20, 9 },
    { 21, 9 }, { 22, 9 } }, 36, { card = true, leave = cat(SILPH_FLOOR, SILPH_WALL), shape = { { 0, 44, 16, 80 } } }),
  repeated("desk", { { 16, 14 }, { 21, 14 }, { 16, 18 }, { 21, 18 } }, 8,
    { back = 235, leave = SILPH_FLOOR, shape = { { 256, 226, 304, 264 } } }),
  repeated("stool", { { 19, 14 }, { 24, 14 }, { 19, 18 }, { 24, 18 } }, 8,
    { leave = SILPH_FLOOR, shape = { { 304, 238, 320, 258 } } }),
  repeated("table", { { 2, 18 }, { 29, 17 } }, 10, { leave = SILPH_FLOOR, shape = { { 32, 296, 80, 336 } } }),
}

-- the Rocket Hideout (under Celadon's Game Corner, Silph's tileset): its walls are bands as Silph's
-- in its own colours (grey-blue over a teal skirting, a 4-row white edge: 28 rows of wall), read
-- the same way; its furniture is Silph's and the Game Corner's where drawn alike. The spinning
-- floors, the stairs and the lift stay as drawn
local ROCKET_BANDS = {
  ["B1F"] = { { 0, 8, 6 }, { 21, 27, 6 }, { 0, 2, 11 }, { 5, 8, 11 }, { 18, 21, 11 }, { 25, 27, 11 }, { 3, 5, 15 }, { 0, 18, 20 }, { 4, 9, 24 }, { 23, 27, 24 }, { 4, 9, 29 } },
  ["B2F"] = { { 13, 16, 3 }, { 18, 26, 10 }, { 27, 31, 15 } },
  ["B3F"] = { { 0, 21, 0 }, { 0, 10, 5 }, { 14, 18, 5 }, { 17, 21, 10 }, { 2, 3, 12 }, { 11, 12, 14 }, { 0, 3, 23 }, { 6, 8, 23 } },
  ["B4F"] = { { 15, 23, 0 }, { 8, 14, 3 }, { 19, 23, 12 }, { 3, 5, 13 }, { 0, 14, 18 }, { 5, 10, 22 }, { 19, 23, 22 } },
}
local function rocketFloor(f)
  local out = {}
  for i, b in ipairs(ROCKET_BANDS[f]) do
    out[#out + 1] = piece("wall_" .. i, { { b[1] * 16, b[3] * 16, b[2] * 16 + 16, b[3] * 16 + 32 } }, 28,
      { fill = 4, foot = b[3] * 16 + 32 })
  end
  return out
end

-- the Pokemon Tower (24 x 20, every floor the same round hall): its back wall stepped down either
-- side, each step a row of panels (26 rows to its foot) under a white rim, and the rim running
-- down the step's inner end (8 px wide) from the step above's - the top of the wall turning south
-- there. TOWER_STEPS is each column's panel row, from column 2 (nil: no wall). The graves (one
-- cell, a headstone on its base) stand wherever drawn, the gold ones too; 7F's two statues are a
-- bust (a card) on a fluted pillar. The stairs, the mats and 1F's counter stay as drawn
local TOWER_FLOOR = { "6a9c6a", "83ac83", "5a835a", "527b52", "416a41" }
local TOWER_STEPS = { 7, 5, 4, 3, 3, 2, 2, 1, 1, 1, 1, 1, 2, 2, 3, 3, 4, 5, 7 }
local function towerShell(steps)
  local out, first = {}, 2
  local mid = first + 9 -- the hall's middle column
  local c = first
  while c <= first + #steps - 1 do
    local p = steps[c - first + 1]
    local c1 = c
    while c1 + 1 <= first + #steps - 1 and steps[c1 + 1 - first + 1] == p do c1 = c1 + 1 end
    if p then
      local shape, skip = { { c * 16, (p - 1) * 16, c1 * 16 + 16, p * 16 + 16 } }, {}
      -- (the rim down the step's inner end, from the step above's)
      local inner = c1 < mid and c1 + 1 or c - 1
      local q = steps[inner - first + 1]
      if q and q < p then
        local x = c1 < mid and c1 * 16 + 8 or c * 16
        shape[#shape + 1] = { x, (q - 1) * 16, x + 8, (p - 1) * 16 }
        -- (the cells the rim crosses are outside the hall: no floor of the piece's)
        for cy = q - 1, p - 2 do
          for cx = c, c1 do skip[#skip + 1] = { cx, cy } end
        end
      end
      out[#out + 1] = piece("wall_" .. c, shape, 26, { fill = 16, foot = p * 16 + 16, skip = skip })
    end
    c = c1 + 1
  end
  return out
end
local function towerFloor(steps, more)
  local out = towerShell(steps)
  for _, pc in ipairs(more or {}) do table.insert(out, 1, pc) end
  return out
end
local TOWER_1F_STEPS = { 7, 5, 4, 3, 3, 2, 2, 1, 1, 1, 1, 1, 2, 2, 3, 3, 4, 5 }
local TOWER_3F = {
  piece("grave", { { 96, 112, 112, 128 } }, 10, { leave = TOWER_FLOOR }),
  repeated("grave_more", {
    { 7, 3 }, { 8, 3 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 6, 6 }, { 7, 6 }, { 8, 6 },
    { 9, 6 }, { 10, 6 }, { 11, 6 }, { 12, 6 }, { 13, 6 }, { 14, 6 }, { 15, 6 }, { 16, 6 }, { 17, 6 }, { 18, 6 },
    { 6, 8 }, { 17, 8 }, { 19, 8 }, { 6, 9 }, { 10, 9 }, { 11, 9 }, { 12, 9 }, { 16, 9 }, { 6, 10 }, { 10, 10 },
    { 11, 10 }, { 12, 10 }, { 16, 10 }, { 6, 11 }, { 16, 11 }, { 6, 12 }, { 16, 12 }, { 19, 12 }, { 20, 12 }, { 6, 13 },
    { 10, 13 }, { 11, 13 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 18, 13 }, { 19, 13 }, { 4, 15 },
    { 5, 15 }, { 6, 15 }, { 17, 15 }, { 18, 15 }, { 6, 16 }, { 9, 17 }, { 10, 17 }, { 11, 17 }, { 12, 17 }, { 13, 17 } }, 10, { leave = TOWER_FLOOR }),
}
local TOWER_7F = {
  piece("grave_gold", { { 80, 96, 96, 112 } }, 10, { leave = TOWER_FLOOR }),
  repeated("grave_gold_more", {
    { 7, 4 }, { 8, 4 }, { 14, 4 }, { 15, 4 }, { 5, 5 }, { 6, 5 }, { 7, 5 }, { 8, 5 }, { 14, 5 },
    { 15, 5 }, { 16, 5 }, { 17, 5 }, { 4, 6 }, { 6, 6 }, { 7, 6 }, { 8, 6 }, { 14, 6 }, { 15, 6 }, { 16, 6 },
    { 17, 6 }, { 18, 6 }, { 3, 7 }, { 4, 7 }, { 5, 7 }, { 6, 7 }, { 7, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 },
    { 18, 7 }, { 19, 7 }, { 3, 8 }, { 4, 8 }, { 5, 8 }, { 6, 8 }, { 16, 8 }, { 17, 8 }, { 18, 8 }, { 19, 8 },
    { 2, 11 }, { 3, 11 }, { 4, 11 }, { 5, 11 }, { 6, 11 }, { 16, 11 }, { 17, 11 }, { 18, 11 }, { 19, 11 }, { 20, 11 },
    { 3, 12 }, { 4, 12 }, { 5, 12 }, { 6, 12 }, { 7, 12 }, { 15, 12 }, { 16, 12 }, { 17, 12 }, { 18, 12 }, { 19, 12 },
    { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 },
    { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 }, { 4, 14 }, { 5, 14 }, { 6, 14 }, { 7, 14 }, { 8, 14 }, { 9, 14 },
    { 13, 14 }, { 14, 14 }, { 15, 14 }, { 16, 14 }, { 17, 14 }, { 18, 14 }, { 5, 15 }, { 6, 15 }, { 7, 15 }, { 8, 15 },
    { 14, 15 }, { 15, 15 }, { 16, 15 }, { 17, 15 }, { 6, 16 }, { 7, 16 }, { 8, 16 }, { 14, 16 }, { 15, 16 }, { 16, 16 } }, 10, { leave = TOWER_FLOOR }),
  repeated("statue_figure", { { 9, 2 }, { 13, 2 } }, 18,
    { base = 20, card = true, leave = TOWER_FLOOR, shape = { { 144, 40, 160, 58 } } }),
  repeated("statue", { { 9, 3 }, { 13, 3 } }, 20, { leave = TOWER_FLOOR, shape = { { 144, 56, 160, 80 } } }),
}

-- Saffron's Fighting Dojo (13 x 16): its back wall (27 rows to its foot at 48, windows and scrolls
-- on it), the two low partitions running from its foot to 110 (a cream top over a lacquered
-- front, 24 rows: the wall's rim shows above them), the vase of flowers before the wall (a card)
-- and the two statues by the door (their figures 12 rows: the pedestals as deep). The mats stay as drawn
local DOJO_FLOOR = { "ded58b", "b4ac62", "9c9452" }
local DOJO_WALL = { "9cbd83", "73a46a", "decd73", "7b6a39", "a4a4ac", "eeeef6" }
local function dojo()
  local out = gymStatues({ 3, 9 }, 13, DOJO_FLOOR, 12)
  local more = {
    piece("vase", { { 97, 40, 109, 56 } }, 16, { card = true, leave = cat(DOJO_FLOOR, DOJO_WALL) }),
    piece("partition_w", { { 64, 24, 80, 110 } }, 24, { foot = 110 }),
    piece("partition_e", { { 128, 24, 144, 110 } }, 24, { foot = 110 }),
    piece("wall", { { 16, 16, 192, 48 } }, 27, { fill = 16, foot = 48 }),
  }
  for _, pc in ipairs(more) do out[#out + 1] = pc end
  return out
end

-- the Pokemon Mansion (38 x 35): its walls are cream under a brown rail, 40 rows from the rail's
-- top to the dark line at their foot, the partitions' salmon tops seen from above (8 rows over the
-- rail: the wall's top). They're read off each floor's drawing: every pixel column drawn as the
-- rail (6 rows or more, then the dark line) with the foot line 40 rows below, the columns with the
-- same rail row grouped (a gap of 3 px or less closed: the rubble's outline at a foot; a column
-- whose foot something stands before counts by its cream 18 rows under the rail). Each
-- { x0, x1 (exclusive), the rail's top } stands 40 rows to its foot under its top. The partitions
-- seen from above, the gates (they open), the rubble and the stairs stay as drawn. (Each floor
-- stands its own walls: a wall isn't looked for elsewhere)
local MANSION_WALLS = {
  ["1F"] = {
    { 24, 584, 8 }, { 16, 22, 16 }, { 586, 592, 16 }, { 464, 526, 88 }, { 304, 350, 152 }, { 402, 462, 152 }, { 24, 208, 168 },
    { 16, 22, 176 }, { 210, 222, 200 }, { 272, 368, 280 }, { 384, 494, 280 }, { 546, 584, 280 }, { 586, 592, 288 }, { 82, 94, 328 },
    { 178, 190, 328 }, { 371, 430, 392 }, { 482, 496, 392 }, { 562, 584, 392 }, { 586, 592, 400 }, { 82, 94, 408 }, { 178, 190, 408 },
    { 82, 94, 488 }, { 178, 190, 488 } },
  ["2F"] = {
    { 24, 192, 8 }, { 208, 328, 8 }, { 360, 584, 8 }, { 16, 22, 16 }, { 330, 336, 16 }, { 352, 358, 16 }, { 586, 592, 16 },
    { 194, 206, 56 }, { 338, 382, 136 }, { 434, 494, 136 }, { 24, 192, 184 }, { 16, 22, 192 }, { 304, 382, 216 }, { 434, 584, 216 },
    { 586, 592, 224 }, { 194, 206, 232 }, { 24, 110, 312 }, { 272, 414, 312 }, { 530, 592, 312 }, { 16, 22, 320 }, { 24, 160, 424 },
    { 16, 22, 432 }, { 258, 270, 440 } },
  ["3F"] = {
    { 24, 328, 8 }, { 360, 456, 8 }, { 488, 584, 8 }, { 16, 22, 16 }, { 330, 336, 16 }, { 352, 358, 16 }, { 458, 464, 16 },
    { 480, 486, 16 }, { 586, 592, 16 }, { 338, 350, 56 }, { 466, 478, 56 }, { 147, 224, 136 }, { 240, 270, 168 }, { 322, 414, 168 },
    { 498, 592, 168 }, { 240, 286, 248 }, { 338, 366, 248 }, { 402, 416, 248 }, { 466, 592, 248 }, { 8, 238, 360 }, { 418, 600, 360 } },
  ["B1F"] = {
    { 24, 192, 8 }, { 208, 400, 8 }, { 416, 584, 8 }, { 16, 22, 16 }, { 586, 592, 16 }, { 208, 270, 104 }, { 322, 400, 104 },
    { 402, 478, 120 }, { 546, 592, 120 }, { 16, 78, 232 }, { 130, 192, 232 }, { 208, 480, 232 }, { 482, 526, 312 }, { 578, 592, 312 },
    { 272, 318, 344 }, { 370, 416, 344 }, { 16, 206, 376 }, { 258, 270, 408 }, { 530, 592, 424 } },
}
-- 1F's furniture, standing as it is on every floor that draws it: the tables (a yellow top 36
-- rows deep over 8 of front and legs), the chairs, the statue (its figure a card on a pedestal 10
-- rows to its foot); 2F's: the tables with the diary on them, the lab machines against the walls
-- (20 rows of front under an 8-row top, backed onto the wall's foot). Its potted plants are the
-- Pokemon Center's
local MANSION_FLOOR = { "9c835a", "decd9c", "ffeebd", "bda473", "8b7331" }
local MANSION_WALL = { "ffeebd", "bda473", "8b5239", "a4624a", "52526a", "de947b" }
local MANSION_1F = {
  piece("table", { { 112, 76, 160, 120 } }, 8, { back = 84, leave = MANSION_FLOOR }),
  piece("table_2", { { 512, 156, 560, 200 } }, 8, { back = 164, leave = MANSION_FLOOR }),
  piece("chair_e", { { 160, 80, 176, 96 } }, 11, { leave = MANSION_FLOOR }),
  piece("chair_w", { { 96, 112, 112, 128 } }, 11, { leave = MANSION_FLOOR }),
  piece("statue_figure", { { 80, 64, 96, 85 } }, 21, { base = 10, card = true, leave = MANSION_FLOOR }),
  piece("statue", { { 80, 84, 96, 96 } }, 10, { leave = MANSION_FLOOR }),
}
local MANSION_2F = {
  piece("table_diary", { { 400, 60, 448, 104 } }, 8, { back = 68, leave = MANSION_FLOOR }),
  piece("table_diary_2", { { 80, 492, 128, 536 } }, 8, { back = 500, leave = MANSION_FLOOR }),
  piece("machine_1", { { 496, 28, 512, 56 } }, 20, { back = 48, leave = cat(MANSION_FLOOR, MANSION_WALL) }),
  piece("machine_2", { { 512, 28, 528, 56 } }, 20, { back = 48, leave = cat(MANSION_FLOOR, MANSION_WALL) }),
  piece("machine_3", { { 528, 28, 544, 56 } }, 20, { back = 48, leave = cat(MANSION_FLOOR, MANSION_WALL) }),
}
local function mansionFloor(f, more)
  local out = {}
  for i, b in ipairs(MANSION_WALLS[f]) do
    out[#out + 1] = piece("wall_" .. i, { { b[1], b[3] - 8, b[2], b[3] + 40 } }, 40,
      { foot = b[3] + 40, alone = true })
  end
  for _, pc in ipairs(more or {}) do table.insert(out, 1, pc) end
  return out
end

-- the S.S. Anne: its walls are white (in the cabins, papered) under a grey cornice and a white rim,
-- 24 rows from the cornice's top to the dark line at their foot (32 in the captain's office), read
-- off each deck's drawing as the Mansion's are: every pixel column drawn as the cornice (6 rows or
-- more, then the dark line) with the foot line that far below (or, a foot hidden, the white 12 rows
-- under the cornice), the columns with the same cornice row grouped, a gap of one door (16 px) or
-- less closed: the doors stand in the walls as drawn. Each { x0, x1 (exclusive), the cornice's
-- top } stands to its foot under the rim (8 rows: the wall's top). The stairs and the railings stay
-- as drawn
local ANNE_WALLS = {
  ["1F_CORRIDOR"] = { { 296, 328, 8 }, { 35, 286, 104 }, { 338, 480, 104 } },
  ["2F_CORRIDOR"] = { { 24, 80, 8 }, { 480, 509, 8 }, { 456, 478, 104 }, { 82, 446, 152 } },
  ["3F_CORRIDOR"] = { { 40, 336, 8 }, { 16, 30, 24 } },
  ["B1F_CORRIDOR"] = { { 16, 333, 24 } },
  ["1F_ROOM1"] = { { 0, 96, 8 } },
  ["2F_ROOM1"] = { { 0, 96, 8 } },
  ["KITCHEN"] = { { 24, 232, 8 } },
  ["CAPTAINS_OFFICE"] = { { 16, 112, 8 } },
}
-- its furniture: the cabins' tables, beds and chairs (each cabin layout serves every cabin of its
-- deck), the kitchen's three counters (a grey top 75 rows deep over 8 of front), the captain's
-- desk, chairs, bookshelf and bin. The plants are the Pokemon Center's
local ANNE_CABIN_1 = { "83b431", "accd31", "5a9c39" }
local ANNE_CABIN_2 = { "ffc562", "ffde9c", "deac62" }
local ANNE_WOOD = { "cdb47b", "a48b52", "836229" }
local ANNE_FURNITURE = {
  ["1F_ROOM1"] = {
    piece("table", { { 8, 84, 32, 128 } }, 8, { back = 92, leave = ANNE_CABIN_1 }),
    piece("chair", { { 36, 96, 48, 112 } }, 10, { leave = ANNE_CABIN_1 }),
    piece("bed", { { 62, 83, 82, 112 } }, 10, { back = 93, leave = ANNE_CABIN_1 }),
  },
  ["2F_ROOM1"] = {
    piece("table", { { 0, 37, 48, 72 } }, 8, { back = 45, leave = ANNE_CABIN_2 }),
    piece("chair", { { 16, 64, 28, 80 } }, 10, { leave = ANNE_CABIN_2 }),
    piece("bed", { { 62, 35, 82, 64 } }, 10, { back = 45, leave = ANNE_CABIN_2 }),
  },
  KITCHEN = {
    piece("counter_w", { { 48, 60, 80, 144 } }, 8, { back = 69, leave = ANNE_WOOD }),
    piece("counter_mid", { { 112, 60, 144, 144 } }, 8, { back = 69, leave = ANNE_WOOD }),
    piece("counter_e", { { 176, 60, 208, 144 } }, 8, { back = 69, leave = ANNE_WOOD }),
  },
  CAPTAINS_OFFICE = {
    piece("desk", { { 16, 53, 64, 80 } }, 8, { back = 61, leave = ANNE_WOOD }),
    piece("armchair", { { 24, 32, 48, 48 } }, 14, { leave = ANNE_WOOD }),
    piece("bin", { { 81, 44, 95, 64 } }, 13, { back = 57, leave = ANNE_WOOD }),
    piece("chair_1", { { 116, 96, 128, 112 } }, 10, { leave = ANNE_WOOD }),
    piece("chair_2", { { 116, 112, 128, 128 } }, 10, { leave = ANNE_WOOD }),
    piece("bookshelf", { { 112, 16, 128, 48 } }, 28, { leave = ANNE_WOOD }),
  },
}
local function anneRoom(r, tall, more)
  more = more or ANNE_FURNITURE[r]
  local out = {}
  for i, b in ipairs(ANNE_WALLS[r]) do
    out[#out + 1] = piece("wall_" .. i, { { b[1], b[3] - 8, b[2], b[3] + tall } }, tall,
      { foot = b[3] + tall, alone = true })
  end
  for _, pc in ipairs(more or {}) do table.insert(out, 1, pc) end
  return out
end

-- Trainer Tower's floors (18 x 17, every floor the same hall): its walls are blue-grey panels under
-- a white rim (6 rows: the wall's top), 26 rows from the panels' top to the grey line at their foot,
-- read as the Mansion's are (a column whose foot the stairs hide counts by its panel 12 rows down);
-- the alcove's lit console (its lights the floor's number: each floor's own) stands as a block 26
-- rows to its foot; the white posts, three to a column in two groups, are each a short post 9 rows
-- tall. The stairs stay as drawn
local TOWER_HALL_WALLS = { { 33, 96, 70 }, { 227, 256, 70 }, { 97, 128, 118 }, { 176, 207, 118 } }
local TT_FLOOR = { "ded55a", "bdb431", "d5cd5a", "c5bd41", "aca420" }
local function trainerTowerFloor(first)
  local out = {}
  if first then
    local cells = {}
    for _, cx in ipairs({ 3, 9, 15 }) do
      for _, cy in ipairs({ 9, 10, 11, 13, 14, 15 }) do
        if not (cx == 3 and cy == 9) then cells[#cells + 1] = { cx, cy } end
      end
    end
    table.insert(cells, 1, { 3, 10 })
    out[#out + 1] = piece("post", { { 48, 157, 64, 173 } }, 9, { leave = TT_FLOOR })
    out[#out + 1] = repeated("post_more", cells, 9, { leave = TT_FLOOR, shape = { { 48, 173, 64, 189 } } })
  end
  out[#out + 1] = piece("wall_console", { { 128, 112, 176, 160 } }, 26, { foot = 160, alone = true })
  for i, b in ipairs(TOWER_HALL_WALLS) do
    out[#out + 1] = piece("wall_" .. i, { { b[1], b[3] - 6, b[2], b[3] + 26 } }, 27,
      { foot = b[3] + 26, alone = true })
  end
  return out
end

-- ── Professor Oak's lab (Pallet Town) ─────────────────────────────────────
-- 13 x 14 (208 x 224 px; the engine names it FR_OAKS_LAB): its back wall a 7-row rim over 25 rows
-- of front to its foot at 32 (D5D5AC under a white rim, its skirting dark), the floor (metatile
-- 0x289) white with grey diagonals, a grey shade under the walls and the furniture. Against the
-- wall: the two machines (fronts 18 and 15 rows to 40), the yellow desks (5 rows of front to 38,
-- the PC and its tower standing at their back), the bookshelves (20 rows of front to 40). In the
-- room: the Poke Ball machine (its dome over a body to 96), the green table (7 rows of front and
-- legs to 92), two rows of bookshelves (20 rows of front to 152), the potted plants by the door
local LAB_FLOOR = { "eeeef6", "cdcdd5", "a4a4ac" }
local OAKS_LAB = {
  piece("machine_1", { { 0, 12, 16, 40 } }, 18, { back = 32, leave = LAB_FLOOR }),
  piece("machine_2", { { 16, 18, 32, 40 } }, 15, { back = 32, leave = LAB_FLOOR }),
  piece("desks", { { 32, 14, 96, 38 } }, 5, { back = 32, leave = cat({ "d5d5ac" }, LAB_FLOOR) }),
  piece("shelves_back", { { 144, 10, 208, 40 } }, 20, { back = 32, leave = cat({ "d5d5ac" }, LAB_FLOOR) }),
  piece("ball_machine", { { 16, 56, 48, 96 } }, 22, { leave = LAB_FLOOR }),
  piece("table", { { 129, 67, 175, 68 }, { 128, 68, 176, 92 } }, 7, { back = 74, leave = LAB_FLOOR }),
  piece("shelves_w", { { 0, 121, 80, 152 } }, 20, { back = 141, leave = LAB_FLOOR }),
  piece("shelves_e", { { 128, 121, 208, 152 } }, 20, { back = 141, leave = LAB_FLOOR }),
  piece("plant_w", { { 0, 176, 16, 208 } }, 28, { card = true, leave = LAB_FLOOR }),
  piece("plant_e", { { 192, 176, 208, 208 } }, 28, { card = true, leave = LAB_FLOOR }),
  piece("wall", { { 0, 0, 208, 32 } }, 25, { foot = 32, alone = true }),
}

-- ── Celadon's Game Corner ─────────────────────────────────────────────────
-- 18 x 15 (288 x 240 px): the back wall a 4-row rim over 28 rows of front (sky blue over a salmon
-- band) to its foot at 32; the floor orange (metatile 0x291) with darker shade under the walls and
-- the furniture. The prize counter: a green L each side (its top from row 24, 10 rows of front to
-- 64), the shelves on it standing at its back against the wall, a glass case between (6 rows of
-- front); the purple counter (18 rows of front to 80); four columns of slot machines, two-sided,
-- each a block (16 rows of front to 176; the outer two half drawn at the room's edges) with stools
-- either side (30, five a column: a blue seat over 5 rows of legs); the plants and the machine by
-- the door
local GC_FLOOR = { "d5a400", "e6b400", "e6c541", "c57b00", "b46200", "cd8b00" }
-- a slot column's outline (its west edge x0, 32 px wide, clipped to the room): its top's corners cut
-- on the diagonal from 8 px in at row 82 to the side at 93
local function slotsTop(x0, west, east)
  local p = {}
  if west then p[#p + 1] = { x0, 93 }; p[#p + 1] = { x0 + 8, 82 } else p[#p + 1] = { 0, 82 } end
  if east then p[#p + 1] = { x0 + 24, 82 }; p[#p + 1] = { x0 + 32, 93 }; p[#p + 1] = { x0 + 32, 176 }
  else p[#p + 1] = { 288, 82 }; p[#p + 1] = { 288, 176 } end
  p[#p + 1] = { west and x0 or 0, 176 }
  return p
end
local function gameCorner()
  local stools = {}
  for _, cx in ipairs({ 1, 4, 7, 10, 13, 16 }) do
    for cy = 6, 10 do stools[#stools + 1] = { cx, cy } end
  end
  return {
    piece("prize_w", { { 16, 7, 64, 64 } }, 10, { back = 32, leave = GC_FLOOR }),
    piece("prize_e", { { 112, 7, 160, 64 } }, 10, { back = 32, leave = GC_FLOOR }),
    piece("glass_case", { { 64, 44, 112, 64 } }, 6, { back = 50, leave = GC_FLOOR }),
    piece("counter", { { 224, 51, 288, 80 } }, 18, { back = 69, leave = GC_FLOOR }),
    -- (a column's top cut on the diagonal at its corners: its machines' side panels)
    piece("slots_1", { slotsTop(80, true, true) }, 16, { back = 98, leave = GC_FLOOR }),
    piece("slots_2", { slotsTop(176, true, true) }, 16, { back = 98, leave = GC_FLOOR }),
    piece("slots_w", { slotsTop(-16, false, true) }, 16, { back = 98, leave = GC_FLOOR }),
    piece("slots_e", { slotsTop(272, true, false) }, 16, { back = 98, leave = GC_FLOOR }),
    repeated("stool", stools, 5, { back = 104, leave = GC_FLOOR, shape = { { 18, 99, 30, 112 } } }),
    piece("plant_n", { { 0, 18, 16, 48 } }, 28, { card = true, leave = GC_FLOOR }),
    piece("plant_s", { { 0, 194, 16, 224 } }, 28, { card = true, leave = GC_FLOOR }),
    piece("machine", { { { 279, 194 }, { 288, 194 }, { 288, 224 }, { 272, 224 }, { 272, 208 } } }, 20,
      { back = 214, leave = GC_FLOOR }),
    piece("wall", { { 0, 0, 288, 32 } }, 28, { foot = 32, alone = true }),
  }
end

-- the S.S. Anne's deck (24 x 19, 384 x 304 px; sailors battle there): the cabin on its east side,
-- a block (its purple roof from row 64, 32 rows of white front and portholes to 208; its west face,
-- drawn light, and the doors' notch in it lie on its top), the two stacks of barrels by it (16 rows
-- of barrel side under their tops), the two deck chairs and three round tables (white tops over 6
-- rows of legs). The railings and the hull stay as drawn
local DECK = { "cdb47b", "a48b52", "836229" }
local ANNE_DECK = {
  piece("cabin", { { 256, 64, 384, 208 } }, 32, { back = 96, leave = DECK }),
  -- (each row of barrels its own block: a block's top is its bounds')
  piece("barrels_n_back", { { 224, 68, 256, 95 } }, 12, { back = 80, leave = DECK }),
  piece("barrels_n_front", { { 240, 89, 256, 111 } }, 12, { back = 101, leave = DECK }),
  piece("barrels_s_back", { { 240, 185, 256, 201 } }, 12, { back = 197, leave = DECK }),
  piece("barrels_s_front", { { 224, 201, 256, 217 } }, 12, { back = 213, leave = DECK }),
  piece("chair_n", { { 144, 96, 160, 128 } }, 8, { back = 104, leave = DECK }),
  piece("chair_s", { { 144, 177, 160, 208 } }, 8, { back = 185, leave = DECK }),
  piece("table_1", { { 128, 112, 145, 128 } }, 6, { back = 118, leave = DECK }),
  piece("table_2", { { 192, 112, 209, 128 } }, 6, { back = 118, leave = DECK }),
  piece("table_3", { { 160, 192, 177, 208 } }, 6, { back = 198, leave = DECK }),
}

-- ── the Tanoby Chambers (Seven Island; wild Unown) ───────────────────────────
-- Every chamber is 23 x 17 (368 x 272 px) round a maze of teal stone walls: each wall a group of
-- the layout's blocked cells, its light top drawn from 13 rows above its cells over 19 rows of
-- dark dotted front to their foot (read off the metatile grid by rule - blocked cells inside the
-- room, 4-connected - and kept as cell lists, as Viridian's gym's); the brick back wall, 22 rows of
-- front to 32 under its top. The sand round the room and its thin side walls stay as drawn
local TANOBY_FLOOR = { "cdd59c", "a4ac8b", "b4c59c", "a4ac9c", "8b9c8b" }
local TANOBY_SIDE = { 120, 61, 136, 80 }
local TANOBY_WALLS = {
  DILFORD = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 3, 5 }, { 3, 6 }, { 3, 7 }, { 3, 8 }, { 3, 9 }, { 3, 10 }, { 3, 11 }, { 3, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 10, 13 } },
    { { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 }, { 19, 8 }, { 19, 9 }, { 19, 10 }, { 19, 11 }, { 19, 12 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 }, { 9, 7 }, { 10, 7 } },
    { { 12, 7 }, { 13, 7 }, { 14, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 } },
    { { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 }, { 9, 10 }, { 10, 10 } },
    { { 12, 10 }, { 13, 10 }, { 14, 10 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
  },
  LIPTOO = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 3, 5 }, { 3, 6 }, { 3, 7 }, { 3, 8 }, { 3, 9 }, { 3, 10 }, { 3, 11 }, { 3, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 10, 13 } },
    { { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 }, { 19, 8 }, { 19, 9 }, { 19, 10 }, { 19, 11 }, { 19, 12 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 }, { 5, 8 }, { 5, 9 }, { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 }, { 9, 10 }, { 10, 10 }, { 11, 10 }, { 12, 10 }, { 13, 10 } },
    { { 10, 7 }, { 11, 7 }, { 12, 7 }, { 13, 7 }, { 14, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
  },
  MONEAN = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 3, 5 }, { 3, 6 }, { 3, 7 } },
    { { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 }, { 9, 7 }, { 10, 7 }, { 5, 8 }, { 5, 9 }, { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 }, { 9, 10 }, { 10, 10 } },
    { { 12, 7 }, { 13, 7 }, { 14, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 12, 10 }, { 13, 10 }, { 14, 10 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
    { { 3, 10 }, { 3, 11 }, { 3, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 10, 13 } },
    { { 19, 10 }, { 19, 11 }, { 19, 12 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
  },
  RIXY = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 3, 5 }, { 3, 6 }, { 3, 7 }, { 3, 8 }, { 3, 9 }, { 3, 10 }, { 3, 11 }, { 3, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 10, 13 } },
    { { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 }, { 19, 8 }, { 19, 9 }, { 19, 10 }, { 19, 11 }, { 19, 12 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 5, 8 }, { 5, 9 }, { 5, 10 }, { 6, 10 }, { 7, 10 } },
    { { 9, 7 }, { 10, 7 }, { 11, 7 }, { 12, 7 }, { 13, 7 } },
    { { 15, 7 }, { 16, 7 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
    { { 9, 10 }, { 10, 10 }, { 11, 10 }, { 12, 10 }, { 13, 10 } },
  },
  SCUFIB = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 3, 5 }, { 3, 6 }, { 3, 7 } },
    { { 9, 4 }, { 10, 4 }, { 11, 4 }, { 12, 4 }, { 13, 4 } },
    { { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 }, { 9, 7 }, { 10, 7 }, { 5, 8 }, { 5, 9 }, { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 }, { 9, 10 }, { 10, 10 } },
    { { 12, 7 }, { 13, 7 }, { 14, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 12, 10 }, { 13, 10 }, { 14, 10 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
    { { 3, 10 }, { 3, 11 }, { 3, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 } },
    { { 19, 10 }, { 19, 11 }, { 19, 12 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
    { { 9, 13 }, { 10, 13 }, { 11, 13 }, { 12, 13 }, { 13, 13 } },
  },
  VIAPOIS = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 3, 5 }, { 3, 6 }, { 3, 7 } },
    { { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 19, 5 }, { 19, 6 }, { 19, 7 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 }, { 9, 7 }, { 10, 7 }, { 11, 7 }, { 12, 7 }, { 13, 7 }, { 14, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 }, { 5, 8 }, { 17, 8 }, { 5, 9 }, { 17, 9 }, { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 }, { 9, 10 }, { 10, 10 }, { 12, 10 }, { 13, 10 }, { 14, 10 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
    { { 3, 10 }, { 19, 10 }, { 3, 11 }, { 19, 11 }, { 3, 12 }, { 19, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 10, 13 }, { 11, 13 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
  },
  WEEPTH = {
    { { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 11, 4 }, { 12, 4 }, { 13, 4 }, { 14, 4 }, { 15, 4 }, { 16, 4 }, { 17, 4 }, { 18, 4 }, { 19, 4 }, { 3, 5 }, { 19, 5 }, { 3, 6 }, { 19, 6 }, { 3, 7 }, { 19, 7 } },
    { { 5, 7 }, { 6, 7 }, { 7, 7 }, { 8, 7 }, { 9, 7 }, { 10, 7 }, { 5, 8 }, { 5, 9 }, { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 }, { 9, 10 }, { 10, 10 } },
    { { 12, 7 }, { 13, 7 }, { 14, 7 }, { 15, 7 }, { 16, 7 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 12, 10 }, { 13, 10 }, { 14, 10 }, { 15, 10 }, { 16, 10 }, { 17, 10 } },
    { { 3, 10 }, { 19, 10 }, { 3, 11 }, { 19, 11 }, { 3, 12 }, { 19, 12 }, { 3, 13 }, { 4, 13 }, { 5, 13 }, { 6, 13 }, { 7, 13 }, { 8, 13 }, { 9, 13 }, { 10, 13 }, { 11, 13 }, { 12, 13 }, { 13, 13 }, { 14, 13 }, { 15, 13 }, { 16, 13 }, { 17, 13 }, { 18, 13 }, { 19, 13 } },
  },
}
local function tanobyChamber(name)
  local out = { piece("wall", { { 16, 0, 352, 32 } }, 22, { foot = 32, alone = true }) }
  for i, cells in ipairs(TANOBY_WALLS[name]) do
    out[#out + 1] = gymBlock("block_" .. i, cells, 19, 13, TANOBY_SIDE, TANOBY_FLOOR)
  end
  return out
end

local ROOMS = {
  { name = "fr_pc1f", interior = { layout = "LAYOUT_CELADON_CITY_POKEMON_CENTER_1F", ground = { 0x281 },
                                   pieces = CENTER_1F, open = CENTER_OPEN } },
  { name = "fr_pc2f", interior = { layout = "LAYOUT_CELADON_CITY_POKEMON_CENTER_2F", ground = { 0x281 },
                                   pieces = CENTER_2F, open = CENTER_OPEN } },
  { name = "fr_mart", interior = { layout = "LAYOUT_CERULEAN_CITY_MART", ground = { 0x281 }, pieces = MART,
                                   open = MART_OPEN } },
  { name = "fr_oaks_lab", interior = { layout = "LAYOUT_OAKS_LAB", ground = { 0x289 }, pieces = OAKS_LAB } },
  { name = "fr_tanoby_monean", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_MONEAN_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("MONEAN") } },
  { name = "fr_tanoby_liptoo", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_LIPTOO_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("LIPTOO") } },
  { name = "fr_tanoby_weepth", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_WEEPTH_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("WEEPTH") } },
  { name = "fr_tanoby_dilford", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_DILFORD_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("DILFORD") } },
  { name = "fr_tanoby_scufib", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_SCUFIB_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("SCUFIB") } },
  { name = "fr_tanoby_rixy", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_RIXY_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("RIXY") } },
  { name = "fr_tanoby_viapois", interior = { layout = "LAYOUT_SEVEN_ISLAND_TANOBY_RUINS_VIAPOIS_CHAMBER", ground = { 0x288 },
                                          pieces = tanobyChamber("VIAPOIS") } },
  { name = "fr_anne_deck", interior = { layout = "LAYOUT_SSANNE_DECK", ground = { 0x350 }, pieces = ANNE_DECK } },
  { name = "fr_game_corner", interior = { layout = "LAYOUT_CELADON_CITY_GAME_CORNER", ground = { 0x291 },
                                          pieces = gameCorner() } },
  { name = "fr_pewter_gym", interior = { layout = "LAYOUT_PEWTER_CITY_GYM", ground = { 0x294 }, pieces = pewterGym() } },
  { name = "fr_vermilion_gym", interior = { layout = "LAYOUT_VERMILION_CITY_GYM", ground = { 0x281 }, pieces = vermilionGym() } },
  { name = "fr_celadon_gym", interior = { layout = "LAYOUT_CELADON_CITY_GYM", ground = { 0x281 }, pieces = celadonGym() } },
  { name = "fr_cerulean_gym", interior = { layout = "LAYOUT_CERULEAN_CITY_GYM", ground = { 0x281 }, pieces = ceruleanGym() } },
  { name = "fr_fuchsia_gym", interior = { layout = "LAYOUT_FUCHSIA_CITY_GYM", ground = { 0x281 }, pieces = fuchsiaGym() } },
  { name = "fr_viridian_gym", interior = { layout = "LAYOUT_VIRIDIAN_CITY_GYM", ground = { 0x281 }, pieces = viridianGym() } },
  { name = "fr_saffron_gym", interior = { layout = "LAYOUT_SAFFRON_CITY_GYM", ground = { 0x281 }, pieces = saffronGym() } },
  { name = "fr_cinnabar_gym", interior = { layout = "LAYOUT_CINNABAR_ISLAND_GYM", ground = { 0x281 }, pieces = cinnabarGym() } },
  { name = "fr_loreleis_room", interior = { layout = "LAYOUT_POKEMON_LEAGUE_LORELEIS_ROOM", ground = { 0x2A8 },
                                            pieces = eliteFourRoom({ "6294c5", "83acde", "8bc5e6" }) } },
  { name = "fr_brunos_room", interior = { layout = "LAYOUT_POKEMON_LEAGUE_BRUNOS_ROOM", ground = { 0x2D0 },
                                          pieces = eliteFourRoom({ "bdb45a", "d5cd6a", "e6de7b" }) } },
  { name = "fr_agathas_room", interior = { layout = "LAYOUT_POKEMON_LEAGUE_AGATHAS_ROOM", ground = { 0x2F0 },
                                           pieces = eliteFourRoom({ "bd94e6", "cdb4ee", "a483cd" }) } },
  { name = "fr_lances_room", interior = { layout = "LAYOUT_POKEMON_LEAGUE_LANCES_ROOM", ground = { 0x310 },
                                          pieces = lancesRoom() } },
  { name = "fr_champions_room", interior = { layout = "LAYOUT_POKEMON_LEAGUE_CHAMPIONS_ROOM", ground = { 0x38F },
                                             pieces = championsRoom() } },
  { name = "fr_silph_2f", interior = { layout = "LAYOUT_SILPH_CO_2F", ground = { 0x334 }, pieces = silphFloor("2F", SILPH_2F) } },
  { name = "fr_silph_1f", interior = { layout = "LAYOUT_SILPH_CO_1F", ground = { 0x334 }, pieces = silphFloor("1F") } },
  { name = "fr_silph_3f", interior = { layout = "LAYOUT_SILPH_CO_3F", ground = { 0x334 }, pieces = silphFloor("3F") } },
  { name = "fr_silph_4f", interior = { layout = "LAYOUT_SILPH_CO_4F", ground = { 0x334 }, pieces = silphFloor("4F") } },
  { name = "fr_silph_5f", interior = { layout = "LAYOUT_SILPH_CO_5F", ground = { 0x334 }, pieces = silphFloor("5F") } },
  { name = "fr_silph_6f", interior = { layout = "LAYOUT_SILPH_CO_6F", ground = { 0x334 }, pieces = silphFloor("6F") } },
  { name = "fr_silph_7f", interior = { layout = "LAYOUT_SILPH_CO_7F", ground = { 0x334 }, pieces = silphFloor("7F") } },
  { name = "fr_silph_8f", interior = { layout = "LAYOUT_SILPH_CO_8F", ground = { 0x334 }, pieces = silphFloor("8F") } },
  { name = "fr_silph_9f", interior = { layout = "LAYOUT_SILPH_CO_9F", ground = { 0x334 }, pieces = silphFloor("9F") } },
  { name = "fr_silph_10f", interior = { layout = "LAYOUT_SILPH_CO_10F", ground = { 0x334 }, pieces = silphFloor("10F") } },
  { name = "fr_silph_11f", interior = { layout = "LAYOUT_SILPH_CO_11F", ground = { 0x334 }, pieces = silphFloor("11F") } },
  { name = "fr_tower_3f", interior = { layout = "LAYOUT_POKEMON_TOWER_3F", ground = { 0x282 }, pieces = towerFloor(TOWER_STEPS, TOWER_3F) } },
  { name = "fr_tower_7f", interior = { layout = "LAYOUT_POKEMON_TOWER_7F", ground = { 0x282 }, pieces = towerFloor(TOWER_STEPS, TOWER_7F) } },
  { name = "fr_tower_1f", interior = { layout = "LAYOUT_POKEMON_TOWER_1F", ground = { 0x282 }, pieces = towerFloor(TOWER_1F_STEPS) } },
  { name = "fr_tower_2f", interior = { layout = "LAYOUT_POKEMON_TOWER_2F", ground = { 0x282 }, pieces = towerFloor(TOWER_STEPS) } },
  { name = "fr_tower_4f", interior = { layout = "LAYOUT_POKEMON_TOWER_4F", ground = { 0x282 }, pieces = towerFloor(TOWER_STEPS) } },
  { name = "fr_tower_5f", interior = { layout = "LAYOUT_POKEMON_TOWER_5F", ground = { 0x282 }, pieces = towerFloor(TOWER_STEPS) } },
  { name = "fr_tower_6f", interior = { layout = "LAYOUT_POKEMON_TOWER_6F", ground = { 0x282 }, pieces = towerFloor(TOWER_STEPS) } },
  { name = "fr_dojo", interior = { layout = "LAYOUT_SAFFRON_CITY_DOJO", ground = { 0x2C0 }, pieces = dojo() } },
  { name = "fr_mansion_1f", interior = { layout = "LAYOUT_POKEMON_MANSION_1F", ground = { 0x284 }, pieces = mansionFloor("1F", MANSION_1F) } },
  { name = "fr_mansion_2f", interior = { layout = "LAYOUT_POKEMON_MANSION_2F", ground = { 0x284 }, pieces = mansionFloor("2F", MANSION_2F) } },
  { name = "fr_mansion_3f", interior = { layout = "LAYOUT_POKEMON_MANSION_3F", ground = { 0x284 }, pieces = mansionFloor("3F") } },
  { name = "fr_mansion_b1f", interior = { layout = "LAYOUT_POKEMON_MANSION_B1F", ground = { 0x284 }, pieces = mansionFloor("B1F") } },
  { name = "fr_anne_1f_corridor", interior = { layout = "LAYOUT_SSANNE_1F_CORRIDOR", ground = { 0x298 }, pieces = anneRoom("1F_CORRIDOR", 24) } },
  { name = "fr_anne_2f_corridor", interior = { layout = "LAYOUT_SSANNE_2F_CORRIDOR", ground = { 0x298 }, pieces = anneRoom("2F_CORRIDOR", 24) } },
  { name = "fr_anne_3f_corridor", interior = { layout = "LAYOUT_SSANNE_3F_CORRIDOR", ground = { 0x298 }, pieces = anneRoom("3F_CORRIDOR", 24) } },
  { name = "fr_anne_b1f_corridor", interior = { layout = "LAYOUT_SSANNE_B1F_CORRIDOR", ground = { 0x298 }, pieces = anneRoom("B1F_CORRIDOR", 24) } },
  { name = "fr_anne_1f_cabin", interior = { layout = "LAYOUT_SSANNE_1F_ROOM1", ground = { 0x31C }, pieces = anneRoom("1F_ROOM1", 24) } },
  { name = "fr_anne_2f_cabin", interior = { layout = "LAYOUT_SSANNE_2F_ROOM1", ground = { 0x324 }, pieces = anneRoom("2F_ROOM1", 24) } },
  { name = "fr_anne_kitchen", interior = { layout = "LAYOUT_SSANNE_KITCHEN", ground = { 0x299 }, pieces = anneRoom("KITCHEN", 24) } },
  { name = "fr_anne_captains_office", interior = { layout = "LAYOUT_SSANNE_CAPTAINS_OFFICE", ground = { 0x298 }, pieces = anneRoom("CAPTAINS_OFFICE", 32) } },
  { name = "fr_trainer_tower_1f", interior = { layout = "LAYOUT_TRAINER_TOWER_1F", ground = { 0x2EE }, pieces = trainerTowerFloor(true) } },
  { name = "fr_trainer_tower_2f", interior = { layout = "LAYOUT_TRAINER_TOWER_2F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_trainer_tower_3f", interior = { layout = "LAYOUT_TRAINER_TOWER_3F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_trainer_tower_4f", interior = { layout = "LAYOUT_TRAINER_TOWER_4F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_trainer_tower_5f", interior = { layout = "LAYOUT_TRAINER_TOWER_5F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_trainer_tower_6f", interior = { layout = "LAYOUT_TRAINER_TOWER_6F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_trainer_tower_7f", interior = { layout = "LAYOUT_TRAINER_TOWER_7F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_trainer_tower_8f", interior = { layout = "LAYOUT_TRAINER_TOWER_8F", ground = { 0x2EE }, pieces = trainerTowerFloor(false) } },
  { name = "fr_rocket_b1f", interior = { layout = "LAYOUT_ROCKET_HIDEOUT_B1F", ground = { 0x281 }, pieces = rocketFloor("B1F") } },
  { name = "fr_rocket_b2f", interior = { layout = "LAYOUT_ROCKET_HIDEOUT_B2F", ground = { 0x281 }, pieces = rocketFloor("B2F") } },
  { name = "fr_rocket_b3f", interior = { layout = "LAYOUT_ROCKET_HIDEOUT_B3F", ground = { 0x281 }, pieces = rocketFloor("B3F") } },
  { name = "fr_rocket_b4f", interior = { layout = "LAYOUT_ROCKET_HIDEOUT_B4F", ground = { 0x281 }, pieces = rocketFloor("B4F") } },
}

ROOMS.ids = {}
ROOMS.swaps = {}

return ROOMS
