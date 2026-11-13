-- Signposts (Battle Scene: Overworld): signs, lamps, posts and boulders standing as thin solids of
-- their own pixels.
--
-- A sign metatile draws the post over the ground it stands on. Its upper layer is the sign; on its
-- lower layer a pixel is ground when its colour is one the clean walkable cells beside it draw on
-- theirs. What remains, closed off from the cell's border by a flood fill, is the sign's
-- silhouette. A lamp's lantern (a gym sign's round top) is drawn in the cell north of it: the
-- upper-layer pixels there joined to the sign's top row. Each 8-connected piece stands on its own
-- bottom, two pixels thick, in the depth band of that bottom's half cell; its cell is laid with the
-- ground round it, the head's cell with its own ground.
--
-- A signpost is a blocked cell outdoors with walkable ground west, east and south, no tree, no
-- building's (nor beside one), and not a run of one drawing down a column (a fence's); and one
-- drawn as such a post is (its metatile, or its upper layer pixel for pixel) wherever it stands
-- with walkable ground south of it (a sign against a wall); and a lamp drawn as a free one is
-- (its post and its lantern), against a wall on one side.
--
-- Adapted from Emerald 3DS (3ds_port/scripts/voxel_sign_mask.py, gen_voxel_sign_masks.py,
-- src/voxel/voxel_sign.c; voxel_cells.py's signposts; by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE). Changes here: found in the game over the
-- window around the battle (no sign events: by shape alone), drawn from a texture of their own.
--
-- Plain Lua over a grid of src/scene/cells.lua and:
--   opt.isWall(coll)
--   opt.layers(mid, pair) -> lower, upper: { [y * 16 + x] = { r, g, b } } of each layer's drawn
--                            pixels (0..1), or nil
--   opt.stands(mid, pair)   a tree's metatile (src/scene/init.lua), never a sign

local Signs = {}

Signs.DEPTH = 2            -- pixels thick
Signs.HEAD_MAX_WIDTH = 15
Signs.HEAD_MAX_PIXELS = 160
Signs.FOLIAGE = 0.5

local floor = math.floor

local function key(c) return floor(c[1] * 255 + 0.5) * 65536 + floor(c[2] * 255 + 0.5) * 256 + floor(c[3] * 255 + 0.5) end

--- Rows of bits: the pixels (set, index y * 16 + x) not reachable from the border through empty ones.
function Signs.cutout(solid, w, h)
  w, h = w or 16, h or 16
  local outside, queue = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if x == 0 or y == 0 or x == w - 1 or y == h - 1 then queue[#queue + 1] = y * w + x end
    end
  end
  local q = 1
  while q <= #queue do
    local p = queue[q]
    q = q + 1
    if not outside[p] and not solid[p] then
      outside[p] = true
      local x, y = p % w, floor(p / w)
      if x + 1 < w then queue[#queue + 1] = p + 1 end
      if x > 0 then queue[#queue + 1] = p - 1 end
      if y + 1 < h then queue[#queue + 1] = p + w end
      if y > 0 then queue[#queue + 1] = p - w end
    end
  end
  local rows = {}
  for y = 0, h - 1 do
    local r = 0
    for x = 0, w - 1 do
      if not outside[y * w + x] then r = r + 2 ^ x end
    end
    rows[y] = r
  end
  return rows
end

local function bit(row, x) return floor(row / 2 ^ x) % 2 == 1 end
local function count(row)
  local n = 0
  for x = 0, 15 do if bit(row, x) then n = n + 1 end end
  return n
end

--- The signposts of a grid: { { cell, rows (16 masks), head (16, or nil), ground (metatile),
--- headGround } }.
function Signs.find(grid, opt)
  local W, H, rows = grid.w, grid.h, grid.rows
  local function cell(i, j) return i >= 0 and j >= 0 and i < W and j < H and rows[j][i] or nil end
  local function off(i, j)
    local c = cell(i, j)
    return not c or c.coll == nil
  end
  local function blocked(i, j)
    local c = cell(i, j)
    return c ~= nil and c.coll ~= nil and opt.isWall(c.coll) == true
  end
  local function layers(c)
    if not c or not c.mid then return nil, nil end
    return opt.layers(c.mid, c.pair)
  end
  local function hasUpper(c)
    local _, up = layers(c)
    return up ~= nil and next(up) ~= nil
  end
  local function foliage(c)
    local lo, up = layers(c)
    local n, green = 0, 0
    for k = 0, 255 do
      local p = (up and up[k]) or (lo and lo[k])
      if p then
        n = n + 1
        local r, g, b = p[1] * 255, p[2] * 255, p[3] * 255
        if g > 64 and g > r + 16 and g > b + 16 then green = green + 1 end
      end
    end
    return n > 0 and green / n or 0
  end
  -- a post open on three sides: no building's (nor beside one: a model's corner), no tree, not a
  -- run of one drawing down a column (a fence's)
  local function besideModel(i, j)
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local n = cell(i + d[1], j + d[2])
      if n and n.model then return true end
    end
    return false
  end
  local function post(i, j)
    local c = cell(i, j)
    if not c or c.model or c.kind ~= "blocked" or c.coll == nil or not blocked(i, j) then return false end
    if opt.stands and opt.stands(c.mid, c.pair) then return false end
    if foliage(c) >= Signs.FOLIAGE then return false end
    return not blocked(i, j - 1) or cell(i, j - 1).mid ~= c.mid
  end
  local function free(i, j)
    if not post(i, j) or besideModel(i, j) then return false end
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
      if off(i + d[1], j + d[2]) or blocked(i + d[1], j + d[2]) then return false end
    end
    return true
  end
  -- lamps: (post, head) drawings of the free posts with a head drawn in the open cell north; one
  -- drawn so against a wall (a building on one side, walkable south) is a lamp too
  local lamps = {}
  for j = 1, H - 1 do
    for i = 0, W - 1 do
      local c, n = rows[j][i], rows[j - 1][i]
      if free(i, j) and not blocked(i, j - 1) and not off(i, j - 1) and hasUpper(n) then
        lamps[tostring(c.pair) .. ":" .. tostring(c.mid) .. ":" .. tostring(n.mid)] = true
      end
    end
  end
  -- signs drawn as the free posts are (their metatile, or its upper layer pixel for pixel): one
  -- is a sign wherever it stands, walkable to its south (a house's sign against its wall)
  local function upperKey(c)
    local _, up = layers(c)
    if not up then return nil end
    local parts = {}
    for k = 0, 255 do
      local p = up[k]
      if p then parts[#parts + 1] = k .. "=" .. key(p) end
    end
    return table.concat(parts, ",")
  end
  local postMids, postUppers = {}, {}
  for j = 0, H - 1 do
    for i = 0, W - 1 do
      if free(i, j) then
        local c = rows[j][i]
        postMids[tostring(c.pair) .. ":" .. tostring(c.mid)] = true
        local u = upperKey(c)
        if u then postUppers[u] = true end
      end
    end
  end
  local function drawnAsPost(c)
    if postMids[tostring(c.pair) .. ":" .. tostring(c.mid)] then return true end
    local u = upperKey(c)
    return u ~= nil and postUppers[u] == true
  end
  local function signpost(i, j)
    if free(i, j) then return true end
    if not post(i, j) or off(i, j + 1) or blocked(i, j + 1) then return false end
    local c = rows[j][i]
    if drawnAsPost(c) then return true end
    if j < 1 then return false end
    local n = rows[j - 1][i]
    if not lamps[tostring(c.pair) .. ":" .. tostring(c.mid) .. ":" .. tostring(n.mid)] then return false end
    local sides = 0
    for _, dx in ipairs({ -1, 1 }) do if blocked(i + dx, j) or off(i + dx, j) then sides = sides + 1 end end
    return sides == 1
  end

  local out = {}
  for j = 0, H - 1 do
    for i = 0, W - 1 do
      if signpost(i, j) then
        local c = rows[j][i]
        local lower, upper = layers(c)
        if lower or upper then
          -- the ground's colours: the clean walkable cells beside and below
          local ground = {}
          for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { 1, 1 } }) do
            local n = cell(i + d[1], j + d[2])
            if n and not off(i + d[1], j + d[2]) and not blocked(i + d[1], j + d[2]) and not hasUpper(n) then
              local lo = layers(n)
              for _, p in pairs(lo or {}) do ground[key(p)] = true end
            end
          end
          local solid = {}
          for k, p in pairs(lower or {}) do if not ground[key(p)] then solid[k] = true end end
          for k in pairs(upper or {}) do solid[k] = true end
          local mask = Signs.cutout(solid)
          local any = false
          for y = 0, 15 do if mask[y] ~= 0 then any = true end end
          if any then
            local rec = { cell = c, rows = mask }
            -- its head: the north cell's upper layer joined to its top row (a lamp's lantern)
            local nc = cell(i, j - 1)
            if nc and not off(i, j - 1) and not blocked(i, j - 1) and count(mask[0]) <= Signs.HEAD_MAX_WIDTH then
              local _, nup = layers(nc)
              if nup then
                local head, queue = {}, {}
                for x = 0, 15 do
                  if nup[15 * 16 + x] and ((x > 0 and bit(mask[0], x - 1)) or bit(mask[0], x)
                      or (x < 15 and bit(mask[0], x + 1))) then
                    head[15 * 16 + x] = true
                    queue[#queue + 1] = 15 * 16 + x
                  end
                end
                local q = 1
                while q <= #queue do
                  local p = queue[q]
                  q = q + 1
                  local px, py = p % 16, floor(p / 16)
                  for dy = -1, 1 do
                    for dx = -1, 1 do
                      local x, y = px + dx, py + dy
                      local k = y * 16 + x
                      if x >= 0 and x < 16 and y >= 0 and y < 16 and nup[k] and not head[k] then
                        head[k] = true
                        queue[#queue + 1] = k
                      end
                    end
                  end
                end
                local n, xmin, xmax = 0, 16, -1
                for k in pairs(head) do
                  n = n + 1
                  xmin, xmax = math.min(xmin, k % 16), math.max(xmax, k % 16)
                end
                if n > 0 and xmax - xmin + 1 <= Signs.HEAD_MAX_WIDTH and n <= Signs.HEAD_MAX_PIXELS then
                  rec.head = Signs.cutout(head)
                  rec.headGround = Signs.headGround(grid, i, j - 1, layers, off, blocked, hasUpper)
                end
              end
            end
            rec.ground = Signs.cellGround(grid, i, j, mask, layers, off, blocked, hasUpper, signpost)
            out[#out + 1] = rec
          end
        end
      end
    end
  end
  return out
end

local function same(a, b)
  if not a or not b then return a == b end
  for k = 0, 255 do
    local p, q = a[k], b[k]
    if (p == nil) ~= (q == nil) then return false end
    if p and key(p) ~= key(q) then return false end
  end
  return true
end

--- The ground under a sign's head: a clean walkable neighbour drawing the head cell's own lower
--- layer, or the commonest clean walkable neighbour.
function Signs.headGround(grid, i, j, layers, off, blocked, hasUpper)
  local own = layers(grid.rows[j][i])
  local counts, order = {}, {}
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = i + dx, j + dy
      if not ((dx == 0 and dy == 0) or (dx == 0 and dy == 1)) and not off(nx, ny) and not blocked(nx, ny) then
        local n = grid.rows[ny][nx]
        if not hasUpper(n) then
          if same(layers(n), own) then return n.mid end
          if not counts[n.mid] then order[#order + 1] = n.mid end
          counts[n.mid] = (counts[n.mid] or 0) + 1
        end
      end
    end
  end
  local best
  for _, m in ipairs(order) do if not best or counts[m] > counts[best] then best = m end end
  return best
end

--- The metatile a sign's own cell is laid with: of the clean walkable cells round it, the one
--- whose lower layer matches most of the cell's drawing outside the sign; then the one that runs
--- on best into its four neighbours; then the commonest; then the cell south.
function Signs.cellGround(grid, i, j, mask, layers, off, blocked, hasUpper, signpost)
  local own = layers(grid.rows[j][i])
  local seen = {}
  for k, p in pairs(own or {}) do
    if not bit(mask[floor(k / 16)], k % 16) then seen[k] = key(p) end
  end
  local south = not off(i, j + 1) and grid.rows[j + 1][i].mid or nil
  local found, order = {}, {}
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = i + dx, j + dy
      if not (dx == 0 and dy == 0) and not off(nx, ny) and not blocked(nx, ny) then
        local n = grid.rows[ny][nx]
        if not hasUpper(n) and not signpost(nx, ny) then
          if not found[n.mid] then order[#order + 1] = n.mid end
          found[n.mid] = (found[n.mid] or 0) + 1
        end
      end
    end
  end
  if south ~= nil and not found[south] then
    found[south] = 0
    order[#order + 1] = south
  end
  if #order == 0 then return nil end
  local seams = {}
  for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    if not off(i + d[1], j + d[2]) then
      seams[#seams + 1] = { layers(grid.rows[j + d[2]][i + d[1]]) or {}, d[1], d[2] }
    end
  end
  local pair = grid.rows[j][i].pair
  local function lowerOf(m)
    for _, row in pairs(grid.rows) do
      for _, c in pairs(row) do
        if c.mid == m and c.pair == pair then return layers(c) or {} end
      end
    end
    return {}
  end
  local function score(m)
    local lower = lowerOf(m)
    local a = 0
    for k, kk in pairs(seen) do if lower[k] and key(lower[k]) == kk then a = a + 1 end end
    local b = 0
    for _, s in ipairs(seams) do
      local other, dx, dy = s[1], s[2], s[3]
      for k = 0, 15 do
        local pa, pb
        if dx ~= 0 then
          if dx > 0 then pa, pb = k * 16 + 15, k * 16 else pa, pb = k * 16, k * 16 + 15 end
        else
          if dy > 0 then pa, pb = 15 * 16 + k, k else pa, pb = k, 15 * 16 + k end
        end
        if lower[pa] and other[pb] and key(lower[pa]) == key(other[pb]) then b = b + 1 end
      end
    end
    return { a, b, found[m], m == south and 1 or 0 }
  end
  local best, bs
  for _, m in ipairs(order) do
    local s = score(m)
    local better = not bs
    if bs then
      for k = 1, 4 do
        if s[k] ~= bs[k] then better = s[k] > bs[k]; break end
      end
    end
    if better then best, bs = m, s end
  end
  return best
end

--- A sign's solid: its pieces' faces, into add(x, y, z, px, py, shade) per vertex (6 a quad; x, z
--- in tiles from the north-west corner of its mask, which starts a cell north with a head; px, py
--- the mask pixel the corner reads). `mask` = rows 0..n-1.
function Signs.emit(mask, n, add)
  local depth = Signs.DEPTH / 16
  local function filled(x, y) return x >= 0 and y >= 0 and x < 16 and y < n and bit(mask[y], x) end
  -- 8-connected pieces, each standing on its own bottom
  local comp, low, nc = {}, {}, 0
  for y = 0, n - 1 do
    for x = 0, 15 do
      if filled(x, y) and not comp[y * 16 + x] then
        nc = nc + 1
        low[nc] = y
        local stack = { y * 16 + x }
        comp[y * 16 + x] = nc
        while #stack > 0 do
          local p = table.remove(stack)
          local px, py = p % 16, floor(p / 16)
          if py > low[nc] then low[nc] = py end
          for dy = -1, 1 do
            for dx = -1, 1 do
              if filled(px + dx, py + dy) and not comp[(py + dy) * 16 + px + dx] then
                comp[(py + dy) * 16 + px + dx] = nc
                stack[#stack + 1] = (py + dy) * 16 + px + dx
              end
            end
          end
        end
      end
    end
  end
  -- a box face: corners in order, each with its pixel
  local function face(pts, shade)
    local a, b, c, d = pts[1], pts[2], pts[3], pts[4]
    for _, p in ipairs({ a, b, c, a, c, d }) do add(p[1], p[2], p[3], p[4], p[5], shade) end
  end
  local function zOf(maxY) return floor(maxY / 8) * 0.5 + 0.25 - depth * 0.5 end
  -- sides, merged down a column
  for x = 0, 15 do
    for _, dx in ipairs({ -1, 1 }) do
      local y = 0
      while y < n do
        if filled(x, y) and not filled(x + dx, y) then
          local start = y
          local maxY = low[comp[y * 16 + x]]
          while y + 1 < n and y + 1 ~= 16 and filled(x, y + 1) and not filled(x + dx, y + 1) do y = y + 1 end
          local xa = (dx < 0) and x / 16 or (x + 1) / 16
          local za = zOf(maxY)
          local zb = za + depth
          local ya, yb = (maxY - y) / 16, (maxY - start + 1) / 16
          local u = x + 0.5
          face({ { xa, ya, zb, u, y + 1 }, { xa, ya, za, u, y + 1 }, { xa, yb, za, u, start },
                 { xa, yb, zb, u, start } }, 0.78)
        end
        y = y + 1
      end
    end
  end
  for y = 0, n - 1 do
    -- tops and bottoms, merged along a row
    for _, dy in ipairs({ -1, 1 }) do
      local x = 0
      while x < 16 do
        if filled(x, y) and not filled(x, y + dy) then
          local start = x
          local maxY = low[comp[y * 16 + x]]
          while x + 1 < 16 and filled(x + 1, y) and not filled(x + 1, y + dy) do x = x + 1 end
          local xa, xb = start / 16, (x + 1) / 16
          local za = zOf(maxY)
          local zb = za + depth
          local yy = dy < 0 and (maxY - y + 1) / 16 or (maxY - y) / 16
          local v = y + 0.5
          face({ { xa, yy, za, start, v }, { xb, yy, za, x + 1, v }, { xb, yy, zb, x + 1, v },
                 { xa, yy, zb, start, v } }, dy < 0 and 1 or 0.55)
        end
        x = x + 1
      end
    end
    -- front and back
    local x = 0
    while x < 16 do
      if filled(x, y) then
        local start = x
        local maxY = low[comp[y * 16 + x]]
        while x + 1 < 16 and filled(x + 1, y) do x = x + 1 end
        local xa, xb = start / 16, (x + 1) / 16
        local za = zOf(maxY)
        local zb = za + depth
        local ya, yb = (maxY - y) / 16, (maxY - y + 1) / 16
        face({ { xa, yb, zb, start, y }, { xb, yb, zb, x + 1, y }, { xb, ya, zb, x + 1, y + 1 },
               { xa, ya, zb, start, y + 1 } }, 1)
        face({ { xb, yb, za, x + 1, y }, { xa, yb, za, start, y }, { xa, ya, za, start, y + 1 },
               { xb, ya, za, x + 1, y + 1 } }, 0.68)
      end
      x = x + 1
    end
  end
  -- how tall it stands (tiles)
  local top = 0
  for k = 1, nc do
    for y = 0, n - 1 do
      for x = 0, 15 do
        if comp[y * 16 + x] == k then top = math.max(top, (low[k] - y + 1) / 16) end
      end
    end
  end
  return top
end

return Signs
