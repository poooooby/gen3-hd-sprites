-- The Gen 1 seams (Red, Blue, Yellow), wrapped by src/engine.lua's install once its Renderer
-- seams are checked (Gen1.prepare checks these first, so nothing is wrapped when one is missing):
--
--   BattleState:drawClassic  the ORIGINAL battle layout's draw (src/battle/BattleState.lua); the
--                          battle pass starts here. The battle draws its HUDs and text box into a
--                          gray canvas together with the white field, colours that canvas zone by
--                          zone (drawZonePass), then draws the Pokemon over it. Battle Fit needs
--                          the field and the UI apart (the UI over the scene, after the UI seam):
--                          with the fit on, the field is drawn without them (drawHUDs and
--                          drawTextArea skipped), then the UI seam, then the HUDs and the text box
--                          on a canvas of their own, coloured by the same zone pass.
--
--   Game:draw              a frame whose lowest drawn state is a whole screen of its own (the
--                          title, the intro, Oak's speech, the naming screens, the Pokedex,
--                          the party, the bag, the options, a menu opened over an ORIGINAL
--                          battle ...: an opaque state that is neither the overworld nor a
--                          battle) is a "screen" pass (src/engine.lua's Renderer:beginFrame
--                          wrapper asks Engine.fullScreen): with Fill Screen it fills the screen
--                          as one picture. Not while a WIDE or world-backed battle is on the
--                          stack (the game shows it around the menu).
--
-- A WIDE battle (src/battle/WideBattle.lua) never reaches drawClassic: it is drawn the game's
-- usual way. So is a battle another mod draws over a world of its own (Terrarium's 3D arena:
-- its BattleState:draw sets the Renderer's world override before the game's draw runs), and
-- any battle whose drawClassic another mod replaced before this one was loaded (it is called
-- through, not around).

local Gen1 = {}

-- The ORIGINAL battle screen (160x144), from pokered's tile layout: the text box's top at row
-- 96 (hlcoord 0,12); the enemy's pic in the 7x7 tile slot at hlcoord 12,0 (x 96-152, feet at
-- y 56); the player's back pic at hlcoord 1,5, its feet on the text box (x 8-64, y 40-96);
-- the enemy's HUD in the zone at tiles 1,0-10,3 and the player's at 9,7-19,11 (with its bracket
-- line). No pads, no wallpaper: the field is the palette's paper colour.
Gen1.LAYOUTS = {
  gen1_og = {
    focus = { 80, 96 }, feetY = 56, feetMax = 58,
    split = 44, spanDefault = { 0, 160 },
    pads = { enemy = { 96, 152 }, player = { 8, 64 } }, inwardMax = 32,
    ui = { enemy = { 8, 0, 88, 32 }, player = { 72, 56, 160, 96 }, text = { -1e4, 96, 1e4, 1e4 } },
    backTopMin = 40, extraMax = 40,
    -- no side shift: the move animations' sprites are placed in the cart's coordinates
    enemyX = 124, playerX = 36, shiftMax = 0,
    ground = false,
    -- the back pic stands on the text box (no pad to tuck): a rising camera lowers it with
    -- the line
    padTop = 96, padRows = 0, padTuck = 0,
    wholeBelow = 36, cutAbove = 56,
  },
}

local function noop() end

--- Check the Gen 1 seams (raises when one is missing, before anything is wrapped) and return
--- the function that wraps them, which src/engine.lua calls once its own seams are in place.
function Gen1.prepare(Engine, hd)
  local need, ours = Engine.need, Engine.ours
  local BattleState = require("src.battle.BattleState")
  local drawClassic = need(BattleState, "drawClassic")
  need(BattleState, "drawHUDs")
  need(BattleState, "drawTextArea")
  need(BattleState, "drawZonePass")
  need(BattleState, "colorMode")
  local okT, Timing = pcall(require, "src.core.Timing")
  if not okT then Timing = nil end
  for name, L in pairs(Gen1.LAYOUTS) do hd.layouts[name] = L end
  hd.useLayout("gen1_og")
  Engine.fullScreen, Engine.fieldBusy = nil, nil
  Engine.dexModules = {}

  -- a whole screen (optional: without it every screen keeps the game's framing)
  local okG, Game = pcall(require, "src.core.Game")
  local gameDraw = okG and type(Game) == "table" and type(Game.draw) == "function" and Game.draw or nil
  local whole = false
  if gameDraw then
    Engine.fullScreen = function() return whole end
  end

  -- the sprites the Renderer draws again over the UI canvas once it is blitted (OG RED's
  -- object-palette sprites: the intro's, the diploma's, a battle's party balls:
  -- PaletteFX.markUiSpriteRedraw), drawn where a filled screen put its UI (hd.uiMap), and
  -- taken off the Renderer's list
  local okPF, PaletteFX = pcall(require, "src.render.PaletteFX")
  Engine.overUi = nil
  if okPF and type(PaletteFX) == "table" and type(PaletteFX.uiSpriteRedraws) == "function" then
    Engine.overUi = function(_, map)
      local list = PaletteFX.uiSpriteRedraws()
      if not (type(list) == "table" and list[1]) then return end
      local G = love.graphics
      local X, U, Uy = map.x, map.sx, map.sy
      G.push("all")
      G.setShader()
      G.setBlendMode("alpha", "alphamultiply")
      for i = 1, #list do
        local r = list[i]
        local c = r.clip
        -- (an upright battle's top band moved up: a sprite above its split goes with it)
        local top = map.banded and r.y < map.split
        local Y = top and map.topY or map.y
        local b = map.banded and (top and map.topBox or map.lowBox) or map.box
        local x1, y1, x2, y2 = b[1], b[2], b[1] + b[3], b[2] + b[4]
        if c then
          x1, y1 = math.max(x1, X + c[1] * U), math.max(y1, Y + c[2] * Uy)
          x2, y2 = math.min(x2, X + (c[1] + c[3]) * U), math.min(y2, Y + (c[2] + c[4]) * Uy)
        end
        if x2 > x1 and y2 > y1 then
          G.setScissor(x1, y1, x2 - x1, y2 - y1)
          local col = r.color
          G.setColor(col and col[1] or 1, col and col[2] or 1, col and col[3] or 1, col and col[4] or 1)
          local sx, sy = U * (r.sx or 1), Uy * (r.sy or 1)
          if r.quad then
            G.draw(r.image, r.quad, X + r.x * U, Y + r.y * Uy, 0, sx, sy)
          else
            G.draw(r.image, X + r.x * U, Y + r.y * Uy, 0, sx, sy)
          end
        end
      end
      G.pop()
      for i = #list, 1, -1 do list[i] = nil end
    end
  end

  -- the HUDs and the text box, on a canvas of their own (the field's size)
  local uiCanvas
  local function canvasFor(w, h)
    if not (uiCanvas and uiCanvas:getWidth() == w and uiCanvas:getHeight() == h) then
      if uiCanvas and uiCanvas.release then pcall(uiCanvas.release, uiCanvas) end
      uiCanvas = hd.real.newCanvas(w, h, { dpiscale = 1 })
      uiCanvas:setFilter("nearest", "nearest")
    end
    return uiCanvas
  end

  -- the window shake drawClassic draws with (SE_SHAKE_SCREEN, the enemy-hit shake)
  local function shake(battle)
    local fx = battle.fx
    local sx = (fx and fx.shakeX) or 0
    local sy = (fx and fx.shakeY) or 0
    if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
      sx = (battle.frame or 0) % 4 < 2 and 2 or -2
    end
    return sx, sy
  end

  --- The ORIGINAL battle, its field and its UI apart (see the header). The HUDs and the text box
  --- are the class's own (another mod's wrappers of them included), asked for when drawn.
  local function drawSplit(battle)
    battle.drawHUDs, battle.drawTextArea = noop, noop
    local ok, err = pcall(drawClassic, battle)
    battle.drawHUDs, battle.drawTextArea = nil, nil
    if not ok then error(err, 0) end
    hd.seam("ui")
    local G = love.graphics
    local prev = G.getCanvas()
    local c = canvasFor(160, 144)
    local slide = (battle.introSlide or 0) * ((Timing and Timing.BATTLE_SLIDE_PX_PER_FRAME) or 2)
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.clear(0, 0, 0, 0)
    G.setColor(1, 1, 1, 1)
    local okU, errU = pcall(function()
      battle:drawHUDs(slide)
      battle:drawTextArea()
    end)
    G.pop()
    G.setCanvas(prev)
    if not okU then error(errU, 0) end
    local sx, sy = shake(battle)
    battle:drawZonePass(c, sx, sy)
    G.setColor(1, 1, 1, 1)
  end

  -- another mod's world under this battle (Terrarium's arena), set for this frame
  local function arena(battle)
    local game = battle.game
    local renderer = game and game.renderer
    return renderer ~= nil and renderer.worldOverride ~= nil
  end

  --- Is this frame a whole screen of its own (see the header)? Read off the state stack the
  --- way Game:draw reads it.
  local function wholeScreen(game)
    local stack = game.stack
    if not (type(stack) == "table" and stack.visibleBase and type(stack.states) == "table") then
      return false
    end
    local base = stack:visibleBase()
    local state = stack.states[base]
    if type(state) ~= "table" or state == game.overworld then return false end
    -- a battle draws its own pass; a WIDE battle or a world-backed one shows around a menu
    -- (by the class's own method: a screen's proxy may answer any method name)
    if state.isWideBattleLayout ~= nil and state.isWideBattleLayout == BattleState.isWideBattleLayout then
      return false
    end
    if Game.drawBaseInStack and Game.drawBaseInStack(stack, base) ~= base then return false end
    if Game.wideBattleInStack and Game.wideBattleInStack(stack) then return false end
    return true
  end

  local function drawn(...)
    whole = false
    return ...
  end

  return function()
    if gameDraw and not ours[gameDraw] then
      Game.draw = function(self, ...)
        local ok, full = pcall(wholeScreen, self)
        whole = ok and full == true
        return drawn(gameDraw(self, ...))
      end
      ours[Game.draw] = true
    end
    if not ours[drawClassic] then
      BattleState.drawClassic = function(self, ...)
        if arena(self) then
          hd.stats.gen1Arena = (hd.stats.gen1Arena or 0) + 1
          return drawClassic(self, ...)
        end
        hd.useLayout("gen1_og")
        local okP, errP = pcall(hd.beginPass, "battle", love.graphics.getCanvas())
        if not okP then hd.fail("battle pass: " .. tostring(errP)) end
        -- the field and the UI apart only when the fit draws them apart, and only on the
        -- coloured path (the flat fallback, a blanked field: drawn whole, filling the screen)
        if not (hd.capturing("battle") and hd.fit.enabled) or self.blankForAskName
            or self.blackoutBlank or not self:colorMode() then
          return drawClassic(self, ...)
        end
        local ok, err = pcall(drawSplit, self)
        if not ok then
          hd.fail("Gen 1 battle: " .. tostring(err))
          return drawClassic(self, ...)
        end
      end
      ours[BattleState.drawClassic] = true
    end
    hd.fit.available = true
  end
end

return Gen1
