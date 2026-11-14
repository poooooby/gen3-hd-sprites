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

return Check
