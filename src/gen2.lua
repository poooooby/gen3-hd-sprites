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
-- A WIDE battle (src/ui/gen2/WideBattle.lua) is drawn the game's usual way, and so is a battle
-- with a black or world background (Game2 paints those around the panel after it is drawn).

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

  local function present(battle, winW, winH)
    local G = love.graphics
    local scale = battle:battlePanelScale(winW, winH)
    local bx, by = Chrome.fitOrigin(winW, winH, scale)
    local box = { bx, by, 160 * scale, 144 * scale }
    if Chrome.letterbox then Chrome.letterbox(winW, winH, 1, 1, 1) end
    local c = canvasFor(160, 144)
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.clear(1, 1, 1, 1)
    G.setColor(1, 1, 1, 1)
    hd.useLayout("gen2_og")
    local okP, errP = pcall(hd.beginPass, "battle", c)
    if not okP then hd.fail("battle pass: " .. tostring(errP)) end
    local ok, err
    if hd.capturing("battle") and hd.fit.enabled then
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
    hd.fit.available = true
  end
end

return Gen2
