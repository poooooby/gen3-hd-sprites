-- Mountains read as the tileset builds them, continued (Battle Scene: Overworld; see
-- src/scene/relief_terraces.lua): the pieces made to meet each other (staircases of bands, bands
-- and faces with nothing to fall, fins, face ends, hidden drops, rims' backs), rough rock laid as
-- one surface, ledges between two levels as steps, the hand marks, and the solve of a group
-- (solve_auto, finish).
--
-- Adapted from Emerald 3DS (3ds_port/scripts/voxel_terraces.py, by Zallax and contributors, CC
-- BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), as the first file says.

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local bit = require("bit")
local band, bor, rshift, lshift, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bnot

return function(S)
  local Solve, Art, T = S.Solve, S.Art, S.T
  local K, KX, KY = Solve.K, Solve.KX, Solve.KY
  local C = Solve.C
  local LEVEL, N = T.LEVEL, T.N
  local counter = Solve.counter
  local tick = S.tick
  local GROUND, TOP, ROCK, UNKNOWN = T.GROUND, T.TOP, T.ROCK, T.UNKNOWN
  local IS_CORNER, CORNERS = T.IS_CORNER, T.CORNERS
  local edge, level5, emax, emin, pg, pieceGrid, pieceEq = T.edge, T.level5, T.emax, T.emin, T.pg, T.pieceGrid, T.pieceEq
  local sortXY, sortedXY, sortedYX, cmpXY, keysOf, isBandKind, splitKind = T.sortXY, T.sortedXY, T.sortedYX, T.cmpXY, T.keysOf, T.isBandKind, T.splitKind
  local gmin, gmax, fill, gcopy, pyround = T.gmin, T.gmax, T.fill, T.gcopy, T.pyround
  local facingNs, facingWe, eflat = T.facingNs, T.facingWe, T.eflat
  local pixelClasses, CF, CT = T.pixelClasses, T.CF, T.CT
  local NULL = S.opt.jsonNull

  local function isnil(v) return v == nil or v == NULL end
  local function pieceKind(pieces, n) local p = pieces[n] return p and p[1] or "" end
  local function cornerOrS(k) return k == "S" or IS_CORNER[k] end
  local function allNear(e, v)
    for i = 0, N do if abs(e[i] - v) > 0.5 then return false end end
    return true
  end

  -- ── staircases of bands, bands with nothing to fall ──────────────────────────

  function T.staircases(c, pieces, flat, kept)
    local function dry(s)
      local out = s[1] == "E" and 1 or -1
      local cells = {}
      if s[2] then cells[#cells + 1] = s[2] end
      if s[4] then cells[#cells + 1] = s[4] end
      for _, cl in ipairs(s[3]) do cells[#cells + 1] = cl end
      for _, cell in ipairs(cells) do
        if c:water(K(KX(cell) + out, KY(cell))) then return false end
      end
      return true
    end
    local segs = {}
    for _, s in ipairs(T.segments(c)) do
      if dry(s) then
        local ok = true
        for _, cell in ipairs(s[3]) do
          if c.keep[cell] or pieceKind(pieces, cell) ~= s[1] then ok = false; break end
        end
        if ok then segs[#segs + 1] = s end
      end
    end
    local function northEdge(n)
      if kept[n] then return nil end
      if flat[n] ~= nil and c.kind[n] ~= ROCK then return level5(flat[n]) end
      local p = pieces[n]
      return p and edge(pg(p), "S") or nil
    end
    local function highEdge(n, side)
      if kept[n] then return nil end
      if flat[n] ~= nil and c.kind[n] ~= ROCK then return level5(flat[n]) end
      local p = pieces[n]
      if p == nil then return nil end
      return edge(pg(p), side == "E" and "E" or "W")
    end
    -- a fin: rock standing over the ground on three sides
    for _, cell in ipairs(sortedXY(pieces)) do
      local p = pieces[cell]
      if c.kind[cell] == ROCK and not c.keep[cell] and not kept[cell] then
        local x, y = KX(cell), KY(cell)
        local wet = c:water(K(x - 1, y)) or c:water(K(x + 1, y)) or c:water(K(x, y - 1))
        if not wet then
          local sides = { facingWe(c, pieces, flat, kept, K(x - 1, y), "W"), facingWe(c, pieces, flat, kept, K(x + 1, y), "E"),
                          facingNs(c, pieces, flat, kept, K(x, y - 1), "N") }
          local ok = true
          for i = 1, 3 do
            local e = sides[i]
            if e == nil or emax(e) - emin(e) > 0.5 then ok = false; break end
          end
          if ok then
            local lv = sides[1][0]
            for i = 1, 3 do if abs(sides[i][0] - lv) > 0.5 then ok = false end end
            if ok and gmax(pg(p)) > lv + 0.5 then pieces[cell] = { "F", lv } end
          end
        end
      end
    end
    for _ = 1, 4 do
      local moved = 0
      for _, s in ipairs(segs) do
        local side, head, cells, foot = s[1], s[2], s[3], s[4]
        T.tickN()
        local step = side == "E" and -1 or 1
        local votes = counter()
        local ask = #cells > 0 and cells or { head }
        for _, cell in ipairs(ask) do
          local n = K(KX(cell) + step, KY(cell))
          local e = highEdge(n, side)
          if e ~= nil and emax(e) - emin(e) <= 0.5 then
            votes.add(e[0], c.kind[n] == UNKNOWN and 1 or 2)
          end
        end
        if #cells == 0 then
          local n = K(KX(head), KY(head) - 1)
          local e = northEdge(n)
          if e ~= nil and emax(e) - emin(e) <= 0.5 then votes.add(e[0], c.kind[n] == UNKNOWN and 1 or 2) end
        end
        local edgeColumn = #cells > 0
        if edgeColumn then
          for _, cell in ipairs(cells) do
            if c.src[K(KX(cell) + step, KY(cell))] then edgeColumn = false; break end
          end
        end
        if edgeColumn then
          for _, cell in ipairs(cells) do
            local e = highEdge(K(KX(cell) - step, KY(cell)), side == "E" and "W" or "E")
            if e ~= nil and emax(e) - emin(e) <= 0.5 then votes.add(e[0] + LEVEL, 2) end
          end
        end
        if #votes.order > 0 then
          local top, tn
          for _, v in ipairs(votes.order) do
            local n = votes.n[v]
            if top == nil or n > tn or (n == tn and v > top) then top, tn = v, n end
          end
          local headPiece = head ~= nil and { "vS" .. side, top } or nil
          local skip = false
          if #cells > 0 then
            local ends = {}
            if head ~= nil then
              local n = K(KX(head), KY(head) - 1)
              local e = northEdge(n)
              local p = pieces[n]
              if c.kind[n] == ROCK and p ~= nil and p[1] == "S" and not kept[n] and e ~= nil
                  and emax(e) - emin(e) <= 0.5 and abs(e[0] + LEVEL - top) <= 0.5 then
                headPiece = { side, top }
              elseif e ~= nil and emax(e) - emin(e) <= 0.5 and c.kind[n] ~= UNKNOWN then
                if edgeColumn and abs(e[0] - top) > 0.5 then headPiece = nil
                else ends[#ends + 1] = e[0] - top end
              end
            end
            if foot ~= nil then
              local n = K(KX(foot), KY(foot) + 1)
              if flat[n] ~= nil and not kept[n] and (c.kind[n] == TOP or c.kind[n] == GROUND) then
                ends[#ends + 1] = flat[n] + LEVEL - top
              end
            end
            for _, d in ipairs(ends) do if abs(d) > 0.5 then skip = true end end
          end
          if not skip then
            local want = {}
            for _, cell in ipairs(cells) do want[#want + 1] = { cell, { side, top } } end
            if headPiece ~= nil then want[#want + 1] = { head, headPiece } end
            if foot ~= nil then want[#want + 1] = { foot, { "cS" .. side, top } } end
            for _, w in ipairs(want) do
              local cell, piece = w[1], w[2]
              if not kept[cell] and not c.keep[cell] and not pieceEq(pieces[cell], piece) then
                pieces[cell] = piece
                moved = moved + 1
              end
            end
          end
        end
      end
      if moved == 0 then break end
    end
  end

  function T.levelBands(c, pieces, flat, kept, measured)
    measured = measured or {}
    local function facing(n, side)
      if kept[n] then return nil end
      if flat[n] ~= nil and c.kind[n] ~= ROCK then return level5(flat[n]) end
      local p = pieces[n]
      if p == nil then return nil end
      return edge(pg(p), side == "W" and "E" or "W")
    end
    local segs = T.segments(c)
    local function plain(cell)
      return c.kind[cell] == ROCK and not c.band[cell] and not c.keep[cell] and not kept[cell]
        and cornerOrS(pieceKind(pieces, cell))
    end
    for _, cell in ipairs(sortedXY(pieces)) do
      local x, y = KX(cell), KY(cell)
      T.tickN()
      local up = K(x, y - 1)
      local go = plain(cell) and not (c.kind[up] == ROCK and not IS_CORNER[pieceKind(pieces, up)])
      if go and plain(up) and not IS_CORNER[pieces[up][1]] then go = false end
      if go then
        local run = { cell }
        while plain(K(x, KY(run[#run]) + 1)) do run[#run + 1] = K(x, KY(run[#run]) + 1) end
        local below = K(x, KY(run[#run]) + 1)
        if c.kind[below] ~= ROCK and not c:water(up) and not c:water(below) then
          local north = facingNs(c, pieces, flat, kept, up, "N")
          local skip = false
          if c.kind[below] == UNKNOWN and (north == nil or abs(gmax(pg(pieces[run[1]])) - emax(north)) <= 0.5) then
            skip = true
          end
          if not skip then
            local south = facingNs(c, pieces, flat, kept, below, "S")
            if north == nil or south == nil or emax(north) - emin(north) > 0.5 or emax(south) - emin(south) > 0.5 then
              skip = true
            end
            if not skip then
              local fall = (north[0] - south[0]) / LEVEL
              local rf = pyround(fall)
              if abs(fall - rf) > 0.01 or not (0 <= rf and rf <= #run) then skip = true end
              if not skip then
                fall = rf
                if fall ~= 0 then
                  for _, cl in ipairs(run) do if pieces[cl][1] ~= "S" then skip = true end end
                end
                if not skip then
                  if fall == 0 then
                    if not measured[up .. "|" .. below] then
                      for _, cl in ipairs(run) do pieces[cl] = { "F", north[0] } end
                    end
                  else
                    for i, cl in ipairs(run) do
                      if i - 1 < fall then pieces[cl] = { "S", north[0] - LEVEL * (i - 1) }
                      else pieces[cl] = { "F", north[0] - LEVEL * fall } end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    local function named(side, share)
      return side .. ":" .. T.fmtG(share)
    end
    local function chains()
      local moved = 0
      local wants, wantOrder = {}, {}
      for _, cell in ipairs(sortedXY(c.band)) do
        local side = c.band[cell]
        local x, y = KX(cell), KY(cell)
        local up = side == "W" and 1 or -1
        T.tickN()
        if c.band[K(x + up, y)] ~= side then
          local chain = { cell }
          while c.band[K(KX(chain[#chain]) - up, y)] == side do chain[#chain + 1] = K(KX(chain[#chain]) - up, y) end
          local bad = false
          for _, cl in ipairs(chain) do
            local pk = pieceKind(pieces, cl)
            if (pk ~= side and pk ~= "F" and splitKind(pk) ~= side) or c.keep[cl] then bad = true; break end
          end
          if not bad then
            local hiN, loN = K(x + up, y), K(KX(chain[#chain]) - up, y)
            local hi = facing(hiN, side == "W" and "E" or "W")
            local lo = facing(loN, side == "W" and "W" or "E")
            if hi ~= nil and lo ~= nil and emax(hi) - emin(hi) <= 0.5 and emax(lo) - emin(lo) <= 0.5 then
              local fall = hi[0] - lo[0]
              if not (fall >= LEVEL * #chain - 0.5) then
                local want = {}
                if fall <= 0.5 then
                  for i = 1, #chain do want[i] = { "F", hi[0] } end
                elseif abs(fall / LEVEL - pyround(fall / LEVEL)) > 0.01 then
                  local share = fall / #chain
                  for i = 1, #chain do want[i] = { named(side, share), hi[0] - share * (i - 1) } end
                else
                  local full = pyround(fall / LEVEL)
                  for i = 1, #chain do
                    if i - 1 < full then want[i] = { side, hi[0] - LEVEL * (i - 1) }
                    else want[i] = { "F", hi[0] - LEVEL * full } end
                  end
                end
                wants[#wants + 1] = { chain = chain, side = side, want = want }
              end
            end
          end
        end
      end
      local flatAt = {}
      for _, w in ipairs(wants) do
        for i, cl in ipairs(w.chain) do if w.want[i][1] == "F" then flatAt[cl] = true end end
      end
      for _, w in ipairs(wants) do
        local side = w.side
        local breaks = false
        for i, cl in ipairs(w.chain) do
          if w.want[i][1] == "F" then
            local x, y = KX(cl), KY(cl)
            for _, n in ipairs({ K(x, y - 1), K(x, y + 1) }) do
              if c.band[n] == side and not flatAt[n] and not c.keep[n] and splitKind(pieceKind(pieces, n)) == side then
                breaks = true
              end
            end
          end
        end
        if not breaks then
          for i, cl in ipairs(w.chain) do
            if not pieceEq(pieces[cl], w.want[i]) then
              pieces[cl] = w.want[i]
              moved = moved + 1
            end
          end
        end
      end
      return moved
    end
    local function ends()
      local moved = 0
      for _, s in ipairs(segs) do
        local side, head, cells, foot = s[1], s[2], s[3], s[4]
        if #cells > 0 then
          local tops, ntops, first = {}, 0, nil
          for _, cl in ipairs(cells) do
            local p = pieces[cl]
            if p then
              local key = p[1] .. "|" .. p[2]
              if not tops[key] then tops[key] = true; ntops = ntops + 1; first = first or p end
            end
          end
          if ntops == 1 and first[1] == "F" then
            local lv = first[2]
            for _, eb in ipairs({ { head, 0, "N" }, { foot, 1, "S" } }) do
              local e_, beyond, mine = eb[1], eb[2], eb[3]
              if e_ ~= nil and not c.keep[e_] and not kept[e_] then
                local n = K(KX(e_), beyond == 0 and KY(e_) - 1 or KY(e_) + 1)
                local e = facingNs(c, pieces, flat, kept, n, mine)
                if e ~= nil and allNear(e, lv) and not pieceEq(pieces[e_], { "F", lv }) then
                  pieces[e_] = { "F", lv }
                  moved = moved + 1
                end
              end
            end
          else
            for _, ebc in ipairs({ { head, cells[1], "vS" }, { foot, cells[#cells], "cS" } }) do
              local e_, bnd, corner = ebc[1], ebc[2], ebc[3]
              if e_ ~= nil and not c.keep[e_] and not kept[e_] and pieces[bnd] then
                local k, share = splitKind(pieces[bnd][1])
                if share ~= nil and k == side then
                  local piece = { corner .. side .. ":" .. T.fmtG(share), pieces[bnd][2] }
                  if not pieceEq(pieces[e_], piece) then
                    pieces[e_] = piece
                    moved = moved + 1
                  end
                end
              end
            end
          end
        end
      end
      return moved
    end
    for _ = 1, 6 do
      if chains() + ends() == 0 then break end
    end
  end

  --- "%g" of a float as Python formats it
  function T.fmtG(v)
    local s = string.format("%g", v)
    return s
  end

  local function nb4(c, pieces, flat, kept, n, its, flatOnly)
    if kept[n] then return nil end
    if flat[n] ~= nil and c.kind[n] ~= ROCK and (not flatOnly or pieceKind(pieces, n) == "F" or pieces[n] == nil) then
      return level5(flat[n])
    end
    local q = pieces[n]
    return q and edge(pg(q), its) or nil
  end

  local ROUND4 = { { 0, -1, "N", "S" }, { 0, 1, "S", "N" }, { -1, 0, "W", "E" }, { 1, 0, "E", "W" } }
  local function misfitOf(c, pieces, flat, kept, cell, piece, flatOnly)
    local g = pg(piece)
    local x, y = KX(cell), KY(cell)
    local total = 0.0
    for _, r in ipairs(ROUND4) do
      local e = nb4(c, pieces, flat, kept, K(x + r[1], y + r[2]), r[4], flatOnly)
      if e ~= nil then
        local mine = edge(g, r[3])
        for i = 0, N do total = total + abs(mine[i] - e[i]) end
      end
    end
    return total
  end

  function T.unstand(c, pieces, flat, kept)
    for _ = 1, 2 do
      local moved = 0
      for _, cell in ipairs(sortedXY(pieces)) do
        local p = pieces[cell]
        T.tickN()
        if c.kind[cell] == ROCK and not c.keep[cell] and not kept[cell] and p[1] ~= "F" then
          local x, y = KX(cell), KY(cell)
          local g = pg(p)
          local behindSet, behindList = {}, {}
          for _, bk in ipairs({ { K(x, y - 1), "N", "S", "S" }, { K(x + 1, y), "E", "W", "W" }, { K(x - 1, y), "W", "E", "E" } }) do
            local e = nb4(c, pieces, flat, kept, bk[1], bk[4], false)
            if e ~= nil then
              local top, foot = edge(g, bk[2]), edge(g, bk[3])
              local n = 0
              for i = 0, N do if top[i] - foot[i] > 0.5 and top[i] - e[i] > 0.5 then n = n + 1 end end
              if n >= 2 then
                for _, v in ipairs({ emax(e), emin(e) }) do
                  if not behindSet[v] then behindSet[v] = true; behindList[#behindList + 1] = v end
                end
              end
            end
          end
          if #behindList > 0 then
            table.sort(behindList)
            local kind = p[1]
            local best, bestM
            for _, lv in ipairs(behindList) do
              for _, k in ipairs({ kind, "F" }) do
                local q = { k, lv }
                local m = misfitOf(c, pieces, flat, kept, cell, q, false)
                if best == nil or m < bestM then best, bestM = q, m end
              end
            end
            if bestM < misfitOf(c, pieces, flat, kept, cell, p, false) - 0.5 then
              pieces[cell] = best
              moved = moved + 1
            end
          end
        end
      end
      if moved == 0 then break end
    end
  end

  function T.faceEnds(c, pieces, flat, kept)
    local function nb(n, its) return nb4(c, pieces, flat, kept, n, its, true) end
    for _, cell in ipairs(sortedXY(pieces)) do
      local p = pieces[cell]
      local m = c:metatile(cell)
      if c.kind[cell] == ROCK and not c.keep[cell] and not kept[cell] and p[1] == "S"
          and (T.UPPER_END[m] or T.LOWER_END[m]) then
        local x, y = KX(cell), KY(cell)
        local g = pg(p)
        for _, opt in ipairs({ { "vSW", K(x + 1, y), K(x - 1, y), "E", "W" }, { "vSE", K(x - 1, y), K(x + 1, y), "W", "E" } }) do
          local kind, topSide, other, mine, theirs = opt[1], opt[2], opt[3], opt[4], opt[5]
          local e, o = nb(topSide, theirs), nb(other, mine)
          local ok = not (e == nil or c.kind[topSide] == UNKNOWN or c:water(topSide) or not allNear(e, p[2]))
          if ok then
            local back = mine == "E" and "W" or "E"
            if o ~= nil then
              local eb = edge(g, back)
              for i = 0, N do if abs(eb[i] - o[i]) > 0.5 then ok = false end end
            end
          end
          if ok then
            local south = K(x, y + 1)
            local q = pieces[south]
            if q ~= nil and q[1] == "F" and not c.models[south] then
              local es = edge(pieceGrid(kind, p[2]), "S")
              for i = 0, N do if abs(es[i] - q[2]) > 0.5 then ok = false end end
            end
          end
          if ok then
            pieces[cell] = { kind, p[2] }
            break
          end
        end
      end
    end
  end

  function T.seamEdges(c, pieces, ref, meets, kept)
    local function top(art, m) return pixelClasses(art, m).T >= 128 end
    for _, cell in ipairs(sortedXY(meets)) do
      local mt = meets[cell]
      local other, meet, side, bx, by = mt[1], mt[2], mt[3], mt[4], mt[5]
      local p = pieces[cell]
      if meet and p ~= nil and p[1] == "F" and ref[cell] ~= nil and not kept[cell] and not c.keep[cell]
          and not c.ledges[cell] and (side == "left" or side == "right") then
        local bArt = T.terraceArt(other)
        if not (c.kind[cell] == TOP and top(c:art(cell), c:metatile(cell)) and top(bArt, bArt.metatile(bx, by))) then
          local r, h = ref[cell], p[2]
          if abs(abs(h - r) - LEVEL) <= 0.5 then
            if side == "right" then
              pieces[cell] = h > r and { "E", h } or { "W", r }
            else
              pieces[cell] = h > r and { "W", h } or { "E", r }
            end
          end
        end
      end
    end
  end

  function T.hiddenFaceEnds(c, pieces, flat, kept)
    local function nb(n, its) return nb4(c, pieces, flat, kept, n, its, false) end
    for _, cell in ipairs(sortedXY(pieces)) do
      local p = pieces[cell]
      if c.kind[cell] == UNKNOWN and c:role(cell) ~= "tree" and not c:house(cell) and not kept[cell] and p[1] == "F"
          and pixelClasses(c:art(cell), c:metatile(cell)).F >= 48 then
        local x, y = KX(cell), KY(cell)
        for _, opt in ipairs({ { "cSW", K(x + 1, y), K(x - 1, y) }, { "cSE", K(x - 1, y), K(x + 1, y) } }) do
          local kind, face, low = opt[1], opt[2], opt[3]
          local q = pieces[face]
          if q ~= nil and q[1] == "S" and not kept[face] and c.kind[face] == ROCK then
            local foot = q[2] - LEVEL
            local lows = { nb(low, kind == "cSW" and "E" or "W"), nb(K(x, y + 1), "N") }
            local ok = abs(p[2] - foot) <= 0.5
            for i = 1, 2 do
              local e = lows[i]
              if e == nil or not allNear(e, foot) then ok = false end
            end
            if ok then
              pieces[cell] = { kind, q[2] }
              break
            end
          end
        end
      end
    end
  end

  function T.rimBacks(c, pieces, flat, kept)
    local function nb(n, its) return nb4(c, pieces, flat, kept, n, its, true) end
    for _, cell in ipairs(sortedXY(pieces)) do
      local p = pieces[cell]
      local side = c.band[cell]
      if side ~= nil and c.kind[cell] == ROCK and not c.keep[cell] and not kept[cell] and p[1] == "F"
          and T.headOf(c:art(cell), c:metatile(cell)) == T.HEAD_DRAWN[side] then
        local x, y = KX(cell), KY(cell)
        local before = side == "E" and K(x - 1, y) or K(x + 1, y)
        local toe = nb(before, side == "E" and "E" or "W")
        local rim = nb(K(x, y + 1), "N")
        if c.band[before] == side and toe ~= nil and rim ~= nil and allNear(toe, p[2]) and allNear(rim, p[2] + LEVEL) then
          pieces[cell] = { side == "E" and "W" or "E", p[2] + LEVEL }
        end
      end
    end
  end

  function T.hiddenDrops(c, pieces, flat, kept)
    local function nb(n, its) return nb4(c, pieces, flat, kept, n, its, true) end
    local function misfit(cell, piece) return misfitOf(c, pieces, flat, kept, cell, piece, true) end
    local cands, candOrder = {}, {}
    for _, cell in ipairs(sortedXY(pieces)) do
      local p = pieces[cell]
      local k = c.kind[cell]
      T.tickN()
      if (k == GROUND or k == UNKNOWN) and c:role(cell) ~= "tree" and p[1] == "F" and not c:house(cell)
          and not kept[cell] and not c.keep[cell] and not c.ledges[cell] and not c.bridges[cell] then
        local s = c.src[cell]
        if not (c:water(cell) and not c.roles_of[s[1]].blocked(s[2], s[3])) then
          local e = nb(K(KX(cell), KY(cell) - 1), "S")
          if e ~= nil and emax(e) >= p[2] + LEVEL - 0.5 and misfit(cell, p) > 0.5 then
            cands[cell] = p
            candOrder[#candOrder + 1] = cell
          end
        end
      end
    end
    for _, cell in ipairs(candOrder) do pieces[cell] = { "S", cands[cell][2] + LEVEL } end
    for _ = 1, 6 do
      local moved = 0
      for _, cell in ipairs(candOrder) do
        local p = cands[cell]
        local options = { p }
        for _, k in ipairs({ "S", "cSW", "cSE", "vSW", "vSE" }) do options[#options + 1] = { k, p[2] + LEVEL } end
        local best, bm, bne
        for _, q in ipairs(options) do
          local m = misfit(cell, q)
          local ne = not pieceEq(q, p)
          if best == nil or m < bm or (m == bm and ne == false and bne == true) then best, bm, bne = q, m, ne end
        end
        if not pieceEq(best, pieces[cell]) and bm < misfit(cell, pieces[cell]) - 0.5 then
          pieces[cell] = best
          moved = moved + 1
        end
      end
      if moved == 0 then break end
    end
    for _, cell in ipairs(candOrder) do
      if misfit(cell, pieces[cell]) > 0.5 then
        pieces[cell] = cands[cell]
        for _, m in ipairs(candOrder) do
          if abs(KX(m) - KX(cell)) + abs(KY(m) - KY(cell)) == 1 then pieces[m] = cands[m] end
        end
      end
    end
  end

  function T.behindTrees(c, flat, grids, pieces, marked)
    marked = marked or {}
    for _, cell in ipairs(sortedYX(grids)) do
      if c.kind[cell] == UNKNOWN and c:role(cell) == "tree" and not c.keep[cell] and not marked[cell]
          and not (pieces ~= nil and pieceKind(pieces, cell) ~= "F" and pieces[cell] ~= nil) then
        local x, y = KX(cell), KY(cell)
        local up = K(x, y - 1)
        local north = grids[up]
        if north ~= nil and not c.keep[up] then
          local low = flat[cell]
          if low == nil then low = gmin(grids[cell]) end
          local top = north[N]
          if emax(top) > low + 0.5 then
            local trunk = K(x, y + 1)
            local function faceBeside(n)
              local p = pieces ~= nil and pieces[n] or nil
              return p ~= nil and (p[1] == "S" or IS_CORNER[p[1]]) and abs(p[2] - top[0]) < 0.5
            end
            local tf = flat[trunk]
            if tf == nil then tf = low end
            if pieces ~= nil and not T.treeCard(c, cell) and c.src[trunk] ~= nil and T.smallTrunk(c, trunk)
                and emax(top) - emin(top) < 0.5 and abs(top[0] - LEVEL - tf) < 0.5
                and (faceBeside(K(x - 1, y)) or faceBeside(K(x + 1, y))) then
              pieces[cell] = { "S", top[0] }
              grids[cell] = pieceGrid("S", top[0])
            else
              grids[cell] = fill(low)
            end
          end
        end
      end
    end
  end

  -- ── groups, the world's placement ────────────────────────────────────────────

  local JOIN = { { "LAYOUT_ROUTE115", "LAYOUT_ROUTE114" } }
  T.TWINS = { { "LAYOUT_ROUTE111_NO_MIRAGE_TOWER", "LAYOUT_ROUTE111" } }
  local TWIN_OF = {}
  for _, tw in ipairs(T.TWINS) do TWIN_OF[tw[1]] = tw[2] end

  --- { { layout, x, y } }: the drawn group a layout is solved in, placed
  function T.groupOf(lid)
    local function drawn(l)
      for _, g in ipairs(S.DRAWN) do
        if g.at[l] then
          local d = {}
          for _, m in ipairs(g.members) do d[m] = { g.at[m][1], g.at[m][2] } end
          return d, g.members
        end
      end
      return { [l] = { 0, 0 } }, { l }
    end
    local placed, order = drawn(lid)
    local grown = true
    while grown do
      grown = false
      for _, j in ipairs(JOIN) do
        for _, ho in ipairs({ { j[1], j[2] }, { j[2], j[1] } }) do
          local have, other = ho[1], ho[2]
          if placed[have] and not placed[other] then
            local link
            for _, cn in ipairs(S.propConnections()[have] or {}) do
              if cn[1] == other then link = { cn[2], cn[3] }; break end
            end
            if link then
              local ox, oy = placed[have][1] + link[1], placed[have][2] + link[2]
              local theirs, torder = drawn(other)
              local bx, by = theirs[other][1], theirs[other][2]
              for _, l in ipairs(torder) do
                if not placed[l] then
                  placed[l] = { theirs[l][1] - bx + ox, theirs[l][2] - by + oy }
                  order[#order + 1] = l
                end
              end
              grown = true
            end
          end
        end
      end
    end
    local out = {}
    for _, l in ipairs(order) do out[#out + 1] = { l, placed[l][1], placed[l][2] } end
    table.sort(out, function(a, b)
      local fa, fb = a[1] ~= lid, b[1] ~= lid
      if fa ~= fb then return not fa end
      return a[1] < b[1]
    end)
    return out
  end

  local function layoutIndex(lid) local L = S.input.byName[lid] return L and L.id end
  T.layoutIndex = layoutIndex
  local function sizeOf(lid) local L = S.input.byName[lid] return L.w, L.h end

  --- {canvas cell: height in the world} of a model's cells (centre point)
  function T.referenceHeights(M, members)
    local out = {}
    for _, mem in ipairs(members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local t = M.layouts[layoutIndex(lid)]
      if t ~= nil then
        local w, h = sizeOf(lid)
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local g = t.cells[y * t.w + x]
            out[K(x + ox, y + oy)] = t.base + (g and g[12] or 0)
          end
        end
      end
    end
    return out
  end

  local function seamCells(a, b, direction, offset)
    local aw, ah = sizeOf(a)
    local bw, bh = sizeOf(b)
    local out = {}
    if direction == "up" or direction == "down" then
      for x = max(0, offset), min(aw, offset + bw) - 1 do
        out[#out + 1] = { direction == "down" and "down" or "up", x, direction == "down" and "up" or "down", x - offset }
      end
    else
      for y = max(0, offset), min(ah, offset + bh) - 1 do
        out[#out + 1] = { direction == "right" and "right" or "left", y, direction == "right" and "left" or "right", y - offset }
      end
    end
    return out
  end
  T.seamCells = seamCells
  local function cellAt(lid, edge_, i)
    local w, h = sizeOf(lid)
    if edge_ == "down" then return i, h - 1 elseif edge_ == "up" then return i, 0
    elseif edge_ == "right" then return w - 1, i end
    return 0, i
  end

  --- {canvas cell: { map across, meets, edge, bx, by }}
  function T.seamFaces(M, members)
    local at = {}
    for _, mem in ipairs(members) do at[mem[1]] = { mem[2], mem[3] } end
    local function height(lid, x, y)
      local t = M.layouts[layoutIndex(lid)]
      if t == nil then return 0 end
      local g = t.cells[y * t.w + x]
      return t.base + (g and g[12] or 0)
    end
    local same = {}
    for l in pairs(at) do same[l] = true end
    for alt, base in pairs(S.alternates) do
      if at[base] then same[alt] = true end
      if at[alt] then same[base] = true end
    end
    local out = {}
    for _, l in ipairs(S.mapLinks()) do
      local a, b, direction, offset = l[1], l[2], l[3], l[4]
      if at[a] and not same[b] then
        for _, sc in ipairs(seamCells(a, b, direction, offset)) do
          local ea, ia, eb, ib = sc[1], sc[2], sc[3], sc[4]
          local ax, ay = cellAt(a, ea, ia)
          local bx, by = cellAt(b, eb, ib)
          local ha, hb = height(a, ax, ay), height(b, bx, by)
          local cell = K(ax + at[a][1], ay + at[a][2])
          local prev = out[cell]
          out[cell] = { b, (prev ~= nil and prev[2]) or abs(ha - hb) <= floor(LEVEL / 2), ea, bx, by }
        end
      end
    end
    return out
  end

  -- ── rough rock ───────────────────────────────────────────────────────────────

  local CRAGS = { lavaridge = { [0x268] = true, [0x269] = true, [0x26a] = true, [0x27e] = true, [0x27f] = true } }
  local ROUGH_MIN, ROUGH_HOLE = 8, 6
  local BY_CORNERS = { ["0,0,0,0"] = "F", ["0,0,-1,-1"] = "S", ["0,-1,0,-1"] = "E", ["-1,0,-1,0"] = "W",
                       ["0,-1,-1,-1"] = "cSE", ["-1,0,-1,-1"] = "cSW", ["0,0,0,-1"] = "vSE", ["0,0,-1,0"] = "vSW" }
  local BACK, BACK_RIM, BACK_MAX = 3.0, 0.2, 4
  local WALL, DRAWN, RIDGE, WALKED, BACK_IN, FACE_LIT = 20.0, 2.0, 0.6, 2.0, 0.5, 1.0
  local CORNER_COST, FIN = T.CORNER, T.FIN

  function T.seamCellsOf(c)
    local at = {}
    for _, mem in ipairs(c.members) do at[mem[1]] = { mem[2], mem[3] } end
    local out = {}
    for _, l in ipairs(S.mapLinks()) do
      local a, b, direction, offset = l[1], l[2], l[3], l[4]
      if at[a] then
        local w, h = sizeOf(a)
        for _, sc in ipairs(seamCells(a, b, direction, offset)) do
          local ea, i = sc[1], sc[2]
          local x, y
          if ea == "up" then x, y = i, 0 elseif ea == "down" then x, y = i, h - 1
          elseif ea == "left" then x, y = 0, i else x, y = w - 1, i end
          out[K(x + at[a][1], y + at[a][2])] = true
        end
      end
    end
    return out
  end

  local function bxor_(e, b) return bit.bxor(e, b) end
  -- the nodes on the source's side of a minimum s-t cut (Dinic's blocking flows)
  local function sourceSide(n, arcs, s, t)
    local to, cap, nxt, head = {}, {}, {}, {}
    for u = 0, n - 1 do head[u] = -1 end
    local ne = 0
    for _, a in ipairs(arcs) do
      local u, v, w = a[1], a[2], a[3]
      to[ne], cap[ne], nxt[ne] = v, w, head[u]
      head[u] = ne
      to[ne + 1], cap[ne + 1], nxt[ne + 1] = u, 0.0, head[v]
      head[v] = ne + 1
      ne = ne + 2
    end
    local eps = 1e-9
    local lvl = {}
    while true do
      for u = 0, n - 1 do lvl[u] = -1 end
      lvl[s] = 0
      local queue = { s }
      local qi = 1
      while qi <= #queue do
        local u = queue[qi]
        qi = qi + 1
        local e = head[u]
        while e >= 0 do
          if cap[e] > eps and lvl[to[e]] < 0 then
            lvl[to[e]] = lvl[u] + 1
            queue[#queue + 1] = to[e]
          end
          e = nxt[e]
        end
      end
      if lvl[t] < 0 then break end
      local it = {}
      for u = 0, n - 1 do it[u] = head[u] end
      while true do
        local path, u = {}, s
        local dead = false
        while u ~= t do
          local e = it[u]
          while e >= 0 and not (cap[e] > eps and lvl[to[e]] == lvl[u] + 1) do e = nxt[e] end
          it[u] = e
          if e < 0 then
            if #path == 0 then dead = true; break end
            lvl[u] = -1
            e = table.remove(path)
            u = to[bxor_(e, 1)]
            it[u] = nxt[it[u]]
          else
            path[#path + 1] = e
            u = to[e]
          end
        end
        if dead or u ~= t then break end
        local push = math.huge
        for _, e in ipairs(path) do push = min(push, cap[e]) end
        for _, e in ipairs(path) do
          cap[e] = cap[e] - push
          local r = bxor_(e, 1)
          cap[r] = cap[r] + push
        end
      end
      tick()
    end
    local seen = {}
    for u = 0, n - 1 do seen[u] = false end
    seen[s] = true
    local queue = { s }
    local qi = 1
    while qi <= #queue do
      local u = queue[qi]
      qi = qi + 1
      local e = head[u]
      while e >= 0 do
        if cap[e] > eps and not seen[to[e]] then
          seen[to[e]] = true
          queue[#queue + 1] = to[e]
        end
        e = nxt[e]
      end
    end
    return seen
  end

  -- integer labels 0..K-1 minimising unary + convex hinges: one minimum cut (Ishikawa)
  local function convexLabels(Kn, unary, hinges)
    local INF = 1e12
    local nv = #unary
    local u2 = {}
    for v = 1, nv do
      local row = {}
      for lab = 0, Kn - 1 do row[lab] = unary[v][lab] end
      u2[v] = row
    end
    local arcs = {}
    local function node(v, k) return 2 + (v - 1) * (Kn - 1) + (k - 1) end
    for _, h in ipairs(hinges) do
      local i, j, t, w = h[1], h[2], h[3], h[4]
      if w == nil then w = INF end
      for k = t + 1, Kn + max(0, t) do
        if k <= 0 then
          for lab = 0, min(Kn, k - t) - 1 do u2[j][lab] = u2[j][lab] + w end
        elseif k > Kn - 1 then
          -- continue
        elseif k - t > Kn - 1 then
          for lab = k, Kn - 1 do u2[i][lab] = u2[i][lab] + w end
        elseif k - t >= 1 then
          arcs[#arcs + 1] = { node(i, k), node(j, k - t), w }
        end
      end
    end
    for v = 1, nv do
      local low = math.huge
      for lab = 0, Kn - 1 do low = min(low, u2[v][lab]) end
      local u = {}
      for lab = 0, Kn - 1 do u[lab] = min(INF, u2[v][lab] - low) end
      if Kn > 1 then arcs[#arcs + 1] = { 0, node(v, 1), u[0] } else arcs[#arcs + 1] = { 0, 1, 0.0 } end
      for k = 1, Kn - 2 do
        arcs[#arcs + 1] = { node(v, k), node(v, k + 1), u[k] }
        arcs[#arcs + 1] = { node(v, k + 1), node(v, k), INF }
      end
      if Kn > 1 then arcs[#arcs + 1] = { node(v, Kn - 1), 1, u[Kn - 1] } end
    end
    local side = sourceSide(2 + nv * (Kn - 1), arcs, 0, 1)
    local out = {}
    for v = 1, nv do
      local n = 0
      for k = 1, Kn - 1 do if side[node(v, k)] then n = n + 1 end end
      out[v] = n
    end
    return out
  end

  local function layRough(c, field, fieldList, pieces, kept)
    local function fixed(n)
      if field[n] or not c.kind[n] then return nil end
      if kept[n] then return kept[n] end
      return pieces[n] and pg(pieces[n]) or nil
    end
    local info = {}
    for _, cell in ipairs(fieldList) do
      local cls = pixelClasses(c:art(cell), c:metatile(cell))
      local f = cls.F / 256.0
      local pref = c.band[cell] or (T.isFace(c, cell) and "S" or "F")
      if pref == "W" or pref == "E" then
        local x, y = KX(cell), KY(cell)
        local high = pref == "W" and K(x + 1, y) or K(x - 1, y)
        if c.band[high] or c.kind[high] == ROCK then pref, f = "F", 0.0 end
      end
      if c.walked_tops[cell] or c:role(cell) == "floor" then pref = "_" end
      info[cell] = { pref, f }
    end
    -- the lattice's points, sorted as Python sorts ("D" before "U", then x, then y)
    local vset, verts = {}, {}
    local function addV(tag, x, y)
      local key = tag .. "|" .. x .. "|" .. y
      if not vset[key] then
        vset[key] = true
        verts[#verts + 1] = { tag, x, y, key }
      end
    end
    for _, cell in ipairs(fieldList) do
      local x, y = KX(cell), KY(cell)
      addV("U", x, y); addV("U", x + 1, y)
      addV("D", x, y + 1); addV("D", x + 1, y + 1)
    end
    table.sort(verts, function(a, b)
      if a[1] ~= b[1] then return a[1] < b[1] end
      if a[2] ~= b[2] then return a[2] < b[2] end
      return a[3] < b[3]
    end)
    local index = {}
    for k, v in ipairs(verts) do index[v[4]] = k end          -- 1-based
    local function idx(tag, x, y) return index[tag .. "|" .. x .. "|" .. y] end
    local lo, hiT
    for _, cell in ipairs(fieldList) do
      local a, b, cc, d = T.four(cell)
      for _, n in ipairs({ a, b, cc, d }) do
        local g = fixed(n)
        if g ~= nil then
          local m = gmax(g)
          if lo == nil or m < lo then lo = m end
          if hiT == nil or m > hiT then hiT = m end
        end
      end
    end
    lo = floor(lo / LEVEL + 1e-6)
    local Kn = ceil(hiT / LEVEL - 1e-6) + BACK_MAX - lo + 1
    local unary = {}
    for v = 1, #verts do
      local row = {}
      for lab = 0, Kn - 1 do row[lab] = 0.0 end
      unary[v] = row
    end
    local hinges = {}
    local function linear(v, w)
      local row = unary[v]
      for lab = 0, Kn - 1 do row[lab] = row[lab] + w * lab end
    end
    local function meet(v, p, below, above)
      local row = unary[v]
      for lab = 0, Kn - 1 do
        local d = lo + lab - p / LEVEL
        row[lab] = row[lab] + 0.5 * (d > 0 and above(d) or below(-d))
      end
    end
    local function wall(d) return WALL * d end
    for _, cell in ipairs(fieldList) do
      local x, y = KX(cell), KY(cell)
      local n = K(x, y - 1)
      while field[n] do n = K(KX(n), KY(n) - 1) end
      local g = fixed(n)
      if g ~= nil then
        local cap = floor(emax(edge(g, "S")) / LEVEL + 1e-6) + BACK_MAX - lo
        for _, v in ipairs({ idx("U", x, y), idx("U", x + 1, y), idx("D", x, y + 1), idx("D", x + 1, y + 1) }) do
          local row = unary[v]
          for lab = max(0, cap + 1), Kn - 1 do row[lab] = row[lab] + WALL * (lab - cap) end
        end
      end
    end
    for _, v in ipairs(verts) do
      if v[1] == "U" then
        local i, j = v[2], v[3]
        local dn = idx("D", i, j)
        if dn ~= nil then
          local u = index[v[4]]
          local face = false
          for _, n in ipairs({ K(i - 1, j), K(i, j) }) do
            local inf = info[n]
            if (inf and inf[1] or "F") == "S" then face = true end
          end
          hinges[#hinges + 1] = { dn, u, 0, nil }
          hinges[#hinges + 1] = { u, dn, face and 0 or 1, nil }
          linear(u, BACK_IN)
          linear(dn, -BACK_IN)
        end
      end
    end
    for _, cell in ipairs(fieldList) do
      local x, y = KX(cell), KY(cell)
      local a, b = idx("U", x, y), idx("U", x + 1, y)
      local cc, d = idx("D", x, y + 1), idx("D", x + 1, y + 1)
      for _, h in ipairs({ { cc, a, 0 }, { a, cc, 1 }, { d, b, 0 }, { b, d, 1 }, { a, b, 1 }, { b, a, 1 },
                           { cc, d, 1 }, { d, cc, 1 }, { a, d, 1 }, { b, cc, 1 } }) do
        hinges[#hinges + 1] = { h[1], h[2], h[3], nil }
      end
      local pref, f = info[cell][1], info[cell][2]
      local fall, ew
      if pref == "S" then
        fall, ew = { DRAWN * f / 2, 0.0 }, { CORNER_COST, 0.0, CORNER_COST }
      elseif pref == "E" then
        fall, ew = { 0.0, CORNER_COST }, { DRAWN * f + FIN / 2, DRAWN * f / 2, 0.0 }
      elseif pref == "W" then
        fall, ew = { 0.0, CORNER_COST }, { 0.0, DRAWN * f / 2, DRAWN * f + FIN / 2 }
      elseif pref == "_" then
        fall, ew = { 0.0, WALL }, { WALL, 0.0, WALL }
        for _, v in ipairs({ a, b, cc, d }) do
          local row = unary[v]
          for lab = 0, Kn - 1 do row[lab] = row[lab] + 0.25 * WALKED * abs(lo + lab - pieces[cell][2] / LEVEL) end
        end
      else
        local up = max(0.0, (RIDGE - DRAWN * f) / 2)
        fall, ew = { DRAWN * f / 2, FACE_LIT / 2 }, { up, 0.0, up }
      end
      for _, ns in ipairs({ { a, cc }, { b, d } }) do
        linear(ns[1], fall[2] - fall[1])
        linear(ns[2], fall[1] - fall[2])
      end
      for _, we in ipairs({ { a, b }, { cc, d } }) do
        local s1 = ew[2] - ew[1]
        linear(we[1], s1)
        linear(we[2], -s1)
        hinges[#hinges + 1] = { we[1], we[2], 0, (ew[3] - ew[2]) - s1 }
      end
      for _, nm in ipairs({ { K(x - 1, y), { a, cc }, "E" }, { K(x + 1, y), { b, d }, "W" },
                            { K(x, y - 1), { a, b }, "S" }, { K(x, y + 1), { cc, d }, "N" } }) do
        local g = fixed(nm[1])
        if g ~= nil then
          local e = edge(g, nm[3])
          local mine = nm[2]
          local ps = { e[0], e[N] }
          if nm[3] == "E" or nm[3] == "W" then
            for k = 1, 2 do meet(mine[k], ps[k], wall, wall) end
          elseif nm[3] == "S" then
            local back = (c.rim[cell] and pref == "F") and BACK_RIM or ((pref == "F" or pref == "_") and BACK or WALL)
            local function above(dd) return back * dd + WALL * max(0.0, dd - BACK_MAX) end
            for k = 1, 2 do meet(mine[k], ps[k], wall, above) end
          else
            local function below(dd) return BACK * dd end
            for k = 1, 2 do meet(mine[k], ps[k], below, wall) end
          end
        end
      end
    end
    local labels = convexLabels(Kn, unary, hinges)
    local height = {}
    for k, v in ipairs(verts) do height[v[4]] = lo + labels[k] end
    local out = {}
    for _, cell in ipairs(fieldList) do
      local x, y = KX(cell), KY(cell)
      local a, b = height["U|" .. x .. "|" .. y], height["U|" .. (x + 1) .. "|" .. y]
      local cc, d = height["D|" .. x .. "|" .. (y + 1)], height["D|" .. (x + 1) .. "|" .. (y + 1)]
      local h = max(a, b, cc, d)
      out[cell] = { BY_CORNERS[(a - h) .. "," .. (b - h) .. "," .. (cc - h) .. "," .. (d - h)], h * LEVEL }
    end
    return out
  end

  local function woodsAtFoot(c, field, fieldList, pieces, flat, kept, seams)
    local function tree(n)
      return pieces[n] ~= nil and pieces[n][1] == "F" and not field[n] and not kept[n] and not c.keep[n]
        and not seams[n] and c:role(n) == "tree" and c:drawn_on(n) == "G"
    end
    local seen = {}
    local border, bset = {}, {}
    for _, cell in ipairs(fieldList) do
      local a, b, cc, d = T.four(cell)
      for _, n in ipairs({ a, b, cc, d }) do
        if not field[n] and not bset[n] then bset[n] = true; border[#border + 1] = n end
      end
    end
    sortXY(border)
    for _, start in ipairs(border) do
      if not seen[start] and tree(start) then
        local wood, woodList, todo = {}, {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          wood[cell] = true
          woodList[#woodList + 1] = cell
          local a, b, cc, d = T.four(cell)
          for _, n in ipairs({ a, b, cc, d }) do
            if not seen[n] and tree(n) then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local ground
        for _, cell in ipairs(woodList) do
          local a, b, cc, d = T.four(cell)
          for _, n in ipairs({ a, b, cc, d }) do
            if not wood[n] and not field[n] and pieces[n] ~= nil and pieces[n][1] == "F" and c.kind[n] == GROUND
                and c:role(n) ~= "tree" then
              local v = pieces[n][2]
              if ground == nil or v < ground then ground = v end
            end
          end
        end
        if ground ~= nil then
          for _, cell in ipairs(woodList) do
            pieces[cell] = { "F", ground }
            flat[cell] = ground
          end
        end
      end
    end
  end

  function T.roughFields(c, pieces, flat, kept)
    local function ownId(cell)
      local s = c.src[cell]
      local art = c.arts[s[1]]
      if T.aliased(art) then return art.ownMetatile(s[2], s[3]) end
      return nil
    end
    local function own(cell)
      local m = ownId(cell)
      return m ~= nil and m >= 512
    end
    local seams = T.seamCellsOf(c)
    local function tileset(cell) return S.input.byName[c.src[cell][1]].secondary.name end
    local function member(cell)
      if not c.kind[cell] or c.keep[cell] or kept[cell] or seams[cell] then return false end
      if c:water(cell) or c:is_stair(cell) or c.bridges[cell] or not own(cell) then return false end
      local k = c.kind[cell]
      return k == TOP or k == ROCK or c:drawn_on(cell) ~= "G"
    end
    local seen = {}
    for _, start in ipairs(sortedXY(c.kind)) do
      if not seen[start] and member(start) then
        local field, fieldList, todo = {}, {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          field[cell] = true
          fieldList[#fieldList + 1] = cell
          local a, b, cc, d = T.four(cell)
          for _, n in ipairs({ a, b, cc, d }) do
            if not seen[n] and member(n) then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local crags = 0
        for _, cell in ipairs(fieldList) do
          local cr = CRAGS[tileset(cell)]
          if cr and cr[ownId(cell)] then crags = crags + 1 end
        end
        if crags >= ROUGH_MIN then
          local tried = {}
          local border, bset = {}, {}
          for _, cell in ipairs(fieldList) do
            local a, b, cc, d = T.four(cell)
            for _, n in ipairs({ a, b, cc, d }) do
              if not field[n] and not bset[n] then bset[n] = true; border[#border + 1] = n end
            end
          end
          sortXY(border)
          for _, hs in ipairs(border) do
            if not tried[hs] then
              local hole, holeList, todo2, closed = {}, {}, { hs }, true
              local inTodo = { [hs] = true }
              local nhole = 0
              while #todo2 > 0 do
                local cell = table.remove(todo2)
                if not hole[cell] then
                  hole[cell] = true
                  holeList[#holeList + 1] = cell
                  nhole = nhole + 1
                end
                if not c.kind[cell] or c.keep[cell] or kept[cell] or seams[cell] or c:is_stair(cell)
                    or c:water(cell) or nhole > ROUGH_HOLE then
                  closed = false
                  break
                end
                local a, b, cc, d = T.four(cell)
                for _, n in ipairs({ a, b, cc, d }) do
                  if not field[n] and not hole[n] and not inTodo[n] then
                    inTodo[n] = true
                    todo2[#todo2 + 1] = n
                  end
                end
              end
              for _, h in ipairs(holeList) do tried[h] = true end
              if closed then
                -- (field |= hole: the hole's cells in Python's set order)
                for _, h in ipairs(T.pySetCells(holeList)) do
                  if not field[h] then field[h] = true; fieldList[#fieldList + 1] = h end
                end
              end
            end
          end
          -- (for x, y in field: the set's own order)
          local fieldOrdered = T.pySetCells(fieldList)
          woodsAtFoot(c, field, fieldOrdered, pieces, flat, kept, seams)
          local laid = layRough(c, field, fieldOrdered, pieces, kept)
          for cell, p in pairs(laid) do pieces[cell] = p end
          for cell in pairs(field) do c.rough[cell] = true end
          for cell, p in pairs(laid) do flat[cell] = gmin(pg(p)) end
        end
      end
    end
  end

  -- ── ledges between two levels ────────────────────────────────────────────────

  local lips = {}
  function T.ledgeLip(lid)
    local lip = lips[lid]
    if lip then return lip end
    local art = S.aliasOf(lid) and S.vbArt(lid) or S.layoutArt(lid)
    local cells, list, lip0 = S.ledgeLip(S.openRoles(lid), art)
    lip = {}
    for k, v in pairs(lip0) do lip[k] = v end
    local shape, bare = {}, {}
    local order = {}
    for _, e in ipairs(list) do order[#order + 1] = K(e[1], e[2]) end
    sortXY(order)
    for _, cell in ipairs(order) do
      local x, y = KX(cell), KY(cell)
      local px = {}
      for j = 0, 15 do
        for i = 0, 15 do
          if lip[K(x * 16 + i, y * 16 + j)] then px[#px + 1] = { i, j } end
        end
      end
      if #px > 0 then
        local m = art.metatile(x, y)
        if shape[m] == nil then shape[m] = px end
      else
        bare[#bare + 1] = cell
      end
    end
    for _, cell in ipairs(bare) do
      local x, y = KX(cell), KY(cell)
      for _, ij in ipairs(shape[art.metatile(x, y)] or {}) do lip[K(x * 16 + ij[1], y * 16 + ij[2])] = true end
    end
    lips[lid] = lip
    return lip
  end

  local function ledgeLevel(c, pieces, flat, cell)
    if c.keep[cell] or not c.src[cell] then return nil end
    if pieces ~= nil then
      local p = pieces[cell]
      return (p ~= nil and p[1] == "F") and p[2] or nil
    end
    if c.kind[cell] == ROCK then return nil end
    return flat[cell]
  end

  function T.ledgeLandings(c, flat)
    local function floorCell(n)
      return flat[n] ~= nil and not c.keep[n] and not c:water(n) and (c.kind[n] == GROUND or c:walked(n))
    end
    local landings, seen = {}, {}
    for _, start in ipairs(sortedXY(flat)) do
      if not seen[start] and floorCell(start) then
        local comp, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          comp[#comp + 1] = cell
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
            if not seen[n] and floorCell(n) then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local inside = {}
        for _, cell in ipairs(comp) do inside[cell] = true end
        local ins, outs, closed = {}, {}, true
        for _, cell in ipairs(comp) do
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
            if not inside[n] then
              local dirs = c.jumps[n]
              if dirs then
                for _, d in ipairs(dirs) do
                  local nx, ny = KX(n), KY(n)
                  if K(nx + d[1], ny + d[2]) == cell then ins[#ins + 1] = K(nx - d[1], ny - d[2])
                  elseif K(nx - d[1], ny - d[2]) == cell then outs[#outs + 1] = K(nx + d[1], ny + d[2]) end
                end
              elseif not c.src[n] or c:walked(n) or c:water(n) or c.keep[n] or c:role(n) == "stair" then
                closed = false
              end
            end
          end
          if not closed then break end
        end
        if closed and #ins > 0 and #outs > 0 then
          local i = 1
          while i <= #comp do
            local cell = comp[i]
            local x, y = KX(cell), KY(cell)
            for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
              if not (inside[n] or flat[n] == nil or c.keep[n] or c.kind[n] ~= UNKNOWN or c:walked(n)
                  or c:role(n) == "stair" or c:house(n)) then
                local nx, ny = KX(n), KY(n)
                local all = true
                for _, m in ipairs({ K(nx - 1, ny), K(nx + 1, ny), K(nx, ny - 1), K(nx, ny + 1) }) do
                  if not (inside[m] or c.jumps[m] or c.kind[m] == ROCK) then all = false end
                end
                if all then
                  inside[n] = true
                  comp[#comp + 1] = n
                end
              end
            end
            i = i + 1
          end
          landings[#landings + 1] = { comp, ins, outs }
        end
      end
    end
    local out = {}
    for _ = 1, 8 do
      local moved = false
      for _, l in ipairs(landings) do
        local comp, ins, outs = l[1], l[2], l[3]
        local hi, lo
        for _, n in ipairs(ins) do
          local v = ledgeLevel(c, nil, flat, n)
          if v ~= nil and (hi == nil or v > hi) then hi = v end
        end
        for _, n in ipairs(outs) do
          local v = ledgeLevel(c, nil, flat, n)
          if v ~= nil and (lo == nil or v < lo) then lo = v end
        end
        if hi ~= nil and lo ~= nil and hi > lo + 0.5 then
          local v = (hi + lo) / 2.0
          for _, cell in ipairs(comp) do
            if abs(flat[cell] - v) > 0.01 then
              flat[cell] = v
              out[cell] = v
              moved = true
            end
          end
        end
      end
      if not moved then break end
    end
    return out
  end

  local function ledgeDrawn(c, cell)
    local s = c.src[cell]
    local lip = T.ledgeLip(s[1])
    local x, y = s[2], s[3]
    for j = 0, 15 do
      for i = 0, 15 do
        if lip[K(x * 16 + i, y * 16 + j)] then return true end
      end
    end
    return false
  end

  local function dkey(d) return d[1] .. "," .. d[2] end
  local function sameDir(a, b) return a[1] == b[1] and a[2] == b[2] end

  --- {ledge cell: { dirs = {...}, hl = { [dkey] = { high, low } } }}
  function T.ledgeSides(c, pieces, flat, marks)
    marks = marks or {}
    local function only(n, d)
      local dirs = c.jumps[n]
      return dirs ~= nil and #dirs == 1 and sameDir(dirs[1], d)
    end
    local function chained(a, b, d) return only(a, d) and only(b, d) end
    local out = {}
    for cell, dirs in pairs(c.jumps) do
      local x, y = KX(cell), KY(cell)
      local hl = {}
      for _, d in ipairs(dirs) do
        hl[dkey(d)] = { ledgeLevel(c, pieces, flat, K(x - d[1], y - d[2])), ledgeLevel(c, pieces, flat, K(x + d[1], y + d[2])) }
      end
      out[cell] = { dirs = dirs, hl = hl }
    end
    local cellsSorted = sortedXY(out)
    for _ = 1, 64 do
      local changed = false
      for _, cell in ipairs(cellsSorted) do
        local x, y = KX(cell), KY(cell)
        for _, d in ipairs(out[cell].dirs) do
          local hl = out[cell].hl[dkey(d)]
          for k = 1, 2 do
            if hl[k] == nil then
              for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
                local nx, ny = KX(n), KY(n)
                local skip = (abs(nx - x) == abs(d[1]) and abs(ny - y) == abs(d[2])) and chained(cell, n, d)
                if not skip then
                  local v = out[n] and out[n].hl[dkey(d)]
                  if v ~= nil and v[k] ~= nil then
                    hl[k] = v[k]
                    changed = true
                    break
                  end
                end
              end
            end
          end
        end
      end
      if not changed then break end
    end
    local chains = {}
    for _, cell in ipairs(cellsSorted) do
      for _, d in ipairs(out[cell].dirs) do
        local x, y = KX(cell), KY(cell)
        if only(cell, d) and not chained(K(x - d[1], y - d[2]), cell, d) then
          local chain = { cell }
          while chained(chain[#chain], K(KX(chain[#chain]) + d[1], KY(chain[#chain]) + d[2]), d) do
            chain[#chain + 1] = K(KX(chain[#chain]) + d[1], KY(chain[#chain]) + d[2])
          end
          if #chain > 1 then chains[#chains + 1] = { d, chain } end
        end
      end
    end
    for _, ch in ipairs(chains) do
      local d, chain = ch[1], ch[2]
      local hi, lo = out[chain[1]].hl[dkey(d)][1], out[chain[#chain]].hl[dkey(d)][2]
      if hi ~= nil and lo ~= nil then
        local drawn = {}
        for _, n in ipairs(chain) do if ledgeDrawn(c, n) then drawn[#drawn + 1] = n end end
        if #drawn == 0 then drawn = chain end
        local dset = {}
        for _, n in ipairs(drawn) do dset[n] = true end
        local v = hi
        for _, n in ipairs(chain) do
          local top = v
          if dset[n] then v = v - (hi - lo) / #drawn end
          out[n].hl[dkey(d)] = { top, v }
        end
      end
    end
    for cell, m in pairs(marks) do
      if out[cell] then
        for _, hl in pairs(out[cell].hl) do
          if not isnil(m.level) then
            hl[1] = m.level
            if isnil(m.foot) and hl[2] ~= nil and hl[2] > hl[1] then hl[2] = hl[1] end
          end
          if not isnil(m.foot) then
            hl[2] = m.foot
            if isnil(m.level) and hl[1] ~= nil and hl[1] < hl[2] then hl[1] = hl[2] end
          end
        end
      end
    end
    for _, ch in ipairs(chains) do
      local d, chain = ch[1], ch[2]
      for i = 1, #chain - 1 do
        local a, b = chain[i], chain[i + 1]
        local ma, mb = marks[a] or {}, marks[b] or {}
        if not isnil(mb.level) and isnil(ma.foot) then out[a].hl[dkey(d)][2] = out[b].hl[dkey(d)][1]
        elseif not isnil(ma.foot) and isnil(mb.level) then out[b].hl[dkey(d)][1] = out[a].hl[dkey(d)][2] end
      end
    end
    return out
  end

  local LIP, LIP_WIDTH, LIP_BACK = C.LIP, C.LIP_WIDTH, C.LIP_BACK
  local function stepGrid(lip, x, y, sides)
    local dirs = sides.dirs
    local grid = {}
    for j = 0, N do
      local row = {}
      for i = 0, N do
        local reads = S.ledgeReads(lip, x, y, dirs, i, j)
        local on, front, behindL = {}, {}, {}
        for _, r in ipairs(reads) do
          local sx, sy, dx, dy, f, b = r[1], r[2], r[3], r[4], r[5], r[6]
          local hl = sides.hl[dx .. "," .. dy]
          local hi, lo = hl[1], hl[2]
          if b ~= 0 and f == 0 and not (x * 16 <= sx - dx and sx - dx < x * 16 + 16 and y * 16 <= sy - dy and sy - dy < y * 16 + 16) then
            b = 0
          end
          if f ~= 0 then on[#on + 1] = lo + (hi - lo) * min(f, LIP_WIDTH) / LIP_WIDTH
          elseif b ~= 0 then front[#front + 1] = lo
          else behindL[#behindL + 1] = hi end
        end
        local v
        if #on > 0 and #front == 0 and #behindL == 0 then
          v = math.huge
          for _, q in ipairs(on) do v = min(v, q) end
        elseif #front > 0 then
          v = math.huge
          for _, q in ipairs(front) do v = min(v, q) end
        else
          v = -math.huge
          for _, q in ipairs(on) do v = max(v, q) end
          for _, q in ipairs(behindL) do v = max(v, q) end
        end
        row[i] = 2 * pyround(v / 2.0)
      end
      grid[j] = row
    end
    return grid
  end

  local function bermGrid(lip, x, y, dirs, lvl)
    local grid, front = {}, {}
    for j = 0, N do
      local row = {}
      for i = 0, N do
        local reads = S.ledgeReads(lip, x, y, dirs, i, j)
        local v = 0.0
        local allF, anyB = true, false
        for _, r in ipairs(reads) do
          if r[5] == 0 then allF = false end
          if r[6] ~= 0 and r[5] == 0 then anyB = true end
        end
        if allF then
          v = math.huge
          for _, r in ipairs(reads) do v = min(v, S.lipHeight(r[5])) end
        elseif anyB then
          front[j * (N + 1) + i] = true
        else
          for _, r in ipairs(reads) do
            local sx, sy, dx, dy = r[1], r[2], r[3], r[4]
            local k
            for kk = 0, LIP_BACK - 1 do
              if lip[K(sx + kk * dx, sy + kk * dy)] then k = kk; break end
            end
            if k ~= nil then
              local top = S.lipHeight(S.lipRun(lip, sx + k * dx, sy + k * dy, dx, dy))
              v = max(v, top * (1.0 - k / LIP_BACK))
            end
          end
        end
        row[i] = lvl + 2 * pyround(v / 2.0)
      end
      grid[j] = row
    end
    return grid, front
  end

  local function meetEdges(c, pieces, cell, grid)
    local x, y = KX(cell), KY(cell)
    local sides = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    local want = {}
    for _, d in ipairs(sides) do
      local dx, dy = d[1], d[2]
      local n = K(x + dx, y + dy)
      if not c.keep[n] and pieces[n] ~= nil then
        local g = pg(pieces[n])
        local points = {}
        if dx == -1 then for j = 0, N do points[#points + 1] = { 0, j } end
        elseif dx == 1 then for j = 0, N do points[#points + 1] = { N, j } end
        elseif dy == -1 then for i = 0, N do points[#points + 1] = { i, 0 } end
        else for i = 0, N do points[#points + 1] = { i, N } end end
        for _, ij in ipairs(points) do
          local i, j = ij[1], ij[2]
          local v = g[j - dy * N][i - dx * N]
          if not (dy < 0 and v < grid[j][i]) then
            local key = j * (N + 1) + i
            local l = want[key]
            if not l then l = {}; want[key] = l end
            l[#l + 1] = v
          end
        end
      end
    end
    for key, vs in pairs(want) do
      local i, j = key % (N + 1), floor(key / (N + 1))
      local best, bd
      for _, v in ipairs(vs) do
        local d = abs(v - grid[j][i])
        if best == nil or d < bd then best, bd = v, d end
      end
      grid[j][i] = best
    end
  end

  local function cornerGrid(c, lip, cell, kept, pieces, flat)
    local s = c.src[cell]
    local lx, ly = s[2], s[3]
    local ox, oy = lx * 16, ly * 16
    local onLip, comp = {}, {}
    for j = 0, 15 do
      for i = 0, 15 do onLip[j * 16 + i] = lip[K(ox + i, oy + j)] == true end
    end
    local regions = {}
    for j0 = 0, 15 do
      for i0 = 0, 15 do
        local k0 = j0 * 16 + i0
        if not onLip[k0] and comp[k0] == nil then
          local k = #regions
          local todo, px = { { i0, j0 } }, {}
          comp[k0] = k
          while #todo > 0 do
            local p = table.remove(todo)
            local i, j = p[1], p[2]
            px[#px + 1] = { i, j }
            for _, ab in ipairs({ { i - 1, j }, { i + 1, j }, { i, j - 1 }, { i, j + 1 } }) do
              local a, b = ab[1], ab[2]
              if a >= 0 and a < 16 and b >= 0 and b < 16 and not onLip[b * 16 + a] and comp[b * 16 + a] == nil then
                comp[b * 16 + a] = k
                todo[#todo + 1] = { a, b }
              end
            end
          end
          regions[k + 1] = px
        end
      end
    end
    local x, y = KX(cell), KY(cell)
    local function across(dx, dy, k)
      local n = K(x + dx, y + dy)
      local g
      if kept[n] then g = kept[n]
      elseif pieces ~= nil and pieces[n] ~= nil then g = pg(pieces[n])
      elseif flat[n] ~= nil and not c.keep[n] then return flat[n]
      else return nil end
      if dx > 0 then return g[k][0] elseif dx < 0 then return g[k][N] elseif dy > 0 then return g[0][k] end
      return g[N][k]
    end
    local lvl = {}
    for r, px in ipairs(regions) do
      local vs = {}
      for _, ij in ipairs(px) do
        local i, j = ij[1], ij[2]
        for _, e in ipairs({ { -1, 0, i == 0 }, { 1, 0, i == 15 }, { 0, -1, j == 0 }, { 0, 1, j == 15 } }) do
          if e[3] then
            local dx, dy = e[1], e[2]
            local v = across(dx, dy, min(N, floor((dx ~= 0 and j or i) / (16 / N))))
            if v ~= nil then vs[#vs + 1] = v end
          end
        end
      end
      if #vs > 0 then
        table.sort(vs)
        lvl[r] = vs[floor(#vs / 2) + 1]
      else
        lvl[r] = false
      end
    end
    local known = {}
    for r, v in ipairs(lvl) do if v ~= false then known[#known + 1] = { r, v } end end
    if #known == 0 then return nil end
    local grid = {}
    for j = 0, N do
      local row = {}
      for i = 0, N do
        local near, nearList = {}, {}
        for _, a in ipairs({ i * 4 - 1, i * 4 }) do
          for _, b in ipairs({ j * 4 - 1, j * 4 }) do
            if a >= 0 and a < 16 and b >= 0 and b < 16 then
              local r = comp[b * 16 + a]
              if r ~= nil and lvl[r + 1] ~= false and not near[r] then
                near[r] = true
                nearList[#nearList + 1] = r
              end
            end
          end
        end
        local v
        if #nearList > 0 then
          -- (sum over a set of ints / len)
          local total = 0
          for _, r in ipairs(nearList) do total = total + lvl[r + 1] end
          v = total / #nearList
        else
          local best, bestOrder = {}, {}
          for _, kv in ipairs(known) do
            local r, h = kv[1], kv[2]
            local d = math.huge
            for _, ab in ipairs(regions[r]) do
              d = min(d, abs(ab[1] - i * 4 + 0.5) + abs(ab[2] - j * 4 + 0.5))
            end
            if best[h] == nil then best[h] = d; bestOrder[#bestOrder + 1] = h
            elseif d < best[h] then best[h] = d end
          end
          local items = {}
          for idx_, h in ipairs(bestOrder) do items[#items + 1] = { h, best[h], idx_ } end
          table.sort(items, function(p, q)
            if p[2] ~= q[2] then return p[2] < q[2] end
            return p[3] < q[3]
          end)
          local h1, d1 = items[1][1], items[1][2]
          local h2, d2
          if #items >= 2 then h2, d2 = items[2][1], items[2][2] else h2, d2 = h1, d1 end
          v = h1 == h2 and h1 or (h1 * d2 + h2 * d1) / (d1 + d2)
        end
        row[i] = 2 * pyround(v / 2.0)
      end
      grid[j] = row
    end
    return grid
  end

  --- lay_ledges: in place in kept and cuts; returns { sides, steps, uphill }
  function T.layLedges(c, pieces, flat, kept, cuts, marks)
    marks = marks or {}
    local sides = T.ledgeSides(c, pieces, flat, marks)
    local steps, uphill = {}, {}
    if pieces ~= nil then
      for _, cell in ipairs(sortedXY(sides)) do
        local ways = sides[cell]
        local any = false
        for _, hl in pairs(ways.hl) do
          if hl[1] ~= nil and hl[2] ~= nil and hl[1] - hl[2] > 0.5 then any = true end
        end
        if any then
          local x, y = KX(cell), KY(cell)
          for _, nk in ipairs({ { K(x - 1, y), "vSW" }, { K(x + 1, y), "vSE" } }) do
            local n, kind = nk[1], nk[2]
            local p, below = pieces[n], pieces[K(KX(n), KY(n) + 1)]
            if p ~= nil and p[1] == kind and c.kind[n] == ROCK and not c.keep[n] and marks[n] == nil
                and below ~= nil and below[1] == "F" and abs(below[2] - (p[2] - LEVEL)) < 0.5 then
              pieces[n] = { "S", p[2] }
            end
          end
        end
      end
    end
    for _, cell in ipairs(sortedXY(sides)) do
      local ways = sides[cell]
      local known, nknown, firstKnown = {}, 0, nil
      for _, d in ipairs(ways.dirs) do
        local hl = ways.hl[dkey(d)]
        if hl[1] ~= nil and hl[2] ~= nil then
          known[dkey(d)] = hl
          nknown = nknown + 1
          firstKnown = firstKnown or hl
        end
      end
      if nknown > 0 then
        local allLevel = true
        for _, d in ipairs(ways.dirs) do
          local hl = known[dkey(d)]
          if hl then
            if hl[1] < hl[2] - 0.5 then
              uphill[cell] = true
              hl[2] = hl[1]
            end
            if abs(hl[1] - hl[2]) > 0.5 then allLevel = false end
          end
        end
        if allLevel then
          local lo = math.huge
          for _, hl in pairs(known) do lo = min(lo, hl[2]) end
          local d = kept[cell] and (lo - gmin(kept[cell])) or 0
          if abs(d) >= LEVEL / 2 then
            local g = kept[cell]
            local ng = {}
            for j = 0, N do local r = {} for i = 0, N do r[i] = g[j][i] + d end ng[j] = r end
            kept[cell] = ng
            if cuts[cell] then
              local cu = cuts[cell]
              cuts[cell] = { cu[1], cu[2] + d, cu[3], cu[4], cu[5], cu[6] }
            end
          end
          if kept[cell] then
            local s = c.src[cell]
            local lid, lx, ly = s[1], s[2], s[3]
            local x0, y0 = KX(cell), KY(cell)
            local g, front = bermGrid(T.ledgeLip(lid), lx, ly, ways.dirs, lo)
            local off = false
            for key in pairs(front) do
              local i, j = key % (N + 1), floor(key / (N + 1))
              if abs(kept[cell][j][i] - lo) > LIP then off = true end
            end
            if off then
              for j = 0, N do
                for i = 0, N do
                  local xs = i == 0 and { x0 - 1, x0 } or i == N and { x0, x0 + 1 } or { x0 }
                  local ys = j == 0 and { y0 - 1, y0 } or j == N and { y0, y0 + 1 } or { y0 }
                  local all = true
                  for _, a in ipairs(xs) do
                    for _, b in ipairs(ys) do if not c.jumps[K(a, b)] then all = false end end
                  end
                  if not all then g[j][i] = lo end
                end
              end
              kept[cell] = g
              if cuts[cell] then
                local cu = cuts[cell]
                cuts[cell] = { cu[1], lo, cu[3], 0xFFFF, 255, cu[6] }
              end
            end
          end
        else
          for _, d in ipairs(ways.dirs) do
            if not known[dkey(d)] then
              ways.hl[dkey(d)] = { firstKnown[1], firstKnown[2] }
            end
          end
          local s = c.src[cell]
          kept[cell] = stepGrid(T.ledgeLip(s[1]), s[2], s[3], ways)
          if pieces ~= nil then meetEdges(c, pieces, cell, kept[cell]) end
          steps[cell] = true
          cuts[cell] = nil
        end
      end
    end
    for _, cell in ipairs(sortedXY(steps)) do
      if #c.jumps[cell] >= 2 then
        local s = c.src[cell]
        local g = cornerGrid(c, T.ledgeLip(s[1]), cell, kept, pieces, flat)
        if g ~= nil then
          kept[cell] = g
          if pieces ~= nil then meetEdges(c, pieces, cell, kept[cell]) end
        end
        local x, y = KX(cell), KY(cell)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local dx, dy = d[1], d[2]
          local n = K(x + dx, y + dy)
          if kept[n] and c.jumps[n] and #c.jumps[n] == 1 then
            for k = 0, N do
              local i, j
              if dx ~= 0 then i, j = (dx > 0 and N or 0), k else i, j = k, (dy > 0 and N or 0) end
              kept[cell][j][i] = kept[n][j - dy * N][i - dx * N]
            end
          end
        end
      end
    end
    return { sides = sides, steps = steps, uphill = uphill }
  end

  local function soilLevel(grid)
    local cnt = counter()
    for j = 0, N do
      for i = 0, N do
        if i == 0 or i == N or j == 0 or j == N then cnt.add(grid[j][i]) end
      end
    end
    return cnt.most()
  end

  function T.laySoil(c, pieces, kept, cuts, marks, marked)
    marked = marked or {}
    local seen = {}
    local starts = {}
    for cell in pairs(c.keep) do
      if not c.jumps[cell] and kept[cell] then starts[#starts + 1] = cell end
    end
    sortXY(starts)
    for _, start in ipairs(starts) do
      if not seen[start] then
        local run, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          run[#run + 1] = cell
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
            if c.keep[n] and not c.jumps[n] and kept[n] and not seen[n] then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local nowC = counter()
        for _, cell in ipairs(run) do nowC.add(gmin(kept[cell])) end
        local now = nowC.most()
        local target = {}
        for _, cell in ipairs(run) do
          local m = marks[cell]
          if m and not isnil(m.level) then target[#target + 1] = m.level end
        end
        local near = {}
        for _, cell in ipairs(run) do
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do near[n] = true end
        end
        local want
        local go = true
        if #target > 0 then
          want = Art.commonest(target, Art.hashInt)
        else
          local touches = false
          for n in pairs(near) do if marked[n] then touches = true end end
          if not touches then
            go = false
          else
            local roundIt = counter()
            for _, cell in ipairs(run) do
              local x, y = KX(cell), KY(cell)
              for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
                if not c.keep[n] and pieces[n] ~= nil and pieces[n][1] == "F" then roundIt.add(pieces[n][2]) end
              end
            end
            if #roundIt.order == 0 then go = false else want = roundIt.most() end
          end
        end
        if go then
          for _, cell in ipairs(run) do
            local m = marks[cell]
            local own = m and not isnil(m.level) and m.level or nil
            local d = own ~= nil and (own - soilLevel(kept[cell])) or (want - now)
            if abs(d) >= 0.5 then
              local g = kept[cell]
              local ng = {}
              for j = 0, N do local r = {} for i = 0, N do r[i] = g[j][i] + d end ng[j] = r end
              kept[cell] = ng
              if cuts[cell] then
                local cu = cuts[cell]
                cuts[cell] = { cu[1], cu[2] + d, cu[3], cu[4], cu[5], cu[6] }
              end
            end
          end
        end
      end
    end
  end

  function T.facesAtLandings(c, pieces, grids, steps)
    for _, cell in ipairs(sortedXY(steps)) do
      local x, y = KX(cell), KY(cell)
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local dx, dy = d[1], d[2]
        local n = K(x + dx, y + dy)
        local q = pieces[n]
        if not c.keep[n] and q ~= nil and q[1] == "F" and grids[n] ~= nil then
          local g, s = gcopy(grids[n]), grids[cell]
          local frac = ((q[2] - gmin(s)) / LEVEL) % 1
          if not (abs(frac - 0.5) > 0.1) then
            for k = 0, N do
              local i, j
              if dx ~= 0 then i, j = (dx > 0 and 0 or N), k else i, j = k, (dy > 0 and 0 or N) end
              g[j][i] = s[j + dy * N][i + dx * N]
            end
            grids[n] = g
          end
        end
      end
    end
    for cell, p in pairs(pieces) do
      if not c.keep[cell] and c.kind[cell] == ROCK and grids[cell] ~= nil then
        local g = gcopy(grids[cell])
        grids[cell] = g
        local top, foot = gmax(g), gmin(g)
        local x, y = KX(cell), KY(cell)
        for _, di in ipairs({ { -1, 0 }, { 1, N } }) do
          local n = K(x + di[1], y)
          local q = pieces[n]
          if not (c.keep[n] or q == nil or q[1] ~= "F" or not (foot + 0.5 < q[2] and q[2] < top - 0.5)
              or abs(((q[2] - foot) / LEVEL) % 1 - 0.5) > 0.1) then
            for j = 0, N do g[j][di[2]] = min(g[j][di[2]], q[2]) end
          end
        end
      end
    end
  end

  -- ── the solve ────────────────────────────────────────────────────────────────

  function T.solveAuto(lid, reference)
    local members = T.groupOf(lid)
    local c = T.newCells(members)
    tick()
    local runs = T.runsOf(c)
    local comp, compOrder = T.terraces(c, runs)
    tick()
    local ref = reference ~= nil and T.referenceHeights(reference, members) or nil
    local meets = reference ~= nil and T.seamFaces(reference, members) or nil
    local lvl, dropped = T.solveLevels(c, comp, compOrder, runs, ref, meets)
    tick()
    local counted = {}
    for _, r in ipairs(runs) do counted[r[2]] = true; counted[r[4]] = true end
    local membersOf, mOrder = {}, {}
    for _, cell in ipairs(compOrder) do
      local t = comp[cell]
      local l = membersOf[t]
      if not l then l = {}; membersOf[t] = l; mOrder[#mOrder + 1] = t end
      l[#l + 1] = cell
    end
    for _, t in ipairs(mOrder) do
      local cells = membersOf[t]
      local skip = #cells > 4
      if not skip then
        for _, cell in ipairs(cells) do
          if counted[cell] or c.kind[cell] ~= GROUND or c:water(cell) then skip = true; break end
        end
      end
      if not skip then
        local roundIt = counter()
        for _, cell in ipairs(cells) do
          local x, y = KX(cell), KY(cell)
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
            if comp[n] and comp[n] ~= t and not c:water(n) then roundIt.add(lvl[comp[n]]) end
          end
        end
        if #roundIt.order > 0 then
          local best, k = roundIt.most()
          local total = 0
          for _, v in ipairs(roundIt.order) do total = total + roundIt.n[v] end
          if best ~= lvl[t] and 2 * k > total then lvl[t] = best end
        end
      end
    end
    local U = T.upperLevels(c, comp, lvl, runs)
    local fixed = {}
    for _, r in ipairs(runs) do
      local d, hi, cells, lo = r[1], r[2], r[3], r[4]
      if comp[hi] and comp[lo] then
        local _, n = T.steps(c, cells, d)
        if lvl[comp[hi]] - lvl[comp[lo]] == LEVEL * n then
          for _, cell in ipairs(cells) do fixed[cell] = true end
        end
      end
    end
    local flat = {}
    for cell, t in pairs(comp) do flat[cell] = lvl[t] end
    for cell, v in pairs(T.unknownLevels(c, comp, lvl, U)) do flat[cell] = v end
    tick()
    U = T.settle(c, U, flat, fixed)
    for _, cell in ipairs(sortedXY(c.band)) do
      local side = c.band[cell]
      local x, y = KX(cell), KY(cell)
      local up = side == "W" and 1 or -1
      local hi = K(x + up, y)
      if c.band[hi] ~= side then
        local chain = { cell }
        while c.band[K(KX(chain[#chain]) - up, y)] == side do chain[#chain + 1] = K(KX(chain[#chain]) - up, y) end
        local lo = K(KX(chain[#chain]) - up, y)
        if flat[hi] ~= nil and flat[lo] ~= nil and c.kind[hi] ~= ROCK and c.kind[lo] ~= ROCK
            and abs(flat[hi] - flat[lo] - LEVEL * #chain) <= 0.5 then
          for i, b in ipairs(chain) do U[b] = flat[hi] - LEVEL * (i - 1) end
        end
      end
    end
    local landings = T.ledgeLandings(c, flat)
    local kept, keepShift, keptCuts = {}, {}, {}
    if reference ~= nil then
      for cell in pairs(c.keep) do
        local s = c.src[cell]
        local t = reference.layouts[layoutIndex(s[1])]
        if t ~= nil then
          local g = t.cells[s[3] * t.w + s[2]]
          local kg = {}
          for j = 0, N do
            local row = {}
            for i = 0, N do row[i] = t.base + (g and g[j * (N + 1) + i] or 0) end
            kg[j] = row
          end
          kept[cell] = kg
        end
      end
      local function refAt(cell)
        local s = c.src[cell]
        local t = reference.layouts[layoutIndex(s[1])]
        if t == nil then return nil end
        local g = t.cells[s[3] * t.w + s[2]]
        local mn = 0
        if g then mn = math.huge for k = 0, 24 do mn = min(mn, g[k]) end end
        return t.base + mn
      end
      local seen = {}
      -- (for start in list(kept): the dict's order - c.keep's iteration order, a set: Python's)
      local keptList = T.pySetCells(c.keepOrder)
      local kl2 = {}
      for _, cell in ipairs(keptList) do if kept[cell] then kl2[#kl2 + 1] = cell end end
      for _, start in ipairs(kl2) do
        if not seen[start] then
          local run, todo = {}, { start }
          seen[start] = true
          while #todo > 0 do
            local cell = table.remove(todo)
            run[#run + 1] = cell
            local x, y = KX(cell), KY(cell)
            for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
              if kept[n] and not seen[n] then
                seen[n] = true
                todo[#todo + 1] = n
              end
            end
          end
          local shifts = counter()
          for _, cell in ipairs(run) do
            local x, y = KX(cell), KY(cell)
            for _, n in ipairs({ K(x - 1, y), K(x + 1, y), K(x, y - 1), K(x, y + 1) }) do
              if not kept[n] and flat[n] ~= nil and c.kind[n] == GROUND and not c:water(n) then
                local r = refAt(n)
                if r ~= nil then shifts.add(pyround(flat[n] - r)) end
              end
            end
          end
          if #shifts.order > 0 then
            local d = shifts.most()
            if d ~= 0 then
              for _, cell in ipairs(run) do
                local g = kept[cell]
                local ng = {}
                for j = 0, N do local r = {} for i = 0, N do r[i] = g[j][i] + d end ng[j] = r end
                kept[cell] = ng
                keepShift[cell] = d
              end
            end
          end
        end
      end
      for cell in pairs(kept) do
        local s = c.src[cell]
        local lay = layoutIndex(s[1])
        local rec = reference.cuts[lay * 65536 + s[2] * 256 + s[3]]
        if rec ~= nil then
          keptCuts[cell] = { rec[1], rec[2] + reference.layouts[lay].base + (keepShift[cell] or 0), rec[3], rec[4], rec[5], rec[6] }
        end
      end
    end
    local keptBerm, keptCutsBerm = {}, {}
    for k, v in pairs(kept) do keptBerm[k] = v end
    for k, v in pairs(keptCuts) do keptCutsBerm[k] = v end
    local ledges = T.layLedges(c, nil, flat, kept, keptCuts)
    local pieces = T.blocks(c, U, flat, kept)
    local trace = S.opt.trace or function() end
    trace("after_blocks", pieces)
    tick()
    -- a gap in a face drawn in a town's own tiles
    local function gapCell(n, h)
      local q = pieces[n]
      if q == nil or q[1] ~= "F" or c.keep[n] or c.bridges[n] then return false end
      local k = c.kind[n]
      if not (k == GROUND or (k == UNKNOWN and (c:role(n) ~= "tree" or c:metatile(n) >= 512))) then return false end
      if q[2] >= h - 0.5 then return k == GROUND end
      local up = K(KX(n), KY(n) - 1)
      local north = pieces[up]
      return abs(q[2] - (h - LEVEL)) < 0.5 and north ~= nil and north[2] >= h - 0.5 and c.kind[up] ~= ROCK
    end
    local byRow = keysOf(pieces)
    table.sort(byRow, function(a, b)
      local ya, yb = KY(a), KY(b)
      if ya ~= yb then return ya > yb end
      return KX(a) < KX(b)
    end)
    for _, cell in ipairs(byRow) do
      local x, y = KX(cell), KY(cell)
      local left = pieces[K(x - 1, y)]
      if left ~= nil and left[1] == "S" then
        local h = left[2]
        if gapCell(cell, h) then
          local run = { cell }
          while true do
            local n = K(KX(run[#run]) + 1, y)
            local q = pieces[n]
            if q == nil or #run > 6 then run = nil; break end
            if q[1] == "S" and abs(q[2] - h) < 0.5 then break end
            if not gapCell(n, h) then run = nil; break end
            run[#run + 1] = n
          end
          if run then
            local all = true
            for _, cl in ipairs(run) do
              local below = pieces[K(KX(cl), y + 1)]
              if not (below ~= nil and below[2] < h - 0.5) then all = false end
            end
            if all then
              for _, cl in ipairs(run) do pieces[cl] = { "S", h } end
              c.cheeks[K(x - 1, y)] = true
              c.cheeks[K(KX(run[#run]) + 1, y)] = true
            end
          end
        end
      end
    end
    -- a waterfall falls a level a row
    for _, cell in ipairs(sortedXY(c.falls)) do
      local x, y = KX(cell), KY(cell)
      if not c.falls[K(x, y - 1)] then
        local run = { cell }
        while c.falls[K(x, KY(run[#run]) + 1)] do run[#run + 1] = K(x, KY(run[#run]) + 1) end
        local above, below = K(x, y - 1), K(x, KY(run[#run]) + 1)
        if flat[above] ~= nil and flat[below] ~= nil then
          local top, foot = flat[above], flat[below]
          if abs(top - foot - #run * LEVEL) <= 0.5 then
            for k, f in ipairs(run) do pieces[f] = { "S", top - (k - 1) * LEVEL } end
            for _, side in ipairs({ -1, 1 }) do
              local beside = {}
              for _, f in ipairs(run) do beside[#beside + 1] = K(KX(f) + side, KY(f)) end
              local ok = true
              for _, b in ipairs(beside) do
                if not (pieces[b] and c.kind[b] == ROCK and not c.keep[b] and not c.band[b]) then ok = false end
              end
              if ok then
                for k, b in ipairs(beside) do pieces[b] = { "S", top - (k - 1) * LEVEL } end
              end
            end
          end
        end
      end
    end
    -- the shoulders of a mound
    for _ = 1, 2 do
      -- (list(pieces.items()): the dict's order, c.kind's)
      for _, cell in ipairs(c.kindOrder) do
        local p = pieces[cell]
        if c.kind[cell] == ROCK and (p[1] == "F" or p[1] == "T") and not c.keep[cell] then
          local x, y = KX(cell), KY(cell)
          local south = pieces[K(x, y + 1)]
          for _, n in ipairs({ K(x - 1, y), K(x + 1, y) }) do
            local q = pieces[n]
            if q ~= nil and (q[1] == "F" or q[1] == "T") and q[2] > p[2]
                and (c.kind[n] == TOP or c.kind[n] == ROCK) and south ~= nil and south[2] >= q[2] then
              pieces[cell] = { KX(n) > x and "W" or "E", q[2] }
              break
            end
          end
        end
      end
    end
    -- the flanks of a mound
    for _, cell in ipairs(c.kindOrder) do
      local p = pieces[cell]
      if c.kind[cell] == ROCK and not c.keep[cell] and not c.band[cell] then
        local x, y = KX(cell), KY(cell)
        for _, io in ipairs({ { K(x + 1, y), K(x - 1, y), "W" }, { K(x - 1, y), K(x + 1, y), "E" } }) do
          local inner, outer, kind = io[1], io[2], io[3]
          local q = pieces[inner]
          if q ~= nil and c.kind[inner] == ROCK and (q[1] == "S" or q[1] == "W" or q[1] == "E" or IS_CORNER[q[1]])
              and q[2] > p[2] and flat[outer] ~= nil and c.kind[outer] ~= ROCK then
            local drop = q[2] - flat[outer]
            if abs(drop - LEVEL) < 0.5 then pieces[cell] = { kind, q[2] }
            elseif abs(drop - 2 * LEVEL) < 0.5 then pieces[cell] = { kind .. "2", q[2] } end
            break
          end
        end
      end
    end
    local measured = {}
    for _, r in ipairs(runs) do if r[1] == "S" then measured[r[2] .. "|" .. r[4]] = true end end
    for _ = 1, 3 do
      local before = {}
      for cell, p in pairs(pieces) do before[cell] = p end
      trace("before_staircases", pieces)
      T.staircases(c, pieces, flat, kept)
      trace("after_staircases", pieces)
      T.levelBands(c, pieces, flat, kept, measured)
      trace("after_level_bands", pieces)
      local same = true
      for cell, p in pairs(pieces) do if not pieceEq(before[cell], p) then same = false; break end end
      if same then break end
    end
    tick()
    T.unstand(c, pieces, flat, kept)
    trace("after_unstand", pieces)
    T.faceEnds(c, pieces, flat, kept)
    trace("after_face_ends", pieces)
    T.hiddenDrops(c, pieces, flat, kept)
    trace("after_hidden_drops", pieces)
    T.hiddenFaceEnds(c, pieces, flat, kept)
    trace("after_hidden_face_ends", pieces)
    T.rimBacks(c, pieces, flat, kept)
    trace("after_rim_backs", pieces)
    T.roughFields(c, pieces, flat, kept)
    trace("after_rough_fields", pieces)
    if meets ~= nil then T.seamEdges(c, pieces, ref, meets, kept); trace("after_seam_edges", pieces) end
    trace("final", pieces)
    tick()
    return { cells = c, comp = comp, level = lvl, U = U, flat = flat, kept = kept, pieces = pieces,
             dropped = dropped, keep_shift = keepShift, kept_cuts = keptCuts, kept_berm = keptBerm,
             kept_cuts_berm = keptCutsBerm, landings = landings, ledges = ledges, members = members, ref = ref }
  end

  -- ── hand marks ───────────────────────────────────────────────────────────────

  local MARK_PIECES = { F = true, S = true, W = true, E = true, W2 = true, E2 = true, cSE = true, cSW = true, vSE = true, vSW = true }

  function T.zeroOf(auto)
    local c = auto.cells
    local tops = counter()
    for _, cell in ipairs(c.kindOrder) do
      local p = auto.pieces[cell]
      if p[1] == "F" and c.kind[cell] == GROUND then tops.add(LEVEL * pyround(p[2] / LEVEL)) end
    end
    if #tops.order == 0 then return 0 end
    return tops.most()
  end

  local function fixesLayouts()
    local fixes = S.opt.fixes
    return fixes and fixes.layouts or {}
  end
  local function keyOrder(tbl)
    local order = S.opt.fixesOrder
    local o = order and order[tbl]
    if o then return o end
    local ks = keysOf(tbl)
    table.sort(ks)
    return ks
  end

  function T.loadMarks(c, zero)
    local layouts = fixesLayouts()
    local out, order = {}, {}
    for _, mem in ipairs(c.members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local spec = layouts[lid]
      local own = spec and spec.terraces
      if not own or next(own) == nil then
        local tw = layouts[TWIN_OF[lid] or ""]
        own = tw and tw.terraces or {}
      end
      for _, key in ipairs(keyOrder(own)) do
        local m = own[key]
        local x, y = key:match("^(%-?%d+),(%-?%d+)$")
        x, y = tonumber(x), tonumber(y)
        local lv, piece = m.level, m.piece
        if isnil(lv) then lv = nil end
        if isnil(piece) then piece = nil end
        if piece ~= nil and not MARK_PIECES[splitKind(piece)] then error(lid .. " " .. key .. ": no piece " .. piece) end
        local cell = K(x + ox, y + oy)
        local e = { level = lv ~= nil and zero + LEVEL * lv or nil, piece = piece }
        if not isnil(m.foot) then e.foot = zero + LEVEL * m.foot end
        if m.under == "rock" or m.under == "open" then e.under = m.under end
        if out[cell] == nil then order[#order + 1] = cell end
        out[cell] = e
      end
    end
    return out, order
  end

  function T.loadBehind(c)
    local layouts = fixesLayouts()
    local out = {}
    for _, mem in ipairs(c.members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local spec = layouts[lid]
      local own = spec and spec.behind
      if not own or next(own) == nil then
        local tw = layouts[TWIN_OF[lid] or ""]
        own = tw and tw.behind or {}
      end
      for key, m in pairs(own) do
        local x, y = key:match("^(%-?%d+),(%-?%d+)$")
        out[K(tonumber(x) + ox, tonumber(y) + oy)] = floor(m)
      end
    end
    return out
  end

  function T.markedLayouts()
    local layouts = fixesLayouts()
    local names = keysOf(layouts)
    table.sort(names)
    local marked, mset = {}, {}
    for _, lid in ipairs(names) do
      local t = layouts[lid].terraces
      if t and next(t) ~= nil then marked[#marked + 1] = lid; mset[lid] = true end
    end
    local twins = {}
    for _, tw in ipairs(T.TWINS) do
      if mset[tw[2]] and not mset[tw[1]] then twins[#twins + 1] = tw[1] end
    end
    table.sort(twins)
    for _, t in ipairs(twins) do marked[#marked + 1] = t end
    return marked
  end

  -- round(x, 2) as Python rounds it, then %g
  local function named(kind, drop)
    if abs(drop - LEVEL) < 0.5 then return kind end
    if (kind == "W" or kind == "E") and abs(drop - 2 * LEVEL) < 0.5 then return kind .. "2" end
    local r = tonumber(string.format("%.2f", drop))
    return kind .. ":" .. T.fmtG(r)
  end

  local function autoPiece(lvl, cell)
    local x, y = KX(cell), KY(cell)
    local t = lvl[cell]
    local function fallOf(...)
      local hs
      for _, n in ipairs({ ... }) do
        if lvl[n] ~= nil then hs = hs == nil and lvl[n] or min(hs, lvl[n]) end
      end
      if hs == nil then return 0.0 end
      return max(0.0, t - hs)
    end
    local w, e, s = K(x - 1, y), K(x + 1, y), K(x, y + 1)
    local drops = { NW = fallOf(w), NE = fallOf(e), SW = fallOf(w, s, K(x - 1, y + 1)), SE = fallOf(e, s, K(x + 1, y + 1)) }
    local low, nlow = {}, 0
    for _, k in ipairs({ "NW", "NE", "SW", "SE" }) do
      if drops[k] > 0.5 then low[k] = true; nlow = nlow + 1 end
    end
    if nlow == 0 then return { "F", t } end
    local drop = 0
    for k in pairs(low) do drop = max(drop, drops[k]) end
    local kind
    if nlow == 2 and low.SW and low.SE then kind = "S"
    elseif nlow == 2 and low.NW and low.SW then kind = "W"
    elseif nlow == 2 and low.NE and low.SE then kind = "E"
    elseif nlow == 3 and low.NW and low.SW and low.SE then kind = "cSW"
    elseif nlow == 3 and low.NE and low.SE and low.SW then kind = "cSE"
    elseif nlow == 1 and low.SW then kind = "vSW"
    elseif nlow == 1 and low.SE then kind = "vSE" end
    if kind == nil then
      if fallOf(s) <= 0.5 then return { "F", t } end
      kind, drop = "S", fallOf(s)
    end
    return { named(kind, drop), t }
  end

  local function markRuns(c, auto, lvl)
    local out = {}
    local function share(run, top, foot, kind)
      local k, d = #run, top - foot
      local each = d < k * LEVEL and d / k or LEVEL
      for i, cell in ipairs(run) do
        local fall = (i - 1 < k - 1) and each or (d - each * (k - 1))
        out[cell] = { named(kind, fall), top - each * (i - 1) }
        lvl[cell] = top - each * (i - 1)
      end
    end
    local function runFrom(cell, step, ok)
      local run = { cell }
      while true do
        local n = K(KX(run[#run]) + step[1], KY(run[#run]) + step[2])
        if not auto[n] or not ok(n) or abs(lvl[n] - lvl[cell]) > 0.5 then return run end
        run[#run + 1] = n
      end
    end
    local seen = {}
    for _, cell in ipairs(sortedYX(auto)) do
      if not seen[cell] and not c.band[cell] and T.isFace(c, cell) then
        local x, y = KX(cell), KY(cell)
        local up = K(x, y - 1)
        if not (auto[up] and T.isFace(c, up) and abs(lvl[up] - lvl[cell]) < 0.5) then
          local run = runFrom(cell, { 0, 1 }, function(n) return not c.band[n] and T.isFace(c, n) end)
          for _, r in ipairs(run) do seen[r] = true end
          local foot = K(x, KY(run[#run]) + 1)
          if #run > 1 and lvl[foot] ~= nil and lvl[foot] < lvl[cell] - 0.5 then share(run, lvl[cell], lvl[foot], "S") end
        end
      end
    end
    for _, cell in ipairs(sortedXY(auto)) do
      local side = c.band[cell]
      if not seen[cell] and side ~= nil then
        local down = side == "W" and { -1, 0 } or { 1, 0 }
        local x, y = KX(cell), KY(cell)
        local prev = K(x - down[1], y)
        if not (auto[prev] and c.band[prev] == side and abs(lvl[prev] - lvl[cell]) < 0.5) then
          local run = runFrom(cell, down, function(n) return c.band[n] == side end)
          for _, r in ipairs(run) do seen[r] = true end
          local foot = K(KX(run[#run]) + down[1], y)
          if #run > 1 and lvl[foot] ~= nil and lvl[foot] < lvl[cell] - 0.5 then share(run, lvl[cell], lvl[foot], side) end
        end
      end
    end
    return out
  end

  local function meetP(pieces, a, b)
    local ga, gb = pg(pieces[a]), pg(pieces[b])
    local dx, dy = KX(b) - KX(a), KY(b) - KY(a)
    if dx ~= 0 and dy ~= 0 then
      return abs(ga[dy > 0 and N or 0][dx > 0 and N or 0] - gb[dy > 0 and 0 or N][dx > 0 and 0 or N]) < 0.5
    end
    local s1, s2
    if dx == 1 then s1, s2 = "E", "W" elseif dx == -1 then s1, s2 = "W", "E"
    elseif dy == 1 then s1, s2 = "S", "N" else s1, s2 = "N", "S" end
    local ea, eb = edge(ga, s1), edge(gb, s2)
    for i = 0, N do if abs(ea[i] - eb[i]) >= 0.5 then return false end end
    return true
  end

  function T.applyMarks(c, pieces, flat, kept, marks, markOrder)
    local use, useOrder = {}, {}
    for _, cell in ipairs(markOrder) do
      if pieces[cell] ~= nil and not kept[cell] and not c.keep[cell] then
        use[cell] = marks[cell]
        useOrder[#useOrder + 1] = cell
      end
    end
    if #useOrder == 0 then return {} end
    local lvl = {}
    for cell, p in pairs(pieces) do lvl[cell] = p[2] end
    for _, cell in ipairs(useOrder) do
      local m = use[cell]
      if m.level ~= nil then lvl[cell] = m.level end
    end
    local auto = {}
    for _, cell in ipairs(useOrder) do
      local m = use[cell]
      if m.piece == nil or m.piece == "auto" then auto[cell] = true end
    end
    local runs = markRuns(c, auto, lvl)
    for _, cell in ipairs(useOrder) do
      local m = use[cell]
      if runs[cell] then pieces[cell] = runs[cell]
      elseif auto[cell] then pieces[cell] = autoPiece(lvl, cell)
      else pieces[cell] = { m.piece, lvl[cell] } end
      if c.bridges[cell] then pieces[cell] = { "F", lvl[cell] } end
      if pieces[cell][1] == "F" then flat[cell] = lvl[cell] end
    end
    local sortedMarks = keysOf(use)
    sortXY(sortedMarks)
    for _, cell in ipairs(sortedMarks) do
      local x, y = KX(cell), KY(cell)
      for j = -1, 1 do
        for i = -1, 1 do
          if i ~= 0 or j ~= 0 then
            local n = K(x + i, y + j)
            if not (use[n] or pieces[n] == nil or kept[n] or c.keep[n] or meetP(pieces, cell, n)) and not c:water(n) then
              pieces[n] = autoPiece(lvl, n)
              if pieces[n][1] == "F" then flat[n] = lvl[n] end
            end
          end
        end
      end
    end
    return use
  end

  function T.finish(auto, marks, markOrder, behind)
    local c, kept = auto.cells, auto.kept
    local pieces, flat = {}, {}
    for k, v in pairs(auto.pieces) do pieces[k] = v end
    for k, v in pairs(auto.flat) do flat[k] = v end
    if marks == nil then marks, markOrder = T.loadMarks(c, T.zeroOf(auto)) end
    local rock, anyRock = {}, false
    for cell, m in pairs(marks) do
      if c.jumps[cell] and m.piece ~= nil and m.piece ~= "auto" then rock[cell] = true; anyRock = true end
    end
    if anyRock then
      c = c:copy()
      local jumps, keep, ledges = {}, {}, {}
      for k, v in pairs(c.jumps) do if not rock[k] then jumps[k] = v end end
      for k, v in pairs(c.keep) do if not rock[k] then keep[k] = v end end
      for k, v in pairs(c.ledges) do if not rock[k] then ledges[k] = v end end
      c.jumps, c.keep, c.ledges = jumps, keep, ledges
      local k2 = {}
      for k, v in pairs(kept) do if not rock[k] then k2[k] = v end end
      kept = k2
    end
    local marked = T.applyMarks(c, pieces, flat, kept, marks, markOrder)
    local cuts = {}
    kept = {}
    for k, v in pairs(auto.kept_berm or auto.kept) do kept[k] = v end
    for k, v in pairs(auto.kept_cuts_berm or auto.kept_cuts or {}) do cuts[k] = v end
    for cell in pairs(rock) do kept[cell] = nil; cuts[cell] = nil end
    local ledgeMarks = {}
    for cell, m in pairs(marks) do if c.jumps[cell] then ledgeMarks[cell] = m end end
    local ledges = T.layLedges(c, pieces, flat, kept, cuts, ledgeMarks)
    local soilMarks = {}
    for cell, m in pairs(marks) do if c.keep[cell] and not c.jumps[cell] then soilMarks[cell] = m end end
    T.laySoil(c, pieces, kept, cuts, soilMarks, marked)
    local under = {}
    for cell, m in pairs(marks) do if m.under and c.bridges[cell] then under[cell] = m.under end end
    for cell in pairs(ledgeMarks) do marked[cell] = true end
    for cell in pairs(soilMarks) do marked[cell] = true end
    for cell in pairs(under) do marked[cell] = true end
    local grids = {}
    for cell, p in pairs(pieces) do grids[cell] = pg(p) end
    for cell, g in pairs(kept) do grids[cell] = g end
    T.facesAtLandings(c, pieces, grids, ledges.steps)
    T.behindTrees(c, flat, grids, pieces, marked)
    if behind == nil then behind = T.loadBehind(c) end
    local sol = {}
    for k, v in pairs(auto) do sol[k] = v end
    sol.cells, sol.pieces, sol.flat, sol.grids, sol.marked, sol.kept = c, pieces, flat, grids, marked, kept
    sol.kept_cuts, sol.ledges, sol.under, sol.behind = cuts, ledges, under, behind
    return sol
  end

  function T.solve(lid, reference)
    return T.finish(T.solveAuto(lid, reference), nil)
  end
end
