-- Driver: boots Emerald in a portrait window, starts a wild battle with a sprite mod that
-- tags its pics, and screenshots the battle menu with Fill Screen on, then the same in a
-- landscape window. Logs the fill scale and where the UI landed. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/portrait_battle.lua love .

-- (vsync = 0: the runs go as fast as the machine allows)
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
  love.window.setMode(432, 768, { resizable = true, highdpi = true, vsync = 0 })
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
  -- HD_SPOT=MAP[:x:y]: the battle starts there (Littleroot by default), on the walkable land
  -- cell nearest that one (the map's middle without x:y)
  local mapId, sx, sy = (os.getenv("HD_SPOT") or ""):match("^([%w_]+):?(%d*):?(%d*)$")
  mapId = mapId or "EM_LITTLEROOT_TOWN"
  sx, sy = tonumber(sx), tonumber(sy)
  if (os.getenv("HD_SPOT") or "") == "" then sx, sy = 14, 12 end
  local okL, errL = pcall(Map.load, nil, game, mapId, { x = sx or 0, y = sy or 0, facing = "down" })
  if not okL then log("FAIL Map.load", mapId, tostring(errL)) end
  local def = Map.currentDef()
  local L = def and def.midLayout
  local W, H = L and L.width or 0, L and L.height or 0
  sx, sy = sx or math.floor(W / 2), sy or math.floor(H / 2)
  local Collision = require("src.core.game3.collision")
  local function land(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return false end
    local okW, walk = pcall(Collision.isWalkable, x, y)
    if not (okW and walk) then return false end
    local okB, beh = pcall(Collision.behavior, x, y)
    return not (okB and Collision.isSurfable(beh))
  end
  local px, py = sx, sy
  if not land(sx, sy) then
    for r = 1, 40 do
      local hit
      for dy = -r, r do
        for dx = -r, r do
          if not hit and math.max(math.abs(dx), math.abs(dy)) == r and land(sx + dx, sy + dy) then
            hit = { sx + dx, sy + dy }
          end
        end
      end
      if hit then px, py = hit[1], hit[2]; break end
    end
  end
  log(("spot %s %dx%d asked %d,%d at %d,%d"):format(mapId, W, H, sx, sy, px, py))
  local s = Runtime.getSession()
  -- (on the spot before each battle: a new game's intro, late on a busy machine, can still load
  -- the moving truck after the spot is set)
  local function toSpot()
    local d0 = Map.currentDef()
    if not (d0 and (d0.id or d0.name) == mapId) then
      log("back to the spot from", tostring(d0 and (d0.id or d0.name)))
      pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "down" })
    end
    s = Runtime.getSession() or s
    if s then s.x, s.y = px, py end
    Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
    Player.targetX, Player.targetY = px, py
  end
  pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "down" })
  toSpot()
  -- HD_PLAYER / HD_ENEMY=SPECIES_X:level: the two battlers (Torchic 12 against Wailord 20)
  local function mon(name, sp, lv)
    local a, b = (os.getenv(name) or ""):match("^(SPECIES_[%w_]+):?(%d*)$")
    return C:require("species", a or sp), tonumber(b) or lv
  end
  if s and #(s.party or {}) == 0 then Party.giveMon(s, mon("HD_PLAYER", "SPECIES_TORCHIC", 12)) end
  U.wait(60)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  log("hd active:", hd.isActive(), "fit:", hd.fitEnabled(), "fill:", hd.fillEnabled())
  -- HD_FILLOFF=1: Fill Screen off; HD_HIDEBOTTOM=1: the battle's bottom UI hidden, as Kanto
  -- Gear's GEAR screens hide it (battle.bottom_ui_visible)
  if os.getenv("HD_FILLOFF") == "1" and hd.setFill then hd.setFill(false) end
  -- HD_SCENE=off: Battle Scene on CLASSIC (no 3D world) for this run
  if os.getenv("HD_SCENE") == "off" and hd.setScene then hd.setScene(false) end
  -- HD_REALSIZES=off: 3D Sizing off (the 3D world's battlers drawn as in classic battles)
  if os.getenv("HD_REALSIZES") == "off" and hd.setRealSizes then hd.setRealSizes(false) end
  if os.getenv("HD_HIDEBOTTOM") == "1" then
    local BUi = require("src.core.game3.battle.ui")
    BUi.bottomUIVisible = function() return false end
  end
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
    toSpot()
    U.wait(2)
    local okB, errB = pcall(function()
      local BattleBridge = require("src.core.game3.battle_bridge")
      local sp, lv = mon("HD_ENEMY", "SPECIES_WAILORD", 20)
      local enc = { species = sp, level = lv }
      local ok, err = BattleBridge.startWild(Runtime._mod, game, enc, {})
      if not ok then error(tostring(err)) end
    end)
    if not okB then log("startWild failed:", tostring(errB)); return end
    local reached = false
    -- HD_BAR=1: the battle's text box shot too, with its first message and its move menu
    local bar, msgShot = os.getenv("HD_BAR") == "1", false
    -- HD_EARLY=f,f,...: shots that many frames into the battle (its opening)
    local early = {}
    for f in (os.getenv("HD_EARLY") or ""):gmatch("%d+") do early[tonumber(f)] = true end
    for frame = 1, 1500 do
      U.wait(1)
      if early[frame] then U.shot(game, ("%s/%s_f%03d.png"):format(dir, name, frame)) end
      local p, sn = prompt()
      if p == "advance" then
        if bar and not msgShot then
          msgShot = true
          U.wait(20)
          U.shot(game, dir .. "/" .. name .. "_message.png")
        end
        U.tap(game, "a"); U.wait(4)
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
      .. "  grow " .. tostring(st.grow) .. " inward " .. tostring(st.inward) .. " shiftE " .. tostring(st.shiftEnemy) .. " shiftP " .. tostring(st.shiftPlayer)
      .. " scene " .. tostring(st.scene) .. " " .. tostring(st.sceneError) .. " packed " .. tostring(st.packed) .. " shrink " .. tostring(st.worldShrink) .. " rest " .. tostring(st.boxRest))
    local defB = Map.currentDef()
    log(("%s: at %s %s,%s facing %s moving %s stage %s score %s"):format(name, tostring(defB and (defB.id or defB.name)),
      tostring(Player.cellX), tostring(Player.cellY), tostring(Player.facing), tostring(Player.moving),
      tostring(st.sceneStage), tostring(st.sceneScore)))
    -- each battler's world size: its side, height (m), scale, raised to the smallest, ground px/tile
    local hdc = hd._core and hd._core() or hd
    for _, e in ipairs((hdc and hdc._worldMons) or {}) do
      log(("%s: mon %s h %.2f k %.4f raised %s limited %s ppt %.2f"):format(name, tostring(e.of and e.of.side),
        e.height or -1, e.k or -1, tostring(e.raised), tostring(e.limited), e.ppt or -1))
    end
    U.shot(game, dir .. "/" .. name .. ".png")
    if bar then
      U.tap(game, "a"); U.wait(20)
      U.shot(game, dir .. "/" .. name .. "_moves.png")
      U.tap(game, "b"); U.wait(20)
    end
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
  -- HD_SCENES=on,off,...: Battle Scene for each battle in turn (OVERWORLD / CLASSIC)
  local scenes = {}
  for v in (os.getenv("HD_SCENES") or ""):gmatch("[^,]+") do scenes[#scenes + 1] = v end
  for i, sz in ipairs(sizes) do
    local w0, h0 = love.graphics.getDimensions()
    if (i > 1 or sz[1] ~= 432 or sz[2] ~= 768) and (w0 ~= sz[1] or h0 ~= sz[2]) then
      love.window.setMode(sz[1], sz[2], { resizable = true, highdpi = true, vsync = 0 })
      U.wait(10)
    end
    if scenes[i] and hd.setScene then hd.setScene(scenes[i] ~= "off") end
    battleShot((sz[2] > sz[1] and "portrait_" or "landscape_") .. sz[1] .. "x" .. sz[2]
      .. (scenes[i] and ("_" .. i .. "_" .. scenes[i]) or ""))
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
