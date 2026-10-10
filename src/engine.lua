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
          local function blit(c)
            return blitCanvas(self, c, sx, sy, zoneList, zsx, zsy, bx, by,
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
        hd.beginPass("battle", love.graphics.getCanvas())
        return battleDraw(...)
      end
      ours[Battle.draw] = true
    end
    Engine.wrapDex(hd)
  end)
  if not ok then return false, err end
  return true
end

return Engine
