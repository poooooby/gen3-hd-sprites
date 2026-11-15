-- The proofs of a building model against its drawing (dev only, never shipped): Emerald 3DS's
-- ortho_check and density_check (3ds_port/scripts/voxel_building.py; by Zallax and contributors,
-- CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), written in Lua over the
-- kernel's meshes (src/scene/models/kernel.lua). WoobleView's own building specs - FireRed's,
-- which have no reference build to compare against - pass only when both hold.
--
--   Check.ortho(mesh, art, exact, margin) -> wrong, missing, extra, image
--     The model rendered in the GBA's projection (a point (x, y, z) lands at u = x, v = z - y, the
--     nearer the larger y + z) and compared with the drawing over `exact` (rectangles { x0, y0, x1,
--     y1[, behind] }; nil: the whole art): pixels drawn in the wrong colour, drawn pixels nothing
--     covers, pixels covered where the drawing has ground (allowed where `behind`). Faces tagged
--     "~depth" or "~behind" are real depth the drawing never shows and are not judged.
--     art = { w, h, at(x, y) -> 0xRRGGBB or nil where clear }. `image` (when asked: margin) the
--     render's colours { [y * W + x] = c } and its size, for a sheet.
--   Check.density(mesh, tolerance) -> { { tag, along, down, shear }, ... }
--     Every face lays its art one texel a pixel along its horizontal and cos(b) + sin(b) texels a
--     pixel down its fall line (b its pitch), unsheared: no stretched texel ever reaches the screen.
--     Faces tagged "~clamp" or "~proj" are exempt.

local Check = {}
local floor, ceil, abs, sqrt, min, max, asin, cos, sin = math.floor, math.ceil, math.abs, math.sqrt,
  math.min, math.max, math.asin, math.cos, math.sin

local function judged(tag)
  tag = tag or ""
  return not (tag:find("~depth", 1, true) or tag:find("~behind", 1, true))
end

function Check.ortho(mesh, art, exact, margin)
  local W, H = art.w, art.h
  local M = margin or 32
  local RW, RH = W + 2 * M, H + M
  local depth, color, owner = {}, {}, {}
  for _, t in ipairs(mesh.tris) do
    if judged(t.tag) then
      local v0, v1, v2 = t[1], t[2], t[3]
      local x0, y0, d0 = v0[1] + M, v0[3] - v0[2] + M, v0[2] + v0[3]
      local x1, y1, d1 = v1[1] + M, v1[3] - v1[2] + M, v1[2] + v1[3]
      local x2, y2, d2 = v2[1] + M, v2[3] - v2[2] + M, v2[2] + v2[3]
      local area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
      if abs(area) >= 1e-9 then
        local inv = 1.0 / area
        local shade = t.shade or 1.0
        for py = max(0, floor(min(y0, y1, y2))), min(RH - 1, ceil(max(y0, y1, y2))) do
          local cy = py + 0.5
          for px = max(0, floor(min(x0, x1, x2))), min(RW - 1, ceil(max(x0, x1, x2))) do
            local cx = px + 0.5
            local a = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) * inv
            local b = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) * inv
            local c = 1.0 - a - b
            if a >= -1e-7 and b >= -1e-7 and c >= -1e-7 then
              local d = a * d0 + b * d1 + c * d2
              local idx = py * RW + px
              if d > (depth[idx] or -1e30) then
                local tu = floor(a * v0[4] + b * v1[4] + c * v2[4])
                local tv = floor(a * v0[5] + b * v1[5] + c * v2[5])
                local col = tu >= 0 and tv >= 0 and tu < W and tv < H and art.at(tu, tv) or nil
                if col then
                  depth[idx], owner[idx] = d, true
                  local r, g, bl = floor(col / 65536), floor(col / 256) % 256, col % 256
                  color[idx] = floor(r * shade) * 65536 + floor(g * shade) * 256 + floor(bl * shade)
                end
              end
            end
          end
        end
      end
    end
  end
  local wrong, missing, extra = 0, 0, 0
  local marks = {}
  for _, rg in ipairs(exact or { { 0, 0, W, H } }) do
    local behind = rg[5]
    for y = rg[2], rg[4] - 1 do
      for x = rg[1], rg[3] - 1 do
        local want = art.at(x, y)
        local idx = (y + M) * RW + x + M
        if want then
          if not owner[idx] then
            missing = missing + 1; marks[idx] = 0xFF00FF
          elseif color[idx] ~= want then
            wrong = wrong + 1; marks[idx] = 0xFF0000
          end
        elseif owner[idx] and not behind then
          extra = extra + 1; marks[idx] = 0x00FFFF
        end
      end
    end
  end
  return wrong, missing, extra, { w = RW, h = RH, color = color, marks = marks, margin = M }
end

--- A room's pieces drawn together in the GBA's projection, the nearer over the farther:
--- meshes = { { tris, at(u, v) -> colour or nil (the piece's texture), ox, oy (where its art's
--- top left stands in the room, pixels) } }, over a W x H room. -> colour, owner (by y * W + x;
--- owner the mesh's index), each pixel's tag.
function Check.render(meshes, W, H)
  local depth, color, owner, tags = {}, {}, {}, {}
  for k, m in ipairs(meshes) do
    for _, t in ipairs(m.tris) do
      if judged(t.tag) then
        local v0, v1, v2 = t[1], t[2], t[3]
        local x0, y0, d0 = v0[1] + m.ox, v0[3] - v0[2] + m.oy, v0[2] + v0[3] + m.oy
        local x1, y1, d1 = v1[1] + m.ox, v1[3] - v1[2] + m.oy, v1[2] + v1[3] + m.oy
        local x2, y2, d2 = v2[1] + m.ox, v2[3] - v2[2] + m.oy, v2[2] + v2[3] + m.oy
        local area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) >= 1e-9 then
          local inv = 1.0 / area
          local shade = t.shade or 1.0
          for py = max(0, floor(min(y0, y1, y2))), min(H - 1, ceil(max(y0, y1, y2))) do
            local cy = py + 0.5
            for px = max(0, floor(min(x0, x1, x2))), min(W - 1, ceil(max(x0, x1, x2))) do
              local cx = px + 0.5
              local a = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) * inv
              local b = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) * inv
              local c = 1.0 - a - b
              if a >= -1e-7 and b >= -1e-7 and c >= -1e-7 then
                local d = a * d0 + b * d1 + c * d2
                local idx = py * W + px
                if d > (depth[idx] or -1e30) then
                  local tu = floor(a * v0[4] + b * v1[4] + c * v2[4])
                  local tv = floor(a * v0[5] + b * v1[5] + c * v2[5])
                  local col = m.at(tu, tv)
                  if col then
                    depth[idx], owner[idx], tags[idx] = d, k, t.tag
                    local r, g, bl = floor(col / 65536), floor(col / 256) % 256, col % 256
                    color[idx] = floor(r * shade) * 65536 + floor(g * shade) * 256 + floor(bl * shade)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return color, owner, tags
end

function Check.density(mesh, tolerance)
  tolerance = tolerance or 1e-3
  local bad = {}
  for _, t in ipairs(mesh.tris) do
    local tag = t.tag or ""
    if not (tag:sub(-6) == "~clamp" or tag:sub(-5) == "~proj") then
      local p0, p1, p2 = t[1], t[2], t[3]
      local e1 = { p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3] }
      local e2 = { p2[1] - p0[1], p2[2] - p0[2], p2[3] - p0[3] }
      local n = { e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1] }
      local nl = sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
      if nl >= 1e-9 then
        n = { n[1] / nl, n[2] / nl, n[3] / nl }
        local h, f
        if abs(n[2]) > 1 - 1e-9 then
          h, f = { 1, 0, 0 }, { 0, 0, 1 }
        else
          local hl = sqrt(n[3] * n[3] + n[1] * n[1])
          h = { n[3] / hl, 0, -n[1] / hl }
          f = { h[2] * n[3] - h[3] * n[2], h[3] * n[1] - h[1] * n[3], h[1] * n[2] - h[2] * n[1] }
        end
        local beta = asin(min(1.0, sqrt(n[1] * n[1] + n[3] * n[3])))
        local expect = cos(beta) + sin(beta)
        local a1 = e1[1] * h[1] + e1[2] * h[2] + e1[3] * h[3]
        local b1 = e1[1] * f[1] + e1[2] * f[2] + e1[3] * f[3]
        local a2 = e2[1] * h[1] + e2[2] * h[2] + e2[3] * h[3]
        local b2 = e2[1] * f[1] + e2[2] * f[2] + e2[3] * f[3]
        local det = a1 * b2 - a2 * b1
        if abs(det) >= 1e-9 then
          local du1, dv1 = p1[4] - p0[4], p1[5] - p0[5]
          local du2, dv2 = p2[4] - p0[4], p2[5] - p0[5]
          local dh1, dh2 = (du1 * b2 - du2 * b1) / det, (dv1 * b2 - dv2 * b1) / det
          local df1, df2 = (du2 * a1 - du1 * a2) / det, (dv2 * a1 - dv1 * a2) / det
          local along, down = sqrt(dh1 * dh1 + dh2 * dh2), sqrt(df1 * df1 + df2 * df2)
          local shear = abs(dh1 * df1 + dh2 * df2)
          if abs(along - 1.0) > tolerance or abs(down - expect) > tolerance or shear > tolerance then
            bad[#bad + 1] = { tag, along, down / expect, shear }
          end
        end
      end
    end
  end
  return bad
end

-- ── the proofs as the drivers run them (tests/drivers/model_check.lua, room_check.lua, review.lua) ──
-- Each returns a result { name, ok, wrong, missing, extra / over, judged, stretched, sheet }, the
-- sheet { w, h, at(x, y) -> 0xRRGGBB } three panels wide: the drawing | the model at 45 degrees |
-- the marks (red wrong, magenta missing, cyan extra, amber over) on the render dimmed.

local function colourOf(px, w, x, y)
  local o = (y * w + x) * 4
  if (px[o + 4] or 0) < 0.5 then return nil end
  return floor(px[o + 1] * 255 + 0.5) * 65536 + floor(px[o + 2] * 255 + 0.5) * 256 + floor(px[o + 3] * 255 + 0.5)
end
Check.colourOf = colourOf

local function dim(g)
  return floor(floor(g / 65536) / 3) * 65536 + floor(floor(g / 256) % 256 / 3) * 256 + floor(g % 256 / 3)
end
Check.dim = dim

--- The cell { x, y } the most faults gather round (5 x 5 cells), of per = { [cy * 4096 + cx] = n },
--- or nil.
function Check.focus(per)
  local best, bx, by = 0, nil, nil
  for k in pairs(per) do
    local cx, cy = k % 4096, floor(k / 4096)
    local n = 0
    for dy = -2, 2 do for dx = -2, 2 do n = n + (per[(cy + dy) * 4096 + cx + dx] or 0) end end
    if n > best then best, bx, by = n, cx, cy end
  end
  return bx and { bx, by } or nil
end

--- Three W x H panels side by side, each at(x, y) -> colour or nil (black).
function Check.sheet(W, H, a, b, c)
  local panels = { a, b, c }
  return { w = W * #panels, h = H, at = function(x, y)
    local p = panels[floor(x / W) + 1]
    return p and p(x % W, y) or 0
  end }
end

function Check.writePPM(path, sheet)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(("P6\n%d %d\n255\n"):format(sheet.w, sheet.h))
  local row = {}
  for y = 0, sheet.h - 1 do
    for x = 0, sheet.w - 1 do
      local c = sheet.at(x, y) or 0
      row[#row + 1] = string.char(floor(c / 65536) % 256, floor(c / 256) % 256, c % 256)
    end
  end
  f:write(table.concat(row))
  f:close()
  return true
end

--- A building spec's model (hd._sceneModel(name)) against its drawing over its exact rectangles.
function Check.building(hd, name, exact)
  local md = hd._sceneModel(name)
  if not md then return nil end
  local art, tex = md.art, md.tex or md.art
  exact = exact or md.spec.exact
  local refAt = function(x, y) return colourOf(art.px, art.w, x, y) end
  -- (rendered with the model's own texture, judged against the drawing: the sizes may differ)
  local texArt = { w = art.w, h = art.h, at = function(x, y)
    return x < tex.w and y < tex.h and colourOf(tex.px, tex.w, x, y) or nil
  end }
  local _, _, _, img = Check.ortho({ tris = md.tris }, texArt, exact, 32)
  local W, M = img.w, img.margin
  local wrong, missing, extra, judgedN = 0, 0, 0, 0
  local marks = {}
  for _, rg in ipairs(exact or { { 0, 0, art.w, art.h } }) do
    for y = rg[2], rg[4] - 1 do
      for x = rg[1], rg[3] - 1 do
        local want = refAt(x, y)
        local idx = (y + M) * W + x + M
        local got = img.color[idx]
        if want then
          judgedN = judgedN + 1
          if got == nil then missing = missing + 1; marks[idx] = 0xFF00FF
          elseif got ~= want then wrong = wrong + 1; marks[idx] = 0xFF0000 end
        elseif got ~= nil and not rg[5] then
          extra = extra + 1; marks[idx] = 0x00FFFF
        end
      end
    end
  end
  local bad = Check.density({ tris = md.tris })
  return { name = name, kind = "building", ok = wrong == 0 and missing == 0 and extra == 0 and #bad == 0,
    wrong = wrong, missing = missing, extra = extra, judged = judgedN, stretched = bad, marks = marks,
    W = W, M = M,
    sheet = Check.sheet(W, img.h,
      function(x, y) local ax, ay = x - M, y - M
        return ax >= 0 and ay >= 0 and ax < art.w and ay < art.h and refAt(ax, ay) or nil end,
      function(x, y) return img.color[y * W + x] end,
      function(x, y) return marks[y * W + x] or dim(img.color[y * W + x] or 0) end) }
end

--- A room's pieces (every piece standing in it: modelled there, reused there, or found by its
--- pixels) against the room as drawn. rooms = hd._rooms(); r one of them.
function Check.room(hd, rooms, r, log)
  local A = hd._roomLayout(r.layout)
  if not A then return nil, "no layout " .. tostring(r.layout) end
  local W, H = A.w * 16, A.h * 16
  local function drawn(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return nil end
    local img = A.cellImage(A.metatile(floor(x / 16), floor(y / 16)))
    return img[(y % 16) * 16 + x % 16]
  end
  local meshes, stretched = {}, {}
  local function texAt(tex)
    return function(u, v)
      if u < 0 or v < 0 or u >= tex.w or v >= tex.h then return nil end
      return colourOf(tex.px, tex.w, u, v)
    end
  end
  for _, r2 in ipairs(rooms) do
    for _, pc in ipairs(r2.pieces or {}) do
      local at = {}
      if pc.placed then
        for _, p in ipairs(pc.placed) do if p[1] == r.layout then at[#at + 1] = { p[2], p[3] } end end
      elseif pc.layout == r.layout then
        at[#at + 1] = { pc.rect[1], pc.rect[2] }
      end
      for _, p in ipairs(pc.reused_at or {}) do if p[1] == r.layout then at[#at + 1] = { p[2], p[3] } end end
      -- (found by its own pixels in a room drawn otherwise round it: its bare twin stands there)
      local bare = {}
      for _, p in ipairs(pc.bare_at or {}) do if p[1] == r.layout then bare[#bare + 1] = { p[2], p[3] } end end
      if #bare > 0 then
        local okT, twin = xpcall(hd._roomBuild, debug.traceback, pc, true)
        if okT then
          for _, p in ipairs(bare) do
            meshes[#meshes + 1] = { tris = twin.tris, ox = p[1] * 16, oy = p[2] * 16, piece = pc, at = texAt(twin.tex) }
          end
        end
      end
      if #at > 0 then
        local okB, md = xpcall(hd._roomBuild, debug.traceback, pc)
        if not okB then
          if log then log(("  FAIL build %s: %s"):format(pc.name, tostring(md))) end
        else
          local bad = Check.density({ tris = md.tris })
          if #bad > 0 then stretched[#stretched + 1] = ("%s (%d, %s)"):format(pc.name, #bad, tostring(bad[1][1])) end
          for _, p in ipairs(at) do
            meshes[#meshes + 1] = { tris = md.tris, ox = p[1] * 16, oy = p[2] * 16, piece = pc, at = texAt(md.tex) }
          end
        end
      end
    end
  end
  local color, owner = Check.render(meshes, W, H)
  local wrong, missing, over, covered, marks, byPiece = 0, 0, 0, 0, {}, {}
  local function note(k, what, x, y)
    local m = meshes[k]
    local name = m and m.piece.name or "?"
    local b = byPiece[name]
    if not b then b = { wrong = 0, missing = 0, x0 = x, y0 = y, x1 = x, y1 = y }; byPiece[name] = b end
    b[what] = b[what] + 1
    b.x0, b.y0, b.x1, b.y1 = min(b.x0, x), min(b.y0, y), max(b.x1, x), max(b.y1, y)
  end
  -- (a pixel the covering piece doesn't own - a top rising over what is drawn behind it, at 45
  -- degrees as Emerald 3DS's rooms stand - is counted apart: over)
  for idx, c in pairs(color) do
    covered = covered + 1
    local x, y = idx % W, floor(idx / W)
    if c ~= drawn(x, y) then
      local m = meshes[owner[idx]]
      local own = m and m.piece.own
      if own and not own[(y - m.oy) * 4096 + (x - m.ox)] then
        over = over + 1; marks[idx] = 0xFFC000
      else
        wrong = wrong + 1; marks[idx] = 0xFF0000; note(owner[idx], "wrong", x, y)
      end
    end
  end
  for k, m in ipairs(meshes) do
    for key in pairs(m.piece.own or {}) do
      local x, y = m.ox + key % 4096, m.oy + floor(key / 4096)
      if x >= 0 and y >= 0 and x < W and y < H and color[y * W + x] == nil then
        missing = missing + 1; marks[y * W + x] = 0xFF00FF; note(k, "missing", x, y)
      end
    end
  end
  local placed = {}
  for _, m in ipairs(meshes) do placed[m.piece.name] = (placed[m.piece.name] or 0) + 1 end
  -- (where the faults gather: the cell whose 5 x 5 cells round it hold the most, for a shot there)
  local per = {}
  for idx, c in pairs(marks) do
    if c ~= 0xFFC000 then
      local k = floor(floor(idx / W) / 16) * 4096 + floor(idx % W / 16)
      per[k] = (per[k] or 0) + 1
    end
  end
  return { name = r.name, kind = "room", layout = r.layout, error = r.error,
    ok = wrong == 0 and missing == 0 and #stretched == 0,
    wrong = wrong, missing = missing, over = over, judged = covered, pieces = #meshes,
    stretched = stretched, byPiece = byPiece, placed = placed, focus = Check.focus(per),
    sheet = Check.sheet(W, H,
      function(x, y) return drawn(x, y) end,
      function(x, y) return color[y * W + x] or drawn(x, y) end,
      function(x, y) return marks[y * W + x] or dim(color[y * W + x] or drawn(x, y) or 0) end) }
end

return Check
