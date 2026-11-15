-- FireRed's (and LeafGreen's) own tables for the relief (Battle Scene: Overworld): what Emerald 3DS's
-- relief generator names in Emerald's General tileset, read here off FireRed's own drawing by the
-- same method (src/scene/relief_solve.lua, Solve.useGame; src/scene/roles.lua, Roles.useGame).
-- WoobleView's own reading: ids, colours and roles only - nothing of the cartridge's.
--
-- How it was read. FireRed's General tileset draws its rock as Emerald's does, a top, a rim, a
-- south face and its bands, but with its own art in its own places:
--   * the colours: palette 1, slots 9-14, as Emerald's palette 3 slots 9-14 (the same roles, the
--     slot for slot): rim EED5C5, tops DEC5A4 and BD948B, fleck 946A6A, faces 7B4A4A and 5A3941
--     (Emerald's darkest face, slot 8, is a grey in FireRed's palette and no rock's);
--   * the pieces, where they stand on Route 3, Route 4, Mt Moon's slopes and Route 22:
--       top        071
--       south face 07C (its upper row) and 079 (its foot), whose ends are 078 / 07A (the foot's)
--                  and 07B / 07D (the upper row's), and their corners 0B2 / 0B3; 090 / 092 the
--                  foot's ends over sand
--       west band  070 (the outer column) and 073 (the inner); 088 the inner over sand
--       east band  072 (the outer) and 075 (the inner); 08A the outer over sand
--   The rest of the rock (the north rims 068-06D, the rims' turns 0BA / 0BB) is read pixel by
--   pixel against these, as Emerald 3DS reads its own.

local F = {}

F.general = "fr:general"     -- (the family's name for it: src/scene/family.lua)
F.primary = 640              -- (where the primary's metatiles end)

local function rgb(r, g, b) return r * 65536 + g * 256 + b end

F.rock = {
  top = { rgb(0xDE, 0xC5, 0xA4), rgb(0xBD, 0x94, 0x8B) },
  rim = { rgb(0xEE, 0xD5, 0xC5) },
  face = { rgb(0x7B, 0x4A, 0x4A), rgb(0x5A, 0x39, 0x41) },
  fleck = { rgb(0x94, 0x6A, 0x6A) },
}

-- the reference pieces drawn_role matches the rest against, in order
F.lists = {
  FACE_SOUTH = { 0x07C, 0x079, 0x078, 0x07A, 0x090, 0x092 },
  SIDE_WEST = { 0x070, 0x073, 0x088 },
  SIDE_EAST = { 0x072, 0x075, 0x08A },
}

-- the rock a map must hold to be read as drawn (with the lists' ids)
F.rockTiles = { 0x07B, 0x07D, 0x0B2, 0x0B3 }

-- the General rock's range: a cliff's corner standing free is never a signpost
F.mountainRock = { 0x068, 0x0BF }

-- The terraces (src/scene/relief_terraces*.lua: Emerald 3DS's counted levels), read off the same
-- pieces. FireRed keeps Emerald's arrangement of the General's rock for its rims, bands and face
-- ends (Emerald's General is FireRed's redrawn), so most roles sit at the same ids; where they do
-- not, FireRed's own:
--   * rims over pale beach sand 098 / 099 / 09A, their bands 0A0 (west) and 0A2 (east), the
--     face's foot ends there 0A8 / 0AA; 0A1 a west band at a sand edge;
--   * 074 is drawn black and 089 a stair (Emerald's band heads): FireRed draws no band head, so
--     none is named;
--   * the stairs cut into a face: 089 (at its foot) and 091 (up it);
--   * a face drawn with a tree in front of it 0B4 / 0B5, and the cave's mouth 0A9;
--   * the side ledges 083-086 / 08B-08E, the sand ledges 08F / 097 / 0B8 / 0B9 and the ledge 087,
--     0B0 / 0B1 are ledges, not rock (the game jumps them); the round boulders 09F / 0A7 / 0AF /
--     0B7 stand alone on the ground, not on a terrace.
-- The trees: tip 00E / 00F, crowns 00A-00D and 01A-01F, bases 014-017 and 024-027; small trees
-- 012 / 022 and 013 / 023. The mountain outline's grey: 7B7B83 (palette 1 slot 4, Emerald's
-- 83838B).
local function range(a, b, out)
  out = out or {}
  for m = a, b do out[#out + 1] = m end
  return out
end
local notRock = {}
for _, m in ipairs({ 0x074, 0x083, 0x084, 0x085, 0x086, 0x087, 0x08B, 0x08C, 0x08D, 0x08E, 0x08F, 0x093, 0x094,
                     0x095, 0x096, 0x097, 0x09B, 0x09C, 0x09D, 0x09E, 0x09F, 0x0A3, 0x0A4, 0x0A5, 0x0A6, 0x0A7,
                     0x0AB, 0x0AC, 0x0AD, 0x0AE, 0x0AF, 0x0B0, 0x0B1, 0x0B7, 0x0B8, 0x0B9, 0x0BC, 0x0BD, 0x0BE,
                     0x0BF }) do notRock[m] = true end
local mountain = {}
for m = 0x068, 0x0BF do if not notRock[m] then mountain[#mountain + 1] = m end end

F.terraces = {
  bandWest = { 0x070, 0x073, 0x088, 0x06B, 0x080, 0x068, 0x098, 0x0A0, 0x0A1 },
  bandEast = { 0x072, 0x075, 0x08A, 0x06D, 0x082, 0x06A, 0x09A, 0x0A2 },
  heads = { [0x068] = "W", [0x080] = "W", [0x098] = "W", [0x06A] = "E", [0x082] = "E", [0x09A] = "E" },
  headsSorted = { 0x068, 0x06A, 0x080, 0x082, 0x098, 0x09A },
  onTop = {}, boulderFoot = {}, boulderHead = {}, loose = {},
  carvedSteps = { 0x089, 0x091 },
  upperEnd = {},
  lowerEnd = { 0x07D, 0x07B, 0x078, 0x07A, 0x092, 0x090, 0x0A8, 0x0AA },
  bandHead = { E = {}, W = {} },
  bandFoot = { E = { 0x07A, 0x07D, 0x092, 0x0AA }, W = { 0x07B, 0x078, 0x090, 0x0A8 } },
  mountain = mountain,
  smallTrunks = { 0x022, 0x023 },
  treeCards = range(0x00A, 0x00F, range(0x012, 0x017, range(0x01A, 0x01F, range(0x022, 0x027)))),
  ownTrunks = {},
  faces = { 0x07C, 0x0A9, 0x079, 0x0B4, 0x0B5 },
  outlineGrey = { rgb(0x7B, 0x7B, 0x83) },
  canopyTop = 0x00E,
  sideFace = { W = 0x070, E = 0x072 },
  headDrawn = { W = 0x068, E = 0x06A },
  plainTop = 0x071,
  -- every map read as drawn is rebuilt terrace by terrace (Emerald's are a chosen list)
  groups = "drawn",
}

-- The caves (src/scene/relief_caves.lua). FireRed's cave tilesets (Mt Moon's, Rock Tunnel's,
-- Cerulean Cave's, Diglett's Cave's, Seafoam's, Mt Ember's, Navel Rock's) draw their rock alike up
-- to 2E0, each in its own colours, the same piece at the same id; past it each has its own. Read
-- off Mt Moon's, Victory Road's and Rock Tunnel's drawing, and each shared piece checked in every
-- cave tileset against Mt Moon's by its pixels (its top, face and floor colours):
--   * a block of rock: its rim 289 (the top's north edge, the ground behind showing past it) and
--     its corners 288 / 28A (each the head of the side under it, falling as it does), its top 291,
--     its sides 290 (west) / 292 (east), a slope a tile across a level; its south face 299 and the face's
--     ends 298 / 29A; the inside corners 29B (the rock north and west) and 29C (north and east);
--     the outer walls' faces 2C3-2C5 / 2CE and sides 2C6 (west) / 2C7 (east); faces drawn with a
--     cave mouth 28C, stairs 284 (and the General's 091, Cerulean Cave's), a ladder 28F, falls
--     2EE / 2EF;
--   * a thin wall (a path on the rock, its sides sheer): its rim 2DF, 29D / 29E and 2F0 / 2F1 its
--     corners, 2EA / 2EB its head against a taller face; its sides 2E6 / 2A5 (west), 2E7 (east);
--   * a raised floor: its rim 2D0 / 2D1 / 2D2 (and 2B5 / 2B6, 2C8-2CA, 2D7 along a rim), its floor
--     2D8-2DA, 2E0-2E2, faced as a block;
--   * the dark past the rock 280 / 2F2;
--   * the floor 281, the sand, the boulders, ladders and holes: flat.
F.caves = {
  layouts = { "LAYOUT_MT_MOON_", "LAYOUT_VICTORY_ROAD_", "LAYOUT_ROCK_TUNNEL_", "LAYOUT_CERULEAN_CAVE_",
              "LAYOUT_DIGLETTS_CAVE_", "LAYOUT_SEAFOAM_ISLANDS_", "LAYOUT_FIVE_ISLAND_LOST_CAVE_",
              "LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL", "LAYOUT_SIX_ISLAND_ALTERING_CAVE",
              "LAYOUT_FOUR_ISLAND_ICEFALL_CAVE_", "LAYOUT_MT_EMBER_RUBY_PATH_", "LAYOUT_MT_EMBER_SUMMIT_PATH_",
              "LAYOUT_NAVEL_ROCK_", "LAYOUT_SIX_ISLAND_DOTTED_HOLE_", "LAYOUT_MT_EMBER_EXTERIOR$",
              "LAYOUT_MT_EMBER_SUMMIT$" },
  face = 0x299,
  ground = 0x281,
  -- (water besides the relief's own: Seafoam's currents and fast water, drawn as water)
  water = { "MB_FAST_WATER", "MB_EASTWARD_CURRENT", "MB_WESTWARD_CURRENT", "MB_NORTHWARD_CURRENT",
            "MB_SOUTHWARD_CURRENT" },
  -- the pieces every cave tileset draws alike (a mouth drawn on a face, 294, is the face)
  pieces = {
    [0x299] = "F", [0x28B] = "F", [0x28D] = "F", [0x293] = "F", [0x295] = "F", [0x2C3] = "F", [0x2C4] = "F",
    [0x2C5] = "F", [0x2CE] = "F", [0x284] = "F", [0x28C] = "F", [0x28F] = "F",
    [0x2EE] = "F", [0x2EF] = "F", [0x091] = "F", [0x294] = "F",
    [0x290] = "W", [0x2C6] = "W", [0x292] = "E", [0x2C7] = "E",
    [0x298] = "SW", [0x29A] = "SE", [0x29B] = "FE", [0x29C] = "FW",
    [0x289] = "N", [0x2D1] = "N", [0x2C8] = "N", [0x2C9] = "N", [0x2CA] = "N", [0x2D7] = "N", [0x2B5] = "N",
    [0x2B6] = "N", [0x2DF] = "N",
    [0x288] = "HW", [0x28A] = "HE", [0x2D0] = "NW", [0x2EA] = "NW", [0x29D] = "NW", [0x2F0] = "NW",
    [0x2D2] = "NE", [0x2EB] = "NE", [0x29E] = "NE", [0x2F1] = "NE",
    [0x2E6] = "TW", [0x2A5] = "TW", [0x2E7] = "TE",
    [0x280] = "void", [0x2F2] = "void",
  },
  -- and each tileset's own (its layouts by name): where the tilesets part, past 2E0
  groups = {
    -- Mt Moon's (Victory Road, the Lost Cave, the Dunsparce Tunnel) and Mt Ember's
    { layouts = { "LAYOUT_MT_MOON_", "LAYOUT_VICTORY_ROAD_", "LAYOUT_FIVE_ISLAND_LOST_CAVE_",
                  "LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL", "LAYOUT_MT_EMBER_RUBY_PATH_", "LAYOUT_MT_EMBER_SUMMIT_PATH_" },
      pieces = { [0x2E3] = "F", [0x2E4] = "F", [0x2E5] = "F", [0x2ED] = "W", [0x2EC] = "E" } },
    -- Mt Moon's alone (its side walls' tunnel mouths, the Lost Cave's, drawn on the side: 30A east, 309 west)
    { layouts = { "LAYOUT_MT_MOON_", "LAYOUT_VICTORY_ROAD_", "LAYOUT_FIVE_ISLAND_LOST_CAVE_",
                  "LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL" },
      pieces = { [0x2A3] = "N", [0x2A4] = "N",
                 [0x310] = "F", [0x311] = "F", [0x312] = "F", [0x314] = "F", [0x315] = "W", [0x313] = "W", [0x30D] = "W",
                 [0x316] = "E", [0x30E] = "E", [0x31E] = "E", [0x319] = "TW", [0x31A] = "TE", [0x30A] = "E", [0x309] = "W" } },
    -- Seafoam's (and the Icefall Cave's): a raised floor's west side over the sand 365 / 35D, its
    -- face's west end there 36D; the outer rock's tops rimmed where its side steps 355 / 356, and along
    -- the south wall over the floor 2A3 / 2A4
    { layouts = { "LAYOUT_SEAFOAM_ISLANDS_", "LAYOUT_FOUR_ISLAND_ICEFALL_CAVE_" },
      pieces = { [0x33D] = "W", [0x33E] = "HW", [0x30B] = "N", [0x2FE] = "NW", [0x2FF] = "NE", [0x367] = "NW", [0x366] = "NE", [0x36F] = "TW", [0x36E] = "TE",
                 [0x365] = "W", [0x35D] = "W", [0x36D] = "SW", [0x355] = "N", [0x356] = "N", [0x2A3] = "N",
                 [0x2A4] = "N", [0x2A0] = "HW", [0x2A1] = "N", [0x2A2] = "HE" } },
    -- Diglett's Cave's entrances (their pits): the north wall's face 2E1, the west side 2DA, the
    -- rim's ends along the south wall 2A3 / 2A4 (in the tunnel below the same tiles rim its raised
    -- rock tops, read as drawn there without them)
    { layouts = { "LAYOUT_DIGLETTS_CAVE_NORTH_ENTRANCE", "LAYOUT_DIGLETTS_CAVE_SOUTH_ENTRANCE" },
      pieces = { [0x2E1] = "F", [0x2DA] = "E", [0x2A3] = "N", [0x2A4] = "N" } },
    -- Mt Ember's outside and its summit (the Sevii Islands' outdoor tileset: grey rock stepped as a
    -- mountain's, read as a cave's by sight - the summit's sand at the top has a side falling west
    -- on its west, 353, and one falling east on its east, 355). The light top 351 is flat; its
    -- faces 35C / 359, a cave's mouth 346, the stairs 091 / 089; the sides falling west 353, over
    -- sand 336 / 354, over grass 34E, and east 355, over sand 337, over grass 34F; a face's west
    -- end 35B (over sand 33E, grass 345), its east end 35D (33F, 347); the inside corners, the
    -- rock north and east 335 (a west side's head beside a face's end) and north and west 334.
    -- The sand, grass, ledges, boulders and the summit's rock lip lie flat. Read over the
    -- relief's (the outdoor reading leaves the mountain flat), its walls in its own face and sand
    { layouts = { "LAYOUT_MT_EMBER_EXTERIOR$", "LAYOUT_MT_EMBER_SUMMIT$" }, over = true, face = 0x35C, ground = 0x385,
      pieces = { [0x35C] = "F", [0x359] = "F", [0x346] = "F", [0x091] = "F", [0x089] = "F",
                 [0x353] = "W", [0x336] = "W", [0x354] = "W", [0x34E] = "W",
                 [0x355] = "E", [0x337] = "E", [0x34F] = "E",
                 [0x35B] = "SW", [0x33E] = "SW", [0x345] = "SW", [0x35D] = "SE", [0x33F] = "SE", [0x347] = "SE",
                 [0x335] = "FW", [0x334] = "FE" },
      -- by sight, where the summit's drawing contradicts itself: the crater's foot lies level with
      -- the sand (its last face, and the sides beside the sand's tongue, drawn a level too many)
      marks = { LAYOUT_MT_EMBER_SUMMIT = { ["8,3"] = ".", ["9,3"] = ".", ["6,6"] = ".", ["6,7"] = ".",
                                           ["12,6"] = ".", ["12,7"] = ".", ["7,3"] = ".", ["7,4"] = ".",
                                           ["10,3"] = ".", ["10,4"] = "." } } },
    -- Mt Ember's: its rims with ash on them 328 / 32A
    { layouts = { "LAYOUT_MT_EMBER_RUBY_PATH_", "LAYOUT_MT_EMBER_SUMMIT_PATH_" },
      pieces = { [0x328] = "N", [0x32A] = "N" } },
    -- Rock Tunnel's (and the Altering Cave's): its sides 306 / 316 / 30E (west) and 307 / 317 / 30F
    -- (east), a ridge's foot 308 / 309 / 30A, the north wall's face 309
    { layouts = { "LAYOUT_ROCK_TUNNEL_", "LAYOUT_SIX_ISLAND_ALTERING_CAVE" },
      pieces = { [0x306] = "W", [0x316] = "W", [0x30E] = "W", [0x307] = "E", [0x317] = "E", [0x30F] = "E",
                 [0x308] = "SW", [0x309] = "F", [0x30A] = "SE" } },
  },
}

-- Kanto's General tree (src/scene/trees.lua, Trees.useGame): built as Hoenn's is - 2x2, a crown row
-- whose upper layer covers the player over a trunk row, stacked through the woods - and stood as
-- the same model. Read off FireRed's drawing on Route 2, Pallet Town and Viridian Forest:
--   * crown row: 01E / 01F alone on grass, 01C / 01D with the tree above's foot behind;
--   * trunk row: 024 / 025 alone on grass (the trunk shows), 014 / 015 and 016 / 017 with the next
--     tree's crown or the wood's edge behind, 026 / 027 on the darker ground;
--   * the crown's tip is drawn in the cell above the tree: 00E / 00F, grass under it (001's);
--   * by the sea (Six Island): the crown row 0FA / 0FB over the shore, its tip 255 / 25D over the
--     sea (273's); and over a picket fence (Celadon, Routes 4, 16, 18): its tip 0D6 / 0D7, the
--     fence drawn in the lower layer, read as the plain fence (0E7) so its posts stand as its props.
-- Every variant stands as the one tree (its art, Trees.kantoArt, read off the alone tree's three
-- rows); the one-wide sapling (01B over 023, Four Island's) is a species of its own, below.
-- It stands as its own model (Trees.kantoTree): its crown a cone, its trunk upright, its shadow on
-- the ground. In texels of the alone tree drawn from its tip row's top (32 x 48), read off the
-- drawing: the crown's tip drawn at row 3, its skirt's front edge at row 41 (its last leaves,
-- and their shade, over the trunk's top), the tree standing about column 16 on row 40 (the middle of its shadow's ellipse, rows
-- 32-47); its skirt's sides end at row 34 two texels in, which a crown squashed to 0.65 of its
-- width in depth gives. The trunk is drawn in its two colours (413931, 736262), its foot (its
-- front, on the ground) at row 44.
F.trees = {
  general = F.general,
  parts = {
    [0x01C] = 0, [0x01E] = 0, [0x0FA] = 0, [0x01D] = 1, [0x01F] = 1, [0x0FB] = 1,
    [0x014] = 2, [0x016] = 2, [0x024] = 2, [0x026] = 2,
    [0x015] = 3, [0x017] = 3, [0x025] = 3, [0x027] = 3,
  },
  alone = { tip = { 0x00E, 0x00F }, crown = { 0x01E, 0x01F }, trunk = { 0x024, 0x025 } },
  cone = { axis = 16, depth = 40, radius = 16, squash = 0.65, tip = 3, skirt = 41 },
  trunk = { rgb(0x41, 0x39, 0x31), rgb(0x73, 0x62, 0x62) },
  ground = { [0x00E] = 0x001, [0x00F] = 0x001, [0x255] = 0x273, [0x25D] = 0x273, [0x0D6] = 0x0E7, [0x0D7] = 0x0E7 },
  -- Viridian Forest's own tree (its tileset's, Six Island's Pattern Bush's too): 3x3 cells, a tip
  -- row over the grass (288-28A), a crown row (290-292 in a stack, 2A0-2A2 at its foot, 28E / 2A1
  -- / 28F alone) and a trunk row (298-29A in a stack, the next tree's crown behind; 2A3-2A5 alone),
  -- stacked two rows apart. Drawn whole on the upper layer over plain grass, its grass and its
  -- shadow's rings too (groundColours); 299 is drawn alike as the middle of a stack's top tip row
  -- (tipToo: no crown row over it). Read off the alone tree in the forest's south (its tip row
  -- 288-28A): a dome, its flat top drawn on row 0 (seen from above: the apex 6 texels over the
  -- top row's height, tip -6), the skirt's front edge at row 30 (the leaves' last, over the trunk's
  -- top at 31), the tree standing at its trunk about column 24 (its foot drawn at row 37, the
  -- trunk's middle 34), its crown 0.4 of its width in depth (a crown that stood at its shadow's
  -- middle, row 38, at the General tree's 0.65, stood on a trunk 1.4 tiles tall); the trunk in its
  -- three colours.
  -- Three Island's Berry Forest draws the same tree in its own tileset, its leaves golden: the
  -- same species data, its art read off its own tiles.
  forests = {
    { layouts = { "LAYOUT_VIRIDIAN_FOREST", "LAYOUT_SIX_ISLAND_PATTERN_BUSH" }, w = 3,
      parts = {
        [0x290] = 0, [0x2A0] = 0, [0x28E] = 0, [0x291] = 1, [0x2A1] = 1, [0x292] = 2, [0x2A2] = 2, [0x28F] = 2,
        [0x298] = 3, [0x2A3] = 3, [0x299] = 4, [0x2A4] = 4, [0x29A] = 5, [0x2A5] = 5,
      },
      alone = { tip = { 0x288, 0x289, 0x28A }, crown = { 0x28E, 0x2A1, 0x28F }, trunk = { 0x2A3, 0x2A4, 0x2A5 } },
      cone = { axis = 24, depth = 34, radius = 22, squash = 0.4, tip = -6, skirt = 30, lid = 25 },
      trunk = { rgb(0x41, 0x39, 0x31), rgb(0x83, 0x6A, 0x52), rgb(0x62, 0x41, 0x4A) },
      groundColours = { rgb(0x73, 0xCD, 0xA4), rgb(0x41, 0xB4, 0x8B), rgb(0x18, 0xA4, 0x6A), rgb(0x39, 0x73, 0x18) },
      ground = { [0x288] = 0x009, [0x289] = 0x009, [0x28A] = 0x009 },
      tipToo = { [0x299] = true },
    },
  },
}
do
  local berry = {}
  for k, v in pairs(F.trees.forests[1]) do berry[k] = v end
  berry.layouts = { "LAYOUT_THREE_ISLAND_BERRY_FOREST" }
  F.trees.forests[2] = berry
end
-- Four Island's saplings: a one-wide tree in the General's tiles (its crown 01B, its trunk row
-- 023), its tip drawn in the island's own tile over the fence behind it (2BF; the fence alone,
-- 0E6, is its ground). Its crown row is drawn under the player (its layer type), over the grass,
-- the fence and their shadows: its leaves are what is drawn on either layer, less their colours
-- (groundColours, leavesBelow). Read off the drawing (16 x 48 from its tip row's top): the crown's tip at row
-- 11, its skirt's front edge at row 40 (its last leaves and their shade over the trunk's top), the
-- grass under its crown the island's (008, its tip's lower layer the fence), the tree standing at
-- column 8 on row 42 (its shadow's ellipse, rows 37-47), 0.65 of its width in depth as the General
-- tree; its trunk in the General's two colours.
F.trees.forests[3] = {
  layouts = { "LAYOUT_FOUR_ISLAND" }, w = 1,
  parts = { [0x01B] = 0, [0x023] = 1 },
  alone = { tip = { 0x2BF }, crown = { 0x01B }, trunk = { 0x023 } },
  cone = { axis = 8, depth = 42, radius = 8, squash = 0.65, tip = 11, skirt = 40 },
  trunk = { rgb(0x41, 0x39, 0x31), rgb(0x73, 0x62, 0x62) },
  groundColours = { rgb(0x73, 0xCD, 0xA4), rgb(0x18, 0xA4, 0x6A), rgb(0x41, 0xB4, 0x8B),
                    rgb(0x7B, 0x4A, 0x4A), rgb(0x5A, 0x39, 0x41), rgb(0x94, 0x6A, 0x6A), rgb(0xDE, 0xC5, 0xA4),
                    rgb(0xBD, 0x94, 0x8B), rgb(0x7B, 0x7B, 0x83) },
  ground = { [0x2BF] = 0x0E6 }, leavesBelow = true, leafGround = 0x008,
}
-- The Safari Zone's own tree: 3 cells across, a broad flat crown on a forked trunk, drawn four
-- rows tall - its crown's crest in the cell over its tip row (310-312 on the grass, 300-302 on the
-- tall grass, 308-30A over a ledge, 315-317 under the foot of the tree behind), its tip row (318 /
-- 319 / 31A alone), its crown row (the crown's underside and the trunk's top: 30B / 306 / 30C
-- alone) and its trunk row (its foot ringed with low leaves and a shadow: 313 / 30E / 314 alone) -
-- and stacked two rows apart through the woods, as Viridian Forest's is: there the crown row is
-- 2F5-2F7 (305-307 where the trunk row below it is its own, 320-322 at a wood's west or east
-- edge, 2FC at an east edge with a ledge beside it, 328-32D over a roof's back), the trunk row
-- 2FD-2FF (the next tree's tip; 31D-31F under the crest at a stack's top, 323 / 31A at a wood's
-- edges, 304 by the ledge), alone 325-327 / 30D-30F. The woods are drawn on the lower layer, the
-- alone tree's crown on the upper (306, its middle, below): its leaves are either layer's, less
-- the ground's colours (the grass, the shadow and its ring). Read off the alone trees in the north
-- (19-21 and 29-31, rows 7-10; 48 x 64 from the crest row's top): the crown's top drawn at row 11,
-- its skirt's front edge at row 37 (the shade under it, the trunk's fork below), the tree standing
-- at column 24 on row 50 (the trunk's foot at 53, its shadow's middle), its crown 0.4 of its width
-- in depth as the forest's; the trunk in its three colours.
F.trees.forests[4] = {
  layouts = { "LAYOUT_SAFARI_ZONE_NORTH", "LAYOUT_SAFARI_ZONE_CENTER", "LAYOUT_SAFARI_ZONE_EAST",
              "LAYOUT_SAFARI_ZONE_WEST" }, w = 3,
  parts = {
    [0x2F5] = 0, [0x305] = 0, [0x30B] = 0, [0x320] = 0, [0x328] = 0, [0x32B] = 0,
    [0x2F6] = 1, [0x306] = 1, [0x321] = 1, [0x329] = 1, [0x32C] = 1,
    [0x2F7] = 2, [0x307] = 2, [0x30C] = 2, [0x322] = 2, [0x2FC] = 2, [0x32A] = 2, [0x32D] = 2,
    [0x2FD] = 3, [0x31D] = 3, [0x318] = 3, [0x323] = 3, [0x325] = 3, [0x313] = 3, [0x30D] = 3,
    [0x2FE] = 4, [0x31E] = 4, [0x319] = 4, [0x326] = 4, [0x30E] = 4,
    [0x2FF] = 5, [0x31F] = 5, [0x31A] = 5, [0x304] = 5, [0x327] = 5, [0x314] = 5, [0x30F] = 5,
  },
  alone = { crest = { 0x310, 0x311, 0x312 }, tip = { 0x318, 0x319, 0x31A }, crown = { 0x30B, 0x306, 0x30C },
            trunk = { 0x313, 0x30E, 0x314 } },
  cone = { axis = 24, depth = 50, radius = 24, squash = 0.4, tip = 5, skirt = 37, lid = 33 },
  trunk = { rgb(0x41, 0x39, 0x31), rgb(0x5A, 0x62, 0x31), rgb(0x8B, 0x83, 0x31) },
  groundColours = { rgb(0x73, 0xCD, 0xA4), rgb(0x41, 0xB4, 0x8B), rgb(0xA4, 0xE6, 0xC5), rgb(0x39, 0x8B, 0x62),
                    rgb(0x39, 0xAC, 0x9C), rgb(0x8B, 0xDE, 0xBD) },
  -- (a crest over plain ground lies as that ground; the tip row under a crest, or atop a stack, is
  -- that tip)
  ground = { [0x310] = 0x008, [0x311] = 0x009, [0x312] = 0x008, [0x300] = 0x00D, [0x301] = 0x00D, [0x302] = 0x00D },
  tipToo = { [0x2FD] = true, [0x2FE] = true, [0x2FF] = true, [0x31D] = true, [0x31E] = true, [0x31F] = true,
             [0x318] = true, [0x319] = true, [0x31A] = true, [0x323] = true, [0x304] = true },
  leavesBelow = true,
}

-- Runs of no fixed shape (src/scene/models/components.lua), in the tilesets as this game's family
-- names them ("fr:" + the engine's name: Route 23's secondary is rom_082d4b84).
-- Route 23's badge-gate walls (to Victory Road): long blocks of any length, east-west and
-- north-south, drawn as a slatted top lined with white column ridges (28C / 28D / 28E), their caps
-- over whatever lies north (2C0-2C3 over the trees, 284-286 the grass, 2A5 / 2A6 / 2AE / 2AF / 320
-- / 321 / 29A the water, 2A2 the sand, 2A8 / 2AC, 2AD / 2B5 and 328 / 32C an arch's posts) and a front: a cornice (294 /
-- 295 / 298 / 299) over a façade of mesh and doors (2A0 / 2A1), a statue before each pillar (297 /
-- 29C / 29D: the league's statue, a building spec of its own, so each pillar's front ends at its
-- plinth a row behind the façade, an alcove the statue stands in). Read off the drawing: the front is the cornice's dark band and the façade, rows 33-63
-- of the two rows (31 texels, a door 16 tall in it); all the rest is the top. Its upper layer
-- alone is the wall. The arch's beams over a gap (2B1-2B3, 2B9-2BB, 325-32F, 2A9-2AB, 2BD-2BF)
-- are not the wall's, nor the statues' pedestals and shadows below the front.
F.components = {
  { name = "fr_route23_wall", secondary = "fr:rom082d4b84", upper = true, height = 31, hull = 0, bridge = 0,
    tiles = { 0x28C, 0x28D, 0x28E, 0x294, 0x295, 0x298, 0x299, 0x2A0, 0x2A1,
              0x2C0, 0x2C1, 0x2C2, 0x2C3, 0x284, 0x285, 0x286, 0x2A5, 0x2A6, 0x2AE, 0x2AF, 0x320, 0x321,
              0x29A, 0x2A2, 0x2A8, 0x2AC, 0x2AD, 0x2B5, 0x328, 0x32C, 0x2B0, 0x2B4, 0x2B8, 0x2BC },
    ground = { 0x28A, 0x008, 0x009, 0x12B } },
  -- Routes 12 and 13's boardwalks over the sea (rom_082d4b0c): plank decks on stilts, the planks
  -- across a north-south walk (2F3-2F5, 346, 34B, 343, 345, 34F) and along an east-west one (2FC,
  -- 2FD, 304, 305, 347-34A), the landings (310-315), and under each deck's south edge the cell drawn
  -- with its dark edge, its pilings and its shade on the water (308-30B). Read off the drawing (Route
  -- 12, 9 x 10-12): the planks to row 30, the edge row 31, the pilings and shade rows 32-36 - 6
  -- texels of front; its upper layer alone is the deck, the planks' one-texel gaps left clear (a
  -- north-south walk's runs joined across them: `hull`).
  { name = "fr_boardwalk", secondary = "fr:rom082d4b0c", upper = true, height = 6, hull = 1, bridge = 0,
    tiles = { 0x2F3, 0x2F4, 0x2F5, 0x346, 0x34B, 0x343, 0x345, 0x34F, 0x2FC, 0x2FD, 0x304, 0x305,
              0x347, 0x348, 0x349, 0x34A, 0x310, 0x311, 0x312, 0x313, 0x314, 0x315,
              0x308, 0x309, 0x30A, 0x30B },
    ground = { 0x12B } },
}

return F
