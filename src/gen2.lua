-- The Gen 2 seams (Gold, Silver, Crystal), wrapped by src/engine.lua's install once its Renderer
-- seams are checked (Gen2.prepare checks these first, so nothing is wrapped when one is missing).
--
-- Gold composites its own frame (src/core/Game2.lua): nothing goes through the Renderer, and the
-- battle draws its 160x144 panel straight to the window, scaled (Chrome.withPanel). So this
-- adapter makes the canvas the other generations have:
--
--   BattleState:drawWidescreen   the ORIGINAL layout's battle (src/ui/gen2/BattleState.lua): its
--                          scene is drawn into a 160x144 canvas of ours, in a battle pass, then
--                          composited to the window where the panel would stand (hd.composite,
--                          with a blit of our own for the Renderer's). The panel's parts are drawn
--                          apart for Battle Fit: the scene (the paper, the two pics, the move
--                          animation's objects), then the UI seam, then the HP boxes and the
--                          text box (drawEnemyHud, drawPlayerHud, drawBottom: skipped while the
--                          scene draws, then drawn after it).
--
--   World:drawPeople        the field's people (src/world/gen2/World.lua), the player, the NPCs and
--                          what other mods add to them (Vivid Worlds: OG's wild Pokemon). Gold
--                          draws its map and people straight to the window at its zoom, so they
--                          are already at window resolution: a direct field pass (hd.beginDirect)
--                          draws a tagged sheet in place at its spec's size about its feet.
--
--   WideBattle.draw         the WIDE layout's battle (src/ui/gen2/WideBattle.lua, 304x144): the same,
--                          on a 304x144 canvas (layout "gen2_wide"), composited where its 38x18
--                          tile panel would stand. Its field (WideBattle.drawField: the ORIGINAL's
--                          scene moved right by FIELD_X) is the scene; its HUDs (drawTopHud,
--                          drawBottomHud) come after the UI seam. With its HUD docked to the window
--                          (the EXTENDED HUD) it is drawn the game's usual way.
--
-- A battle with a black or world background is drawn the game's usual way (Game2 paints those
-- around the panel after it is drawn).

local Gen2 = {}

-- The ORIGINAL battle screen (160x144), from pokecrystal's tile layout: the text box's top at row
-- 96; the enemy's pic in the 7x7 tile box at (96, 0) (feet at y 56); the player's back pic in the
-- 6x6 box at (16, 48), its feet on the text box; the enemy's HUD in the 4x11 tile block DrawEnemyHUD
-- clears from (1, 0), the player's from (9, 7) to the bracket under its HP. No pads, no wallpaper.
Gen2.LAYOUTS = {
  gen2_og = {
    focus = { 80, 96 }, feetY = 56, feetMax = 58,
    split = 44, spanDefault = { 0, 160 },
    pads = { enemy = { 96, 152 }, player = { 16, 64 } }, inwardMax = 32,
    ui = { enemy = { 8, 0, 96, 32 }, player = { 72, 56, 160, 96 }, text = { -1e4, 96, 1e4, 1e4 } },
    backTopMin = 48, extraMax = 40,
    -- no side shift: the move animations' objects are placed in the cart's coordinates
    enemyX = 124, playerX = 40, shiftMax = 0,
    ground = false,
    padTop = 96, padRows = 0, padTuck = 0,
    wholeBelow = 36, cutAbove = 56,
  },
  -- The WIDE battle screen (304x144): the ORIGINAL's scene moved right by FIELD_X (72): the
  -- enemy's pic box at x 168-224, the player's at 88-136; the enemy's HUD where the ORIGINAL
  -- has it, the player's moved right by 144 (EXTRA_TILES), the text box across the bottom
  gen2_wide = {
    focus = { 152, 96 }, feetY = 56, feetMax = 58,
    split = 44, spanDefault = { 0, 304 },
    pads = { enemy = { 168, 224 }, player = { 88, 136 } }, inwardMax = 32,
    ui = { enemy = { 8, 0, 96, 32 }, player = { 216, 56, 304, 96 }, text = { -1e4, 96, 1e4, 1e4 } },
    backTopMin = 48, extraMax = 40,
    enemyX = 196, playerX = 112, shiftMax = 0,
    ground = false,
    padTop = 96, padRows = 0, padTuck = 0,
    wholeBelow = 36, cutAbove = 56,
  },
}

local function noop() end

--- Check the Gen 2 seams (raises when one is missing, before anything is wrapped) and return
--- the function that wraps them, which src/engine.lua calls once its own seams are in place.
function Gen2.prepare(Engine, hd)
  local need, ours = Engine.need, Engine.ours
  local BattleState = require("src.ui.gen2.BattleState")
  local Chrome = require("src.ui.gen2.Chrome")
  local drawWidescreen = need(BattleState, "drawWidescreen")
  need(BattleState, "drawScene")
  need(BattleState, "drawEnemyHud")
  need(BattleState, "drawPlayerHud")
  need(BattleState, "drawBottom")
  need(BattleState, "battlePanelScale")
  need(BattleState, "wideLayout")
  need(Chrome, "fitOrigin")
  local okF, Font = pcall(require, "src.render.Font")
  if not (okF and type(Font) == "table" and type(Font.useBattleExtra) == "function") then Font = nil end
  local okP, GbcPalette = pcall(require, "src.render.GbcPalette")
  if not (okP and type(GbcPalette) == "table" and type(GbcPalette.setBgp) == "function") then GbcPalette = nil end
  -- (optional: without it a WIDE battle is drawn the game's own way)
  local okWB, WideBattle = pcall(require, "src.ui.gen2.WideBattle")
  local wideDraw = okWB and type(WideBattle) == "table" and type(WideBattle.draw) == "function"
    and type(WideBattle.drawField) == "function" and type(WideBattle.drawTopHud) == "function"
    and type(WideBattle.drawBottomHud) == "function" and type(WideBattle.docked) == "function"
    and type(WideBattle.drawSurface) == "function" and type(Chrome.fitOriginFor) == "function"
    and WideBattle.draw or nil
  -- (optional: without it the field is drawn the game's own way)
  local okW, World = pcall(require, "src.world.gen2.World")
  local drawPeople = okW and type(World) == "table" and type(World.drawPeople) == "function"
    and World.drawPeople or nil
  for name, L in pairs(Gen2.LAYOUTS) do hd.layouts[name] = L end
  hd.useLayout("gen2_og")
  Engine.fullScreen, Engine.fieldBusy = nil, nil
  Engine.dexModules = {}
  local real = hd.real

  -- the battle's canvas (the panel's size)
  local base
  local function canvasFor(w, h)
    if not (base and base:getWidth() == w and base:getHeight() == h) then
      if base and base.release then pcall(base.release, base) end
      base = real.newCanvas(w, h, { dpiscale = 1 })
      base:setFilter("nearest", "nearest")
    end
    return base
  end

  --- The panel's UI, drawn after the UI seam: the HP boxes (with the battle's font extras, as
  --- drawHud draws them) and the text box, under the battle's exit fade like the rest.
  local function drawUI(battle)
    local prevBgp
    if GbcPalette and battle.exitFadeBgp then
      prevBgp = GbcPalette.setBgp(battle:exitFadeBgp() or GbcPalette.bgp)
    end
    local was = Font and Font.useBattleExtra(true)
    battle:drawEnemyHud()
    battle:drawPlayerHud()
    if Font then Font.useBattleExtra(was) end
    battle:drawBottom(0)
    if GbcPalette and battle.exitFadeBgp then GbcPalette.setBgp(prevBgp) end
  end

  --- The WIDE battle's scene, then the UI seam, then its HUDs (under the exit fade's palette, as
  --- drawScene draws them), into the pass's canvas.
  local function drawWideSplit(battle)
    local sides = false
    battle:drawScene(function() sides = WideBattle.drawField(battle) end)
    if not sides then return end
    if hd.capturing("battle") then hd.seam("ui") end
    local prevBgp
    if GbcPalette and battle.exitFadeBgp then
      prevBgp = GbcPalette.setBgp(battle:exitFadeBgp() or GbcPalette.bgp)
    end
    WideBattle.drawTopHud(battle)
    WideBattle.drawBottomHud(battle)
    if GbcPalette and battle.exitFadeBgp then GbcPalette.setBgp(prevBgp) end
  end

  --- The scene, then the UI seam, then the UI, into `c` (a battle pass on it).
  local function drawSplit(battle)
    battle.drawEnemyHud, battle.drawPlayerHud, battle.drawBottom = noop, noop, noop
    local ok, err = pcall(battle.drawScene, battle)
    battle.drawEnemyHud, battle.drawPlayerHud, battle.drawBottom = nil, nil, nil
    if not ok then error(err, 0) end
    if hd.capturing("battle") then hd.seam("ui") end
    drawUI(battle)
  end

  -- the battle draws over its own white paper; a black or world background is painted around
  -- the panel afterwards (Game2:paintBattleSurround), which a filled screen would hide
  local function whitePaper(battle)
    local ok, mode = pcall(battle.bgMode, battle)
    return not ok or mode == nil or mode == "white"
  end

  local function present(battle, winW, winH, wide)
    local G = love.graphics
    local scale = battle:battlePanelScale(winW, winH)
    local cw = wide and WideBattle.WIDTH or 160
    local bx, by
    if wide then
      bx, by = Chrome.fitOriginFor(winW, winH, scale, cw / 8, 144 / 8)
    else
      bx, by = Chrome.fitOrigin(winW, winH, scale)
    end
    local box = { bx, by, cw * scale, 144 * scale }
    if Chrome.letterbox then Chrome.letterbox(winW, winH, 1, 1, 1) end
    local c = canvasFor(cw, 144)
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.clear(1, 1, 1, 1)
    G.setColor(1, 1, 1, 1)
    hd.useLayout(wide and "gen2_wide" or "gen2_og")
    local okP, errP = pcall(hd.beginPass, "battle", c)
    if not okP then hd.fail("battle pass: " .. tostring(errP)) end
    local ok, err
    if wide then
      if hd.capturing("battle") and hd.fit.enabled then
        ok, err = pcall(drawWideSplit, battle)
      else
        ok, err = pcall(battle.drawScene, battle, function() WideBattle.drawSurface(battle) end)
      end
    elseif hd.capturing("battle") and hd.fit.enabled then
      ok, err = pcall(drawSplit, battle)
    else
      ok, err = pcall(battle.drawScene, battle)
    end
    if hd.capturing() then hd.endPass() end
    G.pop()
    if not ok then error(err, 0) end
    -- the window as the battle's view (Fill Screen), less a notch and touch controls
    local view
    if hd.fit.fill then
      view = { 0, 0, winW, winH }
      view.top, view.bottom = Engine.usableRows(0, winH, winW)
    end
    -- the Renderer's blit, for ours: the canvas at its origin and scale, clipped to a box
    local function blit(cv, obx, oby, osx, osy, obox)
      local b = obox or box
      real.setScissor(b[1], b[2], b[3], b[4])
      real.draw(cv, obx or bx, oby or by, 0, osx or scale, osy or scale)
      real.setScissor()
    end
    local okC, done = pcall(hd.composite, c, blit, bx, by, scale, scale, box, view)
    if not okC then
      hd.fail("composite: " .. tostring(done))
      local cur = hd.done[c]
      if cur then pcall(hd.flatten, cur) end
      done = false
    end
    if not done then
      G.push("all")
      G.setColor(1, 1, 1, 1)
      blit(c)
      G.pop()
    end
    hd.endFrame()
  end

  return function()
    if not ours[drawWidescreen] then
      BattleState.drawWidescreen = function(self, winW, winH, ...)
        if self:wideLayout() or not hd.enabled.battle or hd.failed or not whitePaper(self) then
          return drawWidescreen(self, winW, winH, ...)
        end
        local ok, err = pcall(present, self, winW, winH)
        if not ok then
          hd.fail("Gen 2 battle: " .. tostring(err))
          return drawWidescreen(self, winW, winH, ...)
        end
      end
      ours[BattleState.drawWidescreen] = true
    end
    if wideDraw and not ours[wideDraw] then
      WideBattle.draw = function(battle, winW, winH, ...)
        local okD, docked = pcall(WideBattle.docked, battle)
        if not hd.enabled.battle or hd.failed or not okD or docked or not whitePaper(battle) then
          return wideDraw(battle, winW, winH, ...)
        end
        local ok, err = pcall(present, battle, winW, winH, true)
        if not ok then
          hd.fail("Gen 2 WIDE battle: " .. tostring(err))
          return wideDraw(battle, winW, winH, ...)
        end
      end
      ours[WideBattle.draw] = true
    end
    if drawPeople and not ours[drawPeople] then
      World.drawPeople = function(self, ...)
        local began = hd.beginDirect("field")
        if not began then return drawPeople(self, ...) end
        local ok, err = pcall(drawPeople, self, ...)
        hd.endDirect()
        if not ok then error(err, 0) end
      end
      ours[World.drawPeople] = true
    end
    hd.fit.available = true
  end
end

return Gen2
