-- Fences built post by post from their drawing (Battle Scene: Overworld).
--
-- A fence is not a wall: the General tileset's grey fence is a row of posts with two-pixel rails
-- between them, and Mauville's a row of short logs standing apart. Every post is found by its own
-- drawn top (a fence post's light 4x2 cap, a log's cut face) wherever it is drawn, and stands
-- where the drawing puts it: its foot where its front ends on the ground (or, hidden by the next
-- post south, the family's own height); a post is a box, a rail a bar between two posts of a row
-- or down a column, a log an upright cylinder. Their faces the 45-degree view sees take the
-- drawing projected, their sides a strip of the family's reference metatile; what the drawing
-- paints round them on the ground (the rails' shadow) lies flat on it (a Decal).
--
-- Ported from Emerald 3DS's scripts/voxel_fence.py (by Zallax and contributors, CC BY-NC-SA 4.0,
-- https://github.com/ZallaxDev/emerald-3ds; see LICENSE). A run is built whole here (not cut into
-- blocks), so no post stands across a block's seam.
--
-- Art images are { w, h, px = { r, g, b, a, ... } } (0..1, row major).

return function(K)
  local Fence = {}
  local CELL = 16
  local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

  local function newArt(w, h)
    local px = {}
    for i = 1, w * h * 4 do px[i] = 0 end
    return { w = w, h = h, px = px }
  end
  Fence.newArt = newArt
  local function get(a, u, v)
    local o = (v * a.w + u) * 4
    return a.px[o + 1], a.px[o + 2], a.px[o + 3], a.px[o + 4]
  end
  local function set(a, u, v, r, g, b, al)
    local o = (v * a.w + u) * 4
    a.px[o + 1], a.px[o + 2], a.px[o + 3], a.px[o + 4] = r, g, b, al
  end
  local function key(r, g, b) return floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5) end
  local function opaque(a, u, v) return u >= 0 and v >= 0 and u < a.w and v < a.h and a.px[(v * a.w + u) * 4 + 4] >= 0.5 end
  local function colourAt(a, u, v) local r, g, b = get(a, u, v); return key(r, g, b) end

  -- the colours of a rectangle's drawn pixels
  local function rectColours(img, rect)
    local out = {}
    for v = rect[2], rect[4] - 1 do
      for u = rect[1], rect[3] - 1 do
        if opaque(img, u, v) then out[colourAt(img, u, v)] = true end
      end
    end
    return out
  end

  -- every (u, v) where the pattern (rows of colour keys) is drawn whole
  local function find(img, pattern)
    local ph, pw = #pattern, #pattern[1]
    local out = {}
    for v = 0, img.h - ph do
      for u = 0, img.w - pw do
        local ok = true
        for b = 1, ph do
          for a = 1, pw do
            if not opaque(img, u + a - 1, v + b - 1) or colourAt(img, u + a - 1, v + b - 1) ~= pattern[b][a] then
              ok = false
              break
            end
          end
          if not ok then break end
        end
        if ok then out[#out + 1] = { u, v } end
      end
    end
    return out
  end

  -- a cell-tall strip of the reference's front: its rows repeated down
  local function strip(ref, rect)
    local u0, v0, u1, v1 = rect[1], rect[2], rect[3], rect[4]
    local out = newArt(u1 - u0, CELL)
    for v = 0, CELL - 1 do
      local sv = v0 + v % (v1 - v0)
      for u = u0, u1 - 1 do set(out, u - u0, v, get(ref, u, sv)) end
    end
    return out
  end

  -- down column u from row v: where the post's front ends on the ground, or nil where more of the
  -- fence goes on over it, or it runs off what is composed
  local function footOf(img, u, v, trunk, body, drawn)
    while v < img.h and opaque(img, u, v) and trunk[colourAt(img, u, v)] do v = v + 1 end
    if v >= img.h or not drawn[floor(u / CELL) .. "," .. floor(v / CELL)] then return nil end
    if opaque(img, u, v) and body[colourAt(img, u, v)] then return nil end
    return v
  end

  --- The art pixels a mesh draws in the GBA's 45-degree view, its "~behind" faces left out:
  --- { [v * W + u] = true } over W x H.
  function Fence.drawnBy(tris, tex, W, H)
    local out = {}
    for _, t in ipairs(tris) do
      if not (t.tag and t.tag:find("~behind", 1, true)) then
        local p = {}
        for k = 1, 3 do p[k] = { t[k][1], t[k][3] - t[k][2], t[k][4], t[k][5] } end
        local x0, y0, x1, y1, x2, y2 = p[1][1], p[1][2], p[2][1], p[2][2], p[3][1], p[3][2]
        local area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if math.abs(area) >= 1e-9 then
          local inv = 1 / area
          for py = max(0, floor(min(y0, y1, y2))), min(H - 1, ceil(max(y0, y1, y2))) do
            local cy = py + 0.5
            for px_ = max(0, floor(min(x0, x1, x2))), min(W - 1, ceil(max(x0, x1, x2))) do
              local cx = px_ + 0.5
              local a = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) * inv
              local b = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) * inv
              local c = 1 - a - b
              if a >= -1e-7 and b >= -1e-7 and c >= -1e-7 then
                local tu = floor(a * p[1][3] + b * p[2][3] + c * p[3][3])
                local tv = floor(a * p[1][4] + b * p[2][4] + c * p[3][4])
                if opaque(tex, tu, tv) then out[py * W + px_] = true end
              end
            end
          end
        end
      end
    end
    return out
  end

  --- One run of a fence: { tex (the texture: drawing, ground band, side strip), parts }.
  ---   w, h            the run's rectangle, in cells
  ---   owned           { [i .. "," .. j] = true }
  ---   compose(keep)   -> its cells' drawing over (w x (h + 2)) cells from the row north of it:
  ---                    their upper layer, and lower-layer pixels of the colours in `keep`
  ---   ref             the family's reference metatile's upper layer (16 x 16 art)
  ---   family          the spec's `posts` table
  function Fence.build(w, h, owned, compose, ref, family)
    local fu, fv, fw, fh = family.find[1], family.find[2], family.find[3], family.find[4]
    local pattern = {}
    for b = 1, fh do
      pattern[b] = {}
      for a = 1, fw do pattern[b][a] = colourAt(ref, fu + a - 1, fv + b - 1) end
    end
    local body = rectColours(ref, family.body)
    local trunk = rectColours(ref, family.trunk)
    local ext = compose(body)
    local drawn = {}
    for c in pairs(owned) do
      local i, j = c:match("(-?%d+),(-?%d+)")
      drawn[tonumber(i) .. "," .. (tonumber(j) + 1)] = true
    end
    local W, H0 = w * CELL, h * CELL
    local posts = {}
    for _, at in ipairs(find(ext, pattern)) do
      local u, v = at[1], at[2]
      local r = v - CELL
      local own = r >= 0 and r < H0 and owned[floor(u / CELL) .. "," .. floor(r / CELL)] == true
      if family.kind == "box" then
        local px0 = u - fu + family.post[1]
        local px1 = u - fu + family.post[2]
        local d = family.depth
        local top = r - fv + family.top
        local foot = footOf(ext, u - fu + family.scan, v - fv + family.top + d, trunk, body, drawn)
        local hgt = foot and (foot - CELL - top - d) or family.hidden
        local z0 = top + hgt
        posts[#posts + 1] = { x0 = px0, x1 = px1, z0 = z0, z1 = z0 + d, h = hgt, own = own }
      else
        local dx, rx, rz = family.log[1], family.log[2], family.log[3]
        local cx = u - fu + dx
        local mid = r - fv + family.top
        local foot = footOf(ext, u - fu + family.scan, v - fv + family.trunk_row, trunk, body, drawn)
        local cz = foot and (foot - CELL - rz) or (mid + family.hidden)
        local hgt = cz - mid
        posts[#posts + 1] = { x0 = cx - rx, x1 = cx + rx, z0 = cz - rz, z1 = cz + rz, h = hgt, own = own,
                              log = { cx, cz, rx, rz } }
      end
    end
    -- the art: the run's rows and the row south (ext from its second row)
    local art = newArt(W, H0 + CELL)
    for v = 0, H0 + CELL - 1 do
      for u = 0, W - 1 do set(art, u, v, get(ext, u, v + CELL)) end
    end
    local o = H0 + CELL
    local R = o + H0
    local st = strip(ref, family.strip)
    local tex = newArt(max(W, st.w), R + CELL)
    for v = 0, art.h - 1 do for u = 0, W - 1 do set(tex, u, v, get(art, u, v)) end end
    for v = 0, CELL - 1 do for u = 0, st.w - 1 do set(tex, u, R + v, get(st, u, v)) end end
    local side = { 0, st.w, R + CELL }
    local parts, rails = {}, {}
    if family.kind == "box" then
      local ry0, ry1 = family.rail[1], family.rail[2]
      for _, p in ipairs(posts) do
        if p.own then
          parts[#parts + 1] = K.PlanPrism("post", { { p.x0, p.z0 }, { p.x1, p.z0 }, { p.x1, p.z1 }, { p.x0, p.z1 } }, -1, p.h, side)
        end
      end
      -- rails along a row: between the posts of one row, wherever the drawing has their top and
      -- their front's first row
      local levels, seen = {}, {}
      for _, p in ipairs(posts) do
        local k = p.z0 .. ":" .. p.z1
        if p.own and not seen[k] then seen[k] = true; levels[#levels + 1] = { p.z0, p.z1 } end
      end
      table.sort(levels, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
      for _, lv in ipairs(levels) do
        local z0, z1 = lv[1], lv[2]
        local r0, r1 = floor(z0 - ry1), floor(z1 - ry1)
        if r0 >= 0 then
          local inside = {}
          for _, p in ipairs(posts) do if p.z0 == z0 and p.z1 == z1 then inside[#inside + 1] = { p.x0, p.x1 } end end
          local run = {}
          for u = 0, W do
            local ok = u < W
            if ok then
              for v = r0, r1 do if not opaque(art, u, v) then ok = false; break end end
            end
            if ok then
              for _, ab in ipairs(inside) do if ab[1] <= u and u < ab[2] then ok = false; break end end
            end
            if ok then
              run[#run + 1] = u
            else
              if #run > 0 then rails[#rails + 1] = { run[1], run[#run] + 1, z0, z1 } end
              run = {}
            end
          end
        end
      end
      -- rails down a column: from a post to the next one south in its line, where the drawing
      -- goes on unbroken between their tops
      local byX, order = {}, {}
      for _, p in ipairs(posts) do
        local k = p.x0 .. ":" .. p.x1
        if not byX[k] then byX[k] = {}; order[#order + 1] = k end
        table.insert(byX[k], p)
      end
      for _, k in ipairs(order) do
        local line = byX[k]
        table.sort(line, function(a, b) return a.z0 < b.z0 end)
        for i = 1, #line - 1 do
          local p, q = line[i], line[i + 1]
          if p.own and q.z0 > p.z1 then
            local u = floor(p.x0) + 1
            local v0, v1 = floor(p.z0 - p.h), floor(q.z0 - q.h)
            local ok = v1 - v0 <= 2 * CELL
            if ok then
              for vv = max(0, v0), v1 - 1 do
                if not (vv < art.h and opaque(art, u, vv)) then ok = false; break end
              end
            end
            if ok then
              local inset = family.rail_inset or 1
              rails[#rails + 1] = { p.x0 + inset, p.x1 - inset, p.z1, q.z0 }
            end
          end
        end
      end
      for _, r in ipairs(rails) do
        parts[#parts + 1] = K.PlanPrism("rail", { { r[1], r[3] }, { r[2], r[3] }, { r[2], r[4] }, { r[1], r[4] } }, ry0, ry1, side)
      end
    else
      local bark = K.Tile(0, R, st.w, R + CELL)
      for _, p in ipairs(posts) do
        if p.own then
          parts[#parts + 1] = K.Cylinder("log", p.log[1], p.log[2], p.log[3], p.log[4], -1, p.h, bark,
            { sides = family.sides or 16 })
        end
      end
    end
    -- what the drawing paints on the ground round them: its pixels no post or rail draws at 45
    -- degrees, of no colour of the fence's own
    local covered = Fence.drawnBy(K.build(parts).tris, tex, W, H0)
    local north = {}
    for _, p in ipairs(posts) do
      if not p.own then
        local a, b, c, d = floor(p.x0), floor(p.z0 - p.h), ceil(p.x1), ceil(p.z1)
        for v = max(0, b), min(H0, d) - 1 do
          for u = max(0, a), min(W, c) - 1 do north[v * W + u] = true end
        end
      end
    end
    for cell in pairs(owned) do
      local i, j = cell:match("(-?%d+),(-?%d+)")
      i, j = tonumber(i), tonumber(j)
      if not owned[i .. "," .. (j - 1)] then
        for u = i * CELL, i * CELL + CELL - 1 do
          for v = j * CELL, j * CELL + CELL - 1 do
            if covered[v * W + u] then break end
            if opaque(art, u, v) and body[colourAt(art, u, v)] then north[v * W + u] = true end
          end
        end
      end
    end
    local decal, cells = {}, {}
    for v = 0, H0 - 1 do
      for u = 0, W - 1 do
        local idx = v * W + u
        if opaque(art, u, v) and not covered[idx] and not north[idx] and not body[colourAt(art, u, v)] then
          set(tex, u, o + v, get(art, u, v))
          local ck = floor(u / CELL) .. "," .. floor(v / CELL)
          local lu, lv = u % CELL, v % CELL
          local bx = decal[ck]
          if not bx then
            decal[ck] = { lu, lv, lu + 1, lv + 1 }
            cells[#cells + 1] = { floor(u / CELL), floor(v / CELL) }
          else
            decal[ck] = { min(bx[1], lu), min(bx[2], lv), max(bx[3], lu + 1), max(bx[4], lv + 1) }
          end
        end
      end
    end
    if #cells > 0 then parts[#parts + 1] = K.Decal("shadow", cells, o, 0.5, decal) end
    return { tex = tex, parts = parts, posts = posts }
  end

  return Fence
end
