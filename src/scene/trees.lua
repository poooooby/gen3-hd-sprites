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
--   * against rock or higher ground behind it (AgainstRock, worked out by src/scene/init.lua off
--     the cells' roles and relief) a small tree's crown and a tuft stand up steeper (run 0.8),
--     and a tileset's own large tree's (0.4); where the relief lays a tree's ground (on a band's
--     rock, or on a one-level slope: EmitGround, src/scene/relief.lua's treeStep) no flat plate.
--
-- Changes from the port: written in Lua for LOVE; a secondary tileset is told by its name (the
-- engine's tileset pair, "general__petalburg").

local Trees = {}

Trees.DIM = 128
Trees.SMALL, Trees.GRASS = 4, 5
local SECONDARY = 0x200     -- (the family's: Trees.useFamily)
-- The game's tileset family (src/scene/family.lua; nil: Emerald's). Hoenn's trees below are read
-- off Hoenn's tilesets only: FireRed's are named apart (Family's pairNames), so none is taken
-- for them
Trees.family = nil
function Trees.useFamily(F)
  Trees.family = F
  SECONDARY = F and F.primaryMetatiles or 0x200
end

-- Another game's own tree (src/scene/games/<game>.lua's `trees`; nil: Hoenn's, below): Kanto's
-- General tree is built as Hoenn's is - 2x2, a crown row whose upper layer covers the player over a
-- trunk row, stacked through the woods - and stands as the same model, its art read off the
-- player's own tiles (Trees.kantoArt). { general = the primary's name, parts = { [mid] = part },
-- alone = { tip, crown, trunk } (the tree alone on grass: each a row's two metatiles), ground =
-- { [mid] = mid } (a cell drawing only a crown's tip over something else) }
Trees.kanto = nil
-- The game's tree species: [0] its General tree (Trees.kanto, 2x2), [1..] a forest tileset's own
-- (`trees.forests`: { layouts = { LAYOUT_X, ... } (the maps drawn with it: their secondary tileset,
-- Trees.resolveForests), w (cells across), parts = { [mid] = row * w + col } (row 0 the crown
-- row, 1 the trunk row), alone, ground, cone, trunk } as the General tree's). A species' art lies
-- in the tree atlas at its own place (art); a forest's parts are numbered from FOREST_PART (8 a
-- species), so the General tree's stay 0-3.
local FOREST_PART, FOREST_SPAN = 16, 8
Trees.species = nil
Trees.forestBySec = {}
local function speciesArt(k, w)
  if k == 0 then
    return { crownX = 0, crownY = 16, rowPx = 16, groundX = 32, groundY = 16, foot = 0.70, tip = 16,
             texX = 0, texY = 0, groundTexX = 32, trunkX = 64 }
  end
  -- (below the General tree's: crown, ground and trunk side by side, each 48 tall)
  local y = 64 * k
  return { crownX = 0, crownY = y + 16, rowPx = 16, groundX = 16 * w, groundY = y + 16, foot = 0.70, tip = 16,
           texX = 0, texY = y, groundTexX = 16 * w, trunkX = 32 * w - 16 }
end
function Trees.useGame(G)
  local K = type(G) == "table" and type(G.trees) == "table" and G.trees or nil
  -- (the same game again: its species as they are, their tilesets found and their art read)
  if K and K == Trees.kanto and Trees.species then return end
  Trees.kanto = K
  Trees.species, Trees.forestBySec, Trees.forestsResolved = nil, {}, false
  -- (the atlas: the General tree's and one forest's in 128 x 128 as Hoenn's art; more forests, 256)
  local more = K and #(K.forests or {}) > 1
  Trees.KANTO_W, Trees.KANTO_H = more and 256 or 128, more and 256 or 128
  Trees.DIM = K and Trees.KANTO_W or 128
  if K then
    local S = { [0] = { w = 2, parts = K.parts, alone = K.alone, ground = K.ground, cone = K.cone, trunk = K.trunk,
                        art = speciesArt(0, 2) } }
    for k, f in ipairs(K.forests or {}) do
      if k * 64 + 48 <= Trees.KANTO_H and (f.w or 3) * 16 * 2 + 16 <= 128 then
        S[k] = { w = f.w or 3, parts = f.parts, alone = f.alone, ground = f.ground, cone = f.cone, trunk = f.trunk,
                 layouts = f.layouts, tipToo = f.tipToo, groundColours = f.groundColours,
                 art = speciesArt(k, f.w or 3) }
      end
    end
    Trees.species = S
    -- (each species' crown in the atlas, graded brighter as the tree texture loads)
    local crowns = {}
    for k = 0, #S do crowns[#crowns + 1] = { S[k].art.texX, S[k].art.texY, S[k].w * 16, 48 } end
    Trees.KANTO_CROWNS = crowns
  else
    Trees.KANTO_CROWNS = { { 0, 0, 32, 48 } }
  end
end

--- The forests' tilesets, as this game names them: pairOf(layoutId) -> the engine's tileset pair
--- of a layout the species names (nil: unknown). Their parts are read only in these tilesets.
function Trees.resolveForests(pairOf)
  Trees.forestBySec = {}
  local S = Trees.species
  if not S then return end
  for k = 1, #S do
    for _, id in ipairs(S[k].layouts or {}) do
      local pair = pairOf(id)
      local sec = pair and Trees.tilesets(pair)
      if sec then
        Trees.forestBySec[sec] = k
        S[k].pair = S[k].pair or pair
      end
    end
  end
  Trees.forestsResolved = true
end

--- A large tree part's place in its tree: col, row (0 crown row, 1 trunk row), the tree's width
--- (cells), its species (0 the General tree); nil for SMALL, GRASS or none.
function Trees.partCell(part)
  if type(part) ~= "number" then return nil end
  if part >= FOREST_PART then
    local k = math.floor((part - FOREST_PART) / FOREST_SPAN) + 1
    local S = Trees.species and Trees.species[k]
    if not S then return nil end
    local loc = (part - FOREST_PART) % FOREST_SPAN
    return loc % S.w, math.floor(loc / S.w), S.w, k
  end
  if part >= 0 and part <= 3 then return part % 2, math.floor(part / 2), 2, 0 end
  return nil
end

-- The workshop's settings (src/scene/tune.lua: lean, height, foot, sink), the game's; nil: the
-- models' own constants
Trees.tune = nil
function Trees.useTune(t) Trees.tune = t end

--- The secondary tileset of an engine tileset pair ("general__petalburg" -> "petalburg"),
--- without underscores; and whether the pair's primary is the General tileset.
function Trees.tilesets(pair)
  local p, s
  if Trees.family and Trees.family.namespace then
    p, s = Trees.family.pairNames(pair)
    if not p then return nil, false end
    -- (Kanto's: its own General, by its family's name; Hoenn's tables never)
    local K = Trees.kanto
    return (s:gsub("_", "")):lower(), K ~= nil and p:lower() == tostring(K.general):lower()
  else
    p, s = tostring(pair or ""):match("^([^_]+)__(.+)$")
  end
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
  if Trees.kanto then
    if m < SECONDARY then return Trees.kanto.parts[m] end
    local k = Trees.forestBySec[sec]
    local S = k and Trees.species and Trees.species[k]
    local loc = S and not S.failed and S.parts[m]
    return loc and FOREST_PART + (k - 1) * FOREST_SPAN + loc or nil
  end
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
  if Trees.kanto then return true end
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
  if Trees.kanto then
    if m < SECONDARY then return Trees.kanto.ground and Trees.kanto.ground[m] or m end
    local k = Trees.forestBySec[sec]
    local S = k and Trees.species and Trees.species[k]
    return S and not S.failed and S.ground and S.ground[m] or m
  end
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
-- Kanto's tree in its art (Trees.kantoArt): the ground of its rows (tip, crown, trunk) at (32, 0), each
-- part cell's from its row (the crown and the trunk: Trees.kantoTree)
local KANTO_ART = { crownX = 0, crownY = 16, rowPx = 16, groundX = 32, groundY = 16, foot = 0.70, tip = 16 }
-- (laid in an atlas of the Hoenn art's size: the tree meshes' uvs are texels over Trees.DIM)
Trees.KANTO_W, Trees.KANTO_H = 128, 128
-- the art's crowns (graded brighter as the tree texture loads: src/scene/light.lua gradeTrees)
Trees.KANTO_CROWNS = { { 0, 0, 32, 48 } }

local function largeArt(sec, m)
  if Trees.kanto then return KANTO_ART end
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

-- a setting: the cell's mark's, else the game's (Trees.tune), else nil (the model's own)
local function setting(mark, key)
  local m = mark and mark.trees
  if m and m[key] ~= nil then return m[key] end
  local t = Trees.tune
  return t and t[key] or nil
end

-- one row of a large crown over the cell (x, y), column col, row row of a tree whose trunk row
-- is y - row + 1; and above the crown row, the tip the art has (art.tip texels, Kanto's: drawn in
-- the cell above the tree)
local function crownCard(put, art, x, y, col, row, steep, mark)
  local u0 = art.crownX + col * 16
  local v0 = art.crownY + row * art.rowPx
  local length = art.rowPx / 8 * (setting(mark, "height") or 1)
  -- (against rock or higher ground behind the trunk, a tileset's own tree stands up steeper)
  local lean = setting(mark, "lean")
  local up, back = 0.766044, 0.642788
  if lean and lean ~= 50 then up, back = math.sin(math.rad(lean)), math.cos(math.rad(lean)) end
  local rise, run = up * length, (steep and 0.4 or back) * length
  local baseZ = y - row + 1 + (setting(mark, "foot") or art.foot)
  local sink = setting(mark, "sink")
  local base = sink and -sink or BASE_HEIGHT
  local top, bottom = 1 - row * 0.5, 0.5 - row * 0.5
  put({ x, base + top * rise, baseZ - top * run },
      { x + 1, base + top * rise, baseZ - top * run },
      { x + 1, base + bottom * rise, baseZ - bottom * run },
      { x, base + bottom * rise, baseZ - bottom * run },
      u0, v0, u0 + 16, v0 + art.rowPx, "card")
  if row == 0 and art.tip then
    local tip = 1 + art.tip / (2 * art.rowPx)
    put({ x, base + tip * rise, baseZ - tip * run },
        { x + 1, base + tip * rise, baseZ - tip * run },
        { x + 1, base + top * rise, baseZ - top * run },
        { x, base + top * rise, baseZ - top * run },
        u0, v0 - art.tip, u0 + 16, v0, "card")
  end
end

-- a small tree's or a tuft's art: its card's top left, its ground's, and whether it is Dewford's
local function smallArt(sec, m, part)
  local grass = part == Trees.GRASS
  local trunk = not grass and smallTrunkGround(sec, m) or nil
  local dewford = not grass and m >= SECONDARY and trunk == nil
  local cx = grass and 80 or dewford and 64 or 32
  local cy = dewford and 0 or 32
  local tx = trunk and TRUNKS[trunk][1] or cx + 16
  local ty = trunk and TRUNKS[trunk][2] or cy
  return cx, cy, tx, ty, dewford
end

-- a small tree's trunk cell (its 16:32 crown leant back on it) or a long grass tuft; against rock
-- (o.rock) it stands up steeper, its top at the trunk cell's back edge; o.noGround: the relief
-- lays its ground
local function smallCell(put, sec, m, x, y, part, o)
  local cx, cy, tx, ty, dewford = smallArt(sec, m, part)
  if not o.noGround then ground(put, x, y, tx, ty, tx + 16, ty + 16) end
  local rise, run = 1.532089, o.rock and 0.8 or 1.285575
  local baseZ = y + (dewford and 0.975 or 0.825)
  put({ x, BASE_HEIGHT + rise, baseZ - run }, { x + 1, BASE_HEIGHT + rise, baseZ - run },
      { x + 1, BASE_HEIGHT, baseZ }, { x, BASE_HEIGHT, baseZ },
      cx, cy, cx + 16, cy + 32, "card")
end

--- Where a tree part's cell lays its ground from the art: the 16x16 texels' top left (tx, ty), and
--- whether it is a decal over water (laid just off the surface, never on the relief).
function Trees.groundArt(sec, m, part)
  if part == Trees.SMALL or part == Trees.GRASS then
    local _, _, tx, ty = smallArt(sec, m, part)
    return tx, ty, false
  end
  if Trees.kanto then
    local col, row, _, k = Trees.partCell(part)
    local art = Trees.species[k].art
    return art.groundX + col * 16, art.groundY + row * 16, false
  end
  local art = largeArt(sec, m)
  return art.groundX + (part % 2) * 16, art.groundY + math.floor(part / 2) * 16, art.decal == true
end

--- Emit a tree part's cell at (x, y) (map cells). partAt(x, y) -> the tree part of another cell
--- of the same map, or nil (for the crown's other row); false outside this map (and a second
--- value, true, outside the scene's window). o: { rock (it stands against rock or
--- higher ground: AgainstRock), noGround (the relief lays its ground: on the rock of a band, or
--- on a one-level slope), mark (the cell's workshop mark, src/scene/tune.lua: its settings, or
--- hide: its ground alone) }, or nil.
function Trees.emit(put, sec, m, x, y, part, partAt, o)
  o = o or {}
  if Trees.kanto and part ~= Trees.SMALL and part ~= Trees.GRASS then
    -- Kanto's: each cell lays its row's ground (the shadow flat), and the tree stands once, from
    -- its crown row's west cell (or its trunk row's: a crown row drawn over by something else, or
    -- past the scene's window)
    local col, row, w, k = Trees.partCell(part)
    local S = Trees.species[k]
    local art = S.art
    -- (a forest's trunk row drawn where no crown row is over it - the top of its stack, where the
    -- next tree's tip is drawn alike - is that tip: its ground, and no tree)
    local above, outside
    if row == 1 then above, outside = partAt(x, y - 1) end
    local tipOnly = k > 0 and row == 1 and above == nil and outside ~= true and S.tipToo and S.tipToo[m]
    if not o.noGround then
      local u0, v0 = art.groundX + col * 16, art.groundY + (tipOnly and -1 or row) * 16
      ground(put, x, y, u0, v0, u0 + 16, v0 + 16, 0)
    end
    if o.mark and o.mark.hide then return end
    if tipOnly then return end
    if col == 0 and (row == 0 or above == nil or outside == true) then
      Trees.kantoTree(put, x, (row == 0 and y or y - 1) - 1, k)
    end
    return
  end
  if part == Trees.SMALL or part == Trees.GRASS then
    smallCell(put, sec, m, x, y, part, o)
    return
  end
  local mark = o.mark
  local art = largeArt(sec, m)
  local col, row = part % 2, math.floor(part / 2)
  local u0, v0 = art.groundX + col * 16, art.groundY + row * 16
  -- over the water: its roots and shadow just off the surface
  if art.decal then
    ground(put, x, y, u0, v0, u0 + 16, v0 + 16, 0.02)
  elseif not o.noGround then
    ground(put, x, y, u0, v0, u0 + 16, v0 + 16, 0)
  end
  -- (only a tileset's own tree stands up steeper)
  local own = not Trees.kanto and m >= SECONDARY and ownLarge(sec, m) ~= nil
  local steep = o.rock and own
  if mark and mark.hide then return end
  crownCard(put, art, x, y, col, row, steep, mark)
  -- the crown's other row, when that row's cell is something else drawn over the tree (a General
  -- tree's only inside its own map: across the edge the next map's cells answer; a tileset's own
  -- tree's always, as its crown row is never a part)
  local other = row == 0 and y + 1 or y - 1
  local partner = row == 0 and part + 2 or part - 2
  local otherPart = partAt(x, other)     -- a part, nil (none), or false (outside this map)
  if otherPart == partner then return end
  if not own and otherPart == false then return end
  crownCard(put, art, x, other, col, 1 - row, steep, mark)
end

-- ── Kanto's tree as its own model ─────────────────────────────────────────
-- Built off its drawing as the rooms' pieces are (src/scene/models/interiors.lua): every texel of
-- it stands where the GBA's 45-degree view puts it, so seen from there the tree is its drawing.
-- In texels of the alone tree from its tip row's top (32 x 48; x east, v the drawing's row, y up,
-- z south, v = z - y):
--   * the crown is turned about the axis (axis, depth), squashed to `squash` of its width in depth:
--     `radius` wide at its skirt, which stands so its front edge is drawn at row `skirt`, rising to
--     its tip at row `tip`, as wide at each height as the drawn crown is on the row its side is
--     drawn on (its outline the drawing's). Its front is cut into quads by the drawing's columns and rows, each
--     corner the point of the cone (or, past its outline, of the plane through its axis; under its
--     skirt, of the skirt's edge straight down) that the view puts there, its texels the drawing's:
--     the tip and crown rows' upper layers, and of the trunk row what the cone covers;
--   * the trunk is a card upright at its drawn foot (its front), from the ground into the cone, its texels the
--     trunk's colours (the game's `trunk`), carried up each column where the cone hides it;
--   * the ground under each row is that row's lower layer: the trunk row's with what the cone and
--     the trunk cover taken off it: behind the tree's foot the shadow's drawn front turned about
--     that row (its back, as round as its front), else the first of the ground below it in its
--     column (the shadow, laid flat); under the leaves of the rows above, the tip row's grass.
-- the crown's half-width on each row of the drawing (Trees.kantoArt), its outline's
Trees.KANTO_PROFILE = nil
local function coneOf(k)
  local S = Trees.species and Trees.species[k or 0]
  local c = S and S.cone
  if not c then return nil end
  local C = { ax = c.axis, cz = c.depth, s = c.squash, R0 = c.radius, w = S.profile }
  -- (read off the drawing, the skirt is as wide as the crown's widest row: the radius meets it)
  if C.w and C.w[31] then C.R0 = C.w[31] end
  C.h0 = C.cz + C.s * C.R0 - c.skirt
  C.top = C.cz - c.tip
  C.lid = c.lid
  return C
end
Trees.kantoCone = coneOf
-- (its side, seen at 45 degrees, is drawn on the row cz - y: the radius there is the drawn
-- crown's half-width on that row, or a straight cone's without the drawing)
local function coneRadius(C, y)
  if y <= C.h0 then return C.R0 end
  if y >= C.top then return 0 end
  local w = C.w
  if w then
    local v = C.cz - y - 0.5
    -- (above the drawing's top row - a dome's top, seen from above - closing to its apex)
    if v < 0 then return math.min(C.R0, (w[0] or 0) * (C.top - y) / math.max(1e-6, C.top - (C.cz - 0.5))) end
    local v0 = math.floor(v)
    local a, b = w[v0] or 0, w[v0 + 1] or C.R0
    return math.min(C.R0, a + (b - a) * (v - v0))
  end
  return C.R0 * (C.top - y) / (C.top - C.h0)
end
--- The point of the crown's front the 45-degree view draws at (x, v): y, z (texels), and whether
--- it is on the cone (not under its skirt nor past its outline).
function Trees.kantoFront(C, x, v)
  local dx = x - C.ax
  local function at(y)
    local R = coneRadius(C, y)
    local d = R * R - dx * dx
    return C.cz + (d > 0 and C.s * math.sqrt(d) or 0), d
  end
  -- (z - y falls as y rises: the one y it is v)
  local lo, hi = -64, 192
  for _ = 1, 32 do
    local mid = (lo + hi) / 2
    if at(mid) - mid > v then lo = mid else hi = mid end
  end
  local y = (lo + hi) / 2
  local z, d = at(y)
  return y, z, y >= C.h0 - 1e-6 and y <= C.top and d >= 0
end

-- the art's places: the crown's texels at (0, 0), the ground's at (32, 0), the trunk's at (64, 0)
local KANTO_TRUNK_X = 64
-- the crown's quads (Trees.kantoArt: those holding a texel of it) and the trunk's card, in texels
Trees.KANTO_QUADS = nil
Trees.KANTO_TRUNK = nil
local QUAD_W, QUAD_H = 4, 3

--- A tree of species k (0 or nil: the General tree) standing with the top left of its tip row at
--- the cell (x, z) (map cells).
function Trees.kantoTree(put, x, z, k)
  k = k or 0
  local S = Trees.species and Trees.species[k]
  local C = coneOf(k)
  if not (S and C) then return end
  local art = S.art
  local W = S.w * 16
  local function P(u, v)
    local y, zz = Trees.kantoFront(C, u, v)
    return { x + u / 16, y / 16, z + zz / 16 }
  end
  local quads = S.quads
  if not quads then
    quads = {}
    for v = 0, 47, QUAD_H do
      for u = 0, W - 1, QUAD_W do quads[#quads + 1] = { u, v, u + QUAD_W, math.min(48, v + QUAD_H) } end
    end
  end
  local tx, ty = art.texX, art.texY
  for _, q in ipairs(quads) do
    put(P(q[1], q[2]), P(q[3], q[2]), P(q[3], q[4]), P(q[1], q[4]), tx + q[1], ty + q[2], tx + q[3], ty + q[4], "card")
  end
  -- (a dome's lid, `cone.lid` texels up: the crown's texels laid level there, each where the
  -- 45-degree view draws it, so it hides behind the front there and closes the crown seen from
  -- above; only the quads whose front stands at least that high)
  local lid = C.lid
  if lid and S.lidQuads then
    local function L(u, v) return { x + u / 16, lid / 16, z + (v + lid) / 16 } end
    for _, q in ipairs(S.lidQuads) do
      put(L(q[1], q[2]), L(q[3], q[2]), L(q[3], q[4]), L(q[1], q[4]), tx + q[1], ty + q[2], tx + q[3], ty + q[4], "card")
    end
  end
  local tr = S.trunkCard
  if tr then
    -- (upright at its foot, from the ground into the cone)
    local y1 = tr.foot - tr.top
    local zz = z + tr.foot / 16
    put({ x + tr.x0 / 16, y1 / 16, zz }, { x + tr.x1 / 16, y1 / 16, zz },
        { x + tr.x1 / 16, 0, zz }, { x + tr.x0 / 16, 0, zz },
        art.trunkX + tr.x0, ty + tr.top, art.trunkX + tr.x1, ty + tr.foot, "card")
  end
end

--- Kanto's tree art (Trees.KANTO_W x KANTO_H), read off the player's own tiles: px(mid, layer, x, y)
--- -> r, g, b, a (0-1; nil or a < 0.5 where that layer draws nothing), set(x, y, r, g, b, a).
--- Read off the tree alone on grass (Trees.kanto.alone), as above; sets Trees.KANTO_QUADS and
--- KANTO_TRUNK. Returns the number of crown texels (0: nothing read).
function Trees.kantoArt(px, set, k)
  k = k or 0
  local K = Trees.species and Trees.species[k]
  local A = K and K.alone
  local C = coneOf(k)
  if not (A and A.tip and A.crown and A.trunk and C) then return 0 end
  local art = K.art
  local W = K.w * 16
  local tx, ty, gx, trX = art.texX, art.texY, art.groundTexX, art.trunkX
  -- (each texel at its place in the atlas: the trunk's only where its card's room is)
  local function put(x0, x, v, r, g, b, a)
    if x0 == trX and (trX + x < trX + (k == 0 and 0 or 16) or trX + x >= Trees.KANTO_W) then return end
    set(x0 + x, ty + v, r, g, b, a)
  end
  -- (colours told apart as the GBA draws them, 5 bits a channel: readers widen them to 8 bits
  -- their own ways)
  local function key(r, g, b)
    return math.floor(r * 31 + 0.5) * 1024 + math.floor(g * 31 + 0.5) * 32 + math.floor(b * 31 + 0.5)
  end
  local trunkColour = {}
  for _, c in ipairs(K.trunk or {}) do
    trunkColour[key(math.floor(c / 65536) / 255, math.floor(c / 256) % 256 / 255, c % 256 / 255)] = true
  end
  local rows = { A.tip, A.crown, A.trunk }
  local function layer(x, v, l)
    local m = rows[math.floor(v / 16) + 1][math.floor(x / 16) + 1]
    local r, g, b, a = px(m, l, x % 16, v % 16)
    if r and (l == 0 or (a and a >= 0.5)) then return r, g, b end
  end
  -- (a species that draws its tree whole on the upper layer, its grass and its shadow too: those
  -- colours there are ground, not leaves - its `groundColours`)
  local groundColour = {}
  for _, c in ipairs(K.groundColours or {}) do
    groundColour[key(math.floor(c / 65536) / 255, math.floor(c / 256) % 256 / 255, c % 256 / 255)] = true
  end
  local function leaf(x, v)
    local r, g, b = layer(x, v, 1)
    if r and not groundColour[key(r, g, b)] then return r, g, b end
  end
  -- (what is drawn there, the upper layer over the lower)
  local function drawn(x, v)
    local r, g, b = layer(x, v, 1)
    if r then return r, g, b end
    return layer(x, v, 0)
  end
  -- the rows read as the trunk row is (what is drawn: the trunk, the cone's cover or the ground):
  -- the trunk row's, and any under the skirt's front edge
  local low = math.min(32, math.floor(K.cone.skirt or 47) + 1)
  -- the crown's outline: its half-width on each row of the tip and crown rows (never narrowing
  -- down the drawing)
  local w, widest = {}, 0
  for v = 0, 31 do
    for x = 0, W - 1 do
      if v < low and leaf(x, v) then widest = math.max(widest, math.abs(x + 0.5 - C.ax) + 0.5) end
    end
    w[v] = widest
  end
  K.profile = w
  if k == 0 then Trees.KANTO_PROFILE = w end
  C = coneOf(k)
  local crown, n = {}, 0
  local covered, trunk = {}, {}
  local tx0, tx1, ttop, tfoot = math.huge, -math.huge, math.huge, -math.huge
  for v = 0, 47 do
    for x = 0, W - 1 do
      if v < low then
        local r, g, b = leaf(x, v)
        if r then crown[v * W + x] = { r, g, b } end
      else
        local lr, lg, lb = drawn(x, v)
        if lr and trunkColour[key(lr, lg, lb)] then
          trunk[v * W + x] = { lr, lg, lb }
          tx0, tx1, ttop, tfoot = math.min(tx0, x), math.max(tx1, x + 1), math.min(ttop, v), math.max(tfoot, v + 1)
        elseif lr and select(3, Trees.kantoFront(C, x + 0.5, v + 0.5)) then
          crown[v * W + x] = { lr, lg, lb }
          covered[v * W + x] = true
        end
      end
    end
  end
  for i, c in pairs(crown) do put(tx, i % W, math.floor(i / W), c[1], c[2], c[3], 1); n = n + 1 end
  -- the ground: each row's lower layer, the trunk row's with the cone and the trunk taken off it;
  -- under the tip and crown rows' leaves the grass the tip row draws there (a reader may give a
  -- crown row's lower layer with its leaves)
  -- (the shadow is an ellipse about where the tree stands: its back, hidden under the crown, is
  -- its drawn front turned about that row)
  local function bare(x, v)
    return v >= low and v <= 47 and not covered[v * W + x] and not trunk[v * W + x]
  end
  for x = 0, W - 1 do
    local fill
    for v = 47, 0, -1 do
      local r, g, b = drawn(x, v)
      if v < low and leaf(x, v) then r, g, b = layer(x, v % 16, 0) end
      if v >= low and (covered[v * W + x] or trunk[v * W + x]) then
        local mv = math.floor(2 * C.cz - v - 1 + 0.5)
        if v < C.cz and bare(x, mv) then
          r, g, b = drawn(x, mv)
        elseif fill then
          r, g, b = fill[1], fill[2], fill[3]
        end
      elseif v >= low and r then
        fill = { r, g, b }
      end
      if r then put(gx, x, v, r, g, b, 1) end
    end
  end
  -- the trunk's card: its texels, carried up each column into the cone
  K.trunkCard = nil
  if k == 0 then Trees.KANTO_TRUNK = nil end
  if tx1 > tx0 then
    -- (it reaches 2 texels into the skirt)
    local top = math.floor(tfoot - C.h0 - 2)
    for x = tx0, tx1 - 1 do
      -- (the column's own topmost trunk texel, carried up)
      local colTop
      for v = low, 47 do if not colTop and trunk[v * W + x] then colTop = v end end
      for v = top, 47 do
        local c = trunk[v * W + x]
        if not c and colTop and v < colTop then
          if select(3, Trees.kantoFront(C, x + 0.5, v + 0.5)) then
            -- (up the column where the cone hides it: seen at 45 degrees, nothing of it shows)
            c = trunk[colTop * W + x]
          else
            -- (between the skirt and the trunk's top: what is drawn there, the shade under the crown)
            local r, g, b = drawn(x, v)
            if r then c = { r, g, b } end
          end
        end
        if c and v < tfoot then put(trX, x, v, c[1], c[2], c[3], 1) end
      end
    end
    K.trunkCard = { x0 = tx0, x1 = tx1, top = top, foot = tfoot }
    if k == 0 then Trees.KANTO_TRUNK = K.trunkCard end
  end
  -- the crown's quads: those holding a texel of it
  local quads = {}
  for v = 0, 47, QUAD_H do
    for u = 0, W - 1, QUAD_W do
      local v1 = math.min(48, v + QUAD_H)
      local any = false
      for yy = v, v1 - 1 do
        for xx = u, u + QUAD_W - 1 do if crown[yy * W + xx] then any = true end end
      end
      if any then quads[#quads + 1] = { u, v, u + QUAD_W, v1 } end
    end
  end
  K.quads = quads
  if k == 0 then Trees.KANTO_QUADS = quads end
  K.lidQuads = nil
  if C.lid then
    local lidQuads = {}
    for _, q in ipairs(quads) do
      local high = true
      for _, c in ipairs({ { q[1], q[2] }, { q[3], q[2] }, { q[3], q[4] }, { q[1], q[4] } }) do
        if Trees.kantoFront(C, c[1], c[2]) < C.lid then high = false end
      end
      if high then lidQuads[#lidQuads + 1] = q end
    end
    K.lidQuads = lidQuads
  end
  return n
end

return Trees
