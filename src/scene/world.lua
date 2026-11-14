-- The game's own layouts, as Emerald 3DS's generators read them (Battle Scene: Overworld, and any
-- later 3D view of the overworld: nothing here knows of battles).
--
-- Emerald 3DS reads pret's data: each layout's blockdata (metatile, collision bits), its maps'
-- events (warps, sign events, outdoor or not) and its tilesets' drawings. The engine's cache holds
-- the same, read off the player's cartridge: map_tree/maps/G_N/{header.json, events.json,
-- grid.bin} by map slot, and each tileset pair's atlas blobs (mids*.idx, palettes.bin) for its
-- drawings layer by layer. This module joins them per layout id (the cartridge's: its map
-- headers'), as voxel_cells.MapEvents does, and builds src/scene/roles.lua's adapters over them.
--
-- Emerald only (its maps are EM_*), once a game; everything is cached.

return function(deps)
  local Roles, json = deps.Roles, deps.json      -- (json(text) -> table or nil)
  local Signs = deps.Signs                        -- (optional: src/scene/signs.lua, for signMetatiles)
  local Input = deps.Input                        -- (optional: src/scene/relief_input.lua, for the
                                                  -- layouts a script swaps in)
  local Cache = deps.Cache                        -- (src/scene/cache.lua: the engine's cache roots)
  local World = {}

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  -- the bytes at `rel` under the engine's cache root, or nil
  local function cread(rel) return Cache and Cache.read(rel) or nil end

  local state            -- per game data table: { layouts, byName, arts, roles, posts, ... }

  -- the rooms' layouts a script swaps in, which no map is drawn with (pret's names and ids; the
  -- engine bakes them as alt_<id>), and the map layout each stands in for - the outdoor ones are
  -- relief_input's Input.ALTERNATES
  World.ROOM_ALTERNATES = {
    [432] = { "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE", "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB" },
    [433] = { "LAYOUT_SKY_PILLAR_1F_CLEAN", "LAYOUT_SKY_PILLAR_1F" },
    [434] = { "LAYOUT_SKY_PILLAR_2F_CLEAN", "LAYOUT_SKY_PILLAR_2F" },
    [435] = { "LAYOUT_SKY_PILLAR_3F_CLEAN", "LAYOUT_SKY_PILLAR_3F" },
    [436] = { "LAYOUT_SKY_PILLAR_4F_CLEAN", "LAYOUT_SKY_PILLAR_4F" },
    [437] = { "LAYOUT_SKY_PILLAR_5F_CLEAN", "LAYOUT_SKY_PILLAR_5F" },
    [441] = { "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F_STAIRS_UNBLOCKED",
              "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F" },
  }
  -- and the swaps to another map's own layout: Shoal Cave's rooms at high tide
  World.MAP_SWAPS = {
    LAYOUT_SHOAL_CAVE_LOW_TIDE_ENTRANCE_ROOM = "LAYOUT_SHOAL_CAVE_HIGH_TIDE_ENTRANCE_ROOM",
    LAYOUT_SHOAL_CAVE_LOW_TIDE_INNER_ROOM = "LAYOUT_SHOAL_CAVE_HIGH_TIDE_INNER_ROOM",
  }

  local function gameData()
    local Runtime = req("src.core.game3.runtime")
    local game = Runtime and Runtime._game
    return game and game.data and game.data.maps
  end

  -- a pair's drawings, layer by layer, off its atlas blobs (Roles.blobPixels: exact layers, colour
  -- index 0 left out, colours as pret computes them)
  local function artOf(s, pair)
    local a = s.arts[pair]
    if a then return a end
    local Dataset, NativePack = req("src.core.game3.dataset"), req("src.import.gba.native_pack")
    local cache = Dataset and Dataset.cache()
    local native = Cache and Cache.native()
    if not (cache and NativePack and native) then return nil end
    local root = native .. "/" .. pair
    local function blob(name)
      local b = cache:read(root .. "/" .. name)
      return b and { blob = b, index = Roles.blobIndex(b) } or nil
    end
    local under, over, middle = blob("mids.idx"), blob("mids_over.idx"), blob("mids_mid.idx")
    local rawPal = cache:read(root .. "/palettes.bin")
    if not (under and rawPal) then return nil end
    local pals = Roles.palettes(NativePack.decodePalettes(rawPal))
    local layers, cells = {}, {}
    a = {
      pixels = function(m, layer)
        local l = layers[m]
        if not l then
          local lo, up = Roles.blobPixels(under, over, middle, pals, m)
          l = { lo, up }
          layers[m] = l
        end
        return l[layer + 1]
      end,
      cell = function(m)
        local c = cells[m]
        if not c then
          c = Roles.blobCell(under, over, middle, pals, m)
          cells[m] = c
        end
        return c
      end,
    }
    s.arts[pair] = a
    return a
  end

  -- a tileset's short name (voxel_props compares them): "battle_frontier" -> "battlefrontier"
  local function short(name) return (tostring(name or ""):gsub("^gTileset_", ""):gsub("_", "")):lower() end

  -- every Emerald map by its slot: layouts by id, their maps' events joined
  local function load()
    local maps = gameData()
    if type(maps) ~= "table" then return nil end
    if state and state.maps == maps then return state end
    local Dataset, Rse = req("src.core.game3.dataset"), req("src.core.game3.rse")
    local cache = Dataset and Dataset.cache()
    if not (cache and Rse and json) then return nil end
    local s = { maps = maps, layouts = {}, byName = {}, byMap = {}, bySlot = {}, arts = {}, roles = {} }
    for id, def in pairs(maps) do
      if type(id) == "string" and id:match("^EM_") then
        local okG, g, n = pcall(Rse.mapGroupNum, id)
        local slot = okG and g and (g .. "_" .. n)
        local rawH = slot and cread("map_tree/maps/" .. slot .. "/header.json")
        local okJ, h = pcall(function() return rawH and json(rawH) end)
        if okJ and h and h.layoutId then
          local L = s.layouts[h.layoutId]
          if not L then
            L = { id = h.layoutId, w = h.width, h = h.height, pair = def.pair, warps = {}, signs = {},
                  outdoor = false, maps = {}, links = {},
                  tilesets = { h.primaryTileset, h.secondaryTileset },
                  primary = short(select(1, Roles.pairTilesets(def.pair))),
                  secondary = short(select(2, Roles.pairTilesets(def.pair))),
                  grid = cread("map_tree/maps/" .. slot .. "/grid.bin") }
            s.layouts[h.layoutId] = L
          end
          L.maps[#L.maps + 1] = id
          s.bySlot[slot] = L
          -- (its maps' connections: { direction, the neighbour's slot, offset })
          for _, c in ipairs(h.connections or {}) do
            L.links[#L.links + 1] = { c.dir or c.direction, tostring(c.mapGroup) .. "_" .. tostring(c.mapNum),
                                      tonumber(c.offset) or 0 }
          end
          L.outdoor = L.outdoor or Dataset.isOutdoorMapType(h.mapType)
          local rawE = cread("map_tree/maps/" .. slot .. "/events.json")
          local okE, e = pcall(function() return rawE and json(rawE) end)
          for _, w in ipairs(okE and e and e.warps or {}) do L.warps[#L.warps + 1] = { w.x, w.y } end
          for _, b in ipairs(okE and e and e.bgEvents or {}) do
            if b.type == "sign" then L.signs[b.x .. "," .. b.y] = true end
          end
          s.byName["LAYOUT_" .. id:gsub("^EM_", "")] = L
          s.byMap[id] = L
        end
      end
    end
    -- (maps sharing a layout keep one name: the first in sorted order, as the layout is named)
    for name, L in pairs(s.byName) do
      if not L.name or name < L.name then L.name = name end
    end
    -- the layouts a script swaps in (setmaplayoutindex), which no map is drawn with: the engine's
    -- baked cells over their base's (relief_input's Input.ALTERNATES and alternateBlocks, as the
    -- relief reads them), the base's tilesets, events and outdoor-ness; no connections (no map is
    -- drawn with it: voxel_props.connections), and the engine's collision codes (`codes`)
    local Perm = req("src.core.CollPermissions")
    local alternates = {}
    for id, row in pairs(Input and Input.ALTERNATES or {}) do alternates[id] = row end
    for id, row in pairs(World.ROOM_ALTERNATES) do alternates[id] = row end
    for id, row in pairs(Input and alternates or {}) do
      local base = s.byName[row[2]]
      if base and base.grid and Perm and not s.layouts[id] then
        local function baked(name) return Input.baked(cread("native/layouts/" .. name .. ".mid")) end
        local bb = {}
        for i = 0, base.w * base.h - 1 do bb[i] = base.grid:byte(i * 2 + 1) + base.grid:byte(i * 2 + 2) * 256 end
        local alt = baked("alt_" .. id)
        local okA, blocks = pcall(Input.alternateBlocks, { w = base.w, h = base.h, blocks = bb }, alt,
          baked("EM_" .. base.name:sub(8)), function(c) return Perm.isWall(c) or Perm.isLedge(c) end)
        if okA and blocks then
          local bytes, codes = {}, {}
          for i = 0, base.w * base.h - 1 do
            local v = blocks[i]
            bytes[i + 1] = string.char(v % 256, math.floor(v / 256) % 256)
            local _, code = alt.at(i % base.w, math.floor(i / base.w))
            codes[i] = code
          end
          local L = { id = id, name = row[1], w = base.w, h = base.h, pair = base.pair, warps = base.warps,
                      signs = base.signs, outdoor = base.outdoor, maps = {}, links = {},
                      tilesets = base.tilesets, primary = base.primary, secondary = base.secondary,
                      grid = table.concat(bytes), codes = codes, alternateOf = base }
          s.layouts[id] = L
          s.byName[row[1]] = L
        end
      end
    end
    s.drawn = {}
    -- Emerald's behaviour names as the engine's ids (src/core/game3/mb.lua: FireRed's value where
    -- FireRed has the behaviour, 0x100 + Emerald's otherwise)
    local MB, Constants = req("src.core.game3.mb"), req("src.core.game3.constants")
    s.behaviours = {}
    local okC, em = pcall(function() return Constants.of("emerald").metatile_behaviors.byName end)
    for name in pairs(okC and em or {}) do
      if type(name) == "string" and name:match("^MB_") then s.behaviours[name] = MB.id(name) end
    end
    state = s
    return s
  end

  --- Every layout's id, in order.
  function World.layoutIds()
    local s = load()
    local out = {}
    for id in pairs(s and s.layouts or {}) do
      if type(id) == "number" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
  end

  --- The layout of an Emerald map (EM_X) - the one it is drawn with now (World.settle) - or of a
  --- layout id or name: { id, name, w, h, pair, warps, signs, outdoor, maps, grid, alternateOf (a
  --- layout a script swaps in: its base) }, or nil.
  function World.layout(key)
    local s = load()
    if not s then return nil end
    if type(key) == "number" then return s.layouts[key] end
    return s.drawn[key] or s.byMap[key] or s.byName[key]
  end

  -- Emerald 3DS's voxel_world.c sLayoutSwaps: a neighbour is drawn with the layout its script
  -- would swap in when the player enters it (Route 131's Sky Pillar, rising out of the sea only
  -- once the player has crossed into the route otherwise)
  World.NEIGHBOUR_SWAPS = {
    EM_ROUTE111 = { 392, function(Rse, sess) return not Rse.flag("FLAG_MIRAGE_TOWER_VISIBLE", sess) end },
    EM_ROUTE130 = { 46, function(_, sess, FieldRse) return FieldRse.isMirageIslandPresent(sess) == true end },
    EM_ROUTE131 = { 319 },
  }

  --- Of `candidates` (layouts of `base`'s size), the one a script swapped into a map drawn with
  --- `base`: every cell of it that differs from the base the map draws so now (liveMid(x, y) ->
  --- metatile; the engine keeps no layout id, it writes the cells), or nil.
  function World.swappedIn(base, candidates, liveMid)
    local function mid(L, i) return (L.grid:byte(i * 2 + 1) + L.grid:byte(i * 2 + 2) * 256) % 1024 end
    for _, L in ipairs(candidates) do
      if L.w == base.w and L.h == base.h then
        local differs, same = false, true
        for i = 0, L.w * L.h - 1 do
          local a = mid(L, i)
          if a ~= mid(base, i) then
            differs = true
            if liveMid(i % L.w, math.floor(i / L.w)) ~= a then same = false; break end
          end
        end
        if differs and same then return L end
      end
    end
    return nil
  end

  --- Which layout each map is drawn with now, as voxel_world.c's FillInstance takes it: the
  --- current map (`current`, its cells as the game draws them: liveMid(x, y) -> metatile) the one
  --- a script swapped in (World.swappedIn over its alternates and MAP_SWAPS), a neighbour its
  --- NEIGHBOUR_SWAPS one where the game's flags say so. Asked once a scene.
  function World.settle(current, liveMid)
    local s = load()
    if not s then return end
    s.drawn = {}
    local base = current and s.byMap[current]
    if base and liveMid then
      local candidates = {}
      for _, L in pairs(s.layouts) do
        if L.alternateOf == base then candidates[#candidates + 1] = L end
      end
      table.sort(candidates, function(p, q) return p.id < q.id end)
      local other = World.MAP_SWAPS[base.name] and s.byName[World.MAP_SWAPS[base.name]]
      if other then candidates[#candidates + 1] = other end
      s.drawn[current] = World.swappedIn(base, candidates, liveMid)
    end
    local Rse, FieldRse = req("src.core.game3.rse.init"), req("src.core.game3.scripting.natives_field_rse")
    local Runtime = req("src.core.game3.runtime")
    local sess = Runtime and Runtime.getSession and Runtime.getSession()
    for mapId, sw in pairs(World.NEIGHBOUR_SWAPS) do
      local L = s.layouts[sw[1]]
      if mapId ~= current and L and s.byMap[mapId] and L.alternateOf == s.byMap[mapId] then
        local ok, yes = true, true
        if sw[2] then ok, yes = pcall(sw[2], Rse, sess, FieldRse) end
        if ok and yes then s.drawn[mapId] = L end
      end
    end
  end

  --- The layout a map is drawn with in place of its own (World.settle), or nil.
  function World.swapped(mapId)
    local s = load()
    return s and s.drawn[mapId] or nil
  end

  --- src/scene/roles.lua's adapter over a layout (World.layout's), or nil.
  function World.adapter(L)
    local s = load()
    if not (s and L and L.grid and L.pair) then return nil end
    if L.adapter then return L.adapter end
    local grid, W = L.grid, L.w
    local function cellAt(x, y)
      local i = (y * W + x) * 2 + 1
      return grid:byte(i) + grid:byte(i + 1) * 256
    end
    local p, sec = Roles.pairTilesets(L.pair)
    local art = artOf(s, L.pair)
    if not art then return nil end
    local IS = req("src.core.game3.scripting.interaction_scripts")
    local beh = IS and IS.behaviors and IS.behaviors[L.pair] or {}
    L.adapter = {
      id = L.name, w = L.w, h = L.h, outdoor = L.outdoor, warps = L.warps, signs = L.signs,
      primary = p, secondary = sec,
      metatile = function(x, y) return cellAt(x, y) % 1024 end,
      blocked = function(x, y) return math.floor(cellAt(x, y) / 1024) % 4 ~= 0 end,
      behaviour = function(x, y) return beh[cellAt(x, y) % 1024] or 0 end,
      pixels = art.pixels, cell = art.cell,
    }
    return L.adapter
  end

  --- A pair's drawings off its atlas blobs: { pixels(m, layer) -> { [y * 16 + x] = { r, g, b } }
  --- (0..255; layer 0 the lower, 1 the upper), cell(m) }, or nil.
  function World.art(pair)
    local s = load()
    return s and pair and artOf(s, pair) or nil
  end

  --- The game's sign posts (Roles.posts over every outdoor layout with sign events): posts,
  --- postDrawings. Once a game.
  --- The metatiles of a layout drawn as a signpost's (Signs.signMetatiles), once a layout.
  function World.signMetatiles(L)
    if not L then return {} end
    if L.signMetatiles then return L.signMetatiles end
    L.signMetatiles = {}
    local A, r = World.adapter(L), World.roles(L)
    local art = World.art(L.pair)
    if not (A and r and art and Signs and Signs.signMetatiles and r.drawsPostSign) then return L.signMetatiles end
    L.signMetatiles = Signs.signMetatiles({ w = L.w, h = L.h, metatile = A.metatile, blocked = A.blocked,
      role = r.role, signs = L.signs or {}, pixels = art.pixels, drawsPostSign = r.drawsPostSign })
    return L.signMetatiles
  end

  function World.posts()
    local s = load()
    if not s then return nil end
    if not s.posts then
      local all = {}
      for _, L in pairs(s.layouts) do
        if L.outdoor and next(L.signs) and not L.alternateOf then
          local A = World.adapter(L)
          if A then all[#all + 1] = A end
        end
      end
      s.posts, s.postDrawings = Roles.posts(all)
    end
    return s.posts, s.postDrawings
  end

  --- A layout's neighbours: { { L2, dx, dy } } where each neighbour's origin lies in the layout's
  --- cells, from its maps' connections (voxel_props.connections).
  local DIRS = { north = "up", south = "down", west = "left", east = "right", up = "up", down = "down",
                 left = "left", right = "right" }
  function World.neighbours(L)
    local s = load()
    if not (s and L) then return {} end
    if L._neighbours then return L._neighbours end
    local out = {}
    for _, c in ipairs(L.links or {}) do
      local B = s.bySlot[c[2]]
      local d, off = DIRS[tostring(c[1]):lower()], c[3]
      if B and B ~= L and d then
        local at = d == "down" and { off, L.h } or d == "up" and { off, -B.h } or d == "right" and { L.w, off }
          or { -B.w, off }
        out[#out + 1] = { B, at[1], at[2] }
      end
    end
    L._neighbours = out
    return out
  end

  --- A layout's upper layer in subtiles (voxel_props.upper_subtiles), off the raw metatiles:
  --- { at = { [sy * 4096 + sx] = tile + palette * 1024 + flips * 16384 }, order = { keys, row by
  --- row } }, or nil.
  function World.subtiles(L)
    local s = load()
    if not (s and L and L.grid and L.tilesets) then return nil end
    if L._subs ~= nil then return L._subs or nil end
    L._subs = false
    local Dataset = req("src.core.game3.dataset")
    local cache = Dataset and Dataset.cache()
    if not cache then return nil end
    local function metatiles(key)
      return key and cread("map_tree/tilesets/" .. tostring(key) .. "/metatiles.bin") or ""
    end
    local pt, st = metatiles(L.tilesets[1]), metatiles(L.tilesets[2])
    local grid, W = L.grid, L.w
    local at, order = {}, {}
    for y = 0, L.h - 1 do
      for x = 0, W - 1 do
        local i = (y * W + x) * 2 + 1
        local m = (grid:byte(i) + grid:byte(i + 1) * 256) % 1024
        local ts, k = pt, m
        if m >= 512 then ts, k = st, m - 512 end
        if (k + 1) * 16 <= #ts then
          for q = 0, 3 do
            local o = k * 16 + (4 + q) * 2 + 1
            local en = ts:byte(o) + ts:byte(o + 1) * 256
            if en % 1024 ~= 0 then
              local key = (y * 2 + math.floor(q / 2)) * 4096 + x * 2 + q % 2
              at[key] = en % 1024 + (math.floor(en / 4096) % 16) * 1024 + (math.floor(en / 1024) % 4) * 16384
              order[#order + 1] = key
            end
          end
        end
      end
    end
    L._subs = { at = at, order = order }
    return L._subs
  end

  --- A layout's tilesets as pret composes them (src/scene/relief_art.lua's Art.pair over its two
  --- tilesets, read off the cache: subtiles(m, layer), cellImage(m), colours as 0xRRGGBB), or nil.
  function World.pretArt(L)
    local s = load()
    local Art = deps.Art
    if not (s and L and L.tilesets and Art) then return nil end
    local key = tostring(L.tilesets[1]) .. "/" .. tostring(L.tilesets[2])
    s.pretPairs = s.pretPairs or {}
    if s.pretPairs[key] ~= nil then return s.pretPairs[key] or nil end
    s.pretPairs[key] = false
    local Dataset = req("src.core.game3.dataset")
    local cache = Dataset and Dataset.cache()
    if not cache then return nil end
    s.pretTilesets = s.pretTilesets or {}
    local function tileset(k)
      local t = s.pretTilesets[k]
      if t then return t end
      local base = "map_tree/tilesets/" .. tostring(k) .. "/"
      local tiles = cread(base .. "tiles.4bpp")
      if not tiles then return nil end
      t = { key = k, name = short(k), tiles = tiles, metatiles = cread(base .. "metatiles.bin") or "",
            attributes = cread(base .. "attributes.bin") or "",
            palettes = Art.palettes(cread(base .. "palettes.bin")) }
      s.pretTilesets[k] = t
      return t
    end
    local pt, st = tileset(L.tilesets[1]), tileset(L.tilesets[2])
    if not (pt and st) then return nil end
    local p = Art.pair(pt, st)
    s.pretPairs[key] = p
    return p
  end

  --- A layout's roles (Roles.new over its adapter, cached), or nil.
  function World.roles(L)
    local s = load()
    if not (s and L) then return nil end
    local r = s.roles[L.id]
    if r ~= nil then return r or nil end
    s.roles[L.id] = false
    local A = World.adapter(L)
    if not A then return nil end
    local posts, drawings = World.posts()
    local ref = World.layout("LAYOUT_ROUTE116")
    r = Roles.new(A, { behaviours = s.behaviours, posts = posts, postDrawings = drawings,
                       reference = ref and World.adapter(ref) or nil })
    s.roles[L.id] = r
    return r
  end

  return World
end
