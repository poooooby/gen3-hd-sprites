-- The relief, built once a game in the background (Battle Scene: Overworld, and any later 3D
-- view of the overworld: nothing here knows of battles).
--
-- Emerald 3DS builds its relief offline (gen_voxel_relief.py, voxel_terraces.py, its hand marks)
-- and ships the result. WoobleView builds the same bytes in the game from the player's own
-- cartridge, the first time a game is played: the solver (src/scene/relief_solve.lua and parts),
-- the terraces (src/scene/relief_terraces.lua), the last passes (src/scene/relief_post.lua), run
-- in a coroutine a few milliseconds a frame while the player walks about, and the result kept in
-- the mod's cache (mod.cache: keyed by the game and a fingerprint of its map data, and this
-- pipeline's version), so every later session reads it in a frame.
--
-- Run.install(deps) hooks core.update. deps = { Relief, Post, WorldMaps, Terraces (the three
-- relief_terraces* modules, optional: without them only a cached relief is served), models(name)
-- -> { [Solve.K(x, y)] = true } the cells the building models own in a layout (or nil), fixes
-- (the hand marks' JSON text), cache
-- (mod.cache), hooks (mod.hooks), version (GameVersion-like: get() -> game id), readCache(rel)
-- (the engine cache's bytes, for the fingerprint), onReady(bytes), onFrame() (called every frame
-- first: the scene's model warm-up), log }.
--
--   Run.state() -> "idle" | "cached" | "running" | "ready" | "failed", detail
--   Run.start()    begin (or serve the cache) for the current game; no-op while running

return function(deps)
  local Relief, Post, WorldMaps, Terraces = deps.Relief, deps.Post, deps.WorldMaps, deps.Terraces
  local Run = { VERSION = 1, SLICE = 0.003 }

  local state, detail = "idle", nil
  local co, clock
  local game, key, phases

  local function log(fmt, ...)
    if deps.log and deps.log.info then pcall(deps.log.info, deps.log, "[relief] " .. fmt, ...) end
  end

  -- FNV-1a over a string, 32 bits
  local function fnv(s, h)
    h = h or 2166136261
    for i = 1, #s do
      h = bit.bxor(h, s:byte(i))
      h = (h * 16777619) % 4294967296
    end
    return h
  end

  local function cacheKey()
    local okG, id = pcall(function() return deps.version.get() end)
    if not (okG and type(id) == "string") then return nil end
    local census = deps.readCache and deps.readCache("data/generated/gba/map_tree/census.json")
    if type(census) ~= "string" then return nil end
    local files = deps.readCache("data/generated/gba/native/layout_files.lua") or ""
    local fp = fnv(files, fnv(census))
    return ("relief/v%d/%s-%08x.bin"):format(Run.VERSION, id, fp), id
  end

  local function ready(bytes, how)
    state, detail = "ready", how
    if deps.onReady then pcall(deps.onReady, bytes) end
  end

  -- the whole pipeline, run inside the coroutine
  local function pipeline()
    local tick = function()
      local t = clock()
      -- (dev: Run.watch = seconds; every stretch between two ticks longer than that, where it
      -- ended and the heap then, in Run.gaps)
      if Run.watch then
        if t - Run._lastTick > Run.watch then
          Run.gaps[#Run.gaps + 1] = { (t - Run._lastTick) * 1000, debug and debug.traceback("", 2) or "?",
                                      collectgarbage and collectgarbage("count") / 1024 or 0,
                                      phases[#phases] or "-" }
        end
        Run._lastTick = t
      end
      if t - Run._sliceStart >= Run.SLICE then coroutine.yield() end
    end
    local function phase(name)
      local t = clock()
      phases[#phases + 1] = ("%s %.0f ms"):format(name, (t - Run._phaseAt) * 1000)
      Run._phaseAt = t
    end
    local fixes, order = Post.json(deps.fixes or "{}", tick)
    local model, S = WorldMaps.solve({
      tick = tick, phase = phase,
      -- (the terraces: their three parts join the solve; the hand marks, the buildings' cells)
      parts = Terraces,
      fixes = fixes, fixesOrder = order, jsonNull = Post.NULL, Relief = Relief,
      models = deps.models and function(name) return deps.models(name, tick) end or nil,
    })
    if not model then return nil, S end
    phase("export")
    if S.T then
      S.T.apply(model)
      phase("terraces")
    end
    -- the last passes, over the maps as the solver read them
    local input = S.input
    local links = S.mapLinks()
    local MB = input.behaviours
    local waterRaw = {}
    for _, n in ipairs(deps.Roles and deps.Roles.WATER_NAMES or {}) do
      if MB[n] then waterRaw[MB[n]] = true end
    end
    local world = {
      index = function(name) local L = input.byName[name]; return L and L.id end,
      size = function(name) local L = input.byName[name]; return L.w, L.h end,
      links = links,
      tilesets = function(name) local L = input.byName[name]; return L.primary.name, L.secondary.name end,
      metatile = function(name, x, y) local L = input.byName[name]; return L.blocks[y * L.w + x] % 1024 end,
      isWater = function(name, m)
        local L = input.byName[name]
        local ts = m < 512 and L.primary or L.secondary
        local i = m - (m < 512 and 0 or 512)
        local a = ts.attributes
        if not a or 2 * i + 2 > #a then return false end
        return waterRaw[a:byte(2 * i + 1)] == true
      end,
    }
    Post.seaRamps(model, world)
    tick()
    Post.cutFeet(model)
    tick()
    Post.applyFixes(model, world, fixes, order, tick)
    phase("post")
    local bytes = Relief.encode(model, Post.seamEases(model, world), tick)
    phase("encode")
    return bytes
  end

  function Run.start()
    if state == "running" or state == "ready" then return end
    clock = (love and love.timer and love.timer.getTime) or os.clock
    local k, id = cacheKey()
    if not k then state, detail = "idle", "no game"; return end
    key, game = k, id
    local okR, cached = pcall(function() return deps.cache and deps.cache:read(key) end)
    if okR and type(cached) == "string" and #cached > 16 and Relief.decode(cached) then
      ready(cached, "cached")
      log("%s: relief read from the cache (%d KiB)", game, math.floor(#cached / 1024))
      return
    end
    if not (Terraces and WorldMaps) then
      state, detail = "idle", "no solver"
      return
    end
    phases = {}
    Run._phaseAt = clock()
    co = coroutine.create(pipeline)
    state, detail = "running", nil
    log("%s: building the relief in the background", game)
  end

  --- One slice of the build: at most Run.SLICE seconds of it.
  function Run.step()
    if state ~= "running" or not co then return end
    Run._sliceStart = clock()
    Run._lastTick = Run._sliceStart
    local ok, bytes, why = coroutine.resume(co)
    if not ok then
      state, detail = "failed", tostring(bytes)
      log("relief build failed: %s", tostring(bytes))
      co = nil
    elseif coroutine.status(co) == "dead" then
      co = nil
      if bytes then
        pcall(function() if deps.cache then deps.cache:write(key, bytes) end end)
        ready(bytes, "built")
        log("%s: relief built (%d KiB): %s", game, math.floor(#bytes / 1024), table.concat(phases, ", "))
      else
        state, detail = "failed", tostring(why)
        log("relief build failed: %s", tostring(why))
      end
    end
  end

  function Run.state() return state, detail, phases end

  --- "<game>-<fingerprint>" of the current game's map data (what the cache is keyed by), or nil.
  function Run.gameKey()
    local k, id = cacheKey()
    if not k then return nil end
    return k:match("/([^/]+)%.bin$")
  end

  --- Hook the engine's frame; start when a game is up.
  function Run.install()
    if not (deps.hooks and deps.hooks.wrap) then return false end
    deps.hooks:wrap("core.update", function(next, g, dt)
      next(g, dt)
      if deps.onFrame then pcall(deps.onFrame) end
      if state == "idle" then Run.start() end
      Run.step()
    end)
    return true
  end

  return Run
end
