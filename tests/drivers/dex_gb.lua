-- Driver: Pokedex & Summary HD in a Game Boy game (Red, Blue, Yellow, Gold, Silver, Crystal) with
-- a sprite mod that tags its Pokedex frames (WoobleSpritePack). Puts the player in the field,
-- then opens the Pokedex (Gen 2: its list, then the entry) and the summary of a party Pokemon,
-- and shoots each in every colour mode of DEX_COLORS (Gen 1: PaletteFX modes, default
-- "gbc,redpp"; Gen 2: GbcPalette modes, default "gbc,dmg"): with Pokedex & Summary HD on, off,
-- and on without Fill Screen. DEX_SPECIES (default CHARIZARD) is the Pokemon shown; DEX_SIZE
-- (default 1920x1080) the window. Run from an engine root with the mods installed:
--   SHOT_DIR=<dir> POKEPORT_VERSION=red POKEPORT_GAME=red \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/dex_gb.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local gen = GameVersion.generation and GameVersion.generation() or 1
  local dir = env("SHOT_DIR") or "/tmp/hd_dex_gb"
  U.wait(60)
  local exports = game.mods and game.mods.exports or {}
  local hd = exports["gen3-hd-sprites"]
  if not hd then
    log("WoobleView not loaded: the game's own drawing")
    hd = { stats = function() return {} end, setEnabled = function() end, setFill = function() end,
           isActive = function() return false end }
  end
  -- (diagnostics: DEX_PATCH=notag drops every tag, noshades a tag's shades)
  local patch = env("DEX_PATCH")
  if patch and hd.tag then
    local tag = hd.tag
    hd.tag = function(image, spec)
      if patch == "notag" then return end
      if patch == "noshades" and type(spec) == "table" then spec.shades = nil end
      return tag(image, spec)
    end
  end
  local w, h = (env("DEX_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
  local species = env("DEX_SPECIES") or "CHARIZARD"
  log(("gen %d: WoobleView active %s, showing %s"):format(gen, tostring(hd.isActive()), species))

  local mon
  if gen == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    mon = Pokemon.new(game.data, species, 36)
    game.save.party = { mon, Pokemon.new(game.data, "PIKACHU", 15) }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    mon = Mon.new(game.data, species, 36)
    game.save.party = { mon }
    for _ = 1, 600 do
      if game.world and game.world.map then break end
      U.wait(1)
    end
    if not game.world:setMap("ROUTE_29", 17, 5, "down") then log("FAIL setMap"); return end
    if game.world.dropBakes then game.world:dropBakes() end
  end
  -- every species seen and owned
  game.save.pokedex = game.save.pokedex or {}
  local dex = game.save.pokedex
  dex.seen, dex.owned, dex.caught = dex.seen or {}, dex.owned or {}, dex.caught or {}
  for id in pairs(game.data.pokemon or {}) do dex.seen[id], dex.owned[id], dex.caught[id] = true, true, true end
  U.wait(60)

  local function stat(k) return tostring(hd.stats()[k]) end
  local function setColors(mode)
    if gen == 1 then
      local P = require("src.render.PaletteFX")
      if P.setMode then P.setMode(mode) else P.mode = mode end
    else
      require("src.render.GbcPalette").mode = mode
    end
  end
  local function shots(name)
    local kinds = { hd = { "hd", true, true }, nohd = { "nohd", false, true }, plain = { "plain", true, false },
                    bare = { "bare", false, false, true }, bare_dex = { "bare_dex", true, false, true } }
    for kind in (env("DEX_SHOTS") or "hd,nohd,plain"):gmatch("[^,]+") do
      local v = kinds[kind]
      hd.setEnabled("dex", v[2])
      hd.setFill(v[3])
      hd.setEnabled("screen", not v[4])
      U.wait(4)
      U.still(game, ("%s/%s_%s.png"):format(dir, name, v[1]))
      U.still(game, ("%s/%s_%s_b.png"):format(dir, name, v[1]))
    end
    hd.setEnabled("dex", true)
    hd.setEnabled("screen", true)
    hd.setFill(true)
    log(("%s: dexPasses %s dexInPass %s screenPasses %s direct %s shaded %s card %s failed %s"):format(name,
      stat("dexPasses"), stat("dexInPass"), stat("screenPasses"), stat("direct"), stat("shaded"),
      stat("card"), stat("failed")))
  end
  local function close()
    for _ = 1, 20 do
      if game.stack:top() == game.overworld then return end
      game.stack:pop()
      U.wait(4)
    end
  end

  local modes = env("DEX_COLORS") or (gen == 1 and "gbc,redpp" or "gbc,dmg")
  for mode in modes:gmatch("[^,]+") do
    setColors(mode)
    if gen == 1 then
      local DexEntryMenu = require("src.ui.DexEntryMenu")
      game.stack:push(DexEntryMenu.new(game, species))
      U.wait(90)
      shots(mode .. "_1_dex_entry")
      close()
      local SummaryMenu = require("src.ui.SummaryMenu")
      game.stack:push(SummaryMenu.new(game, mon))
      U.wait(30)
      shots(mode .. "_2_summary")
      close()
    else
      local PokedexMenu = require("src.ui.gen2.PokedexMenu")
      game.stack:push(PokedexMenu.new(game, {}))
      U.wait(40)
      shots(mode .. "_1_dex_list")
      U.tap(game, "a")
      U.wait(90)
      shots(mode .. "_2_dex_entry")
      close()
      local SummaryMenu = require("src.ui.gen2.SummaryMenu")
      game.stack:push(SummaryMenu.new(game, { mon = mon }))
      U.wait(40)
      shots(mode .. "_3_summary")
      close()
    end
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_dex_gb"
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
