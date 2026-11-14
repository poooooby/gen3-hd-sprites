-- The relief solver's input off the engine (Battle Scene: Overworld, and any later 3D view of the
-- overworld): src/scene/relief_input.lua over the engine's cache of the player's cartridge, and
-- the solve (src/scene/relief_solve.lua) run on it. Emerald only.
--
-- deps = { Solve, Art, Input, Roles, parts = { relief_drawn, relief_shape, relief_cuts,
-- relief_world } } (the plain modules, loaded by the caller).
--
--   WorldMaps.input(tick) -> relief_input's tables, or nil and why
--   WorldMaps.solve(opt)  -> the relief model (src/scene/relief.lua's) and the solve state S, or
--                            nil and why; opt.tick (called now and then: run it in a coroutine and
--                            yield there), opt.phase(name) (as each phase ends), opt.parts (more
--                            parts: the terraces' three), opt.fixes / fixesOrder / jsonNull (the
--                            hand marks), opt.Relief, opt.models(layoutName) (the buildings' cells),
--                            opt.regionTies (only without the terraces' parts)

return function(deps)
  local WorldMaps = {}

  local function req(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  function WorldMaps.input(tick)
    local Dataset, Constants = req("src.core.game3.dataset"), req("src.core.game3.constants")
    local Perm = req("src.core.CollPermissions")
    local json = deps.json
    local okC, cache = pcall(function() return Dataset and Dataset.cache() end)
    if not (okC and cache and json and Constants and Perm) then return nil, "no cache" end
    -- Emerald's behaviour enum, its raw values (pret's include/constants/metatile_behaviors.h)
    local okB, byName = pcall(function() return Constants.of("emerald").metatile_behaviors.byName end)
    if not (okB and type(byName) == "table") then return nil, "no behaviours" end
    local behaviours = {}
    for name, v in pairs(byName) do
      if type(name) == "string" and name:match("^MB_") and type(v) == "number" then behaviours[name] = v end
    end
    -- (rel under the engine's cache root, from its own constants: src/scene/cache.lua)
    local Cache = deps.Cache
    if not (Cache and Cache.root()) then return nil, "no cache root" end
    local io_ = {
      read = function(rel) return Cache.read(rel) end,
      json = function(text)
        local ok, t = pcall(json, text)
        return ok and t or nil
      end,
      lua = function(src)
        local chunk = src and load(src, "=cache", "t", {})
        if not chunk then return nil end
        local ok, t = pcall(chunk)
        return ok and t or nil
      end,
      behaviours = behaviours,
      -- (an alternate layout's baked cell, its metatile not the base's there: pret's collision bits
      -- are set on walls and on ledges' jump cells)
      collBlocked = function(c) return Perm.isWall(c) or Perm.isLedge(c) end,
      tick = tick,
    }
    local ok, input = pcall(deps.Input.build, io_, deps.Art.palettes)
    if not ok then return nil, tostring(input) end
    if not next(input.layouts) then return nil, "no Emerald layouts" end
    return input
  end

  function WorldMaps.solve(opt)
    opt = opt or {}
    local input, why = WorldMaps.input(opt.tick)
    if not input then return nil, why end
    -- (the solver's parts, then any more the caller joins: the terraces')
    local parts = {}
    for _, p in ipairs(deps.parts) do parts[#parts + 1] = p end
    for _, p in ipairs(opt.parts or {}) do parts[#parts + 1] = p end
    return deps.Solve.run(input, { Art = deps.Art, Roles = deps.Roles, parts = parts,
                                   regionTies = opt.regionTies, tick = opt.tick, phase = opt.phase,
                                   fixes = opt.fixes, fixesOrder = opt.fixesOrder, jsonNull = opt.jsonNull,
                                   Relief = opt.Relief, models = opt.models })
  end

  return WorldMaps
end
