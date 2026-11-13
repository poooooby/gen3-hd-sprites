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
  local World = {}

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  local state            -- per game data table: { layouts, byName, arts, roles, posts, ... }

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
    local Dataset, NativePack, CachePaths = req("src.core.game3.dataset"), req("src.import.gba.native_pack"),
      req("src.core.game3.cache_paths")
    local cache = Dataset and Dataset.cache()
    if not (cache and NativePack) then return nil end
    local root = ((CachePaths and CachePaths.NATIVE_ROOT) or "data/generated/gba/native") .. "/" .. pair
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

  -- every Emerald map by its slot: layouts by id, their maps' events joined
  local function load()
    local maps = gameData()
    if type(maps) ~= "table" then return nil end
    if state and state.maps == maps then return state end
    local Dataset, Rse = req("src.core.game3.dataset"), req("src.core.game3.rse")
    local cache = Dataset and Dataset.cache()
    if not (cache and Rse and json) then return nil end
    local s = { maps = maps, layouts = {}, byName = {}, byMap = {}, arts = {}, roles = {} }
    for id, def in pairs(maps) do
      if type(id) == "string" and id:match("^EM_") then
        local okG, g, n = pcall(Rse.mapGroupNum, id)
        local slot = okG and g and (g .. "_" .. n)
        local rawH = slot and cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
        local okJ, h = pcall(function() return rawH and json(rawH) end)
        if okJ and h and h.layoutId then
          local L = s.layouts[h.layoutId]
          if not L then
            L = { id = h.layoutId, w = h.width, h = h.height, pair = def.pair, warps = {}, signs = {},
                  outdoor = false, maps = {},
                  grid = cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/grid.bin") }
            s.layouts[h.layoutId] = L
          end
          L.maps[#L.maps + 1] = id
          L.outdoor = L.outdoor or Dataset.isOutdoorMapType(h.mapType)
          local rawE = cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/events.json")
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

  --- The layout of an Emerald map (EM_X), or of a layout id: { id, name, w, h, pair, warps,
  --- signs, outdoor, maps, grid }, or nil.
  function World.layout(key)
    local s = load()
    if not s then return nil end
    if type(key) == "number" then return s.layouts[key] end
    return s.byMap[key] or s.byName[key]
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
  function World.posts()
    local s = load()
    if not s then return nil end
    if not s.posts then
      local all = {}
      for _, L in pairs(s.layouts) do
        if L.outdoor and next(L.signs) then
          local A = World.adapter(L)
          if A then all[#all + 1] = A end
        end
      end
      s.posts, s.postDrawings = Roles.posts(all)
    end
    return s.posts, s.postDrawings
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
