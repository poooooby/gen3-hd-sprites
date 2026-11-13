-- Mountains read off the drawing (Battle Scene: Overworld; src/scene/relief_solve.lua's part):
-- the maps whose mountains are drawn with the General tileset's rock, read pixel by pixel as
-- tops, faces and rims on one canvas a group of maps wide, split into terraces and solved cell by
-- cell. Emerald 3DS's gen_voxel_relief.py drawn_canvas, drawn_role, _wrapped, _clusters,
-- _rim_gaps, _neck, split_wrapped, drawn_prepare, solve_drawn and pier_ends (by Zallax and
-- contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE).
-- Changes here: a canvas's pixel kinds are kept a string a row (a group's canvas runs to twelve
-- million pixels), the rock pixels' votes counted over a sliding window, and a region's pixels
-- kept after the reading only at the cells' middles (all that is read of them later).

local floor, ceil, min, max, abs, sqrt = math.floor, math.ceil, math.min, math.max, math.abs, math.sqrt
local byte, char, concat = string.byte, string.char, table.concat

return function(S)
  local Solve, Art = S.Solve, S.Art
  local C, SETS = Solve.C, Solve.SETS
  local K, KX, KY = Solve.K, Solve.KX, Solve.KY
  local LEVEL, STEP, PER_CELL = C.LEVEL, C.STEP, C.PER_CELL
  local GROUND, TOP, FACE, FLECK, RIM, VOID, FREE = C.GROUND, C.TOP, C.FACE, C.FLECK, C.RIM, C.VOID, C.FREE
  local FOOTPRINT, REGION_MIN, THIN = C.FOOTPRINT, C.REGION_MIN, C.THIN
  local FACE_SOUTH, SIDE_WEST, SIDE_EAST = SETS.FACE_SOUTH, SETS.SIDE_WEST, SETS.SIDE_EAST
  local SEA_CAPS, BOULDER, DIRT, FLAT_ROLES = SETS.SEA_CAPS, SETS.BOULDER, SETS.DIRT, SETS.FLAT_ROLES
  local WRAP_GROUPS = SETS.WRAP_GROUPS
  local ROCK_TOP, ROCK_RIM, ROCK_FACE, ROCK_FLECK, ROCK_ALL =
    Solve.ROCK_TOP, Solve.ROCK_RIM, Solve.ROCK_FACE, Solve.ROCK_FLECK, Solve.ROCK_ALL
  local tick = S.tick
  local grid2 = Solve.grid2
  -- (a tick every `n` steps of a long loop: a flood over the open sea runs millions of them)
  local steps_ = 0
  local function tickEvery(n)
    steps_ = steps_ + 1
    if steps_ >= n then
      steps_ = 0
      tick()
    end
  end

  -- ── drawn_role ────────────────────────────────────────────────────────────────
  -- ROLE_REFERENCE's order: FACE_SOUTH's ids under 0x200 in Python's set order, then SIDE_WEST's,
  -- then SIDE_EAST's
  local function pyset(list) return Art.setOrder(list, Art.hashInt) end
  local ROLE_REFERENCE, REF_IDS = {}, {}
  do
    for _, m in ipairs(pyset({ 0x07C, 0x0A9, 0x09F, 0x0A7, 0x091, 0x079, 0x1B0, 0x0AF, 0x0CF, 0x1F0, 0x1F1, 0x33B, 0x33C })) do
      if m < 0x200 then ROLE_REFERENCE[#ROLE_REFERENCE + 1] = { m, "face" } end
    end
    for _, m in ipairs(pyset({ 0x070, 0x073 })) do ROLE_REFERENCE[#ROLE_REFERENCE + 1] = { m, "west" } end
    for _, m in ipairs(pyset({ 0x072, 0x075, 0x0A2 })) do ROLE_REFERENCE[#ROLE_REFERENCE + 1] = { m, "east" } end
    for _, r in ipairs(ROLE_REFERENCE) do REF_IDS[r[1]] = true end
  end
  local function rockPixels(art, m, lowerOnly)
    local img = art.cellImage(m, lowerOnly)
    local out, n = {}, 0
    for k = 0, 255 do
      if ROCK_ALL[img[k]] then
        out[k] = img[k]
        n = n + 1
      end
    end
    return out, n
  end
  local rolesDrawn = S.ROLES_DRAWN
  local refs
  local function drawnRole(art, m)
    local key = art.primary .. "|" .. art.secondary .. "|" .. m .. "|" .. tostring(art.reading)
    local hit = rolesDrawn[key]
    if hit then return hit[1], hit[2] end
    local role, low = nil, false
    if FACE_SOUTH[m] or SIDE_WEST[m] or SIDE_EAST[m] then
      role = FACE_SOUTH[m] and "face" or SIDE_WEST[m] and "west" or "east"
    elseif art.primary == "general" then
      if not refs then
        refs = {}
        for i, r in ipairs(ROLE_REFERENCE) do
          local px, n = rockPixels(art, r[1])
          refs[i] = { px, n, r[2] }
        end
      end
      local hi, lo = art.cellImage(m), art.cellImage(m, true)
      local cover, rockCover = 0, false
      for k = 0, 255 do
        if hi[k] ~= lo[k] then
          cover = cover + 1
          if ROCK_ALL[hi[k]] then rockCover = true end
        end
      end
      local upper = cover >= 64 and not rockCover
      for pass = 1, 2 do
        local lowPass = pass == 2
        if lowPass and not upper then break end
        local a, na = rockPixels(art, m, lowPass)
        if na > 0 then
          for _, ref in ipairs(refs) do
            local b, nb = ref[1], ref[2]
            local same, union = 0, nb
            for k, c in pairs(a) do
              if b[k] == c then same = same + 1 end
              if b[k] == nil then union = union + 1 end
            end
            if same >= 0.9 * union then
              role, low = ref[3], lowPass and not REF_IDS[m]
              break
            end
          end
        end
        if role then break end
      end
    end
    rolesDrawn[key] = { role, low }
    return role, low
  end
  S.drawnRole = drawnRole

  -- ── drawn_canvas ─────────────────────────────────────────────────────────────
  local VOID_ROW = char(VOID):rep(16)
  local GROUND_ROW = char(GROUND):rep(16)
  local FACE_ROW = char(FACE):rep(16)
  local GROUND_ROWS, FACE_ROWS = {}, {}
  for j = 0, 15 do GROUND_ROWS[j], FACE_ROWS[j] = GROUND_ROW, FACE_ROW end
  local tileKinds = {}
  local rockyWater = S.ROCKY_WATER
  local function kindRows(art, m, lowerOnly, stair)
    local key = art.primary .. "|" .. art.secondary .. "|" .. m .. "|" .. (lowerOnly and 0 or 1) .. "|"
      .. (stair and 1 or 0) .. "|" .. tostring(art.reading)
    local rows = tileKinds[key]
    if rows then return rows end
    rows = {}
    local img = art.cellImage(m, lowerOnly)
    for j = 0, 15 do
      local r = {}
      for i = 0, 15 do
        local c = img[j * 16 + i]
        r[i + 1] = stair and FREE or ROCK_TOP[c] and TOP or ROCK_FACE[c] and FACE or ROCK_FLECK[c] and FLECK
          or ROCK_RIM[c] and RIM or GROUND
      end
      rows[j] = char(unpack(r))
    end
    tileKinds[key] = rows
    return rows
  end

  function S.drawnCanvas(name)
    local g = S.DRAWN_BY[name]
    local members = g.members
    local layouts = {}
    for _, lid in ipairs(members) do layouts[lid] = S.openRoles(lid) end
    for _, lid in ipairs(members) do S.layoutArt(lid) end
    local CW, CH = 0, 0
    for _, lid in ipairs(members) do
      CW = max(CW, g.at[lid][1] + layouts[lid].w)
      CH = max(CH, g.at[lid][2] + layouts[lid].h)
    end
    local W, H = CW * 16, CH * 16
    local cellRows = grid2(CW, CH)        -- each cell's 16 rows of kinds (strings)
    local blocked, side, flat = grid2(CW, CH, false), grid2(CW, CH, 0), grid2(CW, CH, false)
    local faceLow = {}
    for _, lid in ipairs(members) do
      local ox, oy = g.at[lid][1], g.at[lid][2]
      local L, A = layouts[lid], S.artMemo[lid]
      local props = S.propsIn(lid)
      local keep = {}
      if S.aliasOf(lid) then
        local ledges = S.ledgeCells(L)
        for k in pairs(ledges) do keep[k] = true end
        for y = 0, L.h - 1 do
          for x = 0, L.w - 1 do
            if L.behaviour(x, y) == S.BERRY then keep[K(x, y)] = true end
          end
        end
      end
      for cy = 0, L.h - 1 do
        if cy % 8 == 0 then tick() end
        for cx = 0, L.w - 1 do
          local X, Y = ox + cx, oy + cy
          repeat
            if keep[K(cx, cy)] then
              flat[Y][X] = "floor"
              cellRows[Y][X] = GROUND_ROWS
              break
            end
            if props[K(cx, cy)] then
              local e = A.entries(A.metatile(cx, cy))
              local all = true
              for q = 0, 3 do
                local t = e and e[q] % 1024
                if t and not (t >= 432 and t < 462) then all = false end
              end
              if all then
                flat[Y][X] = "water"
                cellRows[Y][X] = GROUND_ROWS
                break
              end
            end
            local role = L.role_at(cx, cy)
            blocked[Y][X] = L.blocked(cx, cy) and (role == "tree" or role == "wall" or role == "prop")
            local m = A.metatile(cx, cy)
            local dRole, dLow = drawnRole(A, m)
            if dLow and role ~= "tree" then dRole, dLow = nil, false end
            side[Y][X] = dRole == "west" and 1 or dRole == "east" and -1 or 0
            if dRole == "face" then faceLow[K(X, Y)] = true end
            local beh = L.behaviour(cx, cy)
            if beh == S.WATERFALL then
              flat[Y][X] = "fall"
              cellRows[Y][X] = FACE_ROWS
              break
            end
            local tkey = L.secondary .. "|" .. m
            if role == "water" and rockyWater[tkey] == nil then
              local img = A.cellImage(m)
              local n = 0
              for k = 0, 255 do if ROCK_ALL[img[k]] then n = n + 1 end end
              rockyWater[tkey] = n >= 0.5 * 256
            end
            if dRole ~= "face" and not FACE_SOUTH[m] and ((FLAT_ROLES[role] and not L.warps[cx .. "," .. cy]
                and not L.covers(m) and not (role == "water" and rockyWater[tkey]) and not SEA_CAPS[m])
                or S.FLAT_BEHAVIOURS[beh]) then
              flat[Y][X] = S.FLAT_BEHAVIOURS[beh] and "bridge" or (role == "water" or role == "signpost") and role
                or "floor"
            end
            local lowerOnly = props[K(cx, cy)] or (dRole == "face" and dLow) or false
            local stair = role == "stair" and not flat[Y][X]
            if DIRT[m] then
              cellRows[Y][X] = GROUND_ROWS
              break
            end
            cellRows[Y][X] = kindRows(A, m, lowerOnly, stair)
          until true
        end
      end
      tick()
    end
    -- a bridge's ends, drawn over the player where they cross a rock's lip, are the bridge
    local grow = true
    while grow do
      grow = false
      for _, lid in ipairs(members) do
        local ox, oy = g.at[lid][1], g.at[lid][2]
        local L = layouts[lid]
        for cy = 0, L.h - 1 do
          for cx = 0, L.w - 1 do
            local r = L.role_at(cx, cy)
            if not flat[oy + cy][ox + cx] and (r == "floor" or r == "stair") then
              for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local x, y = cx + d[1], cy + d[2]
                if x >= 0 and x < L.w and y >= 0 and y < L.h and flat[oy + y][ox + x] == "bridge" then
                  flat[oy + cy][ox + cx] = "bridge"
                  grow = true
                  break
                end
              end
            end
          end
        end
      end
    end
    -- a pier: walked planks drawn over the player, a run of them out into the water
    local pierSeq = {}
    for _, lid in ipairs(members) do
      local ox, oy = g.at[lid][1], g.at[lid][2]
      local L, A = layouts[lid], S.artMemo[lid]
      local planks, plankList = {}, {}
      for cy = 0, L.h - 1 do
        for cx = 0, L.w - 1 do
          if not flat[oy + cy][ox + cx] and L.role_at(cx, cy) == "floor" and not L.blocked(cx, cy)
              and not S.SANDS[L.behaviour(cx, cy)] and L.covers(A.metatile(cx, cy)) then
            planks[K(cx, cy)] = true
            plankList[#plankList + 1] = { cx, cy }
          end
        end
      end
      -- sorted(planks): by x, then y
      table.sort(plankList, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
      local seen = {}
      for _, start in ipairs(plankList) do
        local ks = K(start[1], start[2])
        if not seen[ks] then
          local run, stack = {}, { start }
          seen[ks] = true
          while #stack > 0 do
            local c = table.remove(stack)
            run[#run + 1] = c
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local q = { c[1] + d[1], c[2] + d[2] }
              local kq = K(q[1], q[2])
              if planks[kq] and not seen[kq] then
                seen[kq] = true
                stack[#stack + 1] = q
              end
            end
          end
          local sides, ns = {}, 0
          for _, c in ipairs(run) do
            for i, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local x, y = c[1] + d[1], c[2] + d[2]
              if x >= 0 and x < L.w and y >= 0 and y < L.h and L.role_at(x, y) == "water" and not sides[i] then
                sides[i] = true
                ns = ns + 1
              end
            end
          end
          if ns >= 3 then
            for _, c in ipairs(run) do pierSeq[#pierSeq + 1] = K(ox + c[1], oy + c[2]) end
          end
        end
      end
    end
    local pier = {}
    for _, k in ipairs(pierSeq) do pier[k] = true end
    S.PIER[name] = { set = pier, seq = pierSeq }
    -- the canvas's kinds, a string a row
    local kind = {}
    for y = 0, H - 1 do
      local cy, j = floor(y / 16), y % 16
      local parts = {}
      local row = cellRows[cy]
      for cx = 0, CW - 1 do
        local r = row[cx]
        parts[cx + 1] = r and r[j] or VOID_ROW
      end
      kind[y] = concat(parts)
    end
    cellRows = nil
    tick()
    -- a rock pixel is what most rock round it is: the votes over a (2R+1)^2 window
    local R = C.MAJORITY
    local colT, colF = {}, {}
    for x = 0, W - 1 do colT[x], colF[x] = 0, 0 end
    local function addRow(y, d)
      local s = kind[y]
      for x = 0, W - 1 do
        local k = byte(s, x + 1)
        if k == TOP or k == RIM then colT[x] = colT[x] + d
        elseif k == FACE then colF[x] = colF[x] + d end
      end
    end
    for y = 0, min(R, H - 1) do addRow(y, 1) end
    local voted = {}
    for y = 0, H - 1 do
      -- the window's rows: y - R .. y + R (clipped)
      local s = kind[y]
      local out
      local t, f = 0, 0
      for x = 0, min(R, W - 1) do t, f = t + colT[x], f + colF[x] end
      for x = 0, W - 1 do
        local k = byte(s, x + 1)
        if k == TOP or k == FACE or k == FLECK then
          if not out then
            out = {}
            for i = 1, W do out[i] = byte(s, i) end
          end
          out[x + 1] = t > f and TOP or FACE
        end
        -- slide: drop column x - R, add column x + R + 1
        if x - R >= 0 then t, f = t - colT[x - R], f - colF[x - R] end
        if x + R + 1 < W then t, f = t + colT[x + R + 1], f + colF[x + R + 1] end
      end
      if out then
        local parts = {}
        for i = 1, W, 4096 do parts[#parts + 1] = char(unpack(out, i, min(W, i + 4095))) end
        voted[y] = concat(parts)
      else
        voted[y] = s
      end
      if y - R >= 0 then addRow(y - R, -1) end
      if y + R + 1 < H then addRow(y + R + 1, 1) end
      if y % 64 == 0 then tick() end
    end
    return layouts, CW, CH, voted, blocked, side, flat, faceLow
  end

  -- ── terraces the flood joined (_wrapped .. split_wrapped) ─────────────────────
  local WRAP_DROP, WRAP_COLUMNS, WRAP_CUT, WRAP_POCKET = C.WRAP_DROP, C.WRAP_COLUMNS, C.WRAP_CUT, C.WRAP_POCKET
  local WRAP_REACH, WRAP_DEEP = C.WRAP_REACH, C.WRAP_DEEP

  local function wrapped(region, kind, side, south, W, H)
    local out, order = {}, {}
    local function add(r, hi, lo)
      if not out[r] then out[r] = {}; order[#order + 1] = r end
      out[r][#out[r] + 1] = { hi, lo }
    end
    local function k(x, y) return byte(kind[y], x + 1) end
    for x = 0, W - 1 do
      local y = 0
      tickEvery(64)
      while y < H do
        if k(x, y) ~= FACE then
          y = y + 1
        else
          local y0 = y
          while y < H and k(x, y) == FACE do y = y + 1 end
          if y0 > 0 and y < H and y - y0 >= WRAP_DROP and region[y][x] >= 0 and region[y0 - 1][x] == region[y][x] then
            local n = 0
            for j = y0, y - 1 do if south[K(floor(x / 16), floor(j / 16))] then n = n + 1 end end
            if n * 2 > y - y0 then add(region[y][x], { x, y0 - 1 }, { x, y }) end
          end
        end
      end
    end
    for x = 0, W - 1 do
      local y = 0
      tickEvery(64)
      while y < H do
        if k(x, y) ~= RIM then
          y = y + 1
        else
          local y0 = y
          while y < H and k(x, y) == RIM do y = y + 1 end
          local r = y < H and region[y][x] or -1
          if r >= 0 and y0 >= WRAP_DEEP and y + WRAP_DEEP <= H then
            local ok = true
            for kk = 1, WRAP_DEEP do
              if not (k(x, y0 - kk) == TOP and region[y0 - kk][x] == r) then ok = false; break end
            end
            if ok then
              for kk = 0, WRAP_DEEP - 1 do
                if not (k(x, y + kk) == TOP and region[y + kk][x] == r) then ok = false; break end
              end
            end
            if ok then add(r, { x, y }, { x, y0 - 1 }) end
          end
        end
      end
    end
    for y = 0, H - 1 do
      local x = 0
      tickEvery(64)
      while x < W do
        if k(x, y) ~= FACE then
          x = x + 1
        else
          local x0 = x
          while x < W and k(x, y) == FACE do x = x + 1 end
          local cy = floor(y / 16)
          if x0 > 0 and x < W and x - x0 >= WRAP_DROP and region[y][x] >= 0 and region[y][x0 - 1] == region[y][x]
              and side[cy][floor(x0 / 16)] ~= 0 and side[cy][floor((x - 1) / 16)] ~= 0 then
            if side[cy][floor(x0 / 16)] > 0 then add(region[y][x], { x, y }, { x0 - 1, y })
            else add(region[y][x], { x0 - 1, y }, { x, y }) end
          end
        end
      end
    end
    return out, order
  end

  local function cmpPair(a, b)
    -- ((x, y), (x, y)) tuples
    if a[1][1] ~= b[1][1] then return a[1][1] < b[1][1] end
    if a[1][2] ~= b[1][2] then return a[1][2] < b[1][2] end
    if a[2][1] ~= b[2][1] then return a[2][1] < b[2][1] end
    return a[2][2] < b[2][2]
  end
  local function samePair(a, b)
    return a[1][1] == b[1][1] and a[1][2] == b[1][2] and a[2][1] == b[2][1] and a[2][2] == b[2][2]
  end
  local function clusters(prs, near)
    near = near or 2
    local sorted_ = {}
    for i, p in ipairs(prs) do sorted_[i] = p end
    table.sort(sorted_, cmpPair)
    local groups = {}
    for _, pr in ipairs(sorted_) do
      local c = { floor(pr[1][1] / 16), floor(pr[1][2] / 16) }
      local hits, rest = {}, {}
      for _, g in ipairs(groups) do
        local hit = false
        for _, d in pairs(g.cells) do
          if max(abs(c[1] - d[1]), abs(c[2] - d[2])) <= near then hit = true; break end
        end
        if hit then hits[#hits + 1] = g else rest[#rest + 1] = g end
      end
      local merged = { cells = { [K(c[1], c[2])] = c }, list = { pr } }
      for _, g in ipairs(hits) do
        for kk, d in pairs(g.cells) do merged.cells[kk] = d end
        for _, p in ipairs(g.list) do merged.list[#merged.list + 1] = p end
      end
      rest[#rest + 1] = merged
      groups = rest
    end
    local out = {}
    for i, g in ipairs(groups) do out[i] = g.list end
    return out
  end

  local function rimGaps(kind, W, H, reach)
    reach = reach or 4
    local out = {}
    local function k(x, y) return byte(kind[y], x + 1) end
    for y = 0, H - 1 do
      local s = kind[y]
      for x = 0, W - 1 do
        local kx = byte(s, x + 1)
        if kx == TOP or kx == GROUND then
          for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
            local dx, dy = d[1], d[2]
            local back, fwd = false, false
            for kk = 1, reach do
              local xx, yy = x - kk * dx, y - kk * dy
              if xx >= 0 and xx < W and yy >= 0 and yy < H and k(xx, yy) == RIM then back = true; break end
            end
            if back then
              for kk = 1, reach do
                local xx, yy = x + kk * dx, y + kk * dy
                if xx >= 0 and xx < W and yy >= 0 and yy < H and k(xx, yy) == RIM then fwd = true; break end
              end
            end
            if back and fwd then
              out[K(x, y)] = true
              break
            end
          end
        end
      end
      if y % 32 == 0 then tick() end
    end
    return out
  end

  -- the narrowest cut between tops and feet in region r (sets keyed K(x, y))
  local function neck(region, r, tops, feet, gaps, W, H, limit)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for kk in pairs(tops) do x0, y0, x1, y1 = min(x0, KX(kk)), min(y0, KY(kk)), max(x1, KX(kk)), max(y1, KY(kk)) end
    for kk in pairs(feet) do x0, y0, x1, y1 = min(x0, KX(kk)), min(y0, KY(kk)), max(x1, KX(kk)), max(y1, KY(kk)) end
    local bx0, by0, bx1, by1 = x0 - WRAP_REACH, y0 - WRAP_REACH, x1 + WRAP_REACH, y1 + WRAP_REACH
    local function inside(qx, qy) return bx0 <= qx and qx <= bx1 and by0 <= qy and qy <= by1 end
    local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local function steps(p, fn)
      if gaps[p] then return end
      local x, y = KX(p), KY(p)
      for _, d in ipairs(DIRS) do
        local qx, qy = x + d[1], y + d[2]
        if qx >= 0 and qx < W and qy >= 0 and qy < H and region[qy][qx] == r then
          local q = K(qx, qy)
          if not gaps[q] then fn(q, qx, qy) end
        end
      end
    end
    local flow = {}
    local function fk(p, q) return p * 4 + (q - p == 1 and 0 or q - p == -1 and 1 or q > p and 2 or 3) end
    local function reach()
      local prev, queue, qi = {}, {}, 1
      for kk in pairs(tops) do
        prev[kk] = false
        queue[#queue + 1] = kk
      end
      while qi <= #queue do
        local p = queue[qi]
        qi = qi + 1
        tickEvery(50000)
        if feet[p] then return prev, p end
        steps(p, function(q, qx, qy)
          if prev[q] == nil and inside(qx, qy) and (flow[fk(p, q)] or 0) < 1 then
            prev[q] = p
            queue[#queue + 1] = q
          end
        end)
      end
      return prev, nil
    end
    local function spread(start, isTops, allowed, cap)
      local seen, n = {}, 0
      local queue, qi = {}, 1
      for kk in pairs(start) do
        seen[kk] = true
        n = n + 1
        queue[#queue + 1] = kk
      end
      while qi <= #queue do
        local p = queue[qi]
        qi = qi + 1
        local stop
        steps(p, function(q, qx, qy)
          if stop ~= nil then return end
          if not seen[q] and allowed(p, q, qx, qy) then
            if feet[q] and isTops then stop = false; return end
            seen[q] = true
            n = n + 1
            queue[#queue + 1] = q
            if cap and n >= cap then stop = true end
          end
        end)
        if stop == false then return nil end
        if stop == true then return seen, n end
      end
      return seen, n
    end
    for width = 0, limit do
      local prev, ending = reach()
      if ending ~= nil then
        while prev[ending] do
          local p = prev[ending]
          flow[fk(p, ending)] = (flow[fk(p, ending)] or 0) + 1
          flow[fk(ending, p)] = (flow[fk(ending, p)] or 0) - 1
          ending = p
        end
      else
        local near = prev
        local side, nside = spread(tops, true, function(p, q, qx, qy)
          return near[q] ~= nil or not inside(qx, qy) or near[p] == nil
        end)
        if side == nil then return nil end
        local far, nfar = spread(feet, false, function(p, q) return not side[q] end,
          nside < WRAP_POCKET and WRAP_POCKET or nil)
        return side, nside, far, nfar, width
      end
    end
    return nil
  end

  local function splitWrapped(region, sizes, kind, side, south, W, H)
    local made = {}
    local tried = {}
    local gaps
    while true do
      local todo = {}
      local out, order = wrapped(region, kind, side, south, W, H)
      for _, r in ipairs(order) do
        for _, grp in ipairs(clusters(out[r])) do
          local keys = {}
          for i, p in ipairs(grp) do keys[i] = p[1][1] .. "," .. p[1][2] .. "," .. p[2][1] .. "," .. p[2][2] end
          table.sort(keys)
          local key = r .. ":" .. concat(keys, ";")
          if #grp >= WRAP_COLUMNS and not tried[key] then
            todo[#todo + 1] = { #grp, r, grp, key }
          end
        end
      end
      if #todo == 0 then return made end
      gaps = gaps or rimGaps(kind, W, H)
      -- sorted(todo, reverse=True): by size, region, the pairs as listed
      table.sort(todo, function(a, b)
        if a[1] ~= b[1] then return a[1] > b[1] end
        if a[2] ~= b[2] then return a[2] > b[2] end
        local ga, gb = a[3], b[3]
        for i = 1, min(#ga, #gb) do
          if not samePair(ga[i], gb[i]) then return cmpPair(gb[i], ga[i]) end
        end
        return #ga > #gb
      end)
      local done = false
      for _, t in ipairs(todo) do
        local r, grp, key = t[2], t[3], t[4]
        tried[key] = true
        local tops, feet = {}, {}
        for _, p in ipairs(grp) do
          tops[K(p[1][1], p[1][2])] = true
          feet[K(p[2][1], p[2][2])] = true
        end
        local nt, nf = {}, {}
        for kk in pairs(tops) do if not feet[kk] then nt[kk] = true end end
        for kk in pairs(feet) do if not tops[kk] then nf[kk] = true end end
        tops, feet = nt, nf
        local cut, far, nfar, width
        while next(tops) and next(feet) do
          local side_, nside, far_, nfar_, width_ = neck(region, r, tops, feet, gaps, W, H, WRAP_CUT)
          if side_ == nil then break end
          cut, far, nfar, width = side_, far_, nfar_, width_
          if width == 0 then
            cut = nil
            break
          end
          if nside < WRAP_POCKET then
            for kk in pairs(cut) do tops[kk] = nil end
          elseif nfar < WRAP_POCKET then
            for kk in pairs(far) do feet[kk] = nil end
          else
            break
          end
          cut = nil
        end
        if cut ~= nil then
          local n = S._nRegions
          for kk in pairs(far) do region[KY(kk)][KX(kk)] = n end
          sizes[r] = sizes[r] - nfar
          sizes[n] = nfar
          S._nRegions = n + 1
          made[r] = true
          made[n] = true
          done = true
          break
        end
      end
      if not done then return made end
    end
  end

  -- ── drawn_prepare ────────────────────────────────────────────────────────────
  function S.drawnPrepare(name)
    if S.PREP[name] then return S.PREP[name] end
    local g = S.DRAWN_BY[name]
    local members = g.members
    local layouts, CW, CH, kind, blocked, side, flat, faceLow = S.drawnCanvas(name)
    local function metatileAt(cx, cy)
      for _, lid in ipairs(members) do
        local L = layouts[lid]
        local ox, oy = g.at[lid][1], g.at[lid][2]
        if ox <= cx and cx < ox + L.w and oy <= cy and cy < oy + L.h then
          return S.artMemo[lid].metatile(cx - ox, cy - oy)
        end
      end
      return nil
    end
    local W, H = CW * 16, CH * 16
    local function kd(x, y) return byte(kind[y], x + 1) end
    -- regions
    local region = {}
    for y = 0, H - 1 do
      local row = {}
      for x = 0, W - 1 do row[x] = -1 end
      region[y] = row
    end
    local sizes = {}
    local nRegions = 0
    local pier = S.PIER[name].set
    local function apart(a, b, i, j)
      local cx, cy, dx, dy = floor(a / 16), floor(b / 16), floor(i / 16), floor(j / 16)
      if cx == dx and cy == dy then return false end
      local cin, din = pier[K(cx, cy)] == true, pier[K(dx, dy)] == true
      if cin == din then return false end
      local ox, oy = dx, dy
      if cin then ox, oy = dx, dy else ox, oy = cx, cy end
      local f = flat[oy][ox]
      return not (f == "floor" or f == "bridge")
    end
    local function bandSeam(a, b, i, j)
      if floor(b / 16) == floor(j / 16) then return false end
      local sa, sb = side[floor(b / 16)][floor(a / 16)], side[floor(j / 16)][floor(i / 16)]
      if (sa ~= 0) == (sb ~= 0) then return false end
      local cx, cy
      if sa ~= 0 then cx, cy = floor(a / 16), floor(b / 16) else cx, cy = floor(i / 16), floor(j / 16) end
      local s0 = side[cy][cx]
      local low = cx - s0
      while low >= 0 and low < CW and side[cy][low] == s0 do low = low - s0 end
      return low >= 0 and low < CW and flat[cy][low] == "water"
    end
    local crossing = {}
    local function crosses(a, b, i, j)
      local key = ((floor(a / 16) * 1024 + floor(b / 16)) * 1024 + floor(i / 16)) * 1024 + floor(j / 16)
      local v = crossing[key]
      if v == nil then
        v = not apart(a, b, i, j) and not bandSeam(a, b, i, j)
        crossing[key] = v
      end
      return v
    end
    for y = 0, H - 1 do
      local rrow, s = region[y], kind[y]
      for x = 0, W - 1 do
        local k = byte(s, x + 1)
        if (k == GROUND or k == TOP) and rrow[x] < 0 then
          local n = nRegions
          local stack, count = { x, y }, 0
          rrow[x] = n
          while #stack > 0 do
            local b = table.remove(stack)
            local a = table.remove(stack)
            count = count + 1
            tickEvery(50000)
            local ra, ka = region[b], kind[b]
            if a + 1 < W and ra[a + 1] < 0 and byte(ka, a + 2) == k and ((a + 1) % 16 ~= 0 or crosses(a, b, a + 1, b)) then
              ra[a + 1] = n
              stack[#stack + 1] = a + 1; stack[#stack + 1] = b
            end
            if a > 0 and ra[a - 1] < 0 and byte(ka, a) == k and (a % 16 ~= 0 or crosses(a, b, a - 1, b)) then
              ra[a - 1] = n
              stack[#stack + 1] = a - 1; stack[#stack + 1] = b
            end
            if b + 1 < H and region[b + 1][a] < 0 and byte(kind[b + 1], a + 1) == k
                and ((b + 1) % 16 ~= 0 or crosses(a, b, a, b + 1)) then
              region[b + 1][a] = n
              stack[#stack + 1] = a; stack[#stack + 1] = b + 1
            end
            if b > 0 and region[b - 1][a] < 0 and byte(kind[b - 1], a + 1) == k and (b % 16 ~= 0 or crosses(a, b, a, b - 1)) then
              region[b - 1][a] = n
              stack[#stack + 1] = a; stack[#stack + 1] = b - 1
            end
          end
          sizes[n] = count
          nRegions = nRegions + 1
        end
      end
      if y % 64 == 0 then tick() end
    end
    local cutApart = {}
    if WRAP_GROUPS[name] then
      local south = {}
      for cy = 0, CH - 1 do
        for cx = 0, CW - 1 do
          if faceLow[K(cx, cy)] or FACE_SOUTH[metatileAt(cx, cy) or -1] then south[K(cx, cy)] = true end
        end
      end
      S._nRegions = nRegions
      cutApart = splitWrapped(region, sizes, kind, side, south, W, H)
      nRegions = S._nRegions
    end
    -- a strip of top a few pixels thick is part of the face
    local columns = {}
    for n = 0, nRegions - 1 do columns[n] = { n = 0 } end
    for y = 0, H - 1 do
      local row = region[y]
      tickEvery(64)
      for x = 0, W - 1 do
        local r = row[x]
        if r >= 0 then
          local c = columns[r]
          if not c[x] then
            c[x] = true
            c.n = c.n + 1
          end
        end
      end
    end
    local big = {}
    for n = 0, nRegions - 1 do
      big[n] = sizes[n] >= REGION_MIN and (sizes[n] >= THIN * columns[n].n or cutApart[n] == true)
    end
    columns = nil
    -- what the columns say: (upper, lower) -> drops (an ordered map)
    local runs = { order = {}, at = {} }
    local function run(a, b, v)
      local key = a * 1000000 + b
      local e = runs.at[key]
      if not e then
        e = { a = a, b = b, v = {} }
        runs.at[key] = e
        runs.order[#runs.order + 1] = key
      end
      e.v[#e.v + 1] = v
      return e
    end
    for x = 0, W - 1 do
      local y = 0
      tickEvery(64)
      while y < H do
        local k = kd(x, y)
        if k ~= FACE and k ~= RIM then
          y = y + 1
        else
          local y0 = y
          while y < H and kd(x, y) == k do y = y + 1 end
          if not (y0 == 0 or y == H) then
            local a, b = region[y0 - 1][x], region[y][x]
            if a >= 0 and b >= 0 and a ~= b and big[a] and big[b] then
              if not (kd(x, y) == GROUND and blocked[floor(y / 16)][floor(x / 16)]) then
                local skip = false
                if k == FACE then
                  local n = 0
                  for j = y0, y - 1 do if side[floor(j / 16)][floor(x / 16)] ~= 0 then n = n + 1 end end
                  if n * 2 > y - y0 then skip = true end
                end
                if not skip then run(a, b, k == FACE and y - y0 or -C.RIM_RISE) end
              end
            end
          end
        end
      end
    end
    for y = 0, H - 1 do
      local x = 0
      local cy = floor(y / 16)
      tickEvery(64)
      while x < W do
        if kd(x, y) ~= FACE then
          x = x + 1
        else
          local x0 = x
          while x < W and kd(x, y) == FACE do x = x + 1 end
          if not (x0 == 0 or x == W) then
            local turn = 0
            for i = x0, x - 1 do turn = turn + side[cy][floor(i / 16)] end
            if not (abs(turn) * 2 <= x - x0) then
              local left, right = region[y][x0 - 1], region[y][x]
              if left >= 0 and right >= 0 and left ~= right and big[left] and big[right] then
                if turn > 0 then run(right, left, C.SIDE_RISE) else run(left, right, C.SIDE_RISE) end
              end
            end
          end
        end
      end
    end
    for y = 0, H - 1 do
      local cy = floor(y / 16)
      local cx = 0
      while cx < CW do
        local s_ = side[cy][cx]
        if s_ == 0 then
          cx = cx + 1
        else
          local x0 = cx
          while cx < CW and side[cy][cx] == s_ do cx = cx + 1 end
          if not (cx - x0 < 2 or x0 == 0 or cx == CW) then
            local west, east = region[y][x0 * 16 - 8], region[y][cx * 16 + 8]
            if west >= 0 and east >= 0 and west ~= east and big[west] and big[east] then
              local rise = C.SIDE_RISE * (cx - x0)
              if s_ > 0 then run(east, west, rise) else run(west, east, rise) end
            end
          end
        end
      end
    end
    local function southFace(cx, cy)
      local f = flat[cy][cx]
      -- (flat is False or a word: `in (None, "fall")` holds for a waterfall only)
      return side[cy][cx] == 0 and f == "fall"
        and (FACE_SOUTH[metatileAt(cx, cy) or -1] or faceLow[K(cx, cy)] or f == "fall")
    end
    for x = 8, W - 1, 16 do
      local cx = floor(x / 16)
      local cy = 0
      while cy < CH do
        if not southFace(cx, cy) then
          cy = cy + 1
        else
          local y0 = cy
          while cy < CH and southFace(cx, cy) do cy = cy + 1 end
          if not (cy - y0 < 2 or y0 == 0 or cy == CH) then
            for i = x - 6, x + 6, 3 do
              local up, down = region[y0 * 16 - 4][i], region[cy * 16 + 4][i]
              if up >= 0 and down >= 0 and up ~= down and big[up] and big[down] then
                run(up, down, LEVEL * (cy - y0))
              end
            end
          end
        end
      end
    end
    -- the ground walked from one to the other is one level
    local WALKED = 1000
    local walkRegion, walkOrder = {}, {}
    local tiesSeq = {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local f = flat[cy][cx]
        if f == "floor" or f == "bridge" or f == "water" then
          local cnt, order = {}, {}
          for j = 0, 15, 2 do
            local rr = region[cy * 16 + j]
            for i = 0, 15, 2 do
              local r = rr[cx * 16 + i]
              if cnt[r] == nil then cnt[r] = 0; order[#order + 1] = r end
              cnt[r] = cnt[r] + 1
            end
          end
          local best
          for _, r in ipairs(order) do
            if r >= 0 and big[r] then
              local n = cnt[r]
              if not best or n > best[1] or (n == best[1] and r > best[2]) then best = { n, r } end
            end
          end
          walkRegion[K(cx, cy)] = best and best[2] or false
          walkOrder[#walkOrder + 1] = K(cx, cy)
        end
      end
    end
    local seenWalk = {}
    for _, start in ipairs(walkOrder) do
      if not seenWalk[start] then
        local comp, stack = {}, { start }
        seenWalk[start] = true
        while #stack > 0 do
          local c = table.remove(stack)
          comp[#comp + 1] = c
          local x, y = KX(c), KY(c)
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local qx, qy = x + d[1], y + d[2]
            local q = K(qx, qy)
            if walkRegion[q] ~= nil and not seenWalk[q] then
              local fa, fb = flat[qy][qx], flat[y][x]
              if not ((fa == "bridge" and fb == "water") or (fa == "water" and fb == "bridge")) then
                seenWalk[q] = true
                stack[#stack + 1] = q
              end
            end
          end
        end
        local found, have = {}, {}
        for _, c in ipairs(comp) do
          local r = walkRegion[c]
          if r and not have[r] then have[r] = true; found[#found + 1] = r end
        end
        table.sort(found)
        for i = 2, #found do
          local e = run(found[1], found[i], 0)
          e.v[#e.v] = nil
          for _ = 1, WALKED do e.v[#e.v + 1] = 0 end
          tiesSeq[#tiesSeq + 1] = found[1] * 1000000 + found[i]
        end
      end
    end
    local tiesOrdered = {}
    for _, kk in ipairs(Art.setOrder(tiesSeq, function(kk)
      return Art.hashTuple({ floor(kk / 1000000), kk % 1000000 }, 2)
    end)) do
      tiesOrdered[#tiesOrdered + 1] = { floor(kk / 1000000), kk % 1000000 }
    end
    -- per cell: how much of it is drawn, as top, as ground, and which terraces it is drawn in
    local stats, freeMid = grid2(CW, CH), grid2(CW, CH, false)
    for cy = 0, CH - 1 do
      tick()
      for cx = 0, CW - 1 do
        local counts = { n = {}, order = {} }
        local n, top, ground = 0, 0, 0
        for j = 0, 15 do
          local ks, rr = kind[cy * 16 + j], region[cy * 16 + j]
          for i = cx * 16, cx * 16 + 15 do
            local k = byte(ks, i + 1)
            if k ~= VOID then
              n = n + 1
              if k == TOP or k == RIM then top = top + 1 end
              if k == GROUND then ground = ground + 1 end
              local r = rr[i]
              if r >= 0 and big[r] then
                if counts.n[r] == nil then counts.n[r] = 0; counts.order[#counts.order + 1] = r end
                counts.n[r] = counts.n[r] + 1
              end
            end
          end
        end
        if n > 0 then stats[cy][cx] = { n, top, ground, counts } end
        freeMid[cy][cx] = kd(cx * 16 + 8, cy * 16 + 8) == FREE
      end
    end
    -- what stands at each map's edges
    local edges = {}
    for _, lid in ipairs(members) do
      local L = layouts[lid]
      local ox, oy = g.at[lid][1], g.at[lid][2]
      for _, edge in ipairs({ "up", "down", "left", "right" }) do
        local px = {}
        if edge == "up" or edge == "down" then
          local y = edge == "up" and oy * 16 + 1 or (oy + L.h) * 16 - 2
          for i = 0, L.w - 1 do px[#px + 1] = { (ox + i) * 16 + 8, y } end
        else
          local x = edge == "left" and ox * 16 + 1 or (ox + L.w) * 16 - 2
          for j = 0, L.h - 1 do px[#px + 1] = { x, (oy + j) * 16 + 8 } end
        end
        local list = {}
        for i, p in ipairs(px) do
          local r = region[p[2]][p[1]]
          local k = kd(p[1], p[2])
          list[i - 1] = (r >= 0 and big[r] and (k == GROUND or k == TOP)) and r or nil
        end
        edges[lid .. "|" .. edge] = list
      end
    end
    -- (a region's pixels are read later only at the cells' middles)
    local mid = {}
    for cy = 0, CH - 1 do
      local row = {}
      for cx = 0, CW - 1 do row[cx] = region[cy * 16 + 8][cx * 16 + 8] end
      mid[cy] = row
    end
    local prep = { members = members, at = g.at, layouts = layouts, CW = CW, CH = CH, side = side, flat = flat,
                   sizes = sizes, big = big, runs = runs, tiesOrdered = tiesOrdered, stats = stats,
                   freeMid = freeMid, faceLow = faceLow, regionMid = mid, edges = edges, nRegions = nRegions,
                   metatileAt = metatileAt }
    if S.opt.keepRegion then prep.region = region end
    S.PREP[name] = prep
    tick()
    return prep
  end
end
