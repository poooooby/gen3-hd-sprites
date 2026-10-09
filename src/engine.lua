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
        if hd.capturing("battle") then hd.endPass() end
        for base, cur in pairs(hd.done) do
          local willBlit = base == self.canvas
            or (base == self.worldCanvas and self.worldActive and not self.worldOverride
                and not self.uprightActive)
          if not willBlit then hd.flatten(cur) end
        end
        local results = { endFrame(self, ...) }
        hd.endFrame()
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
  end)
  if not ok then return false, err end
  return true
end

return Engine
