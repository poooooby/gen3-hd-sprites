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
  function G.rectangle() G.log[#G.log + 1] = { op = "rect", target = st.canvas } end
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

print(string.format("%d/%d checks passed (gen3-hd-sprites core)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
