-- The player's battle pad, whole. Gen 3 keeps only the top 11 rows of the player's pad: the
-- rest is always under the text box. Battle Fit raises the camera, so that cut shows. Every
-- Gen 3 terrain (FRLG and RSE alike) draws the player's pad as the same 128x32 oval as the
-- enemy's, 112 px left and 53 px down, so the enemy's pad, moved there, is a whole one.
--
-- Built from the art the game imported from the player's own ROM, once per terrain:
--   * inside the oval (OVAL below) every pixel of the enemy pad is copied;
--   * outside it only what is not the wallpaper (the rim, grass tufts, rocks) -- the pad's
--     tiles are opaque rectangles whose corners are ground, and ground moved 53 rows down
--     would not line up with the wallpaper's stripes;
--   * everything else is transparent, so the wallpaper shows around the pad.

local Pads = {}

-- the enemy pad's oval: centre (176, 64), half-axes 64 x 16 (rows 48-79, columns 112-239)
Pads.OVAL = { cx = 176, cy = 64, rx = 64, ry = 16 }
-- where the player's pad stands relative to the enemy's
Pads.DX, Pads.DY = -112, 53
Pads.W, Pads.H = 256, 160

local function insideOval(x, y)
  local o = Pads.OVAL
  local u, v = (x + 0.5 - o.cx) / o.rx, (y + 0.5 - o.cy) / o.ry
  return u * u + v * v <= 1
end

--- The whole player pad as pixels. enemy, bg: readers with getPixel(x, y) -> r, g, b, a
--- (ImageData). out: a blank (transparent) W x H ImageData to fill. Returns out, or nil
--- when the enemy pad does not fill its oval (not a Gen 3 pad: draw the game's own).
function Pads.build(enemy, bg, out)
  local o = Pads.OVAL
  local x0, x1 = o.cx - o.rx, o.cx + o.rx - 1
  local y0, y1 = o.cy - o.ry - 4, o.cy + o.ry + 3     -- a little room for rims and tufts
  -- a Gen 3 pad fills its oval, and most of it is not the ground (FRLG Lance's: 68%)
  local inside, filled, art = 0, 0, 0
  for y = math.max(0, y0), math.min(Pads.H - 1, y1) do
    for x = math.max(0, x0 - 4), math.min(Pads.W - 1, x1 + 4) do
      local r, g, b, a = enemy:getPixel(x, y)
      local keep
      local br, bgc, bb = bg:getPixel(x, y)
      local notGround = a > 0 and (r ~= br or g ~= bgc or b ~= bb)
      if insideOval(x, y) then
        inside = inside + 1
        if a > 0 then filled = filled + 1 end
        if notGround then art = art + 1 end
        keep = a > 0
      else
        keep = notGround
      end
      local tx, ty = x + Pads.DX, y + Pads.DY
      if keep and tx >= 0 and tx < Pads.W and ty >= 0 and ty < Pads.H then
        out:setPixel(tx, ty, r, g, b, a)
      end
    end
  end
  if inside == 0 or filled < inside * 0.95 or art < inside * 0.5 then return nil end
  return out
end

-- an Image's pixels, read back through a canvas (LOVE 11 Images cannot be read directly)
local function readback(G, image)
  local ok, data = pcall(function()
    local c = G.newCanvas(Pads.W, Pads.H, { dpiscale = 1 })
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("replace", "premultiplied")
    G.setColor(1, 1, 1, 1)
    G.clear(0, 0, 0, 0)
    G.draw(image, 0, 0)
    G.pop()
    local d = c:newImageData()
    c:release()
    return d
  end)
  return ok and data or nil
end

local built = setmetatable({}, { __mode = "k" })

--- The whole player pad for a terrain entry (BattleChrome.terrain), as an Image, or nil
--- (then the game's own is drawn). G: the unwrapped graphics functions (hd.real), newImage
--- and newImageData: LOVE's constructors.
function Pads.playerPad(entry, G, newImage, newImageData)
  local hit = built[entry]
  if hit ~= nil then return hit or nil end
  local image = false
  local enemy = entry.enemyPlat and readback(G, entry.enemyPlat)
  local bg = entry.bgImage and readback(G, entry.bgImage)
  if enemy and bg then
    local ok, out = pcall(newImageData, Pads.W, Pads.H)
    if ok and out and Pads.build(enemy, bg, out) then
      local okI, img = pcall(newImage, out)
      if okI and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        image = img
      end
    end
  end
  built[entry] = image
  return image or nil
end

return Pads
