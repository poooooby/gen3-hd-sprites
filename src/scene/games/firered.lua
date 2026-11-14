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

return F
