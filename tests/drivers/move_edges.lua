-- Driver: every move's animation, with Fill Screen, looking for effects anchored to the canvas's
-- sides (Surf's wave, Fake Out's curtains): the "edge" layers whose sides run on to the screen's.
-- Boots a game, starts a wild battle against a big foe (the camera pulled back), plays each move
-- from both sides and logs, per move, the edge layers it opened (stats().edge), the background
-- bands drawn across the view (stats().wide) and the whole-scene layers (stats().screen: a
-- background, a flash, a fade, stretched over the screen); screenshots the first moment
-- of each move with an edge layer. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/move_edges.lua love .
-- HD_SIZES=WxH (default 1920x1080); EDGE_MOVES=SURF,FAKE_OUT (default: all); EDGE_SIDES=player,enemy;
-- EDGE_SHOTS=n,n (frames to screenshot every move at, instead of the first edge moment).

-- an environment setting, empty counting as unset
local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_move_edges"
  local w, h = (env("HD_SIZES") or "1920x1080"):match("(%d+)x(%d+)")
  love.window.setMode(tonumber(w), tonumber(h), { resizable = true, highdpi = true })
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimCtx = require("src.core.game3.battle.anim_ctx")
  local Ui = require("src.core.game3.battle.ui")
  local version = env("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local s = Runtime.getSession()
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false
  end
  local function sp(name) return C:require("species", "SPECIES_" .. name) end
  s.party = {}
  Party.giveMon(s, sp("SALAMENCE"), 50, "SALAMENCE")
  local started = BattleBridge.startWild(Runtime._mod, game, { species = sp("WAILORD"), level = 50 }, { fade = false })
  if not started then log("FAIL wild battle did not start"); return end
  local ready = false
  for _ = 1, 6000 do
    if Battle.isActive() and Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  if not ready then log("FAIL battle did not reach the action menu"); return end
  U.wait(60)
  log(("battle ready: zoom %s fill %s"):format(tostring(hd.stats().zoom), tostring(hd.stats().fill)))

  local st = Battle._st
  local pSpecies = st and st.player and st.player.mon and st.player.mon.species or sp("SALAMENCE")
  local eSpecies = st and st.enemy and st.enemy.mon and st.enemy.mon.species or sp("WAILORD")
  local function opts(side, turn, moveId)
    local target = side == "player" and "enemy" or "player"
    return {
      attackerSide = side, targetSide = target, isReversed = side == "enemy",
      attackerSpecies = side == "player" and pSpecies or eSpecies,
      targetSpecies = side == "player" and eSpecies or pSpecies,
      moveTurn = turn or 0, turn = turn or 0,
      ctx = AnimCtx.build(side, target, { moveId = moveId }),
    }
  end
  local function restore()
    for _, side in ipairs({ "player", "enemy" }) do
      local p = Anim.present(side)
      if p then
        p.visible = true
        p.ox, p.oy, p.sx, p.sy, p.rotation = 0, 0, 1, 1, 0
        p.blendCoeff = 0
        p.invisible = nil
        p.transformSpecies = nil
      end
      if p and p.substitute then Anim.setSubstitute(side, false) end
    end
  end

  local shots = nil
  if env("EDGE_SHOTS") then
    shots = {}
    for n in env("EDGE_SHOTS"):gmatch("%d+") do shots[tonumber(n)] = true end
  end
  local edgeMoves, wideMoves, screenMoves = {}, {}, {}
  local function run(label, launch)
    local st0 = hd.stats()
    local e0, w0, s0 = st0.edge or 0, st0.wide or 0, st0.screen or 0
    local ok, err = pcall(launch)
    if not ok then log("launch failed", label, tostring(err)) return end
    local shotAt, f = nil, 0
    while f < 1500 do
      U.wait(1)
      f = f + 1
      local s1 = hd.stats()
      if not shots and not shotAt and ((s1.edge or 0) > e0 or (s1.wide or 0) > w0 or (s1.screen or 0) > s0) then
        shotAt = f + 10
      end
      if (shots and shots[f]) or f == shotAt then
        U.shot(game, ("%s/%s_%03d.png"):format(dir, label:lower(), f))
      end
      if not Anim.busy() and f > (shotAt or 0) then break end
    end
    local s2 = hd.stats()
    local de, dw, ds = (s2.edge or 0) - e0, (s2.wide or 0) - w0, (s2.screen or 0) - s0
    if de > 0 then edgeMoves[#edgeMoves + 1] = label .. "(" .. de .. ")" end
    if dw > 0 then wideMoves[#wideMoves + 1] = label .. "(" .. dw .. ")" end
    if ds > 0 then screenMoves[#screenMoves + 1] = label .. "(" .. ds .. ")" end
    log(("%s frames %d edge %d wide %d screen %d"):format(label, f, de, dw, ds))
    restore()
    U.wait(4)
  end

  local only = env("EDGE_MOVES")
  local sides = env("EDGE_SIDES") or "player,enemy"
  for id = 1, 354 do
    local name = (C:name("moves", id, "MOVE_") or ("MOVE_" .. id)):gsub("^MOVE_", "")
    local pick = not only
    if only then
      for m in only:gmatch("[^,]+") do if m == name then pick = true end end
    end
    if pick then
      for side in sides:gmatch("[^,]+") do
        run(name .. "_" .. side, function() Anim.launchMove(id, opts(side, 0, id)) end)
      end
    end
  end
  log("EDGE " .. table.concat(edgeMoves, " "))
  log("WIDE " .. table.concat(wideMoves, " "))
  log("SCREEN " .. table.concat(screenMoves, " "))
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_move_edges"
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
