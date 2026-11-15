-- What the relief solver reads (Battle Scene: Overworld), off the engine's cache of the player's
-- cartridge: what pret's data gives Emerald 3DS's generators.
--
-- Paths under the engine's cache root (src/scene/cache.lua: the engine's own constants):
--   map_tree/census.json                 every map's slot (group_num) and name
--   map_tree/maps/<slot>/header.json     its layout id, type, size, tilesets, connections
--   map_tree/maps/<slot>/events.json, grid.bin   its warps and sign events; its layout's blockdata
--                                        (u16 a cell, raw)
--   map_tree/tilesets/<ts>/              tiles.4bpp, palettes.bin, metatiles.bin, attributes.bin,
--                                        as pret builds them
--   native/layout_files.lua, manifest.lua   a layout id's map name, a map's tileset pair (its
--                                        tilesets' names); without layout_files (FireRed's cache
--                                        has none) a layout id's name is its first map's baked one
--                                        (the engine's match: Family.normal)
--   native/layouts/alt_<id>.mid          a layout a script swaps in (no map uses it), baked by the
--                                        engine
--
-- Plain Lua: Input.build(io) with
--   io.read(rel) -> bytes or nil       rel under the cache's root (the paths above)
--   io.json(text) -> table             io.lua(text) -> the table a "return {...}" source gives
--   io.behaviours                      { MB_NAME = value } the game's behaviour enum (raw values)
--   io.family, io.Family               optional: the game's tileset family and src/scene/family.lua
--                                       (without them, Emerald's: RSE, "EM_" names)
--   io.collBlocked(coll) -> bool       an engine collision code that blocks (an alternate layout's
--                                       baked cells keep no collision bits: where its metatile is
--                                       not the base layout's there, this decides)
--   io.tick                            optional, called now and then
-- Returns { layouts = { [id] = L }, byName = { [name] = L }, maps = { map... sorted by name },
-- tilesets = { [ts] = ts }, behaviours, game (io.game: "emerald", "firered"; nil without it) }, with
--   L = { id, name ("LAYOUT_ROUTE104"), w, h, blocks (0-based raw u16s), primary, secondary (ts
--         records), outdoor, warps = { {x, y} } (sorted), signs = { ["x,y"] = true }, alternateOf
--         (the base's name) }
--   map = { name ("Route104"), layout (id), outdoor, connections = { { direction ("up", "down",
--           "left", "right"), layout (id), offset } } }
--   ts = { key, name (short: "general", "mossdeep", "battlefrontieroutsideeast"), tiles, palettes,
--          metatiles, attributes, family (io.family) }

local Input = {}

-- The layouts a script swaps in, which no map uses (pret's names; the engine bakes them as
-- alt_<id>), and the map layout each stands in for
Input.ALTERNATES = {
  [46] = { "LAYOUT_ROUTE130_MIRAGE_ISLAND", "LAYOUT_ROUTE130" },
  [319] = { "LAYOUT_ROUTE131_SKY_PILLAR", "LAYOUT_ROUTE131" },
  [357] = { "LAYOUT_SOOTOPOLIS_CITY_LEGENDS_BATTLE", "LAYOUT_SOOTOPOLIS_CITY" },
  [392] = { "LAYOUT_ROUTE111_NO_MIRAGE_TOWER", "LAYOUT_ROUTE111" },
  [438] = { "LAYOUT_SKY_PILLAR_TOP_CLEAN", "LAYOUT_SKY_PILLAR_TOP" },
}
-- FireRed's and LeafGreen's (their scripts' setmaplayoutindex; each matched to its base by its
-- cells: the Dunsparce Tunnel dug open, which the game draws from the start (special 403), the
-- currents stopped in Seafoam B3F / B4F, the Seven Island house's room with its door open; our
-- names)
Input.ALTERNATES_FRLG = {
  [264] = { "LAYOUT_SEVEN_ISLAND_HOUSE_ROOM1_DOOR_OPEN", "LAYOUT_SEVEN_ISLAND_HOUSE_ROOM1" },
  [278] = { "LAYOUT_SEAFOAM_ISLANDS_B3F_CURRENT_STOPPED", "LAYOUT_SEAFOAM_ISLANDS_B3F" },
  [279] = { "LAYOUT_SEAFOAM_ISLANDS_B4F_CURRENT_STOPPED", "LAYOUT_SEAFOAM_ISLANDS_B4F" },
  [319] = { "LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL_OPEN", "LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL" },
}

--- A game's alternates and the prefix its maps' baked layouts take (native/layouts/<prefix><name>).
function Input.alternatesFor(game)
  if game == "firered" or game == "leafgreen" then return Input.ALTERNATES_FRLG, "FR_" end
  -- (Ruby's and Sapphire's scripts swap no layouts in: Mirage Tower, the Sky Pillar's crumbled top
  -- and Sootopolis's legends are Emerald's)
  if game == "ruby" then return {}, "RU_" end
  if game == "sapphire" then return {}, "SA_" end
  return Input.ALTERNATES, "EM_"
end

local DIRECTIONS = { north = "up", south = "down", west = "left", east = "right",
                     up = "up", down = "down", left = "left", right = "right" }

local function u16(s, i) return s:byte(i + 1) + s:byte(i + 2) * 256 end

--- An engine-baked layout (native/layouts/<name>.mid): { w, h, at(x, y) -> metatile, collision
--- code, elevation } (its grid padded past its size to an even one), or nil.
function Input.baked(blob)
  if not (blob and #blob >= 16) then return nil end
  local W, TW, TH = u16(blob, 6), u16(blob, 10), u16(blob, 12)
  local off = 16 + blob:byte(15) * blob:byte(16) * 2
  return { w = TW, h = TH, at = function(x, y)
    local o = off + (y * W + x) * 4
    return u16(blob, o), blob:byte(o + 3), blob:byte(o + 4)
  end }
end

--- An alternate layout's blocks (0-based raw u16s: metatile, collision bits, elevation), over its
--- base (`base`: w, h, blocks): `alt` and `own` the engine's baked cells of the alternate and of
--- the base (Input.baked). A baked cell keeps no collision bits: where it is the base's own cell
--- (metatile and code alike) it has the base's; else the bits the base gives that metatile with
--- that code; else the code says (collBlocked(code)). nil unless the sizes agree.
function Input.alternateBlocks(base, alt, own, collBlocked, tick)
  if not (alt and own and alt.w == base.w and alt.h == base.h and own.w == base.w and own.h == base.h) then
    return nil
  end
  local learned = {}
  for y = 0, base.h - 1 do
    if tick then tick() end
    for x = 0, base.w - 1 do
      local mid, coll = own.at(x, y)
      local bits = math.floor(base.blocks[y * base.w + x] / 1024) % 4
      local k = mid * 256 + coll
      local t = learned[k]
      if not t then t = {}; learned[k] = t end
      t[bits] = (t[bits] or 0) + 1
    end
  end
  local blocks = {}
  for y = 0, base.h - 1 do
    if tick then tick() end
    for x = 0, base.w - 1 do
      local i = y * base.w + x
      local mid, coll, elev = alt.at(x, y)
      local bmid, bcoll = own.at(x, y)
      local bits
      if mid == bmid and coll == bcoll then
        bits = math.floor(base.blocks[i] / 1024) % 4
      else
        local t = learned[mid * 256 + coll]
        if t then
          local best, bn
          for b = 0, 3 do if t[b] and (not bn or t[b] > bn) then best, bn = b, t[b] end end
          bits = best
        else
          bits = collBlocked(coll) and 1 or 0
        end
      end
      blocks[i] = mid + bits * 1024 + (elev % 16) * 4096
    end
  end
  return blocks
end

--- A tileset's short name: "gTileset_EverGrande", "ever_grande" -> "evergrande".
function Input.short(name)
  local s = tostring(name or ""):gsub("^gTileset_", "")
  return (s:gsub("_", "")):lower()
end

function Input.build(io, palettesOf)
  local ROOT = ""     -- (io.read's paths are under the cache's root already)
  local tick = io.tick
  local F, Fam = io.family, io.Family
  -- (the prefix of a baked name of the game's: "EM_"; FireRed's "FR_" and "SEVII_")
  local function prefixOf(file)
    if F and Fam then return Fam.prefixOf(F, file) end
    return file:match("^EM_") and "EM_" or nil
  end
  local census = io.json(io.read(ROOT .. "map_tree/census.json") or "{}") or {}
  local files = io.lua(io.read(ROOT .. "native/layout_files.lua") or "return {}") or {}
  local manifest = io.lua(io.read(ROOT .. "native/manifest.lua") or "return {}") or {}
  local pairOfMap = {}
  for name, info in pairs(manifest.layouts or {}) do pairOfMap[name] = info.pair end
  local out = { layouts = {}, byName = {}, maps = {}, tilesets = {}, behaviours = io.behaviours, game = io.game }
  local tilesets = out.tilesets
  local function tileset(key, short)
    local t = tilesets[key]
    if t then return t end
    local base = ROOT .. "map_tree/tilesets/" .. key .. "/"
    t = { key = key, name = short, tiles = io.read(base .. "tiles.4bpp") or "",
          metatiles = io.read(base .. "metatiles.bin") or "", attributes = io.read(base .. "attributes.bin") or "",
          family = F }
    t.palettes = palettesOf(io.read(base .. "palettes.bin"))
    tilesets[key] = t
    return t
  end
  -- every map, by slot
  local slots, bySlot = {}, {}
  for _, g in ipairs(census.groups or {}) do
    for _, m in ipairs(g.maps or {}) do
      if m.slot then
        slots[#slots + 1] = m.slot
        bySlot[m.slot] = m
      end
    end
  end
  local headers = {}
  for _, slot in ipairs(slots) do
    local h = io.json(io.read(ROOT .. "map_tree/maps/" .. slot .. "/header.json") or "null")
    if h then headers[slot] = h end
    if tick then tick() end
  end
  -- (no layout_files: each layout id named after its maps' baked layouts, which the engine's own
  -- name match finds; maps sharing a layout keep the first name in sorted order, as World names it)
  if next(files) == nil and F and Fam then
    local names, byNormal = {}, {}
    for name in pairs(manifest.layouts or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local k = Fam.normal(F, name)
      if byNormal[k] == nil then byNormal[k] = name end
    end
    for _, slot in ipairs(slots) do
      local h = headers[slot]
      local id = h and tonumber(h.layoutId)
      local k = id and byNormal[Fam.normal(F, tostring(h.pretName or h.id or ""))]
      if k then
        local had = files[id]
        if had == nil or k:sub(#prefixOf(k) + 1) < had:sub(#prefixOf(had) + 1) then files[id] = k end
      end
    end
    -- (a map the engine names otherwise - Pallet's rooms keep Gen 1's names: FR_OAKS_LAB for
    -- PalletTown_ProfessorOaksLab - by the longest name no map took that its own name ends with)
    local taken = {}
    for _, name in pairs(files) do taken[name] = true end
    for _, slot in ipairs(slots) do
      local h = headers[slot]
      local id = h and tonumber(h.layoutId)
      if id and files[id] == nil then
        local full = Fam.normal(F, tostring(h.pretName or h.id or ""))
        local best, bestK
        for k, name in pairs(byNormal) do
          if not taken[name] and #k >= 6 and #k < #full and full:sub(-#k) == k and (not bestK or #k > #bestK) then
            best, bestK = name, k
          end
        end
        if best then files[id], taken[best] = best, true end
      end
    end
  end
  local OUTDOOR = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true }
  for _, slot in ipairs(slots) do
    local h = headers[slot]
    local id = h and tonumber(h.layoutId)
    local file = id and files[id]
    local prefix = type(file) == "string" and prefixOf(file)
    if prefix then
      local L = out.layouts[id]
      if not L then
        local grid = io.read(ROOT .. "map_tree/maps/" .. slot .. "/grid.bin")
        local pair = pairOfMap[file]
        local p, s
        if F and F.namespace then
          p, s = F.pairNames(pair, "^(.-)__(.+)$")
        else
          p, s = tostring(pair or ""):match("^(.-)__(.+)$")
        end
        if grid and p then
          local blocks = {}
          for i = 0, h.width * h.height - 1 do blocks[i] = u16(grid, i * 2) end
          L = { id = id, name = "LAYOUT_" .. file:sub(#prefix + 1), w = h.width, h = h.height, blocks = blocks,
                primary = tileset(h.primaryTileset, Input.short(p)),
                secondary = tileset(h.secondaryTileset, Input.short(s)),
                outdoor = false, warps = {}, signs = {}, warpSet = {} }
          out.layouts[id] = L
          out.byName[L.name] = L
        end
      end
      if L then
        L.outdoor = L.outdoor or OUTDOOR[tonumber(h.mapType) or -1] == true
        local e = io.json(io.read(ROOT .. "map_tree/maps/" .. slot .. "/events.json") or "null") or {}
        for _, w in ipairs(e.warps or {}) do
          local k = w.x .. "," .. w.y
          if not L.warpSet[k] then
            L.warpSet[k] = true
            L.warps[#L.warps + 1] = { w.x, w.y }
          end
        end
        for _, b in ipairs(e.bgEvents or {}) do
          if b.type == "sign" then L.signs[b.x .. "," .. b.y] = true end
        end
        local m = { name = h.id or bySlot[slot].id, layout = id, outdoor = OUTDOOR[tonumber(h.mapType) or -1] == true,
                    connections = {}, slot = slot }
        for _, c in ipairs(h.connections or {}) do
          local d = DIRECTIONS[c.dir or c.direction]
          local th = headers[tostring(c.mapGroup) .. "_" .. tostring(c.mapNum)]
          if th then m.connections[#m.connections + 1] = { direction = d, layout = tonumber(th.layoutId),
                                                          offset = tonumber(c.offset) or 0, raw = c.dir } end
        end
        out.maps[#out.maps + 1] = m
      end
    end
  end
  for _, L in pairs(out.layouts) do
    table.sort(L.warps, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  end
  table.sort(out.maps, function(a, b) return a.name < b.name end)
  -- the alternates: the engine's baked cells (Input.alternateBlocks), the base's tilesets, events
  -- and outdoor-ness
  local function baked(name) return Input.baked(io.read(ROOT .. "native/layouts/" .. name .. ".mid")) end
  local alternates, prefix = Input.alternatesFor(io.game)
  if F and F.name ~= "rse" and alternates == Input.ALTERNATES then alternates = {} end
  for id, row in pairs(alternates) do
    local base = out.byName[row[2]]
    local blocks = base and Input.alternateBlocks(base, baked("alt_" .. id), baked(prefix .. base.name:sub(8)),
      io.collBlocked, tick)
    if blocks then
      local L = { id = id, name = row[1], w = base.w, h = base.h, blocks = blocks, primary = base.primary,
                  secondary = base.secondary, outdoor = base.outdoor, warps = base.warps, signs = base.signs,
                  warpSet = base.warpSet, alternateOf = base.name }
      out.layouts[id] = L
      out.byName[L.name] = L
    end
    if tick then tick() end
  end
  return out
end

return Input
