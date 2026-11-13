-- Trees in the battle scene (Battle Scene: OVERWORLD): the General tileset's trees, and the ones
-- some secondary tilesets draw on their own, stood up as their models instead of lying flat.
--
-- Adapted from Emerald 3DS's 3ds_port/src/voxel/voxel_tree.c (by Zallax and contributors,
-- CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), with its tree art
-- (assets/scene/trees.png, packed by tools/pack_trees.py at the places the port packs it):
--
--   * a 2x2 tree's four cells (its crown row, parts 0 and 1, and its trunk row, 2 and 3) each
--     lay their ground from the tree's own art (the trunk and its shadow) and carry a row of its
--     crown: a card leant back at 50 degrees, fixed in the world, its foot sunk a little into
--     the trunk row; where the other row's cell is not a tree part (a hedge, a roof drawn over
--     it), that row of the crown is added anyway;
--   * a small tree's trunk cell lays its trunk's ground and carries a 16:32 crown card, and long
--     grass a tuft leant back the same way;
--   * a cell whose drawing is only a crown's top over something else lays that something else
--     (groundMetatile): the crown comes from the tree.
--
-- Changes from the port: written in Lua for LOVE; no relief yet (every tree stands on the flat
-- ground, so it never stands up steeper against rock); a secondary tileset is told by its name
-- (the engine's tileset pair, "general__petalburg").

local Trees = {}

Trees.DIM = 128
Trees.SMALL, Trees.GRASS = 4, 5
local SECONDARY = 0x200

--- The secondary tileset of an engine tileset pair ("general__petalburg" -> "petalburg"),
--- without underscores; and whether the pair's primary is the General tileset.
function Trees.tilesets(pair)
  local p, s = tostring(pair or ""):match("^([^_]+)__(.+)$")
  if not p then return nil, false end
  return (s:gsub("_", "")):lower(), p:lower() == "general"
end

-- Fortree's houses, decks and bridges stand in the treetops: the cells they are drawn on are a
-- small tree's each
local function fortreeWood(m)
  return (m >= 0x224 and m <= 0x226) or (m >= 0x22B and m <= 0x22F) or (m >= 0x233 and m <= 0x237)
    or (m >= 0x23B and m <= 0x23F) or m == 0x243 or (m >= 0x245 and m <= 0x247) or m == 0x256
end

local TRUNK_JUNGLE, TRUNK_GRASS_ROAD, TRUNK_VOLCAN, TRUNK_GENERAL, TRUNK_ACCESS = 0, 1, 2, 3, 4
local TRUNKS = { [0] = { 48, 48 }, { 80, 16 }, { 64, 32 }, { 48, 32 }, { 112, 32 } }

-- where a small trunk's ground is packed, for the trunks a secondary tileset draws on its own
-- ground; nil for any other metatile
local function smallTrunkGround(sec, m)
  if sec == "fortree" and m == 0x253 then return TRUNK_JUNGLE end
  if sec == "fortree" and (m == 0x22A or fortreeWood(m)) then return TRUNK_GENERAL end
  if sec == "mauville" and m == 0x226 then return TRUNK_GRASS_ROAD end
  if (sec == "rustboro" and m == 0x307) or (sec == "lavaridge" and m == 0x201) then return TRUNK_ACCESS end
  if sec == "lavaridge" and (m == 0x218 or m == 0x21A or m == 0x3B8 or m == 0x203) then return TRUNK_VOLCAN end
  return nil
end

-- a secondary tileset's own 2x2 trees (Mossdeep's round tree, Route 113's leaning one): only the
-- trunk row is a tree part (2 left, 3 right), and the kind of ground it stands on
local OWN_GRASS, OWN_SHALLOWS, OWN_SOIL, OWN_ASH = 0, 1, 2, 3
local OWN = {
  mossdeep = {
    [0x322] = { 2, OWN_GRASS }, [0x326] = { 2, OWN_GRASS }, [0x355] = { 2, OWN_GRASS },
    [0x323] = { 3, OWN_GRASS }, [0x327] = { 3, OWN_GRASS }, [0x356] = { 3, OWN_GRASS },
    [0x2F8] = { 2, OWN_SHALLOWS }, [0x324] = { 2, OWN_SHALLOWS },
    [0x2F9] = { 3, OWN_SHALLOWS }, [0x325] = { 3, OWN_SHALLOWS },
  },
  fallarbor = {
    [0x20E] = { 2, OWN_SOIL }, [0x26C] = { 2, OWN_SOIL }, [0x273] = { 2, OWN_SOIL }, [0x2CA] = { 2, OWN_SOIL },
    [0x2CF] = { 2, OWN_SOIL },
    [0x20F] = { 3, OWN_SOIL }, [0x26B] = { 3, OWN_SOIL }, [0x274] = { 3, OWN_SOIL }, [0x2CB] = { 3, OWN_SOIL },
    [0x2CE] = { 3, OWN_SOIL },
    [0x20C] = { 2, OWN_ASH }, [0x26E] = { 2, OWN_ASH }, [0x275] = { 2, OWN_ASH },
    [0x20D] = { 3, OWN_ASH }, [0x26D] = { 3, OWN_ASH }, [0x276] = { 3, OWN_ASH },
  },
}
local function ownLarge(sec, m)
  local t = OWN[sec] and OWN[sec][m]
  if t then return t[1], t[2] end
  return nil
end
local OWN_GROUND = {
  mossdeep = { [0x2F0] = 0x19E, [0x2F1] = 0x19E, [0x2F8] = 0x19E, [0x2F9] = 0x19E, [0x324] = 0x19E, [0x325] = 0x19E,
               [0x31A] = 0x001, [0x31B] = 0x001, [0x31C] = 0x07C, [0x31D] = 0x07C, [0x31E] = 0x002, [0x31F] = 0x002 },
  fallarbor = { [0x204] = 0x218, [0x205] = 0x218, [0x206] = 0x279, [0x207] = 0x279, [0x214] = 0x271,
                [0x215] = 0x271, [0x2C2] = 0x269, [0x2C3] = 0x269, [0x2CC] = 0x170, [0x2CD] = 0x170 },
}

-- the General tileset's parts
local GENERAL = {
  -- the secret base's tree: its upper row, and the lower closed or opened
  [0x01E] = 0, [0x01F] = 1, [0x026] = 2, [0x036] = 2, [0x027] = 3, [0x037] = 3,
  [0x1D4] = 0, [0x1D6] = 0, [0x1D5] = 1, [0x1D7] = 1,
  [0x1DC] = 2, [0x1DE] = 2, [0x1E4] = 2, [0x1E6] = 2,
  [0x1DD] = 3, [0x1DF] = 3, [0x1E5] = 3, [0x1E7] = 3,
  -- a large tree's lower row under a small tree's canopy top
  [0x1EC] = 2, [0x1ED] = 3,
  -- a lower row under the canopy top of a tree one column to the side (staggered woods)
  [0x1F3] = 2, [0x1F2] = 3,
  -- an upper row in front of a fence or rock (the Safari Zone's)
  [0x1FC] = 0, [0x1FD] = 1,
  -- small trees: a wood's edge, and inside it where the next crown overlaps the trunk
  [0x016] = 4, [0x017] = 4, [0x0C6] = 4, [0x0C7] = 4, [0x1F4] = 4, [0x1F5] = 4,
  [0x015] = 5,   -- long grass
}

--- The tree part a metatile is (0-3 a 2x2 tree's, SMALL, GRASS), or nil.
function Trees.part(sec, m)
  if m >= SECONDARY then
    local part = ownLarge(sec, m)
    if part then return part end
    if sec == "dewford" and (m == 0x23A or m == 0x243) then return Trees.SMALL end
    if smallTrunkGround(sec, m) then return Trees.SMALL end
    if sec == "fortree" and (m == 0x208 or (m >= 0x281 and m <= 0x283)) then return Trees.GRASS end
    return nil
  end
  return GENERAL[m]
end

--- Whether a tree part's cell lays its own ground (not over water the ground pass lays).
function Trees.laysGround(sec, m)
  if m >= SECONDARY then
    local part, ground = ownLarge(sec, m)
    if part and ground == OWN_SHALLOWS then return false end
  end
  return true
end

local GENERAL_GROUND = {
  [0x1C6] = 0x00D, [0x1C7] = 0x00D,   -- tall grass without canopy
  [0x1CE] = 0x001, [0x1CF] = 0x001,   -- ordinary grass
  [0x00E] = 0x001, [0x00F] = 0x001, [0x040] = 0x001,   -- a small tree's canopy top
  [0x01D] = 0x002,                    -- ledge edge
  [0x025] = 0x00D,                    -- tall grass
  [0x02D] = 0x0A1,                    -- reflective water
  [0x035] = 0x170, [0x193] = 0x170,   -- calm water
  [0x0CE] = 0x091,                    -- rock wall, sand base
}

--- The metatile the ground under a cell is drawn with: a crown's top over something else is
--- that something else.
function Trees.groundMetatile(sec, m)
  if m >= SECONDARY then
    local own = OWN_GROUND[sec] and OWN_GROUND[sec][m]
    if own then return own end
    if sec == "dewford" and m == 0x239 then return 0x124 end
    if (sec == "rustboro" and m == 0x2C0) or (sec == "lilycove" and m == 0x277) then return 0x079 end
    if sec == "lavaridge" and (m == 0x211 or m == 0x20B) then return m == 0x211 and 0x079 or 0x07D end
    if sec == "battlefrontieroutsidewest" and m == 0x3F8 then return 0x204 end
    if sec == "mauville" and m == 0x2C1 then return 0x205 end
    if sec == "evergrande" and m == 0x262 then return 0x222 end
    if sec == "fortree" and (m == 0x316 or m == 0x317) then return 0x001 end
    if sec == "fortree" and (m == 0x244 or (m >= 0x248 and m <= 0x24A) or (m >= 0x250 and m <= 0x252)
        or m == 0x241 or m == 0x25C or m == 0x273) then
      return 0x001
    end
    if sec == "fortree" and (m == 0x24B or m == 0x24C) then return 0x261 end
    return m
  end
  return GENERAL_GROUND[m] or m
end

-- a 2x2 tree's art: its crown (rows of rowPx texels), its trunk's ground, and how far into the
-- trunk row the crown's foot stands
local LARGE = { crownX = 0, crownY = 0, rowPx = 18, groundX = 32, groundY = 0, foot = 0.35 }
local BASE = { crownX = 0, crownY = 64, rowPx = 16, groundX = 96, groundY = 0, foot = 0.66 }
local BASE_OPEN = { crownX = 32, crownY = 64, rowPx = 16, groundX = 96, groundY = 0, foot = 0.66 }
local OWN_ART = {
  [OWN_GRASS] = { crownX = 64, crownY = 64, rowPx = 16, groundX = 64, groundY = 80, foot = 1.15 },
  [OWN_SHALLOWS] = { crownX = 64, crownY = 64, rowPx = 16, groundX = 96, groundY = 80, foot = 0.95, decal = true },
  [OWN_SOIL] = { crownX = 96, crownY = 64, rowPx = 16, groundX = 0, groundY = 80, foot = 1.00 },
  [OWN_ASH] = { crownX = 96, crownY = 64, rowPx = 16, groundX = 32, groundY = 80, foot = 1.00 },
}
local function largeArt(sec, m)
  if m >= SECONDARY then
    local part, ground = ownLarge(sec, m)
    if part then return OWN_ART[ground] end
  end
  if m == 0x01E or m == 0x01F or m == 0x026 or m == 0x027 then return BASE end
  if m == 0x036 or m == 0x037 then return BASE_OPEN end
  return LARGE
end

local BASE_HEIGHT = -0.10

-- The emitters hand quads to put(a, b, c, d, u0, v0, u1, v1, kind): corners { x, y, z } in map
-- cells (a the texture's top left, then clockwise), the uv rect in atlas texels; kind "ground"
-- (a plate on the cell) or "card" (leaves, a tuft).

local function ground(put, x, z, u0, v0, u1, v1, lift)
  local y = lift or 0
  put({ x, y, z }, { x + 1, y, z }, { x + 1, y, z + 1 }, { x, y, z + 1 }, u0, v0, u1, v1, "ground")
end

-- one row of a large crown over the cell (x, y), column col, row row of a tree whose trunk row
-- is y - row + 1
local function crownCard(put, art, x, y, col, row)
  local u0 = art.crownX + col * 16
  local v0 = art.crownY + row * art.rowPx
  local length = art.rowPx / 8
  local rise, run = 0.766044 * length, 0.642788 * length
  local baseZ = y - row + 1 + art.foot
  local top, bottom = 1 - row * 0.5, 0.5 - row * 0.5
  put({ x, BASE_HEIGHT + top * rise, baseZ - top * run },
      { x + 1, BASE_HEIGHT + top * rise, baseZ - top * run },
      { x + 1, BASE_HEIGHT + bottom * rise, baseZ - bottom * run },
      { x, BASE_HEIGHT + bottom * rise, baseZ - bottom * run },
      u0, v0, u0 + 16, v0 + art.rowPx, "card")
end

-- a small tree's trunk cell (its 16:32 crown leant back on it) or a long grass tuft
local function smallCell(put, sec, m, x, y, part)
  local grass = part == Trees.GRASS
  local trunk = not grass and smallTrunkGround(sec, m) or nil
  local dewford = not grass and m >= SECONDARY and trunk == nil
  local cx = grass and 80 or dewford and 64 or 32
  local cy = dewford and 0 or 32
  local tx = trunk and TRUNKS[trunk][1] or cx + 16
  local ty = trunk and TRUNKS[trunk][2] or cy
  ground(put, x, y, tx, ty, tx + 16, ty + 16)
  local rise, run = 1.532089, 1.285575
  local baseZ = y + (dewford and 0.975 or 0.825)
  put({ x, BASE_HEIGHT + rise, baseZ - run }, { x + 1, BASE_HEIGHT + rise, baseZ - run },
      { x + 1, BASE_HEIGHT, baseZ }, { x, BASE_HEIGHT, baseZ },
      cx, cy, cx + 16, cy + 32, "card")
end

--- Emit a tree part's cell at (x, y) (map cells). partAt(x, y) -> the tree part of another cell
--- of the same map, or nil (for the crown's other row).
function Trees.emit(put, sec, m, x, y, part, partAt)
  if part == Trees.SMALL or part == Trees.GRASS then
    smallCell(put, sec, m, x, y, part)
    return
  end
  local art = largeArt(sec, m)
  local col, row = part % 2, math.floor(part / 2)
  local u0, v0 = art.groundX + col * 16, art.groundY + row * 16
  -- over the water: its roots and shadow just off the surface
  ground(put, x, y, u0, v0, u0 + 16, v0 + 16, art.decal and 0.02 or 0)
  crownCard(put, art, x, y, col, row)
  -- the crown's other row, when that row's cell is something else drawn over the tree (a General
  -- tree's only inside its own map: across the edge the next map's cells answer; a tileset's own
  -- tree's always, as its crown row is never a part)
  local other = row == 0 and y + 1 or y - 1
  local partner = row == 0 and part + 2 or part - 2
  local own = m >= SECONDARY and ownLarge(sec, m) ~= nil
  local otherPart = partAt(x, other)     -- a part, nil (none), or false (outside this map)
  if otherPart == partner then return end
  if not own and otherPart == false then return end
  crownCard(put, art, x, other, col, 1 - row)
end

return Trees
