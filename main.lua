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

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
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
  if SceneInit and sceneDeps.Camera and sceneDeps.Cells and sceneDeps.Stage and sceneDeps.Render then
    local ok, Scene = pcall(SceneInit, sceneDeps)
    if ok and type(Scene) == "table" then
      Engine.Scene = Scene
      hd.scene = Scene
      hd.sceneRenderer = Scene.render
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
    if Engine.Scene then Engine.Scene.enabled = option("battle_scene", "classic") == "overworld" end
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
  pcall(install)

  mod.events:on("mod.options_changed", function(ev)
    if ev and ev.mod == mod.id then applyOptions() end
  end)

  Api(mod, hd, state)
end
