-- Headless checks of src/hd.lua with a fake love.graphics. Run from the mod root:
--   luajit tests/hd_test.lua
local HD = dofile("src/hd.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end

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
  function G.setScissor() end
  function G.clear() G.log[#G.log + 1] = { op = "clear", target = st.canvas } end
  function G.newCanvas(w, h) made = made + 1; return canvas("layer" .. made, w, h) end
  function G.draw(img, ...)
    G.log[#G.log + 1] = { op = "draw", target = st.canvas, image = img, args = { ... },
                          blend = st.blend[2] }
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
  local layer = G.getCanvas()
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
  G.draw(opts.pic, 176, 40, 0, 1, 1, 32, 32)
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
  end, 0, 0, 4, 4, { 0, 0, 960, 640 })
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
  for _, e in ipairs(G.log) do
    if e.image == page then d = e end
    if e.image == wall then w = e end
  end
  check(d and near(d.args[2], 4 * (120 + (176 - 120) * 0.5)) and near(d.args[3], 4 * 76),
    "the sprite stands where its pad went, feet on y = 76 (" .. tostring(d and d.args[2]) .. ", "
    .. tostring(d and d.args[3]) .. ")")
  check(d and near(d.args[5], 2), "...at half its size")
  -- the wallpaper zooms less (parallax) and still covers the whole view
  local zb = 1 - 0.5 * hd.fit.parallax
  check(w and near(w.args[6], 4 * zb), "the wallpaper zooms less: " .. tostring(w and w.args[6]))
  local _, _, uw, vh = w.args[1]:getViewport()
  check(w and w.args[2] <= 1e-9 and w.args[3] <= 1e-9 and near(w.args[2] + uw * w.args[5], 960)
    and near(w.args[3] + vh * w.args[6], 640), "...and is drawn over the whole view, wrapped")
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

  -- no UI seam (the post-catch Pokedex scene): nothing is zoomed
  blits = fitFrame(G, hd, base, { wall = wall, pad = pad, pic = pic, seam = false })
  local anyZoom = false
  for _, b in ipairs(blits) do if b.sx then anyZoom = true end end
  check(not anyZoom, "a frame with no UI seam is composited unzoomed")

  -- the floor: Fit Sprites never pulls back past 60%
  hd.fit.zMin = 0.6
  for _ = 1, 200 do fitFrame(G, hd, base, frame) end
  check(near(hd.stats.zoom, 0.6), "the zoom never goes below zMin")
end

-- Battle Fit and the player's own Pokemon (a back sprite: side = "player", body)
do
  local G = fakeGraphics()
  local hd = HD.new(G)
  hd.install()
  hd.fit.enabled, hd.fit.zMin = true, 0.4
  local fit = hd.fit
  -- a back as drawn: its side lowered so its pad stays tucked, the Pokemon raised above a small
  -- back's pad so minVisible of its body shows
  local function placed(r, z, e)
    local lift = hd.fitLift(z) + e
    local drop = hd.fitPlayerDrop(z, lift)
    local raise = hd.fitBackRaise(r, z, lift, drop)
    local v = drop - raise
    local ue, uo, y0 = hd.fitHidden({ r[1], r[2] + v, r[3], r[4] + v }, z, lift)
    local visible = (fit.focus[2] - y0) / ((r[4] - r[2]) * z)
    local t = r.top and (fit.focus[2] + (r.top + v - fit.focus[2]) * z - lift)
    return ue, uo, y0, t, visible, raise
  end
  local function check2(z, e, rects, label)
    local ok = true
    for _, r in ipairs(rects) do
      local ue, _, y0, _, visible = placed(r, z, e)
      if ue > fit.maxHidden + 1e-9 or y0 < fit.backTopMin - 1e-9 then ok = false end
      if visible < fit.minVisible - 1e-6 then ok = false end
    end
    check(ok, label .. " (zoom " .. string.format("%.3f", z) .. ", rise +" .. e .. ")")
  end

  -- a small back (30 px body, feet 7 px under the text box's top) is raised to show whole; a big
  -- one (79 px) already shows minVisible and keeps the over-the-shoulder cut
  check(math.abs(hd.fitBackRaise({ 20, 89, 50, 119 }, 1, 0, 0) - 7) < 1e-9,
    "a small back is raised until its whole body shows")
  check(hd.fitBackRaise({ 10, 40, 100, 119 }, 1, 0, 0) == 0, "a big back keeps its cut")

  -- a back that shows most of itself already: nothing moves, nothing raised
  local small = { 20, 60, 100, 130 }
  local z, e = hd.fitSolve(math.huge, { small })
  local _, _, _, _, _, raise = placed(small, z, e)
  check(z == 1 and e == 0 and raise == 0, "a back mostly in view: no zoom, no rise, not raised")

  -- a back mostly under the text box (37% shows): raised until 65% shows, standing behind its
  -- pad; raised that high it needs the camera back for its headroom (112 - 0.65 * 140 * z >= 52)
  local deep = { 20, 60, 100, 200 }
  z, e = hd.fitSolve(math.huge, { deep })
  _, _, _, _, _, raise = placed(deep, z, e)
  check(raise > 0, "a back mostly under the text box is raised")
  check2(z, e, { deep }, "...until 65% of it shows, its headroom kept")

  -- a back reaching up under the enemy's HP box: brought down to the cart's headroom
  local high = { 20, 14, 100, 50 }
  z, e = hd.fitSolve(math.huge, { high })
  check2(z, e, { high }, "a back up under the enemy's HP box is brought down to the cart's headroom")

  -- with a tall enemy too: the enemy still fits (its top under the screen's)
  local top = -40
  z, e = hd.fitSolve(top, { deep })
  local lift = hd.fitLift(z) + e
  local enemyTop = fit.focus[2] + (top - fit.focus[2]) * z - lift
  check(enemyTop >= fit.margin - 1e-6, "...and a tall enemy still fits under the top (" .. string.format("%.2f", enemyTop) .. ")")
  check2(z, e, { deep }, "...with the back's headroom and 65% kept")

  -- headroom: a large body that starts above the tallest cart back (row 52) is brought down to
  -- it, and not raised (it shows all of itself)
  local horned = { 20, 30, 140, 112 }
  z, e = hd.fitSolve(math.huge, { horned })
  local _, _, y0, _, _, hraise = placed(horned, z, e)
  check(y0 >= fit.backTopMin - 1e-9 and hraise == 0, "a large back gets the cart's headroom, unraised (top "
    .. string.format("%.2f, zoom %.3f", y0, z) .. ")")
  local _, _, y1 = placed(horned, z + fit.zStep, 0)
  check(z > fit.zMin and y1 < fit.backTopMin, "...and no further back than that ("
    .. string.format("%.3f", z) .. ")")

  -- the whole animation must stay on the screen, but only the resting body needs headroom: a
  -- head flung high in the animation (Blacephalon) pulls back only as far as the screen's top
  local flung = { 20, 60, 100, 112, top = -40 }
  z, e = hd.fitSolve(math.huge, { flung })
  local _, _, _, t = placed(flung, z, e)
  check(t >= fit.margin - 1e-9, "a flung head stays on the screen (" .. string.format("%.2f", t) .. ")")

  -- a back that needs more than the limit: clamped to the limit, not left at the enemy's 1.00
  local huge = { 10, -150, 130, 112, top = -200 }
  z, e = hd.fitSolve(math.huge, { huge })
  check(near(z, fit.zMin) and e == 0, "a back past the limit clamps to zMin (" .. tostring(z) .. "), not 1")
  z = hd.fitSolve(-300, {})
  check(near(z, fit.zMin), "...as an enemy past the limit does")

  -- a back whose headroom is out of reach (its body's top on row -40: even zoom 0.4 with its
  -- side lowered leaves it above 52), with a small enemy: the limit, not 1.00 -- the looser
  -- rules would be met at 1.00, but the limit is still the nearest to the headroom
  local eternatus = { 10, -40, 130, 112 }
  z, e = hd.fitSolve(math.huge, { eternatus })
  check(near(z, fit.zMin), "headroom out of reach clamps to zMin (" .. tostring(z) .. "), not 1")

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
  -- a tall enemy (zoom 0.5) and a small back
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
  local function frame(drawFoe)
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
  mod.exports.setFit("tall")
  check(hd.fit.zMin == 0.4, "setFit('tall') lets it pull back to 40%")
  mod.exports.setFit("off")
  check(not mod.exports.fitEnabled() and mod.exports.sceneZoom() == 1, "setFit('off') turns it off")
end

print(string.format("%d/%d checks passed (gen3-hd-sprites core)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
