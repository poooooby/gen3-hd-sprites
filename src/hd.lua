-- The capture / composite core of gen3-hd-sprites. Engine-agnostic: it is given the
-- graphics table (love.graphics) to wrap and the Renderer to composite through, so it
-- can be tested with fakes.
--
-- How it works. A "pass" draws a frame into one canvas that the Renderer later blits to
-- the window, scaled up by a whole number: the battle into the 240x160 UI canvas, the
-- field into the world canvas. While a pass runs:
--   * a draw of a TAGGED image on that canvas is not drawn. It is recorded (the drawn
--     quad, its draw arguments, the graphics transform, colour, shader and blend mode),
--     and everything drawn after it goes to a fresh transparent "layer" canvas of the same
--     size. Tagged draws with nothing drawn between them share one split.
--   * setCanvas / pop that would return to the pass's canvas (or an older layer) go to
--     the current layer instead, so engine code that switches canvases keeps its order.
-- When the Renderer blits the pass canvas (Renderer:blitCanvas), the blit is replaced by:
-- the base canvas, then each recorded draw at WINDOW resolution, then the next layer, and
-- so on, each blit made with the Renderer's own arguments. So the engine's z order is kept
-- exactly, and a tagged sprite is drawn with the window's pixels instead of the canvas's.
-- When a pass cannot be composited (the canvas is swapped out, the blit never comes), it
-- is "flattened" back into the base canvas the low-res way, so nothing is ever lost.

local HD = {}

local PRIMITIVES = { "rectangle", "polygon", "line", "circle", "ellipse", "arc", "points",
                     "print", "printf", "drawInstanced", "drawLayer" }

local function isQuad(v)
  return type(v) == "userdata" or (type(v) == "table" and type(v.getViewport) == "function")
end

--- G: the graphics table to wrap (love.graphics). opts.log: optional logger.
function HD.new(G, opts)
  opts = opts or {}
  local self = {
    G = G,
    log = opts.log,
    tags = setmetatable({}, { __mode = "k" }),
    enabled = { battle = true, field = true },
    -- most splits (window-sized layers) a pass may use; a tagged draw past it is drawn low-res
    caps = { battle = 8, field = 12 },
    cur = nil,          -- the pass being captured
    done = {},          -- finished passes waiting for their blit, by base canvas
    pool = {},          -- layer canvases by "w x h" -> list
    stats = { splits = 0, composites = 0, flattened = 0, overCap = 0 },
  }
  local real = {}
  self.real = real

  -- ------------------------------------------------------------------ tags

  --- Tag an image: draws of it inside a pass are drawn at window resolution.
  --- spec: { texture = img|nil, quad = q|nil, pivot = {x, y}|nil, lowPivot = {x, y}|nil,
  ---         scale = k (default 1), anchor = "feet"|nil, filter = "nearest"|"linear"|nil,
  ---         quadPivots = { [quad] = {x, y, scale?} }|nil }  (read at draw time, so it can grow)
  function self.tag(image, spec)
    if image == nil then return end
    spec = spec or {}
    local f = spec.filter or "nearest"
    local tex = spec.texture or image
    if tex.setFilter and f then pcall(tex.setFilter, tex, f, f) end
    self.tags[image] = spec
  end

  function self.untag(image)
    if image ~= nil then self.tags[image] = nil end
  end

  function self.tagOf(image)
    return self.tags[image]
  end

  -- --------------------------------------------------------------- capture

  local function getLayer(w, h, index)
    local key = w .. "x" .. h
    local list = self.pool[key]
    if not list then
      list = {}
      self.pool[key] = list
    end
    local c = list[index]
    if not c then
      c = real.newCanvas(w, h, { dpiscale = 1 })
      if c.setFilter then c:setFilter("nearest", "nearest") end
      list[index] = c
    end
    return c
  end

  local function isPassCanvas(c)
    local cur = self.cur
    return cur ~= nil and c ~= nil and (c == cur.base or cur.layerSet[c] == true)
  end

  -- a non-tagged draw is about to happen on the pass: open the layer a tagged draw left pending
  local function openPending()
    local cur = self.cur
    if not (cur and cur.pending) then return end
    cur.pending = false
    cur.layerCount = cur.layerCount + 1
    local layer = getLayer(cur.w, cur.h, cur.layerCount)
    cur.layerSet[layer] = true
    cur.current = layer
    cur.items[#cur.items + 1] = { kind = "layer", canvas = layer }
    real.setCanvas(layer)
    real.push("all")
    real.origin()
    real.setScissor()
    real.setShader()
    real.setBlendMode("alpha", "alphamultiply")
    real.clear(0, 0, 0, 0)
    real.pop()
  end

  local function onPass()
    return self.cur ~= nil and isPassCanvas(real.getCanvas())
  end

  local function record(image, spec, a, b, c, d, e, f, g, h, i)
    local quad, x, y, r, sx, sy, ox, oy
    if isQuad(a) then
      quad, x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g, h
    else
      x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g
    end
    if type(x) ~= "number" then return nil end
    local t0x, t0y = real.transformPoint(0, 0)
    local t1x = real.transformPoint(1, 0)
    local _, t2y = real.transformPoint(0, 1)
    local cr, cg, cb, ca = real.getColor()
    local bm, am = real.getBlendMode()
    return {
      spec = spec, image = image, quad = quad,
      x = x, y = y or 0, r = r or 0, sx = sx or 1, sy = sy or (sx or 1), ox = ox or 0, oy = oy or 0,
      tx = t0x, ty = t0y, tsx = t1x - t0x, tsy = t2y - t0y,
      color = { cr, cg, cb, ca }, shader = real.getShader(), blend = { bm, am },
    }
  end

  local function wrappedDraw(image, ...)
    local cur = self.cur
    if cur and onPass() then
      local spec = self.tags[image]
      if spec and cur.splits < cur.cap then
        local rec = record(image, spec, ...)
        if rec then
          -- tagged draws with nothing drawn between them share one split
          if not cur.pending then cur.splits = cur.splits + 1 end
          cur.items[#cur.items + 1] = { kind = "hd", rec = rec }
          cur.pending = true
          self.stats.splits = self.stats.splits + 1
          return
        end
      elseif spec then
        self.stats.overCap = self.stats.overCap + 1
      end
      openPending()
    end
    return real.draw(image, ...)
  end

  local function wrapPrimitive(name)
    return function(...)
      if self.cur and onPass() then openPending() end
      return real[name](...)
    end
  end

  local function redirectArg(arg)
    local cur = self.cur
    if not cur then return arg end
    if isPassCanvas(arg) then return cur.current end
    if type(arg) == "table" and isPassCanvas(arg[1]) then
      local copy = {}
      for k, v in pairs(arg) do copy[k] = v end
      copy[1] = cur.current
      return copy
    end
    return arg
  end

  local function wrappedSetCanvas(arg, ...)
    if self.cur then arg = redirectArg(arg) end
    return real.setCanvas(arg, ...)
  end

  local function wrappedPop(...)
    local res = { real.pop(...) }
    local cur = self.cur
    if cur then
      local c = real.getCanvas()
      if isPassCanvas(c) and c ~= cur.current then real.setCanvas(cur.current) end
    end
    return unpack(res)
  end

  --- Wrap the graphics functions (once). Returns false when something needed is missing.
  function self.install()
    if self.installed then return true end
    for _, name in ipairs({ "draw", "setCanvas", "getCanvas", "pop", "push", "origin", "clear",
                            "transformPoint", "getColor", "setColor", "getShader", "setShader",
                            "getBlendMode", "setBlendMode", "setScissor", "newCanvas", "translate",
                            "scale" }) do
      if type(G[name]) ~= "function" then return false, name end
      real[name] = G[name]
    end
    for _, name in ipairs(PRIMITIVES) do
      if type(G[name]) == "function" then real[name] = G[name] end
    end
    G.draw = wrappedDraw
    G.setCanvas = wrappedSetCanvas
    G.pop = wrappedPop
    for _, name in ipairs(PRIMITIVES) do
      if real[name] then G[name] = wrapPrimitive(name) end
    end
    self.installed = true
    return true
  end

  --- Restore the graphics functions.
  function self.uninstall()
    if not self.installed then return end
    for name, fn in pairs(real) do G[name] = fn end
    self.installed = false
  end

  --- Start capturing a pass on `base` (the canvas currently drawn into).
  function self.beginPass(pass, base)
    -- a pass that was never ended (its frame was not presented the usual way): put it back
    if self.cur then self.flatten(self.cur) end
    if not (self.installed and self.enabled[pass] and base and base.getWidth) then return false end
    self.cur = {
      pass = pass, base = base, current = base, layerSet = {}, items = {},
      w = base:getWidth(), h = base:getHeight(), layerCount = 0, splits = 0,
      cap = self.caps[pass] or 8, pending = false,
    }
    return true
  end

  --- Stop capturing. The pass waits for its canvas's blit (or flatten).
  function self.endPass()
    local cur = self.cur
    if not cur then return nil end
    self.cur = nil
    -- leave the drawing target where the engine expects it
    local c = real.getCanvas()
    if c ~= nil and (c == cur.base or cur.layerSet[c]) and c ~= cur.base then real.setCanvas(cur.base) end
    if #cur.items > 0 then self.done[cur.base] = cur end
    return cur
  end

  function self.capturing(pass)
    return self.cur ~= nil and (pass == nil or self.cur.pass == pass)
  end

  -- ------------------------------------------------------------- composite

  local function hdDraw(rec, bx, by, bsx, bsy)
    local spec = rec.spec
    local tex = spec.texture or rec.image
    local quad = spec.texture and spec.quad or rec.quad
    -- a quad of its own may stand on another point (a sprite drawn cut short) and
    -- carry its own size (a slice already drawn at its final size: 1)
    local qp = spec.quadPivots and rec.quad and spec.quadPivots[rec.quad]
    -- the low-res point that the HD pivot stands on, and the pivot in the HD texture
    local lpx, lpy, hpx, hpy
    if spec.anchor == "feet" and rec.quad and not qp then
      local _, _, qw, qh = rec.quad:getViewport()
      lpx, lpy = qw / 2, qh
      hpx, hpy = lpx, lpy
    else
      local lp = qp or spec.lowPivot or { 32, 32 }
      local hp = (not qp and spec.pivot) or lp
      lpx, lpy, hpx, hpy = lp[1], lp[2], hp[1], hp[2]
    end
    local k = (qp and qp[3]) or spec.scale or 1
    -- where the low-res draw put that point, in the pass canvas's pixels
    local dx, dy = (lpx - rec.ox) * rec.sx, (lpy - rec.oy) * rec.sy
    local cs, sn = math.cos(rec.r), math.sin(rec.r)
    local px = rec.x + dx * cs - dy * sn
    local py = rec.y + dx * sn + dy * cs
    local X = rec.tx + px * rec.tsx
    local Y = rec.ty + py * rec.tsy
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    real.setShader(rec.shader)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    local SX, SY = bx + X * bsx, by + Y * bsy
    local ssx, ssy = rec.sx * k * rec.tsx * bsx, rec.sy * k * rec.tsy * bsy
    if quad then
      real.draw(tex, quad, SX, SY, rec.r, ssx, ssy, hpx, hpy)
    else
      real.draw(tex, SX, SY, rec.r, ssx, ssy, hpx, hpy)
    end
  end

  --- Replace a blit of a captured canvas. `blit(canvas)` performs the Renderer's own blit
  --- of a canvas with the same arguments; bx/by/bsx/bsy map canvas pixels to the screen;
  --- box = {x, y, w, h} clip (or nil). Returns true when the blit was handled.
  function self.composite(canvas, blit, bx, by, bsx, bsy, box)
    local cur = self.done[canvas]
    if not cur then return false end
    blit(cur.base)
    real.push("all")
    for _, item in ipairs(cur.items) do
      if item.kind == "hd" then
        if box then real.setScissor(box[1], box[2], box[3], box[4]) else real.setScissor() end
        hdDraw(item.rec, bx, by, bsx, bsy)
      else
        real.setScissor()
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "premultiplied")
        blit(item.canvas)
        real.setBlendMode("alpha", "alphamultiply")
      end
    end
    real.pop()
    self.stats.composites = self.stats.composites + 1
    return true
  end

  --- Put a captured pass back into its base canvas the low-res way (it cannot be
  --- composited): each tagged draw as it was asked for, then each layer.
  function self.flatten(cur)
    cur = cur or self.cur
    if not cur then return end
    local midPass = self.cur == cur
    if midPass then self.cur = nil end
    if #cur.items == 0 then
      if midPass then real.setCanvas(cur.base) end
      return
    end
    self.done[cur.base] = nil
    real.push("all")
    real.setCanvas(cur.base)
    real.origin()
    real.setScissor()
    for _, item in ipairs(cur.items) do
      if item.kind == "hd" then
        local rec = item.rec
        real.push()
        real.translate(rec.tx, rec.ty)
        real.scale(rec.tsx, rec.tsy)
        real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
        real.setShader(rec.shader)
        real.setBlendMode(rec.blend[1], rec.blend[2])
        if rec.quad then
          real.draw(rec.image, rec.quad, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
        else
          real.draw(rec.image, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
        end
        real.pop()
      else
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "premultiplied")
        real.draw(item.canvas, 0, 0)
        real.setBlendMode("alpha", "alphamultiply")
      end
    end
    real.pop()
    -- flattened in the middle of a pass: the engine carries on drawing into its own canvas
    if midPass then real.setCanvas(cur.base) end
    self.stats.flattened = self.stats.flattened + 1
  end

  --- The frame is over: anything still waiting for a blit that never came is dropped
  --- (it was flattened when that could be known in time).
  function self.endFrame()
    self.done = {}
  end

  return self
end

return HD
