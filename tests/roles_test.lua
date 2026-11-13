-- Unit checks for src/scene/roles.lua (Emerald 3DS's voxel_cells.py roles), on synthetic layouts.
--   luajit tests/roles_test.lua

package.path = "./?.lua;" .. package.path
local Roles = dofile("src/scene/roles.lua")

local passed, total = 0, 0
local function check(ok, what)
  total = total + 1
  if ok then passed = passed + 1 else print("FAIL: " .. what) end
end

-- ---------------------------------------------------------------- the engine's blobs
do
  local pals = Roles.palettes({ [0] = { [1] = 4 + 27 * 32 + 31 * 1024 } })
  local c = pals[0][1]
  check(c[1] == 32 and c[2] == 222 and c[3] == 255, "palettes: c * 255 // 31 a channel, as pret's voxel_art reads them")
  -- a blob of mids 7 (NORMAL: lower in under and middle, upper in over), 8 (COVERED: under the
  -- two together, middle the upper) and 9 (SPLIT: middle empty)
  local function blob(bytesOf)
    local mids = { 7, 8, 9 }
    local parts = { "MIDX", string.char(1, 2, #mids, 0, 16, 0, 1, 0) }
    for _, m in ipairs(mids) do parts[#parts + 1] = string.char(m % 256, math.floor(m / 256)) end
    for _, m in ipairs(mids) do
      local t = {}
      for i = 0, 255 do t[#t + 1] = string.char(bytesOf(m, i)) end
      parts[#parts + 1] = table.concat(t)
    end
    local s = table.concat(parts)
    return { blob = s, index = Roles.blobIndex(s) }
  end
  local LOW, UP = 0x01, 0x12   -- palette 0 colour 1; palette 1 colour 2
  local lowerOf = function(i) return i < 128 and LOW or 0 end       -- the top half drawn
  local upperOf = function(i) return i % 16 < 4 and UP or 0 end     -- four columns drawn
  local under = blob(function(m, i)
    if m == 8 then return upperOf(i) ~= 0 and upperOf(i) or lowerOf(i) end
    return lowerOf(i)
  end)
  local over = blob(function(m, i) return m == 8 and 0 or upperOf(i) end)
  local middle = blob(function(m, i)
    if m == 7 then return lowerOf(i) elseif m == 8 then return upperOf(i) end
    return 0
  end)
  local P = Roles.palettes({ [0] = { [1] = 31 }, [1] = { [2] = 31 * 32 } })
  local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  local lo, up = Roles.blobPixels(under, over, middle, P, 7)
  check(count(lo) == 128 and count(up) == 64 and lo[0][1] == 255 and up[0][2] == 255,
    "blobPixels: a NORMAL metatile's lower and upper layers")
  lo, up = Roles.blobPixels(under, over, middle, P, 8)
  check(count(up) == 64 and lo[0] == nil and lo[4] ~= nil and count(lo) == 128 - 32,
    "...a COVERED one's upper from the middle, its lower what shows round it")
  lo, up = Roles.blobPixels(under, over, middle, P, 9)
  check(count(lo) == 128 and count(up) == 64, "...a SPLIT one's from under and over")
  local cell = Roles.blobCell(under, over, middle, P, 8)
  check(cell[1] == 0x00FF00 and cell[5] == 0xFF0000 and cell[129 + 4] == Roles.CLEAR,
    "blobCell: drawn whole, colour index 0 of the lower layer CLEAR")
end

-- ---------------------------------------------------------------- roles
-- A layout from rows of characters:
--   .  walkable ground (sand)         ~  water           _  a ledge (jump south, blocked)
--   =  walkable steps                 T  a tree          #  rock (blocked)
--   P  a post (grey, blocked)         D  a house door    H  a house's wall (blocked)
--   R  the General's mountain rock    M  a secondary tile in the mountain's colours
--   B  a boulder drawn over the player
local SAND, GREY, GREEN, ROCKC, BROWN = { 222, 197, 148 }, { 98, 98, 98 }, { 32, 160, 48 }, { 0xDE, 0xB4, 0xA4 }, { 120, 80, 40 }
local MIDS = { ["."] = 1, ["~"] = 2, ["_"] = 3, ["="] = 4, T = 5, ["#"] = 6, P = 7, D = 8, H = 9, R = 0x070,
               M = 0x2A0, B = 10 }
local BEH = { MB_NORMAL = 0, MB_OCEAN_WATER = 21, MB_JUMP_SOUTH = 59, MB_ANIMATED_DOOR = 105 }
local function layout(rows, extra)
  extra = extra or {}
  local H, W = #rows, #rows[1]
  local ch = {}
  for y = 0, H - 1 do
    ch[y] = {}
    for x = 0, W - 1 do ch[y][x] = rows[y + 1]:sub(x + 1, x + 1) end
  end
  local blocking = { _ = true, T = true, ["#"] = true, P = true, H = true, R = true, M = true, B = true }
  local function fill(c) local t = {} for i = 0, 255 do t[i] = c end return t end
  local pixels = {
    [1] = { fill(SAND), {} }, [2] = { fill({ 40, 80, 200 }), {} }, [3] = { fill(BROWN), {} },
    [5] = { fill(GREEN), {} }, [6] = { fill(BROWN), {} }, [8] = { fill(BROWN), {} }, [9] = { fill(BROWN), {} },
    [0x070] = { fill(ROCKC), {} }, [0x2A0] = { fill(ROCKC), {} },
  }
  -- steps: rows alternating light and dark right across
  local steps = {}
  for i = 0, 255 do steps[i] = (math.floor(i / 16) % 2 == 0) and { 230, 230, 230 } or { 90, 90, 90 } end
  pixels[4] = { steps, {} }
  -- a post: sand round a grey board on its lower layer
  local post = fill(SAND)
  for i = 0, 255 do if i % 16 >= 6 and i % 16 < 10 then post[i] = GREY end end
  pixels[7] = { post, {} }
  -- a boulder: its upper layer over twelve columns of every row
  local up = {}
  for i = 0, 255 do if i % 16 < 12 then up[i] = GREY end end
  pixels[10] = { fill(SAND), up }
  local warps = {}
  for y = 0, H - 1 do for x = 0, W - 1 do if ch[y][x] == "D" then warps[#warps + 1] = { x, y } end end end
  local L = {
    id = extra.id or "LAYOUT_TEST", w = W, h = H, outdoor = extra.outdoor ~= false, warps = warps,
    signs = extra.signs or {}, primary = "gTileset_General", secondary = extra.secondary or "gTileset_Petalburg",
    metatile = function(x, y) return MIDS[ch[y][x]] end,
    blocked = function(x, y) return blocking[ch[y][x]] == true end,
    behaviour = function(x, y)
      local c = ch[y][x]
      return c == "~" and 21 or c == "_" and 59 or c == "D" and 105 or 0
    end,
    pixels = function(m, layer) local p = pixels[m] return p and p[layer + 1] or {} end,
  }
  return L
end
local function roleGrid(L, opt)
  opt = opt or {}
  opt.behaviours = opt.behaviours or BEH
  local r = Roles.new(L, opt)
  return Roles.letters(r, L.w, L.h), r
end

do
  local L = layout({
    "~~~~~~~~",
    "..._....",
    ".=..T...",
    "........",
    ".###....",
    "........",
  })
  local g = roleGrid(L)
  check(g[1] == "~~~~~~~~", "roles: water by its behaviour")
  check(g[2]:sub(4, 4) == "_", "...a ledge by its jump, blocked or not")
  check(g[3]:sub(2, 2) == "=" and g[4]:sub(2, 2) == ".", "...steps drawn as treads are stairs, other walkable cells floor")
  check(g[3]:sub(5, 5) == "T", "...a blocked cell drawn mostly in leaves is a tree")
  check(g[5]:sub(3, 3) == "|", "...a blocked cell walkable on both sides is a fence")
end

do
  -- rock: a mass touching walkable ground is cliff, its inside shelf
  local L = layout({
    "#####",
    "#####",
    "#####",
    ".....",
  })
  local g = roleGrid(L)
  check(g[1] == "%%%%%" and g[3] == "#####", "roles: blocked rock touching the walk is cliff, away from it shelf")
end

do
  -- posts: open on three sides (west, east, south)
  local L = layout({
    "......",
    ".P....",
    "......",
  })
  check(roleGrid(L)[2]:sub(2, 2) == "S", "signposts: a drawing open on three sides outdoors")
  L.outdoor = false
  check(roleGrid(L)[2]:sub(2, 2) == "|", "...never indoors")
  -- the General tileset's mountain rock, a tile in the mountain's colours, a boulder: never posts
  for _, case in ipairs({ { "R", "the General's mountain rock" }, { "M", "a tile in the mountain's colours" },
                          { "B", "a cover drawn over the player" } }) do
    local K = layout({ "......", "." .. case[1] .. "....", "......" })
    check(roleGrid(K)[2]:sub(2, 2) ~= "S", "...not " .. case[2])
  end
  -- a sign event always is
  local K = layout({ "......", ".R....", "......" }, { signs = { ["1,1"] = true } })
  check(roleGrid(K)[2]:sub(2, 2) == "S", "...but a sign event always is")
  -- a run of one drawing down a column is a fence's
  K = layout({ "......", ".P....", ".P....", "......" })
  local g = roleGrid(K)
  check(g[2]:sub(2, 2) ~= "S" and g[3]:sub(2, 2) ~= "S", "...nor a run of one drawing down a column (a fence's)")
end

do
  -- a house: the blocked mass above its door is its wall
  local L = layout({
    "..HHH..",
    "..HHH..",
    "..HDH..",
    ".......",
  })
  local g, r = roleGrid(L)
  check(g[1]:sub(3, 5) == "WWW" and g[2]:sub(3, 5) == "WWW" and g[3]:sub(3, 3) == "W",
    "houses: the blocked mass above a door")
  check(r.inHouse(2, 2) and not r.inHouse(0, 0), "...its cells")
end

do
  -- drawn as a sign event that stands free somewhere: one against a wall is a sign too
  local L = layout({
    "######",
    "#P####",
    "......",
  })
  local posts = { [Roles.postKey("gTileset_General", "gTileset_Petalburg", 7)] = true }
  check(roleGrid(L, { posts = posts })[2]:sub(2, 2) == "S", "signposts: drawn as a sign event's metatile, walkable south")
  check(roleGrid(L)[2]:sub(2, 2) ~= "S", "...not without it")
  -- Roles.posts finds that metatile where its sign event stands open
  local K = layout({ "......", ".P....", "......" }, { signs = { ["1,1"] = true } })
  local found, drawings = Roles.posts({ K })
  check(found[Roles.postKey("general", "petalburg", 7)] == true and next(drawings) == nil,
    "Roles.posts: a sign event open on three sides, by its tileset's name")
end

do
  -- the ledge junction: a blocked cell with jumps on two sides at right angles
  local L = layout({
    "....",
    ".#_.",
    "._..",
  })
  local _, r = roleGrid(L)
  check(r.isLedgeJunction(1, 1) and not r.isLedgeJunction(2, 1), "ledge junctions: jumps beside and below")
end

do
  -- alias_of: a map whose rock is the General's drawn again in its own colours
  local own, ref = {}, {}
  for i = 1, 256 do
    own[i] = (i % 2 == 0) and 0x111111 or 0x222222
    ref[i] = (i % 2 == 0) and 0xDEB4A4 or 0x836A5A
  end
  local L = layout({ "MM", "MM" }, { id = "LAYOUT_JAGGED_PASS", secondary = "gTileset_Lavaridge" })
  local blank = {}
  for i = 1, 256 do blank[i] = 0 end
  L.cell = function(m) return m == 0x2A0 and own or blank end
  local reference = { cell = function(m) return m == 0x070 and ref or blank end }
  local alias, back, colour = Roles.aliasOf(L, reference)
  check(alias and alias[0x2A0] == 0x070 and back[0x070] == 0x2A0 and colour[0x111111] == 0xDEB4A4,
    "alias_of: a recoloured tile stands for the General's, colour for colour")
  L.id = "LAYOUT_ROUTE104"
  check(Roles.aliasOf(L, reference) == nil, "...only on the maps read so")
end

print(string.format("%d/%d checks passed (roles)", passed, total))
if passed ~= total then os.exit(1) end
