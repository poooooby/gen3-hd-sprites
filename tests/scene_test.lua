-- Headless checks of the battle scene's plain-Lua parts (src/scene/). Run from the mod root:
--   luajit tests/scene_test.lua
local Camera = dofile("src/scene/camera.lua")
local Cells = dofile("src/scene/cells.lua")
local Stage = dofile("src/scene/stage.lua")
local Render = dofile("src/scene/render.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function near(a, b, e) return type(a) == "number" and math.abs(a - b) < (e or 1e-6) end

-- ------------------------------------------------------------------ camera
do
  local p = Camera.pose(10.5, 20.5)
  local u, v = Camera.project(p, 10.5, 0, 20.5)
  check(near(u, 120) and near(v, 80), "the target lands on the canvas's centre")
  local x, z = Camera.ground(p, 30, 140)
  local u2, v2 = Camera.project(p, x, 0, z)
  check(near(u2, 30, 1e-6) and near(v2, 140, 1e-6), "a canvas point cast onto the ground projects back onto itself")
  check(z > 20.5, "...a point low on the canvas is south of the target (nearer the camera)")
  local _, ztop = Camera.ground(p, 120, 0)
  check(ztop < 20.5 - 5, "the canvas's top shows the ground well north of the target")
  check(Camera.ground(Camera.pose(0, 0, math.rad(10)), 120, 0) == nil, "a ray above the horizon meets no ground")
  -- the stage pose's scale: a tile at the target is about 36 canvas pixels across
  local ua = Camera.project(p, 10, 0, 20.5)
  local ub = Camera.project(p, 11, 0, 20.5)
  check(near(ub - ua, Camera.F / 7, 1e-6), "one tile across at the target is F / 7 pixels")

  -- the shader's projection: screen pixel * depth is linear in the view coordinates
  local u0, v0, kx, ky = -40, -20, 6, 6
  local proj = Camera.screenProjection(u0, v0, kx, ky)
  local px, py, pz = 12.25, 0.75, 18.5
  local xc, yc, zc = Camera.view(p, px, py, pz)
  local cu, cv = Camera.project(p, px, py, pz)
  local sx = (proj[1] * xc + proj[2] * zc) / zc
  local sy = (-proj[3] * yc + proj[4] * zc) / zc
  check(near(sx, (cu - u0) * kx, 1e-6) and near(sy, (cv - v0) * ky, 1e-6),
    "the shader's projection puts a point where the canvas mapping does (" .. sx .. ", " .. sy .. ")")
  -- the view rows agree with Camera.view
  local R = Camera.viewRows(p)
  local function row(r) return r[1] * px + r[2] * py + r[3] * pz + r[4] end
  check(near(row(R[1]), xc) and near(row(R[2]), yc) and near(row(R[3]), zc), "the view matrix rows match Camera.view")

  -- the glide: from the field's pose to the stage's
  local from = Camera.pose(5.5, 5.5, Camera.FIELD_PITCH, Camera.FIELD_DIST)
  local to = Camera.pose(4, 2)
  local g0, g1 = Camera.glide(from, to, 0), Camera.glide(from, to, 1)
  check(near(g0.tx, 5.5) and near(g0.pitch, Camera.FIELD_PITCH) and near(g0.dist, Camera.FIELD_DIST),
    "the glide starts at the field's pose")
  check(near(g1.tx, 4) and near(g1.tz, 2) and near(g1.pitch, to.pitch) and near(g1.dist, to.dist),
    "...and ends at the stage's")
  local mid = Camera.glide(from, to, 0.39)
  check(mid.pitch > to.pitch and mid.pitch <= Camera.PITCH_MAX + 1e-9, "...its pitch arcs on the way")
  -- the field's pose shows 10 rows of tiles on the canvas
  local _, zt = Camera.ground(from, 120, 0)
  local _, zb = Camera.ground(from, 120, 160)
  check(near(zb - zt, 10, 1e-6), "straight down, the canvas shows the field's 10 rows (" .. (zb - zt) .. ")")
end

-- ------------------------------------------------------------------- cells
-- a fake map from rows of characters: . floor, g grass, s sand, w water, T blocked, outside: none
local function fakeEnv(map, indoor)
  local h = #map
  local env = { indoor = indoor }
  function env.mid(cx, cy) return (cy * 100 + cx) % 1024, "pair" end
  function env.cell(cx, cy)
    local line = map[cy + 1]
    if cx < 0 or cy < 0 or cy >= h or cx >= #line then return nil end
    local ch = line:sub(cx + 1, cx + 1)
    if ch == "T" then return 1, 0 end
    if ch == "w" then return 2, 0 end
    if ch == "g" then return 0, 0x02 end
    if ch == "s" then return 0, 0x21 end
    return 0, 0
  end
  env.isWall = function(c) return c == 1 end
  env.isWater = function(c) return c == 2 end
  env.isSurfable = function() return false end
  return env
end

do
  local map = {
    "..........",
    ".TT.......",
    ".TT...T...",
    "......T...",
    "gggg..T...",
    "gggg......",
    "wwww......",
  }
  local grid = Cells.build(fakeEnv(map), 0, 0, 10, 7)
  check(grid.at(0, 4).kind == "grass" and grid.at(0, 6).kind == "water" and grid.at(1, 1).kind == "blocked"
    and grid.at(5, 5).kind == "floor", "cells take their kinds from collision and behaviour")
  check(grid.at(6, 4).up == 0 and grid.at(6, 3).up == 1 and grid.at(6, 2).up == 2 and grid.at(6, 2).base == 4,
    "a column's blocked run stands from its southern cell up")
  check(grid.at(1, 2).up == 0 and grid.at(1, 1).up == 1 and grid.at(1, 1).base == 2, "...each column on its own")
  check(grid.at(5, 5).up == nil, "open ground stands nothing up")
  -- with env.stands: only a run drawn as leaves stands; a rock, a cliff's edge lies flat
  local env2 = fakeEnv(map)
  env2.mid = function(cx, cy) return cx, "p" end
  env2.stands = function(mid) return mid ~= 6 end
  local g2 = Cells.build(env2, 0, 0, 10, 7)
  check(g2.at(6, 4).up == nil and g2.at(6, 4).kind == "blocked" and g2.at(1, 2).up == 0,
    "a blocked run not drawn as leaves lies flat; a tree's stands")
  check(grid.at(20, 20) == nil, "outside the window: nil")
  local out = Cells.build(fakeEnv(map), -2, 0, 3, 1)
  check(out.at(-1, 0).kind == "blocked", "outside every map, outdoors: blocked (the border stands up)")
  local inside = Cells.build(fakeEnv(map, true), -2, 0, 3, 1)
  check(inside.at(-1, 0).kind == "void", "...indoors: void")
  -- a run longer than RUN_MAX starts again
  local tall = {}
  for i = 1, Cells.RUN_MAX + 2 do tall[i] = "T" end
  local tg = Cells.build(fakeEnv(tall), 0, 0, 1, #tall)
  check(tg.at(0, #tall - 1).up == 0 and tg.at(0, #tall - Cells.RUN_MAX).up == Cells.RUN_MAX - 1
    and tg.at(0, #tall - Cells.RUN_MAX - 1).up == 0, "a run is at most RUN_MAX tall, then another starts")
end

-- -------------------------------------------------------------------- stage
local function field(w, h, fill)
  local m = {}
  for y = 1, h do m[y] = string.rep(fill or "g", w) end
  return m
end
local FEET = { enemy = { 176, 70 }, player = { 72, 114 } }
local SPRITES = { enemy = { 144, 8, 208, 72 }, player = { 40, 48, 104, 112 } }

do
  -- open grass everywhere: the player's Pokemon stands on the player's own cell
  local map = field(60, 60)
  local grid = Cells.build(fakeEnv(map), 0, 0, 60, 60)
  local best = Stage.search(Camera, grid, { player = { cx = 30, cy = 40 }, want = { player = "grass", enemy = "grass" },
    feet = FEET, sprites = SPRITES })
  check(best and math.floor(best.feet.player[1]) == 30 and math.floor(best.feet.player[2]) == 40,
    "open ground: the player's Pokemon stands on the player's cell")
  check(best and best.feet.enemy[2] < best.feet.player[2] and best.feet.enemy[1] > best.feet.player[1],
    "...the foe north-east of it")

  -- a tree line just south of the player: the stage moves so nothing stands in front
  local map2 = field(60, 60)
  for y = 41, 43 do map2[y + 1] = string.rep("T", 60) end
  local grid2 = Cells.build(fakeEnv(map2), 0, 0, 60, 60)
  local c = grid2.at(30, 41)
  check(c.up ~= nil, "(the tree line stands up)")
  local best2 = Stage.search(Camera, grid2, { player = { cx = 30, cy = 40 }, want = { player = "grass", enemy = "grass" },
    feet = FEET, sprites = SPRITES })
  local pf = best2 and grid2.at(math.floor(best2.feet.player[1]), math.floor(best2.feet.player[2]))
  check(pf and pf.kind == "grass", "with trees about: the player's Pokemon still on grass")
  check(best2 and best2.score > Stage.FLOOR, "...a stage that fits")

  -- indoors: a small room in the void; the stage keeps the void off the feet
  local room = {}
  for y = 1, 40 do room[y] = string.rep(" ", 40) end
  for y = 18, 30 do room[y] = string.rep(" ", 14) .. string.rep(".", 12) .. string.rep(" ", 14) end
  local env = fakeEnv(room, true)
  local cellOf = env.cell
  env.cell = function(cx, cy)
    local line = room[cy + 1]
    if not line or cx < 0 or cx >= #line or line:sub(cx + 1, cx + 1) == " " then return nil end
    return cellOf(cx, cy)
  end
  local grid3 = Cells.build(env, 0, 0, 40, 40)
  local best3 = Stage.search(Camera, grid3, { player = { cx = 20, cy = 27 }, feet = FEET, sprites = SPRITES, void = true })
  local p3 = best3 and grid3.at(math.floor(best3.feet.player[1]), math.floor(best3.feet.player[2]))
  local e3 = best3 and grid3.at(math.floor(best3.feet.enemy[1]), math.floor(best3.feet.enemy[2]))
  check(p3 and p3.kind == "floor" and e3 and e3.kind == "floor", "indoors: both sides stand inside the room")
  check(best3 and best3.score > Stage.FLOOR, "...a stage that fits")

  -- all void: nothing fits
  local none = Cells.build(fakeEnv({ "" }, true), 0, 0, 30, 30)
  local best4 = Stage.search(Camera, none, { player = { cx = 15, cy = 15 }, feet = FEET, sprites = SPRITES, void = true })
  check(best4 and best4.score < Stage.FLOOR, "all void: below the floor (the wallpaper is kept)")
end

-- ------------------------------------------------------------------- render
do
  local map = { "...", ".T.", "..." }
  local grid = Cells.build(fakeEnv(map), 0, 0, 3, 3)
  local function img(name) return { name = name, getDimensions = function() return 256, 256 end } end
  local under, over = img("under"), img("over")
  local function q(x, y) return { getViewport = function() return x, y, 16, 16 end } end
  local tiles = function()
    return { image = under, overImage = over, slot = function(mid) return mid end,
             quad = function(s) return q(0, 0) end, overQuad = function(s) return q(16, 0) end }
  end
  local lists = Render.vertices(grid, tiles, 1, 1)
  local lo, up = lists.lower[under], lists.upper[over]
  -- 9 ground quads + 1 card, 6 vertices each, per layer
  check(lo and #lo == 60 and up and #up == 60, "each cell lies on the ground, the blocked one stands too (both layers)")
  -- the card: at the run's southern edge (z = base + 1 - origin), one tile high, darker
  -- (cell (1, 1) is the fifth: its ground quad is vertices 25-30, its card 31-36)
  local card = lo[31]
  check(card and near(card[1], 0) and near(card[2], 1) and near(card[3], 1) and near(card[6], Render.CARD_SHADE),
    "the card stands on its cell's southern edge, a tile high, shaded")
  check(near(lo[1][1], -1) and near(lo[1][3], -1), "positions are relative to the origin")
  check(lo[1][4] > 0 and lo[1][4] < 1 / 256, "uvs are kept off the tile's edge")
end

-- -------------------------------------------------------------------- trees
do
  local Trees = dofile("src/scene/trees.lua")
  local sec, general = Trees.tilesets("general__petalburg")
  check(sec == "petalburg" and general == true, "a pair's secondary tileset and whether its primary is General")
  check(select(1, Trees.tilesets("battle_frontier_outside_west")) == nil, "...a name with no pair: none")
  check(Trees.part(sec, 0x1D4) == 0 and Trees.part(sec, 0x1D5) == 1 and Trees.part(sec, 0x1E4) == 2
    and Trees.part(sec, 0x1E7) == 3, "the General's large tree: its four parts")
  check(Trees.part(sec, 0x0C6) == Trees.SMALL and Trees.part(sec, 0x015) == Trees.GRASS, "...a small tree, long grass")
  check(Trees.part(sec, 0x001) == nil and Trees.part(sec, 0x2F8) == nil, "...grass is none, nor another tileset's id")
  check(Trees.part("mossdeep", 0x2F8) == 2 and Trees.laysGround("mossdeep", 0x2F8) == false,
    "Mossdeep's tree in the shallows: its trunk row, over the water the ground lays")
  check(Trees.groundMetatile(sec, 0x00E) == 0x001 and Trees.groundMetatile(sec, 0x1C6) == 0x00D
    and Trees.groundMetatile(sec, 0x087) == 0x087, "a crown's top over grass lays grass; anything else itself")
  check(Trees.groundMetatile("dewford", 0x239) == 0x124, "...a secondary tileset's own")

  local quads = {}
  local function put(a, b, c, d, u0, v0, u1, v1, kind) quads[#quads + 1] = { a, b, c, d, u0, v0, u1, v1, kind } end
  -- a whole tree: its trunk row's left cell (part 2) at (10, 5), the crown row above it a tree part
  Trees.emit(put, sec, 0x1E4, 10, 5, 2, function(x, y) return y == 4 and 0 or nil end)
  check(#quads == 2 and quads[1][9] == "ground" and quads[2][9] == "card", "a tree cell lays its ground and one crown row")
  check(near(quads[1][1][1], 10) and near(quads[1][1][3], 5) and quads[1][5] == 32 and quads[1][6] == 16,
    "...its ground from the trunk's art (32, 16: the trunk row's left)")
  local top = quads[2][1]
  check(top[2] > 0 and top[3] < 6.35, "...its crown card leans back from the trunk row's foot")
  -- the crown row covered by something else (a roof): that row is added
  quads = {}
  Trees.emit(put, sec, 0x1E4, 10, 5, 2, function() return nil end)
  check(#quads == 3, "a crown row drawn over by something else is added anyway")
  quads = {}
  Trees.emit(put, sec, 0x1E4, 10, 5, 2, function() return false end)
  check(#quads == 2, "...but not across the map's edge")
  -- a small tree: a trunk plate and a 16:32 crown card
  quads = {}
  Trees.emit(put, sec, 0x0C6, 3, 3, Trees.SMALL, function() return nil end)
  check(#quads == 2 and quads[1][5] == 48 and quads[1][6] == 32 and quads[2][5] == 32 and quads[2][8] == 64,
    "a small tree: its trunk plate (48, 32) and crown (32, 32)-(48, 64)")
end

-- ---------------------------------------------------------------- signs
do
  local Signs = dofile("src/scene/signs.lua")
  -- a 4x4 square in the middle, and a ring with a hole: the hole is the sign's (closed off)
  local solid = {}
  for y = 6, 9 do for x = 6, 9 do solid[y * 16 + x] = true end end
  local rows = Signs.cutout(solid)
  check(rows[6] == 2 ^ 6 + 2 ^ 7 + 2 ^ 8 + 2 ^ 9 and rows[5] == 0, "a sign's mask: its pixels, row by row")
  local ring = {}
  for y = 2, 5 do for x = 2, 5 do if x == 2 or x == 5 or y == 2 or y == 5 then ring[y * 16 + x] = true end end end
  check(Signs.cutout(ring)[3] == 2 ^ 2 + 2 ^ 3 + 2 ^ 4 + 2 ^ 5, "...a hole closed off from the border is the sign's too")
  -- a map: a post open on three sides (2, 2), one of the same drawing against a wall (5, 2), and a
  -- wall (4, 2) beside it; ground plain sand, posts drawn grey on their lower layer's middle
  local map = { ".....", ".....", "..P.WP", "......" }
  local grid = { x0 = 0, y0 = 0, w = 6, h = 4, rows = {} }
  for j = 0, 3 do
    grid.rows[j] = {}
    for i = 0, 5 do
      local ch = map[j + 1]:sub(i + 1, i + 1)
      grid.rows[j][i] = { cx = i, cy = j, pair = "p", kind = (ch == "P" or ch == "W") and "blocked" or "floor",
        coll = (ch == "P" or ch == "W") and 1 or 0, mid = ch == "P" and 7 or ch == "W" and 8 or 1 }
    end
  end
  function grid.at(x, y) return grid.rows[y] and grid.rows[y][x] end
  local function layers(mid)
    local lo = {}
    for k = 0, 255 do
      local x, y = k % 16, math.floor(k / 16)
      local post = mid == 7 and x >= 6 and x < 10 and y >= 4
      lo[k] = post and { 0.5, 0.5, 0.5 } or (mid == 8 and { 0.6, 0.3, 0.2 }) or { 0.8, 0.7, 0.4 }
    end
    return lo, nil
  end
  -- (2, 2) is a sign event, and its metatile one the game's free-standing sign events are drawn with
  local found = Signs.find(grid, { isWall = function(c) return c == 1 end, layers = layers,
    signAt = function(x, y) return x == 2 and y == 2 end, postAt = function(mid) return mid == 7 end })
  local at = {}
  for _, f in ipairs(found) do at[f.cell.cx .. "," .. f.cell.cy] = f end
  check(#found == 2 and at["2,2"] and at["5,2"] and not at["4,2"],
    "signs: a post open on three sides, and one drawn as a sign event against a wall; not the wall")
  -- with no sign events, a post open on three sides still is one; not one drawn alike against a wall
  found = Signs.find(grid, { isWall = function(c) return c == 1 end, layers = layers })
  check(#found == 1 and found[1].cell.cx == 2, "...with no sign event, only the post open on three sides")
  -- the mountain is never a post: the General tileset's rock, a tile drawn in its colours, a cover
  local function one(mid, pair, opt)
    grid.rows[2][2].mid, grid.rows[2][2].pair = mid, pair
    opt = opt or {}
    opt.isWall = function(c) return c == 1 end
    opt.layers = function(m)
      local lo, up = {}, nil
      for k = 0, 255 do
        local x = k % 16
        if m == 0x300 then lo[k] = { 0xDE / 255, 0xB4 / 255, 0xA4 / 255 }   -- the mountain's top colour
        elseif m == 0x301 then
          lo[k] = { 0.8, 0.7, 0.4 }
          up = up or {}
          if x < 12 then up[k] = { 0.4, 0.4, 0.4 } end                     -- drawn over the player
        elseif m >= 0x64 and m <= 0xBF then lo[k] = (x >= 6 and x < 10) and { 0.5, 0.5, 0.5 } or { 0.8, 0.7, 0.4 }
        else return layers(m) end
      end
      return lo, up
    end
    local f = Signs.find(grid, opt)
    for _, s in ipairs(f) do if s.cell.cx == 2 and s.cell.cy == 2 then return true end end
    return false
  end
  check(not one(0x070, "general__mossdeep", { mountainRock = true }) and one(0x070, "general__mossdeep"),
    "...not the General tileset's mountain rock (a ledge's end), in Hoenn")
  check(not one(0x300, "general__mossdeep"), "...nor a tile drawn in the mountain's colours")
  check(not one(0x301, "general__mossdeep"), "...nor one drawn over the player down the cell (a boulder)")
  check(one(0x070, "general__mossdeep", { mountainRock = true, signAt = function(x, y) return x == 2 and y == 2 end }),
    "...but a sign event always is")
  grid.rows[2][2].mid, grid.rows[2][2].pair = 7, "p"
  check(at["2,2"].rows[4] == 2 ^ 6 + 2 ^ 7 + 2 ^ 8 + 2 ^ 9 and at["2,2"].rows[3] == 0 and at["2,2"].ground == 1,
    "...its silhouette is what the ground round it does not draw; its cell laid with that ground")
  local quads, top = 0, 0
  top = Signs.emit(at["2,2"].rows, 16, function() quads = quads + 1 end)
  check(quads > 0 and quads % 6 == 0 and near(top, 12 / 16), "...a solid of its pixels, as tall as it is drawn")
end

-- ---------------------------------------------------------------- buildings
do
  local K = dofile("src/scene/models/kernel.lua")
  dofile("src/scene/models/solids.lua")(K)
  local specs = dofile("src/scene/models/specs.lua")(K)
  local solidSpecs = dofile("src/scene/models/solid_specs.lua")(K, specs)
  local B = dofile("src/scene/buildings.lua")
  -- the kernel: clipping keeps the coordinates it carries exact
  local half = K.clip({ { 0, 0, 10 }, { 4, 0, 14 }, { 4, 4, 18 }, { 0, 4, 14 } }, 1, 2, true)
  local edge = 0
  for _, p in ipairs(half) do if near(p[1], 2) then edge = edge + 1; check(near(p[3], 12 + p[2]), "a clipped point's carried value is interpolated") end end
  check(#half == 4 and edge == 2, "a square clipped down its middle keeps four corners, two on the cut")
  check(#K.triangulate({ { 0, 0 }, { 4, 0 }, { 4, 4 }, { 2, 1 }, { 0, 4 } }) == 3, "a concave pentagon is three ears")
  -- a tile repeated over a face: one piece per repeat, each a translation of the art
  local pieces = K.tilePieces({ { 0, 0 }, { 20, 0 }, { 20, 8 }, { 0, 8 } }, K.Tile(8, 40, 16, 48))
  check(#pieces == 3, "a 20-wide face over an 8-wide tile: three pieces")
  local ok = true
  for _, pc in ipairs(pieces) do
    for _, p in ipairs(pc) do if p[4] < 40 - 1e-9 or p[4] > 48 + 1e-9 or p[3] < 8 - 1e-9 or p[3] > 16 + 1e-9 then ok = false end end
  end
  check(ok, "...every piece reads inside the tile")
  -- a wall projected: u = X, v = Z - Y
  local mesh = K.build({ K.Walls("w", { { 0, 64 }, { 32, 64 } }, 0, 20) })
  local proj = true
  for _, t in ipairs(mesh.tris) do
    for k = 1, 3 do if not (near(t[k][4], t[k][1]) and near(t[k][5], t[k][3] - t[k][2])) then proj = false end end
  end
  check(#mesh.tris == 2 and proj, "a wall the drawing shows is the drawing projected (u = X, v = Z - Y)")
  -- every spec builds (the same triangles as Emerald 3DS's generator: see DEVELOPMENT.md)
  local built, bad = 0, nil
  -- (a spec read off its drawing gets a made-up one: opaque but for a clear top-left corner)
  local function fakeArt(w, h)
    local a = { w = w * 16, h = h * 16, px = {} }
    for v = 0, a.h - 1 do
      for u = 0, a.w - 1 do
        local o = (v * a.w + u) * 4
        a.px[o + 1], a.px[o + 2], a.px[o + 3], a.px[o + 4] = (u % 7) / 7, (v % 5) / 5, 0.5, (u + v > 6) and 1 or 0
      end
    end
    return a
  end
  local artSpecs = 0
  -- (a spec reading another building's drawing gets a made-up one too)
  local artCtx = { layoutArt = function(_, _, _, w, h) return fakeArt(w, h) end }
  for _, sp in ipairs(specs) do
    local okB, m = pcall(function()
      if sp.parts_art then
        artSpecs = artSpecs + 1
        K.HEIGHTSOLID_LOD = sp.lod
        local okA, parts, tex = pcall(sp.parts_art, fakeArt(sp.rect[3], sp.rect[4]), artCtx)
        K.HEIGHTSOLID_LOD = nil
        assert(okA, parts)
        assert(not tex or (tex.w and tex.h))
        return K.build(parts)
      end
      return K.build(sp.parts())
    end)
    if okB and #m.tris > 0 then built = built + 1 else bad = sp.name .. " " .. tostring(m) end
  end
  check(built == #specs and #specs >= 100 and artSpecs >= 50 and #solidSpecs >= 30,
    "every building spec builds (" .. built .. "/" .. #specs .. ", " .. tostring(bad) .. ")")
  -- solids: a dome cut to a drawn disc stands within its drawing and is closed (walls at its ends)
  do
    local W = 32
    local a = { w = W, h = W, px = {} }
    for v = 0, W - 1 do
      for u = 0, W - 1 do
        local o = (v * W + u) * 4
        local inside = ((u + 0.5 - 16) / 16) ^ 2 + ((v + 0.5 - 16) / 16) ^ 2 <= 1
        a.px[o + 1], a.px[o + 2], a.px[o + 3], a.px[o + 4] = 0.5, 0.5, 0.5, inside and 1 or 0
      end
    end
    local tex = K.withRing(a, {})
    local hs = K.HeightSolid("d", tex, W, K.Volume():dome(16, 20, 15, 10, 12), { depth = { 0, 32 }, step = 1, mirror_z = 20 })
    local m = K.build({ hs })
    local inDrawing, walls, front = true, 0, 0
    for _, t in ipairs(m.tris) do
      if t.tag == "d~proj" then
        front = front + 1
        for k = 1, 3 do
          local u, v = t[k][4], t[k][5]
          if u < -1e-6 or u > W + 1e-6 or v < -1.5 or v > W + 0.01 then inDrawing = false end
        end
      elseif t.tag == "d.wall~behind~proj" then walls = walls + 1 end
    end
    check(front > 0 and walls > 0 and inDrawing, "a HeightSolid: its seen faces read its drawing, walls close its ends")
    -- clip_art cuts a card standing past the drawing to the drawing's box
    local cm = K.mesh()
    cm:poly({ { -8, 0, 40, -8, 40 }, { 40, 0, 40, 40, 40 }, { 40, 48, 40, 40, -8 }, { -8, 48, 40, -8, -8 } }, 1, "c")
    K.clipToArt(cm, a)
    local inside = true
    for _, t in ipairs(cm.tris) do
      for k = 1, 3 do if t[k][4] < 0 or t[k][4] > 32 or t[k][5] < 0 or t[k][5] > 32 then inside = false end end
    end
    check(#cm.tris >= 2 and inside, "clip_art: a card past the drawing is cut to its box")
  end
  local lh
  for _, sp in ipairs(specs) do if sp.name == "littleroot_house_w" then lh = K.build(sp.parts()) end end
  check(lh and #lh.tris == 614, "Littleroot's house: 614 triangles, as the generator makes it")

  -- placing: a 2x2 building over a fake map, its art read from fake layers
  local spec = { name = "hut", layout = "L", rect = { 1, 1, 2, 2 }, ground = { 1 } }
  local refMids = { [1] = { [1] = 10, [2] = 11 }, [2] = { [1] = 12, [2] = 13 } }
  local ctx = { layout = function(id)
    return id == "L" and { pair = "general__x", mid = function(x, y) return (refMids[y] or {})[x] or 1 end } or nil
  end }
  local ref = B.reference(spec, ctx)
  check(ref and ref.w == 2 and ref.template[1] == 10 and ref.template[4] == 13, "a reference reads its template")
  -- layers: ground (1) is plain green; 10..13 draw a roof on their upper layer's top half only
  local src = {
    under = function(m, x, y) if m == 1 or (m >= 10 and m <= 13) then return 0, 1, 0, 1 end end,
    over = function(m, x, y) if m >= 10 and m <= 13 and y < 8 then return 1, 0, 0, 1 end return 0, 0, 0, 0 end,
  }
  local art = B.art(spec, ref, src)
  local function alpha(x, y) return art.px[(y * art.w + x) * 4 + 4] end
  check(art.w == 32 and alpha(3, 3) == 1 and alpha(3, 12) == 0, "its art: the upper layer kept, the ground's quarters clear")
  local core = B.core(spec, ref, art)
  check(#core == 4, "...every cell it draws in is core")
  -- the map: the hut at (5, 3) and a half copy at (9, 3)
  local mapMids = { ["5,3"] = 10, ["6,3"] = 11, ["5,4"] = 12, ["6,4"] = 13, ["9,3"] = 10, ["10,3"] = 11 }
  local grid = { w = 14, h = 8, rows = {} }
  for j = 0, 7 do
    grid.rows[j] = {}
    for i = 0, 13 do grid.rows[j][i] = { cx = i, cy = j, kind = "floor", pair = "general__y", mid = mapMids[i .. "," .. j] or 1 } end
  end
  grid.at = function(x, y) local r = grid.rows[y]; return r and r[x] end
  local md = { spec = spec, ref = ref, core = core, primaryOnly = true, tris = K.build({ K.Walls("w", { { 0, 32 }, { 32, 32 } }, 0, 16) }).tris }
  local found = B.find(grid, { md })
  check(#found == 1 and found[1].cx == 5 and found[1].cy == 3, "it stands where the map draws it whole, not at a half copy")
  md.primaryOnly = false
  check(#B.find(grid, { md }) == 0, "...a building of a secondary tileset stands only over its own pair")
  md.primaryOnly = true
  -- a town's own metatile drawing the building's pixels stands for the template's (not the anchor)
  grid.rows[4][6].mid = 99
  md.art = art
  check(#B.find(grid, { md }) == 0, "a cell drawn otherwise: no building")
  local alike = B.find(grid, { md }, function(m, cell, i, j) return cell.mid == 99 and i == 1 and j == 1 end)
  check(#alike == 1 and alike[1].cx == 5, "...unless that cell draws what the model owns there")
  grid.rows[4][6].mid = 13
  check(B.groundOf(grid, found[1], function() return true end) == 1, "...on the ground round it")
  local tops = B.tops(md)
  check(near(tops["0,1"], 1) and tops["1,1"] ~= nil, "a model's height over its cells, in tiles (the wall: 16 px)")
  -- the stage keeps the feet off a building's cells, as off a card's
  local open = { w = 30, h = 30, rows = {} }
  for j = 0, 29 do
    open.rows[j] = {}
    for i = 0, 29 do open.rows[j][i] = { cx = i, cy = j, kind = "floor" } end
  end
  open.at = function(x, y) local r = open.rows[y]; return r and r[x] end
  local opts = { player = { cx = 15, cy = 20 }, feet = { player = { 72, 114 }, enemy = { 176, 70 } } }
  local free = Stage.search(Camera, open, opts)
  local pf = open.at(math.floor(free.feet.player[1]), math.floor(free.feet.player[2]))
  pf.model, pf.top = true, 2
  local moved = Stage.search(Camera, open, opts)
  check(moved.score < free.score and (moved.tx ~= free.tx or moved.tz ~= free.tz),
    "the stage moves off a building's cell (" .. free.score .. " -> " .. moved.score .. ")")
  local verts = {}
  B.emit(found[1], 5, 3, function(v) verts[#verts + 1] = v end)
  check(#verts == 6 and near(verts[1][1], 0) and near(verts[1][3], 2) and near(verts[3][2], 1),
    "its triangles in tiles from the window's origin, 16 pixels a tile")
end

-- -------------------------------------------------------- hedges, fences, kits
do
  local K = dofile("src/scene/models/kernel.lua")
  local Fence = dofile("src/scene/models/fence.lua")(K)
  local C = dofile("src/scene/models/components.lua")(K, Fence)
  local B = dofile("src/scene/buildings.lua")
  local p, s = C.names("general__battle_frontier_outside_west")
  check(p == "general" and s == "battlefrontieroutsidewest", "a pair's names, as the specs spell tilesets")
  -- a fake map: a hedge run (0x23d) of three cells in Petalburg's tiles, the same tiles in
  -- another town's pair, and a curb of nothing but its plain middle (0x05E)
  local function grid(cells)
    local g = { w = 12, h = 8, rows = {} }
    for j = 0, 7 do
      g.rows[j] = {}
      for i = 0, 11 do
        local c = cells[i .. "," .. j]
        g.rows[j][i] = { cx = i, cy = j, kind = "floor", pair = c and c[2] or "general__petalburg", mid = c and c[1] or 1 }
      end
    end
    g.at = function(x, y) local r = g.rows[y]; return r and r[x] end
    return g
  end
  local g = grid({ ["2,2"] = { 0x23d }, ["3,2"] = { 0x23d }, ["3,3"] = { 0x23d },
                   ["8,2"] = { 0x23d, "general__rustboro" }, ["6,6"] = { 0x05E }, ["7,6"] = { 0x05E } })
  local runs = C.find(g)
  local hedges, curbs = 0, 0
  for _, r in ipairs(runs) do
    if r.spec.name == "hedge" then
      hedges = hedges + 1
      check(r.x0 == 2 and r.y0 == 2 and r.w == 2 and r.h == 2 and r.owned["1,1"] and not r.owned["0,1"],
        "a hedge run: its cells, connected, in its bounding box")
    end
    if r.spec.name == "curb" then curbs = curbs + 1 end
  end
  check(hedges == 1, "...only in its own tileset's towns")
  check(curbs == 0, "a run of nothing but a curb's plain middle is the road, not a curb")
  -- built from a fake drawing: every cell's upper layer a block 12 rows tall from row 4
  local src = {
    under = function(m) if m then return 0.2, 0.6, 0.2, 1 end end,
    over = function(m, x, y)
      if m == 0x23d and y >= 4 then return 0.1, 0.5, 0.1, 1 end
      return 0, 0, 0, 0
    end,
  }
  local hedgeRun
  for _, r in ipairs(runs) do if r.spec.name == "hedge" then hedgeRun = r end end
  local built = C.build(hedgeRun, src, function(x, y) local c = g.at(x, y); return c and c.mid end, function() return nil end)
  local mesh = built and K.build(built.parts)
  check(mesh and #mesh.tris > 0, "a hedge run builds a solid read off its drawing")
  local tall = 0
  for _, t in ipairs(mesh and mesh.tris or {}) do for k = 1, 3 do tall = math.max(tall, t[k][2]) end end
  check(math.abs(tall - 11) < 1e-6, "...its front the spec's 11 rows tall (" .. tall .. ")")
  -- a fence's rasteriser: a projected wall covers the pixels the drawing shows it on
  local tex = Fence.newArt(16, 16)
  for i = 4, #tex.px, 4 do tex.px[i] = 1 end
  local wall = K.build({ K.Walls("w", { { 2, 12 }, { 10, 12 } }, 0, 6) }).tris
  local cov = Fence.drawnBy(wall, tex, 16, 16)
  check(cov[6 * 16 + 2] and cov[11 * 16 + 9] and not cov[12 * 16 + 5] and not cov[8 * 16 + 11],
    "the pixels a post's front draws at 45 degrees (u = X, v = Z - Y)")
  -- kits: a block found by its corner, top row, end and foot
  local kg = grid({ ["1,1"] = { 0x220, "general__rustboro" }, ["2,1"] = { 0x221, "general__rustboro" },
                    ["3,1"] = { 0x223, "general__rustboro" }, ["1,2"] = { 0x228, "general__rustboro" },
                    ["1,3"] = { 0x240, "general__rustboro" } })
  local specs = dofile("src/scene/models/specs.lua")(K)
  local kits = B.kits(kg, specs.kits, function(pair) return select(2, C.names(pair)) end)
  check(#kits == 1 and kits[1].cx == 1 and kits[1].cy == 1 and kits[1].spec.rect[3] == 3 and kits[1].spec.rect[4] == 3,
    "a Rustboro block: found by its corner, 3 wide to its end, 3 tall to its foot")
  local okK, km = pcall(K.build, kits[1].spec.parts())
  check(okK and #km.tris > 0, "...and built as a flat-roofed block of that size")
end

-- ---------------------------------------------------------------- relief
do
  local Relief = dofile("src/scene/relief.lua")
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end
  -- a relief.bin: layout 7, 2 x 1 cells, cell (1, 0) a south face a level tall (its north row
  -- 16 px, its south row 0); one cut variant (the tile's lower half its background), one cut record
  local heights = {}
  for j = 0, 4 do for i = 0, 4 do heights[#heights + 1] = string.char((4 - j) * 4) end end
  local head = "VXL4" .. u16(1) .. u16(5)
  local index = u16(7) .. u16(1) .. u16(2) .. u16(1) .. u32(8 + 14) .. u16(0)
  local cells = string.char(1, 0) .. table.concat(heights)
  local blob = head .. index .. cells
  local rows = ""
  for j = 0, 15 do rows = rows .. u16(j >= 8 and 0xFFFF or 0) end
  local cutTable = u16(1) .. u16(1) .. u16(7) .. u16(0x70) .. rows
    .. u16(7) .. string.char(1, 0) .. u16(0) .. u16(16) .. u16(1) .. u16(0x7C) .. string.char(0xFF, 0)
  local s = blob .. cutTable .. u32(#blob) .. "CUTS"
  local R = Relief.parse(s)
  local L = R and R.layouts[7]
  check(L and L.w == 2 and L.h == 1 and L.cells[1] and L.cells[1][0] == 16 and L.cells[1][24] == 0 and not L.cells[0],
    "relief: a layout's cells read, heights in pixels, row by row")
  local cut = L and L.cuts[1]
  check(cut and cut.variant == 0 and cut.foot == 16 and cut.ground == 1 and cut.wall == 0x7C and cut.sides == 0xFF
    and L.faceTile == 0x7C and R.variants[0].metatile == 0x70 and R.variants[0].rows[8] == 0xFFFF,
    "...its cut record and variant, the map's face tile its commonest wall")
  check(Relief.isSlope(L.cells[1]) and Relief.centre(L.cells[1]) == 8 and Relief.sample(L.cells[1], 0.5, 0) == 16,
    "...a slope, its middle and its points sampled")
  -- a tile cut corner to corner: one 45-degree side; a half cut straight across: none
  local tri = {}
  for j = 0, 15 do
    local r = 0
    for i = 0, 15 do if i + j > 15 then r = r + 2 ^ i end end
    tri[j] = r
  end
  local d = Relief.cutDiagonals(tri)
  check(d.count == 1 and d.a[1] == 1 and d.b[1] == 1, "a cut tile's rock cut along its diagonal")
  check(Relief.cutDiagonals(R.variants[0].rows).count == 0, "...a straight cut has no diagonal")
  local tex = Relief.cutTexture(R.variants[0].rows, function() return { 1, 0, 0 } end)
  check(tex[0] and not tex[8 * 16], "...its texture: the rock drawn, the background clear")
  -- a seam: two maps side by side, the east one's edge a level under the west one's
  local A = { base = 0, w = 1, h = 2, cells = {} }
  local Bm = { base = 0, w = 1, h = 2, cells = {} }
  local function level(v) local g = {} for k = 0, 24 do g[k] = v end return g end
  A.cells[0], A.cells[1] = level(16), level(16)
  check(Relief.seamStep({ L = A, x = 0, y = 0, w = 1, h = 2 }, { L = Bm, x = 1, y = 0, w = 1, h = 2 }) == 16,
    "a seam asks the map beside to stand a level up to meet it")
  -- a cell with cliffs: its south face walled down to the lower ground in front
  local quads = 0
  local B = { quad = function() quads = quads + 1 end, tri = function() quads = quads + 1 end,
              sameMap = function() return true end, cell = function(x, y) return x == 0 and y == 0 and level(16) or nil end,
              cut = function() return nil end, variant = function() return nil end,
              tileUV = function() return 0, 0, 1, 1 end, metatileUV = function() return 0, 0, 1, 1 end,
              cutUV = function() return nil end }
  Relief.cliffWalls(B, 0, 0, level(16), level(16), 0x7C, nil, 0, 0xFF, false)
  check(quads == 12, "...a level-topped cell walls its west, east and south sides down to the ground, a quad a lattice step")
  -- a model round-trips through relief.bin's bytes
  local M = Relief.decode(s)
  check(Relief.encode(M) == s, "...a relief.bin decoded and encoded again is the same bytes")
  check(Relief.pyround(2.5) == 2 and Relief.pyround(3.5) == 4 and Relief.pyround(-0.5) == 0,
    "...heights rounded as Python rounds (half to even)")
end

-- ---------------------------------------------------------------- relief's last passes
do
  local Relief = dofile("src/scene/relief.lua")
  local Post = dofile("src/scene/relief_post.lua")
  local v, order = Post.json('{"b":1,"a":{"y":[1,2],"x":null},"c":true}')
  check(order[v][1] == "b" and order[v][2] == "a" and order[v][3] == "c" and v.a.x == Post.NULL and v.a.y[2] == 2,
    "the hand marks' JSON: objects keep their keys' order, null kept apart from absent")
  -- a cut tile on level ground at 32 px whose foot sank to 0: raised to the ground beside it
  local function level(h) local g = {} for k = 0, 24 do g[k] = h end return g end
  local M = { layouts = { [5] = { w = 3, h = 3, flags = 0, base = 0, cells = {} } }, cuts = {}, edges = {} }
  for k = 0, 8 do M.layouts[5].cells[k] = level(32) end
  M.cuts[5 * 65536 + 1 * 256 + 1] = { 0, 0, 0xFFFF, 0xFFFF, 0xFF, 0 }
  check(Post.cutFeet(M) == 1 and M.cuts[5 * 65536 + 257][2] == 32, "a cut tile's foot raised to the ground round it")
  -- the marks: a level set on a cell with no lattice yet (on one that has its own, a level only
  -- places a piece or a cut), a base on the map
  M.layouts[5].cells[2] = nil
  local world = { index = function(n) return n == "LAYOUT_X" and 5 or nil end, size = function() return 3, 3 end,
                  links = {}, tilesets = function() return "gTileset_General", "gTileset_X" end,
                  metatile = function() return 0 end, isWater = function() return false end }
  local fixes, ord = Post.json('{"layouts":{"LAYOUT_X":{"base":16,"cells":{"2,0":{"level":48}}}}}')
  Post.applyFixes(M, world, fixes, ord)
  check(M.layouts[5].base == 16 and M.layouts[5].cells[2][12] == 48, "the hand marks: a map's base, a cell's level")
  check(Relief.decode(Relief.encode(M)).layouts[5].cells[2][0] == 48, "...and written as relief.bin")
end

print(("%d/%d checks passed (battle scene)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
