-- Driver: a Gen 2 battle with WoobleView (Gold, Silver, Crystal). Puts the player on Route 29 with
-- a small party, starts a wild battle (GEN2_FOE, default ONIX), waits for the FIGHT menu and
-- screenshots it in each window size (HD_SIZES, default 1920x1080), with Fill Screen on and off,
-- logging WoobleView's stats; GEN2_LAYOUTS=og,wide shoots each battle layout. GEN2_MENUS=1 also
-- opens the menus over the battle (PKMN: the party, then a summary; PACK; a text box) and shoots each with
-- Fill Screen on and off. GEN2_FIT=on|off sets Battle Fit; GEN2_MAP=MAP:x:y the place; GEN2_STAGES the stat stages
-- (player:attack=2,defense=-1;enemy:speed=1); GEN2_MON the
-- player's Pokemon (default TYPHLOSION), GEN2_MOVESET its moves; GEN2_FIGHT=n a real turn shot
-- every 3 frames (GEN2_FILL_ONLY=1: no Fill Screen off shots before it); GEN2_SLIDE_SHOTS=0,20,40 shoots those frames of the
-- intro slide; GEN2_INTRO_EVERY=n a shot every n steps from there to the menu. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/gen2_battle.lua love .

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = dofile("tests/drivers/util.lua")
  local dir = env("SHOT_DIR") or "/tmp/hd_gen2"
  local Mon = require("src.battle.gen2.Mon")
  local Permissions = require("src.world.gen2.Permissions")
  for _ = 1, 600 do
    if game.world and game.world.map then break end
    U.wait(1)
  end
  local world = game.world
  if not (world and world.map) then log("FAIL the world did not boot"); return end
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then
    log("WoobleView not loaded: the game's own drawing")
    hd = { stats = function() return {} end, setFill = function() end, isActive = function() return false end }
  end
  log(("WoobleView active %s"):format(tostring(hd.isActive())))
  -- GEN2_HD=off: Battle HD off (the game's own battle drawing, other mods' as they are)
  if env("GEN2_HD") == "off" and hd.setEnabled then hd.setEnabled("battle", false) end
  -- GEN2_FIT=on|off: Battle Fit
  if env("GEN2_FIT") and hd.setFit then hd.setFit(env("GEN2_FIT") ~= "off" and env("GEN2_FIT") or false) end

  -- GEN2_FACETS=set[:borders]: Facets' battle scene set (its BATTLE BG, e.g. scenery) and its
  -- BORDERS (blur, fill, off)
  if env("GEN2_FACETS") then
    local set, borders = env("GEN2_FACETS"):match("^([^:]+):?(%a*)$")
    loader.modOptions.facets = loader.modOptions.facets or {}
    loader.modOptions.facets.classicBattleBg = set
    if borders and borders ~= "" then loader.modOptions.facets.sceneBorders = borders end
  end
  -- GEN2_MON: the player's Pokemon (default TYPHLOSION)
  -- GEN2_MOVESET=BODY_SLAM,TACKLE: its moves (default its level-up ones)
  local moveset
  if env("GEN2_MOVESET") then
    moveset = {}
    for id in env("GEN2_MOVESET"):gmatch("[^,]+") do
      local def = game.data.moves and game.data.moves[id]
      moveset[#moveset + 1] = { id = id, pp = def and def.pp or 10, maxPp = def and def.pp or 10 }
    end
  end
  game.save.party = { Mon.new(game.data, env("GEN2_MON") or "TYPHLOSION", 40, { moves = moveset }) }
  game.save.inventory = { POKE_BALL = 5, POTION = 3 }
  -- the battle starts in GEN2_LAYOUTS's first layout (its intro too)
  if (env("GEN2_LAYOUTS") or "og"):match("^[^,]+") == "wide" then game.options.battleLayout = "wide" end
  -- GEN2_MAP=MAP:x:y: where the battle is (default ROUTE_29:15:11; a town gives a town scene)
  local mapId, mx, my = (env("GEN2_MAP") or "ROUTE_29:15:11"):match("^([%w_]+):(%d+):(%d+)$")
  mx, my = tonumber(mx), tonumber(my)
  if not world:setMap(mapId, mx, my, "down") then log("FAIL setMap"); return end
  U.wait(8)
  if not Permissions.isWalkable(world:playerCollision()) then
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 } }) do
      if world:setMap(mapId, mx + step[1], my + step[2], "down")
          and Permissions.isWalkable(world:playerCollision()) then
        break
      end
    end
    U.wait(8)
  end
  game.options.battleBg = "white"
  local foe = env("GEN2_FOE") or "ONIX"
  if not world:startBattle({ wild = Mon.new(game.data, foe, 30) }) then log("FAIL startBattle"); return end
  local battle
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  if not battle then log("FAIL no battle"); return end
  -- GEN2_SLIDE_SHOTS=0,20,40: the intro slide shot at those of its frames (battle.slideFrame),
  -- in the first of HD_SIZES
  if env("GEN2_SLIDE_SHOTS") then
    local w, h = (env("HD_SIZES") or "1920x1080"):match("(%d+)x(%d+)")
    love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
    for n in env("GEN2_SLIDE_SHOTS"):gmatch("%d+") do
      local want = tonumber(n)
      for _ = 1, 600 do
        if type(battle.slideFrame) == "number" and battle.slideFrame >= want then break end
        U.wait(1)
      end
      U.shot(game, ("%s/slide_%03d.png"):format(dir, want))
    end
  end
  -- GEN2_INTRO_EVERY=n: a shot every n of these steps (2 frames each) until the menu
  local every = tonumber(env("GEN2_INTRO_EVERY") or "")
  for i = 1, 300 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(2)
    if every and i % every == 0 then
      U.shot(game, ("%s/intro_%03d.png"):format(dir, i))
      log(("  intro %d: uiTopDy %s grow %s"):format(i, tostring(hd.stats().uiTopDy), tostring(hd.stats().grow)))
    end
  end
  if battle.phase ~= "menu" then log("FAIL battle never reached its menu (phase " .. tostring(battle.phase) .. ")"); return end
  -- GEN2_STAGES=player:attack=2,defense=-1;enemy:speed=1: stat stages set (battle.stages[side],
  -- the keys the engine's: attack, defense, speed, specialAttack, specialDefense, accuracy,
  -- evasion), as moves would leave them (National Dex's Stat Hints show them by the HP boxes)
  if env("GEN2_STAGES") and type(battle.battle) == "table" then
    battle.battle.stages = battle.battle.stages or {}
    for side, list in env("GEN2_STAGES"):gmatch("(%a+):([^;]+)") do
      local st = battle.battle.stages[side] or {}
      battle.battle.stages[side] = st
      for key, v in list:gmatch("(%a+)=(%-?%d+)") do st[key] = tonumber(v) end
    end
    log("stages set:", env("GEN2_STAGES"))
  end
  U.wait(20)
  local function stat(k) return tostring(hd.stats()[k]) end
  -- GEN2_LAYOUTS=og,wide: each battle layout in turn (the game reads it every frame)
  local before = game.options.battleLayout
  for layout in (env("GEN2_LAYOUTS") or "og"):gmatch("[^,]+") do
    game.options.battleLayout = layout == "wide" and "wide" or "og"
    for size in (env("HD_SIZES") or "1920x1080"):gmatch("[^,]+") do
      local w, h = size:match("(%d+)x(%d+)")
      love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
      U.wait(10)
      for _, fill in ipairs(env("GEN2_FILL_ONLY") and { true } or { true, false }) do
        hd.setFill(fill)
        U.wait(6)
        U.shot(game, ("%s/%s_%s_%s.png"):format(dir, layout, size, fill and "fill" or "nofill"))
        log(("%s %s fill=%s: zoom %s fillScale %s uiScale %s composites %s failed %s"):format(layout, size,
          tostring(fill), stat("zoom"), stat("fill"), stat("uiScale"), stat("composites"), stat("failed")))
        log(("  fit: zoomTarget %s lift %s extraLift %s backTop %s raise %s drop %s hidden own %s enemy %s"):format(
          stat("zoomTarget"), stat("lift"), stat("extraLift"), stat("backTop"), stat("raisePlayer"),
          stat("dropPlayer"), stat("hiddenOwnUI"), stat("hiddenEnemyUI")))
      end
      hd.setFill(true)
    end
  end
  -- GEN2_MENUS=1: the menus over the battle, from its action menu (FIGHT PKMN / PACK RUN)
  if env("GEN2_MENUS") then
    local names = {}
    for name, m in pairs(package.loaded) do
      if type(m) == "table" and name:match("^src%.ui%.") then names[m] = name end
    end
    local function top()
      local t = game.stack:top()
      local mt = t and getmetatable(t)
      return t and (names[mt] or (mt and names[mt.__index])) or tostring(t)
    end
    local function both(name)
      for _, fill in ipairs({ true, false }) do
        hd.setFill(fill)
        U.wait(6)
        U.shot(game, ("%s/menu_%s_%s.png"):format(dir, name, fill and "fill" or "nofill"))
      end
      hd.setFill(true)
      log(("menu %s (%s, %d states): composites %s failed %s"):format(name, top(), #game.stack.states,
        stat("composites"), stat("failed")))
    end
    local function back()
      for _ = 1, 20 do
        if game.stack:top() == battle and battle.phase == "menu" then return true end
        U.tap(game, "b")
        U.wait(10)
      end
      log("stuck at " .. top())
      return false
    end
    local function press(btn, n)
      for _ = 1, n or 1 do U.tap(game, btn); U.wait(8) end
    end
    -- PKMN
    press("right"); press("a"); U.wait(30)
    both("party")
    press("a"); U.wait(10)
    both("party_choice")
    press("a"); U.wait(30)
    both("summary")
    if back() then
      -- PACK
      press("left"); press("down"); press("a"); U.wait(30)
      both("pack")
      back()
    end
    -- a text box over the battle (a state of its own, as a script's message is)
    if game.say then
      game:say("A message over\nthe battle.")
      U.wait(40)
      both("textbox")
      for _ = 1, 6 do
        if game.stack:top() == battle then break end
        press("a")
      end
    end
  end
  -- GEN2_FIGHT=n: a real turn, the first move from FIGHT, shot every 3 frames for n frames
  -- (fight_NNN.png), logging where the enemy's HP box stands (uiTopDy)
  if env("GEN2_FIGHT") then
    U.tap(game, "a"); U.wait(10)
    U.tap(game, "a")
    for f = 1, tonumber(env("GEN2_FIGHT")) do
      U.wait(1)
      if f % 3 == 0 then
        U.shot(game, ("%s/fight_%03d.png"):format(dir, f))
        log(("  fight %d: phase %s uiTopDy %s zoom %s"):format(f, tostring(battle.phase), stat("uiTopDy"), stat("zoom")))
      end
      if f % 20 == 0 and battle.phase ~= "menu" then U.tap(game, "a") end
    end
  end
  -- GEN2_MOVES=PSYCHIC,EARTHQUAKE: those moves' animations (the player's turn), shot at
  -- GEN2_MOVE_SHOTS frames (default 10,30)
  local moves = env("GEN2_MOVES")
  if moves then
    local shots = {}
    for n in (env("GEN2_MOVE_SHOTS") or "10,30"):gmatch("%d+") do shots[tonumber(n)] = true end
    for move in moves:gmatch("[^,]+") do
      local ok, started = pcall(battle.animForMove, battle, move, "player", 0)
      if not (ok and started) then
        log("move", move, "did not start:", tostring(started))
      else
        for f = 1, 600 do
          U.wait(1)
          if shots[f] then
            U.shot(game, ("%s/og_move_%s_%03d.png"):format(dir, move:lower(), f))
            log(("  %s %d: zoom %s zoomTarget %s uiTopDy %s lift %s"):format(move, f, stat("zoom"),
              stat("zoomTarget"), stat("uiTopDy"), stat("lift")))
          end
          if not battle.anim and f > 40 then break end
        end
        log("move", move, "done, composites", stat("composites"), "failed", stat("failed"))
      end
    end
  end
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_gen2"
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
