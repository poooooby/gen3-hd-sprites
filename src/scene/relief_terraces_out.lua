-- Mountains read as the tileset builds them, into the relief (Battle Scene: Overworld; see
-- src/scene/relief_terraces.lua): a solved group's records (cut tiles, the ground run on behind
-- a back, cliff walls), the merge of a group into the relief model, the groups chosen, the
-- terraces' count of a group's regions for the world's placement (region_ties), and the pass
-- itself over a model (apply_file).
--
-- Adapted from Emerald 3DS (3ds_port/scripts/voxel_terraces.py, by Zallax and contributors, CC
-- BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), as the first file says.

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local bit = require("bit")
local band, bor, rshift, lshift, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bnot
local byte = string.byte

return function(S)
  local Solve, Art, T = S.Solve, S.Art, S.T
  local K, KX, KY = Solve.K, Solve.KX, Solve.KY
  local C = Solve.C
  local LEVEL, N = T.LEVEL, T.N
  local counter = Solve.counter
  local tick = S.tick
  local GROUND, TOP, ROCK, UNKNOWN = T.GROUND, T.TOP, T.ROCK, T.UNKNOWN
  local IS_CORNER = T.IS_CORNER
  local edge, emax, emin, pg, pieceGrid = T.edge, T.emax, T.emin, T.pg, T.pieceGrid
  local sortXY, sortedXY, sortedYX, keysOf, isBandKind = T.sortXY, T.sortedXY, T.sortedYX, T.keysOf, T.isBandKind
  local gmin, gmax, pyround = T.gmin, T.gmax, T.pyround
  local pixelClasses, clsAt, CF, CT = T.pixelClasses, T.clsAt, T.CF, T.CT
  local twin, HEADS, BOULDER_HEAD, ON_TOP = T.twin, T.HEADS, T.BOULDER_HEAD, T.ON_TOP
  local ROCK_ALL, ROCK_TOP, ROCK_RIM = Solve.ROCK_ALL, Solve.ROCK_TOP, Solve.ROCK_RIM

  local CUT_LIFT = 2
  local FACES = { 0x07c, 0x0a9, 0x079, 0x091 }
  local BLOCK_WALLS, PLAIN, THIN_DECK = 4, 1, 8
  local OUTLINE_GREY = { [0x83 * 65536 + 0x83 * 256 + 0x8b] = true }
  local GOES_ON, GOES_ON_FACE, GOES_ON_SOUTH, FACE_TOP, CANOPY = C.GOES_ON, 32, 64, 16, 128
  local CANOPY_TOP = 0x00E
  local SIDE_FACE = { W = 0x070, E = 0x072 }
  local HEAD_DRAWN = { W = 0x068, E = 0x06a }
  T.HEAD_DRAWN = HEAD_DRAWN
  local LIP_ROWS = 6
  local NONE16, NO_VARIANT = 0xFFFF, 0xFFFF
  local DRAWN_FLAG = 0x8000

  local function cacheOn(c, name)
    local t = c[name]
    if not t then t = {}; c[name] = t end
    return t
  end
  local function artCache(store, art)
    local t = store[art]
    if not t then t = {}; store[art] = t end
    return t
  end
  local function bitset(rows, i, j) return band(rshift(rows[j], i), 1) ~= 0 end
  local function anyBits(rows)
    if not rows then return false end
    for j = 0, 15 do if rows[j] ~= 0 then return true end end
    return false
  end
  local function zeroRows() local r = {} for j = 0, 15 do r[j] = 0 end return r end
  local function cellsAll(list) return list end

  --- metatile m as the GBA composes it: { [k] = { colour, upper } } (nil where neither draws)
  local function rawPixels(art, m)
    local out = {}
    for layer = 0, 1 do
      local blocks = art.pair.subtiles(m, layer)
      for q = 0, 3 do
        local block = blocks[q]
        for j = 0, 7 do
          for i = 0, 7 do
            local ci = block[64 + j * 8 + i]
            if ci ~= nil and ci ~= 0 then
              out[(floor(q / 2) * 8 + j) * 16 + (q % 2) * 8 + i] = { block[j * 8 + i], layer == 1 }
            end
          end
        end
      end
    end
    return out
  end

  local canopyOf = setmetatable({}, { __mode = "k" })
  local function canopyMask(art, m)
    local known = artCache(canopyOf, art)
    local v = known[m]
    if v ~= nil then return v or nil end
    local ref = rawPixels(art, CANOPY_TOP)
    local crown = {}
    for k = 0, 255 do if ref[k] ~= nil and ref[k][2] then crown[#crown + 1] = k end end
    local own = rawPixels(art, m)
    local same = {}
    for _, k in ipairs(crown) do
      if own[k] ~= nil and own[k][1] == ref[k][1] then same[#same + 1] = k end
    end
    local rows = false
    if m ~= CANOPY_TOP and #same >= 0.9 * #crown then
      rows = zeroRows()
      for _, k in ipairs(same) do rows[floor(k / 16)] = bor(rows[floor(k / 16)], lshift(1, k % 16)) end
      for k = 0, 255 do
        if own[k] == nil then rows[floor(k / 16)] = bor(rows[floor(k / 16)], lshift(1, k % 16)) end
      end
    end
    known[m] = rows
    return rows or nil
  end

  local runsSouthOf = setmetatable({}, { __mode = "k" })
  local function runsSouth(art, m)
    local known = artCache(runsSouthOf, art)
    local v = known[m]
    if v == nil then
      local img = art.cellImage(m)
      local same = 0
      for j = 0, 15 do for i = 0, 15 do if img[j * 16 + i] == img[i] then same = same + 1 end end end
      v = same >= 192
      known[m] = v
    end
    return v
  end

  local function rockOf(c, lid)
    local rock_of = cacheOn(c, "_rock_of")
    local r = rock_of[lid]
    if not r then
      r = {}
      for cell, k in pairs(c.kind) do
        if (k == ROCK or k == TOP) and c.src[cell][1] == lid then r[K(c.src[cell][2], c.src[cell][3])] = true end
      end
      rock_of[lid] = r
    end
    return r
  end

  local function treeGround(c, cell)
    local s = c.src[cell]
    local lid, x, y = s[1], s[2], s[3]
    local art, m = c.arts[lid], c:metatile(cell)
    local px
    if T.treeCard(c, cell) then
      local img = art.cellImage(m, true)
      px = {}
      for k = 0, 255 do px[#px + 1] = img[k] end
    else
      local img = art.cellImage(m)
      local rows = canopyMask(art, m) or zeroRows()
      px = {}
      for k = 0, 255 do
        if not bitset(rows, k % 16, floor(k / 16)) then px[#px + 1] = img[k] end
      end
    end
    local drawn = {}
    for _, p in ipairs(px) do if not OUTLINE_GREY[p] then drawn[#drawn + 1] = p end end
    local px2 = {}
    for _, p in ipairs(drawn) do if not ROCK_ALL[p] then px2[#px2 + 1] = p end end
    if #px2 < 8 then
      if T.treeCard(c, cell) or #drawn < 8 then return nil end
      return S.plainGround(art, c.roles_of[lid], {}, x, y, nil, Art.commonest(drawn, Art.hashRGB), false)
    end
    return S.plainGround(art, c.roles_of[lid], rockOf(c, lid), x, y, nil, Art.commonest(px2, Art.hashRGB), false)
  end

  local function sideFace(c, cell, side)
    local s = c.src[cell]
    local lid, x, y = s[1], s[2], s[3]
    local art = c.arts[lid]
    local known = cacheOn(c, "_side_faces")
    local key = lid .. "|" .. side
    local found = known[key]
    if not found then
      local tiles = side == "W" and T.BAND_WEST or T.BAND_EAST
      found = {}
      -- (c.band.items(): the dict's order, c.kind's)
      for _, n in ipairs(c.kindOrder) do
        local sd = c.band[n]
        if sd == side and c.src[n][1] == lid then
          local m = c:metatile(n)
          local tw = twin(art, m)
          if tiles[tw] and not HEADS[tw] then
            local cls = pixelClasses(art, m)
            if cls.F >= 0.5 * 256 then found[#found + 1] = { c.src[n][2], c.src[n][3], m } end
          end
        end
      end
      known[key] = found
    end
    local best, bd
    for _, f in ipairs(found) do
      local d = abs(f[1] - x) + abs(f[2] - y)
      if best == nil or d < bd then best, bd = f[3], d end
    end
    return best or SIDE_FACE[side]
  end

  local headOfCache = setmetatable({}, { __mode = "k" })
  function T.headOf(art, m)
    m = twin(art, m)
    if m >= 0x200 or BOULDER_HEAD[m] then return nil end
    local known = artCache(headOfCache, art)
    local v = known[m]
    if v ~= nil then return v or nil end
    local function face(t)
      local cls = pixelClasses(art, t)
      local out, n = {}, 0
      for k = 1, 256 do if byte(cls.s, k) == CF then out[k] = true; n = n + 1 end end
      return out, n
    end
    local mine, nm = face(m)
    v = false
    if nm >= 32 then
      for _, side in ipairs({ "W", "E" }) do
        local h = HEAD_DRAWN[side]
        local theirs = face(h)
        local diff = 0
        for k = 1, 256 do if (mine[k] == true) ~= (theirs[k] == true) then diff = diff + 1 end end
        if diff <= 4 then v = h; break end
      end
    end
    known[m] = v
    return v or nil
  end

  local function headMask(h)
    local west = h == HEAD_DRAWN.W
    local rows = {}
    for j = 0, 15 do
      local r = 0
      for i = 0, 15 do
        if (west and i + j <= 15) or (not west and i >= j) then r = r + lshift(1, i) end
      end
      rows[j] = r
    end
    return rows
  end

  local function outline(art, m, mask, openSides)
    local img = art.cellImage(m)
    local grey = {}
    local any = false
    for j = 0, 15 do for i = 0, 15 do if OUTLINE_GREY[img[j * 16 + i]] then grey[j * 16 + i] = true; any = true end end end
    if not any then return nil end
    local seen = {}
    local todo = {}
    local sides = {}
    for _, d in ipairs(openSides) do sides[d] = true end
    for j = 0, 15 do
      for i = 0, 15 do
        if grey[j * 16 + i] then
          local take = (sides.W and i == 0) or (sides.E and i == 15) or (sides.N and j == 0) or (sides.S and j == 15)
          if not take and mask then
            for _, ab in ipairs({ { i - 1, j }, { i + 1, j }, { i, j - 1 }, { i, j + 1 } }) do
              local a, b = ab[1], ab[2]
              if a >= 0 and a < 16 and b >= 0 and b < 16 and bitset(mask, a, b) then take = true; break end
            end
          end
          if take then todo[#todo + 1] = j * 16 + i end
        end
      end
    end
    local found = false
    while #todo > 0 do
      local p = table.remove(todo)
      if not seen[p] then
        seen[p] = true
        found = true
        local i, j = p % 16, floor(p / 16)
        for _, ab in ipairs({ { i - 1, j }, { i + 1, j }, { i, j - 1 }, { i, j + 1 } }) do
          local a, b = ab[1], ab[2]
          if a >= 0 and a < 16 and b >= 0 and b < 16 then
            local q = b * 16 + a
            if grey[q] and not seen[q] then todo[#todo + 1] = q end
          end
        end
      end
    end
    if not found then return nil end
    local rows = zeroRows()
    for p in pairs(seen) do rows[floor(p / 16)] = bor(rows[floor(p / 16)], lshift(1, p % 16)) end
    return rows
  end

  local function sample(g, px, py)
    local fx, fy = px / (16 / N), py / (16 / N)
    local a, b = min(floor(fx), N - 1), min(floor(fy), N - 1)
    local tx, ty = fx - a, fy - b
    return (g[b][a] * (1 - tx) + g[b][a + 1] * tx) * (1 - ty) + (g[b + 1][a] * (1 - tx) + g[b + 1][a + 1] * tx) * ty
  end

  local function plainTop(c, lid)
    local known = cacheOn(c, "_plain_top")
    local v = known[lid]
    if v ~= nil then return v or nil end
    local art = c.arts[lid]
    local best, bs, bm
    for _, cell in ipairs(c.kindOrder) do
      if c.kind[cell] == TOP and c.src[cell][1] == lid and not c.rim[cell] then
        local m = c:metatile(cell)
        if not ON_TOP[m] then
          local img = art.cellImage(m)
          local score = 0
          for k = 0, 255 do if ROCK_TOP[img[k]] then score = score + 1 end end
          if best == nil or score > bs or (score == bs and -m > -bm) then best, bs, bm = m, score, m end
        end
      end
    end
    v = (best ~= nil and bs >= 192) and best or false
    known[lid] = v
    return v or nil
  end

  local function behindOf(c, out, cell, lid, grids, lvl)
    local x, y = KX(cell), KY(cell)
    for k = 1, 3 do
      local n = K(x, y - k)
      if not c.src[n] or c.src[n][1] ~= lid then break end
      local lifted = grids ~= nil and lvl ~= nil and grids[n] ~= nil and emin(edge(grids[n], "S")) > lvl + LEVEL / 2
      if lifted then
        if out[n] and out[n][3] ~= nil and out[n][3] ~= false then return out[n][3] end
      else
        if k == 1 and c.kind[n] == ROCK then return c:metatile(n) end
        if (c.kind[n] == UNKNOWN and c:role(n) == "tree") or c:crown(n) then
          local m = treeGround(c, n)
          if m ~= nil then return m end
        end
        if c.kind[n] == GROUND and c:water(n) and runsSouth(c:art(n), c:metatile(n)) then return c:metatile(n) end
        if c.kind[n] == GROUND or c.kind[n] == TOP then
          local s = c.src[n]
          local nx, ny = s[2], s[3]
          local rock = rockOf(c, lid)
          local plain_of = cacheOn(c, "_plain_of")
          local key = lid .. "|" .. nx .. "|" .. ny
          local m = plain_of[key]
          if m == nil then
            local art = c.arts[lid]
            local seen = T.aliased(art) and S.vbArt(lid) or art
            local past = rock
            if seen ~= art then
              past = {}
              for kk in pairs(rock) do past[kk] = true end
              for r in pairs(c.rim) do
                if c.src[r][1] == lid then past[K(c.src[r][2], c.src[r][3])] = true end
              end
            end
            local pm = S.plainGround(seen, c.roles_of[lid], past, nx, ny, "S", nil, seen ~= art)
            if seen ~= art then pm = art.alias.alias[pm] or pm end
            m = pm == nil and false or pm
            plain_of[key] = m
          end
          if m == false then m = nil end
          if c.kind[n] == TOP and m ~= nil and ON_TOP[m] and not ON_TOP[c:metatile(n)] then
            m = plainTop(c, lid) or m
          end
          return m == nil and c:metatile(n) or m
        end
        if out[n] and out[n][3] ~= nil and out[n][3] ~= false then return out[n][3] end
      end
    end
    return 0x071
  end

  local function lowSide(c, cell)
    local side = c.band[cell]
    if side == nil then return nil end
    local cls = pixelClasses(c:art(cell), c:metatile(cell))
    local rows, js = {}, {}
    for j = 0, 15 do
      local fx
      for i = 0, 15 do
        if clsAt(cls, i, j) == CF then
          if side == "E" then fx = fx == nil and i or max(fx, i) else fx = fx == nil and i or min(fx, i) end
        end
      end
      if fx ~= nil then rows[j] = fx; js[#js + 1] = j end
    end
    if #js < 3 then return nil end
    local n = #js
    local sj, sx = 0, 0
    for _, j in ipairs(js) do sj = sj + j; sx = sx + rows[j] end
    local mj, mx = sj / n, sx / n
    local sjj = 0
    for _, j in ipairs(js) do sjj = sjj + (j - mj) ^ 2 end
    if sjj == 0 then sjj = 1.0 end
    local cov = 0
    for _, j in ipairs(js) do cov = cov + (j - mj) * (rows[j] - mx) end
    local slope = cov / sjj
    local out = {}
    for j = 0, 15 do
      local e = rows[j] ~= nil and rows[j] or (mx + slope * (j - mj))
      local bits = 0
      for i = 0, 15 do
        local beyond = side == "E" and (i > e + 0.5) or (side ~= "E" and (i < e - 0.5))
        if beyond and clsAt(cls, i, j) == CT then bits = bits + lshift(1, i) end
      end
      out[j] = bits
    end
    return out
  end

  local function faceGoesOn(c, n, side)
    if not c.src[n] or c.kind[n] ~= GROUND or not c:water(n) then return false end
    local img = c:art(n).cellImage(c:metatile(n))
    local i = side == "W" and 15 or 0
    local cnt = 0
    for j = 0, 15 do if ROCK_ALL[img[j * 16 + i]] then cnt = cnt + 1 end end
    return cnt >= 12
  end

  local function edgeStrip(mask)
    local cleared = {}
    for j = 0, 15 do for i = 0, 15 do if bitset(mask, i, j) then cleared[#cleared + 1] = { i, j } end end end
    if #cleared > 0 then
      local j0, j15, i0, i15 = true, true, true, true
      for _, p in ipairs(cleared) do
        if p[2] ~= 0 then j0 = false end
        if p[2] ~= 15 then j15 = false end
        if p[1] ~= 0 then i0 = false end
        if p[1] ~= 15 then i15 = false end
      end
      if j0 or j15 or i0 or i15 then return zeroRows() end
    end
    local out = {}
    for j = 0, 15 do out[j] = mask[j] end
    return out
  end

  local function lipMask(art, m)
    local img = art.cellImage(m)
    local rows = zeroRows()
    local total = 0
    for i = 0, 15 do
      local j
      for jj = 0, LIP_ROWS - 1 do
        if ROCK_RIM[img[jj * 16 + i]] then j = jj; break end
      end
      for k = 0, (j or 0) - 1 do rows[k] = bor(rows[k], lshift(1, i)); total = total + 1 end
    end
    if total >= 4 then return rows end
    return nil
  end

  local function drawnRockPixels(art, m)
    local img = art.cellImage(m)
    local n = 0
    for k = 0, 255 do if ROCK_ALL[img[k]] then n = n + 1 end end
    return n
  end

  local function orRows(a, b)
    local out = {}
    for j = 0, 15 do out[j] = bor(a and a[j] or 0, b[j]) end
    return out
  end
  -- a piece's kind: whole ("W:8" as it is), or split at ":" where the generator splits it
  local function rawKind(sol, cell)
    local p = sol.pieces[cell]
    return p and p[1] or ""
  end
  local function kindOfPiece(sol, cell)
    local k = rawKind(sol, cell)
    local i = k:find(":", 1, true)
    return i and k:sub(1, i - 1) or k
  end
  local function newRec() return { false, 0, false, false, 0, 0 } end     -- (false: None)
  local function rv(v) if v == false then return nil end return v end

  --- {canvas cell: { mask or "fill" or false, foot, ground or false, wall or false, sides, flags }}
  function T.records(sol)
    local c, grids = sol.cells, sol.grids
    local localRock, localFalls, pastRims, houses = {}, {}, {}, {}
    local function setOf(tbl, lid) local t = tbl[lid] if not t then t = {}; tbl[lid] = t end return t end
    for cell, k in pairs(c.kind) do
      if k == ROCK or k == TOP then
        local s = c.src[cell]
        setOf(localRock, s[1])[K(s[2], s[3])] = true
        if k == ROCK then setOf(localFalls, s[1])[K(s[2], s[3])] = true end
      end
    end
    for cell in pairs(c.rim) do
      local s = c.src[cell]
      setOf(pastRims, s[1])[K(s[2], s[3])] = true
    end
    for cell in pairs(c.src) do
      local r = c:role(cell)
      if c:house(cell) or r == "wall" or r == "signpost" or r == "fence" or r == "shelf" then
        local s = c.src[cell]
        setOf(houses, s[1])[K(s[2], s[3])] = true
      end
    end
    for _, mem in ipairs(c.members) do
      setOf(localRock, mem[1]); setOf(localFalls, mem[1]); setOf(pastRims, mem[1]); setOf(houses, mem[1])
    end
    local drawnRock = {}
    for cell, g in pairs(grids) do
      local k = c.kind[cell]
      if not (k == ROCK or k == TOP or c.keep[cell] or c.bridges[cell] or not c:water(cell)) then
        local x, y = KX(cell), KY(cell)
        local low
        for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
          local nk = c.kind[n]
          if grids[n] ~= nil and nk ~= ROCK and nk ~= TOP then
            local v = gmin(grids[n])
            low = low == nil and v or min(low, v)
          end
        end
        if low ~= nil and gmax(g) >= low + LEVEL - 0.5 then
          local lid = c.src[cell][1]
          if drawnRockPixels(c.arts[lid], c:metatile(cell)) >= 32 then drawnRock[cell] = low end
        end
      end
    end
    local faceOf = {}
    for _, mem in ipairs(c.members) do
      local lid = mem[1]
      local art = c.arts[lid]
      local drawn = {}
      for y = 0, art.h - 1 do for x = 0, art.w - 1 do drawn[art.metatile(x, y)] = true end end
      local f = FACES[1]
      for _, ff in ipairs(FACES) do if drawn[ff] then f = ff; break end end
      faceOf[lid] = f
    end
    local out = {}
    local outOrder = {}
    local function outSet(cell, rec) if out[cell] == nil then outOrder[#outOrder + 1] = cell end out[cell] = rec end
    for _, cell in ipairs(sortedYX(grids)) do
      local g = grids[cell]
      local x, y = KX(cell), KY(cell)
      T.tickN()
      local s = c.src[cell]
      local lid, lx, ly = s[1], s[2], s[3]
      local art, roles = c.arts[lid], c.roles_of[lid]
      local rec = newRec()
      local kind = c.kind[cell]
      local isRock = kind == ROCK or kind == TOP
      for _, d in ipairs({ { K(x - 1, y), "W", "E" }, { K(x + 1, y), "E", "W" }, { K(x, y + 1), "S", "N" } }) do
        local n = d[1]
        if grids[n] ~= nil then
          local a, b = edge(g, d[2]), edge(grids[n], d[3])
          local over = false
          for i = 0, N do if a[i] - b[i] > 0.5 then over = true; break end end
          if over then
            local own = c.bridges[cell] == true
            local piece = kindOfPiece(sol, cell)
            local bandK = isBandKind(piece) and piece:sub(1, 1) or nil
            rec[4] = own and c:metatile(cell) or (bandK and sideFace(c, cell, bandK) or faceOf[lid])
            rec[5] = 0xFF
            rec[6] = bor(rec[6], BLOCK_WALLS)
          end
        end
      end
      local pieceK = rawKind(sol, cell)
      local roughBand = c.rough[cell] == true and isBandKind(pieceK)
      local mask
      local nearRough = false
      local a4, b4, c4, d4 = T.four(cell)
      for _, n in ipairs({ a4, b4, c4, d4 }) do if c.rough[n] then nearRough = true end end
      if (isRock or drawnRock[cell] ~= nil) and not c:is_stair(cell) and not c:muddy(cell) and not c.cheeks[cell]
          and (roughBand or (not c.rough[cell] and not nearRough)) then
        mask = S.cutMask(art, roles, lx, ly, localRock[lid])
      end
      if mask and T.aliased(art) and not roughBand then
        local m = c:metatile(cell)
        local head = twin(art, m)
        if head ~= m and HEADS[head] then mask = headMask(HEAD_DRAWN[HEADS[head]]) end
      end
      if mask and c.src[K(x, y + 1)] and c:role(K(x, y + 1)) == "tree" and T.isFace(c, cell) then mask = nil end
      if mask and isRock and not c:is_stair(cell) and not c:muddy(cell) and not c.cheeks[cell]
          and (isBandKind(pieceK) or IS_CORNER[pieceK]) then
        local openSides = {}
        for _, dn in ipairs({ { "N", K(x, y - 1) }, { "S", K(x, y + 1) }, { "W", K(x - 1, y) }, { "E", K(x + 1, y) } }) do
          local n = dn[2]
          local nk = c.kind[n]
          if c.src[n] and c.src[n][1] == lid and nk ~= ROCK and nk ~= TOP and c:role(n) ~= "tree" then
            openSides[#openSides + 1] = dn[1]
          end
        end
        local grey = outline(art, c:metatile(cell), mask, openSides)
        if grey ~= nil and anyBits(grey) then
          local nm = {}
          for j = 0, 15 do nm[j] = band(mask[j], bnot(grey[j])) end
          mask = anyBits(nm) and nm or nil
        end
      end
      local low = lowSide(c, cell)
      local head = isRock and T.headOf(art, c:metatile(cell)) or nil
      if head ~= nil and not (roughBand and anyBits(mask)) and (anyBits(mask) or anyBits(low)) then
        mask, low = headMask(head), nil
      end
      local boulderBand = pieceK
      if head == nil and BOULDER_HEAD[twin(art, c:metatile(cell))] and (boulderBand == "W" or boulderBand == "E") then
        head = HEAD_DRAWN[boulderBand]
        mask, low = headMask(head), nil
      end
      local side = c.band[cell]
      local foot
      if head ~= nil and mask ~= nil then foot = gmin(g) end
      if low and side and c.band[side == "W" and K(x - 1, y) or K(x + 1, y)] == side then
        low = nil
      elseif low and side and faceGoesOn(c, side == "W" and K(x - 1, y) or K(x + 1, y), side) then
        low = nil
      end
      if low and anyBits(low) then
        mask = orRows(mask, low)
        foot = gmin(g)
      end
      local lipOnly = false
      if head == nil and not anyBits(mask) and c.rim[cell] and isRock and grids[K(x, y - 1)] ~= nil
          and not c.cheeks[cell] and not c.rough[cell] and not c:is_stair(cell) and not c:muddy(cell) then
        local n = K(x, y - 1)
        local npiece = rawKind(sol, n)
        local back = emin(edge(grids[n], "S"))
        if not c.band[n] and not isBandKind(npiece) and emin(edge(g, "N")) - back >= LEVEL / 2 then
          local lm = lipMask(art, c:metatile(cell))
          if lm ~= nil and anyBits(edgeStrip(lm)) then
            lipOnly = not anyBits(mask)
            mask = orRows(mask, lm)
            foot = foot == nil and back or min(foot, back)
          end
        end
      end
      if mask and anyBits(mask) then
        local grounds = {}
        for _, n in ipairs({ K(x, y - 1), K(x - 1, y), K(x + 1, y), K(x, y + 1) }) do
          local nk = c.kind[n]
          if sol.flat[n] ~= nil and (nk == GROUND or nk == UNKNOWN) then grounds[#grounds + 1] = sol.flat[n] end
        end
        local gmn
        if #grounds > 0 then gmn = math.huge for _, v in ipairs(grounds) do gmn = min(gmn, v) end end
        if drawnRock[cell] ~= nil then foot = drawnRock[cell]
        elseif foot == nil then foot = gmn ~= nil and gmn or gmin(g)
        elseif gmn ~= nil then foot = min(foot, gmn) end
        if head ~= nil and drawnRock[cell] == nil and not c.rough[cell] then
          local beside
          local touchW, touchE = false, false
          for j = 0, 15 do
            if band(mask[j], 1) ~= 0 then touchW = true end
            if band(rshift(mask[j], 15), 1) ~= 0 then touchE = true end
          end
          for _, nt in ipairs({ { K(x, y - 1), "S", mask[0] ~= 0 }, { K(x, y + 1), "N", mask[15] ~= 0 },
                                { K(x - 1, y), "E", touchW }, { K(x + 1, y), "W", touchE } }) do
            if nt[3] and grids[nt[1]] ~= nil then
              local v = emin(edge(grids[nt[1]], nt[2]))
              beside = beside == nil and v or min(beside, v)
            end
          end
          if beside ~= nil and beside < foot then foot = beside end
        end
        local lifted = 0
        for j = 0, 15 do
          for i = 0, 15 do
            if bitset(mask, i, j) and sample(g, i + 0.5, j + 0.5) - foot > CUT_LIFT then lifted = lifted + 1 end
          end
        end
        if lifted >= 4 then
          local drawn = mask
          mask = edgeStrip(mask)
          rec[1], rec[2] = mask, foot
          local seen = T.aliased(art) and S.vbArt(lid) or art
          local past = {}
          for kk in pairs(localRock[lid]) do past[kk] = true end
          if seen ~= art then for kk in pairs(pastRims[lid]) do past[kk] = true end end
          for kk in pairs(houses[lid]) do past[kk] = true end
          if lipOnly then
            rec[3] = behindOf(c, out, cell, lid, grids, foot)
            if S.plainBackground(art, art.metatile(lx, ly), drawn, rec[3]) then rec[6] = bor(rec[6], PLAIN) end
          else
            local content
            if seen ~= art then content = past
            else
              content = {}
              for kk in pairs(localFalls[lid]) do content[kk] = true end
              for kk in pairs(pastRims[lid]) do content[kk] = true end
            end
            local ground = S.behind(seen, roles, lx, ly, past, drawn, seen ~= art, content, OUTLINE_GREY)
            if ground ~= nil and S.plainBackground(seen, seen.metatile(lx, ly), drawn, ground) then rec[6] = bor(rec[6], PLAIN) end
            if ground ~= nil then
              rec[3] = seen ~= art and (art.alias.alias[ground] or ground) or ground
            else
              rec[3] = false
            end
          end
          if rec[4] ~= false then
            local bits = 0
            for k = 0, 3 do
              for j = 4 * k, 4 * k + 3 do
                if band(mask[j], 1) == 0 then bits = bor(bits, lshift(1, k)) end
                if band(rshift(mask[j], 15), 1) == 0 then bits = bor(bits, lshift(1, 4 + k)) end
              end
            end
            rec[5] = bits
            rec[6] = band(rec[6], bnot(BLOCK_WALLS))
          end
        end
      end
      if rec[1] == false and grids[K(x, y - 1)] ~= nil then
        local north = edge(grids[K(x, y - 1)], "S")
        local mine = edge(g, "N")
        local over = false
        for i = 0, N do if mine[i] - north[i] > 0.5 then over = true; break end end
        if over then
          rec[1] = "fill"
          rec[2] = emin(north)
          rec[3] = behindOf(c, out, cell, lid, grids, rec[2])
          local n = K(x, y - 1)
          local gn = grids[n]
          local piece = rawKind(sol, n)
          local sd = c.band[n] or (isBandKind(piece) and piece:sub(1, 1) or nil)
          if sd and c.src[n][1] == lid then
            local ok = true
            for i = 0, N do if not (north[i] <= mine[i] + 0.5) then ok = false end end
            if ok then
              for j = 0, N do for i = 0, N do if abs(gn[j][i] - gn[N][i]) > 1.0 then ok = false end end end
            end
            if ok then
              rec[6] = bor(rec[6], GOES_ON)
              local on = out[n]
              if on and type(on[1]) == "table" and rec[4] == false then
                rec[4] = sideFace(c, n, sd)
                rec[6] = bor(rec[6], GOES_ON_FACE)
              elseif on and band(on[6], FACE_TOP) ~= 0 and on[4] ~= false and rec[4] == false then
                rec[4] = on[4]
                rec[6] = bor(rec[6], GOES_ON_FACE)
              end
            end
          end
        end
      end
      local under = sol.under and sol.under[cell] or nil
      local south = K(x, y + 1)
      while c.bridges[south] do south = K(x, KY(south) + 1) end
      local overRock = (c.kind[south] == ROCK or c.kind[south] == TOP) and grids[south] ~= nil
        and gmin(g) - gmin(grids[south]) >= LEVEL - 0.5
      local bandUnder = 0
      if c.bridges[cell] and under == nil and overRock then
        for _, nf in ipairs({ { K(x, y - 1), GOES_ON }, { K(x, y + 1), GOES_ON_SOUTH } }) do
          local n = nf[1]
          local p = sol.pieces[n]
          if not c.bridges[n] and grids[n] ~= nil and p ~= nil and isBandKind(p[1]) then
            bandUnder = nf[2]
            break
          end
        end
      end
      if bandUnder ~= 0 then
        rec[1] = "fill"
        rec[2] = gmin(grids[bandUnder == GOES_ON and K(x, y - 1) or K(x, y + 1)])
        rec[3] = false
        rec[4] = c:metatile(cell)
        rec[5] = 0xFF
        rec[6] = bor(band(rec[6], bnot(BLOCK_WALLS)), bandUnder, THIN_DECK)
      elseif c.bridges[cell] and (under == "rock" or (under ~= "open" and overRock)) then
        rec[4] = faceOf[lid]
        rec[5] = 0xFF
        rec[6] = bor(rec[6], BLOCK_WALLS)
      elseif c.bridges[cell] then
        local underL = {}
        for _, d in ipairs({ { K(x - 1, y), "W", "E" }, { K(x + 1, y), "E", "W" }, { K(x, y + 1), "S", "N" } }) do
          local n = d[1]
          if grids[n] ~= nil then
            local a, b = edge(g, d[2]), edge(grids[n], d[3])
            for i = 0, N do if a[i] - b[i] > 0.5 then underL[#underL + 1] = n; break end end
          end
        end
        local thin = rec[4] ~= false
        if thin then
          for _, n in ipairs(underL) do if not (c:water(n) or c.bridges[n]) then thin = false end end
        end
        if thin then rec[6] = bor(rec[6], THIN_DECK) end
        local lowN, lowV
        for _, n in ipairs({ K(x, y + 1), K(x - 1, y), K(x + 1, y), K(x, y - 1) }) do
          if grids[n] ~= nil and not c.bridges[n] and c:water(n) then
            local v = gmin(grids[n])
            if lowN == nil or v < lowV then lowN, lowV = n, v end
          end
        end
        if lowN ~= nil then
          local bottom = lowV
          if thin and rec[1] == false and bottom < gmin(g) - 0.5 then
            rec[1], rec[2], rec[3] = "fill", bottom, c:metatile(lowN)
          end
        end
      end
      if rec[4] == false and (c:role(cell) == "tree" or c:crown(cell)) and gmax(g) - gmin(g) == LEVEL then
        local p = sol.pieces[cell]
        local pk = p and p[1] or ""
        rec[4] = isBandKind(pk) and sideFace(c, cell, pk:sub(1, 1)) or faceOf[lid]
        rec[6] = bor(rec[6], FACE_TOP)
      end
      if rec[1] ~= false or rec[4] ~= false then outSet(cell, rec) end
    end
    -- beside a thin deck
    local thinCells = {}
    for _, cell in ipairs(outOrder) do if band(out[cell][6], THIN_DECK) ~= 0 then thinCells[#thinCells + 1] = cell end end
    for _, cell in ipairs(thinCells) do
      local x, y = KX(cell), KY(cell)
      for _, n in ipairs({ K(x - 1, y), K(x + 1, y) }) do
        if grids[n] ~= nil then
          local other = out[n]
          if other == nil then other = newRec(); outSet(n, other) end
          if band(other[6], THIN_DECK) == 0 then
            if c.bridges[n] then
              other[6] = band(bor(other[6], THIN_DECK), bnot(BLOCK_WALLS))
            end
            if other[4] == false then other[4] = c.bridges[n] and c:metatile(n) or faceOf[c.src[n][1]] end
            if other[5] == 0 then other[5] = 0xFF end
          end
        end
      end
    end
    -- under every piece of rock standing over ground round it, the lowest of that ground runs on
    for _, cell in ipairs(sortedYX(grids)) do
      local k = c.kind[cell]
      if (k == ROCK or k == TOP or k == UNKNOWN) and not c.keep[cell] then
        local rec = out[cell]
        if not (rec ~= nil and rec[1] ~= false) then
          local lid = c.src[cell][1]
          local x, y = KX(cell), KY(cell)
          local near
          for i = -1, 1 do
            for j = -1, 1 do
              local n = K(x + i, y + j)
              if grids[n] ~= nil and n ~= cell and c.src[n][1] == lid then
                local v = gmin(grids[n])
                near = near == nil and v or min(near, v)
              end
            end
          end
          local own = gmin(grids[cell])
          if near ~= nil and not (near > own - 0.5) then
            if rec == nil then rec = newRec(); outSet(cell, rec) end
            rec[1], rec[2], rec[3] = "fill", near, behindOf(c, out, cell, lid, grids, near)
          end
        end
      end
    end
    -- a back k levels over the ground behind it stands k rows south of that ground
    local chosen = sol.behind or {}
    local carried = {}
    sol.behind_carried = carried
    for _, cell in ipairs(sortedYX(out)) do
      local rec = out[cell]
      local x, y = KX(cell), KY(cell)
      local up = K(x, y - 1)
      local isFill = rec[1] == "fill"
      local cutFlat = type(rec[1]) == "table" and grids[up] ~= nil and abs(emin(edge(grids[up], "S")) - rec[2]) < 0.5
      if (isFill or cutFlat) and (isFill or rec[3] ~= false) then
        local rise = emax(edge(grids[cell], "N")) - rec[2]
        for k = 1, floor((rise + 2.5) / LEVEL) do
          local n = K(x, y + k)
          if grids[n] == nil or c.src[n][1] ~= c.src[cell][1] then break end
          if gmin(grids[n]) <= rec[2] + 0.5 then break end
          local m = out[n]
          if m == nil then m = newRec(); outSet(n, m) end
          if m[1] == false then
            m[1], m[2], m[3] = "fill", rec[2], rec[3]
            if chosen[cell] ~= nil and chosen[n] == nil then carried[n] = chosen[cell] end
          end
        end
      end
    end
    -- a canopy the tile draws over the ground north of its small tree
    for _, cell in ipairs(sortedYX(grids)) do
      local s = c.src[cell]
      local lid = s[1]
      local art = c.arts[lid]
      local below = K(KX(cell), KY(cell) + 1)
      if not (c:metatile(cell) < 512 or c.keep[cell] or not c.src[below] or not T.smallTrunk(c, below)) then
        local rows = canopyMask(art, c:metatile(cell))
        local rec = out[cell]
        if not (rows == nil or (rec ~= nil and (type(rec[1]) == "table" or rec[4] ~= false))) then
          local plate = treeGround(c, cell)
          if plate ~= nil then
            if rec == nil then rec = newRec(); outSet(cell, rec) end
            if rec[1] ~= "fill" then
              rec[2], rec[3] = gmin(grids[cell]), false
            end
            rec[1], rec[4], rec[5] = rows, plate, 0
            rec[6] = bor(rec[6], CANOPY)
          end
        end
      end
    end
    return out
  end

  --- merge: a solved group into a model (src/scene/relief.lua's), in place
  function T.merge(sol, M)
    local c = sol.cells
    local recs = T.records(sol)
    local function tsOf(lay) return S.input.layouts[lay].secondary.name end
    local function vkey(lay, m, rows)
      return (m >= 512 and tsOf(lay) or "-") .. "|" .. m .. "|" .. table.concat(rows, ",", 0, 15)
    end
    local keyof = {}
    for i = 0, M.nVariants - 1 do
      local v = M.variants[i]
      keyof[vkey(v.layout, v.metatile, v.rows)] = i
    end
    for _, mem in ipairs(c.members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local lay = T.layoutIndex(lid)
      local art = c.arts[lid]
      local isAl = T.aliased(art)
      local ownXY = isAl and art.ownMetatile or art.metatile
      local function own(m) if m == nil then return nil end return T.terraceOwnId(lid, m) end
      local function recoloured(x, y)
        local mine, theirs = 0, 0
        for j = -1, 1 do
          for i = -1, 1 do
            local n = K(x + i + ox, y + j + oy)
            if c.src[n] and c.src[n][1] == lid and (c.kind[n] == ROCK or c.kind[n] == TOP) then
              if ownXY(x + i, y + j) >= 512 then mine = mine + 1 else theirs = theirs + 1 end
            end
          end
        end
        return mine > theirs
      end
      local t = M.layouts[lay]
      if t == nil then
        t = { w = art.w, h = art.h, flags = DRAWN_FLAG, base = 0, belt = 0, ease = 0, level = false, cells = {} }
        M.layouts[lay] = t
      end
      local base = t.base
      local mine = {}
      for _, cell in ipairs(c.kindOrder) do if c.src[cell][1] == lid then mine[#mine + 1] = cell end end
      local keep = {}
      for _, cell in ipairs(mine) do if c.keep[cell] then keep[K(c.src[cell][2], c.src[cell][3])] = true end end
      local laid = {}
      for _, cell in ipairs(mine) do
        if sol.kept and sol.kept[cell] then laid[K(c.src[cell][2], c.src[cell][3])] = cell end
      end
      local cells = {}
      for ck, g in pairs(t.cells) do
        local xy = K(ck % t.w, floor(ck / t.w))
        if keep[xy] and not laid[xy] then cells[ck] = g end
      end
      local function flatOf(cell)
        local g = sol.grids[cell]
        local out, any = {}, false
        for j = 0, N do
          for i = 0, N do
            local v = g[j][i] - base
            out[j * 5 + i] = v
            if abs(v) > 0.25 then any = true end
          end
        end
        return out, any
      end
      for xy, cell in pairs(laid) do
        local g, any = flatOf(cell)
        local ck = KY(xy) * t.w + KX(xy)
        if any or t.cells[ck] ~= nil then cells[ck] = g end
      end
      for _, cell in ipairs(mine) do
        local xy = K(c.src[cell][2], c.src[cell][3])
        if not keep[xy] then
          local g, any = flatOf(cell)
          if c.kind[cell] == ROCK or c.kind[cell] == TOP or any or recs[cell] ~= nil then
            cells[KY(xy) * t.w + KX(xy)] = g
          end
        end
      end
      t.cells = cells
      t.flags = bor(t.flags, DRAWN_FLAG)
      local cuts = {}
      for key, v in pairs(M.cuts) do
        local l = floor(key / 65536)
        local x, y = floor(key / 256) % 256, key % 256
        local xy = K(x, y)
        if l ~= lay or (keep[xy] and not laid[xy]) then cuts[key] = v end
      end
      for xy, cell in pairs(laid) do
        local rec = sol.kept_cuts and sol.kept_cuts[cell]
        if rec ~= nil then
          cuts[lay * 65536 + KX(xy) * 256 + KY(xy)] = { rec[1], Art.round(rec[2] - base), rec[3], rec[4], rec[5], rec[6] }
        end
      end
      for _, cell in ipairs(mine) do
        local xy = K(c.src[cell][2], c.src[cell][3])
        T.tickN()
        local r = recs[cell]
        if r ~= nil and not keep[xy] then
          local mask, foot, ground, wall, sides, flags = rv(r[1]), r[2], rv(r[3]), rv(r[4]), r[5], r[6]
          if isAl then
            ground = own(ground)
            if wall ~= nil and (recoloured(KX(xy), KY(xy)) or band(flags, CANOPY) ~= 0) then wall = own(wall) end
          end
          local hand = sol.behind and sol.behind[cell]
          if hand == nil then hand = sol.behind_carried and sol.behind_carried[cell] end
          if hand ~= nil and mask ~= nil then ground = hand end
          local k
          if mask == nil or mask == "fill" then
            k = NO_VARIANT
          else
            local m = ownXY(KX(xy), KY(xy))
            local key = vkey(lay, m, mask)
            if keyof[key] == nil then
              keyof[key] = M.nVariants
              local rows = {}
              for j = 0, 15 do rows[j] = mask[j] end
              M.variants[M.nVariants] = { layout = lay, metatile = m, rows = rows }
              M.nVariants = M.nVariants + 1
            end
            k = keyof[key]
          end
          cuts[lay * 65536 + KX(xy) * 256 + KY(xy)] = { k, Art.round(foot - base), ground == nil and NONE16 or ground,
                                                       wall == nil and NONE16 or wall, sides, flags }
        end
      end
      M.cuts = cuts
    end
    return M
  end

  --- every edge where two cells part with no wall closing it and no ground run on behind it
  function T.cracks(sol)
    local g = sol.grids
    local rec = T.records(sol)
    local out = {}
    for cell in pairs(g) do
      local x, y = KX(cell), KY(cell)
      for _, d in ipairs({ { K(x + 1, y), "E", "W" }, { K(x, y + 1), "S", "N" } }) do
        local n = d[1]
        if g[n] ~= nil then
          local a, b = edge(g[cell], d[2]), edge(g[n], d[3])
          local m1, m2 = -math.huge, -math.huge
          for i = 0, N do m1 = max(m1, a[i] - b[i]); m2 = max(m2, b[i] - a[i]) end
          if m1 > 0.5 and not (rec[cell] and rec[cell][4] ~= false) then out[#out + 1] = { cell, n, d[2] } end
          if m2 > 0.5 then
            local closed = rec[n] and (d[2] == "E" and rec[n][4] ~= false or (d[2] ~= "E" and rec[n][1] ~= false))
            if not closed then out[#out + 1] = { cell, n, d[2] } end
          end
        end
      end
    end
    return out
  end

  -- ── the groups, the world's count, the pass ──────────────────────────────────

  T.GROUPS = { "LAYOUT_ROUTE104", "LAYOUT_ROUTE105", "LAYOUT_ROUTE106", "LAYOUT_ROUTE116",
               "LAYOUT_SLATEPORT_CITY", "LAYOUT_ROUTE103", "LAYOUT_ROUTE109", "LAYOUT_DEWFORD_TOWN",
               "LAYOUT_ROUTE117", "LAYOUT_ROUTE115", "LAYOUT_ROUTE114", "LAYOUT_ROUTE123",
               "LAYOUT_PACIFIDLOG_TOWN", "LAYOUT_ROUTE133", "LAYOUT_ROUTE134", "LAYOUT_SAFARI_ZONE_NORTH",
               "LAYOUT_ROUTE111", "LAYOUT_ROUTE111_NO_MIRAGE_TOWER", "LAYOUT_LAVARIDGE_TOWN" }

  --- {(a, b): d} as a list { {a, b, d} }: the levels of a group's regions as the world solver reads
  --- them, counted as the terraces count them
  function T.regionTies(name, prep)
    local g = S.DRAWN_BY[name]
    local members = {}
    for _, lid in ipairs(g.members) do members[#members + 1] = { lid, g.at[lid][1], g.at[lid][2] } end
    local c = T.newCells(members)
    local runs = T.runsOf(c)
    local comp, compOrder = T.terraces(c, runs)
    local block = {}
    local lvl = T.solveLevels(c, comp, compOrder, runs, nil, nil, block)
    local regionMid, big, sizes = prep.regionMid, prep.big, prep.sizes
    local CW, CH = prep.CW, prep.CH
    local votes, vOrder = {}, {}
    for _, cell in ipairs(compOrder) do
      local t = comp[cell]
      local cx, cy = KX(cell), KY(cell)
      if cy < CH and cx < CW and cy >= 0 and cx >= 0 then
        local r = regionMid[cy][cx]
        if r >= 0 and big[r] then
          local v = votes[r]
          if not v then v = counter(); votes[r] = v; vOrder[#vOrder + 1] = r end
          v.add(block[t] .. "|" .. lvl[t])
        end
      end
    end
    local byBlock, bOrder = {}, {}
    for _, r in ipairs(vOrder) do
      local got = votes[r]
      local key, n = got.most()
      local total = 0
      for _, k in ipairs(got.order) do total = total + got.n[k] end
      if n * 5 >= total * 3 then
        local bar = key:find("|", 1, true)
        local b, lv = key:sub(1, bar - 1), tonumber(key:sub(bar + 1))
        local l = byBlock[b]
        if not l then l = {}; byBlock[b] = l; bOrder[#bOrder + 1] = b end
        l[#l + 1] = { r, lv }
      end
    end
    local ties = {}
    for _, b in ipairs(bOrder) do
      local rs = byBlock[b]
      local r0, l0
      for _, e in ipairs(rs) do
        if r0 == nil or sizes[e[1]] > sizes[r0] or (sizes[e[1]] == sizes[r0] and -e[1] > -r0) then r0, l0 = e[1], e[2] end
      end
      for _, e in ipairs(rs) do
        if e[1] ~= r0 then ties[#ties + 1] = { r0, e[1], l0 - e[2] } end
      end
    end
    return ties
  end
  if S.opt.regionTies == nil then
    S.opt.regionTies = function(name, prep) return T.regionTies(name, prep) end
  end

  function T.chosenLayouts()
    local out, have = {}, {}
    for _, l in ipairs(T.GROUPS) do out[#out + 1] = l; have[l] = true end
    for _, l in ipairs(T.markedLayouts()) do
      if not have[l] then out[#out + 1] = l; have[l] = true end
    end
    return out
  end

  --- The terraces over a model (the export's), in place: `reference` an untouched copy of it
  --- (Relief.decode(Relief.encode(M)) when not given, through opt.Relief). Returns the groups
  --- solved, { { name, terraces, dropped } }.
  function T.apply(M, reference, layouts)
    if reference == nil then
      local Relief = S.opt.Relief
      reference = Relief.decode(Relief.encode(M, nil, S.tick), S.tick)
    end
    local done = {}
    local report = {}
    for _, lid in ipairs(layouts or T.chosenLayouts()) do
      if not done[lid] and S.input.byName[lid] then
        local sol = T.solve(lid, reference)
        for _, mem in ipairs(sol.members) do done[mem[1]] = true end
        T.merge(sol, M)
        local nt, tset = 0, {}
        for _, t in pairs(sol.comp) do if not tset[t] then tset[t] = true; nt = nt + 1 end end
        report[#report + 1] = { name = lid, terraces = nt, dropped = #sol.dropped }
        if S.opt.phase then S.opt.phase("terraces:" .. lid) end
        tick()
      end
    end
    return report
  end
end
