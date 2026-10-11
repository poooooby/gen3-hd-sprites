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
      elseif hd.beginPass("dex", love.graphics.getCanvas()) then
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
    Chrome.drawTerrain = function(key, enemyOx, playerOx, bgOx, ...)
      if fitting() then
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
      return drawTerrain(key, enemyOx, playerOx, bgOx, ...)
    end
    ours[Chrome.drawTerrain] = true
  end

  local ballDraw = BallOpen.draw
  if not ours[ballDraw] then
    BallOpen.draw = function(...)
      local results = { ballDraw(...) }
      if fitting() then hd.seam("ui") end
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
    local home = Engine.shiftHome or { player = S[0].x, enemy = S[1].x }
    Engine.shiftHome = home
    local function place(t, x)
      t.x = x
      t[1] = x
    end
    -- the intro's own copies of the battlers' spots (ball targets, the catch, a switch)
    local EM, PM = type(Anim.ENEMY_MON) == "table" and Anim.ENEMY_MON, type(Anim.PLAYER_MON) == "table" and Anim.PLAYER_MON
    home.enemyMon = home.enemyMon or (EM and EM.x)
    home.playerMon = home.playerMon or (PM and PM.x)
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
      place(S[1], home.enemy + e)
      place(S[0], home.player + p)
      if EM and home.enemyMon then EM.x = home.enemyMon + e end
      if PM and home.playerMon then PM.x = home.playerMon + p end
      Engine.shiftNow = { enemy = e, player = p }
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
          local d = Engine.shiftNow and Engine.shiftNow.player or 0
          if type(x) == "number" then x = x + d end
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
            hd.tag(entry.image, spec)
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

    local okG, missing = hd.install()
    if not okG then error("love.graphics has no " .. tostring(missing), 0) end

    if not ours[blitCanvas] then
      Renderer.blitCanvas = function(self, canvas, sx, sy, zoneList, zsx, zsy, bx, by,
                                     boxX, boxY, boxW, boxH, dpiX, dpiY)
        if hd.done[canvas] then
          -- the Renderer's own blit; Battle Fit's zoomed scene passes its own origin and scale
          local function blit(c, obx, oby, osx, osy)
            return blitCanvas(self, c, osx or sx, osy or sy, zoneList, zsx, zsy, obx or bx, oby or by,
                              boxX, boxY, boxW, boxH, dpiX, dpiY)
          end
          local box = boxX and { boxX, boxY, boxW, boxH } or nil
          if hd.composite(canvas, blit, bx, by, sx, sy, box) then return end
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
        if not busy then hd.beginPass("field", self.worldCanvas) end
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
        hd.beginPass("battle", love.graphics.getCanvas())
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
