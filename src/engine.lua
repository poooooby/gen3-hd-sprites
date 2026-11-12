-- The engine seams gen3-hd-sprites uses (all checked before anything is wrapped). These are
-- the Renderer's, shared by every generation that draws through it; a generation's own seams
-- (its battle, its Pokedex, its screens) are wrapped by its adapter (src/gen3.lua, src/gen1.lua),
-- picked by the game's generation:
--
--   Renderer:blitCanvas    every canvas blit to the window goes through it: a captured
--                          canvas is composited here (src/hd.lua composite)
--   Renderer:endFrame      the battle pass ends here; a pass whose canvas this frame will
--                          not blit is flattened back first, then the frame's leftovers cleared
--   Renderer:beginFrame    a frame of a whole screen over the field is a "screen" pass, filling
--                          the screen (the adapter's Engine.fullScreen says which)
--   Renderer:beginWorldPass / endWorldPass   the field pass (the world canvas)
--   Renderer:exchangeWorldCanvas             a field compositor (RSE weather) that reads the
--                          world canvas: the field pass is flattened before it, so it reads
--                          everything, and that frame's field is drawn the usual way
--
-- Field capture is skipped in tilt mode and while the adapter's Engine.fieldBusy says so (a
-- battle transition), which draw the field through canvases of their own.

local Engine = {}

local function need(t, name)
  if type(t) ~= "table" or type(t[name]) ~= "function" then
    error(("the engine has no %s"):format(name), 0)
  end
  return t[name]
end
Engine.need = need

-- our own wrappers, so a reload does not wrap them twice
local ours = setmetatable({}, { __mode = "k" })
Engine.ours = ours

-- the generations' adapters, by generation (main.lua fills it: src/gen3.lua, src/gen1.lua)
Engine.adapters = {}

local dexMissing = {}       -- module names that could not be required (not asked again)

--- Wrap the draw of every Pokedex screen not wrapped yet (the adapter's Engine.dexModules, by
--- module name). Called at install and each frame from the endFrame wrapper (require is cached,
--- so that is cheap), in case a screen's module replaces its draw. Through require: a mod's
--- `package.loaded` is not the engine's. Both the module's draw and its stack Host's draw are
--- wrapped: national_dex_gen3 swaps in a patched copy of the RSE screen whose Host.draw calls
--- the copy's own draw, not the module's.
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
  for _, name in ipairs(Engine.dexModules or {}) do
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

--- The game's generation (1, 2 or 3), from the engine's GameVersion.
function Engine.generation()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and type(GameVersion) == "table" and type(GameVersion.generation) == "function" then
    local okG, g = pcall(GameVersion.generation)
    if okG and type(g) == "number" then return g end
  end
  return 1
end

function Engine.install(hd)
  local ok, err = pcall(function()
    local gen = Engine.generation()
    local adapter = Engine.adapters[gen]
    if type(adapter) ~= "table" or type(adapter.prepare) ~= "function" then
      error(("generation %d is not supported"):format(gen), 0)
    end
    local Renderer = require("src.render.Renderer")
    local Tilt = package.loaded["src.render.Tilt"] or require("src.render.Tilt")
    local G = love and love.graphics
    need(G, "transformPoint")
    local blitCanvas = need(Renderer, "blitCanvas")
    local endFrame = need(Renderer, "endFrame")
    local beginFrame = need(Renderer, "beginFrame")
    local beginWorldPass = need(Renderer, "beginWorldPass")
    local endWorldPass = need(Renderer, "endWorldPass")
    local exchange = need(Renderer, "exchangeWorldCanvas")
    -- the generation's own seams, checked (raises when one is missing); wrapped below
    local wrapGeneration = adapter.prepare(Engine, hd)

    local okG, missing = hd.install()
    if not okG then error("love.graphics has no " .. tostring(missing), 0) end

    if not ours[blitCanvas] then
      Renderer.blitCanvas = function(self, canvas, sx, sy, zoneList, zsx, zsy, bx, by,
                                     boxX, boxY, boxW, boxH, dpiX, dpiY)
        if hd.done[canvas] then
          -- a field under a weather's colour map (hd.colorMapStart): composited into a canvas the
          -- size of its place on the screen, at its corner (ox, oy: that place), then drawn
          -- through the colour map, then what the weather drew over it
          local cm = hd.done[canvas].cm
          if not (cm and cm.shader) then cm = nil end
          local ox, oy, mapped, out = 0, 0, nil, nil
          if cm then
            local cw, ch = hd.done[canvas].w, hd.done[canvas].h
            ox, oy = bx, by
            mapped, out = hd.mapTargets(math.max(1, math.ceil(cw * sx)), math.max(1, math.ceil(ch * sy)))
            love.graphics.push("all")
            love.graphics.setCanvas(mapped)
            love.graphics.origin()
            love.graphics.setScissor()
            love.graphics.clear(0, 0, 0, 0)
          end
          -- the Renderer's own blit; Battle Fit's zoomed scene passes its own origin and scale
          -- (a zone list's scales follow the blit's, so an SGB zone stays on its pixels; zk:
          -- the canvas's pixels per game pixel, for the UI drawn larger to scale it sharply)
          local function blit(c, obx, oby, osx, osy, obox, zk)
            local kx, ky = (osx or sx) / sx * (zk or 1), (osy or sy) / sy * (zk or 1)
            local b = obox or { boxX, boxY, boxW, boxH }
            local b1, b2 = b[1], b[2]
            if not obox and b1 then b1, b2 = b1 - ox, b2 - oy end
            return blitCanvas(self, c, osx or sx, osy or sy, zoneList, zsx and zsx * kx, zsy and zsy * ky,
                              (obx or bx) - (obx and 0 or ox), (oby or by) - (oby and 0 or oy),
                              b1, b2, b[3], b[4], dpiX, dpiY)
          end
          local box = boxX and { boxX - ox, boxY - oy, boxW, boxH } or nil
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
          local ok, handled = pcall(hd.composite, canvas, blit, bx - ox, by - oy, sx, sy, box, view)
          if cm then
            love.graphics.pop()
            if ok and handled then
              hd.drawMapped(cm, mapped, out)
              local bm, am = love.graphics.getBlendMode()
              love.graphics.setScissor(boxX, boxY, boxW, boxH)
              love.graphics.setBlendMode("alpha", "premultiplied")
              love.graphics.draw(out, bx, by)
              love.graphics.setScissor()
              -- (rain, a flash: drawn over the colour map, untinted)
              blitCanvas(self, canvas, sx, sy, zoneList, zsx, zsy, bx, by, boxX, boxY, boxW, boxH, dpiX, dpiY)
              love.graphics.setBlendMode(bm, am)
              return
            end
          end
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
        if hd.capturing() and not hd.capturing("field") then hd.endPass() end
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

    -- a frame of a whole screen over the field (the Pokedex, the party, the bag, the options, the
    -- mods: Gen 3's screen stack's fullscreen layers, which the display draws with no field behind
    -- them) is a screen pass: with Fill Screen it fills the screen as one picture. Not a frame
    -- the screens before the game starts present (Engine.presentingUi: those are boot passes).
    if not ours[beginFrame] then
      Renderer.beginFrame = function(self, transparent, ...)
        -- (the Renderer's beginFrame returns nothing: no results table each frame)
        beginFrame(self, transparent, ...)
        if not transparent and not Engine.presentingUi and hd.enabled.screen and Engine.fullScreen then
          local okS, full = pcall(Engine.fullScreen)
          if okS and full then
            hd.stats.screenPasses = (hd.stats.screenPasses or 0) + 1
            local okP, errP = pcall(hd.beginPass, "screen", love.graphics.getCanvas())
            if not okP then hd.fail("screen pass: " .. tostring(errP)) end
          end
        end
      end
      ours[Renderer.beginFrame] = true
    end

    if not ours[beginWorldPass] then
      Renderer.beginWorldPass = function(self, ...)
        local results = { beginWorldPass(self, ...) }
        local busy = (Tilt.active and Tilt.active()) or (Engine.fieldBusy and Engine.fieldBusy())
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
        -- a weather's colour map over the field: the pass goes on (its composite is mapped),
        -- unless the swap does not happen
        if hd.capturing("field") then
          local cur = hd.cur
          local done = exchange(self, current, replacement, ...)
          if done and current == cur.base and hd.colorMapStart(replacement) then return done end
          hd.flatten(cur)
          return done
        end
        return exchange(self, current, replacement, ...)
      end
      ours[Renderer.exchangeWorldCanvas] = true
    end

    wrapGeneration()
    Engine.wrapDex(hd)
  end)
  if not ok then return false, err end
  return true
end

return Engine
