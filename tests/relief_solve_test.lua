-- luajit tests/relief_solve_test.lua (from the repository root): the relief solver's pieces
-- (src/scene/relief_art.lua, relief_input.lua, relief_solve.lua and its parts) on synthetic data.
-- The solver itself is checked byte for byte against Emerald 3DS's generator by
-- tests/drivers/relief_dump.lua.

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local Art = dofile("src/scene/relief_art.lua")
local Input = dofile("src/scene/relief_input.lua")
local Solve = dofile("src/scene/relief_solve.lua")
local Roles = dofile("src/scene/roles.lua")
local function rgb(r, g, b) return r * 65536 + g * 256 + b end

-- ---------------------------------------------------------------- Python, exactly
do
  -- (answers from CPython 3.13: gen_voxel_relief.commonest / set_order)
  local c = Art.commonest({ rgb(9, 9, 9), rgb(1, 2, 3), rgb(1, 2, 3), rgb(9, 9, 9), rgb(200, 100, 50), rgb(200, 100, 50) },
    Art.hashRGB)
  check(c == rgb(200, 100, 50), "commonest: a three-way tie falls as CPython's set orders the colours")
  local o = Art.setOrder({ rgb(9, 9, 9), rgb(1, 2, 3), rgb(200, 100, 50) }, Art.hashRGB)
  check(o[1] == rgb(200, 100, 50) and o[2] == rgb(1, 2, 3) and o[3] == rgb(9, 9, 9), "...the set's order of colours")
  check(Art.commonest({ 5, 3, 3, 5, 40, 40 }) == 40, "...and of ints")
  local io = Art.setOrder({ 40, 5, 3, 17, 8 }, Art.hashInt)
  check(io[1] == 3 and io[2] == 5 and io[3] == 40 and io[4] == 8 and io[5] == 17, "...the set's order of ints")
  check(Art.commonest({ -1, 2, -1, 2 }) == 2, "...hash(-1) is -2")
  check(Art.round(2.5) == 2 and Art.round(3.5) == 4 and Art.round(-0.5) == 0 and Art.round(2.4999) == 2,
    "round: half to even")
  local tenth = {}
  for i = 1, 10 do tenth[i] = 0.1 end
  check(Art.fsum(tenth) == 1.0, "sum() of floats is compensated (ten tenths are 1.0)")
  local v = Art.mixedSum({ 1e16, 1, -1e16, 0.5 }, { true, false, true, true })
  check(v == 0.5, "...an int past a float is added plainly")
end

-- ---------------------------------------------------------------- the drawing
local function tileset(name, tiles, metas, attrs, tint)
  local pals = {}
  for p = 0, 15 do
    local pal = {}
    for i = 0, 15 do pal[i] = rgb(p * 16, i * 16, ((tint or 0) + p + i) % 256) end
    pals[p] = pal
  end
  local function u16s(list)
    local parts = {}
    for _, v in ipairs(list) do parts[#parts + 1] = string.char(v % 256, math.floor(v / 256)) end
    return table.concat(parts)
  end
  return { key = name, name = name, tiles = tiles, palettes = pals, metatiles = u16s(metas), attributes = u16s(attrs) }
end
do
  -- tile 0 all colour index 0, tile 1 all index 3 but its first pixel 0
  local t1 = string.char(0x30) .. string.rep(string.char(0x33), 31)
  local tiles = string.rep("\0", 32) .. t1
  -- metatile 0: lower tile 1 (palette 2), upper tile 0; metatile 1: lower tile 0, upper tile 1
  -- x-flipped in the top-left quarter (palette 7: the secondary's)
  local metas = { 2 * 4096 + 1, 2 * 4096 + 1, 2 * 4096 + 1, 2 * 4096 + 1, 0, 0, 0, 0,
                  0, 0, 0, 0, 7 * 4096 + 0x400 + 1, 0, 0, 0 }
  local pt = tileset("general", tiles, metas, { 0, 0 })
  local st = tileset("petalburg", tiles, metas, { 0, 0 }, 100)
  local P = Art.pair(pt, st)
  local img = P.cellImage(0)
  check(img[0] == pt.palettes[2][0] and img[1] == pt.palettes[2][3], "a cell's lower layer: opaque, index 0 its palette's colour 0")
  check(next(P.layerPixels(0, 1)) == nil and P.layerPixels(0, 0)[0] == nil and P.layerPixels(0, 0)[1] == pt.palettes[2][3],
    "...a layer's drawn pixels leave index 0 out")
  local up = P.cellImage(1)
  check(up[6] == st.palettes[7][3] and up[7] == pt.palettes[0][0] and up[8] == pt.palettes[0][0],
    "...the upper over it where its index is not 0, flipped, its palette the secondary's past 5")
end

-- ---------------------------------------------------------------- the input
do
  local files = {}
  local function put(path, s) files[path] = s end   -- (io.read's paths are under the cache root)
  local function grid(w, h, f)
    local parts = {}
    for y = 0, h - 1 do for x = 0, w - 1 do local v = f(x, y); parts[#parts + 1] = string.char(v % 256, math.floor(v / 256)) end end
    return table.concat(parts)
  end
  put("map_tree/census.json", "C")
  put("native/layout_files.lua", "F")
  put("native/manifest.lua", "M")
  put("map_tree/maps/0_0/header.json", "H")
  put("map_tree/maps/0_0/events.json", "E")
  put("map_tree/maps/0_0/grid.bin", grid(2, 2, function(x, y) return 1 + (x == 1 and 1024 or 0) end))
  for _, f in ipairs({ "tiles.4bpp", "metatiles.bin", "attributes.bin", "palettes.bin" }) do
    put("map_tree/tilesets/ts_a/" .. f, "")
    put("map_tree/tilesets/ts_b/" .. f, "")
  end
  local decoded = {
    C = { groups = { { maps = { { id = "Route101", slot = "0_0" } } } } },
    H = { layoutId = 17, id = "Route101", mapType = 3, width = 2, height = 2, primaryTileset = "ts_a",
          secondaryTileset = "ts_b", connections = {} },
    E = { warps = { { x = 1, y = 0 }, { x = 0, y = 0 } }, bgEvents = { { type = "sign", x = 0, y = 1 } } },
  }
  local luas = { F = { [17] = "EM_ROUTE101" }, M = { layouts = { EM_ROUTE101 = { pair = "general__petalburg" } } } }
  local input = Input.build({ read = function(p) return files[p] end, json = function(s) return decoded[s] end,
                              lua = function(s) return luas[s] end, behaviours = {}, collBlocked = function() return true end },
    Art.palettes)
  local L = input.byName.LAYOUT_ROUTE101
  check(L and L.id == 17 and L.w == 2 and L.blocks[1] == 1025 and L.outdoor and L.primary.name == "general"
    and L.secondary.name == "petalburg", "input: a layout by its id, named, its raw cells, tilesets, outdoor")
  check(L and L.warps[1][1] == 0 and L.warps[2][1] == 1 and L.signs["0,1"], "...its warps sorted, its sign events")
end

-- ---------------------------------------------------------------- a solve
do
  -- LAYOUT_ROUTE104 (solved as its region extrusion): two rows of land over two rows of rock over
  -- two of land - the upper land a level over the lower
  local W, H = 4, 6
  local blocks = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local rock = y == 2 or y == 3
      blocks[y * W + x] = (rock and 2 or 1) + (rock and 1024 or 0)
    end
  end
  local tiles = string.rep("\0", 64)
  local metas = {}
  for m = 0, 3 do for q = 0, 7 do metas[#metas + 1] = 0 end end
  local ts = tileset("general", tiles, metas, { 0, 0, 0, 0 })
  local L = { id = 20, name = "LAYOUT_ROUTE104", w = W, h = H, blocks = blocks, primary = ts, secondary = ts,
              outdoor = true, warps = {}, signs = {}, warpSet = {} }
  local MB = {}
  for _, n in ipairs(Roles.WATER_NAMES) do MB[n] = 0x100 + #n end
  MB.MB_WATERFALL, MB.MB_BERRY_TREE_SOIL = 0x13, 0xA0
  local input = { layouts = { [20] = L }, byName = { LAYOUT_ROUTE104 = L }, maps = {}, behaviours = MB }
  local function part(n) return dofile("src/scene/" .. n .. ".lua") end
  local ticks = 0
  local model = Solve.run(input, { Art = Art, Roles = Roles, tick = function() ticks = ticks + 1 end,
    parts = { part("relief_drawn"), part("relief_shape"), part("relief_cuts"), part("relief_world") } })
  local t = model.layouts[20]
  check(t and t.w == 4 and t.h == 6 and t.base == 0 and t.flags == 0, "a solve: the map written, at its base, not drawn")
  local top, foot = t and t.cells[0], t and t.cells[5 * W]
  check(top and top[0] == 16 and top[24] == 16, "...the land over the rock band a level up")
  check(t and foot == nil, "...the land under it on the ground, not written")
  local face = t and t.cells[2 * W + 1]
  check(face and face[0] == 16 and face[20] < 16 and face[20] > 0, "...the rock between them falling from one to the other")
  check(ticks > 0, "...ticking as it goes")
end

print(("%d/%d checks passed (relief solve)"):format(passed, passed + failed))
