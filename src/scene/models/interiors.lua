-- Rooms in 3D (Battle Scene: Overworld): a room's drawing cut into its walls and furniture, a
-- model each.
--
-- A room's drawing is walls, furniture and floor. Every pixel equal to the floor metatile's own at
-- that place in its cell is floor, left to the terrain; the rest is claimed by the first piece
-- (front first) whose shape holds it, and each piece is read off the pixels it claimed - a box
-- read column by column (K.Relief), a counter on its plan (K.PlanPrism), a Poke Ball turned
-- (K.ProjLathe), a plant a card, a table on its legs. What the pieces in front of a wall hide of it
-- is drawn from its own pixels a panel away; the floor's own marks (a mat, shadows) are laid flat
-- by the pieces whose cells hold them. A piece modelled in one room stands, as it is, in every
-- later room that draws its tiles again (the registry: register / placeReused).
--
-- Ported from Emerald 3DS's scripts/gen_voxel_buildings.py (interior_specs and its helpers:
-- _inside, fill_hidden, find_supports, auto_leave, support_left, outline_trim, leg_split,
-- plain_side, side_image, slab_side, table_plan, table_parts, pick_side, ball_fit, lathe_fit,
-- dome_fit, post_parts, decal_cells, floor_under and the reuse of pieces; by Zallax and
-- contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), with the
-- same arithmetic, so a piece built here is the generator's triangle for triangle. Left out: the
-- proofs and the lint's facts (room_facts, piece_facts), the diagnostics images.
--
-- Plain Lua. An image here is { w, h, c = { [v * w + u] = colour } } (a colour the integer
-- r * 65536 + g * 256 + b, nil clear); a room's layout is io.layout(name) (Art.layoutArt over its
-- pair, with blocks: the collision bits too).

return function(K, Art)

local bit = require("bit")
local I = {}
local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local cos, pi = math.cos, math.pi
local INF = math.huge

I.SHELL_PIECES = { wall = true, side = true, stairwell = true, corner = true, edge = true, block = true,
                   partition = true, divider = true }
I.LOOSE_PIXELS = 64
I.POST_WIDTH = 6
I.SLAB_ROWS = 4

-- Python's truthiness of a spec value: nil, false, 0, "" and an empty list are false
local function truthy(v)
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" and next(v) == nil then return false end
  return true
end
I.truthy = truthy

local function prefix(name) return (name:match("^([^_]*)")) end
local function isShellName(pc) return I.SHELL_PIECES[prefix(pc.name)] == true end

local function lum(c)
  local r, g, b = floor(c / 65536), floor(c / 256) % 256, c % 256
  return 0.299 * r + 0.587 * g + 0.114 * b
end
I.lum = lum

-- ── images ─────────────────────────────────────────────────────────────────

local function newImg(w, h) return { w = w, h = h, c = {} } end
local function imgCopy(img)
  local o = newImg(img.w, img.h)
  for k, v in pairs(img.c) do o.c[k] = v end
  return o
end
-- PIL's paste without a mask: every pixel of src, clear ones too, clipped to dst
local function paste(dst, src, ox, oy)
  for v = 0, src.h - 1 do
    local y = oy + v
    if y >= 0 and y < dst.h then
      for u = 0, src.w - 1 do
        local x = ox + u
        if x >= 0 and x < dst.w then dst.c[y * dst.w + x] = src.c[v * src.w + u] end
      end
    end
  end
end
-- alpha_composite of opaque-or-clear images: src's drawn pixels over dst's
local function composite(dst, src, ox, oy)
  ox, oy = ox or 0, oy or 0
  for k, col in pairs(src.c) do
    local u, v = k % src.w, floor(k / src.w)
    local x, y = ox + u, oy + v
    if x >= 0 and x < dst.w and y >= 0 and y < dst.h then dst.c[y * dst.w + x] = col end
  end
end
-- a crop of a W x H colour array (clear beyond it)
local function cropFlat(flat, W, H, x0, y0, x1, y1)
  local o = newImg(x1 - x0, y1 - y0)
  for y = y0, y1 - 1 do
    for x = x0, x1 - 1 do
      if x >= 0 and x < W and y >= 0 and y < H then o.c[(y - y0) * o.w + (x - x0)] = flat[y * W + x] end
    end
  end
  return o
end
local function crop(img, x0, y0, x1, y1) return cropFlat(img.c, img.w, img.h, x0, y0, x1, y1) end
-- PIL getbbox: (left, upper, right, lower) of the drawn pixels, or nil
local function bbox(img)
  local x0, y0, x1, y1 = INF, INF, -INF, -INF
  for k in pairs(img.c) do
    local u, v = k % img.w, floor(k / img.w)
    if u < x0 then x0 = u end
    if u > x1 then x1 = u end
    if v < y0 then y0 = v end
    if v > y1 then y1 = v end
  end
  if x0 == INF then return nil end
  return { x0, y0, x1 + 1, y1 + 1 }
end
-- the kernel's art: { w, h, px = { r, g, b, a, ... } } (0..1)
local function toArt(img)
  local px, w = {}, img.w
  for i = 0, w * img.h - 1 do
    local col = img.c[i]
    local o = i * 4
    if col then
      px[o + 1], px[o + 2], px[o + 3], px[o + 4] = floor(col / 65536) / 255, (floor(col / 256) % 256) / 255,
        (col % 256) / 255, 1
    else
      px[o + 1], px[o + 2], px[o + 3], px[o + 4] = 0, 0, 0, 0
    end
  end
  return { w = w, h = img.h, px = px }
end
I.newImg, I.paste, I.composite, I.crop, I.bbox, I.toArt = newImg, paste, composite, crop, bbox, toArt

-- ── Counter: Python's collections.Counter, its ties in the order the keys came ─────

local function counter()
  return { n = {}, keys = {} }
end
local function cAdd(c, key, by)
  local v = c.n[key]
  if v == nil then c.keys[#c.keys + 1] = key; v = 0 end
  c.n[key] = v + (by or 1)
end
-- most_common(): the keys by count, most first, ties in insertion order
local function mostCommon(c)
  local order = {}
  for i, k in ipairs(c.keys) do order[i] = { k, c.n[k], i } end
  table.sort(order, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[3] < b[3]
  end)
  local out = {}
  for i, e in ipairs(order) do out[i] = e[1] end
  return out
end
local function mostCommon1(c)
  local best, bn
  for _, k in ipairs(c.keys) do
    if bn == nil or c.n[k] > bn then best, bn = k, c.n[k] end
  end
  return best
end
local function cTotal(c)
  local t = 0
  for _, k in ipairs(c.keys) do t = t + c.n[k] end
  return t
end
--- The colours that make up `share` of a count (gen_voxel_buildings.commonest): a room's
--- plaster and floor, not the greys of an outline drawn round it.
local function commonest(c, share)
  share = share or 0.85
  local total, keep, acc = cTotal(c), {}, 0
  for _, k in ipairs(mostCommon(c)) do
    if acc >= share * total then break end
    keep[k] = true
    acc = acc + c.n[k]
  end
  return keep
end
I.counter, I.cAdd, I.mostCommon, I.commonest = counter, cAdd, mostCommon, commonest

-- ── shapes ─────────────────────────────────────────────────────────────────
-- A shape is a list of parts: rectangles { x0, y0, x1, y1 }, ellipses { "ellipse", cx, cy, rx, ry }
-- and polygons { { x, y }, ... }.

local function partKind(part)
  if part[1] == "ellipse" then return "ellipse" end
  if type(part[1]) == "table" then return "poly" end
  return "rect"
end

--- Is pixel (x, y) in a piece's shape (_inside)?
local function inside(shape, x, y)
  local cx, cy = x + 0.5, y + 0.5
  for _, part in ipairs(shape) do
    local kind = partKind(part)
    if kind == "ellipse" then
      local ex, ey, rx, ry = part[2], part[3], part[4], part[5]
      if ((cx - ex) / rx) ^ 2 + ((cy - ey) / ry) ^ 2 <= 1.0 then return true end
    elseif kind == "rect" then
      if part[1] <= cx and cx < part[3] and part[2] <= cy and cy < part[4] then return true end
    else
      local hit, n = false, #part
      for k = 1, n do
        local a, b = part[k], part[k % n + 1]
        local ax, ay, bx, by = a[1], a[2], b[1], b[2]
        if (ay > cy) ~= (by > cy) and cx < ax + (bx - ax) * (cy - ay) / (by - ay) then hit = not hit end
      end
      if hit then return true end
    end
  end
  return false
end
I.inside = inside

--- A shape over a W x H room: { [y * W + x] = true }, with its bounds x0, y0, x1, y1 (exclusive)
--- - asked only within the shape's bounds and two pixels round (_inside_grid).
local function insideGrid(shape, W, H)
  local g = { x0 = 0, y0 = 0, x1 = 0, y1 = 0, set = {} }
  local xs, ys = {}, {}
  for _, part in ipairs(shape) do
    local kind = partKind(part)
    if kind == "ellipse" then
      xs[#xs + 1], xs[#xs + 2] = part[2] - abs(part[4]), part[2] + abs(part[4])
      ys[#ys + 1], ys[#ys + 2] = part[3] - abs(part[5]), part[3] + abs(part[5])
    elseif kind == "rect" then
      xs[#xs + 1], xs[#xs + 2] = part[1], part[3]
      ys[#ys + 1], ys[#ys + 2] = part[2], part[4]
    else
      for _, p in ipairs(part) do xs[#xs + 1], ys[#ys + 1] = p[1], p[2] end
    end
  end
  if #xs == 0 then return g end
  local mnx, mxx, mny, mxy = INF, -INF, INF, -INF
  for _, v in ipairs(xs) do mnx, mxx = min(mnx, v), max(mxx, v) end
  for _, v in ipairs(ys) do mny, mxy = min(mny, v), max(mxy, v) end
  local x0, x1 = max(0, floor(mnx) - 2), min(W, ceil(mxx) + 2)
  local y0, y1 = max(0, floor(mny) - 2), min(H, ceil(mxy) + 2)
  g.x0, g.y0, g.x1, g.y1 = x0, y0, max(x0, x1), max(y0, y1)
  local set = g.set
  for y = y0, y1 - 1 do
    for x = x0, x1 - 1 do
      if inside(shape, x, y) then set[y * W + x] = true end
    end
  end
  return g
end
I.insideGrid = insideGrid

-- a set's pixels in reading order (row by row), as a sorted list of indices
local function sortedIdx(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return out
end
I.sortedIdx = sortedIdx

--- `seeds` and every pixel of `allowed` reached from them, 4-connected (_flood). Sets of indices
--- over a W x H room.
local function flood(seeds, allowed, W, H)
  local out, todo = {}, {}
  for k in pairs(seeds) do
    if allowed[k] and not out[k] then out[k] = true; todo[#todo + 1] = k end
  end
  while #todo > 0 do
    local k = todo[#todo]
    todo[#todo] = nil
    local x, y = k % W, floor(k / W)
    local ns = { x + 1 < W and k + 1 or nil, x > 0 and k - 1 or nil, y + 1 < H and k + W or nil, y > 0 and k - W or nil }
    for i = 1, 4 do
      local n = ns[i]
      if n and allowed[n] and not out[n] then out[n] = true; todo[#todo + 1] = n end
    end
  end
  return out
end
I.flood = flood

-- ── what is a piece's, and what is the room's ───────────────────────────────

--- What the pieces listed before piece k (`fill` given) hide of it (fill_hidden): a period (a
--- wall's panels), the pixel that many columns along its row from any wall's own; "column", its
--- own nearest pixel up or down its column. -> { [idx] = colour }
local function fillHidden(pc, k, owner, fpx, walls, W, H)
  local period = pc.fill
  local out = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local o = owner[y * W + x]
      if o ~= nil and o < k and inside(pc.shape, x, y) then
        if period == "column" then
          for d = 1, H - 1 do
            local hit
            for _, yy in ipairs({ y - d, y + d }) do
              if yy >= 0 and yy < H and owner[yy * W + x] == k then hit = yy; break end
            end
            if hit then out[y * W + x] = fpx[hit * W + x]; break end
          end
        else
          local d = period
          while d < W do
            local hit
            for _, xx in ipairs({ x - d, x + d }) do
              if xx >= 0 and xx < W and walls[owner[y * W + xx] or false] then hit = xx; break end
            end
            if hit then out[y * W + x] = fpx[y * W + hit]; break end
            d = d + period
          end
        end
      end
    end
  end
  return out
end

--- `px` and every pixel beside one of them (_around), those in the room (a set of indices).
local function around(px, W, H)
  local out = {}
  for k in pairs(px) do
    local x, y = k % W, floor(k / W)
    out[k] = true
    if x + 1 < W then out[k + 1] = true end
    if x > 0 then out[k - 1] = true end
    if y + 1 < H then out[k + W] = true end
    if y > 0 then out[k - W] = true end
  end
  return out
end

--- What each lifted piece (`base`) stands on: the piece whose shape is drawn under its shape's
--- foot and whose top is at the height it is lifted to (find_supports). { [k] = support }
local function findSupports(pieces, grids, W, H)
  local out = {}
  for k, pc in ipairs(pieces) do
    if truthy(pc.base) then
      local g = grids[k]
      local last
      for y = 0, H - 1 do
        if y >= g.y0 and y < g.y1 then
          for x = g.x0, g.x1 - 1 do
            if g.set[y * W + x] then last = y; break end
          end
        end
      end
      if last and last + 1 < H then
        local b = last
        local votes = counter()
        for x = 0, W - 1 do
          if g.set[b * W + x] then
            for j, other in ipairs(pieces) do
              if j ~= k and grids[j].set[(b + 1) * W + x]
                  and abs((other.base or 0) + other.height - pc.base) <= 2 then
                cAdd(votes, j)
                break
              end
            end
          end
        end
        if #votes.keys > 0 then out[k] = mostCommon1(votes) end
      end
    end
  end
  return out
end

--- The colours each piece leaves where they run on into its shape from round it, beyond its own
--- `leave` (auto_leave): the room round it, the colours more the room's walls' and floor's than
--- its own and not its body's; for a card any of those, but for one on a stand. -> { [k] = set }
local function autoLeave(pieces, grids, ground, hexes, supports, W, H)
  local shell = {}
  for k, pc in ipairs(pieces) do
    if pc.facet or truthy(pc.walls) or isShellName(pc) then shell[k] = true end
  end
  local things = {}
  for k = 1, #pieces do if not shell[k] then things[#things + 1] = k end end
  local roomy = {}
  local room = counter()
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local i = y * W + x
      local any = false
      for _, k in ipairs(things) do
        if grids[k].set[i] then any = true; break end
      end
      if not any then roomy[i] = true; cAdd(room, hexes[i]) end
    end
  end
  local main = commonest(room)
  local out = {}
  for k, pc in ipairs(pieces) do
    if shell[k] or truthy(pc.fill) or pc.facet then
      out[k] = {}
    else
      local set = grids[k].set
      local ours, mineRoomy = {}, {}
      for i in pairs(set) do
        local c = hexes[i]
        ours[c] = (ours[c] or 0) + 1
        if roomy[i] then mineRoomy[c] = (mineRoomy[c] or 0) + 1 end
      end
      local function theirs(c)
        local v = (room.n[c] or 0) - (mineRoomy[c] or 0)
        return v > 0 and v or 0
      end
      local leave = {}
      if pc.card then
        if not supports[k] then
          for c, n in pairs(ours) do
            if theirs(c) > 2 * n and lum(c) >= 90 then leave[c] = true end
          end
        end
      else
        local body = {}
        for i in pairs(set) do
          local x, y = i % W, floor(i / W)
          local all = true
          for dj = -2, 2 do
            for di = -2, 2 do
              local xx, yy = x + di, y + dj
              if not (xx >= 0 and xx < W and yy >= 0 and yy < H and set[yy * W + xx]) then all = false; break end
            end
            if not all then break end
          end
          if all then body[hexes[i]] = true end
        end
        for c, n in pairs(ours) do
          if main[c] and theirs(c) > n and not body[c] and lum(c) >= 90 then leave[c] = true end
        end
      end
      out[k] = leave
    end
  end
  return out
end

--- The pixels of a lifted piece's shape that are its support's top going on under it, reached
--- from the piece's outline (support_left); never half the piece. `sibs`: the others standing on
--- the same support.
local function supportLeft(k, s, grids, hexes, W, H, sibs)
  local set = grids[k].set
  local edge, ours = {}, {}
  for i in pairs(set) do
    local x, y = i % W, floor(i / W)
    if not (x + 1 < W and set[i + 1]) or not (x > 0 and set[i - 1]) or not (y + 1 < H and set[i + W])
        or not (y > 0 and set[i - W]) then
      edge[i] = true
    end
    ours[hexes[i]] = (ours[hexes[i]] or 0) + 1
  end
  local top = {}
  local theirs = counter()
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local i = y * W + x
      if grids[s].set[i] and not set[i] then
        local other = false
        for _, j in ipairs(sibs) do
          if grids[j].set[i] then other = true; break end
        end
        if not other then top[i] = true; cAdd(theirs, hexes[i]) end
      end
    end
  end
  local main = commonest(theirs)
  local alike = {}
  local count = 0
  for i in pairs(set) do
    local c = hexes[i]
    if main[c] and (theirs.n[c] or 0) > (ours[c] or 0) and lum(c) >= 90 then alike[i] = true end
    count = count + 1
  end
  local seeds = {}
  for i in pairs(edge) do if alike[i] then seeds[i] = true end end
  local left = flood(seeds, alike, W, H)
  local n = 0
  for _ in pairs(left) do n = n + 1 end
  if 2 * n < count then return left end
  local goesOn = {}
  for i in pairs(set) do
    local c = hexes[i]
    if lum(c) >= 90 then
      local x, y = i % W, floor(i / W)
      for _, d in ipairs({ 2, 4, 6, 8 }) do
        local hit = false
        for _, xx in ipairs({ x - d, x + d }) do
          if xx >= 0 and xx < W and top[y * W + xx] and hexes[y * W + xx] == c then hit = true; break end
        end
        if hit then goesOn[i] = true; break end
      end
    end
  end
  seeds = {}
  for i in pairs(edge) do if goesOn[i] then seeds[i] = true end end
  left = flood(seeds, goesOn, W, H)
  n = 0
  for _ in pairs(left) do n = n + 1 end
  if 2 * n < count then return left end
  return {}
end

--- The pixels of `pts` past those of `by` both along their row and down their column (_past);
--- above only if `above`; `both` false: either way. With `box` (x0, x1, y0, y1), nothing when `by`
--- spans less than three quarters of it either way.
local function past(pts, by, box, above, both, W)
  if both == nil then both = true end
  if next(by) == nil then return {} end
  local X0, X1, Y0, Y1 = INF, -INF, INF, -INF
  local rowsMin, rowsMax, colsMin, colsMax = {}, {}, {}, {}
  for i in pairs(by) do
    local x, y = i % W, floor(i / W)
    X0, X1, Y0, Y1 = min(X0, x), max(X1, x), min(Y0, y), max(Y1, y)
    rowsMin[y] = min(rowsMin[y] or INF, x)
    rowsMax[y] = max(rowsMax[y] or -INF, x)
    colsMin[x] = min(colsMin[x] or INF, y)
    colsMax[x] = max(colsMax[x] or -INF, y)
  end
  if box then
    local bx0, bx1, by0, by1 = box[1], box[2], box[3], box[4]
    if 4 * (X1 - X0 + 1) < 3 * (bx1 - bx0 + 1) or 4 * (Y1 - Y0 + 1) < 3 * (by1 - by0 + 1) then return {} end
  end
  local function across(x, y)
    if rowsMin[y] then return x < rowsMin[y] or x > rowsMax[y] end
    return not (Y0 <= y and y <= Y1)
  end
  local function down(x, y)
    if not colsMin[x] then return not (X0 <= x and x <= X1) end
    return y > colsMax[x] or (above and y < colsMin[x])
  end
  local out = {}
  for i in pairs(pts) do
    local x, y = i % W, floor(i / W)
    if both then
      if across(x, y) and down(x, y) then out[i] = true end
    elseif across(x, y) or down(x, y) then
      out[i] = true
    end
  end
  return out
end

local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end
I.count = count

--- A piece's pixels as its own outline delimits them, out of those its shape takes
--- (outline_trim): what is past its outline both ways below or beside it, in a colour its body
--- has nowhere; what it stands on (`under`, `taken`) past what is left of it both ways.
local function outlineTrim(cand, hexes, under, taken, W)
  local out = {}
  for i in pairs(cand) do out[i] = true end
  local n = count(cand)
  if n == 0 then return out end
  local vals = {}
  local idx = sortedIdx(cand)
  -- (the mean in the order Python's set iterates them: an int's hash is itself)
  local ordered = Art.setOrder(idx, function(i)
    return Art.hashTuple({ i % W, floor(i / W) }, 2)
  end)
  for k, i in ipairs(ordered) do vals[k] = lum(hexes[i]) end
  local fl = max(90, 0.6 * Art.fsum(vals, #vals) / n)
  local dark, theirs = {}, {}
  local bx0, bx1, by0, by1 = INF, -INF, INF, -INF
  for i in pairs(cand) do
    local x, y = i % W, floor(i / W)
    bx0, bx1, by0, by1 = min(bx0, x), max(bx1, x), min(by0, y), max(by1, y)
    if lum(hexes[i]) < fl then dark[i] = true end
  end
  for i in pairs(cand) do
    if not dark[i] and (taken[i] or under[i]) then theirs[i] = true end
  end
  local box = { bx0, bx1, by0, by1 }
  local rest = {}
  for i in pairs(cand) do
    if not dark[i] and not theirs[i] then rest[i] = true end
  end
  local loose = past(rest, dark, box, false, true, W)
  local pastEither = past(rest, dark, box, true, false, W)
  local body = {}
  for i in pairs(rest) do
    if not pastEither[i] then body[hexes[i]] = true end
  end
  for i in pairs(loose) do
    if not body[hexes[i]] then out[i] = nil end
  end
  local others = {}
  for i in pairs(out) do if not theirs[i] then others[i] = true end end
  local gone = past(theirs, others, nil, true, true, W)
  if 4 * (count(out) - count(gone)) >= n then
    for i in pairs(gone) do out[i] = nil end
  end
  return out
end

--- Where furniture stands on legs (leg_split): the row its top ends at, when the rows up from
--- its foot are three quarters floor or less across its width; -> row, released pixels, or nil.
local function legSplit(mine, hexes, foot, height, release, explicit, W)
  local x0, x1 = INF, -INF
  for i in pairs(mine) do
    local x = i % W
    x0, x1 = min(x0, x), max(x1, x)
  end
  local function gapish(x, y)
    local i = y * W + x
    return not mine[i] or release[hexes[i]] == true
  end
  local function gapped(v)
    local solid = 0
    for x = x0, x1 do
      if not gapish(x, v) then solid = solid + 1 end
    end
    return solid > 0 and 4 * solid <= 3 * (x1 - x0 + 1)
  end
  local row
  if truthy(explicit) then
    row = foot - height + floor(explicit)
  else
    for v = foot - 1, foot - height + 1, -1 do
      if not gapped(v) then break end
      row = v
    end
    if row == nil or foot - row < 2 then return nil end
    local hem = foot - height
    while hem < row do
      local any = false
      for x = x0, x1 do
        if gapish(x, hem) then any = true; break end
      end
      if any then break end
      hem = hem + 1
    end
    row = hem
  end
  if row == nil or foot - row < (truthy(explicit) and 1 or 2) or row - (foot - height) < 1 then return nil end
  local released = {}
  for i in pairs(mine) do
    if floor(i / W) >= row and release[hexes[i]] then released[i] = true end
  end
  return row, released
end

--- Whether the lowest rows of a piece's front have floor between its own pixels (front_gaps).
local function frontGaps(mine, foot, W, rows)
  rows = rows or 4
  for v = foot - rows, foot - 1 do
    local mn, mx, n = INF, -INF, 0
    for i in pairs(mine) do
      if floor(i / W) == v then
        local x = i % W
        mn, mx, n = min(mn, x), max(mx, x), n + 1
      end
    end
    if n > 0 and mx - mn + 1 > n then return true end
  end
  return false
end

--- A piece drawn no deeper than its front and the one row of outline over it (is_flat).
local function isFlat(obj, height)
  local longest = 0
  for u = 0, obj.w - 1 do
    local run = 0
    for v = 0, obj.h - 1 do
      run = obj.c[v * obj.w + u] and run + 1 or 0
      longest = max(longest, run)
    end
  end
  return longest > 0 and longest <= height + 1
end

I._fillHidden, I._findSupports, I._autoLeave, I._supportLeft = fillHidden, findSupports, autoLeave, supportLeft
I._past, I._outlineTrim, I._legSplit, I._frontGaps, I._isFlat = past, outlineTrim, legSplit, frontGaps, isFlat
I._around = around

-- ── the faces the drawing never shows ───────────────────────────────────────

-- list(set(seq)) of (x, y) pairs as 64-bit CPython orders it (_set_order): seq { { x, y } }
local function setOrderXY(seq)
  local keys = {}
  for i, p in ipairs(seq) do keys[i] = p[1] * 65536 + p[2] end
  local out = {}
  for i, key in ipairs(Art.setOrder(keys, function(k)
    return Art.hashTuple({ floor(k / 65536), k % 65536 }, 2)
  end)) do
    out[i] = { floor(key / 65536), key % 65536 }
  end
  return out
end
I.setOrderXY = setOrderXY

--- A piece's side as its front shows its casing where the two meet, row by row (plain_side):
--- each of the front's `height` rows at its foot in the commonest colour of its `ends` pixels at
--- either end that is not its outline; an outline row takes the stuff above it; its first and
--- last rows keep their outline where the front has one at its ends. `mine` an ordered list of
--- { x, y } (setOrderXY: the order breaks ties), get(x, y) -> colour. -> image width x height
local function plainSide(mine, get, height, foot, width, ends)
  width, ends = width or 16, ends or 3
  local vals, all = {}, counter()
  for k, p in ipairs(mine) do
    local c = get(p[1], p[2])
    vals[k] = lum(c)
    cAdd(all, c)
  end
  local mean = max(Art.fsum(vals, #vals) / #mine, lum(mostCommon1(all)))
  local thr = max(90, 0.6 * mean)
  local function dark(c) return lum(c) < thr end
  local outline = counter()
  for _, p in ipairs(mine) do
    local c = get(p[1], p[2])
    if dark(c) then cAdd(outline, c) end
  end
  local byRow = {}
  for _, p in ipairs(mine) do
    local r = byRow[p[2]]
    if not r then r = {}; byRow[p[2]] = r end
    r[#r + 1] = p[1]
  end
  local rows, rims = {}, {}
  for i = 1, height do
    local v = foot - height + (i - 1)
    local row = {}
    for _, x in ipairs(byRow[v] or {}) do row[#row + 1] = x end
    table.sort(row)
    local tips = {}
    for k = 1, min(ends, #row) do tips[#tips + 1] = get(row[k], v) end
    for k = max(1, #row - ends + 1), #row do tips[#tips + 1] = get(row[k], v) end
    local light = counter()
    for _, c in ipairs(tips) do if not dark(c) then cAdd(light, c) end end
    local pick
    if #light.keys > 0 then
      pick = mostCommon(light)[1]
    else
      local rc = counter()
      for _, x in ipairs(row) do cAdd(rc, get(x, v)) end
      for _, c in ipairs(mostCommon(rc)) do
        if not dark(c) then pick = c; break end
      end
    end
    rows[i] = pick
    local nd = 0
    for _, c in ipairs(tips) do if dark(c) then nd = nd + 1 end end
    rims[i] = #row > 0 and dark(get(row[1], v)) and dark(get(row[#row], v)) and nd * 2 > #tips
  end
  local any = false
  for i = 1, height do if rows[i] ~= nil then any = true; break end end
  if not any then
    local c = mostCommon1(all)
    for i = 1, height do rows[i] = c end
  end
  for i = 1, height do
    if rows[i] == nil then
      local got
      for j = i - 1, 1, -1 do if rows[j] ~= nil then got = rows[j]; break end end
      if got == nil then
        for j = i + 1, height do if rows[j] ~= nil then got = rows[j]; break end end
      end
      rows[i] = got
    end
  end
  local rim
  if #outline.keys > 0 then
    rim = mostCommon1(outline)
  else
    for i = 1, height do
      if rim == nil or lum(rows[i]) < lum(rim) then rim = rows[i] end
    end
  end
  if height >= 2 and rims[1] then rows[1] = rim end
  if height >= 2 and rims[height] then rows[height] = rim end
  local img = newImg(width, height)
  for i = 1, height do
    for u = 0, width - 1 do img.c[(i - 1) * width + u] = rows[i] end
  end
  return img
end
I.plainSide = plainSide

--- The stretch a piece's hidden sides and back are dressed with, and the pixels of it that are
--- not the piece's own (side_image); nil to read it off its own front (pick_side). `side`: a
--- rectangle of the room, a list of them one under another, "plain" (plain_side), "cell" (its
--- first whole cell) or "front".
local function sideImage(pc, mine, filled, fpx, shell, foot, W, H)
  local side = pc.side
  if side == nil then
    side = (shell or truthy(pc.card) or (frontGaps(mine, foot, W) and not truthy(pc.base))) and "front" or "plain"
  end
  if side == "front" then return nil end
  if side == "plain" then
    local seq = {}
    for _, i in ipairs(sortedIdx(mine)) do seq[#seq + 1] = { i % W, floor(i / W) } end
    return plainSide(setOrderXY(seq), function(x, y) return fpx[y * W + x] end, floor(pc.height), foot), {}
  end
  if side == "cell" then
    local seen, cells = {}, {}
    for i in pairs(mine) do
      local cy, cx = floor(floor(i / W) / 16), floor((i % W) / 16)
      local key = cy * 4096 + cx
      if not seen[key] then seen[key] = true; cells[#cells + 1] = key end
    end
    table.sort(cells)
    local pick
    for _, key in ipairs(cells) do
      local cy, cx = floor(key / 4096), key % 4096
      local whole = true
      for j = 0, 15 do
        for i = 0, 15 do
          if not mine[(cy * 16 + j) * W + cx * 16 + i] then whole = false; break end
        end
        if not whole then break end
      end
      if whole then pick = { cx * 16, cy * 16, cx * 16 + 16, cy * 16 + 16 }; break end
    end
    if not pick then return nil end
    side = pick
  end
  local rects = type(side[1]) == "number" and { side } or side
  local width = rects[1][3] - rects[1][1]
  local total = 0
  for _, r in ipairs(rects) do total = total + (r[4] - r[2]) end
  local img = newImg(width, total)
  local foreign, top = {}, 0
  for _, r0 in ipairs(rects) do
    local r = { r0[1], r0[2], r0[1] + width, r0[4] }
    local c = cropFlat(filled, W, H, r[1], r[2], r[3], r[4])
    for y = r[2], r[4] - 1 do
      for x = r[1], r[3] - 1 do
        if x >= 0 and x < W and y >= 0 and y < H and mine[y * W + x] then
          c.c[(y - r[2]) * c.w + (x - r[1])] = fpx[y * W + x]
        else
          foreign[(y - r[2] + top) * width + (x - r[1])] = true
        end
      end
    end
    paste(img, c, 0, top)
    top = top + r[4] - r[2]
  end
  return img, foreign
end

--- An 8-column tile of the object's own drawn front, for the faces the drawing never shows
--- (pick_side): the longest stretch of columns whose runs end on the same row with a full front.
local function pickSide(art, height, longest)
  local W, Hh = art.w, art.h
  local function drawn(u, v) return art.c[v * W + u] ~= nil end
  local ends = {}
  for u = 0, W - 1 do
    local e
    for v = Hh - 1, 0, -1 do
      if drawn(u, v) then e = v + 1; break end
    end
    local full = e ~= nil and e >= height
    if full then
      for v = e - height, e - 1 do
        if not drawn(u, v) then full = false; break end
      end
    end
    ends[u] = full and e or false
  end
  if longest then
    local best
    local u = 0
    while u < W do
      local k = u
      while k < W and ends[u] and ends[k] == ends[u] do k = k + 1 end
      if ends[u] and (best == nil or k - u > best[2] - best[1]) then best = { u, k } end
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
        for k = 0, width - 1 do
          if ends[u + k] ~= e then ok = false; break end
        end
        if ok and (best == nil or e > best[2]) then best = { u, e } end
      end
    end
    if best then return K.Tile(best[1], best[2] - height, best[1] + width, best[2]) end
  end
  -- no straight front at all: the block of its own drawing with the most drawn pixels
  local best, score = nil, -1
  for v = 0, max(1, Hh - height + 1) - 1 do
    for u = 0, max(1, W - 4 + 1) - 1 do
      local n = 0
      for i = 0, min(4, W) - 1 do
        for j = 0, min(height, Hh) - 1 do
          if drawn(u + i, v + j) then n = n + 1 end
        end
      end
      if n > score then best, score = { u, v }, n end
    end
  end
  return K.Tile(best[1], best[2], best[1] + min(4, W), best[2] + min(height, Hh))
end
I.pickSide = pickSide

--- A table's top seen from the side, `depth` long and its front's `rows` tall (slab_side): under
--- each pixel of the top's edge, what the front shows under a pixel of the same colour of the
--- top's front edge; the front's plain stuff elsewhere, and all along a body thicker than
--- SLAB_ROWS.
local function slabSide(obj, rows, depth, zBack, height, ends)
  ends = ends or 2
  local W, H = obj.w, obj.h
  local function own(u, v) return v >= 0 and v < H and obj.c[v * W + u] ~= nil end
  local function get(u, v) return obj.c[v * W + u] end
  local first = rows[1]
  local cols = {}
  for u = 0, W - 1 do
    local all = true
    for _, v in ipairs(rows) do
      if not own(u, v) then all = false; break end
    end
    if all then cols[#cols + 1] = u end
  end
  local img = newImg(max(1, depth), #rows)
  local seq = {}
  for _, u in ipairs(cols) do
    for _, v in ipairs(rows) do seq[#seq + 1] = { u, v } end
  end
  local plain = #seq > 0 and plainSide(setOrderXY(seq), get, #rows, rows[#rows] + 1) or nil
  local function plainAt(i) return plain and plain.c[(i - 1) * plain.w] or nil end
  if #cols == 0 or #rows > I.SLAB_ROWS then
    for d = 0, img.w - 1 do
      for i = 1, #rows do img.c[(i - 1) * img.w + d] = plainAt(i) end
    end
    return img
  end
  local xa, xb = cols[1], cols[#cols]
  local under = {}
  for k = ends + 1, #cols - ends do
    local u = cols[k]
    if own(u, first - 1) and lum(get(u, first - 1)) >= 90 then
      local c = get(u, first - 1)
      under[c] = under[c] or {}
      local l = under[c]
      l[#l + 1] = u
    end
  end
  for d = 0, depth - 1 do
    local v = zBack + d - height
    local colour
    if v >= 0 and v < first then
      local n = 0
      for u = 0, W - 1 do
        if own(u, v) then
          n = n + 1
          if n > 3 then break end
          if colour == nil and lum(get(u, v)) >= 90 then colour = get(u, v) end
        end
      end
    end
    local match = colour ~= nil and under[colour] or nil
    if match then
      local rel = (d + 0.5) / depth
      local best, bd
      for _, u in ipairs(match) do
        local dd = abs((u - xa + 0.5) / (xb - xa + 1) - rel)
        if bd == nil or dd < bd then best, bd = u, dd end
      end
      for i, vv in ipairs(rows) do img.c[(i - 1) * img.w + d] = get(best, vv) end
    else
      for i = 1, #rows do img.c[(i - 1) * img.w + d] = plainAt(i) end
    end
  end
  return img
end

--- A piece on legs, read off its drawing below its top's front (table_plan): column by column a
--- post, a pedestal or an apron, with the sides each is dressed with stacked in one image.
--- -> runs, image, rects (keyed "slab" and the run's number)
local function tablePlan(obj, hem, foot, height, back)
  local W, Hh = obj.w, obj.h
  local function own(u, v) return obj.c[v * W + u] ~= nil end
  local legs = foot - hem
  local first
  for v = 0, Hh - 1 do
    for u = 0, W - 1 do
      if own(u, v) then first = v; break end
    end
    if first then break end
  end
  local zBack = back ~= nil and back or first + height
  local depth = max(1, foot - zBack)
  local below = {}
  for u = 0, W - 1 do
    local l = {}
    for v = hem, foot - 1 do if own(u, v) then l[#l + 1] = v end end
    below[u] = l
  end
  local runs = {}
  for u = 0, W - 1 do
    local b = below[u]
    if #b > 0 then
      local kind = b[#b] >= foot - 2 and "leg" or "apron"
      local last = runs[#runs]
      if last and last.kind == kind and last.u1 == u then
        last.u1 = u + 1
      else
        runs[#runs + 1] = { kind = kind, u0 = u, u1 = u + 1 }
      end
    end
  end
  for _, r in ipairs(runs) do
    local lastRow, core = -INF, 0
    for u = r.u0, r.u1 - 1 do
      local b = below[u]
      lastRow = max(lastRow, b[#b])
      if 2 * #b >= legs then core = core + 1 end
    end
    r.last, r.core = lastRow + 1, core
    if r.kind == "leg" then r.kind = core <= I.POST_WIDTH and "post" or "pedestal" end
  end
  local slabRows = {}
  for v = foot - height, hem - 1 do slabRows[#slabRows + 1] = v end
  local sides = { { "slab", slabSide(obj, slabRows, depth, zBack, height) } }
  for n, r in ipairs(runs) do
    if r.kind ~= "post" then
      local seq = {}
      for u = r.u0, r.u1 - 1 do
        for v = hem, r.last - 1 do
          if own(u, v) then seq[#seq + 1] = { u, v } end
        end
      end
      sides[#sides + 1] = { n, plainSide(setOrderXY(seq), function(x, y) return obj.c[y * W + x] end,
        r.last - hem, r.last) }
    end
  end
  local w, h = 0, 0
  for _, s in ipairs(sides) do w, h = max(w, s[2].w), h + s[2].h end
  local img = newImg(w, h)
  local rects, top = {}, 0
  for _, s in ipairs(sides) do
    paste(img, s[2], 0, top)
    rects[s[1]] = { 0, top, s[2].w, top + s[2].h }
    top = top + s[2].h
  end
  return { runs = runs, img = img, rects = rects }
end

--- A piece on legs built (table_parts): its top lifted onto its legs; posts as deep as they are
--- wide, each with a copy at the top's back where the top hides it at 45 degrees; a pedestal and
--- an apron as deep as the top. Its sides are table_plan's image, at `voff` of its art.
local function tableParts(pc, obj, plan, hem, foot, back, topTile, voff)
  local runs, rects = plan.runs, plan.rects
  local W, Hh = obj.w, obj.h
  local height = floor(pc.height)
  local legs = foot - hem
  local function own(u, v) return obj.c[v * W + u] ~= nil end
  local function tile(key)
    local r = rects[key]
    return K.Tile(r[1], voff + r[2], r[3], voff + r[4])
  end
  local first
  for v = 0, Hh - 1 do
    for u = 0, W - 1 do
      if own(u, v) then first = v; break end
    end
    if first then break end
  end
  local rear = back ~= nil and back or first + height
  local against = pc.against ~= nil
  local function cut(u0, u1, v0, v1)
    local img = newImg(W, Hh)
    for k, c in pairs(obj.c) do
      local u, v = k % W, floor(k / W)
      if u0 <= u and u < u1 and v0 <= v and v < v1 then img.c[k] = c end
    end
    return toArt(img)
  end
  local parts = { K.Lifted(K.Relief(pc.name, cut(0, W, 0, hem), height - legs, tile("slab"),
    { foot = hem, solid = true, back = back ~= nil and back - legs or nil, top_tile = topTile, proj_back = true,
      against = against, skirt = 0 }), legs) }
  for n, r in ipairs(runs) do
    local u0, u1 = r.u0, r.u1
    if r.kind == "apron" then
      local lift = foot - r.last
      parts[#parts + 1] = K.Lifted(K.Relief(pc.name, cut(u0, u1, hem, r.last), r.last - hem, tile(n),
        { foot = r.last, solid = true, back = rear - lift, proj_back = true, skirt = 0 }), lift)
    elseif r.kind == "pedestal" then
      parts[#parts + 1] = K.Relief(pc.name, cut(u0, u1, hem, foot), legs, tile(n),
        { foot = foot, solid = true, back = rear, proj_back = true })
    else
      local post = K.Relief(pc.name, cut(u0, u1, hem, foot), legs, K.Tile(u0, hem, u1, foot),
        { foot = foot, solid = true, back = foot - r.core, proj_back = true })
      parts[#parts + 1] = post
      local dz = rear - (foot - r.core)
      if dz < 0 then
        local all = true
        for u = u0, u1 - 1 do
          local legged = false
          for vv = hem, foot - 1 do
            if own(u, vv) then legged = true; break end
          end
          if legged then
            for v = max(0, rear - legs), min(Hh, rear + r.core) - 1 do
              if not own(u, v) then all = false; break end
            end
          end
          if not all then break end
        end
        if all then parts[#parts + 1] = K.Moved(post, 0, dz, "~depth") end
      end
    end
  end
  return parts
end

-- ── round things fitted to their drawing ───────────────────────────────────

local function drawnPts(obj)
  local pts = {}
  for v = 0, obj.h - 1 do
    for u = 0, obj.w - 1 do
      if obj.c[v * obj.w + u] then pts[#pts + 1] = { u, v } end
    end
  end
  return pts
end

local function covers(part, pts)
  local hull = K.viewHull()
  part:emit(hull)
  for _, p in ipairs(pts) do
    if not hull.covers(p[1], p[2]) then return false end
  end
  return true
end

--- A ball drawn as a circle (ball_fit): the ellipsoid on `base` whose 45-degree view is that
--- circle, grown until its polygons cover the pixels' centres. -> cx, cz, rx, rz, profile
local function ballFit(obj, base, seg, rings)
  seg, rings = seg or 16, rings or 8
  local pts = {}
  local x0, x1, top, foot = INF, -INF, INF, -INF
  for _, p in ipairs(drawnPts(obj)) do
    local u, v = p[1] + 0.5, p[2] + 0.5
    pts[#pts + 1] = { u, v }
    x0, x1, top, foot = min(x0, u), max(x1, u), min(top, v), max(foot, v)
  end
  x0, x1, top, foot = x0 - 0.5, x1 + 0.5, top - 0.5, foot + 0.5
  local grow = 0.0
  while true do
    local cx, rx = (x0 + x1) / 2.0, (x1 - x0) / 2.0 + grow
    local e = (foot - top) / 2.0 + grow
    local ry = e / sqrt(2.0)
    local rz = ry
    local yc = base + ry
    local cz = (top + foot) / 2.0 + yc
    local profile = {}
    for i = 0, rings do
      profile[i + 1] = { yc - ry * cos(pi * i / rings), (i == 0 or i == rings) and 0.0 or rx * math.sin(pi * i / rings) }
    end
    if covers(K.ProjLathe("ball", cx, cz, profile, rz / rx, seg), pts) then return cx, cz, rx, rz, profile end
    grow = grow + 0.125
  end
end

-- bisect.bisect_right over a sorted list
local function bisectRight(list, x)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if x < list[mid] then hi = mid else lo = mid + 1 end
  end
  return lo - 1
end

--- A turned thing drawn standing (lathe_fit): a surface of revolution on `base`, `height` tall,
--- its plan `squash` as deep as wide, its radius at `bands` + 1 rings fitted so that its 45-degree
--- view covers every pixel of the piece's own and as few others as it can. -> cx, cz, profile
local function latheFit(obj, height, base, squash, bands, seg)
  squash, bands, seg = squash or 0.7, bands or 4, seg or 16
  local own = {}
  local x0, x1, top, foot = INF, -INF, INF, -INF
  local list = drawnPts(obj)
  for _, p in ipairs(list) do
    own[p[2] * 65536 + p[1]] = true
    x0, x1, top, foot = min(x0, p[1]), max(x1, p[1]), min(top, p[2]), max(foot, p[2])
  end
  x1, foot = x1 + 1, foot + 1
  local cx, h = (x0 + x1) / 2.0, height + 0.0
  local need, spare = {}, {}
  for v = top - 2, foot + 1 do
    local nd, sp = {}, {}
    for u = x0, x1 - 1 do if own[v * 65536 + u] then nd[#nd + 1] = abs(u + 0.5 - cx) end end
    for u = x0 - 2, x1 + 1 do if not own[v * 65536 + u] then sp[#sp + 1] = abs(u + 0.5 - cx) end end
    need[v], spare[v] = nd, sp
  end
  local n = floor(4 * h) + 1
  local ys = {}
  for k = 0, n - 1 do ys[k + 1] = h * k / (n - 1) end
  local function radius(radii, y)
    local t = y / h * bands
    local i = min(floor(t), bands - 1)
    return radii[i + 1] + (radii[i + 2] - radii[i + 1]) * (t - i)
  end
  local needSorted, spareSorted = {}, {}
  for v = top - 2, foot + 1 do
    local a, b = {}, {}
    for i, d in ipairs(need[v]) do a[i] = d end
    for i, d in ipairs(spare[v]) do b[i] = d end
    table.sort(a)
    table.sort(b)
    needSorted[v], spareSorted[v] = a, b
  end
  local costs = {}
  local function cost(cz, radii)
    local parts = { ("%.17g"):format(cz) }
    for i, r in ipairs(radii) do parts[i + 1] = ("%.17g"):format(r) end
    local key = table.concat(parts, ",")
    if costs[key] then return costs[key] end
    local rs = {}
    for i, y in ipairs(ys) do rs[i] = { y, radius(radii, y) } end
    local c = 0
    for v = top - 2, foot + 1 do
      local dv = v + 0.5 + base - cz
      local w = -1.0
      for _, yr in ipairs(rs) do
        local y, r = yr[1], yr[2]
        if r > 0 then
          local t = (dv + y) / (squash * r)
          if -1.0 <= t and t <= 1.0 then w = max(w, r * sqrt(1.0 - t * t)) end
        end
      end
      local nd, sp = needSorted[v], spareSorted[v]
      c = c + 1000 * (#nd - bisectRight(nd, w)) + bisectRight(sp, w)
    end
    costs[key] = c
    return c
  end
  local function drawnRadii(cz)
    local out = {}
    for i = 0, bands do
      local row = need[floor(cz - base - h * i / bands)] or {}
      local m = 0.0
      for _, d in ipairs(row) do m = max(m, d) end
      out[i + 1] = m + 0.5
    end
    return out
  end
  local best
  local k = 0
  while top + h + 0.25 * k <= foot do
    local cz = top + h + base + 0.25 * k
    k = k + 1
    local starts = { {}, drawnRadii(cz) }
    for i = 1, bands + 1 do starts[1][i] = (x1 - x0) / 2.0 end
    for _, radii in ipairs(starts) do
      local c0 = cost(cz, radii)
      local better = true
      while better do
        better = false
        for i = 1, bands + 1 do
          for _, d in ipairs({ -0.25, 0.25, -1.0, 1.0 }) do
            local rr = {}
            for j, r in ipairs(radii) do rr[j] = r end
            rr[i] = max(0.0, rr[i] + d)
            local c1 = cost(cz, rr)
            if c1 < c0 then radii, c0, better = rr, c1, true end
          end
        end
      end
      if best == nil or c0 < best[1] then best = { c0, cz, radii } end
    end
  end
  local cz, radii = best[2], best[3]
  local pts = {}
  for i, p in ipairs(list) do pts[i] = { p[1] + 0.5, p[2] + 0.5 } end
  local grow = 0.0
  while true do
    local profile = {}
    for i, r in ipairs(radii) do profile[i] = { base + h * (i - 1) / bands, r + grow } end
    if covers(K.ProjLathe("lathe", cx, cz, profile, squash, seg), pts) then return cx, cz, profile end
    grow = grow + 0.125
  end
end

--- A round lid drawn as one (dome_fit): the ellipsoid cap on `base`, crowned `height` above it,
--- whose 45-degree view covers every pixel of the piece's own, grown until its polygons do.
--- -> cx, cz, rx, rz, h, y0
local function domeFit(obj, height, base, seg, rings)
  seg, rings = seg or 16, rings or 4
  local pts = drawnPts(obj)
  local x0, x1, top, foot = INF, -INF, INF, -INF
  for _, p in ipairs(pts) do
    x0, x1, top, foot = min(x0, p[1]), max(x1, p[1]), min(top, p[2]), max(foot, p[2])
  end
  x1, foot = x1 + 1, foot + 1
  local k = cos(pi / seg) * cos(pi / (4 * rings))
  local function covered(cx, cz, rx, rz, h, u, v)
    for i = 0, 40 do
      local y = base + h * i / 40.0
      local z = v + y
      if ((u - cx) / (k * rx)) ^ 2 + ((z - cz) / (k * rz)) ^ 2 + ((y - base) / (k * h)) ^ 2 <= 1.0 then
        return true
      end
    end
    return false
  end
  local grow = 0.0
  while true do
    local cx, rx = (x0 + x1) / 2.0, (x1 - x0) / 2.0 + grow
    local d, h = foot - top + 2 * grow, height + 0.0 + grow
    local rz = (d * d - h * h) / (2 * d)
    local cz = foot + grow + base - rz
    local all = true
    for _, p in ipairs(pts) do
      if not covered(cx, cz, rx, rz, h, p[1] + 0.5, p[2] + 0.5) then all = false; break end
    end
    if all then return cx, cz, rx, rz, h, base + 0.0 end
    grow = grow + 0.25
  end
end

--- A row of little turned things cut into one image each (post_parts): a pixel is the one whose
--- top it is under, the lowest one's down to the column's foot.
local function postParts(obj, pw, ph)
  local W, H = obj.w, obj.h
  local own = drawnPts(obj)
  local cnt = counter()
  for _, p in ipairs(own) do cAdd(cnt, floor(p[1] / pw)) end
  local strips = {}
  for _, i in ipairs(cnt.keys) do
    if 2 * cnt.n[i] >= pw * ph then strips[#strips + 1] = i end
  end
  if #strips == 0 then for _, i in ipairs(cnt.keys) do strips[#strips + 1] = i end end
  local near = {}
  for _, i in ipairs(cnt.keys) do
    local best, bd
    for _, j in ipairs(strips) do
      if bd == nil or abs(j - i) < bd then best, bd = j, abs(j - i) end
    end
    near[i] = best
  end
  local out, outKeys = {}, {}
  local sortedStrips = {}
  for i, s in ipairs(strips) do sortedStrips[i] = s end
  table.sort(sortedStrips)
  for _, strip in ipairs(sortedStrips) do
    local mine = {}
    local top, foot = INF, -INF
    for _, p in ipairs(own) do
      if near[floor(p[1] / pw)] == strip then
        mine[#mine + 1] = p
        top, foot = min(top, p[2]), max(foot, p[2])
      end
    end
    foot = foot + 1
    local n = max(1, floor((foot - top) / ph))
    local step = counter()
    local stepPx = {}
    for _, p in ipairs(mine) do
      local s = min(floor((p[2] - top) / ph), n - 1)
      if not stepPx[s] then stepPx[s] = {}; cAdd(step, s, 0) end
      local l = stepPx[s]
      l[#l + 1] = p
    end
    local kept = {}
    for _, s in ipairs(step.keys) do
      if 4 * #stepPx[s] >= pw * ph then kept[#kept + 1] = s end
    end
    if #kept == 0 then for _, s in ipairs(step.keys) do kept[#kept + 1] = s end end
    for _, s in ipairs(step.keys) do
      local best, bd
      for _, j in ipairs(kept) do
        local d = abs(j - s)
        if bd == nil or d < bd or (d == bd and j < best) then best, bd = j, d end
      end
      local key = strip * 4096 + best
      local img = out[key]
      if not img then img = newImg(W, H); out[key] = img; outKeys[#outKeys + 1] = key end
      for _, p in ipairs(stepPx[s]) do img.c[p[2] * W + p[1]] = obj.c[p[2] * W + p[1]] end
    end
  end
  table.sort(outKeys)
  local list = {}
  for i, key in ipairs(outKeys) do list[i] = out[key] end
  return list
end

I._sideImage, I._slabSide, I._tablePlan, I._tableParts = sideImage, slabSide, tablePlan, tableParts
I._ballFit, I._latheFit, I._domeFit, I._postParts = ballFit, latheFit, domeFit, postParts

-- ── a room's layout ─────────────────────────────────────────────────────────

--- A layout as the room reader reads it (voxel_building.LayoutArt): L = { name, w, h, blocks
--- (0-based u16 list: metatile and collision) } over its pair (Art.pair). -> { id, w, h, blocks,
--- metatile(x, y), cellImage(m[, lowerOnly]), upperSource(x, y), tilePixel(tile, pixel),
--- palette(id), primary, secondary }
function I.layoutOf(L, pair)
  local A = Art.layoutArt(L, pair)
  A.blocks = L.blocks
  local band = bit.band
  function A.upperSource(x, y)
    local q = floor((y % 16) / 8) * 2 + floor((x % 16) / 8)
    local e = pair.entries(A.metatile(floor(x / 16), floor(y / 16)))
    local entry = e and e[4 + q] or 0
    local px, py = x % 8, y % 8
    if band(entry, 0x400) ~= 0 then px = 7 - px end
    if band(entry, 0x800) ~= 0 then py = 7 - py end
    return band(entry, 0x3FF), py * 8 + px, floor(entry / 4096) % 16
  end
  function A.tilePixel(tile, pixel)
    local ts = tile < 512 and pair.primary or pair.secondary
    local loc = tile < 512 and tile or tile - 512
    if (loc + 1) * 32 > #ts.tiles then return 0 end
    local b = ts.tiles:byte(loc * 32 + floor(pixel / 8) * 4 + floor((pixel % 8) / 2) + 1)
    return pixel % 2 == 1 and floor(b / 16) or b % 16
  end
  function A.palette(id)
    local ts = id < 6 and pair.primary or pair.secondary
    return ts.palettes[id]
  end
  return A
end

-- a layout's drawing with `draw`'s cells ({ { x, y, metatile } }) laid with those metatiles
-- (drawn_as): the room as a script leaves it
local function drawnAs(io, name, draw)
  local layout = io.layout(name)
  if not layout then return nil end
  if draw and #draw > 0 then
    local blocks = {}
    for k, v in pairs(layout.blocks) do blocks[k] = v end
    for _, d in ipairs(draw) do
      local i = d[2] * layout.w + d[1]
      blocks[i] = blocks[i] - blocks[i] % 1024 + d[3]
    end
    local copy = {}
    for k, v in pairs(layout) do copy[k] = v end
    copy.blocks = blocks
    copy.metatile = function(x, y) return blocks[y * layout.w + x] % 1024 end
    layout = copy
  end
  return layout
end

-- ── reuse: a tile modelled once is modelled everywhere ──────────────────────
--
-- A piece of furniture is modelled in the first room (in the specs' order) that has it. Any other
-- room that repeats its tiles exactly - every cell of the piece's rectangle drawing the same
-- pixels, whatever tileset or metatile number they come from - gets the same model; a thing
-- standing in the room (not a wall) also where its own pixels are drawn again, pixel for pixel.

--- A registry of the pieces modelled so far: I.registry() -> reg
function I.registry()
  return { pieces = {}, keys = {}, arrays = {}, reusedPixels = {}, rooms = {} }
end

-- each cell's drawing as a string, [y][x] (cell_keys): two cells are the same tile when they draw
-- the same pixels
local function cellKeys(reg, layout)
  if layout._keys then return layout._keys end
  local out = {}
  for y = 0, layout.h - 1 do
    local row = {}
    for x = 0, layout.w - 1 do
      local m = layout.metatile(x, y)
      local ck = layout.primary .. "/" .. layout.secondary .. "/" .. m
      local key = reg.keys[ck]
      if not key then
        local img = layout.cellImage(m)
        local parts = {}
        for k = 0, 255 do parts[k + 1] = img[k] end
        key = table.concat(parts, ",")
        reg.keys[ck] = key
        reg.arrays[key] = img
      end
      row[x] = key
    end
    out[y] = row
  end
  layout._keys = out
  return out
end

local function sameRoom(a, b)
  if a.w ~= b.w or a.h ~= b.h then return false end
  for k = 0, a.w * a.h - 1 do
    if a.blocks[k] % 1024 ~= b.blocks[k] % 1024 then return false end
  end
  return true
end

local function cellDrawn(reg, key, want)
  local arr = reg.arrays[key]
  for _, w in ipairs(want) do
    if arr[w[1]] ~= w[2] then return false end
  end
  return true
end

local function looseStarts(reg, p, layout, keys)
  local ai, aj = p.anchor[1], p.anchor[2]
  local want = p.cells[aj * 256 + ai]
  local seen, out = {}, {}
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do
      local key = keys[y][x]
      if seen[key] == nil then seen[key] = cellDrawn(reg, key, want) end
      if seen[key] then out[(y - aj) * 65536 + (x - ai)] = true end
    end
  end
  return out
end

local function drawnAt(reg, p, keys, x, y)
  for ck, want in pairs(p.cells) do
    local i, j = ck % 256, floor(ck / 256)
    if not cellDrawn(reg, keys[y + j][x + i], want) then return false end
  end
  return true
end

--- The furniture already modelled that `layout` repeats (reuse_pieces):
--- { { piece, x, y, pixels (room indices), exact } }
local function reusePieces(reg, io, layout)
  local keys = cellKeys(reg, layout)
  local drawn = {}
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do drawn[keys[y][x]] = true end
  end
  local W = layout.w * 16
  local rooms, candidates = {}, {}
  for _, p in ipairs(reg.pieces) do
    local src = p.layout
    if src ~= layout.id then
      if rooms[src] == nil then
        local other = io.layout(src)
        rooms[src] = other ~= nil and sameRoom(other, layout)
      end
      if not rooms[src] then candidates[#candidates + 1] = p end
    end
  end
  local placed, taken = {}, {}
  for _, exact in ipairs({ true, false }) do
    for _, p in ipairs(candidates) do
      if exact or p.loose then
        local w, h = p.size[1], p.size[2]
        local first = p.keys[0][0]
        if not (exact and not drawn[first]) then
          local loose = exact and {} or looseStarts(reg, p, layout, keys)
          for y = 0, layout.h - h do
            for x = 0, layout.w - w do
              local ok
              if exact then
                ok = keys[y][x] == first
                if ok then
                  for j = 0, h - 1 do
                    for i = 0, w - 1 do
                      if keys[y + j][x + i] ~= p.keys[j][i] then ok = false; break end
                    end
                    if not ok then break end
                  end
                end
              else
                ok = loose[y * 65536 + x] and drawnAt(reg, p, keys, x, y)
              end
              if ok then
                local pts, clash = {}, false
                for _, uv in ipairs(p.pixels) do
                  local k = (y * 16 + uv[2]) * W + x * 16 + uv[1]
                  if taken[k] then clash = true; break end
                  pts[#pts + 1] = k
                end
                if not clash then
                  local set = {}
                  for _, k in ipairs(pts) do taken[k] = true; set[k] = true end
                  placed[#placed + 1] = { p, x, y, set, exact }
                end
              end
            end
          end
        end
      end
    end
  end
  return placed
end

--- Stand the known furniture in `layout` (place_reused); -> the room pixels it draws, the cells
--- it covers ({ [y * w + x] = true }). `ground` nil: a room nobody modelled. `pit`: the room's
--- rectangles that draw the floor below it, where nothing of the room below is stood.
function I.placeReused(reg, io, layout, ground, pit)
  pit = pit or {}
  local pixels, cells = {}, {}
  local painted = {}
  for k = 0, layout.w * layout.h - 1 do painted[layout.blocks[k] % 1024] = true end
  local W = layout.w * 16
  for _, pl in ipairs(reusePieces(reg, io, layout)) do
    local p, x, y, pts, exact = pl[1], pl[2], pl[3], pl[4], pl[5]
    local inPit = false
    for k in pairs(pts) do
      local u, v = k % W, floor(k / W)
      for _, r in ipairs(pit) do
        if r[1] <= u and u < r[3] and r[2] <= v and v < r[4] then inPit = true; break end
      end
      if inPit then break end
    end
    if not inPit then
      local spec = p.spec
      if exact then
        local own = spec.ground[1]
        local on = (ground ~= nil and painted[own]) and own or nil
        spec.reused_at = spec.reused_at or {}
        spec.reused_at[#spec.reused_at + 1] = { layout.id, x, y, on }
      else
        spec.bare_at = spec.bare_at or {}
        spec.bare_at[#spec.bare_at + 1] = { layout.id, x, y }
        spec.own = p.ownPixels
      end
      for k in pairs(pts) do pixels[k] = true end
      for j = 0, p.size[2] - 1 do
        for i = 0, p.size[1] - 1 do cells[(y + j) * layout.w + x + i] = true end
      end
    end
  end
  local rp = reg.reusedPixels[layout.id] or {}
  for k in pairs(pixels) do rp[k] = true end
  reg.reusedPixels[layout.id] = rp
  return pixels, cells
end

--- Remember a room's piece for the rooms that repeat it (register_piece). `art` its drawing;
--- `hidden` what it fills in behind the pieces in front of it; `loose` a thing standing in the
--- room, found by its own pixels too; `own` the pixels it claimed. (Local sets: v * 4096 + u.)
local function registerPiece(reg, pieceSpec, layout, art, hidden, loose, own)
  local x0, y0, w, h = pieceSpec.rect[1], pieceSpec.rect[2], pieceSpec.rect[3], pieceSpec.rect[4]
  local keys = cellKeys(reg, layout)
  local pixels = {}
  for v = 0, h * 16 - 1 do
    for u = 0, w * 16 - 1 do
      local lk = v * 4096 + u
      if art.c[v * art.w + u] and not hidden[lk] and (own == nil or not loose or own[lk]) then
        pixels[#pixels + 1] = { u, v }
      end
    end
  end
  if #pixels == 0 then return end
  local grid = {}
  for j = 0, h - 1 do
    grid[j] = {}
    for i = 0, w - 1 do grid[j][i] = keys[y0 + j][x0 + i] end
  end
  local cells, order = {}, {}
  for _, p in ipairs(pixels) do
    local u, v = p[1], p[2]
    local ck = floor(v / 16) * 256 + floor(u / 16)
    local o = (v % 16) * 16 + u % 16
    local l = cells[ck]
    if not l then l = {}; cells[ck] = l; order[#order + 1] = ck end
    l[#l + 1] = { o, reg.arrays[grid[floor(v / 16)][floor(u / 16)]][o] }
  end
  local anchor, an
  for _, ck in ipairs(order) do
    if an == nil or #cells[ck] > an then anchor, an = ck, #cells[ck] end
  end
  local ownPixels = {}
  for _, p in ipairs(pixels) do ownPixels[p[2] * 4096 + p[1]] = true end
  reg.pieces[#reg.pieces + 1] = {
    spec = pieceSpec, layout = layout.id, size = { w, h }, pixels = pixels, ownPixels = ownPixels,
    keys = grid, cells = cells, anchor = { anchor % 256, floor(anchor / 256) },
    loose = loose and (#pixels >= I.LOOSE_PIXELS or truthy(pieceSpec.found)) or false }
end

--- The cells of a piece whose floor copy (`vOffset` rows down its art) paints something, and the
--- box of what it paints in each (decal_cells). -> cells { { i, j } }, boxes { ["i,j"] = box }
local function decalCells(art, cells, x0, y0, vOffset)
  local out, boxes = {}, {}
  for _, c in ipairs(cells) do
    local i, j = c[1] - x0, c[2] - y0
    local b = bbox(crop(art, i * 16, j * 16 + vOffset, i * 16 + 16, j * 16 + vOffset + 16))
    if b then
      out[#out + 1] = { i, j }
      boxes[i .. "," .. j] = b
    end
  end
  return out, boxes
end

--- Under a piece put at `places`, the floor as drawn there where that is not `ground`'s - a
--- cell's lower layer, if that is floor alone (floor_under). -> { ["x,y"] = { { i, j, lower } } }
local function floorUnder(layout, pc, ground, places, w, h)
  local floorish = {}
  for _, c in ipairs(pc.leave or {}) do floorish[c] = true end
  local gimg = layout.cellImage(ground)
  for k = 0, 255 do floorish[gimg[k]] = true end
  local plain = layout.cellImage(ground, true)
  local under, any = {}, false
  for _, a in ipairs(places) do
    local ax, ay = a[1], a[2]
    for j = 0, h - 1 do
      for i = 0, w - 1 do
        if ax + i >= 0 and ax + i < layout.w and ay + j >= 0 and ay + j < layout.h then
          local mt = layout.metatile(ax + i, ay + j)
          local lower = layout.cellImage(mt, true)
          local subset, same = true, true
          for k = 0, 255 do
            if not floorish[lower[k]] then subset = false end
            if lower[k] ~= plain[k] then same = false end
          end
          if mt ~= ground and subset and not same then
            local key = ax .. "," .. ay
            under[key] = under[key] or {}
            local l = under[key]
            l[#l + 1] = { i, j, lower }
            any = true
          end
        end
      end
    end
  end
  return any and under or nil
end

I._cellKeys, I._reusePieces, I._registerPiece, I._decalCells, I._floorUnder =
  cellKeys, reusePieces, registerPiece, decalCells, floorUnder
I._drawnAs = drawnAs

-- ── a room cut into pieces ──────────────────────────────────────────────────

local function setOf(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end
local function union(a, b)
  local s = {}
  for k in pairs(a) do s[k] = true end
  for k in pairs(b) do s[k] = true end
  return s
end
local function keyOfColours(set)
  local l = {}
  for c in pairs(set) do l[#l + 1] = c end
  table.sort(l)
  return table.concat(l, ",")
end

--- Expand a room spec (interior_specs): spec.interior = { layout, ground = { metatiles },
--- pieces, open, shade, pit, draw }. -> the pieces' specs, each { name, layout, rect = { x0, y0,
--- w, h }, ground, art (an image), parts, owned, placed, placed_patches, when, found, interior },
--- registered with `reg` for the rooms after it. tick(label) yields to the frame (optional).
function I.room(spec, io, reg, tick)
  tick = tick or function() end
  local room = spec.interior
  local layout = drawnAs(io, room.layout, room.draw)
  if not layout then return nil, "no layout " .. tostring(room.layout) end
  local W, H = layout.w * 16, layout.h * 16
  local fpx = {}
  for cy = 0, layout.h - 1 do
    for cx = 0, layout.w - 1 do
      local img = layout.cellImage(layout.metatile(cx, cy))
      for j = 0, 15 do
        local row = (cy * 16 + j) * W + cx * 16
        for i = 0, 15 do fpx[row + i] = img[j * 16 + i] end
      end
    end
  end
  local hexes = fpx
  local floors = {}
  for i, m in ipairs(room.ground) do floors[i] = layout.cellImage(m) end
  local pieces = room.pieces
  local np = #pieces
  tick("room")
  -- floor: a pixel the floor metatile has there too - and, inside a piece's shape, one the open
  -- floor reaches through such pixels
  local match = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local c, k = fpx[y * W + x], (y % 16) * 16 + x % 16
      for _, f in ipairs(floors) do
        if f[k] == c then match[y * W + x] = true; break end
      end
    end
  end
  local grids = {}
  for k, pc in ipairs(pieces) do grids[k] = insideGrid(pc.shape, W, H) end
  tick("room")
  -- a piece of some tiles of the upper layer alone: its pixels only
  for k, pc in ipairs(pieces) do
    if pc.tiles then
      local lo, hi = pc.tiles[1], pc.tiles[2]
      local set = grids[k].set
      for i in pairs(set) do
        local tile, pixel = layout.upperSource(i % W, floor(i / W))
        if not (lo <= tile and tile <= hi and layout.tilePixel(tile, pixel) ~= 0) then set[i] = nil end
      end
    end
  end
  local shaped = {}
  for k = 1, np do
    for i in pairs(grids[k].set) do shaped[i] = true end
  end
  local ground = {}
  for i = 0, W * H - 1 do
    if match[i] and not shaped[i] then ground[i] = true end
  end
  -- the room's front corners, black in the drawing: floor
  local opened = insideGrid(room.open or {}, W, H).set
  local todo = {}
  for i = 0, W * H - 1 do if ground[i] then todo[#todo + 1] = i end end
  while #todo > 0 do
    local i = todo[#todo]
    todo[#todo] = nil
    local x, y = i % W, floor(i / W)
    local ns = { x + 1 < W and i + 1 or nil, x > 0 and i - 1 or nil, y + 1 < H and i + W or nil, y > 0 and i - W or nil }
    for n = 1, 4 do
      local j = ns[n]
      if j and match[j] and not ground[j] then
        ground[j] = true
        todo[#todo + 1] = j
      end
    end
  end
  tick("room")
  -- the floor's shaded variants: their colours are floor wherever they run on from the open floor
  local shade = {}
  for _, m in ipairs(room.shade or {}) do
    if type(m) == "string" then
      shade[tonumber(m, 16)] = true
    else
      local img = layout.cellImage(m)
      for k = 0, 255 do shade[img[k]] = true end
    end
  end
  local owner = {}
  local variantPx = {}
  -- the room's shell, where a piece's copies never take a pixel
  local wallsAt = {}
  for j, p in ipairs(pieces) do
    if truthy(p.fill) or isShellName(p) then
      for i in pairs(grids[j].set) do wallsAt[i] = true end
    end
  end
  -- (the floor the terrain lays under a piece's cells)
  local floorHexes = {}
  do
    local img = layout.cellImage(room.ground[1])
    for k = 0, 255 do floorHexes[img[k]] = true end
  end

  local function variantGroups(k, pc, x0, y0, w, h)
    local vp = variantPx[k]
    local aroundL, floorish = vp.around, vp.floorish
    local rect = {}
    for v = 0, h * 16 - 1 do
      for u = 0, w * 16 - 1 do rect[#rect + 1] = { x0 * 16 + u, y0 * 16 + v } end
    end
    vp.rect = rect
    local groups, order = {}, {}
    local places = { { x0, y0 } }
    for _, a in ipairs(pc.at or {}) do places[#places + 1] = a end
    for _, a in ipairs(places) do
      local dx, dy = (a[1] - x0) * 16, (a[2] - y0) * 16
      local key = {}
      for n, p in ipairs(aroundL) do
        local X, Y = p[1] + dx, p[2] + dy
        local ownPx = false
        if X >= 0 and X < W and Y >= 0 and Y < H then
          local i = Y * W + X
          local o = owner[i]
          ownPx = (o == k or o == -1) and not ground[i] and not floorish[hexes[i]]
        end
        key[n] = ownPx and fpx[Y * W + X] or false
      end
      local n0 = #aroundL
      for n, p in ipairs(rect) do
        local X, Y = p[1] + dx, p[2] + dy
        local mark = false
        if X >= 0 and X < W and Y >= 0 and Y < H then
          local i = Y * W + X
          local o = owner[i]
          mark = (o == nil or ((o == k or o == -1) and floorish[hexes[i]] == true))
            and (not ground[i] or not floorHexes[hexes[i]])
        end
        key[n0 + n] = mark and fpx[Y * W + X] or false
      end
      local parts = {}
      for n, v in ipairs(key) do parts[n] = v and tostring(v) or "-" end
      local ks = table.concat(parts, ",")
      if not groups[ks] then groups[ks] = { key = key, places = {} }; order[#order + 1] = ks end
      local g = groups[ks].places
      g[#g + 1] = { a[1], a[2] }
    end
    local list = {}
    for i, ks in ipairs(order) do list[i] = groups[ks] end
    return list
  end

  local function variantArt(k, art, key, x0, y0, h, shapeOnly)
    local vp = variantPx[k]
    local aroundL, rect = vp.around, vp.rect
    local vart = imgCopy(art)
    for v = 0, 2 * h * 16 - 1 do
      for u = 0, art.w - 1 do vart.c[v * art.w + u] = nil end
    end
    local n0 = #aroundL
    for n, p in ipairs(aroundL) do
      local c = key[n]
      if c then vart.c[(p[2] - y0 * 16) * art.w + (p[1] - x0 * 16)] = c end
    end
    for n, p in ipairs(rect) do
      local c = key[n0 + n]
      if c and not shapeOnly then
        local u, v = p[1] - x0 * 16, p[2] - y0 * 16
        vart.c[(v + h * 16) * art.w + u] = c
        if vart.c[v * art.w + u] == nil then vart.c[v * art.w + u] = c end
      end
    end
    return vart
  end

  -- the furniture an earlier room has modelled, standing here as it is
  local reused, reusedCells = I.placeReused(reg, io, layout, room.ground[1], room.pit)
  for i in pairs(reused) do owner[i] = -1 end
  tick("room")
  local supports = findSupports(pieces, grids, W, H)
  -- how many things' shapes hold each pixel (a room's walls hold them all)
  local shapesAt = {}
  for k, pc in ipairs(pieces) do
    if not (truthy(pc.fill) or pc.facet or truthy(pc.walls)) then
      for i in pairs(grids[k].set) do shapesAt[i] = (shapesAt[i] or 0) + 1 end
    end
  end
  local leaves = autoLeave(pieces, grids, ground, hexes, supports, W, H)
  tick("room")
  local partsOf = {}
  local function leaveParts(colours)
    local key = keyOfColours(colours)
    if partsOf[key] then return partsOf[key] end
    local seen, parts = {}, {}
    for i = 0, W * H - 1 do
      if not seen[i] and colours[hexes[i]] then
        seen[i] = true
        local part, st = {}, { i }
        while #st > 0 do
          local p = st[#st]
          st[#st] = nil
          part[#part + 1] = p
          local x, y = p % W, floor(p / W)
          local ns = { x + 1 < W and p + 1 or nil, x > 0 and p - 1 or nil, y + 1 < H and p + W or nil, y > 0 and p - W or nil }
          for n = 1, 4 do
            local j = ns[n]
            if j and not seen[j] and colours[hexes[j]] then seen[j] = true; st[#st + 1] = j end
          end
        end
        parts[#parts + 1] = part
      end
    end
    partsOf[key] = parts
    return parts
  end

  for k, pc in ipairs(pieces) do
    local g = grids[k]
    local ins = g.set
    local isWallish = truthy(pc.fill) or pc.facet ~= nil
    local leave = setOf(pc.leave)
    if not isWallish then
      for c in pairs(shade) do leave[c] = true end
    end
    local taken = {}
    if supports[k] and not truthy(pc.fill) then
      local sibs = {}
      for j, s in pairs(supports) do
        if s == supports[k] and j ~= k then sibs[#sibs + 1] = j end
      end
      table.sort(sibs)
      taken = supportLeft(k, supports[k], grids, hexes, W, H, sibs)
    end
    local left = {}
    if next(leaves[k]) then
      local roomPx = {}
      for i in pairs(ins) do
        if leaves[k][hexes[i]] then roomPx[i] = true end
      end
      local edge = {}
      for i in pairs(roomPx) do
        local x, y = i % W, floor(i / W)
        if not (x + 1 < W and ins[i + 1]) or not (x > 0 and ins[i - 1]) or not (y + 1 < H and ins[i + W])
            or not (y > 0 and ins[i - W]) then
          edge[i] = true
        end
      end
      for i in pairs(flood(edge, roomPx, W, H)) do left[i] = true end
    end
    if pc.through then
      local own = setOf(pc.leave)
      for i in pairs(ins) do
        if own[hexes[i]] then left[i] = true end
      end
    end
    if next(leave) then
      for _, part in ipairs(leaveParts(leave)) do
        local out = false
        for _, i in ipairs(part) do
          if not ins[i] then out = true; break end
        end
        if out then
          for _, i in ipairs(part) do
            if ins[i] then left[i] = true end
          end
        end
      end
    end
    local cand = {}
    for i in pairs(ins) do
      if owner[i] == nil and (not ground[i] or isWallish or (pc.claim and #pc.claim > 0
          and inside(pc.claim, i % W, floor(i / W)))) and not left[i] then
        cand[i] = true
      end
    end
    if not (isWallish or truthy(pc.walls) or pc.card or isShellName(pc)) then
      local under = {}
      if supports[k] then
        local s = supports[k]
        local stuff = {}
        for i in pairs(grids[s].set) do
          if shapesAt[i] == 1 then stuff[hexes[i]] = true end
        end
        for i in pairs(cand) do
          if grids[s].set[i] and stuff[hexes[i]] then under[i] = true end
        end
      end
      cand = outlineTrim(cand, hexes, under, taken, W)
    else
      for i in pairs(taken) do cand[i] = nil end
    end
    for i in pairs(cand) do owner[i] = k end
    if truthy(pc.at) and next(cand) then
      -- the same piece again: where the room draws its pixels at each place it stands, they are
      -- that copy's
      local mnx, mny = INF, INF
      for i in pairs(cand) do mnx, mny = min(mnx, i % W), min(mny, floor(i / W)) end
      local cx0, cy0 = floor(mnx / 16), floor(mny / 16)
      local aroundSet
      if pc.variants then
        aroundSet = {}
        for i in pairs(around(cand, W, H)) do
          if ins[i] then aroundSet[i] = true end
        end
      else
        aroundSet = cand
      end
      local floorish = union(setOf(pc.leave), shade)
      if pc.variants then
        for i in pairs(aroundSet) do
          if owner[i] == nil and not ground[i] and not floorish[hexes[i]] then owner[i] = k end
        end
      end
      for _, a in ipairs(pc.at) do
        local dx, dy = (a[1] - cx0) * 16, (a[2] - cy0) * 16
        for i in pairs(aroundSet) do
          local X, Y = i % W + dx, floor(i / W) + dy
          if X >= 0 and X < W and Y >= 0 and Y < H then
            local j = Y * W + X
            if owner[j] == nil and not wallsAt[j] then
              local hit
              if not pc.variants then
                hit = fpx[j] == fpx[i]
              else
                hit = not ground[j] and not floorish[hexes[j]]
              end
              if hit then owner[j] = -1 end
            end
          end
        end
      end
      if pc.variants then
        local al = {}
        for _, i in ipairs(sortedIdx(aroundSet)) do al[#al + 1] = { i % W, floor(i / W) } end
        -- (sorted as Python sorts (x, y) pairs: by x, then y)
        table.sort(al, function(a, b)
          if a[1] ~= b[1] then return a[1] < b[1] end
          return a[2] < b[2]
        end)
        variantPx[k] = { cx0 = cx0, cy0 = cy0, around = al, floorish = floorish }
      end
    end
    tick("claims")
  end
  -- each piece's pixels
  local ownedBy = {}
  for k = 1, np do ownedBy[k] = {} end
  for i = 0, W * H - 1 do
    local o = owner[i]
    if o ~= nil and o > 0 then ownedBy[o][i] = true end
  end
  -- furniture on legs: below the hem of its top, the floor between its legs is the floor's
  local legsOf = {}
  for k, pc in ipairs(pieces) do
    local mine = ownedBy[k]
    local skip = pc.legs == false or truthy(pc.base) or pc.card or truthy(pc.fill) or truthy(pc.run)
      or pc.plan ~= nil or not (pc.side == nil or pc.side == "plain")
      or (pc.facet or truthy(pc.walls) or next(mine) == nil or isShellName(pc))
    if not skip then
      local footK = pc.foot
      if footK == nil then
        local my = -INF
        for i in pairs(mine) do my = max(my, floor(i / W)) end
        footK = my + 1
      end
      local release = union(setOf(pc.leave), shade)
      local row, released = legSplit(mine, hexes, footK, floor(pc.height), release, pc.legs, W)
      if row then
        legsOf[k] = row
        for i in pairs(released) do
          owner[i] = nil
          mine[i] = nil
        end
      end
    end
  end
  local walls = {}
  for k, pc in ipairs(pieces) do if truthy(pc.fill) then walls[k] = true end end
  local standing = {}
  for k, sup in pairs(supports) do
    standing[sup] = standing[sup] or {}
    standing[sup][#standing[sup] + 1] = k
  end
  local drawn, skipped = {}, {}
  for k, pc in ipairs(pieces) do
    local mine = ownedBy[k]
    local fill = {}
    local period = pc.fill
    if standing[k] and not truthy(period) then
      for _, j in ipairs(standing[k]) do
        for i in pairs(ownedBy[j]) do
          if grids[k].set[i] then
            local x, y = i % W, floor(i / W)
            for _, d in ipairs({ 4, 8, 12, 16, 2, 6, 10, 14, 18, 20, 24 }) do
              local hit
              for _, xx in ipairs({ x - d, x + d }) do
                if xx >= 0 and xx < W and owner[y * W + xx] == k then hit = xx; break end
              end
              if hit then fill[i] = fpx[y * W + hit]; break end
            end
          end
        end
      end
    end
    if truthy(period) then
      for i, c in pairs(fillHidden(pc, k, owner, fpx, walls, W, H)) do fill[i] = c end
    end
    if next(mine) == nil and not truthy(pc.walls) then
      local reusedHere = false
      for i in pairs(grids[k].set) do
        if owner[i] == -1 then reusedHere = true; break end
      end
      if reusedHere then
        skipped[k] = true
      else
        error(("%s: piece %s claims no pixel"):format(spec.name, pc.name), 0)
      end
    end
    drawn[k] = { mine = mine, fill = fill }
  end
  tick("fills")
  -- the room with what the pieces hide filled in: where hidden faces are dressed from
  local filled = {}
  for i = 0, W * H - 1 do filled[i] = fpx[i] end
  for k = 1, np do
    for i, c in pairs(drawn[k].fill) do filled[i] = c end
  end
  local rects = {}
  for k = 1, np do
    if not skipped[k] then
      local pc = pieces[k]
      local xs0, ys0, xs1, ys1 = INF, INF, -INF, -INF
      local function add(x, y)
        xs0, ys0, xs1, ys1 = min(xs0, x), min(ys0, y), max(xs1, x), max(ys1, y)
      end
      for i in pairs(drawn[k].mine) do add(i % W, floor(i / W)) end
      for i in pairs(drawn[k].fill) do add(i % W, floor(i / W)) end
      if pc.facet then
        local a, b = pc.facet[1], pc.facet[2]
        add(floor(a[1]), floor(a[3]) - 1)
        add(floor(b[1]) - 1, floor(b[3]) - 1)
      end
      for _, wall in ipairs(pc.walls or {}) do
        local wa, wb = wall[1], wall[2]
        add(min(floor(wa[1]), W - 1), min(floor(wa[2]), H - 1))
        add(min(floor(wb[1]), W - 1), min(floor(wb[2]), H - 1))
      end
      for _, c in ipairs(pc.cells or {}) do add(c[1] * 16, c[2] * 16) end
      rects[k] = { floor(xs0 / 16), floor(ys0 / 16), floor(xs1 / 16) + 1, floor(ys1 / 16) + 1 }
    end
  end
  local underMarks = {}
  local function markUnder(x, y)
    local key = y * W + x
    local v = underMarks[key]
    if v == nil then
      local found = {}
      v = false
      for n, step in ipairs({ -1, 1 }) do
        local xx = x
        while xx >= 0 and xx < W and owner[y * W + xx] ~= nil do xx = xx + step end
        if not (xx >= 0 and xx < W) or ground[y * W + xx] or opened[y * W + xx] then found = nil; break end
        found[n] = fpx[y * W + xx]
      end
      if found and found[1] == found[2] then v = found[1] end
      underMarks[key] = v
    end
    return v or nil
  end
  -- the cells a piece stands again in (`at`): its copies'
  local copied = {}
  for k = 1, np do
    local r = rects[k]
    if r then
      for _, a in ipairs(pieces[k].at or {}) do
        for j = 0, r[4] - r[2] - 1 do
          for i = 0, r[3] - r[1] - 1 do copied[(a[2] + j) * 4096 + a[1] + i] = true end
        end
      end
    end
  end
  local decalOf = {}
  for k = 1, np do
    local r = rects[k]
    if r then
      local skipSet = {}
      for _, c in ipairs(pieces[k].skip or {}) do skipSet[c[2] * 4096 + c[1]] = true end
      for cy = r[2], r[4] - 1 do
        for cx = r[1], r[3] - 1 do
          local ck = cy * 4096 + cx
          if not skipSet[ck] and not copied[ck] and decalOf[ck] == nil then decalOf[ck] = k end
        end
      end
    end
  end
  tick("rects")
  local out = {}
  for k, pc in ipairs(pieces) do
    if not skipped[k] then
      local mine, fill = drawn[k].mine, drawn[k].fill
      local r = rects[k]
      local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
      local w, h = x1 - x0, y1 - y0
      local obj = newImg(w * 16, h * 16)
      for i in pairs(mine) do obj.c[(floor(i / W) - y0 * 16) * obj.w + (i % W - x0 * 16)] = fpx[i] end
      for i, c in pairs(fill) do obj.c[(floor(i / W) - y0 * 16) * obj.w + (i % W - x0 * 16)] = c end
      local shell = pc.facet ~= nil or truthy(pc.walls) or next(mine) == nil or isShellName(pc)
      local footRow = pc.foot
      if footRow == nil and next(mine) then
        local my = -INF
        for i in pairs(mine) do my = max(my, floor(i / W)) end
        footRow = my + 1
      end
      local sample
      if footRow ~= nil and not truthy(pc.run) then
        sample = sideImage(pc, mine, filled, fpx, shell, footRow, W, H)
      end
      local plan
      if legsOf[k] then
        local wallZ = pc.against == nil and pc.back or pc.against
        plan = tablePlan(obj, legsOf[k] - y0 * 16, footRow - y0 * 16, floor(pc.height),
          wallZ ~= nil and wallZ - y0 * 16 or nil)
        sample = plan.img
      end
      if sample == nil and not (pc.side == nil or pc.side == "front" or pc.side == "plain") then
        sample = sideImage(pc, mine, filled, fpx, true, 0, W, H)
      end
      local sh = sample and sample.h or 0
      local sw = sample and sample.w or 0
      local lid = pc.top
      local th = lid and (lid[4] - lid[2]) or 0
      local tw = lid and (lid[3] - lid[1]) or 0
      local ch = pc.card and h * 16 or 0
      local uo = 2 * h * 16 + sh + th + ch
      local art = newImg(max(w * 16, sw, tw), uo + h * 16)
      if sample then paste(art, sample, 0, 2 * h * 16) end
      if lid then paste(art, cropFlat(filled, W, H, lid[1], lid[2], lid[3], lid[4]), 0, 2 * h * 16 + sh) end
      paste(art, obj, 0, 0)
      local cells = {}
      for ck, o in pairs(decalOf) do
        if o == k then cells[#cells + 1] = { ck % 4096, floor(ck / 4096) } end
      end
      table.sort(cells, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
      end)
      for _, c in ipairs(cells) do
        local cx, cy = c[1], c[2]
        for j = 0, 15 do
          for i = 0, 15 do
            local x, y = cx * 16 + i, cy * 16 + j
            local lx, ly = x - x0 * 16, y - y0 * 16
            local idx = y * W + x
            local o = owner[idx]
            if not ground[idx] and o == nil and not opened[idx] then
              art.c[ly * art.w + lx] = fpx[idx]
              art.c[(ly + h * 16) * art.w + lx] = fpx[idx]
            elseif o ~= nil and o > 0 and not pieces[o].card then
              local under
              if y + 1 < H and owner[idx + W] ~= nil then under = markUnder(x, y) end
              if under ~= nil then art.c[(ly + uo) * art.w + lx] = under end
            end
          end
        end
      end
      local drawing = art
      if legsOf[k] then
        drawing = imgCopy(art)
        for v = legsOf[k] - y0 * 16, footRow - y0 * 16 - 1 do
          for u = 0, w * 16 - 1 do
            if obj.c[v * obj.w + u] == nil then art.c[v * art.w + u] = nil end
          end
        end
      end
      local side
      if sample then
        side = K.Tile(0, 2 * h * 16, sw, 2 * h * 16 + sh)
      else
        side = pickSide(obj, floor(pc.height))
      end
      local parts
      local back
      if pc.facet then
        local a, b = pc.facet[1], pc.facet[2]
        local ox, oz = x0 * 16, y0 * 16
        parts = { K.Facet(pc.name, { a[1] - ox, a[3] + 1 - oz }, { b[1] - ox, b[3] + 1 - oz }, a[3] + 1 - a[2],
          b[3] + 1 - b[2]) }
      elseif next(mine) == nil then
        parts = {}
      else
        local foot
        if pc.foot ~= nil then
          foot = pc.foot - y0 * 16
        elseif not truthy(pc.fill) then
          local my = -INF
          for i in pairs(mine) do my = max(my, floor(i / W)) end
          foot = my + 1 - y0 * 16
        end
        back = pc.against == nil and pc.back or pc.against
        if back ~= nil then back = back - y0 * 16 - (pc.base or 0) end
        local span
        if pc.anim then
          error(("%s: piece %s: animated pieces are not ported yet"):format(spec.name, pc.name), 0)
        end
        local liveTag = ""
        if pc.flat then
          local band = 2 * h * 16 + sh + th
          paste(art, obj, 0, band)
          local ht = pc.height
          local mnx, mxx, mnz, mxz = INF, -INF, INF, -INF
          for i in pairs(mine) do
            local x, z = i % W - x0 * 16, floor(i / W) - y0 * 16
            mnx, mxx, mnz, mxz = min(mnx, x), max(mxx, x), min(mnz, z), max(mxz, z)
          end
          parts = { K.Ribbon(pc.name .. "_lid", mnx, mxx + 1, mnz, ht, mxz + 1, ht, band + ht) }
        elseif pc.ribbon then
          error(("%s: piece %s: ribbons (animated) are not ported yet"):format(spec.name, pc.name), 0)
        elseif pc.card then
          paste(art, obj, 0, 2 * h * 16 + sh + th)
          parts = { K.Card(pc.name .. liveTag, toArt(obj), foot, 2 * h * 16 + sh + th, pc.base or 0, span) }
        elseif truthy(pc.run) then
          local ox, oz = x0 * 16, y0 * 16
          parts = {}
          for _, run in ipairs(pc.run) do
            local sec = {}
            for n, p in ipairs(run[2]) do sec[n] = { p[1] - ox, p[2] } end
            parts[#parts + 1] = K.ProjRun(pc.name .. "_" .. run[1], sec, run[3] - oz, run[4] - oz)
          end
        elseif pc.plan then
          local ox, oz = x0 * 16, y0 * 16
          local strip
          if sample then
            strip = { 0, sw, 2 * h * 16 + sh }
          else
            strip = { side.rect[1], side.rect[3], side.rect[4] }
          end
          local b0 = pc.base or 0
          local blocks = pc.plan
          if type(blocks[1][1]) == "number" then
            blocks = { { false, blocks, b0, b0 + pc.height, false } }
          end
          parts = {}
          for _, blk in ipairs(blocks) do
            local part, poly, ya, yb, own = blk[1], blk[2], blk[3], blk[4], blk[5]
            local pl = {}
            for n, p in ipairs(poly) do pl[n] = { p[1] - ox, p[2] - oz } end
            parts[#parts + 1] = K.PlanPrism(part and (pc.name .. "_" .. part) or pc.name, pl, ya, yb,
              own and { own[1] - ox, own[2] - ox, own[3] - oz } or strip)
          end
        elseif pc.round == "ball" then
          local cx, cz, rx, rz, profile = ballFit(obj, pc.base or 0)
          parts = { K.ProjLathe(pc.name, cx, cz, profile, rz / rx, 16) }
        elseif pc.round == "lathe" then
          local shapeObj = obj
          if variantPx[k] then
            shapeObj = imgCopy(obj)
            for _, grp in ipairs(variantGroups(k, pc, x0, y0, w, h)) do
              composite(shapeObj, crop(variantArt(k, art, grp.key, x0, y0, h, true), 0, 0, w * 16, h * 16))
            end
          end
          if pc.posts then
            local turn = pc.turn or { 12, 4 }
            local seg, bands = turn[1], turn[2]
            parts = {}
            for n, post in ipairs(postParts(shapeObj, pc.posts[1], pc.posts[2])) do
              local cx, cz, profile = latheFit(post, pc.height, pc.base or 0, 0.7, bands, seg)
              parts[#parts + 1] = K.ProjLathe(("%s_post%d"):format(pc.name, n - 1), cx, cz, profile, 0.7, seg)
            end
          else
            local sq = pc.squash or 0.7
            local turn = pc.turn or { 16, 4 }
            local seg, bands = turn[1], turn[2]
            local cx, cz, profile = latheFit(shapeObj, pc.height, pc.base or 0, sq, bands, seg)
            parts = { K.ProjLathe(pc.name, cx, cz, profile, sq, seg) }
          end
        elseif pc.round == "dome" then
          local cx, cz, rx, rz, crown, rim = domeFit(obj, pc.height, pc.base or 0)
          parts = { K.ProjDome(pc.name, cx, cz, rx, rz, crown, rim, 16, 4) }
        else
          local topTile = lid and K.Tile(0, 2 * h * 16 + sh, tw, 2 * h * 16 + sh + th) or nil
          local solid = pc.solid
          if solid == nil then
            solid = not shell and (truthy(pc.base) or not frontGaps(mine, footRow, W))
          end
          if back == nil and not shell and not legsOf[k] and isFlat(obj, floor(pc.height)) then
            back = foot - 2
          end
          if legsOf[k] then
            parts = tableParts(pc, obj, plan, legsOf[k] - y0 * 16, foot, back, topTile, 2 * h * 16)
          else
            local relief = K.Relief(pc.name, toArt(obj), pc.height, side, {
              foot = foot, solid = solid, back = back, top_tile = topTile, proj_back = not shell,
              against = pc.against ~= nil, see_through = pc.through == true })
            parts = { truthy(pc.base) and K.Lifted(relief, pc.base) or relief }
          end
        end
      end
      for n, wall in ipairs(pc.walls or {}) do
        local wa, wb = wall[1], wall[2]
        local tall = wall[3] or pc.height
        local ox, oz = x0 * 16, y0 * 16
        local behind = next(mine) and "" or "~behind"
        parts[#parts + 1] = K.PlainWall(("%s_side%d%s"):format(pc.name, n - 1, behind), { wa[1] - ox, wa[2] - oz },
          { wb[1] - ox, wb[2] - oz }, -1, tall, side)
      end
      if variantPx[k] then
        cells = {}
        for j = 0, h - 1 do
          for i = 0, w - 1 do cells[#cells + 1] = { x0 + i, y0 + j } end
        end
        local marks = newImg(art.w, h * 16)
        for _, grp in ipairs(variantGroups(k, pc, x0, y0, w, h)) do
          composite(marks, crop(variantArt(k, art, grp.key, x0, y0, h, false), 0, h * 16, art.w, 2 * h * 16))
        end
        paste(art, marks, 0, h * 16)
      end
      local localCells, localBox = decalCells(art, cells, x0, y0, h * 16)
      if #localCells > 0 then
        parts[#parts + 1] = K.Decal(pc.name .. "_floor", localCells, h * 16, nil, localBox)
      end
      local hidden, hiddenBox = decalCells(art, cells, x0, y0, uo)
      if #hidden > 0 then
        parts[#parts + 1] = K.Decal(pc.name .. "_under~behind", hidden, uo, 0.25, hiddenBox)
      end
      local owned
      if truthy(pc.skip) then
        local skipSet = {}
        for _, c in ipairs(pc.skip) do skipSet[c[2] * 4096 + c[1]] = true end
        owned = {}
        for j = 0, h - 1 do
          for i = 0, w - 1 do
            if not skipSet[(y0 + j) * 4096 + x0 + i] then owned[i .. "," .. j] = true end
          end
        end
      end
      local model = { name = spec.name .. "_" .. pc.name, layout = room.layout, rect = { x0, y0, w, h },
                      ground = room.ground, art = art, owned = owned, parts = parts, interior = spec.name,
                      piece = pc }
      if pc.when or truthy(pc.at) or room.draw or (owned ~= nil and next(owned) == nil) then
        local g0 = room.ground[1]
        local places = { { x0, y0 } }
        for _, a in ipairs(pc.at or {}) do places[#places + 1] = { a[1], a[2] } end
        model.placed = {}
        for n, a in ipairs(places) do model.placed[n] = { room.layout, a[1], a[2], g0 } end
        model.placed_patches = floorUnder(layout, pc, g0, places, w, h)
      end
      if pc.when then model.when = { pc.when[1] - x0, pc.when[2] - y0, pc.when[3] } end
      if pc.found then model.found = true end
      if room.draw then model.layoutArt = layout end
      out[#out + 1] = model
      if variantPx[k] then
        local g0 = room.ground[1]
        local groups = variantGroups(k, pc, x0, y0, w, h)
        local base = table.remove(out)
        -- (most places first; Python's sort is stable)
        local ordered = {}
        for n, grp in ipairs(groups) do ordered[n] = { grp, n } end
        table.sort(ordered, function(a, b)
          if #a[1].places ~= #b[1].places then return #a[1].places > #b[1].places end
          return a[2] < b[2]
        end)
        for n, e in ipairs(ordered) do
          local grp = e[1]
          local m = {}
          for key, v in pairs(base) do m[key] = v end
          m.art = variantArt(k, art, grp.key, x0, y0, h, false)
          m.placed = {}
          for i, a in ipairs(grp.places) do m.placed[i] = { room.layout, a[1], a[2], g0 } end
          if n > 1 then m.name = ("%s_v%d"):format(base.name, n - 1) end
          m.placed_patches = floorUnder(layout, pc, g0, grp.places, w, h)
          out[#out + 1] = m
        end
      end
      if not (pc.alone or model.placed) then
        local hiddenL, ownL = {}, {}
        for i in pairs(fill) do hiddenL[(floor(i / W) - y0 * 16) * 4096 + (i % W - x0 * 16)] = true end
        for i in pairs(mine) do ownL[(floor(i / W) - y0 * 16) * 4096 + (i % W - x0 * 16)] = true end
        registerPiece(reg, out[#out], layout, drawing, hiddenL,
          not (truthy(pc.fill) or pc.facet ~= nil or truthy(pc.walls)), ownL)
      end
      tick("pieces")
    end
  end
  return out
end

--- A piece's model as the generator builds it (build_models): its triangles and its texture (the
--- kernel's art); with `bare`, the piece as it stands on another room's floor - nothing of its own
--- room in its art but its own pixels, and no floor marks.
function I.build(piece, bare)
  local art = piece.art
  local parts = piece.parts
  if bare then
    local own = piece.own or {}
    local b = newImg(art.w, art.h)
    local w, h = piece.rect[3], piece.rect[4]
    for k, c in pairs(art.c) do
      local u, v = k % art.w, floor(k / art.w)
      if not (u < w * 16 and v < h * 16) or own[v * 4096 + u] then b.c[k] = c end
    end
    -- (beyond its drawing's rectangle the art is kept: its sides' stretches)
    for v = 0, h * 16 - 1 do
      for u = 0, w * 16 - 1 do
        if not own[v * 4096 + u] then b.c[v * art.w + u] = nil end
      end
    end
    art = b
    local kept = {}
    for _, p in ipairs(parts) do
      if not (p.name and p.name:sub(-6) == "_floor") then kept[#kept + 1] = p end
    end
    parts = kept
  end
  local mesh = K.build(parts)
  return { tris = mesh.tris, art = art, tex = toArt(art) }
end

return I
end
