-- Objects drawn as one block of upper-layer subtiles, wherever it lands (Battle Scene: Overworld).
--
-- The grey rock in the sea is four 8x8 tiles of the General tileset (141, 142 over 157, 158,
-- palette 1) drawn on the upper layer over the water. The cartridge has a dozen metatiles that
-- carry it - centred on four cells, half in one cell and half in the next, beside a sandbank, by
-- a shore - but the rock is always the same four tiles in the same square. So it is found by its
-- tiles, not by its metatiles: every place in every layout where the square is drawn, at whatever
-- 8-pixel offset, is one rock. The scene stands a model there (one per offset and per variant of
-- what is drawn of it), on the cells' own ground.
--
-- Ported from Emerald 3DS's scripts/voxel_props.py and the `props` specs of
-- voxel_building_specs.py / gen_voxel_buildings.prop_specs (by Zallax and contributors, CC
-- BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE). The relief solver has its
-- own copy of the finder (src/scene/relief_solve.lua), which leaves these cells to the models.

local Props = {}
local floor = math.floor

-- name -> the tilesets the tiles are in (short names), the subtile grid row by row (tile ids,
-- false where nothing of the object is drawn) and the palette. A grid entry may be optional, and
-- drawn in a palette of its own: { tile, true, palette } - drawn in some copies, left out in
-- others (the sea stack's corner over a shallow).
Props.OBJECTS = {
  sea_rock = { tileset = "general", palette = 1, grid = { { 141, 142 }, { 157, 158 } } },
  -- on the land: its cell is ground at the level round it
  sand_boulder = { land = true, tileset = "general", palette = 3, grid = { { 88, 89 }, { 104, 105 } } },
  sea_stack = { tileset = "general", palette = 3,
    grid = { { false, 65, 68, { 69, true, 0 } }, { 80, 81, 84, 85 }, { 128, 129, 132, 133 }, { 144, 145, 148, 149 } } },
  -- the same boulder and stack in Fallarbor's beige (Routes 114 and 115): the General's tiles
  -- drawn in the secondary tileset's palette 11
  sand_boulder_fallarbor = { land = true, tileset = "general", secondary = "fallarbor", palette = 11,
    grid = { { 88, 89 }, { 104, 105 } } },
  sea_stack_fallarbor = { tileset = "general", secondary = "fallarbor", palette = 11,
    grid = { { false, 65, 68, { 69, true, 11 } }, { 80, 81, 84, 85 }, { 128, 129, 132, 133 }, { 144, 145, 148, 149 } } },
  -- the Battle Frontier's flags along its walls: the cloth three tiles across and two down (the
  -- tiles the game animates, 218-223 of the secondary tileset), the pole two tiles under its west
  -- end, each side's tileset its own copy of them
  frontier_flag_east = { land = true, tileset = "general", secondary = "battlefrontieroutsideeast", palette = 11,
    grid = { { 730, 731, 732 }, { 733, 734, 735 }, { 746, false, false }, { 762, false, false } } },
  frontier_flag_west = { land = true, tileset = "general", secondary = "battlefrontieroutsidewest", palette = 11,
    grid = { { 730, 731, 732 }, { 733, 734, 735 }, { 746, false, false }, { 762, false, false } } },
  -- Slateport market's goods, each a cell of the secondary tileset's upper layer over whatever
  -- paving it stands on
  basket_green = { land = true, tileset = "general", secondary = "slateport", palette = 7, grid = { { 518, 519 }, { 534, 535 } } },
  basket_orange = { land = true, tileset = "general", secondary = "slateport", palette = 7, grid = { { 516, 517 }, { 532, 533 } } },
  basket_red = { land = true, tileset = "general", secondary = "slateport", palette = 7, grid = { { 514, 515 }, { 530, 531 } } },
  urn = { land = true, tileset = "general", secondary = "slateport", palette = 7, grid = { { 614, 615 }, { 630, 631 } } },
  fruit = { land = true, tileset = "general", secondary = "slateport", palette = 7, grid = { { 736, 737 }, { 738, 739 } } },
}

-- The props the scene models, in the specs' order. `shape`: a Mound (the default;
-- src/scene/models/solids.lua) `rise` times as tall as deep, its lattice `step`, `ring` the
-- colours round its foot on the water (laid flat, never lifted); "lathe" (ProjLathe, its centre
-- moved by the variant's half-cell offset), "dome" (ProjDome, likewise) or "flag" (a card standing
-- at the pole's foot over the whole grid, its cloth `live_tiles` following the game's animation).
-- `clip_art`: every triangle cut to the drawing's box.
Props.SPECS = {
  -- the grey rock in the sea: a low dome, as deep as it is drawn tall below its crest; the water
  -- round it stays the map's own; its foam on the water
  { name = "sea_rock", props = "sea_rock", ground = { 0x170 }, rise = 1.0, step = 2, ring = { { 222, 230, 238 } } },
  -- a boulder on the sand or the grass, a cell across (Route 106's beach, Route 111's desert, the
  -- Safari Zone)
  { name = "sand_boulder", props = "sand_boulder", ground = { 0x124 }, rise = 1.0, step = 2 },
  -- the brown stack in the sea: a peak, taller than it is deep; its grey shadow on the water
  { name = "sea_stack", props = "sea_stack", ground = { 0x170 }, rise = 1.6, step = 4, ring = { { 131, 131, 139 } } },
  -- the same stack in Fallarbor's beige: in the sea, and on Route 115's terraces as their mounds
  { name = "sea_stack_fallarbor", props = "sea_stack_fallarbor", ground = { 0x170 }, rise = 1.6, step = 4,
    ring = { { 131, 131, 139 } } },
  -- the boulder in Fallarbor's beige, on the mountain's top
  { name = "sand_boulder_fallarbor", props = "sand_boulder_fallarbor", ground = { 0x241 }, rise = 1.0, step = 2 },
  -- a pot, turned smooth: its foot, its belly, a neck under the lip round its dark mouth
  { name = "urn", props = "urn", clip_art = true, ground = { 0x211 }, shape = "lathe",
    lathe = { cx = 8, cz = 13, squash = 0.7, profile = { { 0, 6 }, { 3.5, 8.5 }, { 7, 7.5 }, { 9, 5.1 }, { 10, 5.5 } } } },
  -- the baskets: an oval drawn round, its rim and goods on top, 5 rows of wicker in front; a
  -- smooth drum under its drawing, cut to it
  { name = "basket_green", props = "basket_green", ground = { 0x211 }, shape = "lathe", clip_art = true,
    lathe = { cx = 8, cz = 11, squash = 0.7, seg = 16, profile = { { 0, 8.5 }, { 5, 8.5 } } } },
  { name = "basket_orange", props = "basket_orange", ground = { 0x211 }, shape = "lathe", clip_art = true,
    lathe = { cx = 8, cz = 11, squash = 0.7, seg = 16, profile = { { 0, 8.5 }, { 5, 8.5 } } } },
  { name = "basket_red", props = "basket_red", ground = { 0x211 }, shape = "lathe", clip_art = true,
    lathe = { cx = 8, cz = 11, squash = 0.7, seg = 16, profile = { { 0, 8.5 }, { 5, 8.5 } } } },
  -- a pile of fruit: a smooth dome under its drawing
  { name = "fruit", props = "fruit", clip_art = true, ground = { 0x211 }, shape = "dome",
    dome = { cx = 8.5, cz = 9, rx = 8.5, rz = 7.5, h = 7 } },
  -- the Battle Frontier's flags, on every wall they stand on: a pole and its cloth, flat - a card
  -- standing at the pole's foot, facing the view; the wall or the cliff under them the map's own
  { name = "frontier_flag_east", props = "frontier_flag_east", ground = { 0x170 }, shape = "flag", live_tiles = { 730, 736 } },
  { name = "frontier_flag_west", props = "frontier_flag_west", ground = { 0x170 }, shape = "flag", live_tiles = { 730, 736 } },
}

local function short(name) return (tostring(name or ""):gsub("^gTileset_", ""):gsub("_", "")):lower() end
Props.short = short

--- The objects in one layout: { { name, sx, sy, present } }, sorted (voxel_props.find): the
--- object's top-left subtile and the grid entries drawn there (present: { ["i,j"] = true } and
--- its key, a string). An object a seam cuts is found from the map that holds its top-left
--- corner; the rest of it is looked for in the map across the seam.
--- L = { w, h, primary, secondary (short names) }; subtiles(L) -> { at, order } (World.subtiles);
--- neighbours(L) -> { { L2, dx, dy } } (World.neighbours).
function Props.find(L, subtiles, neighbours, names)
  local found = {}
  local subs
  local w, h = L.w, L.h
  local list = {}
  for name in pairs(Props.OBJECTS) do list[#list + 1] = name end
  table.sort(list)
  for _, name in ipairs(list) do
    local obj = Props.OBJECTS[name]
    if (not names or names[name]) and L.primary == obj.tileset and (obj.secondary or L.secondary) == L.secondary then
      subs = subs or subtiles(L)
      if not subs then return found end
      local function subAt(sx, sy)
        if sx >= 0 and sx < w * 2 and sy >= 0 and sy < h * 2 then return subs.at[sy * 4096 + sx] end
        local x, y = floor(sx / 2), floor(sy / 2)
        for _, nb in ipairs(neighbours(L)) do
          local B, dx, dy = nb[1], nb[2], nb[3]
          if x - dx >= 0 and x - dx < B.w and y - dy >= 0 and y - dy < B.h then
            if B.primary ~= L.primary then return nil end
            local bs = subtiles(B)
            return bs and bs.at[((y - dy) * 2 + sy % 2) * 4096 + (x - dx) * 2 + sx % 2]
          end
        end
        return nil
      end
      local grid = obj.grid
      local ai, aj, at
      for j, row in ipairs(grid) do
        for i, t in ipairs(row) do
          if not ai and t and type(t) ~= "table" then ai, aj, at = i - 1, j - 1, t end
        end
      end
      for _, k in ipairs(subs.order) do
        if subs.at[k] == at + obj.palette * 1024 then
          local x0, y0 = k % 4096 - ai, floor(k / 4096) - aj
          local present, keys, ok = {}, {}, true
          for j, row in ipairs(grid) do
            for i, t in ipairs(row) do
              if t then
                local want, optional, pal
                if type(t) == "table" then want, optional, pal = t[1], t[2], t[3]
                else want, optional, pal = t, false, obj.palette end
                if subAt(x0 + i - 1, y0 + j - 1) == want + pal * 1024 then
                  present[(i - 1) .. "," .. (j - 1)] = true
                  keys[#keys + 1] = (i - 1) .. "," .. (j - 1)
                elseif not optional then
                  ok = false
                  break
                end
              end
            end
            if not ok then break end
          end
          if ok then
            table.sort(keys)
            found[#found + 1] = { name = name, sx = x0, sy = y0, present = present, key = table.concat(keys, ";") }
          end
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    if a.sx ~= b.sx then return a.sx < b.sx end
    if a.sy ~= b.sy then return a.sy < b.sy end
    return a.key < b.key
  end)
  return found
end

--- The cells an object found at subtile (sx, sy) is drawn over: { { x, y } }, and its box
--- (x0, y0, w, h).
function Props.cellsOf(name, sx, sy)
  local grid = Props.OBJECTS[name].grid
  local seen, out = {}, {}
  local x0, y0, x1, y1
  for j, row in ipairs(grid) do
    for i, t in ipairs(row) do
      if t then
        local x, y = floor((sx + i - 1) / 2), floor((sy + j - 1) / 2)
        if not seen[x .. "," .. y] then
          seen[x .. "," .. y] = true
          out[#out + 1] = { x, y }
          x0, y0 = x0 and math.min(x0, x) or x, y0 and math.min(y0, y) or y
          x1, y1 = x1 and math.max(x1, x) or x, y1 and math.max(y1, y) or y
        end
      end
    end
  end
  return out, x0, y0, x1 - x0 + 1, y1 - y0 + 1
end

return Props
