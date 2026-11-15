-- Ruby's and Sapphire's own rooms (Battle Scene: Overworld): the rooms they draw otherwise than
-- Emerald - Emerald redrew every gym - read by src/scene/models/interiors.lua, in the format of
-- interior_specs.lua. Each takes the place of Emerald 3DS's room of the same layout (main.lua);
-- Emerald's hold wherever Ruby and Sapphire draw Emerald's maps (src/scene/prints.lua).
--
-- WoobleView's own reading, by Emerald 3DS's method and with its helpers (interior_specs.lua's
-- `helpers`): each piece a shape of the room's drawing, its front `height` rows standing at its
-- drawn foot. Every number is read off Ruby's drawing (Sapphire's rooms are Ruby's, tile for tile):
-- pixels, colours and cells only. Each room is checked by tests/drivers/room_check.lua.

return function(H)
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

  return ROOMS
end
