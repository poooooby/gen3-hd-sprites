-- What Emerald 3DS's relief generator reads off a layout's drawing (Battle Scene: Overworld): its
-- metatiles composed as the GBA composes them, layer by layer, from the tilesets' own data (the
-- 4bpp tiles, the 16-colour palettes, the 8 tile entries of each metatile), and the few bits of
-- Python the generator's output depends on, reproduced exactly: CPython's set order (which a
-- tie between equally common colours falls to), its compensated float sum and its round.
--
-- Adapted from Emerald 3DS (3ds_port/scripts/voxel_building.py LayoutArt, dump_region_art.py,
-- voxel_art.py Pair, gen_voxel_relief.py's commonest / set_order / alias_of / AliasArt; by Zallax
-- and contributors, CC BY-NC-SA 4.0, https://github.com/ZallaxDev/emerald-3ds; see LICENSE).
-- Changes here: written in Lua, over the cartridge's tileset data as the engine's cache keeps it
-- (pret builds the same bytes) instead of pret's files. LuaJIT only (64-bit integers for the hash).
--
-- Plain Lua. A tileset: { name ("gTileset_General"), tiles (4bpp bytes, a string), palettes
-- (sixteen palettes of sixteen colours, each r * 65536 + g * 256 + b, 0-based), metatiles (8 u16
-- tile entries a metatile, a string), attributes (a u16 a metatile, a string) }. A colour is the
-- integer r * 65536 + g * 256 + b throughout.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift
local floor = math.floor

local Art = {}

Art.NUM_PRIMARY = 512
local MAGENTA = 255 * 65536 + 0 * 256 + 255

-- ── Python, exactly ──────────────────────────────────────────────────────────

local P1 = 11400714785074694791ULL
local P2 = 14029467366897019727ULL
local P5 = 2870177450012600261ULL
local ALL = 0xFFFFFFFFFFFFFFFFULL

--- hash(n) of a small int, as an unsigned 64-bit value (Python's -1 is -2).
local function hashInt(v)
  if v == -1 then v = -2 end
  return 0ULL + v
end
Art.hashInt = hashInt

--- hash(tuple of small ints) as 64-bit CPython computes it (xxHash lanes), unsigned.
local function hashTuple(items, n)
  local acc = P5
  for i = 1, n do
    acc = acc + hashInt(items[i]) * P2
    acc = bor(lshift(acc, 31), rshift(acc, 33))
    acc = acc * P1
  end
  acc = acc + bxor(0ULL + n, bxor(P5, 3527539ULL))
  if acc == ALL then return 1546275796ULL end
  return acc
end
Art.hashTuple = hashTuple

local rgbTmp = {}
--- hash((r, g, b)) of a colour key.
-- (a colour's hash, once: there are few colours, and every 64-bit operation allocates)
local rgbHashes = {}
function Art.hashRGB(c)
  local h = rgbHashes[c]
  if h then return h end
  rgbTmp[1], rgbTmp[2], rgbTmp[3] = floor(c / 65536), floor(c / 256) % 256, c % 256
  h = hashTuple(rgbTmp, 3)
  rgbHashes[c] = h
  return h
end

local function insertClean(tbl, mask, key, h)
  local perturb = h
  local i = tonumber(band(perturb, mask))
  while true do
    if tbl[i] == nil then
      tbl[i] = { h, key }
      return
    end
    if i + 9 <= mask then
      for j = i + 1, i + 9 do
        if tbl[j] == nil then
          tbl[j] = { h, key }
          return
        end
      end
    end
    perturb = rshift(perturb, 5)
    i = tonumber(band(0ULL + i * 5 + 1 + perturb, 0ULL + mask))
  end
end

--- list(set(seq)) as 64-bit CPython orders it; hashOf(key) -> its hash (unsigned 64-bit).
function Art.setOrder(seq, hashOf)
  -- (only the distinct keys, in the order they first come: a key met again finds its own slot and
  -- changes nothing, so the table, and the order, are the same - without hashing every repeat)
  local distinct, seen = {}, {}
  for _, key in ipairs(seq) do
    if not seen[key] then seen[key] = true; distinct[#distinct + 1] = key end
  end
  local mask, tbl, used = 7, {}, 0
  for _, key in ipairs(distinct) do
    local h = hashOf(key)
    local perturb = h
    local i = tonumber(band(perturb, 0ULL + mask))
    local slot
    while slot == nil do
      local probes = (i + 9 <= mask) and 9 or 0
      local j = i
      while true do
        local e = tbl[j]
        if e == nil then
          slot = j
          break
        end
        if e[1] == h and e[2] == key then
          slot = -1
          break
        end
        if probes == 0 then break end
        probes = probes - 1
        j = j + 1
      end
      if slot == nil then
        perturb = rshift(perturb, 5)
        i = tonumber(band(0ULL + i * 5 + 1 + perturb, 0ULL + mask))
      end
    end
    if slot >= 0 then
      tbl[slot] = { h, key }
      used = used + 1
      if used * 5 >= mask * 3 then
        local size = 8
        local minused = used > 50000 and used * 2 or used * 4
        while size <= minused do size = size * 2 end
        local old, oldMask = tbl, mask
        tbl, mask = {}, size - 1
        for k = 0, oldMask do
          local e = old[k]
          if e then insertClean(tbl, mask, e[2], e[1]) end
        end
      end
    end
  end
  local out = {}
  for k = 0, mask do
    if tbl[k] then out[#out + 1] = tbl[k][2] end
  end
  return out
end

--- max(set(seq), key=seq.count) with 64-bit CPython's tie-break. hashOf: Art.hashRGB for colours,
--- Art.hashInt (the default) for ints.
function Art.commonest(seq, hashOf)
  local counts = {}
  for _, v in ipairs(seq) do counts[v] = (counts[v] or 0) + 1 end
  local best, bn
  for _, v in ipairs(Art.setOrder(seq, hashOf or hashInt)) do
    if not bn or counts[v] > bn then best, bn = v, counts[v] end
  end
  return best
end

--- sum() of Python floats (3.12+: Neumaier's compensated sum), of a list of numbers that are all
--- floats.
function Art.fsum(list, n)
  n = n or #list
  if n == 0 then return 0 end
  local f, c = list[1], 0.0
  for i = 2, n do
    local x = list[i]
    local t = f + x
    if math.abs(f) >= math.abs(x) then c = c + ((f - t) + x) else c = c + ((x - t) + f) end
    f = t
  end
  if c ~= 0 and c == c and c ~= math.huge and c ~= -math.huge then f = f + c end
  return f
end

--- sum() of Python numbers some of which are ints: values[i], isFloat[i]. Returns the sum and
--- whether it is a float. (An int prefix sums exactly; past the first float, ints are added
--- plainly and floats compensated.)
function Art.mixedSum(values, isFloat, n)
  n = n or #values
  local i, isum = 1, 0
  while i <= n and not isFloat[i] do
    isum = isum + values[i]
    i = i + 1
  end
  if i > n then return isum, false end
  local f, c = isum + values[i], 0.0
  for k = i + 1, n do
    local x = values[k]
    if isFloat[k] then
      local t = f + x
      if math.abs(f) >= math.abs(x) then c = c + ((f - t) + x) else c = c + ((x - t) + f) end
      f = t
    else
      f = f + x
    end
  end
  if c ~= 0 and c == c and c ~= math.huge and c ~= -math.huge then f = f + c end
  return f, true
end

--- round(x) of a Python float: to the nearest int, ties to even.
function Art.round(x)
  local f = floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 end
  if d < 0.5 then return f end
  return (f % 2 == 0) and f or f + 1
end

-- ── tilesets ─────────────────────────────────────────────────────────────────

local function u16(s, i) return s:byte(i + 1) + s:byte(i + 2) * 256 end
Art.u16 = u16

--- A tileset's sixteen palettes from its GBA colours (palettes.bin: BGR555, a u16 a colour), each
--- channel as pret reads it (c * 255 // 31).
function Art.palettes(bin)
  local out = {}
  for p = 0, 15 do
    local pal = {}
    for i = 0, 15 do
      local o = (p * 16 + i) * 2
      if bin and o + 2 <= #bin then
        local v = u16(bin, o)
        local r, g, b = band(v, 31), band(rshift(v, 5), 31), band(rshift(v, 10), 31)
        pal[i] = floor(r * 255 / 31) * 65536 + floor(g * 255 / 31) * 256 + floor(b * 255 / 31)
      else
        pal[i] = MAGENTA
      end
    end
    out[p] = pal
  end
  return out
end

--- A primary/secondary pair's drawing: Art.pair(primary, secondary) (tilesets as above).
function Art.pair(pt, st)
  st = st or pt
  local P = { primary = pt, secondary = st, _sub = {}, _sub2 = {}, _cells = {}, _layers = {} }
  -- an 8x8 block: { [k] = colour, [64 + k] = colour index }, row major, or nil (pret's Pair:
  -- unreadable); `magenta` as Tilesets.subtile has it (magenta, index 0)
  local function readSubtile(tileId, palId, magenta)
    local ts = tileId < 512 and pt or st
    local loc = tileId < 512 and tileId or tileId - 512
    local base = loc * 32
    if base + 32 > #ts.tiles then
      if not magenta then return nil end
      local out = {}
      for k = 0, 63 do out[k], out[64 + k] = MAGENTA, 0 end
      return out
    end
    local pal = (palId < 6 and pt or st).palettes[palId]
    if not pal then
      if not magenta then return nil end
      pal = {}
      for i = 0, 15 do pal[i] = MAGENTA end
    end
    local out = {}
    for y = 0, 7 do
      for x = 0, 7 do
        local packed = ts.tiles:byte(base + y * 4 + floor(x / 2) + 1)
        local idx = (x % 2 == 1) and rshift(packed, 4) or band(packed, 15)
        out[y * 8 + x], out[64 + y * 8 + x] = pal[idx], idx
      end
    end
    return out
  end
  --- The 8 tile entries of metatile m, or nil past its table.
  function P.entries(m)
    local ts = m < 512 and pt or st
    local i = m < 512 and m or m - 512
    if (i + 1) * 16 > #ts.metatiles then return nil end
    local e = {}
    for k = 0, 7 do e[k] = u16(ts.metatiles, i * 16 + k * 2) end
    return e
  end
  --- Its attribute (the behaviour is its low byte).
  function P.attribute(m)
    local ts = m < 512 and pt or st
    local i = m < 512 and m or m - 512
    if not ts.attributes or (i + 1) * 2 > #ts.attributes then return 0 end
    return u16(ts.attributes, i * 2)
  end
  -- LayoutArt.subtiles(m, layer): four blocks of 64 { colour, index }, flips applied (magenta
  -- where a tile is unreadable)
  local function subtiles(m, layer)
    local key = m * 2 + layer
    local s = P._sub[key]
    if s then return s end
    s = {}
    local e = P.entries(m)
    for q = 0, 3 do
      local entry = e and e[layer * 4 + q]
      local data = entry and readSubtile(band(entry, 0x3FF), band(rshift(entry, 12), 15), true)
      local blk = {}
      if data then
        local fx, fy = band(entry, 0x400) ~= 0, band(entry, 0x800) ~= 0
        for y = 0, 7 do
          for x = 0, 7 do
            local k = (fy and 7 - y or y) * 8 + (fx and 7 - x or x)
            blk[y * 8 + x], blk[64 + y * 8 + x] = data[k], data[64 + k]
          end
        end
      end
      s[q] = blk
    end
    P._sub[key] = s
    return s
  end
  P.subtiles = subtiles
  --- A whole metatile as the ground renderer draws it: 256 colours, row major from 0 (with
  --- lowerOnly, its lower layer alone). The lower layer is opaque (an index 0 pixel shows its
  --- palette's colour 0); the upper is keyed on index 0.
  function P.cellImage(m, lowerOnly)
    local key = m * 2 + (lowerOnly and 1 or 0)
    local img = P._cells[key]
    if img then return img end
    img = {}
    local low, high = subtiles(m, 0), subtiles(m, 1)
    for q = 0, 3 do
      local lo, hi = low[q], high[q]
      for k = 0, 63 do
        local X = (q % 2) * 8 + k % 8
        local Y = floor(q / 2) * 8 + floor(k / 8)
        local i1 = hi[64 + k]
        if i1 and i1 ~= 0 and not lowerOnly then img[Y * 16 + X] = hi[k]
        else img[Y * 16 + X] = lo[k] or 0 end
      end
    end
    P._cells[key] = img
    return img
  end
  --- What one layer draws (voxel_art.Pair.layer_pixels): { [y * 16 + x] = colour }, index 0 left out
  --- (an unreadable tile draws nothing).
  function P.layerPixels(m, layer)
    local key = m * 2 + layer
    local out = P._layers[key]
    if out then return out end
    out = {}
    local e = P.entries(m)
    if e then
      for q = 0, 3 do
        local entry = e[layer * 4 + q]
        local data = readSubtile(band(entry, 0x3FF), band(rshift(entry, 12), 15), false)
        if data then
          local fx, fy = band(entry, 0x400) ~= 0, band(entry, 0x800) ~= 0
          local ox, oy = (q % 2) * 8, floor(q / 2) * 8
          for y = 0, 7 do
            for x = 0, 7 do
              local k = (fy and 7 - y or y) * 8 + (fx and 7 - x or x)
              if data[64 + k] ~= 0 then out[(oy + y) * 16 + ox + x] = data[k] end
            end
          end
        end
      end
    end
    P._layers[key] = out
    return out
  end
  return P
end

--- A layout's drawing (voxel_building.LayoutArt): L = { name, w, h, blocks (0-based u16 list) },
--- over its pair (Art.pair). art.metatile(x, y), art.cellImage(m[, lowerOnly]), art.entries(m),
--- art.primary / art.secondary (tileset names); art.id its name; art.reading (nil: its own
--- colours; an AliasArt's name).
function Art.layoutArt(L, pair)
  local A = { id = L.name, w = L.w, h = L.h, pair = pair, primary = pair.primary.name,
              secondary = pair.secondary.name }
  local blocks, W = L.blocks, L.w
  function A.metatile(x, y) return band(blocks[y * W + x], 0x3FF) end
  A.ownMetatile = A.metatile
  function A.cellImage(m, lowerOnly) return pair.cellImage(m, lowerOnly) end
  function A.entries(m) return pair.entries(m) end
  return A
end

-- alias_of: the maps whose rock is the General tileset's drawn again in their own colours
Art.ALIAS_TILESETS = { lavaridge = true, fallarbor = true, mossdeep = true }   -- (short names)
Art.ALIAS_LAYOUTS = { LAYOUT_JAGGED_PASS = true, LAYOUT_MT_CHIMNEY = true, LAYOUT_LAVARIDGE_TOWN = true }
Art.ALIAS_TERRACES = { LAYOUT_ROUTE115 = true, LAYOUT_ROUTE114 = true, LAYOUT_ROUTE112 = true,
                       LAYOUT_ROUTE126 = true }
Art.ALIAS_REFERENCE = "LAYOUT_ROUTE116"

-- a tile's drawing without its palette: colours numbered as they come
local function drawingKey(img)
  local lab, n, parts = {}, 0, {}
  for k = 0, 255 do
    local c = img[k]
    local l = lab[c]
    if not l then
      l = n
      lab[c] = l
      n = n + 1
    end
    parts[k + 1] = l
  end
  return table.concat(parts, ",")
end

--- alias_of(lid): ({ own id: General id }, { General id: own id }, { own colour: General colour })
--- of a layout drawn with an ALIAS_TILESETS tileset, else nil. art: its LayoutArt; ref: the
--- reference's (LAYOUT_ROUTE116); roles: the General rock tiles matched (ROCK_TILES | SIDE_WEST |
--- SIDE_EAST | SEA_CAPS | BOULDER, sorted); boulderHeads.
function Art.aliasOf(art, ref, rolesSorted, boulderHeads)
  if not Art.ALIAS_TILESETS[art.secondary] then return nil end
  local known = {}
  for _, m in ipairs(rolesSorted) do
    if m < 512 then
      local k = drawingKey(ref.cellImage(m))
      if known[k] == nil then known[k] = m end
    end
  end
  local used, order = {}, {}
  for y = 0, art.h - 1 do
    for x = 0, art.w - 1 do
      local m = art.metatile(x, y)
      if not used[m] then
        used[m] = 0
        order[#order + 1] = m
      end
      used[m] = used[m] + 1
    end
  end
  local alias, aliasOrder = {}, {}
  local votes, voteOrder = {}, {}
  for _, m in ipairs(order) do
    if m >= 512 then
      local g = known[drawingKey(art.cellImage(m))]
      if g then
        alias[m] = g
        aliasOrder[#aliasOrder + 1] = m
        local a, b = art.cellImage(m), ref.cellImage(g)
        local n = used[m]
        for k = 0, 255 do
          local va = votes[a[k]]
          if not va then
            va = { n = {}, order = {} }
            votes[a[k]] = va
            voteOrder[#voteOrder + 1] = a[k]
          end
          if not va.n[b[k]] then
            va.n[b[k]] = 0
            va.order[#va.order + 1] = b[k]
          end
          va.n[b[k]] = va.n[b[k]] + n
        end
      end
    end
  end
  -- a boulder's head is the boulder only where the map draws it over the boulder's foot
  local kept = {}
  for _, m in ipairs(aliasOrder) do
    local g = alias[m]
    local keep = true
    if boulderHeads[g] then
      local over = 0
      for y = 0, art.h - 2 do
        for x = 0, art.w - 1 do
          if art.metatile(x, y) == m and alias[art.metatile(x, y + 1)] == boulderHeads[g] then over = over + 1 end
        end
      end
      if 2 * over < used[m] then keep = false end
    end
    if keep then kept[#kept + 1] = m else alias[m] = nil end
  end
  if #kept == 0 then return nil end
  local colour = {}
  for _, a in ipairs(voteOrder) do
    local va = votes[a]
    local best, bn
    for _, b in ipairs(va.order) do
      if not bn or va.n[b] > bn then best, bn = b, va.n[b] end
    end
    colour[a] = best
  end
  -- back: by how much each is used, ties as aliased
  local byUse = {}
  for i, m in ipairs(kept) do byUse[i] = m end
  local pos = {}
  for i, m in ipairs(kept) do pos[m] = i end
  table.sort(byUse, function(p, q)
    if used[p] ~= used[q] then return used[p] > used[q] end
    return pos[p] < pos[q]
  end)
  local back = {}
  for _, m in ipairs(byUse) do
    local g = alias[m]
    if back[g] == nil then back[g] = m end
  end
  return { alias = alias, back = back, colour = colour }
end

--- AliasArt: a layout's drawing as the analysis reads it (its secondary tileset's General rock
--- tiles read as the General's ids, its own colours in the General's).
function Art.aliasArt(art, a)
  local A = {}
  for k, v in pairs(art) do A[k] = v end
  A.alias = a
  A.reading = art.id
  local cache = {}
  function A.metatile(x, y)
    local m = art.metatile(x, y)
    return a.alias[m] or m
  end
  A.ownMetatile = art.metatile
  function A.cellImage(m, lowerOnly)
    local key = m * 2 + (lowerOnly and 1 or 0)
    local img = cache[key]
    if img then return img end
    img = art.cellImage(m, lowerOnly)
    if m >= 512 then
      local out = {}
      for k = 0, 255 do out[k] = a.colour[img[k]] or img[k] end
      img = out
    end
    cache[key] = img
    return img
  end
  return A
end

return Art
