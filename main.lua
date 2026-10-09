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

  -- the engine does not register a mod's options from its manifest: define them here
  local schema = loadSibling(mod, "options.lua")
  if type(schema) == "table" and mod.options and mod.options.define then
    pcall(mod.options.define, mod.options, schema)
  end

  local hd = HD.new(love.graphics, { log = mod.log })
  local state = { active = false }

  local function option(key, default)
    local ok, v = pcall(function() return mod.options and mod.options:get(key) end)
    if ok and v ~= nil then return v end
    return default
  end
  local function applyOptions()
    hd.enabled.battle = option("battle_hd", true) ~= false
    hd.enabled.field = option("field_hd", true) ~= false
  end

  local function install()
    if state.active then return end
    local ok, why = Engine.install(hd)
    if ok then
      state.active = true
      applyOptions()
      mod.log:info("drawing tagged sprites at window resolution (battle %s, field %s)",
        hd.enabled.battle and "on" or "off", hd.enabled.field and "on" or "off")
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
