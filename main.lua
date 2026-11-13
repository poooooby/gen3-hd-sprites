-- gen3-hd-sprites: draws tagged sprites at WINDOW resolution in Gen 3 battles and on the
-- field, so a sprite mod can show its art at any size without the game's pixel grid
-- resampling it. Other mods use it through mod.exports (src/api.lua):
--
--   local hd = mod:find("gen3-hd-sprites")
--   if hd and hd.exports.isActive() then
--     hd.exports.tag(image, { scale = 0.6, anchor = "feet" })
--   end
--
-- Only images a mod tags are touched; with nothing tagged, or this mod off, every frame
-- is drawn exactly as the game draws it. See src/hd.lua for how a frame is split and
-- composited, and README.md for the API.

local function loadSibling(mod, name, optional)
  local source = mod:read(name)
  if not source then
    if not optional then mod.log:error("%s is missing -- reinstall the mod", name) end
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  local HD = loadSibling(mod, "src/hd.lua")
  local Engine = loadSibling(mod, "src/engine.lua")
  local Api = loadSibling(mod, "src/api.lua")
  if not (HD and Engine and Api) then return end
  -- the generations it draws, each by its own adapter (src/engine.lua picks the game's)
  Engine.adapters[1] = loadSibling(mod, "src/gen1.lua")
  Engine.adapters[2] = loadSibling(mod, "src/gen2.lua")
  Engine.adapters[3] = loadSibling(mod, "src/gen3.lua")
  -- optional: without it the player's pad is the game's own (cut at the text box)
  Engine.Pads = loadSibling(mod, "src/pads.lua")

  -- the engine does not register a mod's options from its manifest: define them here
  local schema = loadSibling(mod, "options.lua")
  if type(schema) == "table" and mod.options and mod.options.define then
    pcall(mod.options.define, mod.options, schema)
  end

  local hd = HD.new(love.graphics, { log = mod.log })
  local state = { active = false }

  -- optional: Battle Scene (Gen 3's battles over the overworld in 2.5D, src/scene/)
  local SceneInit = loadSibling(mod, "src/scene/init.lua")
  local sceneDeps = {
    Camera = loadSibling(mod, "src/scene/camera.lua"),
    Cells = loadSibling(mod, "src/scene/cells.lua"),
    Stage = loadSibling(mod, "src/scene/stage.lua"),
    Render = loadSibling(mod, "src/scene/render.lua"),
    -- (optional: without it trees stand as cut-outs too)
    Trees = loadSibling(mod, "src/scene/trees.lua"),
    -- (optional: without them buildings stand as cut-outs)
    Buildings = loadSibling(mod, "src/scene/buildings.lua"),
    Kernel = loadSibling(mod, "src/scene/models/kernel.lua"),
    -- (optional: without it signs, lamps and boulders lie flat)
    Signs = loadSibling(mod, "src/scene/signs.lua"),
    Relief = loadSibling(mod, "src/scene/relief.lua"),
    -- (Emerald 3DS's cell roles, over the game's own layouts: src/scene/world.lua)
    Roles = loadSibling(mod, "src/scene/roles.lua"),
    path = mod.path,
    hd = hd,
  }
  local specsOf = loadSibling(mod, "src/scene/models/specs.lua")
  local fenceOf = loadSibling(mod, "src/scene/models/fence.lua")
  local componentsOf = loadSibling(mod, "src/scene/models/components.lua")
  -- (optional: the solids round things are read off, and their specs)
  local solidsOf = loadSibling(mod, "src/scene/models/solids.lua")
  local solidSpecsOf = loadSibling(mod, "src/scene/models/solid_specs.lua")
  if type(specsOf) == "function" and sceneDeps.Kernel then
    local okS = type(solidsOf) == "function" and pcall(solidsOf, sceneDeps.Kernel)
    local ok, specs = pcall(specsOf, sceneDeps.Kernel)
    if ok and type(specs) == "table" then
      sceneDeps.Specs = specs
      if okS and type(solidSpecsOf) == "function" then pcall(solidSpecsOf, sceneDeps.Kernel, specs) end
    end
    local okF, fence = pcall(fenceOf, sceneDeps.Kernel)
    if okF and type(fence) == "table" and type(componentsOf) == "function" then
      local okC, comps = pcall(componentsOf, sceneDeps.Kernel, fence)
      if okC and type(comps) == "table" then sceneDeps.Components = comps end
    end
  end
  local worldOf = loadSibling(mod, "src/scene/world.lua")
  local Post = loadSibling(mod, "src/scene/relief_post.lua")
  -- (JSON read with relief_post's own decoder: the engine's belongs to its link code)
  local json = Post and function(text) return (Post.json(text)) end or nil
  if type(worldOf) == "function" and sceneDeps.Roles and json then
    local okW, world = pcall(worldOf, { Roles = sceneDeps.Roles, json = json })
    if okW and type(world) == "table" then sceneDeps.World = world end
  end
  if SceneInit and sceneDeps.Camera and sceneDeps.Cells and sceneDeps.Stage and sceneDeps.Render then
    local ok, Scene = pcall(SceneInit, sceneDeps)
    if ok and type(Scene) == "table" then
      Engine.Scene = Scene
      hd.scene = Scene
      hd.sceneRenderer = Scene.render
    end
  end
  -- the relief, built once a game in the background and cached (src/scene/relief_run.lua): the
  -- solver (src/scene/relief_solve.lua and parts), the terraces (relief_terraces.lua, optional:
  -- without it only a cached relief is served) and the last passes (relief_post.lua)
  local reliefRun
  if Engine.Scene and sceneDeps.Relief and sceneDeps.Roles then
    local Art, Input = loadSibling(mod, "src/scene/relief_art.lua"), loadSibling(mod, "src/scene/relief_input.lua")
    local Solve = loadSibling(mod, "src/scene/relief_solve.lua")
    local parts = { loadSibling(mod, "src/scene/relief_drawn.lua"), loadSibling(mod, "src/scene/relief_shape.lua"),
                    loadSibling(mod, "src/scene/relief_cuts.lua"), loadSibling(mod, "src/scene/relief_world.lua") }
    local worldMapsOf = loadSibling(mod, "src/scene/world_maps.lua")
    -- (the terraces: three parts of the solve, all or none)
    local Terraces
    do
      local a, b, c = loadSibling(mod, "src/scene/relief_terraces.lua", true),
        loadSibling(mod, "src/scene/relief_terraces_fit.lua", true), loadSibling(mod, "src/scene/relief_terraces_out.lua", true)
      if a and b and c then Terraces = { a, b, c } end
    end
    local runOf = loadSibling(mod, "src/scene/relief_run.lua")
    local okM, WorldMaps = pcall(function()
      return worldMapsOf({ Solve = Solve, Art = Art, Input = Input, Roles = sceneDeps.Roles, parts = parts, json = json })
    end)
    if Post and okM and type(WorldMaps) == "table" and type(runOf) == "function" then
      local okV, GameVersion = pcall(require, "src.core.GameVersion")
      local okD, Dataset = pcall(require, "src.core.game3.dataset")
      local okR, run = pcall(runOf, {
        Relief = sceneDeps.Relief, Post = Post, WorldMaps = WorldMaps, Terraces = Terraces, Roles = sceneDeps.Roles,
        fixes = mod:read("assets/scene/relief_fixes.json"),
        cache = mod.cache, hooks = mod.hooks, log = mod.log,
        version = okV and GameVersion or nil,
        readCache = function(rel)
          local okC, c = pcall(function() return okD and Dataset.cache() end)
          return okC and c and c:read(rel) or nil
        end,
        onReady = function(bytes) Engine.Scene.setReliefBytes(bytes) end,
        models = function(name) return Engine.Scene.modelCells(name) end,
        onFrame = function() Engine.Scene.warmStep() end,
      })
      if okR and type(run) == "table" then
        reliefRun = run
        Engine.Scene.reliefRun = run
        -- (the models' cache: the mod's, under the same game key as the relief's)
        Engine.Scene.modelCache = {
          read = function(name)
            local k = run.gameKey()
            local okC, b = pcall(function() return k and mod.cache:read("models/v" .. Engine.Scene.MODELS_VERSION .. "/" .. k .. "/" .. name) end)
            return okC and b or nil
          end,
          write = function(name, bytes)
            local k = run.gameKey()
            return k and pcall(function() mod.cache:write("models/v" .. Engine.Scene.MODELS_VERSION .. "/" .. k .. "/" .. name, bytes) end)
          end,
        }
      else
        mod.log:warn("relief: the background build is off (%s)", tostring(run))
      end
    else
      mod.log:warn("relief: the background build is off (%s)", tostring(okM and (Post and "no runner" or "no post passes") or WorldMaps))
    end
  end

  local function option(key, default)
    local ok, v = pcall(function() return mod.options and mod.options:get(key) end)
    if ok and v ~= nil then return v end
    return default
  end
  local function applyOptions()
    hd.enabled.battle = option("battle_hd", true) ~= false
    hd.enabled.field = option("field_hd", true) ~= false
    hd.enabled.dex = option("dex_hd", true) ~= false
    -- (a value saved by the old Off / Fit Sprites / Fit Tall Too choice reads as off or on)
    local fit = option("battle_fit", true)
    hd.fit.enabled = hd.fit.available and fit ~= "off" and fit ~= false
    hd.fit.fill = option("fill_screen", true) ~= false
    -- (the screens before the game starts, and the whole screens opened over the field, are
    -- only captured to fill the screen)
    hd.enabled.boot = hd.enabled.battle and hd.fit.enabled and hd.fit.fill
    hd.enabled.screen = hd.enabled.boot
    if Engine.Scene then
      Engine.Scene.enabled = option("battle_scene", "classic") == "overworld"
      Engine.Scene.cacheModels = option("scene_cache", true) ~= false
    end
  end

  local function install()
    if state.active then return end
    local ok, why = Engine.install(hd)
    if ok then
      state.active = true
      applyOptions()
      mod.log:info("drawing tagged sprites at window resolution (battle %s, field %s, Pokedex %s, Battle Fit %s)",
        hd.enabled.battle and "on" or "off", hd.enabled.field and "on" or "off",
        hd.enabled.dex and "on" or "off",
        hd.fit.enabled and "on" or (hd.fit.available and "off" or "unavailable"))
    elseif not state.warned then
      state.warned = true
      mod.log:warn("not active: %s -- every sprite is drawn the game's usual way", tostring(why))
    end
  end

  mod.events:on("game.ready", function() install() end, 0)
  if Engine.Scene then
    mod.events:on("map.entered", function(ev)
      if not (ev and ev.mapId and Engine.Scene.enabled) then return end
      -- (Scene Cache: every town's models from the first map on, read from the cache or built
      -- and kept; else this map's)
      if Engine.Scene.cacheModels and Engine.Scene.warmAll then pcall(Engine.Scene.warmAll) end
      pcall(Engine.Scene.warm, ev.mapId)
    end)
  end
  if reliefRun then
    local okI, hooked = pcall(reliefRun.install)
    if not (okI and hooked) then mod.log:warn("relief: no frame hook (%s)", tostring(hooked)) end
  end
  pcall(install)

  mod.events:on("mod.options_changed", function(ev)
    if ev and ev.mod == mod.id then applyOptions() end
  end)

  Api(mod, hd, state)
end
