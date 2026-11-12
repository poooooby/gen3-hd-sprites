-- Driver: Field HD in a Game Boy game (Red, Blue, Yellow, Gold, Silver, Crystal) with Vivid
-- Worlds: OG's wild Pokemon. Puts the player on Route 1 (Gen 1) or Route 29 (Gen 2), lets the
-- wild Pokemon spawn, places a few more next to the player (FIELD_SPECIES, default a big, a
-- middling and a small one), then screenshots the field in each window size (HD_SIZES,
-- default 1920x1080) with Field HD on and off, logging WoobleView's stats and the sizes
-- Vivid Worlds draws its sheets at. Run from an engine root with both mods installed:
--   SHOT_DIR=<dir> POKEPORT_VERSION=red POKEPORT_GAME=red \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/field_gb.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local gen = GameVersion.generation and GameVersion.generation() or 1
  local dir = env("SHOT_DIR") or "/tmp/hd_field_gb"
  U.wait(60)
  local exports = game.mods and game.mods.exports or {}
  local hd = exports["gen3-hd-sprites"]
  local vw = exports.vivid_worlds_og
  if not vw then log("FAIL Vivid Worlds: OG not loaded"); return end
  if not hd then
    log("WoobleView not loaded: the game's own drawing")
    hd = { stats = function() return {} end, setEnabled = function() end, isActive = function() return false end }
  end
  log(("gen %d: WoobleView active %s, Vivid Worlds engine %s"):format(gen, tostring(hd.isActive()),
    tostring(vw.engineReady)))
  local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
  if gen == 1 and okP then log("colour mode " .. tostring(PaletteFX.mode)) end
  if env("FIELD_COLORS") and gen == 1 and okP then
    PaletteFX.mode = env("FIELD_COLORS")
    log("colour mode set to " .. tostring(PaletteFX.mode))
  end

  local route, species
  if gen == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 15) }
    route, species = "ROUTE_1", "ONIX,BULBASAUR,PIDGEY"
    U.teleport(game, route, 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "TYPHLOSION", 40) }
    route, species = "ROUTE_29", "ONIX,CHIKORITA,SENTRET"
    for _ = 1, 600 do
      if game.world and game.world.map then break end
      U.wait(1)
    end
    if not game.world:setMap(route, 17, 5, "down") then log("FAIL setMap"); return end
  end
  U.wait(360)
  local sm = vw.spawnManager
  for name in (env("FIELD_SPECIES") or species):gmatch("[^,]+") do
    local placed = sm:spawnSpecies(name, 10, { radius = 3, terrain = "land" })
    log("placed " .. name .. ": " .. tostring(placed))
  end
  U.wait(90)
  local HdField = vw.hdField
  local fa = vw.followerAdapter
  local function sizeOf(r)
    local path = r and r.imagePath and r:imagePath()
    return tostring(path and path:match("[^/]+/[^/]+$")) .. " x" .. tostring(HdField and path and HdField.scaleOfPath(r.mod, path))
  end
  log("partner " .. sizeOf(fa and fa.renderer))
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and e.renderer then log("wild " .. tostring(e.species) .. " " .. sizeOf(e.renderer)) end
  end

  local function stat(k) return tostring(hd.stats()[k]) end
  for size in (env("HD_SIZES") or "1920x1080"):gmatch("[^,]+") do
    local w, h = size:match("(%d+)x(%d+)")
    love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
    -- (a new window loses Gold's baked map canvases: baked again)
    if game.world and game.world.dropBakes then game.world:dropBakes() end
    U.wait(10)
    for _, on in ipairs({ true, false }) do
      hd.setEnabled("field", on)
      U.wait(6)
      U.shot(game, ("%s/field_%s_%s.png"):format(dir, size, on and "hd" or "plain"))
      log(("%s field=%s: splits %s composites %s direct %s overCap %s offCanvas %s failed %s"):format(size,
        tostring(on), stat("splits"), stat("composites"), stat("direct"), stat("overCap"), stat("offCanvas"),
        stat("failed")))
    end
    hd.setEnabled("field", true)
  end
  -- FIELD_WALK=n: the player walks right n steps, a shot every few frames (the partner gliding)
  local steps = tonumber(env("FIELD_WALK") or "")
  if steps then
    for i = 1, steps * 16 do
      if U.hold then U.hold(game, "right", 1) else U.tap(game, "right") end
      U.wait(1)
      if i % 4 == 0 and i <= 32 then U.shot(game, ("%s/walk_%03d.png"):format(dir, i)) end
    end
    log("walked; failed " .. stat("failed"))
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_field_gb"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
