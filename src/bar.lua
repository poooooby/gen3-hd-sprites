-- Gen 3's battle bar (Ruby, Sapphire, Emerald): the cart's text box and its action / move
-- menus redrawn as one bar across the bottom of the screen, smooth at the screen's
-- resolution, three quarters of the cart's height (36 rows, from canvas row 124 down).
--
-- The look is the cart's, modernised in the way of Emerald 3DS's HD text box (its frame,
-- edge and panel gradients): the message panel red-framed and teal, the menus white with
-- the purple-grey frame, without the cart's dark outer border. The panels sit side by side,
-- joined, the menu's anchored to the screen's right edge. The text and cursors stay the
-- game's own, drawn into a layer of their own (hd.bar) and moved into the bar.
--
-- Each panel is drawn from three pieces cached per scale: its left end, one column stretched
-- across its middle, its right end (the left one mirrored). Ends on the screen's edge are
-- rounded; ends where two panels meet are square, so the panels join.

local Bar = {}

-- canvas rows: the bar's top (the cart's text box starts at 112) and the screen's bottom
Bar.TOP, Bar.BOTTOM = 124, 160
-- the bar's height in UI px, and the room above it its shadow takes
local H, PAD = Bar.BOTTOM - Bar.TOP, 3

-- per layout: how far the game's text moves down into the bar (dy, canvas rows) and where
-- the menus' panel starts in each panel mode (canvas x: the cart's menu frame's left edge;
-- nil: one panel across)
-- Ruby / Sapphire's red cursor box widened this many canvas px to the left in the bar (the
-- cart's starts a pixel left of its text)
Bar.CURSOR_PAD = 2

Bar.LAYOUT = {
  emerald = { dy = 4, split = { menu = 120, moves = 160 } },
  rs = { dy = 6, split = { menu = 136, moves = 176 } },
}

local function rgb(hex)
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- each panel kind's colours and frame (UI px): the frame's gradient (top, middle, bottom),
-- its top rim's highlight, the line inside it, the panel's gradient, the panel's inner shadow
Bar.KINDS = {
  message = {
    frame = { rgb("ea6650"), rgb("d64a3a"), rgb("b4382c") }, rim = rgb("ffb8a4"),
    line = { rgb("8c9494"), rgb("747c7e") },
    panel = { rgb("80baba"), rgb("6ba5a5"), rgb("5a9496") },
    shade = rgb("284648"), shadeA = 0.27,
    side = 4, seam = 2, topF = 1.5, botF = 1.5, lineW = 1,
  },
  menu = {
    frame = { rgb("877f9b"), rgb("736b84"), rgb("5e576f") }, rim = rgb("aeaeea"),
    line = { rgb("e6dfe6"), rgb("d6cfd8") },
    panel = { rgb("ffffff"), rgb("faf9fb"), rgb("eeebf1") },
    shade = rgb("5a5070"), shadeA = 0.14,
    side = 3, seam = 2, topF = 1.5, botF = 1.5, lineW = 1,
  },
}
local RADIUS = 4      -- an outer end's top corners (UI px)
local INNER_R = 2.5   -- the line's and panel's corners

--- The game layout's numbers (nil: no bar for it).
function Bar.layout(name)
  return Bar.LAYOUT[name]
end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function grad3(c, t)
  if t < 0.5 then
    local k = t / 0.5
    return lerp(c[1][1], c[2][1], k), lerp(c[1][2], c[2][2], k), lerp(c[1][3], c[2][3], k)
  end
  local k = (t - 0.5) / 0.5
  return lerp(c[2][1], c[3][1], k), lerp(c[2][2], c[3][2], k), lerp(c[2][3], c[3][3], k)
end

-- signed distance (UI px) from (x, y) to a box from (x0, y0) to (x1, y1) whose top corners on
-- the left are rounded by rl and on the right by rr (its bottom corners square: the bar runs
-- off the bottom); negative inside
local function sdBox(x, y, x0, y0, x1, y1, rl, rr)
  if rl > 0 and x < x0 + rl and y < y0 + rl then
    local dx, dy = x - (x0 + rl), y - (y0 + rl)
    return math.sqrt(dx * dx + dy * dy) - rl
  end
  if rr > 0 and x > x1 - rr and y < y0 + rr then
    local dx, dy = x - (x1 - rr), y - (y0 + rr)
    return math.sqrt(dx * dx + dy * dy) - rr
  end
  return math.max(x0 - x, x - x1, y0 - y, y - y1)
end

--- The colour (r, g, b, a: straight alpha) of a panel of `kind` at (x, y) UI px, the panel
--- from x 0 to w (w large: its left end only), y 0 (the bar's top) to H; `round`: its left
--- end on the screen's edge (rounded), else at a seam (square, thinner).
function Bar.pixel(kind, x, y, w, round, aa)
  local K = Bar.KINDS[kind]
  aa = aa or 0.25
  local side = round and K.side or K.seam
  local rl = round and RADIUS or 0
  local function cover(d) return clamp01(0.5 - d / (2 * aa)) end
  -- the shadow it casts up onto the scene
  local r, g, b, a = 0.04, 0.10, 0.08, 0
  if y < 0 then
    local d = sdBox(x, 1, 0, 0, w, H + 10, rl, rl)
    if d < 0 then a = 0.32 * (1 - clamp01(-y / PAD)) ^ 2 end
  end
  local function over(cr, cg, cb, ca)
    local oa = ca + a * (1 - ca)
    if oa <= 0 then return end
    r = (cr * ca + r * a * (1 - ca)) / oa
    g = (cg * ca + g * a * (1 - ca)) / oa
    b = (cb * ca + b * a * (1 - ca)) / oa
    a = oa
  end
  local t = clamp01(y / H)
  -- the frame
  local fc = cover(sdBox(x, y, 0, 0, w, H + 10, rl, rl))
  if fc > 0 then
    local fr, fg, fb = grad3(K.frame, t)
    over(fr, fg, fb, fc)
    -- its top rim's highlight, fading down
    local rim = clamp01(1 - (y - 0.2) / 0.9) * 0.75
    if rim > 0 then over(K.rim[1], K.rim[2], K.rim[3], rim * fc) end
  end
  -- the line inside it
  local lx0, ly0, ly1 = side, K.topF, H - K.botF
  local lr = round and INNER_R or 0
  local lc = cover(sdBox(x, y, lx0, ly0, w - lx0, ly1, lr, lr))
  if lc > 0 then
    local k = clamp01((y - ly0) / (ly1 - ly0))
    over(lerp(K.line[1][1], K.line[2][1], k), lerp(K.line[1][2], K.line[2][2], k),
      lerp(K.line[1][3], K.line[2][3], k), lc)
  end
  -- the panel
  local px0, py0, py1 = lx0 + K.lineW, ly0 + K.lineW, ly1 - K.lineW
  local pr = round and math.max(0, INNER_R - 0.5) or 0
  local pc = cover(sdBox(x, y, px0, py0, w - px0, py1, pr, pr))
  if pc > 0 then
    local pr2, pg2, pb2 = grad3(K.panel, clamp01((y - py0) / (py1 - py0)))
    over(pr2, pg2, pb2, pc)
    -- its inner shadow under the top edge
    local sh = clamp01(1 - (y - py0) / 2.2) * K.shadeA
    if sh > 0 then over(K.shade[1], K.shade[2], K.shade[3], sh * pc) end
  end
  return r, g, b, a
end

-- the cached pieces: [kind .. end .. scale] = { image, width }
local pieces = {}
local CAP = 9   -- an end piece's width (UI px): past the side, the corners and the line

-- a panel's end (round or seam) or its middle column ("mid"), at s screen px per UI px
local function piece(kind, which, s)
  local key = kind .. which .. string.format("%.3f", s)
  local p = pieces[key]
  if p then return p end
  local w = which == "mid" and 1 or math.ceil(CAP * s)
  local h = math.ceil((H + PAD) * s)
  local data = love.image.newImageData(w, h)
  local aa = 0.5 / s
  for py = 0, h - 1 do
    local y = (py + 0.5) / s - PAD
    for px = 0, w - 1 do
      -- (the middle: a column far from either end)
      local x = which == "mid" and CAP + 5 or (px + 0.5) / s
      local r, g, b, a = Bar.pixel(kind, x, y, 1e4, which == "round", aa)
      data:setPixel(px, py, r, g, b, a)
    end
  end
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  p = { image = image, w = w, h = h }
  pieces[key] = p
  return p
end

--- Forget the cached pieces (a new window size makes new ones anyway).
function Bar.reset()
  for k, p in pairs(pieces) do
    if p.image and p.image.release then pcall(p.image.release, p.image) end
    pieces[k] = nil
  end
end

--- Where the menus' panel starts (screen px): the cart's split column (canvas x, on the UI
--- at x, sx) moved right with the UI's right margin (extraR), so that panel keeps its width
--- and ends on the screen's right edge.
function Bar.splitX(split, x, sx, extraR)
  return math.floor(x + split * sx + extraR + 0.5)
end

--- The panels for a panel mode ("none": the message; "menu": the prompt and the action menu;
--- "moves": the move names and their PP / type), as { kind, x0, x1, leftRound, rightRound }
--- in screen px, from the view's left (l) to its right (r).
function Bar.panels(L, mode, l, r, x, sx, extraR)
  local split = L.split[mode]
  if not split then return { { "message", l, r, true, true } } end
  local d = Bar.splitX(split, x, sx, extraR)
  local left = mode == "moves" and "menu" or "message"
  return { { left, l, d, true, false }, { "menu", d, r, false, true } }
end

local function drawPanel(kind, x0, x1, lr, rr, top, s)
  local a = piece(kind, lr and "round" or "seam", s)
  local b = piece(kind, rr and "round" or "seam", s)
  local m = piece(kind, "mid", s)
  local y = top - math.ceil(PAD * s)
  local w = x1 - x0
  local aw, bw = math.min(a.w, math.floor(w / 2)), math.min(b.w, math.floor(w / 2))
  love.graphics.draw(a.image, x0, y)
  love.graphics.draw(b.image, x1, y, 0, -1, 1)
  if w - aw - bw > 0 then love.graphics.draw(m.image, x0 + aw, y, 0, w - aw - bw, 1) end
end

--- hd.paint's function: the bar under this frame's text. a: { layout = Bar.LAYOUT entry,
--- mode = panel mode }; ctx: where the UI is on the screen (x, y, sx, sy) and the view's
--- left and right (l, r), the UI's margin to its right (extraR).
function Bar.paint(a, ctx)
  local s = ctx.sy
  local top = math.floor(ctx.y + Bar.TOP * s + 0.5)
  local l, r = math.floor(ctx.l + 0.5), math.floor(ctx.r + 0.5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("alpha", "alphamultiply")
  local split = a.layout.split[a.mode]
  if not split then
    drawPanel("message", l, r, true, true, top, s)
    return
  end
  local d = Bar.splitX(split, ctx.x, ctx.sx, ctx.extraR or 0)
  drawPanel(a.mode == "moves" and "menu" or "message", l, d, true, false, top, s)
  drawPanel("menu", d, r, false, true, top, s)
end

return Bar
