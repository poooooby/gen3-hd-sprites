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
--
-- Battle Fit. A battle pass can be cut into a SCENE (the wallpaper, pads, Pokemon and move
-- effects) and the UI over it, by seam("ui") (the engine calls it after the last scene draw).
-- The wallpaper is recorded with backdrop() instead of drawn. At composite time the scene's
-- layers and sprites are zoomed out about `fit.focus` (the text box's top centre) just enough
-- that the tallest tagged sprite fits under the top of the screen. Past the point where that
-- would sink the enemy's feet line (`fit.feetY`) below `fit.feetMax` (into the player's HP
-- box), the camera also rises, keeping the feet on that line. The wallpaper zooms less
-- (parallax, drawn wrapped so no edge shows) and the UI is blitted as it always is. A draw
-- that covers the whole scene (a move's background, a flash) gets a layer of its own that is
-- not zoomed, so it still covers the view.
--
-- Shaders. A recorded draw is replayed later than it was asked for, and one shader is often
-- shared (both battlers' blend, a stat change's two passes), so what each shader is sent is
-- remembered (Shader:send is wrapped) and each draw replays with its own uniforms. A shader
-- that works in the drawn image's own pixels (PIXEL_SHADERS, told by its uniforms) has them
-- remapped for the HD texture, so its pattern or blocks keep the cart's pixel size.

local HD = {}

local PRIMITIVES = { "rectangle", "polygon", "line", "circle", "ellipse", "arc", "points",
                     "print", "printf", "drawInstanced", "drawLayer" }

-- Shaders in the drawn image's pixels, by the uniforms they are sent. remap(u, m) gets the
-- uniforms as sent (u[name][1]: the first value) and the HD draw's texture mapping m (its
-- texcoords in the low-res image's: tl = a + th * b, each axis; the HD texture's size; HD
-- texels per low-res pixel), and returns the uniforms to send instead ({ name = { values } }).
local PIXEL_SHADERS = {
  -- the stat-change pattern: pos = origin + tc * size (flip mirrors x), in the battle's pixels
  { uniforms = { "origin", "size", "flip", "maskTex" }, remap = function(u, m)
    local o, s, flip = u.origin[1], u.size[1], u.flip[1]
    if type(o) ~= "table" or type(s) ~= "table" or type(flip) ~= "number" then return nil end
    local ax, bx = m.ax, m.bx
    if flip > 0.5 then ax, bx = 1 - ax, -bx end
    return { origin = { { o[1] + ax * s[1], o[2] + m.ay * s[2] } },
             size = { { bx * s[1], m.by * s[2] } }, flip = { 0 } }
  end },
  -- mosaic: blocks of `block` texels of a `texSize` texture
  { uniforms = { "texSize", "block" }, remap = function(u, m)
    local b = u.block[1]
    if type(b) ~= "number" then return nil end
    return { texSize = { { m.w, m.h } }, block = { b * m.texels } }
  end },
}

local function sentAll(u, names)
  for _, name in ipairs(names) do if not u[name] then return false end end
  return true
end

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
    enabled = { battle = true, field = true, dex = true },
    -- most splits (window-sized layers) a pass may use; a tagged draw past it is drawn low-res
    caps = { battle = 8, field = 12, dex = 8 },
    cur = nil,          -- the pass being captured
    done = {},          -- finished passes waiting for their blit, by base canvas
    pool = {},          -- layer canvases by "w x h" -> list
    stats = { splits = 0, composites = 0, flattened = 0, overCap = 0, zoom = 1, zoomTarget = 1, lift = 0 },
    -- Battle Fit (see the header). z eases toward target: out fast, back in only after the
    -- target has stayed larger for holdFrames, so a sprite's animation never pumps it.
    fit = {
      -- zMin: the farthest it may pull back (40% fits the very biggest, Lugia and Koraidon)
      enabled = false, available = false, zMin = 0.4, focus = { 120, 112 }, margin = 2, parallax = 0.35,
      -- the enemy's feet (its 64x64 pic box's bottom, ui.lua ENEMY_MON y 40 + 32) and the
      -- lowest they may sink to: the top of the player's HP box is just below
      feetY = 72, feetMax = 76,
      -- fill: the battle's scene fills the screen (from its top down to the text box's line,
      -- out to its sides), its UI keeping its own whole-pixel scale, docked to the bottom
      fill = false, uiK = 1,
      -- stacked (a screen taller than the canvas's 3:2): the UI spans the screen's width, its
      -- rows above `split` (the enemy's HP box) moved up by uiTopDy UI px to the top of the
      -- screen, its rows below (the player's HP box, the text box, the menus) docked to the
      -- bottom. topY: the canvas y of the screen's top in the scene's pixels (0 when the
      -- scene reaches it; negative with sky above), the highest art may rise
      split = 66, uiTopDy = 0, topY = 0,
      -- ... and the scene grows (grow, eased like the zoom) into the space above it, up to the
      -- screen's top, its sides cropped: only as far as both sides' art (span, canvas x where
      -- it rests, zoomed; the platforms until seen) stays on the screen, cropMargin
      -- canvas px clear of its edges
      grow = nil, span = nil, spanDefault = { 0, 240 }, cropMargin = 4,
      -- ... and when the width stops it short of the top, the two sides slide toward each other
      -- (the enemy left, the player right) so it can grow further: a back whose top is below
      -- the enemy's feet may come under the enemy (centres at most aligned); one level with
      -- the enemy keeps sideGap canvas px clear of it. wantW: the art width (zoomed canvas px)
      -- the growth to the top needs, from the composite; nil when not stacked
      sideGap = 4, wantW = nil,
      -- ... a back level with the enemy may still slide in front of the enemy's platform, over
      -- up to overlapFoe of the enemy's frame width (its margin and feet, not its body)
      overlapFoe = 0.3,
      -- ... both platforms stay whole on the screen (their ovals across, canvas x where they
      -- rest: the enemy's centred on 176, the player's rebuilt 112 px left of it), and the
      -- slide is at most inwardMax canvas px in all, so neither side leaves its spot far
      pads = { enemy = { 112, 240 }, player = { 0, 128 } }, inwardMax = 48,
      -- ... and when the scene still stops short of the top, the enemy's HP box comes down to
      -- sit hugGap canvas px above the highest art (artTop: zoomed canvas y, from the fit)
      hugGap = 4, artTop = nil,
      -- ... and with nothing below to dock to (no touch controls), the whole block is raised
      -- (raise, screen px, settling from frame to frame) to sit centred: sky above, ground below
      raise = 0,
      -- the battle UI over the scene, in canvas pixels (singles, both cart layouts): the
      -- enemy's HP box, the player's HP box, the text box (and everything below it, off the
      -- screen too). The player's own Pokemon (a tag with side = "player" and its body box)
      -- keeps at most maxHiddenOwn of its body under its own side's UI when the camera can
      -- manage it, and at most maxHidden under the enemy's box when there is no headroom
      ui = { enemy = { 14, 16, 113, 44 }, player = { 134, 74, 236, 110 }, text = { -1e4, 112, 1e4, 1e4 } },
      maxHidden = 0.5, maxHiddenOwn = 0.3,
      -- headroom: the player's Pokemon's body top stays no higher than the tallest cart back
      -- sprite's (Tyranitar, Steelix, Meganium: row 0 of the 64x64 back box, centred at
      -- y = 80 + 4, so y = 52), 8 px below the enemy's HP box
      backTopMin = 52,
      -- the camera may rise this far past what the enemy's feet need, to lift the player's
      -- Pokemon out from under the text box; zooms are tried in steps of zStep
      extraMax = 48, zStep = 0.005,
      -- side shift: zoomed out, the two Pokemon and their pads crowd the middle. Each side is
      -- moved back toward where it stood unzoomed (the enemy's spot x 176, the player's 72):
      -- the tagged Pokemon and pads here, the move animations by the engine's battler
      -- coordinates (src/engine.lua). At most shiftMax canvas px, so an effect drawn there
      -- stays inside the canvas. It follows the zoom from a battle's first frame; the
      -- trainers (tags with trainer = true) move with their side too.
      enemyX = 176, playerX = 72, shiftMax = 40,
      -- the wallpaper's rows that are ground just above the text box's line, repeated below
      -- that line (image rows; the cart's rows past 112 are black)
      ground = { 104, 112 },
      shift = { enemy = 0, player = 0, playerY = 0, playerRaise = 0 },
      -- the player's pad stays tucked under the text box for scale: on the cart its top 11
      -- of 32 rows show (padTop 101, padRows 32); pulled back, the player's side is lowered
      -- (playerY) so that only padRows * (1 - padTuck) show at zMin, blending from the cart's
      -- 11 at zoom 1. Its Pokemon, trainer and the engine's coordinates go down with it.
      padTop = 101, padRows = 32, padTuck = 0.75,
      -- a small back stands a little behind its pad: when less than minVisible of its resting
      -- body shows above the text box, the Pokemon alone (not its pad or trainer) is raised
      -- (playerRaise) until that much shows; a larger back is left where it is
      minVisible = 0.65,
      -- ... and a back whose resting body is no taller than wholeBelow (canvas px, before the
      -- zoom) shows WHOLE: its feet just above the text box (Pikachu, Joltik, Natu). Taller than
      -- cutAbove it keeps minVisible (the over-the-shoulder cut); in between the share blends.
      wholeBelow = 36, cutAbove = 56,
      outRate = 0.2, inRate = 0.05, holdFrames = 45,
      z = 1, target = 1, extra = 0, extraTarget = 0, hold = 0, idle = 99,
    },
  }
  local real = {}
  self.real = real

  -- ---------------------------------------------------------------- shaders

  -- what each shader was last sent: sent[shader][name] = { fn = the send used, n, values... }
  local sent = setmetatable({}, { __mode = "k" })
  local shaderMethods, shaderReal = nil, {}

  -- wrap Shader:send / sendColor (one method table for every shader) to remember each send
  local function trackShaders()
    local probe = G.newShader("vec4 effect(vec4 c, Image t, vec2 tc, vec2 sc) { return Texel(t, tc) * c; }")
    local mt = getmetatable(probe)
    local methods = mt and (type(mt.__index) == "table" and mt.__index or mt)
    if not (methods and type(methods.send) == "function") then return end
    shaderMethods = methods
    for _, name in ipairs({ "send", "sendColor" }) do
      local fn = methods[name]
      if type(fn) == "function" then
        shaderReal[name] = fn
        methods[name] = function(sh, uniform, ...)
          local res = { fn(sh, uniform, ...) }
          local v = { fn = fn, n = select("#", ...), ... }
          -- a vector or array is copied (it may be reused and changed); anything else is kept
          for i = 1, v.n do
            if type(v[i]) == "table" and v[i][1] ~= nil then
              local copy = {}
              for k, x in pairs(v[i]) do copy[k] = x end
              v[i] = copy
            end
          end
          local u = sent[sh]
          if not u then
            u = {}
            sent[sh] = u
          end
          u[uniform] = v
          return unpack(res)
        end
      end
    end
  end

  local function resend(sh, name, v)
    pcall(v.fn, sh, name, unpack(v, 1, v.n))
  end

  -- shaders a composite or flatten sent old uniforms to: put back to their latest after it
  local touched = {}
  local function restoreShaders()
    for sh in pairs(touched) do
      for name, v in pairs(sent[sh] or {}) do resend(sh, name, v) end
      touched[sh] = nil
    end
  end

  -- set a recorded draw's shader with the uniforms it was drawn with; m: the HD draw's texture
  -- mapping (texMap), for a shader in the image's own pixels
  local function useShader(rec, m)
    local sh = rec.shader
    real.setShader(sh)
    local u = rec.uniforms
    if not (sh and u) then return end
    local over
    if m then
      for _, p in ipairs(PIXEL_SHADERS) do
        if sentAll(u, p.uniforms) then
          local ok, res = pcall(p.remap, u, m)
          over = ok and res or nil
          break
        end
      end
    end
    touched[sh] = true
    for name, v in pairs(u) do
      local o = over and over[name]
      if o and shaderReal.send then
        pcall(shaderReal.send, sh, name, unpack(o))
      else
        resend(sh, name, v)
      end
    end
  end

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

  local function onPass()
    return self.cur ~= nil and isPassCanvas(real.getCanvas())
  end

  -- start a fresh transparent layer; what the pass draws next goes into it.
  -- screen: a layer of whole-scene draws, composited without Battle Fit's zoom
  local function openLayer(screen)
    local cur = self.cur
    local drawing = onPass()
    cur.pending = false
    cur.screenOpen = screen and true or false
    cur.layerCount = cur.layerCount + 1
    local layer = getLayer(cur.w, cur.h, cur.layerCount)
    cur.layerSet[layer] = true
    cur.current = layer
    cur.items[#cur.items + 1] = { kind = "layer", canvas = layer, screen = screen }
    real.push("all")
    real.setCanvas(layer)
    real.origin()
    real.setScissor()
    real.setShader()
    real.setBlendMode("alpha", "alphamultiply")
    real.clear(0, 0, 0, 0)
    real.pop()
    if drawing then real.setCanvas(layer) end
  end

  -- a draw is about to happen on the pass: open the layer a tagged draw left pending, or
  -- move between whole-scene draws and the rest
  local function beforeDraw(screen)
    local cur = self.cur
    if screen then
      if not cur.screenOpen then openLayer(true) end
    elseif cur.pending or cur.screenOpen then
      openLayer(false)
    end
  end

  -- whole-scene draws are only told apart in a battle's scene, with Battle Fit on
  local function sceneFit()
    local cur = self.cur
    return self.fit.enabled and cur.pass == "battle" and cur.segment == "scene" and not cur.stageDraw
  end

  -- does the rectangle (x, y, w, h), in the current transform, cover the scene (down to the
  -- text box's line), or with `bottom` the canvas down to that row?
  local function coversScene(x, y, w, h, bottom)
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
      return false
    end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + h)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    return x0 <= 0.5 and y0 <= 0.5 and x1 >= self.cur.w - 0.5 and y1 >= (bottom or self.fit.focus[2]) - 0.5
  end

  -- the rectangle (x, y, w, h) an image draw covers, before the current transform; nil when
  -- it cannot tell (rotated, no size)
  local function drawRect(image, a, b, c, d, e, f, g, h)
    local w, hh, x, y, r, sx, sy, ox, oy
    if isQuad(a) then
      local _
      _, _, w, hh = a:getViewport()
      x, y, r, sx, sy, ox, oy = b, c, d, e, f, g, h
    else
      if not (image and image.getWidth) then return nil end
      w, hh = image:getWidth(), image:getHeight()
      x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g
    end
    if (r or 0) ~= 0 or type(x) ~= "number" then return nil end
    sx = sx or 1
    sy = sy or sx
    return x - (ox or 0) * sx, (y or 0) - (oy or 0) * sy, w * sx, hh * sy
  end

  local function drawCoversScene(image, a, b, c, d, e, f, g, h, bottom)
    -- a canvas drawn over the scene is an effect drawn in scene coordinates: it zooms
    if type(image) == "userdata" and image.typeOf and image:typeOf("Canvas") then return false end
    local x, y, w, hh = drawRect(image, a, b, c, d, e, f, g, h)
    if not x then return false end
    return coversScene(x, y, w, hh, bottom)
  end

  -- a UI draw across the row the stacked layout splits the UI at (a level-up window, the
  -- intro's closing wipe): that frame's UI is drawn in one piece, so nothing is torn. An
  -- invisible draw, or one over the whole canvas (a fade), is not a window: it splits fine
  local function noteStraddle(x, y, w, h)
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
      return
    end
    local split = self.fit.split
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + h)
    if y0 > y1 then y0, y1 = y1, y0 end
    if x0 > x1 then x0, x1 = x1, x0 end
    if not (y0 < split - 0.5 and y1 > split + 0.5) then return end
    local cur = self.cur
    if x0 <= 0.5 and y0 <= 0.5 and x1 >= cur.w - 0.5 and y1 >= cur.h - 0.5 then return end
    local _, _, _, a = real.getColor()
    if a < 0.01 then return end
    cur.uiStraddle = true
  end

  -- an opaque draw over the battle's whole canvas after the UI seam (a menu or summary
  -- screen opened over the battle, a fade at full black): fill sits that frame out, so the
  -- screen shows framed like the game's own rather than docked over the scene
  local function noteUICover(covers)
    local cur = self.cur
    if not (covers and self.fit.fill and cur.pass == "battle" and cur.segment == "ui") then return end
    local _, _, _, a = real.getColor()
    if a >= 0.99 then cur.uiCovers = true end
  end
  local function uiFill()
    local cur = self.cur
    return self.fit.fill and cur.pass == "battle" and cur.segment == "ui" and not cur.uiCovers
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
    local shader = real.getShader()
    local uniforms
    if shader and sent[shader] then
      uniforms = {}
      for name, v in pairs(sent[shader]) do uniforms[name] = v end
    end
    return {
      spec = spec, image = image, quad = quad,
      x = x, y = y or 0, r = r or 0, sx = sx or 1, sy = sy or (sx or 1), ox = ox or 0, oy = oy or 0,
      tx = t0x, ty = t0y, tsx = t1x - t0x, tsy = t2y - t0y,
      color = { cr, cg, cb, ca }, shader = shader, uniforms = uniforms, blend = { bm, am },
    }
  end

  local function wrappedDraw(image, ...)
    local cur = self.cur
    if cur and onPass() then
      local spec = self.tags[image]
      if spec and cur.splits < cur.cap then
        local rec = record(image, spec, ...)
        if rec then
          -- drawn by a move animation: already where the engine's (shifted) coordinates put it
          rec.inAnim = self.inAnim == true
          -- tagged draws with nothing drawn between them share one split
          if not cur.pending then cur.splits = cur.splits + 1 end
          cur.items[#cur.items + 1] = { kind = "hd", rec = rec }
          cur.pending = true
          cur.screenOpen = false
          self.stats.splits = self.stats.splits + 1
          return
        end
      elseif spec then
        self.stats.overCap = self.stats.overCap + 1
      end
      -- the wallpaper drawn again in the scene (a ground fill continued under a text box moved
      -- off the screen, Kanto Gear): the recorded wallpaper already covers the whole view
      if image == cur.backdropImage and sceneFit() then return end
      local uiScreen = false
      if uiFill() then
        local a, b, c, d, e, f, g, h = ...
        uiScreen = drawCoversScene(image, a, b, c, d, e, f, g, h, cur.h)
        noteUICover(uiScreen)
        if not cur.uiStraddle then noteStraddle(drawRect(image, a, b, c, d, e, f, g, h)) end
      end
      -- a draw over the whole scene, or with fill over the whole UI (a fade), gets a layer of
      -- its own that covers the whole screen
      beforeDraw(uiScreen or (sceneFit() and drawCoversScene(image, ...)))
    end
    return real.draw(image, ...)
  end

  local function wrapPrimitive(name)
    return function(...)
      if self.cur and onPass() then
        local screen = false
        if name == "rectangle" and sceneFit() then
          local mode, x, y, w, h = ...
          screen = mode == "fill" and coversScene(x, y, w, h)
        end
        if name == "rectangle" and uiFill() then
          local mode, x, y, w, h = ...
          screen = mode == "fill" and coversScene(x, y, w, h, self.cur.h)
          noteUICover(screen)
          if not self.cur.uiStraddle then noteStraddle(x, y, w, h) end
        end
        beforeDraw(screen)
      end
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
    -- optional: the wallpaper is drawn wrapped through a quad of our own
    if type(G.newQuad) == "function" then real.newQuad = G.newQuad end
    -- optional: each recorded draw replays with the shader uniforms it was drawn with
    if type(G.newShader) == "function" and not shaderMethods then pcall(trackShaders) end
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
    if shaderMethods then
      for name, fn in pairs(shaderReal) do shaderMethods[name] = fn end
      shaderMethods, shaderReal = nil, {}
    end
    self.installed = false
  end

  --- Something of ours failed on this device: say so once, put back any pass in flight, and
  --- capture nothing more this session, so every frame is drawn the game's own way.
  function self.fail(err)
    if self.failed then return end
    self.failed = tostring(err)
    self.stats.failed = self.failed
    if self.log and self.log.error then
      pcall(self.log.error, self.log, "turned off for this session, frames are drawn the game's usual way: %s",
        self.failed)
    end
    if self.cur then pcall(self.flatten, self.cur) end
  end

  --- Start capturing a pass on `base` (the canvas currently drawn into).
  function self.beginPass(pass, base)
    -- a pass that was never ended (its frame was not presented the usual way): put it back
    if self.cur then self.flatten(self.cur) end
    self.inAnim = false
    if self.failed then return false end
    -- the engine no longer presents through the Renderer (canCapture: src/engine.lua): a pass
    -- could never be composited, so the game draws its own way
    if self.canCapture and not self.canCapture() then return false end
    if not (self.installed and self.enabled[pass] and base and base.getWidth) then return false end
    self.cur = {
      pass = pass, base = base, current = base, layerSet = {}, items = {},
      w = base:getWidth(), h = base:getHeight(), layerCount = 0, splits = 0,
      cap = self.caps[pass] or 8, pending = false, screenOpen = false,
      segment = "scene", hasUI = false,
      prefit = {},
      -- the side shift this frame is drawn with (the engine's move coordinates use the same)
      shift = { enemy = self.fit.shift.enemy, player = self.fit.shift.player,
                playerY = self.fit.shift.playerY, playerRaise = self.fit.shift.playerRaise },
    }
    return true
  end

  --- The scene of a battle ends here: what the pass draws next is the UI (Battle Fit).
  function self.seam(name)
    local cur = self.cur
    if not cur then return end
    cur.items[#cur.items + 1] = { kind = "seam", name = name }
    if name == "ui" then
      cur.segment = "ui"
      cur.hasUI = true
    end
    openLayer(false)
  end

  --- Draw the battle's wallpaper: recorded, then drawn at window resolution, wrapped so the
  --- zoomed-out scene never shows its edge. Outside a pass it is simply drawn.
  function self.backdrop(image, x, y)
    local cur = self.cur
    if not (cur and onPass()) then return real.draw(image, x, y) end
    local rec = record(image, {}, x, y)
    if not rec then return real.draw(image, x, y) end
    cur.items[#cur.items + 1] = { kind = "backdrop", rec = rec }
    cur.backdropImage = image
    cur.pending = true
    cur.screenOpen = false
  end

  --- Draw a band that wraps sideways (the intro's scrolling grass): recorded, then drawn at
  --- window resolution with the scene's zoom, repeated across the whole view so the zoomed-out
  --- scene never shows its ends. Outside a pass it is simply drawn.
  function self.band(image, x, y)
    local cur = self.cur
    if not (cur and onPass()) then return real.draw(image, x, y) end
    local rec = record(image, {}, x, y)
    if not rec then return real.draw(image, x, y) end
    cur.items[#cur.items + 1] = { kind = "band", rec = rec }
    cur.pending = true
    cur.screenOpen = false
  end

  --- Draw part of the battle's stage that is as big as the screen but is not a whole-scene
  --- effect (a pad, drawn on a transparent screen-sized image): it zooms with the scene.
  --- side ("enemy" / "player", optional): the pad moves with that side's shift (Battle Fit),
  --- so it is recorded and drawn at window resolution instead of into the canvas.
  function self.drawStage(image, x, y, side)
    local cur = self.cur
    if side and cur and onPass() and self.fit.enabled and cur.pass == "battle" then
      local rec = record(image, {}, x, y)
      if rec then
        cur.items[#cur.items + 1] = { kind = "stage", rec = rec, side = side }
        cur.pending = true
        cur.screenOpen = false
        return
      end
    end
    if cur then cur.stageDraw = true end
    G.draw(image, x, y)
    if cur then cur.stageDraw = false end
  end

  --- A battler in the battle, as it rests: its tagged pic as the battle draws it centred on
  --- (x, y) (origin 32, 32). The fit uses this for its side instead of the drawn pic, so the
  --- camera is framed for a trainer's Pokemon before its send-out and does not follow the
  --- Pokemon's own movement (a jump, a lunge). Cleared each pass.
  function self.prefit(side, image, x, y)
    local cur = self.cur
    local spec = image ~= nil and self.tags[image]
    if not (cur and spec and type(x) == "number" and type(y) == "number") then return end
    cur.prefit[side] = {
      spec = spec, image = image, x = x, y = y, r = 0, sx = 1, sy = 1, ox = 32, oy = 32,
      tx = 0, ty = 0, tsx = 1, tsy = 1,
    }
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

  -- where a tagged draw stands: the point in pass-canvas pixels where its HD pivot goes
  -- (X, Y), that pivot in the HD frame (hpx, hpy), its size k, the texture and quad
  local function place(rec)
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
    -- a part of the pic drawn on its own (its rows one by one, each shifted: Rapid Spin,
    -- Extrasensory, Dig): the pivot is the whole pic's, and the HD frame is cut to that part
    -- (cut: {x0, y0, x1, y1} in the HD texture's pixels)
    local ox, oy, cut = rec.ox, rec.oy, nil
    if spec.texture and spec.quad and rec.quad and not qp then
      local vx, vy, vw, vh = rec.quad:getViewport()
      ox, oy = ox + vx, oy + vy
      local fx, fy, fw, fh = spec.quad:getViewport()
      cut = { math.max(fx, fx + hpx + (vx - lpx) / k), math.max(fy, fy + hpy + (vy - lpy) / k),
              math.min(fx + fw, fx + hpx + (vx + vw - lpx) / k), math.min(fy + fh, fy + hpy + (vy + vh - lpy) / k) }
    end
    -- where the low-res draw put that point, in the pass canvas's pixels
    local dx, dy = (lpx - ox) * rec.sx, (lpy - oy) * rec.sy
    local cs, sn = math.cos(rec.r), math.sin(rec.r)
    local px = rec.x + dx * cs - dy * sn
    local py = rec.y + dx * sn + dy * cs
    return rec.tx + px * rec.tsx, rec.ty + py * rec.tsy, hpx, hpy, k, tex, quad, cut
  end

  -- the top of a tagged draw's art, in pass-canvas pixels (spec.top: its first row of art
  -- in the frame, the highest over its animation; else the frame's top)
  local function artTop(rec)
    local _, Y, _, hpy, k = place(rec)
    return Y - (hpy - (rec.spec.top or 0)) * math.abs(rec.sy * k * rec.tsy)
  end

  -- layout values (scales, offsets) are kept to two decimals
  local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

  -- the left and right of a tagged draw's frame, in pass-canvas pixels
  local function artSpan(rec)
    local X, _, hpx, _, k, tex, quad = place(rec)
    local fw
    if quad then
      local _
      _, _, fw = quad:getViewport()
    elseif tex and tex.getWidth then
      fw = tex:getWidth()
    else
      fw = 64
    end
    local s = math.abs(rec.sx * k * rec.tsx)
    return X - hpx * s, X + (fw - hpx) * s
  end

  -- an HD draw's texcoords in the low-res image's (tl = a + th * b, each axis), its texture's
  -- size and its texels per low-res pixel, for a shader in the image's own pixels; nil when
  -- it cannot tell (rotated, no sizes)
  local function texMap(rec, X, Y, hpx, hpy, k, tex, quad)
    local img = rec.image
    if rec.r ~= 0 or rec.sx == 0 or rec.sy == 0 or rec.tsx == 0 or rec.tsy == 0 or k == 0 then return nil end
    if not (tex.getWidth and img.getWidth) then return nil end
    local PW, PH = tex:getWidth(), tex:getHeight()
    local LW, LH = img:getWidth(), img:getHeight()
    local qx, qy, lqx, lqy = 0, 0, 0, 0
    if quad then qx, qy = quad:getViewport() end
    if rec.quad then lqx, lqy = rec.quad:getViewport() end
    -- HD texel u lands at canvas X + (u - qx - hpx) * s; the low-res draw put its pixel lx at
    -- rec.tx + (rec.x + (lx - rec.ox) * rec.sx) * rec.tsx: so lx = lx0 + u * k
    local s, sy = rec.sx * k * rec.tsx, rec.sy * k * rec.tsy
    local lx0 = rec.ox + ((X - (qx + hpx) * s - rec.tx) / rec.tsx - rec.x) / rec.sx
    local ly0 = rec.oy + ((Y - (qy + hpy) * sy - rec.ty) / rec.tsy - rec.y) / rec.sy
    return { ax = (lqx + lx0) / LW, bx = PW * k / LW, ay = (lqy + ly0) / LH, by = PH * k / LH,
             w = PW, h = PH, texels = 1 / k }
  end

  -- pinTo (screen y, optional): the frame's bottom is put exactly there (a trainer cut off by
  -- the text box stands on it, so it still reads as a whole sprite behind the box)
  local cutQuad
  local function hdDraw(rec, bx, by, bsx, bsy, pinTo)
    local X, Y, hpx, hpy, k, tex, quad, cut = place(rec)
    -- a part of the pic: only that part of the HD frame, about the same pivot
    if cut and real.newQuad and tex.getWidth then
      if cut[3] <= cut[1] or cut[4] <= cut[2] then return end
      local fx, fy = quad:getViewport()
      local tw, th = tex:getWidth(), tex:getHeight()
      if cutQuad and cutQuad.setViewport then
        cutQuad:setViewport(cut[1], cut[2], cut[3] - cut[1], cut[4] - cut[2], tw, th)
      else
        cutQuad = real.newQuad(cut[1], cut[2], cut[3] - cut[1], cut[4] - cut[2], tw, th)
      end
      quad = cutQuad
      hpx, hpy = hpx - (cut[1] - fx), hpy - (cut[2] - fy)
    end
    local m = rec.uniforms and texMap(rec, X, Y, hpx, hpy, k, tex, quad)
    if pinTo then
      local fh
      if quad then
        local _
        _, _, _, fh = quad:getViewport()
      elseif tex.getHeight then
        fh = tex:getHeight()
      end
      if fh then
        local bottom = by + (Y + (fh - hpy) * rec.sy * k * rec.tsy) * bsy
        by = by + (pinTo - bottom)
      end
    end
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec, m)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    local SX, SY = bx + X * bsx, by + Y * bsy
    local ssx, ssy = rec.sx * k * rec.tsx * bsx, rec.sy * k * rec.tsy * bsy
    if quad then
      real.draw(tex, quad, SX, SY, rec.r, ssx, ssy, hpx, hpy)
    else
      real.draw(tex, SX, SY, rec.r, ssx, ssy, hpx, hpy)
    end
  end

  -- a recorded plain image (a pad) at window resolution, mapped by (bx, by, bsx, bsy)
  local function imageDraw(rec, bx, by, bsx, bsy)
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    local X, Y = rec.tx + rec.x * rec.tsx, rec.ty + rec.y * rec.tsy
    local sx, sy = rec.sx * rec.tsx * bsx, rec.sy * rec.tsy * bsy
    if rec.quad then
      real.draw(rec.image, rec.quad, bx + X * bsx, by + Y * bsy, rec.r, sx, sy, rec.ox, rec.oy)
    else
      real.draw(rec.image, bx + X * bsx, by + Y * bsy, rec.r, sx, sy, rec.ox, rec.oy)
    end
  end

  local wrapped = setmetatable({}, { __mode = "k" })
  local backdropQuad, groundQuad

  -- the wallpaper, mapped by (bx, by, bsx, bsy), drawn over the whole of the pass canvas's
  -- view (which (fx, fy, fsx, fsy), the unzoomed mapping, puts on the screen): its own
  -- horizontal wrap repeats it, the top row stretches up
  -- wrapV: how the image wraps vertically ("clamp": the wallpaper's top row stretches up;
  -- "clampzero": nothing past its edge, a band such as the intro's grass)
  local function drawBackdrop(rec, cw, ch, bx, by, bsx, bsy, fx, fy, fsx, fsy, wrapV)
    local img = rec.image
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    local iw, ih = img.getWidth and img:getWidth(), img.getHeight and img:getHeight()
    if not (real.newQuad and iw and ih) then
      real.draw(img, bx + (rec.tx + rec.x * rec.tsx) * bsx, by + (rec.ty + rec.y * rec.tsy) * bsy,
        0, rec.tsx * bsx, rec.tsy * bsy)
      return
    end
    wrapV = wrapV or "clamp"
    if wrapped[img] ~= wrapV then
      wrapped[img] = wrapV
      if img.setWrap and not pcall(img.setWrap, img, "repeat", wrapV) then
        pcall(img.setWrap, img, "repeat", "clamp")
      end
    end
    -- the view in canvas pixels of this mapping, then in the image's pixels
    local p0x, p1x = (fx - bx) / bsx, (fx + cw * fsx - bx) / bsx
    local p0y, p1y = (fy - by) / bsy, (fy + ch * fsy - by) / bsy
    local u0 = (p0x - rec.tx) / rec.tsx - rec.x
    local v0 = (p0y - rec.ty) / rec.tsy - rec.y
    local uw, vh = (p1x - p0x) / rec.tsx, (p1y - p0y) / rec.tsy
    local function quad(q, u, v, w, h)
      if q and q.setViewport then
        q:setViewport(u, v, w, h, iw, ih)
        return q
      end
      return real.newQuad(u, v, w, h, iw, ih)
    end
    local sx, sy = rec.tsx * bsx, rec.tsy * bsy
    -- the wallpaper's own rows end at the text box's line (the cart's rows below it are black,
    -- hidden by the text box): past it, its last ground band repeats down to the view's bottom,
    -- so a zoomed-out scene, or a text box moved off the screen (Kanto Gear), shows ground
    local g = self.fit.ground
    local stop = (wrapV == "clamp" and g) and math.min(v0 + vh, g[2]) or v0 + vh
    if stop > v0 then
      backdropQuad = quad(backdropQuad, u0, v0, uw, stop - v0)
      real.draw(img, backdropQuad, bx + p0x * bsx, by + p0y * bsy, 0, sx, sy)
    end
    if stop < v0 + vh then
      local bandH = g[2] - g[1]
      groundQuad = quad(groundQuad, u0, g[1], uw, bandH)
      local row = math.max(g[2], v0)
      row = g[2] + math.floor((row - g[2]) / bandH) * bandH
      while row < v0 + vh do
        real.draw(img, groundQuad, bx + p0x * bsx, by + (p0y + (row - v0) * rec.tsy) * bsy, 0, sx, sy)
        row = row + bandH
      end
    end
  end

  -- how far the camera rises at zoom z (canvas pixels): enough that the enemy's feet line,
  -- zoomed about the focus, sinks no lower than feetMax
  -- a UI row (canvas px of the UI) in the scene's canvas pixels: the same with the scene and UI
  -- at one scale; with fill the scene is bigger, so the UI shrinks about the text box's line
  local function uiY(y)
    local fy = self.fit.focus[2]
    return fy + (y - fy) * (self.fit.uiK or 1)
  end
  local function uiRect(r)
    local fit = self.fit
    local k = fit.uiK or 1
    if k == 1 then return r end
    local fx, fy = fit.focus[1], fit.focus[2]
    return { fx + (r[1] - fx) * k, fy + (r[2] - fy) * k, fx + (r[3] - fx) * k, fy + (r[4] - fy) * k }
  end

  -- the enemy's HP box over the scene, in the scene's canvas pixels: moved up with the
  -- stacked layout's top band, then as uiRect (remembered: the solver asks for it a lot)
  local enemyUI, enemyUIKey = nil, nil
  local function uiEnemy()
    local fit = self.fit
    local d = fit.uiTopDy or 0
    local key = (fit.uiK or 1) * 1e6 + d
    if enemyUIKey ~= key then
      local e = fit.ui.enemy
      enemyUI = uiRect({ e[1], e[2] + d, e[3], e[4] + d })
      enemyUIKey = key
    end
    return enemyUI
  end

  -- the highest canvas row art may reach: the screen's top, less the margin
  local function topLimit()
    return (self.fit.topY or 0) + self.fit.margin
  end

  local function fitLift(z)
    local fit = self.fit
    local fy = fit.focus[2]
    return math.max(0, fy + (fit.feetY - fy) * z - uiY(fit.feetMax))
  end
  self.fitLift = fitLift

  -- the zoom that brings `top` to the margin: about the focus while the feet stay above
  -- feetMax, else (the camera rising) with the feet held on feetMax
  local function fitZoom(top)
    local fit = self.fit
    local limit = topLimit()
    if top >= limit then return 1 end
    local fy = fit.focus[2]
    local z = (fy - limit) / (fy - top)
    if fitLift(z) > 0 then z = (uiY(fit.feetMax) - limit) / (fit.feetY - top) end
    return math.min(1, z)
  end
  self.fitZoom = fitZoom

  -- a tagged draw's body box (spec.body = {x0, y0, x1, y1}, frame pixels) in canvas pixels
  local function bodyRect(rec)
    local b = rec.spec.body
    local X, Y, hpx, hpy, k = place(rec)
    local sx, sy = rec.sx * k * rec.tsx, rec.sy * k * rec.tsy
    local xa, xb = X + (b[1] - hpx) * sx, X + (b[3] - hpx) * sx
    local ya, yb = Y + (b[2] - hpy) * sy, Y + (b[4] - hpy) * sy
    return math.min(xa, xb), math.min(ya, yb), math.max(xa, xb), math.max(ya, yb)
  end

  local function overlap(a0, a1, b0, b1) return math.max(0, math.min(a1, b1) - math.max(a0, b0)) end

  -- how much of the rectangle (canvas px, unzoomed), seen at zoom z raised by lift, is under
  -- the enemy's HP box, and under the player's side (its HP box and the text box); and its top
  --- How far the player's side is lowered (canvas px before the zoom) at zoom z raised by
  --- lift, so its pad stays tucked under the text box (fit.padTuck).
  local function playerDrop(z, lift)
    local fit = self.fit
    if z >= 1 and lift <= 0 then return 0 end
    local cart = fit.focus[2] - fit.padTop                 -- rows the cart shows (11)
    local tucked = fit.padRows * (1 - fit.padTuck)         -- rows shown at zMin (8)
    local u = math.max(0, math.min(1, (z - fit.zMin) / math.max(1e-6, 1 - fit.zMin)))
    local visible = tucked + (cart - tucked) * u
    return (lift + (cart - visible) * z) / z
  end
  self.fitPlayerDrop = playerDrop

  --- How far a back (r, its resting body, canvas px) is raised above its side (canvas px
  --- before the zoom) at zoom z raised by lift, its side lowered by v: enough that its body
  --- shows above the text box's line, all of it for a small back (wholeBelow), minVisible of it
  --- for a big one (cutAbove), blended between; 0 for a back already showing that much.
  local function backRaise(r, z, lift, v)
    local fit = self.fit
    local line = fit.focus[2]
    local top = line + (r[2] + v - line) * z - lift
    local h = r[4] - r[2]
    local u = math.max(0, math.min(1, (h - fit.wholeBelow) / math.max(1e-6, fit.cutAbove - fit.wholeBelow)))
    local share = 1 + (fit.minVisible - 1) * u          -- 1 (whole) for a small back
    local want = line - share * h * z
    if top <= want then return 0 end
    return (top - want) / z
  end
  self.fitBackRaise = backRaise

  local function hidden(r, z, lift)
    local fit = self.fit
    local fx, fy = fit.focus[1], fit.focus[2]
    local x0, x1 = fx + (r[1] - fx) * z, fx + (r[3] - fx) * z
    local y0, y1 = fy + (r[2] - fy) * z - lift, fy + (r[4] - fy) * z - lift
    local area = math.max(1e-6, (x1 - x0) * (y1 - y0))
    local function under(u) return overlap(x0, x1, u[1], u[3]) * overlap(y0, y1, u[2], u[4]) end
    return under(uiEnemy()) / area, (under(uiRect(fit.ui.player)) + under(fit.ui.text)) / area, y0
  end
  self.fitHidden = hidden

  --- The camera for a frame: the largest zoom (and with it the least rise past the enemy's
  --- feet) that keeps the enemy's art under the top of the screen with its feet above the
  --- player's HP box, and for each of the player's Pokemon (`backs`, resting body rects):
  ---   * its whole animation (r.top, a head flung up) on the screen, always;
  ---   * headroom: its body's top no higher than backTopMin, the tallest cart back sprite's
  ---     (which also keeps its head out from under the enemy's HP box);
  ---   * at most maxHiddenOwn of its body under its own side's UI, if any camera manages it.
  --- When no camera gives the headroom, at most maxHidden of the body may sit under the enemy's
  --- HP box instead. top: the enemy art's top (math.huge: none). Returns the zoom and the rise.
  local solved, solvedCount = {}, 0
  local function fitSolveRaw(top, backs)
    local fit = self.fit
    local fy = fit.focus[2]
    local zFront = math.max(fit.zMin, fitZoom(top))
    if #backs == 0 then return zFront, 0 end
    local limit = topLimit()
    -- headroom: the cart's gap under the enemy's HP box, moved up with the box
    local headroom = uiY(fit.backTopMin + (fit.uiTopDy or 0))
    -- levels, strictest first: { headroom, own side mostly in view }
    local levels = { { true, true }, { true, false }, { false, true }, { false, false } }
    local function fits(z, lift, level)
      for _, r in ipairs(backs) do
        -- the back where the player side's drop puts it
        local v = playerDrop(z, lift)
        v = v - backRaise(r, z, lift, v)
        local underEnemy, underOwn, y0 = hidden({ r[1], r[2] + v, r[3], r[4] + v }, z, lift)
        local t = r.top and (fy + (r.top + v - fy) * z - lift) or y0
        if y0 < limit or t < limit then return false end
        if level[1] then
          if y0 < headroom then return false end
        elseif underEnemy > fit.maxHidden then
          return false
        end
        if level[2] and underOwn > fit.maxHiddenOwn then return false end
      end
      return true
    end
    for _, level in ipairs(levels) do
      -- headroom out of reach at every allowed zoom: the limit is still the nearest to it,
      -- so the looser levels only choose the rise there (never a closer camera)
      local z = level[1] and zFront or fit.zMin
      while z >= fit.zMin - 1e-9 do
        local base = fitLift(z)
        local most = base + fit.extraMax
        -- rising lifts the enemy too: its art's top must stay under the screen's
        if top < math.huge then most = math.min(most, fy + (top - fy) * z - limit) end
        local lift = base
        while lift <= most + 1e-9 do
          if fits(z, lift, level) then return z, lift - base end
          lift = lift + 1
        end
        z = z - fit.zStep
      end
    end
    -- nothing fits even pulled all the way back: pulled all the way back is still the
    -- nearest, so clamp to the limit (never fall back to the enemy's own zoom)
    return fit.zMin, 0
  end

  -- the same, remembered: an animation repeats its frames, so a frame's inputs recur
  local function fitSolve(top, backs)
    local fit = self.fit
    local parts = { string.format("%.2f|%.3f|%.4f|%.2f|%.2f", top, fit.zMin, fit.uiK or 1,
      fit.topY or 0, fit.uiTopDy or 0) }
    for _, r in ipairs(backs) do
      parts[#parts + 1] = string.format("%.2f,%.2f,%.2f,%.2f,%.2f", r[1], r[2], r[3], r[4], r.top or 0)
    end
    local key = table.concat(parts, ";")
    local hit = solved[key]
    if hit then return hit[1], hit[2] end
    local z, e = fitSolveRaw(top, backs)
    if solvedCount >= 256 then solved, solvedCount = {}, 0 end
    solved[key] = { z, e }
    solvedCount = solvedCount + 1
    return z, e
  end
  self.fitSolve = fitSolve

  -- the stage zoom for this frame: the camera that fits the tagged sprites, eased (out fast;
  -- back in only after the target has stayed nearer for holdFrames)
  local function fitStep(cur)
    local fit = self.fit
    local top, backs = math.huge, {}
    local seen = {}
    -- each side's art where it rests (canvas px, unshifted, unzoomed): its frame across, the
    -- enemy's feet (its pic box's bottom), the top of the player's body (else of its art)
    local eL, eR, eB = math.huge, -math.huge, -math.huge
    local pL, pR, pT = math.huge, -math.huge, math.huge
    local function take(rec)
      local spec = rec.spec
      if spec.side then seen[spec.side] = true end
      local d = (not rec.inAnim and cur.shift[spec.side == "player" and "player" or "enemy"]) or 0
      local a, b = artSpan(rec)
      if spec.side == "player" then
        if not rec.inAnim then a, b = a + d - cur.shift.player, b + d - cur.shift.player end
        pL, pR = math.min(pL, a), math.max(pR, b)
        if spec.body then
          local r = { bodyRect(rec) }
          pT = math.min(pT, r[2])
          -- where the side shift puts it (only its x: which UI it is under)
          r[1], r[3] = r[1] + d, r[3] + d
          if spec.top then r.top = artTop(rec) end
          backs[#backs + 1] = r
        else
          pT = math.min(pT, artTop(rec))
        end
      else
        if not rec.inAnim then a, b = a + d - cur.shift.enemy, b + d - cur.shift.enemy end
        eL, eR = math.min(eL, a), math.max(eR, b)
        -- its feet: where the cart's pic box ends (a frame's own bottom may be empty margin)
        eB = fit.feetY
        local t = artTop(rec)
        if t < top then top = t end
      end
    end
    -- a battler the engine reported (hd.prefit) is fitted where it rests, drawn yet or not:
    -- its send-out jump, a lunge or a shake never moves the camera
    for _, rec in pairs(cur.prefit) do take(rec) end
    -- the platforms count as each side's art: the scene never crops them
    if fit.wantW then
      local pe, pp = fit.pads.enemy, fit.pads.player
      eL, eR = math.min(eL, pe[1]), math.max(eR, pe[2])
      pL, pR = math.min(pL, pp[1]), math.max(pR, pp[2])
    end
    for _, item in ipairs(cur.items) do
      if item.kind == "seam" and item.name == "ui" then break end
      local spec = item.kind == "hd" and item.rec.spec
      if spec and not spec.trainer and not (spec.side and cur.prefit[spec.side]) then
        take(item.rec)
      end
    end
    local zt, et = fitSolve(top, backs)
    fit.target, fit.extraTarget = zt, et
    if fit.idle > 2 then
      -- a new battle: start where it should be, unshifted until its intro is over
      fit.z, fit.extra, fit.hold = zt, et, 0
      fit.shift.enemy, fit.shift.player = 0, 0
    else
      local outward = zt < fit.z or et > fit.extra
      local inward = zt > fit.z or et < fit.extra
      if outward then fit.hold = 0 elseif inward then fit.hold = fit.hold + 1 else fit.hold = 0 end
      local settle = fit.hold >= fit.holdFrames
      if zt < fit.z then
        fit.z = math.max(zt, fit.z - math.max((fit.z - zt) * fit.outRate, 0.002))
      elseif zt > fit.z and settle then
        fit.z = math.min(zt, fit.z + math.max((zt - fit.z) * fit.inRate, 0.001))
      end
      if et > fit.extra then
        fit.extra = math.min(et, fit.extra + math.max((et - fit.extra) * fit.outRate, 0.2))
      elseif et < fit.extra and settle then
        fit.extra = math.max(et, fit.extra - math.max((fit.extra - et) * fit.inRate, 0.1))
      end
    end
    -- the side shift: back toward each side's unzoomed spot, as far as shiftMax allows. Only a
    -- side whose Pokemon is tagged moves: an untagged one is drawn by the game where it always
    -- is, so its pad (and the engine's coordinates) must stay there too
    local fx = fit.focus[1]
    local wantE, wantP = 0, 0
    if fit.z < 1 then
      local k = (1 - fit.z) / fit.z
      if seen.enemy then wantE = math.min(fit.shiftMax, (fit.enemyX - fx) * k) end
      if seen.player then wantP = -math.min(fit.shiftMax, (fx - fit.playerX) * k) end
    end
    fit.shift.playerY = (fit.z < 1 and seen.player)
      and playerDrop(fit.z, fitLift(fit.z) + fit.extra) or 0
    fit.shift.playerRaise = backs[1]
      and backRaise(backs[1], fit.z, fitLift(fit.z) + fit.extra, fit.shift.playerY) or 0
    -- stacked, the width short of what growing to the top needs: the sides slide inward, as far
    -- as they may without the Pokemon overlapping (canvas px before the zoom, split evenly);
    -- both Pokemon must be tagged, or one would be left behind its pad
    local inward = 0
    if fit.wantW and eL < eR and pL < pR and seen.enemy and seen.player then
      local z = fit.z
      local L, R = math.min(eL + wantE, pL + wantP), math.max(eR + wantE, pR + wantP)
      local need = ((R - L) * z - fit.wantW) / z
      if need > 0 then
        local most
        if pT + fit.shift.playerY - fit.shift.playerRaise >= eB then
          most = ((eL + eR) - (pL + pR)) / 2 + wantE - wantP        -- centres aligned
        else
          -- side by side, the back in front of the enemy's platform
          most = (eL + wantE) + fit.overlapFoe * (eR - eL) - (pR + wantP)
        end
        inward = math.max(0, math.min(need, most, fit.inwardMax))
      end
    end
    -- split evenly, but the player's Pokemon stops short of its own HP box (its body, else its
    -- art, no further right than the box's left edge); the enemy takes the rest
    local toP = inward / 2
    if inward > 0 then
      local box = uiRect(fit.ui.player)
      local right = (backs[1] and (backs[1][3] - cur.shift.player)) or pR
      local room = (box[1] - fx) / fit.z + fx - (right + wantP)
      toP = math.max(0, math.min(toP, room))
    end
    fit.shift.enemy, fit.shift.player = round2(wantE - (inward - toP)), round2(wantP + toP)
    -- the art's extent as the stage's zoom shows it, for the next frame's growth
    if eL < eR or pL < pR then
      local z = fit.z
      local L = math.min(eL + fit.shift.enemy, pL + fit.shift.player)
      local R = math.max(eR + fit.shift.enemy, pR + fit.shift.player)
      fit.span = { fx + (L - fx) * z, fx + (R - fx) * z }
    end
    self.stats.inward = inward
    -- the highest art as the camera shows it (zoomed, raised), for the HP box to sit above
    local lift = fitLift(fit.z) + fit.extra
    local at = math.huge
    if top < math.huge then at = fit.focus[2] + (top - fit.focus[2]) * fit.z - lift end
    for _, r in ipairs(backs) do
      local v = fit.shift.playerY - fit.shift.playerRaise
      local y = (r.top or r[2]) + v
      at = math.min(at, fit.focus[2] + (y - fit.focus[2]) * fit.z - lift)
    end
    fit.artTop = at < math.huge and at or nil
    fit.idle = 0
    self.stats.zoom, self.stats.zoomTarget, self.stats.extraLift = fit.z, zt, fit.extra
    self.stats.shiftEnemy, self.stats.shiftPlayer = fit.shift.enemy, fit.shift.player
    self.stats.dropPlayer = fit.shift.playerY
    self.stats.raisePlayer = fit.shift.playerRaise
    -- the most of any player's Pokemon's body hidden under each UI, as drawn this frame
    -- and the highest body top (canvas px; headroom asks for backTopMin or lower)
    local he, ho, bt = 0, 0, math.huge
    for _, r in ipairs(backs) do
      local lift = fitLift(fit.z) + fit.extra
      local v = playerDrop(fit.z, lift)
      v = v - backRaise(r, fit.z, lift, v)
      local e, o, y0 = hidden({ r[1], r[2] + v, r[3], r[4] + v }, fit.z, lift)
      he, ho, bt = math.max(he, e), math.max(ho, o), math.min(bt, y0)
    end
    self.stats.hiddenEnemyUI, self.stats.hiddenOwnUI = he, ho
    self.stats.backTop = bt < math.huge and bt or nil
    return fit.z
  end

  -- a rect {x, y, w, h} clipped to another
  local function clipRect(x, y, w, h, v)
    local x0, y0 = math.max(x, v[1]), math.max(y, v[2])
    local x1, y1 = math.min(x + w, v[1] + v[3]), math.min(y + h, v[2] + v[4])
    return { x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0) }
  end

  -- the UI at a scale that is not a whole number, kept sharp and even: drawn pixel for pixel
  -- at the next whole scale k into a canvas of its own, which is then scaled down smoothly
  -- (every UI pixel the same width, its edges at most one screen pixel soft)
  local sharp, sharpW, sharpH = nil, 0, 0
  local function sharpen(c, w, h, k)
    if not (real.newCanvas and real.setCanvas) then return c, 1 end
    if not sharp or sharpW ~= w * k or sharpH ~= h * k then
      if sharp and sharp.release then pcall(sharp.release, sharp) end
      sharp = real.newCanvas(w * k, h * k, { dpiscale = 1 })
      if sharp.setFilter then sharp:setFilter("linear", "linear") end
      sharpW, sharpH = w * k, h * k
    end
    real.push("all")
    real.setCanvas(sharp)
    real.origin()
    real.setScissor()
    real.setShader()
    real.clear(0, 0, 0, 0)
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("alpha", "premultiplied")
    real.draw(c, 0, 0, 0, k, k)
    real.pop()
    return sharp, k
  end

  --- Replace a blit of a captured canvas. `blit(canvas, bx, by, bsx, bsy, box, zk)` performs
  --- the Renderer's own blit of a canvas with the same arguments (the optional ones replace
  --- its origin, scale and clip; zk: the canvas's pixels per game pixel, for one drawn larger);
  --- bx/by/bsx/bsy map canvas pixels to the screen; box = {x, y, w, h} clip (or nil).
  --- view = {x, y, w, h, top =, bottom =}, the whole screen area (or nil), its usable rows
  --- from top (below a notch) to bottom (above touch controls): with fit.fill the battle
  --- fills it (see fit.fill and fit.split). Returns true when the blit was handled.
  function self.composite(canvas, blit, bx, by, bsx, bsy, box, view)
    local cur = self.done[canvas]
    if not cur then return false end
    local fit = self.fit
    local fitted = cur.pass == "battle" and cur.hasUI and fit.enabled
    local fx, fy = fit.focus[1], fit.focus[2]
    -- the scene's frame on screen: where canvas (fx, fy) lands and how big a canvas pixel is;
    -- the UI's origin and scale. Without fill both are the Renderer's letterbox.
    local cx, cy, S, Sy = bx + fx * bsx, by + fy * bsy, bsx, bsy
    local ubx, uby, U, Uy = bx, by, bsx, bsy
    local sceneBox, uiBox = box, box
    local filling = fitted and fit.fill and view ~= nil and not cur.uiCovers
    local stacked, dyTop, top = false, 0, nil
    fit.wantW = nil
    if filling then
      local vx, vy, vw, vh = view[1], view[2], view[3], view[4]
      top = math.max(vy, view.top or vy)
      local bottom = math.min(vy + vh, view.bottom or (vy + vh))
      -- controls that leave no room for the UI are not docked to
      if bottom - top < cur.h * bsy then top, bottom = vy, vy + vh end
      local free = view.bottom == nil
      if (bottom - top) * cur.w > vw * cur.h + 0.5 then
        if free then bottom = bottom - (fit.raise or 0) end
        -- taller than the canvas: the UI spans the width, its lower rows docked to the bottom
        -- and its top band (the enemy's HP box) moved up to the top; the scene at the UI's
        -- scale, the wallpaper's sky above it
        stacked = true
        U = round2(vw / cur.w)
        Uy = round2(U * bsy / bsx)
        ubx = round2(vx + (vw - cur.w * U) / 2)
        uby = round2(bottom - cur.h * Uy)
        dyTop = math.min(0, round2((top - uby) / Uy))
        cy = uby + fy * Uy
        -- the scene grows about the text box's line into the space above, up to the screen's
        -- top, or until both sides' art spans the width, whichever comes first
        local span = fit.span or fit.spanDefault
        local m = fit.cropMargin
        local gH = (cy - top) / (fy * Uy)
        local gW = vw / (U * (span[2] - span[1] + 2 * m))
        fit.wantW = vw / (U * gH) - 2 * m
        local gt = math.max(1, math.min(gH, gW))
        local g = fit.grow
        if not g or fit.idle > 2 then
          g = gt
        elseif gt < g then
          g = math.max(gt, g - math.max((g - gt) * fit.outRate, 0.002))
        elseif gt > g then
          g = math.min(gt, g + math.max((gt - g) * fit.inRate, 0.001))
        end
        fit.grow = g
        g = round2(g)
        self.stats.grow = g
        S, Sy = U * g, Uy * g
        -- centred, and moved sideways only as far as keeps both sides' art on the screen
        cx = vx + vw / 2
        local l, r = cx + (span[1] - m - fx) * S, cx + (span[2] + m - fx) * S
        if r - l >= vw then
          cx = cx + (vx + vw / 2) - (l + r) / 2   -- wider than the screen: centred on the art
        elseif l < vx then
          cx = cx + (vx - l)
        elseif r > vx + vw then
          cx = cx - (r - vx - vw)
        end
        cx = round2(cx)
      else
        -- wider: the UI keeps the Renderer's scale, docked to the bottom; the scene grows about
        -- the text box's line up to the top, or out to the sides, whichever it reaches first
        fit.grow = nil
        uby = bottom - cur.h * bsy
        cy = uby + fy * bsy
        local fH = (cy - top) / (fy * bsy)
        local fW = vw / (cur.w * bsx)
        local f = math.max(1, math.min(fH, fW))
        S, Sy = bsx * f, bsy * f
      end
      sceneBox = { vx, vy, vw, vh }
      uiBox = clipRect(ubx, uby, cur.w * U, cur.h * Uy, sceneBox)
    end
    -- the UI over the scene, in the scene's canvas pixels: shrunk about the line by the
    -- ratio of their scales; the enemy's HP box moved with the top band; the screen's top
    fit.uiK = U / S
    fit.uiTopDy = dyTop
    fit.topY = filling and math.min(0, round2(fy - (cy - top) / Sy)) or 0
    self.stats.topY, self.stats.uiK = fit.topY, fit.uiK
    local z, lift = 1, 0
    if fitted then
      z = fitStep(cur)
      lift = fitLift(z) + fit.extra
    end
    local moved = z ~= 1 or lift ~= 0 or filling
    local zb = 1 - (1 - z) * fit.parallax
    -- canvas pixels -> screen, zoomed by k about the focus and raised by `up` canvas pixels
    local function zoomed(k, up)
      return cx - fx * k * S, cy - (fy * k + up) * Sy, S * k, Sy * k
    end
    local sx0, sy0, ssx, ssy = zoomed(z, lift)
    -- the far wallpaper does not rise: its rows below the text box's top are not scenery
    -- (the cart hides them), so the text box's line stays its bottom edge
    local bkx, bky, bksx, bksy = zoomed(zb, 0)
    -- the screen rect a wallpaper covers (canvas size at scale 1)
    local cover = filling and sceneBox or { bx, by, cur.w * bsx, cur.h * bsy }
    -- the stacked UI in two bands (one when a draw crosses the split this frame)
    local split = fit.split
    -- the HP box drawn just above the highest art when the scene stops short of the top (the
    -- fit still sees it at the top: nothing it places comes up under it)
    local dyDraw = dyTop
    if stacked and fit.artTop then
      local artY = cy + (fit.artTop - fy) * Sy
      local boxBottom = fit.ui.enemy[4] + 4
      local want = (artY - (fit.hugGap * Sy) - boxBottom * Uy - uby) / Uy
      dyDraw = math.max(dyTop, math.min(0, round2(want)))
    end
    -- centred when nothing is below: the sky over the HP box and the ground under the text
    -- box made equal (halving the difference each frame)
    if stacked and view.bottom == nil then
      local gapTop = uby + dyDraw * Uy - top
      fit.raise = round2(math.max(0, (gapTop + (fit.raise or 0)) / 2))
    else
      fit.raise = 0
    end
    local banded = stacked and dyDraw < 0 and not cur.uiStraddle
    local topBy = uby + dyDraw * Uy
    local topBox, lowBox
    if banded then
      topBox = clipRect(ubx, topBy, cur.w * U, split * Uy, sceneBox)
      lowBox = clipRect(ubx, uby + split * Uy, cur.w * U, (cur.h - split) * Uy, sceneBox)
    end
    local k = filling and U ~= math.floor(U) and math.ceil(U) or 1
    self.stats.lift = lift
    self.stats.fill = S / bsx
    self.stats.uiScale = U
    self.stats.uiTopDy = banded and dyDraw or 0
    local function scissor(b)
      if b then real.setScissor(b[1], b[2], b[3], b[4]) else real.setScissor() end
    end
    local inScene = true
    if not moved then blit(cur.base) else blit(cur.base, sx0, sy0, ssx, ssy, sceneBox) end
    real.push("all")
    for _, item in ipairs(cur.items) do
      if item.kind == "seam" then
        if item.name == "ui" then inScene = false end
      elseif item.kind == "hd" or item.kind == "backdrop" or item.kind == "stage" or item.kind == "band" then
        scissor(inScene and sceneBox or uiBox)
        if item.kind == "backdrop" then
          if inScene then
            drawBackdrop(item.rec, cover[3], cover[4], bkx, bky, bksx, bksy, cover[1], cover[2], 1, 1)
          else
            drawBackdrop(item.rec, cur.w, cur.h, ubx, uby, U, Uy, ubx, uby, U, Uy)
          end
        elseif item.kind == "band" then
          if inScene then
            -- zoomed with the scene but not raised: its bottom stays on the text box's line,
            -- where the cart puts it
            local gx, gy = zoomed(z, 0)
            drawBackdrop(item.rec, cover[3], cover[4], gx, gy, ssx, ssy, cover[1], cover[2], 1, 1, "clampzero")
          else
            drawBackdrop(item.rec, cur.w, cur.h, ubx, uby, U, Uy, ubx, uby, U, Uy, "clampzero")
          end
        elseif item.kind == "stage" then
          local d = (fitted and cur.shift[item.side]) or 0
          local dy = (fitted and item.side == "player" and cur.shift.playerY) or 0
          imageDraw(item.rec, sx0 + d * ssx, sy0 + dy * ssy, ssx, ssy)
        elseif inScene then
          -- a battler drawn by the battle itself moves with its side's shift; one drawn by a
          -- move animation is already where the shifted coordinates put it
          local spec = item.rec.spec
          local side = spec.side
          local d = (fitted and side and not item.rec.inAnim and cur.shift[side]) or 0
          -- (a trainer is anchored to the text box instead: pinBottom below)
          local dy = (fitted and side == "player" and not item.rec.inAnim and not spec.trainer
            and cur.shift.playerY) or 0
          -- the Pokemon itself, not its trainer, stands raised above a small back's pad
          if fitted and side == "player" and not item.rec.inAnim and not spec.trainer then
            dy = dy - (cur.shift.playerRaise or 0)
          end
          -- pinBottom (canvas y): the text box's line, under the unzoomed mapping
          local pin = fitted and spec.pinBottom and (cy + (spec.pinBottom - fy) * Sy) or nil
          hdDraw(item.rec, sx0 + d * ssx, sy0 + dy * ssy, ssx, ssy, pin)
        elseif banded and item.rec.ty + item.rec.y * item.rec.tsy < split then
          scissor(topBox)
          hdDraw(item.rec, ubx, topBy, U, Uy)
        else
          if banded then scissor(lowBox) end
          hdDraw(item.rec, ubx, uby, U, Uy)
        end
      else
        real.setScissor()
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "premultiplied")
        if item.screen and filling then
          -- a whole-scene draw (a move's background, a flash) or a whole-UI one (a fade) covers
          -- the whole screen
          local v = sceneBox
          local sc = math.max(v[3] / cur.w, v[4] / cur.h)
          blit(item.canvas, v[1] + (v[3] - cur.w * sc) / 2, v[2] + (v[4] - cur.h * sc) / 2, sc, sc, sceneBox)
        elseif inScene and not item.screen and moved then
          blit(item.canvas, sx0, sy0, ssx, ssy, sceneBox)
        elseif not inScene and filling then
          local c, kk = item.canvas, 1
          if k > 1 then c, kk = sharpen(item.canvas, cur.w, cur.h, k) end
          if banded then
            blit(c, ubx, topBy, U / kk, Uy / kk, topBox, kk)
            blit(c, ubx, uby, U / kk, Uy / kk, lowBox, kk)
          else
            blit(c, ubx, uby, U / kk, Uy / kk, uiBox, kk)
          end
        else
          blit(item.canvas)
        end
        real.setBlendMode("alpha", "alphamultiply")
      end
    end
    real.pop()
    restoreShaders()
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
      if item.kind == "hd" or item.kind == "backdrop" or item.kind == "stage" or item.kind == "band" then
        local rec = item.rec
        real.push()
        real.translate(rec.tx, rec.ty)
        real.scale(rec.tsx, rec.tsy)
        real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
        useShader(rec)
        real.setBlendMode(rec.blend[1], rec.blend[2])
        if rec.quad then
          real.draw(rec.image, rec.quad, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
        else
          real.draw(rec.image, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
        end
        real.pop()
      elseif item.kind == "layer" then
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "premultiplied")
        real.draw(item.canvas, 0, 0)
        real.setBlendMode("alpha", "alphamultiply")
      end
    end
    real.pop()
    restoreShaders()
    -- flattened in the middle of a pass: the engine carries on drawing into its own canvas
    if midPass then real.setCanvas(cur.base) end
    self.stats.flattened = self.stats.flattened + 1
  end

  --- The frame is over: anything still waiting for a blit that never came is dropped
  --- (it was flattened when that could be known in time).
  function self.endFrame()
    self.done = {}
    -- frames since a battle was last fitted: a gap means the next battle starts afresh
    self.fit.idle = self.fit.idle + 1
  end

  return self
end

return HD
