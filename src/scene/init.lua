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

  local function imageOf(W, H, fill)
    local ok, data = pcall(love.image.newImageData, W, H)
    if not ok then return nil end
    fill(data)
    local okI, img = pcall(G.newImage, data)
    if not okI then return nil end
    img:setFilter("nearest", "nearest")
    return img
  end

  -- a spec made ready to place: its reference, art (image), core cells and triangles (once)
  local function ready(spec, NativeTileset, ctx)
    if spec._model ~= nil then return spec._model end
    spec._model = false
    local ref = Buildings.reference(spec, ctx)
    if not ref then return false end
    local src = pixelSource(NativeTileset, ref.pair)
    if not src then return false end
    local art = Buildings.art(spec, ref, src)
    -- (parts read off the drawing come with a texture of their own: the drawing and its bands)
    local okM, mesh, tex = pcall(function()
      local parts, t
      if spec.parts_art then parts, t = spec.parts_art(art) else parts = spec.parts() end
      return Kernel.build(parts), t
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
    local image = imageOf(tex.w, tex.h, function(data)
      local px = tex.px
      for y = 0, tex.h - 1 do
        for x = 0, tex.w - 1 do
          local o = (y * tex.w + x) * 4
          data:setPixel(x, y, px[o + 1], px[o + 2], px[o + 3], px[o + 4])
        end
      end
    end)
    spec._model = { spec = spec, ref = ref, art = art, core = core, primaryOnly = primaryOnly,
                    tris = mesh.tris, image = image, texW = tex.w, texH = tex.h }
    return spec._model
  end

  local Components = deps.Components

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

  -- the runs of hedges, fences, curbs and railings in the grid, each its own model, added to
  -- `found` (their cells marked as a building's are)
  function placeComponents(grid, NativeTileset, found)
    local runs = Components.find(grid)
    local report = {}
    local mid = function(x, y) local c = grid.at(x, y); return c and c.mid end
    for _, run in ipairs(runs) do
      local src = pixelSource(NativeTileset, run.pair)
      local okB, built = pcall(function()
        return src and Components.build(run, src, mid, function(m) return refSource(NativeTileset, run.pair, m) end)
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
          local md = { spec = { name = run.spec.name, owned = run.owned, ground = run.spec.ground },
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
          local pl = { model = md, cx = run.x0, cy = run.y0 }
          local g = Buildings.groundOf(grid, pl, function(m) return src.ts.midToSlot[m] ~= nil end)
          for _, c in ipairs(run.cells) do
            c.model = pl
            c.top = Buildings.tops(md)[(c.cx - run.x0) .. "," .. (c.cy - run.y0)] or 0
          end
          -- its cells' ground: the map's own drawing where the model draws nothing; under it the
          -- ground metatile (or, for what is drawn on the upper layer, the cell's own lower layer)
          pl.ground = imageOf(run.w * 16, run.h * 16, function(data)
            for _, c in ipairs(run.cells) do
              local i, j = c.cx - run.x0, c.cy - run.y0
              for y = 0, 15 do
                for x = 0, 15 do
                  local X, Y = i * 16 + x, j * 16 + y
                  local covered = art.px[(Y * art.w + X) * 4 + 4] >= 0.5
                  local r, gg, b
                  if covered and not run.spec.upper and g then
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
      else
        report[#report + 1] = run.spec.name .. ":none"
      end
    end
    hd.stats.sceneRuns = #runs .. " " .. table.concat(report, " ")
  end

  -- the buildings standing in the grid: placements, their cells marked (cell.model)
  local function placeBuildings(grid, NativeTileset)
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
    local found = Buildings.find(grid, models)
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
      -- the ground under it: the placement's ground metatile, and in a cell the map paints
      -- otherwise than the template, the map's own drawing wherever the model draws nothing
      local anchor = grid.at(pl.cx + md.core[1][1], pl.cy + md.core[1][2])
      local src = anchor and pixelSource(NativeTileset, anchor.pair)
      if src then
        local g = Buildings.groundOf(grid, pl, function(m) return src.ts.midToSlot[m] ~= nil end)
        local art = md.art
        pl.ground = imageOf(w * 16, h * 16, function(data)
          for j = 0, h - 1 do
            for i = 0, w - 1 do
              local c = grid.at(pl.cx + i, pl.cy + j)
              local own = c and c.model == pl
              local odd = own and c.mid ~= md.ref.template[j * w + i + 1]
              for y = 0, 15 do
                for x = 0, 15 do
                  local X, Y = i * 16 + x, j * 16 + y
                  local m = g
                  if odd and art.px[(Y * art.w + X) * 4 + 4] < 0.5 then m = c.mid end
                  if own and m then
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
    -- the objects of no fixed shape (hedges, fences, curbs, railings), found by their runs
    if Components then
      local okC, extra = pcall(placeComponents, grid, NativeTileset, found)
      if not okC then hd.stats.sceneBuildingError = tostring(extra) end
    end
    return found
  end

  -- per battle state: the built scene, or false (keep the wallpaper)
  local built = setmetatable({}, { __mode = "k" })
  Scene.last = nil

  local function build(st, key, wallpaper)
    local env = engineEnv()
    local Player = req("src.core.game3.player")
    local NativeTileset = req("src.core.game3.tileset_native")
    if not (env and Player and NativeTileset) then return nil, "no map" end
    local px, py = tonumber(Player.cellX) or 0, tonumber(Player.cellY) or 0
    if Player.moving and Player.targetX then px, py = Player.targetX, Player.targetY end
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
    local okB, placed = pcall(placeBuildings, grid, NativeTileset)
    if not okB then
      hd.stats.sceneBuildingError = tostring(placed)
      placed = {}
    end
    local stage = Stage.search(Camera, grid, {
      player = { cx = px, cy = py }, want = want, feet = Scene.FEET, sprites = Scene.SPRITES,
      void = env.indoor,
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
    local lists = Render.vertices(grid, tilesFor(NativeTileset), px, py,
      { Trees = Trees, image = treesArt(), outdoor = not env.indoor },
      { Buildings = Buildings, placements = placed })
    local meshes = Render.meshes(G, lists)
    if not meshes or #meshes == 0 then return nil, "no meshes" end
    shadows = shadows or { enemy = shadow(Scene.SHADOW.enemy), player = shadow(Scene.SHADOW.player) }
    local indoor = env.indoor
    local haze = indoor and Scene.HAZE.indoor or topColour(wallpaper) or Scene.HAZE.outdoor
    return {
      key = key, meshes = meshes, ox = px, oz = py, stage = stage, want = want, cards = cards,
      from = Camera.pose(px + 0.5, py + 0.5, Camera.FIELD_PITCH, Camera.FIELD_DIST),
      to = Camera.pose(stage.tx, stage.tz),
      progress = 0, frames = 0, haze = haze, fog = indoor and Scene.FOG.indoor or Scene.FOG.outdoor,
      shadows = shadows,
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
  function Scene.render(item, bx, by, bsx, bsy, box)
    local s = item.scene
    if not (s and s.meshes) then return nil end
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
