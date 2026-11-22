-- Driver: a Dynamax (Galar Rising, max_raids) in a game's own battle, with Battle Fit: the player's
-- lead Dynamaxes on turn 1 and fights its three turns, the foe kept sturdy. Every frame the camera
-- and the foe's HP box are logged (zoom, the box's rows, the player's art top as the fit sees it),
-- and a line each time the box moves; shots when the giant has grown, every SHOT_EVERY frames of
-- the turns, after each turn and once it is over. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/dynamax_battle.lua love .
-- HD_SIZE=WxH (1920x1080); HD_SCENE=on (3D Battle Scene); HD_FILL=off; HD_REALSIZES=off;
-- HD_SIZEMODE=medium|accurate|minimal; HD_PLAYER=SPECIES_X (Charizard); HD_GMAX=0 (a plain
-- Dynamax); HD_FOE=SPECIES_X (Geodude); HD_DOUBLE=1 (a double battle: the first of two
-- Dynamaxes); HD_SPOT=MAP:x:y (Route 101's middle, Route 1 on FireRed); SHOT_EVERY=n (40).

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_dynamax"
  local sw, sh = (os.getenv("HD_SIZE") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(sw), tonumber(sh), { resizable = true, highdpi = true, vsync = 0 })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(60)
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local fr = version == "firered" or version == "leafgreen"
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local mapId, px, py = (os.getenv("HD_SPOT") or (fr and "FR_ROUTE_1:10:20" or "EM_ROUTE101:10:10"))
    :match("^([%w_]+):(%d+):(%d+)$")
  px, py = tonumber(px), tonumber(py)
  for _ = 1, 4 do
    pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "down" })
    local s0 = Runtime.getSession()
    if s0 then s0.x, s0.y = px, py end
    Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
    Player.targetX, Player.targetY = px, py
    U.wait(20)
  end
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Trainers = require("src.core.game3.scripting.trainers")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Commands = require("src.core.game3.battle.commands")
  local C = require("src.core.game3.constants").of(version)
  local loader = game.mods
  local hd = loader.exports["gen3-hd-sprites"]
  local X = loader.exports.max_raids
  local nd = loader.exports.national_dex_gen3
  if not (hd and X and X._test and nd and nd.dynamax) then log("FAIL mods missing"); return end
  local Dm, Tt = X._test.dmax, X._test
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  hd.setFit(true)
  hd.setFill(os.getenv("HD_FILL") ~= "off")
  hd.setScene(os.getenv("HD_SCENE") == "on")
  -- (the 3D world's cache built first: FireRed's world needs it)
  if os.getenv("HD_SCENE") == "on" and hd._reliefStep then
    for _ = 1, 200000 do
      local st = hd._reliefStep()
      if st == "ready" or st == nil or st == "failed" then log("relief " .. tostring(st)) break end
    end
  end
  if hd.setRealSizes then hd.setRealSizes(os.getenv("HD_REALSIZES") ~= "off") end
  local core = hd._core and hd._core()
  if core and os.getenv("HD_SIZEMODE") then core.fit.sizeMode = os.getenv("HD_SIZEMODE") end

  local s = Runtime.getSession()
  local function sp(n) return C.species.byName["SPECIES_" .. n] end
  local function mv(n) return C.moves.byName["MOVE_" .. n] end
  s.party = {}
  local mine = (os.getenv("HD_PLAYER") or "SPECIES_CHARIZARD"):gsub("^SPECIES_", "")
  Party.giveMon(s, sp(mine), 50)
  Party.giveMon(s, sp("GARDEVOIR"), 50)
  local lead = s.party[1]
  lead.moves = { mv("FLAMETHROWER"), mv("SLASH"), mv("GROWL"), mv("WING_ATTACK") }
  lead.pp, lead.maxPp = { 15, 20, 40, 35 }, { 15, 20, 40, 35 }
  nd.dynamax.setLevel(lead, 10)
  nd.dynamax.setFactor(lead, os.getenv("HD_GMAX") ~= "0")
  Bag.add(s.bag, Tt.band.index, 1)
  Tt.dmaxMode("all")

  local double = os.getenv("HD_DOUBLE") == "1"
  local by = C.trainers.byName
  local tid = double and (by.TRAINER_TATE_AND_LIZA_1 or by.TRAINER_TWINS_ELI_AND_ANNE or by.TRAINER_TATE_AND_LIZA)
    or by.TRAINER_ROXANNE_1 or by.TRAINER_LEADER_BROCK
  local foe = Trainers.foeFromId(tid)
  local foeSp = os.getenv("HD_FOE")
  if foeSp and foe.party then
    for _, m in ipairs(foe.party) do m.species = C.species.byName[foeSp] end
  end
  local ok, err = BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = tid })
  if not ok then log("FAIL start " .. tostring(err)); return end

  local lastTap, f = 0, 0
  local function pump()
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 10 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end
  local function atCommand() return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" end
  local st
  local function sturdy()
    for _, m in ipairs(st.foeParty or {}) do m.maxHp, m.hp = 999, 999 end
    for id = 1, 3, 2 do
      local b = (id == 1 and st.enemy) or (st.battlers and st.battlers[id])
      if b and b.mon then b.mon.maxHp, b.mon.hp = 999, 999 end
    end
  end
  for _ = 1, 3000 do if Battle.isActive() then break end U.wait(1) end
  st = Battle.getState()
  for _ = 1, 8000 do
    if atCommand() then break end
    if st then sturdy() end
    if not pump() then U.wait(1) end
  end
  st = Battle.getState()
  sturdy()
  -- HD_CHIPS=n: no Dynamax; each foe's stats raised and lowered (n of them: WoobleDex's stat chips
  -- by its HP box), each of yours HD_CHIPS_MINE, a shot at the command menu, and done
  local nChips = tonumber(os.getenv("HD_CHIPS") or "0")
  if nChips > 0 then
    local keys = { "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion" }
    local vals = { 2, -1, 1, -2, 3, -1, 1 }
    local function stage(b, n)
      if not (b and n > 0) then return end
      b.stages = b.stages or {}
      for i = 1, math.min(n, #keys) do b.stages[keys[i]] = vals[i] end
    end
    local mineN = tonumber(os.getenv("HD_CHIPS_MINE") or "0")
    stage(st.enemy, nChips)
    stage(st.player, mineN)
    if st.battlers then
      for id = 0, 3 do stage(st.battlers[id], id % 2 == 1 and nChips or mineN) end
    end
    for _ = 1, 120 do U.wait(1) end
    local core0 = hd._core and hd._core()
    local f0 = core0 and core0.fit
    local e = f0 and f0.ui and f0.ui.enemy
    log(("chips: zoom %s dy %s enemy %s split %s"):format(tostring(f0 and f0.z), tostring(core0 and core0.stats.uiTopDy),
      e and table.concat(e, ",") or "-", tostring(f0 and f0.split)))
    log("shot", "chips", U.shot(game, dir .. "/chips.png") and "ok" or "MISSING")
    return
  end
  -- (the foes' moves: Tackle, never a switch)
  local enemyAction = Commands.enemyAction
  Commands.enemyAction = function(...)
    local a = enemyAction(...)
    if type(a) == "table" and a.kind ~= "move" then
      return { kind = "move", move = mv("TACKLE"), slot = 1, user = a.user or "enemy", battler = a.battler or 1 }
    end
    return a
  end

  local fit = core and core.fit
  local every = tonumber(os.getenv("SHOT_EVERY") or "40")
  local shots, frame = 0, 0
  local function shot(name)
    shots = shots + 1
    log("shot", name, U.shot(game, ("%s/%02d_%s.png"):format(dir, shots, name)) and "ok" or "MISSING")
  end
  local last = {}
  local function sample(tag)
    frame = frame + 1
    if not fit then return end
    local v = Dm.vis[0]
    local stats = core.stats or {}
    -- (dy: the foe's HP box's rows as drawn - 0 when the UI was not drawn in bands)
    local row = { z = fit.z and math.floor(fit.z * 1000 + 0.5) / 1000, dy = stats.uiTopDy,
      boxBottom = fit.boxBottom, held = core.hudHeld or 0, k = v and v.k and math.floor(v.k * 100 + 0.5) / 100 }
    local x0, y0, x1, y1
    if hd.battlerRect then x0, y0, x1, y1 = hd.battlerRect("player") end
    local moved = row.dy ~= last.dy or row.boxBottom ~= last.boxBottom
    local zMoved = row.z ~= last.z
    if moved or (zMoved and frame % 10 == 0) or frame % 60 == 0 then
      local g = core.giants and core.giants[0]
      local fix = g and g.on and ("%.1f,%.1f"):format(g.fixX or 0, g.fixY or 0) or "-"
      log(("f%05d %-8s phase %-10s z %s dy %s boxBottom %s held %s k %s grow %s lift %s fix %s player %s"):format(frame, tag,
        tostring(Battle._phase), tostring(row.z), tostring(row.dy), tostring(row.boxBottom), tostring(row.held),
        tostring(row.k), tostring(stats.grow), tostring(stats.lift and math.floor(stats.lift * 100 + 0.5) / 100), fix, x0 and ("%d,%d-%d,%d"):format(x0, y0, x1, y1) or "-"))
    end
    if moved and last.dy ~= nil and (row.k or 1) > 1.01 then
      log(("  BOX MOVED while giant: dy %s -> %s, boxBottom %s -> %s"):format(tostring(last.dy), tostring(row.dy),
        tostring(last.boxBottom), tostring(row.boxBottom)))
      if shots < 60 then shot(("moved_f%05d"):format(frame)) end
    end
    last = row
  end
  -- HD_FOEGIANT=1: no Dynamax; the foe drawn as a full-grown giant through exports.giant alone (at
  -- its own draw), so the camera pulls back as for one with the player's Pokemon as it is
  local foeGiant = os.getenv("HD_FOEGIANT") == "1"
  local giantInfo = { scale = 1, dx = 0, dy = 0, grow = 1 }
  local function step(tag)
    if foeGiant then hd.giant(1, giantInfo) end
    if not pump() then U.wait(1) end
    sample(tag)
  end

  shot("start")
  for turn = 1, 4 do
    sturdy()
    for _ = 1, 8 do
      if Ui._mode == "moves" then break end
      U.tap(game, "a")
      for _ = 1, 40 do
        if Ui._mode == "moves" then break end
        if foeGiant then hd.giant(1, giantInfo) end
        U.wait(1)
        sample("menu")
      end
    end
    if turn == 1 and not foeGiant then
      U.tap(game, "r")
      U.wait(8)
      log("Dynamax picked: " .. tostring(Dm.sel[0]))
    end
    U.tap(game, "a")
    local n, grownShot = 0, false
    for _ = 1, 9000 do
      if atCommand() or not Battle.isActive() then break end
      sturdy()
      step("turn" .. turn)
      n = n + 1
      local v = Dm.vis[0]
      if not grownShot and v and (v.k or 1) > 1.45 then grownShot = true shot("t" .. turn .. "_grown") end
      if every > 0 and n % every == 0 then shot(("t%d_f%04d"):format(turn, n)) end
    end
    for _ = 1, 40 do
      if foeGiant then hd.giant(1, giantInfo) end
      U.wait(1)
      sample("idle" .. turn)
    end
    shot("t" .. turn .. "_after")
    log(("turn %d over: Dynamaxed %s"):format(turn, tostring(st.player and st.player.__mrDmax ~= nil)))
    if not Battle.isActive() then break end
  end
  for _ = 1, 120 do U.wait(1) sample("end") end
  shot("end")
  Commands.enemyAction = enemyAction
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "."
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
