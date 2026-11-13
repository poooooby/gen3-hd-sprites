-- The relief's last passes (Battle Scene: Overworld): what Emerald 3DS's generator does to its
-- relief after the terraces, over the model src/scene/relief.lua decodes and encodes:
--
--   * sea ramps (gen_voxel_relief.sea_ramps): the level a step seam gives up, laid over a whole
--     map of open sea as a slope;
--   * cut feet (cut_feet): a cut tile's foot raised to the ground beside it where it sank further;
--   * the hand marks (voxel_relief_fixes.apply, its assets/voxel/relief_fixes.json): bases,
--     belts, edge fills and cells set by hand;
--   * the seam eases pack() writes (seam_eases).
--
-- Adapted from Emerald 3DS (3ds_port/scripts/gen_voxel_relief.py, voxel_relief_fixes.py; by
-- Zallax and contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see
-- LICENSE). Changes: written in Lua; the maps come in through `world` instead of pret's files.
--
-- Plain Lua. world = {
--   index(name) -> layout id (the cartridge's; LAYOUT_X names), or nil
--   size(name) -> w, h
--   links = { { a, b, direction ("up", "down", "left", "right"), offset } }, sorted as Python sorts
--           the tuples (map_links)
--   metatile(name, x, y), tilesets(name) -> primary, secondary (Emerald 3DS's names,
--   "gTileset_General"), isWater(name, metatile)
-- }

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local Post = {}

local SIDE, PER_CELL = 5, 4
Post.CUT_SINK = 2
Post.SEA_RAMPS = { "LAYOUT_ROUTE108" }
-- layouts that are one map drawn twice: the second takes the first's marks where it has none
Post.TWINS = { { "LAYOUT_ROUTE111_NO_MIRAGE_TOWER", "LAYOUT_ROUTE111" } }
local DRAWN, UNIT2 = 0x8000, 0x4000
local NO_VARIANT, NONE16, NO_FACE = 0xFFFF, 0xFFFF, 0xFFFE
local EDGES = { W = 1, E = 2, N = 4, S = 8 }
local EDGE_TOP, EDGE_WATER_SHIFT = 2, 4

-- ── JSON, its objects' key order kept ────────────────────────────────────────

--- Decode JSON text: value, order (order[object] = its keys as written). tick (optional) is
--- called every few thousand values.
function Post.json(text, tick)
  local order = setmetatable({}, { __mode = "k" })
  local pos = 1
  local nv = 0
  local function ws()
    pos = text:find("[^ \t\r\n]", pos) or #text + 1
  end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = text:sub(i, i)
      if c == '"' then break end
      if c == "\\" then
        local e = text:sub(i + 1, i + 1)
        if e == "u" then
          local code = tonumber(text:sub(i + 2, i + 5), 16)
          out[#out + 1] = code < 128 and string.char(code) or "?"
          i = i + 6
        else
          out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e
          i = i + 2
        end
      else
        local j = text:find('["\\]', i)
        out[#out + 1] = text:sub(i, j - 1)
        i = j
      end
    end
    pos = i + 1
    return table.concat(out)
  end
  function value()
    if tick then
      nv = nv + 1
      if nv % 4096 == 0 then tick() end
    end
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj, keys = {}, {}
      pos = pos + 1
      ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1; order[obj] = keys; return obj end
      while true do
        ws()
        local k = str()
        ws()
        pos = pos + 1          -- ':'
        obj[k] = value()
        keys[#keys + 1] = k
        ws()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then break end
      end
      order[obj] = keys
      return obj
    elseif c == "[" then
      local arr = {}
      pos = pos + 1
      ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value()
        ws()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then break end
      end
      return arr
    elseif c == '"' then
      return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return Post.NULL
    end
    local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    pos = pos + #num
    return tonumber(num)
  end
  return value(), order
end
Post.NULL = setmetatable({}, { __tostring = function() return "null" end })

-- ── seams ────────────────────────────────────────────────────────────────────

--- The cells of a seam: { { edge of a, index along it, edge of b, index along it } }.
function Post.seamCells(world, a, b, direction, offset)
  local aw, ah = world.size(a)
  local bw, bh = world.size(b)
  local out = {}
  if direction == "up" or direction == "down" then
    for x = max(0, offset), min(aw, offset + bw) - 1 do
      out[#out + 1] = { direction == "down" and "down" or "up", x, direction == "down" and "up" or "down", x - offset }
    end
  else
    for y = max(0, offset), min(ah, offset + bh) - 1 do
      out[#out + 1] = { direction == "right" and "right" or "left", y, direction == "right" and "left" or "right",
                        y - offset }
    end
  end
  return out
end

local EDGE_POINTS = { left = {}, right = {}, up = {}, down = {} }
for j = 0, SIDE - 1 do
  EDGE_POINTS.left[#EDGE_POINTS.left + 1] = j * SIDE
  EDGE_POINTS.right[#EDGE_POINTS.right + 1] = j * SIDE + SIDE - 1
  EDGE_POINTS.up[#EDGE_POINTS.up + 1] = j
  EDGE_POINTS.down[#EDGE_POINTS.down + 1] = (SIDE - 1) * SIDE + j
end

--- SEA_RAMPS over a model, in place: each map's sea leans from its west (north) neighbour's level
--- at their seam to its east (south) one's, every lattice point by its distance across the map.
--- Returns the maps changed.
function Post.seaRamps(M, world)
  local function edgeCell(name, edge, i)
    local w, h = world.size(name)
    if edge == "down" then return i, h - 1 elseif edge == "up" then return i, 0
    elseif edge == "right" then return w - 1, i end
    return 0, i
  end
  -- the commonest height of lid's neighbour `direction` along their seam (first counted on ties)
  local function levelAt(lid, direction)
    local count, seen = {}, {}
    for _, l in ipairs(world.links) do
      local a, b, d, off = l[1], l[2], l[3], l[4]
      if a == lid and d == direction then
        local t = M.layouts[world.index(b)]
        local base = t and t.base or 0
        for _, sc in ipairs(Post.seamCells(world, a, b, d, off)) do
          local eb, ib = sc[3], sc[4]
          local g
          if t then
            local x, y = edgeCell(b, eb, ib)
            g = t.cells[y * t.w + x]
          end
          for _, k in ipairs(EDGE_POINTS[eb]) do
            local v = base + (g and g[k] or 0)
            if not count[v] then count[v] = 0; seen[#seen + 1] = v end
            count[v] = count[v] + 1
          end
        end
      end
    end
    local best
    for _, v in ipairs(seen) do if not best or count[v] > count[best] then best = v end end
    return best
  end
  local changed = {}
  local names = {}
  for _, n in ipairs(Post.SEA_RAMPS) do names[#names + 1] = n end
  table.sort(names)
  for _, lid in ipairs(names) do
    local index = world.index(lid)
    local w, h = world.size(lid)
    local start, stop, lo, hi, across
    for _, way in ipairs({ { "left", "right", true }, { "up", "down", false } }) do
      local s0, s1 = levelAt(lid, way[1]), levelAt(lid, way[2])
      if s0 ~= nil and s1 ~= nil and s0 ~= s1 then
        start, stop, lo, hi, across = s0, s1, way[1], way[2], way[3]
        break
      end
    end
    if index and start then
      local t = M.layouts[index]
      if not t then
        t = { w = w, h = h, flags = 0, base = 0, belt = 0, ease = 0, cells = {} }
        M.layouts[index] = t
      end
      if (t.flags or 0) % 0x10000 >= UNIT2 then error(lid .. ": a sea ramp over a drawn map's relief") end
      if next(t.cells) then error(lid .. ": a sea ramp over a map with relief of its own") end
      local span = across and w or h
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local g, any = {}, false
          for j = 0, SIDE - 1 do
            for i = 0, SIDE - 1 do
              local f = (across and (x + i / PER_CELL) or (y + j / PER_CELL)) / span
              local v = start + (stop - start) * f - t.base
              g[j * SIDE + i] = floor(v + 0.5)
              if g[j * SIDE + i] ~= 0 then any = true end
            end
          end
          if any then t.cells[y * t.w + x] = g end
        end
      end
      changed[#changed + 1] = lid
    end
  end
  return changed
end

--- Every cut tile's foot at most CUT_SINK under the lowest edge point of the cells beside it that
--- are no cut tile themselves (the one north always counts), in place. Returns how many it raised.
function Post.cutFeet(M)
  local facing = {
    { 0, -1, EDGE_POINTS.down }, { 0, 1, EDGE_POINTS.up }, { -1, 0, EDGE_POINTS.right }, { 1, 0, EDGE_POINTS.left },
  }
  local raised = 0
  for key, rec in pairs(M.cuts) do
    local lay, x, y = floor(key / 65536), floor(key / 256) % 256, key % 256
    local t = M.layouts[lay]
    if rec[1] ~= NO_VARIANT and t then
      local low
      for _, f in ipairs(facing) do
        local nx, ny = x + f[1], y + f[2]
        if nx >= 0 and nx < t.w and ny >= 0 and ny < t.h then
          local other = M.cuts[lay * 65536 + nx * 256 + ny]
          if not (other and other[1] ~= NO_VARIANT and f[2] >= 0) then
            local g = t.cells[ny * t.w + nx]
            local v = 0
            if g then
              v = math.huge
              for _, k in ipairs(f[3]) do v = min(v, g[k]) end
            end
            low = low and min(low, v) or v
          end
        end
      end
      if low and rec[2] < low - Post.CUT_SINK then
        rec[2] = low
        raised = raised + 1
      end
    end
  end
  return raised
end

--- { [layout id] = ease, 8 px units }: the commonest shortfall of the seams where the heights
--- meet, under each map's south edge (none under 8 px: a point stands as far south as it is high
--- in the world, so this finds none).
function Post.seamEases(M, world)
  local tally, order = {}, {}
  for _, l in ipairs(world.links) do
    local a, b, d, off = l[1], l[2], l[3], l[4]
    if d == "down" then
      local ia, ib = world.index(a), world.index(b)
      local ta = ia and M.layouts[ia]
      if ta then
        local tb = ib and M.layouts[ib]
        local aw, ah = world.size(a)
        local bw = world.size(b)
        for x = max(0, off), min(aw, off + bw) - 1 do
          local ga = ta.cells[(ah - 1) * ta.w + x]
          local gb = tb and tb.cells[x - off] or nil
          local ha, hb = ga and ga[22] or 0, gb and gb[2] or 0
          local tbBase = tb and tb.base or 0
          if abs(ta.base + ha - (tbBase + hb)) <= 1 then
            local gap = (tbBase + hb) - (ta.base + ha)
            local c = tally[ia]
            if not c then c = { n = {}, seen = {} }; tally[ia] = c; order[#order + 1] = ia end
            if not c.n[gap] then c.n[gap] = 0; c.seen[#c.seen + 1] = gap end
            c.n[gap] = c.n[gap] + 1
          end
        end
      end
    end
  end
  local out = {}
  for _, ia in ipairs(order) do
    local c = tally[ia]
    local gap, n, total = nil, 0, 0
    for _, g in ipairs(c.seen) do
      total = total + c.n[g]
      if c.n[g] > n then gap, n = g, c.n[g] end
    end
    if gap >= 8 and 2 * n >= total then out[ia] = min(15, floor(gap / 8)) end
  end
  return out
end

-- ── the hand marks ───────────────────────────────────────────────────────────

-- a cell's level when the marks give none: the top of its lattice, to the terrace
local function levelOf(g)
  if not g then return 0 end
  local top = -math.huge
  for k = 0, 24 do top = max(top, g[k]) end
  local q = top / 16
  local f = floor(q)
  local d = q - f
  local r = d > 0.5 and f + 1 or d < 0.5 and f or (f % 2 == 0 and f or f + 1)
  return r * 16
end

local function isNull(v) return v == nil or v == Post.NULL end

local function edgeRows(world, name, spec, index)
  local rows = {}
  for _, e in ipairs(spec.edges or {}) do
    local side = EDGES[tostring(e.edge or ""):upper()]
    if not side or isNull(e.metatile) then error(name .. ": an edge fill needs an edge (W E N S) and a metatile") end
    local first, last = e.first, e.last
    if isNull(first) then first, last = -1, -1
    elseif isNull(last) then last = first end
    local ms = type(e.metatile) == "table" and e.metatile or { e.metatile, e.metatile, e.metatile, e.metatile }
    if #ms ~= 4 then error(name .. ": an edge fill: one metatile or four") end
    local flags = isNull(e.top) and 0 or EDGE_TOP
    for q = 1, 4 do
      if world.isWater(name, ms[q]) then flags = flags + 2 ^ (EDGE_WATER_SHIFT + q - 1) end
    end
    rows[#rows + 1] = { index, side, flags, min(first, last), max(first, last), isNull(e.top) and 0 or e.top,
                        ms[1], ms[2], ms[3], ms[4] }
  end
  return rows
end

--- The hand marks (relief_fixes.json, decoded by Post.json: fixes, order) over a model, in place.
--- Returns a line per map changed.
function Post.applyFixes(M, world, fixes, order, tick)
  local pieces = fixes.pieces or {}
  local specs, names = {}, {}
  for _, name in ipairs(order[fixes.layouts] or {}) do
    specs[name] = fixes.layouts[name]
    names[#names + 1] = name
  end
  for _, tw in ipairs(Post.TWINS) do
    local twin, first = tw[1], tw[2]
    if specs[first] then
      local merged = {}
      for k, v in pairs(specs[first]) do merged[k] = v end
      for k, v in pairs(specs[twin] or {}) do merged[k] = v end
      if not specs[twin] then names[#names + 1] = twin end
      specs[twin] = merged
    end
  end
  local report = {}
  for _, name in ipairs(names) do
    local spec = specs[name]
    local index = world.index(name)
    if not index then
      report[#report + 1] = name .. ": no such layout"
    else
      local w, h = world.size(name)
      local t = M.layouts[index]
      if not t then
        t = { w = w, h = h, flags = 0, base = 0, belt = 0, ease = 0, cells = {} }
        M.layouts[index] = t
      end
      if spec.base ~= nil then t.base = spec.base end
      if spec.drawn then t.flags = (t.flags or 0) % DRAWN + DRAWN end
      if spec.edges ~= nil then
        local kept = {}
        for _, e in ipairs(M.edges) do if e[1] ~= index then kept[#kept + 1] = e end end
        for _, e in ipairs(edgeRows(world, name, spec, index)) do kept[#kept + 1] = e end
        M.edges = kept
      end
      if spec.belt ~= nil then
        local courses = floor(spec.belt / 16)
        if courses * 16 ~= spec.belt or courses < 0 or courses > 15 then error(name .. ": belt is not 0-15 levels") end
        t.belt = courses
      end
      local enabled = {}
      for _, p in ipairs(spec.pieces or {}) do
        local pid, rect = p, nil
        if type(p) == "table" then pid, rect = p.id, p.rect end
        if pieces[pid] then enabled[#enabled + 1] = { pieces[pid], rect } end
      end
      local cellsFix = spec.cells or {}
      local cellOrder = order[cellsFix] or {}
      local changed = 0
      if #enabled > 0 or #cellOrder > 0 then
        local primary, secondary = world.tilesets(name)
        -- (a tileset by its short name: "gTileset_General", "general" alike)
        local function short(n) return (tostring(n):gsub("^gTileset_", ""):gsub("_", "")):lower() end
        local function tilesetOf(m) return short(m < 512 and primary or secondary) end
        if #enabled > 0 then
          for y = 0, h - 1 do
            for x = 0, w - 1 do
              local key = x .. "," .. y
              local fx = cellsFix[key] or {}
              if not (fx.nopiece or fx.piece ~= nil) then
                local m = world.metatile(name, x, y)
                for _, e in ipairs(enabled) do
                  local pc, rect = e[1], e[2]
                  if pc.metatile == m and (pc.tileset and short(pc.tileset) or tilesetOf(m)) == tilesetOf(m)
                      and (not rect or (rect[1] <= x and x < rect[3] and rect[2] <= y and y < rect[4])) then
                    local g = t.cells[y * t.w + x]
                    local lvl = fx.level ~= nil and fx.level or levelOf(g)
                    local ng = {}
                    for k = 0, 24 do ng[k] = lvl + pc.grid[k + 1] end
                    t.cells[y * t.w + x] = ng
                    changed = changed + 1
                    break
                  end
                end
              end
            end
          end
        end
        for ci, key in ipairs(cellOrder) do
          if tick and ci % 256 == 0 then tick() end
          local fix = cellsFix[key]
          local x, y = key:match("^(%-?%d+),(%-?%d+)$")
          x, y = tonumber(x), tonumber(y)
          local ck = y * t.w + x
          if fix.remove then
            t.cells[ck] = nil
            M.cuts[index * 65536 + x * 256 + y] = nil
          else
            local g = t.cells[ck]
            local lvl = fix.level ~= nil and fix.level or levelOf(g)
            if fix.piece ~= nil and pieces[fix.piece] then
              local ng = {}
              for k = 0, 24 do ng[k] = lvl + pieces[fix.piece].grid[k + 1] end
              g = ng
            elseif fix.level ~= nil and g == nil and fix.grid == nil then
              g = {}
              for k = 0, 24 do g[k] = lvl end
            end
            if fix.grid ~= nil then
              g = {}
              for k = 0, 24 do g[k] = floor(fix.grid[k + 1]) end
            end
            if fix.offset ~= nil then
              local ng = {}
              for k = 0, 24 do ng[k] = (g and g[k] or 0) + floor(fix.offset) end
              g = ng
            end
            if g ~= nil then t.cells[ck] = g end
            if fix.cut ~= nil then
              local c = fix.cut
              local ckey = index * 65536 + x * 256 + y
              local rec = M.cuts[ckey] or { NO_VARIANT, 0, NONE16, NONE16, 0xFF, 0 }
              if c.variant == "none" then rec[1] = NO_VARIANT end
              if c.foot ~= nil then rec[2] = floor(c.foot) end
              if c.sides ~= nil then rec[5] = floor(c.sides) end
              if c.flags ~= nil then rec[6] = floor(c.flags) end
              for _, kv in ipairs({ { 3, "ground" }, { 4, "wall" } }) do
                local v = c[kv[2]]
                if v ~= nil then
                  rec[kv[1]] = v == Post.NULL and NONE16 or (v == "noface" and NO_FACE or floor(v))
                end
              end
              if c.delete then
                M.cuts[ckey] = nil
              else
                M.cuts[ckey] = rec
                if not t.cells[ck] then
                  local ng = {}
                  for k = 0, 24 do ng[k] = lvl end
                  t.cells[ck] = ng
                end
              end
            end
          end
          changed = changed + 1
        end
      end
      if changed > 0 or spec.base ~= nil or spec.belt ~= nil then
        report[#report + 1] = name .. ": " .. changed .. " cell(s)"
      end
    end
  end
  return report
end

return Post
