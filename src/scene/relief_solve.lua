-- Terrain relief read off the drawing (Battle Scene: Overworld): Emerald 3DS's relief generator,
-- run once a game over the player's own maps. It reads every outdoor layout's drawing and writes
-- what Emerald 3DS's relief.bin holds after its export pass: each lifted cell's 5x5 lattice of
-- heights (pixels), each map's base, its cut tiles (src/scene/relief.lua draws them).
--
-- The premise (gen_voxel_relief.py's): the GBA draws the world in a 45-degree oblique view, a
-- point (X, Y, Z) landing on the art at u = X, v = Z - Y. So a height h for every point of the art
-- places it at (u, h, v + h), and for any h the GBA's view of that is the drawing itself: the only
-- question is how high each point is. The drawing answers it: land splits into regions at its
-- rock bands and a band between two regions is a face, one level; maps whose mountains are drawn
-- with the General tileset's rock are read pixel by pixel, terrace by terrace, and the world's maps
-- are placed against each other so the ground meets at every seam. Ledges are berms raised off
-- their lip's drawing.
--
-- Adapted from Emerald 3DS (3ds_port/scripts/gen_voxel_relief.py up to and including export(),
-- with voxel_cells.py's roles (src/scene/roles.lua) and voxel_props.py; by Zallax and
-- contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes
-- here: written in Lua over the cartridge's own data (src/scene/relief_input.lua), its output a
-- table instead of a file; every rule, constant and tie-break the same (the result is byte for
-- byte the generator's).
--
-- Plain Lua (LuaJIT: src/scene/relief_art.lua's hash). Solve.run(input, opt) with
--   input       src/scene/relief_input.lua's
--   opt.Art, opt.Roles   src/scene/relief_art.lua, src/scene/roles.lua
--   opt.parts   { relief_drawn, relief_shape, relief_cuts, relief_world } (each function(S))
--   opt.regionTies(group, prep) -> { {a, b, d}, ... } or nil: voxel_terraces.region_ties for
--               the groups the world places by the terraces' count (Route 111's), in its order
--   opt.tick    optional, called now and then (the solve is sliced in a coroutine)
--   opt.phase(name)   optional, called as each phase ends ("groups", "world", "export")
-- returns { layouts = { [id] = { w, h, flags, base, belt, ease, level, cells } }, variants = { [k]
-- = { layout, metatile, rows } } (from 0), nVariants, cuts = { [layout * 65536 + x * 256 + y] =
-- { variant, foot, ground, wall, sides, flags } }, edges = {} } - src/scene/relief.lua's model.

local Solve = {}

local floor, ceil, min, max, abs, sqrt = math.floor, math.ceil, math.min, math.max, math.abs, math.sqrt

-- ── constants (gen_voxel_relief.py's) ────────────────────────────────────────

local LEVEL, STEP = 16, 4
local PER_CELL = 4
local MOUND, MOUND_MAX = 8, 24
Solve.ENABLED = { "LAYOUT_ROUTE104", "LAYOUT_RUSTBORO_CITY" }
local ENABLED = { LAYOUT_ROUTE104 = true, LAYOUT_RUSTBORO_CITY = true }
local RELIEF_ROLES = { cliff = true, shelf = true, stair = true }
local JUMPS = { [0x38] = { { 1, 0 } }, [0x39] = { { -1, 0 } }, [0x3A] = { { 0, -1 } }, [0x3B] = { { 0, 1 } },
                [0x3C] = { { 1, 0 }, { 0, -1 } }, [0x3D] = { { -1, 0 }, { 0, -1 } },
                [0x3E] = { { 1, 0 }, { 0, 1 } }, [0x3F] = { { -1, 0 }, { 0, 1 } } }
local LIP, LIP_WIDTH, LIP_BACK = 6, 8, 8

local function rgb(r, g, b) return r * 65536 + g * 256 + b end
local ROCK_TOP = { [rgb(0xDE, 0xB4, 0xA4)] = true, [rgb(0xBD, 0x94, 0x8B)] = true }
local ROCK_RIM = { [rgb(0xEE, 0xD5, 0xCD)] = true }
local ROCK_FACE = { [rgb(0x83, 0x5A, 0x5A)] = true, [rgb(0x62, 0x41, 0x52)] = true, [rgb(0x41, 0x31, 0x41)] = true }
local ROCK_FLECK = { [rgb(0x9C, 0x73, 0x73)] = true }
local ROCK_ALL = {}
for _, t in ipairs({ ROCK_TOP, ROCK_RIM, ROCK_FACE, ROCK_FLECK }) do for k in pairs(t) do ROCK_ALL[k] = true end end
Solve.ROCK_TOP, Solve.ROCK_RIM, Solve.ROCK_FACE, Solve.ROCK_FLECK, Solve.ROCK_ALL =
  ROCK_TOP, ROCK_RIM, ROCK_FACE, ROCK_FLECK, ROCK_ALL
local RIM_RISE = 16
local GOES_ON = 2
local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
local DIRT = set({ 0x113, 0x114, 0x115, 0x14B, 0x14C, 0x14D })
local BOULDER = set({ 0x93, 0x94, 0x9B, 0x9C })
local BOULDER_HEADS = { [0x93] = 0x9B, [0x94] = 0x9C }
local SIDE_WEST = set({ 0x070, 0x073 })
local SIDE_EAST = set({ 0x072, 0x075, 0x0A2 })
local SEA_CAPS = set({ 0x172, 0x174 })
local SIDE_RISE = 16
local RIDGE_TOP = 2
local FACE_SOUTH = set({ 0x07C, 0x0A9, 0x09F, 0x0A7, 0x091, 0x079, 0x1B0, 0x0AF, 0x0CF, 0x1F0, 0x1F1, 0x33B, 0x33C })
local FOOTPRINT, REGION_MIN, THIN, MAJORITY = 0.6, 200, 7, 2
local GROUND, TOP, FACE, FLECK, RIM, VOID, FREE = 0, 1, 2, 3, 4, 5, 6
local FLAT_ROLES = { floor = true, signpost = true, water = true }
local ROCKY_WATER = 0.5
local SHORE_STRIP = 8
local DRAWN_MIN, DRAWN_SEAM = 5, 2
local ROCK_TILES = set({ 0x070, 0x072, 0x073, 0x074, 0x075, 0x07B, 0x07C, 0x07D, 0x089, 0x0A9 })
for m in pairs(FACE_SOUTH) do ROCK_TILES[m] = true end
for m in pairs(SIDE_WEST) do ROCK_TILES[m] = true end
for m in pairs(SIDE_EAST) do ROCK_TILES[m] = true end
local GROUND_SPREAD, MASSIF = 0.05, 160
local DRAWN_EXCLUDED = { route122 = true, ever_grande_city = true }
local SEAM_WEIGHT = 16
local STEP_SEAMS = { ["LAYOUT_ROUTE107|LAYOUT_ROUTE108"] = true, ["LAYOUT_ROUTE108|LAYOUT_ROUTE107"] = true }
local STEP_SEAM_WEIGHT = 1
local COUNTED_GROUPS = { route111 = true, route111_no_mirage_tower = true }
local HARD_WEIGHT, LOOSE_WEIGHT = 1e6, 0.01
local WORLD_ROOT = "LAYOUT_LITTLEROOT_TOWN"
local ROLE_MATCH = 0.9
local WRAP_GROUPS = { route104 = true, route105 = true, route106 = true }
local WRAP_DROP, WRAP_COLUMNS, WRAP_CUT, WRAP_POCKET, WRAP_REACH, WRAP_DEEP = 6, 3, 24, 64, 64, 5
local PIER_REACH = 2
local HEIGHT_UNIT = 2
local CUT_LIFT, CUT_PIXELS = 2.0, 4
local SPREAD = 1.25
local NO_FACE = 0xFFFE
Solve.C = { LEVEL = LEVEL, STEP = STEP, PER_CELL = PER_CELL, GROUND = GROUND, TOP = TOP, FACE = FACE,
            FLECK = FLECK, RIM = RIM, VOID = VOID, FREE = FREE, FOOTPRINT = FOOTPRINT, REGION_MIN = REGION_MIN,
            THIN = THIN, MAJORITY = MAJORITY, RIM_RISE = RIM_RISE, SIDE_RISE = SIDE_RISE, RIDGE_TOP = RIDGE_TOP,
            SHORE_STRIP = SHORE_STRIP, ROCKY_WATER = ROCKY_WATER, ROLE_MATCH = ROLE_MATCH,
            WRAP_DROP = WRAP_DROP, WRAP_COLUMNS = WRAP_COLUMNS, WRAP_CUT = WRAP_CUT, WRAP_POCKET = WRAP_POCKET,
            WRAP_REACH = WRAP_REACH, WRAP_DEEP = WRAP_DEEP, PIER_REACH = PIER_REACH, CUT_LIFT = CUT_LIFT,
            CUT_PIXELS = CUT_PIXELS, SPREAD = SPREAD, NO_FACE = NO_FACE, GOES_ON = GOES_ON,
            LIP = LIP, LIP_WIDTH = LIP_WIDTH, LIP_BACK = LIP_BACK }
Solve.SETS = { DIRT = DIRT, BOULDER = BOULDER, BOULDER_HEADS = BOULDER_HEADS, SIDE_WEST = SIDE_WEST,
               SIDE_EAST = SIDE_EAST, SEA_CAPS = SEA_CAPS, FACE_SOUTH = FACE_SOUTH, ROCK_TILES = ROCK_TILES,
               FLAT_ROLES = FLAT_ROLES, WRAP_GROUPS = WRAP_GROUPS }

-- the General rock tiles alias_of matches (ROCK_TILES | SIDE_WEST | SIDE_EAST | SEA_CAPS | BOULDER)
local ALIAS_MATCHED = {}
do
  local all = {}
  for m in pairs(ROCK_TILES) do all[m] = true end
  for m in pairs(SEA_CAPS) do all[m] = true end
  for m in pairs(BOULDER) do all[m] = true end
  for m in pairs(all) do ALIAS_MATCHED[#ALIAS_MATCHED + 1] = m end
  table.sort(ALIAS_MATCHED)
end

-- voxel_props.OBJECTS: drawn as a block of upper-layer subtiles wherever it lands
local OBJECTS = {
  { name = "sea_rock", tileset = "general", palette = 1, grid = { { 141, 142 }, { 157, 158 } } },
  { name = "sand_boulder", land = true, tileset = "general", palette = 3, grid = { { 88, 89 }, { 104, 105 } } },
  { name = "sea_stack", tileset = "general", palette = 3,
    grid = { { false, 65, 68, { 69, true, 0 } }, { 80, 81, 84, 85 }, { 128, 129, 132, 133 }, { 144, 145, 148, 149 } } },
  { name = "sand_boulder_fallarbor", land = true, tileset = "general", secondary = "fallarbor", palette = 11,
    grid = { { 88, 89 }, { 104, 105 } } },
  { name = "sea_stack_fallarbor", tileset = "general", secondary = "fallarbor", palette = 11,
    grid = { { false, 65, 68, { 69, true, 11 } }, { 80, 81, 84, 85 }, { 128, 129, 132, 133 }, { 144, 145, 148, 149 } } },
  { name = "frontier_flag_east", tileset = "general", secondary = "battlefrontieroutsideeast", land = true,
    palette = 11, grid = { { 730, 731, 732 }, { 733, 734, 735 }, { 746, false, false }, { 762, false, false } } },
  { name = "frontier_flag_west", tileset = "general", secondary = "battlefrontieroutsidewest", land = true,
    palette = 11, grid = { { 730, 731, 732 }, { 733, 734, 735 }, { 746, false, false }, { 762, false, false } } },
  { name = "basket_green", tileset = "general", secondary = "slateport", land = true, palette = 7,
    grid = { { 518, 519 }, { 534, 535 } } },
  { name = "basket_orange", tileset = "general", secondary = "slateport", land = true, palette = 7,
    grid = { { 516, 517 }, { 532, 533 } } },
  { name = "basket_red", tileset = "general", secondary = "slateport", land = true, palette = 7,
    grid = { { 514, 515 }, { 530, 531 } } },
  { name = "urn", tileset = "general", secondary = "slateport", land = true, palette = 7, grid = { { 614, 615 }, { 630, 631 } } },
  { name = "fruit", tileset = "general", secondary = "slateport", land = true, palette = 7, grid = { { 736, 737 }, { 738, 739 } } },
}

-- ── small helpers ────────────────────────────────────────────────────────────

-- a cell or point key (coordinates may run a little negative)
local function K(x, y) return (y + 4096) * 16384 + (x + 4096) end
local function KX(k) return k % 16384 - 4096 end
local function KY(k) return floor(k / 16384) - 4096 end
Solve.K, Solve.KX, Solve.KY = K, KX, KY

local function grid2(W, H, v)
  local t = {}
  for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do row[x] = v end
    t[y] = row
  end
  return t
end
Solve.grid2 = grid2

local function copyRow(r, n)
  local o = {}
  for i = 0, n - 1 do o[i] = r[i] end
  return o
end

-- a cell's 5x5 lattice out of a layout's: g[j][i]
local function cellGrid(h, x, y)
  local g = {}
  for j = 0, PER_CELL do
    local row, src = {}, h[y * PER_CELL + j]
    for i = 0, PER_CELL do row[i] = src[x * PER_CELL + i] end
    g[j] = row
  end
  return g
end
Solve.cellGrid = cellGrid

local function gridEq(a, b)
  for j = 0, PER_CELL do
    for i = 0, PER_CELL do if a[j][i] ~= b[j][i] then return false end end
  end
  return true
end
Solve.gridEq = gridEq

local function gridCopy(g)
  local o = {}
  for j = 0, PER_CELL do o[j] = copyRow(g[j], PER_CELL + 1) end
  return o
end
Solve.gridCopy = gridCopy

local function gmax(g)
  local m = -math.huge
  for j = 0, PER_CELL do for i = 0, PER_CELL do if g[j][i] > m then m = g[j][i] end end end
  return m
end
local function gmin(g)
  local m = math.huge
  for j = 0, PER_CELL do for i = 0, PER_CELL do if g[j][i] < m then m = g[j][i] end end end
  return m
end
Solve.gmax, Solve.gmin = gmax, gmin

-- a Counter's most_common(1): the greatest count, ties to the first counted (keys in `order`)
local function mostCommon(counts, order)
  local best, bn
  for _, k in ipairs(order) do
    if not bn or counts[k] > bn then best, bn = k, counts[k] end
  end
  return best, bn
end
Solve.mostCommon = mostCommon

local function counter()
  local c = { n = {}, order = {} }
  function c.add(k, v)
    if c.n[k] == nil then
      c.n[k] = 0
      c.order[#c.order + 1] = k
    end
    c.n[k] = c.n[k] + (v or 1)
  end
  function c.most() return mostCommon(c.n, c.order) end
  return c
end
Solve.counter = counter

-- ── the run ──────────────────────────────────────────────────────────────────

function Solve.run(input, opt)
  local Art, Roles = opt.Art, opt.Roles
  local tick = opt.tick or function() end
  local S = { input = input, opt = opt, Art = Art, Roles = Roles, tick = tick, Solve = Solve }
  local layouts = input.byName
  local MB = input.behaviours

  -- the layouts in the cartridge's order (by id)
  local ids = {}
  for id in pairs(input.layouts) do ids[#ids + 1] = id end
  table.sort(ids)
  local ordered = {}
  for _, id in ipairs(ids) do ordered[#ordered + 1] = input.layouts[id] end
  S.ordered = ordered

  -- vc.MapEvents().outdoor and vc.alternate_layouts()
  local outdoor = {}
  for _, L in ipairs(ordered) do if L.outdoor then outdoor[L.name] = true end end
  local alternates = {}       -- alt name -> base name
  for _, L in ipairs(ordered) do if L.alternateOf then alternates[L.name] = L.alternateOf end end
  S.outdoor, S.alternates = outdoor, alternates

  -- behaviour sets by name
  local WATERFALL = MB.MB_WATERFALL
  local BERRY = MB.MB_BERRY_TREE_SOIL
  local FLAT_BEHAVIOURS, SANDS = {}, {}
  for name, v in pairs(MB) do
    if name:find("BRIDGE", 1, true) or name:find("_LOG_", 1, true) or name:sub(-5) == "_DOOR"
        or name == "MB_NO_RUNNING" then
      FLAT_BEHAVIOURS[v] = true
    end
    if name:find("SAND", 1, true) then SANDS[v] = true end
  end
  if MB.MB_REFLECTION_UNDER_BRIDGE then FLAT_BEHAVIOURS[MB.MB_REFLECTION_UNDER_BRIDGE] = nil end
  -- (a name the enum has twice keeps both values: Python's set of every name's value)
  S.WATERFALL, S.BERRY, S.FLAT_BEHAVIOURS, S.SANDS = WATERFALL, BERRY, FLAT_BEHAVIOURS, SANDS

  -- the drawings: a pair per tileset pair, a LayoutArt per layout
  local pairs_ = {}
  local function pairOf(L)
    local key = L.primary.key .. "/" .. L.secondary.key
    local p = pairs_[key]
    if not p then
      p = Art.pair(L.primary, L.secondary)
      pairs_[key] = p
    end
    return p
  end
  local plainArt = {}
  local function vbArt(lid)
    local a = plainArt[lid]
    if not a then
      local L = layouts[lid]
      a = Art.layoutArt(L, pairOf(L))
      plainArt[lid] = a
    end
    return a
  end
  S.vbArt, S.pairOf = vbArt, pairOf

  -- alias_of(lid, layouts)
  local aliasMemo = {}
  local function aliasOf(lid, set_)
    set_ = set_ or Art.ALIAS_LAYOUTS
    if not set_[lid] then return nil end
    local hit = aliasMemo[lid]
    if hit ~= nil then return hit or nil end
    aliasMemo[lid] = false
    local L = layouts[lid]
    if not L then return nil end
    local a = Art.aliasOf(vbArt(lid), vbArt(Art.ALIAS_REFERENCE), ALIAS_MATCHED, BOULDER_HEADS)
    aliasMemo[lid] = a or false
    return a
  end
  S.aliasOf = aliasOf

  local artMemo = {}
  local function layoutArt(lid)
    local a = artMemo[lid]
    if a then return a end
    local al = aliasOf(lid)
    a = al and Art.aliasArt(vbArt(lid), al) or vbArt(lid)
    artMemo[lid] = a
    return a
  end
  S.layoutArt = layoutArt
  function S.ownId(lid, m)
    local a = aliasOf(lid)
    return a and a.back[m] or m
  end
  S.artMemo = artMemo

  -- ── the roles (voxel_cells.Layout, src/scene/roles.lua over the raw drawing) ──
  local roleAdapters = {}
  local rgbCache = {}
  local function adapter(L)
    local A = roleAdapters[L.name]
    if A then return A end
    local p = pairOf(L)
    local W = L.w
    local pix = {}
    A = {
      id = L.name, w = L.w, h = L.h, outdoor = L.outdoor, warps = L.warps, signs = L.signs,
      primary = L.primary.name, secondary = L.secondary.name,
      metatile = function(x, y) return L.blocks[y * W + x] % 1024 end,
      blocked = function(x, y) return floor(L.blocks[y * W + x] / 1024) % 4 ~= 0 end,
      behaviour = function(x, y) return p.attribute(L.blocks[y * W + x] % 1024) % 256 end,
      pixels = function(m, layer)
        local key = m * 2 + layer
        local t = pix[key]
        if not t then
          t = {}
          for k, c in pairs(p.layerPixels(m, layer)) do
            local e = rgbCache[c]
            if not e then
              e = { floor(c / 65536), floor(c / 256) % 256, c % 256 }
              rgbCache[c] = e
            end
            t[k] = e
          end
          pix[key] = t
        end
        return t
      end,
      cell = function(m)
        local img = p.cellImage(m)
        local t = {}
        for k = 0, 255 do t[k + 1] = img[k] end
        return t
      end,
    }
    roleAdapters[L.name] = A
    return A
  end
  local postsMemo
  local function posts()
    if not postsMemo then
      local all = {}
      for _, L in ipairs(ordered) do
        if L.outdoor and next(L.signs) then all[#all + 1] = adapter(L) end
      end
      local p, d = Roles.posts(all)
      postsMemo = { p, d }
    end
    return postsMemo[1], postsMemo[2]
  end
  local rolesMemo = {}
  local function rolesOf(lid)
    local r = rolesMemo[lid]
    if r then return r end
    local L = layouts[lid]
    local p, d = posts()
    local ref = layouts[Art.ALIAS_REFERENCE]
    r = Roles.new(adapter(L), { behaviours = MB, posts = p, postDrawings = d,
                                reference = ref and adapter(ref) or nil, memo = nil })
    rolesMemo[lid] = r
    return r
  end

  -- the sides some map using a layout connects on
  local mapSides = {}
  for _, m in ipairs(input.maps) do
    local L = input.layouts[m.layout]
    if L then
      local s = mapSides[L.name]
      if not s then s = {}; mapSides[L.name] = s end
      for _, c in ipairs(m.connections) do
        if c.direction then s[c.direction] = true end
      end
    end
  end

  --- open_roles(lid, connections): the layout as the generators ask it
  local rlMemo = {}
  local function openRoles(lid, connections)
    local key = lid .. (connections == false and "|0" or "|1")
    local RL = rlMemo[key]
    if RL then return RL end
    local L = layouts[lid]
    local r = rolesOf(lid)
    local W, H = L.w, L.h
    local p = pairOf(L)
    RL = { layout_id = lid, w = W, h = H, outdoor = L.outdoor, primary = L.primary.name,
           secondary = L.secondary.name, L = L, roles = r }
    function RL.off_map(x, y) return x < 0 or y < 0 or x >= W or y >= H end
    function RL.metatile(x, y)
      if x < 0 or y < 0 or x >= W or y >= H then return nil end
      return L.blocks[y * W + x] % 1024
    end
    function RL.blocked(x, y)
      if x < 0 or y < 0 or x >= W or y >= H then return false end
      return floor(L.blocks[y * W + x] / 1024) % 4 ~= 0
    end
    function RL.behaviour(x, y)
      if x < 0 or y < 0 or x >= W or y >= H then return 0 end
      return p.attribute(L.blocks[y * W + x] % 1024) % 256
    end
    RL.role_at = r.role
    RL.covers = r.covers
    RL.is_ledge_junction = r.isLedgeJunction
    RL.warps = L.warpSet
    if connections ~= false then
      local sides = {}
      for d in pairs(mapSides[lid] or {}) do sides[#sides + 1] = d end
      table.sort(sides)
      RL.connected_sides = sides
    end
    rlMemo[key] = RL
    return RL
  end
  S.openRoles = openRoles

  -- ── voxel_props: the objects found by their upper-layer subtiles ─────────────
  local propConnections
  local function connectionsOf()
    if propConnections then return propConnections end
    local out = {}
    for _, m in ipairs(input.maps) do
      local A = input.layouts[m.layout]
      for _, c in ipairs(m.connections) do
        local B = input.layouts[c.layout]
        if A and B and B ~= A then
          local off, d = c.offset, c.direction
          local at = d == "down" and { off, A.h } or d == "up" and { off, -B.h } or d == "right" and { A.w, off }
            or d == "left" and { -B.w, off } or nil
          if at then
            local t = out[A.name]
            if not t then t = {}; out[A.name] = t end
            t[#t + 1] = { B.name, at[1], at[2] }
          end
        end
      end
    end
    propConnections = out
    return out
  end
  local subsMemo = {}
  local function subtilesOf(lid)
    local s = subsMemo[lid]
    if s then return s end
    local L = layouts[lid]
    local p = pairOf(L)
    s = {}
    local order = {}
    for y = 0, L.h - 1 do
      for x = 0, L.w - 1 do
        local e = p.entries(L.blocks[y * L.w + x] % 1024)
        if e then
          for q = 0, 3 do
            local en = e[4 + q]
            if en % 1024 ~= 0 then
              local k = K(x * 2 + q % 2, y * 2 + floor(q / 2))
              s[k] = { en % 1024, floor(en / 4096) % 16, floor(en / 1024) % 4 }
              order[#order + 1] = k
            end
          end
        end
      end
    end
    s = { at = s, order = order }
    subsMemo[lid] = s
    return s
  end
  local function beyond(lid, x, y)
    for _, c in ipairs(connectionsOf()[lid] or {}) do
      local B = layouts[c[1]]
      if x - c[2] >= 0 and x - c[2] < B.w and y - c[3] >= 0 and y - c[3] < B.h then
        return c[1], x - c[2], y - c[3]
      end
    end
    return nil
  end
  local function findProps(lid)
    local L = layouts[lid]
    local found = {}
    local primary, secondary = L.primary.name, L.secondary.name
    local w, h = L.w, L.h
    for _, obj in ipairs(OBJECTS) do
      if primary == obj.tileset and (obj.secondary or secondary) == secondary then
        local subs = subtilesOf(lid)
        local function subAt(sx, sy)
          if sx >= 0 and sx < w * 2 and sy >= 0 and sy < h * 2 then return subs.at[K(sx, sy)] end
          local b, bx, by = beyond(lid, floor(sx / 2), floor(sy / 2))
          if not b then return nil end
          if layouts[b].primary.name ~= primary then return nil end
          return subtilesOf(b).at[K(bx * 2 + sx % 2, by * 2 + sy % 2)]
        end
        local grid = obj.grid
        local ai, aj, at
        for j, row in ipairs(grid) do
          for i, t in ipairs(row) do
            if not ai and t and type(t) ~= "table" then ai, aj, at = i - 1, j - 1, t end
          end
        end
        for _, k in ipairs(subs.order) do
          local sub = subs.at[k]
          if sub[1] == at and sub[2] == obj.palette and sub[3] == 0 then
            local x0, y0 = KX(k) - ai, KY(k) - aj
            local ok = true
            for j, row in ipairs(grid) do
              for i, t in ipairs(row) do
                if t then
                  local want, optional, pal
                  if type(t) == "table" then want, optional, pal = t[1], t[2], t[3]
                  else want, optional, pal = t, false, obj.palette end
                  local got = subAt(x0 + i - 1, y0 + j - 1)
                  if not (got and got[1] == want and got[2] == pal and got[3] == 0) and not optional then
                    ok = false
                    break
                  end
                end
              end
              if not ok then break end
            end
            if ok then found[#found + 1] = { obj, x0, y0 } end
          end
        end
      end
    end
    return found
  end
  local function propCells(obj, sx, sy, into, w, h, dx, dy, onlyOutside, bw, bh)
    local grid = obj.grid
    for j, row in ipairs(grid) do
      for i, t in ipairs(row) do
        if t then
          local x, y = floor((sx + i - 1) / 2), floor((sy + j - 1) / 2)
          local X, Y = x + (dx or 0), y + (dy or 0)
          if onlyOutside then
            if not (x >= 0 and x < bw and y >= 0 and y < bh) and X >= 0 and X < w and Y >= 0 and Y < h then
              into[K(X, Y)] = true
            end
          elseif x >= 0 and x < w and y >= 0 and y < h then
            into[K(x, y)] = true
          end
        end
      end
    end
  end
  S.findProps, S.propConnections = findProps, connectionsOf
  --- voxel_props.cells_in: the cells of a layout an object is drawn over (keys)
  local propsMemo = {}
  function S.propsIn(lid)
    local hit = propsMemo[lid]
    if hit then return hit end
    local L = layouts[lid]
    local out = {}
    for _, f in ipairs(findProps(lid)) do propCells(f[1], f[2], f[3], out, L.w, L.h) end
    for _, c in ipairs(connectionsOf()[lid] or {}) do
      local B = layouts[c[1]]
      for _, f in ipairs(findProps(c[1])) do
        propCells(f[1], f[2], f[3], out, L.w, L.h, c[2], c[3], true, B.w, B.h)
      end
    end
    propsMemo[lid] = out
    return out
  end

  -- ── solve(): the region extrusion of the ENABLED maps ────────────────────────
  local function awash(RL, mass, kind)
    local art = layoutArt(RL.layout_id)
    local water = {}
    for _, c in ipairs(mass) do
      local x, y = c[1], c[2]
      for _, n in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
        local nx, ny = n[1], n[2]
        if nx >= 0 and nx < RL.w and ny >= 0 and ny < RL.h and kind[ny][nx] == "water" then
          local img = art.cellImage(art.metatile(nx, ny))
          for k = 0, 255 do water[img[k]] = true end
        end
      end
    end
    local same, total = 0, 0
    for _, c in ipairs(mass) do
      local img = art.cellImage(art.metatile(c[1], c[2]))
      for k = 0, 255 do
        total = total + 1
        if water[img[k]] then same = same + 1 end
      end
    end
    return total > 0 and same > floor(total / 2)
  end

  local function solve(RL)
    local W, H = RL.w, RL.h
    local role, kind = grid2(W, H), grid2(W, H)
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local r = RL.role_at(x, y)
        role[y][x] = r
        kind[y][x] = RELIEF_ROLES[r] and "relief" or r == "water" and "water" or "land"
      end
    end
    local region = grid2(W, H, -1)
    local count = 0
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if kind[y][x] == "land" and region[y][x] < 0 then
          local stack = { { x, y } }
          region[y][x] = count
          while #stack > 0 do
            local c = table.remove(stack)
            for _, n in ipairs({ { c[1] + 1, c[2] }, { c[1] - 1, c[2] }, { c[1], c[2] + 1 }, { c[1], c[2] - 1 } }) do
              local nx, ny = n[1], n[2]
              if nx >= 0 and nx < W and ny >= 0 and ny < H and kind[ny][nx] == "land" and region[ny][nx] < 0 then
                region[ny][nx] = count
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
          count = count + 1
        end
      end
    end
    -- south faces
    local edges, edgeOrder = {}, {}
    for x = 0, W - 1 do
      local y = 0
      while y < H do
        if kind[y][x] ~= "relief" or role[y][x] == "stair" then
          y = y + 1
        else
          local y0 = y
          while y < H and kind[y][x] == "relief" and role[y][x] ~= "stair" do y = y + 1 end
          if y0 > 0 and y < H and kind[y0 - 1][x] == "land" and kind[y][x] == "land" then
            local up, down = region[y0 - 1][x], region[y][x]
            if up ~= down then
              local k = up * 100000 + down
              if not edges[k] then
                edges[k] = 0
                edgeOrder[#edgeOrder + 1] = { up, down, k }
              end
              edges[k] = edges[k] + 1
            end
          end
        end
      end
    end
    local level = {}
    local adj = {}
    for r = 0, count - 1 do adj[r] = {} end
    for _, e in ipairs(edgeOrder) do
      local up, down = e[1], e[2]
      adj[up][#adj[up] + 1] = { down, -1 }
      adj[down][#adj[down] + 1] = { up, 1 }
    end
    for start = 0, count - 1 do
      if level[start] == nil then
        level[start] = 0
        local comp, queue = { start }, { start }
        while #queue > 0 do
          local r = table.remove(queue)
          for _, od in ipairs(adj[r]) do
            local o, d = od[1], od[2]
            if level[o] == nil then
              level[o] = level[r] + d
              comp[#comp + 1] = o
              queue[#queue + 1] = o
            end
          end
        end
        local low = math.huge
        for _, r in ipairs(comp) do low = min(low, level[r]) end
        for _, r in ipairs(comp) do level[r] = level[r] - low end
      end
    end
    local cell = grid2(W, H)
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if kind[y][x] == "land" then cell[y][x] = level[region[y][x]] end
      end
    end
    -- level 0 is the land the map meets its neighbours with
    local edge = {}
    for _, side in ipairs(RL.connected_sides or {}) do
      local cells = {}
      if side == "up" then for x = 0, W - 1 do cells[#cells + 1] = { x, 0 } end
      elseif side == "down" then for x = 0, W - 1 do cells[#cells + 1] = { x, H - 1 } end
      elseif side == "left" then for y = 0, H - 1 do cells[#cells + 1] = { 0, y } end
      else for y = 0, H - 1 do cells[#cells + 1] = { W - 1, y } end end
      for _, c in ipairs(cells) do
        if kind[c[2]][c[1]] == "land" then edge[#edge + 1] = cell[c[2]][c[1]] end
      end
    end
    if #edge > 0 then
      local ref = Art.commonest(edge)
      for y = 0, H - 1 do
        for x = 0, W - 1 do
          if cell[y][x] ~= nil then cell[y][x] = cell[y][x] - ref end
        end
      end
    end
    -- water: the lowest land it touches
    local seen = {}
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if kind[y][x] == "water" and not seen[K(x, y)] then
          local body, stack, touch = {}, { { x, y } }, {}
          seen[K(x, y)] = true
          while #stack > 0 do
            local c = table.remove(stack)
            body[#body + 1] = c
            local cx, cy = c[1], c[2]
            for _, n in ipairs({ { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } }) do
              local nx, ny = n[1], n[2]
              if nx >= 0 and nx < W and ny >= 0 and ny < H then
                if kind[ny][nx] == "water" and not seen[K(nx, ny)] then
                  seen[K(nx, ny)] = true
                  stack[#stack + 1] = { nx, ny }
                elseif kind[ny][nx] == "land" then
                  touch[#touch + 1] = cell[ny][nx]
                elseif kind[ny][nx] == "relief" and role[ny][nx] ~= "stair" then
                  local dx, dy = nx - cx, ny - cy
                  local ax, ay = nx, ny
                  for _ = 1, 3 do
                    ax, ay = ax + dx, ay + dy
                    if not (ax >= 0 and ax < W and ay >= 0 and ay < H) or kind[ay][ax] == "water" then break end
                    if kind[ay][ax] == "land" then
                      touch[#touch + 1] = cell[ay][ax] - 1
                      break
                    end
                  end
                end
              end
            end
          end
          local lv = 0
          if #touch > 0 then
            lv = math.huge
            for _, v in ipairs(touch) do lv = min(lv, v) end
          end
          for _, c in ipairs(body) do cell[c[2]][c[1]] = lv end
        end
      end
    end
    -- rock masses with one level all round
    local mounds = {}
    local massSeen = {}
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if kind[y][x] == "relief" and role[y][x] ~= "stair" and not massSeen[K(x, y)] then
          local mass, stack, around, aroundN, wet = {}, { { x, y } }, {}, 0, false
          local aroundVal
          massSeen[K(x, y)] = true
          while #stack > 0 do
            local c = table.remove(stack)
            mass[#mass + 1] = c
            local cx, cy = c[1], c[2]
            for _, n in ipairs({ { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } }) do
              local nx, ny = n[1], n[2]
              if nx >= 0 and nx < W and ny >= 0 and ny < H then
                if kind[ny][nx] == "relief" and role[ny][nx] ~= "stair" then
                  if not massSeen[K(nx, ny)] then
                    massSeen[K(nx, ny)] = true
                    stack[#stack + 1] = { nx, ny }
                  end
                elseif cell[ny][nx] ~= nil then
                  local v = cell[ny][nx]
                  if not around[v] then
                    around[v] = true
                    aroundN = aroundN + 1
                    aroundVal = v
                  end
                  wet = wet or kind[ny][nx] == "water"
                end
              end
            end
          end
          if aroundN <= 1 then
            if wet and not awash(RL, mass, kind) then
              mounds[#mounds + 1] = mass
            else
              local lv = aroundN == 1 and aroundVal or 0
              for _, c in ipairs(mass) do cell[c[2]][c[1]] = lv end
            end
          end
        end
      end
    end
    -- lattice
    local LW, LH = W * PER_CELL + 1, H * PER_CELL + 1
    local h, fixed = grid2(LW, LH, 0.0), grid2(LW, LH, false)
    for j = 0, LH - 1 do
      for i = 0, LW - 1 do
        local xs = (i % PER_CELL == 0) and { floor(i / PER_CELL) - 1, floor(i / PER_CELL) } or { floor(i / PER_CELL) }
        local ys = (j % PER_CELL == 0) and { floor(j / PER_CELL) - 1, floor(j / PER_CELL) } or { floor(j / PER_CELL) }
        local best
        for _, cx in ipairs(xs) do
          for _, cy in ipairs(ys) do
            if cx >= 0 and cx < W and cy >= 0 and cy < H and cell[cy][cx] ~= nil then
              if best == nil or cell[cy][cx] > best then best = cell[cy][cx] end
            end
          end
        end
        if best ~= nil then
          h[j][i] = best * LEVEL
          fixed[j][i] = true
        end
      end
    end
    local free = {}
    for j = 0, LH - 1 do for i = 0, LW - 1 do if not fixed[j][i] then free[#free + 1] = { i, j } end end end
    for _ = 1, 400 do
      local delta = 0.0
      for _, p in ipairs(free) do
        local i, j = p[1], p[2]
        local s, n = 0.0, 0
        if i + 1 < LW then s = s + h[j][i + 1]; n = n + 1 end
        if i - 1 >= 0 then s = s + h[j][i - 1]; n = n + 1 end
        if j + 1 < LH then s = s + h[j + 1][i]; n = n + 1 end
        if j - 1 >= 0 then s = s + h[j - 1][i]; n = n + 1 end
        local v = s / n
        delta = max(delta, abs(v - h[j][i]))
        h[j][i] = v
      end
      tick()
      if delta < 0.01 then break end
    end
    -- mounds
    for _, mass in ipairs(mounds) do
      local inside, insideList = {}, {}
      for _, c in ipairs(mass) do
        for j = c[2] * PER_CELL, c[2] * PER_CELL + PER_CELL do
          for i = c[1] * PER_CELL, c[1] * PER_CELL + PER_CELL do
            if not fixed[j][i] and not inside[K(i, j)] then
              inside[K(i, j)] = true
              insideList[#insideList + 1] = { i, j }
            end
          end
        end
      end
      local dist = {}
      local frontier = {}
      -- (frontier is a list over the set `inside`: its order sets nothing but the walk; the
      -- distances are a breadth-first search's, the same whatever order it starts in)
      for _, p in ipairs(insideList) do
        local i, j = p[1], p[2]
        for _, q in ipairs({ { i + 1, j }, { i - 1, j }, { i, j + 1 }, { i, j - 1 } }) do
          if q[1] >= 0 and q[1] < LW and q[2] >= 0 and q[2] < LH and fixed[q[2]][q[1]] then
            frontier[#frontier + 1] = p
            break
          end
        end
      end
      for _, p in ipairs(frontier) do dist[K(p[1], p[2])] = 1 end
      local k = 1
      while k <= #frontier do
        local p = frontier[k]
        k = k + 1
        for _, q in ipairs({ { p[1] + 1, p[2] }, { p[1] - 1, p[2] }, { p[1], p[2] + 1 }, { p[1], p[2] - 1 } }) do
          local kq = K(q[1], q[2])
          if inside[kq] and not dist[kq] then
            dist[kq] = dist[K(p[1], p[2])] + 1
            frontier[#frontier + 1] = q
          end
        end
      end
      for _, p in ipairs(frontier) do
        local d = dist[K(p[1], p[2])]
        h[p[2]][p[1]] = h[p[2]][p[1]] + min(MOUND_MAX, d * MOUND)
      end
    end
    return role, cell, h
  end
  S.solveEnabled = solve

  -- ── ledges ───────────────────────────────────────────────────────────────────
  --- ledge_cells(layout, junctions): an ordered list of { x, y, dirs } and a lookup by key
  local function ledgeCells(RL, junctions)
    local out, list = {}, {}
    for y = 0, RL.h - 1 do
      for x = 0, RL.w - 1 do
        local d = JUMPS[RL.behaviour(x, y)]
        if d then
          local e = { x, y, d }
          out[K(x, y)] = e
          list[#list + 1] = e
        end
      end
    end
    if junctions == false or ENABLED[RL.layout_id] then return out, list end
    local joins, joinOrder = {}, {}
    for _, e in ipairs(list) do
      local x, y = e[1], e[2]
      for _, n in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
        local nx, ny = n[1], n[2]
        if not (out[K(nx, ny)] or RL.off_map(nx, ny) or not RL.blocked(nx, ny)) and RL.is_ledge_junction(nx, ny) then
          local k = K(nx, ny)
          local dirs = joins[k]
          if not dirs then
            dirs = {}
            joins[k] = dirs
            joinOrder[#joinOrder + 1] = { nx, ny, k }
          end
          for _, d in ipairs(e[3]) do
            local have = false
            for _, o in ipairs(dirs) do if o[1] == d[1] and o[2] == d[2] then have = true end end
            if not have then dirs[#dirs + 1] = d end
          end
        end
      end
    end
    for _, j in ipairs(joinOrder) do
      local e = { j[1], j[2], joins[j[3]] }
      if not out[j[3]] then list[#list + 1] = e end
      out[j[3]] = e
    end
    -- (dict.update keeps an existing key's place: a join is never a jump cell, so it is new)
    return out, list
  end
  S.ledgeCells = ledgeCells

  local function lipHeight(f) return LIP * min(f, LIP_WIDTH) / LIP_WIDTH end
  local function lipRun(lip, px, py, dx, dy, limit)
    limit = limit or 64
    local n = 0
    while n < limit and lip[K(px + n * dx, py + n * dy)] do n = n + 1 end
    return n
  end
  local function ledgeReads(lip, x, y, dirs, i, j)
    local px, py = x * 16 + i * STEP, y * 16 + j * STEP
    local reads = {}
    for _, d in ipairs(dirs) do
      local dx, dy = d[1], d[2]
      local sx, sy
      if dx == 0 then
        sx = min(max(px, x * 16), x * 16 + 15)
        sy = py - (dy < 0 and 1 or 0)
      else
        sx = px - (dx < 0 and 1 or 0)
        sy = min(max(py, y * 16), y * 16 + 15)
      end
      reads[#reads + 1] = { sx, sy, dx, dy, lipRun(lip, sx, sy, dx, dy), lipRun(lip, sx - dx, sy - dy, -dx, -dy) }
    end
    return reads
  end
  local function ledgeLip(RL, art)
    local cells, list = ledgeCells(RL)
    local lip = {}
    for _, e in ipairs(list) do
      local x, y, dirs = e[1], e[2], e[3]
      local ground, any = {}, false
      local ring1 = {}
      for _, d in ipairs(dirs) do ring1[#ring1 + 1] = { -d[1], -d[2] } end
      for _, d in ipairs(dirs) do ring1[#ring1 + 1] = { d[1], d[2] } end
      local ring2 = {}
      for dx = -1, 1 do for dy = -1, 1 do ring2[#ring2 + 1] = { dx, dy } end end
      for _, ring in ipairs({ ring1, ring2 }) do
        for _, d in ipairs(ring) do
          local nx, ny = x + d[1], y + d[2]
          if not (cells[K(nx, ny)] or RL.off_map(nx, ny) or RL.blocked(nx, ny)) then
            local img = art.cellImage(art.metatile(nx, ny))
            for k = 0, 255 do ground[img[k]] = true end
            any = true
          end
        end
        if any then break end
      end
      if any then
        local img = art.cellImage(art.metatile(x, y))
        for j = 0, 15 do
          for i = 0, 15 do
            if not ground[img[j * 16 + i]] then lip[K(x * 16 + i, y * 16 + j)] = true end
          end
        end
      end
    end
    return cells, list, lip
  end
  --- ledge_berms: raise every ledge's lip off the drawing, into h; the ledge cells' count
  local function ledgeBerms(RL, art, h)
    local cells, list, lip = ledgeLip(RL, art)
    if #list == 0 then return 0 end
    local function first(px, py, dx, dy, limit)
      for k = 0, limit - 1 do
        if lip[K(px + k * dx, py + k * dy)] then return k end
      end
      return nil
    end
    local raised, order = {}, {}
    for _, e in ipairs(list) do
      local x, y, dirs = e[1], e[2], e[3]
      for j = 0, PER_CELL do
        for i = 0, PER_CELL do
          local reads = ledgeReads(lip, x, y, dirs, i, j)
          local allF, anyB = true, false
          for _, r in ipairs(reads) do
            if r[5] == 0 then allF = false end
            if r[6] ~= 0 and r[5] == 0 then anyB = true end
          end
          local best
          if allF then
            best = math.huge
            for _, r in ipairs(reads) do best = min(best, lipHeight(r[5])) end
          elseif anyB then
            best = 0.0
          else
            best = 0.0
            for _, r in ipairs(reads) do
              local k = first(r[1], r[2], r[3], r[4], LIP_BACK)
              if k ~= nil then
                local top = lipHeight(lipRun(lip, r[1] + k * r[3], r[2] + k * r[4], r[3], r[4]))
                best = max(best, top * (1.0 - k / LIP_BACK))
              end
            end
          end
          local key = K(x * PER_CELL + i, y * PER_CELL + j)
          if raised[key] == nil then
            raised[key] = best
            order[#order + 1] = key
          else
            raised[key] = max(raised[key], best)
          end
        end
      end
    end
    for _, key in ipairs(order) do
      local gx, gy = KX(key), KY(key)
      local xs = { floor((gx - 1) / PER_CELL), floor(gx / PER_CELL) }
      local ys = { floor((gy - 1) / PER_CELL), floor(gy / PER_CELL) }
      local all = true
      for a = 1, 2 do
        for b = 1, 2 do
          local cx, cy = xs[a], ys[b]
          if not (a == 2 and xs[1] == xs[2]) and not (b == 2 and ys[1] == ys[2]) then
            if cx >= 0 and cx < RL.w and cy >= 0 and cy < RL.h and not cells[K(cx, cy)] then all = false end
          end
        end
      end
      if not all then raised[key] = 0.0 end
    end
    local fall = LIP * STEP / LIP_WIDTH
    -- sorted by -gy, stable: the insertion order within a row
    local pos = {}
    for i, key in ipairs(order) do pos[key] = i end
    local byRow = {}
    for i, key in ipairs(order) do byRow[i] = key end
    table.sort(byRow, function(a, b)
      local ya, yb = KY(a), KY(b)
      if ya ~= yb then return ya > yb end
      return pos[a] < pos[b]
    end)
    for _, key in ipairs(byRow) do
      local gx, gy = KX(key), KY(key)
      local south = raised[K(gx, gy + 1)]
      if south ~= nil and raised[key] > south + fall then raised[key] = south + fall end
    end
    for _, key in ipairs(order) do
      local gx, gy = KX(key), KY(key)
      h[gy][gx] = h[gy][gx] + raised[key]
    end
    return #list
  end
  S.ledgeBerms = ledgeBerms
  -- (for src/scene/relief_terraces.lua)
  S.ledgeLip, S.ledgeReads, S.lipHeight, S.lipRun = ledgeLip, ledgeReads, lipHeight, lipRun

  local function ledgesOnGround(RL, h)
    local cells, list = ledgeCells(RL)
    local function keeps(cx, cy)
      return not cells[K(cx, cy)] and not RL.off_map(cx, cy) and RL.blocked(cx, cy)
    end
    local P = PER_CELL
    for _, e in ipairs(list) do
      local x, y = e[1], e[2]
      local x0, y0 = x * P, y * P
      local c00, c10 = h[y0][x0], h[y0][x0 + P]
      local c01, c11 = h[y0 + P][x0], h[y0 + P][x0 + P]
      for j = 0, P do
        for i = 0, P do
          if not ((i == 0 or i == P) and (j == 0 or j == P)) then
            local sides = {}
            if i == 0 then sides[#sides + 1] = { x - 1, y } end
            if i == P then sides[#sides + 1] = { x + 1, y } end
            if j == 0 then sides[#sides + 1] = { x, y - 1 } end
            if j == P then sides[#sides + 1] = { x, y + 1 } end
            local kept = false
            for _, s in ipairs(sides) do if keeps(s[1], s[2]) then kept = true end end
            if not kept then
              local t, s = i / P, j / P
              h[y0 + j][x0 + i] = ((c00 * (1 - t) + c10 * t) * (1 - s) + (c01 * (1 - t) + c11 * t) * s)
            end
          end
        end
      end
    end
  end
  S.ledgesOnGround = ledgesOnGround

  function S.flatLattice(RL) return grid2(RL.w * PER_CELL + 1, RL.h * PER_CELL + 1, 0.0) end

  --- raise_pits: a boulder standing in open ground, as a mound and not a pit
  function S.raisePits(h)
    local LH, LW = h.n, h.w
    local span = 2 * PER_CELL
    local raised = 0
    local done = {}
    for j0 = 1, LH - 2 do
      for i0 = 1, LW - 2 do
        if not done[K(i0, j0)] then
          local rim = -math.huge
          for a = -1, 1 do for b = -1, 1 do rim = max(rim, h[j0 + b][i0 + a]) end end
          if not (h[j0][i0] >= rim - 0.5) then
            local body, stack, ok = { { i0, j0 } }, { { i0, j0 } }, true
            local seen = { [K(i0, j0)] = true }
            local loI, hiI, loJ, hiJ = i0, i0, j0, j0
            while #stack > 0 and ok do
              local p = table.remove(stack)
              local i, j = p[1], p[2]
              for a = -1, 1 do
                for b = -1, 1 do
                  local qx, qy = i + a, j + b
                  if not seen[K(qx, qy)] then
                    if not (qx >= 0 and qx < LW and qy >= 0 and qy < LH) then
                      ok = false
                      break
                    end
                    local v = h[qy][qx]
                    if v < rim - 0.5 then
                      seen[K(qx, qy)] = true
                      body[#body + 1] = { qx, qy }
                      stack[#stack + 1] = { qx, qy }
                      loI, hiI = min(loI, qx), max(hiI, qx)
                      loJ, hiJ = min(loJ, qy), max(hiJ, qy)
                      if hiI - loI >= span or hiJ - loJ >= span then
                        ok = false
                        break
                      end
                    elseif abs(v - rim) > 0.5 then
                      ok = false
                      break
                    end
                  end
                end
                if not ok then break end
              end
            end
            if ok then
              for _, p in ipairs(body) do done[K(p[1], p[2])] = true end
              local lo = math.huge
              for _, p in ipairs(body) do lo = min(lo, h[p[2]][p[1]]) end
              if not (abs(lo - (rim - LEVEL)) > 0.5) then
                for _, p in ipairs(body) do h[p[2]][p[1]] = 2 * rim - h[p[2]][p[1]] end
                raised = raised + 1
              end
            end
          end
        end
      end
    end
    return raised
  end

  -- ── the drawn groups (find_drawn) ────────────────────────────────────────────
  local function findDrawn()
    local blocks, seeds, seedList = {}, {}, {}
    for _, L in ipairs(ordered) do
      local lid = L.name
      if not alternates[lid] and L.primary.name == "general" then
        local ms = {}
        local a = aliasOf(lid)
        local n = 0
        for i = 0, L.w * L.h - 1 do
          local m = L.blocks[i] % 1024
          if a then m = a.alias[m] or m end
          ms[i] = m
          if ROCK_TILES[m] then n = n + 1 end
        end
        if n > 0 and outdoor[lid] then
          blocks[lid] = ms
          if n >= DRAWN_MIN then
            seeds[lid] = true
            seedList[#seedList + 1] = lid
          end
        end
      end
    end
    local function rockNear(lid, x0, y0, x1, y1)
      local L, ms = layouts[lid], blocks[lid]
      for y = max(0, y0), min(L.h, y1) - 1 do
        for x = max(0, x0), min(L.w, x1) - 1 do
          if ROCK_TILES[ms[y * L.w + x]] then return true end
        end
      end
      return false
    end
    local links = {}
    for _, m in ipairs(input.maps) do
      local A = input.layouts[m.layout]
      local a = A and A.name
      if a and blocks[a] then
        for _, c in ipairs(m.connections) do
          local B = input.layouts[c.layout]
          local b = B and B.name
          if b and blocks[b] and b ~= a then
            local off, d = c.offset, c.direction
            local dx, dy, seam
            if d == "down" then
              dx, dy = off, A.h
              seam = rockNear(a, off, A.h - DRAWN_SEAM, off + B.w, A.h) and rockNear(b, -off, 0, -off + A.w, DRAWN_SEAM)
            elseif d == "up" then
              dx, dy = off, -B.h
              seam = rockNear(a, off, 0, off + B.w, DRAWN_SEAM) and rockNear(b, -off, B.h - DRAWN_SEAM, -off + A.w, B.h)
            elseif d == "right" then
              dx, dy = A.w, off
              seam = rockNear(a, A.w - DRAWN_SEAM, off, A.w, off + B.h) and rockNear(b, 0, -off, DRAWN_SEAM, -off + A.h)
            elseif d == "left" then
              dx, dy = -B.w, off
              seam = rockNear(a, 0, off, DRAWN_SEAM, off + B.h) and rockNear(b, B.w - DRAWN_SEAM, -off, B.w, -off + A.h)
            end
            if dx and seam then
              links[a] = links[a] or {}
              links[a][#links[a] + 1] = { b, dx, dy }
              links[b] = links[b] or {}
              links[b][#links[b] + 1] = { a, -dx, -dy }
            end
          end
        end
      end
    end
    table.sort(seedList)
    local groups, seen = {}, {}
    for _, lid in ipairs(seedList) do
      if not seen[lid] then
        local pos, posOrder, queue = { [lid] = { 0, 0 } }, { lid }, { lid }
        local qi = 1
        while qi <= #queue do
          local a = queue[qi]
          qi = qi + 1
          for _, l in ipairs(links[a] or {}) do
            local b = l[1]
            if not pos[b] then
              pos[b] = { pos[a][1] + l[2], pos[a][2] + l[3] }
              posOrder[#posOrder + 1] = b
              queue[#queue + 1] = b
            end
          end
        end
        for _, l in ipairs(posOrder) do seen[l] = true end
        local mx, my = math.huge, math.huge
        for _, l in ipairs(posOrder) do mx, my = min(mx, pos[l][1]), min(my, pos[l][2]) end
        local members, at = {}, {}
        for _, l in ipairs(posOrder) do
          members[#members + 1] = l
          at[l] = { pos[l][1] - mx, pos[l][2] - my }
        end
        groups[#groups + 1] = { name = lid:sub(8):lower(), members = members, at = at }
      end
    end
    -- a layout a script swaps in is solved with its map's neighbours, in its map's place
    local originals = {}
    for i, g in ipairs(groups) do originals[i] = g end
    local alts = {}
    for alt in pairs(alternates) do alts[#alts + 1] = alt end
    table.sort(alts)
    for _, alt in ipairs(alts) do
      local base = alternates[alt]
      for _, g in ipairs(originals) do
        if g.at[base] and outdoor[alt] then
          local members, at = {}, {}
          for _, l in ipairs(g.members) do
            local nl = l == base and alt or l
            members[#members + 1] = nl
            at[nl] = g.at[l]
          end
          local name = alt:sub(8):lower()
          local replaced = false
          for i, og in ipairs(groups) do
            if og.name == name then
              groups[i] = { name = name, members = members, at = at }
              replaced = true
            end
          end
          if not replaced then groups[#groups + 1] = { name = name, members = members, at = at } end
        end
      end
    end
    local byName = {}
    for _, g in ipairs(groups) do byName[g.name] = g end
    return groups, byName
  end
  S.DRAWN, S.DRAWN_BY = findDrawn()
  tick()
  local phase = opt.phase or function() end
  phase("groups")

  -- the shared caches of the generator
  S.PREP, S.DRAWN_OUT, S.SHIFT, S.ROCK, S.CELLS, S.BASE, S.PIER = {}, {}, {}, {}, {}, {}, {}
  S.ROCKY_WATER, S.ROLES_DRAWN, S.QUALITY = {}, {}, {}

  function S.drawnGroup(lid, checked)
    for _, g in ipairs(S.DRAWN) do
      if g.at[lid] then
        if checked == false or S.drawnOk(g.name) then return g.name end
        return nil
      end
    end
    return nil
  end
  function S.drawnOk(name)
    if DRAWN_EXCLUDED[name] then return false end
    return S.worldLevels().regions[name] ~= nil
  end

  -- the other parts: src/scene/relief_drawn.lua, relief_shape.lua, relief_cuts.lua, relief_world.lua
  for _, part in ipairs(opt.parts) do part(S) end

  -- ── layout_heights, ledge_layouts, export ────────────────────────────────────
  local function layoutHeights(lid)
    local RL = openRoles(lid)
    local group = S.drawnGroup(lid)
    local h
    if group then
      local src = S.solveDrawn(group)[lid]
      h = { n = src.n, w = src.w }
      for j = 0, src.n - 1 do h[j] = copyRow(src[j], src.w) end
      S.raisePits(h)
      ledgesOnGround(RL, h)
      S.pierEnds(group, lid, RL, h)
    elseif ENABLED[lid] then
      local _, _, hh = solve(RL)
      h = hh
      h.n, h.w = RL.h * PER_CELL + 1, RL.w * PER_CELL + 1
      ledgesOnGround(RL, h)
    else
      h = S.flatLattice(RL)
      h.n, h.w = RL.h * PER_CELL + 1, RL.w * PER_CELL + 1
    end
    local art = artMemo[lid] or layoutArt(lid)
    local ledges = ledgeBerms(RL, aliasOf(lid) and vbArt(lid) or art, h)
    return RL, h, ledges
  end
  S.layoutHeights = layoutHeights

  local function ledgeLayouts()
    local out = {}
    for _, L in ipairs(ordered) do
      local RL = openRoles(L.name, false)
      if RL.outdoor then
        local _, list = ledgeCells(RL, false)
        if #list > 0 then out[#out + 1] = L.name end
      end
    end
    return out
  end

  local function reliefCells(RL, h)
    local out = {}
    for y = 0, RL.h - 1 do
      for x = 0, RL.w - 1 do
        local g = cellGrid(h, x, y)
        local any = false
        for j = 0, PER_CELL do for i = 0, PER_CELL do if abs(g[j][i]) > 0.25 then any = true end end end
        if any then out[#out + 1] = { x, y, g } end
      end
    end
    return out
  end

  -- the default list: ENABLED, every drawn group's member, every map with a ledge
  local lids, have = {}, {}
  -- (a layout the cartridge lacks is left out: Emerald has every one these name)
  local function add(l) if not have[l] and layouts[l] then have[l] = true; lids[#lids + 1] = l end end
  for _, l in ipairs(Solve.ENABLED) do add(l) end
  for _, g in ipairs(S.DRAWN) do for _, l in ipairs(g.members) do add(l) end end
  for _, l in ipairs(ledgeLayouts()) do add(l) end
  tick()

  -- export()
  local world = S.worldLevels().base
  phase("world")
  local extra = {}
  for l, b in pairs(world) do
    if b ~= 0 and not have[l] and S.drawnGroup(l) == nil then extra[#extra + 1] = l end
  end
  table.sort(extra)
  for _, l in ipairs(extra) do lids[#lids + 1] = l end
  local index = {}
  for _, L in ipairs(ordered) do index[L.name] = L.id end
  local variants, variantOrder = {}, {}
  local cuts = {}
  local tables = {}
  local function pyRoundStore(v, unit)
    local s = Art.round(v / unit)
    if s < -128 then s = -128 elseif s > 127 then s = 127 end
    return s
  end
  for _, lid in ipairs(lids) do
    local RL, h, ledges = layoutHeights(lid)
    local drawn = S.drawnGroup(lid) ~= nil
    local cut = drawn and S.cutCells(lid, RL, h) or {}
    local cells = reliefCells(RL, h)
    local unit = drawn and HEIGHT_UNIT or 1
    if drawn and aliasOf(lid) then
      local fits = true
      for j = 0, h.n - 1 do for i = 0, h.w - 1 do
        local v = h[j][i]
        if v ~= nil and (v < -120 or v > 120) then fits = false end
      end end
      if fits then unit = 1 end
    end
    if drawn then
      local art = layoutArt(lid)
      local have_ = {}
      for _, c in ipairs(cells) do have_[K(c[1], c[2])] = true end
      local flatp = {}
      for _, c in ipairs(cut) do
        local x, y, m, mask, foot, ground = c[1], c[2], c[3], c[4], c[5], c[6]
        if ground ~= nil and S.plainBackground(art, m, mask, ground) then flatp[K(x, y)] = 1 end
        m = art.ownMetatile(x, y)
        ground = ground ~= nil and S.ownId(lid, ground) or nil
        local tsName = m < 512 and art.primary or art.secondary
        local vkey = tsName .. "|" .. m .. "|" .. table.concat(mask, ",", 0, 15)
        if not variants[vkey] then
          variants[vkey] = { #variantOrder, index[lid], m, mask }
          variantOrder[#variantOrder + 1] = vkey
        end
        local k = variants[vkey][1]
        cuts[#cuts + 1] = { index[lid], x, y, k, unit * Art.round(foot / unit), ground == nil and 0xFFFF or ground }
        if not have_[K(x, y)] then
          cells[#cells + 1] = { x, y, cellGrid(h, x, y) }
          have_[K(x, y)] = true
        end
      end
      local grids, fills, walls, wallOrder = S.cellShapes(lid, RL, h, cut)
      local goesOn = {}
      for _, f in ipairs(fills) do
        local x, y, foot, ground, flag = f[1], f[2], f[3], f[4], f[5]
        cuts[#cuts + 1] = { index[lid], x, y, 0xFFFF, unit * Art.round(foot / unit),
                            ground == nil and 0xFFFF or S.ownId(lid, ground) }
        if flag == GOES_ON then goesOn[K(x, y)] = true end
      end
      -- got: the cut records of this layout, by cell (the last one written wins)
      local got, gotOrder = {}, {}
      for k, c in ipairs(cuts) do
        if c[1] == index[lid] then
          local key = K(c[2], c[3])
          if got[key] == nil then gotOrder[#gotOrder + 1] = key end
          got[key] = k
        end
      end
      for _, key in ipairs(wallOrder) do
        if got[key] == nil then
          cuts[#cuts + 1] = { index[lid], KX(key), KY(key), 0xFFFF, 0, 0xFFFF }
          got[key] = #cuts
          gotOrder[#gotOrder + 1] = key
        end
      end
      for _, key in ipairs(gotOrder) do
        local k = got[key]
        local wall = walls[key] or { 0xFFFF, 0xFF }
        local w0 = wall[1]
        if w0 ~= 0xFFFF and w0 ~= NO_FACE then w0 = S.ownId(lid, w0) end
        local c = cuts[k]
        cuts[k] = { c[1], c[2], c[3], c[4], c[5], c[6], w0, wall[2],
                    (flatp[key] or 0) + (goesOn[key] and GOES_ON or 0) }
      end
      local list = {}
      for _, key in ipairs(gotOrder) do list[#list + 1] = key end
      for key in pairs(grids) do list[#list + 1] = key end
      for _, key in ipairs(list) do
        if not have_[key] then
          cells[#cells + 1] = { KX(key), KY(key), cellGrid(h, KX(key), KY(key)) }
          have_[key] = true
        end
      end
      for _, c in ipairs(cells) do
        local g = grids[K(c[1], c[2])]
        if g then c[3] = g end
      end
      table.sort(cells, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
      -- every blocked cell of rock, and every cell its map's depth lattice moves
      local shift = S.SHIFT[lid]
      for y = 0, RL.h - 1 do
        for x = 0, RL.w - 1 do
          if not have_[K(x, y)] then
            local take = RL.blocked(x, y) and RELIEF_ROLES[RL.role_at(x, y)]
            if not take and shift then
              local sg = cellGrid(shift, x, y)
              for j = 0, PER_CELL do for i = 0, PER_CELL do if abs(sg[j][i]) > 0.25 then take = true end end end
            end
            if take then
              cells[#cells + 1] = { x, y, cellGrid(h, x, y) }
              have_[K(x, y)] = true
            end
          end
        end
      end
      table.sort(cells, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    end
    local lift = drawn and (S.BASE[lid] or 0) or (world[lid] or 0)
    if #cells > 0 or lift ~= 0 then
      local t = { w = RL.w, h = RL.h, flags = (drawn and 0x8000 or 0) + (unit == 2 and 0x4000 or 0),
                  base = floor(lift), belt = 0, ease = 0, level = false, cells = {} }
      for _, c in ipairs(cells) do
        local g = c[3]
        local px = {}
        for j = 0, PER_CELL do
          for i = 0, PER_CELL do px[j * 5 + i] = pyRoundStore(g[j][i] / unit, 1) * unit end
        end
        t.cells[c[2] * RL.w + c[1]] = px
      end
      tables[index[lid]] = t
    end
    tick()
  end
  local model = { layouts = tables, variants = {}, nVariants = #variantOrder, cuts = {}, edges = {} }
  for _, vkey in ipairs(variantOrder) do
    local v = variants[vkey]
    local rows = {}
    for j = 0, 15 do rows[j] = v[4][j] end
    model.variants[v[1]] = { layout = v[2], metatile = v[3], rows = rows }
  end
  for _, c in ipairs(cuts) do
    local wall, sides, flags = c[7] or 0xFFFF, c[8] or 0xFF, c[9] or 0
    model.cuts[c[1] * 65536 + c[2] * 256 + c[3]] = { c[4], c[5], c[6], wall, sides, flags }
  end
  model.cutList = cuts
  S.model = model
  phase("export")
  return model, S
end

return Solve
