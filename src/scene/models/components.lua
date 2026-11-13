-- Objects of no fixed shape (Battle Scene: Overworld): hedges, fences, curbs, railings, walls,
-- crates. A spec names the metatiles that draw the object; every connected run of them on the map
-- becomes its own model, read off its own drawing: a Relief (column by column: a top and a front
-- `height` rows tall) or a fence built post by post (src/scene/models/fence.lua).
--
-- Ported from Emerald 3DS's scripts/voxel_building_specs.py (the `components` specs, numbers
-- unchanged) and gen_voxel_buildings.py (component_specs, building_art, close_gaps, trim_outline,
-- join_corners, fill_behind, pick_side, flank_band, clear_rgb), by Zallax and contributors,
-- CC BY-NC-SA 4.0 (https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes: a run is
-- found in the window around the battle and built whole (not cut into blocks); colours are
-- compared at the GBA's 5 bits a channel (the generator's are the decomp's 8-bit palettes).

return function(K, Fence)
  local C = {}
  local GRASS = 0x001
  local floor, max, min = math.floor, math.max, math.min

  local function set(list)
    local o = {}
    for _, v in ipairs(list) do o[v] = true end
    return o
  end
  -- a colour at 5 bits a channel
  local function key5(r, g, b) return floor(r * 31 + 0.5) * 1024 + floor(g * 31 + 0.5) * 32 + floor(b * 31 + 0.5) end
  local function rgb(list)
    local o = {}
    for _, c in ipairs(list) do o[key5(c[1] / 255, c[2] / 255, c[3] / 255)] = true end
    return o
  end
  C.key5 = key5

  local SOOTOPOLIS_WALL = { 0x240, 0x241, 0x242, 0x246, 0x247, 0x25C, 0x26E, 0x26F, 0x254, 0x255, 0x25E, 0x25F, 0x256, 0x25D }
  local SOOTOPOLIS_GROUND = { 0x2D9, 0x2E1, 0x2E2, 0x2D3, 0x2DA }
  local SOOTOPOLIS_ROCK = { { 205, 205, 189 }, { 222, 222, 213 }, { 246, 246, 238 }, { 148, 148, 123 }, { 172, 172, 156 }, { 131, 131, 139 } }

  -- tileset names as the engine's pairs spell them, lower case without underscores
  -- (gTileset_BattleFrontierOutsideWest, battle_frontier_outside_west: battlefrontieroutsidewest)
  C.SPECS = {
    { name = "frontier_planter_west", secondary = "battlefrontieroutsidewest",
      tiles = set({ 0x208, 0x209, 0x20A, 0x210, 0x211, 0x212, 0x218, 0x219, 0x21A }), height = 6,
      ground = { 0x05E, 0x05D, 0x05F } },
    { name = "frontier_planter_east", secondary = "battlefrontieroutsideeast",
      tiles = set({ 0x2C8, 0x2CB, 0x2F7, 0x2D0, 0x2CC, 0x2FF, 0x2C9, 0x2CD, 0x307 }), height = 6,
      ground = { 0x05E, 0x101, 0x109 } },
    { name = "hedge", secondary = "petalburg",
      tiles = set({ 0x23c, 0x23d, 0x23e, 0x23f, 0x244, 0x245, 0x246, 0x24c, 0x24d, 0x24e, 0x254, 0x255, 0x256, 0x264, 0x265, 0x266 }),
      height = 11,
      clean = { [0x24d] = 0x23d, [0x24e] = 0x23d, [0x255] = 0x23c, [0x256] = 0x23e, [0x244] = 0x24c, [0x246] = 0x24c },
      joins = { [0x244] = 1, [0x246] = -1 },
      under = { [0x23d] = 0x245 },
      side_longest = true, close = 2, outline = { 57, 82, 0 },
      ground = { GRASS } },
    { name = "railing", secondary = "rustboro",
      tiles = set({ 0x2A7, 0x2FC, 0x318, 0x319, 0x31A, 0x315, 0x31D, 0x320, 0x321, 0x32C, 0x32D, 0x2BE, 0x2BF, 0x2CD, 0x352, 0x2E9,
                    0x2B7, 0x2C6, 0x2C7, 0x2D5, 0x2D7, 0x2DC, 0x2DE, 0x2DF, 0x2E6, 0x2E7, 0x2EC, 0x31B }),
      height = 12, hull = 12, bridge = 3, upper = true, flank = 0x2A7,
      ground = { 0x2BB, 0x2C3, GRASS } },
    { name = "fence", primary = "general",
      tiles = set({ 0x132, 0x133, 0x134, 0x138, 0x139, 0x13A, 0x140, 0x141, 0x142, 0x148, 0x149, 0x14A }),
      also = {
        battlefrontieroutsideeast = set({ 0x24D, 0x255, 0x25D, 0x26D, 0x27D, 0x320, 0x322, 0x324, 0x3D7, 0x3E5, 0x3E7 }),
        battlefrontieroutsidewest = set({ 0x22F, 0x286, 0x28E, 0x296, 0x29E, 0x2A6, 0x2E5, 0x2E8, 0x2ED, 0x2F0, 0x2F4, 0x2F5,
                                          0x2F8, 0x2FC, 0x2FD, 0x300, 0x304, 0x308, 0x30C }),
        mauville = set({ 0x323, 0x34D, 0x34E, 0x381, 0x3B0 }),
        lavaridge = set({ 0x285, 0x286, 0x287, 0x28D, 0x28E, 0x28F, 0x293, 0x294, 0x296, 0x297 }),
      },
      upper = true,
      posts = { kind = "box", ref = 0x149, find = { 2, 3, 4, 2 }, post = { 2, 6 }, top = 3, depth = 2,
                scan = 3, hidden = 10, rail = { 4, 6 }, body = { 2, 3, 6, 13 }, trunk = { 2, 5, 6, 13 }, strip = { 3, 5, 5, 13 } },
      ground = { GRASS } },
    { name = "railing_lilycove", secondary = "lilycove",
      tiles = set({ 0x249, 0x250, 0x251, 0x252, 0x258, 0x25A }),
      height = 12, hull = 12, bridge = 3, upper = true, flank = 0x251,
      ground = { GRASS } },
    { name = "curb", primary = "general",
      tiles = set({ 0x03D, 0x03E, 0x03F, 0x045, 0x047, 0x04D, 0x04E, 0x04F, 0x055, 0x056, 0x057, 0x05D, 0x05E, 0x05F }),
      height = 3, fill = set({ 0x05E }),
      skip = set({ "battlefrontieroutsidewest", "battlefrontieroutsideeast" }),
      ground = { GRASS, 0x001 } },
    { name = "stakes", secondary = "mauville",
      tiles = set({ 0x273, 0x27A, 0x27B, 0x27C, 0x27D, 0x280, 0x282, 0x288, 0x28A, 0x290, 0x291, 0x292, 0x2B1, 0x2B2, 0x2B9, 0x2BA }),
      upper = true,
      posts = { kind = "log", ref = 0x291, find = { 1, 5, 5, 2 }, log = { 3.5, 2.5, 2.0 }, top = 6,
                scan = 3, trunk_row = 8, hidden = 7, sides = 16, body = { 1, 4, 6, 14 }, trunk = { 1, 8, 6, 14 }, strip = { 1, 8, 6, 14 } },
      ground = { GRASS } },
    { name = "sootopolis_wall", secondary = "sootopolis", tiles = set(SOOTOPOLIS_WALL), height = 8,
      ground = SOOTOPOLIS_GROUND, ground_rgb = rgb(SOOTOPOLIS_ROCK) },
    { name = "spring_rim", secondary = "lavaridge",
      tiles = set({ 0x299, 0x29A, 0x29B, 0x2A1, 0x2A5, 0x2A9, 0x2AD, 0x2B1, 0x2B2, 0x2B3, 0x2B4, 0x2B5 }), height = 4,
      ground = { 0x2A3, 0x31D, 0x2A8, 0x2BC } },
    { name = "spring_bench", secondary = "lavaridge", tiles = set({ 0x29C, 0x29E }), height = 4,
      ground = { 0x2A8, 0x274, 0x2AE } },
    { name = "slateport_curb", secondary = "slateport",
      tiles = set({ 0x245, 0x24D, 0x255, 0x25D, 0x2FF, 0x2FE, 0x23C, 0x234, 0x2CF }), height = 3,
      ground = { 0x202 },
      ground_rgb = rgb({ { 65, 180, 131 }, { 115, 197, 164 }, { 164, 213, 197 }, { 205, 205, 222 }, { 230, 230, 238 } }) },
    { name = "crate", secondary = "slateport", tiles = set({ 0x33E, 0x33F }), height = 8, upper = true, ground = { 0x211 } },
    { name = "crate_stack", secondary = "slateport", tiles = set({ 0x32E, 0x32F, 0x336, 0x337 }), height = 24, upper = true,
      ground = { 0x211 } },
    { name = "flower_crate", secondary = "slateport", tiles = set({ 0x20B, 0x28D, 0x213, 0x214 }), height = 3, upper = true,
      ground = { 0x211 } },
  }

  local function norm(s) return (s or ""):lower():gsub("_", "") end
  --- A pair's primary and secondary names (normalised).
  function C.names(pair)
    if type(pair) ~= "string" then return nil end
    local p, s = pair:match("^(.-)__(.*)$")
    if not p then return norm(pair), "" end
    return norm(p), norm(s)
  end

  -- the spec's tiles in a pair (with its `also`), or nil when the spec is not drawn by it
  local function tilesIn(spec, pair)
    local p, s = C.names(pair)
    if not p then return nil end
    if spec.skip and spec.skip[s] then return nil end
    if spec.primary and spec.primary ~= p then return nil end
    if spec.secondary and spec.secondary ~= s then return nil end
    local extra = spec.also and spec.also[s]
    if not extra then return spec.tiles end
    local all = {}
    for m in pairs(spec.tiles) do all[m] = true end
    for m in pairs(extra) do all[m] = true end
    return all
  end
  C.tilesIn = tilesIn

  --- Every run of every spec's metatiles in the grid (src/scene/cells.lua), skipping cells a
  --- building already stands on: { spec, pair, x0, y0, w, h, owned = { ["i,j"] = true }, cells }.
  function C.find(grid, specs)
    specs = specs or C.SPECS
    local runs = {}
    local seen = {}
    for _, spec in ipairs(specs) do
      for j = 0, grid.h - 1 do
        for i = 0, grid.w - 1 do
          local cell = grid.rows[j][i]
          local k = spec.name .. ":" .. cell.cx .. "," .. cell.cy
          local tiles = cell.mid and not cell.model and not seen[k] and tilesIn(spec, cell.pair)
          if tiles and tiles[cell.mid] then
            local pair = cell.pair
            local todo, cells = { cell }, {}
            seen[k] = true
            while #todo > 0 do
              local c = table.remove(todo)
              cells[#cells + 1] = c
              for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local n = grid.at(c.cx + d[1], c.cy + d[2])
                local nk = n and (spec.name .. ":" .. n.cx .. "," .. n.cy)
                if n and not seen[nk] and not n.model and n.pair == pair and n.mid and tiles[n.mid] then
                  seen[nk] = true
                  todo[#todo + 1] = n
                end
              end
            end
            local allFill = spec.fill ~= nil
            for _, c in ipairs(cells) do if not (spec.fill and spec.fill[c.mid]) then allFill = false end end
            if not allFill then
              local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
              for _, c in ipairs(cells) do
                x0, y0, x1, y1 = min(x0, c.cx), min(y0, c.cy), max(x1, c.cx), max(y1, c.cy)
              end
              local owned = {}
              for _, c in ipairs(cells) do owned[(c.cx - x0) .. "," .. (c.cy - y0)] = true end
              runs[#runs + 1] = { spec = spec, pair = pair, x0 = x0, y0 = y0, w = x1 - x0 + 1, h = y1 - y0 + 1,
                                  owned = owned, cells = cells }
            end
          end
        end
      end
    end
    return runs
  end

  -- ── art ──

  local function newArt(w, h)
    local px = {}
    for i = 1, w * h * 4 do px[i] = 0 end
    return { w = w, h = h, px = px }
  end
  local function opaque(a, u, v) return u >= 0 and v >= 0 and u < a.w and v < a.h and a.px[(v * a.w + u) * 4 + 4] >= 0.5 end
  local function getP(a, u, v)
    local o = (v * a.w + u) * 4
    return a.px[o + 1], a.px[o + 2], a.px[o + 3], a.px[o + 4]
  end
  local function setP(a, u, v, r, g, b, al)
    local o = (v * a.w + u) * 4
    a.px[o + 1], a.px[o + 2], a.px[o + 3], a.px[o + 4] = r, g, b, al
  end
  local function clear(a, u, v) setP(a, u, v, 0, 0, 0, 0) end

  -- the ground's lower-layer quarters and pixels, as building_art tests them
  local function groundOf(src, ground)
    local quarters, pixels = {}, {}
    for _, g in ipairs(ground) do
      if src.under(g, 0, 0) ~= nil then
        local pix = {}
        for q = 0, 3 do
          local parts = {}
          for k = 0, 63 do
            local lx, ly = (q % 2) * 8 + k % 8, floor(q / 2) * 8 + floor(k / 8)
            local c = key5(src.under(g, lx, ly))
            parts[k + 1] = c
            pix[ly * 16 + lx] = c
          end
          quarters[table.concat(parts, ",")] = true
        end
        pixels[#pixels + 1] = pix
      end
    end
    return quarters, pixels
  end

  --- building_art: an art image of cells (absolute map cells, mid(x, y) their metatile), every
  --- ground pixel clear. o = { quarters, pixels (ground_px: or nil), upper, swap }
  function C.compose(src, x0, y0, w, h, cells, mid, o)
    local img = newArt(w * 16, h * 16)
    for _, c in ipairs(cells) do
      local cx, cy = c[1] - x0, c[2] - y0
      local m = mid(c[1], c[2])
      if m and o.swap and o.swap[m] then m = o.swap[m] end
      if m and cx >= 0 and cy >= 0 and cx < w and cy < h and src.under(m, 0, 0) ~= nil then
        for q = 0, 3 do
          local parts = {}
          for k = 0, 63 do
            local lx, ly = (q % 2) * 8 + k % 8, floor(q / 2) * 8 + floor(k / 8)
            parts[k + 1] = key5(src.under(m, lx, ly))
          end
          local isGround = o.quarters[table.concat(parts, ",")] == true
          for k = 0, 63 do
            local lx, ly = (q % 2) * 8 + k % 8, floor(q / 2) * 8 + floor(k / 8)
            local X, Y = cx * 16 + lx, cy * 16 + ly
            local r1, g1, b1, a1 = src.over(m, lx, ly)
            if a1 and a1 > 0.5 then
              setP(img, X, Y, r1, g1, b1, 1)
            elseif not o.upper and not isGround then
              local keep = true
              if o.pixels then
                for _, gp in ipairs(o.pixels) do if gp[ly * 16 + lx] == parts[k + 1] then keep = false; break end end
              end
              if keep then
                local r0, g0, b0 = src.under(m, lx, ly)
                setP(img, X, Y, r0, g0, b0, 1)
              end
            end
          end
        end
      end
    end
    return img
  end

  -- give back the object's pixels the ground test took inside it
  local function closeGaps(art, drawn, gap)
    local holes = {}
    for u = 0, art.w - 1 do
      for v = 0, art.h - 1 do
        if not opaque(art, u, v) and opaque(drawn, u, v) then
          local up, down = false, false
          for k = 1, gap do
            if v - k >= 0 and opaque(art, u, v - k) then up = true end
            if v + k < art.h and opaque(art, u, v + k) then down = true end
          end
          if up and down then holes[#holes + 1] = { u, v } end
        end
      end
    end
    for _, h in ipairs(holes) do setP(art, h[1], h[2], getP(drawn, h[1], h[2])) end
  end

  -- take off what lies past the object's own dark outline (a hedge's shadow on the lawn)
  local function trimOutline(art, colour, reach)
    reach = reach or 2
    local mark = key5(colour[1] / 255, colour[2] / 255, colour[3] / 255)
    local out = {}
    local function line(points)
      local k = 1
      while k <= #points do
        local p = points[k]
        if not opaque(art, p[1], p[2]) then
          k = k + 1
        else
          local run = {}
          while k <= #points and opaque(art, points[k][1], points[k][2]) do
            run[#run + 1] = points[k]
            k = k + 1
          end
          local marks = {}
          for i, q in ipairs(run) do
            local r, g, b = getP(art, q[1], q[2])
            if key5(r, g, b) == mark then marks[#marks + 1] = i end
          end
          if #marks > 0 then
            local tail1, tail2 = {}, {}
            for i = marks[#marks] + 1, #run do tail1[#tail1 + 1] = run[i] end
            for i = 1, marks[1] - 1 do tail2[#tail2 + 1] = run[i] end
            for _, t in ipairs({ tail1, tail2 }) do
              if #t > 0 and #t <= reach then for _, q in ipairs(t) do out[#out + 1] = q end end
            end
          end
        end
      end
    end
    for v = 0, art.h - 1 do
      local pts = {}
      for u = 0, art.w - 1 do pts[#pts + 1] = { u, v } end
      line(pts)
    end
    for u = 0, art.w - 1 do
      local pts = {}
      for v = 0, art.h - 1 do pts[#pts + 1] = { u, v } end
      line(pts)
    end
    for _, q in ipairs(out) do clear(art, q[1], q[2]) end
  end

  -- an arm's inner corner drawn straight: the run turning into it goes on into the gap
  local function joinCorners(run, art, mid)
    local spec = run.spec
    for key in pairs(run.owned) do
      local i, j = key:match("(-?%d+),(-?%d+)")
      i, j = tonumber(i), tonumber(j)
      local side = spec.joins[mid(run.x0 + i, run.y0 + j)]
      if side and i + side >= 0 and i + side < run.w then
        local edge = (i + side) * 16 + (side < 0 and 15 or 0)
        local finish = 0
        while finish < 16 and opaque(art, edge, j * 16 + finish) do finish = finish + 1 end
        for r = 0, finish - 1 do
          for k = 1, 3 do
            local u, v = edge - side * k, j * 16 + r
            if not opaque(art, u, v) or r < finish - spec.height - 1 then setP(art, u, v, getP(art, edge, v)) end
          end
        end
      end
    end
  end

  -- a run that goes on behind a building: drawn on under the roof as it is in the open
  local function fillBehind(run, art, drawn, src, mid, quarters, pixels)
    local spec = run.spec
    local groundSet = set(spec.ground)
    local swap = spec.clean or {}
    for key in pairs(run.owned) do
      local i, j = key:match("(-?%d+),(-?%d+)")
      i, j = tonumber(i), tonumber(j)
      if not run.owned[i .. "," .. (j + 1)] and j + 1 < run.h then
        local X, Y = run.x0 + i, run.y0 + j
        local south = mid(X, Y + 1)
        if south and not spec.tiles[south] and not groundSet[south] then
          local m = mid(X, Y)
          local below = spec.under and spec.under[swap[m] or m]
          if below then
            local v = j * 16 + 15
            local cut = false
            for u = i * 16, i * 16 + 15 do
              local n = 0
              while v - n >= 0 and opaque(art, u, v - n) do n = n + 1 end
              if n > 0 and n < spec.height then cut = true end
            end
            if cut then
              for _, pass in ipairs({ { art, pixels }, { drawn, nil } }) do
                local cell = C.compose(src, X, Y + 1, 1, 1, { { X, Y + 1 } }, mid,
                  { quarters = quarters, pixels = pass[2], swap = { [south] = below } })
                for cv = 0, 15 do
                  for cu = 0, 15 do
                    if opaque(cell, cu, cv) then setP(pass[1], i * 16 + cu, (j + 1) * 16 + cv, getP(cell, cu, cv)) end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- an 8-column tile of the object's own drawn front, for the faces the drawing never shows
  local function pickSide(art, height, longest)
    local W, Hh = art.w, art.h
    local ends = {}
    for u = 0, W - 1 do
      local finish
      for v = Hh - 1, 0, -1 do if opaque(art, u, v) then finish = v + 1; break end end
      local full = finish ~= nil and finish >= height
      if full then
        for v = finish - height, finish - 1 do if not opaque(art, u, v) then full = false; break end end
      end
      ends[u] = full and finish or false
    end
    if longest then
      local best
      local u = 0
      while u < W do
        local k = u
        while k < W and ends[u] and ends[k] == ends[u] do k = k + 1 end
        if ends[u] and (not best or k - u > best[2] - best[1]) then best = { u, k } end
        u = max(k, u + 1)
      end
      if best and best[2] - best[1] >= 8 then
        local a, b = best[1] + 2, best[2] - 2
        local width = min(8, b - a)
        local uu = floor((a + b - width) / 2)
        local e = ends[uu]
        return K.Tile(uu, e - height, uu + width, e)
      end
    end
    for _, width in ipairs({ 8, 6, 4 }) do
      local best
      for u = 0, W - width do
        local e = ends[u]
        if e then
          local ok = true
          for k = 0, width - 1 do if ends[u + k] ~= e then ok = false; break end end
          if ok and (not best or e > best[2]) then best = { u, e } end
        end
      end
      if best then return K.Tile(best[1], best[2] - height, best[1] + width, best[2]) end
    end
    local best, score = { 0, 0 }, -1
    for v = 0, max(1, Hh - height + 1) - 1 do
      for u = 0, max(1, W - 4 + 1) - 1 do
        local n = 0
        for i = 0, min(4, W) - 1 do
          for j = 0, min(height, Hh) - 1 do if opaque(art, u + i, v + j) then n = n + 1 end end
        end
        if n > score then best, score = { u, v }, n end
      end
    end
    return K.Tile(best[1], best[2], best[1] + min(4, W), best[2] + min(height, Hh))
  end

  -- a railing down a column shows the bars of the same railing along a row: that metatile's upper
  -- layer appended below the art
  local function flankBand(art, src, m, height)
    local rows = height + 2
    local out = newArt(art.w, art.h + rows)
    for v = 0, art.h - 1 do for u = 0, art.w - 1 do setP(out, u, v, getP(art, u, v)) end end
    for v = 16 - rows, 15 do
      for u = 0, 15 do
        local r, g, b, a = src.over(m, u, v)
        if a and a > 0.5 and u < out.w then setP(out, u, art.h + v - (16 - rows), r, g, b, 1) end
      end
    end
    return out, K.Tile(0, art.h, 16, art.h + rows)
  end

  --- A run's model: { art (its texture), parts } or nil.
  ---   src      the run's pair's layers (src.under / src.over)
  ---   mid(x, y) the map's metatile at an absolute cell
  ---   refSrc(m) a pair's layers that draw metatile m of the run's primary (a fence's reference)
  function C.build(run, src, mid, refSrc)
    local spec = run.spec
    local quarters, pixels = groundOf(src, spec.ground)
    local cells = {}
    for _, c in ipairs(run.cells) do cells[#cells + 1] = { c.cx, c.cy } end
    if spec.posts then
      local fam = spec.posts
      local rs = refSrc(fam.ref)
      if not rs then return nil end
      local ref = newArt(16, 16)
      for v = 0, 15 do
        for u = 0, 15 do
          local r, g, b, a = rs.over(fam.ref, u, v)
          if a and a > 0.5 then setP(ref, u, v, r, g, b, 1) end
        end
      end
      local compose = function(keep)
        local img = newArt(run.w * 16, (run.h + 2) * 16)
        for _, c in ipairs(cells) do
          local i, j = c[1] - run.x0, c[2] - run.y0 + 1
          local m = mid(c[1], c[2])
          if m and src.under(m, 0, 0) ~= nil then
            for y = 0, 15 do
              for x = 0, 15 do
                local r1, g1, b1, a1 = src.over(m, x, y)
                if a1 and a1 > 0.5 then
                  setP(img, i * 16 + x, j * 16 + y, r1, g1, b1, 1)
                else
                  local r0, g0, b0 = src.under(m, x, y)
                  local r, g, b = r0, g0, b0
                  -- (the fence's colour keys are the fence module's 8-bit ones)
                  if keep[floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5)] then
                    setP(img, i * 16 + x, j * 16 + y, r, g, b, 1)
                  end
                end
              end
            end
          end
        end
        return img
      end
      local built = Fence.build(run.w, run.h, run.owned, compose, ref, fam)
      return { art = built.tex, parts = built.parts }
    end
    local art = C.compose(src, run.x0, run.y0, run.w, run.h, cells, mid,
      { quarters = quarters, pixels = pixels, upper = spec.upper, swap = spec.clean })
    if spec.close or spec.under then
      local drawn = C.compose(src, run.x0, run.y0, run.w, run.h, cells, mid, { quarters = quarters, swap = spec.clean })
      if spec.under then fillBehind(run, art, drawn, src, mid, quarters, pixels) end
      if spec.joins then joinCorners(run, art, mid) end
      if spec.close then closeGaps(art, drawn, spec.close) end
    end
    if spec.outline then trimOutline(art, spec.outline) end
    if spec.ground_rgb then
      for v = 0, art.h - 1 do
        for u = 0, art.w - 1 do
          if opaque(art, u, v) and spec.ground_rgb[key5(getP(art, u, v))] then clear(art, u, v) end
        end
      end
    end
    local side = pickSide(art, spec.height, spec.side_longest)
    local flank
    if spec.flank then art, flank = flankBand(art, src, spec.flank, spec.height) end
    local relief = K.Relief("relief", art, spec.height, side, { hull = spec.hull, bridge = spec.bridge,
      seam = { run.h * 16, {}, {} }, flank_tile = flank })
    return { art = art, parts = { relief } }
  end

  return C
end
