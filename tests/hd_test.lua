-- Headless checks of src/hd.lua with a fake love.graphics. Run from the mod root:
--   luajit tests/hd_test.lua
local HD = dofile("src/hd.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
-- layout values are rounded to two decimals
local function approx(a, b) return type(a) == "number" and math.abs(a - b) < 0.05 end

-- ------------------------------------------------------------- fake graphics
local function canvas(name, w, h)
  return { name = name, getWidth = function() return w end, getHeight = function() return h end,
           setFilter = function() end }
end
local function quad(x, y, w, h)
  return { getViewport = function() return x, y, w, h end }
end

local function fakeGraphics()
  local G = { log = {} }
  local st = { canvas = nil, tx = 0, ty = 0, sx = 1, sy = 1, color = { 1, 1, 1, 1 }, shader = nil,
               blend = { "alpha", "alphamultiply" } }
  local stack = {}
  local made = 0
  function G.setCanvas(c) st.canvas = type(c) == "table" and c[1] and not c.getWidth and c[1] or c end
  function G.getCanvas() return st.canvas end
  function G.push(kind)
    stack[#stack + 1] = { all = kind == "all", canvas = st.canvas, tx = st.tx, ty = st.ty, sx = st.sx, sy = st.sy,
                          color = { unpack(st.color) }, shader = st.shader, blend = { unpack(st.blend) } }
  end
  function G.pop()
    local s = table.remove(stack)
    st.tx, st.ty, st.sx, st.sy = s.tx, s.ty, s.sx, s.sy
    if s.all then st.canvas, st.color, st.shader, st.blend = s.canvas, s.color, s.shader, s.blend end
  end
  function G.origin() st.tx, st.ty, st.sx, st.sy = 0, 0, 1, 1 end
  function G.translate(x, y) st.tx, st.ty = st.tx + x * st.sx, st.ty + y * st.sy end
  function G.scale(x, y) st.sx, st.sy = st.sx * x, st.sy * (y or x) end
  function G.transformPoint(x, y) return st.tx + x * st.sx, st.ty + y * st.sy end
  function G.getColor() return unpack(st.color) end
  function G.setColor(r, g, b, a) st.color = { r, g, b, a or 1 } end
  function G.getShader() return st.shader end
  function G.setShader(s) st.shader = s end
  function G.getBlendMode() return st.blend[1], st.blend[2] end
  function G.setBlendMode(a, b) st.blend = { a, b } end
  function G.setScissor(x, y, w, h) st.scissor = x and { x, y, w, h } or nil end
  function G.clear() G.log[#G.log + 1] = { op = "clear", target = st.canvas } end
  function G.newCanvas(w, h) made = made + 1; return canvas("layer" .. made, w, h) end
  -- shaders share one method table, as LOVE's do; u: each uniform's first value as last sent
  local shaderMethods = {}
  function shaderMethods.send(sh, name, v) sh.u[name] = v end
  function G.newShader(src) return setmetatable({ src = src, u = {} }, { __index = shaderMethods }) end
  function G.draw(img, ...)
    local u
    if st.shader then
      u = {}
      for k, v in pairs(st.shader.u) do u[k] = v end
    end
    -- vp: a quad's viewport as drawn (a quad may be reused for the next draw)
    local q = ...
    local vp = type(q) == "table" and q.getViewport and { q:getViewport() } or nil
    G.log[#G.log + 1] = { op = "draw", target = st.canvas, image = img, args = { ... },
                          blend = st.blend[2], mode = st.blend[1], uniforms = u, vp = vp,
                          scissor = st.scissor, shader = st.shader, tx = st.tx, sx = st.sx }
  end
  function G.rectangle(mode, x, y, w, h)
    G.log[#G.log + 1] = { op = "rect", target = st.canvas, args = { mode, x, y, w, h } }
  end
  function G.newQuad(x, y, w, h, sw, sh)
    local q = quad(x, y, w, h)
    function q:setViewport(nx, ny, nw, nh) x, y, w, h = nx, ny, nw, nh end
    q.getViewport = function() return x, y, w, h end
    return q
  end
  function G.print() G.log[#G.log + 1] = { op = "print", target = st.canvas } end
  G.state = st
  return G
end

-- a card's draws past the blit, to the window (its edges run out, its blurred backdrop and the
-- backdrop's rim): the canvases it made, drawn as they are
local function cardDraws(G)
  local out = {}
  for _, e in ipairs(G.log) do
    if e.op == "draw" and e.scissor and type(e.image) == "table"
        and tostring(e.image.name):match("^layer") then
      local a = e.args
      out[#out + 1] = { canvas = e.image, bx = a[1], by = a[2], sx = a[4], sy = a[5], box = e.scissor,
                        u = e.uniforms or {} }
    end
  end
  return out
end

local function drawsTo(G, target)
  local n = 0
  for _, e in ipairs(G.log) do if e.target == target and e.op ~= "clear" then n = n + 1 end end
  return n
end

-- ------------------------------------------------------- a battle-like frame
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  check(hd.install() == true, "installs over the fake graphics")
  local base = canvas("ui", 240, 160)
  local monLow, monHD = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  local monQuad = quad(0, 0, 94, 94)
  hd.tag(monLow, { texture = monHD, quad = monQuad, pivot = { 47, 90 }, scale = 0.5 })

  -- outside a pass a tagged image is just drawn
  G.setCanvas(base)
  G.draw(monLow, 10, 10)
  check(G.log[#G.log].image == monLow, "outside a pass a tagged image draws normally")
  G.log = {}

  check(hd.beginPass("battle", base), "a pass starts")
  G.draw(canvas("bg", 240, 160), 0, 0)                 -- background
  G.push()
  G.translate(5, 3)
  G.setColor(1, 0.5, 0.5, 1)
  G.draw(monLow, 100, 50, 0, 1, 1, 32, 32)             -- the tagged mon
  G.pop()
  G.rectangle()                                        -- a particle / HUD after it
  G.print()
  hd.endPass()

  check(drawsTo(G, base) == 1, "only the background reaches the base canvas")
  local layer = nil
  for _, e in ipairs(G.log) do if e.op == "rect" then layer = e.target end end
  check(layer ~= nil and layer ~= base, "what came after the mon went to a layer of its own")
  check(drawsTo(G, layer) == 2, "...the rectangle and the text")
  local drewMon = false
  for _, e in ipairs(G.log) do if e.image == monLow then drewMon = true end end
  check(not drewMon, "the tagged mon was not drawn into any canvas")

  -- composite: the Renderer blits the base with bx=10, by=20, scale 4
  G.log = {}
  local blits = {}
  local ok = hd.composite(base, function(c) blits[#blits + 1] = c; G.draw(c, 10, 20, 0, 4, 4) end,
    10, 20, 4, 4, { 0, 0, 960, 640 })
  check(ok, "the base blit is composited")
  check(blits[1] == base and blits[2] == layer and #blits == 2, "base, then the layer")
  local hdDraw
  for _, e in ipairs(G.log) do if e.image == monHD then hdDraw = e end end
  check(hdDraw ~= nil, "the mon is drawn from its full-resolution texture")
  local a = hdDraw and hdDraw.args or {}
  check(a[1] == monQuad, "...with its frame quad")
  check(near(a[2], 10 + (5 + 100) * 4) and near(a[3], 20 + (3 + 50) * 4),
    "...where the low-res pic's (32, 32) was, in window pixels (" .. tostring(a[2]) .. ", " .. tostring(a[3]) .. ")")
  check(near(a[5], 2) and near(a[6], 2), "...at scale 0.5 x the blit's 4 (" .. tostring(a[5]) .. ")")
  check(a[7] == 47 and a[8] == 90, "...around its own pivot")
  local layerBlit
  for _, e in ipairs(G.log) do if e.image == layer then layerBlit = e end end
  check(layerBlit and layerBlit.blend == "premultiplied", "a layer is blitted premultiplied")
  hd.endFrame()
  check(not hd.composite(base, function() end, 0, 0, 1, 1), "after the frame there is nothing to composite")
end

-- ------------------------------------- consecutive tags merge; the cap holds
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("world", 400, 240)
  local sheet = canvas("sheet", 64, 1152)
  hd.tag(sheet, { scale = 1, anchor = "feet" })
  G.setCanvas(base)
  hd.caps.field = 2
  hd.beginPass("field", base)
  local q = quad(0, 0, 32, 32)
  G.draw(sheet, q, 10, 10)
  G.draw(sheet, q, 50, 10)          -- straight after: same split
  G.rectangle()                     -- opens layer 1
  G.draw(sheet, q, 90, 10)          -- split 2
  G.rectangle()                     -- opens layer 2
  G.draw(sheet, q, 130, 10)         -- over the cap: drawn low-res into layer 2
  local cur = hd.endPass()
  local hdCount, layers = 0, 0
  for _, it in ipairs(cur.items) do
    if it.kind == "hd" then hdCount = hdCount + 1 else layers = layers + 1 end
  end
  check(hdCount == 3, "three sprites recorded (two merged, one more), got " .. hdCount)
  check(layers == 2, "two layers, got " .. layers)
  check(hd.stats.overCap == 1, "the fourth went over the cap")
  local low = 0
  for _, e in ipairs(G.log) do if e.image == sheet then low = low + 1 end end
  check(low == 1, "...and was drawn the low-res way")
  -- feet anchor: a 32x32 quad drawn at (10, 10) has its feet at (26, 42)
  G.log = {}
  hd.composite(base, function(c) G.draw(c, 0, 0) end, 0, 0, 3, 3, nil)
  local first
  for _, e in ipairs(G.log) do if e.image == sheet then first = first or e end end
  check(first and near(first.args[2], 26 * 3) and near(first.args[3], 42 * 3)
    and first.args[7] == 16 and first.args[8] == 32, "a feet-anchored sprite stands where it stood")
end

-- ------------- a direct pass (Gen 2's field, drawn at window resolution): sized in place
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local sheet = canvas("sheet", 32, 576)
  local other = canvas("other", 16, 16)
  hd.tag(sheet, { scale = 1.5, lowPivot = { 16, 28 } })
  local q = quad(0, 0, 32, 32)
  check(hd.beginDirect("field") == true, "a direct pass starts")
  check(hd.beginDirect("field") == false, "...a nested one does not")
  G.log = {}
  G.draw(sheet, q, 10, 20)
  G.draw(other, 40, 40)
  hd.endDirect()
  local e = G.log[1]
  -- its pivot (16, 28) stood at (26, 48): the frame drawn 1.5x about it, there
  check(e and e.image == sheet and near(e.args[2], 26) and near(e.args[3], 48) and near(e.args[5], 1.5)
    and e.args[7] == 16 and e.args[8] == 28, "a tagged sheet is drawn at its size about its pivot")
  check(G.log[2] and G.log[2].image == other and G.log[2].args[1] == 40, "anything else is drawn as it was")
  check(hd.stats.direct == 1 and hd.cur == nil and next(hd.done) == nil, "nothing is recorded")
  G.log = {}
  G.draw(sheet, q, 10, 20)
  check(G.log[1] and near(G.log[1].args[2], 10) and G.log[1].args[5] == nil, "after it ends, drawn as it was")
  hd.enabled.field = false
  check(hd.beginDirect("field") == false, "Field HD off: no direct pass")
  hd.enabled.field = true
  hd.fail("test")
  check(hd.beginDirect("field") == false, "...nor after a failure")
end

-- ---------------- flip: a full-resolution frame mirrored about its pivot (a mirrored stand-in)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 160, 144)
  local pic, atlas = canvas("pic", 56, 56), canvas("atlas", 1024, 1024)
  local frame = quad(100, 0, 80, 90)
  hd.tag(pic, { texture = atlas, quad = frame, pivot = { 30, 88 }, lowPivot = { 28, 56 }, scale = 0.5, flip = true })
  local function drawn(flip)
    hd.tagOf(pic).flip = flip
    G.setCanvas(base)
    hd.beginPass("battle", base)
    G.draw(pic, 96, 0)
    hd.endPass()
    G.log = {}
    hd.composite(base, function() end, 0, 0, 4, 4, { 0, 0, 640, 576 })
    hd.endFrame()
    for _, e in ipairs(G.log) do if e.image == atlas then return e end end
  end
  local e = drawn(true)
  check(e and e.args[1] == frame and near(e.args[2], (96 + 28) * 4) and near(e.args[3], 56 * 4)
    and near(e.args[5], -2) and near(e.args[6], 2) and e.args[7] == 30 and e.args[8] == 88,
    "a flipped frame is drawn mirrored about its pivot, where the stand-in's pivot was")
  e = drawn(nil)
  check(e and near(e.args[5], 2), "...and unflipped as it is")
  -- in place (a direct pass, or past a pass's cap): mirrored the same
  hd.tagOf(pic).flip = true
  hd.beginDirect("battle")
  G.log = {}
  G.draw(pic, 10, 20)
  hd.endDirect()
  check(G.log[1] and G.log[1].image == atlas and near(G.log[1].args[5], -0.5) and near(G.log[1].args[6], 0.5),
    "...drawn in place, mirrored too")
end

-- ------ shades: a stand-in in the Game Boy's shades (Red's Pokedex, Gold's DMG palette)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 160, 144)
  local pic, atlas = canvas("pic", 56, 56), canvas("atlas", 1024, 1024)
  local frame = quad(100, 0, 80, 90)
  local shades, palette = G.newShader("shades"), G.newShader("palette")
  hd.tag(pic, { texture = atlas, quad = frame, pivot = { 40, 90 }, lowPivot = { 28, 56 }, scale = 0.5,
                shades = shades })
  -- a dex pass, the pic drawn mirrored as Red's Pokedex entry draws it; composited at 4.5x
  G.setCanvas(base)
  hd.beginPass("dex", base)
  G.draw(pic, 8 + 56, 8, 0, -1, 1)
  hd.endPass()
  G.log = {}
  local blits = {}
  hd.composite(base, function(c, ...) blits[#blits + 1] = { c = c, ... } end, 0, 0, 4.5, 4.5, nil)
  local e
  for _, x in ipairs(G.log) do if x.image == atlas then e = x end end
  -- k = 5: the pivot stood at (64 - 28, 8 + 56) = (36, 64), x5 in the shaded canvas
  check(e and e.target and e.target ~= base and e.shader == shades and near(e.args[2], 36 * 5)
    and near(e.args[3], 64 * 5) and near(e.args[5], -2.5) and near(e.args[6], 2.5),
    "a shaded frame is drawn through its shades shader, mirrored, into a canvas 5x the pass's")
  local b = blits[#blits]
  check(b and e and b.c == e.target and near(b[3], 0.9) and near(b[4], 0.9) and b[6] == 5,
    "...which goes through the game's blit at 1/5 the scale, its zones 5x (zk)")
  check(hd.stats.shaded == 1, "...counted")
  hd.endFrame()

  -- in place (Gold: a direct pass, under the palette shader the stand-in is drawn with)
  hd.beginDirect("dex")
  G.log = {}
  G.setShader(palette)
  G.draw(pic, 10, 20)
  G.setShader()
  hd.endDirect()
  local into, out
  for _, x in ipairs(G.log) do
    if x.image == atlas then into = x elseif x.op == "draw" and x.target == base then out = x end
  end
  check(into and into.target and into.shader == shades and into.mode == "replace" and into.args[1] == frame
    and near(into.args[2], 0) and near(into.args[3], 0), "in place: the frame is shaded 1:1 into a canvas")
  check(out and into and out.image == into.target and out.shader == palette and near(out.args[2], 38)
    and near(out.args[3], 76) and near(out.args[5], 0.5) and out.args[7] == 40 and out.args[8] == 90
    and out.vp and out.vp[3] == 80 and out.vp[4] == 90,
    "...then drawn at its size about its pivot, under the palette shader")
  -- without shades, under a shader: the stand-in (its colours would be wrong)
  hd.tagOf(pic).shades = nil
  hd.beginDirect("dex")
  G.log = {}
  G.setShader(palette)
  G.draw(pic, 10, 20)
  G.setShader()
  hd.endDirect()
  check(#G.log == 1 and G.log[1].image == pic, "...a full-colour frame under a shader: the stand-in")
  local api = assert(loadfile("src/api.lua"))
  local mod = {}
  api()(mod, hd, { active = true })
  check(mod.exports.features.shades == true, "features.shades is advertised")
  -- uiMap(): the UI's placement only while the last UI canvas blit was WoobleView's
  hd.uiLive = false
  check(mod.exports.features.uiMap == true and mod.exports.uiMap() == nil,
    "features.uiMap is advertised; nil while the Renderer blits the UI itself")
  hd.uiLive = true
  check(mod.exports.uiMap() == hd.uiMap, "...and the live map once WoobleView placed it")
  hd.uiLive = false
end

-- ---------------------- a quad of its own stands on its own pivot (quadPivots)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("world", 400, 240)
  local sheet = canvas("sheet", 64, 64)
  local full, short = quad(0, 0, 32, 40), quad(0, 0, 32, 24)
  local spec = { scale = 2, lowPivot = { 16, 30 }, quadPivots = {} }
  hd.tag(sheet, spec)
  spec.quadPivots[short] = { 16, 20 } -- added after tagging: read at draw time
  G.setCanvas(base)
  hd.beginPass("field", base)
  G.draw(sheet, full, 10, 10)
  G.draw(sheet, short, 50, 10)
  hd.endPass()
  G.log = {}
  hd.composite(base, function(c) G.draw(c, 0, 0) end, 0, 0, 3, 3, nil)
  local d = {}
  for _, e in ipairs(G.log) do if e.image == sheet then d[#d + 1] = e end end
  check(#d == 2, "both sprites drawn")
  check(d[1] and near(d[1].args[2], 26 * 3) and near(d[1].args[3], 40 * 3)
    and d[1].args[7] == 16 and d[1].args[8] == 30, "the full quad scales about lowPivot")
  check(d[2] and near(d[2].args[2], 66 * 3) and near(d[2].args[3], 30 * 3)
    and d[2].args[7] == 16 and d[2].args[8] == 20, "the short quad scales about its own pivot")
  check(d[1] and near(d[1].args[5], 2 * 3), "...both at the spec's scale")
end

-- ------- a quad with its own scale (a slice already drawn at its final size)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("world", 400, 240)
  local feet = canvas("feet", 64, 64)
  local slice = quad(4, 8, 10, 6)
  hd.tag(feet, { scale = 1.5, anchor = "feet", quadPivots = { [slice] = { 0, 0, 1 } } })
  G.setCanvas(base)
  hd.beginPass("field", base)
  G.draw(feet, slice, 20, 30, 0, 2, -2)
  hd.endPass()
  G.log = {}
  hd.composite(base, function(c) G.draw(c, 0, 0) end, 0, 0, 3, 3, nil)
  local e
  for _, x in ipairs(G.log) do if x.image == feet then e = x end end
  check(e and near(e.args[2], 20 * 3) and near(e.args[3], 30 * 3), "a scale-1 slice lands exactly where it was drawn")
  check(e and near(e.args[5], 2 * 3) and near(e.args[6], -2 * 3), "...at its own size, flip kept (not the spec's 1.5)")
  local api = assert(loadfile("src/api.lua"))
  local mod = {}
  api()(mod, hd, { active = true })
  check(mod.exports.features and mod.exports.features.quadPivots == true, "features.quadPivots is advertised")
end

-- ------- `frame`: a piece of a frame (a reflection's slices) shows the grown frame through its own rectangle
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("world", 400, 240)
  local sheet = canvas("npc", 32, 288)
  hd.tag(sheet, { scale = 0.75, anchor = "feet", frame = { 32, 32 } })
  -- one draw composited at 2x; returns its log entry and the quad's viewport as drawn
  local function one(draw)
    G.setCanvas(base)
    hd.beginPass("field", base)
    draw()
    hd.endPass()
    G.log = {}
    hd.composite(base, function(c) G.draw(c, 0, 0) end, 0, 0, 2, 2, nil)
    for _, e in ipairs(G.log) do
      if e.image == sheet then return e, { e.args[1]:getViewport() } end
    end
  end
  -- the window rectangle a draw covers: x0, x1, y0, y1
  local function rect(e, v)
    local X, Y, ssx, ssy, hx, hy = e.args[2], e.args[3], e.args[5], e.args[6], e.args[7], e.args[8]
    local xa, xb = X - hx * ssx, X + (v[3] - hx) * ssx
    local ya, yb = Y - hy * ssy, Y + (v[4] - hy) * ssy
    return math.min(xa, xb), math.max(xa, xb), math.min(ya, yb), math.max(ya, yb)
  end
  local e, v = one(function() G.draw(sheet, quad(0, 64, 32, 32), 100, 50) end)
  check(e and near(e.args[2], 116 * 2) and near(e.args[3], 82 * 2) and e.args[7] == 16 and e.args[8] == 32,
    "a whole frame: about its feet, as without `frame`")
  -- its piece x 8-16, rows 20-32, drawn upside down at (108, 90): it covers x 108-116, y 78-90
  e, v = one(function() G.draw(sheet, quad(8, 64 + 20, 8, 12), 108, 90, 0, 1, -1) end)
  local x0, x1, y0, y1 = rect(e, v)
  check(near(x0, 216) and near(x1, 232) and near(y0, 156) and near(y1, 180),
    ("a piece covers just its own rectangle (%.2f-%.2f, %.2f-%.2f)"):format(x0, x1, y0, y1))
  -- ...showing the frame grown about its feet (16, 96 in the sheet): x 16 - 8/0.75 to 16, rows 96 - 12/0.75 to 96
  check(near(v[1], 16 - 8 / 0.75) and near(v[3], 8 / 0.75) and near(v[2], 96 - 12 / 0.75) and near(v[4], 12 / 0.75),
    ("...the grown frame's pixels there (%.2f, %.2f, %.2f, %.2f)"):format(v[1], v[2], v[3], v[4]))
  check(near(e.args[5], 0.75 * 2) and near(e.args[6], -0.75 * 2), "...flipped, at 0.75")
  -- the next 1-px column (x 9, at 109) covers 109-110: the columns meet
  e, v = one(function() G.draw(sheet, quad(9, 64 + 20, 1, 12), 109, 90, 0, 1, -1) end)
  x0, x1 = rect(e, v)
  check(near(x0, 218) and near(x1, 220), ("...and a column covers its own pixel (%.2f-%.2f)"):format(x0, x1))
  local api = assert(loadfile("src/api.lua"))
  local mod = {}
  api()(mod, hd, { active = true })
  check(mod.exports.features.frame == true, "features.frame is advertised")
end

-- ------- one quad, moved between draws (a reflection's slices): each drawn through its own viewport
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("world", 400, 240)
  local sheet = canvas("npc", 64, 64)
  hd.tag(sheet, { scale = 0.75, anchor = "feet" })
  G.setCanvas(base)
  hd.beginPass("field", base)
  local q = G.newQuad(0, 0, 1, 1, 64, 64)
  q:setViewport(0, 0, 16, 32); G.draw(sheet, q, 10, 10)
  G.rectangle()
  q:setViewport(16, 0, 16, 32); G.draw(sheet, q, 50, 10)
  q:setViewport(0, 0, 3, 3)                     -- moved again after the last draw
  hd.endPass()
  G.log = {}
  hd.composite(base, function(c) G.draw(c, 0, 0) end, 0, 0, 2, 2, nil)
  local d = {}
  for _, e in ipairs(G.log) do
    if e.image == sheet then d[#d + 1] = table.concat({ e.args[1]:getViewport() }, ",") end
  end
  check(#d == 2 and d[1] == "0,0,16,32" and d[2] == "16,0,16,32",
    "each draw through the viewport it was drawn with (" .. table.concat(d, " / ") .. ")")
  local sq = quad(0, 0, 32, 32)
  hd.beginPass("field", base)
  G.draw(sheet, sq, 10, 10)
  hd.endPass()
  G.log = {}
  hd.composite(base, function(c) G.draw(c, 0, 0) end, 0, 0, 2, 2, nil)
  local e
  for _, x in ipairs(G.log) do if x.image == sheet then e = x end end
  check(e and e.args[1] == sq, "an unmoved quad is drawn through itself")
end

-- -------------------------------- setCanvas and pop go to the current layer
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base, temp = canvas("ui", 240, 160), canvas("temp", 64, 64)
  local pic = canvas("pic", 64, 64)
  hd.tag(pic, {})
  G.setCanvas(base)
  hd.beginPass("battle", base)
  G.push("all")                     -- engine code saves the state with the base canvas...
  G.draw(pic, 0, 0)
  G.rectangle()                     -- (opens the layer)
  local layer = G.getCanvas()
  G.pop()                           -- ...and its pop would return to the base
  check(G.getCanvas() == layer, "pop back to the base canvas lands on the current layer")
  G.setCanvas(temp)
  G.rectangle()
  G.setCanvas(base)                 -- a temp canvas, then "back to" the base
  check(G.getCanvas() == layer, "setCanvas(base) lands on the current layer")
  G.setCanvas({ base, stencil = true })
  check(G.getCanvas() == layer, "...in the table form too")
  hd.endPass()
  G.setCanvas(base)
  check(G.getCanvas() == base, "after the pass setCanvas is untouched")
end

-- --------------------------------------------- flatten puts it all back low-res
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("world", 400, 240)
  local pic = canvas("pic", 64, 64)
  hd.tag(pic, { scale = 0.5 })
  G.setCanvas(base)
  hd.beginPass("field", base)
  G.draw(pic, 20, 30)
  G.rectangle()
  local layer = hd.cur.current
  check(layer ~= base and G.getCanvas() == base,
    "a field layer is the target, but getCanvas answers the field's own canvas")
  hd.flatten(hd.cur)                 -- a weather pass is about to read the world canvas
  check(G.getCanvas() == base, "after a mid-pass flatten the engine draws into its own canvas again")
  local sawPic, sawLayer = false, false
  for _, e in ipairs(G.log) do
    if e.target == base and e.image == pic then sawPic = true end
    if e.target == base and e.image == layer then sawLayer = true end
  end
  check(sawPic and sawLayer, "the sprite (low-res) and the layer were drawn into the base")
  check(not hd.capturing(), "...and the pass is over")
  check(not hd.composite(base, function() end, 0, 0, 1, 1), "...with nothing left to composite")
end

-- ---------------------------------------- a disabled pass captures nothing
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.enabled.field = false
  check(hd.beginPass("field", canvas("w", 10, 10)) == false, "a disabled pass does not start")
  hd.uninstall()
  check(hd.installed == false, "uninstall restores the graphics functions")
end

-- ------------------------------------------------- the cap: defaults and the API
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  check(hd.caps.field == 12 and hd.caps.battle == 8, "default caps: 12 layers in the field, 8 in battle")
  local mod = {}
  local state = { active = true }
  local chunk = assert(loadfile("src/api.lua"))
  chunk()(mod, hd, state)
  local ex = mod.exports
  check(ex.cap("field") == 12, "cap(pass) reads it")
  check(ex.setCap("field", 16) == 16 and hd.caps.field == 16, "setCap changes it")
  check(ex.setCap("field", 500) == 32, "...up to 32")
  check(ex.setCap("field", 0) == 1, "...and at least 1")
  check(ex.setCap("nonsense", 5) == nil and hd.caps.nonsense == nil, "an unknown pass is ignored")
  check(ex.setCap("field", "x") == 1, "a non-number changes nothing")
end

-- ----------------------------------- a Pokedex frame: top-left and scaled draws
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  check(hd.enabled.dex == true and hd.caps.dex == 8, "the dex pass is on by default, cap 8")
  local base = canvas("ui", 240, 160)
  local pic, page = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  local frame = quad(0, 0, 96, 96)
  -- a 96 px frame fitted into the 64 px box: its bottom-centre on the box's bottom-centre
  hd.tag(pic, { texture = page, quad = frame, pivot = { 48, 96 }, lowPivot = { 32, 64 }, scale = 64 / 96 })
  G.setCanvas(base)
  check(hd.beginPass("dex", base), "a dex pass starts")
  G.draw(pic, 152, 24)                                  -- FR/LG entry page: top-left, no origin
  G.rectangle()
  G.setColor(0, 0, 0, 1)
  G.draw(pic, 40, 104, 0, 0.5, 0.5, 32, 32)             -- a size page: scaled, black
  hd.endPass()
  G.log = {}
  hd.composite(base, function(c) G.draw(c, 0, 0, 0, 4, 4) end, 0, 0, 4, 4)
  local draws = {}
  for _, e in ipairs(G.log) do if e.image == page then draws[#draws + 1] = e end end
  check(#draws == 2, "both Pokedex draws are drawn from the atlas page")
  local a = draws[1] and draws[1].args or {}
  check(near(a[2], (152 + 32) * 4) and near(a[3], (24 + 64) * 4),
    "a top-left draw: the frame's feet on the box's bottom-centre (" .. tostring(a[2]) .. ", " .. tostring(a[3]) .. ")")
  check(near(a[5], 4 * 64 / 96), "...fitted to the box at window resolution")
  local b = draws[2] and draws[2].args or {}
  check(near(b[2], (40 + 0) * 4) and near(b[3], (104 + 16) * 4), "a scaled draw maps the same point")
  check(near(b[5], 0.5 * 4 * 64 / 96), "...and keeps the draw's own scale")
end

-- ------------------------------------------------------------------ Battle Fit
-- one battle frame: wallpaper, a pad, a front sprite (tall or not), a move's flash,
-- the seam, the text box; composited at scale 4 with the blits recorded
local function fitFrame(G, hd, base, opts)
  opts = opts or {}
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(opts.wall, 0, 0)
  hd.drawStage(opts.pad, 0, 0)                        -- screen-sized, but part of the stage
  G.draw(opts.pic, 176, opts.picY or 40, 0, opts.picS or 1, opts.picS or 1, 32, 32)
  if opts.mine then G.draw(opts.mine, 64, 80, 0, 1, 1, 32, 32) end  -- the player's Pokemon
  if opts.flash then G.rectangle("fill", 0, 0, 240, 160) end
  G.rectangle("fill", 170, 30, 4, 4)                  -- a particle
  if opts.seam ~= false then hd.seam("ui") end
  G.rectangle("fill", 0, 112, 240, 48)                -- the text box
  hd.endPass()
  G.log = {}
  local blits = {}
  hd.composite(base, function(c, bx, by, sx, sy)
    blits[#blits + 1] = { canvas = c, bx = bx, by = by, sx = sx, sy = sy }
    G.draw(c, bx or 0, by or 0, 0, sx or 4, sy or 4)
  end, 0, 0, 4, 4, { 0, 0, 960, 640 }, opts.view)
  hd.endFrame()
  return blits
end

do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.45
  local base = canvas("ui", 240, 160)
  local wall, pad = canvas("wall", 256, 160), canvas("pad", 256, 160)
  local pic, page = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  local tall, short = quad(0, 0, 100, 200), quad(0, 0, 100, 60)
  local tallSpec = { texture = page, quad = tall, pivot = { 50, 200 }, lowPivot = { 32, 64 }, top = 52 }
  local shortSpec = { texture = page, quad = short, pivot = { 50, 60 }, lowPivot = { 32, 64 } }
  local frame = { wall = wall, pad = pad, pic = pic, flash = true }

  -- feet at (176, 72), art 148 px tall: its top at y = -76. Zoomed about the text box's top
  -- (y = 112) its feet would sink below feetMax (76), so the camera rises to hold them there:
  -- the zoom that brings the top to y = 2 is (76 - 2) / (72 + 76) = 0.5, the rise 16
  check(near(hd.fitZoom(-10), 110 / 122), "a little overflow: zoom about the text box, no rise")
  check(near(hd.fitLift(110 / 122), 0), "...and its feet stay above the HP box")
  hd.tag(pic, tallSpec)
  local blits = fitFrame(G, hd, base, frame)
  check(near(hd.stats.zoom, 0.5) and near(hd.stats.zoomTarget, 0.5),
    "a tall sprite's first frame starts at the zoom that fits it (" .. tostring(hd.stats.zoom) .. ")")
  check(near(hd.stats.lift, 16), "...with the camera raised 16 px (" .. tostring(hd.stats.lift) .. ")")
  -- zoom 0.5 about (120, 112), raised 16, at scale 4: origin (240, 4 * (56 - 16)), scale 2
  check(blits[1].canvas == base and near(blits[1].bx, 240) and near(blits[1].by, 160) and near(blits[1].sx, 2),
    "the base canvas is blitted zoomed about the text box's top centre, raised")
  local screens, zoomedLayers, plain = 0, 0, 0
  for i = 2, #blits do
    if blits[i].sx == nil then plain = plain + 1 else zoomedLayers = zoomedLayers + 1 end
  end
  check(zoomedLayers == 2, "the pad's and the particle's layers are zoomed, got " .. zoomedLayers)
  check(plain == 2, "the flash's layer and the UI's layer are not, got " .. plain)
  local d, w
  local walls = {}
  for _, e in ipairs(G.log) do
    if e.image == page then d = e end
    if e.image == wall then
      w = w or e
      walls[#walls + 1] = e
    end
  end
  check(d and near(d.args[2], 4 * (120 + (176 - 120) * 0.5)) and near(d.args[3], 4 * 76),
    "the sprite stands where its pad went, feet on y = 76 (" .. tostring(d and d.args[2]) .. ", "
    .. tostring(d and d.args[3]) .. ")")
  check(d and near(d.args[5], 2), "...at half its size")
  -- the wallpaper zooms less (parallax) and still covers the whole view
  local zb = 1 - 0.5 * hd.fit.parallax
  check(w and near(w.args[6], 4 * zb), "the wallpaper zooms less: " .. tostring(w and w.args[6]))
  -- its own rows down to the text box's line, then its ground band (rows 104-112) repeated
  -- to the view's bottom: no black cart rows, whatever the zoom
  local _, v0, uw, vh = w.args[1]:getViewport()
  check(w and w.args[2] <= 1e-9 and w.args[3] <= 1e-9 and near(w.args[2] + uw * w.args[5], 960)
    and near(v0 + vh, hd.fit.ground[2]), "...and is drawn across the whole view down to the line, wrapped")
  local last = walls[#walls]
  local _, lv, _, lh = last.args[1]:getViewport()
  check(#walls > 1 and lv == hd.fit.ground[1] and lh == hd.fit.ground[2] - hd.fit.ground[1]
    and last.args[3] + lh * last.args[6] >= 640 - 1e-6, "...then its ground band repeated to the view's bottom")
  for _ = 1, 3 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 0.5), "it holds while the sprite stays")

  -- the tall sprite leaves: no zoom back for holdFrames, then slowly
  hd.tag(pic, shortSpec)
  for _ = 1, hd.fit.holdFrames - 1 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoomTarget, 1) and near(hd.stats.zoom, 0.5), "a short sprite: the zoom waits first")
  fitFrame(G, hd, base, frame)
  local z1 = hd.stats.zoom
  check(z1 > 0.5 and z1 < 0.6, "...then eases back in slowly (" .. tostring(z1) .. ")")
  for _ = 1, 400 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 1), "...until it is back to 1")
  blits = fitFrame(G, hd, base, frame)
  check(blits[1].sx == nil, "at zoom 1 the base canvas is blitted as the Renderer asked")

  -- the tall one comes back: out quickly, not in one jump
  hd.tag(pic, tallSpec)
  fitFrame(G, hd, base, frame)
  local zOut = hd.stats.zoom
  check(zOut < 1 and zOut > 0.5, "a tall sprite in mid-battle: the zoom eases out (" .. tostring(zOut) .. ")")
  for _ = 1, 60 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 0.5), "...and reaches its fit within a second")

  -- a turn playing (a move swells the sprite for a moment, then it shrinks back): the camera
  -- stays pulled out, however long, and comes back in only once the battle waits again
  hd.setTurn(true)
  hd.tag(pic, shortSpec)
  for _ = 1, hd.fit.holdFrames * 4 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoomTarget, 1) and near(hd.stats.zoom, 0.5), "a turn playing: the zoom never comes back in")
  hd.tag(pic, tallSpec)
  fitFrame(G, hd, base, frame)
  hd.tag(pic, shortSpec)
  for _ = 1, 10 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 0.5), "...nor bounces as the sprite grows and shrinks again")
  hd.setTurn(false)
  for _ = 1, hd.fit.holdFrames - 1 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 0.5), "the menu: it waits holdFrames first")
  for _ = 1, 400 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 1), "...then eases back in")
  hd.setTurn(true)
  hd.tag(pic, tallSpec)
  fitFrame(G, hd, base, frame)
  check(hd.stats.zoom < 1, "a turn playing: a tall sprite still pulls the camera out at once")
  for _ = 1, 60 do fitFrame(G, hd, base, frame) end
  hd.setTurn(false)

  -- no UI seam (the post-catch Pokedex scene): nothing is zoomed
  blits = fitFrame(G, hd, base, { wall = wall, pad = pad, pic = pic, seam = false })
  local anyZoom = false
  for _, b in ipairs(blits) do if b.sx then anyZoom = true end end
  check(not anyZoom, "a frame with no UI seam is composited unzoomed")

  -- the floor: it never pulls back past zMin
  hd.fit.zMin = 0.6
  for _ = 1, 200 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 0.6), "the zoom never goes below zMin")
end

-- scissorOver: a screen box's scissor over its every pixel. LÖVE drops each number's fraction,
-- in units and again in pixels: on Android's 2.625 DPI a battle panel's box lost up to four
-- pixels at its right and bottom (a white line beside the panel)
do
  local G = fakeGraphics()
  local got
  G.setScissor = function(x, y, w, h) got = { x, y, w, h } end
  local hd = HD.new(G)
  hd.install()
  local function onDpi(d)
    local c = canvas("screen", 900, 400)
    c.getDPIScale = function() return d end
    G.setCanvas(c)
  end
  onDpi(2.625)
  hd.scissorOver(232.38, 12.19, 426.67, 384)
  -- the pixels LÖVE keeps: each number truncated, times the DPI, truncated
  local function px(v) return math.floor(math.floor(v) * 2.625) end
  local right, bottom = px(got[1]) + px(got[3]), px(got[2]) + px(got[4])
  check(px(got[1]) <= math.floor(232.38 * 2.625) and right >= math.ceil((232.38 + 426.67) * 2.625)
    and px(got[2]) <= math.floor(12.19 * 2.625) and bottom >= math.ceil((12.19 + 384) * 2.625),
    "scissorOver: covers the box's every pixel on a fractional DPI (" .. table.concat(got, ",") .. ")")
  -- a whole DPI: whole units out to the box's edges, nothing more
  onDpi(1)
  hd.scissorOver(610.5, 30, 1120, 1008)
  check(got[1] == 610 and got[2] == 30 and got[3] == 1121 and got[4] == 1008,
    "scissorOver: on a whole DPI, the box out to whole pixels (" .. table.concat(got, ",") .. ")")
end

-- World scale (Battle Scene: Overworld): with the 3D world drawn, each battler stands in it at
-- the world's scale: its art's real height (tag `height`, metres) over a tile's metres, times the
-- canvas px a tile spans where its feet stand (the scene's groundScale), over its art's frame px;
-- the camera alone makes room (no side shift, drop or raise); a giant held to its room at the
-- furthest zoom; measured at rest
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  check(hd.fit.worldMin == 0.1, "world: the smallest's share of the battle's height: 10%")
  hd.fit.worldMin = 0   -- (true to scale until the minimum's own checks below)
  check(hd.fit.heightKnee == 3 and hd.fit.heightMax == 5 and hd.fit.heightMaxFoe == 4.5 and hd.fit.widthMax == 6,
    "world: a soft ceiling from 3 m toward 5 m (a foe's 4.5 m), no art wider than 6 m")
  local heightMax, heightMaxFoe, widthMax = hd.fit.heightMax, hd.fit.heightMaxFoe, hd.fit.widthMax
  -- (uncapped until the caps' own checks below)
  hd.fit.heightMax, hd.fit.heightMaxFoe, hd.fit.widthMax = nil, nil, nil
  -- (a tile spans 20 px plus a fifth of the row: 34 at the foe's feet row 70, 42.4 at the player's 112)
  local function ppt(v) return 20 + v * 0.2 end
  hd.scene = { METRES_PER_TILE = 1, SHADOW = { enemy = { 176, 70, 26, 6 }, player = { 72, 115, 32, 7 } },
               groundScale = function(_, _, v) return ppt(v) end }
  hd.sceneRenderer = function() return nil end   -- (the wallpaper shows: only the sizes matter here)
  local base = canvas("ui", 240, 160)
  local wall, shadow = canvas("wall", 256, 160), canvas("shadow", 256, 160)
  local pic, mine, pic2 = canvas("pic", 64, 64), canvas("mine", 64, 64), canvas("pic2", 64, 64)
  local pageE, pageP, page2 = canvas("atlasE", 4096, 4096), canvas("atlasP", 4096, 4096), canvas("atlas2", 4096, 4096)
  -- a 100x200 frame, its feet on its bottom row, its art from the top: 200 frame px of art
  local function mon(page, side, height, extra)
    local spec = { texture = page, quad = quad(0, 0, 100, 200), pivot = { 50, 200 }, lowPivot = { 32, 62 },
                   top = 0, art = { 0, 0, 100, 200 }, body = { 20, 100, 80, 200 }, side = side,
                   height = height, scale = 0.3 }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return spec
  end
  local function frame(o)
    o = o or {}
    G.setCanvas(base)
    hd.beginPass("battle", base)
    local okW = hd.world(wall, { to = {}, look = o.look }, 0, 0)
    hd.drawStage(shadow, 0, 0, "enemy")
    G.draw(pic, 176, 40 + (o.dy or 0), 0, o.s or 1, o.s or 1, 32, 32)
    if o.pic2 then G.draw(pic2, 208, 36, 0, 1, 1, 32, 32) end
    if o.mine ~= false then G.draw(mine, 72, 80, 0, 1, 1, 32, 32) end
    hd.seam("ui")
    G.rectangle("fill", 0, 112, 240, 48)
    hd.endPass()
    G.log = {}
    hd.composite(base, function(c, bx, by, sx, sy) G.draw(c, bx or 0, by or 0, 0, sx or 4, sy or 4) end,
      0, 0, 4, 4, { 0, 0, 960, 640 }, o.view)
    hd.endFrame()
    return okW
  end
  local function drawn(page)
    local d
    for _, e in ipairs(G.log) do if e.image == page then d = e end end
    return d
  end
  -- (the size a draw has in the canvas, its zoom taken out: frame px -> canvas px)
  local function size(page) local d = drawn(page) return d and d.args[5] / (4 * hd.stats.zoom) end
  hd.tag(pic, mon(pageE, "enemy", 2))
  hd.tag(mine, mon(pageP, "player", 2))
  check(frame(), "world: the world item is recorded")
  check(hd.worldScene ~= nil, "world: the pass drew the 3D world")
  -- the foe's feet at row 70 (40 + 62 - 32): 34 px a tile, 2 m of art over its 200 frame px
  local kE, kP = size(pageE), size(pageP)
  check(kE and near(kE, 2 * ppt(70) / 200), "world: a 2 m foe at 34 px a tile: 68 canvas px of art (" .. tostring(kE) .. ")")
  check(kP and near(kP, 2 * ppt(110) / 200), "world: the same height nearer the camera, larger by its ground's scale alone ("
    .. tostring(kP) .. ")")
  -- a giant foe (20 m: 680 px of art): the camera zooms out and the sides stay on their ground
  -- (the wide ones' step outward off until its own checks below)
  check(hd.fit.wideLine == 0.45 and hd.fit.wideKeep == 0.6,
    "world: a wide one kept back of 45% of the screen from its edge, 60% of it on the screen")
  local wideLine = hd.fit.wideLine
  hd.fit.wideLine = nil
  hd.tag(pic, mon(pageE, "enemy", 20, { body = { 0, 100, 100, 200 } }))
  for _ = 1, 60 do frame() end
  kE = size(pageE)
  check(hd.stats.zoom < 1, "world: a giant foe: the camera zooms out (" .. tostring(hd.stats.zoom) .. ")")
  check(hd.stats.shiftEnemy == 0 and hd.stats.shiftPlayer == 0 and hd.stats.dropPlayer == 0
    and hd.stats.raisePlayer == 0, "world: no side moved off its ground (shift, drop, raise all 0)")
  -- ... wide, each stepped out toward its own edge (the screen the canvas's 240 columns, the
  -- focus column 120): the foe's art's left edge (its feet at 176, 50 frame px each side) on the
  -- 55% line (132), the player's right edge (at 72) on the 45% line (108), the camera unmoved
  do
    local zBefore = hd.stats.zoom
    hd.fit.wideLine = wideLine
    frame()
    local z, kP2 = hd.stats.zoom, size(pageP)
    local foeL = 120 + (176 - 50 * kE + hd.stats.shiftEnemy - 120) * z
    local mineR = 120 + (72 + 50 * kP2 + hd.stats.shiftPlayer - 120) * z
    check(near(z, zBefore) and hd.stats.shiftEnemy > 0 and math.abs(foeL - 132) < 0.02,
      "world: a wide foe stepped right, its left edge on the 55% line (" .. string.format("%.2f", foeL) .. ")")
    check(hd.stats.shiftPlayer < 0 and math.abs(mineR - 108) < 0.02,
      "world: ...a wide back stepped left, its right edge on the 45% line (" .. string.format("%.2f", mineR) .. ")")
    -- ... never past 40% of it off the screen: with the line on the screen's edges (0), each
    -- would go all the way off; the point 60% of its art in from its inner edge (10 frame px
    -- past its feet, outward) is held on the edge instead
    hd.fit.wideLine = 0
    frame()
    z = hd.stats.zoom
    kP2 = size(pageP)
    local midE = 120 + (176 + 10 * kE + hd.stats.shiftEnemy - 120) * z
    local midP = 120 + (72 - 10 * kP2 + hd.stats.shiftPlayer - 120) * z
    check(math.abs(midE - 240) < 0.02 and math.abs(midP) < 0.02,
      "world: ...never more than 40% off the screen (at " .. string.format("%.2f, %.2f", midP, midE) .. ")")
    hd.fit.wideLine = wideLine
    hd.fit.double = true
    frame()
    check(hd.stats.shiftEnemy == 0 and hd.stats.shiftPlayer == 0, "world: ...not in a double battle")
    hd.fit.double = false
    -- ... nor a giant (exports.giant: Galar Rising's Dynamax), which keeps its own spot, the
    -- camera pulled back for its whole width instead; the other side still steps
    local zStep = hd.stats.zoom
    for _ = 1, 60 do
      hd.setGiant(1, { scale = 1, dx = 0, dy = 0, grow = 1 })
      frame()
    end
    check(hd.stats.shiftEnemy == 0 and hd.stats.shiftPlayer < 0,
      "world: ...not a giant foe, which keeps its spot (the player's back still steps)")
    check(hd.stats.zoom <= zStep + 1e-9, ("world: ...the camera no nearer for it (%.3f from %.3f)")
      :format(hd.stats.zoom, zStep))
    hd.setGiant(1, nil)
    for _ = 1, 3 do frame() end
    -- ... and, easing out, not while the Battle Camera's view is turned (look.still)
    local full = hd.stats.shiftEnemy
    local look = { still = 0.5, on = true, feet = {}, frame = 0 }
    for _ = 1, 60 do frame({ look = look }) end
    local half = hd.stats.shiftEnemy
    look.still = 0
    for _ = 1, 60 do frame({ look = look }) end
    check(half > 0 and half < full and hd.stats.shiftEnemy == 0 and hd.stats.shiftPlayer == 0,
      ("world: ...eased out as the Battle Camera's view turns (%.2f, half way %.2f, then none: %s %s)"):format(full,
      half, tostring(hd.stats.shiftEnemy), tostring(hd.stats.shiftPlayer)))
    frame()
    hd.fit.wideLine = nil
    frame()
  end
  -- the foe's HP box over the highest head (Fill Screen, singles: the screen the canvas, 4x;
  -- the box's rows 16-44 in UI px, the UI 1:1 over the scene): placed when a new Pokemon comes
  -- out, held through a faint, placed afresh for a new one and a new battle
  do
    local view = { 0, 0, 960, 640 }
    local giant = hd.pair.enemy
    hd.fit.fill = true
    hd.tag(pic, mon(pageE, "enemy", 2))
    for _ = 1, 60 do frame({ view = view }) end
    local b1 = hd.fit.boxBottom
    check(hd.fit.headBox and b1 and b1 >= 2 + 28 - 1e-6 and b1 <= hd.fit.ui.player[2] - 2,
      "world: the foe's HP box placed over the heads (its bottom at " .. tostring(b1) .. ")")
    check(near(hd.fit.uiTopDy, b1 - 44), "world: ...the top band moved there (" .. tostring(hd.fit.uiTopDy) .. ")")
    -- (the heads under its columns, at the camera's target: the player's art top, 200 frame px
    -- over its feet at row 110; the foe's, on the right, needs no room)
    local z, lift = hd.stats.zoomTarget, hd.fitLift(hd.stats.zoomTarget) + hd.fit.extraTarget
    local head = 112 + (110 - 200 * size(pageP) - 112) * z - lift
    check(head >= b1 + 2 - 0.05, "world: ...the player's head, under its columns, under it ("
      .. string.format("%.2f", head) .. ")")
    -- the player's Pokemon gone (fainted): held
    for _ = 1, 30 do frame({ view = view, mine = false }) end
    check(hd.fit.boxBottom == b1, "world: ...held when a Pokemon faints")
    -- a new foe, much shorter: placed afresh
    hd.tag(pic, mon(pageE, "enemy", 0.5))
    for _ = 1, 60 do frame({ view = view }) end
    check(hd.fit.boxBottom and hd.fit.boxBottom ~= b1, "world: ...placed afresh for a new Pokemon ("
      .. tostring(hd.fit.boxBottom) .. ")")
    -- a new battle: afresh
    hd.fit.idle = 3
    frame({ view = view })
    check(hd.fit.boxBottom ~= nil, "world: ...and when a battle starts")
    hd.fit.fill = false
    hd.tag(pic, giant)
    for _ = 1, 60 do frame() end
    check(hd.fit.headBox == false and hd.fit.boxBottom == nil, "world: no Fill Screen, no box placement")
  end
  -- a double battle: none taller than 1.5 m, and none wider than its spot (here columns 120, 176
  -- and 232: the foe at 176 has 28 px each side, less the 2 px gap: its art, 50 frame px each
  -- side of its feet, at most 26 / 50)
  do
    check(hd.fit.heightKneeDouble == 2 and hd.fit.heightMaxDouble == 5 and hd.fit.spotGap == 2
      and hd.fit.spreadMax == 1.6, "world doubles: a soft ceiling from 2 m toward 5 m, 2 px between spots")
    local spots, giant = hd.fit.doubleSpots, hd.pair.enemy
    -- (the world's sizes in a double battle: doublesOwnSize off until its own check below)
    check(hd.fit.doublesOwnSize == true, "world doubles: the sprite mod's own sizes by default")
    hd.fit.doublesOwnSize = false
    -- (the spread off until its own checks below)
    hd.fit.double, hd.fit.doubleSpots, hd.fit.spreadMax = true, { 120, 176, 232 }, 1
    hd.tag(pic, mon(pageE, "enemy", 4))
    for _ = 1, 30 do frame() end
    local eh
    for _, w in ipairs(hd._worldMons) do if w.of.height == 4 then eh = w.height end end
    local want4 = 2 + 3 * (1 - math.exp(-2 / 3))
    check(eh and near(eh, want4), "world doubles: a 4 m foe eased to " .. want4 .. " m (" .. tostring(eh) .. ")")
    hd.fit.heightMaxDouble = nil
    hd.tag(pic, mon(pageE, "enemy", 4, { body = { 0, 100, 100, 200 } }))
    for _ = 1, 30 do frame() end
    check(near(size(pageE), 26 / 50), "world doubles: ...no wider than its spot (" .. tostring(size(pageE)) .. ")")
    -- the spread: Gen 3's columns moved apart about the focus (120) as far as keeps the outer
    -- two's feet 20 px inside the screen at the camera's target, up to 1.6; each battler's move
    -- its column's distance from the focus times (spread - 1)
    hd.fit.doubleSpots, hd.fit.spreadMax, hd.fit.heightMaxDouble = spots, 1.6, 5
    hd.fit.idle = 3
    for _ = 1, 90 do frame() end
    local sp, st = hd.fit.spread, hd.fit.spreadTarget
    check(st and st > 1 and st <= 1.6 and near(sp, st, 1e-3),
      "world doubles: spread apart (" .. tostring(sp) .. ", target " .. tostring(st) .. ")")
    check(near(hd.spreadDx(200), 80 * (sp - 1)) and near(hd.spreadDx(32), -88 * (sp - 1)),
      "world doubles: ...each battler moved by its column's distance from the focus")
    -- own sizes: the tag's scale (0.3), no spread
    hd.fit.doublesOwnSize = true
    hd.fit.idle = 3
    for _ = 1, 30 do frame() end
    check(near(size(pageE), 0.3) and hd.fit.spread == 1, "world doubles: own sizes, no spread ("
      .. tostring(size(pageE)) .. ", " .. tostring(hd.fit.spread) .. ")")
    check(hd.stats.zoomTarget == 1, "world doubles: ...the camera where it stands while all show ("
      .. tostring(hd.stats.zoomTarget) .. ")")
    -- ... one far too big for the screen keeps its size, the camera pulled back only as far as
    -- shows its art whole: its top on the screen, its sides inside it
    hd.tag(pic, mon(pageE, "enemy", 4, { scale = 3 }))
    for _ = 1, 30 do frame() end
    local zd = hd.stats.zoomTarget
    check(near(size(pageE), 3) and zd < 1 and hd.fit.extraTarget == 0,
      "world doubles: ...never shrunk, the camera pulled back for it (" .. tostring(size(pageE)) .. ", "
      .. tostring(zd) .. ")")
    hd.fit.double = false
    frame()
    check(hd.spreadDx(200) == 0 and hd.fit.spread == 1, "world: no spread in singles")
    -- every battler small (0.3 m: 10 and 13 canvas px of art): the camera comes in, toward the
    -- taller (the player's, 0.3 * 42 px) standing 30% of the battle's 112 rows, as far as 2.5,
    -- every art top still on the screen
    check(hd.fit.zMax == 2.5 and hd.fit.smallFill == 0.3, "world: small ones zoomed in, up to 2.5, toward 30%")
    local mineSpec = hd.pair.player
    hd.tag(pic, mon(pageE, "enemy", 0.3))
    hd.tag(mine, mon(pageP, "player", 0.3))
    hd.fit.idle = 3
    frame()
    local zi = hd.stats.zoomTarget
    local want = math.min(2.5, 0.3 * 112 / (0.3 * ppt(110)))
    check(zi > 1 and zi <= want + 1e-6, "world: ...in (" .. tostring(zi) .. ", at most " .. want .. ")")
    local foeTop = 112 + (70 - 200 * size(pageE) - 112) * hd.stats.zoom
    check(foeTop >= -1e-6, "world: ...the foe's head still on the screen (" .. string.format("%.2f", foeTop) .. ")")
    hd.tag(pic, giant)
    hd.tag(mine, mineSpec)
    hd.fit.idle = 3
    for _ = 1, 30 do frame() end
    check(hd.stats.zoomTarget <= 1, "world: ...not with a big one on the field")
    -- a small foe (0.3 m) before a bigger Pokemon of the player's (1.2 m): in, gently, toward the
    -- foe standing 17% of the height, no further than 1.4
    check(hd.fit.smallFoe == 0.17 and hd.fit.zFoeMax == 1.4, "world: a small foe zoomed in toward 17%, up to 1.4")
    hd.tag(pic, mon(pageE, "enemy", 0.3))
    hd.tag(mine, mon(pageP, "player", 1.2))
    hd.fit.idle = 3
    for _ = 1, 30 do frame() end
    local zs = hd.stats.zoomTarget
    check(zs > 1 and zs <= 1.4 + 1e-6, "world: ...a small foe before a bigger one brings the camera in (" .. tostring(zs) .. ")")
    -- its moves aimed at the middle of its art as drawn, under the cart's pic box's middle (row
    -- 40, its feet at 72): a small foe stands low
    local aim = hd.fit.aimEnemy
    check(aim and aim > 40 and aim < 72, "world: a small foe's moves aimed at its body (row " .. tostring(aim) .. ")")
    hd.tag(pic, giant)
    hd.tag(mine, mineSpec)
    hd.fit.idle = 3
    for _ = 1, 30 do frame() end
    -- 3D Sizing off: drawn as outside the 3D world, at the tag's own size (0.3: its 60 px of art
    -- fit the 70 rows of its room), nothing fitted round it
    check(hd.fit.worldSizes == true, "world: 3D Sizing on by default")
    hd.fit.worldSizes, hd.fit.fill = false, true
    hd.tag(pic, mon(pageE, "enemy", 20))
    hd.fit.idle = 3
    for _ = 1, 30 do frame({ view = { 0, 0, 960, 640 } }) end
    check(near(size(pageE), 0.3) and not hd.fit.headBox and hd.stats.zoomTarget == 1,
      "world: 3D Sizing off, a 20 m foe at its own size, nothing fitted (" .. tostring(size(pageE)) .. ")")
    hd.fit.worldSizes, hd.fit.fill = true, false
    -- the 3D world's single battles frame what is out on the field (each side as the engine
    -- reports it, out or not yet / no longer, and whether the opposing trainer is shown)
    local function frameLive(eOut, pOut, trainer)
      G.setCanvas(base)
      hd.beginPass("battle", base)
      hd.world(wall, { to = {} }, 0, 0)
      hd.prefit("enemy", pic, 176, 40, nil, eOut)
      hd.prefit("player", mine, 72, 80, nil, pOut)
      hd.fieldTrainer(trainer)
      if eOut then G.draw(pic, 176, 40, 0, 1, 1, 32, 32) end
      if pOut then G.draw(mine, 72, 80, 0, 1, 1, 32, 32) end
      hd.seam("ui")
      G.rectangle("fill", 0, 112, 240, 48)
      hd.endPass()
      G.log = {}
      hd.composite(base, function(c, bx, by, sx, sy) G.draw(c, bx or 0, by or 0, 0, sx or 4, sy or 4) end,
        0, 0, 4, 4, { 0, 0, 960, 640 })
      hd.endFrame()
    end
    hd.tag(pic, giant)
    hd.tag(mine, mon(pageP, "player", 0.3))
    hd.fit.idle = 3
    -- (the trainer's intro, nothing out: the camera's own zoom)
    frameLive(false, false, true)
    check(hd.stats.zoom == 1 and hd.stats.zoomTarget == 1, "world live: a battle starts at the camera's own zoom ("
      .. tostring(hd.stats.zoom) .. ")")
    for _ = 1, 30 do frameLive(false, false, true) end
    check(hd.stats.zoom == 1, "world live: ...held there until a Pokemon is out")
    -- (the foe out: pulled out for it, from 1)
    frameLive(true, false, false)
    local z1 = hd.stats.zoom
    for _ = 1, 60 do frameLive(true, false, false) end
    local zFoe = hd.stats.zoomTarget
    check(zFoe < 1 and z1 > zFoe and near(hd.stats.zoom, zFoe, 1e-3),
      "world live: the giant foe out, the camera eased out for it (" .. tostring(z1) .. " -> " .. tostring(zFoe) .. ")")
    -- (the player's out: framed again with both)
    for _ = 1, 120 do frameLive(true, true, false) end
    local zBoth = hd.stats.zoomTarget
    check(zBoth <= 1 and near(hd.stats.zoom, zBoth, 1e-3), "world live: the player's out, framed again (" .. tostring(zBoth) .. ")")
    -- (the foe down, then its next reported before its send-out: held where it was)
    local small = mon(pageE, "enemy", 0.3)
    for _ = 1, 60 do frameLive(false, true, false) end
    check(hd.stats.zoomTarget == zBoth and near(hd.stats.zoom, zBoth, 1e-3),
      "world live: the foe down, the camera held (" .. tostring(hd.stats.zoom) .. ")")
    hd.tag(pic, small)
    for _ = 1, 60 do frameLive(false, true, false) end
    check(hd.stats.zoomTarget == zBoth and near(hd.stats.zoom, zBoth, 1e-3),
      "world live: ...the next foe not yet out, still held (" .. tostring(hd.stats.zoom) .. ")")
    -- (the next out: framed again, a turn playing or not; both small, in)
    hd.setTurn(true)
    for _ = 1, 400 do frameLive(true, true, false) end
    hd.setTurn(false)
    check(hd.stats.zoomTarget > 1 and near(hd.stats.zoom, hd.stats.zoomTarget, 1e-3),
      "world live: the next foe out, framed again mid-turn (" .. tostring(hd.stats.zoom) .. ")")
    -- (the foe down for good, the trainer's last words: back to the camera's own zoom)
    hd.tag(pic, giant)
    for _ = 1, 120 do frameLive(true, true, false) end
    local zEnd = hd.stats.zoom
    hd.setTurn(true)
    for _ = 1, 30 do frameLive(false, true, false) end
    check(near(hd.stats.zoom, zEnd, 1e-3), "world live: the last foe down, held")
    for _ = 1, 300 do frameLive(false, true, true) end
    hd.setTurn(false)
    check(zEnd < 1 and hd.stats.zoomTarget == 1 and near(hd.stats.zoom, 1, 1e-3),
      "world live: the trainer back for its last words, at the camera's own zoom (" .. tostring(zEnd) .. " -> "
      .. tostring(hd.stats.zoom) .. ")")
    hd.tag(mine, mineSpec)
    hd.tag(pic, giant)
    hd.fit.idle = 3
    for _ = 1, 30 do frame() end
  end
  -- (its room: from its feet (row 70) up to the screen's top at zoom 0.4 about the focus row 112,
  -- 112 - 112 / 0.4 = -168: 238 rows for 200 px of art)
  local most = (70 - (112 - 112 / 0.4)) / 200
  local e
  for _, w in ipairs(hd._worldMons) do if w.of.height == 20 then e = w end end
  check(kE and near(kE, most) and e and e.limited, "world: the giant held to its room at the furthest zoom ("
    .. tostring(kE) .. ", room " .. most .. ")")
  -- the scene's shadow under each side spans its Pokemon's body at its size
  check(hd.worldShadow.enemy and near(hd.worldShadow.enemy, 100 * most / 52), "world: the foe's shadow as wide as its body ("
    .. tostring(hd.worldShadow.enemy) .. ")")
  local sh
  for _, en in ipairs(G.log) do if en.image == shadow then sh = en end end
  check(sh and near(sh.args[4], 4 * hd.stats.zoom * hd.worldShadow.enemy), "world: ...drawn scaled to it")
  local feet = drawn(pageE)
  -- (a draw with no quad: x, y, r, sx, sy; the foe's feet at its pic's canvas (176, 70))
  check(sh and feet and near(sh.args[1] + 176 * sh.args[4], feet.args[2]) and near(sh.args[2] + 70 * sh.args[5], feet.args[3]),
    "world: ...about its middle, under the foe's feet (" .. tostring(sh and sh.args[1] + 176 * sh.args[4]) .. ", "
    .. tostring(sh and sh.args[2] + 70 * sh.args[5]) .. " vs " .. tostring(feet and feet.args[2]) .. ", "
    .. tostring(feet and feet.args[3]) .. ")")
  -- a wide foe (3 m, its art 600 frame px across: 306 canvas px about its feet at x 176): the
  -- camera zooms out until its art lies inside the scene's edges (less the margin), not just
  -- under its top
  hd.tag(pic, mon(pageE, "enemy", 3, { quad = quad(0, 0, 600, 200), pivot = { 300, 200 }, art = { 0, 0, 600, 200 },
    body = { 0, 100, 600, 200 } }))
  frame()
  local half = 300 * 3 * ppt(70) / 200
  -- (and then bigPull further back, a giant)
  local want = (240 - hd.fit.margin - 120) / (176 + half - 120) * hd.fit.bigPull
  check(near(hd.stats.zoomTarget, want, 1e-3), "world: a wide foe: zoomed until it fits across, a little further (" ..
    tostring(hd.stats.zoomTarget) .. ", want " .. want .. ")")
  -- coming out of its ball (drawn small, 16 rows low): measured again when it rests, then kept
  -- through a lunge
  hd.tag(pic, mon(pageE, "enemy", 1.2))
  frame({ s = 0.16, dy = 16 })
  frame({ dy = 0 })
  local rest = size(pageE)
  check(rest and near(rest, 1.2 * ppt(70) / 200), "world: the send-out measured where it rests (" .. tostring(rest) .. ")")
  frame({ dy = -10 })
  check(near(size(pageE), rest), "world: a lunge keeps its size")
  -- a second foe further back (a double battle's): sized by its own ground
  hd.tag(pic2, mon(page2, "enemy", 1.1))
  frame({ pic2 = true })
  local k2 = size(page2)
  check(k2 and near(k2, 1.1 * ppt(66) / 200), "world: each battler by the ground under its own feet (" .. tostring(k2) .. ")")
  -- the smallest: its art's longest side at least worldMin of the battle's 160 rows before the
  -- camera's zoom, the same on any screen (a 0.1 m foe: 3.4 px of art, raised to 7% = 11.2
  -- rows); above it, true (worldShare off for these)
  local shareDefault = hd.fit.worldShare
  check(shareDefault == 0.2, "world: the smallest at least 20% of the tallest by default")
  hd.fit.worldMin, hd.fit.worldShare = 0.07, 0
  hd.tag(pic2, mon(page2, "enemy", 0.1))
  frame({ pic2 = true })
  local tiny = size(page2)
  local e2
  for _, w in ipairs(hd._worldMons) do if w.of.height == 0.1 then e2 = w end end
  check(tiny and near(tiny * 200, 0.07 * 160, 1e-6) and e2 and e2.raised,
    "world: a tiny foe raised to 7% of the battle's 160 rows, before the zoom (" .. tostring(tiny and tiny * 200) .. " rows)")
  -- ... and no smaller than worldShare of the tallest on the field's art height (here the
  -- player's), before the zoom too: a Pikachu beside a Wailord alike on an upright screen and a
  -- wide one
  hd.fit.worldShare = 0.15
  frame({ pic2 = true })
  local mineW
  for _, w in ipairs(hd._worldMons) do if w.of == hd.pair.player then mineW = w end end
  local wantS = mineW and math.max(0.07 * 160, 0.15 * mineW.px) / 200
  check(wantS and wantS * 200 > 0.07 * 160 and near(size(page2), wantS, 1e-6),
    "world: ...and 15% of the tallest's art height (" .. tostring(size(page2)) .. ", want " .. tostring(wantS) .. ")")
  -- (Accurate: no share of the tallest, only worldMinAccurate of the battle's height)
  check(hd.fit.worldMinAccurate == 0.04, "world: Accurate's floor 4% of the battle's height by default")
  hd.fit.sizeMode, hd.fit.worldMinAccurate = "accurate", 0.07
  frame({ pic2 = true })
  check(near(size(page2), 0.07 * 160 / 200, 1e-6), "world: ...Accurate: the tiny foe at its own floor, not the tallest's share ("
    .. tostring(size(page2)) .. ")")
  -- (Minimal: Medium's raised size, curved toward 1 m: bigger still, as metres where it stands
  -- ^0.75; its raise, curved alike, left out of the zoom-in)
  hd.fit.sizeMode, hd.fit.worldMinAccurate, hd.fit.worldShare = "minimal", 0.04, 0
  frame({ pic2 = true })
  local eM
  for _, w in ipairs(hd._worldMons) do if w.of.height == 0.1 then eM = w end end
  local medK = 0.07 * 160 / 200
  check(eM and size(page2) > medK and near(eM.height, (medK / (eM.ppt / 200)) ^ 0.75, 1e-6),
    "world: ...Minimal: the raised tiny foe bigger than Medium's (" .. tostring(size(page2)) .. " over " .. medK .. ")")
  check(eM and eM.lift > 1 and near(size(page2) / eM.lift, (0.1) ^ 0.75 * eM.ppt / 200, 1e-6),
    "world: ...its raise left out of the zoom-in, curved (" .. tostring(eM and eM.lift) .. ")")
  hd.fit.sizeMode, hd.fit.worldShare = "medium", 0.15
  hd.fit.worldShare = 0
  -- a flat one (its art 400 px across, 200 tall): by its width, raised half as much (wideFloor
  -- off) ...
  local wideDefault = hd.fit.wideFloor
  check(wideDefault == 1.4, "world: a wide one's floors at most 1.4 times by default")
  hd.fit.wideFloor = 1
  hd.tag(pic2, mon(page2, "enemy", 0.1, { quad = quad(0, 0, 400, 200), pivot = { 200, 200 }, art = { 0, 0, 400, 200 } }))
  frame({ pic2 = true })
  local flat = size(page2)
  check(flat and near(flat * 400, 0.07 * 160, 1e-6), "world: a flat one by its longest side, its width ("
    .. tostring(flat and flat * 400) .. " px across)")
  -- ... and with wideFloor its floor raised by its width over its height (2), at most 1.4 times
  hd.fit.wideFloor = 1.4
  frame({ pic2 = true })
  local flatW = size(page2)
  check(flatW and near(flatW * 400, 0.07 * 160 * 1.4, 1e-6), "world: a wide one's floor raised 1.4 times ("
    .. tostring(flatW and flatW * 400) .. " px across)")
  hd.fit.wideFloor = 1.2
  frame({ pic2 = true })
  check(near(size(page2) * 400, 0.07 * 160 * 1.2, 1e-6), "world: ...by wideFloor at most ("
    .. tostring(size(page2) * 400) .. ")")
  hd.fit.wideFloor = wideDefault
  -- (the 1.2 m foe: true to scale where that is above 7%, else raised to it)
  local want1 = math.max(rest, 0.07 * 160 / 200)
  check(near(size(pageE), want1), "world: ...a bigger one true to scale unless under it ("
    .. tostring(size(pageE)) .. ", want " .. want1 .. ")")
  hd.fit.worldShare = shareDefault
  -- indoors, a ceiling: a 6 m foe stands as tall as the knee (2 m) plus the ceiling's metre less
  -- e^-4 of it; one under the knee true to scale; outdoors the same foe at its 6 m
  local function sized(indoor, h, cap, side, extra, wide, mode)
    local G3 = fakeGraphics()
    local h3 = HD.new(G3)
    h3.install()
    h3.fit.enabled, h3.fit.zMin, h3.fit.worldMin, h3.fit.heightMax = true, 0.4, 0, cap
    h3.fit.worldMinAccurate, h3.fit.sizeMode = 0, mode or h3.fit.sizeMode
    h3.fit.widthMax, h3.fit.heightMaxFoe = wide, cap and heightMaxFoe or nil
    h3.scene, h3.sceneRenderer = hd.scene, hd.sceneRenderer
    h3.tag(pic, mon(pageE, side or "enemy", h, extra))
    G3.setCanvas(base)
    h3.beginPass("battle", base)
    h3.world(wall, { to = {}, indoor = indoor }, 0, 0)
    G3.draw(pic, 176, 40, 0, 1, 1, 32, 32)
    h3.seam("ui")
    h3.endPass()
    h3.composite(base, function(c) G3.draw(c, 0, 0, 0, 4, 4) end, 0, 0, 4, 4, { 0, 0, 960, 640 })
    h3.endFrame()
    return h3._worldMons[1] and h3._worldMons[1].height
  end
  local inH, outH, smallH = sized(true, 6), sized(false, 6), sized(true, 1.5)
  check(inH and near(inH, 2 + (1 - math.exp(-4))), "world: indoors a 6 m foe under the ceiling (" .. tostring(inH) .. " m)")
  check(outH and near(outH, 6), "world: ...outdoors its own 6 m")
  -- the soft ceiling: 3 + (max - 3) * (1 - e^-((h - 3) / (max - 3))); the same 6 m foe
  -- outdoors under 4.5 m, the player's own under 5 m; indoors eased first, then under the
  -- room's ceiling
  local function soft(h, mx) return 3 + (mx - 3) * (1 - math.exp(-(h - 3) / (mx - 3))) end
  local capH, capIn = sized(false, 6, heightMax), sized(true, 6, heightMax)
  check(capH and near(capH, soft(6, 4.5)), "world: a 6 m foe eased under 4.5 m (" .. tostring(capH) .. ")")
  check(capIn and near(capIn, 2 + (1 - math.exp(-(soft(6, 4.5) - 2)))), "world: ...indoors, capped then under the ceiling ("
    .. tostring(capIn) .. ")")
  local ownH = sized(false, 6, heightMax, "player")
  check(ownH and near(ownH, soft(6, 5)), "world: ...the player's own under 5 m (" .. tostring(ownH) .. ")")
  -- the width: a 4 m foe (eased to 3.73) whose art box is twice as wide as tall drawn 6 m wide,
  -- 3 m tall; the test's 100x200 frame (half as wide as tall) keeps its height
  local wideH = sized(false, 4, heightMax, "enemy", { art = { -50, 100, 150, 200 }, top = 100 }, widthMax)
  check(wideH and near(wideH, 3), "world: a wide one held to 6 m across (" .. tostring(wideH) .. " m tall)")
  local thinH = sized(false, 4.4, heightMax, "enemy", nil, widthMax)
  check(thinH and near(thinH, soft(4.4, 4.5)), "world: ...a tall, thin one keeps its height (" .. tostring(thinH) .. ")")
  check(smallH and near(smallH, 1.5), "world: ...indoors one under the knee true to scale")
  -- 3D Sizing's choices: Medium by default (all of the above); Minimal draws Medium's heights
  -- toward 1 m, 1 * (h / 1) ^ 0.75: a 0.4 m one 0.50, a 6 m foe eased to soft(6, 4.5) then
  -- under it; Accurate the tag's height as it is: no soft ceiling, no width cap
  check(hd.fit.sizeMode == "medium" and hd.fit.minimalMid == 1 and hd.fit.minimalPow == 0.75,
    "world: 3D Sizing on Medium by default, Minimal toward 1 m by ^0.75")
  local minSmall, minBig = sized(false, 0.4, heightMax, nil, nil, nil, "minimal"),
    sized(false, 6, heightMax, nil, nil, nil, "minimal")
  check(minSmall and near(minSmall, 0.4 ^ 0.75), "world: Minimal: a 0.4 m one drawn "
    .. tostring(minSmall) .. " m, bigger")
  check(minBig and near(minBig, soft(6, 4.5) ^ 0.75), "world: ...a 6 m foe Medium's eased "
    .. soft(6, 4.5) .. " drawn " .. tostring(minBig) .. " m, smaller")
  local mid = sized(false, 1, heightMax, nil, nil, nil, "minimal")
  check(mid and near(mid, 1), "world: ...a 1 m one as it is")
  local accBig = sized(false, 6, heightMax, nil, nil, widthMax, "accurate")
  check(accBig and near(accBig, 6), "world: Accurate: a 6 m foe its own 6 m (" .. tostring(accBig) .. ")")
  local accWide = sized(false, 4, heightMax, "enemy", { art = { -50, 100, 150, 200 }, top = 100 }, widthMax, "accurate")
  check(accWide and near(accWide, 4), "world: ...a wide one not held to 6 m across (" .. tostring(accWide) .. ")")
  local accIn = sized(true, 6, heightMax, nil, nil, nil, "accurate")
  check(accIn and near(accIn, 2 + (1 - math.exp(-4))), "world: ...indoors still under the room's ceiling ("
    .. tostring(accIn) .. ")")
  -- no world drawn: Battle Fit's species sizing, as before
  local G2 = fakeGraphics()
  local plain = HD.new(G2)
  plain.install()
  plain.fit.enabled = true
  plain.tag(pic, mon(pageE, "enemy", 2))
  G2.setCanvas(base)
  plain.beginPass("battle", base)
  plain.backdrop(wall, 0, 0)
  G2.draw(pic, 176, 40, 0, 1, 1, 32, 32)
  plain.seam("ui")
  plain.endPass()
  plain.composite(base, function(c) G2.draw(c, 0, 0, 0, 4, 4) end, 0, 0, 4, 4, { 0, 0, 960, 640 })
  plain.endFrame()
  check(plain.worldScene == nil, "world: none without the 3D world")
end

-- Battle Fit outside the 3D world: each battler at its tag's own size (the sprite mod's), shrunk
-- only when too big for its room (its pic box grown by fitRoom: Gen 3's enemy 8 rows up to the
-- screen's top, 16 columns each side)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.45
  local base = canvas("ui", 240, 160)
  local wall, pad = canvas("wall", 256, 160), canvas("pad", 256, 160)
  local pic, page = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  local frame = { wall = wall, pad = pad, pic = pic }
  local function drawn()
    local d
    for _, e in ipairs(G.log) do if e.image == page then d = e end end
    return d
  end
  local function tall(extra)
    local spec = { texture = page, quad = quad(0, 0, 100, 200), pivot = { 50, 200 }, lowPivot = { 32, 64 },
                   top = 52, side = "enemy", height = 1.8, scale = 0.3 }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return spec
  end
  -- (its room: the 64 rows over its feet and the 8 above them hold 72 / 148 of its art)
  hd.tag(pic, tall())
  fitFrame(G, hd, base, frame)
  local d = drawn()
  check(d and near(d.args[5], 4 * 0.3) and near(d.args[3], 4 * 72) and near(hd.stats.zoomTarget, 1),
    "own size: a battler that fits is drawn at its own size, on its feet, the camera in (" .. tostring(d and d.args[5]) .. ")")
  -- ... whatever the other side's species: no sizing by height
  hd.pair.player = { height = 7.2 }
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], 4 * 0.3), "own size: the other side's height changes nothing (" .. tostring(d and d.args[5]) .. ")")
  hd.pair.player = nil
  -- too big for its room: just small enough to fit it, so the camera need not pull back
  hd.tag(pic, tall({ scale = 1 }))
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], 4 * 72 / 148) and near(hd.stats.zoomTarget, 1),
    "own size: one too big for its room shrinks to fit it (" .. tostring(d and d.args[5]) .. ")")
  -- ... measured as it rests: drawn at half size coming out of its ball, it is half its fitted
  -- size, not its own (its room in those pixels twice as big), so it never grows past it
  frame.picS = 0.5
  fitFrame(G, hd, base, frame)
  frame.picS = nil
  d = drawn()
  check(d and near(d.args[5], 4 * 0.5 * 72 / 148), "own size: coming out of its ball, the room as it rests ("
    .. tostring(d and d.args[5]) .. ")")
  -- the art's own columns (spec.art, not the frame's) and the room's sides: 30 art px each side
  -- of its feet, 32 + 16 canvas px beside them
  hd.tag(pic, tall({ quad = quad(0, 0, 100, 40), pivot = { 50, 40 }, art = { 20, 0, 80, 40 }, top = 0, scale = 4 }))
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], 4 * 48 / 30), "own size: the room measured by the art's own columns and its sides ("
    .. tostring(d and d.args[5]) .. ")")
  -- a mirrored frame: its right side drawn on the left (feet at x 20 of the box: 20 + 16 / 40)
  hd.tag(pic, tall({ quad = quad(0, 0, 50, 20), pivot = { 10, 20 }, lowPivot = { 20, 64 }, top = 0, flip = true, scale = 4 }))
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], -4 * 36 / 40), "own size: a mirrored frame fits by its drawn sides (" .. tostring(d and d.args[5]) .. ")")
  -- the player's room: up to the enemy's HP box (16 rows here), its feet kept
  hd.fit.fitRoom = { player = { up = 16 } }
  hd.tag(pic, tall({ side = "player", scale = 1 }))
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], 4 * 80 / 148) and near(d.args[3], 4 * 72),
    "own size: the player's room reaches up to the enemy's HP box (" .. tostring(d and d.args[5]) .. ")")
  -- a tag without a height is held to its room too; a trainer keeps its own size
  hd.tag(pic, tall({ side = "player", scale = 1, height = false }))
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], 4 * 80 / 148), "own size: a tag without a height is held to its room too")
  local function own(spec, msg)
    hd.tag(pic, spec)
    fitFrame(G, hd, base, frame)
    d = drawn()
    check(d and near(d.args[5], 4 * spec.scale), msg .. " (" .. tostring(d and d.args[5]) .. ")")
  end
  own(tall({ trainer = true, scale = 1 }), "own size: a trainer keeps its own size")
  -- a double battle: each the same way
  hd.fit.double = true
  hd.fit.fitRoom = { enemy = { up = 0 } }
  own(tall(), "doubles: one that fits keeps its own size")
  hd.tag(pic, tall({ scale = 1 }))
  fitFrame(G, hd, base, frame)
  d = drawn()
  check(d and near(d.args[5], 4 * 64 / 148), "doubles: one too big shrinks to its room (" .. tostring(d and d.args[5]) .. ")")
  hd.fit.double = false
  hd.fit.enabled = false
  own(tall({ scale = 1 }), "own size: Battle Fit off, never shrunk")
end

-- Battle Fit and the player's own Pokemon (a back sprite: side = "player", body): outside the 3D
-- world as in it, the camera only makes room for what would leave the screen; the HP boxes and
-- the text box may cover a back, as on the cart
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  local fit = hd.fit
  local function placed(r, z, e)
    local lift = hd.fitLift(z) + e
    local v = hd.fitPlayerDrop(z, lift)
    local _, _, y0 = hd.fitHidden({ r[1], r[2] + v, r[3], r[4] + v }, z, lift)
    local t = r.top and (fit.focus[2] + (r.top + v - fit.focus[2]) * z - lift)
    return y0, t
  end
  -- a back mostly under the text box, or reaching up under the enemy's HP box: nothing moves
  for _, r in ipairs({ { 20, 60, 100, 130 }, { 20, 60, 100, 200 }, { 20, 14, 100, 50 } }) do
    local z, e = hd.fitSolve(math.huge, { r })
    check(z == 1 and e == 0, "a back on the screen: no zoom, no rise (" .. table.concat(r, ",") .. ")")
  end
  -- with a tall enemy: the enemy fits (its top under the screen's)
  local top = -40
  local z, e = hd.fitSolve(top, { { 20, 60, 100, 200 } })
  local lift = hd.fitLift(z) + e
  local enemyTop = fit.focus[2] + (top - fit.focus[2]) * z - lift
  check(enemyTop >= fit.margin - 1e-6, "a tall enemy fits under the top (" .. string.format("%.2f", enemyTop) .. ")")
  -- the whole animation stays on the screen: a head flung high (Blacephalon) pulls back only as
  -- far as the screen's top
  local flung = { 20, 60, 100, 112, top = -40 }
  z, e = hd.fitSolve(math.huge, { flung })
  local _, t = placed(flung, z, e)
  check(z < 1 and t >= fit.margin - 1e-9, "a flung head stays on the screen (" .. string.format("%.2f", t) .. ")")
  local _, t2 = placed(flung, z + fit.zStep, 0)
  check(t2 < fit.margin, "...and no further back than that")
  -- a back that needs more than the limit: clamped to the limit
  z, e = hd.fitSolve(math.huge, { { 10, -150, 130, 112, top = -200 } })
  check(near(z, fit.zMin) and e == 0, "a back past the limit clamps to zMin (" .. tostring(z) .. "), not 1")
  z = hd.fitSolve(-300, {})
  check(near(z, fit.zMin), "...as an enemy past the limit does")
  -- without backs the solve is the enemy's own fit
  z, e = hd.fitSolve(-76, {})
  check(near(z, 0.5) and e == 0, "no back: the enemy's fit, unchanged")
end

-- the side shift: zoomed out, each side moves back toward its unzoomed spot
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  local fit = hd.fit
  local base = canvas("ui", 240, 160)
  local wall, pad = canvas("wall", 256, 160), canvas("pad", 256, 160)
  local foe, mine, page = canvas("foe", 64, 64), canvas("mine", 64, 64), canvas("atlas", 4096, 4096)
  -- a tall enemy (zoom 0.5: its room past the screen's top, so it keeps its size) and a small back
  fit.fitRoom = { enemy = { up = 400, left = 400, right = 400 } }
  hd.tag(foe, { texture = page, quad = quad(0, 0, 100, 200), pivot = { 50, 200 }, lowPivot = { 32, 64 },
                top = 52, side = "enemy" })
  hd.tag(mine, { texture = page, quad = quad(0, 0, 40, 40), pivot = { 20, 40 }, lowPivot = { 32, 64 },
                 side = "player", body = { 0, 0, 40, 40 } })
  local function frame(animCopy)
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(wall, 0, 0)
    hd.drawStage(pad, 0, 0, "enemy")
    G.draw(foe, 176, 40, 0, 1, 1, 32, 32)
    G.draw(mine, 72, 80, 0, 1, 1, 32, 32)
    if animCopy then
      hd.inAnim = true                      -- a move animation draws the foe at its own spot
      G.draw(foe, 176 + fit.shift.enemy, 40, 0, 1, 1, 32, 32)
      hd.inAnim = false
    end
    hd.seam("ui")
    G.rectangle("fill", 0, 112, 240, 48)
    hd.endPass()
    G.log = {}
    hd.composite(base, function(c, bx, by, sx, sy) G.draw(c, bx or 0, by or 0, 0, sx or 4, sy or 4) end,
      0, 0, 4, 4, { 0, 0, 960, 640 })
    hd.endFrame()
  end
  frame()
  check(near(fit.shift.enemy, fit.shiftMax) and near(fit.shift.player, -fit.shiftMax),
    "the sides spread from the battle's first frame, no easing")
  -- z = 0.5: the enemy's spot 176 is back where it was with a shift of 56 -> capped at 40
  check(near(fit.shift.enemy, fit.shiftMax) and near(fit.shift.player, -fit.shiftMax),
    "the sides spread to the cap (" .. fit.shift.enemy .. ", " .. fit.shift.player .. ")")
  frame(true)
  local foes, padDraw = {}, nil
  for _, e in ipairs(G.log) do
    if e.image == page and e.args[1] and select(4, e.args[1]:getViewport()) == 200 then foes[#foes + 1] = e end
    if e.image == pad then padDraw = e end
  end
  local z = fit.z
  local want = 4 * (120 + (176 + fit.shiftMax - 120) * z)
  check(#foes == 2 and near(foes[1].args[2], want) and near(foes[2].args[2], want),
    "the foe and a move animation's copy of it stand on the same shifted spot")
  check(padDraw and near(padDraw.args[1], 4 * (120 * (1 - z) + fit.shiftMax * z)),
    "its pad moves with it, drawn at window resolution")

  -- the player's trainer (cut by the text box at y 112): shifted with its side, and its
  -- frame's bottom kept on the text box's line however the camera rises
  local trainer = canvas("trainer", 64, 320)
  local tq = quad(0, 0, 64, 64)
  hd.tag(trainer, { side = "player", trainer = true, pinBottom = 112 })
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  -- (the engine reports the player's lead where it will rest, before its send-out)
  hd.prefit("player", mine, 72, 80)
  G.draw(foe, 176, 40, 0, 1, 1, 32, 32)
  G.draw(trainer, tq, 80 - 32, 80 - 32)
  hd.seam("ui")
  G.rectangle("fill", 0, 112, 240, 48)
  hd.endPass()
  G.log = {}
  hd.composite(base, function(c, bx, by, sx, sy) G.draw(c, bx or 0, by or 0, 0, sx or 4, sy or 4) end,
    0, 0, 4, 4, { 0, 0, 960, 640 })
  hd.endFrame()
  local t
  for _, e in ipairs(G.log) do if e.image == trainer then t = e end end
  local zz, lift = fit.z, hd.fitLift(fit.z) + fit.extra
  local s = 4 * zz
  -- drawn about the frame's centre (32, 32): its left edge and its bottom
  check(t and near(t.args[2] - 32 * s, 4 * (120 * (1 - zz) + (48 + fit.shift.player) * zz)),
    "the trainer moves with the player's side")
  -- (anchored there exactly, whatever the camera or its side's drop does)
  check(t and near(t.args[3] + 32 * s, 4 * 112), "...its cut bottom stands on the text box's line ("
    .. tostring(t and (t.args[3] + 32 * s) / 4) .. ")")
  check(near(fit.z, zz) and fit.target == fit.z, "...and a trainer does not change the fit")
end

-- a battler not drawn yet (a trainer's Pokemon before its send-out) frames the camera already
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  local base = canvas("ui", 240, 160)
  local wall = canvas("wall", 256, 160)
  local foe, page = canvas("foe", 64, 64), canvas("atlas", 4096, 4096)
  hd.tag(foe, { texture = page, quad = quad(0, 0, 100, 200), pivot = { 50, 200 }, lowPivot = { 32, 64 },
                top = 52, side = "enemy" })
  local giantInfo   -- (exports.giant's report, made each frame as a mod makes it)
  local function frame(drawFoe)
    if giantInfo then hd.setGiant(1, giantInfo) end
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(wall, 0, 0)
    hd.prefit("enemy", foe, 176, 40)
    if drawFoe then G.draw(foe, 176, 40, 0, 1, 1, 32, 32) end
    hd.seam("ui")
    hd.endPass()
    hd.composite(base, function() end, 0, 0, 4, 4, { 0, 0, 960, 640 })
    hd.endFrame()
    return hd.fit.z
  end
  local before = frame(false)
  local after = frame(true)
  check(before < 1 and near(before, after), "the camera is framed for a Pokemon before it is sent out ("
    .. string.format("%.3f, then %.3f", before, after) .. ")")
  -- a giant (exports.giant: Galar Rising's Dynamax, 1.5x about its feet): the camera pulls back
  -- for it where it rests at that size, drawn this frame or not (a G-Max move's look hides it),
  -- its feet on its own's; let go, the camera comes back in (between turns)
  local own = after
  giantInfo = { scale = 1.5, dx = 0, dy = -32 * 0.5, grow = 1 }
  local function settle(drawFoe)
    local z
    for _ = 1, 120 do z = frame(drawFoe) end
    return z
  end
  local giant = settle(true)
  local hidden = frame(false)
  local g = hd.giants[1]
  check(giant < own - 0.05 and near(hidden, giant), "a giant: the camera pulls back for it, and holds while it is "
    .. "hidden (" .. string.format("%.3f, giant %.3f, hidden %.3f", own, giant, hidden) .. ")")
  check(g and math.abs(g.fixX or 9) < 1e-6 and math.abs(g.fixY or 9) < 1.01,
    "...its feet where its own stand (" .. tostring(g and g.fixX) .. ", " .. tostring(g and g.fixY) .. ")")
  hd.setGiant(1, nil)
  giantInfo = nil
  local back = settle(true)
  check(near(back, own), "...let go, the camera back in (" .. string.format("%.3f", back) .. ")")
  -- (one its mod stops telling of without a nil - its record gone - is off two frames on)
  giantInfo = { scale = 1.5, dx = 0, dy = -32 * 0.5, grow = 1 }
  settle(true)
  giantInfo = nil
  frame(true)
  frame(true)
  check(not hd.giantLive(hd.giants[1]), "...and one no longer told of is off by the frame after next")
end

-- a double battle's foes, each reported by its battler id: both count (the later report does
-- not replace the earlier), and the target cursor hiding the tall one moves nothing
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  local base = canvas("ui", 240, 160)
  local wall = canvas("wall", 256, 160)
  local tall, small, page = canvas("tall", 64, 64), canvas("small", 64, 64), canvas("atlas", 4096, 4096)
  hd.tag(tall, { texture = page, quad = quad(0, 0, 100, 200), pivot = { 50, 200 }, lowPivot = { 32, 64 },
                 top = 52, side = "enemy" })
  hd.tag(small, { texture = page, quad = quad(0, 0, 64, 64), pivot = { 32, 64 }, lowPivot = { 32, 64 },
                  top = 30, side = "enemy" })
  local function frame(reports, drawTall)
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(wall, 0, 0)
    for _, r in ipairs(reports) do hd.prefit("enemy", r[1], r[2], 40, r[3]) end
    if drawTall then G.draw(tall, 200, 40, 0, 1, 1, 32, 32) end
    G.draw(small, 152, 32, 0, 1, 1, 32, 32)
    hd.seam("ui")
    hd.endPass()
    hd.composite(base, function() end, 0, 0, 4, 4, { 0, 0, 960, 640 })
    hd.endFrame()
    return hd.fit.target
  end
  local both = { { tall, 200, 1 }, { small, 152, 3 } }
  local z1 = frame(both, true)
  local z2 = frame(both, false)
  local z3 = frame(both, true)
  local zSmall = frame({ { small, 152, 3 } }, false)
  check(z1 < zSmall, "both foes count: the tall one frames the camera though the small one was "
    .. "reported after it (" .. string.format("%.3f vs %.3f", z1, zSmall) .. ")")
  check(near(z1, z2) and near(z2, z3),
    "the target cursor hiding a reported foe does not move the camera ("
    .. string.format("%.3f %.3f %.3f", z1, z2, z3) .. ")")
end

-- the intro's scrolling grass: a band repeated across the whole zoomed-out view
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  local base = canvas("ui", 240, 160)
  local wall, grass = canvas("wall", 256, 160), canvas("grass", 256, 64)
  local foe, page = canvas("foe", 64, 64), canvas("atlas", 4096, 4096)
  hd.tag(foe, { texture = page, quad = quad(0, 0, 100, 200), pivot = { 50, 200 }, lowPivot = { 32, 64 },
                top = 52, side = "enemy" })
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  G.draw(foe, 176, 40, 0, 1, 1, 32, 32)
  hd.band(grass, -30, 40)
  hd.seam("ui")
  hd.endPass()
  G.log = {}
  hd.composite(base, function() end, 0, 0, 4, 4, { 0, 0, 960, 640 })
  local g
  for _, e in ipairs(G.log) do if e.image == grass then g = e end end
  check(hd.fit.z < 1, "the scene is zoomed out")
  local uw = 0
  if g then
    local _
    _, _, uw = g.args[1]:getViewport()
  end
  check(g and g.args[2] <= 1e-9 and near(g.args[2] + uw * g.args[5], 960),
    "the grass band reaches both edges of the view (" .. tostring(g and g.args[2]) .. ")")
  check(g and near(g.args[5], 4 * hd.fit.z), "...at the scene's zoom")
  -- drawn at canvas y 40 with 64 rows: its bottom (104) zoomed about the text box's line, not raised
  local zb = hd.fit.z
  local _, gv, _, gh = 0, 0, 0, 0
  if g then _, gv, _, gh = g.args[1]:getViewport() end
  local bottomY = g and (g.args[3] + (40 + 64 - 40 - gv) * g.args[6])
  check(g and near(bottomY, 4 * (112 + (104 - 112) * zb)),
    "...and is not raised with the camera (bottom " .. tostring(bottomY and bottomY / 4) .. ")")
end

-- Fill Screen: the intro's grass reaches both sides, and its black bars open across the screen
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local grass = canvas("grass", 256, 256)
  local passLog
  local function frame(slide, top, bottom, fill)
    hd.fit.fill = fill ~= false
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.window(top, bottom)
    hd.backdrop(canvas("wall", 256, 160), 0, 0)
    hd.band(grass, 0, slide)
    hd.seam("ui")
    G.rectangle("fill", 0, 112, 240, 48)              -- the text box
    G.setColor(0, 0, 0, 1)
    if top then
      G.rectangle("fill", 0, 0, 240, top)              -- the engine's bars (ui.lua, stage.win0)
      G.rectangle("fill", 0, bottom, 240, 160 - bottom)
    end
    G.setColor(1, 1, 1, 1)
    hd.endPass()
    passLog = G.log
    G.log = {}
    -- a 1920x1080 screen: the Renderer's 6x box is 1440 wide, centred
    hd.composite(base, function() end, 240, 60, 6, 6, { 240, 60, 1440, 960 }, { 0, 0, 1920, 1080 })
    hd.endFrame()
  end
  local function rects(log)
    local out = {}
    for _, e in ipairs(log or G.log) do if e.op == "rect" then out[#out + 1] = e.args end end
    return out
  end
  frame(0, 80, 80)
  local g
  for _, e in ipairs(G.log) do if e.image == grass then g = e end end
  -- the text box's line: docked at y 120 + 112 * 6 = 792 (the 1440x960 box at the bottom)
  check(g and near(g.args[2], 0) and near(g.args[2] + g.vp[3] * g.args[5], 1920),
    "filled: the grass reaches both sides of the screen")
  check(g and g.scissor and near(g.scissor[2], 0) and near(g.scissor[2] + g.scissor[4], 792),
    "...and is hidden below the text box's line, as the cart's text box hides it")
  -- a band ending on a solid row (grass, sand, waves): not hidden below the line, its last solid
  -- row repeated from under it down to the screen's bottom
  hd.solidRow = function(img) return img == grass and 111 or false end
  frame(0, 80, 80)
  local art, run
  for _, e in ipairs(G.log) do
    if e.image == grass then
      if e.vp and e.vp[2] == 111 and e.vp[4] == 1 then run = e else art = e end
    end
  end
  check(art and not (art.scissor and near(art.scissor[2] + art.scissor[4], 792)),
    "solid grass is not hidden below the text box's line")
  check(run and near(run.args[3], 792) and near(run.args[3] + run.args[6], 1080),
    "...its last row runs on from the line to the screen's bottom (" .. tostring(run and run.args[3]) .. ")")
  hd.solidRow = function() return false end
  frame(0, 80, 80)
  local r = rects()
  check(#r == 2 and near(r[1][2], 0) and near(r[1][3], 0) and near(r[1][4], 1920)
    and near(r[1][3] + r[1][5], r[2][3]) and near(r[2][3] + r[2][5], 1080),
    "shut: the bars black out the whole screen, meeting in the middle")
  frame(0, 40, 120)
  r = rects()
  -- they open about the scene's row 80: the text box's line (y 792, docked) less 32 scene rows
  local yc = 792 + (80 - 112) * 6 * hd.stats.fill
  check(#r == 2 and near(r[1][4], 1920) and near(r[1][5], yc / 2) and near(1080 - r[2][3], (1080 - yc) / 2),
    "half open: each bar covers half of its side of the screen")
  frame(0, 40, 120, false)
  r = rects(passLog)
  local bars = 0
  for _, a in ipairs(r) do if a[4] == 240 and (a[5] == 40 or a[3] == 120) then bars = bars + 1 end end
  check(bars == 2 and #rects() == 0, "Fill Screen off: the engine's own bars, drawn as always")
end

-- Fill Screen: a move's effect anchored to the canvas's sides runs on to the screen's sides. A
-- fill reaching a side (Fake Out's curtains) or a polygon spanning the width (a wave) goes in an
-- "edge" layer, drawn through a quad over the whole view, clamped; a background drawn in bands
-- (Surf's) is recorded and its tiled image drawn across the whole view, and below the text box's
-- line beside it. A sprite crossing a side is not, and a whole background covers the screen as
-- before
do
  local G = fakeGraphics()
  function G.polygon(mode, ...) G.log[#G.log + 1] = { op = "polygon", target = G.getCanvas(), args = { mode, ... } } end
  local newCanvas = G.newCanvas
  function G.newCanvas(w, h)
    local c = newCanvas(w, h)
    function c.setWrap(self, a, b) self.wrap = { a, b } end
    return c
  end
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local wave = canvas("wave", 512, 256)
  wave.getWrap = function() return "repeat", "repeat" end
  local spark = canvas("spark", 16, 16)
  local function frame(draw, fill)
    hd.fit.fill = fill ~= false
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(canvas("wall", 256, 160), 0, 0)
    draw()
    hd.seam("ui")
    G.rectangle("fill", 0, 112, 240, 48)
    local cur = hd.endPass()
    G.log = {}
    hd.composite(base, function(c, ...) G.log[#G.log + 1] = { op = "blit", image = c, args = { ... } } end,
      240, 60, 6, 6, { 240, 60, 1440, 960 }, { 0, 0, 1920, 1080 })
    hd.endFrame()
    local layers = {}
    for _, it in ipairs(cur.items) do if it.kind == "layer" then layers[#layers + 1] = it end end
    return cur, layers
  end
  local function drawOf(image)
    for _, e in ipairs(G.log) do if e.op == "draw" and e.image == image then return e end end
  end
  -- Fake Out's left curtain
  local cur, layers = frame(function()
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, 60, 160)
    G.setColor(1, 1, 1, 1)
  end)
  local edge = layers[1]
  local e = edge and drawOf(edge.canvas)
  check(edge and edge.edge and e and near(e.args[2], 0) and e.vp[1] < 0 and e.vp[1] + e.vp[3] > 240
      and near(e.vp[3] * e.args[5], 1920) and edge.canvas.wrap and edge.canvas.wrap[1] == "clamp",
    "a curtain reaching a side: its layer drawn across the whole screen, its edge run on")
  -- an effect over the battle stops on the text box's line (the cart's text box hid the rest):
  -- its last row runs on from the line (y 792 here) down beside the text box to the screen's bottom
  local function runOf(c)
    for _, ev in ipairs(G.log) do
      if ev.op == "draw" and ev.image == c and ev.vp and near(ev.vp[2], 111) and near(ev.vp[4], 1) then return ev end
    end
  end
  cur, layers = frame(function()
    G.setColor(0, 0, 0, 0.5)
    G.rectangle("fill", 0, 0, 240, 112)                 -- a fade to the line (Encore's dimming)
    G.setColor(1, 1, 1, 1)
  end)
  local run = layers[1] and runOf(layers[1].canvas)
  check(layers[1] and layers[1].screen and layers[1].toLine and run and near(run.args[3] + run.args[6], 1080)
      and near(run.args[2], 0) and near(run.vp[3] * run.args[5], 1920),
    "a fade to the text box's line runs on down beside it to the screen's bottom")
  cur, layers = frame(function() G.polygon("fill", 0, 50, 240, 40, 240, 112, 0, 112) end)
  run = layers[1] and runOf(layers[1].canvas)
  check(layers[1] and layers[1].edge and run and near(run.args[3], 792) and near(run.args[3] + run.args[6], 1080),
    "...and so does an edge effect ending on the line")
  cur, layers = frame(function() G.draw(wave, G.newQuad(0, 0, 240, 160, 512, 256), 0, 0) end)
  check(layers[1] and layers[1].below and not runOf(layers[1].canvas), "a background reaching below the line does not")
  -- a wave spanning the width, then a sprite crossing the left side: not in the wave's layer
  cur, layers = frame(function()
    G.polygon("fill", 0, 50, 240, 40, 240, 112, 0, 112)
    G.draw(spark, -8, 30)
  end)
  check(#layers >= 2 and layers[1].edge and not layers[2].edge, "a wave across the width is an edge layer, a sprite crossing a side is not")
  -- Surf's bands: one quad moved from band to band, the wave above the text box's line (the cart's
  -- text box hides the rest). Each covers the whole view's width with its tiles; the band reaching
  -- the line runs on below it, beside the text box, down to the screen's bottom
  local q = G.newQuad(0, 0, 240, 48, 512, 256)
  local function surf()
    G.draw(wave, q, 0, 0)
    q:setViewport(100, 48, 240, 64)
    G.draw(wave, q, 0, 48)
  end
  cur = frame(surf)
  local wides = {}
  for _, it in ipairs(cur.items) do if it.kind == "wide" then wides[#wides + 1] = it end end
  local bands = {}
  for _, ev in ipairs(G.log) do if ev.op == "draw" and ev.image == wave then bands[#bands + 1] = ev end end
  check(#wides == 2 and wides[1].qy == 0 and wides[1].qh == 48 and wides[2].qx == 100 and wides[2].bottom
      and not wides[1].bottom, "a background's bands are recorded with their quad as drawn")
  check(#bands == 2 and near(bands[1].args[2], 0) and bands[1].vp[1] < 0 and near(bands[1].vp[2], 0)
      and near(bands[1].vp[3] * bands[1].args[5], 1920) and near(bands[1].vp[4], 48),
    "...each drawn across the whole screen, its tiles continued sideways")
  -- the line: y 792 on this screen (the 1440x960 box docked at the bottom)
  check(bands[2] and near(bands[2].vp[2], 48) and near(bands[2].args[3] + 64 * bands[2].args[6], 792)
      and near(bands[2].args[3] + bands[2].vp[4] * bands[2].args[6], 1080),
    "...the band reaching the text box's line runs on below it to the screen's bottom")
  -- the scene raised: still down to the bottom, never up past the canvas's top
  hd.fit.extra = 60
  q:setViewport(0, 0, 240, 48)
  frame(surf)
  hd.fit.extra = 0
  bands = {}
  for _, ev in ipairs(G.log) do if ev.op == "draw" and ev.image == wave then bands[#bands + 1] = ev end end
  check(bands[1] and near(bands[1].vp[2], 0) and near(bands[1].vp[4], 48) and bands[2]
      and near(bands[2].args[3] + bands[2].vp[4] * bands[2].args[6], 1080),
    "...with the scene raised too, and the top band does not run on upward")
  -- a whole background (the canvas's size) still covers the screen as a whole-scene layer
  cur, layers = frame(function() G.draw(wave, G.newQuad(0, 0, 240, 160, 512, 256), 0, 0) end)
  check(layers[1] and layers[1].screen, "a whole background is still a whole-scene layer")
  -- a plane (WoobleDex's Gen 9 animations: a picture repeated across the screen as copies on a
  -- grid from its top left, scrolled): the copies together are one whole-scene layer, whatever
  -- the scroll (alone, none covers the scene)
  local sheet = canvas("sheet", 1024, 1024)
  local pq = G.newQuad(10, 20, 240, 160, 1024, 1024)
  cur, layers = frame(function()
    G.draw(sheet, pq, -100, 0)
    G.draw(sheet, pq, 140, 0)
  end)
  -- (the scene's layers: those before the UI's seam)
  local function sceneLayers()
    local out = {}
    for _, it in ipairs(cur.items) do
      if it.kind == "seam" then break end
      if it.kind == "layer" then out[#out + 1] = it end
    end
    return out
  end
  layers = sceneLayers()
  check(#layers == 1 and layers[1].screen, "a plane scrolled sideways: its two copies one whole-scene layer")
  pq:setViewport(0, 0, 286, 480)
  cur, layers = frame(function()
    G.draw(sheet, pq, -41, -388)
    G.draw(sheet, pq, -41, 92)
    G.draw(spark, 100, 60)
  end)
  layers = sceneLayers()
  check(#layers == 2 and layers[1].screen and not layers[2].screen,
    "...and scrolled up (Surf's wave): one whole-scene layer, a sprite drawn next not in it")
  -- one copy alone (Encore's dimming at 0, 0, its spotlight's window on its target): not a plane
  pq:setViewport(0, 0, 240, 100)
  cur, layers = frame(function() G.draw(sheet, pq, 0, 0) end)
  layers = sceneLayers()
  check(#layers == 1 and not layers[1].screen and layers[1].edge, "a single picture at the top left stays an edge layer")
  -- a run's first copy after an edge draw: a layer of its own, which alone becomes whole-scene
  pq:setViewport(0, 0, 240, 160)
  cur, layers = frame(function()
    G.polygon("fill", 0, 50, 240, 40, 240, 112, 0, 112)
    G.draw(sheet, pq, -100, -30)
    G.draw(sheet, pq, 140, -30)
  end)
  layers = sceneLayers()
  check(#layers == 2 and layers[1].edge and not layers[1].screen and layers[2].screen,
    "...a plane after an edge effect: the effect's layer kept, the plane's its own")
  -- a row of pieces side by side across the scene (WoobleDex's Surf: its wall of water, the
  -- water and the crest by turns, sharing their foot): carried on to the screen's sides, the
  -- water repeated, and down from the canvas's foot to the screen's bottom
  local water, crest = G.newQuad(0, 500, 72, 54, 1024, 1024), G.newQuad(100, 500, 72, 72, 1024, 1024)
  local k = 180 / 72
  local function wall()
    G.draw(sheet, water, -175, 25, 0, k, k)
    G.draw(sheet, crest, 5, -20, 0, k, k)
    G.draw(sheet, water, 185, 25, 0, k, k)
  end
  local function rowDraws()
    local out = {}
    for _, ev in ipairs(G.log) do if ev.op == "draw" and ev.image == sheet then out[#out + 1] = ev end end
    return out
  end
  local function rowOf()
    for _, it in ipairs(cur.items) do if it.kind == "row" then return it end end
  end
  -- (the pieces drawn past the canvas: their span, the crest's places, a foot run on down)
  local function across()
    local xl, xr, crestX, down = math.huge, -math.huge, {}, false
    for _, ev in ipairs(rowDraws()) do
      xl, xr = math.min(xl, ev.args[2]), math.max(xr, ev.args[2] + ev.vp[3] * ev.args[5])
      if near(ev.vp[1], 100) and near(ev.vp[4], 72) then crestX[math.floor(ev.args[2] + 0.5)] = true end
      if near(ev.vp[4], 1) and near(ev.args[3] + ev.args[6], 1080) then down = true end
    end
    local places = 0
    for _ in pairs(crestX) do places = places + 1 end
    return xl, xr, places, down
  end
  cur = frame(function() wall() end)
  local row = rowOf()
  local xl, xr, places = across()
  check(row and row.carryLo and row.carryHi and #row.pieces == 3, "a row of pieces across the scene is recorded")
  check(xl <= 0 and xr >= 1920, "...carried on to the screen's sides (" .. xl .. " to " .. xr .. ")")
  check(places == 1, "...the water repeated, its crest (shown once) never")
  -- the scene raised, the canvas's foot on the screen: the row runs on below it
  hd.fit.extra = 60
  cur = frame(function() wall() end)
  hd.fit.extra = 0
  local _, _, _, down = across()
  check(down, "...and a piece reaching the text box's line runs on down to the screen's bottom")
  -- the crest and one water piece: neither repeats, so each is drawn whole and the row ends there
  local crest2, water2 = G.newQuad(200, 500, 72, 72, 1024, 1024), G.newQuad(300, 500, 72, 54, 1024, 1024)
  cur = frame(function()
    G.draw(sheet, crest2, -85, -20, 0, k, k)
    G.draw(sheet, water2, 95, 25, 0, k, k)
  end)
  row = rowOf()
  local n = #rowDraws()
  check(row and not row.carryLo and row.carryHi and n > 0,
    "a row of a crest and its water: the crest, taller, is its end; the water carries it on (" .. n .. " draws)")
  -- a move's effect crossing a side (a slash on a giant near the canvas's edge): recorded and
  -- drawn uncut over the view at the scene's mapping; one wholly off the canvas (parked there to
  -- hide it) is not
  local function freeItems()
    local out = {}
    for _, it in ipairs(cur.items) do if it.kind == "free" then out[#out + 1] = it end end
    return out
  end
  local slash = canvas("slash", 64, 32)
  cur = frame(function() G.draw(slash, 200, 40) end)
  local fr = freeItems()
  local sd = drawOf(slash)
  -- (clipped only by the screen, past the canvas's right side, column 240)
  check(#fr == 1 and sd and sd.scissor and sd.scissor[1] + sd.scissor[3] > sd.tx + 240 * sd.sx + 1,
    "an effect crossing the canvas's right side is drawn uncut past it")
  cur = frame(function() G.draw(slash, 225, 40, 0.5, 1, 1, 32, 16) end)
  check(#freeItems() == 1, "...turned too")
  cur = frame(function() G.draw(slash, -100, 40) end)
  check(#freeItems() == 0, "one wholly off the canvas is not drawn")
  cur = frame(function() G.draw(slash, 100, 40) end)
  check(#freeItems() == 0, "one inside it stays in its layer")
  -- a move's pieces grown with a giant (the 3D world's singles: fxLine where the moves run, each
  -- side's growth): one at the foe's end by its factor, about its middle; none outside a move's
  -- animation, nor a background
  hd.fit.fxLine, hd.fit.fxPlayer, hd.fit.fxEnemy = { 72, 100, 176, 40 }, 1, 2
  local grownBefore = hd.stats.fxGrown or 0
  local grownAt
  cur = frame(function()
    hd.inAnim = true
    G.draw(slash, 176, 40, 0, 1, 1, 32, 16)
    local e = G.log[#G.log]
    grownAt = e and e.sx
    G.draw(sheet, G.newQuad(0, 0, 240, 160, 1024, 1024), 0, 0)
    hd.inAnim = false
    G.draw(slash, 100, 40, 0, 1, 1, 32, 16)
  end)
  check((hd.stats.fxGrown or 0) - grownBefore == 1 and grownAt and near(grownAt, 2),
    "a move's piece at a giant's end grown by its factor, nothing else (" .. tostring(grownAt) .. ")")
  hd.fit.fxLine, hd.fit.fxPlayer, hd.fit.fxEnemy = nil, nil, nil
  -- a mosaic (pieces that together cover the scene, Seismic Toss's sky): a whole-scene layer
  -- from the pass after it is seen
  local left, right = G.newQuad(0, 700, 120, 112, 1024, 1024), G.newQuad(120, 700, 120, 112, 1024, 1024)
  local function sky()
    G.draw(sheet, left, 0, 0)
    G.draw(sheet, right, 120, 0)
  end
  cur = frame(sky)
  cur, layers = frame(sky)
  layers = sceneLayers()
  check(#layers == 1 and layers[1].screen, "a mosaic covering the scene: one whole-scene layer")
  -- Fill Screen off: nothing of this
  cur, layers = frame(function()
    G.polygon("fill", 0, 50, 240, 40, 240, 112, 0, 112)
    G.draw(wave, q, 0, 48)
  end, false)
  local any = false
  for _, it in ipairs(cur.items) do if it.kind == "wide" or it.edge then any = true end end
  check(not any, "Fill Screen off: no edge layers, no backgrounds across the view")
  cur = frame(function() wall() end, false)
  any = false
  for _, it in ipairs(cur.items) do if it.kind == "row" then any = true end end
  check(not any, "Fill Screen off: no rows carried on")
end

-- a band's last solid row, read back from its pixels: nine tenths of the width opaque
do
  local G = fakeGraphics()
  local alphaAt
  function G.newCanvas(w, h)
    local c = canvas("readback", w, h)
    c.newImageData = function()
      return { getPixel = function(_, x, y) return 0, 0, 0, alphaAt(x, y) end }
    end
    return c
  end
  local hd = HD.new(G)
  hd.install()
  alphaAt = function(_, y) return (y >= 50 and y <= 111) and 1 or 0 end
  check(hd.solidRow(canvas("grass", 256, 256)) == 111, "the grass's last solid row is found")
  alphaAt = function(x, y) return (y >= 60 and y <= 100 and x % 3 == 0) and 1 or 0 end
  check(hd.solidRow(canvas("lines", 256, 256)) == false, "speed lines have none")
end

-- when the game presents without the Renderer (its fallback), or something of ours failed,
-- nothing is captured: every frame is drawn the game's own way
do
  local G = fakeGraphics()
  local logged, infos = {}, {}
  local hd = HD.new(G, { log = { error = function(_, fmt, ...) logged[#logged + 1] = string.format(fmt, ...) end,
                                 info = function(_, fmt, ...) infos[#infos + 1] = string.format(fmt, ...) end } })
  hd.install()
  local clock = 100
  hd.now = function() return clock end
  local mod = {}
  assert(loadfile("src/api.lua"))()(mod, hd, { active = true })
  local base = canvas("ui", 240, 160)
  local pic = canvas("pic", 64, 64)
  hd.tag(pic, {})
  local broken = true
  hd.canCapture = function() return not broken end
  G.setCanvas(base)
  check(hd.beginPass("battle", base) == false, "no pass while the game presents without the Renderer")
  G.log = {}
  G.draw(pic, 10, 10)
  check(G.log[1] and G.log[1].image == pic and G.log[1].target == base, "...a tagged image is drawn as usual")
  broken = false
  check(hd.beginPass("battle", base) == true, "...and passes resume once it presents through the Renderer")
  G.draw(pic, 10, 10)
  hd.fail("boom")
  check(hd.failed == "boom" and #logged == 1 and logged[1]:find("boom", 1, true), "a failure is logged once")
  check(not hd.capturing(), "...the pass in flight is put back")
  local sawPic = false
  for _, e in ipairs(G.log) do if e.image == pic and e.target == base then sawPic = true end end
  check(sawPic, "...its sprite drawn into the canvas the usual way")
  check(hd.beginPass("battle", base) == false, "...and nothing is captured meanwhile")
  check(mod.exports.isActive() == false and mod.exports.enabled("battle") == false,
    "...while it is down the exports say it is off (a sprite mod draws its own plain sprites)")
  hd.fail("again")
  check(#logged == 1 and hd.failed == "boom", "...a second failure meanwhile is not logged again")
  -- retryAfter (2 s) later it tries again: captured, the exports on again
  clock = clock + 1.9
  check(hd.beginPass("battle", base) == false, "...not before retryAfter")
  clock = clock + 0.2
  check(hd.beginPass("battle", base) == true and hd.failed == nil and #infos == 1,
    "...then it tries again (" .. tostring(infos[1]) .. ")")
  check(mod.exports.isActive() == true and mod.exports.enabled("battle") == true, "...the exports on again")
  hd.flatten(hd.cur)
  check(logged[1]:find("failure 1 of 3", 1, true) ~= nil, "the failure is logged with its count (" .. logged[1] .. ")")
  -- the third failure turns it off for the session
  hd.fail("two")
  clock = clock + 5
  hd.endFrame()
  check(hd.failed == nil, "a second failure is retried too")
  hd.fail("three")
  check(logged[3]:find("turned off for this session", 1, true) ~= nil, "the third turns it off (" .. logged[3] .. ")")
  clock = clock + 60
  hd.endFrame()
  check(hd.beginPass("battle", base) == false and hd.failed == "three" and mod.exports.isActive() == false,
    "...for good: no retry, the exports off")
end

-- the wallpaper drawn again in the scene (Kanto Gear continuing the ground under a text box it
-- moved off the screen) is left to the recorded wallpaper, which already covers the view
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled = true
  local base = canvas("ui", 240, 160)
  local wall = canvas("wall", 256, 160)
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  G.draw(wall, quad(0, 104, 240, 8), 0, 112)
  local drew = false
  for _, e in ipairs(G.log) do if e.image == wall then drew = true end end
  check(not drew, "a second draw of the wallpaper in the scene is skipped")
  hd.seam("ui")
  G.draw(wall, 0, 0)
  drew = false
  for _, e in ipairs(G.log) do if e.image == wall then drew = true end end
  check(drew, "...but not in the UI")
  hd.endPass()
end

-- Fill Screen: the scene fills the view (top down to the text box's line, out to the sides);
-- the UI keeps its scale, docked to the view's bottom
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local wall, pad = canvas("wall", 256, 160), canvas("pad", 256, 160)
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  hd.drawStage(pad, 0, 0)
  hd.seam("ui")
  G.rectangle("fill", 0, 112, 240, 48)                -- the text box
  hd.endPass()
  -- a 1920x1080 view; the Renderer letterboxes the 240x160 UI at 6x: origin (240, 60)
  local blits = {}
  G.log = {}
  hd.composite(base, function(c, bx, by, sx, sy, box)
    blits[#blits + 1] = { canvas = c, bx = bx, by = by, sx = sx, sy = sy, box = box }
  end, 240, 60, 6, 6, { 240, 60, 1440, 960 }, { 0, 0, 1920, 1080 })
  local ui = blits[#blits]
  check(ui and ui.sx == 6 and ui.bx == 240 and near(ui.by, 1080 - 960), "the UI keeps its 6x, docked to the bottom")
  -- the text box's line at y = 120 + 112 * 6 = 792; the scene from y 0 down to it: f = 792 / 672
  local f = 792 / 672
  check(near(hd.stats.fill, f), "the scene is scaled to fill the height (" .. tostring(hd.stats.fill) .. ")")
  local b = blits[1]
  check(b and b.canvas == base and near(b.sx, 6 * f) and near(b.by + 112 * b.sy, 792)
    and near(b.bx + 120 * b.sx, 960), "...about the text box's line, centred")
  check(b and b.box and b.box[3] == 1920 and b.box[4] == 1080, "...clipped to the whole view, not the letterbox")
  local w
  for _, e in ipairs(G.log) do if e.image == wall then w = w or e end end
  local uw = 0
  if w then uw = select(3, w.args[1]:getViewport()) end
  check(w and w.args[2] <= 1e-6 and w.args[3] <= 1e-6 and near(w.args[2] + uw * w.args[5], 1920),
    "the wallpaper spans the whole view")
end

-- Fill Screen on a tall screen: stacked. The UI spans the width; its rows below the split
-- (the player's HP box, the text box) dock above the touch controls, its top band (the
-- enemy's HP box) moves to the top; the scene is at the UI's scale, its line on the text box
local function stackedFrame(opts)
  opts = opts or {}
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local wall, pad = canvas("wall", 256, 160), canvas("pad", 256, 160)
  local hpIcon = canvas("hpicon", 8, 8)
  hd.tag(hpIcon, { scale = 1 })
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  hd.drawStage(pad, 0, 0)
  hd.seam("ui")
  if opts.topSeam then hd.seam("uiTop") end           -- the enemy's HUD as a layer of its own
  G.rectangle("fill", 14, 16, 99, 28)                -- the enemy's HP box
  G.draw(hpIcon, 20, 20)                              -- a tagged draw in the top band
  if opts.topSeam then hd.seam("uiTopEnd") end
  G.rectangle("fill", 0, 112, 240, 48)                -- the text box
  if opts.straddle then G.rectangle("fill", 150, 8, 90, 96) end   -- a level-up window
  if opts.wash then                                   -- a red flash over the field (Max Move)
    G.setColor(1, 0.1, 0.3, 0.3)
    G.rectangle("fill", 0, 0, 240, 112)
    G.setColor(1, 1, 1, 1)
  end
  hd.endPass()
  local blits = {}
  G.log = {}
  hd.composite(base, function(c, bx, by, sx, sy, box, zk)
    blits[#blits + 1] = { canvas = c, bx = bx, by = by, sx = sx, sy = sy, box = box, zk = zk }
  end, 60, 100, 4, 4, { 60, 100, 960, 640 }, opts.view)
  return hd, G, blits, base, wall, hpIcon
end

do
  -- a 1920x1080 window: the UI at the Renderer's 4x, docked to the bottom (y 440); the enemy's
  -- HP box (row 16) raised to topGap (2) UI px under the screen's top: 110 + 14 UI px, its band
  -- blitted 496 px higher, and the fit sees it there
  local view = { 0, 0, 1920, 1080 }
  local hd, _, blits = stackedFrame({ view = view })
  local top, low = 0, 0
  for _, e in ipairs(blits) do
    if e.box and near(e.by, 440 - 496) then top = top + 1 end
    if e.box and near(e.by, 440) then low = low + 1 end
  end
  check(hd.stats.uiTopDy == -124 and near(hd.fit.uiTopDy, -124) and top > 0 and low > 0,
    "a filled landscape battle: the enemy's HP box 2 UI px under the screen's top (" .. tostring(hd.stats.uiTopDy)
    .. ", bands " .. top .. "/" .. low .. ")")
  local hd2 = stackedFrame({ view = view, straddle = true })
  check(hd2.stats.uiTopDy == 0, "...not on a frame whose UI crosses the split (drawn whole)")
  -- a wash over the field drawn with the UI (Galar Rising's red flash on a Max Move): a wash item
  -- over the view, not a draw across the split - the box stays raised
  local hd3 = stackedFrame({ view = view, wash = true })
  check(hd3.stats.uiTopDy == -124, "a wash over the field with the UI: the enemy's HP box stays raised ("
    .. tostring(hd3.stats.uiTopDy) .. ")")
  -- the enemy's HUD drawn as a layer of its own (hd.seam "uiTop"): that layer moves up whole and
  -- the rest stays, so a draw across the split row (stat chips rising from the player's box)
  -- moves nothing back (it had dropped the enemy's box over the player's Pokemon)
  local hd3, G3, blits3, _, _, icon3 = stackedFrame({ view = view, straddle = true, topSeam = true })
  local moved, kept, split = 0, 0, 0
  for _, e in ipairs(blits3) do
    if e.zk or e.box then
      if near(e.by, 440 - 496) then moved = moved + 1 end
      if near(e.by, 440) then kept = kept + 1 end
      if e.box and e.box[4] < 160 * 4 - 1 and near(e.by, 440) then split = split + 1 end
    end
  end
  check(hd3.stats.uiTopDy == -124 and moved == 1 and kept >= 2 and split == 0,
    "the enemy's HUD as its own layer: moved up whole, the rest (a draw across the split) kept, none cut by rows ("
    .. moved .. "/" .. kept .. "/" .. split .. ")")
  local icon
  for _, e in ipairs(G3.log) do if e.image == icon3 then icon = e end end
  check(icon and approx(icon.args[2], 440 - 496 + (20 + 32) * 4),
    "...a tagged draw in that layer goes up with it (" .. tostring(icon and icon.args[2]) .. ")")
end

do
  -- a 1080x2400 phone, touch controls from y 1500 down, a notch to y 40
  local view = { 0, 0, 1080, 2400, top = 40, bottom = 1500 }
  local hd, G, blits, _, wall, hpIcon = stackedFrame({ view = view })
  local U = 4.5
  check(near(hd.stats.uiScale, U), "stacked: the UI spans the width (" .. tostring(hd.stats.uiScale) .. ")")
  -- non-whole: each UI layer is drawn at 5x into a canvas of its own, blitted at 4.5/5
  local ui = {}
  for _, e in ipairs(blits) do if e.zk then ui[#ui + 1] = e end end
  -- (two UI layers: the tagged draw splits them; each in two bands, the HP box's moved up)
  check(#ui == 4 and ui[1].zk == 5 and near(ui[1].sx, U / 5) and ui[1].canvas:getWidth() == 1200,
    "...sharp: drawn at the next whole scale and scaled down")
  local low = ui[2]
  check(low and near(low.by, 1500 - 160 * U) and near(low.bx, 0), "...docked above the controls")
  -- (its top, row 16, stackGap (2) UI px under the scene's top: the scene at the UI's scale,
  -- its row 0 the UI's, far below the notch)
  local dy = 2 - 16
  check(approx(hd.stats.uiTopDy, dy) and approx(ui[1].by + 16 * U, 1500 - 160 * U + 2 * U),
    "the HP box stackGap under the scene's top (" .. tostring(hd.stats.uiTopDy) .. ")")
  check(approx(hd.fit.uiTopDy, dy), "the fit sees the HP box moved up by " .. tostring(hd.fit.uiTopDy))
  -- nothing seen yet: the platforms (x 0 to 240) already span the width, so the scene stays
  -- at the UI's scale, its line on the text box
  check(near(hd.stats.grow, 1) and approx(hd.stats.fill, U / 4), "the scene keeps both platforms whole (" .. tostring(hd.stats.fill) .. ")")
  local b = blits[1]
  check(b and near(b.by + 112 * b.sy, 1500 - 48 * U) and near(b.sx, U) and approx(b.bx, 0),
    "...spanning the width, its line on the text box")
  check(hd.fit.topY < -50 and approx(hd.fit.topY, 112 - (1500 - 48 * U - 40) / U),
    "the screen's top, above the canvas, is the art's limit (" .. tostring(hd.fit.topY) .. ")")
  local icon
  for _, e in ipairs(G.log) do if e.image == hpIcon then icon = e end end
  -- (placed about its default 32, 32 pivot)
  check(icon and approx(icon.args[2], 1500 - 160 * U + (2 - 16 + 20 + 32) * U), "a tagged UI draw in the top band goes up with it ("
    .. tostring(icon and icon.args[2]) .. ")")
  local w
  for _, e in ipairs(G.log) do if e.image == wall then w = w or e end end
  check(w and w.args[3] <= 1e-6, "the wallpaper's sky covers the top of the screen")
  check(w and w.vp[2] >= -1e-6, "...scaled up so its own top row reaches it (none stretched) (" .. tostring(w and w.vp[2]) .. ")")
end

do
  -- stacked, the enemy's HP box stays under the scene's top, wherever the art is drawn
  -- (it hugged the highest art, and Body Slam drawing the Pokemon lower bounced it on a phone)
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local pic, page = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  hd.tag(pic, { texture = page, quad = quad(0, 0, 64, 64), pivot = { 32, 64 }, lowPivot = { 32, 64 },
                side = "enemy", scale = 1 })
  local opts = { wall = canvas("wall", 256, 160), pad = canvas("pad", 256, 160), pic = pic, picY = 40,
                 view = { 0, 0, 1080, 2400, bottom = 1500 } }
  local function run(n) for _ = 1, n do fitFrame(G, hd, base, opts) end return hd.stats.uiTopDy end
  local top = 2 - 16
  local rest = run(30)
  check(approx(rest, top), "stacked: the HP box stackGap under the scene's top (" .. tostring(rest) .. ")")
  hd.setTurn(true)
  opts.picY = 70
  check(run(60) == rest, "...a move drawing the Pokemon lower leaves it there")
  hd.setTurn(false)
  check(run(120) == rest, "...and so after the turn")
  opts.picY = 20
  check(run(30) == rest, "...and with the art higher")
end

-- the battle bar (Gen 3's text box redrawn, src/bar.lua): hd.paint paints at the screen's
-- resolution in the pass's order, cutting off the UI drawn before it at its row (what the cart's
-- taller text box hid); hd.bar's layers move down into the bar, the part left of the split to
-- the screen's left, the rest to its right
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local wall, pad = canvas("wall", 256, 160), canvas("pad", 256, 160)
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  hd.drawStage(pad, 0, 0)
  check(hd.paint(function() end, nil, 112) == false, "bar: no paint in the scene")
  hd.seam("ui")
  G.rectangle("fill", 134, 74, 100, 46)               -- the player's HP box, past row 112
  local told
  check(hd.paint(function(a, ctx)
    told = { a = a, x = ctx.x, y = ctx.y, sx = ctx.sx, l = ctx.l, r = ctx.r, extraL = ctx.extraL, extraR = ctx.extraR }
  end, "menu", 112), "bar: painted in the UI")
  check(hd.bar({ top = 124, bottom = 160, dy = 4, split = 120 }), "bar: its text window opens")
  G.rectangle("fill", 10, 122, 50, 12)                -- the prompt
  G.rectangle("fill", 130, 122, 50, 12)               -- FIGHT
  hd.bar(nil)
  G.rectangle("fill", 20, 20, 30, 10)                 -- drawn after it: a layer of its own
  hd.endPass()
  local blits = {}
  hd.composite(base, function(c, bx, by, sx, sy, box, zk)
    blits[#blits + 1] = { canvas = c, bx = bx, by = by, sx = sx, sy = sy,
                          box = box and { box[1], box[2], box[3], box[4] }, zk = zk }
  end, 480, 220, 4, 4, { 480, 220, 960, 640 }, { 0, 0, 1920, 1080 })
  -- the UI at 4x, centred (x 480) and docked (y 440): 480 px each side of it
  check(told and told.a == "menu" and told.x == 480 and told.y == 440 and told.sx == 4 and told.l == 0
    and told.r == 1920 and told.extraL == 480 and told.extraR == 480,
    "bar: the paint is told where the UI is and the view's sides")
  -- (the HP box raised to the screen's top: each UI layer in two bands, the lower one last)
  local byCanvas, order = {}, {}
  for _, e in ipairs(blits) do
    if e.zk then
      if not byCanvas[e.canvas] then byCanvas[e.canvas] = {}; order[#order + 1] = e.canvas end
      local t = byCanvas[e.canvas]
      t[#t + 1] = e
    end
  end
  local hpB, barB, afterB = byCanvas[order[1]], byCanvas[order[2]], byCanvas[order[3]]
  local hp, left, right, after = hpB and hpB[#hpB], barB and barB[1], barB and barB[2], afterB and afterB[#afterB]
  check(hp and near(hp.box[2] + hp.box[4], 440 + 112 * 4), "bar: the UI drawn before it cut off at row 112 ("
    .. tostring(hp and hp.box[2] + hp.box[4]) .. ")")
  check(left and near(left.bx, 0) and near(left.by, 440 + 16) and near(left.box[1], 0)
    and near(left.box[2], 440 + 124 * 4) and near(left.box[3], 120 * 4) and near(left.box[4], 36 * 4),
    "bar: its text left of the split moved to the screen's left and 4 rows down, cut at the split")
  check(right and right.canvas == left.canvas and near(right.bx, 960) and near(right.box[1], 1440)
    and near(right.box[3], 480), "bar: the rest moved to the screen's right")
  check(after and after.canvas ~= left.canvas and near(after.by, 440) and near(after.box[2] + after.box[4], 1080),
    "bar: what is drawn after it is the UI's as usual, uncut")
  -- put back the low-res way: painted at the canvas's own scale, the text moved down
  told = nil
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.seam("ui")
  hd.paint(function(_, ctx) told = { sx = ctx.sx, r = ctx.r } end, nil, 112)
  hd.bar({ top = 124, bottom = 160, dy = 4 })
  G.rectangle("fill", 10, 122, 50, 12)
  hd.bar(nil)
  local cur = hd.cur
  hd.endPass()
  G.log = {}
  hd.flatten(cur)
  local moved
  for _, e in ipairs(G.log) do if e.op == "draw" and e.args[2] == 4 then moved = true end end
  check(told and told.sx == 1 and told.r == 240 and moved, "bar: a flattened pass paints at 1x and draws its text 4 rows down")
end

-- the bar's art and layout (src/bar.lua)
do
  local Bar = dofile("src/bar.lua")
  check(Bar.TOP == 124 and Bar.BOTTOM - Bar.TOP == 36, "bar: three quarters of the cart's 48 rows")
  check(Bar.layout("emerald") and Bar.layout("rs") and Bar.layout("frlg"), "bar: every Gen 3 layout")
  -- FireRed / LeafGreen: their own panels - gold-framed deep blue messages, violet-framed white menus
  local PF = Bar.panels(Bar.LAYOUT.frlg, "moves", 0, 1920, 480, 4, 480)
  check(PF[1][1] == "frlgMenu" and PF[2][1] == "frlgMenu" and PF[1][3] == 480 + 156 * 4 + 480,
    "bar: FireRed's move names and PP panels its own white ones, split at its PP box")
  PF = Bar.panels(Bar.LAYOUT.frlg, "none", 0, 960, 0, 4, 0)
  check(#PF == 1 and PF[1][1] == "frlgMessage", "bar: FireRed's message panel its own")
  do
    local r, g, b, a = Bar.pixel("frlgMessage", 20, 18, 1e4, true, 0.1)
    check(a > 0.99 and b > r + 0.2 and b > g, "bar: FireRed's message panel deep blue")
    r, g, b = Bar.pixel("frlgMessage", 1.5, 18, 1e4, true, 0.1)
    check(r > b + 0.3 and g > b + 0.2, "bar: its frame gold")
    r, g, b = Bar.pixel("frlgMenu", 1, 18, 1e4, true, 0.1)
    check(b > g and r < 0.6, "bar: FireRed's menu frame violet")
  end
  local P = Bar.panels(Bar.LAYOUT.emerald, "menu", 0, 1920, 480, 4, 480)
  check(#P == 2 and P[1][1] == "message" and P[1][3] == 1440 and P[2][1] == "menu" and P[2][2] == 1440
    and P[2][3] == 1920 and P[1][4] and not P[1][5] and not P[2][4] and P[2][5],
    "bar: the prompt's panel to the menu's, which keeps its width on the screen's right, joined square")
  P = Bar.panels(Bar.LAYOUT.emerald, "moves", 0, 1920, 480, 4, 480)
  check(P[1][1] == "menu" and P[1][3] == 480 + 160 * 4 + 480, "bar: the move names' panel white, to the PP's")
  P = Bar.panels(Bar.LAYOUT.rs, "none", 0, 960, 0, 4, 0)
  check(#P == 1 and P[1][1] == "message" and P[1][2] == 0 and P[1][3] == 960, "bar: a message across the whole bar")
  -- the colours: teal inside the message panel, red on its frame, white in a menu's, the
  -- purple-grey frame round it, a soft shadow above, clear beyond
  local function px(kind, x, y, round)
    local r, g, b, a = Bar.pixel(kind, x, y, 1e4, round ~= false, 0.1)
    return r, g, b, a
  end
  local r, g, b, a = px("message", 20, 18)
  check(a > 0.99 and g > r + 0.15 and b > r + 0.15, "bar: the message panel teal")
  r, g, b = px("message", 1.5, 18)
  check(r > g + 0.3 and r > b + 0.3, "bar: its frame red")
  r, g, b = px("menu", 20, 18)
  check(r > 0.95 and g > 0.95 and b > 0.95, "bar: a menu's panel white")
  r, g, b = px("menu", 1, 18)
  check(b > g and r < 0.6, "bar: its frame purple-grey")
  local _, _, _, sa = px("message", 20, -1)
  local _, _, _, ca = px("message", 20, -3.5)
  local _, _, _, ka = px("message", 0.2, 0.2)
  check(sa > 0.05 and sa < 0.4 and ca == 0 and ka < 0.5, "bar: a soft shadow above, a rounded corner on the edge")
  local _, _, _, sq = px("message", 0.2, 0.2, false)
  check(sq > 0.9, "bar: a square end where panels join")
end

do
  -- a draw across the split: that frame's UI stays in one piece, docked
  local hd, _, blits = stackedFrame({ view = { 0, 0, 1080, 2400, bottom = 1500 }, straddle = true })
  local ui = {}
  for _, e in ipairs(blits) do if e.zk then ui[#ui + 1] = e end end
  check(#ui == 2 and near(ui[1].by, 1500 - 160 * 4.5) and near(ui[2].by, 1500 - 160 * 4.5)
    and hd.stats.uiTopDy == 0,
    "a level-up window across the split: the UI unsplit for that frame")
  check(hd.fit.uiTopDy < 0, "...while the camera keeps the stacked fit (no bob)")
end

do
  -- a whole-number width: no sharpening canvas; controls too tall to dock to: the view's bottom
  local hd, _, blits = stackedFrame({ view = { 0, 0, 960, 2000, bottom = 300 } })
  local last = blits[#blits]
  check(near(hd.stats.uiScale, 4) and last.zk == 1 and last.canvas:getWidth() == 240
    and near(last.by, 2000 - 160 * 4), "4x: blitted straight; no room above the controls: docked to the bottom")
end

do
  -- the solver: a foe's art 30 px above the canvas needs 0.8 framed, none with the sky above
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.fit.zMin = 0.4
  hd.fit.topY, hd.fit.uiTopDy = 0, 0
  local framed = hd.fitSolve(-30, {})
  hd.fit.topY, hd.fit.uiTopDy = -150, -100
  local stackedZ = hd.fitSolve(-30, {})
  check(framed < 0.85 and stackedZ == 1, "stacked: a tall foe rises into the sky instead of shrinking ("
    .. tostring(framed) .. " -> " .. tostring(stackedZ) .. ")")
end

-- stacked, the width short of the top: the sides slide toward each other so the scene grows
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill, hd.fit.zMin = true, true, 0.4
  local fit = hd.fit
  local base = canvas("ui", 240, 160)
  local foe, mine, page = canvas("foe", 64, 64), canvas("mine", 64, 64), canvas("atlas", 4096, 4096)
  -- a foe that fits unzoomed, its feet on y 72; a small back whose body's top (y 72) is no
  -- higher than the foe's feet
  hd.tag(foe, { texture = page, quad = quad(0, 0, 64, 64), pivot = { 32, 64 }, lowPivot = { 32, 64 },
                top = 10, side = "enemy" })
  hd.tag(mine, { texture = page, quad = quad(0, 0, 40, 40), pivot = { 20, 40 }, lowPivot = { 32, 64 },
                 side = "player", body = { 0, 0, 40, 40 } })
  local function frame(view)
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(canvas("wall", 256, 160), 0, 0)
    G.draw(foe, 176, 40, 0, 1, 1, 32, 32)
    G.draw(mine, 72, 80, 0, 1, 1, 32, 32)
    hd.seam("ui")
    G.setColor(0, 0, 0, 0.3)
    G.rectangle("fill", 0, 0, 240, 160)               -- a fade: not a window across the split
    G.setColor(0, 0, 0, 0)
    G.rectangle("fill", 150, 8, 90, 96)                -- an invisible one: neither
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 0, 112, 240, 48)
    hd.endPass()
    hd.composite(base, function() end, 60, 100, 4, 4, { 60, 100, 960, 640 }, view)
    hd.endFrame()
  end
  local tall = { 0, 0, 1080, 2400, bottom = 1500 }
  frame(tall)
  local g1 = hd.stats.grow
  frame(tall)
  check(fit.shift.enemy < 0 and fit.shift.player > 0 and near(fit.shift.enemy, -fit.shift.player),
    "the sides slide toward each other, evenly (" .. fit.shift.enemy .. ", " .. fit.shift.player .. ")")
  -- the foe's frame spans 144..208 and the back's 52..92: centres at most aligned (104 apart)
  check(hd.stats.inward > 0 and hd.stats.inward <= 104 + 1e-6, "...no further than lines their centres up")
  for _ = 1, 200 do frame(tall) end
  check(hd.stats.grow > g1, "...so the scene grows on (" .. tostring(g1) .. " -> " .. tostring(hd.stats.grow) .. ")")
  check(hd.stats.uiTopDy < 0, "a fade or an invisible draw across the split keeps the bands")
  frame({ 0, 0, 1920, 1080 })
  check(hd.stats.inward == 0 and fit.shift.enemy >= 0 and fit.shift.player <= 0,
    "wide: no slide (only the zoom's usual spread)")
end

-- no sprite mod: the Pokemon are drawn by the game where they always are, so nothing slides
-- (their pads would leave them behind)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local fit = hd.fit
  local base = canvas("ui", 240, 160)
  local foe, mine = canvas("foe", 64, 64), canvas("mine", 64, 64)
  local enemyPad, playerPad = canvas("epad", 256, 160), canvas("ppad", 256, 160)
  local pads = {}
  for _ = 1, 30 do
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(canvas("wall", 256, 160), 0, 0)
    hd.drawStage(enemyPad, 0, 0, "enemy")
    hd.drawStage(playerPad, 0, 0, "player")
    G.draw(foe, 176, 40, 0, 1, 1, 32, 32)
    G.draw(mine, 72, 80, 0, 1, 1, 32, 32)
    hd.seam("ui")
    G.rectangle("fill", 0, 112, 240, 48)
    hd.endPass()
    G.log = {}
    hd.composite(base, function() end, 60, 100, 4, 4, { 60, 100, 960, 640 }, { 0, 0, 1080, 2400, bottom = 1500 })
    hd.endFrame()
    for _, e in ipairs(G.log) do if e.image == enemyPad then pads.enemy = e end end
    for _, e in ipairs(G.log) do if e.image == playerPad then pads.player = e end end
  end
  check(hd.stats.inward == 0 and fit.shift.enemy == 0 and fit.shift.player == 0,
    "untagged Pokemon on a tall screen: no slide (" .. tostring(fit.shift.enemy) .. ", " .. tostring(fit.shift.player) .. ")")
  -- each pad drawn where the scene's own canvas puts x 0: with its Pokemon
  local b = pads.enemy and pads.player
  check(b and near(pads.enemy.args[1], pads.player.args[1]), "...both pads stay on the scene's own spots")
end

-- Fill Screen: a whole screen over the battle (the summary, the party, a Pokedex page) and the
-- caught scene are one picture that fills the screen, its edges continued past it (with the
-- blur off: the boot tests below check the blurred backdrop)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill, hd.fit.cardBlur = true, true, false
  local base = canvas("ui", 240, 160)
  local mon = canvas("mon", 64, 64)
  hd.tag(mon, { scale = 1 })
  local function frame(menuAlpha, view, noSeam)
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.backdrop(canvas("wall", 256, 160), 0, 0)
    if not noSeam then hd.seam("ui") end
    G.setColor(1, 1, 1, menuAlpha)
    G.rectangle("fill", 0, 0, 240, 160)
    G.setColor(1, 1, 1, 1)
    G.draw(mon, 120, 80)
    G.rectangle("fill", 0, 112, 240, 48)
    hd.endPass()
    local blits = {}
    G.log = {}
    hd.composite(base, function(c, bx, by, sx, sy, box, zk)
      blits[#blits + 1] = { canvas = c, bx = bx, by = by, sx = sx, sy = sy, box = box, zk = zk }
    end, 240, 60, 6, 6, { 240, 60, 1440, 960 }, view)
    hd.endFrame()
    return blits, cardDraws(G)
  end
  local function pictures(blits)
    local pics = {}
    for _, e in ipairs(blits) do if e.zk then pics[#pics + 1] = e end end
    return pics
  end
  local wide = { 0, 0, 1920, 1080 }
  local blits, edges = frame(1, wide)
  local pics = pictures(blits)
  local U = 6.75
  check(near(hd.stats.uiScale, U) and #pics >= 1 and near(pics[1].bx, 150) and near(pics[1].by, 0)
    and near(pics[1].sx * pics[1].zk, U), "an opaque full-canvas screen is scaled as far as it fits, centred")
  check(pics[1].zk == 7 and near(pics[1].box[3], 1620) and near(pics[1].box[4], 1080), "...sharply, whole")
  check(blits[1].canvas ~= base and blits[1].bx == 0 and blits[1].sx == 1 and blits[1].zk == nil,
    "...first through the blit, one pixel to a pixel (the picture as the game colours it)")
  local left, right = edges[1], edges[2]
  check(left and left.box and near(left.box[1], 0) and near(left.box[3], 150) and near(left.sx, 150)
    and near(left.bx, 0), "its first column runs out to the left edge")
  check(right and right.box and near(right.box[1], 1770) and near(right.box[3], 150) and near(right.sx, 150)
    and near(right.bx + 239 * right.sx, 1770), "its last column to the right edge")
  local icon
  for _, e in ipairs(G.log) do if e.image == mon then icon = e end end
  check(icon and near(icon.args[1], 150 + (120 + 32) * U), "a tagged draw on it is at the picture's scale")
  -- upright, above the touch controls: the width fits; its edge rows above and below
  blits, edges = frame(1, { 0, 0, 1080, 2400, bottom = 1500 })
  pics = pictures(blits)
  check(near(hd.stats.uiScale, 4.5) and near(pics[1].bx, 0) and near(pics[1].by, 1500 - 160 * 4.5),
    "upright: spanning the width, docked above the controls")
  check(edges[1].box and near(edges[1].box[4], 780) and near(edges[1].sy, 780)
    and edges[2].box and near(edges[2].box[2], 1500) and near(edges[2].box[4], 900),
    "...its top row up to the screen's top, its bottom row down to the bottom")
  -- upright with nothing below: centred
  blits = frame(1, { 0, 0, 1080, 2400 })
  pics = pictures(blits)
  check(near(pics[1].by, (2400 - 720) / 2), "upright, no controls: centred")
  -- the caught scene: no seam, the same
  blits = frame(1, wide, true)
  pics = pictures(blits)
  check(near(hd.stats.uiScale, U) and near(pics[1].bx, 150), "a frame with no seam (the caught scene) fills the same")
  -- a translucent cover is not a screen: the battle goes on under it, the cover over the whole screen
  blits = frame(0.5, wide)
  local cover
  for _, e in ipairs(blits) do if near(e.sx, 8) then cover = e end end
  check(hd.stats.fill > 1 and near(hd.stats.uiScale, 6) and cover and near(cover.bx, 0),
    "a half-faded cover keeps the battle's fill, and covers the whole screen")
  -- Fill Screen off: the frame is the Renderer's
  hd.fit.fill = false
  blits = frame(1, wide)
  check(blits[#blits].bx == nil, "Fill Screen off: as the game draws it")
end

-- a double battle's layout: its HP boxes, from setDouble
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled = true
  local single = hd.fit.ui
  local enemy, player = { 1, 5, 104, 54 }, { 137, 62, 239, 110 }
  hd.setDouble(true, enemy, player)
  check(hd.fit.feetMax == 62 and hd.fit.backTopMin == 58 and hd.fit.split == 58 and hd.fit.ui.player == player,
    "doubles: the foes' feet stop at the player's upper box, the UI splits between the two sides")
  check(hd.fitLift(1) == 0, "doubles without tagged foes: the scene keeps its place")
  hd.fit.doubleArt = true
  check(near(hd.fitLift(1), 10), "doubles with tagged foes: the camera rises to clear the boxes")
  hd.setDouble(false)
  check(hd.fit.ui == single and hd.fit.feetMax == 76 and hd.fit.backTopMin == 44 and hd.fit.split == 66
    and hd.fitLift(1) == 0, "back to singles: the singles layout")
  hd.setDouble(true, nil, nil)
  check(hd.fit.double == false, "no box positions: the singles layout")

  -- a battler stands on the shifted coordinates: recorded back on its own spot; one drawn by a
  -- move animation is left where it is
  hd.setDouble(true, enemy, player)
  check(hd.fit.shiftMax == 16, "doubles: the side shift stays small")
  local base, foe = canvas("ui", 240, 160), canvas("foe", 64, 64)
  hd.tag(foe, { side = "enemy" })
  hd.fit.shift.enemy = 10
  G.setCanvas(base)
  hd.beginPass("battle", base)
  G.draw(foe, 210, 40)
  hd.inAnim = true
  G.draw(foe, 210, 40)
  hd.inAnim = false
  local cur = hd.endPass()
  check(near(cur.items[1].rec.tx, -10) and near(cur.items[2].rec.tx, 0),
    "doubles: a battler is recorded on its unshifted spot, an animation's draw is not")
  hd.endFrame()

  -- upright with rows to spare: the scene's line above the player's boxes, the UI where it was
  hd.fit.fill, hd.fit.shift.enemy = true, 0
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.seam("ui")
  G.rectangle("fill", 8, 8, 16, 16)
  hd.endPass()
  hd.composite(base, function() end, 0, 900, 4.5, 4.5, nil, { 0, 0, 1080, 2400, bottom = 1500 })
  hd.endFrame()
  check(near(hd.stats.sceneUp, 54) and near(hd.stats.uiScale, 4.5), "doubles upright: the scene stands above the player's boxes")
  -- ... and the foes' band stackGap (2) UI px under the scene's top - its first row, where
  -- WoobleDex's stat chips may stand above the upper box (chipRowsDouble) - not pinned to the
  -- screen's (the UI docked at 1500 - 160 x 4.5 = 780; the scene's line sceneUp rows above the
  -- text box's)
  do
    local cy = 780 + (112 - hd.stats.sceneUp) * 4.5
    local sceneTop = math.max(0, cy - 112 * 4.5 * hd.stats.grow)
    local boxTop = 780 + (math.min(enemy[2], hd.fit.chipRowsDouble) + hd.fit.uiTopDy) * 4.5
    check(sceneTop > 2 * 4.5 and math.abs(boxTop - (sceneTop + 2 * 4.5)) < 1,
      "doubles upright: the foes' band just under the scene's top (" .. tostring(boxTop) .. ", scene "
      .. tostring(sceneTop) .. ")")
  end
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.seam("ui")
  G.rectangle("fill", 8, 8, 16, 16)
  hd.endPass()
  hd.composite(base, function() end, 0, 0, 6, 6, nil, { 0, 0, 1920, 1080 })
  hd.endFrame()
  check(hd.stats.sceneUp == 0, "doubles on a wide screen: the scene stays on the text box")
  -- an HP box's empty rows may cross the split; a window across it still counts
  local function crosses(y, h)
    G.setCanvas(base)
    hd.beginPass("battle", base)
    hd.seam("ui")
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 0, y, 128, h)
    local c = hd.endPass()
    hd.endFrame()
    return c.uiStraddle == true
  end
  check(not crosses(28, 32), "doubles: an HP box's empty rows do not stop the split")
  check(crosses(30, 60), "doubles: a window across the split still does")
  hd.setDouble(false)
  check(hd.fit.shiftMax == 40, "back to singles: the singles side shift")
end

-- Fill Screen: the screens before the game starts (nothing tagged) are composited, as one picture
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local function frame(view)
    G.setCanvas(base)
    check(hd.beginPass("boot", base) == true, "a boot pass starts")
    G.rectangle("fill", 8, 8, 16, 16)
    local cur = hd.endPass()
    check(hd.done[base] == cur, "...and waits for its blit with nothing tagged")
    local blits = {}
    G.log = {}
    local handled = hd.composite(base, function(c, bx, by, sx, sy, box, zk)
      local sh = G.getShader()
      local u = {}
      if sh then for k, v in pairs(sh.u) do u[k] = { unpack(v) } end end
      blits[#blits + 1] = { canvas = c, bx = bx, by = by, sx = sx, sy = sy, box = box, zk = zk,
                            shader = sh, u = u }
    end, 240, 60, 6, 6, { 240, 60, 1440, 960 }, view)
    hd.endFrame()
    return blits, handled, cardDraws(G)
  end
  local blits, handled, plain = frame({ 0, 0, 1920, 1080 })
  local pic
  for _, e in ipairs(blits) do if e.zk then pic = e end end
  check(handled and near(hd.stats.uiScale, 6.75) and pic and near(pic.bx, 150) and near(pic.by, 0),
    "a boot screen fills the screen, centred")
  -- behind it, the picture blurred at a quarter size, grown to cover the screen (1920 wide: 8 a
  -- game pixel, 32 a blurred one; 1280 tall, centred) and clipped to it
  local soft = plain[1]
  check(soft.canvas.getWidth() == 60 and near(soft.sx, 32) and near(soft.sy, 32) and near(soft.bx, 0)
      and near(soft.by, -100) and soft.box[1] == 0 and soft.box[3] == 1920 and soft.box[4] == 1080
      and soft ~= pic, "...over its picture blurred, covering the screen")
  -- last, the picture's rim fades into it: the backdrop again through the feather, clipped to the
  -- picture; its sides fade (the picture from 150 to 1770 of a backdrop 1920 wide, 4 game pixels
  -- in), its top and bottom, with no gap beside them, do not
  local rim = plain[#plain]
  local r, f = rim.u.rect, rim.u.feather
  local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] end
  check(#plain == 2 and rim.canvas == soft.canvas and r and f and same(rim.box, pic.box)
      and near(r[1], 150 / 1920) and near(r[3], 1770 / 1920) and r[2] < 0 and r[4] > 1
      and near(f[1], 4 * 6.75 / 1920), "...the picture's sides fade into it, its top and bottom do not")
  hd.fit.cardBlur = false
  blits, handled, plain = frame({ 0, 0, 1920, 1080 })
  check(plain[1].box and near(plain[1].box[3], 150), "without the blur its edges run out to the sides")
  blits = frame({ 0, 0, 1080, 2400, bottom = 1500 })
  for _, e in ipairs(blits) do if e.zk then pic = e end end
  check(near(hd.stats.uiScale, 4.5) and near(pic.by, 1500 - 720), "upright: spanning the width, above the controls")
  -- a scale that puts the picture's edges inside a screen pixel (2560x1369: 252.8 to 2307.2): the
  -- clips are cut to whole pixels, so the side strips and the picture together cover every column
  blits, handled, plain = frame({ 0, 0, 2560, 1369 })
  for _, e in ipairs(blits) do if e.zk then pic = e end end
  local left, right = plain[1].box, plain[2].box
  local function cut(b) return math.floor(b[1]), math.floor(b[1]) + math.floor(b[3]) end
  local l0, l1 = cut(left)
  local r0, r1 = cut(right)
  local p0, p1 = cut(pic.box)
  check(near(pic.bx, 252.8) and l0 == 0 and l1 >= p0 and l1 >= 253 and p1 >= r0 and r0 <= 2307 and r1 == 2560,
    "a picture's edge inside a screen pixel leaves no unpainted column")
  -- where the picture went, for the game's own redraws over it; blitted again in parts (a docked
  -- text box apart) in the same frame, the card is drawn once
  do
    G.setCanvas(base)
    hd.beginPass("boot", base)
    local cur = hd.endPass()
    local n = 0
    local function count() n = n + 1 end
    check(hd.composite(base, count, 240, 60, 6, 6, { 240, 60, 1440, 960 }, { 0, 0, 1920, 1080 }) == true
      and hd.uiMap.cur == cur and near(hd.uiMap.x, 150) and near(hd.uiMap.y, 0)
      and near(hd.uiMap.sx, 6.75) and near(hd.uiMap.box[3], 1620), "a card records where its picture went")
    local first = n
    check(hd.composite(base, count, 240, 60, 6, 6, { 240, 60, 1440, 960 }, { 0, 0, 1920, 1080 }) == true
      and n == first, "...and a second blit of its canvas that frame draws nothing more")
    hd.endFrame()
  end
  hd.fit.cardBlur = true
  hd.enabled.boot = false
  G.setCanvas(base)
  check(not hd.beginPass("boot", base), "with Fill Screen off no boot pass starts")
end

-- Fill Screen: a whole screen over the field (the Pokedex, the party, the bag) fills the screen
-- as one picture; its tagged Pokemon at full resolution only with Pokedex & Summary HD on
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.fill = true, true
  local base = canvas("ui", 240, 160)
  local pic = canvas("pic", 64, 64)
  hd.tag(pic, {})
  local function frame()
    G.setCanvas(base)
    check(hd.beginPass("screen", base) == true, "a screen pass starts")
    G.rectangle("fill", 0, 0, 240, 160)
    G.draw(pic, 88, 48)
    local cur = hd.endPass()
    local tagged = 0
    for _, it in ipairs(cur.items) do if it.kind == "hd" then tagged = tagged + 1 end end
    local cards = hd.stats.card or 0
    local handled = hd.composite(base, function() end, 240, 60, 6, 6, { 240, 60, 1440, 960 },
      { 0, 0, 1920, 1080 })
    hd.endFrame()
    return handled and hd.stats.card == cards + 1 and near(hd.stats.uiScale, 6.75), tagged
  end
  local filled, tagged = frame()
  check(filled and tagged == 1, "a screen over the field fills the screen, its Pokemon sharp")
  hd.enabled.dex = false
  filled, tagged = frame()
  check(filled and tagged == 0, "...with Pokedex & Summary HD off its Pokemon are drawn plainly")
  -- with nothing tagged it still waits for its blit
  hd.enabled.dex = true
  G.setCanvas(base)
  hd.beginPass("screen", base)
  G.rectangle("fill", 0, 0, 240, 160)
  local cur = hd.endPass()
  check(hd.done[base] == cur, "a screen with nothing tagged is composited too")
  hd.endFrame()
  hd.enabled.screen = false
  G.setCanvas(base)
  check(not hd.beginPass("screen", base), "with Fill Screen off no screen pass starts")
end

-- Battle Fit off: a full-scene flash is drawn in the layer like anything else
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 240, 160)
  local pic = canvas("pic", 64, 64)
  hd.tag(pic, {})
  G.setCanvas(base)
  hd.beginPass("battle", base)
  G.draw(pic, 0, 0)
  G.rectangle("fill", 10, 10, 2, 2)
  G.rectangle("fill", 0, 0, 240, 160)
  local cur = hd.endPass()
  local layers = 0
  for _, it in ipairs(cur.items) do if it.kind == "layer" then layers = layers + 1 end end
  check(layers == 1, "with Battle Fit off a full-scene draw opens no layer of its own")
end

-- a fitted pass that cannot be composited is put back with its wallpaper
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled = true
  local base = canvas("ui", 240, 160)
  local wall = canvas("wall", 256, 160)
  G.setCanvas(base)
  hd.beginPass("battle", base)
  hd.backdrop(wall, 0, 0)
  G.rectangle("fill", 10, 10, 2, 2)
  hd.seam("ui")
  G.rectangle("fill", 0, 112, 240, 48)
  hd.flatten(hd.cur)
  local sawWall = false
  for _, e in ipairs(G.log) do if e.target == base and e.image == wall then sawWall = true end end
  check(sawWall, "flatten draws the wallpaper into the base canvas")
  local api = assert(loadfile("src/api.lua"))
  local mod = {}
  hd.fit.available = true
  api()(mod, hd, { active = true })
  check(mod.exports.features.battleFit == true and mod.exports.fitEnabled(), "fitEnabled() reports it")
  check(hd.fit.zMin == 0.4, "it pulls back to 40% at most")
  mod.exports.setFit(false)
  check(not mod.exports.fitEnabled() and mod.exports.sceneZoom() == 1, "setFit(false) turns it off")
  mod.exports.setFit("tall")
  check(mod.exports.fitEnabled(), "an old mode name still turns it on")
  mod.exports.setFit("off")
  check(not mod.exports.fitEnabled(), "...and 'off' off")
end

-- ---------------------------------- shaders replay with their own uniforms, remapped for HD
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 240, 160)
  local monLow, monHD = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  local monQuad = quad(200, 100, 94, 94)
  hd.tag(monLow, { texture = monHD, quad = monQuad, pivot = { 47, 90 }, scale = 0.5 })
  local blend, mask, mosaic = G.newShader("blend"), G.newShader("mask"), G.newShader("mosaic")
  local maskTex = canvas("maskTex", 256, 256)
  local function frame(flip)
    G.log = {}
    G.setCanvas(base)
    hd.beginPass("battle", base)
    -- both battlers through one blend shader, each with its own coefficient
    blend:send("coeff", 3)
    G.setShader(blend)
    G.draw(monLow, 100, 50, 0, 1, 1, 32, 32)
    G.rectangle()
    blend:send("coeff", 9)
    G.draw(monLow, 60, 80, 0, 1, 1, 32, 32)
    G.rectangle()
    -- the stat-change pattern, in the battle's pixels
    mask:send("maskTex", maskTex)
    mask:send("origin", { 68, 18 })
    mask:send("size", { 64, 64 })
    mask:send("flip", flip and 1 or 0)
    G.setShader(mask)
    G.draw(monLow, 100, 50, 0, flip and -1 or 1, 1, 32, 32)
    G.rectangle()
    -- mosaic, in the pic's texels
    mosaic:send("texSize", { 64, 64 })
    mosaic:send("block", 4)
    G.setShader(mosaic)
    G.draw(monLow, 100, 50, 0, 1, 1, 32, 32)
    G.setShader()
    blend:send("coeff", 12)                     -- the engine moves on before the composite
    hd.endPass()
    G.log = {}
    hd.composite(base, function() end, 0, 0, 4, 4)
    local hdDraws = {}
    for _, e in ipairs(G.log) do if e.image == monHD then hdDraws[#hdDraws + 1] = e end end
    return hdDraws
  end

  local d = frame(false)
  check(#d == 4, "four HD draws, got " .. #d)
  check(d[1] and d[1].uniforms.coeff == 3 and d[2] and d[2].uniforms.coeff == 9,
    "each blend draw replays its own coefficient")
  check(blend.u.coeff == 12, "after the composite the shader has what it was last sent")
  -- the pattern's position at an HD texel equals the canvas x the HD draw puts it at
  local u = d[3] and d[3].uniforms or {}
  local function pos(th, axis) return u.origin[axis] + th * u.size[axis] end
  check(u.flip == 0, "the pattern is sent unflipped")
  check(u.origin and near(pos((200 + 47) / 4096, 1), 100) and near(pos((100 + 90) / 4096, 2), 50),
    "the HD pivot reads the pattern where the low-res pic's centre did")
  check(u.origin and near(pos((200 + 47 + 10) / 4096, 1), 105), "...10 HD texels on: 5 battle pixels on")
  check(u.maskTex == maskTex, "...the other uniforms are replayed as sent")
  local mu = d[4] and d[4].uniforms or {}
  check(mu.texSize and mu.texSize[1] == 4096 and mu.texSize[2] == 4096, "mosaic is told the HD texture's size")
  check(near(mu.block, 8), "...and blocks of 8 texels (4 pixels at 0.5)")
  check(mosaic.u.block == 4 and mosaic.u.texSize[1] == 64, "...then put back")
  hd.endFrame()

  d = frame(true)
  u = d[3] and d[3].uniforms or {}
  check(u.origin and near(pos((200 + 47 + 10) / 4096, 1), 95), "flipped: 10 HD texels on is 5 battle pixels back")

  -- flattened, the pic draws low-res: its uniforms as sent, not remapped
  G.log = {}
  G.setCanvas(base)
  hd.beginPass("battle", base)
  mask:send("origin", { 68, 18 })
  G.setShader(mask)
  G.draw(monLow, 100, 50, 0, 1, 1, 32, 32)
  G.setShader()
  mask:send("origin", { 0, 0 })
  hd.flatten(hd.cur)
  local low
  for _, e in ipairs(G.log) do if e.image == monLow then low = e end end
  check(low and low.uniforms.origin[1] == 68, "flatten replays the uniforms the draw was made with")
  check(mask.u.origin[1] == 0, "...then puts back the latest")
end

-- ----------------------- a pic drawn row by row (Rapid Spin, Extrasensory): each row its strip
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 240, 160)
  local monLow, monHD = canvas("pic", 64, 64), canvas("atlas", 4096, 4096)
  -- the HD frame: 128x128 at (200, 100), its pivot (64, 64) on the pic's (32, 32), at 0.5
  hd.tag(monLow, { texture = monHD, quad = quad(200, 100, 128, 128), pivot = { 64, 64 }, scale = 0.5 })
  G.setCanvas(base)
  hd.beginPass("battle", base)
  for r = 0, 63 do
    -- the engine's wave: each row of the pic on its own, shifted (pic top-left at y 18)
    G.draw(monLow, quad(0, r, 64, 1), 100 + (r % 2), 18 + r, 0, 1, 1, 32, 0)
  end
  hd.endPass()
  G.log = {}
  hd.composite(base, function() end, 0, 0, 1, 1)
  local rows = {}
  for _, e in ipairs(G.log) do if e.image == monHD then rows[#rows + 1] = e end end
  check(#rows == 64, "every row is drawn, got " .. #rows)
  local okAll = true
  for r = 0, 63 do
    local a = rows[r + 1].args
    local vx, vy, vw, vh = unpack(rows[r + 1].vp)
    -- row r of the pic is HD rows 2r .. 2r+2 of the frame, all of its width
    if not (near(vx, 200) and near(vy, 100 + 2 * r) and near(vw, 128) and near(vh, 2)) then okAll = false end
    -- ... placed where the low-res row was: its top at 18 + r, its pivot column at 100 (+ shift)
    local top = a[3] - a[8] * a[6]
    local px = a[2]
    if not (near(top, 18 + r) and near(px, 100 + (r % 2))) then okAll = false end
  end
  check(okAll, "each row draws only its own strip of the HD frame, where the row was")
end

-- OmniUI draws the screen (src/omni.lua): WoobleView steps aside from it, never from the field
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 240, 160)
  local kind = "battle"
  local loaded = package.loaded["mods.omni_ui.core.ModernOverlay"]
  package.loaded["mods.omni_ui.core.ModernOverlay"] = { getActiveScreen = function() return kind end }
  local opts = {}
  local fakeMod = { game = { mods = { modOptions = { omni_ui = opts } } }, find = function() return {} end }
  local Omni = dofile("src/omni.lua")(fakeMod)
  hd.aside, hd.asideTick, hd.asidePeek = Omni.aside, Omni.tick, Omni.peek
  G.setCanvas(base)
  check(hd.beginPass("battle", base) == false, "no battle pass on a battle OmniUI draws")
  check(hd.stats.aside == "battle", "the step aside is noted")
  check(hd.beginPass("field", base) == true, "the field pass goes on under OmniUI's menus")
  hd.endPass()
  local mod = {}
  assert(loadfile("src/api.lua"))()(mod, hd, { active = true })
  check(mod.exports.enabled("battle") == false and mod.exports.isActive() == true,
    "...and the exports say the battle is off meanwhile (a sprite mod hands over its plain sprites)")
  hd.endFrame()
  -- an evolution with OmniUI's message box over it, then the box gone: the screen stays
  -- stepped aside while it keeps coming
  kind = "dialogue"
  check(hd.beginPass("screen", base) == false, "no screen pass under OmniUI's message box")
  hd.endFrame()
  kind = nil
  check(hd.beginPass("screen", base) == false, "a screen OmniUI claimed last frame stays stepped aside")
  hd.endFrame()
  check(hd.beginPass("screen", base) == false, "... frame after frame while it is shown")
  hd.endFrame()
  hd.endFrame()
  check(hd.beginPass("screen", base) == true, "once that screen stops coming, WoobleView takes the next one")
  hd.endPass()
  hd.endFrame()
  -- its MODERN HIGH-RES UI off, or OmniUI not running: nothing steps aside
  kind, opts.overlay = "battle", false
  check(hd.beginPass("battle", base) == true, "OmniUI's overlay off: the battle is WoobleView's")
  check(mod.exports.enabled("battle") == true, "...and the exports say it is on")
  hd.endPass()
  hd.endFrame()
  opts.overlay = nil
  fakeMod.find = function() return nil end
  check(hd.beginPass("battle", base) == true, "OmniUI not running: the battle is WoobleView's")
  hd.endPass()
  hd.endFrame()
  package.loaded["mods.omni_ui.core.ModernOverlay"] = loaded
end

-- a sprite mod asking the exports (enabled) never changes when WoobleView steps aside: OmniUI
-- claims the battle, then lets it go while the sprite mod keeps asking every frame (its live
-- pics) and no battle pass comes for a while; the next battle is WoobleView's
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  local base = canvas("ui", 240, 160)
  local kind = "battle"
  local loaded = package.loaded["mods.omni_ui.core.ModernOverlay"]
  package.loaded["mods.omni_ui.core.ModernOverlay"] = { getActiveScreen = function() return kind end }
  local opts = {}
  local fakeMod = { game = { mods = { modOptions = { omni_ui = opts } } }, find = function() return {} end }
  local Omni = dofile("src/omni.lua")(fakeMod)
  hd.aside, hd.asideTick, hd.asidePeek = Omni.aside, Omni.tick, Omni.peek
  local mod = {}
  assert(loadfile("src/api.lua"))()(mod, hd, { active = true })
  G.setCanvas(base)
  check(mod.exports.enabled("battle") == false, "a sprite mod asking first: off while OmniUI draws the battle")
  check(hd.beginPass("battle", base) == false, "...and WoobleView steps aside from it the same frame")
  hd.endFrame()
  -- OmniUI's overlay switched off; the sprite mod asks every frame, no battle pass meanwhile
  opts.overlay = false
  check(mod.exports.enabled("battle") == false,
    "...the frame after, still off: held as WoobleView itself would hold it (src/omni.lua)")
  hd.endFrame()
  local onAll = true
  for _ = 1, 5 do
    if mod.exports.enabled("battle") ~= true then onAll = false end
    hd.endFrame()
  end
  check(onAll, "...then on again for the sprite mod, frame after frame")
  check(hd.beginPass("battle", base) == true, "...and the next battle is WoobleView's (the asking held nothing)")
  hd.endPass()
  hd.endFrame()
  package.loaded["mods.omni_ui.core.ModernOverlay"] = loaded
end

-- the Battle Camera (src/scene/orbit.lua): the anchor a battler stands on while the 3D world's
-- view is turned - none at rest; its side's own in singles, the nearest spot in a double battle
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  check(hd.lookFoot("enemy") == nil, "Battle Camera: no 3D world, no anchor")
  local fe = { side = "enemy", frame = 3, u0 = 176, v0 = 70, u = 190, v = 80, r = 1.2 }
  local look = { on = false, frame = 3, feet = { enemy = fe } }
  hd.worldScene = { look = look }
  check(hd.lookFoot("enemy") == nil, "... the view at rest: drawn as without it")
  look.on = true
  check(hd.lookFoot("enemy") == fe and hd.lookFoot("player") == nil, "... turned: its side's anchor")
  fe.frame = 2
  check(hd.lookFoot("enemy") == nil, "... an anchor not given this frame is not used")
  fe.frame = 3
  local a = { side = "enemy", frame = 3, u0 = 200, v0 = 70, u = 210, v = 80, r = 1 }
  local b = { side = "enemy", frame = 3, u0 = 152, v0 = 62, u = 160, v = 70, r = 1 }
  look.double, look.feet[1], look.feet[3] = true, a, b
  check(hd.lookFoot("enemy", 198) == a and hd.lookFoot("enemy", 150) == b and hd.lookFoot("enemy") == fe,
    "... a double battle: the nearest of its side's spots (the side's own for its shadow)")
  -- (what of the world stands in front of a battler drawn over it: only with the world's depth)
  check(hd.occBegin(5, 0, 0, 100, 100) == false, "occlusion: none without the world's depth (drawn as ever)")
  hd.worldScene = nil
  check(hd.occBegin(5, 0, 0, 100, 100) == false, "... nor without a 3D world")
end

print(string.format("%d/%d checks passed (gen3-hd-sprites core)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
