-- The engine seams gen3-hd-sprites uses (all checked before anything is wrapped):
--
--   Renderer:blitCanvas    every canvas blit to the window goes through it: a captured
--                          canvas is composited here (src/hd.lua composite)
--   Renderer:endFrame      the battle pass ends here; a pass whose canvas this frame will
--                          not blit is flattened back first, then the frame's leftovers cleared
--   Renderer:beginWorldPass / endWorldPass   the field pass (the world canvas)
--   Renderer:exchangeWorldCanvas             a field compositor (RSE weather) that reads the
--                          world canvas: the field pass is flattened before it, so it reads
--                          everything, and that frame's field is drawn the usual way
--   Battle.draw            the battle pass starts here (src/core/game3/battle/init.lua)
--   Pokedex.draw           the Pokedex pass starts here: Ruby/Sapphire/Emerald's
--                          (src/ui/game3/rse/pokedex.lua) and FireRed/LeafGreen's
--                          (src/ui/game3/pokedex.lua), wrapped once each is loaded; like the
--                          battle pass it ends at Renderer:endFrame. Inside a battle (a caught
--                          Pokemon's entry) the battle pass is already capturing it.
--
-- Field capture is skipped in tilt mode and during a battle transition, which draw the
-- field through canvases of their own.
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

local Engine = {}

local function need(t, name)
  if type(t) ~= "table" or type(t[name]) ~= "function" then
    error(("the engine has no %s"):format(name), 0)
  end
  return t[name]
end

-- our own wrappers, so a reload does not wrap them twice
local ours = setmetatable({}, { __mode = "k" })

-- the Pokedex screens, by module name; each is wrapped when it is first seen loaded
local DEX_MODULES = { "src.ui.game3.rse.pokedex", "src.ui.game3.pokedex" }

local dexMissing = {}       -- module names that could not be required (not asked again)

--- Wrap the draw of every Pokedex screen not wrapped yet. Called at install and each frame
--- from the endFrame wrapper (require is cached, so that is cheap), in case a screen's module
--- replaces its draw. Through require: a mod's `package.loaded` is not the engine's.
--- Both the module's draw and its stack Host's draw are wrapped: national_dex_gen3 swaps in a
--- patched copy of the RSE screen whose Host.draw calls the copy's own draw, not the module's.
function Engine.wrapDex(hd)
  local function wrap(t)
    local draw = type(t) == "table" and t.draw
    if type(draw) ~= "function" or ours[draw] then return end
    t.draw = function(...)
      if hd.capturing() then
        hd.stats.dexInPass = (hd.stats.dexInPass or 0) + 1
      elseif select(2, pcall(hd.beginPass, "dex", love.graphics.getCanvas())) == true then
        hd.stats.dexPasses = (hd.stats.dexPasses or 0) + 1
      end
      return draw(...)
    end
    ours[t.draw] = true
  end
  for _, name in ipairs(DEX_MODULES) do
    local M
    if not dexMissing[name] then
      local ok, m = pcall(require, name)
      if ok then M = m else dexMissing[name] = true end
    end
    if type(M) == "table" then
      wrap(M)
      wrap(M.Host)
    end
  end
end

--- Wrap the Battle Fit seams. Returns true when both are in place.
function Engine.wrapFit(hd)
  local okC, Chrome = pcall(require, "src.ui.game3.battle_chrome")
  local okB, BallOpen = pcall(require, "src.core.game3.battle.ball_open")
  if not (okC and type(Chrome) == "table" and type(Chrome.drawTerrain) == "function"
          and type(Chrome.terrain) == "function"
          and okB and type(BallOpen) == "table" and type(BallOpen.draw) == "function") then
    return false
  end
  local function fitting() return hd.fit.enabled and hd.capturing("battle") end

  local drawTerrain = Chrome.drawTerrain
  if not ours[drawTerrain] then
    local function fitTerrain(key, enemyOx, playerOx, bgOx)
      key = key or "building"
      local entry = Chrome.terrain(key) or Chrome.terrain("building") or Chrome.terrain("grass")
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

  -- the intro's scrolling grass (a background layer that wraps on the cart): drawn as a band
  -- across the whole zoomed-out view instead of one screen-wide image
  local drawEntry = Chrome.drawEntry
  if type(drawEntry) == "function" and type(Chrome.entry) == "function" and not ours[drawEntry] then
    Chrome.drawEntry = function(key, scrollX, scrollY, alpha, ...)
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
    BallOpen.draw = function(...)
      local results = { ballDraw(...) }
      if fitting() then
        local ok, err = pcall(hd.seam, "ui")
        if not ok then hd.fail("seam: " .. tostring(err)) end
      end
      return unpack(results)
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
      Anim.drawParticles = function(...)
        -- (hd.beginPass clears it too, should a draw here ever throw)
        hd.inAnim = true
        local results = { drawParticles(...) }
        hd.inAnim = false
        return unpack(results)
      end
      ours[Anim.drawParticles] = true
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
    home.enemyMon = home.enemyMon or (EM and EM.x)
    home.playerMon = home.playerMon or (PM and PM.x)
    home.playerMonY = home.playerMonY or (PM and PM.y)
    local function on(Battle)
      local st = Battle._st
      return hd.fit.enabled and st ~= nil and not st.double
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
      place(S[1], home.enemy + e)
      place(S[0], home.player + p)
      if home.playerY then S[0].y, S[0][2] = home.playerY + pm, home.playerY + pm end
      if EM and home.enemyMon then EM.x = home.enemyMon + e end
      if PM and home.playerMon then PM.x = home.playerMon + p end
      if PM and home.playerMonY then PM.y = home.playerMonY + pm end
      Engine.shiftNow = { enemy = e, player = p, playerY = py }
    end

    --- Both leads, before they are sent out: their pics as the battle will draw them (asked for
    --- inside the battle's draw, so a sprite mod hands over its battle pics), centred where
    --- the battle will put them, so the camera is framed for them from the first frame.
    local okPk, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okUi, Ui = pcall(require, "src.core.game3.battle.ui")
    -- through require: a mod's package.loaded is not the engine's
    local okB2, BattleMod = pcall(require, "src.core.game3.battle")
    if not okB2 then BattleMod = nil end
    if okPk and okUi and type(Pokemon) == "table" and type(Ui) == "table"
        and type(Ui.battlerSpriteCenter) == "function" and type(Ui.picArgs) == "function" then
      local spots = {
        enemy = { x = home.enemyMon or 176, y = EM and EM.y or 40 },
        player = { x = home.playerMon or 72, y = PM and PM.y or 80 },
      }
      Engine.prefit = function()
        local B = BattleMod
        local st = B and B._st
        if not st or st.double then return end
        for side, spot in pairs(spots) do
          local battler = st[side]
          local mon = battler and battler.mon
          local sp = mon and Pokemon.speciesOf and Pokemon.speciesOf(mon)
          if sp then
            local picSp, shiny, personality = Ui.picArgs(battler, sp)
            local entry
            if side == "enemy" then
              entry = Pokemon.frontPic and Pokemon.frontPic(picSp, nil, shiny, personality)
            else
              entry = Pokemon.backPic and Pokemon.backPic(picSp, nil, shiny)
            end
            if entry and entry.image then
              local cx, cy = Ui.battlerSpriteCenter(side, sp, { x = spot.x, y = spot.y }, nil, false)
              hd.prefit(side, entry.image, cx, cy)
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
      tagging("back", { side = "player", trainer = true, pinBottom = 112 })
    end
  end
  return true
end

-- The rows of a full-window view (no cutout) the battle may use: from below the safe
-- area's top (a notch) down to above the on-screen touch controls when they overlay a tall
-- screen. Either may be nil (use the view's edge).
function Engine.usableRows(vy, vh, vw)
  local top, bottom
  local okS, SafeArea = pcall(require, "src.core.SafeArea")
  if okS and type(SafeArea) == "table" and SafeArea.rect then
    local ok, _, y = pcall(SafeArea.rect)
    if ok and type(y) == "number" and y > vy then top = y end
  end
  if vh > vw then
    local okT, TC = pcall(require, "src.core.TouchControls")
    if okT and type(TC) == "table" and TC.visible and TC.layout then
      local okV, shown = pcall(TC.visible, TC)
      local okL, L = false, nil
      if okV and shown then okL, L = pcall(TC.layout, TC) end
      if okL and type(L) == "table" then
        for name, z in pairs(L) do
          -- the hotbar button sits in a top corner, over the game: not part of the deck
          if name ~= "hotbar" and type(z) == "table" and z.cy and z.w then
            local zt = z.cy - (z.h or z.w) / 2
            if zt > vy + vh * 0.25 and (not bottom or zt < bottom) then bottom = zt end
          end
        end
      end
    end
  end
  return top, bottom
end

function Engine.install(hd)
  local ok, err = pcall(function()
    local Renderer = require("src.render.Renderer")
    local Battle = require("src.core.game3.battle")
    local Tilt = package.loaded["src.render.Tilt"] or require("src.render.Tilt")
    local G = love and love.graphics
    need(G, "transformPoint")
    local blitCanvas = need(Renderer, "blitCanvas")
    local endFrame = need(Renderer, "endFrame")
    local beginWorldPass = need(Renderer, "beginWorldPass")
    local endWorldPass = need(Renderer, "endWorldPass")
    local exchange = need(Renderer, "exchangeWorldCanvas")
    local battleDraw = need(Battle, "draw")

    -- the Gen 3 display falls back to presenting without the Renderer when anything in its
    -- plane path errors (Display.planesBroken, for the session): a pass could then never be
    -- composited, so nothing is captured and every frame is drawn the game's own way
    local okD, Display = pcall(require, "src.core.game3.display")
    hd.canCapture = function()
      return not (okD and type(Display) == "table" and Display.planesBroken)
    end

    local okG, missing = hd.install()
    if not okG then error("love.graphics has no " .. tostring(missing), 0) end

    if not ours[blitCanvas] then
      Renderer.blitCanvas = function(self, canvas, sx, sy, zoneList, zsx, zsy, bx, by,
                                     boxX, boxY, boxW, boxH, dpiX, dpiY)
        if hd.done[canvas] then
          -- the Renderer's own blit; Battle Fit's zoomed scene passes its own origin and scale
          -- (a zone list's scales follow the blit's, so an SGB zone stays on its pixels; zk:
          -- the canvas's pixels per game pixel, for the UI drawn larger to scale it sharply)
          local function blit(c, obx, oby, osx, osy, obox, zk)
            local kx, ky = (osx or sx) / sx * (zk or 1), (osy or sy) / sy * (zk or 1)
            local b = obox or { boxX, boxY, boxW, boxH }
            return blitCanvas(self, c, osx or sx, osy or sy, zoneList, zsx and zsx * kx, zsy and zsy * ky,
                              obx or bx, oby or by, b[1], b[2], b[3], b[4], dpiX, dpiY)
          end
          local box = boxX and { boxX, boxY, boxW, boxH } or nil
          -- the whole screen area (Battle Fit's fill): the Renderer's view rect (inside a
          -- cutout, a touch skin's or a layout mod's game area, that rectangle), with the rows
          -- the battle may use: below the notch, above on-screen touch controls
          local view
          if hd.fit.fill and canvas == self.canvas and self.frameRects then
            local okR, R = pcall(self.frameRects, self)
            if okR and type(R) == "table" and R.vuw then
              view = { R.vux, R.vuy, R.vuw, R.vuh }
              if not R.cut then view.top, view.bottom = Engine.usableRows(R.vuy, R.vuh, R.vuw) end
            end
          end
          local cur = hd.done[canvas]
          local ok, handled = pcall(hd.composite, canvas, blit, bx, by, sx, sy, box, view)
          if ok and handled then return end
          if not ok then
            -- put the frame back into its canvas the usual way, then blit that
            hd.fail("composite: " .. tostring(handled))
            pcall(hd.flatten, cur)
          end
        end
        return blitCanvas(self, canvas, sx, sy, zoneList, zsx, zsy, bx, by,
                          boxX, boxY, boxW, boxH, dpiX, dpiY)
      end
      ours[Renderer.blitCanvas] = true
    end

    if not ours[endFrame] then
      Renderer.endFrame = function(self, ...)
        if hd.capturing("battle") or hd.capturing("dex") then hd.endPass() end
        for base, cur in pairs(hd.done) do
          local willBlit = base == self.canvas
            or (base == self.worldCanvas and self.worldActive and not self.worldOverride
                and not self.uprightActive)
          if not willBlit then hd.flatten(cur) end
        end
        local results = { endFrame(self, ...) }
        hd.endFrame()
        Engine.wrapDex(hd)
        return unpack(results)
      end
      ours[Renderer.endFrame] = true
    end

    if not ours[beginWorldPass] then
      Renderer.beginWorldPass = function(self, ...)
        local results = { beginWorldPass(self, ...) }
        local BattleTransition = package.loaded["src.core.game3.battle_transition"]
        local busy = (Tilt.active and Tilt.active())
          or (BattleTransition and BattleTransition.isActive and BattleTransition.isActive())
        if not busy then
          local ok, err = pcall(hd.beginPass, "field", self.worldCanvas)
          if not ok then hd.fail("field pass: " .. tostring(err)) end
        end
        return unpack(results)
      end
      ours[Renderer.beginWorldPass] = true
    end

    if not ours[endWorldPass] then
      Renderer.endWorldPass = function(self, ...)
        if hd.capturing("field") then hd.endPass() end
        return endWorldPass(self, ...)
      end
      ours[Renderer.endWorldPass] = true
    end

    if not ours[exchange] then
      Renderer.exchangeWorldCanvas = function(self, current, replacement, ...)
        if hd.capturing("field") then hd.flatten(hd.cur) end
        return exchange(self, current, replacement, ...)
      end
      ours[Renderer.exchangeWorldCanvas] = true
    end

    if not ours[battleDraw] then
      Battle.draw = function(...)
        if Engine.shiftCoords then pcall(Engine.shiftCoords, Battle) end
        local ok, err = pcall(hd.beginPass, "battle", love.graphics.getCanvas())
        if not ok then hd.fail("battle pass: " .. tostring(err)) end
        return battleDraw(...)
      end
      ours[Battle.draw] = true
    end
    Engine.wrapDex(hd)
    local okFit, fitOk = pcall(Engine.wrapFit, hd)
    hd.fit.available = okFit and fitOk == true
  end)
  if not ok then return false, err end
  return true
end

return Engine
