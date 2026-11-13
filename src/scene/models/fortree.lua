-- Fortree City (Battle Scene: Overworld): the tree houses and the rope bridges between them, and
-- the palms.
--
-- Fortree is a town in the treetops. Its houses stand on decks laid over the wood, the decks are
-- joined by bridges of planks, and a ladder comes down from each deck to the forest floor. A
-- ladder is drawn from the deck's front edge to its foot on the path 28 rows lower, so the deck
-- stands DECK = 28 px over the ground. The drawing is the 45-degree view (a point (X, Y, Z) lands
-- on the art at u = X, v = Z - Y), so the whole house is built at its drawn rows and lifted by
-- DECK along the line of sight (K.Lifted): exact at 45 degrees, standing on the treetops.
--
--   the deck     planks running east-west, its front edge three rows: a slab DECK - 3 to DECK
--   the hut      walls 25 px tall on the deck, its front corners cut at 45 degrees
--   the roof     fronds over the hut: a low frustum of flat faces (LeafRoof)
--   the ladder   one upright face at the deck's front edge, the drawing projected
--   a bridge     its planks drawn 13 rows deep and two of front: a slab under each plank, the
--                gaps open, the two ropes across a strip at the planks' height
--
-- The cells under them are the wood's small trees (src/scene/trees.lua), so nothing is hollow.
-- A palm is a card cut out of the drawing, leaning back from its foot, exact at 45 degrees.
--
-- Ported from Emerald 3DS's scripts/voxel_fortree.py and its specs in voxel_building_specs.py (by
-- Zallax and contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see
-- LICENSE). Every number is theirs.

return function(K, specs)
  local h = specs.helpers
  local GRASS = h.GRASS
  local floor, sqrt, sin, cos, asin, rad, min = math.floor, math.sqrt, math.sin, math.cos, math.asin, math.rad, math.min
  local SHADE_ART, SHADE_EAST, SHADE_WEST, SHADE_BACK = K.SHADE_ART, K.SHADE_EAST, K.SHADE_WEST, K.SHADE_BACK

  local DECK = 28     -- px: the decks and bridges over the forest floor
  local SLAB = 3      -- px: a deck's front edge
  local PLANK = 2     -- px: a bridge plank's front, drawn under its top
  local WALL = 25     -- px: the hut's walls over the deck
  local EAVE = 21     -- px: the roof's foot over the deck, behind the walls' top

  local function key5(r, g, b) return floor(r * 31 + 0.5) * 1024 + floor(g * 31 + 0.5) * 32 + floor(b * 31 + 0.5) end
  local function key8(c) return key5(c[1] / 255, c[2] / 255, c[3] / 255) end
  -- a bridge's planks: the colours of their tops and fronts; the ropes are the outline's dark blue
  local PLANK_RGB = {}
  for _, c in ipairs({ { 65, 74, 106 }, { 238, 246, 189 }, { 205, 213, 164 }, { 172, 180, 123 }, { 131, 139, 74 } }) do
    PLANK_RGB[key8(c)] = true
  end
  local ROPE = key8({ 65, 74, 106 })

  local function rgbAt(art, u, v)
    local o = (v * art.w + u) * 4
    if art.px[o + 4] < 0.5 then return nil end
    return key5(art.px[o + 1], art.px[o + 2], art.px[o + 3])
  end

  --- A triangle wound to face `normal`.
  local function tri(mesh, a, b, c, normal, shade, tag)
    local e1x, e1y, e1z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local e2x, e2y, e2z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
    if nx * normal[1] + ny * normal[2] + nz * normal[3] < 0 then b, c = c, b end
    mesh:tri(a, b, c, shade, tag)
  end

  --- A flat polygon of (x, y, z) laid with the drawing projected: exact at 45 degrees wherever it
  --- stands (a ladder's face).
  local function ProjPoly(name, pts)
    return { name = name, emit = function(_, mesh)
      local q = {}
      for i, p in ipairs(pts) do q[i] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
      mesh:poly(q, SHADE_ART, name .. "~proj")
    end }
  end

  local function unit(v)
    local L = sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    return { v[1] / L, v[2] / L, v[3] / L }
  end

  --- A roof of fronds: a frustum from the plan `base` at y0 to its inset by `run` at y1, its
  --- first face the front. The faces the 45-degree view sees in front take the drawing
  --- projected; every other face is laid with the front's own fronds as the front shows them (the
  --- columns `cols`, its foot drawn on row `foot`); the top takes the drawing on from the front's
  --- top edge, mirrored there. Those faces read the grown band (`~behind`).
  local function LeafRoof(name, base, y0, run, y1, cols, foot)
    local top = K.insetPlan(base, run)
    return { name = name, emit = function(_, mesh)
      local b, t, n = base, top, #base
      local cx, cz = 0, 0
      for _, p in ipairs(b) do cx, cz = cx + p[1], cz + p[2] end
      cx, cz = cx / n, cz / n
      for i = 1, n do
        local j = i % n + 1
        local f = { { b[i][1], y0, b[i][2] }, { b[j][1], y0, b[j][2] }, { t[j][1], y1, t[j][2] }, { t[i][1], y1, t[i][2] } }
        local e1 = { f[2][1] - f[1][1], f[2][2] - f[1][2], f[2][3] - f[1][3] }
        local e2 = { f[4][1] - f[1][1], f[4][2] - f[1][2], f[4][3] - f[1][3] }
        local nrm = { e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1] }
        local mx, mz = (f[1][1] + f[2][1]) / 2 - cx, (f[1][3] + f[2][3]) / 2 - cz
        if nrm[1] * mx + nrm[3] * mz < 0 then nrm = { -nrm[1], -nrm[2], -nrm[3] } end
        local L = sqrt(nrm[1] ^ 2 + nrm[2] ^ 2 + nrm[3] ^ 2)
        if nrm[3] / L > 0.3 then
          -- turned south: the front and its cut corners, as drawn
          local q = {}
          for k, p in ipairs(f) do q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
          tri(mesh, q[1], q[2], q[3], nrm, SHADE_ART, name .. "~proj")
          tri(mesh, q[1], q[3], q[4], nrm, SHADE_ART, name .. "~proj")
        else
          -- the front's fronds, row for row at the same height: a texel a pixel along the face,
          -- the fall line as the projection lays it on the front
          local P0 = f[1]
          local hv = unit({ f[2][1] - P0[1], f[2][2] - P0[2], f[2][3] - P0[3] })
          local rise = { f[4][1] - P0[1], f[4][2] - P0[2], f[4][3] - P0[3] }
          local hr = rise[1] * hv[1] + rise[2] * hv[2] + rise[3] * hv[3]
          local up = { rise[1] - hr * hv[1], rise[2] - hr * hv[2], rise[3] - hr * hv[3] }
          local D = sqrt(up[1] ^ 2 + up[2] ^ 2 + up[3] ^ 2)
          up = { up[1] / D, up[2] / D, up[3] / D }
          local beta = asin(min(1.0, sqrt(nrm[1] ^ 2 + nrm[3] ^ 2) / L))
          local k = cos(beta) + sin(beta)
          local tile = K.Tile(cols[1], foot - D * k, cols[2], foot, { s0 = 7.0 * (i - 1) })
          local loc = {}
          for m, p in ipairs(f) do
            local d = { p[1] - P0[1], p[2] - P0[2], p[3] - P0[3] }
            loc[m] = { d[1] * hv[1] + d[2] * hv[2] + d[3] * hv[3], (D - (d[1] * up[1] + d[2] * up[2] + d[3] * up[3])) * k }
          end
          local shade = nrm[1] / L > 0.5 and SHADE_EAST or nrm[1] / L < -0.5 and SHADE_WEST or SHADE_BACK
          for _, piece in ipairs(K.tilePieces(loc, tile)) do
            local pts = {}
            for m, q in ipairs(piece) do
              local ps, pt = q[1], q[2]
              local s2 = D - pt / k
              pts[m] = { P0[1] + ps * hv[1] + s2 * up[1], P0[2] + ps * hv[2] + s2 * up[2], P0[3] + ps * hv[3] + s2 * up[3],
                         q[3], q[4] }
            end
            for m = 2, #pts - 1 do tri(mesh, pts[1], pts[m], pts[m + 1], nrm, shade, name .. ".side~behind") end
          end
        end
      end
      -- the top: the drawing mirrored at the front's top edge
      local seam = t[1][2]
      local edge = seam - y1
      local tp = {}
      for k, p in ipairs(t) do tp[k] = { p[1], y1, p[2], p[1], edge + (seam - p[2]) } end
      for k = 2, n - 1 do tri(mesh, tp[1], tp[k], tp[k + 1], { 0.0, 1.0, 0.0 }, SHADE_ART, name .. ".top~behind") end
    end }
  end

  --- The bridge planks crossing art row `row` (their tops' middle): runs of their colours at least
  --- 4 px wide, { { u0, u1 } }.
  local function plankRuns(art, row, x0, x1)
    local W = x1 or art.w
    local runs, start = {}, nil
    for u = x0 or 0, W do
      local on = u < W and PLANK_RGB[rgbAt(art, u, row) or -1] == true
      if on and not start then
        start = u
      elseif not on and start then
        if u - start >= 4 then runs[#runs + 1] = { start, u } end
        start = nil
      end
    end
    return runs
  end

  --- The planks of a bridge drawn in the art between columns x0-x1, their tops from row `top`
  --- (13 rows, then PLANK rows of front): a slab under each, and the ropes drawn across the gaps
  --- (rows top + 3 and top + 9) as flat strips at the planks' height. Built at the ground.
  local function bridgePlanks(art, top, x0, x1)
    x0 = x0 or 0
    local parts = {}
    for k, r in ipairs(plankRuns(art, top + 6, x0, x1)) do
      local u0, u1 = r[1], r[2]
      parts[#parts + 1] = K.PlanPrism(("plank%d_%d"):format(top, k - 1),
        { { u0, top }, { u1, top }, { u1, top + 12 }, { u0, top + 12 } }, -PLANK, 0, { u0, u1, top + 12 + PLANK })
    end
    local W = x1 or art.w
    for _, rr in ipairs({ top + 3, top + 9 }) do
      local run
      for u = x0, W do
        local on = u < W and rgbAt(art, u, rr) == ROPE
        if on and not run then
          run = u
        elseif not on and run then
          parts[#parts + 1] = ProjPoly(("rope%d_%d"):format(rr, run),
            { { run, -0.2, rr }, { u, -0.2, rr }, { u, -0.2, rr + 1 }, { run, -0.2, rr + 1 } })
          run = nil
        end
      end
    end
    return parts
  end

  --- A tree house drawn in a 5-cell-wide rectangle whose top row holds the roof's fronds: the
  --- hut's front wall foot on row 48 of the art, the deck's front edge on row `front` (64, or 80
  --- for the deeper deck), the ladder (if any) in columns ladder..ladder + 16 from there to its
  --- foot DECK rows lower. Every part at its drawn rows, lifted by DECK.
  local function treehouse(art, front, ladder)
    local deckBack = 19
    local hutFront, hutBack = 48, 16
    local deck = K.PlanPrism("deck", { { 8, deckBack }, { 72, deckBack }, { 72, front }, { 8, front } },
      -SLAB, 0, { 9, 17, front + SLAB })
    local hut = K.PlanPrism("hut", { { 24.5, hutFront }, { 55.5, hutFront }, { 62, hutFront - 6.5 }, { 62, hutBack },
      { 18, hutBack }, { 18, hutFront - 6.5 } }, 0, WALL, { 27, 31, hutFront })
    -- the fronds: their foot along the walls' top at the front, down over the cut corners; their
    -- tips on rows 17-20, the frustum's top edge there
    local roof = LeafRoof("roof", { { 24.5, 44 }, { 55.5, 44 }, { 63.5, 41 }, { 63.5, 11 }, { 56, 8 }, { 24, 8 },
      { 16.5, 11 }, { 16.5, 41 } }, EAVE, 8, EAVE + 13, { 26, 54 }, 23)
    local lifted = { deck, hut, roof }
    -- the planks of a bridge drawn in the deck's end cells, past its edge
    for _, p in ipairs(bridgePlanks(art, front - 15, 0, 8)) do lifted[#lifted + 1] = p end
    for _, p in ipairs(bridgePlanks(art, front - 15, 72, 80)) do lifted[#lifted + 1] = p end
    local parts = {}
    for i, p in ipairs(lifted) do parts[i] = K.Lifted(p, DECK) end
    if ladder then
      local z = front + DECK + 0.5
      parts[#parts + 1] = ProjPoly("ladder", { { ladder, 0, z }, { ladder + 16, 0, z }, { ladder + 16, DECK + 2, z },
        { ladder, DECK + 2, z } })
    end
    return parts
  end

  --- One cell of a bridge (Fortree's 0x256 over the wood, 0x24E over the path): its planks, lifted.
  local function bridgeCell(art)
    local parts = {}
    for i, p in ipairs(bridgePlanks(art, 1)) do parts[i] = K.Lifted(p, DECK) end
    return parts
  end

  --- flat() for parts read off the art: their hidden faces read the grown band.
  local function flatArt(make)
    return function(art)
      local tex = K.withRing(art, {})
      local parts = {}
      for i, p in ipairs(make(art)) do parts[i] = K.Grown(p, 2 * art.h) end
      return parts, tex
    end
  end

  -- The palms are drawn three cells wide: a crown of fronds two rows deep on the upper layer over
  -- the wood's canopy, and a trunk on the lower layer, one cell (0x25C) or two (0x241 over 0x273),
  -- the lowest with the crown of the small tree in front drawn over its foot. A palm is a card
  -- leaning back PALM_TILT degrees from its foot, the drawing itself with the trunk whole down to
  -- the ground (the small tree in front is a tree of its own), as long as makes it, at 45
  -- degrees, the drawing pixel for pixel.
  local PALM_TILT = 50.0
  local PALM_TRUNKS = { [0x25C] = 0x241, [0x273] = 0x273 }    -- trunk cell: whose lower layer

  local function palm(trunkCells)
    return function(art, ctx)
      local tex = { w = art.w, h = art.h, px = {} }
      for i = 1, #art.px do tex.px[i] = art.px[i] end
      for _, tc in ipairs(trunkCells) do
        local cx, cy, m = tc[1], tc[2], tc[3]
        local low = ctx.lowerOf and ctx.lowerOf(PALM_TRUNKS[m])
        if not low then error("fortree palm: no lower layer for " .. m, 0) end
        for y = 0, 15 do
          for x = 0, 15 do
            local r, g, b = low(x, y)
            local o = ((cy * 16 + y) * tex.w + cx * 16 + x) * 4
            tex.px[o + 1], tex.px[o + 2], tex.px[o + 3], tex.px[o + 4] = r, g, b, 1
          end
        end
      end
      local W, H = tex.w, tex.h
      local a = rad(PALM_TILT)
      local s = H / (cos(a) + sin(a))
      local topY, topZ = s * sin(a), H - s * cos(a)
      return { ProjPoly("palm", { { 0, 0, H }, { W, 0, H }, { W, topY, topZ }, { 0, topY, topZ } }) }, tex
    end
  end

  -- ── the specs ─────────────────────────────────────────────────────────────

  -- the forest floor the tree houses stand on, and what their cells draw that is the wood's: the
  -- canopy, the path
  local FORTREE_GROUND = { GRASS, 0x22A, 0x244, 0x237, 0x261, 0x253 }
  -- a house's cells: not its top corners (small trees of the wood) nor the row under its deck but
  -- the ladder's foot
  local function houseCells(rows, foot)
    local s = {}
    for j = 0, rows - 1 do
      for i = 0, 4 do
        if not ((i == 0 or i == 4) and j == 0) then s[i .. "," .. j] = true end
      end
    end
    if foot then s["2," .. rows] = true end
    return s
  end
  local function cellSet(list)
    local s = {}
    for _, c in ipairs(list) do s[c[1] .. "," .. c[2]] = true end
    return s
  end
  local L = "LAYOUT_FORTREE_CITY"
  local list = {
    -- the house at (10, 11) is the one at (8, 1) again
    { name = "fortree_treehouse", layout = L, rect = { 8, 1, 5, 6 }, owned = houseCells(5, true),
      repeat_at = { { 8, 1 }, { 10, 11 } }, ground = FORTREE_GROUND, parts_art = flatArt(function(art) return treehouse(art, 64, 32) end) },
    -- bridges east and west, a ladder
    { name = "fortree_treehouse_c", layout = L, rect = { 23, 1, 5, 6 }, owned = houseCells(5, true),
      ground = FORTREE_GROUND, parts_art = flatArt(function(art) return treehouse(art, 64, 32) end) },
    -- bridges east and west, no ladder
    { name = "fortree_treehouse_b", layout = L, rect = { 15, 1, 5, 5 }, owned = houseCells(5, false),
      ground = FORTREE_GROUND, parts_art = flatArt(function(art) return treehouse(art, 64) end) },
    -- the deeper deck in the north-east, one row more of it
    { name = "fortree_treehouse_d", layout = L, rect = { 30, 0, 5, 7 }, owned = houseCells(6, true),
      ground = FORTREE_GROUND, parts_art = flatArt(function(art) return treehouse(art, 80, 32) end) },
    -- the east one: a bridge west, a ladder without its hook
    { name = "fortree_treehouse_f", layout = L, rect = { 35, 11, 5, 6 }, owned = houseCells(5, true),
      ground = FORTREE_GROUND, parts_art = flatArt(function(art) return treehouse(art, 64, 32) end) },
    -- the tall palms, their trunks two cells (the other at (28, 6))
    { name = "fortree_palm", layout = L, rect = { 12, 6, 3, 4 }, repeat_at = { { 12, 6 }, { 28, 6 } },
      owned = cellSet({ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 1, 2 }, { 1, 3 } }),
      ground = FORTREE_GROUND, parts_art = palm({ { 1, 2, 0x25C }, { 1, 3, 0x273 } }) },
    -- the short ones, one cell of trunk (also at (14, 16) and (27, 17))
    { name = "fortree_palm_short", layout = L, rect = { 1, 1, 3, 3 }, repeat_at = { { 1, 1 }, { 14, 16 }, { 27, 17 } },
      owned = cellSet({ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 1, 2 } }),
      ground = FORTREE_GROUND, parts_art = palm({ { 1, 2, 0x25C } }) },
    { name = "fortree_bridge", layout = L, rect = { 13, 4, 1, 1 }, ground = FORTREE_GROUND, parts_art = flatArt(bridgeCell) },
    -- over the path, which runs on under it
    { name = "fortree_bridge_path", layout = L, rect = { 30, 14, 1, 1 }, ground = { 0x261, GRASS, 0x22A, 0x244, 0x237, 0x261, 0x253 },
      parts_art = flatArt(bridgeCell) },
  }
  for _, sp in ipairs(list) do specs[#specs + 1] = sp end

  -- The deck table (voxel_fortree.deck_table), for an overworld that lifts its walkers (the battle
  -- scene has none): the cells walked up on a deck or a bridge (lifted DECK; where the path passes
  -- under, only at elevation 4) and the ladders (lifted as the player climbs: the foot stays where
  -- it is drawn, DECK rows south of the deck's front - a 45-degree ramp, top to bottom of each
  -- cell). decks(io) -> { { x, y, top, bottom, gate } }, io = { w, h, metatile(x, y),
  -- elevation(x, y) }.
  local DECK_TILES = { [0x233] = true, [0x237] = true, [0x23B] = true, [0x23C] = true, [0x23D] = true,
                       [0x23E] = true, [0x23F] = true, [0x256] = true, [0x24E] = true, [0x235] = true }
  local LADDER_TOP, LADDER_FOOT = 0x245, 0x24D
  specs.decks = specs.decks or {}
  specs.decks[L] = function(io)
    local out = {}
    for y = 0, io.h - 1 do
      for x = 0, io.w - 1 do
        local m = io.metatile(x, y)
        if DECK_TILES[m] then
          out[#out + 1] = { x, y, DECK, DECK, io.elevation(x, y) == 15 and 4 or 0 }
        elseif m == LADDER_TOP then
          out[#out + 1] = { x, y, DECK, DECK - 16, 0 }
        elseif m == LADDER_FOOT then
          out[#out + 1] = { x, y, DECK - 16, 0, 0 }
        end
      end
    end
    return out
  end
  return list
end
