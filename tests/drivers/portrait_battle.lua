-- Driver: boots Emerald in a portrait window, starts a wild battle with a sprite mod that
-- tags its pics, and screenshots the battle menu with Fill Screen on, then the same in a
-- landscape window. Logs the fill scale and where the UI landed. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/portrait_battle.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_portrait"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(432, 768, { resizable = true, highdpi = true })
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
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  log("hd active:", hd.isActive(), "fit:", hd.fitEnabled(), "fill:", hd.fillEnabled())
  -- keep the touch surface mod out of the way: no cutout, no split
  for _, id in ipairs({ "play_nav", "ds_touch" }) do   -- PlayNav, ds_touch before 0.3.0
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
    loader.modOptions[id].refresh = false   -- no care prompt after the battle
  end
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local intent = 0
  local function prompt() local sn = bapi:snapshot(); return sn and sn.prompt, sn end
  local Renderer = require("src.render.Renderer")
  local function battleShot(name)
    local okB, errB = pcall(function()
      local BattleBridge = require("src.core.game3.battle_bridge")
      local enc = { species = C:require("species", "SPECIES_WAILORD"), level = 20 }
      local ok, err = BattleBridge.startWild(Runtime._mod, game, enc, {})
      if not ok then error(tostring(err)) end
    end)
    if not okB then log("startWild failed:", tostring(errB)); return end
    local reached = false
    for _ = 1, 1500 do
      U.wait(1)
      local p, sn = prompt()
      if p == "advance" then U.tap(game, "a"); U.wait(4)
      elseif p == "menu" then reached = true; break end
    end
    U.wait(30)
    local st = hd.stats()
    local R = Renderer:frameRects()
    local w, h = love.graphics.getDimensions()
    local okE, Engine = pcall(require, "src.core.TouchControls")
    local ctop = "-"
    if okE and Engine:visible() then
      local L = Engine:layout()
      local t = math.huge
      for k, z in pairs(L) do if k ~= "hotbar" and type(z) == "table" and z.cy then t = math.min(t, z.cy - (z.h or z.w) / 2) end end
      ctop = ("%.0f"):format(t)
    end
    log(("%s: menu %s  window %dx%d  view %d,%d %dx%d cut %s  controlsTop %s  fill %.3f ui %.2f topDy %.2f zoom %.2f composites %d flattened %d failed %s"):format(
      name, tostring(reached), w, h, R.vux, R.vuy, R.vuw, R.vuh, tostring(R.cut), ctop, st.fill or -1, st.uiScale or -1,
      st.uiTopDy or 0, st.zoom or -1, st.composites or 0, st.flattened or 0, tostring(st.failed))
      .. "  grow " .. tostring(st.grow) .. " inward " .. tostring(st.inward) .. " shiftE " .. tostring(st.shiftEnemy) .. " shiftP " .. tostring(st.shiftPlayer))
    U.shot(game, dir .. "/" .. name .. ".png")
    -- run away
    local ran = false
    for _ = 1, 1500 do
      U.wait(1)
      local p, sn = prompt()
      if p == "advance" then U.tap(game, "a"); U.wait(4)
      elseif p == "menu" and not ran then
        intent = intent + 1
        local ok = bapi:submit({ id = intent, revision = sn.revision, kind = "menu", choice = "run" })
        if ok then ran = true end
      elseif not p and ran then break end
    end
    U.wait(30)
  end
  -- HD_SIZES=WxH,WxH,...: the windows to battle in (the first is already open)
  local sizes = {}
  for w, h in (os.getenv("HD_SIZES") or "432x768,540x960,540x1200,1280x720"):gmatch("(%d+)x(%d+)") do
    sizes[#sizes + 1] = { tonumber(w), tonumber(h) }
  end
  for i, sz in ipairs(sizes) do
    if i > 1 or sz[1] ~= 432 or sz[2] ~= 768 then
      love.window.setMode(sz[1], sz[2], { resizable = true, highdpi = true })
      U.wait(10)
    end
    battleShot((sz[2] > sz[1] and "portrait_" or "landscape_") .. sz[1] .. "x" .. sz[2])
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_portrait"
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
