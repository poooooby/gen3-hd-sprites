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
--   SummaryMenu:drawPanel, PokedexMenu:drawPanel   the summary and the Pokedex (src/ui/gen2/;
--                          both their draw and their drawWidescreen draw the panel through it):
--                          drawn straight to the window too, so each is a direct dex pass, in which a
--                          sprite mod's tagged pic is drawn at its spec's size in place. A pic in
--                          the four shades under the palette shader (DMG, CLASSIC, a custom
--                          palette) is drawn as its shades for that shader to colour (spec.shades).
--
--   BattleState:draw        a state over a battle (a script's message): Gold draws the
--                          stack again where the panel stands, the battle first. A battle this
--                          frame filled the screen with is not drawn again, and what follows is
--                          moved to where its UI went (hd.uiMap); Game2:draw counts the frames.
--
--   Game2:paintBattleSurround   a black or world background, painted round the panel after the
--                          battle is drawn (a world one over the overworld Game2 drew first): the
--                          battle is ours on any background, its white paper laid under it (the
--                          window when it fills it, else its panel), and the surround is not
--                          painted in a frame the battle filled the window.

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
    backTopMin = 32, extraMax = 40,
    -- no side shift: the move animations' objects are placed in the cart's coordinates
    enemyX = 124, playerX = 40, shiftMax = 0,
    ground = false,
    padTop = 96, padRows = 0, padTuck = 0,
    wholeBelow = 36, cutAbove = 56,
    -- species sizing's room, clear of the UI: the enemy (its box at x 96-152, from the screen's
    -- top, its HUD up to x 96) out to the screen's edge; the player's up to the enemy's HUD's
    -- bottom (row 32; its box at 48), out to the screen's edge and its own HUD (x 16-64 to 0-72)
    fitRoom = { enemy = { up = 0, left = 0, right = 8 }, player = { up = 16, left = 16, right = 8 } },
  },
  -- The WIDE battle screen (304x144): the ORIGINAL's scene moved right by FIELD_X (72): the
  -- enemy's pic box at x 168-224, the player's at 88-136; the enemy's HUD where the ORIGINAL
  -- has it, the player's moved right by 144 (EXTRA_TILES), the text box across the bottom
  gen2_wide = {
    focus = { 152, 96 }, feetY = 56, feetMax = 58,
    split = 44, spanDefault = { 0, 304 },
    pads = { enemy = { 168, 224 }, player = { 88, 136 } }, inwardMax = 32,
    ui = { enemy = { 8, 0, 96, 32 }, player = { 216, 56, 304, 96 }, text = { -1e4, 96, 1e4, 1e4 } },
    backTopMin = 32, extraMax = 40,
    enemyX = 196, playerX = 112, shiftMax = 0,
    ground = false,
    padTop = 96, padRows = 0, padTuck = 0,
    wholeBelow = 36, cutAbove = 56,
    -- (the enemy's box at x 168-224, its HUD up to x 96)
    fitRoom = { enemy = { up = 0, left = 8, right = 8 }, player = { up = 16, left = 16, right = 8 } },
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
  -- (optional: without them a state over a filled battle is drawn the game's own way, over the
  -- battle drawn again where the panel stood)
  local okG, Game2 = pcall(require, "src.core.Game2")
  local gameDraw = okG and type(Game2) == "table" and type(Game2.draw) == "function" and Game2.draw or nil
  local battleDraw = type(BattleState.draw) == "function" and BattleState.draw or nil
  -- this frame (counted by Game2:draw), and where it showed a filled battle's UI
  local frame = 0
  local shown = { battle = nil, frame = -1, x = 0, y = 0, sx = 1, sy = 1 }
  -- (optional: without them those screens' Pokemon are drawn the game's own way)
  local screens = {}
  for _, name in ipairs({ "src.ui.gen2.SummaryMenu", "src.ui.gen2.PokedexMenu" }) do
    local okS, M = pcall(require, name)
    if okS and type(M) == "table" and type(M.drawPanel) == "function" then screens[#screens + 1] = M end
  end
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

  -- The intro slide on a filled screen. The game slides its two halves in the way the cart's
  -- scroll does (BattleAnimView:presentSlide: the bands baked and blitted row by row, shifted;
  -- the back pic drawn over them from the right), all inside its 160-px panel, so on a screen
  -- wider than that both pics would appear cut at the panel's edges. Here, with Fill Screen, the
  -- panel is drawn unshifted with the enemy's pic moved by the top band's own offset (in from
  -- the left), the back pic by its own (in from the right), every pic drawn at window
  -- resolution (a pic no sprite mod tagged, a trainer's, is tagged for the frame), so each is on
  -- the screen from the slide's first frame. The intro's blackout palette is a dark tint there
  -- (a shader would send a full-colour frame back to its stand-in, inside the panel). Only the
  -- bands' own scroll of the paper is not kept.
  local okAV, BattleAnimView = pcall(require, "src.ui.gen2.BattleAnimView")
  local okPal, Palettes = pcall(require, "src.world.gen2.Palettes")
  local slideFill = okAV and type(BattleAnimView) == "table" and type(BattleAnimView.slideOffsets) == "function"
    and type(BattleAnimView.slideBackpicOffset) == "function" and tonumber(BattleAnimView.SLIDE_FRAMES)
    and okPal and type(Palettes) == "table" and type(Palettes.BLACKOUT) == "table"
    and GbcPalette and type(GbcPalette.with) == "function"
    and type(BattleState.drawPic) == "function" and type(BattleState.pic) == "function"
  local function sliding(battle)
    return slideFill and hd.fit.enabled and hd.fit.fill and hd.capturing("battle") and battle.animView ~= nil
      and type(battle.slideFrame) == "number" and battle.slideFrame < BattleAnimView.SLIDE_FRAMES
  end
  local function drawSliding(battle, draw, ...)
    local G = love.graphics
    local tagged = {}
    local function tagFor(img, side)
      if img ~= nil and type(img) ~= "number" and img.getWidth and not hd.tagOf(img) then
        hd.tag(img, { side = side, trainer = true })
        tagged[#tagged + 1] = img
      end
    end
    tagFor(battle.playerBackImage, "player")
    tagFor(battle.enemyTrainerImage, "enemy")
    battle.pic = function(self, mon, back, ...)
      local a, b, c, d = BattleState.pic(self, mon, back, ...)
      tagFor(a, back and "player" or "enemy")
      return a, b, c, d
    end
    local with = GbcPalette.with
    GbcPalette.with = function(colors, body)
      if colors ~= Palettes.BLACKOUT then return with(colors, body) end
      local r, g, b, a = G.getColor()
      local c = Palettes.BLACKOUT[3]
      G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
      local okB, errB = pcall(body)
      G.setColor(r, g, b, a)
      if not okB then error(errB, 0) end
      return true
    end
    local view = battle.animView
    view.presentSlide = function(_, frame, drawBg, drawBackpic)
      -- (the top band's scroll: in from the left, 144 px to none, 2 a frame)
      local dx = -(BattleAnimView.slideOffsets(frame))
      battle.drawPic = function(self, mon, back, ...)
        if back then return BattleState.drawPic(self, mon, back, ...) end
        G.push()
        G.translate(dx, 0)
        local okD, errD = pcall(BattleState.drawPic, self, mon, back, ...)
        G.pop()
        if not okD then error(errD, 0) end
      end
      local okP, errP = pcall(drawBg)
      battle.drawPic = nil
      if not okP then error(errP, 0) end
      if drawBackpic then drawBackpic(BattleAnimView.slideBackpicOffset(frame)) end
    end
    local ok, err = pcall(draw, battle, ...)
    view.presentSlide, battle.pic, battle.drawPic = nil, nil, nil
    GbcPalette.with = with
    for _, img in ipairs(tagged) do hd.untag(img) end
    if not ok then error(err, 0) end
  end
  local function drawScene(battle, ...)
    if sliding(battle) then return drawSliding(battle, battle.drawScene, ...) end
    return battle:drawScene(...)
  end

  --- The WIDE battle's scene, then the UI seam, then its HUDs (under the exit fade's palette, as
  --- drawScene draws them), into the pass's canvas.
  local function drawWideSplit(battle)
    local sides = false
    drawScene(battle, function() sides = WideBattle.drawField(battle) end)
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
    local ok, err = pcall(drawScene, battle)
    battle.drawEnemyHud, battle.drawPlayerHud, battle.drawBottom = nil, nil, nil
    if not ok then error(err, 0) end
    if hd.capturing("battle") then hd.seam("ui") end
    drawUI(battle)
  end

  -- the battle draws over its own white paper whatever the background; a black or world one is
  -- painted round the panel afterwards (Game2:paintBattleSurround), a world one over the
  -- overworld Game2 drew first (with Chrome.worldSurround set, so the letterbox paints nothing)
  local filledFrame = -1    -- the frame (Game2:draw's count) the battle filled the window in
  -- (optional: without the surround's seam and the frame count, only a white background's
  -- battle is ours; a black or world one is drawn the game's way)
  local paintSurround = okG and type(Game2) == "table" and type(Game2.paintBattleSurround) == "function"
    and Game2.paintBattleSurround or nil
  local surrounds = gameDraw and battleDraw and paintSurround and true or false
  local function paperOk(battle)
    if surrounds then return true end
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
    -- the battle's white paper: the window when the battle fills it, else under its panel (a
    -- world background's overworld stays round it, the game's dimming painted after)
    local fills = hd.fit.enabled and hd.fit.fill
    if Chrome.letterbox then
      local world = Chrome.worldSurround
      if world and not fills then
        G.push("all")
        hd.scissorOver(box[1], box[2], box[3], box[4])
      end
      Chrome.worldSurround = false
      Chrome.letterbox(winW, winH, 1, 1, 1)
      Chrome.worldSurround = world
      if world and not fills then G.pop() end
    end
    local c = canvasFor(cw, 144)
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.clear(1, 1, 1, 1)
    G.setColor(1, 1, 1, 1)
    hd.useLayout(wide and "gen2_wide" or "gen2_og")
    -- (a turn playing, anything but the menus that wait for the player: src/ui/gen2/
    -- BattleState.lua; Battle Fit only pulls out meanwhile)
    if hd.setTurn then
      local ph = battle.phase
      hd.setTurn(not (ph == "menu" or ph == "submenu" or ph == "moves"))
    end
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
      hd.scissorOver(b[1], b[2], b[3], b[4])
      real.draw(cv, obx or bx, oby or by, 0, osx or scale, osy or scale)
      real.setScissor()
    end
    local cur = hd.done[c]
    local okC, done = pcall(hd.composite, c, blit, bx, by, scale, scale, box, view)
    -- (the game's black or dimmed surround is not painted over a battle that fills the window)
    if okC and done and fills then filledFrame = frame end
    -- a filled screen: where its UI went (a state drawn over the battle goes there too: over a
    -- WIDE battle, where the game puts it, the 160-wide panel's place in the middle of its 304)
    if okC and done and cur and hd.uiMap.cur == cur and gameDraw and battleDraw then
      local m = hd.uiMap
      local dx = (cw - 160) / 2
      shown.battle, shown.frame, shown.x, shown.y, shown.sx, shown.sy = battle, frame, m.x + dx * m.sx, m.y,
        m.sx, m.sy
    end
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
    if gameDraw and battleDraw and not ours[Game2.draw] then
      Game2.draw = function(...)
        frame = frame + 1
        return gameDraw(...)
      end
      ours[Game2.draw] = true
    end
    -- A state over the battle (a script's message): Gold draws the stack again where the panel
    -- stands, the battle first. A battle this frame filled the screen with is on it already, so
    -- it is not drawn again; what is drawn over it is moved to where its UI went (its text box
    -- over the battle's own).
    if gameDraw and battleDraw and not ours[BattleState.draw] then
      BattleState.draw = function(self, ...)
        if shown.battle == self and shown.frame == frame then
          local G = love.graphics
          G.origin()
          G.translate(shown.x, shown.y)
          G.scale(shown.sx, shown.sy)
          hd.stats.overBattle = (hd.stats.overBattle or 0) + 1
          return
        end
        return battleDraw(self, ...)
      end
      ours[BattleState.draw] = true
    end
    -- A black or world background: Gold paints it round the panel after the battle is drawn. A
    -- battle that filled the window this frame has no panel's edge to paint round, so it is not
    -- painted (it would cover the battle with bars).
    if surrounds and not ours[paintSurround] then
      Game2.paintBattleSurround = function(self, ...)
        if filledFrame == frame then
          hd.stats.surroundSkipped = (hd.stats.surroundSkipped or 0) + 1
          return
        end
        return paintSurround(self, ...)
      end
      ours[Game2.paintBattleSurround] = true
    end
    if not ours[drawWidescreen] then
      BattleState.drawWidescreen = function(self, winW, winH, ...)
        if self:wideLayout() or not hd.enabled.battle or hd.failed or not paperOk(self) then
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
        if not hd.enabled.battle or hd.failed or not okD or docked or not paperOk(battle) then
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
    for _, M in ipairs(screens) do
      local draw = M.drawPanel
      if not ours[draw] then
        M.drawPanel = function(...)
          if not hd.beginDirect("dex") then return draw(...) end
          hd.stats.dexPasses = (hd.stats.dexPasses or 0) + 1
          local ok, err = pcall(draw, ...)
          hd.endDirect()
          if not ok then error(err, 0) end
        end
        ours[M.drawPanel] = true
      end
    end
    hd.fit.available = true
  end
end

return Gen2
