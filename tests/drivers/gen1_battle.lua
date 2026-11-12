-- Driver: a Gen 1 battle with WoobleView (Red, Blue, Yellow). Puts the player on Route 1 with a
-- small party, starts a wild battle (GEN1_FOE, default ONIX), waits for the action menu and
-- screenshots it in each battle layout (GEN1_LAYOUTS, default "og,wide") and window size
-- (HD_SIZES, default 1920x1080), with Fill Screen on and off, logging WoobleView's stats.
-- GEN1_MOVES=THUNDERBOLT,PSYCHIC plays those moves too (from the player's side), shooting
-- GEN1_MOVE_SHOTS frames of each (default 10,30). Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=red POKEPORT_VERSION=red \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/gen1_battle.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = dofile("tests/drivers/util.lua")
  local dir = env("SHOT_DIR") or "/tmp/hd_gen1"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  U.wait(10)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  -- (without WoobleView: the game's own battle, for comparison)
  if not hd then
    log("WoobleView not loaded: the game's own drawing")
    hd = { stats = function() return {} end, setFill = function() end, isActive = function() return false end }
  end
  log(("WoobleView active %s"):format(tostring(hd.isActive())))

  game.save.party = {}
  for _, slot in ipairs({ { "PIKACHU", 30 }, { "MEWTWO", 70 } }) do
    table.insert(game.save.party, Pokemon.new(game.data, slot[1], slot[2]))
  end
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  if not ow then log("FAIL no overworld"); return end

  local options = game.save.options
  local foe = env("GEN1_FOE") or "ONIX"
  local function stat(k) return tostring(hd.stats()[k]) end
  for layout in (env("GEN1_LAYOUTS") or "og,wide"):gmatch("[^,]+") do
    options.battleLayout = layout
    local battle = BattleState.newWild(game, foe, 30)
    battle.onFinish = function() end
    ow:pushBattle(battle)
    local ready = false
    for _ = 1, 3000 do
      if game.stack:top() == battle and battle.phase == "menu" then ready = true break end
      U.tap(game, "a")
      U.wait(4)
    end
    if not ready then log("FAIL", layout, "battle never reached its menu (phase " .. tostring(battle.phase) .. ")"); return end
    U.wait(20)
    for size in (env("HD_SIZES") or "1920x1080"):gmatch("[^,]+") do
      local w, h = size:match("(%d+)x(%d+)")
      love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
      U.wait(10)
      for _, fill in ipairs({ true, false }) do
        hd.setFill(fill)
        U.wait(6)
        local name = ("%s/%s_%s_%s.png"):format(dir, layout, size, fill and "fill" or "nofill")
        U.shot(game, name)
        log(("%s %s fill=%s: zoom %s fillScale %s composites %s splits %s arena %s failed %s"):format(layout, size,
          tostring(fill), stat("zoom"), stat("fill"), stat("composites"), stat("splits"), stat("gen1Arena"),
          stat("failed")))
      end
      hd.setFill(true)
    end
    local moves = env("GEN1_MOVES")
    if moves then
      local shots = {}
      for n in (env("GEN1_MOVE_SHOTS") or "10,30"):gmatch("%d+") do shots[tonumber(n)] = true end
      for move in moves:gmatch("[^,]+") do
        -- as the battle's own queue starts one (BattleState.lua, the anim queue item)
        local ok, err = pcall(function()
          assert(battle.animPlayer, "no animation player")
          battle.animPlayer:start(move, true)
          battle.animPlaying = true
          battle.animName = move
          battle.animAttackerIsPlayer = true
          battle:resetPicFx()
        end)
        if not ok then log("move", move, "failed:", tostring(err)) else
          for f = 1, 400 do
            U.wait(1)
            if shots[f] then U.shot(game, ("%s/%s_move_%s_%03d.png"):format(dir, layout, move:lower(), f)) end
            if not battle.animPlaying and f > 40 then break end
          end
          log(layout, "move", move, "done")
        end
      end
    end
    -- out of the battle for the next layout
    game.stack:pop()
    U.wait(10)
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_gen1"
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
