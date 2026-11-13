-- The world's levels (Battle Scene: Overworld; src/scene/relief_solve.lua's part): every drawn
-- group's terraces solved against each other in blocks, then the blocks and the maps that are not
-- drawn placed so that the ground either side of every seam meets; where the world does not close
-- up, the seams that disagree most are given up. Emerald 3DS's gen_voxel_relief.py world_levels,
-- map_links, _seam_cells, _gauss_seidel, _robust, _give_up_seams, _blocks (by Zallax and
-- contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE), with
-- Python's dict orders and float sums kept (the levels are least-squares answers: a float summed
-- in another order is another answer).

local floor, abs, max = math.floor, math.abs, math.max

return function(S)
  local Art, Solve = S.Art, S.Solve
  local C = Solve.C
  local LEVEL, FOOTPRINT = C.LEVEL, C.FOOTPRINT
  local SEAM_WEIGHT, STEP_SEAM_WEIGHT = 16, 1
  local HARD_WEIGHT, LOOSE_WEIGHT = 1e6, 0.01
  local GROUND_SPREAD, MASSIF = 0.05, 160
  local WORLD_ROOT = "LAYOUT_LITTLEROOT_TOWN"
  local DRAWN_EXCLUDED = { route122 = true, ever_grande_city = true }
  local COUNTED_GROUPS = { route111 = true, route111_no_mirage_tower = true }
  local STEP_SEAMS = { ["LAYOUT_ROUTE107|LAYOUT_ROUTE108"] = true, ["LAYOUT_ROUTE108|LAYOUT_ROUTE107"] = true }
  local tick = S.tick

  -- an ordered map of pairs: { order = { key... }, at = { [key] = entry } }, key a * 1e6 + b
  local function omap() return { order = {}, at = {} } end
  local function okey(a, b) return a * 1000000 + b end
  local function oset(m, a, b, e)
    local k = okey(a, b)
    if m.at[k] == nil then m.order[#m.order + 1] = k end
    e.a, e.b = a, b
    m.at[k] = e
  end
  local function odel(m, k)
    m.at[k] = nil
    for i, v in ipairs(m.order) do
      if v == k then
        table.remove(m.order, i)
        return
      end
    end
  end

  local function median(list)
    local v = {}
    for i, x in ipairs(list) do v[i] = x end
    table.sort(v)
    return v[floor(#v / 2) + 1]
  end

  --- map_links(): { a, b, direction, offset } of every connection between two outdoor layouts,
  --- sorted; a layout a script swaps in has its map's
  local function mapLinks()
    local found, seen = {}, {}
    local function add(a, b, d, off)
      local k = a .. "|" .. b .. "|" .. d .. "|" .. off
      if not seen[k] then
        seen[k] = true
        found[#found + 1] = { a, b, d, off }
      end
    end
    for _, m in ipairs(S.input.maps) do
      local A = S.input.layouts[m.layout]
      local a = A and A.name
      if a and S.outdoor[a] then
        for _, c in ipairs(m.connections) do
          local B = S.input.layouts[c.layout]
          local b = B and B.name
          if b and S.outdoor[b] and b ~= a and c.direction then add(a, b, c.direction, c.offset) end
        end
      end
    end
    local alts = {}
    for _, L in ipairs(S.ordered) do if L.alternateOf then alts[#alts + 1] = L end end
    for _, L in ipairs(alts) do
      local alt, base = L.name, L.alternateOf
      if S.outdoor[alt] then
        local snapshot = {}
        for i, l in ipairs(found) do snapshot[i] = l end
        for _, l in ipairs(snapshot) do
          if l[1] == base then add(alt, l[2], l[3], l[4]) end
          if l[2] == base then add(l[1], alt, l[3], l[4]) end
        end
      end
    end
    table.sort(found, function(p, q)
      for i = 1, 4 do
        if p[i] ~= q[i] then return p[i] < q[i] end
      end
      return false
    end)
    return found
  end

  local function seamCells(a, b, direction, offset)
    local A, B = S.input.byName[a], S.input.byName[b]
    local aw, ah, bw, bh = A.w, A.h, B.w, B.h
    local out = {}
    if direction == "up" or direction == "down" then
      for x = max(0, offset), math.min(aw, offset + bw) - 1 do
        out[#out + 1] = { direction == "down" and "down" or "up", x, direction == "down" and "up" or "down", x - offset }
      end
    else
      for y = max(0, offset), math.min(ah, offset + bh) - 1 do
        out[#out + 1] = { direction == "right" and "right" or "left", y, direction == "right" and "left" or "right", y - offset }
      end
    end
    return out
  end

  --- _gauss_seidel(n, pairs, fixed): least squares over h[a] - h[b] = d, `fixed` held. pairs: an
  --- ordered map of { d, w, wf (w is a Python float) }; fixed: { [node] = value }.
  local function gaussSeidel(n, prs, fixed, iterations)
    iterations = iterations or 4000
    local h = {}
    for r = 0, n - 1 do h[r] = 0.0 end
    for k, v in pairs(fixed) do h[k] = v end
    local adj = {}
    for r = 0, n - 1 do adj[r] = {} end
    for _, k in ipairs(prs.order) do
      local e = prs.at[k]
      local la, lb = adj[e.a], adj[e.b]
      la[#la + 1] = { e.b, e.d, e.w, e.wf }
      lb[#lb + 1] = { e.a, -e.d, e.w, e.wf }
    end
    local num, ws, wf = {}, {}, {}
    for _ = 1, iterations do
      local delta = 0.0
      for r = 0, n - 1 do
        local list = adj[r]
        if fixed[r] == nil and #list > 0 then
          for i, t in ipairs(list) do
            num[i] = t[3] * (h[t[1]] + t[2])
            ws[i], wf[i] = t[3], t[4]
          end
          local top = Art.fsum(num, #list)
          local bottom = Art.mixedSum(ws, wf, #list)
          local v = top / bottom
          delta = max(delta, abs(v - h[r]))
          h[r] = v
        end
      end
      if delta < 0.001 then break end
    end
    tick()
    return h
  end

  -- a list of { d, w, wf } samples: their median drop and summed weight (and whether a float)
  local function summed(v)
    local ds, ws, wf = {}, {}, {}
    for i, s in ipairs(v) do ds[i], ws[i], wf[i] = s[1], s[2], s[3] end
    local w, isF = Art.mixedSum(ws, wf, #v)
    return median(ds), w, isF
  end

  --- _robust(n, samples, fixed, hard): samples an ordered map of { list = { { d, w, wf }... } };
  --- hard: a list of { a, b } in Python's set order
  local function robust(n, samples, fixed, hard)
    local tie = omap()
    for _, p in ipairs(hard or {}) do oset(tie, p[1], p[2], { d = 0.0, w = HARD_WEIGHT, wf = true }) end
    local first = omap()
    for _, k in ipairs(tie.order) do local e = tie.at[k]; oset(first, e.a, e.b, { d = e.d, w = e.w, wf = e.wf }) end
    for _, k in ipairs(samples.order) do
      if tie.at[k] == nil then
        local e = samples.at[k]
        local d, w, wf = summed(e.list)
        oset(first, e.a, e.b, { d = d, w = w, wf = wf })
      end
    end
    local sol = gaussSeidel(n, first, fixed)
    local kept = omap()
    for _, k in ipairs(tie.order) do local e = tie.at[k]; oset(kept, e.a, e.b, { d = e.d, w = e.w, wf = e.wf }) end
    for _, k in ipairs(samples.order) do
      if tie.at[k] == nil then
        local e = samples.at[k]
        local good = {}
        for _, s in ipairs(e.list) do
          if abs(sol[e.a] - sol[e.b] - s[1]) <= 8 then good[#good + 1] = s end
        end
        if #good > 0 then
          local d, w, wf = summed(good)
          oset(kept, e.a, e.b, { d = d, w = w, wf = wf })
        end
      end
    end
    return gaussSeidel(n, kept, fixed), kept
  end

  local function giveUpSeams(n, samples, fixed)
    local prs = omap()
    for _, k in ipairs(samples.order) do
      local e = samples.at[k]
      local d, w, wf = summed(e.list)
      oset(prs, e.a, e.b, { d = d, w = w, wf = wf })
    end
    while true do
      local off = gaussSeidel(n, prs, fixed)
      local worst, err = nil, 8.0
      for _, k in ipairs(prs.order) do
        local e = prs.at[k]
        local ee = abs(off[e.a] - off[e.b] - e.d)
        if e.w >= SEAM_WEIGHT and ee > err then worst, err = k, ee end
      end
      if worst == nil then
        local whole = {}
        for r = 0, n - 1 do whole[r] = LEVEL * Art.round(off[r] / LEVEL) end
        err = 0.0
        for _, k in ipairs(prs.order) do
          local e = prs.at[k]
          local ee = abs(off[e.a] - off[e.b] - e.d)
          if e.w >= SEAM_WEIGHT and abs(whole[e.a] - whole[e.b] - e.d) > 8.0 and ee > err then worst, err = k, ee end
        end
      end
      if worst == nil then return off end
      odel(prs, worst)
    end
  end

  --- _blocks(prep, counted): (levels relative to their block's first terrace, block of each)
  local function blocks(prep, counted)
    local sizes, runs = prep.sizes, prep.runs
    local n = prep.nRegions
    local cset = {}
    for _, c in ipairs(counted or {}) do cset[okey(c[1], c[2])] = true end
    local runList = {}
    for _, k in ipairs(runs.order) do
      local e = runs.at[k]
      if not (counted and (cset[okey(e.a, e.b)] or cset[okey(e.b, e.a)])) then runList[#runList + 1] = e end
    end
    local adj = {}
    for r = 0, n - 1 do adj[r] = {} end
    for _, e in ipairs(runList) do adj[e.a][e.b] = true; adj[e.b][e.a] = true end
    for _, c in ipairs(counted or {}) do adj[c[1]][c[2]] = true; adj[c[2]][c[1]] = true end
    local block, anchors = {}, {}
    for r = 0, n - 1 do block[r] = -1 end
    local byBig = {}
    for r = 0, n - 1 do byBig[#byBig + 1] = r end
    table.sort(byBig, function(p, q)
      if sizes[p] ~= sizes[q] then return sizes[p] > sizes[q] end
      return p < q
    end)
    local nAnchors = 0
    for _, r in ipairs(byBig) do
      if block[r] < 0 and prep.big[r] then
        local k = nAnchors
        anchors[r] = 0.0
        nAnchors = nAnchors + 1
        block[r] = k
        local stack = { r }
        while #stack > 0 do
          local c = table.remove(stack)
          for o in pairs(adj[c]) do
            if block[o] < 0 then
              block[o] = k
              stack[#stack + 1] = o
            end
          end
        end
      end
    end
    local samples = omap()
    for _, e in ipairs(runList) do
      local list = {}
      for i, d in ipairs(e.v) do list[i] = { d, 1, false } end
      oset(samples, e.a, e.b, { list = list })
    end
    for _, c in ipairs(counted or {}) do
      oset(samples, c[1], c[2], { list = { { c[3], HARD_WEIGHT, true } } })
    end
    local level = robust(n, samples, anchors, prep.tiesOrdered)
    return level, block
  end
  S.blocks = blocks

  local WORLD
  function S.worldLevels()
    if WORLD then return WORLD end
    local links = mapLinks()
    local candidates = {}
    for _, g in ipairs(S.DRAWN) do
      if not DRAWN_EXCLUDED[g.name] then candidates[#candidates + 1] = g.name end
    end
    local localLv = {}
    for _, g in ipairs(candidates) do
      local prep = S.drawnPrepare(g)
      local counted = nil
      if COUNTED_GROUPS[g] and S.opt.regionTies then counted = S.opt.regionTies(g, prep) end
      local level, block = blocks(prep, counted)
      localLv[g] = { level, block, prep.nRegions }
      tick()
    end
    local function solve(groups)
      local owner = {}
      for _, g in ipairs(groups) do
        for _, lid in ipairs(S.DRAWN_BY[g].members) do
          if owner[lid] == nil then owner[lid] = g end
        end
      end
      local nodes, index = {}, {}
      local function node(key)
        local i = index[key]
        if i == nil then
          i = #nodes
          index[key] = i
          nodes[i + 1] = key
        end
        return i
      end
      local samples = omap()
      local function sample(a, b, d, w, wf)
        local k = okey(a, b)
        local e = samples.at[k]
        if not e then
          e = { list = {} }
          oset(samples, a, b, e)
        end
        e.list[#e.list + 1] = { d, w, wf }
      end
      for _, g in ipairs(groups) do
        local block = localLv[g][2]
        local main = node("b|" .. g .. "|0")
        local ks, nb = {}, 0
        for r = 0, localLv[g][3] - 1 do
          local k = block[r]
          if k ~= -1 and k ~= 0 and not ks[k] then ks[k] = true; nb = max(nb, k) end
        end
        for k = 1, nb do
          if ks[k] then sample(node("b|" .. g .. "|" .. k), main, 0.0, LOOSE_WEIGHT, true) end
        end
      end
      for _, l in ipairs(links) do
        local a, b, direction, offset = l[1], l[2], l[3], l[4]
        local ga, gb = owner[a], owner[b]
        local inside = ga ~= nil and ga == gb and S.DRAWN_BY[ga].at[b] and S.DRAWN_BY[ga].at[a]
        if not inside then
          for _, sc in ipairs(seamCells(a, b, direction, offset)) do
            local function side(g, lid, edge, i)
              if g == nil then return { node("f|" .. lid), 0.0 } end
              local r = S.PREP[g].edges[lid .. "|" .. edge][i]
              if r == nil then return nil end
              local level, block = localLv[g][1], localLv[g][2]
              return { node("b|" .. g .. "|" .. block[r]), level[r] }
            end
            local sa = side(ga, a, sc[1], sc[2])
            local sb = side(gb, b, sc[3], sc[4])
            if sa and sb then
              local w = (STEP_SEAMS[a .. "|" .. b] or STEP_SEAMS[b .. "|" .. a]) and STEP_SEAM_WEIGHT or SEAM_WEIGHT
              sample(sa[1], sb[1], sb[2] - sa[2], w, false)
            end
          end
        end
      end
      local n = #nodes
      local fixed = {}
      local root = index["f|" .. WORLD_ROOT]
      local comp = {}
      for i = 0, n - 1 do comp[i] = -1 end
      local adj = {}
      for i = 0, n - 1 do adj[i] = {} end
      for _, k in ipairs(samples.order) do
        local e = samples.at[k]
        adj[e.a][e.b] = true
        adj[e.b][e.a] = true
      end
      local order = {}
      if root ~= nil then order[1] = root end
      for i = 0, n - 1 do order[#order + 1] = i end
      for _, start in ipairs(order) do
        if comp[start] < 0 then
          comp[start] = start
          fixed[start] = 0.0
          local stack = { start }
          while #stack > 0 do
            local c = table.remove(stack)
            for o in pairs(adj[c]) do
              if comp[o] < 0 then
                comp[o] = start
                stack[#stack + 1] = o
              end
            end
          end
        end
      end
      local off = giveUpSeams(n, samples, fixed)
      local regions = {}
      for _, g in ipairs(groups) do
        local level, block, nr = localLv[g][1], localLv[g][2], localLv[g][3]
        local out = {}
        for r = 0, nr - 1 do
          local key = "b|" .. g .. "|" .. block[r]
          if block[r] >= 0 and index[key] ~= nil then
            out[r] = LEVEL * Art.round((off[index[key]] + level[r]) / LEVEL)
          else
            out[r] = LEVEL * Art.round(off[index["b|" .. g .. "|0"]] / LEVEL)
          end
        end
        regions[g] = out
      end
      local base = {}
      for i = 0, n - 1 do
        local key = nodes[i + 1]
        if key:sub(1, 2) == "f|" then base[key:sub(3)] = LEVEL * Art.round(off[i] / LEVEL) end
      end
      return regions, base
    end
    local function spread(g, regions)
      local prep = S.PREP[g]
      local got = Solve.counter()
      for cy = 0, prep.CH - 1 do
        for cx = 0, prep.CW - 1 do
          local st = prep.stats[cy][cx]
          if st ~= nil then
            local n, _, ground, counts = st[1], st[2], st[3], st[4]
            if ground >= FOOTPRINT * n and #counts.order > 0 then
              local best = Solve.mostCommon(counts.n, counts.order)
              got.add(regions[g][best])
            end
          end
        end
      end
      if #got.order == 0 then return 0.0 end
      local mode = got.most()
      local far, total = 0, 0
      for _, k in ipairs(got.order) do
        total = total + got.n[k]
        if abs(k - mode) > MASSIF then far = far + got.n[k] end
      end
      return far / total
    end
    local groups = {}
    for i, g in ipairs(candidates) do groups[i] = g end
    local regions, base
    while true do
      regions, base = solve(groups)
      local bad = {}
      for _, g in ipairs(groups) do
        S.QUALITY[g] = spread(g, regions)
        if S.QUALITY[g] > GROUND_SPREAD then bad[g] = true end
      end
      if not next(bad) then break end
      local kept = {}
      for _, g in ipairs(groups) do if not bad[g] then kept[#kept + 1] = g end end
      groups = kept
    end
    WORLD = { regions = regions, base = base }
    return WORLD
  end
end
