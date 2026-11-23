-- The Gen 3 seams (FireRed, LeafGreen, Ruby, Sapphire, Emerald), wrapped by src/engine.lua's
-- install once its Renderer seams are checked (Gen3.prepare checks these first, so nothing is
-- wrapped when one is missing):
--
--   Battle.draw            the battle pass starts here (src/core/game3/battle/init.lua)
--   Pokedex.draw           the Pokedex pass starts here: Ruby/Sapphire/Emerald's
--                          (src/ui/game3/rse/pokedex.lua) and FireRed/LeafGreen's
--                          (src/ui/game3/pokedex.lua), wrapped once each is loaded; like the
--                          battle pass it ends at Renderer:endFrame. Inside a battle (a caught
--                          Pokemon's entry) the battle pass is already capturing it.
--   SummaryMenu.draw       the Pokemon summary screen, a dex pass: FireRed/LeafGreen's
--                          (src/ui/game3/summary_menu.lua) and the skins the screen stack draws
--                          in its place, Emerald's (rse/summary_menu.lua) and Ruby/Sapphire's
--                          (rs/summary_menu.lua)
--   Display.presentUi      a "boot" frame (the intro movie, the title, the main menu, Oak's or
--                          Birch's speech, the naming screens) is a boot pass: with Fill Screen
--                          it fills the screen as one picture
--   Stack.fullscreen       a frame of a whole screen over the field (the screen stack's
--                          fullscreen layers: the Pokedex, the party, the bag, the options, the
--                          mods, the trainer card...) is a "screen" pass (src/engine.lua's
--                          Renderer:beginFrame wrapper asks Engine.fullScreen)
--   Display.planesBroken   the display presents without the Renderer: nothing is captured
--   BattleTransition       the field is not captured during a battle transition
--
-- Battle Fit (optional: without them the HD sprites still work, only the fit is off):
--   BattleChrome.drawTerrain   the battle's wallpaper is handed to hd.backdrop and the two
--                          pads drawn on their own (src/ui/game3/battle_chrome.lua; the same
--                          split art the intro slide draws), the player's whole (Engine.Pads,
--                          src/pads.lua)
--   BattleChrome.drawEntry the intro's scrolling grass, drawn as a band across the whole view
--   BallOpen.draw          the last draw of the battle scene (src/core/game3/battle/ui.lua
--                          Ui.draw): the UI seam goes after it
--   Anim.drawParticles     a Pokemon drawn by a move animation is flagged (hd.inAnim)
--   AnimCoords.SINGLES, Anim.ENEMY_MON / PLAYER_MON   the battlers' coordinates move
--                          animations and the intro aim at: moved with the side shift before
--                          each battle frame (Engine.shiftCoords)
--   Pokedude.sendOutOrigin where the player's ball is thrown from: moved with the trainer
--   TrainerPic.front / back   the trainers' pics, tagged so they move with their side
--   Pokemon.frontPic / backPic   asked for both leads inside the battle's draw (Engine.prefit),
--                          so the camera is framed for a trainer's Pokemon before its send-out

local Gen3 = {}

-- the player's trainer's tag: cut by the text box, so pinned to its line (the bar's top when
-- the bar is drawn: Gen3.wrapBar)
local BACK_SPEC = { side = "player", trainer = true, pinBottom = 112 }

-- the player's HP boxes with no bottom UI drawn under them (Gen3.prepare's noteDrop): lowered
-- until their bottom is level with the player's Pokemon's feet (hd.fit.playerFeetUI), never
-- above where the game draws them, nor lower than BOX_MARGIN rows above the screen's bottom
-- (the cart leaves them 2 above its text box) or BOX_LOW. Gen3.boxDrop: this frame's, whole rows
Gen3.BOX_LOW, Gen3.BOX_MARGIN = 158, 2
Gen3.boxDrop = 0

-- the Pokedex screens and the summary screen, by module name; each is wrapped when it is first
-- seen loaded, and draws in a dex pass
local DEX_MODULES = { "src.ui.game3.rse.pokedex", "src.ui.game3.pokedex", "src.ui.game3.summary_menu",
  "src.ui.game3.rse.summary_menu", "src.ui.game3.rs.summary_menu" }

--- Wrap the Battle Fit seams. Returns true when both are in place.
function Gen3.wrapFit(Engine, hd)
  local ours = Engine.ours
  local okC, Chrome = pcall(require, "src.ui.game3.battle_chrome")
  local okB, BallOpen = pcall(require, "src.core.game3.battle.ball_open")
  if not (okC and type(Chrome) == "table" and type(Chrome.drawTerrain) == "function"
          and type(Chrome.terrain) == "function"
          and okB and type(BallOpen) == "table" and type(BallOpen.draw) == "function") then
    return false
  end
  local function fitting() return hd.fit.enabled and hd.capturing("battle") end
  -- this battle's 2.5D scene (Battle Scene: Overworld, src/scene/), or nil: the wallpaper
  local okBM, BattleMod = pcall(require, "src.core.game3.battle")
  local function sceneFor(key, entry)
    local Scene = Engine.Scene
    if not (Scene and Scene.enabled and okBM and type(BattleMod) == "table") then return nil end
    return Scene.forBattle(BattleMod._st, key, entry and entry.bgImage)
  end

  local drawTerrain = Chrome.drawTerrain
  if not ours[drawTerrain] then
    local function fitTerrain(key, enemyOx, playerOx, bgOx)
      key = key or "building"
      local entry = Chrome.terrain(key) or Chrome.terrain("building") or Chrome.terrain("grass")
      local scene = sceneFor(key, entry)
      if scene and entry and entry.bgImage and hd.world(entry.bgImage, scene, 0, 0) then
        -- the world in place of the wallpaper; a soft shadow under each side instead of its pad
        -- (sliding in with the side, as the pads do)
        Engine.Scene.step(scene, enemyOx)
        local G = love.graphics
        local fade = math.min(1, scene.progress * 1.5)
        G.setColor(1, 1, 1, Engine.Scene.SHADOW_ALPHA * fade)
        if scene.shadows.enemy then hd.drawStage(scene.shadows.enemy, tonumber(enemyOx) or 0, 0, "enemy") end
        if scene.shadows.player then hd.drawStage(scene.shadows.player, tonumber(playerOx) or 0, 0, "player") end
        G.setColor(1, 1, 1, 1)
        if Engine.prefit then
          local okP, errP = pcall(Engine.prefit)
          if not okP then hd.stats.prefitError = tostring(errP) end
        end
        return true
      end
      if entry and entry.bgImage and entry.enemyPlat and entry.playerPlat then
        local G = love.graphics
        G.setColor(1, 1, 1, 1)
        hd.backdrop(entry.bgImage, -((tonumber(bgOx) or 0) % 256), 0)
        hd.drawStage(entry.enemyPlat, tonumber(enemyOx) or 0, 0, "enemy")
        -- the player's pad whole (src/pads.lua): the camera may rise past its cut
        local pad = Engine.Pads and Engine.Pads.playerPad(entry, hd.real,
          love.graphics.newImage, love.image and love.image.newImageData)
        hd.drawStage(pad or entry.playerPlat, tonumber(playerOx) or 0, 0, "player")
        if Engine.prefit then
          local okP, errP = pcall(Engine.prefit)
          if not okP then hd.stats.prefitError = tostring(errP) end   -- for stats(), never fatal
        end
        return true
      end
    end
    Chrome.drawTerrain = function(key, enemyOx, playerOx, bgOx, ...)
      if fitting() then
        local ok, drawn = pcall(fitTerrain, key, enemyOx, playerOx, bgOx)
        if not ok then hd.fail("drawTerrain: " .. tostring(drawn))
        elseif drawn then return true end
      end
      return drawTerrain(key, enemyOx, playerOx, bgOx, ...)
    end
    ours[Chrome.drawTerrain] = true
  end

  -- the battle's sandstorm picture (AnimTask_LoadSandstormBackground, on BG1): none over a battle
  -- scene whose world blows its own sand, the task's blend and its flying sprites kept (Emerald
  -- 3DS's battle_anim_rock.c patch and CtrBattle_Sandstorm, CC BY-NC-SA 4.0; see LICENSE). The
  -- task's first call lays the picture on BG1; it is taken off again at once (P.bg1Clear)
  local okT, AnimTasks = pcall(require, "src.core.game3.battle.anim_tasks")
  local REG = okT and type(AnimTasks) == "table" and type(AnimTasks.REGISTRY) == "table" and AnimTasks.REGISTRY
  local loadSand = REG and REG.LoadSandstormBackground
  if type(loadSand) == "function" and not ours[loadSand] then
    local function noSandPicture(t, vm, ...)
      local r = loadSand(t, vm, ...)
      -- (run in the game's update, outside the draw pass: the scene's own flag, set as it draws)
      if type(t) == "table" and t._bg1key == "SANDSTORM" and hd.fit.enabled and not Engine.asideNow and Engine.Scene
          and Engine.Scene.enabled and Engine.Scene.drawsSand and okBM and type(BattleMod) == "table"
          and Engine.Scene.drawsSand(BattleMod._st) then
        t.draw, t._bg1key = nil, nil
        hd.stats.sceneSandPicture = "dropped"
      end
      return r
    end
    REG.LoadSandstormBackground = noSandPicture
    REG.AnimTask_LoadSandstormBackground = noSandPicture
    ours[noSandPicture] = true
  end

  -- the intro's scrolling grass (a background layer that wraps on the cart): drawn as a band
  -- across the whole zoomed-out view instead of one screen-wide image
  local drawEntry = Chrome.drawEntry
  if type(drawEntry) == "function" and type(Chrome.entry) == "function" and not ours[drawEntry] then
    Chrome.drawEntry = function(key, scrollX, scrollY, alpha, ...)
      -- (the battle scene's glide is this battle's entrance: no bands over it)
      if fitting() and Engine.Scene and okBM and type(BattleMod) == "table"
          and Engine.Scene.current(BattleMod._st) then
        return true
      end
      if fitting() then
        -- (an entry missing from the cache errors exactly as the game's own draw would)
        local e = Chrome.entry(key)
        if not e then return false end
        alpha = alpha or 1
        if alpha <= 0 then return true end
        local G = love.graphics
        G.setColor(1, 1, 1, alpha)
        local ok, err = pcall(hd.band, e.image, -((math.floor(scrollX or 0)) % 256), -(math.floor(scrollY or 0)))
        G.setColor(1, 1, 1, 1)
        if ok then return true end
        hd.fail("drawEntry: " .. tostring(err))
      end
      return drawEntry(key, scrollX, scrollY, alpha, ...)
    end
    ours[Chrome.drawEntry] = true
  end

  local ballDraw = BallOpen.draw
  if not ours[ballDraw] then
    -- (the draw's results passed through, no table each call)
    local function afterBall(...)
      if fitting() then
        local ok, err = pcall(hd.seam, "ui")
        if not ok then hd.fail("seam: " .. tostring(err)) end
      end
      return ...
    end
    BallOpen.draw = function(...)
      return afterBall(ballDraw(...))
    end
    ours[BallOpen.draw] = true
  end

  -- the side shift (src/hd.lua fit.shift). Move animations aim at the engine's battler
  -- coordinates, so those move with the shift; a Pokemon drawn while an animation runs is
  -- flagged (hd.inAnim), as it already stands on the shifted coordinates
  local okA, Anim = pcall(require, "src.core.game3.battle.anim")
  local okC2, AnimCoords = pcall(require, "src.core.game3.battle.anim_coords")
  if okA and type(Anim) == "table" and type(Anim.drawParticles) == "function" and okC2
      and type(AnimCoords) == "table" and type(AnimCoords.SINGLES) == "table"
      and AnimCoords.SINGLES[0] and AnimCoords.SINGLES[1] then
    local drawParticles = Anim.drawParticles
    if not ours[drawParticles] then
      local function afterParticles(setY, wasY, ...)
        if setY then setY(wasY) end
        hd.inAnim = false
        return ...
      end
      Anim.drawParticles = function(...)
        -- (hd.beginPass clears it too, should a draw here ever throw)
        hd.inAnim = true
        local setY = Engine.doublesY
        local wasY = setY and setY(true)
        return afterParticles(setY, wasY, drawParticles(...))
      end
      ours[Anim.drawParticles] = true
    end
    -- the intro's black bars (ui.lua draws stage.win0 as two rectangles after the UI seam):
    -- with Fill Screen, hd draws them across the whole view
    if type(Anim.stage) == "function" then
      Engine.introWindow = function()
        local s = Anim.stage()
        local w = type(s) == "table" and s.win0
        if type(w) == "table" then hd.window(w[1], w[2]) else hd.window(nil, nil) end
      end
    end

    local S = AnimCoords.SINGLES
    local home = Engine.shiftHome or { player = S[0].x, enemy = S[1].x, playerY = S[0].y }
    Engine.shiftHome = home
    local function place(t, x)
      t.x = x
      t[1] = x
    end
    -- the intro's own copies of the battlers' spots (ball targets, the catch, a switch)
    local EM, PM = type(Anim.ENEMY_MON) == "table" and Anim.ENEMY_MON, type(Anim.PLAYER_MON) == "table" and Anim.PLAYER_MON
    home.enemyY = home.enemyY or S[1].y
    home.enemyMon = home.enemyMon or (EM and EM.x)
    home.playerMon = home.playerMon or (PM and PM.x)
    home.playerMonY = home.playerMonY or (PM and PM.y)
    home.enemyMonY = home.enemyMonY or (EM and EM.y)
    -- a double battle's own table: its battlers are drawn on these too, so hd puts a tagged one
    -- back on its unshifted spot when it records it (hd's wrapped draw) and shifts it as usual.
    -- Their rows are the unshifted ones while the battle draws them (Engine.doublesY false): the
    -- game caps how low a back stands, which would swallow the player's side's drop; moves read
    -- the shifted rows, between draws and in Anim.drawParticles
    local D = type(AnimCoords.DOUBLES) == "table" and AnimCoords.DOUBLES or nil
    if D and not home.doubles then
      home.doubles = {}
      for id = 0, 3 do home.doubles[id] = D[id] and { x = D[id].x, y = D[id].y } or nil end
    end
    local doublesDy, yShifted = 0, true
    -- (each double battler's column as shifted and spread, and how far the Battle Camera's turned
    -- view moves its spot: moves read them, the battle draws on the column alone)
    local doublesX, lookDx, lookDy = {}, { [0] = 0, 0, 0, 0 }, { [0] = 0, 0, 0, 0 }
    if D then
      --- Put the battlers' rows on the shifted or the unshifted spots; returns the previous state.
      Engine.doublesY = function(shifted)
        local was = yShifted
        yShifted = shifted
        for id = 0, 3 do
          local h = home.doubles[id]
          if h then
            local y = h.y + ((shifted and id % 2 == 0) and doublesDy or 0) + (shifted and lookDy[id] or 0)
            D[id].y, D[id][2] = y, y
            local x = doublesX[id]
            if x then
              x = x + (shifted and lookDx[id] or 0)
              D[id].x, D[id][1] = x, x
            end
          end
        end
        return was
      end
    end
    -- the Battle Camera (src/scene/orbit.lua): each battler's anchor given and the view stepped,
    -- once each battle frame before the coordinates below are set; Engine.lookNow the look while
    -- the view is turned (nil at rest)
    Engine.lookStep = function(Battle)
      Engine.lookNow = nil
      local Scene = Engine.Scene
      local Orbit = Scene and Scene.Orbit
      if not (Orbit and Scene.enabled and hd.fit.enabled and not Engine.asideNow) then return end
      local st = Battle._st
      local s = type(st) == "table" and Scene.current(st)
      if not (s and s.to) then return end
      local F = Scene.FEET
      local double = st.double == true
      -- (the sides' singles feet: in a double battle only the middle between them)
      Orbit.foot(s, "enemy", "enemy", F.enemy[1], F.enemy[2], double)
      Orbit.foot(s, "player", "player", F.player[1], F.player[2], double)
      if double and home.doubles then
        for id = 0, 3 do
          local h = home.doubles[id]
          if h then
            local side = id % 2 == 1 and "enemy" or "player"
            local sx = hd.spreadDx and hd.spreadDx(h.x) or 0
            local hy = side == "enemy" and (home.enemyY or 40) or (home.playerY or 80)
            Orbit.foot(s, id, side, h.x + sx, F[side][2] + (h.y - hy))
          end
        end
      end
      Orbit.look(s).double = double
      -- (only with the battlers drawn by a sprite mod: the game's own stay where it draws them)
      local pair = hd.pair
      local tagged = type(pair) == "table" and (pair.enemy ~= nil or pair.player ~= nil)
      local now = love.timer and love.timer.getTime() or 0
      local L = Orbit.step(s, now, tagged and s.progress >= 1)
      if L.on then Engine.lookNow = L end
    end
    -- (a point x, y of the battler at anchor `key`, where the turned view puts it)
    local function looked(key, x, y)
      local L = Engine.lookNow
      local f = L and L.feet[key]
      if not (f and f.frame == L.frame and f.u) then return x, y end
      return f.u + (x - f.u0) * f.r, f.v + (y - f.v0) * f.r
    end
    -- (not on a battle another UI mod draws: Engine.asideNow, set as each battle frame begins)
    local function on(Battle)
      local st = Battle._st
      return hd.fit.enabled and not Engine.asideNow and st ~= nil and not st.double
    end
    local function onDouble(Battle)
      local st = Battle._st
      return hd.fit.enabled and not Engine.asideNow and st ~= nil and st.double == true
    end
    Engine.shiftOn = on
    --- Before each battle frame: the engine's battler coordinates (move animations, the
    --- intro's ball targets) stand where the shift this frame is drawn with puts them.
    Engine.shiftCoords = function(Battle)
      local fit = hd.fit
      local e = on(Battle) and fit.shift.enemy or 0
      local p = on(Battle) and fit.shift.player or 0
      local py = on(Battle) and fit.shift.playerY or 0
      -- the Pokemon's own spot: a small back stands raised above its pad
      local pm = py - (on(Battle) and fit.shift.playerRaise or 0)
      -- (the 3D world: the foe's moves aimed at its body as drawn, hd's fit.aimEnemy; and the
      -- player's, at its body as drawn; each where the Battle Camera's turned view puts it)
      local ey = (on(Battle) and fit.aimEnemy) or home.enemyY
      local ex
      ex, ey = looked("enemy", home.enemy + e, ey or 40)
      place(S[1], ex)
      if home.enemyY then S[1].y, S[1][2] = ey, ey end
      local py0 = home.playerY and ((on(Battle) and fit.aimPlayer) or (home.playerY + pm)) or 80
      local px
      px, py0 = looked("player", home.player + p, py0)
      place(S[0], px)
      if home.playerY then S[0].y, S[0][2] = py0, py0 end
      -- (the line the moves run along, player to foe: where hd grows their pieces, a giant's end
      -- the bigger)
      if on(Battle) and (fit.fxEnemy or 1) + (fit.fxPlayer or 1) > 2.002 then
        local l = fit.fxLine or {}
        l[1], l[2], l[3], l[4] = S[0].x, S[0].y, S[1].x, S[1].y
        fit.fxLine = l
      else
        fit.fxLine = nil
      end
      if EM and home.enemyMon then EM.x, EM.y = looked("enemy", home.enemyMon + e, home.enemyMonY or EM.y) end
      if PM and home.playerMon then
        PM.x, PM.y = looked("player", home.playerMon + p, (home.playerMonY or PM.y) + (home.playerMonY and pm or 0))
      end
      local two = D and onDouble(Battle)
      local de = two and fit.shift.enemy or 0
      local dp = two and fit.shift.player or 0
      doublesDy = two and (fit.shift.playerY - (fit.shift.playerRaise or 0)) or 0
      if D then
        for id = 0, 3 do
          local h = home.doubles[id]
          -- (and its spot spread apart, the 3D world's doubles: hd.spreadDx)
          local sx = two and hd.spreadDx and hd.spreadDx(h and h.x or 0) or 0
          if h then
            local x = h.x + (id % 2 == 0 and dp or de) + sx
            doublesX[id] = x
            place(D[id], x)
            -- (the Battle Camera: how far the turned view moves its spot, its shifted row's)
            local y = h.y + (id % 2 == 0 and two and (fit.shift.playerY - (fit.shift.playerRaise or 0)) or 0)
            local lx, ly = looked(id, x, y)
            lookDx[id], lookDy[id] = lx - x, ly - y
          end
        end
        Engine.doublesY(true)
      end
      Engine.shiftNow = { enemy = two and de or e, player = two and dp or p, playerY = two and fit.shift.playerY or py }
    end

    --- Both leads, before they are sent out: their pics as the battle will draw them (asked for
    --- inside the battle's draw, so a sprite mod hands over its battle pics), centred where
    --- the battle will put them, so the camera is framed for them from the first frame.
    local okPk, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okUi, Ui = pcall(require, "src.core.game3.battle.ui")
    -- through require: a mod's package.loaded is not the engine's
    local okB2, BattleMod = pcall(require, "src.core.game3.battle")
    if not okB2 then BattleMod = nil end
    -- (each battler's presentation: whether its sprite is still up, src/core/game3/battle/anim.lua)
    local okAnim, Anim = pcall(require, "src.core.game3.battle.anim")
    if not (okAnim and type(Anim) == "table") then okAnim, Anim = false, nil end
    if okPk and okUi and type(Pokemon) == "table" and type(Ui) == "table"
        and type(Ui.battlerSpriteCenter) == "function" and type(Ui.picArgs) == "function" then
      local spots = {
        enemy = { x = home.enemyMon or 176, y = EM and EM.y or 40 },
        player = { x = home.playerMon or 72, y = PM and PM.y or 80 },
      }
      -- (the spot handed to battlerSpriteCenter, kept: it reads it there and then)
      local spotArg = {}
      Engine.prefit = function()
        local B = BattleMod
        local st = B and B._st
        if not st then return end
        if st.double then
          -- each battler still in, on its own unshifted spot (the battle draws a tagged one
          -- there): the target cursor hides the picked foe every other beat
          -- (Ui.targetHidden), and a move lunges or swells one; neither moves the camera
          if not (home.doubles and Pokemon.speciesOf) then return end
          for id = 0, 3 do
            local h = home.doubles[id]
            local battler = (id == 0 and st.player) or (id == 1 and st.enemy)
              or (st.battlers and st.battlers[id])
            local mon = battler and battler.mon
            -- (a battler knocked out is still in until its faint hides it: through the hit's blink
            -- it stays fitted where it rests, else the camera followed the blink - with one foe
            -- left, the only one of its side - the picture jumping sideways every few frames)
            local inBattle = (tonumber(mon and mon.hp) or 1) > 0
            if not inBattle and mon then
              local pres = okAnim and type(Anim._present) == "table" and rawget(Anim._present, id)
              inBattle = type(pres) == "table" and pres.visible ~= false
            end
            if h and mon and not (st.absent and st.absent[id]) and inBattle then
              local sp = Pokemon.speciesOf(mon)
              if sp then
                local picSp, shiny, personality = Ui.picArgs(battler, sp)
                local entry
                if id % 2 == 1 then
                  entry = Pokemon.frontPic and Pokemon.frontPic(picSp, nil, shiny, personality)
                else
                  entry = Pokemon.backPic and Pokemon.backPic(picSp, nil, shiny)
                end
                if entry and entry.image then
                  spotArg.x, spotArg.y = h.x, h.y
                  local cx, cy = Ui.battlerSpriteCenter(id, sp, spotArg, nil, false)
                  hd.prefit(id % 2 == 1 and "enemy" or "player", entry.image, cx, cy, id)
                end
              end
            end
          end
          return
        end
        -- (whether each is out on the field, its sprite up: before its send-out and after its
        -- faint it is not; and whether the opposing trainer is shown)
        local stage = okAnim and type(Anim._stage) == "table" and Anim._stage
        local tr = stage and type(stage.trainer) == "table" and stage.trainer.enemy
        if hd.fieldTrainer then hd.fieldTrainer(type(tr) == "table" and tr.visible == true) end
        for side, spot in pairs(spots) do
          local battler = st[side]
          local mon = battler and battler.mon
          local sp = mon and Pokemon.speciesOf and Pokemon.speciesOf(mon)
          local pres = okAnim and type(Anim._present) == "table" and rawget(Anim._present, side == "player" and 0 or 1)
          local out = not (type(pres) == "table" and pres.visible == false)
          if sp then
            local picSp, shiny, personality = Ui.picArgs(battler, sp)
            local entry
            if side == "enemy" then
              entry = Pokemon.frontPic and Pokemon.frontPic(picSp, nil, shiny, personality)
            else
              entry = Pokemon.backPic and Pokemon.backPic(picSp, nil, shiny)
            end
            if entry and entry.image then
              spotArg.x, spotArg.y = spot.x, spot.y
              local cx, cy = Ui.battlerSpriteCenter(side, sp, spotArg, nil, false)
              hd.prefit(side, entry.image, cx, cy, nil, out)
            end
          end
        end
      end
    end

    -- the player's ball is thrown from the trainer's hand: it moves with the trainer
    local okP, Pokedude = pcall(require, "src.core.game3.battle.pokedude")
    if okP and type(Pokedude) == "table" and type(Pokedude.sendOutOrigin) == "function" then
      local origin = Pokedude.sendOutOrigin
      if not ours[origin] then
        Pokedude.sendOutOrigin = function(...)
          local x, y = origin(...)
          -- (only side to side: the trainer stays anchored to the text box)
          local now = Engine.shiftNow or {}
          if type(x) == "number" then x = x + (now.player or 0) end
          return x, y
        end
        ours[Pokedude.sendOutOrigin] = true
      end
    end

    -- the trainers move with their side; the player's, cut by the text box, stays cut there
    local okT, TrainerPic = pcall(require, "src.core.game3.trainer_pic")
    if okT and type(TrainerPic) == "table" then
      local function tagging(name, spec)
        local fn = TrainerPic[name]
        if type(fn) ~= "function" or ours[fn] then return end
        TrainerPic[name] = function(...)
          local entry = fn(...)
          if type(entry) == "table" and entry.image and not hd.tagOf(entry.image) then
            pcall(hd.tag, entry.image, spec)
          end
          return entry
        end
        ours[TrainerPic[name]] = true
      end
      tagging("front", { side = "enemy", trainer = true })
      tagging("back", BACK_SPEC)
    end
  end
  return true
end

--- Check the Gen 3 seams (raises when one is missing, before anything is wrapped) and return
--- the function that wraps them, which src/engine.lua calls once its own seams are in place.
function Gen3.prepare(Engine, hd)
  local need, ours = Engine.need, Engine.ours
  local Battle = require("src.core.game3.battle")
  local battleDraw = need(Battle, "draw")
  hd.useLayout("gen3")

  -- the Gen 3 display falls back to presenting without the Renderer when anything in its
  -- plane path errors (Display.planesBroken, for the session): a pass could then never be
  -- composited, so nothing is captured and every frame is drawn the game's own way
  local okD, Display = pcall(require, "src.core.game3.display")
  hd.canCapture = function()
    return not (okD and type(Display) == "table" and Display.planesBroken)
  end

  -- a whole screen over the field (the screen stack's fullscreen layers, which the display
  -- draws with no field behind them): a screen pass
  local Stack
  Engine.fullScreen = function()
    -- (through require: a mod's package.loaded is not the engine's)
    Stack = Stack or require("src.ui.game3.stack")
    return type(Stack) == "table" and type(Stack.fullscreen) == "function"
      and not Battle.isActive() and Stack.fullscreen() == true
  end
  -- a battle transition draws the field through canvases of its own
  Engine.fieldBusy = function()
    local BattleTransition = package.loaded["src.core.game3.battle_transition"]
    return BattleTransition and BattleTransition.isActive and BattleTransition.isActive()
  end
  Engine.dexModules = DEX_MODULES

  return function()
    -- a double battle's HP boxes, from the engine's own centres (they differ by game): each
    -- side's two together, {x0, y0, x1, y1}; the box's extent about its centre as the game draws it
    local okH, Healthbox = pcall(require, "src.core.game3.battle.healthbox")
    local function doubleBoxes(st)
      if not (okH and type(Healthbox) == "table" and type(Healthbox.center) == "function") then return nil end
      local function span(a, b, x0, x1, y0)
        local ca, cb = Healthbox.center(st, a), Healthbox.center(st, b)
        return { math.min(ca.x, cb.x) + x0, math.min(ca.y, cb.y) + y0,
                 math.max(ca.x, cb.x) + x1, math.max(ca.y, cb.y) + 10 }
      end
      return span(1, 3, -31, 60, -14), span(0, 2, -22, 68, -13)
    end
    -- each HP box drawn between hd.boxBegin and hd.boxEnd (so a placement can move it whole, in a
    -- layer of its own): Healthbox.draw wrapped, and wrapped again whenever a mod
    -- wraps it after us (Wooble Dex's badges, Facets' box sets), so what they draw with a box is
    -- inside ours. id: its battler (singles: 1 the foe's, 0 the player's); ox, oy: the game's
    -- slide-in (its stage offset) and bounce, from where it rests
    local okA, Anim = pcall(require, "src.core.game3.battle.anim")
    local boxDraw, boxDepth = nil, 0
    local function boxOffsets(side, opts)
      local key = side
      local stage = okA and type(Anim) == "table" and Anim.stage and Anim.stage()
      local tbl = type(stage) == "table" and stage.healthbox
      local hb = type(tbl) == "table" and (tbl[key] or (key == 0 and tbl.player) or (key == 1 and tbl.enemy)
        or (key == "player" and tbl[0]) or (key == "enemy" and tbl[1])) or nil
      local ox = ((type(hb) == "table" and tonumber(hb.ox)) or 0) + ((type(opts) == "table" and tonumber(opts.ox)) or 0)
      local oy = ((type(hb) == "table" and type(side) == "number" and tonumber(hb.oy)) or 0)
        + ((type(opts) == "table" and tonumber(opts.oy)) or 0)
      return ox, oy
    end
    -- a battle hiding its bottom UI (Ui.bottomUIVisible: Kanto Gear's GEAR view shows the
    -- commands elsewhere) draws neither the bar nor the cart's text box there: the player's HP
    -- boxes, and its party's ball row, are drawn lower, their bottom on the Pokemon's feet as the
    -- last frame drew them (never past the screen's bottom: BOX_LOW, BOX_MARGIN), and the fit
    -- sees them there. Not while the battle hides its HP boxes too
    -- (Kanto Gear's FULL view), nor with Battle HD off. Gen3.boxDrop: this frame's, canvas rows
    local okU, Ui = pcall(require, "src.core.game3.battle.ui")
    local okC, Chrome = pcall(require, "src.ui.game3.battle_chrome")
    local base = setmetatable({}, { __mode = "k" }) -- [a fit's player box rect] = its own rows
    local function lowered()
      if not (hd.enabled.battle and okU and type(Ui) == "table") then return false end
      local okB, bottom = pcall(Ui.bottomUIVisible)
      if not okB or bottom ~= false then return false end
      local okS, status = pcall(Ui.statusHUDVisible)
      return okS and status ~= false
    end
    local function noteDrop()
      local p = hd.layout == "gen3" and hd.fit.ui and hd.fit.ui.player
      local rows = type(p) == "table" and base[p]
      if type(p) == "table" and not rows then
        rows = { p[2], p[4] }
        base[p] = rows
      end
      local drop = 0
      local feet = tonumber(hd.fit.playerFeetUI)
      if feet and lowered() then
        local bottom = rows and rows[2] or 110
        local low = math.min(Gen3.BOX_LOW, (tonumber(hd.fit.screenBottomUI) or 160) - Gen3.BOX_MARGIN)
        drop = math.max(0, math.min(math.floor(low - bottom), math.floor(feet - bottom + 0.5)))
      end
      Gen3.boxDrop = drop
      hd.stats.boxDrop = drop
      if rows then p[2], p[4] = rows[1] + drop, rows[2] + drop end
    end
    if okC and type(Chrome) == "table" and type(Chrome.drawPartyBar) == "function"
        and not ours[Chrome.drawPartyBar] then
      local drawPartyBar = Chrome.drawPartyBar
      Chrome.drawPartyBar = function(x, y, balls, ox, isOpponent, ...)
        if not isOpponent and Gen3.boxDrop ~= 0 and type(y) == "number" then y = y + Gen3.boxDrop end
        return drawPartyBar(x, y, balls, ox, isOpponent, ...)
      end
      ours[Chrome.drawPartyBar] = true
    end

    local function wrapBoxes()
      if not (okH and type(Healthbox) == "table" and type(Healthbox.draw) == "function" and hd.boxBegin) then return end
      if Healthbox.draw == boxDraw then return end
      local inner = Healthbox.draw
      local function after(began, pushed, ok, ...)
        if began then hd.boxEnd() end
        if pushed then love.graphics.pop() end
        boxDepth = boxDepth - 1
        if not ok then error((...), 0) end
        return ...
      end
      boxDraw = function(side, battler, opts, ...)
        if boxDepth > 0 or battler == nil then return inner(side, battler, opts, ...) end
        local id = side == "enemy" and 1 or side == "player" and 0 or side
        local ox, oy = boxOffsets(side, opts)
        boxDepth = boxDepth + 1
        -- (the player's boxes, 0 and 2, lowered: noteDrop)
        local pushed = Gen3.boxDrop ~= 0 and (id == 0 or id == 2)
        if pushed then
          love.graphics.push()
          love.graphics.translate(0, Gen3.boxDrop)
        end
        local began = hd.boxBegin(id, ox, oy)
        return after(began, pushed, pcall(inner, side, battler, opts, ...))
      end
      Healthbox.draw = boxDraw
      ours[boxDraw] = true
    end

    local wasDouble = false
    local function noteDouble()
      local st = Battle._st
      local double = type(st) == "table" and st.double == true
      if double == wasDouble then return end
      wasDouble = double
      if double then hd.setDouble(true, doubleBoxes(st)) else hd.setDouble(false) end
    end

    -- the battlers' rows go back to the shifted ones once the battle is drawn (see Engine.doublesY)
    local function drawn(...)
      if Engine.doublesY then Engine.doublesY(true) end
      return ...
    end

    if not ours[battleDraw] then
      Battle.draw = function(...)
        pcall(noteDouble)
        pcall(noteDrop)
        -- (a turn playing, anything but the command menu: Battle Fit only pulls out meanwhile)
        if hd.setTurn then hd.setTurn(Battle._phase ~= nil and Battle._phase ~= "command") end
        -- (a battle OmniUI draws: the game's own, no shift either - src/omni.lua)
        local okA, aside = pcall(function() return hd.aside and hd.enabled.battle and hd.aside("battle") end)
        Engine.asideNow = okA and aside == true
        pcall(wrapBoxes)
        if Engine.lookStep then
          local okL, errL = pcall(Engine.lookStep, Battle)
          if not okL then hd.stats.lookError = tostring(errL) end
        end
        if Engine.shiftCoords then pcall(Engine.shiftCoords, Battle) end
        local ok, err = pcall(hd.beginPass, "battle", love.graphics.getCanvas())
        if not ok then hd.fail("battle pass: " .. tostring(err)) end
        if Gen3.barFrame then pcall(Gen3.barFrame) end
        if Engine.introWindow then pcall(Engine.introWindow) end
        if Engine.doublesY then Engine.doublesY(false) end
        return drawn(battleDraw(...))
      end
      ours[Battle.draw] = true
    end
    -- the screens before the game starts: one reused closure, the frame's own draw in a local
    if okD and type(Display) == "table" and type(Display.presentUi) == "function"
        and not ours[Display.presentUi] then
      local presentUi = Display.presentUi
      local drawFrame
      local function drawBoot()
        local okB, errB = pcall(hd.beginPass, "boot", love.graphics.getCanvas())
        if not okB then hd.fail("boot pass: " .. tostring(errB)) end
        return drawFrame()
      end
      local function presented(...)
        Engine.presentingUi = false
        return ...
      end
      Display.presentUi = function(game, winW, winH, kind, drawFn, ...)
        Engine.presentingUi = true
        if kind ~= "boot" then return presented(presentUi(game, winW, winH, kind, drawFn, ...)) end
        drawFrame = drawFn
        return presented(presentUi(game, winW, winH, kind, drawBoot, ...))
      end
      ours[Display.presentUi] = true
    end
    local okFit, fitOk = pcall(Gen3.wrapFit, Engine, hd)
    hd.fit.available = okFit and fitOk == true
    local okBar, barErr = pcall(Gen3.wrapBar, Engine, hd)
    if not okBar then hd.fail("battle bar: " .. tostring(barErr)) end
  end
end

--- The battle bar (src/bar.lua; every Gen 3 game, Battle Text Box on: hd.barEnabled):
--- the cart's text box and menu frames replaced by the bar, painted at the screen's resolution
--- (hd.paint) where the battle draws its panel, and what the battle draws on it (the prompt,
--- the menus, the cursors, its message) moved into it (hd.bar). Nothing is drawn when the
--- battle hides its bottom UI (Ui.bottomUIVisible: Kanto Gear's GEAR screens take it), or
--- without a battle pass (Battle HD off): the game's own boxes then. The screens that show the
--- battle's text box without its UI - a catch's Pokedex page and nickname prompt (in the battle
--- pass), an evolution and an egg hatching (a screen pass) - have the bar too (hd.cardUi: their
--- whole picture fills the screen, the bar across it).
--
--   BattleChrome.drawPanel        the text box's art (src/ui/game3/battle_chrome.lua): the
--                                 bar painted instead, and its text window opened
--   BattleChrome.drawMenuFrames   the menus' frames (the player's FRAME): not drawn under it
--   rs.menu_cursor.draw           Ruby / Sapphire's red cursor: widened left in the bar
--   Ui.voiceoverDim               called just after the menus (src/core/game3/battle/ui.lua
--                                 Ui.draw): the text window closes
--   Message.draw                  the battle's message (src/ui/game3/message.lua), after the
--                                 battle's draw: in a text window of its own; not drawn at
--                                 all while the battle hides its bottom UI (every Gen 3 game)
function Gen3.wrapBar(Engine, hd)
  local ours, Bar = Engine.ours, Engine.Bar
  if type(Bar) ~= "table" then return false end
  local okC, Chrome = pcall(require, "src.ui.game3.battle_chrome")
  local okU, Ui = pcall(require, "src.core.game3.battle.ui")
  if not (okC and type(Chrome) == "table" and type(Chrome.drawPanel) == "function"
          and type(Chrome.layout) == "function" and okU and type(Ui) == "table") then
    return false
  end
  local okM, Message = pcall(require, "src.ui.game3.message")
  -- each layout's text windows, by panel mode, and the paint's argument (made once)
  local specs, args = {}, {}
  for name, L in pairs(Bar.LAYOUT) do
    specs[name], args[name] = {}, {}
    for _, mode in ipairs({ "none", "menu", "moves" }) do
      specs[name][mode] = { top = Bar.TOP, bottom = Bar.BOTTOM, dy = L.dy, split = L.split[mode] }
      args[name][mode] = { layout = L, mode = mode }
    end
  end
  local function layoutName()
    local ok, name = pcall(Chrome.layout)
    return ok and name or nil
  end
  local function shown()
    if type(Ui.bottomUIVisible) ~= "function" then return true end
    local ok, v = pcall(Ui.bottomUIVisible)
    return not ok or v ~= false
  end
  -- (the screens over the field that draw the battle's text box: an evolution, an egg hatching)
  local okE, Evo = pcall(require, "src.ui.game3.evolution_scene")
  local okH, Hatch = pcall(require, "src.ui.game3.egg_hatch")
  local function panelScreen()
    if not hd.capturing("screen") then return false end
    if okE and type(Evo) == "table" and Evo.open then return true end
    if okH and type(Hatch) == "table" and (Hatch.open or Hatch._open or (type(Hatch.isOpen) == "function" and Hatch.isOpen())) then
      return true
    end
    return false
  end
  -- the bar for this game, wanted (Battle Text Box on, Battle HD on, a battle pass or a screen
  -- with the battle's text box)
  local function wanted()
    return hd.barEnabled ~= false and hd.enabled.battle and (hd.capturing("battle") or panelScreen())
      and Bar.LAYOUT[layoutName() or ""] ~= nil
  end
  Gen3.barWanted = wanted
  -- the pass the bar was painted in (its text windows belong to it: by its serial - a pass's
  -- table is reused the frame after next), the window open
  local barPass, windowOpen = nil, false
  local function inBarPass(cur) return cur ~= nil and barPass ~= nil and cur.serial == barPass end

  local drawPanel = Chrome.drawPanel
  if not ours[drawPanel] then
    Chrome.drawPanel = function(mode, ...)
      local name = layoutName()
      if wanted() and (shown() or panelScreen()) then
        mode = specs[name][mode] and mode or "none"
        -- (a whole screen with the battle's text box: no UI of a battle - a catch's Pokedex page,
        -- an evolution - the bar across its picture)
        if not (hd.cur and hd.cur.hasUI) then hd.cardUi() end
        if hd.paint(Bar.paint, args[name][mode], 112, Bar.TOP) then
          barPass = hd.cur and hd.cur.serial
          -- (the frame it was drawn and its top row: exports.barTop)
          hd.barDrawn, hd.barRow = hd.frames or 0, Bar.TOP
          -- (a whole screen's only text in the bar is its message, which opens its own window:
          -- what it draws after the panel - a catch's YES / NO - stays where it is)
          if hd.cur and hd.cur.hasUI then windowOpen = hd.bar(specs[name][mode]) else windowOpen = false end
          return
        end
      end
      return drawPanel(mode, ...)
    end
    ours[Chrome.drawPanel] = true
  end
  local drawMenuFrames = Chrome.drawMenuFrames
  if type(drawMenuFrames) == "function" and not ours[drawMenuFrames] then
    Chrome.drawMenuFrames = function(...)
      if inBarPass(hd.cur) then return end
      return drawMenuFrames(...)
    end
    ours[Chrome.drawMenuFrames] = true
  end
  local voiceoverDim = Ui.voiceoverDim
  if type(voiceoverDim) == "function" and not ours[voiceoverDim] then
    Ui.voiceoverDim = function(...)
      if windowOpen then
        windowOpen = false
        hd.bar(nil)
      end
      return voiceoverDim(...)
    end
    ours[Ui.voiceoverDim] = true
  end
  -- Ruby / Sapphire's red menu cursor hugs its text's left edge: in the bar, widened 2 px left
  local okR, RsCursor = pcall(require, "src.ui.game3.rs.menu_cursor")
  if okR and type(RsCursor) == "table" and type(RsCursor.draw) == "function" and not ours[RsCursor.draw] then
    local cursorDraw = RsCursor.draw
    RsCursor.draw = function(x, y, width, ...)
      if windowOpen and type(x) == "number" and type(width) == "number" then
        return cursorDraw(x - Bar.CURSOR_PAD, y, width + Bar.CURSOR_PAD, ...)
      end
      return cursorDraw(x, y, width, ...)
    end
    ours[RsCursor.draw] = true
  end
  if okM and type(Message) == "table" and type(Message.draw) == "function" and not ours[Message.draw] then
    local draw = Message.draw
    local function closed(...)
      hd.bar(nil)
      return ...
    end
    Message.draw = function(...)
      -- a battle hiding its bottom UI (Kanto Gear's GEAR screens show its text instead): its
      -- message is not drawn either (Oak's voiceover is not the battle's)
      if Message._frame ~= "voiceover" and (Message._frame == "battle" or hd.capturing("battle"))
          and not shown() and not panelScreen() then
        return
      end
      local cur = hd.cur
      if inBarPass(cur) then
        local name = layoutName()
        if name and specs[name] and hd.bar(specs[name].none) then return closed(draw(...)) end
      end
      return draw(...)
    end
    ours[Message.draw] = true
  end

  -- each battle frame: the trainer pinned to the bar's top and the fit seeing the text box
  -- there, while the bar is drawn (else the cart's line)
  Gen3.barFrame = function()
    if windowOpen then windowOpen = false end
    local on = wanted() and shown()
    local line = on and Bar.TOP or 112
    BACK_SPEC.pinBottom = line
    local text = hd.fit.ui and hd.fit.ui.text
    if text and hd.layout == "gen3" then text[2] = line end
  end
  return true
end

return Gen3
