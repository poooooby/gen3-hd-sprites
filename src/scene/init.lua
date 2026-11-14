-- Battle Scene: Overworld (Gen 3). The battle's wallpaper and pads give way to the map around
-- where the battle started, in 2.5D: its tiles laid out on the ground in perspective, what blocks
-- a step stood up as cards, the distance fading into haze, a soft shadow under each side's
-- Pokemon. The battle's own sprites, move animations and UI are drawn over it as they always are.
--
--   src/scene/cells.lua    the map window around the player, each cell's kind and upright run
--   src/scene/stage.lua    where the camera aims, so both sides stand on fitting open ground
--   src/scene/camera.lua   the camera, in the battle canvas's own pixels, and the entrance glide
--   src/scene/render.lua   the meshes and the shader
--
-- Once per battle (the first frame of a new battle state) the window is read and the stage
-- searched; a battle with no map, or no stage that fits, keeps the game's wallpaper. The intro
-- glides the camera from straight above the player (the field's view) down to the stage, as
-- the battlers slide in. The world is drawn by WoobleView's battle composite (hd.world, the
-- "world" item): zoomed with the battlers by Battle Fit, across the whole view with Fill Screen.

return function(deps)
  local Camera, Cells, Stage, Render, Trees = deps.Camera, deps.Cells, deps.Stage, deps.Render, deps.Trees
  local hd = deps.hd

  local Scene = { enabled = false, Camera = Camera }

  -- love.graphics as it really is (the functions WoobleView wraps, unwrapped)
  local G = setmetatable({}, { __index = function(_, k) return hd.real[k] or love.graphics[k] end })

  -- the window of cells read around the player (columns either side, rows north and south): the
  -- stage may be up to Stage.REACH tiles off, and a zoomed-out or filled view shows far north
  Scene.WEST, Scene.EAST, Scene.NORTH, Scene.SOUTH = 30, 30, 46, 18
  -- the battle canvas's feet points and sprite boxes (the enemy's 64x64 pic centred at (176, 40),
  -- the player's at (72, 80)), and where the shadows lie
  Scene.FEET = { enemy = { 176, 70 }, player = { 72, 114 } }
  Scene.SPRITES = { enemy = { 144, 8, 208, 72 }, player = { 40, 48, 104, 112 } }
  Scene.SHADOW = { enemy = { 176, 70, 26, 6 }, player = { 72, 115, 32, 7 } }
  Scene.SHADOW_ALPHA = 0.42
  Scene.FOG = { outdoor = { 14, 48, 0.9 }, indoor = { 6, 22, 1 } }
  Scene.HAZE = { outdoor = { 0.80, 0.87, 0.93 }, indoor = { 0, 0, 0 } }
  Scene.GLIDE_FRAMES = 100

  local INDOOR_KINDS = { indoor = true, building = true, cave = true, underground = true, secret_base = true }

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  -- the engine's map, read through what cells.lua asks of it
  local function engineEnv()
    local Map, Collision = req("src.core.game3.map"), req("src.core.game3.collision")
    -- the collision classes (Gen 3's cells carry the same codes as Gold's): the core module, which
    -- a mod may require in any game
    local Perm = req("src.core.CollPermissions") or req("src.world.gen2.Permissions")
    if not (Map and Collision and type(Map.worldMidAt) == "function" and type(Map.currentDef) == "function") then
      return nil
    end
    local okD, def = pcall(Map.currentDef)
    local layout = okD and type(def) == "table" and def.midLayout
    if not layout then return nil end
    local function inside(L, x, y) return x >= 0 and y >= 0 and x < (L.width or 0) and y < (L.height or 0) end
    local env = { def = def, indoor = INDOOR_KINDS[tostring(def.kind)] == true }
    -- a room (Emerald 3DS's `indoor`: MAP_TYPE_INDOOR or MAP_TYPE_SECRET_BASE), ending in black
    -- past its edges; a cave ends in its border as a route does
    local mapType = tonumber(def.mapType)
    if mapType then env.walled = mapType == 8 or mapType == 9 else env.walled = env.indoor end
    function env.mid(cx, cy) return Map.worldMidAt(cx, cy, def) end
    local W, H = layout.width or 0, layout.height or 0
    -- a connected map's cell, found as the engine finds its art (Map.worldMidAt's fromDir: the
    -- side the cell is off, the connection's offset along it)
    local function neighbour(cx, cy)
      local dir = cy < 0 and "north" or cy >= H and "south" or cx < 0 and "west" or cx >= W and "east" or nil
      if not dir then return nil end
      for _, n in ipairs(Map.neighborList or {}) do
        local L = n.dir == dir and n.def and n.def.midLayout
        if L then
          local off = tonumber(n.offset) or 0
          local nx, ny
          if dir == "north" then nx, ny = cx - off, (L.height or 0) + cy
          elseif dir == "south" then nx, ny = cx - off, cy - H
          elseif dir == "west" then nx, ny = (L.width or 0) + cx, cy - off
          else nx, ny = cx - W, cy - off end
          if inside(L, nx, ny) then return L:collAt(nx, ny), Collision.behaviorOn(n.def, nx, ny) end
        end
      end
    end
    function env.cell(cx, cy)
      if inside(layout, cx, cy) then return layout:collAt(cx, cy), Collision.behaviorOn(def, cx, cy) end
      local c, b = neighbour(cx, cy)
      if c then return c, b end
      for _, e in ipairs(Map.world or {}) do
        local L = e.def ~= def and e.def and e.def.midLayout
        if L then
          local nx, ny = cx - (e.ox or 0), cy - (e.oy or 0)
          if inside(L, nx, ny) then return L:collAt(nx, ny), Collision.behaviorOn(e.def, nx, ny) end
        end
      end
      return nil
    end
    -- which map holds a cell (as env.cell finds it): its def, the cell in it, the map's id and
    -- where the map's north-west corner stands in the battle map's cells; nil outside every map
    local Runtime = req("src.core.game3.runtime")
    local sess = Runtime and Runtime.getSession and Runtime.getSession()
    env.mapId = sess and sess.map
    function env.where(cx, cy)
      if inside(layout, cx, cy) then return def, cx, cy, env.mapId, 0, 0 end
      local dir = cy < 0 and "north" or cy >= H and "south" or cx < 0 and "west" or cx >= W and "east" or nil
      for _, n in ipairs(Map.neighborList or {}) do
        local L = n.dir == dir and n.def and n.def.midLayout
        if L then
          local off = tonumber(n.offset) or 0
          local ox, oy
          if dir == "north" then ox, oy = off, -(L.height or 0)
          elseif dir == "south" then ox, oy = off, H
          elseif dir == "west" then ox, oy = -(L.width or 0), off
          else ox, oy = W, off end
          if inside(L, cx - ox, cy - oy) then return n.def, cx - ox, cy - oy, n.mapId or n.map, ox, oy end
        end
      end
      for _, e in ipairs(Map.world or {}) do
        local L = e.def ~= def and e.def and e.def.midLayout
        if L then
          local ox, oy = e.ox or 0, e.oy or 0
          if inside(L, cx - ox, cy - oy) then return e.def, cx - ox, cy - oy, e.id, ox, oy end
        end
      end
      return nil
    end
    -- the events of the maps the window shows (the battle's, its neighbours, the world round it),
    -- by world cell: sign events and warps
    local signsAt, warpsAt, seenDef = {}, {}, {}
    local Space = package.loaded["src.core.game3.scripting.space"]
    local function addEvents(d, id, ox, oy)
      if type(d) ~= "table" or seenDef[d] then return end
      seenDef[d] = true
      local evs = d.bgEvents
      if type(evs) ~= "table" then
        local b = Space and Space.bundle and Space.bundle.events and id and Space.bundle.events[id]
        evs = b and b.bgEvents
      end
      for _, ev in ipairs(type(evs) == "table" and evs or {}) do
        local x, y = tonumber(ev.x), tonumber(ev.y)
        if ev.type == "sign" and x and y then signsAt[(x + ox) .. "," .. (y + oy)] = true end
      end
      for _, w in ipairs(type(d.warps) == "table" and d.warps or {}) do
        local x, y = tonumber(w.x), tonumber(w.y)
        if x and y then warpsAt[(x + ox) .. "," .. (y + oy)] = true end
      end
    end
    addEvents(def, nil, 0, 0)
    for _, n in ipairs(Map.neighborList or {}) do
      local L = n.def and n.def.midLayout
      if L then
        local off = tonumber(n.offset) or 0
        local ox, oy
        if n.dir == "north" then ox, oy = off, -(L.height or 0)
        elseif n.dir == "south" then ox, oy = off, H
        elseif n.dir == "west" then ox, oy = -(L.width or 0), off
        elseif n.dir == "east" then ox, oy = W, off end
        if ox then addEvents(n.def, n.mapId or n.map, ox, oy) end
      end
    end
    for _, e in ipairs(Map.world or {}) do addEvents(e.def, e.id, e.ox or 0, e.oy or 0) end
    function env.signAt(cx, cy) return signsAt[cx .. "," .. cy] == true end
    -- the border block's metatile at any cell, tiled as the engine tiles it past the map's edges,
    -- and whether a metatile of the battle map's tilesets is water (Emerald 3DS's water shapes)
    function env.borderMid(cx, cy)
      local bw, bh = layout.borderWidth or 1, layout.borderHeight or 1
      local mids = layout.borderMids
      if not mids then return nil end
      return mids[(cy % bh) * bw + (cx % bw) + 1]
    end
    local IS = req("src.core.game3.scripting.interaction_scripts")
    local behaviorsOf = IS and IS.behaviors and IS.behaviors[layout.pair or def.pair] or nil
    local waterIds = {}
    local MBw = req("src.core.game3.mb")
    for _, n in ipairs(deps.Roles and deps.Roles.WATER_NAMES or {}) do
      local v = MBw and MBw.id((n:gsub("^MB_", "")))
      if v then waterIds[v] = true end
    end
    function env.waterMid(m)
      return m ~= nil and behaviorsOf ~= nil and waterIds[behaviorsOf[m] or -1] == true
    end
    env.W, env.H = W, H
    function env.doorAt(cx, cy) return warpsAt[cx .. "," .. cy] == true end
    -- a house door's behaviour (Emerald 3DS's HOUSE_DOORS), in the engine's behaviour ids
    local MB = req("src.core.game3.mb")
    local doors = {}
    for _, name in ipairs({ "ANIMATED_DOOR", "PETALBURG_GYM_DOOR", "CLOSED_SOOTOPOLIS_DOOR" }) do
      local v = MB and MB.id(name)
      if v then doors[v] = true end
    end
    function env.isHouseDoor(b) return doors[tonumber(b) or -1] == true end
    -- (without the module: the engine's own fallback, 0x07 / 0xff walls and 0x29 water)
    env.isWall = Perm and Perm.isWall or function(c) return c == 0x07 or c == 0xff end
    env.isWater = Perm and Perm.isWater or function(c) return c == 0x29 end
    env.isSurfable = Collision.isSurfable
    return env
  end

  -- a tileset pair's atlases, as render.lua asks for them
  local tileCache = setmetatable({}, { __mode = "v" })
  local function tilesFor(NativeTileset)
    return function(pair)
      local t = tileCache[pair]
      if t then return t end
      local ok, ts = pcall(NativeTileset.get, pair)
      if not (ok and type(ts) == "table" and ts.image) then return nil end
      t = {
        image = ts.image, overImage = ts.overImage,
        slot = function(mid) return NativeTileset.slotFor(ts, mid) end,
        quad = function(slot) return NativeTileset.quad(ts, slot) end,
        overQuad = function(slot) return ts.overImage and NativeTileset.overQuad(ts, slot) or nil end,
      }
      tileCache[pair] = t
      return t
    end
  end

  -- the kind a side's Pokemon wants to stand on (nil: any open ground)
  local STAND = { grass = true, sand = true, water = true, floor = true }
  local AHEAD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

  -- the wallpaper's top colour (the sky of each terrain), read back once per image
  local tops = setmetatable({}, { __mode = "k" })
  local function topColour(image)
    if not image then return nil end
    local hit = tops[image]
    if hit ~= nil then return hit or nil end
    tops[image] = false
    local ok, c = pcall(G.newCanvas, 1, 1, { dpiscale = 1 })
    if ok and c and c.newImageData then
      G.push("all")
      G.setCanvas(c)
      G.origin()
      G.setScissor()
      G.setShader()
      G.setColor(1, 1, 1, 1)
      G.setBlendMode("replace", "alphamultiply")
      G.draw(image, -8, -2)
      G.pop()
      local okD, data = pcall(c.newImageData, c)
      if okD and data then
        local r, g, b = data:getPixel(0, 0)
        tops[image] = { r, g, b }
      end
    end
    return tops[image] or nil
  end

  -- a soft shadow: a 256x160 layer (as the pads are) with one ellipse on it
  local function shadow(spec)
    local ok, c = pcall(G.newCanvas, 256, 160, { dpiscale = 1 })
    if not ok then return nil end
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.setShader()
    G.clear(0, 0, 0, 0)
    G.setBlendMode("alpha", "alphamultiply")
    local x, y, rx, ry = spec[1], spec[2], spec[3], spec[4]
    for i = 6, 1, -1 do
      local k = i / 6
      G.setColor(0.05, 0.06, 0.12, 0.2)
      G.ellipse("fill", x, y, rx * k, ry * k, 32)
    end
    G.pop()
    c:setFilter("linear", "linear")
    return c
  end
  local shadows

  -- the trees' art (assets/scene/trees.png), loaded once; false when it cannot be
  local treeImage
  local function treesArt()
    if treeImage == nil then
      treeImage = false
      if Trees and deps.path then
        local ok, img = pcall(G.newImage, deps.path .. "/assets/scene/trees.png")
        if ok and img then
          img:setFilter("nearest", "nearest")
          treeImage = img
        end
      end
    end
    return treeImage or nil
  end

  -- ── buildings (src/scene/buildings.lua) ──

  local Buildings, Kernel, Specs = deps.Buildings, deps.Kernel, deps.Specs
  local Signs, Relief, World = deps.Signs, deps.Relief, deps.World
  local placeComponents

  -- a reference layout, by its id (LAYOUT_X is the game's map EM_X)
  local function layoutCtx()
    local Runtime, Map = req("src.core.game3.runtime"), req("src.core.game3.map")
    local game = Runtime and Runtime._game
    return {
      layout = function(id)
        if not (Map and game and type(Map.ensureMidLayout) == "function") then return nil end
        local mapId = "EM_" .. tostring(id):gsub("^LAYOUT_", "")
        local ok, L = pcall(Map.ensureMidLayout, game, mapId)
        local maps = game.data and game.data.maps
        local def = maps and maps[mapId]
        if not (ok and L and def and def.pair) then return nil end
        local W, H = L.width or 0, L.height or 0
        return { pair = def.pair, mid = function(x, y)
          if x < 0 or y < 0 or x >= W or y >= H then return nil end
          return L:midAt(x, y)
        end }
      end,
    }
  end

  -- a tileset pair's two layers, pixel by pixel (its atlases' image data). The engine's atlases
  -- are split by draw order: `image` is the lower layer (with a COVERED metatile's upper layer
  -- drawn over it), `overImage` a NORMAL or SPLIT metatile's upper layer, `midImage` a NORMAL
  -- one's lower layer or a COVERED one's upper. A metatile with nothing over whose lower atlas
  -- shows more than one colour where its middle is clear (a NORMAL one shows only the backdrop
  -- there) is COVERED: its upper layer is its middle.
  local srcCache = setmetatable({}, { __mode = "k" })
  local function pixelSource(NativeTileset, pair)
    local ok, ts = pcall(NativeTileset.get, pair)
    if not (ok and type(ts) == "table" and ts.imageData and ts.midToSlot) then return nil end
    if srcCache[ts] then return srcCache[ts] end
    local under, over, middle = ts.imageData, ts.overImageData, ts.midImageData
    local cols, slots = ts.cols or 16, ts.midToSlot
    local floor = math.floor
    local covered = {}
    local function isCovered(s)
      local c = covered[s]
      if c ~= nil then return c end
      c = false
      if middle then
        local ox, oy = (s % cols) * 16, floor(s / cols) * 16
        local hasOver = false
        if over then
          for y = 0, 15 do
            for x = 0, 15 do
              local _, _, _, a = over:getPixel(ox + x, oy + y)
              if a > 0.5 then hasOver = true; break end
            end
            if hasOver then break end
          end
        end
        if not hasOver then
          local first, many = nil, false
          for y = 0, 15 do
            for x = 0, 15 do
              local _, _, _, a = middle:getPixel(ox + x, oy + y)
              if a <= 0.5 then
                local r, g, b = under:getPixel(ox + x, oy + y)
                local k = floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5)
                if first == nil then first = k elseif k ~= first then many = true; break end
              end
            end
            if many then break end
          end
          c = many
        end
      end
      covered[s] = c
      return c
    end
    local src = {
      ts = ts,
      under = function(mid, x, y)
        local s = slots[mid]
        if not s then return nil end
        return under:getPixel((s % cols) * 16 + x, floor(s / cols) * 16 + y)
      end,
      over = function(mid, x, y)
        local s = slots[mid]
        if not s then return nil end
        local img = isCovered(s) and middle or over
        if not img then return nil end
        return img:getPixel((s % cols) * 16 + x, floor(s / cols) * 16 + y)
      end,
    }
    srcCache[ts] = src
    return src
  end
  -- (for the dev drivers: a pair's layers, pixel by pixel)
  Scene._pixelSource = pixelSource

  -- a metatile less the quarters q of its upper layer (bit 2 * row + column): its whole drawing,
  -- and in those quarters the lower layer alone, read exactly off the atlas blobs (the engine's
  -- lower atlas has a COVERED metatile's upper layer drawn over it). Emerald 3DS's ground variant
  -- (voxel_atlas.c AtlasSourceOf). pixel(x, y) -> r, g, b (0..1) or nil.
  local function lessQuarters(NativeTileset, pair, mid, q)
    local src = pixelSource(NativeTileset, pair)
    local World_ = deps.World
    local wa = q ~= 0 and World_ and World_.art(pair)
    local lower = wa and wa.pixels(mid, 0)
    return function(x, y)
      local bit = 2 ^ ((y >= 8 and 2 or 0) + (x >= 8 and 1 or 0))
      local hidden = math.floor(q / bit) % 2 == 1
      local p = hidden and lower and lower[y * 16 + x]
      if p then return p[1] / 255, p[2] / 255, p[3] / 255 end
      if not src then return nil end
      local r, g, b = src.under(mid, x, y)
      local r1, g1, b1, a1 = src.over(mid, x, y)
      if a1 and a1 > 0.5 and not hidden then r, g, b = r1, g1, b1 end
      return r, g, b
    end
  end

  local function imageOf(W, H, fill)
    local ok, data = pcall(love.image.newImageData, W, H)
    if not ok then return nil end
    fill(data)
    local okI, img = pcall(G.newImage, data)
    if not okI then return nil end
    img:setFilter("nearest", "nearest")
    return img, data
  end

  -- a spec made ready to place: its reference, art (image), core cells and triangles (once)
  -- a model's cache (Scene Cache): its triangles, core cells and texture as bytes, under the
  -- game's key (Scene.modelCache, set by main.lua; Scene.MODELS_VERSION bumps when the specs or
  -- the kernel change what they build)
  Scene.MODELS_VERSION = 7
  -- the models with texels a tile animation redraws (md.live), made ready so far
  local liveModels = {}
  local function serialize(md)
    local out = { "return {primaryOnly=", md.primaryOnly and "true" or "false", ",texW=", md.texW, ",texH=", md.texH,
                  ",core={" }
    for _, c in ipairs(md.core) do out[#out + 1] = ("{%d,%d},"):format(c[1], c[2]) end
    out[#out + 1] = "},tris={"
    local f = function(v) return ("%.17g"):format(v) end
    for _, t in ipairs(md.tris) do
      local parts = {}
      for k = 1, 3 do
        local p = t[k]
        parts[k] = "{" .. f(p[1]) .. "," .. f(p[2]) .. "," .. f(p[3]) .. "," .. f(p[4]) .. "," .. f(p[5]) .. "}"
      end
      out[#out + 1] = "{" .. parts[1] .. "," .. parts[2] .. "," .. parts[3] .. ",shade=" .. f(t.shade or 1) .. "},"
    end
    out[#out + 1] = "}"
    local lv = md.live
    if lv then
      -- (texels the game's tile animation redraws: their frames' colours, flat)
      out[#out + 1] = (",live={pair=%q,mid=%d,frames=%d,texels={"):format(lv.pair, lv.mid, lv.frames)
      for i, v in ipairs(lv.texels) do out[#out + 1] = (i > 1 and "," or "") .. f(v) end
      out[#out + 1] = "}}"
    end
    out[#out + 1] = "}"
    return table.concat(out)
  end
  local function cachedModel(spec)
    local c = Scene.cacheModels and Scene.modelCache
    if not c then return nil end
    local src = c.read(spec.name .. ".lua")
    local rgba = src and c.read(spec.name .. ".rgba")
    if not (src and rgba) then return nil end
    local chunk = load(src, "=model", "t", {})
    local ok, md = pcall(chunk or error)
    if not (ok and type(md) == "table" and md.tris and md.texW and #rgba == md.texW * md.texH * 4) then return nil end
    local okI, img, data = pcall(function()
      local data = love.image.newImageData(md.texW, md.texH, "rgba8", rgba)
      local i = G.newImage(data)
      i:setFilter("nearest", "nearest")
      return i, data
    end)
    if not okI then return nil end
    md.image, md._data = img, data
    if md.live then liveModels[#liveModels + 1] = md end
    return md
  end
  local function keepModel(spec, md, tex)
    local c = Scene.cacheModels and Scene.modelCache
    if not (c and md and tex) then return end
    pcall(function()
      local data = love.image.newImageData(tex.w, tex.h)
      local px = tex.px
      for y = 0, tex.h - 1 do
        for x = 0, tex.w - 1 do
          local o = (y * tex.w + x) * 4
          data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
        end
      end
      c.write(spec.name .. ".rgba", data:getString())
      c.write(spec.name .. ".lua", serialize(md))
    end)
  end
  Scene.modelsFromCache, Scene.modelsBuilt = 0, 0

  -- a metatile's frames in the engine's tile animation banks (whole metatiles, or their upper
  -- layer): frames[f](x, y) -> r, g, b, or nil where clear; nil if it does not move. `upper`:
  -- only the banks of an upper layer (a cell over animated water animates its lower layer too)
  local function animFramesOf(pair, mid, upper)
    local TA = req("src.core.game3.tileset_anim")
    local entry = TA and TA._pairs and TA._pairs[pair]
    if not (mid and entry and entry.rse) then return nil end
    for _, bank in ipairs(entry.banks or {}) do
      local row = bank and bank.row
      for li, layer in ipairs({ { "under", "mids", entry.lut }, { "over", "overMids", entry.lutOver } }) do
        local blob, mids, lut = bank and bank[layer[1]], row and row[layer[2]], layer[3]
        if upper and li == 1 then blob = nil end
        for k, m in ipairs(blob and lut and mids or {}) do
          if m == mid then
            local frames, n = {}, #mids
            for f = 0, (row.frames or 1) - 1 do
              local base = (f * n + (k - 1)) * 256
              if #blob < base + 256 then return nil end
              frames[f] = function(x, y)
                local c = lut[blob:byte(base + y * 16 + x + 1)]
                if c:byte(4) == 0 then return nil end
                return c:byte(1) / 255, c:byte(2) / 255, c:byte(3) / 255
              end
            end
            return frames, row.frames or 1
          end
        end
      end
    end
    return nil
  end

  -- a layout's two layers as its metatiles draw them (voxel_building.LayoutArt.subtiles, over the
  -- cache's raw tilesets: relief_art's pair): the lower layer whole, also under a COVERED
  -- metatile's upper, which the engine's lower atlas has drawn over it (a battle tent's grass
  -- under its foot read as tent, the ground test missed it and left the grass's dots standing).
  -- The same reader as `src` (pixelSource); `src` itself where the raw tilesets are not at hand.
  local layerSources = setmetatable({}, { __mode = "k" })
  local function layerSource(layoutName, src)
    local L = World and World.layout(layoutName)
    local P = L and World.pretArt(L)
    if not P then return src end
    local s = layerSources[P]
    if s then return s end
    local floor = math.floor
    local function at(m, layer, x, y)
      if not P.entries(m) then return nil end
      local blk = P.subtiles(m, layer)[floor(y / 8) * 2 + floor(x / 8)]
      local k = (y % 8) * 8 + x % 8
      return blk[k], blk[64 + k]
    end
    local function rgb(c) return floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255 end
    s = {
      ts = src and src.ts,
      -- (opaque: an index 0 pixel is its palette's first colour, as pret's art reads it)
      under = function(m, x, y)
        local c = at(m, 0, x, y)
        if not c then return nil end
        local r, g, b = rgb(c)
        return r, g, b, 1
      end,
      over = function(m, x, y)
        local c, i = at(m, 1, x, y)
        if not c then return nil end
        if i == 0 then return 0, 0, 0, 0 end
        local r, g, b = rgb(c)
        return r, g, b, 1
      end,
    }
    layerSources[P] = s
    return s
  end

  local function ready(spec, NativeTileset, ctx)
    if spec._model ~= nil then return spec._model end
    local ref = Buildings.reference(spec, ctx)
    if not ref then return false end
    local src = pixelSource(NativeTileset, ref.pair)
    if not src then return false end
    spec._model = false
    local art = Buildings.art(spec, ref, layerSource(spec.layout, src))
    local hit = cachedModel(spec)
    if hit then
      hit.spec, hit.ref, hit.art = spec, ref, art
      spec._model = hit
      Scene.modelsFromCache = Scene.modelsFromCache + 1
      return hit
    end
    -- (parts read off the drawing come with a texture of their own: the drawing and its bands; a
    -- few read another building's drawing too, by its reference)
    local artCtx = { layoutArt = function(layout, x, y, w, h, ground)
      local other = { name = spec.name .. "/ref", layout = layout, rect = { x, y, w, h }, ground = ground,
                      ground_px = true }
      local oref = Buildings.reference(other, ctx)
      local osrc = oref and pixelSource(NativeTileset, oref.pair)
      return osrc and Buildings.art(other, oref, layerSource(layout, osrc)) or nil
    end,
    -- a metatile's lower layer alone (its colour-index-0 pixels as the engine's lower atlas
    -- draws them): lower(x, y) -> r, g, b
    lowerOf = function(m)
      local wa = World and World.art(ref.pair)
      local px = wa and wa.pixels(m, 0)
      if not (px and src.ts.midToSlot[m]) then return nil end
      return function(x, y)
        local p = px[y * 16 + x]
        if p then return p[1] / 255, p[2] / 255, p[3] / 255 end
        local r, g, b = src.under(m, x, y)
        return r, g, b
      end
    end,
    -- the rect's cell (cx, cy) in each frame of its tile animation (the engine's own banks:
    -- whole metatiles, or their upper layer): frames[f](x, y) -> r, g, b, or nil where clear; nil
    -- if it does not move
    animFrames = function(cx, cy)
      local mid = ref.template[cy * ref.w + cx + 1]
      return mid and animFramesOf(ref.pair, mid) or nil
    end }
    local live
    local okM, mesh, tex = pcall(function()
      local parts, t
      if spec.parts_art then
        -- (the spec's level of detail: the least steps of its height fields)
        Kernel.HEIGHTSOLID_LOD = spec.lod
        local ok, p, tt, lv = pcall(spec.parts_art, art, artCtx)
        Kernel.HEIGHTSOLID_LOD = nil
        if not ok then error(p, 0) end
        parts, t = p, tt
        -- (texels a tile animation redraws: { cell = { cx, cy }, frames, texels }, the cell's
        -- metatile found here)
        if lv then
          live = { pair = ref.pair, mid = ref.template[lv.cell[2] * ref.w + lv.cell[1] + 1], frames = lv.frames,
                   texels = lv.texels }
        end
      else
        parts = spec.parts()
      end
      local m = Kernel.build(parts)
      if spec.clip_art and Kernel.clipToArt then Kernel.clipToArt(m, t or art) end
      return m, t
    end)
    if not okM then
      hd.stats.sceneBuildingError = spec.name .. ": " .. tostring(mesh)
      return false
    end
    local core = Buildings.core(spec, ref, art)
    local primaryOnly = true
    for _, c in ipairs(core) do
      if ref.template[c[2] * ref.w + c[1] + 1] >= 512 then primaryOnly = false end
    end
    tex = tex or art
    local image, imageData = imageOf(tex.w, tex.h, function(data)
      local px = tex.px
      for y = 0, tex.h - 1 do
        for x = 0, tex.w - 1 do
          local o = (y * tex.w + x) * 4
          data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
        end
      end
    end)
    spec._model = { spec = spec, ref = ref, art = art, core = core, primaryOnly = primaryOnly,
                    tris = mesh.tris, image = image, _data = imageData, texW = tex.w, texH = tex.h, live = live }
    if live then liveModels[#liveModels + 1] = spec._model end
    Scene.modelsBuilt = Scene.modelsBuilt + 1
    keepModel(spec, spec._model, tex)
    return spec._model
  end

  local Components = deps.Components

  -- ── props: objects found by their upper-layer subtiles (src/scene/props.lua) ──
  local Props = deps.Props
  local propModels, propFinds = {}, {}
  local function propSpec(name)
    for _, sp in ipairs(Props.SPECS) do if sp.props == name then return sp end end
  end
  -- a variant's model (its offset in its cells and what is drawn of it), once a session: the
  -- object's subtiles as the map draws them, a Mound off them
  local function propModel(sp, f, cells, gx0, gy0, w, h, grid)
    local key = ("%s:%d%d:%s"):format(sp.name, f.sx % 2, f.sy % 2, f.key)
    if propModels[key] ~= nil then return propModels[key] or nil end
    propModels[key] = false
    local cx0, cy0 = math.floor(f.sx / 2), math.floor(f.sy / 2)
    local W, H = w * 16, h * 16
    local art = { w = W, h = H, px = {} }
    for i = 1, W * H * 4 do art.px[i] = 0 end
    -- which quarter of which cell each drawn subtile is: what the ground leaves out under it
    local quads = {}
    for k in pairs(f.present) do
      local i, j = k:match("(%d+),(%d+)")
      local sx, sy = f.sx + tonumber(i), f.sy + tonumber(j)
      local ci, cj = math.floor(sx / 2) - cx0, math.floor(sy / 2) - cy0
      local qx, qy = sx % 2, sy % 2
      local c = grid.at(gx0 + ci, gy0 + cj)
      local wa = c and c.mid and World.art(c.pair)
      local upper = wa and wa.pixels(c.mid, 1)
      if not upper then return nil end
      for y = 0, 7 do
        for x = 0, 7 do
          local p = upper[(qy * 8 + y) * 16 + qx * 8 + x]
          if p then
            local o = ((cj * 16 + qy * 8 + y) * W + ci * 16 + qx * 8 + x) * 4
            art.px[o + 1], art.px[o + 2], art.px[o + 3], art.px[o + 4] = p[1] / 255, p[2] / 255, p[3] / 255, 1
          end
        end
      end
      local qk = ci .. "," .. cj
      quads[qk] = (quads[qk] or 0) + 2 ^ (qy * 2 + qx)
    end
    local ring = {}
    for _, c in ipairs(sp.ring or {}) do ring[c[1] * 65536 + c[2] * 256 + c[3]] = true end
    local tex = Kernel.withRing(art, ring)
    local helpers = Specs and Specs.helpers or {}
    local dx, dz = (f.sx % 2) * 8, (f.sy % 2) * 8
    local part
    if sp.shape == "lathe" and helpers.ProjLathe then
      -- a turned thing (a pot, a basket): smooth, its drawing projected, where this variant's
      -- half-cell offset puts it
      local c = sp.lathe
      part = helpers.ProjLathe(sp.name, c.cx + dx, c.cz + dz, c.profile, { squash = c.squash or 1.0, seg = c.seg or 10 })
    elseif sp.shape == "dome" and helpers.ProjDome then
      -- a heap (fruit): a smooth dome, its drawing projected
      local c = sp.dome
      part = helpers.ProjDome(sp.name, c.cx + dx, c.cz + dz, c.rx, c.rz, c.h, { seg = c.seg or 12, rings = c.rings or 3 })
    elseif sp.shape == "flag" then
      -- a flag on its pole: a card standing at the pole's foot, over the whole grid (a frame of the
      -- cloth's animation reaches where the first does not draw)
      local grid0 = Props.OBJECTS[sp.props].grid
      local foot = 0
      for k in pairs(f.present) do
        local _, j = k:match("(%d+),(%d+)")
        foot = math.max(foot, dz + tonumber(j) * 8 + 8)
      end
      part = Kernel.Card("flag~live", art, foot, 0, 0, { dx, dx + #grid0[1] * 8, dz })
    elseif not sp.shape then
      part = Kernel.Mound("mound", tex, { rise = sp.rise, step = sp.step, ring = ring, rows = H })
    end
    if not part then return nil end
    local mesh = Kernel.build({ part })
    -- (cut to the drawing's box: the texel beside it is nothing of the object's)
    if sp.clip_art and Kernel.clipToArt then Kernel.clipToArt(mesh, art) end
    local image, imageData = imageOf(tex.w, tex.h, function(data)
      local px = tex.px
      for y = 0, tex.h - 1 do
        for x = 0, tex.w - 1 do
          local o = (y * tex.w + x) * 4
          data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
        end
      end
    end)
    local owned, core = {}, {}
    for _, c in ipairs(cells) do
      owned[(c[1] - cx0) .. "," .. (c[2] - cy0)] = true
      core[#core + 1] = { c[1] - cx0, c[2] - cy0 }
    end
    local md = { spec = { name = key, owned = owned, ground = sp.ground }, ref = { w = w, h = h, template = {} },
                 core = core, art = art, tris = mesh.tris, image = image, _data = imageData, texW = tex.w, texH = tex.h,
                 primaryOnly = true, quads = quads }
    -- a flag's cloth: every pixel of its tiles follows the game's animation of them (the
    -- engine's bank for them is their upper layer, its colour 0 clear)
    if sp.live_tiles then
      local grid0 = Props.OBJECTS[sp.props].grid
      local texels, lv = {}, nil
      for k in pairs(f.present) do
        local i, j = k:match("(%d+),(%d+)")
        i, j = tonumber(i), tonumber(j)
        local t = grid0[j + 1][i + 1]
        t = type(t) == "table" and t[1] or t
        if t and t >= sp.live_tiles[1] and t < sp.live_tiles[2] then
          local sx, sy = f.sx + i, f.sy + j
          local ci, cj = math.floor(sx / 2) - cx0, math.floor(sy / 2) - cy0
          local qx, qy = sx % 2, sy % 2
          local c = grid.at(gx0 + ci, gy0 + cj)
          local frames, n = animFramesOf(c.pair, c.mid, true)
          if frames and (not lv or lv.frames == n) then
            lv = lv or { pair = c.pair, mid = c.mid, frames = n, texels = texels, upper = true }
            for y = 0, 7 do
              for x = 0, 7 do
                local o = #texels
                texels[o + 1], texels[o + 2] = ci * 16 + qx * 8 + x, cj * 16 + qy * 8 + y
                for fr = 0, n - 1 do
                  local r, g, b = frames[fr](qx * 8 + x, qy * 8 + y)
                  local d = o + 3 + 4 * fr
                  texels[d], texels[d + 1], texels[d + 2], texels[d + 3] = r or 0, g or 0, b or 0, r and 1 or 0
                end
              end
            end
          end
        end
      end
      if lv and #texels > 0 then
        md.live = lv
        liveModels[#liveModels + 1] = md
      end
    end
    propModels[key] = md
    return md
  end

  -- every prop of the maps the window shows, stood where it is drawn: its cells (no building's)
  -- lay their own drawing for ground, the object's subtiles left out
  local function placeProps(grid, NativeTileset, found, where)
    local maps = {}
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        local _, _, _, id, ox, oy = where(c.cx, c.cy)
        if id and not maps[id] then maps[id] = { ox, oy } end
      end
    end
    local ids = {}
    for id in pairs(maps) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local L = World.layout(id)
      local list = L and propFinds[L.id]
      if L and not list then
        list = Props.find(L, World.subtiles, World.neighbours)
        propFinds[L.id] = list
      end
      for _, f in ipairs(list or {}) do
        local sp = propSpec(f.name)
        local cells, x0, y0, w, h = Props.cellsOf(f.name, f.sx, f.sy)
        local gx0, gy0 = x0 + maps[id][1], y0 + maps[id][2]
        local ok = sp ~= nil
        for _, c in ipairs(cells) do
          local g = grid.at(gx0 + c[1] - x0, gy0 + c[2] - y0)
          if not g or not g.mid or g.model then ok = false end
        end
        local md = ok and propModel(sp, f, cells, gx0, gy0, w, h, grid)
        if md then
          local pl = { model = md, cx = gx0, cy = gy0 }
          local tops = Buildings.tops(md)
          for _, c in ipairs(cells) do
            local i, j = c[1] - x0, c[2] - y0
            local g = grid.at(gx0 + i, gy0 + j)
            g.model = pl
            g.top = tops[i .. "," .. j] or 0
          end
          -- the ground: each cell's own drawing, the object's quarters of its upper layer left out
          pl.ground = imageOf(w * 16, h * 16, function(data)
            for _, c in ipairs(cells) do
              local i, j = c[1] - x0, c[2] - y0
              local g = grid.at(gx0 + i, gy0 + j)
              local src = pixelSource(NativeTileset, g.pair)
              local wa = World.art(g.pair)
              local lower = wa and wa.pixels(g.mid, 0)
              local q = md.quads[i .. "," .. j] or 0
              for y = 0, 15 do
                for x = 0, 15 do
                  local r, gg, b
                  local bit = 2 ^ ((y >= 8 and 2 or 0) + (x >= 8 and 1 or 0))
                  local mine = math.floor(q / bit) % 2 == 1
                  local p = mine and lower and lower[y * 16 + x]
                  if p then
                    r, gg, b = p[1] / 255, p[2] / 255, p[3] / 255
                  elseif src then
                    r, gg, b = src.under(g.mid, x, y)
                    local r1, g1, b1, a1 = src.over(g.mid, x, y)
                    if a1 and a1 > 0.5 and not mine then r, gg, b = r1, g1, b1 end
                  end
                  if r then data:setPixel(i * 16 + x, j * 16 + y, r, gg, b, 1) end
                end
              end
            end
          end)
          found[#found + 1] = pl
        end
      end
    end
  end

  -- ── Route 110's Cycling Road: a deck on piers read off its drawing (src/scene/models/bridge.lua) ──
  -- Read once a game for the whole layout (a few seconds of work, run a few milliseconds a frame
  -- from the warm-up, or inside the relief's own background build) and kept in the model cache:
  -- one model per cell drawn alike, all of them on one texture (each block framed by a copy of its
  -- edge, as Emerald 3DS's gutter: a face ending on a block's edge samples a hair past it).
  local Bridge = deps.Bridge
  local bridges = {}          -- layout name -> { co, done, at, models, image, error, ms }
  Scene.BRIDGE_SLICE = 0.004
  local BRIDGE_ROWS = 4096    -- the atlas's height: blocks in columns of 18 texels

  local function bridgeIo(L)
    local roles = World and World.roles(L)
    local pair = World and World.pretArt(L)
    if not (roles and pair and L.grid) then return nil end
    local curb
    for _, sp in ipairs(Components and Components.SPECS or {}) do if sp.name == "curb" then curb = sp end end
    if not curb then return nil end
    local grid, W, H = L.grid, L.w, L.h
    local function cellAt(x, y)
      local i = (y * W + x) * 2 + 1
      return grid:byte(i) + grid:byte(i + 1) * 256
    end
    local function on(x, y) return x >= 0 and y >= 0 and x < W and y < H end
    return {
      w = W, h = H,
      metatile = function(x, y) return cellAt(x, y) % 1024 end,
      elevation = function(x, y) return on(x, y) and math.floor(cellAt(x, y) / 4096) % 16 or 0 end,
      blocked = function(x, y) return on(x, y) and math.floor(cellAt(x, y) / 1024) % 4 ~= 0 end,
      role = function(x, y) return roles.role(x, y) end,
      subtiles = pair.subtiles, cellImage = pair.cellImage,
      curb = { tiles = curb.tiles, fill = curb.fill, ground = curb.ground[1], height = curb.height },
    }
  end

  -- the blocks as the scene's models, on one texture: { at = { [C] = md }, models, image, data }
  local function bridgeModels(list, atlasW, atlasH, pixels)
    local okD, data = pcall(love.image.newImageData, atlasW, atlasH, "rgba8", pixels)
    if not okD then return nil, tostring(data) end
    local okI, image = pcall(G.newImage, data)
    if not okI then return nil, tostring(image) end
    image:setFilter("nearest", "nearest")
    local res = { at = {}, models = {}, image = image, data = data }
    for _, b in ipairs(list) do
      local md = { spec = { name = b.name, owned = { ["0,0"] = true }, ground = { b.ground } },
                   ref = { w = 1, h = 1, template = {} }, core = { { 0, 0 } }, tris = b.tris, image = image,
                   texW = atlasW, texH = atlasH, tops = { ["0,0"] = b.top / 16 }, primaryOnly = true,
                   groundMid = b.ground, patch = b.patch, bridge = true,
                   footprints = { ["0,0"] = b.footprint or false } }
      res.models[#res.models + 1] = md
      for _, p in ipairs(b.placed) do res.at[p[2] * 4096 + p[1]] = md end
    end
    return res
  end

  -- (the cache: one text file of the blocks, their triangles in the atlas's texels, and the atlas)
  local function bridgeSerialize(list, atlasW, atlasH, decks)
    local out = { ("bridge 2 %d %d %d %d\n"):format(atlasW, atlasH, #list, #decks) }
    for _, d in ipairs(decks) do out[#out + 1] = ("D %d %d %d %d %d\n"):format(d[1], d[2], d[3], d[4], d[5]) end
    local f = function(v) return ("%.9g"):format(v) end
    for _, b in ipairs(list) do
      local placed = {}
      for _, p in ipairs(b.placed) do placed[#placed + 1] = p[1] .. " " .. p[2] end
      out[#out + 1] = ("B %s %d %d %d %d %d %s %s\n"):format(b.name, b.ground, b.top, #b.placed,
        b.patch and 1 or 0, #b.tris, table.concat(placed, " "), b.footprint and table.concat(b.footprint, ",") or "-")
      if b.patch then
        local t = {}
        for k = 0, 255 do t[k + 1] = b.patch[k] and tostring(b.patch[k]) or "-1" end
        out[#out + 1] = table.concat(t, " ") .. "\n"
      end
      for _, t in ipairs(b.tris) do
        local v = {}
        for k = 1, 3 do for i = 1, 5 do v[#v + 1] = f(t[k][i]) end end
        v[#v + 1] = f(t.shade or 1)
        out[#out + 1] = table.concat(v, " ") .. "\n"
      end
    end
    return table.concat(out)
  end
  local function bridgeParse(src)
    local lines = src:gmatch("[^\n]+")
    local head = lines()
    local atlasW, atlasH, n, nd = (head or ""):match("^bridge 2 (%d+) (%d+) (%d+) (%d+)$")
    if not atlasW then return nil end
    local decks = {}
    for i = 1, tonumber(nd) do
      local x, y, t, b, g = lines():match("^D (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)$")
      decks[i] = { tonumber(x), tonumber(y), tonumber(t), tonumber(b), tonumber(g) }
    end
    local list = {}
    for _ = 1, tonumber(n) do
      local l = lines()
      local fields = {}
      for w in (l or ""):gmatch("%S+") do fields[#fields + 1] = w end
      if fields[1] ~= "B" then return nil end
      local b = { name = fields[2], ground = tonumber(fields[3]), top = tonumber(fields[4]), placed = {}, tris = {} }
      local np, hasPatch, nt = tonumber(fields[5]), fields[6] == "1", tonumber(fields[7])
      for i = 1, np do b.placed[i] = { tonumber(fields[7 + 2 * i - 1]), tonumber(fields[7 + 2 * i]) } end
      local fp = fields[8 + 2 * np]
      if fp and fp ~= "-" then
        b.footprint = {}
        for v in fp:gmatch("[^,]+") do b.footprint[#b.footprint + 1] = tonumber(v) end
      end
      if hasPatch then
        b.patch = {}
        local k = 0
        for w in lines():gmatch("%S+") do
          local v = tonumber(w)
          if v >= 0 then b.patch[k] = v end
          k = k + 1
        end
      end
      for i = 1, nt do
        local v, j = {}, 0
        for w in lines():gmatch("%S+") do j = j + 1; v[j] = tonumber(w) end
        b.tris[i] = { { v[1], v[2], v[3], v[4], v[5] }, { v[6], v[7], v[8], v[9], v[10] },
                      { v[11], v[12], v[13], v[14], v[15] }, shade = v[16] }
      end
      list[#list + 1] = b
    end
    return list, tonumber(atlasW), tonumber(atlasH), decks
  end

  -- the whole build, inside a coroutine: tick() yields when its slice is spent
  local function bridgeBuild(name, tick)
    local conf = Bridge.BRIDGES[name]
    local L = World.layout(name)
    local io = L and bridgeIo(L)
    if not io then return nil, "no layout data" end
    local br = Bridge.read(io, conf, tick)
    local blocks = Bridge.blocks(br, "cycling_road_" .. name:gsub("^LAYOUT_", ""):lower(), tick)
    local decks = Bridge.decks(br)
    -- the atlas: each block at (ox + 1, oy + 1), framed by a copy of its edge
    local cols, ox, oy = 1, 0, 0
    local spots = {}
    for i, b in ipairs(blocks) do
      if oy + b.art.h + 2 > BRIDGE_ROWS then cols, ox, oy = cols + 1, ox + 18, 0 end
      spots[i] = { ox, oy }
      oy = oy + b.art.h + 2
    end
    local atlasW, atlasH = cols * 18, #blocks > 0 and (cols > 1 and BRIDGE_ROWS or oy) or 1
    local bytes = {}
    local pixels = {}
    local function at(x, y) return (y * atlasW + x) * 4 end
    for k = 0, atlasW * atlasH * 4 - 1 do pixels[k] = 0 end
    local list = {}
    for i, b in ipairs(blocks) do
      local sx, sy = spots[i][1], spots[i][2]
      local a = b.art
      for y = -1, a.h do
        for x = -1, 16 do
          local cx, cy = math.max(0, math.min(15, x)), math.max(0, math.min(a.h - 1, y))
          local o = (cy * 16 + cx) * 4
          local d = at(sx + 1 + x, sy + 1 + y)
          if a.px[o + 4] > 0 then
            pixels[d], pixels[d + 1], pixels[d + 2], pixels[d + 3] = math.floor(a.px[o + 1] * 255 + 0.5),
              math.floor(a.px[o + 2] * 255 + 0.5), math.floor(a.px[o + 3] * 255 + 0.5), 255
          end
        end
      end
      local mesh = Bridge.mesh(b, io.curb.height)
      local tris = {}
      for j, t in ipairs(mesh.tris) do
        local nt = { shade = t.shade }
        for k = 1, 3 do
          local p = t[k]
          nt[k] = { p[1], p[2], p[3], p[4] + sx + 1, p[5] + sy + 1 }
        end
        tris[j] = nt
      end
      list[i] = { name = b.name, ground = b.ground, top = b.top, placed = b.placed, patch = b.patch, tris = tris,
                  footprint = b.footprint }
      tick("atlas")
    end
    for k = 0, atlasW * atlasH * 4 - 1 do bytes[k + 1] = string.char(pixels[k]) end
    return list, atlasW, atlasH, table.concat(bytes), decks
  end

  local function bridgeFinish(name, st, list, atlasW, atlasH, rgba, decks, fromCache)
    local res, why = bridgeModels(list, atlasW, atlasH, rgba)
    if not res then st.error = why; return end
    st.done, st.at, st.models, st.image, st.decks = true, res.at, res.models, res.image, decks
    if not fromCache and Scene.cacheModels and Scene.modelCache then
      Scene.modelCache.write(name .. ".bridge", bridgeSerialize(list, atlasW, atlasH, decks))
      Scene.modelCache.write(name .. ".bridge.rgba", rgba)
    end
  end

  --- (internal) A layout's bridge job: started on first ask, read from the cache when it is
  --- there.
  local function bridgeJob(name)
    local st = bridges[name]
    if st then return st end
    st = {}
    bridges[name] = st
    if not (Bridge and Bridge.BRIDGES[name] and World and Components) then st.error = "no bridge"; return st end
    local c = Scene.cacheModels and Scene.modelCache
    local src = c and c.read(name .. ".bridge")
    local rgba = src and c.read(name .. ".bridge.rgba")
    if src and rgba then
      local okP, list, w, h, decks = pcall(bridgeParse, src)
      if okP and list and #rgba == w * h * 4 then
        bridgeFinish(name, st, list, w, h, rgba, decks, true)
        st.cached = true
        if st.done then return st end
      end
    end
    local clock = love.timer and love.timer.getTime or os.clock
    st.t0 = clock()
    st.co = coroutine.create(function()
      return bridgeBuild(name, function(label)
        local t = clock()
        -- (dev: Scene.bridgeWatch = seconds; every longer stretch between two ticks, the ticks'
        -- labels either side of it)
        if Scene.bridgeWatch then
          if st.lastTick and t - st.lastTick > Scene.bridgeWatch then
            st.gaps = st.gaps or {}
            st.gaps[#st.gaps + 1] = ("%.0f ms %s -> %s"):format((t - st.lastTick) * 1000, tostring(st.lastLabel),
              tostring(label))
          end
          st.lastTick, st.lastLabel = t, label
        end
        if st.budget and t - st.sliceStart > st.budget then
          coroutine.yield()
          st.lastTick = clock()
        end
      end)
    end)
    return st
  end

  --- (internal) Run a layout's bridge job for `budget` seconds (nil: to its end); `outer` is
  --- called between slices (the relief's own tick, when it runs inside that build).
  local function bridgeStep(name, budget, outer)
    local st = bridgeJob(name)
    local clock = love.timer and love.timer.getTime or os.clock
    while st.co do
      st.budget, st.sliceStart = budget or (outer and Scene.BRIDGE_SLICE) or nil, clock()
      local ok, list, w, h, rgba, decks = coroutine.resume(st.co)
      if not ok then
        st.error, st.co = tostring(list), nil
      elseif coroutine.status(st.co) == "dead" then
        st.co = nil
        if list then
          bridgeFinish(name, st, list, w, h, rgba, decks, false)
          st.ms = math.floor((clock() - st.t0) * 1000 + 0.5)
        else
          st.error = tostring(w)
        end
      elseif budget then
        break
      elseif outer then
        outer()
      end
    end
    return st
  end

  --- The bridge of a layout (LAYOUT_X) made ready, built now if it is not yet: { at = { [y * 4096
  --- + x] = model }, models, image } or nil and why. tick (optional): the relief's, between slices.
  function Scene.bridge(name, tick)
    if not (Bridge and Bridge.BRIDGES[name]) then return nil, "no bridge" end
    local st = bridgeStep(name, nil, tick)
    if st.done then return st end
    return nil, st.error
  end
  function Scene.hasBridge(name) return Bridge ~= nil and Bridge.BRIDGES[name] ~= nil end

  --- A layout's deck table (Emerald 3DS's: Route 110's Cycling Road, Fortree's decks, bridges and
  --- ladders), for an overworld that lifts its walkers: { { x, y, top, bottom, gate } } - the
  --- surface a walker on cell (x, y) stands on, pixels over the ground at the cell's top and bottom
  --- edges, and the elevation it must be at to be up there (0: any) - or nil. The bridge's is built
  --- with it (Scene.bridge: now, if it is not yet).
  local deckTables = {}
  function Scene.decks(name)
    if deckTables[name] ~= nil then return deckTables[name] or nil end
    if Scene.hasBridge(name) then
      local st = Scene.bridge(name)
      if st and st.decks then deckTables[name] = st.decks end
      return st and st.decks or nil
    end
    local f = Specs and Specs.decks and Specs.decks[name]
    local L = f and World and World.layout(name)
    if not (L and L.grid) then return nil end
    local grid, W = L.grid, L.w
    local function cellAt(x, y)
      local i = (y * W + x) * 2 + 1
      return grid:byte(i) + grid:byte(i + 1) * 256
    end
    local out = f({ w = L.w, h = L.h, metatile = function(x, y) return cellAt(x, y) % 1024 end,
                    elevation = function(x, y) return math.floor(cellAt(x, y) / 4096) % 16 end })
    deckTables[name] = out or false
    return out
  end
  --- (dev) A layout's bridge read afresh: its blocks (Bridge.blocks) and the curb's height, or nil.
  function Scene._bridgeBlocks(name)
    local L = World and World.layout(name)
    local io = L and bridgeIo(L)
    if not io then return nil end
    local br = Bridge.read(io, Bridge.BRIDGES[name])
    return Bridge.blocks(br, "cycling_road", nil), io.curb.height, br
  end
  function Scene._bridgeMesh(block, curbHeight) return Bridge.mesh(block, curbHeight) end
  --- (dev) One slice of a layout's bridge job (budget seconds; nil: to its end); `fresh` starts it
  --- over, the cache left unread ("cache": over, from the cache). Returns { done, cached, ms, error,
  --- running, models }.
  function Scene._bridgeJob(name, budget, fresh, watch)
    if watch ~= nil then Scene.bridgeWatch = watch or nil end
    if fresh then
      bridges[name] = nil
      local was = Scene.cacheModels
      if fresh ~= "cache" then Scene.cacheModels = false end
      bridgeJob(name)
      Scene.cacheModels = was
    end
    local st = bridgeStep(name, budget)
    return { done = st.done, cached = st.cached, ms = st.ms, error = st.error, running = st.co ~= nil,
             models = st.models and #st.models or 0, gaps = st.gaps }
  end

  -- a placement's ground: its metatile, the drawing laid on it over it (one image per kind)
  local bridgeGrounds = setmetatable({}, { __mode = "k" })
  -- ── rooms: their walls and furniture (src/scene/models/interiors.lua) ──
  local Interiors, RoomSpecs = deps.Interiors, deps.RoomSpecs
  -- the layouts a room reader reads: io.layout(name) -> Interiors.layoutOf's, or nil
  -- a layout no map is drawn with, which a script swaps into one (setmaplayoutindex): its cells
  -- from the engine's own baked layout (metatile, collision, elevation), or nil
  local function swappedBlocks(num, w, h)
    local Dataset, NativePack = req("src.core.game3.dataset"), req("src.import.gba.native_pack")
    local cache = Dataset and Dataset.cache()
    if not (cache and NativePack and NativePack.decodeMidLayout) then return nil end
    local root = "data/generated/gba/native"
    local src = cache:read(root .. "/layout_files.lua")
    local chunk = src and load(src, "=layout_files", "t", {})
    local okF, files = pcall(chunk or error)
    local key = okF and type(files) == "table" and files[num] or nil
    local blob = key and cache:read(root .. "/layouts/" .. key .. ".mid")
    local okD, d = pcall(NativePack.decodeMidLayout, blob)
    -- (its grid padded past the layout's own size; its collision the engine's own code: blocked
    -- or not is all a room reads of it)
    local tw, th = d and (d.trueWidth or d.width), d and (d.trueHeight or d.height)
    if not (okD and d and tw == w and th == h and d.width >= w and #d.cells >= d.width * h) then return nil end
    local blocks = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local c = d.cells[y * d.width + x + 1]
        blocks[y * w + x] = c.mid % 1024 + ((c.coll or 0) ~= 0 and 1024 or 0)
      end
    end
    return blocks
  end
  local bankManifests = {}
  local function roomIo()
    local cache = {}
    return { layout = function(name)
      if cache[name] ~= nil then return cache[name] or nil end
      cache[name] = false
      -- (a room nobody modelled by its number: "#61")
      local num = tonumber(tostring(name):match("^#(%d+)$"))
      num = num or RoomSpecs.ids and RoomSpecs.ids[name]
      local L = World and (num and World.layout(num) or World.layout(name))
      local blocks
      -- (a layout a script swaps into another's map: drawn with that map's tilesets)
      local over = RoomSpecs.swaps and RoomSpecs.swaps[name]
      if not L and over and num then
        L = World.layout(RoomSpecs.ids[over] or over)
        blocks = L and swappedBlocks(num, L.w, L.h)
        if not blocks then return nil end
      end
      local pair = L and World.pretArt(L)
      if not (L and pair and L.grid) then return nil end
      if not blocks then
        local grid = L.grid
        blocks = {}
        for i = 0, L.w * L.h - 1 do blocks[i] = grid:byte(i * 2 + 1) + grid:byte(i * 2 + 2) * 256 end
      end
      local A = Interiors.layoutOf({ name = name, w = L.w, h = L.h, blocks = blocks }, pair)
      A.enginePair = L.pair
      cache[name] = A
      return A
    end,
    -- a metatile's upper layer in each frame of its tile animation: the engine's baked banks,
    -- read off its files whether or not the field has the map bound (its manifest, then each
    -- frame's metatiles as 256 palette bytes, 0 clear)
    animOver = function(A, m)
      local pair = A.enginePair
      local Dataset = req("src.core.game3.dataset")
      local cache = Dataset and Dataset.cache()
      if not (pair and cache) then return nil end
      local root = "data/generated/gba/native/" .. pair .. "/"
      bankManifests[pair] = bankManifests[pair] or (function()
        local src = cache:read(root .. "anim_manifest.lua")
        local chunk = src and load(src, "=anim_manifest", "t", {})
        local ok, man = pcall(chunk or error)
        return ok and type(man) == "table" and man or false
      end)()
      local man = bankManifests[pair]
      for _, row in ipairs(man and man.banks or {}) do
        for k, mid in ipairs(row.overMids or {}) do
          if mid == m and row.overFile then
            local blob = cache:read(root .. row.overFile)
            local n = #row.overMids
            if not blob then return nil end
            local out = {}
            for f = 0, (row.frames or 1) - 1 do
              local base = (f * n + (k - 1)) * 256
              if #blob >= base + 256 then
                out[f] = function(x, y)
                  local b = blob:byte(base + y * 16 + x + 1)
                  if b == 0 then return nil end
                  return b
                end
              end
            end
            return out
          end
        end
      end
      return nil
    end }
  end
  -- (dev: the rooms read afresh, in order, up to and with `upto`: { { name, layout, pieces,
  -- error } }, and the registry of their pieces)
  function Scene._rooms(upto)
    if not (Interiors and RoomSpecs and World) then return nil end
    local io, reg, out = roomIo(), Interiors.registry(), {}
    for _, spec in ipairs(RoomSpecs) do
      local ok, pieces, err = pcall(Interiors.room, spec, io, reg)
      out[#out + 1] = { name = spec.name, layout = spec.interior.layout, pieces = ok and pieces or nil,
                        error = (not ok) and tostring(pieces) or err }
      if spec.name == upto then break end
    end
    return out, reg
  end
  function Scene._roomBuild(piece, bare) return Interiors.build(piece, bare) end

  -- the rooms read once a game, in their order, a slice a frame (warm), and kept in the model cache
  -- (Scene Cache): { co, ready (read, and the known furniture stood in every room nobody
  -- modelled: placeRooms may run), done (and cached), error, io, reg, pieces (every room's, in
  -- order), byId = { [layout id] = room layout name }, everywhere = { [layout id] = true },
  -- reusedPixels = { [layout key] = { [pixel] = true } }, models, bares, cached, ms }
  Scene.ROOM_SLICE = 0.004
  Scene.ROOMS_CACHE = 1        -- bumps when what the rooms build or how they are kept changes
  local roomRun

  -- ── the rooms' cache: rooms.index (every piece's facts and places, compressed Lua) and per room
  -- room_<name>.dat (its pieces' triangles and their textures' sizes) and room_<name>.rgba (the
  -- textures, one after another) ──
  local function packData(text)
    local ok, z = pcall(love.data.compress, "string", "zlib", text)
    if ok and z then return "Z" .. z end
    return "R" .. text
  end
  local function unpackData(blob)
    if not blob or #blob < 1 then return nil end
    local kind, body = blob:sub(1, 1), blob:sub(2)
    if kind == "R" then return body end
    if kind == "Z" then
      local ok, text = pcall(love.data.decompress, "string", "zlib", body)
      return ok and text or nil
    end
    return nil
  end
  -- a set of ints as runs: "start,length,..." (sorted)
  local function runsOfSet(set)
    local keys = {}
    for k in pairs(set or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local out, i = {}, 1
    while i <= #keys do
      local j = i
      while j < #keys and keys[j + 1] == keys[j] + 1 do j = j + 1 end
      out[#out + 1] = keys[i]
      out[#out + 1] = j - i + 1
      i = j + 1
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  local function setOfRuns(runs)
    local set = {}
    for i = 1, #runs, 2 do
      for k = runs[i], runs[i] + runs[i + 1] - 1 do set[k] = true end
    end
    return set
  end
  local function lit(v)
    local t = type(v)
    if t == "number" then
      if v == math.floor(v) and math.abs(v) < 2 ^ 52 then return ("%d"):format(v) end
      return ("%.17g"):format(v)
    elseif t == "string" then
      return ("%q"):format(v)
    elseif t == "boolean" then
      return tostring(v)
    elseif t == "table" then
      local parts, n = {}, #v
      for i = 1, n do parts[#parts + 1] = v[i] == nil and "false" or lit(v[i]) end
      for k, x in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
          parts[#parts + 1] = "[" .. lit(k) .. "]=" .. lit(x)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
  end
  -- the signature of the specs a cache was built from
  local function roomsSig()
    local names = {}
    for i, spec in ipairs(RoomSpecs or {}) do names[i] = spec.name .. "#" .. #spec.interior.pieces end
    local text = table.concat(names, ",")
    local ok, digest = pcall(love.data.hash, "md5", text)
    local hex = ok and digest and love.data.encode("string", "hex", digest) or tostring(#text)
    return ("rooms%d:%s"):format(Scene.ROOMS_CACHE, hex)
  end
  -- an image's RGBA bytes
  local function rgbaOf(img)
    local rows = {}
    local ch = string.char
    for y = 0, img.h - 1 do
      local row = {}
      for x = 0, img.w - 1 do
        local c = img.c[y * img.w + x]
        row[x + 1] = c and ch(math.floor(c / 65536), math.floor(c / 256) % 256, c % 256, 255) or "\0\0\0\0"
      end
      rows[y + 1] = table.concat(row)
    end
    return table.concat(rows)
  end
  -- a piece's facts for the index (its parts stay behind: the triangles are in its room's file)
  local function pieceFacts(pc)
    local patches
    if pc.placed_patches then
      patches = {}
      for key, list in pairs(pc.placed_patches) do
        local l = {}
        for n, p in ipairs(list) do
          local img = {}
          for k = 0, 255 do img[k + 1] = p[3][k] end
          l[n] = { p[1], p[2], img }
        end
        patches[key] = l
      end
    end
    local reused = {}
    for n, p in ipairs(pc.reused_at or {}) do reused[n] = { p[1], p[2], p[3], p[4] or false } end
    local owned
    if pc.owned then
      owned = {}
      for k in pairs(pc.owned) do owned[#owned + 1] = k end
      table.sort(owned)
    end
    local parts = { "{name=", lit(pc.name), ",room=", lit(pc.room), ",layout=", lit(pc.layout), ",rect=", lit(pc.rect),
                    ",ground=", lit(pc.ground), ",owned=", lit(owned), ",when=", lit(pc.when), ",placed=", lit(pc.placed),
                    ",patches=", lit(patches), ",reused_at=", lit(reused), ",bare_at=", lit(pc.bare_at) }
    if pc.bare_at then parts[#parts + 1] = ",own=" .. runsOfSet(pc.own) end
    parts[#parts + 1] = "}"
    return table.concat(parts)
  end
  local function writeRoomsCache(st, tick)
    local c = Scene.cacheModels and Scene.modelCache
    if not c then return end
    -- each room's pieces, built
    local byRoom, order = {}, {}
    for i, pc in ipairs(st.pieces) do
      if not byRoom[pc.room] then byRoom[pc.room] = {}; order[#order + 1] = pc.room end
      local l = byRoom[pc.room]
      l[#l + 1] = i
    end
    for _, room in ipairs(order) do
      local dat, rgba, off = { "return {" }, {}, 0
      for _, i in ipairs(byRoom[room]) do
        local pc = st.pieces[i]
        local entry = { "[", i, "]={" }
        for _, bare in ipairs(pc.bare_at and { false, true } or { false }) do
          local ok, built = pcall(Interiors.build, pc, bare)
          if ok then
            local tris = {}
            for _, t in ipairs(built.tris) do
              for k = 1, 3 do
                local p = t[k]
                tris[#tris + 1] = ("%.9g,%.9g,%.9g,%.9g,%.9g"):format(p[1], p[2], p[3], p[4], p[5])
              end
              tris[#tris + 1] = ("%.9g"):format(t.shade or 1)
            end
            local bytes = rgbaOf(built.art)
            rgba[#rgba + 1] = bytes
            entry[#entry + 1] = ("%s={w=%d,h=%d,off=%d,tris={%s}},"):format(bare and "bare" or "main", built.art.w,
              built.art.h, off, table.concat(tris, ","))
            off = off + #bytes
          end
          tick("cache " .. pc.name)
        end
        entry[#entry + 1] = "},"
        dat[#dat + 1] = table.concat(entry)
      end
      dat[#dat + 1] = "}"
      c.write("room_" .. room .. ".dat", packData(table.concat(dat)))
      c.write("room_" .. room .. ".rgba", packData(table.concat(rgba)))
      tick("cache write " .. room)
    end
    -- the index, last: a cache is whole once it is there
    local idx = { "return {sig=", lit(roomsSig()), ",pieces={" }
    for _, pc in ipairs(st.pieces) do idx[#idx + 1] = pieceFacts(pc) .. "," end
    idx[#idx + 1] = "},reused={"
    for key, set in pairs(st.reg.reusedPixels) do idx[#idx + 1] = "[" .. lit(key) .. "]=" .. runsOfSet(set) .. "," end
    idx[#idx + 1] = "}}"
    c.write("rooms.index", packData(table.concat(idx)))
  end
  local function readRoomsCache(st)
    local c = Scene.cacheModels and Scene.modelCache
    local text = c and unpackData(c.read("rooms.index"))
    if not text then return false end
    local chunk = load(text, "=rooms.index", "t", {})
    local ok, idx = pcall(chunk or error)
    if not (ok and type(idx) == "table" and idx.sig == roomsSig()) then return false end
    for i, f in ipairs(idx.pieces) do
      local pc = { name = f.name, room = f.room, layout = f.layout, rect = f.rect, ground = f.ground, when = f.when,
                   placed = f.placed, bare_at = f.bare_at, idx = i }
      if f.owned then
        pc.owned = {}
        for _, k in ipairs(f.owned) do pc.owned[k] = true end
      end
      if f.patches then
        pc.placed_patches = {}
        for key, list in pairs(f.patches) do
          local l = {}
          for n, p in ipairs(list) do
            local img = {}
            for k = 0, 255 do img[k] = p[3][k + 1] end
            l[n] = { p[1], p[2], img }
          end
          pc.placed_patches[key] = l
        end
      end
      if f.reused_at and #f.reused_at > 0 then
        pc.reused_at = {}
        for n, p in ipairs(f.reused_at) do pc.reused_at[n] = { p[1], p[2], p[3], p[4] or nil } end
      end
      if f.own then pc.own = setOfRuns(f.own) end
      st.pieces[i] = pc
    end
    st.reusedPixels = {}
    for key, runs in pairs(idx.reused or {}) do st.reusedPixels[key] = setOfRuns(runs) end
    return true
  end
  -- a room's file, read once: { [piece index] = { main = { w, h, off, tris }, bare = ... } }, rgba
  local function cachedRoom(st, room)
    st.roomFiles = st.roomFiles or {}
    local hit = st.roomFiles[room]
    if hit ~= nil then return hit or nil end
    st.roomFiles[room] = false
    local c = Scene.modelCache
    local text = c and unpackData(c.read("room_" .. room .. ".dat"))
    local rgba = c and unpackData(c.read("room_" .. room .. ".rgba"))
    local chunk = text and load(text, "=room", "t", {})
    local ok, dat = pcall(chunk or error)
    if not (ok and type(dat) == "table" and rgba) then return nil end
    hit = { dat = dat, rgba = rgba }
    st.roomFiles[room] = hit
    return hit
  end

  local function roomJob()
    if roomRun then return roomRun end
    local st = { pieces = {}, byId = {}, everywhere = {}, models = {}, bares = {}, errors = {} }
    roomRun = st
    if not (Interiors and RoomSpecs and World) then st.error = "no rooms"; return st end
    local clock = love.timer and love.timer.getTime or os.clock
    st.t0 = clock()
    st.io = roomIo()
    for _, spec in ipairs(RoomSpecs) do
      local name = spec.interior.layout
      local num = RoomSpecs.ids and RoomSpecs.ids[name]
      local L = num and World.layout(num) or World.layout(name)
      if L and L.id and not st.byId[L.id] then st.byId[L.id] = name end
    end
    local okC, hit = false, false
    if not Scene.roomsBuildAfresh then okC, hit = pcall(readRoomsCache, st) end
    if okC and hit then
      st.cached, st.ready, st.done, st.all = true, true, true, true
      st.ms = math.floor((clock() - st.t0) * 1000 + 0.5)
      return st
    end
    st.pieces = {}
    st.reg = Interiors.registry()
    st.reusedPixels = st.reg.reusedPixels
    local function tick(label)
      local t = clock()
      -- (dev: Scene.roomsWatch = seconds; every longer stretch between two ticks, with their labels)
      if Scene.roomsWatch then
        if st.lastTick and t - st.lastTick > Scene.roomsWatch then
          st.gaps = st.gaps or {}
          st.gaps[#st.gaps + 1] = ("%.0f ms %s -> %s"):format((t - st.lastTick) * 1000, tostring(st.lastLabel),
            tostring(label))
        end
        st.lastTick, st.lastLabel = t, label
      end
      if st.budget and t - st.sliceStart > st.budget then
        coroutine.yield()
        st.lastTick = clock()
      end
    end
    st.co = coroutine.create(function()
      for _, spec in ipairs(RoomSpecs) do
        local ok, pieces, err = pcall(Interiors.room, spec, st.io, st.reg, tick)
        if ok and pieces then
          for _, pc in ipairs(pieces) do
            pc.room = spec.name
            st.pieces[#st.pieces + 1] = pc
            pc.idx = #st.pieces
          end
        else
          st.errors[#st.errors + 1] = spec.name .. ": " .. tostring(ok and err or pieces)
        end
        tick("room " .. spec.name)
      end
      -- the known furniture in every indoor room nobody modelled (reuse_everywhere), in the
      -- layouts' order
      for _, id in ipairs(World.layoutIds and World.layoutIds() or {}) do
        local L = World.layout(id)
        if L and not L.outdoor and not st.byId[id] and not st.everywhere[id] then
          st.everywhere[id] = true
          local A = st.io.layout("#" .. id)
          if A then pcall(Interiors.placeReused, st.reg, st.io, A, nil, nil, tick) end
          tick("everywhere " .. id)
        end
      end
      st.all = true
      st.ready = true
      st.ms = math.floor((clock() - st.t0) * 1000 + 0.5)
      coroutine.yield()
      -- and kept: the next game's battles read it back
      local okW, err = pcall(writeRoomsCache, st, tick)
      if not okW then st.errors[#st.errors + 1] = "cache: " .. tostring(err) end
    end)
    return st
  end
  local function roomStep(budget, untilReady)
    local st = roomJob()
    local clock = love.timer and love.timer.getTime or os.clock
    while st.co do
      if untilReady and st.ready then break end
      st.budget, st.sliceStart = budget, clock()
      local ok, err = coroutine.resume(st.co)
      if not ok then
        st.error, st.co = tostring(err), nil
      elseif coroutine.status(st.co) == "dead" then
        st.co, st.done = nil, true
      end
      if budget then break end
    end
    return st
  end
  -- (dev: the rooms' job, afresh with `fresh`, run a slice of `budget` seconds: its state)
  function Scene._roomsJob(budget, fresh, watch)
    if fresh then roomRun = nil end
    -- (fresh = "build": not read back from the cache)
    Scene.roomsBuildAfresh = fresh == "build" or (not fresh and Scene.roomsBuildAfresh) or nil
    if watch then Scene.roomsWatch = watch end
    return roomStep(budget)
  end
  --- The rooms read, now if they are not yet (the cache is written later, in the warm-up): the
  --- job's state, or nil and why.
  function Scene.rooms()
    local st = roomStep(nil, true)
    if st.ready then return st end
    return nil, st.error
  end

  -- a piece's model (its bare twin with `bare`), made once: off the cache, or built
  local function roomModel(st, pc, bare)
    local cache = bare and st.bares or st.models
    if cache[pc] ~= nil then return cache[pc] or nil end
    cache[pc] = false
    local tris, art, image, texW, texH
    if st.cached then
      local file = cachedRoom(st, pc.room)
      local e = file and file.dat[pc.idx]
      e = e and (bare and e.bare or e.main)
      if not e then return nil end
      texW, texH = e.w, e.h
      local bytes = file.rgba:sub(e.off + 1, e.off + texW * texH * 4)
      local okI, data = pcall(love.image.newImageData, texW, texH, "rgba8", bytes)
      if not okI then return nil end
      local okG, img = pcall(G.newImage, data)
      if not okG then return nil end
      img:setFilter("nearest", "nearest")
      image = img
      tris = {}
      local f = e.tris
      for i = 1, #f, 16 do
        tris[#tris + 1] = { { f[i], f[i + 1], f[i + 2], f[i + 3], f[i + 4] },
                            { f[i + 5], f[i + 6], f[i + 7], f[i + 8], f[i + 9] },
                            { f[i + 10], f[i + 11], f[i + 12], f[i + 13], f[i + 14] }, shade = f[i + 15] }
      end
      -- (its drawing, for the floor laid round it: drawn wherever a texel is)
      art = { w = texW, h = texH, c = {} }
      for k = 0, texW * texH - 1 do
        if bytes:byte(k * 4 + 4) > 0 then art.c[k] = true end
      end
    else
      local ok, built = pcall(Interiors.build, pc, bare)
      if not ok then
        hd.stats.sceneRoomError = pc.name .. ": " .. tostring(built)
        return nil
      end
      local tex = built.tex
      image = imageOf(tex.w, tex.h, function(data)
        local px = tex.px
        for y = 0, tex.h - 1 do
          for x = 0, tex.w - 1 do
            local o = (y * tex.w + x) * 4
            data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
          end
        end
      end)
      if not image then return nil end
      tris, art, texW, texH = built.tris, built.art, tex.w, tex.h
    end
    local md = { spec = { name = pc.name .. (bare and "_bare" or ""), owned = pc.owned }, piece = pc,
                 ref = { w = pc.rect[3], h = pc.rect[4], template = {} }, core = { { 0, 0 } }, tris = tris,
                 image = image, texW = texW, texH = texH, primaryOnly = true, art = art, room = true }
    cache[pc] = md
    return md
  end

  -- the rooms' pieces standing in the window's layouts (find_placements for a room's piece): at
  -- its own place in its own room (or one drawn cell for cell the same), where its room was found
  -- to repeat it, and in a room nobody modelled wherever its tiles are drawn again - each on its
  -- room's floor, or there on that room's commonest floor with the room's own paint laid over it
  local function placeRooms(grid, found, where)
    hd.stats.sceneRooms, hd.stats.sceneRoomError = nil, nil
    local layouts, order = {}, {}
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.mid then
          local _, lx, ly, id = where(c.cx, c.cy)
          local L = id and World.layout(id)
          if L and L.id and not L.outdoor then
            local e = layouts[L.id]
            if not e then e = { L = L, at = {} }; layouts[L.id] = e; order[#order + 1] = L.id end
            e.at[ly * 4096 + lx] = c
          end
        end
      end
    end
    if #order == 0 then return end
    local st, why = Scene.rooms()
    if not st then hd.stats.sceneRoomError = tostring(why); return end
    local placed = 0
    for _, lid in ipairs(order) do
      local e = layouts[lid]
      local name = st.byId[lid]
      local layoutA = st.io.layout(name or ("#" .. lid))
      if layoutA then
        -- (a layout drawn cell for cell as a modelled room stands that room's own pieces too)
        local sameAs
        if not name then
          for _, n2 in pairs(st.byId) do
            local other = st.io.layout(n2)
            if other and other.w == layoutA.w and other.h == layoutA.h then
              local same = true
              for k = 0, other.w * other.h - 1 do
                if other.blocks[k] % 1024 ~= layoutA.blocks[k] % 1024 then same = false; break end
              end
              if same then sameAs = n2; break end
            end
          end
        end
        -- (a map a script has swapped another layout into, its cells now that layout's: that room)
        if name and RoomSpecs.swaps then
          local function misses(A)
            local n = 0
            for k, c in pairs(e.at) do
              local lx, ly = k % 4096, math.floor(k / 4096)
              if lx < A.w and ly < A.h and c.mid ~= A.blocks[ly * A.w + lx] % 1024 then n = n + 1 end
            end
            return n
          end
          local here = misses(layoutA)
          for swapName, base in pairs(RoomSpecs.swaps) do
            if base == name and here > 0 then
              local S = st.io.layout(swapName)
              if S and S.w == layoutA.w and S.h == layoutA.h and misses(S) < here then
                name, layoutA, here = swapName, S, misses(S)
              end
            end
          end
        end
        local key = name or layoutA.id
        local own = name or sameAs
        if not name and not st.all and not st.everywhere[lid] then
          st.everywhere[lid] = true
          pcall(Interiors.placeReused, st.reg, st.io, layoutA, nil)
        end
        -- { piece, x, y, ground (nil: the room's commonest floor, its paint over every cell), bare }
        local list = {}
        for _, pc in ipairs(st.pieces) do
          if pc.placed then
            for _, p in ipairs(name and pc.placed or {}) do
              if p[1] == name then list[#list + 1] = { pc, p[2], p[3], p[4], false, pc.placed_patches } end
            end
          elseif own and pc.layout == own then
            list[#list + 1] = { pc, pc.rect[1], pc.rect[2], pc.ground[1], false }
          end
          for _, p in ipairs(pc.reused_at or {}) do
            if p[1] == key then list[#list + 1] = { pc, p[2], p[3], p[4], false } end
          end
          for _, p in ipairs(pc.bare_at or {}) do
            if p[1] == key then list[#list + 1] = { pc, p[2], p[3], nil, true } end
          end
        end
        -- (the room's commonest floor: its cells free of collision, the first most common)
        local commonFloor
        do
          local n, firstAt, best, bn = {}, {}, nil, nil
          for k = 0, layoutA.w * layoutA.h - 1 do
            local cell = layoutA.blocks[k]
            if math.floor(cell / 1024) % 4 == 0 then
              local m = cell % 1024
              if not n[m] then n[m] = 0; firstAt[#firstAt + 1] = m end
              n[m] = n[m] + 1
            end
          end
          for _, m in ipairs(firstAt) do
            if bn == nil or n[m] > bn then best, bn = m, n[m] end
          end
          commonFloor = best
        end
        local others = st.reusedPixels and st.reusedPixels[key] or {}
        local RW = layoutA.w * 16
        -- (a room read once for each state of its doors finds another room's piece once for each:
        -- the same model on the same spot stands once)
        local seen = {}
        for _, item in ipairs(list) do
          local pc, px, py, g, bare, patches = item[1], item[2], item[3], item[4], item[5], item[6]
          local w, h = pc.rect[3], pc.rect[4]
          local once = tostring(pc) .. (bare and "b" or "") .. ":" .. px .. ":" .. py
          local stands = not seen[once]
          seen[once] = true
          if stands and pc.when then
            local wc = e.at[(py + pc.when[2]) * 4096 + px + pc.when[1]]
            stands = wc ~= nil and wc.mid == pc.when[3]
          end
          local md = stands and roomModel(st, pc, bare) or nil
          local anchor = e.at[py * 4096 + px]
          if md and anchor then
            local pl = { model = md, cx = anchor.cx, cy = anchor.cy }
            -- (pieces of a room share cells - a Poke Ball on the counter: the first one's lays the
            -- floor; nothing else may stand there)
            local free = true
            for j = 0, h - 1 do
              for i = 0, w - 1 do
                local c = e.at[(py + j) * 4096 + px + i]
                if c and c.model and not c.model.model.room and (not pc.owned or pc.owned[i .. "," .. j]) then
                  free = false
                end
              end
            end
            if free then
              local patchAll = g == nil
              local floorMid = g or commonFloor
              local tops = Buildings.tops(md)
              for j = 0, h - 1 do
                for i = 0, w - 1 do
                  if not pc.owned or pc.owned[i .. "," .. j] then
                    local c = e.at[(py + j) * 4096 + px + i]
                    if c then
                      if not c.model then c.model = pl end
                      c.top = math.max(c.top or 0, tops[i .. "," .. j] or 0)
                    end
                  end
                end
              end
              local cellPatch = {}
              for _, p in ipairs(patches and patches[px .. "," .. py] or {}) do cellPatch[p[2] * 256 + p[1]] = p[3] end
              local art, own = md.art, bare and pc.own or nil
              pl.ground = imageOf(w * 16, h * 16, function(data)
                for j = 0, h - 1 do
                  for i = 0, w - 1 do
                    local base = floorMid and layoutA.cellImage(floorMid)
                    local patch = cellPatch[j * 256 + i]
                    local mapCell = patchAll and py + j < layoutA.h and px + i < layoutA.w
                      and layoutA.cellImage(layoutA.metatile(px + i, py + j)) or nil
                    for y = 0, 15 do
                      for x = 0, 15 do
                        local col = base and base[y * 16 + x]
                        if patch then col = patch[y * 16 + x] end
                        if mapCell then
                          local X, Y = i * 16 + x, j * 16 + y
                          local drawn
                          if own then drawn = own[Y * 4096 + X] else drawn = art.c[Y * art.w + X] ~= nil end
                          if not drawn and not others[((py + j) * 16 + y) * RW + (px + i) * 16 + x] then
                            col = mapCell[y * 16 + x]
                          end
                        end
                        if col then
                          data:setPixel(i * 16 + x, j * 16 + y, math.floor(col / 65536) / 255,
                            math.floor(col / 256) % 256 / 255, col % 256 / 255, 1)
                        end
                      end
                    end
                  end
                end
              end)
              found[#found + 1] = pl
              placed = placed + 1
            end
          end
        end
        hd.stats.sceneRooms = ("%s: %d pieces%s"):format(tostring(name or layoutA.id), placed,
          st.cached and ", from the cache" or "")
      end
    end
    if #st.errors > 0 then hd.stats.sceneRoomError = table.concat(st.errors, "; ") end
  end

  local function bridgeGround(md, src)
    local per = bridgeGrounds[src]
    if not per then per = {}; bridgeGrounds[src] = per end
    local img = per[md]
    if img ~= nil then return img or nil end
    img = imageOf(16, 16, function(data)
      for y = 0, 15 do
        for x = 0, 15 do
          local c = md.patch and md.patch[y * 16 + x]
          local r, g, b
          if c then
            r, g, b = math.floor(c / 65536) / 255, math.floor(c / 256) % 256 / 255, c % 256 / 255
          else
            r, g, b = src.under(md.groundMid, x, y)
            local r1, g1, b1, a1 = src.over(md.groundMid, x, y)
            if a1 and a1 > 0.5 then r, g, b = r1, g1, b1 end
          end
          if r then data:setPixel(x, y, r, g, b, 1) end
        end
      end
    end)
    per[md] = img or false
    return img
  end

  -- the bridges of the maps the window shows: every cell of one that has a block stands it
  local function placeBridges(grid, NativeTileset, found, where)
    hd.stats.sceneBridge, hd.stats.sceneBridgeError = nil, nil
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.mid and not c.model then
          local _, lx, ly, id = where(c.cx, c.cy)
          local L = id and World.layout(id)
          if L and L.name and Scene.hasBridge(L.name) then
            local st, why = Scene.bridge(L.name)
            if not st then
              hd.stats.sceneBridgeError = L.name .. ": " .. tostring(why)
            else
              hd.stats.sceneBridge = ("%s: %d models%s"):format(L.name, #st.models,
                st.cached and ", from the cache" or (st.ms and (", built in " .. st.ms .. " ms") or ""))
              local md = st.at[ly * 4096 + lx]
              local src = md and pixelSource(NativeTileset, c.pair)
              if md and src then
                local pl = { model = md, cx = c.cx, cy = c.cy, ground = bridgeGround(md, src) }
                c.model = pl
                c.top = md.tops["0,0"]
                found[#found + 1] = pl
              end
            end
          end
        end
      end
    end
  end

  -- a pair that draws metatile m (of the given primary): a fence's reference metatile, which the
  -- run's own pair may not hold
  local refPairs
  local function refSource(NativeTileset, pair, m)
    local own = pixelSource(NativeTileset, pair)
    if own and own.ts.midToSlot[m] then return own end
    local primary = Components.names(pair)
    if not refPairs then
      refPairs = {}
      local Runtime = req("src.core.game3.runtime")
      local game = Runtime and Runtime._game
      local seenP = {}
      for _, def in pairs(game and game.data and game.data.maps or {}) do
        local p = type(def) == "table" and rawget(def, "pair")
        if type(p) == "string" and not seenP[p] then seenP[p] = true; refPairs[#refPairs + 1] = p end
      end
      table.sort(refPairs)
    end
    for _, p in ipairs(refPairs) do
      if Components.names(p) == primary then
        local s = pixelSource(NativeTileset, p)
        if s and s.ts.midToSlot[m] then return s end
      end
    end
    return nil
  end

  -- a layout as Buildings.groundPlan reads it (the map a placement stands in): its cells off the
  -- cache, the metatiles it paints and those it paints beside themselves, its water, its cells'
  -- colours as pret draws them; nil without the World's data. Read once per layout.
  local groundMaps = setmetatable({}, { __mode = "k" })
  local rawWater
  local function waterBehaviours()
    if rawWater then return rawWater end
    rawWater = {}
    local Constants = req("src.core.game3.constants")
    local ok, em = pcall(function() return Constants.of("emerald").metatile_behaviors.byName end)
    for _, n in ipairs(deps.Roles and deps.Roles.WATER_NAMES or {}) do
      local v = ok and em and em[n]
      if v then rawWater[v] = true end
    end
    return rawWater
  end
  local function groundMap(L)
    local G = groundMaps[L]
    if G ~= nil then return G or nil end
    groundMaps[L] = false
    local P = World and World.pretArt(L)
    if not (P and L.grid and L.w and L.h) then return nil end
    local grid, W, N = L.grid, L.w, L.w * L.h
    local blocks, painted, across, down = {}, {}, {}, {}
    for k = 0, N - 1 do
      local b = grid:byte(k * 2 + 1) + grid:byte(k * 2 + 2) * 256
      blocks[k] = b
      painted[b % 1024] = true
    end
    for k = 0, N - 1 do
      local m = blocks[k] % 1024
      if (k + 1) % W ~= 0 and k + 1 < N and blocks[k + 1] % 1024 == m then across[m] = true end
      if k + W < N and blocks[k + W] % 1024 == m then down[m] = true end
    end
    local seamless = {}
    for m in pairs(across) do
      if down[m] then seamless[m] = true end
    end
    local water = waterBehaviours()
    G = { id = L.name, w = W, h = L.h, painted = painted, seamless = seamless, P = P,
          block = function(x, y) return blocks[y * W + x] end,
          water = function(m) return water[P.attribute(m) % 256] == true end,
          rgb = function(m) return P.entries(m) and P.cellImage(m) or nil end }
    groundMaps[L] = G
    return G
  end
  -- the map a placement stands in, for Buildings.groundPlan: `cell` one of its cells in the grid,
  -- (i, j) that cell's place in the model's rectangle
  local function groundCtx(md, cell, i, j, where)
    if not (where and World and cell) or Scene.groundPlanOff then return nil end
    local _, lx, ly, id = where(cell.cx, cell.cy)
    local L = id and World.layout(id)
    local G = L and groundMap(L)
    if not G then return nil end
    -- (a spec ground that is water in the reference's own tilesets)
    local RL = md.spec.layout and World.layout(md.spec.layout) or L
    local RP = RL and World.pretArt(RL)
    local water, groundWater = waterBehaviours(), false
    for _, g in ipairs(RP and md.spec.ground or {}) do
      if water[RP.attribute(g) % 256] then groundWater = true end
    end
    return setmetatable({ px = lx - i, py = ly - j, groundWater = groundWater, odd = md.ref.template ~= nil,
                          refP = RP }, { __index = G })
  end

  -- the runs of hedges, fences, curbs and railings in the grid, each its own model, added to
  -- `found` (their cells marked as a building's are)
  -- the map's pixels (X, Y) the buildings whose reference copy it holds keep (their owned cells, or
  -- with `keep` only those rectangles of them), by layout: { [Y * 65536 + X] = true }
  local keptOf = {}
  local function keptPixels(mapId)
    local L = World and World.layout(mapId)
    local name = L and L.name
    if not name then return nil end
    if keptOf[name] then return keptOf[name] end
    local out = {}
    for _, s in ipairs(Specs or {}) do
      if s.layout == name and s.rect then
        local x, y, w, h = s.rect[1], s.rect[2], s.rect[3], s.rect[4]
        for _, r in ipairs(s.keep or { { 0, 0, w * 16, h * 16 } }) do
          for v = r[2], r[4] - 1 do
            for u = r[1], r[3] - 1 do
              if Buildings.owns(s, math.floor(u / 16), math.floor(v / 16)) then
                out[(y * 16 + v) * 65536 + x * 16 + u] = true
              end
            end
          end
        end
      end
    end
    keptOf[name] = out
    return out
  end

  function placeComponents(grid, NativeTileset, found, where)
    -- (a spec's blocks aligned on the run's own map)
    local runs = Components.find(grid, nil, where and function(cx, cy)
      local _, lx, ly = where(cx, cy)
      return lx, ly
    end)
    local report = {}
    local mid = function(x, y) local c = grid.at(x, y); return c and c.mid end
    -- identical blocks (the same cells round them, the same seams): one model, placed at each
    local made = {}
    local function blockKey(run)
      local k = { run.spec.name, run.pair, run.w, run.h }
      for y = run.y0 - 1, run.y0 + run.h do
        for x = run.x0 - 1, run.x0 + run.w do k[#k + 1] = mid(x, y) or -1 end
      end
      for j = 0, run.h - 1 do
        for i = 0, run.w - 1 do k[#k + 1] = run.owned[i .. "," .. j] and 1 or 0 end
      end
      for _, c in ipairs(run.south or {}) do k[#k + 1] = "s" .. c[1] .. "," .. c[2] end
      for _, c in ipairs(run.north or {}) do k[#k + 1] = "n" .. c[1] .. "," .. c[2] end
      for j = 0, run.h - 1 do
        k[#k + 1] = ((run.east or {})[j] and "e" or "") .. ((run.west or {})[j] and "w" or "")
      end
      if run.kept then k[#k + 1] = "kept@" .. run.x0 .. "," .. run.y0 end
      return table.concat(k, ":")
    end
    for _, run in ipairs(runs) do
      local src = pixelSource(NativeTileset, run.pair)
      -- (its art off its map's two layers as pret composes them, as the buildings' is: a COVERED
      -- metatile's lower layer whole)
      local c1 = run.cells[1]
      local mapId, mx, my
      if c1 and where then
        local _, lx, ly, id = where(c1.cx, c1.cy)
        mapId, mx, my = id, lx and c1.cx - lx, ly and c1.cy - ly
      end
      -- (the map's pixels its own buildings keep, gen_voxel_buildings.kept_by_others: a fence
      -- through the Game Corner's corner leaves its wall to it; grid pixels in)
      if run.spec.posts and mapId and mx then
        local kept = keptPixels(mapId)
        local function at(gx, gy) return kept[(gy - my * 16) * 65536 + (gx - mx * 16)] == true end
        -- (only a block some of whose pixels another model keeps: built where it stands)
        for v = 0, (run.h + 2) * 16 - 1 do
          for u = 0, run.w * 16 - 1 do
            if kept and not run.kept and at(run.x0 * 16 + u, (run.y0 - 1) * 16 + v) then run.kept = at end
          end
        end
      end
      local artSrc = src and mapId and layerSource(mapId, src) or src
      local key = blockKey(run)
      local md = made[key]
      if md == nil then
        md = false
        local okB, built = pcall(function()
          -- (a fence's reference post read the same way: its colours are matched to the art's)
          return artSrc and Components.build(run, artSrc, mid, function(m)
            local rs = refSource(NativeTileset, run.pair, m)
            return rs and mapId and layerSource(mapId, rs) or rs
          end)
        end)
        if not okB then
          hd.stats.sceneBuildingError = run.spec.name .. ": " .. tostring(built)
          built = nil
        end
        if built then
          local okM, mesh = pcall(Kernel.build, built.parts)
          if not okM then hd.stats.sceneBuildingError = run.spec.name .. ": " .. tostring(mesh) end
          report[#report + 1] = run.spec.name .. ":" .. (okM and #mesh.tris or -1)
          if okM and #mesh.tris > 0 then
            local art = built.art
            md = { spec = { name = run.spec.name, owned = run.owned, ground = run.spec.ground,
                            patch_own = run.spec.patch_own, ground_fixed = run.spec.ground_fixed,
                            relief_upper = run.spec.upper, component = true },
                   ref = { w = run.w, h = run.h, pair = run.pair }, art = art, texW = art.w, texH = art.h,
                   tris = mesh.tris, component = run.spec }
            md.image = imageOf(art.w, art.h, function(data)
              local px = art.px
              for y = 0, art.h - 1 do
                for x = 0, art.w - 1 do
                  local o = (y * art.w + x) * 4
                  data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
                end
              end
            end)
          end
        else
          report[#report + 1] = run.spec.name .. ":none"
        end
        made[key] = md
      end
      if md then
        local art = md.art
        local pl = { model = md, cx = run.x0, cy = run.y0 }
        -- its ground as Emerald 3DS lays it (Buildings.groundPlan); without the World's data,
        -- the ground metatile under the model and the map's own drawing round it
        local gctx = c1 and groundCtx(md, c1, c1.cx - run.x0, c1.cy - run.y0, where)
        local plan = gctx and Buildings.groundPlan(md, gctx)
        pl.plan = plan
        local g
        if plan then g = plan.ground
        else g = Buildings.groundOf(grid, pl, function(m) return src.ts.midToSlot[m] ~= nil end) end
        -- (a cell a building stands on stays the building's: the first placement keeps it,
        -- voxel_building.c CellGridOf)
        for _, c in ipairs(run.cells) do
          if not c.model then
            c.model = pl
            c.top = Buildings.tops(md)[(c.cx - run.x0) .. "," .. (c.cy - run.y0)] or 0
          end
        end
        pl.ground = imageOf(run.w * 16, run.h * 16, function(data)
          for _, c in ipairs(run.cells) do
            local i, j = c.cx - run.x0, c.cy - run.y0
            local k = j * run.w + i
            local whole = plan and plan.chosen[k]
            local patched = plan and plan.patched[k]
            for y = 0, 15 do
              for x = 0, 15 do
                local X, Y = i * 16 + x, j * 16 + y
                local covered = art.px[(Y * art.w + X) * 4 + 4] >= 0.5
                local r, gg, b
                if plan then
                  -- (the ground metatile, the map's paint over it where the model draws nothing
                  -- in a patched cell, or a ground of the spec's choosing whole)
                  local m = whole or (patched and not covered and c.mid) or g
                  if m then
                    r, gg, b = src.under(m, x, y)
                    local r1, g1, b1, a1 = src.over(m, x, y)
                    if a1 and a1 > 0.5 then r, gg, b = r1, g1, b1 end
                  end
                elseif covered and not run.spec.upper and g then
                  r, gg, b = src.under(g, x, y)
                  local r1, g1, b1, a1 = src.over(g, x, y)
                  if a1 and a1 > 0.5 then r, gg, b = r1, g1, b1 end
                else
                  r, gg, b = src.under(c.mid, x, y)
                  local r1, g1, b1, a1 = src.over(c.mid, x, y)
                  if not covered and a1 and a1 > 0.5 then r, gg, b = r1, g1, b1 end
                end
                if r then data:setPixel(X, Y, r, gg, b, 1) end
              end
            end
          end
        end)
        found[#found + 1] = pl
      end
    end
    hd.stats.sceneRuns = #runs .. " " .. table.concat(report, " ")
  end

  -- (a town's own metatile drawing the pixels the model owns in that cell stands for it: all but
  -- an eighth of them, the bits of ground drawn round a corner - Rustboro's paving where the
  -- reference town has grass)
  local mf = math.floor
  local key5 = function(r, g, b) return mf(r * 31 + 0.5) * 1024 + mf(g * 31 + 0.5) * 32 + mf(b * 31 + 0.5) end
  -- (and a signpost's drawing - a sign's cell, or the cell north of it its head tops - is asked
  -- its lower layer alone, as Emerald 3DS's same_building_pixels asks it: the sign stands in
  -- front of the building with a height of its own. Lavaridge's gym sign tops the gym's corner.
  -- The exact lower layer comes off the atlas blobs, src/scene/world.lua: the engine's lower
  -- atlas has a COVERED metatile's upper layer drawn over it)
  local function alikeOf(NativeTileset, signCell)
    return function(md, cell, i, j)
      local src = pixelSource(NativeTileset, cell.pair)
      if not src or src.under(cell.mid, 0, 0) == nil then return false end
      local art = md.art
      local lower
      if signCell and World and signCell(cell) then
        local wa = World.art(cell.pair)
        lower = wa and wa.pixels(cell.mid, 0) or nil
      end
      local owned, bad = 0, 0
      for y = 0, 15 do
        for x = 0, 15 do
          local o = ((j * 16 + y) * art.w + i * 16 + x) * 4
          if art.px[o + 4] >= 0.5 then
            owned = owned + 1
            local r, g, b, a
            if lower then
              local p = lower[y * 16 + x]
              if p then
                r, g, b = p[1] / 255, p[2] / 255, p[3] / 255
              else
                -- (a colour-index-0 pixel the blobs keep no colour for: the lower atlas where
                -- nothing is drawn over it; under the sign's pixels, not asked)
                local _, _, _, a1 = src.over(cell.mid, x, y)
                if a1 and a1 > 0.5 then owned = owned - 1; r = false else r, g, b = src.under(cell.mid, x, y) end
              end
            else
              r, g, b, a = src.over(cell.mid, x, y)
              if not (a and a > 0.5) then r, g, b = src.under(cell.mid, x, y) end
            end
            if r ~= false and (not r or key5(r, g, b) ~= key5(art.px[o + 1], art.px[o + 2], art.px[o + 3])) then
              bad = bad + 1
              if bad > 32 then return false end
            end
          end
        end
      end
      return owned > 0 and bad * 8 <= owned
    end
  end
  -- the buildings standing in the grid: placements, their cells marked (cell.model)
  local function placeBuildings(grid, NativeTileset, signCell, where)
    if not (Buildings and Kernel and Specs) then return {} end
    local ctx = layoutCtx()
    local mids = {}
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.mid then mids[c.mid] = true end
      end
    end
    -- only the specs one of whose cells the window draws are read at all
    local models = {}
    for _, spec in ipairs(Specs) do
      local ref = Buildings.reference(spec, ctx)
      local seen = false
      if ref then
        for _, m in ipairs(ref.template) do
          if mids[m] then seen = true; break end
        end
      end
      if seen then
        local md = ready(spec, NativeTileset, ctx)
        if md then models[#models + 1] = md end
      end
    end
    local found = Buildings.find(grid, models, alikeOf(NativeTileset, signCell), where and function(cx, cy)
      local _, lx, ly = where(cx, cy)
      return lx, ly
    end)
    -- the kits' blocks (Rustboro's), each modelled from its own drawing where it stands
    local secondaryOf = function(pair)
      if not Components then return nil end
      local _, sec = Components.names(pair)
      return sec
    end
    for _, k in ipairs(Components and Buildings.kits(grid, Specs.kits, secondaryOf) or {}) do
      local spec = k.spec
      local w, h = spec.rect[3], spec.rect[4]
      local anchor = grid.at(k.cx, k.cy)
      local src = anchor and pixelSource(NativeTileset, anchor.pair)
      local okM, mesh = pcall(Kernel.build, spec.parts())
      if src and okM then
        local t = {}
        for j = 0, h - 1 do
          for i = 0, w - 1 do
            local c = grid.at(k.cx + i, k.cy + j)
            t[j * w + i + 1] = c and c.mid or -1
          end
        end
        local ref = { template = t, pair = anchor.pair, w = w, h = h }
        local art = Buildings.art(spec, ref, src)
        local md = { spec = spec, ref = ref, art = art, core = { { 0, 0 } }, tris = mesh.tris }
        md.image = imageOf(art.w, art.h, function(data)
          local px = art.px
          for y = 0, art.h - 1 do
            for x = 0, art.w - 1 do
              local o = (y * art.w + x) * 4
              data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
            end
          end
        end)
        found[#found + 1] = { model = md, cx = k.cx, cy = k.cy }
      end
    end
    for _, pl in ipairs(found) do
      local md = pl.model
      local w, h = md.ref.w, md.ref.h
      for j = 0, h - 1 do
        for i = 0, w - 1 do
          if not md.spec.owned or md.spec.owned[i .. "," .. j] then
            local c = grid.at(pl.cx + i, pl.cy + j)
            if c then
              c.model = pl
              c.top = Buildings.tops(md)[i .. "," .. j] or 0
            end
          end
        end
      end
      -- the ground under it, as Emerald 3DS lays it (Buildings.groundPlan): the placement's
      -- ground metatile, the map's own paint over it where the model draws nothing in a patched
      -- cell, a ground of the spec's choosing whole in its cells. Without the World's data: the
      -- commonest spec ground round it, the map's paint in every cell it paints otherwise than
      -- the template.
      local a = md.core[1]
      local anchor = grid.at(pl.cx + a[1], pl.cy + a[2])
      local src = anchor and pixelSource(NativeTileset, anchor.pair)
      if src then
        local gctx = groundCtx(md, anchor, a[1], a[2], where)
        local plan = gctx and Buildings.groundPlan(md, gctx)
        local g
        if plan then g = plan.ground
        else g = Buildings.groundOf(grid, pl, function(m) return src.ts.midToSlot[m] ~= nil end) end
        if plan then pl.groundMid = g end
        -- (a relief_bare model's bare cells with quarters to leave out: the relief goes on there
        -- (cell.bareQ), drawn less them; where nothing lifts the cell, that drawing lies flat -
        -- voxel_building.c VoxelBuildings_CellAt as Emerald 3DS's dev branch has it, the model's
        -- ground there a square of grass in the sand behind Lilycove's beacon)
        local bareOf = {}
        for k, q in pairs(plan and plan.bare or {}) do
          local c = grid.at(pl.cx + k % w, pl.cy + math.floor(k / w))
          if q ~= 0 and c and c.model == pl and c.mid then
            c.bareQ = q
            bareOf[k] = lessQuarters(NativeTileset, c.pair, c.mid, q)
          end
        end
        pl.ground = imageOf(w * 16, h * 16, function(data)
          for j = 0, h - 1 do
            for i = 0, w - 1 do
              local c = grid.at(pl.cx + i, pl.cy + j)
              local own = c and c.model == pl
              local k = j * w + i
              local whole = plan and plan.chosen[k]
              local patched
              if plan then patched = plan.patched[k]
              else patched = own and c.mid ~= md.ref.template[k + 1] end
              local bareAt = own and bareOf[k]
              for y = 0, 15 do
                for x = 0, 15 do
                  local X, Y = i * 16 + x, j * 16 + y
                  local m = whole or g
                  if not whole and patched and not Buildings.drawn(md, X, Y) then m = c.mid end
                  if bareAt then
                    local r, gg, b = bareAt(x, y)
                    if r then data:setPixel(X, Y, r, gg, b, 1) end
                  elseif own and m then
                    local r, gg, b = src.under(m, x, y)
                    local r1, g1, b1, a1 = src.over(m, x, y)
                    if a1 and a1 > 0.5 then r, gg, b = r1, g1, b1 end
                    if r then data:setPixel(X, Y, r, gg, b, 1) end
                  end
                end
              end
            end
          end
        end)
      end
    end
    -- the rooms' walls and furniture (src/scene/models/interiors.lua)
    if Interiors and World and where then
      local okR, err = pcall(placeRooms, grid, found, where)
      if not okR then hd.stats.sceneRoomError = tostring(err) end
    end
    -- the objects drawn as a block of upper-layer subtiles wherever they land (sea rocks,
    -- boulders, sea stacks: src/scene/props.lua)
    if Props and World and where then
      local okP, err = pcall(placeProps, grid, NativeTileset, found, where)
      if not okP then hd.stats.sceneBuildingError = "props: " .. tostring(err) end
    end
    -- Route 110's Cycling Road (src/scene/models/bridge.lua)
    if Bridge and World and where then
      local okB, err = pcall(placeBridges, grid, NativeTileset, found, where)
      if not okB then hd.stats.sceneBridgeError = tostring(err) end
    end
    -- the objects of no fixed shape (hedges, fences, curbs, railings), found by their runs
    if Components then
      local okC, extra = pcall(placeComponents, grid, NativeTileset, found, where)
      if not okC then hd.stats.sceneBuildingError = tostring(extra) end
    end
    return found
  end

  -- the metatiles signs are drawn with (Emerald 3DS's post_metatiles): every outdoor map's sign
  -- events that stand open on three sides (blocked, walkable west, east and south), read once a
  -- game; by the tileset that draws it and its id, with a pair it was found in
  local postIndex = setmetatable({}, { __mode = "k" })
  local function postKey(mid, pair)
    local primary, secondary = Signs.tilesets(pair)
    return tostring(mid < 512 and primary or secondary) .. ":" .. mid
  end
  local function signPosts(env)
    local Runtime, Map, Dataset = req("src.core.game3.runtime"), req("src.core.game3.map"), req("src.core.game3.dataset")
    local game = Runtime and Runtime._game
    local maps = game and game.data and game.data.maps
    if type(maps) ~= "table" or not (Map and Dataset and Dataset.isOutdoorMapType) then return nil end
    local hit = postIndex[maps]
    if hit then return hit end
    local Space = package.loaded["src.core.game3.scripting.space"]
    local found = {}
    for id, d in pairs(maps) do
      local evs = type(d) == "table" and d.bgEvents
      if type(d) == "table" and type(evs) ~= "table" then
        local b = Space and Space.bundle and Space.bundle.events and Space.bundle.events[id]
        evs = b and b.bgEvents
      end
      if type(evs) == "table" and Dataset.isOutdoorMapType(d.mapType) then
        local L
        for _, ev in ipairs(evs) do
          local x, y = tonumber(ev.x), tonumber(ev.y)
          if ev.type == "sign" and x and y then
            if L == nil then
              local ok, l = pcall(Map.ensureMidLayout, game, id, d)
              L = ok and l or false
            end
            if not L then break end
            local w, h = L.width or 0, L.height or 0
            local function blocked(cx, cy)
              if cx < 0 or cy < 0 or cx >= w or cy >= h then return false end
              return env.isWall(L:collAt(cx, cy)) == true
            end
            if x < w and y < h and blocked(x, y) and not blocked(x - 1, y) and not blocked(x + 1, y)
                and not blocked(x, y + 1) then
              local mid, pair = L:midAt(x, y), L.pair or d.pair
              if mid and pair then found[postKey(mid, pair)] = { mid, pair } end
            end
          end
        end
      end
    end
    postIndex[maps] = found
    return found
  end

  -- the relief (src/scene/relief.lua): heights read off the drawing, by layout id. For now only a
  -- relief.bin a dev driver hands over (Emerald 3DS's own, read locally to check the renderer
  -- against; never shipped); the port of its solver comes next
  local reliefData
  function Scene.setReliefBytes(bytes)
    reliefData = Relief and Relief.parse(bytes) or nil
    return reliefData ~= nil
  end
  function Scene.reliefData() return reliefData end

  -- the models warmed ahead of a battle: on entering a map, the specs one of whose cells its
  -- layout draws are readied one a frame (Scene.warmStep from the frame hook), so the first
  -- battle there does not build them all at once
  local warmQueue, warmed = {}, setmetatable({}, { __mode = "k" })
  function Scene.warm(mapId)
    local Map, NativeTileset = req("src.core.game3.map"), req("src.core.game3.tileset_native")
    local Runtime = req("src.core.game3.runtime")
    local game = Runtime and Runtime._game
    if not (Buildings and Specs and Map and NativeTileset and game and mapId) then return 0 end
    local okL, L = pcall(Map.ensureMidLayout, game, mapId)
    if not (okL and L) then return 0 end
    local mids = {}
    for y = 0, (L.height or 0) - 1 do
      for x = 0, (L.width or 0) - 1 do mids[L:midAt(x, y)] = true end
    end
    local ctx = layoutCtx()
    local n = 0
    -- (and the game's sign posts and this map's roles, read once a game: src/scene/world.lua)
    if World then
      warmQueue[#warmQueue + 1] = function()
        World.posts()
        local L = World.layout(mapId)
        if L then World.roles(L) end
      end
      -- (a bridge of this map or a neighbour's: read a slice a frame)
      local L = World.layout(mapId)
      local near = { L }
      for _, nb in ipairs(L and World.neighbours(L) or {}) do near[#near + 1] = nb[1] end
      for _, B in ipairs(near) do
        if B and B.name and Scene.hasBridge(B.name) and not (bridges[B.name] and bridges[B.name].done) then
          warmQueue[#warmQueue + 1] = { bridge = B.name }
          n = n + 1
        end
      end
      -- (indoors: the rooms, a slice a frame)
      if L and not L.outdoor and Interiors and not (roomRun and roomRun.done) then
        warmQueue[#warmQueue + 1] = { rooms = true }
        n = n + 1
      end
    end
    for _, spec in ipairs(Specs) do
      if spec._model == nil and not warmed[spec] then
        local ref = Buildings.reference(spec, ctx)
        for _, m in ipairs(ref and ref.template or {}) do
          if mids[m] then
            warmed[spec] = true
            warmQueue[#warmQueue + 1] = spec
            n = n + 1
            break
          end
        end
      end
    end
    return n
  end
  --- The cells the building models own in a layout (LAYOUT_X), as the relief solver asks them
  --- (Emerald 3DS reads them off its buildings.bin): { [(y + 4096) * 16384 + (x + 4096)] = true },
  --- or nil. Every spec is readied first; tick (optional) is called after each (the relief's build
  --- runs sliced in a coroutine).
  local modelCellsOf = {}
  -- the building models standing in a whole layout (Buildings.find over its own grid), or nil
  local function layoutFind(name, tick)
    local NativeTileset = req("src.core.game3.tileset_native")
    local L = World and World.layout(name)
    if not (L and L.grid and L.pair and Buildings and Specs and NativeTileset) then return nil end
    local ctx = layoutCtx()
    local models = {}
    for _, spec in ipairs(Specs) do
      local md = ready(spec, NativeTileset, ctx)
      if md then models[#models + 1] = md end
      if tick then tick() end
    end
    local rows = {}
    for y = 0, L.h - 1 do
      local row = {}
      for x = 0, L.w - 1 do
        local i = (y * L.w + x) * 2 + 1
        row[x] = { cx = x, cy = y, mid = (L.grid:byte(i) + L.grid:byte(i + 1) * 256) % 1024, pair = L.pair }
      end
      rows[y] = row
    end
    local grid = { x0 = 0, y0 = 0, w = L.w, h = L.h, rows = rows }
    function grid.at(x, y)
      local row = rows[y]
      return row and row[x] or nil
    end
    local r = World.roles(L)
    local function signCell(c)
      return r ~= nil and (r.role(c.cx, c.cy) == "signpost" or r.role(c.cx, c.cy + 1) == "signpost")
    end
    return Buildings.find(grid, models, alikeOf(NativeTileset, signCell)), grid, NativeTileset
  end
  -- (dev) how many cells a placement's ground lays a patch in: a ground of the spec's choosing, or
  -- the map's paint where the model leaves some of the cell (the pak's patches)
  local function patchCount(md, plan)
    local n = 0
    for _ in pairs(plan.chosen) do n = n + 1 end
    for k in pairs(plan.patched) do
      local i, j = k % md.ref.w, math.floor(k / md.ref.w)
      if not plan.chosen[k] and Buildings.exposed(md, i, j) then n = n + 1 end
    end
    return n
  end
  --- (dev) The models standing in a layout: { { name, x, y, w, h, footprints, tops } }.
  --- With its ground: { ground (metatile), patches (cells laid with a patch: a ground of the spec's
  --- choosing, or the map's paint where the model leaves some of it) }.
  --- With `runs`, the runs of hedges, fences and curbs too (placeComponents over the whole layout,
  --- the buildings' cells left out as in the battle's window).
  function Scene._layoutModels(name, runs)
    local out = {}
    local where = function(cx, cy) return nil, cx, cy, name end
    local found, grid, NativeTileset = layoutFind(name)
    local function add(pl, plan)
      local md = pl.model
      out[#out + 1] = { name = md.spec.name, x = pl.cx, y = pl.cy, w = md.ref.w, h = md.ref.h,
                        footprints = Buildings.footprints(md), tops = Buildings.tops(md), owned = md.spec.owned,
                        tris = md.tris, ground = plan and plan.ground, patches = plan and patchCount(md, plan),
                        plan = plan }
    end
    for _, pl in ipairs(found or {}) do
      local md = pl.model
      local a = md.core[1]
      local cell = { cx = pl.cx + a[1], cy = pl.cy + a[2] }
      local gctx = groundCtx(md, cell, a[1], a[2], where)
      add(pl, gctx and Buildings.groundPlan(md, gctx))
    end
    if runs and grid and Components then
      for _, pl in ipairs(found) do
        for j = 0, pl.model.ref.h - 1 do
          for i = 0, pl.model.ref.w - 1 do
            local c = Buildings.owns(pl.model.spec, i, j) and grid.at(pl.cx + i, pl.cy + j)
            if c then c.model = pl end
          end
        end
      end
      local list = {}
      placeComponents(grid, NativeTileset, list, where)
      for _, pl in ipairs(list) do add(pl, pl.plan) end
    end
    return out
  end
  function Scene.modelCells(name, tick)
    if modelCellsOf[name] ~= nil then return modelCellsOf[name] or nil end
    modelCellsOf[name] = false
    local found = layoutFind(name, tick)
    if not found then return nil end
    local out = {}
    for _, pl in ipairs(found) do
      local ref = pl.model.ref
      for j = 0, ref.h - 1 do
        for i = 0, ref.w - 1 do
          if Buildings.owns(pl.model.spec, i, j) then out[(pl.cy + j + 4096) * 16384 + (pl.cx + i + 4096)] = true end
        end
      end
    end
    -- (and a bridge's blocks, every cell of them)
    if Scene.hasBridge(name) then
      local st = Scene.bridge(name, tick)
      for k in pairs(st and st.at or {}) do
        out[(math.floor(k / 4096) + 4096) * 16384 + (k % 4096 + 4096)] = true
      end
    end
    modelCellsOf[name] = out
    return out
  end

  --- (dev) A spec's readied model by name, built afresh (the cache keeps no part names), or nil.
  function Scene.modelOf(name)
    local NativeTileset = req("src.core.game3.tileset_native")
    for _, spec in ipairs(Specs or {}) do
      if spec.name == name then
        if not NativeTileset then return nil end
        local was = Scene.cacheModels
        Scene.cacheModels = false
        spec._model = nil
        local md = ready(spec, NativeTileset, layoutCtx())
        Scene.cacheModels = was
        return md or nil
      end
    end
    return nil
  end

  --- Every spec queued (Scene Cache): from the cache where kept, built and kept otherwise.
  local warmedAll = false
  function Scene.warmAll()
    if warmedAll or not (Buildings and Specs) then return 0 end
    warmedAll = true
    local n = 0
    if World then warmQueue[#warmQueue + 1] = function() World.posts() end end
    for _, spec in ipairs(Specs) do
      if spec._model == nil and not warmed[spec] then
        warmed[spec] = true
        warmQueue[#warmQueue + 1] = spec
        n = n + 1
      end
    end
    -- (and the rooms, and the bridges, a slice a frame)
    if Interiors and not (roomRun and roomRun.done) then
      warmQueue[#warmQueue + 1] = { rooms = true }
      n = n + 1
    end
    for name in pairs(Bridge and Bridge.BRIDGES or {}) do
      if not (bridges[name] and bridges[name].done) then
        warmQueue[#warmQueue + 1] = { bridge = name }
        n = n + 1
      end
    end
    return n
  end
  --- One model readied, from the frame hook. Returns how many are left.
  function Scene.warmStep()
    local spec = table.remove(warmQueue, 1)
    if type(spec) == "function" then
      pcall(spec)
    elseif type(spec) == "table" and spec.rooms then
      local ok, st = pcall(roomStep, Scene.ROOM_SLICE)
      if ok and st.co then table.insert(warmQueue, 1, spec) end
    elseif type(spec) == "table" and spec.bridge then
      -- (a bridge: a slice, and back to the head of the queue until it is done)
      local ok, st = pcall(bridgeStep, spec.bridge, Scene.BRIDGE_SLICE)
      if ok and st.co then table.insert(warmQueue, 1, spec) end
    elseif spec then
      local NativeTileset = req("src.core.game3.tileset_native")
      if NativeTileset then pcall(ready, spec, NativeTileset, layoutCtx()) end
    end
    return #warmQueue
  end

  -- a map's layout id (the cartridge's: its map header's), as the engine's cache keeps it
  local layoutIds = {}
  local function layoutIdOf(mapId)
    if mapId == nil then return nil end
    local hit = layoutIds[mapId]
    if hit ~= nil then return hit or nil end
    layoutIds[mapId] = false
    local Rse, Dataset = req("src.core.game3.rse"), req("src.core.game3.dataset")
    local ok, g, num = pcall(function() return Rse.mapGroupNum(mapId) end)
    if ok and g and Dataset and Dataset.cache then
      local okC, cache = pcall(Dataset.cache)
      local raw = okC and cache and cache:read("data/generated/gba/map_tree/maps/" .. g .. "_" .. num .. "/header.json")
      layoutIds[mapId] = tonumber(raw and raw:match('"layoutId":(%d+)')) or false
    end
    return layoutIds[mapId] or nil
  end

  -- each cell's relief: its map's heights there (cell.g), and how high what stands on it is
  -- (cell.dy, tiles: its map's level over the battle map's - its base and the lift its seam with
  -- the battle map asks - and its relief's at its middle; a point h up stands h south as well),
  -- less the player's cell's, so the battle stands where it did. Returns the maps placed.
  local function placeRelief(grid, env, R, px, py)
    local maps, clears = {}, {}
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        local d, lx, ly, id, ox, oy = env.where(c.cx, c.cy)
        if d then
          local m = maps[d]
          if not m then
            local ML = d.midLayout
            m = { def = d, L = R.layouts[layoutIdOf(id) or -1], x = ox, y = oy,
                  w = ML and ML.width or 0, h = ML and ML.height or 0 }
            if m.L and (m.L.w ~= m.w or m.L.h ~= m.h) then m.L = nil end
            maps[d] = m
          end
          c.rmap, c.lx, c.ly = m, lx, ly
          c.g = m.L and m.L.cells[ly * m.L.w + lx] or nil
          -- (its cut record, and for the seam skirts which stretches of its north edge a wall may
          -- stand on: not where its cut tile clears the north row, voxel_mesh_builder.c SeamEdge)
          c.cut = c.g and m.L.cuts[ly * m.L.w + lx] or nil
          local v = c.cut and c.cut.variant ~= 0xFFFF and R.variants[c.cut.variant]
          if v then
            local clear = clears[c.cut.variant]
            if not clear then
              clear = Relief.cutClear(v.rows)
              clears[c.cut.variant] = clear
            end
            local st = 0
            for k = 0, 3 do
              if math.floor(clear[0] / 2 ^ (4 * k)) % 16 == 0 then st = st + 2 ^ k end
            end
            c.northStands = st
          end
        end
      end
    end
    local cur = maps[env.def]
    if not cur then return maps end
    for _, m in pairs(maps) do
      if m == cur then
        m.rel = 0
      else
        local step = Relief.seamStep({ L = cur.L, x = 0, y = 0, w = cur.w, h = cur.h },
          { L = m.L, x = m.x, y = m.y, w = m.w, h = m.h })
        m.rel = (m.L and m.L.base or 0) + step - (cur.L and cur.L.base or 0)
      end
    end
    local here = grid.at(px, py)
    local h0 = here and here.rmap and here.rmap.rel + Relief.centre(here.g) or 0
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.rmap then
          c.rmap.lift = (c.rmap.rel - h0) / 16
          c.mapLift = c.rmap.lift
          c.lifted = c.g ~= nil
          -- (for the stage search: its ground's height at its middle, tiles; rock or stairs)
          c.liftT = c.mapLift + Relief.centre(c.g) / 16
          c.slope = Relief.isSlope(c.g)
          -- (a sign at the foot of a face stands on the ground under its board)
          local at = c.g and (c.sign and Relief.isSlope(c.g)) and c.g[3 * Relief.SIDE + 2] or Relief.centre(c.g)
          c.dy = c.mapLift + at / 16
        end
      end
    end
    return maps
  end

  -- the relief's vertices (into `l`, relative to the player's cell px, py) and the texture of the
  -- drawings it lays: each lifted cell as Relief.emitCell draws it, in two passes (the first only
  -- asks which drawings it needs: the cells' own, their grounds and walls, the cut tiles)
  local function emitRelief(grid, R, NativeTileset, px, py)
    local slots, order = {}, {}
    local function slotOf(key, make)
      local s = slots[key]
      if not s then
        order[#order + 1] = { key = key, make = make }
        s = #order
        slots[key] = s
      end
      return s
    end
    local W, image
    local function rect(s)
      if not image then return 0, 0, 1, 1 end
      local e = Render.UV_INSET
      local sx, sy = (s - 1) % 64, math.floor((s - 1) / 64)
      local iw, ih = image:getDimensions()
      return (sx * 16 + e) / iw, (sy * 16 + e) / ih, (sx * 16 + 16 - e) / iw, (sy * 16 + 16 - e) / ih
    end
    local function composite(pair, mid)
      return function(x, y)
        local ps = pixelSource(NativeTileset, pair)
        if not ps then return nil end
        local r, g, b, a = ps.over(mid, x, y)
        if not (a and a > 0.5) then r, g, b, a = ps.under(mid, x, y) end
        if r and a and a > 0.5 then return { r, g, b } end
        return nil
      end
    end
    local function metatileUV(pair, mid)
      if mid == nil or pair == nil then return nil end
      local ps = pixelSource(NativeTileset, pair)
      if not (ps and ps.ts.midToSlot[mid]) then return nil end
      return rect(slotOf(pair .. ":" .. mid, composite(pair, mid)))
    end
    local out = {}
    local function pass()
      out = {}
      for j = 0, grid.h - 1 do
        for i = 0, grid.w - 1 do
          local c = grid.rows[j][i]
          if c.g and c.rmap and c.rmap.L then
            local m = c.rmap
            local L = m.L
            local function same(x, y)
              local o = grid.at(x, y)
              return o ~= nil and o.rmap == m
            end
            local B = { lift = 0, shift = 0, faceTile = L.faceTile }
            local dyBase = c.mapLift
            function B.quad(a, b, cc, d)
              for _, p in ipairs({ a, b, cc, a, cc, d }) do
                out[#out + 1] = { p[1] - px, p[2] + dyBase, p[3] - py + dyBase, p[4], p[5], p[6], p[6], p[6], 1 }
              end
            end
            function B.tri(a, b, cc)
              for _, p in ipairs({ a, b, cc }) do
                out[#out + 1] = { p[1] - px, p[2] + dyBase, p[3] - py + dyBase, p[4], p[5], p[6], p[6], p[6], 1 }
              end
            end
            B.sameMap = same
            function B.cell(x, y)
              local o = grid.at(x, y)
              return o and o.rmap == m and o.g or nil
            end
            function B.cut(x, y)
              local o = grid.at(x, y)
              if not (o and o.rmap == m) then return nil end
              return L.cuts[o.ly * L.w + o.lx]
            end
            function B.variant(k) return R.variants[k] end
            function B.tileUV(x, y)
              local o = grid.at(x, y)
              if not o then return nil end
              return metatileUV(o.pair, o.mid)
            end
            function B.metatileUV(mt) return metatileUV(c.pair, mt) end
            function B.cutUV(k)
              local v = R.variants[k]
              if not v then return nil end
              local pair = c.pair
              return rect(slotOf("cut:" .. pair .. ":" .. k, function(x, y)
                if not v._tex then v._tex = {} end
                local t = v._tex[pair]
                if not t then
                  t = Relief.cutTexture(v.rows, composite(pair, v.metatile))
                  v._tex[pair] = t
                end
                return t[y * 16 + x]
              end))
            end
            function B.sign(x, y)
              local o = grid.at(x, y)
              return o and o.sign and o.groundMid or nil
            end
            function B.headGround(x, y)
              local o = grid.at(x, y)
              return o and not o.sign and o.groundMid or nil
            end
            -- the model's height over its cell, as Emerald 3DS keeps it: a model lower than a
            -- level on a face a level tall (Lavaridge's benches) leaves the relief drawn there
            function B.modelTop(x, y)
              local o = grid.at(x, y)
              -- (a relief_bare model's bare cell with quarters to leave out: the relief's)
              if not (o and o.model) or o.bareQ then return nil end
              local pl = o.model
              if not (pl.model and pl.cx) then return 2 end
              return Buildings.cellTop(pl.model, o.cx - pl.cx, o.cy - pl.cy)
            end
            -- its drawing there: the cell's metatile less those quarters
            function B.bare(x, y)
              local o = grid.at(x, y)
              if not (o and o.bareQ and o.pair and o.mid) then return nil end
              local ps = pixelSource(NativeTileset, o.pair)
              if not (ps and ps.ts.midToSlot[o.mid]) then return nil end
              local px = lessQuarters(NativeTileset, o.pair, o.mid, o.bareQ)
              return rect(slotOf(o.pair .. ":" .. o.mid .. ":q" .. o.bareQ, function(xx, yy)
                local r, g, b = px(xx, yy)
                return r and { r, g, b } or nil
              end))
            end
            local part
            if Trees then
              local sec, general = Trees.tilesets(c.pair)
              part = general and Trees.part(sec, c.mid)
              if part and not Trees.laysGround(sec, c.mid) then part = nil end
            end
            if part then
              Relief.treeStep(B, c.cx, c.cy)
            elseif not Relief.emitCell(B, c.cx, c.cy, c.g) then
              c.lifted = false       -- a model's cell: its ground lies flat at the cell's middle
            elseif c.model then
              c.reliefDrawn = true   -- (a model's cell the relief draws: no ground of the model's)
            end
          end
        end
      end
    end
    pass()
    if #order == 0 then return nil end
    W = math.min(64, #order)
    image = imageOf(16 * W, 16 * math.ceil(#order / 64), function(data)
      for s, e in ipairs(order) do
        local sx, sy = ((s - 1) % 64) * 16, math.floor((s - 1) / 64) * 16
        for y = 0, 15 do
          for x = 0, 15 do
            local p = e.make(x, y)
            if p then data:setPixel(sx + x, sy + y, p[1], p[2], p[3], 1) end
          end
        end
      end
    end)
    if not image then return nil end
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.g and c.lifted == false and c.model then c.lifted = true end
      end
    end
    pass()
    return image, out
  end

  -- per battle state: the built scene, or false (keep the wallpaper)
  local built = setmetatable({}, { __mode = "k" })
  Scene.last = nil

  local function build(st, key, wallpaper)
    local env = engineEnv()
    local Player = req("src.core.game3.player")
    local NativeTileset = req("src.core.game3.tileset_native")
    if not (env and Player and NativeTileset) then return nil, "no map" end
    -- Hoenn's games (Emerald 3DS's rules: nothing stands up but its models) or Kanto's
    local Profile = req("src.core.game3.profile")
    local okV, gameId = pcall(function() return Profile.active().id end)
    local hoenn = okV and (gameId == "emerald" or gameId == "ruby" or gameId == "sapphire")
    -- whether a metatile is a tree's that stands as a cut-out: in Kanto's games only (Hoenn's trees
    -- are models, and nothing else stands there: Mossdeep's ledges, half grass, are no trees), a
    -- primary tileset's drawn as leaves (Emerald 3DS's foliage test: half its drawn pixels green)
    -- with something over the player (a crown). Anything else no model rebuilds lies flat as drawn
    local standsOf = {}
    function env.stands(mid, pair)
      if hoenn or mid == nil or mid >= 512 then return false end
      local key = tostring(pair) .. ":" .. tostring(mid)
      local t = standsOf[key]
      if t ~= nil then return t end
      local src = pixelSource(NativeTileset, pair)
      t = false
      if src and src.under(mid, 0, 0) ~= nil then
        local n, green, over = 0, 0, false
        for y = 0, 15 do
          for x = 0, 15 do
            local r, g, b, a = src.over(mid, x, y)
            if a and a > 0.5 then over = true else r, g, b, a = src.under(mid, x, y) end
            if a and a > 0.5 then
              n = n + 1
              r, g, b = r * 255, g * 255, b * 255
              if g > 64 and g > r + 16 and g > b + 16 then green = green + 1 end
            end
          end
        end
        t = over and n > 0 and green / n >= 0.5
      end
      standsOf[key] = t
      return t
    end
    local px, py = tonumber(Player.cellX) or 0, tonumber(Player.cellY) or 0
    if Player.moving and Player.targetX then px, py = Player.targetX, Player.targetY end
    -- (each phase's time, for the stats)
    local clock = love.timer and love.timer.getTime or os.clock
    local t0, phases = clock(), {}
    local function phase(name)
      local t = clock()
      phases[#phases + 1] = name .. " " .. math.floor((t - t0) * 1000 + 0.5)
      t0 = t
    end
    local grid = Cells.build(env, px - Scene.WEST, py - Scene.NORTH,
      Scene.WEST + Scene.EAST + 1, Scene.NORTH + Scene.SOUTH + 1)
    local here = grid.at(px, py)
    local hereKind = here and STAND[here.kind] and here.kind or nil
    local d = AHEAD[tostring(Player.facing)] or AHEAD.up
    local ahead = grid.at(px + d[1], py + d[2])
    local aheadKind = ahead and STAND[ahead.kind] and ahead.kind or nil
    local want = { player = Player.surfing and "water" or hereKind }
    if Player.surfing then
      want.enemy = "water"
    elseif st and st.trainerId ~= nil then
      want.enemy = aheadKind
    elseif hereKind ~= "grass" and aheadKind == "water" then
      want.enemy = "water"          -- fishing
    else
      want.enemy = hereKind
    end
    phase("cells")
    -- (Emerald's maps: a cell whose role in its own layout is a signpost's, or the cell north of
    -- one: src/scene/roles.lua)
    local function roleOf(cx, cy)
      if not World then return nil end
      local d, lx, ly, id = env.where(cx, cy)
      local L = d and id and World.layout(id)
      local r = L and World.roles(L)
      return r and r.role(lx, ly) or nil
    end
    local function signCell(c)
      return roleOf(c.cx, c.cy) == "signpost" or roleOf(c.cx, c.cy + 1) == "signpost"
    end
    -- (a cell's place in its own map: a spec with owned cells stands only where it is drawn)
    local okB, placed = pcall(placeBuildings, grid, NativeTileset, World and signCell or nil, env.where)
    if not okB then
      hd.stats.sceneBuildingError = tostring(placed)
      placed = {}
    end
    phase("buildings")
    -- the signposts: signs, lamps, posts and boulders as thin solids of their own pixels
    local signs = {}
    if Signs and not env.indoor then
      local layerCache = {}
      local function layersOf(mid, pair)
        local k = tostring(pair) .. ":" .. tostring(mid)
        local e = layerCache[k]
        if e == nil then
          e = false
          local src = pixelSource(NativeTileset, pair)
          if src and src.under(mid, 0, 0) ~= nil then
            local lo, up = {}, {}
            for y = 0, 15 do
              for x = 0, 15 do
                local r0, g0, b0, a0 = src.under(mid, x, y)
                local r1, g1, b1, a1 = src.over(mid, x, y)
                if a0 and a0 > 0.5 then lo[y * 16 + x] = { r0, g0, b0 } end
                if a1 and a1 > 0.5 then up[y * 16 + x] = { r1, g1, b1 } end
              end
            end
            e = { lo, next(up) and up or nil }
          end
          layerCache[k] = e
        end
        if not e then return nil, nil end
        return e[1], e[2]
      end
      -- the game's sign metatiles, and their upper layers: a primary tileset's read through a
      -- pair of the window with the same primary (the same drawing), a secondary's through its own
      -- pair where the window has it
      local okP, posts = pcall(signPosts, env)
      posts = okP and posts or {}
      local windowPairs, byPrimary = {}, {}
      for j = 0, grid.h - 1 do
        for i = 0, grid.w - 1 do
          local p = grid.rows[j][i].pair
          if p and not windowPairs[p] then
            windowPairs[p] = true
            local primary = Signs.tilesets(p)
            if primary and not byPrimary[primary] then byPrimary[primary] = p end
          end
        end
      end
      local uppers = {}
      for _, f in pairs(posts) do
        local mid, pair = f[1], f[2]
        local via = mid < 512 and byPrimary[Signs.tilesets(pair) or ""] or (windowPairs[pair] and pair) or nil
        if via then
          local _, up = layersOf(mid, via)
          if up then uppers[Signs.upperKey(up)] = true end
        end
      end
      local okS, found = pcall(Signs.find, grid, {
        isWall = env.isWall, stands = env.stands, layers = layersOf,
        signAt = env.signAt, doorAt = env.doorAt, isHouseDoor = env.isHouseDoor,
        postAt = function(mid, pair) return mid ~= nil and pair ~= nil and posts[postKey(mid, pair)] ~= nil end,
        postUpper = function(k) return uppers[k] == true end,
        mountainRock = hoenn,
        -- (Emerald's maps: the cell's role in its own layout, src/scene/roles.lua)
        signpostAt = World and function(c)
          local d, lx, ly, id = env.where(c.cx, c.cy)
          local L = d and id and World.layout(id)
          local r = L and World.roles(L)
          if not r then return nil end
          return r.role(lx, ly) == "signpost"
        end or nil,
      })
      if okS then
        local at = {}
        for _, f in ipairs(found) do
          at[#at + 1] = string.format("%d,%d:%03X%s", f.cell.cx, f.cell.cy, f.cell.mid or 0, f.head and "+head" or "")
        end
        hd.stats.sceneSigns = #found .. " " .. table.concat(at, " ")
      end
      if okS then
        signs = found
        for _, s in ipairs(signs) do
          s.cell.sign, s.cell.up, s.cell.base = true, nil, nil
          if not s.cell.model then s.cell.groundMid = s.ground end
          if s.head then
            local h = grid.at(s.cell.cx, s.cell.cy - 1)
            if h then h.groundMid = s.headGround end
          end
        end
      else
        hd.stats.sceneSignError = tostring(found)
      end
    end
    phase("signs")
    -- the relief: each cell's heights and how high what stands on it is (src/scene/relief.lua)
    local R = Relief and Scene.reliefData()
    hd.stats.sceneReliefError = nil
    if Scene.reliefRun then
      local st, why = Scene.reliefRun.state()
      hd.stats.sceneReliefRun = st .. (why and (" (" .. tostring(why) .. ")") or "")
    end
    hd.stats.sceneModels = ("%d from the cache, %d built"):format(Scene.modelsFromCache, Scene.modelsBuilt)
    local maps
    if R then
      local okR, placedMaps = pcall(placeRelief, grid, env, R, px, py)
      maps = okR and placedMaps or nil
      if okR then
        local n, ids = 0, {}
        for j = 0, grid.h - 1 do
          for i = 0, grid.w - 1 do if grid.rows[j][i].g then n = n + 1 end end
        end
        for _, m in pairs(placedMaps) do
          if m.L then ids[#ids + 1] = m.L.id .. "@" .. (m.rel or 0) end
        end
        table.sort(ids)
        hd.stats.sceneRelief = n .. " cells; layouts " .. table.concat(ids, " ")
        for _, pl in ipairs(placed) do
          local ref = pl.model.ref
          local c = grid.at(pl.cx + math.floor((ref.w - 1) / 2), pl.cy + ref.h - 1)
          pl.dy = c and c.dy or 0
        end
      else
        hd.stats.sceneReliefError = tostring(placedMaps)
      end
    end
    -- the border round the battle map (Emerald 3DS's belt, voxel_mesh_builder.c VoxelMesh_EmitBorder,
    -- BorderWaterLevel, VoxelMesh_BorderLevel): every cell past every map, but in a room (its
    -- black filler; a cave has its border). Its metatile is the border block's, or where the map's
    -- hand marks fill that edge (relief_fixes.json "edges"), the fill's. Levels and shifts in
    -- tiles as the cells' (`base`: the battle map's base there):
    --   a belt of water lies flat at the level of the map's sea nearest it along the edge (the
    --     edge cell's when it is water), or at a fill's top;
    --   a belt of land stands two courses at the level of the map's edge cell nearest it (`steps`),
    --     or with its top at a fill's top (its shift the edge cell's still), or at the base past a
    --     sea edge;
    --   a map whose marks give its belt courses (a cave carved out of the rock, Lavaridge in its
    --     crater) lays it as its drawing: `drawn` courses at the base, that many rows south.
    if not env.walled then
      local W, H = env.W or 0, env.H or 0
      local ring = R and maps and maps[env.def]
      local RL = ring and ring.L
      local base = ring and ring.lift or 0
      local drawn = RL and RL.belt or 0
      local edges = R and R.edges
      local C = Render.BORDER_COURSES
      local function inRing(cx, cy) return cx >= 0 and cy >= 0 and cx < W and cy < H end
      local function fillAt(cx, cy)
        return RL and Relief.edgeFillAt(edges, RL.id, W, H, cx, cy) or nil
      end
      local function metatileAt(cx, cy)
        local f = fillAt(cx, cy)
        if f then return f.metatile end
        return env.borderMid(cx, cy)
      end
      local function edgeOf(cx, cy)
        return math.max(0, math.min(W - 1, cx)), math.max(0, math.min(H - 1, cy))
      end
      local function liftOf(o) return o and o.liftT or base end
      for j = 0, grid.h - 1 do
        for i = 0, grid.w - 1 do
          local c = grid.rows[j][i]
          if not c.rmap and c.coll == nil and not env.where(c.cx, c.cy) then
            local m = metatileAt(c.cx, c.cy)
            local ex, ey = edgeOf(c.cx, c.cy)
            local e = grid.at(ex, ey)
            local f = fillAt(c.cx, c.cy)
            -- (mids[h]: the block's metatile h rows north, its courses drawn as the game tiles it)
            local b = { mid = m, water = drawn == 0 and env.waterMid(m), level = base, shift = base,
                        drawn = drawn, courses = drawn > 0 and drawn or C, base = base,
                        mids = { [0] = m, [1] = metatileAt(c.cx, c.cy - 1) } }
            if b.water then
              if f and f.hasTop then
                b.level, b.shift = base + f.top / 16, liftOf(e)
              else
                -- the map's sea nearest it along the edge
                local w = e and e.kind == "water" and e or nil
                if e and not w then
                  local alongY = c.cx < 0 or c.cx >= W
                  for k = 1, 12 do
                    local ax, ay = alongY and ex or ex - k, alongY and ey - k or ey
                    local bx, by = alongY and ex or ex + k, alongY and ey + k or ey
                    local a, bb = grid.at(ax, ay), grid.at(bx, by)
                    if inRing(ax, ay) and a and a.kind == "water" then w = a
                    elseif inRing(bx, by) and bb and bb.kind == "water" then w = bb end
                    if w then break end
                  end
                end
                if w then b.level, b.shift = liftOf(w), liftOf(w) end
              end
            elseif drawn == 0 then
              if f and f.hasTop and not f.water then
                b.level, b.shift, b.steps = base + f.top / 16 - C, liftOf(e), true
              elseif e and e.kind ~= "water" then
                b.level, b.shift, b.steps = liftOf(e), liftOf(e), true
              end
            end
            c.border = b
            -- (a fill's metatile is the cell's: the trees' pass reads it)
            if f then c.mid = m end
            c.dy = b.level
            c.lifted = true
            -- (for the stage search: two courses tall, as Emerald 3DS counts a cell past the map)
            if not b.water then c.top = 2 end
          end
        end
      end
    end
    phase("relief")
    local stage = Stage.search(Camera, grid, {
      player = { cx = px, cy = py }, want = want, feet = Scene.FEET, sprites = Scene.SPRITES,
      void = env.walled,
    })
    if not stage or stage.score < Stage.FLOOR then return nil, "no stage" end
    local cards = 0
    for j = 0, grid.h - 1 do
      for i = 0, grid.w - 1 do
        local c = grid.rows[j][i]
        if c.up and not c.model then cards = cards + 1 end
      end
    end
    local names = {}
    for _, pl in ipairs(placed) do names[#names + 1] = pl.model.spec.name .. "@" .. pl.cx .. "," .. pl.cy end
    hd.stats.sceneBuildings = table.concat(names, " ")
    phase("stage")
    local lists = Render.vertices(grid, tilesFor(NativeTileset), px, py,
      { Trees = Trees, image = treesArt(), outdoor = not env.indoor },
      { Buildings = Buildings, placements = placed })
    if lists.skirts and hd.stats.sceneRelief then
      local k = lists.skirts
      hd.stats.sceneRelief = hd.stats.sceneRelief .. ("; skirts: belt %d, seam %d, gap %d (%s)"):format(k.belt, k.seam, k.gap,
        table.concat(k.cells, " "))
    end
    -- the signs' solids, from one texture of their drawings (16 x 32 each)
    if #signs > 0 then
      local src = {}
      local image = imageOf(16 * #signs, 32, function(data)
        for k, s in ipairs(signs) do
          local ps = pixelSource(NativeTileset, s.cell.pair)
          if ps then
            local ox0 = (k - 1) * 16
            for y = 0, 15 do
              for x = 0, 15 do
                if s.head then
                  local r, g, b, a = ps.over(grid.at(s.cell.cx, s.cell.cy - 1).mid, x, y)
                  if a and a > 0.5 then data:setPixel(ox0 + x, y, r, g, b, 1) end
                end
                local r, g, b, a = ps.over(s.cell.mid, x, y)
                if not (a and a > 0.5) then r, g, b, a = ps.under(s.cell.mid, x, y) end
                if r then data:setPixel(ox0 + x, 16 + y, r, g, b, 1) end
              end
            end
          end
          src[k] = ps
        end
      end)
      if image then
        local l = {}
        lists.models[image] = l
        for k, s in ipairs(signs) do
          local mask, n, row0 = {}, 16, 16
          if s.head then
            for y = 0, 15 do mask[y], mask[16 + y] = s.head[y], s.rows[y] end
            n, row0 = 32, 0
          else
            for y = 0, 15 do mask[y] = s.rows[y] end
          end
          local sdy = s.cell.dy or 0
          local wx, wz = s.cell.cx - px, s.cell.cy - py - (s.head and 1 or 0) + sdy
          local top = Signs.emit(mask, n, function(x, y, z, u, v, shade)
            l[#l + 1] = { wx + x, y + sdy, wz + z, ((k - 1) * 16 + u) / (16 * #signs), (row0 + v) / 32,
                          shade, shade, shade, 1 }
          end)
          s.cell.top = top
        end
      end
    end
    if R then
      local okE, image, l = pcall(emitRelief, grid, R, NativeTileset, px, py)
      if okE and image then
        lists.models[image] = l
      elseif not okE then
        hd.stats.sceneReliefError = tostring(image)
      end
    end
    local live = {}
    for _, md in ipairs(liveModels) do
      if md.image and lists.models[md.image] then md._liveFrame = nil; live[#live + 1] = md end
    end
    -- (models whose texels follow a tile animation, in this scene)
    hd.stats.sceneLive = #live
    local meshes = Render.meshes(G, lists)
    phase("render")
    hd.stats.scenePhases = table.concat(phases, ", ")
    if not meshes or #meshes == 0 then return nil, "no meshes" end
    shadows = shadows or { enemy = shadow(Scene.SHADOW.enemy), player = shadow(Scene.SHADOW.player) }
    local indoor = env.indoor
    local haze = indoor and Scene.HAZE.indoor or topColour(wallpaper) or Scene.HAZE.outdoor
    return {
      key = key, meshes = meshes, ox = px, oz = py, stage = stage, want = want, cards = cards,
      from = Camera.pose(px + 0.5, py + 0.5, Camera.FIELD_PITCH, Camera.FIELD_DIST),
      -- (on lifted ground: as high as it, and as far south again, src/scene/relief.lua)
      to = Camera.pose(stage.tx, stage.tz + (stage.ty or 0), nil, nil, stage.ty),
      progress = 0, frames = 0, haze = haze, fog = indoor and Scene.FOG.indoor or Scene.FOG.outdoor,
      shadows = shadows, live = live,
    }
  end

  --- The scene for this battle state (built on first ask), or nil: the battle keeps its
  --- wallpaper. `key` the battle's terrain sheet, `wallpaper` its image (its sky colour).
  function Scene.forBattle(st, key, wallpaper)
    if not Scene.enabled or type(st) ~= "table" then return nil end
    local s = built[st]
    if s == nil then
      local t0 = love.timer and love.timer.getTime() or 0
      local ok, made, why = pcall(build, st, key, wallpaper)
      hd.stats.sceneMs = love.timer and math.floor((love.timer.getTime() - t0) * 1000 + 0.5) or nil
      if not ok then
        hd.stats.sceneError = tostring(made)
        made = nil
      end
      s = made or false
      built[st] = s
      hd.stats.scene = made and "built" or tostring(why or "failed")
      if made then
        hd.stats.sceneScore = math.floor(made.stage.score * 10 + 0.5) / 10
        hd.stats.sceneCards = made.cards
      end
    end
    Scene.last = s or nil
    return s or nil
  end

  --- This battle state's scene if it is built (never builds one), or nil.
  function Scene.current(st)
    if not Scene.enabled or type(st) ~= "table" then return nil end
    return built[st] or nil
  end

  --- The intro's progress: the battlers' slide (enemyOx runs -240 -> 0), never going back;
  --- a battle that starts with nothing sliding is at rest from its first frame.
  function Scene.step(s, enemyOx)
    local ox = tonumber(enemyOx) or 0
    local p = 1 - math.min(1, math.abs(ox) / 240)
    s.frames = s.frames + 1
    if s.frames == 1 and p >= 1 then s.progress = 1 end
    if p > s.progress then s.progress = p end
    hd.stats.sceneProgress = s.progress
  end

  local function smooth(t) return t * t * (3 - 2 * t) end

  --- (tests) The last scene alone at its settled pose, w x h (the battle canvas scaled to it):
  --- image data, or nil.
  function Scene.snapshot(w, h)
    local s = Scene.last
    if not (s and s.meshes) then return nil end
    local k = math.min(w / 240, h / 160)
    local proj, depth = Camera.screenProjection(0, 0, k, k)
    local c = Render.draw(G, Camera, s, Camera.glide(s.from, s.to, 1), proj, depth, 1, s.haze, s.fog,
      240 * k, 160 * k)
    return c and c:newImageData() or nil
  end

  --- hd.sceneRenderer: the world item for a screen rect `box` with the scene's mapping (canvas
  --- pixels -> screen: bx + u * bsx). Returns the canvas and where it goes, or nil.
  -- a model's texels the game's tile animation redraws (Rustboro's fountain's jet): repainted
  -- when the engine's bank for that metatile turns to another frame
  local function stepLive(md)
    local lv = md.live
    local TA = req("src.core.game3.tileset_anim")
    local entry = TA and TA._pairs and TA._pairs[lv.pair]
    if not (entry and entry.banks and md._data and md.image) then return end
    local bank = md._bank
    if not bank or md._bankOf ~= entry then
      bank = nil
      for _, b in ipairs(entry.banks) do
        local row = b and b.row
        for _, m in ipairs(not lv.upper and row and row.mids or {}) do if m == lv.mid then bank = b end end
        for _, m in ipairs(row and row.overMids or {}) do if m == lv.mid then bank = b end end
      end
      md._bank, md._bankOf = bank, entry
      if not bank then return end
    end
    local f = (bank.frame or 0) % lv.frames
    if f == md._liveFrame then return end
    md._liveFrame = f
    local t, stride = lv.texels, 2 + 4 * lv.frames
    for i = 1, #t, stride do
      local o = i + 2 + 4 * f
      md._data:setPixel(t[i], t[i + 1], t[o], t[o + 1], t[o + 2], t[o + 3])
    end
    pcall(md.image.replacePixels, md.image, md._data)
  end

  function Scene.render(item, bx, by, bsx, bsy, box)
    local s = item.scene
    if not (s and s.meshes) then return nil end
    for _, md in ipairs(s.live or {}) do stepLive(md) end
    local rec = item.rec
    -- the background's shake (a move scrolling it), in canvas pixels
    local shx, shy = rec.tx + (rec.x or 0) * rec.tsx, rec.ty + (rec.y or 0) * rec.tsy
    local x, y, w, h = box[1], box[2], box[3], box[4]
    local u0, v0 = (x - bx) / bsx - shx, (y - by) / bsy - shy
    local proj, depth = Camera.screenProjection(u0, v0, bsx, bsy)
    local pose = Camera.glide(s.from, s.to, s.progress)
    local c = Render.draw(G, Camera, s, pose, proj, depth, smooth(s.progress), s.haze, s.fog, w, h)
    if not c then return nil end
    return c, x, y
  end

  return Scene
end
