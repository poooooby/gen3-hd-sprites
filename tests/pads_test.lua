-- Headless checks of src/pads.lua with fake ImageData. Run from the mod root:
--   luajit tests/pads_test.lua
local Pads = dofile("src/pads.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local W, H = Pads.W, Pads.H
local function data()
  local px = {}
  local d = {}
  function d:getPixel(x, y)
    local p = px[y * W + x]
    if p then return p[1], p[2], p[3], p[4] end
    return 0, 0, 0, 0
  end
  function d:setPixel(x, y, r, g, b, a) px[y * W + x] = { r, g, b, a } end
  return d
end

-- a wallpaper with the cart's 4-row stripes (A on rows 0 mod 4, B elsewhere)
local A, B = { 0.9, 1, 0.8, 1 }, { 0.8, 0.95, 0.8, 1 }
local PAD, RIM, TUFT = { 0.5, 0.9, 0.5, 1 }, { 0.7, 0.95, 0.4, 1 }, { 0.2, 0.6, 0.2, 1 }
local function ground(y) return y % 4 == 0 and A or B end
local bg = data()
for y = 0, H - 1 do for x = 0, W - 1 do bg:setPixel(x, y, unpack(ground(y))) end end

local function inOval(x, y)
  local u, v = (x + 0.5 - 176) / 64, (y + 0.5 - 64) / 16
  return u * u + v * v <= 1
end

-- the enemy pad: opaque tile rectangle rows 48-79, columns 112-239: ground outside the
-- oval, the pad inside (one interior pixel the ground's colour), a rim pixel and a tuft
local function enemyPad(full)
  local e = data()
  for y = 48, 79 do
    for x = 112, 239 do
      if inOval(x, y) and (full or y < 58) then e:setPixel(x, y, unpack(PAD))
      else e:setPixel(x, y, unpack(ground(y))) end
    end
  end
  e:setPixel(176, 64, unpack(ground(64)))       -- inside the oval, but the ground's colour
  e:setPixel(113, 63, unpack(RIM))              -- just outside the oval: kept (not ground)
  e:setPixel(150, 49, unpack(TUFT))
  return e
end

do
  local out = Pads.build(enemyPad(true), bg, data())
  check(out ~= nil, "a Gen 3 pad builds")
  local function at(x, y) return { out:getPixel(x, y) } end
  local function same(p, q) return p[1] == q[1] and p[2] == q[2] and p[3] == q[3] and p[4] == q[4] end
  -- the oval's centre (176, 64) lands on (64, 117): the player's pad, 112 left, 53 down
  check(same(at(64 + 10, 117), PAD), "the pad stands 112 px left and 53 px down")
  check(same(at(64, 117), ground(64)), "...its interior copied whole, ground-coloured pixel too")
  check(same(at(1, 116), RIM), "...the rim outside the oval is kept")
  check(same(at(38, 102), TUFT), "...and a tuft")
  check(at(5, 101)[4] == 0, "the ground around the oval is transparent")
  check(at(64, 133)[4] == 0 and at(64, 132)[4] > 0, "the whole oval, down to row 132")
  check(at(176, 64)[4] == 0, "nothing is left where the enemy's pad was")
end

do
  check(Pads.build(enemyPad(false), bg, data()) == nil, "a pad that does not fill its oval is not used")
  check(Pads.build(data(), bg, data()) == nil, "...nor no pad at all")
end

print(string.format("%d/%d checks passed (gen3-hd-sprites pads)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
