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
-- (the engine cache's bytes at a path under its root, for the fingerprint), onReady(bytes), onFrame() (called every frame
-- first: the scene's model warm-up), log }.
--
--   Run.state() -> "idle" | "cached" | "running" | "ready" | "failed", detail
--   Run.start()    begin (or serve the cache) for the current game; no-op while running
--   Run.progress() how far a build has come, 0..1 (for the Build 3D Cache bar)
--   Run.clear()    the cached relief deleted, back to idle (Clear 3D Cache)
-- deps.wanted() (optional): whether to start at all - the frame hook starts the build only then
-- (the battle scene on).

return function(deps)
  local Relief, Post, WorldMaps, Terraces = deps.Relief, deps.Post, deps.WorldMaps, deps.Terraces
  local Run = { VERSION = 1, SLICE = 0.003, _ticks = 0, _phaseTicks = 0 }

  local state, detail = "idle", nil
  local co, clock
  local game, key, phases

  -- ── progress by the work done ────────────────────────────────────────
  -- The build makes the same ticks for the same map data on every device; what a tick costs differs
  -- by phase (a world tick does far more than an export one), so each phase's ticks are weighted by
  -- its cost. Measured in a whole Emerald build on a desktop (ms a tick; 117030 ticks, 87 s):
  Run.TICK_COST = { groups = 0.32, world = 1.96, export = 0.37, terraces = 1.61, finish = 1.05 }
  -- each phase's ticks in a whole build, by game (the build counts its own and keeps them beside the
  -- relief, `<key>.ticks`: other map data under the same game reads those instead)
  Run.TICKS = {
    emerald = { groups = 1165, world = 8601, export = 82851, terraces = 24157, finish = 256 },
  }
  -- the phase a finished one leads to (src/scene/world_maps.lua and the pipeline below name them)
  local function nextBucket(name)
    if name == "groups" then return "world" end
    if name == "world" then return "export" end
    if name == "export" or name:find("^terraces:") then return "terraces" end
    return "finish"
  end
  local function bucketOf(name)
    if name == "groups" or name == "world" or name == "export" then return name end
    if name:find("^terraces:") then return "terraces" end
    return "finish"
  end
  local work = { done = 0, total = nil, bucket = "groups", ticks = {} }
  local function workOf(counts)
    if type(counts) ~= "table" then return nil end
    local w = 0
    for b, cost in pairs(Run.TICK_COST) do w = w + (tonumber(counts[b]) or 0) * cost end
    return w > 0 and w or nil
  end
  local function ticksKey() return key and (key:gsub("%.bin$", ".ticks")) or nil end
  local function readTicks()
    local k = ticksKey()
    local ok, text = pcall(function() return k and deps.cache and deps.cache:read(k) end)
    if not (ok and type(text) == "string") then return nil end
    local counts = {}
    for b, n in text:gmatch("(%a+)%s+(%d+)") do counts[b] = tonumber(n) end
    return next(counts) and counts or nil
  end
  local function writeTicks()
    local k = ticksKey()
    if not (k and deps.cache) then return end
    local lines = {}
    for b in pairs(Run.TICK_COST) do lines[#lines + 1] = ("%s %d"):format(b, work.ticks[b] or 0) end
    table.sort(lines)
    pcall(function() deps.cache:write(k, table.concat(lines, "\n")) end)
  end

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

  -- (the fingerprint read and hashed once a game: its map data does not change while it runs,
  -- and every model's file asks for the key - gameKey() - so it is kept)
  local keyId, keyOf, gameKeyOf
  local function cacheKey()
    local V = deps.version
    if not (V and V.get) then return nil end
    local okG, id = pcall(V.get)
    if not (okG and type(id) == "string") then return nil end
    if id == keyId then return keyOf, id end
    -- (paths under the engine's cache root)
    local census = deps.readCache and deps.readCache("map_tree/census.json")
    if type(census) ~= "string" then return nil end
    local files = deps.readCache("native/layout_files.lua") or ""
    local fp = fnv(files, fnv(census))
    keyId = id
    keyOf = ("relief/v%d/%s-%08x.bin"):format(Run.VERSION, id, fp)
    gameKeyOf = keyOf:match("/([^/]+)%.bin$")
    return keyOf, id
  end

  local function ready(bytes, how)
    state, detail = "ready", how
    if deps.onReady then pcall(deps.onReady, bytes) end
  end

  -- the whole pipeline, run inside the coroutine
  local function pipeline()
    local tick = function()
      -- (the work done: the build makes the same ticks on every device - Run.progress)
      Run._ticks = Run._ticks + 1
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
      -- (its time and its ticks: what each phase costs a tick, for Run.TICK_COST)
      local n = Run._ticks - Run._phaseTicks
      phases[#phases + 1] = ("%s %.0f ms %d t"):format(name, (t - Run._phaseAt) * 1000, n)
      Run._phaseAt, Run._phaseTicks = t, Run._ticks
      -- (the work done so far, by the phase's cost a tick; and the phase now under way)
      local b = bucketOf(name)
      work.ticks[b] = (work.ticks[b] or 0) + n
      work.done = work.done + n * (Run.TICK_COST[b] or 1)
      work.bucket = nextBucket(name)
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
    Run._startAt = Run._phaseAt
    Run._ticks, Run._phaseTicks = 0, 0
    -- (the whole build's work: this map data's own counts if a build kept them, else the game's)
    work = { done = 0, bucket = "groups", ticks = {},
             total = workOf(readTicks()) or workOf(Run.TICKS[game]) }
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
        writeTicks()
        ready(bytes, "built")
        log("%s: relief built (%d KiB): %s", game, math.floor(#bytes / 1024), table.concat(phases, ", "))
      else
        state, detail = "failed", tostring(why)
        log("relief build failed: %s", tostring(why))
      end
    end
  end

  function Run.state() return state, detail, phases end

  --- The phase under way while running ("groups", "world", "export", "terraces", "finish"), or nil.
  function Run.phase() return state == "running" and work.bucket or nil end

  -- how far a build has come, 0..1: the work done (each phase's ticks by its cost a tick) over the
  -- whole build's (Run.TICKS, or the counts a build of this map data kept). The same ticks come on
  -- every device, so the bar moves at a steady pace wherever it runs - on a phone a phase that
  -- takes a larger share of the time no longer stalls it (and the time left with it).
  -- Without a known whole, by the phases passed instead (their shares of a desktop build's time:
  -- the groups 2%, the world 21%, the export 35%, the 29 terrace groups 42%), creeping on within a
  -- phase at the pace kept so far.
  Run.TERRACE_GROUPS = 29
  Run.GUESS_SECONDS = 90      -- a whole build's time, before the world's phase has measured it
  function Run.progress()
    if state == "ready" then return 1 end
    if state ~= "running" or not phases then return 0 end
    if work.total then
      local now = work.done + (Run._ticks - Run._phaseTicks) * (Run.TICK_COST[work.bucket] or 1)
      return math.max(0, math.min(now / work.total, 0.995))
    end
    local p, terraces = 0, 0
    local groups, world, export = false, false, false
    for i = 1, #phases do
      local ph = phases[i]
      if ph:find("^groups ") then p = math.max(p, 0.02); groups = true
      elseif ph:find("^world ") then p = math.max(p, 0.23); world = true
      elseif ph:find("^export ") then p = math.max(p, 0.58); export = true
      elseif ph:find("^terraces:") then terraces = terraces + 1 end
    end
    local tShare = 0.415 / Run.TERRACE_GROUPS
    p = p + tShare * math.min(terraces, Run.TERRACE_GROUPS)
    -- the phase under way: its share, and how far into it by the pace so far
    local share = not groups and 0.02 or not world and 0.21 or not export and 0.35
      or terraces < Run.TERRACE_GROUPS and tShare or 0.005
    local now = clock and clock() or 0
    local start, at = Run._startAt or now, Run._phaseAt or now
    -- (the groups' phase is too short to judge the pace by: the guess until the world's is done)
    local perShare = p >= 0.23 and (at - start) / p or Run.GUESS_SECONDS
    local into = perShare > 0 and (now - at) / (perShare * share) or 0
    return math.min(p + share * math.min(0.95, math.max(0, into)), 0.995)
  end

  --- Forget the relief (Clear cache): the cached file deleted, the state back to idle, so the next
  --- start builds it again.
  function Run.clear()
    co, phases = nil, nil
    local k = cacheKey()
    if k and deps.cache and deps.cache.delete then pcall(deps.cache.delete, deps.cache, k) end
    state, detail = "idle", "cleared"
  end

  --- "<game>-<fingerprint>" of the current game's map data (what the cache is keyed by), or nil.
  function Run.gameKey()
    if not cacheKey() then return nil end
    return gameKeyOf
  end

  --- Hook the engine's frame; start when a game is up.
  function Run.install()
    if not (deps.hooks and deps.hooks.wrap) then return false end
    deps.hooks:wrap("core.update", function(next, g, dt)
      next(g, dt)
      if deps.onFrame then pcall(deps.onFrame) end
      -- (only while it is wanted: deps.wanted(), the battle scene on)
      if state == "idle" and (not deps.wanted or deps.wanted()) then Run.start() end
      Run.step()
    end)
    return true
  end

  return Run
end
