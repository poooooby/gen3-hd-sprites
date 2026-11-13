-- What every cell of a layout is (Battle Scene: Overworld), for the relief and the signs: Emerald
-- 3DS's voxel_cells.py, every rule of it, in Lua.
--
-- The cartridge answers most of it itself: the behaviour byte says water, ledges and doors; the
-- blockdata says what is blocked; the maps' own events say where the doors (warps) and the signs
-- are, and the map type says whether it is outdoors. The drawing is only asked what the data does
-- not state: whether a blocked cell is drawn as foliage, and whether a walkable one is drawn as
-- steps. Roles, in the order they are decided:
--
--   water     a water behaviour
--   ledge     a jump behaviour
--   stair     walkable and drawn as steps (treads)
--   floor     any other walkable cell
--   signpost  an outdoor post: blocked, open on three sides (a sign, a lamp)
--   wall      part of a building: the blocked mass above a house door
--   tree      blocked and drawn mostly in foliage
--   fence     blocked, one cell thin, walkable on both sides
--   cliff     blocked terrain touching walkable ground
--   shelf     blocked terrain away from walkable ground
--
-- (voxel_cells.py lists a "prop" too; role_at never gives it.)
--
-- Adapted from Emerald 3DS (3ds_port/scripts/voxel_cells.py, and gen_voxel_relief.py's alias_of
-- and rock colours; by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes here: read off the game's own
-- data through an adapter (below) instead of pret's files.
--
-- Plain Lua. A layout adapter L:
--   L.id                    the layout's name ("LAYOUT_ROUTE104": alias_of's maps are named)
--   L.w, L.h
--   L.metatile(x, y)        its metatile id (only asked on the map)
--   L.blocked(x, y)         its collision bits are not 0 (only asked on the map)
--   L.behaviour(x, y)       its behaviour, in the ids opt.behaviours names (the engine: unified ids)
--   L.outdoor               a map of an outdoor type uses it
--   L.warps                 { { x, y }, ... } of every map using it
--   L.signs                 { ["x,y"] = true } its maps' sign events
--   L.primary, L.secondary  its tilesets' names ("gTileset_General" or the engine's "general")
--   L.pixels(m, layer)      { [y * 16 + x] = { r, g, b } } of what layer 0 (lower) or 1 (upper)
--                           draws, colour index 0 left out, colours 0..255 as pret's c * 255 // 31
--                           (Roles.blobPixels reads them off the engine's atlas blobs)
--   L.cell(m)               (alias_of only) 256 colour keys of the metatile as drawn whole,
--                           upper over lower, row major from 1; a lower pixel of colour index 0 is
--                           Roles.CLEAR (see Roles.blobCell)
-- and the game-wide options:
--   opt.behaviours          { MB_NAME = id } Emerald's behaviour names, as L.behaviour's ids
--   opt.posts               { [Roles.postKey(primary, secondary, m)] = true } every metatile a sign
--                           event is drawn with where it stands open on three sides (Roles.posts)
--   opt.postDrawings        { [Roles.drawingKey(upper)] = true } their upper layers
--   opt.reference           (alias_of) an adapter over the General tileset (LAYOUT_ROUTE116's)
--   opt.memo                a table shared by layouts over the same tilesets (what a metatile's
--                           drawing says is the same in all of them)

local Roles = {}

local floor = math.floor

Roles.NUM_PRIMARY = 512
-- A house is at most this many cells either side of its door and this tall.
Roles.HOUSE_HALF_WIDTH, Roles.HOUSE_HEIGHT = 5, 7
Roles.FOLIAGE = 0.5
-- Steps: mean luminance change between neighbouring pixels along a row (at most) and down a
-- column (at least). The General tileset's flight measures 2 and 28; ground, planks and roofs
-- change along their rows too.
Roles.TREAD_ACROSS, Roles.TREAD_DOWN = 4.0, 15.0
-- Rows a covering drawing may leave short: its own outline, top and bottom.
Roles.COVER_SLACK = 2
Roles.CLEAR = -1

local NEIGHBOURS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

-- Secondary-tileset metatiles that stand alone with no sign event and are never a post: drawn flat
-- with their curb or modelled. As signs they stood up as boards: Slateport's curb ends (0x2b9,
-- 0x2c7) by the beach steps and the Contest Hall, its harbour bollard (0x32d), the market's goods
-- (0x20c, 0x26b, 0x26c), a moored sailboat's cell (0x338).
local NOT_POSTS = { slateport = { [0x2B9] = true, [0x2C7] = true, [0x32D] = true, [0x20C] = true,
                                  [0x26B] = true, [0x26C] = true, [0x338] = true } }
-- The General tileset's mountain rock (voxel_terraces.MOUNTAIN's own range): a cliff's corner
-- standing free, or a rock in the sea, is blocked and open on three sides like a post, but it is
-- the mountain - never a post.
local MOUNTAIN_ROCK_FIRST, MOUNTAIN_ROCK_LAST = 0x064, 0x0BF

-- The cells the console draws as water: the game's surfable behaviours, puddles, shallow water,
-- hot springs and the water drawn under a bridge.
Roles.WATER_NAMES = { "MB_POND_WATER", "MB_INTERIOR_DEEP_WATER", "MB_DEEP_WATER", "MB_WATERFALL",
  "MB_SOOTOPOLIS_DEEP_WATER", "MB_OCEAN_WATER", "MB_PUDDLE", "MB_SHALLOW_WATER",
  "MB_NO_SURFACING", "MB_SEAWEED", "MB_SEAWEED_NO_SURFACING", "MB_HOT_SPRINGS",
  "MB_REFLECTION_UNDER_BRIDGE", "MB_EASTWARD_CURRENT", "MB_WESTWARD_CURRENT",
  "MB_NORTHWARD_CURRENT", "MB_SOUTHWARD_CURRENT" }
Roles.HOUSE_DOOR_NAMES = { "MB_ANIMATED_DOOR", "MB_PETALBURG_GYM_DOOR", "MB_CLOSED_SOOTOPOLIS_DOOR" }

-- gen_voxel_relief.py's mountain colours: the tops, the rim, the faces, the speckle in both
local ROCK_ALL = {}
for _, c in ipairs({ { 0xDE, 0xB4, 0xA4 }, { 0xBD, 0x94, 0x8B }, { 0xEE, 0xD5, 0xCD }, { 0x83, 0x5A, 0x5A },
                     { 0x62, 0x41, 0x52 }, { 0x41, 0x31, 0x41 }, { 0x9C, 0x73, 0x73 } }) do
  ROCK_ALL[c[1] * 65536 + c[2] * 256 + c[3]] = true
end
Roles.ROCK_ALL = ROCK_ALL

-- alias_of: the maps whose rock is the General tileset's drawn again in their own colours, and
-- the General rock tiles their tiles are matched with (ROCK_TILES | SIDE_WEST | SIDE_EAST |
-- SEA_CAPS | BOULDER)
local ALIAS_TILESETS = { lavaridge = true, fallarbor = true, mossdeep = true }
Roles.ALIAS_LAYOUTS = { LAYOUT_JAGGED_PASS = true, LAYOUT_MT_CHIMNEY = true, LAYOUT_LAVARIDGE_TOWN = true,
  LAYOUT_ROUTE115 = true, LAYOUT_ROUTE114 = true, LAYOUT_ROUTE112 = true, LAYOUT_ROUTE126 = true }
local ALIAS_ROLES = {}
for _, m in ipairs({ 0x070, 0x072, 0x073, 0x074, 0x075, 0x07B, 0x07C, 0x07D, 0x089, 0x0A9,
                     0x07C, 0x0A9, 0x09F, 0x0A7, 0x091, 0x079, 0x1B0, 0x0AF, 0x0CF, 0x1F0, 0x1F1, 0x33B, 0x33C,
                     0x0A2, 0x172, 0x174, 0x093, 0x094, 0x09B, 0x09C }) do
  ALIAS_ROLES[m] = true
end
local BOULDER_HEADS = { [0x093] = 0x09B, [0x094] = 0x09C }

local function rgbKey(c) return c[1] * 65536 + c[2] * 256 + c[3] end

--- A tileset's short name: "gTileset_General", "general" -> "general"; "gTileset_EverGrande",
--- "ever_grande" -> "evergrande".
function Roles.tilesetName(name)
  local s = tostring(name or ""):gsub("^gTileset_", "")
  return (s:gsub("_", "")):lower()
end

--- An engine tileset pair's tilesets ("general__mossdeep" -> "general", "mossdeep").
function Roles.pairTilesets(pair)
  local p, s = tostring(pair or ""):match("^([^_]+)__(.+)$")
  return p, s
end

--- A metatile as the tileset it is drawn from names it (voxel_cells.post_key).
function Roles.postKey(primary, secondary, m)
  return (m < Roles.NUM_PRIMARY and Roles.tilesetName(primary) or Roles.tilesetName(secondary)) .. ":" .. m
end

--- A layer's drawing pixel by pixel, as one string (voxel_cells.upper_drawing's frozenset).
function Roles.drawingKey(px)
  if not px then return nil end
  local parts = {}
  for k = 0, 255 do
    local p = px[k]
    if p then parts[#parts + 1] = k .. "=" .. rgbKey(p) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ",")
end

-- ---------------------------------------------------------------- the engine's atlas blobs

-- A tileset pair's atlases hold, per metatile, 256 bytes of palette * 16 + colour index, 0 where
-- nothing is drawn (src/import/gba/metatile.lua):
--   under (mids.idx)        the lower layer; a COVERED metatile's upper drawn over it
--   over (mids_over.idx)    a NORMAL or SPLIT metatile's upper layer; a COVERED one's is empty
--   middle (mids_mid.idx)   a NORMAL metatile's lower layer, a COVERED one's upper; a SPLIT one's
--                           is empty
-- So: middle empty - lower is under, upper is over (SPLIT, or a layer drawn empty); over drawn -
-- NORMAL; else middle the same as under - NORMAL with nothing over (or a COVERED one whose lower
-- layer is all under its upper: read as NORMAL, its drawing all lower); else COVERED, its upper
-- the middle and its lower what under shows round it. The lower layer of a COVERED metatile
-- under its upper is not in the blobs: voxel_cells.py only ever reads the two layers together
-- (foliage, treads, rock) or the upper alone (covers, the posts' drawings), which this gives as
-- pret does.

local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end

--- One atlas blob's table: mid -> offset of its 256 bytes.
function Roles.blobIndex(blob)
  if type(blob) ~= "string" or #blob < 12 then return nil end
  local count = u16(blob, 7)
  local index = {}
  local data = 13 + count * 2
  for i = 1, count do index[u16(blob, 11 + i * 2)] = data + (i - 1) * 256 end
  return index
end

--- Colours as pret reads a palette (c * 255 // 31 a channel; Emerald's split: palettes 0-5 the
--- primary's, the rest the secondary's, as the pair's palettes.bin holds them): { [p] = { [c] =
--- { r, g, b } } } from { [p] = { [c] = bgr555 } }.
function Roles.palettes(bgr)
  local out = {}
  for p = 0, 15 do
    local row = bgr and bgr[p]
    out[p] = {}
    for c = 0, 15 do
      local v = row and row[c] or 0
      out[p][c] = { floor((v % 32) * 255 / 31), floor((floor(v / 32) % 32) * 255 / 31),
                    floor((floor(v / 1024) % 32) * 255 / 31) }
    end
  end
  return out
end

--- A metatile's two layers off the blobs: lower, upper ({ [y * 16 + x] = { r, g, b } }).
--- `under`, `over`, `middle` = { blob = string, index = Roles.blobIndex(blob) }.
function Roles.blobPixels(under, over, middle, pals, m)
  local function bytes(b)
    local at = b and b.index and b.index[m]
    if not at then return nil end
    return at, b.blob
  end
  local ua, ub = bytes(under)
  local oa, ob = bytes(over)
  local ma, mb = bytes(middle)
  local function drawn(at, blob)
    if not at then return false end
    for i = 0, 255 do if blob:byte(at + i) ~= 0 then return true end end
    return false
  end
  local function layer(at, blob, keep)
    local out = {}
    if not at then return out end
    for i = 0, 255 do
      local b = blob:byte(at + i)
      if b ~= 0 and (not keep or keep(i)) then out[i] = pals[floor(b / 16) % 16][b % 16] end
    end
    return out
  end
  local overDrawn, middleDrawn = drawn(oa, ob), drawn(ma, mb)
  if not middleDrawn then return layer(ua, ub), layer(oa, ob) end
  if overDrawn then return layer(ma, mb), layer(oa, ob) end
  local same = ua ~= nil
  for i = 0, 255 do
    if not same then break end
    same = ub:byte(ua + i) == mb:byte(ma + i)
  end
  if same then return layer(ua, ub), {} end
  -- COVERED: the upper is the middle, the lower what the under shows round it
  return layer(ua, ub, function(i) return mb:byte(ma + i) == 0 end), layer(ma, mb)
end

--- A metatile drawn whole (voxel_building.LayoutArt.cell_image's colours, upper over lower), row
--- major from 1: colour keys, Roles.CLEAR where the lower layer's colour index is 0 (its palette's
--- first colour, which the blobs do not keep).
function Roles.blobCell(under, over, middle, pals, m)
  local lower, upper = Roles.blobPixels(under, over, middle, pals, m)
  local out = {}
  for i = 0, 255 do
    local p = upper[i] or lower[i]
    out[i + 1] = p and rgbKey(p) or Roles.CLEAR
  end
  return out
end

-- ---------------------------------------------------------------- alias_of

-- A tile's drawing without its palette: colours numbered as they come.
local function drawingOf(cell)
  local lab, n, out = {}, 0, {}
  for i = 1, 256 do
    local c = cell[i]
    local l = lab[c]
    if not l then
      l = n
      lab[c] = l
      n = n + 1
    end
    out[i] = l
  end
  return table.concat(out, ",")
end

--- ({ own id = General id }, { General id = own id }, { own colour = General colour }) of a layout
--- drawn with a tileset whose rock is the General's recoloured (gen_voxel_relief.alias_of over
--- ALIAS_LAYOUTS | ALIAS_TERRACES, the maps the cells read so), else nil. `ref`: an adapter over
--- the General tileset (L.cell of its rock).
function Roles.aliasOf(L, ref)
  if not (Roles.ALIAS_LAYOUTS[L.id] and ALIAS_TILESETS[Roles.tilesetName(L.secondary)]) then return nil end
  if not (ref and ref.cell and L.cell) then return nil end
  local known = {}
  local sorted = {}
  for m in pairs(ALIAS_ROLES) do sorted[#sorted + 1] = m end
  table.sort(sorted)
  for _, m in ipairs(sorted) do
    if m < Roles.NUM_PRIMARY then
      local d = drawingOf(ref.cell(m))
      if known[d] == nil then known[d] = m end
    end
  end
  -- every metatile the map draws, in the order it first comes (rows, then columns), and how often
  local used, order = {}, {}
  for y = 0, L.h - 1 do
    for x = 0, L.w - 1 do
      local m = L.metatile(x, y)
      if used[m] == nil then
        used[m] = 0
        order[#order + 1] = m
      end
      used[m] = used[m] + 1
    end
  end
  local alias, aliasOrder = {}, {}
  local votes, voteOrder = {}, {}     -- own colour -> { counts by General colour, their order }
  for _, m in ipairs(order) do
    if m >= Roles.NUM_PRIMARY then
      local own = L.cell(m)
      local g = known[drawingOf(own)]
      if g then
        alias[m] = g
        aliasOrder[#aliasOrder + 1] = m
        local theirs = ref.cell(g)
        for i = 1, 256 do
          local a, b = own[i], theirs[i]
          local v = votes[a]
          if not v then
            v = { counts = {}, order = {} }
            votes[a] = v
            voteOrder[#voteOrder + 1] = a
          end
          if v.counts[b] == nil then
            v.counts[b] = 0
            v.order[#v.order + 1] = b
          end
          v.counts[b] = v.counts[b] + used[m]
        end
      end
    end
  end
  -- a boulder's head is drawn as a band's head turning the corner under a rim is: it is the
  -- boulder only where the map draws it over the boulder's foot
  for _, m in ipairs(aliasOrder) do
    local g = alias[m]
    if g and BOULDER_HEADS[g] then
      local over = 0
      for y = 0, L.h - 2 do
        for x = 0, L.w - 1 do
          if L.metatile(x, y) == m and alias[L.metatile(x, y + 1)] == BOULDER_HEADS[g] then over = over + 1 end
        end
      end
      if 2 * over < used[m] then alias[m] = nil end
    end
  end
  if next(alias) == nil then return nil end
  local colour = {}
  for _, a in ipairs(voteOrder) do
    local v = votes[a]
    local best, bestN
    for _, b in ipairs(v.order) do
      if not bestN or v.counts[b] > bestN then best, bestN = b, v.counts[b] end
    end
    colour[a] = best
  end
  local back = {}
  local byUse = {}
  for _, m in ipairs(aliasOrder) do if alias[m] then byUse[#byUse + 1] = m end end
  table.sort(byUse, function(a, b)
    if used[a] ~= used[b] then return used[a] > used[b] end
    return a < b
  end)
  for _, m in ipairs(byUse) do if back[alias[m]] == nil then back[alias[m]] = m end end
  return alias, back, colour
end

-- ---------------------------------------------------------------- a layout's roles

--- The game-wide posts (voxel_cells.post_metatiles): every outdoor layout's sign events that stand
--- open on three sides. `layouts`: adapters (L.signs, L.outdoor). Returns posts, postDrawings.
function Roles.posts(layouts)
  local posts, drawings = {}, {}
  for _, L in ipairs(layouts) do
    local r = Roles.new(L, {})
    for k in pairs(L.signs or {}) do
      local x, y = k:match("^(-?%d+),(-?%d+)$")
      x, y = tonumber(x), tonumber(y)
      if x and not r.offMap(x, y) and r.openPost(x, y) then
        local m = L.metatile(x, y)
        posts[Roles.postKey(L.primary, L.secondary, m)] = true
        local d = r.upperDrawing(m)
        if d then drawings[d] = true end
      end
    end
  end
  return posts, drawings
end

--- A layout's roles: an object answering voxel_cells.Layout's questions. role(x, y) is one of
--- the names above.
function Roles.new(L, opt)
  opt = opt or {}
  local W, H = L.w, L.h
  local bv = opt.behaviours or {}
  local water, jumps, doors = {}, {}, {}
  for _, n in ipairs(Roles.WATER_NAMES) do if bv[n] then water[bv[n]] = true end end
  for n, v in pairs(bv) do if n:match("^MB_JUMP_") then jumps[v] = true end end
  for _, n in ipairs(Roles.HOUSE_DOOR_NAMES) do if bv[n] then doors[bv[n]] = true end end
  local primary, secondary = Roles.tilesetName(L.primary), Roles.tilesetName(L.secondary)
  local memo = opt.memo or {}
  memo.foliage = memo.foliage or {}
  memo.treads = memo.treads or {}
  memo.covers = memo.covers or {}
  memo.upper = memo.upper or {}
  memo.drawn = memo.drawn or {}
  local signs = L.signs or {}
  local self = {}

  local function offMap(x, y) return x < 0 or y < 0 or x >= W or y >= H end
  local function metatile(x, y)
    if offMap(x, y) then return nil end
    return L.metatile(x, y)
  end
  local function blocked(x, y)
    if offMap(x, y) then return false end
    return L.blocked(x, y) == true
  end
  local function behaviour(x, y)
    if offMap(x, y) then return 0 end
    return L.behaviour(x, y) or 0
  end
  self.offMap, self.metatile, self.blocked, self.behaviour = offMap, metatile, blocked, behaviour

  local function touchesWalkable(x, y)
    for _, d in ipairs(NEIGHBOURS) do
      if not offMap(x + d[1], y + d[2]) and not blocked(x + d[1], y + d[2]) then return true end
    end
    return false
  end

  -- what the drawing is asked
  local function drawn(m)
    local hit = memo.drawn[m]
    if hit then return hit end
    local lower, upper = L.pixels(m, 0), L.pixels(m, 1)
    local out = {}
    for k, p in pairs(lower or {}) do out[k] = p end
    for k, p in pairs(upper or {}) do out[k] = p end
    memo.drawn[m] = out
    return out
  end
  -- share of a metatile's drawn pixels that are leaves
  local function foliage(m)
    local hit = memo.foliage[m]
    if hit then return hit end
    local n, green = 0, 0
    for _, p in pairs(drawn(m)) do
      n = n + 1
      if p[2] > 64 and p[2] > p[1] + 16 and p[2] > p[3] + 16 then green = green + 1 end
    end
    hit = n > 0 and green / n or 0.0
    memo.foliage[m] = hit
    return hit
  end
  -- drawn over the player right down the cell: the upper layer paints at least half of all but
  -- COVER_SLACK of its rows (a boulder, a bush, a rock outcrop; not a lamp or a post)
  local function covers(m)
    local hit = memo.covers[m]
    if hit ~= nil then return hit end
    local rows = {}
    for k in pairs(L.pixels(m, 1) or {}) do
      local y = floor(k / 16)
      rows[y] = (rows[y] or 0) + 1
    end
    local n = 0
    for y = 0, 15 do if (rows[y] or 0) >= 8 then n = n + 1 end end
    hit = n >= 16 - Roles.COVER_SLACK
    memo.covers[m] = hit
    return hit
  end
  -- drawn as a flight of steps: the cell filled with bands, each row one colour right across and
  -- the rows changing colour down it
  local function treads(m)
    local hit = memo.treads[m]
    if hit ~= nil then return hit end
    local d = drawn(m)
    local count = 0
    for _ in pairs(d) do count = count + 1 end
    local ok = count >= 240
    if ok then
      local lum = {}
      for y = 0, 15 do
        local row = {}
        for x = 0, 15 do
          local p = d[y * 16 + x] or { 0, 0, 0 }
          row[x] = 0.3 * p[1] + 0.59 * p[2] + 0.11 * p[3]
        end
        lum[y] = row
      end
      local across, down = 0, 0
      for y = 0, 15 do for x = 0, 14 do across = across + math.abs(lum[y][x] - lum[y][x + 1]) end end
      for y = 0, 14 do for x = 0, 15 do down = down + math.abs(lum[y][x] - lum[y + 1][x]) end end
      across, down = across / 240.0, down / 240.0
      ok = across <= Roles.TREAD_ACROSS and down >= Roles.TREAD_DOWN
    end
    memo.treads[m] = ok
    return ok
  end
  -- its upper layer, pixel by pixel (nil when it draws nothing there)
  local function upperDrawing(m)
    local hit = memo.upper[m]
    if hit ~= nil then return hit or nil end
    hit = Roles.drawingKey(L.pixels(m, 1)) or false
    memo.upper[m] = hit
    return hit or nil
  end
  self.foliage, self.covers, self.treads, self.upperDrawing, self.drawn = foliage, covers, treads, upperDrawing, drawn

  -- the mountain's colours (gen_voxel_relief.ROCK_ALL; a recoloured map's through alias_of)
  local alias = false
  local function colourMap()
    if alias == false then
      local _, _, colour = Roles.aliasOf(L, opt.reference)
      alias = colour or {}
    end
    return alias
  end
  local function rockPixels(m)
    local colour = colourMap()
    local n = 0
    for _, p in pairs(drawn(m)) do
      local k = rgbKey(p)
      if ROCK_ALL[k] or (colour[k] and ROCK_ALL[colour[k]]) then n = n + 1 end
    end
    return n
  end
  local function mountainDrawn(m)
    local count = 0
    for _ in pairs(drawn(m)) do count = count + 1 end
    return count > 0 and 2 * rockPixels(m) >= count
  end
  self.rockPixels, self.mountainDrawn = rockPixels, mountainDrawn

  -- buildings: the mass above each house door
  local houses
  local function housesOf()
    if houses then return houses end
    houses = {}
    for _, w in ipairs(L.warps or {}) do
      local dx, dy = w[1], w[2]
      if doors[behaviour(dx, dy)] and not offMap(dx, dy - 1) and blocked(dx, dy - 1) then
        local seed = (dy - 1) * W + dx
        local stack, seen = { { dx, dy - 1 } }, { [seed] = true }
        while #stack > 0 do
          local p = table.remove(stack)
          houses[p[2] * W + p[1]] = true
          for _, o in ipairs(NEIGHBOURS) do
            local nx, ny = p[1] + o[1], p[2] + o[2]
            local k = ny * W + nx
            if not (seen[k] or offMap(nx, ny) or not blocked(nx, ny)
                    or math.abs(nx - dx) > Roles.HOUSE_HALF_WIDTH or ny > dy or ny < dy - Roles.HOUSE_HEIGHT
                    or foliage(metatile(nx, ny)) >= Roles.FOLIAGE) then
              seen[k] = true
              stack[#stack + 1] = { nx, ny }
            end
          end
        end
      end
    end
    return houses
  end
  local function inHouse(x, y) return not offMap(x, y) and housesOf()[y * W + x] == true end
  self.inHouse = inHouse

  -- the roles
  local function openPost(x, y)
    return L.outdoor == true and blocked(x, y)
      and not blocked(x + 1, y) and not blocked(x - 1, y) and not blocked(x, y + 1)
  end
  local function drawsPostSign(m)
    local u = upperDrawing(m)
    return u ~= nil and (opt.postDrawings or {})[u] == true
  end
  local function drawnAsPost(m)
    return (opt.posts or {})[Roles.postKey(L.primary, L.secondary, m)] == true or drawsPostSign(m)
  end
  local function freePost(x, y)
    if not openPost(x, y) then return false end
    if signs[x .. "," .. y] then return true end
    local m = metatile(x, y)
    if m >= Roles.NUM_PRIMARY and NOT_POSTS[secondary] and NOT_POSTS[secondary][m] then return false end
    if m < Roles.NUM_PRIMARY and primary == "general" and m >= MOUNTAIN_ROCK_FIRST and m <= MOUNTAIN_ROCK_LAST then
      return false
    end
    if m >= Roles.NUM_PRIMARY and mountainDrawn(m) then return false end
    -- a corner of a mountain's outline: a little of its rock, the mountain drawn on beside it
    if m >= Roles.NUM_PRIMARY and rockPixels(m) > 0 then
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if not offMap(nx, ny) and mountainDrawn(metatile(nx, ny)) then return false end
      end
    end
    if covers(m) then return false end
    if foliage(m) >= Roles.FOLIAGE or inHouse(x, y) then return false end
    return not blocked(x, y - 1) or metatile(x, y - 1) ~= m
  end
  -- (post, head) metatiles of the posts that stand free with no sign event and a head drawn in
  -- the open cell north of them: lamps
  local lamps
  local function lampsOf()
    if lamps then return lamps end
    lamps = {}
    for y = 1, H - 1 do
      for x = 0, W - 1 do
        if not signs[x .. "," .. y] and not blocked(x, y - 1) and next(L.pixels(metatile(x, y - 1), 1) or {})
            and freePost(x, y) then
          lamps[metatile(x, y) .. ":" .. metatile(x, y - 1)] = true
        end
      end
    end
    return lamps
  end
  local function isSignpost(x, y)
    if not L.outdoor or not blocked(x, y) then return false end
    if not blocked(x, y + 1) and not offMap(x, y + 1) and drawnAsPost(metatile(x, y)) then return true end
    if freePost(x, y) then return true end
    -- a lamp drawn like the map's free-standing ones is one against a house's wall too, walkable
    -- to its south and on its other side
    if blocked(x, y + 1) or offMap(x, y + 1) or not lampsOf()[tostring(metatile(x, y)) .. ":" .. tostring(metatile(x, y - 1))] then
      return false
    end
    local sides = {}
    for _, dx in ipairs({ -1, 1 }) do if blocked(x + dx, y) then sides[#sides + 1] = x + dx end end
    return #sides == 1 and inHouse(sides[1], y)
  end
  local function isLedgeJunction(x, y)
    if not blocked(x, y) then return false end
    local horizontal = jumps[behaviour(x - 1, y)] or jumps[behaviour(x + 1, y)]
    local vertical = jumps[behaviour(x, y - 1)] or jumps[behaviour(x, y + 1)]
    return (horizontal and vertical) == true
  end
  self.openPost, self.freePost, self.isSignpost, self.drawnAsPost, self.isLedgeJunction =
    openPost, freePost, isSignpost, drawnAsPost, isLedgeJunction
  self.touchesWalkable = touchesWalkable

  local roles = {}
  local function role(x, y)
    local k = y * W + x
    local hit = roles[k]
    if hit then return hit end
    local b = behaviour(x, y)
    if water[b] then hit = "water"
    elseif jumps[b] then hit = "ledge"
    elseif not blocked(x, y) then hit = treads(metatile(x, y)) and "stair" or "floor"
    elseif isSignpost(x, y) then hit = "signpost"
    elseif inHouse(x, y) then hit = "wall"
    elseif foliage(metatile(x, y)) >= Roles.FOLIAGE then hit = "tree"
    elseif (not blocked(x, y - 1) and not blocked(x, y + 1) and not offMap(x, y - 1) and not offMap(x, y + 1))
        or (not blocked(x - 1, y) and not blocked(x + 1, y) and not offMap(x - 1, y) and not offMap(x + 1, y)) then
      hit = "fence"
    elseif touchesWalkable(x, y) then hit = "cliff"
    else hit = "shelf" end
    roles[k] = hit
    return hit
  end
  self.role = role
  self.water, self.jumps = water, jumps
  return self
end

local LETTERS = { water = "~", ledge = "_", stair = "=", floor = ".", signpost = "S", wall = "W",
                  tree = "T", fence = "|", cliff = "#", shelf = "%", prop = "o" }
Roles.LETTERS = LETTERS

--- A layout's roles as voxel_cells.py prints them: a line of letters a row.
function Roles.letters(r, W, H)
  local lines = {}
  for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do row[#row + 1] = LETTERS[r.role(x, y)] end
    lines[#lines + 1] = table.concat(row)
  end
  return lines
end

return Roles
