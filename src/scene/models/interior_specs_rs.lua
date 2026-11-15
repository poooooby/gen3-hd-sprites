-- Ruby's and Sapphire's own rooms (Battle Scene: Overworld): the rooms they draw otherwise than
-- Emerald - Emerald redrew every gym - read by src/scene/models/interiors.lua, in the format of
-- interior_specs.lua. Each takes the place of Emerald 3DS's room of the same layout (main.lua);
-- Emerald's hold wherever Ruby and Sapphire draw Emerald's maps (src/scene/prints.lua).
--
-- WoobleView's own reading, by Emerald 3DS's method and with its helpers (interior_specs.lua's
-- `helpers`): each piece a shape of the room's drawing, its front `height` rows standing at its
-- drawn foot. Every number is read off Ruby's drawing (Sapphire's rooms are Ruby's, tile for tile):
-- pixels, colours and cells only. Each room is checked by tests/drivers/room_check.lua.

return function(H, EMERALD)
  local piece, ownShell = H.piece, H.ownShell

  local function room(name, layout, ground, pieces, o)
    o = o or {}
    return { name = name, interior = { layout = layout, ground = ground, pieces = pieces, open = o.open,
                                        shade = o.shade, pit = o.pit, draw = o.draw } }
  end

  -- a gym's statue by its door, its top cell's left edge at x and top at y: a ball on a pedestal
  -- (the pedestal's bottom corners rounded off; the ball found by its own few pixels)
  local function statue(name, x, y)
    return {
      piece(name .. "_ball", { { "ellipse", x + 8, y + 7, 7, 7 } }, 8, { base = 16, found = true }),
      piece(name, { { x, y, x + 16, y + 30 }, { x + 1, y + 30, x + 15, y + 31 }, { x + 2, y + 31, x + 14, y + 32 } }, 16,
        { back = y + 16 }),
    }
  end

  -- a maze block: `rects` in cells, each drawn from 8 rows north of its cells to its foot, `height`
  -- rows of front, its sides textured with `side`
  local function block(name, rects, height, side)
    local shape = {}
    for i, r in ipairs(rects) do shape[i] = { r[1] * 16, r[2] * 16 - 8, r[3] * 16, r[4] * 16 } end
    return piece(name, shape, height, { side = side })
  end

  -- a gym's back wall: rows 0 to `foot` (px) across, its two corners down to `cornerFoot`, the side
  -- walls on to the room's front `front`, in stretches of at most `stretch` px
  local function gymWalls(w, foot, cornerFoot, front, height, side)
    local W = w * 16
    local out = {
      piece("wall_w", { { 0, 0, 16, cornerFoot } }, height, { fill = 16, foot = cornerFoot, side = side }),
      piece("wall_e", { { W - 16, 0, W, cornerFoot } }, height, { fill = 16, foot = cornerFoot, side = side }),
      piece("wall", { { 16, 0, W - 16, foot } }, height, { fill = 16, foot = foot, side = side }),
    }
    local mid = math.floor((cornerFoot + front) / 32) * 16
    out[#out + 1] = piece("side_w", {}, height, { side = side, walls = { { { 0, mid }, { 0, cornerFoot } } } })
    out[#out + 1] = piece("side_w2", {}, height, { side = side, walls = { { { 0, front }, { 0, mid } } } })
    out[#out + 1] = piece("side_e", {}, height, { side = side, walls = { { { W, cornerFoot }, { W, mid } } } })
    out[#out + 1] = piece("side_e2", {}, height, { side = side, walls = { { { W, mid }, { W, front } } } })
    return out
  end

  local ROOMS = {}
  local function add(...) ROOMS[#ROOMS + 1] = room(...) end
  -- Emerald 3DS's room `name` whole, for a room Ruby draws a little otherwise where its pieces -
  -- each found by its own pixels - read Ruby's drawing as they read Emerald's (proved so by
  -- room_check); `o` its interior's fields replaced
  local function adopt(name, o)
    for _, r in ipairs(EMERALD or {}) do
      if r.name == name then
        local interior = {}
        for k, v in pairs(r.interior) do interior[k] = v end
        for k, v in pairs(o or {}) do interior[k] = v end
        ROOMS[#ROOMS + 1] = { name = "rs_" .. name, interior = interior, replaces = name }
        return
      end
    end
  end

  -- ── Rustboro's gym: pink stone blocks on a cobbled floor ──────────────────────
  -- 11 x 19. The back wall rows 0-1 (its corners to row 2); the leader's sand dais (rows 2-3) lies
  -- flat, as in Emerald's. The blocks: the cells the player cannot walk, each block's pink top
  -- drawn from 8 rows into the cell north of it, its front 12 rows (the lip at 146, the bricks to
  -- the cell's foot). The statues at (2, 16) and (8, 16).
  local RUSTBORO_BLOCK_SIDE = { 24, 148, 40, 160 }
  local function rustboroGym()
    local out = {}
    for _, p in ipairs(statue("statue_w", 32, 256)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 128, 256)) do out[#out + 1] = p end
    local blocks = {
      { "block_w", { { 0, 6, 4, 7 }, { 0, 7, 2, 9 }, { 0, 9, 4, 10 }, { 0, 10, 1, 15 } } },
      { "block_sw", { { 2, 11, 4, 15 } } },
      { "block_n", { { 7, 6, 9, 10 } } },
      { "block_e", { { 10, 6, 11, 15 }, { 7, 11, 10, 12 }, { 9, 12, 10, 14 }, { 7, 14, 10, 15 } } },
    }
    for _, b in ipairs(blocks) do out[#out + 1] = block(b[1], b[2], 12, RUSTBORO_BLOCK_SIDE) end
    for _, p in ipairs(gymWalls(11, 32, 48, 304, 25, { 64, 7, 80, 32 })) do out[#out + 1] = p end
    return ownShell(out)
  end
  add("rs_rustboro_gym", "LAYOUT_RUSTBORO_CITY_GYM", { 0x208 }, rustboroGym())

  -- ── Dewford's gym: a maze cut in dark rock two cells tall ─────────────────────
  -- 18 x 28. The rock: every cell the player cannot walk but the alcove's two bookcases and the
  -- statues' pedestals, as runs down each column (x, y0, y1), read off the grid; each rectangle of
  -- them (`runRects`) drawn from 8 rows into the cell north of it, its front up to 24 rows (a run
  -- one cell tall, 4 rows less), as Emerald 3DS reads Emerald's. The leader's alcove (rows 1-6,
  -- columns 10-17): a green bookcase at either end (11 and 16, rows 3-4) against its back wall.
  local DEWFORD_GYM_RUNS = {
    { 0, 0, 27 }, { 1, 0, 6 }, { 1, 11, 27 }, { 2, 0, 6 }, { 2, 8, 13 }, { 2, 18, 20 }, { 2, 23, 27 },
    { 3, 0, 6 }, { 3, 8, 13 }, { 3, 15, 21 }, { 3, 24, 27 }, { 4, 0, 6 }, { 4, 8, 13 }, { 4, 15, 21 },
    { 4, 26, 27 }, { 5, 0, 6 }, { 5, 19, 21 }, { 6, 0, 6 }, { 6, 19, 21 }, { 7, 0, 6 }, { 7, 8, 14 },
    { 7, 16, 21 }, { 7, 26, 27 }, { 8, 0, 6 }, { 8, 8, 14 }, { 8, 16, 19 }, { 8, 23, 27 }, { 9, 0, 6 },
    { 9, 12, 14 }, { 9, 16, 21 }, { 9, 23, 27 }, { 10, 0, 10 }, { 10, 12, 14 }, { 10, 16, 21 },
    { 10, 23, 27 }, { 11, 0, 2 }, { 11, 6, 10 }, { 11, 12, 14 }, { 11, 16, 21 }, { 11, 23, 27 },
    { 12, 0, 3 }, { 12, 7, 10 }, { 12, 12, 14 }, { 12, 25, 27 }, { 13, 0, 3 }, { 13, 12, 14 },
    { 13, 16, 27 }, { 14, 0, 3 }, { 14, 12, 14 }, { 14, 16, 27 }, { 15, 0, 3 }, { 15, 7, 14 },
    { 15, 16, 27 }, { 16, 0, 2 }, { 16, 6, 27 }, { 17, 0, 27 },
  }
  local function dewfordGym()
    local side = { 128, 424, 144, 448 }   -- a stretch of the front wall's face
    local out = {
      piece("shelf_w", { { 176, 48, 192, 80 } }, 24, { against = 72, side = { 179, 57, 189, 63 } }),
      piece("shelf_e", { { 256, 48, 272, 80 } }, 24, { against = 72, side = { 259, 57, 269, 63 } }),
    }
    for _, p in ipairs(statue("statue_w", 64, 368)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 112, 368)) do out[#out + 1] = p end
    for _, r in ipairs(H.runRects(DEWFORD_GYM_RUNS)) do
      local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
      out[#out + 1] = piece(("block_%d_%d"):format(x0 / 16, y0 / 16), { { x0, y0 ~= 0 and y0 - 8 or 0, x1, y1 } },
        math.min(24, y1 - y0 - 4), { side = side, solid = true })
    end
    return ownShell(out)
  end
  add("rs_dewford_gym", "LAYOUT_DEWFORD_TOWN_GYM", { 0x201 }, dewfordGym())

  -- ── Mauville's gym: coils and their beams down a corridor ─────────────────────
  -- 10 x 21, drawn as Emerald's with its own puzzle: the dark blocks either side of the corridor
  -- (rows 0-7, their grey tops 6 rows over a striped front to 128), the stubs at (9, 10-11) and
  -- (0, 13-14) and the block east at (7-9, 13-14); the back wall (rows 0-1) with four coils before
  -- it; the coils on the floor, each its head cell over its foot (one drawn whole standing for the
  -- others, as Emerald 3DS has it); the beams between them (the electric gates' tiles, secondary
  -- 144-159), each standing only while its cell holds its lit metatile - Ruby's ids are Emerald's:
  -- 0x220 across, 0x248 down; the dark either side of the entrance hall (rows 17-20).
  local MAUVILLE_SIDE = { 0, 104, 16, 126 }
  local MAUVILLE_FLOOR = { "fff6a4", "cdcd83", "f6e641", "ffff10", "d5d58b", "b4b483" }
  local MAUVILLE_BEAM_TILES = { 512 + 144, 512 + 159 }
  local function mauvilleBeam(x, y, lit)
    return piece(("beam_%d_%d"):format(x, y), { { x * 16, y * 16, x * 16 + 32, y * 16 + 32 } }, 16,
      { card = true, tiles = MAUVILLE_BEAM_TILES, anim = true, when = { x, y, lit } })
  end
  local function mauvilleBeamDown(x, y, lit)
    local za, zb = y * 16 + 16, y * 16 + 57
    return piece(("beam_%d_%d"):format(x, y), { { x * 16, y * 16, x * 16 + 16, y * 16 + 32 } }, 1,
      { tiles = MAUVILLE_BEAM_TILES, anim = true, when = { x, y + 1, lit },
        ribbon = { { za, za - y * 16 }, { zb, zb - y * 16 - 32 } }, skip = { { x, y } } })
  end
  local MAUVILLE_COILS = { { 3, 7 }, { 6, 7 }, { 0, 10 }, { 3, 10 }, { 6, 10 }, { 3, 13 }, { 6, 13 },
                           { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 } }
  local function mauvilleGym()
    local side = MAUVILLE_SIDE
    local c0 = MAUVILLE_COILS[1]
    local copies = {}
    for i = 2, #MAUVILLE_COILS do copies[#copies + 1] = MAUVILLE_COILS[i] end
    local out = {
      mauvilleBeam(4, 7, 0x220),
      mauvilleBeam(4, 13, 0x220),
      mauvilleBeamDown(3, 8, 0x248),
      mauvilleBeamDown(6, 11, 0x248),
      piece("coil", { { c0[1] * 16, c0[2] * 16 + 3, c0[1] * 16 + 16, c0[2] * 16 + 32 } }, 22,
        { round = "lathe", leave = MAUVILLE_FLOOR, at = copies }),
      piece("block_w", { { 0, 0, 48, 128 } }, 24, { side = side, solid = true }),
      piece("block_e", { { 112, 0, 160, 128 } }, 24, { side = side, solid = true }),
      piece("block_e_stub", { { 144, 152, 160, 192 } }, 18, { side = side, solid = true }),
      piece("block_w_stub", { { 0, 200, 16, 240 } }, 18, { side = side, solid = true }),
      piece("block_se", { { 112, 200, 160, 240 } }, 18, { side = side, solid = true }),
      -- (the hall's walls only: the dark beside it lies as drawn, its rim at the hall's mouth)
      piece("side_hall_w", {}, 24, { side = side, walls = { { { 32, 336 }, { 32, 272 } } } }),
      piece("side_hall_e", {}, 24, { side = side, walls = { { { 128, 272 }, { 128, 336 } } } }),
      piece("wall", { { 48, 0, 112, 32 } }, 26, { fill = 16, foot = 32, side = side }),
      piece("side_w", {}, 24, { side = side, walls = { { { 0, 272 }, { 0, 128 } } } }),
      piece("side_e", {}, 24, { side = side, walls = { { { 160, 128 }, { 160, 272 } } } }),
    }
    for _, p in ipairs(statue("statue_w", 48, 272)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 96, 272)) do out[#out + 1] = p end
    return ownShell(out)
  end
  add("rs_mauville_gym", "LAYOUT_MAUVILLE_CITY_GYM", { 0x201 }, mauvilleGym())

  -- ── Lavaridge's gym: sandstone walls in rows, pillars between them ────────────
  -- 11 x 24 both floors. A wall across the room: its cell row blocked, its yellow top (rows 2-5)
  -- over a 16-row front of red triangles, the floor from row 24 of its two cells. A divider
  -- (1F column 5, B1F columns 2, 5, 8): the same wall run north to south, its front at its south
  -- end. B1F's curbs (row 12, row 19 between the pillars): the dark ledges in the lower half of
  -- their cells, 7 rows. The 1F statues at (6, 16) and (10, 16), before the wall.
  local LAVARIDGE_SIDE = { 16, 6, 32, 22 }
  local LAVARIDGE_FLOOR = { "cdac8b", "9c736a", "b48b7b", "e6c594" }
  local function lavaridgeGym(walls, dividers, curbs, front)
    local side, out = LAVARIDGE_SIDE, {}
    for _, c in ipairs(curbs) do
      out[#out + 1] = piece(("block_curb_%d_%d"):format(c[1], c[3]),
        { { c[1] * 16, c[3] * 16 + 8, c[2] * 16, c[3] * 16 + 16 } }, 7, { leave = LAVARIDGE_FLOOR })
    end
    for _, w in ipairs(walls) do
      out[#out + 1] = piece(("block_%d_%d"):format(w[1], w[3]), { { w[1] * 16, w[3] * 16, w[2] * 16, w[3] * 16 + 24 } },
        16, { side = side, solid = true })
    end
    for _, d in ipairs(dividers) do
      out[#out + 1] = piece(("block_div_%d"):format(d[1]), { { d[1] * 16, d[2], d[1] * 16 + 16, d[3] } }, 16,
        { side = side, solid = true })
    end
    out[#out + 1] = piece("side_w", {}, 16, { side = side, walls = { { { 0, front }, { 0, 24 } } } })
    out[#out + 1] = piece("side_e", {}, 16, { side = side, walls = { { { 176, 24 }, { 176, front } } } })
    return out
  end
  local function lavaridgeGym1f()
    local walls = {}
    for _, r in ipairs({ 0, 7, 15 }) do
      walls[#walls + 1] = { 0, 5, r }
      walls[#walls + 1] = { 6, 11, r }
    end
    local out = lavaridgeGym(walls, { { 5, 0, 376 } }, {}, 384)
    for _, p in ipairs(statue("statue_w", 96, 256)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 160, 256)) do out[#out + 1] = p end
    return ownShell(out)
  end
  local function lavaridgeGymB1f()
    local walls = { { 0, 11, 0 }, { 0, 2, 4 }, { 3, 5, 4 }, { 6, 8, 4 }, { 9, 11, 4 } }
    local dividers = { { 2, 64, 312 }, { 5, 64, 312 }, { 8, 64, 312 } }
    local curbs = { { 0, 2, 12 }, { 0, 2, 19 }, { 3, 5, 19 }, { 6, 8, 19 }, { 9, 11, 19 } }
    return ownShell(lavaridgeGym(walls, dividers, curbs, 384))
  end
  add("rs_lavaridge_gym_1f", "LAYOUT_LAVARIDGE_TOWN_GYM_1F", { 0x202 }, lavaridgeGym1f())
  add("rs_lavaridge_gym_b1f", "LAYOUT_LAVARIDGE_TOWN_GYM_B1F", { 0x202 }, lavaridgeGymB1f())

  -- ── Fortree's gym: a wood of round posts on grass ─────────────────────────────
  -- 20 x 25. A post stands on every cell of its metatiles the player cannot walk (20B, 20F, 210,
  -- 211, 218, 219, 21A, 220, 228, 22C, 22D), its top's ellipse in the lower half of the cell north
  -- of it: one drawn whole, at (7, 11), standing again at every other, each textured as drawn there
  -- (Emerald 3DS's columns, turned on a lathe). The log piles (213, 217, 21B, 21F, 229, 233, 234),
  -- two logs side by side a cell, in runs down a column; the three green rails before the
  -- trainers' gaps at rows 9, 13 and 17 (columns 1-4); the statues at (1, 20) and (4, 20).
  local FORTREE_FLOOR = { "ace68b", "6a9c6a", "94c583", "d5eecd" }
  local FORTREE_POSTS = {
    { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 }, { 0, 7 }, { 0, 8 }, { 0, 9 },
    { 0, 10 }, { 0, 11 }, { 0, 12 }, { 0, 13 }, { 0, 14 }, { 0, 15 }, { 0, 16 }, { 0, 17 }, { 0, 18 },
    { 0, 19 }, { 0, 20 }, { 0, 21 }, { 0, 22 }, { 0, 23 }, { 0, 24 }, { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, 24 },
    { 2, 0 }, { 3, 0 }, { 4, 0 }, { 4, 24 }, { 5, 0 }, { 5, 7 }, { 5, 8 }, { 5, 9 }, { 5, 10 }, { 5, 11 },
    { 5, 12 }, { 5, 13 }, { 5, 14 }, { 5, 15 }, { 5, 16 }, { 5, 17 }, { 5, 18 }, { 5, 24 }, { 6, 0 }, { 6, 5 },
    { 6, 6 }, { 6, 7 }, { 6, 8 }, { 6, 9 }, { 6, 10 }, { 6, 11 }, { 6, 12 }, { 6, 13 }, { 6, 14 }, { 6, 15 },
    { 6, 16 }, { 6, 17 }, { 6, 18 }, { 6, 23 }, { 6, 24 }, { 7, 0 }, { 7, 1 }, { 7, 2 }, { 7, 5 }, { 7, 6 },
    { 7, 7 }, { 7, 8 }, { 7, 9 }, { 7, 10 }, { 7, 11 }, { 7, 12 }, { 7, 13 }, { 7, 14 }, { 7, 15 }, { 7, 16 },
    { 7, 17 }, { 7, 18 }, { 7, 21 }, { 7, 22 }, { 7, 23 }, { 7, 24 }, { 8, 0 }, { 8, 1 }, { 8, 2 }, { 8, 4 },
    { 8, 5 }, { 8, 14 }, { 8, 15 }, { 8, 16 }, { 8, 17 }, { 8, 18 }, { 8, 19 }, { 8, 21 }, { 8, 22 },
    { 8, 23 }, { 8, 24 }, { 9, 0 }, { 9, 1 }, { 9, 2 }, { 9, 4 }, { 9, 5 }, { 9, 15 }, { 9, 16 }, { 9, 17 },
    { 9, 18 }, { 9, 19 }, { 9, 21 }, { 9, 22 }, { 9, 23 }, { 9, 24 }, { 10, 0 }, { 10, 1 }, { 10, 2 },
    { 10, 4 }, { 10, 5 }, { 10, 7 }, { 10, 8 }, { 10, 9 }, { 10, 10 }, { 10, 11 }, { 10, 12 }, { 10, 13 },
    { 10, 15 }, { 10, 16 }, { 10, 17 }, { 10, 18 }, { 10, 19 }, { 10, 23 }, { 10, 24 }, { 11, 0 }, { 11, 1 },
    { 11, 2 }, { 11, 7 }, { 11, 8 }, { 11, 9 }, { 11, 10 }, { 11, 11 }, { 11, 12 }, { 11, 13 }, { 11, 15 },
    { 11, 16 }, { 11, 17 }, { 11, 18 }, { 11, 19 }, { 11, 23 }, { 11, 24 }, { 12, 0 }, { 12, 9 }, { 12, 10 },
    { 12, 11 }, { 12, 12 }, { 12, 13 }, { 12, 15 }, { 12, 16 }, { 12, 17 }, { 12, 18 }, { 12, 19 }, { 12, 23 },
    { 12, 24 }, { 13, 0 }, { 13, 10 }, { 13, 11 }, { 13, 15 }, { 13, 16 }, { 13, 17 }, { 13, 18 }, { 13, 19 },
    { 13, 23 }, { 13, 24 }, { 14, 0 }, { 14, 10 }, { 14, 11 }, { 14, 17 }, { 14, 18 }, { 14, 19 }, { 14, 23 },
    { 14, 24 }, { 15, 0 }, { 15, 10 }, { 15, 11 }, { 15, 23 }, { 15, 24 }, { 16, 0 }, { 16, 5 }, { 16, 6 },
    { 16, 7 }, { 16, 8 }, { 16, 9 }, { 16, 10 }, { 16, 11 }, { 16, 17 }, { 16, 18 }, { 16, 23 }, { 16, 24 },
    { 17, 0 }, { 17, 5 }, { 17, 6 }, { 17, 7 }, { 17, 8 }, { 17, 9 }, { 17, 10 }, { 17, 11 }, { 17, 14 },
    { 17, 15 }, { 17, 17 }, { 17, 18 }, { 17, 21 }, { 17, 22 }, { 17, 23 }, { 17, 24 }, { 18, 0 }, { 18, 5 },
    { 18, 6 }, { 18, 7 }, { 18, 8 }, { 18, 9 }, { 18, 10 }, { 18, 11 }, { 18, 12 }, { 18, 17 }, { 18, 18 },
    { 18, 21 }, { 18, 22 }, { 18, 23 }, { 18, 24 }, { 19, 0 }, { 19, 1 }, { 19, 2 }, { 19, 3 }, { 19, 4 },
    { 19, 5 }, { 19, 6 }, { 19, 7 }, { 19, 8 }, { 19, 9 }, { 19, 10 }, { 19, 11 }, { 19, 12 }, { 19, 13 },
    { 19, 14 }, { 19, 15 }, { 19, 16 }, { 19, 17 }, { 19, 18 }, { 19, 19 }, { 19, 20 }, { 19, 21 }, { 19, 22 },
    { 19, 23 }, { 19, 24 },
  }
  local FORTREE_PILES = { { 2, 1, 2 }, { 5, 5, 6 }, { 6, 1, 2 }, { 6, 21, 22 }, { 10, 21, 22 }, { 11, 4, 5 },
                          { 12, 7, 8 }, { 14, 3, 4 }, { 14, 7, 8 }, { 14, 14, 16 }, { 15, 2, 3 }, { 16, 14, 15 },
                          { 16, 21, 22 } }
  local FORTREE_POST_HEIGHT = 8
  local function fortreeGym()
    local fl = FORTREE_FLOOR
    local ref = { 7, 11 }
    local height = FORTREE_POST_HEIGHT
    local dy = math.floor(-height / 16)
    local at = {}
    for _, c in ipairs(FORTREE_POSTS) do
      if not (c[1] == ref[1] and c[2] == ref[2]) then at[#at + 1] = { c[1], c[2] + dy } end
    end
    local out = {
      piece("post", { { ref[1] * 16, ref[2] * 16 - height, ref[1] * 16 + 16, ref[2] * 16 + 16 } }, height,
        { round = "lathe", squash = 1.0, turn = { 8, 1 }, leave = fl, variants = true, at = at }),
    }
    for _, s in ipairs(FORTREE_PILES) do
      out[#out + 1] = piece(("pile_%d_%d"):format(s[1], s[2]), { { s[1] * 16, s[2] * 16, s[1] * 16 + 16, s[3] * 16 + 16 } }, 5,
        { round = "lathe", posts = { 8, 8 }, turn = { 6, 1 }, leave = fl })
    end
    for _, y in ipairs({ 9, 13, 17 }) do
      out[#out + 1] = piece("rail_" .. y, { { 16, y * 16 + 1, 80, y * 16 + 8 } }, 3, { solid = true })
    end
    for _, p in ipairs(statue("statue_w", 16, 320)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 64, 320)) do out[#out + 1] = p end
    return out
  end
  add("rs_fortree_gym", "LAYOUT_FORTREE_CITY_GYM", { 0x202 }, fortreeGym())

  -- ── Mossdeep's gym: spin tiles on blue, low white walls between them ───────────
  -- 20 x 30. The walls: every cell the player cannot walk but the back wall's (240, 248), the
  -- machines (238) and the statues' pedestals (244), in runs down each column; each a white top
  -- (8 rows) over a 6-row front, the blue left as the floor. The machines at (2, 7), (8, 10),
  -- (16, 15) and (5, 24); the statues at (7, 26) and (11, 26); the back wall rows 0-1.
  local MOSSDEEP_FLOOR = { "73acf6", "5aacf6", "739ccd" }
  local MOSSDEEP_RUNS = {
    { 0, 6, 6 }, { 0, 12, 12 }, { 0, 17, 29 }, { 1, 12, 12 }, { 2, 6, 6 }, { 2, 12, 12 }, { 2, 15, 15 },
    { 2, 17, 21 }, { 2, 25, 27 }, { 3, 6, 6 }, { 3, 27, 27 }, { 4, 6, 9 }, { 4, 27, 27 }, { 5, 9, 13 },
    { 5, 15, 20 }, { 5, 27, 27 }, { 6, 27, 27 }, { 7, 6, 6 }, { 7, 8, 13 }, { 7, 15, 18 }, { 8, 6, 6 },
    { 8, 8, 8 }, { 8, 12, 12 }, { 9, 6, 6 }, { 9, 8, 8 }, { 9, 12, 12 }, { 9, 15, 15 }, { 9, 21, 21 },
    { 10, 6, 6 }, { 10, 8, 8 }, { 10, 21, 21 }, { 11, 6, 6 }, { 11, 8, 8 }, { 11, 21, 21 }, { 12, 4, 6 },
    { 12, 8, 13 }, { 12, 15, 18 }, { 12, 21, 21 }, { 12, 27, 27 }, { 13, 18, 18 }, { 13, 21, 21 },
    { 13, 27, 27 }, { 14, 2, 6 }, { 14, 8, 12 }, { 14, 15, 15 }, { 14, 18, 18 }, { 14, 21, 21 },
    { 14, 27, 27 }, { 15, 12, 12 }, { 15, 18, 18 }, { 15, 21, 21 }, { 15, 23, 25 }, { 15, 27, 27 },
    { 16, 8, 8 }, { 16, 12, 12 }, { 16, 18, 18 }, { 16, 21, 21 }, { 16, 27, 27 }, { 17, 8, 14 },
    { 17, 19, 27 }, { 19, 9, 29 },
  }
  local MOSSDEEP_MACHINES = { { 2, 7 }, { 8, 10 }, { 16, 15 }, { 5, 24 } }
  local function mossdeepGym()
    local out = {}
    for _, r in ipairs(H.runRects(MOSSDEEP_RUNS)) do
      out[#out + 1] = piece(("block_%d_%d"):format(r[1] / 16, r[2] / 16), { r }, 6,
        { leave = MOSSDEEP_FLOOR, side = { 40, 106, 56, 112 } })
    end
    for _, c in ipairs(MOSSDEEP_MACHINES) do
      out[#out + 1] = piece(("machine_%d_%d"):format(c[1], c[2]), { { c[1] * 16, c[2] * 16, c[1] * 16 + 16, c[2] * 16 + 16 } }, 10,
        { leave = MOSSDEEP_FLOOR, solid = true })
    end
    for _, p in ipairs(statue("statue_w", 112, 416)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 176, 416)) do out[#out + 1] = p end
    out[#out + 1] = piece("wall", { { 0, 0, 320, 32 } }, 32, { fill = 16, foot = 32, side = { 32, 0, 48, 32 } })
    return ownShell(out)
  end
  add("rs_mossdeep_gym", "LAYOUT_MOSSDEEP_CITY_GYM", { 0x210 }, mossdeepGym())

  -- ── Sootopolis's gym: ice floors in tiers, walls of ice rock between them ──────
  -- 17 x 26 both floors, Emerald's plan with its own walls: every cell the player cannot walk (but
  -- 1F's boulders, 203 / 216, and the statues' pedestals; B1F's rock fill, 201, beyond its walls)
  -- in runs down each column, cut at the tiers' first rows (1F 4, 10, 15, 20; B1F 10, 15, 20) and
  -- read as Emerald 3DS reads Emerald's (a wall rising from one tier to the next leaves its top's
  -- row to the map; a run ending on a tier's first row a level taller). 1F's boulders on the ice;
  -- its statues at (6, 23) and (10, 23).
  local SOOTOPOLIS_ICE = { "a4eeff", "def6ff", "8bd5ff", "6ab4ff" }
  local SOOTOPOLIS_1F_RUNS = {
    { 0, 0, 25 }, { 1, 0, 25 }, { 2, 0, 25 }, { 3, 0, 1 }, { 3, 4, 5 }, { 3, 10, 25 }, { 4, 0, 2 }, { 4, 4, 5 },
    { 4, 10, 25 }, { 5, 0, 2 }, { 5, 4, 5 }, { 5, 10, 11 }, { 5, 15, 21 }, { 6, 0, 2 }, { 6, 4, 5 }, { 6, 10, 11 },
    { 6, 15, 21 }, { 7, 0, 1 }, { 7, 4, 5 }, { 7, 10, 11 }, { 7, 15, 16 }, { 7, 20, 21 }, { 8, 0, 1 }, { 9, 0, 1 },
    { 9, 4, 5 }, { 9, 10, 11 }, { 9, 15, 16 }, { 9, 20, 21 }, { 10, 0, 2 }, { 10, 4, 5 }, { 10, 10, 11 },
    { 10, 15, 21 }, { 11, 0, 2 }, { 11, 4, 5 }, { 11, 10, 11 }, { 11, 15, 21 }, { 12, 0, 2 }, { 12, 4, 5 },
    { 12, 10, 25 }, { 13, 0, 1 }, { 13, 4, 5 }, { 13, 10, 25 }, { 14, 0, 25 }, { 15, 0, 25 }, { 16, 0, 25 },
  }
  local SOOTOPOLIS_ROCKS = { { 8, 7 }, { 12, 7 }, { 3, 9 }, { 11, 9 }, { 6, 13 }, { 9, 14 }, { 9, 17 }, { 7, 19 } }
  local SOOTOPOLIS_B1F_RUNS = {
    { 0, 9, 11 }, { 0, 14, 16 }, { 0, 18, 20 }, { 1, 4, 11 }, { 1, 14, 16 }, { 1, 18, 20 }, { 2, 4, 11 },
    { 2, 14, 16 }, { 2, 18, 20 }, { 3, 4, 5 }, { 3, 10, 16 }, { 3, 18, 25 }, { 4, 4, 5 }, { 4, 10, 16 },
    { 4, 18, 25 }, { 5, 4, 5 }, { 5, 10, 11 }, { 5, 15, 21 }, { 6, 4, 5 }, { 6, 10, 11 }, { 6, 15, 21 },
    { 7, 4, 5 }, { 7, 10, 11 }, { 7, 15, 16 }, { 7, 20, 21 }, { 8, 4, 5 }, { 9, 4, 5 }, { 9, 10, 11 },
    { 9, 15, 16 }, { 9, 20, 21 }, { 10, 4, 5 }, { 10, 10, 11 }, { 10, 15, 21 }, { 11, 4, 5 }, { 11, 10, 11 },
    { 11, 15, 21 }, { 12, 4, 5 }, { 12, 10, 16 }, { 12, 18, 25 }, { 13, 4, 5 }, { 13, 10, 16 }, { 13, 18, 25 },
    { 14, 4, 11 }, { 14, 14, 16 }, { 14, 18, 20 }, { 15, 4, 11 }, { 15, 14, 16 }, { 15, 18, 20 }, { 16, 9, 11 },
    { 16, 14, 16 }, { 16, 18, 20 },
  }
  local function sootopolisGym1f()
    local tiers = { 4, 10, 15, 20 }
    local out = H.rectPieces("walls", H.cutRuns(SOOTOPOLIS_1F_RUNS, tiers), 16,
      { leave = SOOTOPOLIS_ICE, whole = true, per = H.tierTops(tiers) })
    for _, c in ipairs(SOOTOPOLIS_ROCKS) do
      out[#out + 1] = piece(("rock_%d_%d"):format(c[1], c[2]), H.cellsRects({ c }), 10, { leave = SOOTOPOLIS_ICE })
    end
    for _, p in ipairs(statue("statue_w", 96, 368)) do out[#out + 1] = p end
    for _, p in ipairs(statue("statue_e", 160, 368)) do out[#out + 1] = p end
    return ownShell(out)
  end
  local function sootopolisGymB1f()
    local tiers = { 10, 15, 20 }
    return ownShell(H.rectPieces("wall", H.cutRuns(SOOTOPOLIS_B1F_RUNS, tiers), 16,
      { leave = { "ffffff", "def6ff", "000000" }, solid = true, side = function() return "cell" end, whole = true,
        per = H.tierTops(tiers) }))
  end
  add("rs_sootopolis_gym_1f", "LAYOUT_SOOTOPOLIS_CITY_GYM_1F", { 0x20d }, sootopolisGym1f())
  add("rs_sootopolis_gym_b1f", "LAYOUT_SOOTOPOLIS_CITY_GYM_B1F", { 0x211 }, sootopolisGymB1f())

  -- ── Emerald 3DS's rooms that read Ruby's drawing as they read Emerald's ────────
  -- (each proved by room_check against Ruby's: as few pixels wrong as Emerald's own, or fewer; a
  -- layout Ruby names after another map, or one Ruby has its own name for, by that name):
  -- the Mart (every town's), Brendan's 2F and May's house (Emerald redrew a few cells of each),
  -- Rustboro's flat and Devon's 3F, Lilycove's elevator and Slateport's fan club, Mossdeep's game
  -- corner, the Pokemon League's lobby and its corridors (Ruby's Corridor1 is Emerald's short hall,
  -- its Corridor4 Emerald's Hall4), the Battle Tower's corridor, battle room and elevator (Emerald's
  -- Frontier tower's), the link colosseums, Trick House puzzle 5, and the contest lobby of
  -- Fallarbor, Verdanturf and Slateport (Emerald's Battle Tent lobby, the same room)
  local ADOPTED = {
    { "mart", "LAYOUT_OLDALE_TOWN_MART" }, { "brendan_2f" }, { "may_1f" }, { "may_2f" }, { "rustboro_city_flat1_2f" },
    { "rustboro_city_devon_corp_3f" }, { "dept_store_elevator" }, { "slateport_fan_club" }, { "mossdeep_game_corner_1f" },
    { "league_1f", "LAYOUT_EVER_GRANDE_CITY_POKEMON_LEAGUE" }, { "league_hall", "LAYOUT_EVER_GRANDE_CITY_CORRIDOR1" },
    { "league_hall4", "LAYOUT_EVER_GRANDE_CITY_CORRIDOR4" },
    { "frontier_tower_corridor", "LAYOUT_BATTLE_TOWER_CORRIDOR" },
    { "frontier_tower_battle_room", "LAYOUT_BATTLE_TOWER_BATTLE_ROOM" }, { "battle_elevator", "LAYOUT_BATTLE_TOWER_ELEVATOR" },
    { "battle_colosseum_2p", "LAYOUT_SINGLE_BATTLE_COLOSSEUM" }, { "battle_colosseum_4p", "LAYOUT_DOUBLE_BATTLE_COLOSSEUM" },
    { "trick_house_puzzle5" }, { "tent_lobby", "LAYOUT_FALLARBOR_TOWN_CONTEST_LOBBY" },
  }
  for _, t in ipairs(ADOPTED) do adopt(t[1], t[2] and { layout = t[2] } or nil) end

  -- ── the Trick House's puzzle rooms ────────────────────────────────────────────
  -- Ruby's own mazes, read as Emerald 3DS reads Emerald's: each a map of its partitions (the cells
  -- the player cannot walk, rows 2-21, as Emerald 3DS's maps are Emerald's), standing at Emerald's
  -- heights for the same kind of partition, in the room's shell (Emerald's: the same walls); the
  -- eighth's jars on its sand, each a cell's jar turned on a lathe.
  local RS_TRICK_PUZZLES = {
    [1] = { 12, [[
############...
..#...#....#...
...............
..#...#....#...
.##############
....#....#.....
....#.........#
....#....#.....
##.###.########
...#...#....#..
.......#.......
...#...#....#..
.#############.
.....#....#....
.....#.........
.....#....#....
###.########.##
.......#.......
.......#.......
...............
]] },
    [2] = { 6, [[
.#..#..........
.#.######......
.#.#....#.#####
.#...##.###.#.#
.###.#....#.###
...#.#....#....
##.#.#.#######.
...#.#.....#...
...#.##.#.##.##
##.###..#......
.#...#.##.####.
.###.###..#.#..
...#...####.###
##.###.#....#..
.....#.###..#..
.#.#.#...#.....
.#.#.#####.###.
.#.#...#....#..
...#####.##.##.
..........#..#.
]] },
    [3] = { 12, [[
#..#..#..#..#..
#..#..#..#..#..
#..#..#..#..#..
...#.....#.....
#..#..#..####..
#..####..####..
#........#.....
####..#..#..#..
####..#..#..#..
...#..#..#.....
#..#..#..#..#..
#..#..#######..
......#.....#..
#..####..#..#..
#######..#..#..
......#.....#..
#..#..#..#..###
#..#..#..######
...............
...............
]] },
    [4] = { 6, [[
...............
...#######.....
...#....##.....
#..##....#.....
#####....#####.
.......#.....#.
..######.....#.
......##.......
.#.....#.#####.
##.###.#.#.#...
.#...#.#.#..##.
##.#.#.#.......
........#.#.##.
...#.#.#..#....
...#...#..#....
.##############
...............
...............
...............
...............
]] },
    [6] = { 6, [[
.....#.#.#....#
.......#.#.#.##
.....#.#.#.#.##
.....#.#.#...##
##.#.#.#.#..###
#....#.#.#..###
#...##.....#...
#.#.###....#.#.
#.#...######...
..###..........
....#..........
..#.###..#.####
#.#..##..#.####
#....##......##
#....##......##
##.####..###.##
.#...##..###..#
.....##..###..#
..............#
.....##....####
]] },
    [7] = { 6, [[
.......##.#....
........#......
....#.....#....
##.....#..#....
...............
...........#.#.
.#.#.#.####....
...............
.....#.........
....#.......#..
....#........#.
.............#.
...............
...............
............#..
...............
...##..........
...............
...............
...............
]] },
  }
  local RS_TRICK_JARS = [[
############..#
...........#..#
...............
#..............
..........#....
...#.......#...
.......#.....#.
....#....##....
.#####.########
....##.##..#...
###.######.###.
.....#.........
.#..........#..
.............#.
#..............
...............
.........#....#
....#.......#..
..##########...
....#######....
]]
  for n = 1, 7 do
    local p = RS_TRICK_PUZZLES[n]
    if p then
      add("rs_trick_house_puzzle" .. n, "LAYOUT_ROUTE110_TRICK_HOUSE_PUZZLE" .. n, { 0x208 },
        ownShell(H.cat(H.rectPieces("partition", H.runsOf(H.cellsOf(H.rowsOf(p[2]), "#", 2)), p[1]), H.trickHouseShell())))
    end
  end
  do
    local out = {}
    for _, c in ipairs(H.cellsOf(H.rowsOf(RS_TRICK_JARS), "#", 0)) do
      local x, y = c[1], c[2]
      out[#out + 1] = piece(("jar_%d_%d"):format(x, y + 2), { { x * 16 + 2, y * 16 + 33, x * 16 + 14, y * 16 + 47 } }, 9,
        { round = "lathe", leave = H.TRICK_JAR_FLOOR })
    end
    add("rs_trick_house_puzzle8", "LAYOUT_ROUTE110_TRICK_HOUSE_PUZZLE8", { 0x26b }, ownShell(H.cat(out, H.trickHouseShell())))
  end

  return ROOMS
end
