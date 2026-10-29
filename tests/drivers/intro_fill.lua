-- Driver: the battle intro with Fill Screen. Boots Emerald, stands on Route 101 (grass), starts
-- a wild battle and screenshots intro frames (the black bars opening, the grass sliding away)
-- and the battle once settled, in each window size. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/intro_fill.lua love .
-- HD_SIZES=WxH,WxH,... (default 1920x1080,2400x1080,540x1200); INTRO_MAP / INTRO_X / INTRO_Y
-- pick another spot; INTRO_TERRAIN forces the battle's terrain (0 grass, 1 long grass, 2 sand,
-- 4 water: grass slides down, sand and water fade).

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_intro"
  local sizes = {}
  for w, h in (os.getenv("HD_SIZES") or "1920x1080,2400x1080,540x1200"):gmatch("(%d+)x(%d+)") do
    sizes[#sizes + 1] = { tonumber(w), tonumber(h) }
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(sizes[1][1], sizes[1][2], { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local mapId = os.getenv("INTRO_MAP") or "EM_ROUTE101"
  local px, py = tonumber(os.getenv("INTRO_X") or 10), tonumber(os.getenv("INTRO_Y") or 10)
  pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = px, py end
  Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
  Player.targetX, Player.targetY = px, py
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  log("hd active:", hd.isActive(), "fit:", hd.fitEnabled(), "fill:", hd.fillEnabled(), "map:", mapId)
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local shots = { 2, 20, 40, 60, 80, 100, 120, 145 }
  local terrain = tonumber(os.getenv("INTRO_TERRAIN") or "")
  for i, sz in ipairs(sizes) do
    if i > 1 then
      love.window.setMode(sz[1], sz[2], { resizable = true, highdpi = true })
      U.wait(10)
    end
    local name = sz[1] .. "x" .. sz[2]
    local ok, err = BattleBridge.startWild(Runtime._mod, game,
      { species = C:require("species", "SPECIES_WURMPLE"), level = 3 }, { fade = false, terrain = terrain })
    if not ok then log("FAIL startWild", tostring(err)); return end
    local si = 1
    for f = 1, 200 do
      if shots[si] and f >= shots[si] then
        local st = Anim.stage and Anim.stage()
        local w0 = st and st.win0
        U.shot(game, ("%s/%s_intro_%03d.png"):format(dir, name, f))
        log(("%s frame %d: win0 %s entry %s"):format(name, f, w0 and (w0[1] .. "-" .. w0[2]) or "-",
          st and st.entry and (st.entry.key .. " y" .. tostring(st.entry.y)) or "-"))
        si = si + 1
      end
      U.wait(1)
    end
    waitFor(function()
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
      return Ui._mode == "menu" and not Anim.busy()
    end, 3000)
    U.wait(30)
    U.shot(game, ("%s/%s_settled.png"):format(dir, name))
    local stt = hd.stats()
    log(("%s settled: fill %.3f grow %s composites %d flattened %d failed %s"):format(name, stt.fill or -1,
      tostring(stt.grow), stt.composites or 0, stt.flattened or 0, tostring(stt.failed)))
    -- leave the battle the quick way before the next size
    if Battle.abort then pcall(Battle.abort) end
    waitFor(function() return not Battle.isActive() end, 600)
    U.wait(30)
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_intro"
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
