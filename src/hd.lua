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
    -- boot: a screen before the game starts; screen: a whole screen opened over the field (the
    -- Pokedex, the party, the bag, the options, the mods); both only fill the screen
    enabled = { battle = true, field = true, dex = true, boot = true, screen = true },
    -- most splits (window-sized layers) a pass may use; a tagged draw past it is drawn low-res
    caps = { battle = 8, field = 12, dex = 8, boot = 8, screen = 8 },
    cur = nil,          -- the pass being captured
    direct = false,     -- the pass drawn straight at window resolution (self.beginDirect)
    done = {},          -- finished passes waiting for their blit, by base canvas
    -- where the last pass composited to fill the screen put its UI (a card: its whole
    -- picture), for the game's own draws over it (src/engine.lua): its pass, the screen point
    -- canvas pixel (0, 0) went to, the size of a canvas pixel and its clip; banded: the rows
    -- above `split` moved up to `topY` (an upright battle's top band), clipped to topBox, the
    -- rest to lowBox
    uiMap = { cur = nil, x = 0, y = 0, sx = 1, sy = 1, box = { 0, 0, 0, 0 },
              banded = false, split = 0, topY = 0, topBox = { 0, 0, 0, 0 }, lowBox = { 0, 0, 0, 0 } },
    -- this frame's UI canvas went where uiMap says (a filled screen or a card placed it): set
    -- by the engine wrap's blit, cleared as a frame begins; false when the Renderer blitted it
    -- itself (exports.uiMap, read until the next frame begins: render.hud too)
    uiLive = false,
    pool = {},          -- layer canvases by "w x h" -> list
    stats = { splits = 0, composites = 0, flattened = 0, overCap = 0, zoom = 1, zoomTarget = 1, lift = 0 },
    -- Battle Fit (see the header). z eases toward target: out fast, back in only after the
    -- target has stayed larger for holdFrames, so a sprite's animation never pumps it.
    fit = {
      -- zMin: the farthest it may pull back (40% fits the very biggest, Lugia and Koraidon)
      enabled = false, available = false, zMin = 0.4, focus = { 120, 112 }, margin = 2, parallax = 0.35,
      -- outside the 3D world each battle Pokemon is drawn at its tag's own size (the sprite
      -- mod's), shrunk only when it is too big for its room, in canvas px: its picture box grown
      -- `up` rows above its top and `left` / `right` columns beside it (fillScale). Gen 3: the
      -- enemy up to the screen's top (its box at 144-208, from row 8), the player's up to the
      -- enemy's HP box's bottom (44, or where the top band has moved it; its box at 40-104, from
      -- row 52: it stands on its pad, the UI over its lower rows as in the cart), each 16 columns
      -- wider
      fitRoom = { enemy = { up = 8, left = 16, right = 16 }, player = { up = 8, left = 16, right = 16 } },
      -- in the 3D world (worldSize): no battler's art smaller than worldMin of the battle's 160
      -- rows, by its longest side (height or width: a flat Wishiwashi counts its width), nor
      -- than worldShare of the tallest on the field's art height (a Pikachu beside a Wailord
      -- still reads), both before the camera's zoom, so every screen shape draws the pair alike;
      -- above them, true to scale. A wide one (its art wider than tall: a long, low Zigzagoon)
      -- has both raised by its width over its height, at most wideFloor times
      worldMin = 0.1, worldShare = 0.2, wideFloor = 1.4,
      -- ... and a soft ceiling on height: true to size up to heightKnee metres, a taller one
      -- eased toward heightMax (a foe's heightMaxFoe) and never past it, the taller still the
      -- taller (knee + (max - knee) * (1 - e^-((h - knee) / (max - knee))): Groudon's 3.5 m drawn
      -- 3.4, Steelix's 9.2 just under 5, Wailord's 14.5 just under 5), so a giant never needs the
      -- camera pulled far back. And no art wider than widthMax metres (its art box's width at
      -- that height): a wide giant (Wailord) drawn smaller to fit it, a tall, thin one
      -- (Steelix) keeping its height. (Metres at a metre a tile: tuned at half a metre, as 1.5,
      -- 2.5, 2.25 and 3, the giants came out half as tall when the tile went back to a metre)
      heightKnee = 3, heightMax = 5, heightMaxFoe = 4.5, widthMax = 6,
      -- ... and a Pokemon another mod draws giant for a while (exports.giant: Galar Rising's
      -- Dynamax, a Gigantamax form) grows toward giantHeight metres: the tallest Pokemon's,
      -- Eternatus aside (Celesteela, its art's standing height in the sprite mods' measure),
      -- under the player's soft ceiling (a foe's too; no room's ceiling): as tall as the tallest
      -- Pokemon stands outdoors, not the anime's 100 ft; and at least giantMin times its own size
      giantHeight = 10.05, giantMin = 1.5,
      -- ... in a double battle, four sharing the screen: the soft ceiling from heightKneeDouble
      -- toward heightMaxDouble, and each no wider than its spot allows: Gen 3's four battler
      -- columns (doubleSpots, canvas px: the player's 32 and 90, the foes' 152 and 200) spread
      -- apart about the focus column (fit.spread, up to spreadMax, as far as keeps the outer two's
      -- feet spreadEdge canvas px inside the screen at the camera's target zoom: set when a new
      -- Pokemon comes out, eased spreadEase of the way a frame), split halfway between
      -- neighbours, less spotGap, so none reaches over the next (the outer sides left to the
      -- screen). Each battler, its shadow and the engine's coordinates for it move with its spot
      -- (worldSizes: the 3D world's sizing at all, the 3D Sizing option; false: its battlers
      -- drawn and framed as outside it)
      worldSizes = true,
      -- (sizeMode: how true the sizes, 3D Sizing's other choices. "medium": as above. "minimal":
      -- medium's sizes, floors and all, drawn toward minimalMid metres, mid * (h / mid) ^
      -- minimalPow (a Pikachu drawn as 0.62 m beside a Wailord drawn 0.70, the Wailord's eased
      -- 4.3 drawn 3.0). "accurate":
      -- the tag's measured height as it is (WoobleSpritePack's, WoobleDex's artHeightOf `art`:
      -- one dataset): no soft ceiling, no width cap, no floors but worldMinAccurate of the
      -- battle's height; the camera's furthest view and a room's ceiling still hold it)
      sizeMode = "medium", minimalMid = 1, minimalPow = 0.75, worldMinAccurate = 0.04,
      -- (doublesOwnSize: a double battle's four drawn at the sprite mod's own size instead, as
      -- it is, and nothing else done: no world scale, no shrinking (they may overlap a little),
      -- no spread, the camera at zoom 1, the HP boxes where the game puts them)
      doublesOwnSize = true,
      heightKneeDouble = 2, heightMaxDouble = 5, doubleSpots = { 32, 90, 152, 200 }, spotGap = 2,
      spreadMax = 1.6, spreadEdge = 20, spreadEase = 0.1,
      -- ... and in singles a wide one stepped out toward its own edge, partly off the screen,
      -- rather than reaching across the middle: the player's art no further right than wideLine
      -- of the screen's width from its left, the foe's no further left than wideLine from its
      -- right (the camera is fitted to where they rest, so it never pulls back for this), but
      -- never so far that less than wideKeep of its art's width stays on the screen
      wideLine = 0.45, wideKeep = 0.6,
      -- ... and the foe's HP box (a double battle's two) just over the highest head (a foe's or
      -- a player's art top), headGap UI px above it, the camera leaving room for it under the
      -- screen's top (headMargin UI px); worked out when a new Pokemon comes out, from where the
      -- camera is heading, then held (a faint, the battle's end move nothing), eased boxEase of
      -- the way a frame when it moves. A giant that needs the camera pulled back has it pulled
      -- back bigPull further
      headGap = 2, headMargin = 2, boxEase = 0.25, bigPull = 0.9,
      -- ... and when every battler is small (the camera needs no pulling back), it comes in, up
      -- to zMax, toward the tallest's art standing smallFill of the battle's height (the
      -- screen's top to the text box), as far as every art top stays on the screen and under
      -- the foe's HP box where it is under its columns, every art inside the screen's sides,
      -- and zoomInShow of each of the player's above the text box (the zoom, about the focus
      -- row, sinks it when the text box's line is not that row). A small foe beside a bigger
      -- Pokemon of the player's brings it in too, gently: toward the foe's art standing smallFoe
      -- of that height, up to zFoeMax, within the same bounds (a Capsakid before a Dewott)
      zMax = 2.5, smallFill = 0.3, zoomInShow = 0.75, smallFoe = 0.17, zFoeMax = 1.4,
      -- the 3D world's singles: a move's effects grown with a Pokemon drawn bigger than the
      -- sprite mod draws it (its world scale over the mod's, at least 1, at most fxMax), each
      -- piece about its own middle by the factor where it lies on the line between the two
      -- (a beam widens toward a giant); none past fxBig of the canvas across (a background)
      fxGrow = true, fxMax = 4, fxBig = 0.6,
      -- ... and indoors (a room or a cave: the scene's `indoor`) a ceiling: an art height over
      -- indoorKnee metres eases toward indoorCeiling (a Wailord in a gym stands about 3 m, not
      -- 6.4, so the camera need not pull back past the walls); below the knee, true to scale
      indoorKnee = 2, indoorCeiling = 3,
      -- the enemy's HP box (rows 16-44) raised to this many UI px under the screen's top on a
      -- wide screen the battle fills (singles; Gen 3): the player's HP box's gap over the text
      -- box (110 to 112). stackGap: the same under the scene's top on a tall (stacked) one, in
      -- every game. It stays there whatever the art does; the fit sees it there (uiTopDy), the
      -- most the player's Pokemon may rise to
      topGap = 2, stackGap = 2,
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
      -- ... and with nothing below to dock to (no touch controls), the whole block is raised
      -- (raise, screen px, settling from frame to frame) to sit centred: sky above, ground below
      raise = 0, anchor = nil,
      -- the battle UI over the scene, in canvas pixels (singles, both cart layouts): the
      -- enemy's HP box, the player's HP box, the text box (and everything below it, off the
      -- screen too). Where the UI covers a Pokemon is told in the stats (hiddenEnemyUI,
      -- hiddenOwnUI); the camera makes no room for it
      ui = { enemy = { 14, 16, 113, 44 }, player = { 134, 74, 236, 110 }, text = { -1e4, 112, 1e4, 1e4 } },
      -- the enemy's HP box's bottom (44): the tallest cart back sprites (Tyranitar, Steelix,
      -- Meganium) start 8 px lower, at row 0 of the 64x64 back box centred at y = 80 + 4
      backTopMin = 44,
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
      outRate = 0.2, inRate = 0.05, holdFrames = 45,
      -- a turn playing (setTurn: the adapter's battle phase, not the menu): the camera may pull
      -- out but never comes back in until the battle waits for the player again. A move swells,
      -- lunges or lifts a Pokemon for a moment (Bulk Up, Growth, a jump); in a double battle and
      -- on Red to Crystal (no resting pose to plan by, as Gen 3's singles have) the camera
      -- followed each one out and back, move after move
      turn = false,
      z = 1, target = 1, extra = 0, extraTarget = 0, hold = 0, idle = 99,
      -- a double battle (setDouble): a back's head stops this far below the foes' lower HP box.
      -- Its outer battlers stand near the canvas's edges, so the side shift is smaller: a move's
      -- effect on them stays inside the canvas. sceneUp: on a tall screen the scene's line is
      -- raised this many UI rows above the text box, clear of the player's two HP boxes
      -- doublesSlack: rows a UI draw may cross the split and still not count as crossing it (an HP
      -- box is drawn on an image taller than the box: the empty rows meet those of the next one)
      double = false, doublesGap = 4, doublesShiftMax = 16, doublesSlack = 4, sceneUp = 0,
      -- ... and the foes' band moved up (Fill Screen) keeps its row chipRowsDouble on the screen, not
      -- only the upper box's top: WoobleDex's stat chips stand beside the foes' boxes from it
      chipRowsDouble = 0,
      -- a whole screen filling the screen (compositeCard): beyond the picture, the picture blurred
      -- and dimmed to cardDim (cardBlur), or its edge pixels continued outward; with the blur, the
      -- picture's rim fades into it over cardFeather game pixels
      cardBlur = true, cardDim = 0.80, cardFeather = 4,
    },
  }
  self.fit.singles = { ui = self.fit.ui, feetMax = self.fit.feetMax, backTopMin = self.fit.backTopMin,
    split = self.fit.split, shiftMax = self.fit.shiftMax }

  -- Battle layouts: the canvas numbers of one generation's battle screen (its text box's line,
  -- its HP boxes, where its Pokemon stand), by name. The adapter picks one (useLayout) before a
  -- battle pass; "gen3" is the table above.
  local LAYOUT_KEYS = { "focus", "feetY", "feetMax", "split", "spanDefault", "pads", "inwardMax",
    "ui", "backTopMin", "extraMax", "enemyX", "playerX", "shiftMax", "ground", "padTop", "padRows",
    "padTuck", "fitRoom", "topGap" }
  self.layouts = { gen3 = {} }
  for _, key in ipairs(LAYOUT_KEYS) do self.layouts.gen3[key] = self.fit[key] end
  self.layout = "gen3"

  --- Use the battle layout `name` (self.layouts) from now on; returns whether it exists. A key
  --- a layout leaves out is false (no pads, no ground rows). A double battle's own numbers
  --- (setDouble) are set again over it.
  function self.useLayout(name)
    local L = self.layouts[name]
    if not L then return false end
    if self.layout == name then return true end
    self.layout = name
    local fit = self.fit
    for _, key in ipairs(LAYOUT_KEYS) do
      local v = L[key]
      if v == nil then v = false end
      fit[key] = v
    end
    fit.singles = { ui = fit.ui, feetMax = fit.feetMax, backTopMin = fit.backTopMin,
      split = fit.split, shiftMax = fit.shiftMax }
    if fit.double then
      fit.double = false
      fit.doubleArt = false
    end
    return true
  end
  local real = {}
  self.real = real

  -- A scissor over every pixel of a box (x, y, w, h in units). LÖVE takes a scissor in whole
  -- units, dropping each number's fraction, then turns it into pixels by the target's DPI
  -- scale, dropping each fraction again: on a fractional DPI (Android's 2.625) a box's own
  -- numbers lose up to four pixels at its right and bottom, where whatever was under the
  -- screen showed through (a white line beside a battle panel). So: out to whole units, and one
  -- more on a fractional DPI. (no garbage)
  local function scissorOver(x, y, w, h)
    local c = real.getCanvas and real.getCanvas()
    local d = 1
    if c and type(c.getDPIScale) == "function" then
      d = c:getDPIScale()
    elseif love and love.graphics and love.graphics.getDPIScale then
      d = love.graphics.getDPIScale()
    end
    local x0, y0 = math.floor(x + 1e-6), math.floor(y + 1e-6)
    local extra = (d % 1 ~= 0) and 1 or 0
    real.setScissor(x0, y0, math.max(0, math.ceil(x + w - 1e-6) - x0 + extra),
      math.max(0, math.ceil(y + h - 1e-6) - y0 + extra))
  end
  self.scissorOver = scissorOver

  -- ---------------------------------------------------------------- shaders

  -- what each shader was last sent: sent[shader][name] = { fn = the send used, n, values... }
  -- A record is reused by the next send of its uniform (no garbage a send: every mod's shaders
  -- send each frame) unless a recorded draw holds it (`shared`, set by the draw): then a new one.
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
          local u = sent[sh]
          if not u then
            u = {}
            sent[sh] = u
          end
          local v = u[uniform]
          if not v or v.shared then
            v = { copies = {} }
            u[uniform] = v
          end
          local n = select("#", ...)
          v.fn, v.n = fn, n
          -- a vector or array is copied (it may be reused and changed) into the record's own
          -- table for that place; anything else is kept
          local copies = v.copies
          for i = 1, n do
            local x = (select(i, ...))
            if type(x) == "table" and x[1] ~= nil then
              local copy = copies[i]
              if copy then
                for k in pairs(copy) do copy[k] = nil end
              else
                copy = {}
                copies[i] = copy
              end
              for k, y in pairs(x) do copy[k] = y end
              v[i] = copy
            else
              v[i] = x
            end
          end
          return fn(sh, uniform, ...)
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
  ---         quadPivots = { [quad] = {x, y, scale?} }|nil,
  ---         flip = true|nil (texture's frame mirrored about its pivot),
  ---         shades = shader|nil (the stand-in is in the Game Boy's shades, made by this shader
  ---           from the frame's colours: the frame is drawn through it, then coloured by the
  ---           game as the stand-in would be),
  ---         shadow = { texture = img, quad = q|nil, w = px, dx = px, dy = px }|nil (a contact
  ---           shadow under the frame, which the stand-in has baked in: w wide, its bottom
  ---           middle at (dx, dy) from the pivot, all in the frame's pixels; drawn first, at
  ---           the frame's final size and with its flip) }  (read at draw time)
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
  -- open (cur.open, the kind of layer the pass draws into; nil: an ordinary one):
  --   "screen": whole-scene draws, composited without Battle Fit's zoom, covering the screen
  --   "edge": a move's effect anchored to the canvas's sides (Fake Out's curtains, Encore's
  --     dimming), zoomed with the scene, its edge pixels run on out to the screen's sides
  -- The frame's records and items, from two pools taken in turn a frame (self.endFrame swaps
  -- them): a pass's are read by its composite or flatten the frame it is drawn (a field pass
  -- ends with the world pass, the others by the frame's end) - so a pool is filled again only
  -- the frame after next. A record keeps its colour, blend and uniforms tables; an item is
  -- emptied. Past POOL_MAX in a frame (the frame never ends: no Renderer), new tables.
  local POOL_MAX = 4096
  local recPools, itemPools = { { n = 0 }, { n = 0 } }, { { n = 0 }, { n = 0 } }
  local poolTurn = 1
  local function pooledRec()
    local p = recPools[poolTurn]
    if p.n >= POOL_MAX then return { color = {}, blend = {} } end
    local n = p.n + 1
    p.n = n
    local t = p[n]
    if not t then t = { color = {}, blend = {} }; p[n] = t end
    return t
  end
  local function newItem(kind)
    local p = itemPools[poolTurn]
    local t
    if p.n >= POOL_MAX then
      t = {}
    else
      local n = p.n + 1
      p.n = n
      t = p[n]
      if t then
        for k in pairs(t) do t[k] = nil end
      else
        t = {}
        p[n] = t
      end
    end
    t.kind = kind
    return t
  end
  -- (and the passes: by kind, several a frame; told apart by their serial, never by the table
  -- - a pass's table is another of its kind's the frame after next)
  local passPools = { {}, {} }
  local passSerial = 0
  local function poolsTurn()
    poolTurn = 3 - poolTurn
    recPools[poolTurn].n, itemPools[poolTurn].n = 0, 0
    for _, list in pairs(passPools[poolTurn]) do list.n = 0 end
  end
  local function clearT(t)
    if t then for k in pairs(t) do t[k] = nil end end
    return t
  end
  -- a pass's table for this frame, emptied; its lists (layerSet, items, prefit, sides, shift)
  -- kept emptied in `kept` for beginPass to hand back
  local function pooledPass(pass)
    local pools = passPools[poolTurn]
    local list = pools[pass]
    if not list then list = { n = 0 }; pools[pass] = list end
    if list.n >= 64 then return {} end
    local n = list.n + 1
    list.n = n
    local t = list[n]
    if not t then t = { kept = {} }; list[n] = t; return t end
    local kept = t.kept
    kept.layerSet, kept.items, kept.prefit = clearT(t.layerSet), clearT(t.items), clearT(t.prefit)
    kept.sides, kept.shift = clearT(t.sides or kept.sides), t.shift or kept.shift
    clearT(t)
    t.kept = kept
    return t
  end
  -- (a draw nothing tags: its record's spec, shared - specs are only read)
  local NO_SPEC = {}

  local function openLayer(open)
    local cur = self.cur
    local drawing = onPass()
    cur.pending = false
    cur.open = open or nil
    cur.layerCount = cur.layerCount + 1
    local layer = getLayer(cur.w, cur.h, cur.layerCount)
    cur.layerSet[layer] = true
    cur.current = layer
    local item = newItem("layer")
    item.canvas, item.screen, item.edge, item.bar, item.box = layer, open == "screen", open == "edge", cur.barSpec, cur.boxId
    cur.items[#cur.items + 1] = item
    cur.openItem = item
    if open == "edge" then self.stats.edge = (self.stats.edge or 0) + 1 end
    if open == "screen" and cur.segment == "scene" then self.stats.screen = (self.stats.screen or 0) + 1 end
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
  -- move between whole-scene draws, edge-anchored effects and the rest (kind: "screen",
  -- "edge" or nil)
  local function beforeDraw(kind)
    local cur = self.cur
    if kind then
      if cur.open ~= kind then openLayer(kind) end
    elseif cur.pending or cur.open then
      openLayer(nil)
    end
  end

  -- whole-scene draws are only told apart in a battle's scene, with Battle Fit on
  local function sceneFit()
    local cur = self.cur
    return self.fit.enabled and cur.pass == "battle" and cur.segment == "scene" and not cur.stageDraw
  end

  -- does the rectangle (x, y, w, h), in the current transform, cover the scene (down to the
  -- text box's line), or with `bottom` the canvas down to that row?
  -- the bottom row (canvas y) of the last draw coversScene or edgeBounds looked at (markBottom)
  local lastBottom
  local function coversScene(x, y, w, h, bottom)
    lastBottom = nil
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
      return false
    end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + h)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    lastBottom = y1
    return x0 <= 0.5 and y0 <= 0.5 and x1 >= self.cur.w - 0.5 and y1 >= (bottom or self.fit.focus[2]) - 0.5
  end

  -- a whole-scene or edge draw just made in the scene's open layer: does it end on the text box's
  -- line (the cart's text box hid the rows below: an effect over the battle stops there), or
  -- reach below it? A layer whose draws all end on the line runs its last row on down beside a
  -- filled screen's narrower text box (Encore's and Flatter's dimming)
  local function markBottom()
    local item = self.cur.openItem
    if not (item and lastBottom) then return end
    local line = self.fit.focus[2]
    if lastBottom > line + 0.5 then
      item.below = true
    elseif lastBottom > line - 0.5 then
      item.toLine = true
    end
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

  -- does a draw over the canvas's x0..x1, y0..y1 (canvas pixels) belong to an effect anchored
  -- to the canvas's sides? A fill (a rectangle, a polygon) reaching either side, or anything
  -- spanning the whole width, on the canvas's rows (a sprite only crossing a side is not)
  local function edgeBounds(x0, y0, x1, y1, fill)
    lastBottom = y1
    local cur = self.cur
    local w = cur.w
    if not (y1 > 0.5 and y0 < cur.h - 0.5 and x1 > 0.5 and x0 < w - 0.5) then return false end
    local l, r = x0 <= 0.5, x1 >= w - 0.5
    if fill then return l or r end
    return l and r
  end

  -- an image draw in the battle's scene: "screen" over the whole scene, "edge" spanning the
  -- canvas's width (a canvas too: it is zoomed with the scene, its sides run on), else nil
  local function sceneDrawKind(image, ...)
    if drawCoversScene(image, ...) then return "screen" end
    local x, y, w, hh = drawRect(image, ...)
    if not x then return nil end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + hh)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    return edgeBounds(x0, y0, x1, y1, false) and "edge" or nil
  end

  -- the bounds of a polygon's or a line's points (a table, or the arguments from `first` on),
  -- in the current transform; nil when they cannot be read
  local function pointBounds(first, ...)
    local t = select(first, ...)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    local n = type(t) == "table" and #t or select("#", ...) - first + 1
    if n < 4 then return nil end
    for k = 1, n - 1, 2 do
      local x, y
      if type(t) == "table" then
        x, y = t[k], t[k + 1]
      else
        x, y = select(first + k - 1, ...)
      end
      if type(x) ~= "number" or type(y) ~= "number" then return nil end
      x, y = real.transformPoint(x, y)
      if x < x0 then x0 = x end
      if x > x1 then x1 = x end
      if y < y0 then y0 = y end
      if y > y1 then y1 = y end
    end
    return x0, y0, x1, y1
  end

  -- a primitive in the battle's scene anchored to the canvas's sides (edgeBounds): a filled
  -- rectangle or polygon, or a line spanning the width
  local function primitiveEdge(name, ...)
    local x0, y0, x1, y1
    local fill = false
    if name == "rectangle" then
      local mode, x, y, w, h = ...
      if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return false
      end
      x0, y0 = real.transformPoint(x, y)
      x1, y1 = real.transformPoint(x + w, y + h)
      if x0 > x1 then x0, x1 = x1, x0 end
      if y0 > y1 then y0, y1 = y1, y0 end
      fill = mode == "fill"
    elseif name == "polygon" then
      fill = (...) == "fill"
      x0, y0, x1, y1 = pointBounds(2, ...)
    elseif name == "line" then
      x0, y0, x1, y1 = pointBounds(1, ...)
    end
    return x0 ~= nil and edgeBounds(x0, y0, x1, y1, fill)
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
    local slack = 0.5 + (self.fit.double and self.fit.doublesSlack or 0)
    if not (y0 < split - slack and y1 > split + slack) then return end
    local cur = self.cur
    if x0 <= 0.5 and y0 <= 0.5 and x1 >= cur.w - 0.5 and y1 >= cur.h - 0.5 then return end
    local _, _, _, a = real.getColor()
    if a < 0.01 then return end
    cur.uiStraddle = true
  end

  -- a draw inside an HP box's draw (self.boxBegin): its rect (x, y, w, h, in the current
  -- transform) taken into the box's bounds, canvas px
  local function boxBounds(x, y, w, h)
    local cur = self.cur
    local b = cur and cur.boxId ~= nil and cur.boxes and cur.boxes[cur.boxId]
    if not b or type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
      return
    end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + h)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    if x0 < b.x0 then b.x0 = x0 end
    if y0 < b.y0 then b.y0 = y0 end
    if x1 > b.x1 then b.x1 = x1 end
    if y1 > b.y1 then b.y1 = y1 end
  end

  -- an opaque draw over the battle's whole canvas after the UI seam (a screen opened over the
  -- battle: the summary, the party, the bag, evolution; a fade at full black): that frame is a
  -- whole picture, and fills the screen as one (compositeCard)
  local function noteUICover(covers)
    local cur = self.cur
    if not (covers and self.fit.fill and cur.pass == "battle" and cur.segment == "ui") then return end
    local _, _, _, a = real.getColor()
    if a >= 0.99 and not cur.uiCovers then
      cur.uiCovers = true
      -- (from this item on: what the UI drew before it is under it - a bar painted before it too)
      cur.coverAt = #cur.items + 1
    end
  end
  local function uiFill()
    local cur = self.cur
    return self.fit.fill and cur.pass == "battle" and cur.segment == "ui" and not cur.uiCovers
  end

  -- a tag sized by its species: a battle Pokemon's (a side, not a trainer's) with a height
  local function speciesTag(spec)
    return spec.side ~= nil and not spec.trainer and type(spec.height) == "number" and spec.height > 0
      and spec.texture ~= nil
  end

  local function record(image, spec, a, b, c, d, e, f, g, h, i)
    local quad, x, y, r, sx, sy, ox, oy
    if isQuad(a) then
      quad, x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g, h
    else
      x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g
    end
    if type(x) ~= "number" then return nil end
    local cur = self.cur
    -- (a battler sized by its species: this pass's latest of its side, for the pair)
    if cur and cur.sides and speciesTag(spec) then
      cur.sides[spec.side] = spec
      -- (the player's Pokemon drawn: it has come in, so the enemy's sized against it)
      if spec.side == "player" then cur.playerIn = true end
    end
    local t0x, t0y = real.transformPoint(0, 0)
    local t1x = real.transformPoint(1, 0)
    local _, t2y = real.transformPoint(0, 1)
    local cr, cg, cb, ca = real.getColor()
    local bm, am = real.getBlendMode()
    local shader = real.getShader()
    local t = pooledRec()
    local uniforms
    if shader and sent[shader] then
      uniforms = t.unis
      if uniforms then
        for k in pairs(uniforms) do uniforms[k] = nil end
      else
        uniforms = {}
        t.unis = uniforms
      end
      -- (held by this draw: the next send of each makes a new record)
      for name, v in pairs(sent[shader]) do
        v.shared = true
        uniforms[name] = v
      end
    elseif t.unis then
      -- (a pooled record's last uniforms let go: the sends it held are free to be reused)
      for k in pairs(t.unis) do t.unis[k] = nil end
    end
    -- (the quad's viewport as drawn: the engine may move it before the composite)
    local qx, qy, qw, qh, qsw, qsh
    if quad then
      qx, qy, qw, qh = quad:getViewport()
      if quad.getTextureDimensions then qsw, qsh = quad:getTextureDimensions() end
    end
    t.spec, t.image, t.quad, t.qx, t.qy, t.qw, t.qh, t.qsw, t.qsh = spec, image, quad, qx, qy, qw, qh, qsw, qsh
    t.x, t.y, t.r, t.sx, t.sy, t.ox, t.oy = x, y or 0, r or 0, sx or 1, sy or (sx or 1), ox or 0, oy or 0
    t.tx, t.ty, t.tsx, t.tsy = t0x, t0y, t1x - t0x, t2y - t0y
    local col, bl = t.color, t.blend
    col[1], col[2], col[3], col[4] = cr, cg, cb, ca
    bl[1], bl[2] = bm, am
    t.shader, t.uniforms, t.inAnim = shader, uniforms, nil
    return t
  end

  -- a recorded draw's quad with the viewport it was drawn through. The engine may move a quad
  -- after drawing with it (a reflection's slices all go through one quad, each its own
  -- viewport), so a moved one is drawn through a copy of that viewport, from a ring of copies
  -- kept for it (no garbage; each copy is used straight away). An unmoved one is itself, so
  -- what is keyed by it (quadPivots) still finds it.
  local viewRing, viewN, VIEW_RING = {}, 0, 32
  local function ringQuad(x, y, w, h, iw, ih)
    viewN = viewN % VIEW_RING + 1
    local c = viewRing[viewN]
    if c then
      c:setViewport(x, y, w, h, iw, ih)
    else
      c = real.newQuad(x, y, w, h, iw, ih)
      viewRing[viewN] = c
    end
    return c
  end
  local function viewOf(rec)
    local q = rec.quad
    if not (q and rec.qw) then return q end
    local x, y, w, h = q:getViewport()
    if x == rec.qx and y == rec.qy and w == rec.qw and h == rec.qh then return q end
    local iw, ih = rec.qsw, rec.qsh
    if not iw and rec.image and rec.image.getWidth then iw, ih = rec.image:getWidth(), rec.image:getHeight() end
    if not (iw and real.newQuad) then return q end
    return ringQuad(rec.qx, rec.qy, rec.qw, rec.qh, iw, ih)
  end

  -- a feet-anchored draw with `frame` through less than a whole frame: { x, y, w, h } of the
  -- frame it is a piece of (in the sheet), else nil
  local function frameOf(spec, rec, qp)
    local fr = spec.frame
    if not (fr and spec.anchor == "feet" and not spec.texture and rec.quad and rec.qw and not qp) then return nil end
    local fw, fh = tonumber(fr[1]), tonumber(fr[2])
    if not (fw and fh and fw > 0 and fh > 0) or (rec.qw >= fw and rec.qh >= fh) then return nil end
    local fx, fy = rec.qx - rec.qx % fw, math.floor(rec.qy / fh) * fh
    if rec.qx + rec.qw > fx + fw + 1e-6 or rec.qy + rec.qh > fy + fh + 1e-6 then return nil end
    return { fx, fy, fw, fh }
  end
  -- that whole frame's quad (from the ring)
  local function frameQuad(piece, rec)
    local iw, ih = rec.qsw, rec.qsh
    if not iw and rec.image and rec.image.getWidth then iw, ih = rec.image:getWidth(), rec.image:getHeight() end
    if not (iw and real.newQuad) then return viewOf(rec) end
    return ringQuad(piece[1], piece[2], piece[3], piece[4], iw, ih)
  end

  -- a tagged draw past the pass's cap: drawn on the pass's own pixels (no layer), but at the size
  -- and on the point the window-resolution one would have (place's pivot and scale), so a sized
  -- sprite keeps its size. A slice of a full-resolution frame (spec.texture drawn through a quad of
  -- the low-res image) is drawn as it is, and so is a full-resolution frame under a shader (its
  -- uniforms are in the low-res image's pixels: a battle effect's mask or mosaic).
  -- Returns false when it drew nothing
  -- A frame in the Game Boy's shades (spec.shades), at 1:1 in a canvas of ours: the frame drawn
  -- through the sprite mod's shader, kept as it comes out (replace), so whatever colours it next
  -- (Gold's palette shader, under which the stand-in was drawn) reads the shade the stand-in has.
  -- -> the canvas and a quad of the frame in it, or nil
  local shadeCanvas, shadeQuad, shadeCW, shadeCH = nil, nil, 0, 0
  local function shadedFrame(spec)
    local tex, quad = spec.texture, spec.quad
    if not (real.newCanvas and real.newQuad and tex and tex.getWidth) then return nil end
    local qx, qy, qw, qh = 0, 0, tex:getWidth(), tex:getHeight()
    if quad then qx, qy, qw, qh = quad:getViewport() end
    local w, h = math.ceil(qw), math.ceil(qh)
    if w < 1 or h < 1 or w > 1024 or h > 1024 then return nil end
    if not shadeCanvas or shadeCW < w or shadeCH < h then
      if shadeCanvas and shadeCanvas.release then pcall(shadeCanvas.release, shadeCanvas) end
      shadeCW, shadeCH = math.max(w, shadeCW, 128), math.max(h, shadeCH, 128)
      shadeCanvas = real.newCanvas(shadeCW, shadeCH, { dpiscale = 1 })
    end
    local f = spec.filter or "nearest"
    if shadeCanvas.setFilter then shadeCanvas:setFilter(f, f) end
    real.push("all")
    real.setCanvas(shadeCanvas)
    real.origin()
    real.setScissor()
    real.clear(0, 0, 0, 0)
    real.setShader(spec.shades)
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("replace", "alphamultiply")
    if quad then
      real.draw(tex, quad, 0, 0)
    else
      real.draw(tex, 0, 0)
    end
    real.pop()
    if shadeQuad and shadeQuad.setViewport then
      shadeQuad:setViewport(0, 0, qw, qh, shadeCW, shadeCH)
    else
      shadeQuad = real.newQuad(0, 0, qw, qh, shadeCW, shadeCH)
    end
    return shadeCanvas, shadeQuad
  end

  -- Species sizing (Battle Fit, singles): the two battlers' tags (the latest of each side's
  -- with a `height`, metres), kept from pass to pass (endPass) and cleared when a battle starts
  -- afresh (fit.idle), so a side not drawn this frame (fainted, before its send-out) still counts
  self.pair = {}
  -- (the player's Pokemon drawn this battle: the enemy's sized from then on)
  self.playerIn = false

  -- the size at which the art fills its room: the stand-in's box (the picture box the game
  -- draws) grown by fit.fitRoom[side], above and beside the point it stands on (lpx, lpy; its
  -- pivot hpx, hpy in the frame), which stays where it is. The art is spec.art ({x0, y0, x1,
  -- y1}, frame px: its box over the whole animation) or the frame from its top row of art
  -- (spec.top) down. sx, sy: the draw's own scale (the room is in canvas px). nil: unknown.
  -- Also the art's height at that size and its body's (spec.body; else the art's), canvas px.
  -- (no garbage: the dimensions, the viewport and the room's fields are numbers)
  local function fillScale(spec, image, lpx, lpy, hpx, hpy, sx, sy)
    if not (image and image.getWidth) then return nil end
    local fit = self.fit
    local up, roomL, roomR = 0, 0, 0
    local room = fit.fitRoom and fit.fitRoom[spec.side == "player" and "player" or "enemy"]
    if room then
      local kx, ky = math.abs(sx or 1), math.abs(sy or 1)
      if kx < 1e-6 then kx = 1 end
      if ky < 1e-6 then ky = 1 end
      local upPx = room.up or 0
      -- (the player's: up to the enemy's HP box's bottom, `up` rows over its box, where the UI
      -- puts it over the scene: the top band moved (uiTopDy), the UI at its own scale (uiK))
      if spec.side == "player" and fit.ui and fit.ui.enemy then
        local e, fy = fit.ui.enemy[4], fit.focus[2]
        upPx = upPx + e - (fy + (e + (fit.uiTopDy or 0) + (fit.sceneUp or 0) - fy) * (fit.uiK or 1))
      end
      up = upPx / ky
      roomL, roomR = (room.left or 0) / kx, (room.right or 0) / kx
    end
    local W = image:getWidth()
    local ax0, atop, ax1
    local art = spec.art
    if type(art) == "table" and art[1] and art[2] and art[3] then
      ax0, atop, ax1 = art[1], art[2], art[3]
    else
      ax0, atop = 0, spec.top or 0
      if spec.quad then
        local _, _, qw = spec.quad:getViewport()
        ax1 = qw
      else
        ax1 = spec.texture:getWidth()
      end
    end
    -- (a mirrored frame: its right side drawn on the left)
    local left, right = hpx - ax0, ax1 - hpx
    if spec.flip then left, right = right, left end
    local above = hpy - atop
    local s = math.huge
    if above > 0 then s = math.min(s, (lpy + up) / above) end
    if left > 0 then s = math.min(s, (lpx + roomL) / left) end
    if right > 0 then s = math.min(s, (W - lpx + roomR) / right) end
    if s > 0 and s < math.huge then
      -- (and the art's height at that size, canvas px, and its body's longest side, by height or
      -- width)
      local kx, ky = s * math.abs(sx or 1), s * math.abs(sy or 1)
      local h = above > 0 and ky * above or nil
      local b = spec.body
      local bh = h and math.max(h, kx * (ax1 - ax0))
      if type(b) == "table" and tonumber(b[1]) and tonumber(b[2]) and tonumber(b[3]) and tonumber(b[4])
          and b[4] > b[2] then
        bh = math.max(ky * (b[4] - b[2]), kx * (b[3] - b[1]))
      end
      return s, h, bh
    end
    return nil
  end

  -- the same Pokemon's tag: the same table, or one with the same species' height and art. A
  -- sprite mod tags each frame it builds afresh (an animation frame, a rebuilt picture), so the
  -- side measured a frame ago may carry a new tag for the same Pokemon
  local function sameMon(a, b)
    if a == b then return true end
    if not (a and b) or a.height ~= b.height or a.top ~= b.top then return false end
    local x, y = a.art, b.art
    if x == y then return true end
    return type(x) == "table" and type(y) == "table"
      and x[1] == y[1] and x[2] == y[2] and x[3] == y[3] and x[4] == y[4]
  end

  -- the 3D world drawn this pass, with its sizing on (fit.worldSizes, the 3D Sizing option):
  -- the battlers at the world's scale and everything fitted round them (worldSize, the soft
  -- ceilings, the zoom in, the step outward, the foe's HP box over the heads, the doubles'
  -- rules). Off, the 3D world's battlers are drawn and framed as outside it (ownSize)
  local function tuned() return self.worldScene ~= nil and self.fit.worldSizes ~= false end
  self.worldTuned = tuned

  -- Battle Fit outside the 3D world (and in it with 3D Sizing off): a battle Pokemon (a side's,
  -- not a trainer's) at its tag's own size k, the sprite mod's, unless that is too big for its
  -- room (fillScale): then just small enough to fit it. Nothing else changes its size.
  local function ownSize(spec, image, k, lpx, lpy, hpx, hpy, sx, sy)
    if not (self.fit.enabled and spec.side ~= nil and not spec.trainer and spec.texture ~= nil) then return k end
    -- (the 3D world's double battles with doublesOwnSize: the sprite mod's size as it is, never
    -- shrunk; the camera pulls back for what would leave the screen)
    if tuned() and self.fit.double and self.fit.doublesOwnSize then return k end
    -- (its room measured as it rests: coming out of its ball the game draws it small, its room
    -- in those pixels larger, and it grew to its full size, then shrank)
    local f = fillScale(spec, image, lpx, lpy, hpx, hpy, 1, 1)
    if f and f < k then return f end
    return k
  end

  -- World scale (Battle Scene: Overworld): with the 3D world drawn this pass (self.worldScene,
  -- the world item's scene), each battler stands in it at the world's own scale in place of the
  -- species sizing above: its tag's `height` (the real height of its art, feet row to the top of
  -- its animation, metres) over the scene's metres per tile, times the canvas pixels a tile
  -- spans on the ground where its feet stand (the scene's groundScale: nearer the camera, more),
  -- over the art's height in its frame's pixels. The camera then zooms out to fit it (fitStep,
  -- the world and the battlers together), and nothing slides a side off its ground. The largest
  -- limit: its art no larger than what the camera shows at its furthest zoom (zMin, about the
  -- focus) from where its feet stand, so only a giant that cannot fit even then is shrunk. The
  -- smallest: its art no shorter on screen than worldMin of the battle's height (after the zoom:
  -- it grows as the camera pulls out); the largest limit wins. Indoors a ceiling: an art height
  -- over indoorKnee eases toward indoorCeiling metres. Measured where it rests: the first draw at its
  -- own size (a draw grown or shrunk by the game, its send-out, is measured again until then),
  -- the same Pokemon's later tags taking it (sameMon); cleared when a battle starts.
  -- worldShadow[side]: the share of the scene's shadow under that side its Pokemon's body spans.
  local worldMons = {}
  self.worldShadow = {}
  -- the soft ceiling on a height (metres) for a battler of `side`: true to size up to heightKnee,
  -- eased toward heightMax (a foe's heightMaxFoe; a double battle's own pair) and never past it;
  -- none with sizeMode "accurate" in singles
  local function softCeiling(height, side)
    local fit = self.fit
    local double = fit.double
    local cap, knee0 = tonumber(fit.heightMax), tonumber(fit.heightKnee)
    if double then
      cap, knee0 = tonumber(fit.heightMaxDouble), tonumber(fit.heightKneeDouble)
    elseif side ~= "player" and tonumber(fit.heightMaxFoe) then
      cap = math.min(cap or math.huge, tonumber(fit.heightMaxFoe))
    end
    if fit.sizeMode == "accurate" and not double then cap = nil end
    if cap and cap > 0 and height > math.min(knee0 or cap, cap) then
      local kn = math.min(knee0 or cap, cap)
      if kn >= cap then
        height = cap
      else
        height = kn + (cap - kn) * (1 - math.exp(-(height - kn) / (cap - kn)))
      end
    end
    return height
  end
  local function worldSize(spec, image, lpx, lpy, hpx, hpy, sx, sy, X, Y, rest)
    local scene, S = self.worldScene, self.scene
    if not (scene and type(S) == "table" and type(S.groundScale) == "function") then return nil end
    local height = tonumber(spec.height)
    if not (height and height > 0) then return nil end
    local art = spec.art
    local atop = type(art) == "table" and tonumber(art[2]) or tonumber(spec.top)
    if not atop or hpy - atop <= 0 then return nil end
    local e
    -- (a side's own: the same species' front and back are two; two of one species on a side,
    -- a double battle's, share one, their feet a few rows apart)
    for i = 1, #worldMons do
      local o = worldMons[i].of
      if o.side == spec.side and sameMon(o, spec) then e = worldMons[i] break end
    end
    if not e then
      e = {}
      if #worldMons >= 8 then table.remove(worldMons, 1) end
      worldMons[#worldMons + 1] = e
    end
    e.of = spec
    if not e.rest then
      local ok, ppt = pcall(S.groundScale, scene, X, Y)
      if ok and type(ppt) == "number" and ppt > 0 then
        e.ppt = ppt
        e.rest = math.abs(sx or 1) == 1 and math.abs(sy or 1) == 1
        -- (the largest: its art inside what the camera shows at its furthest zoom, about the
        -- focus: the screen's top over it, its sides either side, from where its feet stand)
        local fit = self.fit
        local z = math.max(fit.zMin or 1, 1e-3)
        local fx, fy = fit.focus[1], fit.focus[2]
        local kx, ky = math.abs(sx or 1), math.abs(sy or 1)
        if kx < 1e-6 then kx = 1 end
        if ky < 1e-6 then ky = 1 end
        local most = (Y - (fy - (fy - (fit.topY or 0)) / z)) / ((hpy - atop) * ky)
        local ax0, ax1 = type(art) == "table" and tonumber(art[1]), type(art) == "table" and tonumber(art[3])
        if ax0 and ax1 then
          local left, right = hpx - ax0, ax1 - hpx
          if spec.flip then left, right = right, left end
          local vl, vr = fit.viewL or 0, fit.viewR or 240
          if left > 0 then most = math.min(most, (X - (fx + (vl - fx) / z)) / (left * kx)) end
          if right > 0 then most = math.min(most, (fx + (vr - fx) / z - X) / (right * kx)) end
        end
        e.most = most > 0 and most or nil
      end
    end
    if not e.ppt then return nil end
    -- (the tallest: capped at heightMax, a foe's at heightMaxFoe; the widest at widthMax, its
    -- art box's width in metres at that height)
    local double = self.fit.double
    local mode = self.fit.sizeMode
    local accurate = mode == "accurate" and not double
    height = softCeiling(height, spec.side)
    local wcap = not double and not accurate and tonumber(self.fit.widthMax)
    local wx0, wx1 = type(art) == "table" and tonumber(art[1]), type(art) == "table" and tonumber(art[3])
    if wcap and wcap > 0 and wx0 and wx1 and wx1 > wx0 then
      local wide = height * (wx1 - wx0) / (hpy - atop)
      if wide > wcap then height = height * wcap / wide end
    end
    -- (indoors: under the ceiling, eased in from the knee)
    local knee, ceiling = tonumber(self.fit.indoorKnee), tonumber(self.fit.indoorCeiling)
    if scene.indoor and knee and ceiling and ceiling > knee and height > knee then
      height = knee + (ceiling - knee) * (1 - math.exp(-(height - knee) / (ceiling - knee)))
    end
    e.height = height
    local k = height / (tonumber(S.METRES_PER_TILE) or 1) * e.ppt / (hpy - atop)
    -- (its art's height where it stands, canvas px before the zoom: what worldShare measures by)
    e.px = (hpy - atop) * k
    -- (the smallest: its art's longest side at least worldMin of the battle's height, and at
    -- least worldShare of the tallest on the field's art height, both before the zoom: the same
    -- on any screen. Measured after the zoom it grew as the camera pulled out for a giant, which
    -- a wide screen does and an upright one, room to spare above, does not)
    local least = tonumber(accurate and self.fit.worldMinAccurate or self.fit.worldMin) or 0
    local side = hpy - atop
    -- (a wide one, its art wider than tall: both floors raised by its width over its height, at
    -- most fit.wideFloor times; a long, low one by its length alone looked too small)
    local widen = 1
    if type(art) == "table" and tonumber(art[1]) and tonumber(art[3]) then
      local across = math.abs(art[3] - art[1])
      if across > side and side > 0 and not accurate then
        widen = math.max(1, math.min(tonumber(self.fit.wideFloor) or 1, across / side))
      end
      side = math.max(side, across)
    end
    e.widen = widen
    local kMin = least > 0 and least * 160 * widen / side or 0
    local share = not accurate and tonumber(self.fit.worldShare) or 0
    local pair = self.pair
    if share > 0 and type(pair) == "table" then
      local tallest = 0
      for i = 1, #worldMons do
        local w = worldMons[i]
        local o = w.of
        if w ~= e and w.px and o and ((pair.enemy and o.side == pair.enemy.side and sameMon(o, pair.enemy))
            or (pair.player and o.side == pair.player.side and sameMon(o, pair.player))) then
          tallest = math.max(tallest, w.px)
        end
      end
      kMin = math.max(kMin, share * tallest * widen / side)
    end
    e.raised = k < kMin
    -- (how much the floors raised it: the camera's zoom-in measures it without, so the raise
    -- shows instead of the camera pulling back to undo it)
    e.lift = e.raised and k > 0 and kMin / k or 1
    if e.raised then k = kMin end
    -- (Minimal: Medium's size, its floors' raise and all, drawn toward the middle: as metres at
    -- this spot, mid * (h / mid) ^ minimalPow, the small less small, the big less big. What the
    -- zoom-in leaves out (e.lift) is Medium's raise, curved alike)
    if mode == "minimal" and not double then
      local mid, pw = tonumber(self.fit.minimalMid) or 1, tonumber(self.fit.minimalPow) or 1
      local perM = e.ppt / ((tonumber(S.METRES_PER_TILE) or 1) * (hpy - atop))
      if mid > 0 and pw > 0 and perM > 0 and k > 0 then
        local function curve(kk) return mid * (kk / perM / mid) ^ pw * perM end
        local c0 = curve(k / (e.lift or 1))
        k = curve(k)
        e.lift = c0 > 0 and k / c0 or 1
        e.height = k / perM
      end
    end
    e.limited = e.most ~= nil and k > e.most
    if e.limited then k = e.most end
    -- (a double battle: no wider than its spot, the column it rests on, as the engine reports it
    -- (rest), else where it is drawn)
    if rest then e.restX = X end
    local spots = double and self.fit.doubleSpots
    local ax0, ax1 = type(art) == "table" and tonumber(art[1]), type(art) == "table" and tonumber(art[3])
    if type(spots) == "table" and #spots > 0 and ax0 and ax1 then
      local x, bi, bd = e.restX or X, 1, math.huge
      for i = 1, #spots do
        if math.abs(spots[i] - x) < bd then bi, bd = i, math.abs(spots[i] - x) end
      end
      local gap, sp = tonumber(self.fit.spotGap) or 0, self.fit.spread or 1
      local fxs = self.fit.focus[1]
      local function at(i) return fxs + (spots[i] - fxs) * sp end
      local left, right = hpx - ax0, ax1 - hpx
      if spec.flip then left, right = right, left end
      if spots[bi - 1] and left > 0 then k = math.min(k, math.max(0, (at(bi) - at(bi - 1)) / 2 - gap) / left) end
      if spots[bi + 1] and right > 0 then k = math.min(k, math.max(0, (at(bi + 1) - at(bi)) / 2 - gap) / right) end
    end
    e.k = k
    -- (the side's shadow spans its body at that size)
    local b, sh = spec.body, type(S.SHADOW) == "table" and S.SHADOW[spec.side]
    if type(b) == "table" and b[3] and b[1] and sh and sh[3] and sh[3] > 0 then
      self.worldShadow[spec.side] = math.max(0.1, (b[3] - b[1]) * k / (2 * sh[3]))
    end
    return k
  end
  self._worldMons = worldMons

  -- Pokemon another mod draws giant for a while (exports.giant: Galar Rising's Dynamax), by battler
  -- id (0..3; singles: 0 the player's, 1 the foe's): how the battle draws it now - scale (over its
  -- own draw), dx / dy (canvas px its centre moves), the picture in its place (a Gigantamax form's:
  -- tagged, its pivot at its feet) and grow (0..1, how far grown). The fit takes each where it
  -- rests at that size (hd.prefit), whatever a move does to it meanwhile, so the camera pulls back
  -- for it from its first frame to its last and never for a frame less. In the 3D world with 3D
  -- Sizing it stands toward fit.giantHeight as it grows (giantSize). Off when a battle starts.
  -- own: its own picture's tag, as the battle reports it (its height, its size before it grew)
  self.giants = {}
  -- (a giant counts only while it is told each frame: one the mod stopped telling of - its record
  -- gone without a nil - is off by the frame after next; giantTick counts frames, hd.endFrame)
  self.giantTicks = 0
  function self.giantTick() self.giantTicks = self.giantTicks + 1 end
  local function giantLive(g) return g ~= nil and g.on and self.giantTicks - (g.seen or -9) <= 1 end
  self.giantLive = giantLive
  function self.setGiant(id, info)
    id = tonumber(id)
    if id == nil then return end
    local g = self.giants[id]
    if type(info) ~= "table" then
      if g then g.on = false end
      return
    end
    if not g then
      g = {}
      self.giants[id] = g
    end
    -- (newly on, already grown past a quarter: the camera jumps out for it, fitStep's giantNew)
    if not giantLive(g) and (tonumber(info.grow) or 1) > 0.25 then self.giantNew = 2 end
    g.on, g.seen = true, self.giantTicks
    g.scale = tonumber(info.scale) or 1
    g.dx, g.dy = tonumber(info.dx) or 0, tonumber(info.dy) or 0
    g.image = info.image
    g.grow = math.max(0, math.min(1, tonumber(info.grow) or 1))
  end
  function self.giantsOff()
    for _, g in pairs(self.giants) do g.on, g.own, g.ownRec, g.restRec = false, nil, nil, nil end
  end
  -- the giant a tagged draw is (its Gigantamax picture's tag, or its own picture's while it grows)
  local function giantOf(spec)
    for _, g in pairs(self.giants) do
      if giantLive(g) then
        if g.image ~= nil then
          if self.tags[g.image] == spec then return g end
        else
          local own = g.own or (g.ownRec and g.ownRec.spec)
          if own and spec.side == own.side and sameMon(own, spec) then return g end
        end
      end
    end
    return nil
  end
  self.giantOf = giantOf
  -- a giant's size in the 3D world (the k place() takes, over the draw's own scale): its art from
  -- its own height where it stands (worldSize's, floors and all) toward giantHeight's (softCeiling,
  -- indoors under the ceiling, Minimal's curve), by grow, evenly in proportion; no taller than
  -- the camera shows at its furthest zoom from where its feet stand
  local function giantSize(g, spec, hpy, X, Y)
    local scene, S, fit = self.worldScene, self.scene, self.fit
    if not (scene and type(S) == "table" and type(S.groundScale) == "function") then return nil end
    local own = g.own
    local ownH = own and tonumber(own.height)
    if not (ownH and ownH > 0) then return nil end
    local art = spec.art
    local atop = type(art) == "table" and tonumber(art[2]) or tonumber(spec.top)
    local feet = hpy
    if type(spec.body) == "table" and tonumber(spec.body[4]) and spec.texture == nil then
      feet = math.max(feet, tonumber(spec.body[4]))
    end
    if not atop or feet - atop <= 0 then return nil end
    local ok, ppt = pcall(S.groundScale, scene, X, Y)
    if not (ok and type(ppt) == "number" and ppt > 0) then return nil end
    local mpt = tonumber(S.METRES_PER_TILE) or 1
    -- (its own: as worldSize has it; the giant's: the player's ceiling for either side and no
    -- room's ceiling - a foe's lower one and a room's 3 m left it hardly bigger than itself)
    local function metres(h, giant)
      h = softCeiling(h, giant and "player" or spec.side)
      local knee, ceiling = tonumber(fit.indoorKnee), tonumber(fit.indoorCeiling)
      if not giant and scene.indoor and knee and ceiling and ceiling > knee and h > knee then
        h = knee + (ceiling - knee) * (1 - math.exp(-(h - knee) / (ceiling - knee)))
      end
      if fit.sizeMode == "minimal" and not fit.double then
        local mid, pw = tonumber(fit.minimalMid) or 1, tonumber(fit.minimalPow) or 1
        if mid > 0 and pw > 0 then h = mid * (h / mid) ^ pw end
      end
      return h
    end
    local ownPx
    for i = 1, #worldMons do
      local w = worldMons[i]
      if w.px and w.of.side == own.side and sameMon(w.of, own) then ownPx = w.px break end
    end
    ownPx = ownPx or metres(ownH) / mpt * ppt
    local bigPx = math.max(ownPx * (tonumber(fit.giantMin) or 1), metres(tonumber(fit.giantHeight) or ownH, true) / mpt * ppt)
    local px = ownPx * (bigPx / ownPx) ^ (g.grow or 1)
    local z = math.max(fit.zMin or 1, 1e-3)
    local fy = fit.focus[2]
    local line = fit.topY or 0
    if fit.headBox and fit.boxBottom and spec.side == "player" and not fit.double then
      line = math.max(line, fy + (fit.boxBottom + fit.headGap + (fit.sceneUp or 0) - fy) * (fit.uiK or 1))
    end
    local most = Y - (fy - (fy - line) / z)
    if most > 0 then px = math.min(px, most) end
    local kTot = px / (feet - atop)
    -- (the side's shadow spans its body at that size)
    local b, sh = spec.body, type(S.SHADOW) == "table" and S.SHADOW[spec.side]
    if type(b) == "table" and b[3] and b[1] and sh and sh[3] and sh[3] > 0 then
      self.worldShadow[spec.side] = math.max(0.1, (b[3] - b[1]) * kTot / (2 * sh[3]))
    end
    return kTot / ((g.scale and g.scale > 0) and g.scale or 1)
  end

  --- (a double battle in the 3D world) how far the doubles spread moves the battler resting on
  --- the spot nearest canvas column x (spec: its tag, whose resting column, as the engine
  --- reports it, is used when known), canvas px before the zoom; 0 elsewhere
  local function spreadDx(x, spec)
    local fit = self.fit
    local sp = fit.spread or 1
    local spots = fit.doubleSpots
    if not (fit.double and tuned() and sp ~= 1 and type(spots) == "table" and #spots > 0) then return 0 end
    if spec then
      for i = 1, #worldMons do
        local w = worldMons[i]
        if w.restX and w.of.side == spec.side and sameMon(w.of, spec) then x = w.restX break end
      end
    end
    local best, bd = spots[1], math.huge
    for i = 1, #spots do
      if math.abs(spots[i] - x) < bd then best, bd = spots[i], math.abs(spots[i] - x) end
    end
    return (best - fit.focus[1]) * (sp - 1)
  end
  self.spreadDx = spreadDx

  -- a tag's contact shadow (spec.shadow), under a frame whose pivot is drawn at (px, py) turned
  -- by r and scaled by (fsx, fsy) (the frame's final scale, flip included): its offsets and
  -- width are in the frame's pixels, so it follows the frame's size and mirroring
  local function drawShadow(spec, px, py, r, fsx, fsy)
    local s = spec.shadow
    if type(s) ~= "table" or not (s.texture and s.texture.getWidth) then return end
    local qw, qh
    if s.quad then
      local _
      _, _, qw, qh = s.quad:getViewport()
    else
      qw, qh = s.texture:getWidth(), s.texture:getHeight()
    end
    if not (qw and qh) or qw <= 0 or qh <= 0 then return end
    local ks = (tonumber(s.w) or qw) / qw
    local dx, dy = (tonumber(s.dx) or 0) * fsx, (tonumber(s.dy) or 0) * fsy
    local cs, sn = math.cos(r or 0), math.sin(r or 0)
    local X, Y = px + dx * cs - dy * sn, py + dx * sn + dy * cs
    if s.quad then
      real.draw(s.texture, s.quad, X, Y, r or 0, fsx * ks, fsy * ks, qw / 2, qh)
    else
      real.draw(s.texture, X, Y, r or 0, fsx * ks, fsy * ks, qw / 2, qh)
    end
  end

  -- a feet-anchored draw's pivot in its quad: the quad's bottom middle, or with `frame`
  -- ({w, h}: the sheet's frames, stacked in a column) the feet of the frame the quad is in, so
  -- a piece of a frame drawn on its own (a reflection's slices) grows with the whole frame
  local function feetOf(spec, vx, vy, qw, qh)
    local fr = spec.frame
    local fw, fh = fr and tonumber(fr[1]), fr and tonumber(fr[2])
    if fw and fh and fw > 0 and fh > 0 then
      return fw / 2 - vx % fw, (math.floor(vy / fh) + 1) * fh - vy
    end
    return qw / 2, qh
  end

  local function drawAtScale(shaded, image, spec, a, b, c, d, e, f, g, h)
    local quad, x, y, r, sx, sy, ox, oy
    if isQuad(a) then
      quad, x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g, h
    else
      x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g
    end
    if type(x) ~= "number" then return false end
    -- (a frame in the game's shades is drawn as its shades, so a shader over it colours it)
    if spec.texture and quad then return false end
    if spec.texture and shaded and not spec.shades then return false end
    y, r, sx, ox, oy = y or 0, r or 0, sx or 1, ox or 0, oy or 0
    sy = sy or sx
    local qp = spec.quadPivots and quad and spec.quadPivots[quad]
    local lpx, lpy, hpx, hpy
    if spec.anchor == "feet" and quad and not qp then
      lpx, lpy = feetOf(spec, quad:getViewport())
      hpx, hpy = lpx, lpy
    else
      local lp = qp or spec.lowPivot
      lpx, lpy = lp and lp[1] or 32, lp and lp[2] or 32
      local hp = (not qp and spec.pivot) or lp
      hpx, hpy = hp and hp[1] or lpx, hp and hp[2] or lpy
    end
    local k = (qp and qp[3]) or spec.scale or 1
    if not qp then k = ownSize(spec, image, k, lpx, lpy, hpx, hpy, sx, sy) end
    -- where the draw put the pivot, then the frame drawn k times larger about it
    local dx, dy = (lpx - ox) * sx, (lpy - oy) * sy
    local cs, sn = math.cos(r), math.sin(r)
    local px, py = x + dx * cs - dy * sn, y + dx * sn + dy * cs
    if spec.texture then
      -- (flip: the full-resolution frame mirrored about its pivot)
      local fsx = spec.flip and -sx * k or sx * k
      local tex, tq = spec.texture, spec.quad
      if spec.shades then
        tex, tq = shadedFrame(spec)
        if not tex then return false end
      end
      drawShadow(spec, px, py, r, fsx, sy * k)
      if tq then
        real.draw(tex, tq, px, py, r, fsx, sy * k, hpx, hpy)
      else
        real.draw(tex, px, py, r, fsx, sy * k, hpx, hpy)
      end
    elseif quad then
      real.draw(image, quad, px, py, r, sx * k, sy * k, hpx, hpy)
    else
      real.draw(image, px, py, r, sx * k, sy * k, hpx, hpy)
    end
    return true
  end

  -- a tagged draw wholly off the pass's canvas, allowing for its size (the low-res rectangle
  -- grown by the spec's scale about its middle) and a margin: it shows nothing, so it takes no
  -- layer (a mod's wanderers out of view are still drawn every frame). Unknown (rotated): false.
  -- (no garbage: drawRect and transformPoint return numbers)
  local OFF_MARGIN = 16
  local function offCanvas(image, spec, a, b, c, d, e, f, g, h)
    local x, y, w, hh = drawRect(image, a, b, c, d, e, f, g, h)
    if not x then return false end
    local k = math.max(1, math.abs(tonumber(spec.scale) or 1))
    if spec.quadPivots then
      for _, p in pairs(spec.quadPivots) do
        if p[3] then k = math.max(k, math.abs(p[3])) end
      end
    end
    local mx, my = x + w / 2, y + hh / 2
    local hw, hh2 = math.abs(w) * k / 2, math.abs(hh) * k / 2
    local x0, y0 = real.transformPoint(mx - hw, my - hh2)
    local x1, y1 = real.transformPoint(mx + hw, my + hh2)
    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end
    local cur = self.cur
    return x1 < -OFF_MARGIN or y1 < -OFF_MARGIN or x0 > cur.w + OFF_MARGIN or y0 > cur.h + OFF_MARGIN
  end

  -- a move's background drawn in bands across the battle's scene (Surf's and Muddy Water's wave):
  -- a quad of a tiled image (wrapped "repeat" across) spanning the canvas's
  -- width, upright, but not over the whole canvas (a whole background covers the screen as a
  -- "screen" layer). Returns its "wide" item, recorded with the quad's viewport as drawn (the
  -- engine moves one quad from band to band), or nil
  local function wideBackground(image, a, b, c, d, e, f, g, h)
    local t = type(image)
    if not (real.newQuad and isQuad(a) and (t == "userdata" or t == "table") and image.getWrap and image.getWidth) then
      return nil
    end
    if image.typeOf and image:typeOf("Canvas") then return nil end
    if image:getWrap() ~= "repeat" then return nil end
    if (d or 0) ~= 0 or (e or 1) <= 0 or (f or e or 1) <= 0 then return nil end
    local x, y, w, hh = drawRect(image, a, b, c, d, e, f, g, h)
    if not x then return nil end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + hh)
    if x1 <= x0 or y1 <= y0 then return nil end
    local cur = self.cur
    if not edgeBounds(x0, y0, x1, y1, false) then return nil end
    if y0 <= 0.5 and y1 >= cur.h - 0.5 then return nil end
    local rec = record(image, NO_SPEC, a, b, c, d, e, f, g, h)
    if not rec then return nil end
    local qx, qy, qw, qh = a:getViewport()
    -- (bottom: it reaches the text box's line, below which the cart's text box hid the rest)
    return { kind = "wide", rec = rec, qx = qx, qy = qy, qw = qw, qh = qh,
             bottom = y1 >= self.fit.focus[2] - 0.5 }
  end

  -- a picture repeated across the battle's scene as tiles (a plane: WoobleDex's Gen 9 animations'
  -- backgrounds and foregrounds, Essentials' planes, drawn as copies of one picture on a grid from
  -- the canvas's top left, scrolled). The copies together always cover the canvas, but alone
  -- they don't once it scrolls, so each would be zoomed with the scene, cut off at the canvas's
  -- edges. A run of them is one "screen" layer instead, covering the view whatever the scroll.
  -- An upright, unscaled quad at least planeMin a side reaching over the canvas's top left corner
  -- may start a run ("start": it gets a layer of its own, kind as usual, cur.plane); the same
  -- picture drawn next on its grid continues it ("continue": that layer becomes a "screen" one).
  -- A copy alone stays what it was (Encore's dimming, its spotlight on its target, at 0, 0)
  local planeMin = 48
  local function planeTile(image, a, b, c, d, e, f, g, h)
    local cur = self.cur
    local run = cur.plane
    cur.plane = nil
    if not isQuad(a) or (d or 0) ~= 0 or (e or 1) ~= 1 or (f or e or 1) ~= 1 then return nil end
    local x, y, w, hh = drawRect(image, a, b, c, d, e, f, g, h)
    if not x or w < planeMin or hh < planeMin then return nil end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + hh)
    if math.abs((x1 - x0) - w) > 0.01 or math.abs((y1 - y0) - hh) > 0.01 then return nil end
    local qx, qy, qw, qh = a:getViewport()
    if run and run.image == image and run.qx == qx and run.qy == qy and run.qw == qw and run.qh == qh then
      local i, j = (x0 - run.x0) / w, (y0 - run.y0) / hh
      if math.abs(i - math.floor(i + 0.5)) < 0.01 and math.abs(j - math.floor(j + 0.5)) < 0.01 then
        cur.plane = run
        return "continue", run
      end
    end
    if x0 <= 0.5 and y0 <= 0.5 and x1 > 0.5 and y1 > 0.5 then
      local fresh = { image = image, qx = qx, qy = qy, qw = qw, qh = qh, x0 = x0, y0 = y0 }
      cur.plane = fresh
      return "start", fresh
    end
    return nil
  end

  -- a row of pictures of one width side by side across the battle's scene (WoobleDex's Surf: its
  -- wall of water, the wave's crest and water placed by turns on Essentials' screen to fill it).
  -- Each crosses at most one side, so none is an edge draw, and the row stopped at the canvas's
  -- sides. Once a pass's pieces (upright, unmirrored quads at least rowMin wide, of one width,
  -- sharing their top or bottom row, each the last's width along) reach both sides, a "row" item
  -- is recorded: with fill it carries the row on out to the view's sides (drawRow) with an end
  -- piece that is its body (its lowest) or was seen repeated in a row (rowSeen), and runs its
  -- pieces on below their feet. The candidates are this pass's (cur.rowN), in tables kept
  -- across passes
  local rowMin = 64
  local rowPool = {}
  -- the pieces seen repeated in a row, by picture (weak: a picture dropped takes its entries)
  local rowSeen = setmetatable({}, { __mode = "k" })
  local function samePiece(p, q)
    return p.image == q.image and p.qx == q.qx and p.qy == q.qy and p.qw == q.qw and p.qh == q.qh
  end
  local function rowTile(image, a, b, c, d, e, f, g, h)
    if not isQuad(a) or (d or 0) ~= 0 or (e or 1) <= 0 or (f or e or 1) <= 0 then return end
    local ty = type(image)
    if not (ty == "userdata" or ty == "table") or (image.typeOf and image:typeOf("Canvas")) then return end
    local x, y, w, hh = drawRect(image, a, b, c, d, e, f, g, h)
    if not x or w < rowMin then return end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + hh)
    w, hh = x1 - x0, y1 - y0
    if w < rowMin or hh <= 0 then return end
    local cur = self.cur
    if x1 <= 0 or x0 >= cur.w or y1 <= 0 or y0 >= cur.h then return end
    local qx, qy, qw, qh = a:getViewport()
    local n = cur.rowN or 0
    local t = rowPool[n + 1]
    if not t then
      t = {}
      rowPool[n + 1] = t
    end
    t.image, t.qx, t.qy, t.qw, t.qh, t.x0, t.y0, t.w, t.h, t.done = image, qx, qy, qw, qh, x0, y0, w, hh, false
    cur.rowN = n + 1
    -- the pieces of this row drawn this pass (this one too): their span, each its width along
    local lo, hi, count = x0, x0, 0
    for i = 1, n + 1 do
      local o = rowPool[i]
      if math.abs(o.w - w) < 0.01 and (math.abs(o.y0 - y0) < 0.5 or math.abs(o.y0 + o.h - y1) < 0.5) then
        local k = (o.x0 - x0) / w
        if math.abs(k - math.floor(k + 0.5)) < 0.01 then
          if o.done then return end
          if o.x0 < lo then lo = o.x0 end
          if o.x0 > hi then hi = o.x0 end
          count = count + 1
        end
      end
    end
    local last = math.floor((hi - lo) / w + 0.5)
    if count < 2 or lo > 0.5 or hi + w < cur.w - 0.5 or count ~= last + 1 then return end
    -- the row's pieces in order across (its end pieces carry it on)
    local pieces = {}
    for i = 1, n + 1 do
      local o = rowPool[i]
      if math.abs(o.w - w) < 0.01 and (math.abs(o.y0 - y0) < 0.5 or math.abs(o.y0 + o.h - y1) < 0.5) then
        local k = (o.x0 - lo) / w
        if math.abs(k - math.floor(k + 0.5)) < 0.01 then
          o.done = true
          pieces[math.floor(k + 0.5) + 1] = { image = o.image, qx = o.qx, qy = o.qy, qw = o.qw, qh = o.qh,
                                              y0 = o.y0, h = o.h }
        end
      end
    end
    for k = 1, last + 1 do
      if not pieces[k] then return end
    end
    -- (an end piece a row repeats, in this frame or one before, carries it on: Muddy Water's mud
    -- at its end, beside its crest)
    for k = 1, last + 1 do
      for j = k + 1, last + 1 do
        if samePiece(pieces[k], pieces[j]) then
          local o = pieces[k]
          local byImage = rowSeen[o.image]
          if not byImage then
            byImage = {}
            rowSeen[o.image] = byImage
          end
          byImage[o.qx .. ":" .. o.qy .. ":" .. o.qw .. ":" .. o.qh] = true
        end
      end
    end
    -- (and so does the row's lowest piece, its body: a wave's crest stands above its water)
    local low = math.huge
    for k = 1, last + 1 do low = math.min(low, pieces[k].h) end
    local function repeats(piece)
      if piece.h <= low + 0.5 then return true end
      local byImage = rowSeen[piece.image]
      return byImage ~= nil and byImage[piece.qx .. ":" .. piece.qy .. ":" .. piece.qw .. ":" .. piece.qh] == true
    end
    local carryLo, carryHi = repeats(pieces[1]), repeats(pieces[last + 1])
    local rec = record(image, NO_SPEC, a, b, c, d, e, f, g, h)
    if not rec then return end
    cur.items[#cur.items + 1] = { kind = "row", rec = rec, pieces = pieces, lo = lo, hi = hi, w = w,
                                  cw = cur.w, ch = cur.h, line = self.fit.focus[2], carryLo = carryLo,
                                  carryHi = carryHi }
    self.stats.row = (self.stats.row or 0) + 1
  end

  -- a move's effect crossing the canvas's edges (a slash on a giant drawn near a side, a burst on
  -- the player's Pokemon low on the screen): drawn in a layer, its part past the canvas is lost,
  -- though zoomed out the view shows past it. One that crosses an edge (partly on the canvas: one
  -- wholly off it may be parked there to hide it) is recorded instead, a "free" item drawn at the
  -- scene's mapping over the whole view, uncut (drawFree). Up to freeMax a pass; the rest as before
  local freeMax = 48
  -- a mosaic: big upright pieces drawn one after another that together cover the canvas, down to
  -- the text box's line (Seismic Toss's starry sky, six tiles in two rows). Seen covering it in a
  -- pass, its pieces are "screen" draws from the next pass on, one whole-scene layer covering the
  -- view, as a single whole background is (one frame late, while the run is being seen)
  local mosaicPool = {}
  local function mosaicCovers(n)
    local cur = self.cur
    local line = self.fit.focus[2]
    for j = 0, 7 do
      local py = (j + 0.5) * line / 8
      for i = 0, 11 do
        local px = (i + 0.5) * cur.w / 12
        local hit = false
        for k = 1, n do
          local t = mosaicPool[k]
          if px >= t.x0 and px <= t.x1 and py >= t.y0 and py <= t.y1 then hit = true break end
        end
        if not hit then return false end
      end
    end
    return true
  end
  -- a draw in the scene: is it a piece of a mosaic seen last pass? Noted for this pass's
  local function mosaicPiece(image, a, b, c, d, e, f, g, h)
    local cur = self.cur
    if not isQuad(a) or (d or 0) ~= 0 then
      cur.mosaicN = 0
      return false
    end
    local qx, qy, qw, qh = a:getViewport()
    local key = qx .. ":" .. qy .. ":" .. qw .. ":" .. qh
    local now = self.mosaicNow
    local known = now ~= nil and now[image] ~= nil and now[image][key] == true
    local x, y, w, hh = drawRect(image, a, b, c, d, e, f, g, h)
    if not x then
      cur.mosaicN = 0
      return known
    end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + hh)
    if x1 < x0 then x0, x1 = x1, x0 end
    if y1 < y0 then y0, y1 = y1, y0 end
    -- (one too small, or one covering the scene alone, a whole background: no mosaic's piece)
    if x1 - x0 < planeMin or y1 - y0 < planeMin
        or (x0 <= 0.5 and y0 <= 0.5 and x1 >= cur.w - 0.5 and y1 >= self.fit.focus[2] - 0.5) then
      cur.mosaicN = 0
      return known
    end
    local n = (cur.mosaicN or 0) + 1
    local t = mosaicPool[n]
    if not t then
      t = {}
      mosaicPool[n] = t
    end
    t.image, t.key, t.x0, t.y0, t.x1, t.y1 = image, key, x0, y0, x1, y1
    cur.mosaicN = n
    if n >= 2 and mosaicCovers(n) then
      local nextSet = self.mosaicNext or {}
      self.mosaicNext = nextSet
      for k = 1, n do
        local o = mosaicPool[k]
        nextSet[o.image] = nextSet[o.image] or {}
        nextSet[o.image][o.key] = true
      end
    end
    return known
  end
  local function freeBounds(image, a, b, c, d, e, f, g, h)
    local quadded = isQuad(a)
    local w, hh, x, y, r, sx, sy, ox, oy
    if quadded then
      local _
      _, _, w, hh = a:getViewport()
      x, y, r, sx, sy, ox, oy = b, c, d, e, f, g, h
    else
      if not image.getWidth then return nil end
      w, hh = image:getWidth(), image:getHeight()
      x, y, r, sx, sy, ox, oy = a, b, c, d, e, f, g
    end
    if type(x) ~= "number" then return nil end
    y, r, sx = y or 0, r or 0, sx or 1
    sy, ox, oy = sy or sx, ox or 0, oy or 0
    local cs, sn = math.cos(r), math.sin(r)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for corner = 0, 3 do
      local u = ((corner % 2 == 1) and w or 0) - ox
      local v = ((corner >= 2) and hh or 0) - oy
      u, v = u * sx, v * sy
      local px, py = real.transformPoint(x + u * cs - v * sn, y + u * sn + v * cs)
      if px < x0 then x0 = px end
      if px > x1 then x1 = px end
      if py < y0 then y0 = py end
      if py > y1 then y1 = py end
    end
    return x0, y0, x1, y1
  end
  local function freeDraw(image, a, ...)
    local cur = self.cur
    if (cur.freeN or 0) >= freeMax then return false end
    local ty = type(image)
    if not (ty == "userdata" or ty == "table") or (image.typeOf and image:typeOf("Canvas")) then return false end
    local x0, y0, x1, y1 = freeBounds(image, a, ...)
    if not x0 then return false end
    -- partly on the canvas, partly off it; or, drawn by a move's animation (hd.inAnim), wholly
    -- off it but within a canvas's size of it (a giant of the player's stepped out past the
    -- canvas's left side: its moves aimed at its middle there)
    if x1 <= 0 or x0 >= cur.w or y1 <= 0 or y0 >= cur.h then
      if not (self.inAnim and x1 > -cur.w and x0 < 2 * cur.w and y1 > -cur.h and y0 < 2 * cur.h) then return false end
    end
    if x0 >= -0.5 and y0 >= -0.5 and x1 <= cur.w + 0.5 and y1 <= cur.h + 0.5 then return false end
    local rec = record(image, NO_SPEC, a, ...)
    if not rec then return false end
    local item = newItem("free")
    item.rec = rec
    if isQuad(a) then item.qx, item.qy, item.qw, item.qh = a:getViewport() end
    cur.items[#cur.items + 1] = item
    cur.freeN = (cur.freeN or 0) + 1
    cur.pending = true
    cur.open = nil
    self.stats.free = (self.stats.free or 0) + 1
    return true
  end

  local drawInner
  -- a piece of a move's animation in the 3D world's singles (hd.inAnim; not a tagged picture, not
  -- one fxBig of the canvas across): grown about its own middle by the factor where its middle
  -- lies on the line between the two Pokemon (fit.fxLine, src/gen3.lua: where the moves aim),
  -- each end its side's growth (fit.fxPlayer at 0, fit.fxEnemy at 1)
  local function fxFactor(image, ...)
    local fit, cur = self.fit, self.cur
    local line = fit.fxLine
    if not (self.inAnim and line and fit.fxGrow and cur and cur.pass == "battle" and cur.segment == "scene") then
      return nil
    end
    local fe, fp = fit.fxEnemy or 1, fit.fxPlayer or 1
    if fe <= 1.001 and fp <= 1.001 then return nil end
    if self.tags[image] then return nil end
    local ty = type(image)
    if not (ty == "userdata" or ty == "table") or (image.typeOf and image:typeOf("Canvas")) then return nil end
    local x0, y0, x1, y1 = freeBounds(image, ...)
    if not x0 then return nil end
    local big = fit.fxBig or 0.6
    if x1 - x0 >= big * cur.w or y1 - y0 >= big * cur.h then return nil end
    local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    local ax, ay, bx, by = line[1], line[2], line[3], line[4]
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 1e-6 and math.max(0, math.min(1, ((cx - ax) * dx + (cy - ay) * dy) / len2)) or 0.5
    local f = fp + (fe - fp) * t
    if f <= 1.001 then return nil end
    return f, cx, cy
  end

  local function wrappedDraw(image, ...)
    if self.inAnim and self.cur and onPass() then
      local f, cx, cy = fxFactor(image, ...)
      if f then
        -- (the current transform, scaled by f about the canvas point (cx, cy))
        local ox, oy = real.transformPoint(0, 0)
        local ux = real.transformPoint(1, 0)
        local _, vy = real.transformPoint(0, 1)
        real.push()
        real.origin()
        real.translate(cx + (ox - cx) * f, cy + (oy - cy) * f)
        real.scale((ux - ox) * f, (vy - oy) * f)
        self.stats.fxGrown = (self.stats.fxGrown or 0) + 1
        drawInner(image, ...)
        real.pop()
        return
      end
    end
    return drawInner(image, ...)
  end

  drawInner = function(image, ...)
    local cur = self.cur
    -- the weather's colour pass drawing the field into its new canvas through its colour map
    -- (colorMapStart): its shader and uniforms are kept for the composite, which maps the whole
    -- field at window resolution, sprites and all; the new canvas is left clear for what the
    -- weather draws over it (rain, a flash)
    local cm = cur and cur.cm
    if cm and cm.armed and isPassCanvas(image) and real.getCanvas() == cm.to then
      cm.armed = false
      cm.shader = real.getShader()
      local u = {}
      for name, v in pairs(cm.shader and sent[cm.shader] or {}) do
        v.shared = true
        u[name] = v
      end
      cm.uniforms = u
      real.clear(0, 0, 0, 0)
      return
    end
    -- (no pass: a direct one draws a tagged image at its size in place, self.beginDirect)
    if self.direct and not cur then
      local spec = self.tags[image]
      if spec then
        self.stats.direct = (self.stats.direct or 0) + 1
        if drawAtScale(real.getShader() ~= nil, image, spec, ...) then return end
      end
      return real.draw(image, ...)
    end
    local overSpec
    if cur and onPass() then
      local spec = not cur.plain and self.tags[image]
      -- (the field only: Battle Fit's zoomed-out view shows past the battle canvas's edges)
      if spec and cur.pass == "field" and offCanvas(image, spec, ...) then
        self.stats.offCanvas = (self.stats.offCanvas or 0) + 1
        return real.draw(image, ...)
      end
      if spec and cur.splits < cur.cap then
        local rec = record(image, spec, ...)
        if rec then
          -- drawn by a move animation: already where the engine's (shifted) coordinates put it
          rec.inAnim = self.inAnim == true
          -- a double battle's battlers are placed from the shifted columns themselves: back to
          -- the spot they rest on, so the fit and the draw below treat them as in singles
          if self.fit.double and self.fit.enabled and cur.pass == "battle" and cur.segment == "scene"
              and spec.side and not spec.trainer and not rec.inAnim then
            rec.tx = rec.tx - (cur.shift[spec.side] or 0)
            -- (and the doubles spread the coordinates were moved by: off the spot drawn nearest)
            local spots, sp = self.fit.doubleSpots, cur.spread or 1
            if sp ~= 1 and tuned() and type(spots) == "table" and #spots > 0 then
              local fx0 = self.fit.focus[1]
              local x0 = rec.tx + rec.x * rec.tsx
              local best, bd = 0, math.huge
              for i = 1, #spots do
                local dx = (spots[i] - fx0) * (sp - 1)
                if math.abs(spots[i] + dx - x0) < bd then best, bd = dx, math.abs(spots[i] + dx - x0) end
              end
              rec.tx = rec.tx - best
            end
          end
          -- tagged draws with nothing drawn between them share one split
          if not cur.pending then cur.splits = cur.splits + 1 end
          local item = newItem("hd")
          item.rec = rec
          cur.items[#cur.items + 1] = item
          cur.pending = true
          cur.open = nil
          self.stats.splits = self.stats.splits + 1
          return
        end
      elseif spec then
        self.stats.overCap = self.stats.overCap + 1
        overSpec = spec
      end
      -- the wallpaper drawn again in the scene (a ground fill continued under a text box moved
      -- off the screen, Kanto Gear): the recorded wallpaper already covers the whole view
      if image == cur.backdropImage and sceneFit() then return end
      -- with fill, a move's background in bands is recorded, and drawn across the whole view
      if self.fit.fill and sceneFit() then
        local item = wideBackground(image, ...)
        if item then
          cur.items[#cur.items + 1] = item
          cur.pending = true
          cur.open = nil
          self.stats.wide = (self.stats.wide or 0) + 1
          return
        end
      end
      local uiScreen = false
      if uiFill() then
        local a, b, c, d, e, f, g, h = ...
        uiScreen = drawCoversScene(image, a, b, c, d, e, f, g, h, cur.h)
        noteUICover(uiScreen)
        if not cur.uiStraddle then noteStraddle(drawRect(image, a, b, c, d, e, f, g, h)) end
      end
      -- a draw over the whole scene, or with fill over the whole UI (a fade), gets a layer of
      -- its own that covers the whole screen; with fill, one spanning the scene's width gets one
      -- whose sides run on to the screen's
      local kind = uiScreen and "screen" or nil
      local plane, run
      if not kind and sceneFit() and mosaicPiece(image, ...) then kind = "screen" end
      if not kind and sceneFit() then
        plane, run = planeTile(image, ...)
        if plane == "continue" then
          kind = "screen"
          -- (the run's first copy, alone in its layer still open: that layer covers the view)
          local item = run.item
          if item and cur.openItem == item and not item.screen then
            item.screen, item.edge, cur.open = true, false, "screen"
          end
          if not run.counted then
            run.counted = true
            self.stats.plane = (self.stats.plane or 0) + 1
          end
        elseif self.fit.fill then kind = sceneDrawKind(image, ...)
        elseif drawCoversScene(image, ...) then kind = "screen" end
      end
      -- (a run's first copy in a layer of its own, for it to become a whole-scene one)
      if plane == "start" and kind ~= "screen" then
        if kind and cur.open == kind then openLayer(kind) else cur.pending = true end
      end
      if not kind and self.fit.fill and sceneFit() then rowTile(image, ...) end
      -- (a move's effect crossing the canvas's edges: drawn uncut over the view instead)
      if not kind and not plane and sceneFit() and freeDraw(image, ...) then return end
      beforeDraw(kind)
      if plane == "start" then run.item = cur.openItem end
      if kind and not uiScreen then markBottom() end
      if cur.boxId ~= nil then boxBounds(drawRect(image, ...)) end
      if overSpec and drawAtScale(real.getShader() ~= nil, image, overSpec, ...) then return end
    end
    return real.draw(image, ...)
  end

  -- one of the intro's two black bars (self.window), filled across the UI's whole width from
  -- its top down to the window, or from the window down to its bottom: with Fill Screen it is
  -- recorded once (a "win0" item, drawn across the view) instead of drawn in the UI's box
  local function introBar(mode, x, y, w, h)
    local cur = self.cur
    local win = cur.win0
    if not (win and mode == "fill" and uiFill()) then return false end
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
      return false
    end
    local x0, y0 = real.transformPoint(x, y)
    local x1, y1 = real.transformPoint(x + w, y + h)
    if not (math.abs(x0) < 0.5 and math.abs(x1 - cur.w) < 0.5) then return false end
    local upper = math.abs(y0) < 0.5 and math.abs(y1 - win[1]) < 0.5
    local lower = math.abs(y0 - win[2]) < 0.5 and math.abs(y1 - cur.h) < 0.5
    if not (upper or lower) then return false end
    if not cur.win0Drawn then
      cur.win0Drawn = true
      local r, g, b, a = real.getColor()
      cur.items[#cur.items + 1] = { kind = "win0", top = win[1], bottom = win[2], color = { r, g, b, a } }
      -- what the UI draws after the bars (a bag, a menu) goes to a layer above them
      cur.pending = true
      cur.open = nil
    end
    return true
  end

  -- a wash over the battle's field drawn with its UI (a fill across the whole width from the
  -- top down to the text box's line, not to the canvas's bottom: Galar Rising's red flash on a
  -- Max Move): with Fill Screen it is recorded once (a "wash" item, drawn over the field across
  -- the view) instead of drawn in the UI's box. In the UI it crossed the split row, and the
  -- foe's HP box, moved up with the rows above it, fell back to the cart's place while it showed
  local function fieldWash(mode, x, y, w, h)
    local cur = self.cur
    if mode ~= "fill" or real.getShader() ~= nil then return false end
    if not coversScene(x, y, w, h) or (lastBottom or cur.h) >= cur.h - 0.5 then return false end
    local blend, alphaMode = real.getBlendMode()
    if blend ~= "alpha" then return false end
    local item = newItem("wash")
    item.bottom = lastBottom
    item.r, item.g, item.b, item.a = real.getColor()
    item.premultiplied = alphaMode == "premultiplied"
    cur.items[#cur.items + 1] = item
    -- what the UI draws after it goes to a layer above it
    cur.pending = true
    cur.open = nil
    return true
  end

  local function wrapPrimitive(name)
    return function(...)
      if self.cur and onPass() then
        if name == "rectangle" and introBar(...) then return end
        local kind, scene = nil, false
        if sceneFit() then
          if name == "rectangle" then
            local mode, x, y, w, h = ...
            if mode == "fill" and coversScene(x, y, w, h) then kind = "screen" end
          end
          -- with fill: a move's effect anchored to the canvas's sides (Fake Out's curtains, a
          -- procedural wave) runs on to the screen's
          if not kind and self.fit.fill and primitiveEdge(name, ...) then kind = "edge" end
          scene = kind ~= nil
        end
        if name == "rectangle" and uiFill() and fieldWash(...) then return end
        if name == "rectangle" and uiFill() then
          local mode, x, y, w, h = ...
          local screen = mode == "fill" and coversScene(x, y, w, h, self.cur.h)
          noteUICover(screen)
          if not self.cur.uiStraddle then noteStraddle(x, y, w, h) end
          kind = screen and "screen" or nil
        end
        beforeDraw(kind)
        if scene then markBottom() end
        if name == "rectangle" and self.cur.boxId ~= nil then
          local _, x, y, w, h = ...
          boxBounds(x, y, w, h)
        end
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

  -- the field's canvas while one of its pass's layers is the target: the weather swaps "the
  -- field canvas" for a colour-mapped one (Renderer:exchangeWorldCanvas), and keeps the one it
  -- was given to draw into next frame
  local function wrappedGetCanvas(...)
    local cur = self.cur
    if cur and cur.pass == "field" then
      local c = real.getCanvas(...)
      if c ~= nil and cur.layerSet[c] then return cur.base end
      return c
    end
    return real.getCanvas(...)
  end

  local function wrappedSetCanvas(arg, ...)
    if self.cur then arg = redirectArg(arg) end
    return real.setCanvas(arg, ...)
  end

  -- (love.graphics.pop returns nothing: no table of its results, which was garbage every pop)
  local function wrappedPop(...)
    real.pop(...)
    local cur = self.cur
    if cur then
      local c = real.getCanvas()
      if isPassCanvas(c) and c ~= cur.current then real.setCanvas(cur.current) end
    end
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
    G.getCanvas = wrappedGetCanvas
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

  -- failures this session; after a failure nothing is captured for retryAfter seconds, then it
  -- tries again (a one-off error, say on a screen rushed through on a phone, costs a moment, not
  -- the session); the maxFailures-th turns it off until the game restarts
  self.failures, self.maxFailures, self.retryAfter = 0, 3, 2
  function self.now()
    return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
  end

  --- Something of ours failed on this device: say so (which failure, the error), put back any
  --- pass in flight, and capture nothing until it tries again (self.recover), so the frames
  --- meanwhile are drawn the game's own way. While it is down, the exports report it off
  --- (isActive, enabled), so a sprite mod draws its own plain sprites, not stand-ins left for us.
  function self.fail(err)
    if self.failed then return end
    self.failures = self.failures + 1
    self.failed = tostring(err)
    self.failedAt = self.now()
    self.stats.failed, self.stats.failures = self.failed, self.failures
    self.direct = false
    if self.log and self.log.error then
      if self.failures < self.maxFailures then
        pcall(self.log.error, self.log, "could not draw a frame (failure %d of %d), drawn the game's usual way "
          .. "and trying again in %d s: %s", self.failures, self.maxFailures, self.retryAfter, self.failed)
      else
        pcall(self.log.error, self.log, "turned off for this session after %d failures, frames are drawn the "
          .. "game's usual way: %s", self.failures, self.failed)
      end
    end
    if self.cur then pcall(self.flatten, self.cur) end
  end

  --- After a failure, once retryAfter seconds have passed (and fewer than maxFailures so far):
  --- capture again.
  function self.recover()
    if not self.failed or self.failures >= self.maxFailures then return end
    if self.now() - (self.failedAt or 0) < self.retryAfter then return end
    self.failed, self.stats.failed = nil, nil
    if self.log and self.log.info then
      pcall(self.log.info, self.log, "trying again after failure %d of %d", self.failures, self.maxFailures)
    end
  end

  --- Is it down (failed, not yet trying again)? Checks for a retry first.
  function self.down()
    self.recover()
    return self.failed ~= nil
  end

  --- Start capturing a pass on `base` (the canvas currently drawn into).
  function self.beginPass(pass, base)
    -- a pass that was never ended (its frame was not presented the usual way): put it back
    if self.cur then self.flatten(self.cur) end
    self.inAnim = false
    if self.down() then return false end
    -- the engine no longer presents through the Renderer (canCapture: src/engine.lua): a pass
    -- could never be composited, so the game draws its own way
    if self.canCapture and not self.canCapture() then return false end
    if not (self.installed and self.enabled[pass] and base and base.getWidth) then return false end
    -- a screen another UI mod draws (OmniUI: src/omni.lua): the game draws it its own way
    if self.aside and self.aside(pass) then
      self.stats.aside = pass
      return false
    end
    -- (a pooled table, and its lists: pooledPass; `serial` tells passes apart)
    local c = pooledPass(pass)
    local kept = c.kept or {}
    passSerial = passSerial + 1
    c.serial = passSerial
    c.pass, c.base, c.current = pass, base, base
    c.layerSet, c.items = kept.layerSet or {}, kept.items or {}
    c.w, c.h, c.layerCount, c.splits = base:getWidth(), base:getHeight(), 0, 0
    c.cap, c.pending, c.segment, c.hasUI = self.caps[pass] or 8, false, "scene", false
    c.cardUi, c.coverAt = false, nil
    -- a screen over the field with Pokedex & Summary HD off: its Pokemon are drawn as tagged
    -- images usually are outside a pass (the screen still fills the screen)
    c.plain = pass == "screen" and not self.enabled.dex
    c.prefit = kept.prefit or {}
    -- each side's battler sized by its species, this pass (self.pair at its end)
    if pass == "battle" then c.sides = kept.sides or {} end
    -- the side shift this frame is drawn with (the engine's move coordinates use the same)
    local sh = kept.shift or {}
    sh.enemy, sh.player = self.fit.shift.enemy, self.fit.shift.player
    sh.playerY, sh.playerRaise = self.fit.shift.playerY, self.fit.shift.playerRaise
    c.shift = sh
    -- (the doubles spread the engine's coordinates were moved by for this frame)
    c.spread = self.fit.spread or 1
    self.cur = c
    -- (the mosaics seen covering the scene last battle pass are this one's whole-scene pieces)
    if pass == "battle" then self.mosaicNow, self.mosaicNext = self.mosaicNext, nil end
    return true
  end

  --- The scene of a battle ends here: what the pass draws next is the UI (Battle Fit). Also
  --- "uiTop" / "uiTopEnd" round the enemy's HUD (its HP box and what mods draw with it): on a
  --- screen whose top band is moved up, that layer goes with it whole.
  function self.seam(name)
    local cur = self.cur
    if not cur then return end
    local item = newItem("seam")
    item.name = name
    cur.items[#cur.items + 1] = item
    if name == "ui" then
      cur.segment = "ui"
      cur.hasUI = true
    end
    openLayer(false)
  end

  --- A battle's HP box is drawn from here to boxEnd (the adapter wraps the game's box draw): id
  --- its battler (0 / 2 the player's, 1 / 3 the foes'), ox, oy (canvas px) how far the game's
  --- slide-in and bounce move it from where it rests. With self.boxLayers set (a placement that
  --- moves the boxes; none yet) it is drawn in a layer of its own, with whatever another mod
  --- draws with it (badges, its own box picture), and its bounds are kept (cur.boxes[id]), so the
  --- composite could move it whole (the layer's item.box). Otherwise nothing changes.
  function self.boxBegin(id, ox, oy)
    local cur = self.cur
    if not (cur and self.boxLayers and cur.pass == "battle" and cur.segment == "ui" and cur.boxId == nil
            and id ~= nil and onPass()) then
      return false
    end
    cur.boxes = cur.boxes or {}
    local b = cur.boxes[id]
    if not b then
      b = {}
      cur.boxes[id] = b
    end
    b.ox, b.oy = tonumber(ox) or 0, tonumber(oy) or 0
    b.x0, b.y0, b.x1, b.y1 = math.huge, math.huge, -math.huge, -math.huge
    cur.boxId = id
    openLayer(nil)
    return true
  end
  function self.boxEnd()
    local cur = self.cur
    if not (cur and cur.boxId ~= nil) then return end
    cur.boxId = nil
    -- (what is drawn next goes to a layer of its own)
    cur.pending = true
  end

  --- Paint at the screen's resolution, here in the pass's order (over what the UI drew so far,
  --- under what it draws next): fn(a, ctx) is called when the pass is composited, ctx telling
  --- where the UI is on the screen (x, y: its canvas's origin; sx, sy: screen px per canvas
  --- px), the view's left and right (l, r) and the UI's margins beside it (extraL, extraR); a
  --- pass put back the low-res way calls it at the canvas's own scale. hide (canvas row): what
  --- the UI drew before it is cut off there (the rows a panel drawn in its place covered).
  --- runTo (canvas row): on a whole screen with the battle's text box (cardUi, Fill Screen), the
  --- picture's row above `hide` runs on down to it across the screen (a bar shorter than the
  --- panel it replaces). Returns false (nothing recorded) outside a pass's UI.
  function self.paint(fn, a, hide, runTo)
    local cur = self.cur
    if not (cur and (cur.segment == "ui" or cur.cardUi) and onPass()) then return false end
    cur.items[#cur.items + 1] = { kind = "paint", fn = fn, a = a, hide = hide, runTo = runTo }
    cur.pending = true
    return true
  end

  --- What the pass draws from here goes into layers moved into a bar across the screen's bottom
  --- (spec: { top, bottom: the bar's canvas rows; dy: rows the drawing moves down; split: the
  --- canvas column from which it is moved right with the UI's right margin, the rest left with
  --- its left one (nil: all of it left) }); nil ends it. Returns false outside a pass's UI.
  function self.bar(spec)
    local cur = self.cur
    if not (cur and (cur.segment == "ui" or cur.cardUi)) then return false end
    if cur.barSpec == spec then return true end
    cur.barSpec = spec
    cur.pending = true
    return true
  end

  --- This pass is a whole screen showing the battle's text box without a battle's UI (a catch's
  --- Pokedex page, an evolution): its paint and bar layers are drawn as a battle's UI's are, the
  --- bar across the screen (with Fill Screen, over its whole picture: compositeCard).
  function self.cardUi()
    if self.cur then self.cur.cardUi = true end
  end

  --- Draw the battle's wallpaper: recorded, then drawn at window resolution, wrapped so the
  --- zoomed-out scene never shows its edge. Outside a pass it is simply drawn.
  function self.backdrop(image, x, y)
    local cur = self.cur
    if not (cur and onPass()) then return real.draw(image, x, y) end
    local rec = record(image, NO_SPEC, x, y)
    if not rec then return real.draw(image, x, y) end
    local item = newItem("backdrop")
    item.rec = rec
    cur.items[#cur.items + 1] = item
    cur.backdropImage = image
    cur.pending = true
    cur.open = nil
  end

  --- The battle scene's world in place of the wallpaper (Battle Scene: Overworld, src/scene/):
  --- recorded with the draw state the wallpaper would have had (a move's dimming, flash or
  --- palette shader, the background's shake as the transform), then drawn by the composite at
  --- window resolution through self.sceneRenderer, with the scene's own mapping. `image` (the
  --- wallpaper) is what shows when the frame is put back the low-res way. Returns false outside
  --- a pass (nothing recorded).
  self.sceneRenderer = nil
  function self.world(image, scene, x, y)
    local cur = self.cur
    if not (cur and onPass() and self.sceneRenderer) then return false end
    local rec = record(image, NO_SPEC, x or 0, y or 0)
    if not rec then return false end
    local item = newItem("world")
    item.rec, item.scene = rec, scene
    cur.items[#cur.items + 1] = item
    -- (the battlers stand in it at its scale: worldSize)
    cur.world = scene
    cur.backdropImage = image
    cur.pending = true
    cur.open = nil
    return true
  end

  -- the world item at window resolution: rendered for the screen rect `box` ({x, y, w, h}) with
  -- the scene's mapping (canvas pixels -> screen), then drawn there with its recorded draw state.
  -- False when it could not be (the caller draws the wallpaper instead)
  local function worldDraw(item, bx, by, bsx, bsy, box)
    local ok, c, x, y = pcall(self.sceneRenderer, item, bx, by, bsx, bsy, box)
    if not (ok and c) then
      if not ok then self.stats.sceneError = tostring(c) end
      return false
    end
    local rec = item.rec
    scissorOver(box[1], box[2], box[3], box[4])
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    real.draw(c, x, y)
    self.stats.world = (self.stats.world or 0) + 1
    return true
  end

  --- Draw a band that wraps sideways (the intro's scrolling grass): recorded, then drawn at
  --- window resolution with the scene's zoom, repeated across the whole view so the zoomed-out
  --- scene never shows its ends. Outside a pass it is simply drawn.
  function self.band(image, x, y)
    local cur = self.cur
    if not (cur and onPass()) then return real.draw(image, x, y) end
    local rec = record(image, NO_SPEC, x, y)
    if not rec then return real.draw(image, x, y) end
    local item = newItem("band")
    item.rec, item.fill = rec, self.solidRow(image)
    cur.items[#cur.items + 1] = item
    cur.pending = true
    cur.open = nil
  end

  --- A band's last solid row (at least nine tenths of its width opaque), or false: the grass,
  --- sand and waves of the intro end on one, and past it the band runs on down to the view's
  --- bottom. Read back once an image (a canvas's pixels); false where that cannot be done.
  local solidRows = setmetatable({}, { __mode = "k" })
  function self.solidRow(image)
    local row = solidRows[image]
    if row ~= nil then return row end
    row = false
    local w, h = image.getWidth and image:getWidth(), image.getHeight and image:getHeight()
    if w and h and w > 0 and h > 0 then
      local ok, c = pcall(real.newCanvas, w, h, { dpiscale = 1 })
      if ok and c and c.newImageData then
        real.push("all")
        real.setCanvas(c)
        real.origin()
        real.setScissor()
        real.setShader()
        real.clear(0, 0, 0, 0)
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("replace", "premultiplied")
        real.draw(image, 0, 0)
        real.pop()
        local okD, data = pcall(c.newImageData, c)
        if okD and data then
          local need = math.ceil(w * 0.9)
          for y = h - 1, 0, -1 do
            local n = 0
            for x = 0, w - 1 do
              local _, _, _, a = data:getPixel(x, y)
              if a > 0.5 then n = n + 1 end
            end
            if n >= need then row = y; break end
          end
          if data.release then pcall(data.release, data) end
        end
        if c.release then pcall(c.release, c) end
      end
    end
    solidRows[image] = row
    return row
  end

  --- The battle intro's black bars this pass (the cart's WIN0: rows top..bottom show, the rest
  --- is black; nil, nil: none). With Fill Screen the engine's two bar rectangles are not drawn
  --- in the UI's box but across the whole view (composite, the "win0" item).
  function self.window(top, bottom)
    local cur = self.cur
    if not cur then return end
    cur.win0 = (type(top) == "number" and type(bottom) == "number") and { top, bottom } or nil
  end

  --- Draw part of the battle's stage that is as big as the screen but is not a whole-scene
  --- effect (a pad, drawn on a transparent screen-sized image): it zooms with the scene.
  --- side ("enemy" / "player", optional): the pad moves with that side's shift (Battle Fit),
  --- so it is recorded and drawn at window resolution instead of into the canvas.
  function self.drawStage(image, x, y, side)
    local cur = self.cur
    if side and cur and onPass() and self.fit.enabled and cur.pass == "battle" then
      local rec = record(image, NO_SPEC, x, y)
      if rec then
        local item = newItem("stage")
        item.rec, item.side = rec, side
        cur.items[#cur.items + 1] = item
        cur.pending = true
        cur.open = nil
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
  --- Pokemon's own movement (a jump, a lunge). Cleared each pass. key: one of several on a side
  --- (a double battle's battler id); the side by default.
  --- present: false while it is not out (before its send-out, after its faint): sized, but the
  --- 3D world's single battles frame only the Pokemon out on the field.
  -- (each key's record kept between passes: the pass's fit and composite read it the same frame)
  local prefitKept = {}
  function self.prefit(side, image, x, y, key, present)
    local cur = self.cur
    -- (a Pokemon drawn giant for a while, exports.giant: where it rests at that size, its form's
    -- picture in its place; its own picture's tag kept for its height)
    local g = self.giants[key or (side == "player" and 0 or 1)]
    local gs = 1
    if giantLive(g) and type(x) == "number" and type(y) == "number" then
      local own = image ~= nil and self.tags[image]
      -- (its height, for its size in the 3D world)
      if own and speciesTag(own) then g.own = own end
      if own and own.side ~= nil and not own.trainer then
        -- (its own picture where it rests: the giant's feet are put on its feet)
        local o = g.ownRec
        if not o then o = {}; g.ownRec = o end
        o.spec, o.image, o.x, o.y, o.r, o.sx, o.sy, o.ox, o.oy = own, image, x, y, 0, 1, 1, 32, 32
        o.tx, o.ty, o.tsx, o.tsy, o.rest, o.noGiant = 0, 0, 1, 1, true, true
      else
        g.ownRec = nil
      end
      if g.image ~= nil and self.tags[g.image] then image = g.image end
      x, y, gs = x + g.dx, y + g.dy, g.scale
    end
    local spec = image ~= nil and self.tags[image]
    if not (cur and spec and type(x) == "number" and type(y) == "number") then return end
    local k = key or side
    local r = prefitKept[k]
    if not r then r = {}; prefitKept[k] = r end
    r.spec, r.image, r.x, r.y, r.r, r.sx, r.sy, r.ox, r.oy = spec, image, x, y, 0, gs, gs, 32, 32
    r.tx, r.ty, r.tsx, r.tsy, r.rest, r.out = 0, 0, 1, 1, true, present ~= false
    cur.prefit[k] = r
    if giantLive(g) then g.restRec, g.fixStale = r, true end
    if cur.sides and speciesTag(spec) then cur.sides[spec.side] = spec end
  end

  --- Whether the opposing trainer is shown this pass (its intro, its last words): the 3D world's
  --- single battles frame it at the camera's own zoom.
  function self.fieldTrainer(on)
    if self.cur then self.cur.trainerOut = on == true end
  end

  --- Stop capturing. The pass waits for its canvas's blit (or flatten).
  function self.endPass()
    local cur = self.cur
    if not cur then return nil end
    self.cur = nil
    self.worldScene = cur.pass == "battle" and cur.world or nil
    -- the battlers' pair: afresh when a battle starts (no battle fitted for a few frames), then
    -- each side's latest
    if cur.sides then
      if self.fit.idle > 2 then
        self.pair = {}
        self.playerIn = false
        self.giantsOff()
        for i = #worldMons, 1, -1 do worldMons[i] = nil end
        self.worldShadow.enemy, self.worldShadow.player = nil, nil
      end
      for side, spec in pairs(cur.sides) do self.pair[side] = spec end
      if cur.playerIn then self.playerIn = true end
    end
    -- leave the drawing target where the engine expects it
    local c = real.getCanvas()
    if c ~= nil and (c == cur.base or cur.layerSet[c]) and c ~= cur.base then real.setCanvas(cur.base) end
    if cur.cm and cur.cm.shader then
      self.done[cur.cm.to] = cur
    elseif #cur.items > 0 or cur.pass == "boot" or cur.pass == "screen" then
      -- (a boot screen or a screen over the field is composited even with nothing tagged: it
      -- fills the screen)
      self.done[cur.base] = cur
    end
    return cur
  end

  --- Draws made straight at the window's resolution, with no low-res canvas to capture (Gen 2's
  --- field: Gold draws its map and people to the window at its zoom). While `pass` is on, a
  --- tagged image is drawn in place at its spec's size about its pivot (what a pass's draw past
  --- its cap does on the canvas): already sharp and between pixels, so nothing is recorded.
  --- Returns true when it turned it on (a nested call returns false: the outer one ends it).
  function self.beginDirect(pass)
    if self.direct or self.cur or self.down() then return false end
    if not (self.installed and self.enabled[pass]) then return false end
    if self.aside and self.aside(pass) then return false end
    self.direct = pass
    return true
  end

  function self.endDirect()
    self.direct = false
  end

  --- The weather is about to swap the field canvas for one it draws through its colour map
  --- (`to`): the pass goes on, and the colour map is applied to the composite instead.
  function self.colorMapStart(to)
    local cur = self.cur
    if not (cur and cur.pass == "field" and to) then return false end
    cur.cm = { to = to, armed = true }
    return true
  end

  -- canvases for the colour-mapped composite, by size
  local mapPool = {}
  function self.mapTargets(w, h)
    local key = w .. "x" .. h
    local pair = mapPool[key]
    if not pair then
      pair = { real.newCanvas(w, h, { dpiscale = 1 }), real.newCanvas(w, h, { dpiscale = 1 }) }
      mapPool[key] = pair
    end
    return pair[1], pair[2]
  end

  --- `src` through the pass's colour map into `dst`, at its corner (the shader reads its actor
  --- mask by the target's pixels: maskSize is the target's size)
  local maskSize = { 0, 0 }
  function self.drawMapped(cm, src, dst)
    real.push("all")
    real.origin()
    real.setScissor()
    real.setCanvas(dst)
    real.clear(0, 0, 0, 0)
    real.setColor(1, 1, 1, 1)
    useShader(cm)
    if shaderReal.send and cm.uniforms and cm.uniforms.maskSize then
      maskSize[1], maskSize[2] = dst:getWidth(), dst:getHeight()
      pcall(shaderReal.send, cm.shader, "maskSize", maskSize)
    end
    real.setBlendMode("replace", "premultiplied")
    real.draw(src, 0, 0)
    real.pop()
    restoreShaders()
  end

  function self.capturing(pass)
    return self.cur ~= nil and (pass == nil or self.cur.pass == pass)
  end

  -- ------------------------------------------------------------- composite

  -- where a tagged draw stands: the point in pass-canvas pixels where its HD pivot goes
  -- (X, Y), that pivot in the HD frame (hpx, hpy), its size k, the texture and quad
  -- raw: only where its pivot stands (X, Y), a giant's feet not yet put on its own's
  local function place(rec, raw)
    local spec = rec.spec
    local tex = spec.texture or rec.image
    local quad = spec.texture and spec.quad or viewOf(rec)
    -- a quad of its own may stand on another point (a sprite drawn cut short) and
    -- carry its own size (a slice already drawn at its final size: 1)
    local qp = spec.quadPivots and rec.quad and spec.quadPivots[rec.quad]
    -- the low-res point that the HD pivot stands on, and the pivot in the HD texture
    local lpx, lpy, hpx, hpy
    -- a piece of a frame drawn on its own (`frame`: a reflection, drawn cell by cell or column
    -- by column): a part of the frame, as below, so each piece shows the grown frame through
    -- exactly the rectangle it was drawn in (no gaps, nothing past the water)
    local piece = frameOf(spec, rec, qp)
    if piece then
      lpx, lpy = piece[3] / 2, piece[4]
      hpx, hpy = lpx, lpy
      quad = frameQuad(piece, rec)
    elseif spec.anchor == "feet" and rec.quad and not qp then
      lpx, lpy = feetOf(spec, rec.qx, rec.qy, rec.qw, rec.qh)
      hpx, hpy = lpx, lpy
    else
      local lp = qp or spec.lowPivot or { 32, 32 }
      local hp = (not qp and spec.pivot) or lp
      lpx, lpy, hpx, hpy = lp[1], lp[2], hp[1], hp[2]
    end
    -- a part of the pic drawn on its own (its rows one by one, each shifted: Rapid Spin,
    -- Extrasensory, Dig): the pivot is the whole pic's, and the HD frame is cut to that part
    local ox, oy = rec.ox, rec.oy
    local part = (spec.texture and spec.quad and rec.quad and not qp) or piece ~= nil
    local vx, vy, vw, vh
    if piece then
      vx, vy, vw, vh = rec.qx - piece[1], rec.qy - piece[2], rec.qw, rec.qh
      ox, oy = ox + vx, oy + vy
    elseif part then
      vx, vy, vw, vh = rec.qx, rec.qy, rec.qw, rec.qh
      ox, oy = ox + vx, oy + vy
    end
    -- where the low-res draw put that point, in the pass canvas's pixels
    local dx, dy = (lpx - ox) * rec.sx, (lpy - oy) * rec.sy
    local cs, sn = math.cos(rec.r), math.sin(rec.r)
    local px = rec.x + dx * cs - dy * sn
    local py = rec.y + dx * sn + dy * cs
    -- (a giant, exports.giant: moved so that its feet - its tag's pivot - stand where its own
    -- picture's stand at rest, whatever offsets the mod drawing it gave it: grown or in its
    -- Gigantamax form it stays on the same spot of the ground; worked out once a frame)
    local g = not raw and not rec.noGiant and spec.side ~= nil and not spec.trainer and giantOf(spec) or nil
    if g and g.restRec and g.ownRec then
      if g.fixStale then
        g.fixStale = false
        local ox, oy = place(g.ownRec, true)
        local gx, gy = place(g.restRec, true)
        g.fixX, g.fixY = ox - gx, oy - gy
      end
      px, py = px + (g.fixX or 0), py + (g.fixY or 0)
    end
    local X, Y = rec.tx + px * rec.tsx, rec.ty + py * rec.tsy
    if raw then return X, Y end
    local k = (qp and qp[3]) or spec.scale or 1
    if not qp then
      -- (in the 3D world: at its scale, where it stands - a giant toward the tallest's; else its
      -- own size, unless too big)
      local world = tuned() and self.fit.enabled and not (self.fit.double and self.fit.doublesOwnSize)
      local w = world and g and giantSize(g, spec, hpy, X, Y)
      if not w then
        w = world and speciesTag(spec) and worldSize(spec, rec.image, lpx, lpy, hpx, hpy, rec.sx, rec.sy, X, Y, rec.rest)
      end
      k = w or ownSize(spec, rec.image, k, lpx, lpy, hpx, hpy, rec.sx, rec.sy)
    end
    -- (cut: {x0, y0, x1, y1} in the HD texture's pixels)
    local cut
    if part then
      local fx, fy, fw, fh = (piece and quad or spec.quad):getViewport()
      -- (a mirrored frame: the part's columns from the other side of the pivot)
      local x0, x1 = (vx - lpx) / k, (vx + vw - lpx) / k
      if spec.flip then x0, x1 = -x1, -x0 end
      cut = { math.max(fx, fx + hpx + x0), math.max(fy, fy + hpy + (vy - lpy) / k),
              math.min(fx + fw, fx + hpx + x1), math.min(fy + fh, fy + hpy + (vy + vh - lpy) / k) }
    end
    return X, Y, hpx, hpy, k, tex, quad, cut
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
    if rec.spec.flip then return X - (fw - hpx) * s, X + hpx * s end
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
    if rec.quad then lqx, lqy = rec.qx, rec.qy end
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
  -- shader (optional): drawn through it instead of the draw's own
  local cutQuad
  local function hdDraw(rec, bx, by, bsx, bsy, pinTo, shader)
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
    local flip = rec.spec.flip and rec.spec.texture ~= nil
    local m = rec.uniforms and not flip and not shader and texMap(rec, X, Y, hpx, hpy, k, tex, quad)
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
    if shader then real.setShader(shader) else useShader(rec, m) end
    real.setBlendMode(rec.blend[1], rec.blend[2])
    local SX, SY = bx + X * bsx, by + Y * bsy
    local ssx, ssy = rec.sx * k * rec.tsx * bsx, rec.sy * k * rec.tsy * bsy
    -- flip: the full-resolution frame mirrored about its pivot (a stand-in drawn mirrored)
    if flip then ssx = -ssx end
    -- the contact shadow first, under the whole pic (not a part of it: each part would add one),
    -- and not through a shader mapped to the frame's texture (a move's mask or mosaic)
    if rec.spec.shadow and not cut then
      if m then real.setShader() end
      drawShadow(rec.spec, SX, SY, rec.r, ssx, ssy)
      if m then useShader(rec, m) end
    end
    if quad then
      real.draw(tex, quad, SX, SY, rec.r, ssx, ssy, hpx, hpy)
    else
      real.draw(tex, SX, SY, rec.r, ssx, ssy, hpx, hpy)
    end
  end

  -- A tagged draw at window resolution, mapped by (bx, by, bsx, bsy) and clipped to box (nil: the
  -- blit's own). One in the game's shades (spec.shades) is drawn through that shader into a canvas
  -- k times the pass's size, then through the game's blit (zk = k), which colours it with the
  -- screen as it does the stand-in (Red's SGB palettes, zone by zone). Its art is kept to the pass
  -- canvas's bounds (the Pokedex and summary pics are well inside them).
  local shadeK, shadeKW, shadeKH = nil, 0, 0
  local function tagDraw(rec, cur, blit, bx, by, bsx, bsy, box, pinTo)
    local sh = rec.spec.shades
    if not (sh and blit and real.newCanvas) then return hdDraw(rec, bx, by, bsx, bsy, pinTo) end
    local k = math.max(1, math.min(16, math.ceil(math.max(math.abs(bsx), math.abs(bsy)) - 1e-6)))
    local w, h = cur.w * k, cur.h * k
    if not shadeK or shadeKW ~= w or shadeKH ~= h then
      if shadeK and shadeK.release then pcall(shadeK.release, shadeK) end
      shadeK = real.newCanvas(w, h, { dpiscale = 1 })
      if shadeK.setFilter then shadeK:setFilter("linear", "linear") end
      shadeKW, shadeKH = w, h
    end
    real.push("all")
    real.setCanvas(shadeK)
    real.origin()
    real.setScissor()
    real.clear(0, 0, 0, 0)
    hdDraw(rec, 0, 0, k, k, pinTo and (pinTo - by) / bsy * k, sh)
    real.pop()
    real.setShader()
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("alpha", "premultiplied")
    blit(shadeK, bx, by, bsx / k, bsy / k, box, k)
    real.setBlendMode("alpha", "alphamultiply")
    self.stats.shaded = (self.stats.shaded or 0) + 1
  end

  -- a recorded plain image (a pad) at window resolution, mapped by (bx, by, bsx, bsy)
  local function imageDraw(rec, bx, by, bsx, bsy)
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    local X, Y = rec.tx + rec.x * rec.tsx, rec.ty + rec.y * rec.tsy
    local sx, sy = rec.sx * rec.tsx * bsx, rec.sy * rec.tsy * bsy
    if rec.quad then
      real.draw(rec.image, viewOf(rec), bx + X * bsx, by + Y * bsy, rec.r, sx, sy, rec.ox, rec.oy)
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
  -- fill: a band's last solid row, repeated from below it down to the view's bottom
  local fillQuad
  local function drawBackdrop(rec, cw, ch, bx, by, bsx, bsy, fx, fy, fsx, fsy, wrapV, fill)
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
    if fill then
      local r0, r1 = math.max(fill + 1, v0), v0 + vh
      if r1 > r0 then
        fillQuad = quad(fillQuad, u0, fill, uw, 1)
        real.draw(img, fillQuad, bx + p0x * bsx, by + (p0y + (r0 - v0) * rec.tsy) * bsy, 0, sx, sy * (r1 - r0))
      end
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
    local fit = self.fit
    local fy = fit.focus[2]
    return fy + (y + (fit.sceneUp or 0) - fy) * (fit.uiK or 1)
  end
  local function uiRect(r)
    local fit = self.fit
    local k, up = fit.uiK or 1, fit.sceneUp or 0
    if k == 1 and up == 0 then return r end
    local fx, fy = fit.focus[1], fit.focus[2]
    return { fx + (r[1] - fx) * k, fy + (r[2] + up - fy) * k, fx + (r[3] - fx) * k, fy + (r[4] + up - fy) * k }
  end

  -- the enemy's HP box over the scene, in the scene's canvas pixels: moved up with the
  -- stacked layout's top band, then as uiRect (remembered: the solver asks for it a lot)
  local enemyUI, enemyUIKey, enemyUIUp = nil, nil, nil
  local function uiEnemy()
    local fit = self.fit
    local d = fit.uiTopDy or 0
    local key, up = (fit.uiK or 1) * 1e6 + d, fit.sceneUp or 0
    if enemyUIKey ~= key or enemyUIUp ~= up then
      local e = fit.ui.enemy
      enemyUI = uiRect({ e[1], e[2] + d, e[3], e[4] + d })
      enemyUIKey, enemyUIUp = key, up
    end
    return enemyUI
  end

  -- the highest canvas row art may reach: the screen's top, less the margin (none when species
  -- sizing fits the battlers in their rooms: on the Game Boy the enemy's starts at the top)
  local function topLimit()
    local fit = self.fit
    local sized = not fit.double and (self.pair.enemy ~= nil or self.pair.player ~= nil)
    return (fit.topY or 0) + (sized and 0 or fit.margin)
  end

  local function fitLift(z)
    local fit = self.fit
    -- (a double battle's boxes are higher than the game's own sprites were placed for: without
    -- tagged foes the scene keeps its place, its art's height unknown)
    if fit.double and not fit.doubleArt then return 0 end
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

  -- each battle Pokemon's body box as this frame drew it on the window (exports.battlerRect, for
  -- a mod that draws over a battler from render.hud - Galar Rising's Dynamax cloud): by its side
  -- ("player" / "enemy") and, in a double battle, by its battler id (0..3) too. Window pixels,
  -- whatever the fit, the real sizes or the 3D world made of it; the parts of a pic drawn row by
  -- row joined. Off at each frame's start (Renderer.beginFrame); its tables kept.
  self.battlerRects = {}
  -- who is holding the battle's HUD in place (exports.holdHud): owner -> true
  self.hudHolds, self.hudHeld, self.heldDyTop = {}, 0, nil
  function self.holdHud(who, on)
    if who == nil then return end
    self.hudHolds[who] = on and true or nil
    local n = 0
    for _ in pairs(self.hudHolds) do n = n + 1 end
    self.hudHeld = n
  end
  function self.clearBattlerRects()
    for _, r in pairs(self.battlerRects) do r.on = false end
  end
  local function noteRect(key, x0, y0, x1, y1)
    local r = self.battlerRects[key]
    if not r then r = {} self.battlerRects[key] = r end
    if r.on then
      if x0 < r[1] then r[1] = x0 end
      if y0 < r[2] then r[2] = y0 end
      if x1 > r[3] then r[3] = x1 end
      if y1 > r[4] then r[4] = y1 end
    else
      r[1], r[2], r[3], r[4], r.on = x0, y0, x1, y1, true
    end
  end
  -- a battler's tagged draw at window mapping (bx, by, bsx, bsy) - the composite's own for it
  -- (its box: the tag's body, else its art, else its frame from its top row; canvas px as bodyRect)
  local function noteBattler(cur, rec, bx, by, bsx, bsy)
    local spec = rec and rec.spec
    if not (spec and spec.side and not spec.trainer) then return end
    local X, Y, hpx, hpy, k, _, quad = place(rec)
    local b = type(spec.body) == "table" and spec.body or type(spec.art) == "table" and spec.art or nil
    local b1, b2, b3, b4
    if b then
      b1, b2, b3, b4 = b[1], b[2], b[3], b[4]
    else
      local qw, qh
      if quad and quad.getViewport then
        local _, _, w, h = quad:getViewport()
        qw, qh = w, h
      elseif spec.texture or rec.image then
        local img = spec.texture or rec.image
        if img.getDimensions then qw, qh = img:getDimensions() end
      end
      if not qw then return end
      b1, b2, b3, b4 = 0, tonumber(spec.top) or 0, qw, qh
    end
    local sx, sy = rec.sx * k * rec.tsx, rec.sy * k * rec.tsy
    local a, c = X + (b1 - hpx) * sx, X + (b3 - hpx) * sx
    local bb, d = Y + (b2 - hpy) * sy, Y + (b4 - hpy) * sy
    local x0, x1 = bx + a * bsx, bx + c * bsx
    local y0, y1 = by + bb * bsy, by + d * bsy
    if x1 < x0 then x0, x1 = x1, x0 end
    if y1 < y0 then y0, y1 = y1, y0 end
    noteRect(spec.side, x0, y0, x1, y1)
    -- (a double battle: its battler id from the battle's resting places, the nearest of its side
    -- with the same Pokemon)
    local prefit = cur and cur.prefit
    if not prefit then return end
    local X = (place(rec))
    local best, bestD = nil, math.huge
    for id, pr in pairs(prefit) do
      if type(id) == "number" and pr.spec and pr.spec.side == spec.side and sameMon(pr.spec, spec) then
        local dd = math.abs((place(pr)) - X)
        if dd < bestD then best, bestD = id, dd end
      end
    end
    if best ~= nil then noteRect(best, x0, y0, x1, y1) end
  end
  self.noteBattler = noteBattler

  local function overlap(a0, a1, b0, b1) return math.max(0, math.min(a1, b1) - math.max(a0, b0)) end

  -- how much of the rectangle (canvas px, unzoomed), seen at zoom z raised by lift, is under
  -- the enemy's HP box, and under the player's side (its HP box and the text box); and its top
  --- How far the player's side is lowered (canvas px before the zoom) at zoom z raised by
  --- lift, so its pad stays tucked under the text box (fit.padTuck).
  local function playerDrop(z, lift)
    local fit = self.fit
    if self.worldScene or (z >= 1 and lift <= 0) then return 0 end
    local cart = fit.focus[2] - fit.padTop                 -- rows the cart shows (11)
    local tucked = fit.padRows * (1 - fit.padTuck)         -- rows shown at zMin (8)
    local u = math.max(0, math.min(1, (z - fit.zMin) / math.max(1e-6, 1 - fit.zMin)))
    local visible = tucked + (cart - tucked) * u
    return (lift + (cart - visible) * z) / z
  end
  self.fitPlayerDrop = playerDrop

  local function hidden(r, z, lift)
    local fit = self.fit
    local fx, fy = fit.focus[1], fit.focus[2]
    local x0, x1 = fx + (r[1] - fx) * z, fx + (r[3] - fx) * z
    local y0, y1 = fy + (r[2] - fy) * z - lift, fy + (r[4] - fy) * z - lift
    local area = math.max(1e-6, (x1 - x0) * (y1 - y0))
    local function under(u) return overlap(x0, x1, u[1], u[3]) * overlap(y0, y1, u[2], u[4]) end
    return under(uiEnemy()) / area, (under(uiRect(fit.ui.player)) + under(uiRect(fit.ui.text))) / area, y0
  end
  self.fitHidden = hidden

  --- The camera for a frame: the largest zoom (and with it the least rise past the enemy's
  --- feet) that keeps the enemy's art under the top of the screen with its feet above the
  --- player's HP box, and each of the player's Pokemon (`backs`, resting body rects) with its
  --- whole animation (r.top, a head flung up) on the screen. The HP boxes and the text box may
  --- cover a Pokemon, as on the cart: the camera only makes room for what would leave the
  --- screen. top: the enemy art's top (math.huge: none). Returns the zoom and the rise.
  local solved, solvedCount = {}, 0
  local function fitSolveRaw(top, backs)
    local fit = self.fit
    local fy = fit.focus[2]
    local zFront = math.max(fit.zMin, fitZoom(top))
    if #backs == 0 then return zFront, 0 end
    local limit = topLimit()
    local fx = fit.focus[1]
    local function fits(z, lift)
      for _, r in ipairs(backs) do
        -- the back where the player side's drop puts it
        local v = playerDrop(z, lift)
        local y0 = fy + (r[2] + v - fy) * z - lift
        local t = r.top and (fy + (r.top + v - fy) * z - lift) or y0
        -- (a giant, exports.giant: its head under the foe's HP box too, where it stands under
        -- the box's columns - the cart's own sizes may reach behind it, a giant's would hide)
        local lim = limit
        if r.giant then
          local e = uiEnemy()
          local x0, x1 = fx + (r[1] - fx) * z, fx + (r[3] - fx) * z
          if x1 > e[1] and x0 < e[3] then lim = math.max(lim, e[4] + (fit.headGap or 0) * (fit.uiK or 1)) end
        end
        if y0 < lim or t < lim then return false end
      end
      return true
    end
    local z = zFront
    while z >= fit.zMin - 1e-9 do
      local base = fitLift(z)
      local most = base + fit.extraMax
      -- rising lifts the enemy too: its art's top must stay under the screen's
      if top < math.huge then most = math.min(most, fy + (top - fy) * z - limit) end
      local lift = base
      while lift <= most + 1e-9 do
        if fits(z, lift) then return z, lift - base end
        lift = lift + 1
      end
      z = z - fit.zStep
    end
    -- nothing fits even pulled all the way back: pulled all the way back is still the
    -- nearest, so clamp to the limit (never fall back to the enemy's own zoom)
    return fit.zMin, 0
  end

  -- the same, remembered: an animation repeats its frames, so a frame's inputs recur
  local function fitSolve(top, backs)
    local fit = self.fit
    local parts = { string.format("%.2f|%.3f|%.4f|%.2f|%.2f|%.2f|%s|%s", top, fit.zMin, fit.uiK or 1,
      fit.topY or 0, fit.uiTopDy or 0, fit.sceneUp or 0, tostring(fit.doubleArt), tostring(self.worldScene ~= nil)) }
    for _, r in ipairs(backs) do
      parts[#parts + 1] = string.format("%.2f,%.2f,%.2f,%.2f,%.2f%s", r[1], r[2], r[3], r[4], r.top or 0,
        r.giant and "g" or "")
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

  --- Whether a turn is playing (the battle is not waiting for the player): set by the adapter
  --- before each battle pass. While it is, Battle Fit only pulls out (fit.turn).
  function self.setTurn(on)
    self.fit.turn = on == true
  end

  --- Which battle's UI the fit plans around: a double battle's two HP boxes a side stand
  --- elsewhere. enemy, player: each side's boxes together, {x0, y0, x1, y1} canvas px. The foes'
  --- feet stay above the player's boxes, a back's head just under the foes', and the stacked
  --- layout splits the UI between them. Without both (or `on` false): the singles layout.
  function self.setDouble(on, enemy, player)
    local fit = self.fit
    on = on == true and enemy ~= nil and player ~= nil
    if fit.double == on then return end
    fit.double, fit.doubleArt = on, false
    if on then
      fit.ui = { enemy = enemy, player = player, text = fit.singles.ui.text }
      fit.feetMax = player[2]
      fit.backTopMin = enemy[4] + fit.doublesGap
      fit.split = math.floor((enemy[4] + player[2]) / 2 + 0.5)
      fit.shiftMax = fit.doublesShiftMax
    else
      fit.ui, fit.feetMax = fit.singles.ui, fit.singles.feetMax
      fit.backTopMin, fit.split = fit.singles.backTopMin, fit.singles.split
      fit.shiftMax = fit.singles.shiftMax
    end
    enemyUIKey = nil
    solved, solvedCount = {}, 0
  end

  -- the stage zoom for this frame: the camera that fits the tagged sprites, eased (out fast;
  -- back in only after the target has stayed nearer for holdFrames)
  -- the same Pokemon on each side (and the same screen) as when the foe's HP box was placed
  local function sameOut(a, b) return (a == nil and b == nil) or (a ~= nil and b ~= nil and sameMon(a, b)) end
  -- (fitStep's own lists, kept between frames and emptied each: read only inside it)
  local fitReported, fitSeen, fitHeads, headRows = {}, {}, {}, {}
  local function emptied(t) for k in pairs(t) do t[k] = nil end return t end
  -- a battler taken into fitStep's sums (F: takeF, its state this frame) - one function, not a
  -- closure each frame
  local takeF = {}
  local function takeRec(F, rec)
    local cur, fit = F.cur, self.fit
    local spec = rec.spec
    if spec.side then F.seen[spec.side] = true end
    local d = (not rec.inAnim and cur.shift[spec.side == "player" and "player" or "enemy"]) or 0
    local a, b = artSpan(rec)
    if spec.side and not spec.trainer then
      local sx = spreadDx((place(rec)), spec)
      a, b = a + sx, b + sx
    end
    if spec.side then
      local sd = spec.side == "player" and "player" or "enemy"
      local u0, u1 = a, b
      if not rec.inAnim then u0, u1 = a + d - cur.shift[sd], b + d - cur.shift[sd] end
      local _, feetY = place(rec)
      local heads = F.heads
      local n = #heads + 1
      local row = headRows[n]
      if not row then row = {}; headRows[n] = row end
      row[1], row[2], row[3], row[4], row[5] = u0, u1, artTop(rec), sd, feetY
      heads[n] = row
      -- (each side's body: the middle of its art where it rests, what its moves are aimed at)
      if not spec.trainer and feetY then
        if sd == "enemy" then F.aimE = (artTop(rec) + feetY) / 2 else F.aimP = (artTop(rec) + feetY) / 2 end
      end
    end
    if spec.side == "player" then
      if not rec.inAnim then a, b = a + d - cur.shift.player, b + d - cur.shift.player end
      F.pL, F.pR = math.min(F.pL, a), math.max(F.pR, b)
      F.apL, F.apR = math.min(F.apL, a), math.max(F.apR, b)
      if spec.body then
        local r = { bodyRect(rec) }
        r.giant = giantOf(spec) ~= nil
        F.pT = math.min(F.pT, r[2])
        -- where the side shift puts it (only its x: which UI it is under)
        r[1], r[3] = r[1] + d, r[3] + d
        if spec.top then r.top = artTop(rec) end
        F.backs[#F.backs + 1] = r
      else
        F.pT = math.min(F.pT, artTop(rec))
      end
    else
      if not rec.inAnim then a, b = a + d - cur.shift.enemy, b + d - cur.shift.enemy end
      F.eL, F.eR = math.min(F.eL, a), math.max(F.eR, b)
      F.aeL, F.aeR = math.min(F.aeL, a), math.max(F.aeR, b)
      -- its feet: where the cart's pic box ends (a frame's own bottom may be empty margin)
      F.eB = fit.feetY
      local t = artTop(rec)
      if t < F.top then F.top = t end
    end
  end
  local function fitStep(cur)
    local fit = self.fit
    -- (the 3D world's single battles, sized: the camera frames what is out on the field. It
    -- starts at its own zoom, moves when the foe comes out and again when the player's does,
    -- holds while a side's Pokemon is down (fainted, withdrawn, flown) until the next is out,
    -- and goes back to its own zoom for the opposing trainer's last words)
    local live = tuned() and not fit.double
    local outE, outP = false, false
    local reported = emptied(fitReported)
    for _, rec in pairs(cur.prefit) do
      reported[rec.spec.side or ""] = true
      if rec.out ~= false then
        if rec.spec.side == "enemy" then outE = true elseif rec.spec.side == "player" then outP = true end
      end
    end
    -- (a side the engine reports nothing for: out while its Pokemon is drawn)
    for _, item in ipairs(cur.items) do
      if item.kind == "seam" and item.name == "ui" then break end
      local spec = item.kind == "hd" and item.rec.spec
      if spec and spec.side and not spec.trainer and not reported[spec.side] then
        if spec.side == "enemy" then outE = true elseif spec.side == "player" then outP = true end
      end
    end
    if fit.idle > 2 or not fit.wasOut then fit.wasOut = {} end
    local was = fit.wasOut
    local hold = live and ((was.enemy and not outE) or (was.player and not outP)) or false
    local trainerView = live and cur.trainerOut and not outE or false
    local grew = (outE and not was.enemy) or (outP and not was.player)
    if outE then was.enemy = true end
    if outP then was.player = true end
    -- (the foe's HP box over the heads: placed afresh each battle, and when a new Pokemon comes
    -- out or the screen changes; else held)
    local placing = fit.headBox or (fit.double and tuned())
    if not (fit.double and tuned()) then fit.spread, fit.spreadTarget = 1, nil end
    if placing then
      local k = fit.boxKey
      local screen = string.format("%.1f|%.1f|%s", fit.screenTopUI or 0, (fit.viewR or 0) - (fit.viewL or 0),
        tostring(fit.double))
      local fresh = fit.idle > 2 or not k or k.screen ~= screen
      -- (singles: each side's latest; both: each battler the engine reports, kept through a faint)
      if not fresh and not fit.double then
        fresh = not sameOut(k.enemy, self.pair.enemy) or not sameOut(k.player, self.pair.player)
        -- (live: placed again when a Pokemon comes out, never while a side is down: the next
        -- one, reported before its send-out, waits for it)
        if live then fresh = (fresh or grew) and not hold end
      end
      if not fresh then
        for id, rec in pairs(cur.prefit) do
          if not sameOut(k.mons[id], rec.spec) then fresh = true break end
        end
        if live and hold then fresh = false end
      end
      -- (the HUD held - a Pokemon drawn giant for a while: the box stays, the camera pulls
      -- back for the giant under it; its own picture back, nothing new is out)
      if fresh and k and fit.boxBottom and self.hudHeld > 0 and fit.idle <= 2 and k.screen == screen then
        fresh = false
      end
      if fresh then
        fit.boxBottom = nil
        fit.spreadPending = true
        if fit.idle > 2 then fit.spread, fit.spreadTarget = 1, nil end
        fit.boxKey = { enemy = self.pair.enemy, player = self.pair.player, screen = screen,
                       mons = (k and not (fit.idle > 2 or k.screen ~= screen)) and k.mons or {} }
        for id, rec in pairs(cur.prefit) do fit.boxKey.mons[id] = rec.spec end
      end
    else
      fit.boxBottom, fit.boxKey = nil, nil
    end
    -- (the doubles spread eased toward its target)
    if fit.spreadTarget then
      local sp, want = fit.spread or 1, fit.spreadTarget
      if sp ~= want then
        local step = math.max(math.abs(want - sp) * fit.spreadEase, 0.002)
        fit.spread = want > sp and math.min(want, sp + step) or math.max(want, sp - step)
      end
    end
    -- each side's art where it rests (canvas px, unshifted, unzoomed): its frame across, the
    -- enemy's feet (its pic box's bottom), the top of the player's body (else of its art); and
    -- their art alone, the platforms left out (how wide the Pokemon themselves are); and each
    -- battler's own: across, its top, its side (the heads the foe's HP box must clear) - summed
    -- in takeF by takeRec
    local F = takeF
    F.cur, F.top, F.backs, F.seen, F.heads = cur, math.huge, {}, emptied(fitSeen), emptied(fitHeads)
    F.eL, F.eR, F.eB = math.huge, -math.huge, -math.huge
    F.pL, F.pR, F.pT = math.huge, -math.huge, math.huge
    F.aeL, F.aeR, F.apL, F.apR = math.huge, -math.huge, math.huge, -math.huge
    F.aimE, F.aimP = nil, nil
    -- a battler the engine reported (hd.prefit) is fitted where it rests, drawn yet or not:
    -- its send-out jump, a lunge or a shake never moves the camera
    -- (a side reported by any of its battlers is fitted by those alone)
    -- (live: one not out is not framed, its side's drawn art neither: its send-out grows it)
    local preE, preP = false, false
    for _, rec in pairs(cur.prefit) do
      if not (live and rec.out == false) then takeRec(F, rec) end
      if rec.spec.side == "enemy" then preE = true elseif rec.spec.side == "player" then preP = true end
    end
    -- the platforms count as each side's art: the scene never crops them
    if fit.wantW and fit.pads then
      local pe, pp = fit.pads.enemy, fit.pads.player
      F.eL, F.eR = math.min(F.eL, pe[1]), math.max(F.eR, pe[2])
      F.pL, F.pR = math.min(F.pL, pp[1]), math.max(F.pR, pp[2])
    end
    for _, item in ipairs(cur.items) do
      if item.kind == "seam" and item.name == "ui" then break end
      local spec = item.kind == "hd" and item.rec.spec
      if spec and not spec.trainer and not (spec.side == "enemy" and preE or spec.side == "player" and preP) then
        takeRec(F, item.rec)
      end
    end
    local top, backs, seen, heads = F.top, F.backs, F.seen, F.heads
    local eL, eR, eB, pL, pR, pT = F.eL, F.eR, F.eB, F.pL, F.pR, F.pT
    local aeL, aeR, apL, apR = F.aeL, F.aeR, F.apL, F.apR
    local aimE, aimP = F.aimE, F.aimP
    F.cur, F.backs = nil, nil
    if fit.idle > 2 then fit.doubleArt = false end
    if seen.enemy then fit.doubleArt = true end
    -- the 3D world's single battles: a move aimed at the middle of each side's art as drawn
    -- (canvas y, unzoomed), not the middle of the cart's 64 px pic box: a small one stands at
    -- its feet, well under that, and an effect landed over its head (src/gen3.lua shiftCoords)
    local aiming = tuned() and not fit.double
    fit.aimEnemy = (aiming and aimE) or nil
    fit.aimPlayer = (aiming and aimP) or nil
    -- (and how much bigger than the sprite mod draws it each side's Pokemon stands: its effects'
    -- growth, hd's wrapped draw)
    local function grown(spec)
      if not (aiming and fit.fxGrow and spec) then return 1 end
      for i = 1, #worldMons do
        local w = worldMons[i]
        if w.k and w.of.side == spec.side and sameMon(w.of, spec) then
          local own = math.abs(tonumber(spec.scale) or 0)
          if own <= 0 then return 1 end
          return math.max(1, math.min(fit.fxMax or 4, w.k / own))
        end
      end
      return 1
    end
    fit.fxEnemy, fit.fxPlayer = grown(self.pair.enemy), grown(self.pair.player)
    local zt, et = fitSolve(top, backs)
    -- (in the 3D world, where each battler stands at its true size, its art across the screen
    -- too: zoomed out until it lies between the scene's edges, as far as zMin)
    local world = self.worldScene ~= nil
    -- (the 3D world's sizing on: 3D Sizing)
    local sized = tuned()
    if world then
      local fx = fit.focus[1]
      local vl, vr = (fit.viewL or 0) + fit.margin, (fit.viewR or 240) - fit.margin
      local function across(L, R)
        if not (L < R) then return 1 end
        local z = 1
        if R > vr and R > fx then z = math.min(z, (vr - fx) / (R - fx)) end
        if L < vl and L < fx then z = math.min(z, (fx - vl) / (fx - L)) end
        return z
      end
      -- (singles: a side's outer edge, the player's left, the foe's right, is left to the wide
      -- step outward, which keeps most of it on the screen: the camera pulled back for a wide
      -- one's whole width only to have it stepped half off again)
      if sized and not fit.double and tonumber(fit.wideLine) then
        zt = math.max(fit.zMin, math.min(zt, across(eL, math.min(eR, fx)), across(math.max(pL, fx), pR)))
      else
        zt = math.max(fit.zMin, math.min(zt, across(eL, eR), across(pL, pR)))
      end
      -- (a giant: a little further back)
      if sized and zt < 1 - 1e-6 and fit.bigPull then zt = math.max(fit.zMin, zt * fit.bigPull) end
      -- (the foe's HP box: every head under its columns, where the side shift puts it, under the
      -- box, held where it is, else under the room it needs below the screen's top; a head
      -- beside the box, a foe's on the right, needs no room)
      local fy = fit.focus[2]
      local box, limitY
      if fit.headBox and #heads > 0 then
        local e = fit.ui.enemy
        local line = fit.boxBottom or ((fit.screenTopUI or 0) + fit.headMargin + (e[4] - e[2]))
        limitY = uiY(line + fit.headGap)
        box = uiRect(e)
      end
      -- (at zoom z: every head under the box's columns under it; with `whole` (coming in), also
      -- every art top on the screen, every art wholly inside its sides, and zoomInShow of each
      -- of the player's above the text box)
      local top0 = topLimit()
      local textLine = uiY(fit.ui.text[2])
      local show = fit.zoomInShow or 0
      local vl, vr = (fit.viewL or 0) + fit.margin, (fit.viewR or 240) - fit.margin
      local function clear(z, whole, raise)
        local lift = fitLift(z) + et + (raise or 0)
        local v = playerDrop(z, lift)
        for _, h in ipairs(heads) do
          local sh = fit.shift[h[4]] or 0
          local l, r = fx + (h[1] + sh - fx) * z, fx + (h[2] + sh - fx) * z
          local t = fy + (h[3] + (h[4] == "player" and v or 0) - fy) * z - lift
          if box and r > box[1] and l < box[3] and t < limitY - 1e-6 then return false end
          if whole then
            if t < top0 - 1e-6 or r > vr + 1e-6 or l < vl - 1e-6 then return false end
            if h[4] == "player" and h[5] then
              local f = fy + (h[5] + v - fy) * z - lift
              if f > t and textLine - t < show * (f - t) - 1e-6 then return false end
            end
          end
        end
        return true
      end
      if box then
        local z = zt
        while z > fit.zMin + 1e-9 and not clear(z) do z = z - fit.zStep end
        zt = math.max(fit.zMin, z)
      end
      -- (every battler small, or the foe: in, toward the tallest standing smallFill of the
      -- battle's height or the foe smallFoe of it, the camera rising as it comes in so the
      -- player's feet stay on the row they stand on at zoom 1: a back grows upward instead of
      -- sinking under the text box)
      -- (live: only with both sides out; the foe alone only pulls the camera out)
      if sized and zt >= 1 - 1e-9 and (fit.zMax or 1) > 1 and #heads > 0 and not (fit.double and fit.doublesOwnSize)
          and not (live and not (outE and outP)) then
        -- (each measured at its size before the floors raised it (worldSize's e.lift): else a
        -- small foe raised 15% has the camera come in 13% less, the same on the screen)
        local function lift(side)
          local spec = type(self.pair) == "table" and self.pair[side]
          if not spec then return 1 end
          for i = 1, #worldMons do
            local w = worldMons[i]
            if w.k and w.of.side == spec.side and sameMon(w.of, spec) then return w.lift or 1 end
          end
          return 1
        end
        local liftE, liftP = lift("enemy"), lift("player")
        local tall, foeTall, low = 0, 0, nil
        for _, h in ipairs(heads) do
          if h[5] and h[5] > h[3] then
            local ht = (h[5] - h[3]) / ((h[4] == "enemy" and liftE or liftP) or 1)
            tall = math.max(tall, ht)
            if h[4] == "enemy" then foeTall = math.max(foeTall, ht) end
          end
          if h[4] == "player" and h[5] then low = math.max(low or -math.huge, h[5]) end
        end
        local room = textLine - top0
        if tall > 0 and room > 0 then
          local hi = math.min(fit.zMax, (fit.smallFill or 0.3) * room / tall)
          -- (a small foe: in toward its art standing smallFoe of the height, up to zFoeMax)
          if foeTall > 0 and fit.smallFoe and fit.zFoeMax then
            hi = math.max(hi, math.min(fit.zFoeMax, fit.zMax, fit.smallFoe * room / foeTall))
          end
          local function rise(z) return low and math.max(0, (low - fy) * (z - 1)) or 0 end
          local z = hi
          while z > 1 + 1e-9 and not clear(z, true, rise(z)) do z = z - 0.01 end
          if z > 1 + 1e-9 then
            zt = z
            et = math.min(fit.extraMax or math.huge, et + rise(z))
          end
        end
      end
      self.stats.zoomIn = zt > 1 and zt or nil
      -- (the 3D world's double battles at the sprite mod's own sizes: the camera where it
      -- stands, pulled back only as far as shows every Pokemon's art whole, its top under the
      -- screen's and its sides inside the screen's; never in)
      if sized and fit.double and fit.doublesOwnSize then
        local function whole(z)
          local lift = fitLift(z)
          local v = playerDrop(z, lift)
          for _, h in ipairs(heads) do
            local sh = fit.shift[h[4]] or 0
            local l, r = fx + (h[1] + sh - fx) * z, fx + (h[2] + sh - fx) * z
            local t = fy + (h[3] + (h[4] == "player" and v or 0) - fy) * z - lift
            if t < top0 - 1e-6 or r > vr + 1e-6 or l < vl - 1e-6 then return false end
          end
          return true
        end
        local z = 1
        while z > fit.zMin + 1e-9 and not whole(z) do z = z - fit.zStep end
        zt, et = math.max(fit.zMin, z), 0
      end
    end
    -- (the doubles spread, just placed afresh: the outer two's feet spreadEdge inside the
    -- screen, unzoomed)
    if fit.spreadPending then
      fit.spreadPending = nil
      local spots = fit.doubleSpots
      if fit.double and sized and type(spots) == "table" and #spots > 1 then
        local fx = fit.focus[1]
        local lo, hi = math.huge, -math.huge
        for i = 1, #spots do lo, hi = math.min(lo, spots[i]), math.max(hi, spots[i]) end
        local vl, vr = fit.viewL or 0, fit.viewR or 240
        -- (at zoom 1: the room the screen itself has; taken at the camera's zoom, the sizes it
        -- allowed pulled the camera further back, which allowed a wider spread, and an upright
        -- screen's battle ended at the furthest zoom)
        local edge, z = fit.spreadEdge or 0, 1
        local want = fit.spreadMax or 1
        if lo < fx then want = math.min(want, (fx - (vl + edge)) / ((fx - lo) * z)) end
        if hi > fx then want = math.min(want, ((vr - edge) - fx) / ((hi - fx) * z)) end
        fit.spreadTarget = fit.doublesOwnSize and 1 or math.max(1, want)
        if fit.idle > 2 then fit.spread = fit.spreadTarget end
      end
    end
    -- (the foe's HP box, just placed afresh: over the highest head where the camera is heading,
    -- UI px, then held)
    if fit.headBox and not fit.boxBottom and (top < math.huge or pT < math.huge) then
      local fy = fit.focus[2]
      local lift = fitLift(zt) + et
      local hi = math.huge
      if top < math.huge then hi = fy + (top - fy) * zt - lift end
      local v = playerDrop(zt, lift)
      for _, r in ipairs(backs) do hi = math.min(hi, fy + ((r.top or r[2]) + v - fy) * zt - lift) end
      if pT < math.huge then hi = math.min(hi, fy + (pT + v - fy) * zt - lift) end
      local e = fit.ui.enemy
      local yu = fy + (hi - fy) / (fit.uiK or 1) - (fit.sceneUp or 0)
      local b = yu - fit.headGap
      b = math.min(b, fit.ui.player[2] - fit.headGap)
      b = math.max(b, (fit.screenTopUI or 0) + fit.headMargin + (e[4] - e[2]))
      fit.boxBottom = round2(b)
      self.stats.boxBottom = fit.boxBottom
    end
    -- (live: the opposing trainer shown with no foe out at the camera's own zoom; a side down,
    -- the camera held where it was)
    if trainerView then
      zt, et = 1, 0
    elseif hold and fit.target then
      zt, et = fit.target, fit.extraTarget or et
    end
    fit.target, fit.extraTarget = zt, et
    if self.giantNew then self.giantNew = self.giantNew - 1 if self.giantNew <= 0 then self.giantNew = nil end end
    if fit.idle > 2 then
      -- a new battle: start where it should be (live: at the camera's own zoom, moving as the
      -- Pokemon come out), unshifted until its intro is over
      if live then fit.z, fit.extra = 1, 0 else fit.z, fit.extra = zt, et end
      fit.hold = 0
      fit.shift.enemy, fit.shift.player = 0, 0
    elseif self.giantNew and (zt < fit.z or et > fit.extra) then
      -- (a giant first reported already grown - Galar Rising's foe, grown under its full-screen
      -- scene: the camera is where it must be from its first frame, else its head ran off the
      -- screen's top while the camera eased out)
      fit.z, fit.extra = math.min(fit.z, zt), math.max(fit.extra, et)
      fit.hold = 0
    else
      local outward = zt < fit.z or et > fit.extra
      local inward = zt > fit.z or et < fit.extra
      -- (a turn playing: never settled, so never back in; held from the menu on. Live, framed
      -- at rest and only as the Pokemon come and go, it follows a send-out mid-turn)
      if outward or (fit.turn and not live) then fit.hold = 0 elseif inward then fit.hold = fit.hold + 1 else fit.hold = 0 end
      local settle = fit.hold >= fit.holdFrames or trainerView
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
    -- (in the 3D world each side stands on its ground: the zoom and the rise alone, which move
    -- the world with it, make room)
    if fit.z < 1 and not world then
      local k = (1 - fit.z) / fit.z
      if seen.enemy then wantE = math.min(fit.shiftMax, (fit.enemyX - fx) * k) end
      if seen.player then wantP = -math.min(fit.shiftMax, (fx - fit.playerX) * k) end
    end
    fit.shift.playerY = (fit.z < 1 and seen.player and not world)
      and playerDrop(fit.z, fitLift(fit.z) + fit.extra) or 0
    fit.shift.playerRaise = 0
    -- stacked, the width short of what growing to the top needs: the sides slide inward, as far
    -- as they may without the Pokemon overlapping (canvas px before the zoom, split evenly);
    -- both Pokemon must be tagged, or one would be left behind its pad
    local inward = 0
    if fit.wantW and eL < eR and pL < pR and seen.enemy and seen.player and not world then
      local z = fit.z
      local L, R = math.min(eL + wantE, pL + wantP), math.max(eR + wantE, pR + wantP)
      local need = ((R - L) * z - fit.wantW) / z
      if need > 0 then
        local most
        if pT + fit.shift.playerY >= eB then
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
    -- (the 3D world, singles: a wide Pokemon stepped out toward its own edge, partly off the
    -- screen, so it never reaches past wideLine: the player's art's right edge, the foe's left,
    -- as the zoom now shows them; canvas px before the zoom, as every side shift), never so far
    -- that less than wideKeep of its art's width stays on the screen
    local line = tonumber(fit.wideLine)
    if sized and not fit.double and line then
      local vl0, vr0 = fit.viewL or 0, fit.viewR or 240
      local W, z = vr0 - vl0, math.max(fit.z, 1e-3)
      local keep = math.max(0, math.min(1, tonumber(fit.wideKeep) or 1))
      if seen.player and apL < apR then
        local over = fx + (apR - fx) * z - (vl0 + line * W)
        -- (its art's point keep of its width in from its right edge on the screen's left edge)
        local most = fx + (apR - keep * (apR - apL) - fx) * z - vl0
        local s = math.min(over, most)
        if s > 0 then fit.shift.player = round2(-s / z) end
      end
      if seen.enemy and aeL < aeR then
        local over = (vr0 - line * W) - (fx + (aeL - fx) * z)
        local most = vr0 - (fx + (aeL + keep * (aeR - aeL) - fx) * z)
        local s = math.min(over, most)
        if s > 0 then fit.shift.enemy = round2(s / z) end
      end
    end
    self.stats.inward = inward
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
      local e, o, y0 = hidden({ r[1], r[2] + v, r[3], r[4] + v }, fit.z, lift)
      he, ho, bt = math.max(he, e), math.max(ho, o), math.min(bt, y0)
    end
    self.stats.hiddenEnemyUI, self.stats.hiddenOwnUI = he, ho
    self.stats.backTop = bt < math.huge and bt or nil
    return fit.z
  end

  -- a rect {x, y, w, h} clipped to another
  -- (out: a kept rect filled instead of a new one)
  local function clipRect(x, y, w, h, v, out)
    local x0, y0 = math.max(x, v[1]), math.max(y, v[2])
    local x1, y1 = math.min(x + w, v[1] + v[3]), math.min(y + h, v[2] + v[4])
    out = out or {}
    out[1], out[2], out[3], out[4] = x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0)
    return out
  end
  -- the composite's rects, kept between frames (read only while it runs: noteUi copies what it
  -- keeps), and its helpers as plain functions, not closures made each frame
  local compScene, compUi, compCanvas, compTop, compLow, compTopAll = {}, {}, {}, {}, {}, {}
  local function scissorBox(b)
    if b then scissorOver(b[1], b[2], b[3], b[4]) else real.setScissor() end
  end

  -- the UI at a scale that is not a whole number, kept sharp and even: drawn pixel for pixel
  -- at the next whole scale k into a canvas of its own, which is then scaled down smoothly
  -- (every UI pixel the same width, its edges at most one screen pixel soft)
  local sharp, sharpW, sharpH = nil, 0, 0
  -- what hd.paint's functions are told (one table, refilled for each); a clip box refilled for
  -- each blit that needs one of its own
  local paintCtx, cutScratch = {}, {}
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

  -- the last rows and columns of a card (the pass's picture, flat), for the screen beyond it;
  -- cardShown: that picture as the blit shows it (Red's SGB palettes colour the canvas's shades
  -- as it is blitted, zone by zone), which the backdrop is drawn from as it is
  local cardFlat, cardFlatW, cardFlatH = nil, 0, 0
  local cardShown
  local function flattenCard(cur, blit)
    if not cardFlat or cardFlatW ~= cur.w or cardFlatH ~= cur.h then
      if cardFlat and cardFlat.release then pcall(cardFlat.release, cardFlat) end
      if cardShown and cardShown.release then pcall(cardShown.release, cardShown) end
      cardFlat = real.newCanvas(cur.w, cur.h, { dpiscale = 1 })
      cardShown = real.newCanvas(cur.w, cur.h, { dpiscale = 1 })
      for _, c in ipairs({ cardFlat, cardShown }) do
        if c.setFilter then c:setFilter("nearest", "nearest") end
      end
      cardFlatW, cardFlatH = cur.w, cur.h
    end
    real.push("all")
    real.setCanvas(cardFlat)
    real.origin()
    real.setScissor()
    real.setShader()
    real.clear(0, 0, 0, 0)
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("alpha", "premultiplied")
    local inScene, hidden = true, cur.uiCovers
    if not hidden then real.draw(cur.base, 0, 0) end
    for _, item in ipairs(cur.items) do
      if item.kind == "seam" then
        if item.name == "ui" then inScene = false end
      elseif item.canvas and not (inScene and hidden) then
        real.draw(item.canvas, 0, 0)
      end
    end
    -- through the blit, one canvas pixel to a pixel
    real.setCanvas(cardShown)
    real.clear(0, 0, 0, 0)
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("alpha", "premultiplied")
    blit(cardFlat, 0, 0, 1, 1, { 0, 0, cur.w, cur.h })
    real.pop()
    return cardShown
  end

  -- a canvas drawn as it is (the backdrop, already as the blit shows it), clipped to a box
  local function drawPlain(c, x, y, sx, sy, box)
    scissorOver(box[1], box[2], box[3], box[4])
    real.draw(c, x, y, 0, sx, sy)
    real.setScissor()
  end

  -- a card's blurred backdrop: the flat picture averaged down to a quarter (each halving with
  -- linear filtering is an exact 2x2 average), then a Gaussian across and down, twice
  local BLUR_SRC = [[
extern vec2 dir;
vec4 effect(vec4 c, Image t, vec2 tc, vec2 sc) {
  vec4 s = Texel(t, tc) * 0.2270270270;
  s += (Texel(t, tc + dir * 1.3846153846) + Texel(t, tc - dir * 1.3846153846)) * 0.3162162162;
  s += (Texel(t, tc + dir * 3.2307692308) + Texel(t, tc - dir * 3.2307692308)) * 0.0702702703;
  return s * c;
}]]
  -- the backdrop again over the picture's rim, fading out inward: rect, the picture in the
  -- backdrop's texture coordinates (an edge with no gap beside it is moved out of reach);
  -- feather, how far in the fade reaches
  local FEATHER_SRC = [[
extern vec4 rect;
extern vec2 feather;
vec4 effect(vec4 c, Image t, vec2 tc, vec2 sc) {
  float ax = min(tc.x - rect.x, rect.z - tc.x) / feather.x;
  float ay = min(tc.y - rect.y, rect.w - tc.y) / feather.y;
  float a = 1.0 - smoothstep(0.0, 1.0, clamp(min(ax, ay), 0.0, 1.0));
  return Texel(t, tc) * c * a;
}]]
  local featherShader    -- nil: not made yet; false: this device cannot make it
  local featherRect, featherSize = { 0, 0, 1, 1 }, { 1, 1 }
  local blurShader       -- nil: not made yet; false: this device cannot make it
  local blurHalf, blurA, blurB, blurW, blurH = nil, nil, nil, 0, 0
  local blurDir = { 0, 0 }
  local function blurInto(dst, src, sx, sy)
    real.setCanvas(dst)
    real.clear(0, 0, 0, 0)
    real.draw(src, 0, 0, 0, sx, sy)
  end
  local function blurCard(flat, w, h)
    if blurShader == nil then
      local ok, sh = pcall(G.newShader, BLUR_SRC)
      blurShader = ok and sh or false
    end
    if not blurShader then return nil end
    local w4, h4 = math.ceil(w / 4), math.ceil(h / 4)
    if not blurA or blurW ~= w4 or blurH ~= h4 then
      blurHalf = real.newCanvas(math.ceil(w / 2), math.ceil(h / 2), { dpiscale = 1 })
      blurA = real.newCanvas(w4, h4, { dpiscale = 1 })
      blurB = real.newCanvas(w4, h4, { dpiscale = 1 })
      for _, c in ipairs({ blurHalf, blurA, blurB }) do
        if c.setFilter then c:setFilter("linear", "linear") end
      end
      blurW, blurH = w4, h4
    end
    local send = shaderReal.send or blurShader.send
    real.push("all")
    real.origin()
    real.setScissor()
    real.setShader()
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("replace", "premultiplied")
    if flat.setFilter then flat:setFilter("linear", "linear") end
    blurInto(blurHalf, flat, 0.5, 0.5)
    if flat.setFilter then flat:setFilter("nearest", "nearest") end
    blurInto(blurA, blurHalf, 0.5, 0.5)
    real.setShader(blurShader)
    for _ = 1, 2 do
      blurDir[1], blurDir[2] = 1 / w4, 0
      send(blurShader, "dir", blurDir)
      blurInto(blurB, blurA, 1, 1)
      blurDir[1], blurDir[2] = 0, 1 / h4
      send(blurShader, "dir", blurDir)
      blurInto(blurA, blurB, 1, 1)
    end
    real.pop()
    return blurA
  end

  -- A layer of a move's effect anchored to the canvas's sides ("edge"), drawn with the scene's
  -- mapping (canvas pixel (0, 0) at x0, y0; sx, sy screen pixels a canvas pixel) over the whole
  -- box: through a quad reaching past the canvas, sampled clamped, so its first and last columns
  -- (and its top row, where it reaches the top) run on out to the box's edges. False when it
  -- cannot be drawn so (it is then blitted as any layer).
  local edgeQuad
  local function drawEdge(c, x0, y0, sx, sy, box)
    if not (real.newQuad and c.setWrap and c.getWidth and box) then return false end
    local cw, ch = c:getWidth(), c:getHeight()
    local u0, v0 = (box[1] - x0) / sx, (box[2] - y0) / sy
    local uw, vh = box[3] / sx, box[4] / sy
    if edgeQuad then
      edgeQuad:setViewport(u0, v0, uw, vh, cw, ch)
    else
      edgeQuad = real.newQuad(u0, v0, uw, vh, cw, ch)
    end
    c:setWrap("clamp", "clamp")
    scissorOver(box[1], box[2], box[3], box[4])
    real.draw(c, edgeQuad, box[1], box[2], 0, sx, sy)
    real.setScissor()
    return true
  end

  -- A layer of a move's effect whose draws all end on the text box's line (markBottom: toLine),
  -- mapped with canvas pixel (0, 0) at x0, y0 (sx, sy screen pixels a canvas pixel): its last
  -- row above the line, run on from the line down to the box's bottom across the box's width
  -- (the cart's text box hid those rows; beside a filled screen's narrower one they show)
  local runQuad
  local function runDown(c, x0, y0, sx, sy, line, box)
    if not (real.newQuad and c.setWrap and c.getWidth and box) then return end
    local top, bottom = y0 + line * sy, box[2] + box[4]
    if top >= bottom then return end
    local cw, ch = c:getWidth(), c:getHeight()
    local u0, uw = (box[1] - x0) / sx, box[3] / sx
    if runQuad then
      runQuad:setViewport(u0, line - 1, uw, 1, cw, ch)
    else
      runQuad = real.newQuad(u0, line - 1, uw, 1, cw, ch)
    end
    c:setWrap("clamp", "clamp")
    scissorOver(box[1], box[2], box[3], box[4])
    real.draw(c, runQuad, box[1], top, 0, sx, bottom - top)
    real.setScissor()
  end

  -- A move's background band ("wide", wideBackground) drawn with the scene's mapping (canvas
  -- pixel (0, 0) at x0, y0; sx, sy screen pixels a canvas pixel) across the whole box: its tiled
  -- image continues sideways, and a band reaching the text box's line on down to the box's
  -- bottom (Surf's water stops at the line, where the cart's text box spans the screen: beside a
  -- filled screen's narrower one, the water runs on under it). With its own colour, blend and
  -- shader as drawn.
  local wideQuad
  -- A row of pieces (rowTile) carried on past the canvas: an end piece that carries it (carryLo,
  -- carryHi) repeated, each its width along, out to the view's (box) sides; a piece reaching the
  -- text box's line (the cart's text box hid the rows below it) carried on down from its foot
  -- (its last row of texels) to the view's. With the scene's mapping (canvas point (cx, cy) at
  -- x0 + cx * sx, y0 + cy * sy). The row's own pieces are drawn in their layer, or uncut where
  -- they cross its edges (freeDraw): here only their run-on
  local rowQuad
  local function rowPiece(piece, px, x0, y0, sx, sy, w, line, bottom, body)
    local img = piece.image
    local iw, ih = img:getWidth(), img:getHeight()
    if rowQuad then
      rowQuad:setViewport(piece.qx, piece.qy, piece.qw, piece.qh, iw, ih)
    else
      rowQuad = real.newQuad(piece.qx, piece.qy, piece.qw, piece.qh, iw, ih)
    end
    local kx, ky = sx * w / piece.qw, sy * piece.h / piece.qh
    local x, foot = x0 + px * sx, y0 + (piece.y0 + piece.h) * sy
    if body then real.draw(img, rowQuad, x, y0 + piece.y0 * sy, 0, kx, ky) end
    if piece.y0 + piece.h >= line - 0.5 and foot < bottom then
      rowQuad:setViewport(piece.qx, piece.qy + piece.qh - 1, piece.qw, 1, iw, ih)
      real.draw(img, rowQuad, x, foot, 0, kx, bottom - foot)
    end
  end
  local function drawRow(item, x0, y0, sx, sy, box)
    local rec = item.rec
    local w = item.w
    if not (w > 0 and sx > 0 and sy > 0) then return end
    local bl, bt, br, bb = box[1], box[2], box[1] + box[3], box[2] + box[4]
    local cl, cr, cb = x0, x0 + item.cw * sx, y0 + item.ch * sy
    local pieces = item.pieces
    local first, final = pieces[1], pieces[#pieces]
    local k0 = math.floor(((bl - x0) / sx - item.lo) / w)
    local k1 = math.ceil(((br - x0) / sx - item.hi) / w)
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    -- the view left of the canvas, right of it, under it, and the canvas itself (there only the
    -- pieces' run-on, below their feet)
    for region = 1, 4 do
      local rx0, ry0, rx1, ry1 = bl, bt, cl, bb
      if region == 2 then rx0, rx1 = cr, br
      elseif region == 3 then rx0, ry0, rx1 = math.max(bl, cl), math.max(bt, cb), math.min(br, cr)
      elseif region == 4 then rx0, ry0, rx1, ry1 = math.max(bl, cl), bt, math.min(br, cr), math.min(bb, cb) end
      rx0, rx1 = math.max(rx0, bl), math.min(rx1, br)
      if rx1 - rx0 >= 1 and ry1 - ry0 >= 1 then
        scissorOver(rx0, ry0, rx1 - rx0, ry1 - ry0)
        for k = item.carryLo and math.min(k0, 0) or 0, -1 do
          rowPiece(first, item.lo + k * w, x0, y0, sx, sy, w, item.line, bb, true)
        end
        for i = 1, #pieces do
          rowPiece(pieces[i], item.lo + (i - 1) * w, x0, y0, sx, sy, w, item.line, bb, false)
        end
        for k = 1, item.carryHi and math.max(k1, 0) or 0 do
          rowPiece(final, item.hi + k * w, x0, y0, sx, sy, w, item.line, bb, true)
        end
      end
    end
    real.setScissor()
    real.setShader()
  end

  -- A move's effect that crossed the canvas's edges (freeDraw), replayed as drawn at the scene's
  -- mapping (canvas point (cx, cy) at x0 + cx * sx, y0 + cy * sy), uncut but for the view (box)
  local freeQuad
  local function drawFree(item, x0, y0, sx, sy, box)
    local rec = item.rec
    local img = rec.image
    real.push()
    real.origin()
    real.translate(x0 + rec.tx * sx, y0 + rec.ty * sy)
    real.scale(sx * rec.tsx, sy * rec.tsy)
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    scissorOver(box[1], box[2], box[3], box[4])
    if item.qx then
      local iw, ih = img:getWidth(), img:getHeight()
      if freeQuad then
        freeQuad:setViewport(item.qx, item.qy, item.qw, item.qh, iw, ih)
      else
        freeQuad = real.newQuad(item.qx, item.qy, item.qw, item.qh, iw, ih)
      end
      real.draw(img, freeQuad, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
    else
      real.draw(img, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
    end
    real.pop()
    real.setScissor()
    real.setShader()
  end

  local function drawWide(item, x0, y0, sx, sy, box)
    local rec = item.rec
    local img = rec.image
    local iw, ih = img:getWidth(), img:getHeight()
    -- canvas pixels a texel across and down, and the canvas point of the band's first texel
    local kx, ky = rec.tsx * rec.sx, rec.tsy * rec.sy
    local px = rec.tx + rec.tsx * (rec.x - rec.ox * rec.sx)
    local py = rec.ty + rec.tsy * (rec.y - rec.oy * rec.sy)
    local u0 = item.qx + ((box[1] - x0) / sx - px) / kx
    local uw = box[3] / (sx * kx)
    local top = y0 + py * sy
    local v0, vh = item.qy, item.qh
    local bottom = top + vh * ky * sy
    if item.bottom and bottom < box[2] + box[4] then vh = vh + (box[2] + box[4] - bottom) / (sy * ky) end
    if wideQuad then
      wideQuad:setViewport(u0, v0, uw, vh, iw, ih)
    else
      wideQuad = real.newQuad(u0, v0, uw, vh, iw, ih)
    end
    real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
    useShader(rec)
    real.setBlendMode(rec.blend[1], rec.blend[2])
    scissorOver(box[1], box[2], box[3], box[4])
    real.draw(img, wideQuad, box[1], top, 0, sx * kx, sy * ky)
    real.setScissor()
    real.setShader()
  end

  --- A screen of the game's own in a battle (fit.fill): the Pokedex page and the caught scene of
  --- a new catch, the summary, the nickname screen, evolution, the party, the bag. It is a whole
  --- 240x160 picture, so it is scaled as far as it fits (sharply, as the stacked UI is) and the
  --- rest of the screen continues its edges: each row's first and last pixel out to the sides,
  --- the top and bottom rows up and down. Nothing is cropped or stretched, and no frame shows.
  local function copyRect(dst, src)
    dst[1], dst[2], dst[3], dst[4] = src[1], src[2], src[3], src[4]
  end
  -- self.uiMap, for this pass
  local function noteUi(cur, x, y, sx, sy, box, split, topY, topBox, lowBox)
    local map = self.uiMap
    map.cur, map.serial, map.x, map.y, map.sx, map.sy = cur, cur.serial, x, y, sx, sy
    copyRect(map.box, box)
    map.banded = topBox ~= nil
    if topBox then
      map.split, map.topY = split, topY
      copyRect(map.topBox, topBox)
      copyRect(map.lowBox, lowBox)
    end
  end

  -- a card's state for its rim and bar (compositeCard's, set each call; read by cardRim / cardBar)
  local cardState = {}
  -- the picture's rim fades into the backdrop: the backdrop again, opaque at an edge with a gap
  -- beside it and gone cardFeather game pixels in (once a card: before a bar, which runs on past
  -- the picture's sides unfaded, else after everything)
  local function cardRim()
    local cs = cardState
    if cs.done then return end
    cs.done = true
    local F, soft = self.fit.cardFeather, cs.soft
    if not (soft and F > 0) then return end
    if featherShader == nil then
      local ok, sh = pcall(G.newShader, FEATHER_SRC)
      featherShader = ok and sh or false
    end
    if not featherShader then return end
    local send = shaderReal.send or featherShader.send
    local sdx, sdy, sdw, sdh = cs.sdx, cs.sdy, cs.sdw, cs.sdh
    featherRect[1] = cs.ubx > cs.vx and (cs.ubx - sdx) / sdw or -1
    featherRect[2] = cs.uby > cs.vy and (cs.uby - sdy) / sdh or -1
    featherRect[3] = cs.x1 < cs.vr and (cs.x1 - sdx) / sdw or 2
    featherRect[4] = cs.y1 < cs.vb and (cs.y1 - sdy) / sdh or 2
    featherSize[1], featherSize[2] = F * cs.U / sdw, F * cs.Uy / sdh
    send(featherShader, "rect", featherRect)
    send(featherShader, "feather", featherSize)
    real.setScissor()
    real.setShader(featherShader)
    real.setBlendMode("alpha", "premultiplied")
    local d = self.fit.cardDim
    real.setColor(d, d, d, 1)
    drawPlain(soft, sdx, sdy, sdw / soft:getWidth(), sdh / soft:getHeight(), cs.box)
    real.setShader()
  end
  -- the bar (hd.paint) across the screen at the picture's rows - the picture's last row above it
  -- run on down to it across the screen (the cart's text box began rows higher) - and what is
  -- drawn into it (hd.bar) moved down into it: its left part to the screen's left edge, the rest
  -- after its split to the right one, as a battle's
  local function cardBar(item)
    local cs = cardState
    cardRim()
    real.setShader()
    local ubx, uby, U, Uy = cs.ubx, cs.uby, cs.U, cs.Uy
    local vx, vy, vw, vh, vr, vb = cs.vx, cs.vy, cs.vw, cs.vh, cs.vr, cs.vb
    if item.kind == "paint" then
      if item.hide and item.runTo and item.runTo > item.hide then
        local src = cs.flat or flattenCard(cs.cur, cs.blit)
        cs.flat = src
        if src then
          real.setColor(1, 1, 1, 1)
          real.setBlendMode("alpha", "premultiplied")
          local o = cutScratch
          o[1], o[2], o[3], o[4] = vx, uby + item.hide * Uy, vw, (item.runTo - item.hide) * Uy
          runDown(src, ubx, uby, U, Uy, item.hide, o)
        end
      end
      real.setColor(1, 1, 1, 1)
      real.setBlendMode("alpha", "alphamultiply")
      scissorOver(vx, vy, vw, vh)
      local c = paintCtx
      c.x, c.y, c.sx, c.sy = ubx, uby, U, Uy
      c.l, c.r, c.extraL, c.extraR = vx, vr, cs.extraL, cs.extraR
      local ok, err = pcall(item.fn, item.a, c)
      if not ok then self.stats.paintError = tostring(err) end
    else
      real.setScissor()
      real.setColor(1, 1, 1, 1)
      real.setBlendMode("alpha", "premultiplied")
      local b, cur = item.bar, cs.cur
      local c, kk = item.canvas, 1
      if cs.k > 1 then c, kk = sharpen(item.canvas, cur.w, cur.h, cs.k) end
      local y0 = math.max(uby + b.top * Uy, vy)
      local yb = math.min(uby + b.bottom * Uy, vb)
      local oy = uby + b.dy * Uy
      if yb > y0 then
        local extraL, extraR = cs.extraL, cs.extraR
        local cut = b.split and (ubx - extraL + b.split * U) or vr
        local o = cutScratch
        o[1], o[2], o[3], o[4] = vx, y0, cut - vx, yb - y0
        cs.blit(c, ubx - extraL, oy, U / kk, Uy / kk, o, kk)
        if b.split then
          local d = ubx + b.split * U + extraR
          o[1], o[2], o[3], o[4] = d, y0, vr - d, yb - y0
          cs.blit(c, ubx + extraR, oy, U / kk, Uy / kk, o, kk)
        end
      end
    end
    real.setScissor()
    real.setBlendMode("alpha", "alphamultiply")
  end
  local function compositeCard(cur, blit, bsx, bsy, view)
    -- the camera keeps its place behind the screen
    if cur.hasUI then fitStep(cur) end
    local vx, vy, vw, vh = view[1], view[2], view[3], view[4]
    local top = math.max(vy, view.top or vy)
    local bottom = math.min(vy + vh, view.bottom or (vy + vh))
    local docked = view.bottom ~= nil
    if bottom - top < cur.h * bsy then top, bottom, docked = vy, vy + vh, false end
    local U = round2(math.min(vw / cur.w, (bottom - top) * bsx / (cur.h * bsy)))
    local Uy = round2(U * bsy / bsx)
    local ubx = round2(vx + (vw - cur.w * U) / 2)
    local uby = round2(docked and (bottom - cur.h * Uy) or (top + ((bottom - top) - cur.h * Uy) / 2))
    local x1, y1 = ubx + cur.w * U, uby + cur.h * Uy
    local vr, vb = vx + vw, vy + vh
    local screen = { vx, vy, vw, vh }
    -- the picture's clip, out to whole pixels (a clip's fractions are cut off)
    local bx0, by0 = math.floor(ubx), math.floor(uby)
    local box = clipRect(bx0, by0, math.ceil(x1) - bx0, math.ceil(y1) - by0, screen)
    local k = U ~= math.floor(U) and math.ceil(U) or 1
    self.stats.fill, self.stats.uiScale, self.stats.uiTopDy = U / bsx, U, 0
    self.stats.card = (self.stats.card or 0) + 1
    -- where the picture went (the game's own redraws over it are placed by it)
    noteUi(cur, ubx, uby, U, Uy, box)
    local function picture(c)
      local src, kk = c, 1
      if k > 1 then src, kk = sharpen(c, cur.w, cur.h, k) end
      blit(src, ubx, uby, U / kk, Uy / kk, box, kk)
    end
    real.push("all")
    real.setScissor()
    real.setShader()
    real.setColor(1, 1, 1, 1)
    real.setBlendMode("alpha", "premultiplied")
    -- beyond the picture: a canvas pixel as wide (or tall) as the gap, clipped to the gap. A
    -- clip is cut to whole pixels, so each gap's clip reaches over the picture's edge pixel
    -- (ceil / floor): a screen pixel the picture covers less than half of is the gap's, and the
    -- picture, drawn after, covers the rest
    local soft, sdx, sdy, sdw, sdh, flat
    if ubx > vx or x1 < vr or uby > vy or y1 < vb then
      flat = flattenCard(cur, blit)
      -- the picture blurred, dimmed and grown to cover the whole screen behind it
      soft = self.fit.cardBlur and blurCard(flat, cur.w, cur.h)
      if soft then
        local S = math.max(vw / cur.w, vh * bsx / (cur.h * bsy))
        sdw, sdh = cur.w * S, cur.h * S * bsy / bsx
        sdx, sdy = vx + (vw - sdw) / 2, vy + (vh - sdh) / 2
        local d = self.fit.cardDim
        real.setColor(d, d, d, 1)
        drawPlain(soft, sdx, sdy, sdw / soft:getWidth(), sdh / soft:getHeight(), screen)
        real.setColor(1, 1, 1, 1)
      end
    end
    if not soft and (ubx > vx or x1 < vr or uby > vy or y1 < vb) then
      local flat = cardShown
      local blit = drawPlain
      local floor, ceil = math.floor, math.ceil
      local ry0, ry1 = floor(uby), ceil(y1)
      if ubx > vx then
        local w = ubx - vx
        blit(flat, ubx - w, uby, w, Uy, { vx, ry0, ceil(ubx) - vx, ry1 - ry0 })
      end
      if x1 < vr then
        local w = vr - x1
        blit(flat, x1 - (cur.w - 1) * w, uby, w, Uy, { floor(x1), ry0, vr - floor(x1), ry1 - ry0 })
      end
      local sw = vw / cur.w
      if uby > vy then
        local g = uby - vy
        blit(flat, vx, uby - g, sw, g, { vx, vy, vw, ceil(uby) - vy })
      end
      if y1 < vb then
        local g = vb - y1
        blit(flat, vx, y1 - (cur.h - 1) * g, sw, g, { vx, floor(y1), vw, vb - floor(y1) })
      end
    end
    -- (the rim's feather and the bar's state: cardRim / cardBar)
    local cs = cardState
    cs.done, cs.cur, cs.blit, cs.soft, cs.flat, cs.box, cs.k = false, cur, blit, soft, flat, box, k
    cs.sdx, cs.sdy, cs.sdw, cs.sdh = sdx, sdy, sdw, sdh
    cs.ubx, cs.uby, cs.U, cs.Uy, cs.x1, cs.y1 = ubx, uby, U, Uy, x1, y1
    cs.vx, cs.vy, cs.vw, cs.vh, cs.vr, cs.vb = vx, vy, vw, vh, vr, vb
    cs.extraL, cs.extraR = math.max(0, ubx - vx), math.max(0, vr - x1)
    local inScene, hidden = true, cur.uiCovers
    if not hidden then picture(cur.base) end
    local coverAt = cur.coverAt
    for i, item in ipairs(cur.items) do
      if item.kind == "seam" then
        if item.name == "ui" then inScene = false end
      elseif item.kind == "paint" or (item.canvas and item.bar) then
        -- (not under a whole screen the UI drew over it after: it ran on past that screen's sides)
        if not (coverAt and i < coverAt) then cardBar(item) end
      elseif not (inScene and hidden) then
        scissorOver(box[1], box[2], box[3], box[4])
        if item.kind == "hd" then
          tagDraw(item.rec, cur, blit, ubx, uby, U, Uy, box)
        elseif item.kind == "world" then
          if not worldDraw(item, ubx, uby, U, Uy, box) then
            scissorOver(box[1], box[2], box[3], box[4])
            drawBackdrop(item.rec, cur.w, cur.h, ubx, uby, U, Uy, ubx, uby, U, Uy)
          end
        elseif item.kind == "stage" then
          imageDraw(item.rec, ubx, uby, U, Uy)
        elseif item.kind == "backdrop" or item.kind == "band" then
          drawBackdrop(item.rec, cur.w, cur.h, ubx, uby, U, Uy, ubx, uby, U, Uy,
            item.kind == "band" and "clampzero" or nil)
        elseif item.kind == "win0" then
          real.setShader()
          real.setBlendMode("alpha", "alphamultiply")
          local c = item.color
          real.setColor(c[1], c[2], c[3], c[4])
          real.rectangle("fill", ubx, uby, cur.w * U, item.top * Uy)
          real.rectangle("fill", ubx, uby + item.bottom * Uy, cur.w * U, (cur.h - item.bottom) * Uy)
        elseif item.kind == "wash" then
          real.setShader()
          real.setBlendMode("alpha", item.premultiplied and "premultiplied" or "alphamultiply")
          real.setColor(item.r, item.g, item.b, item.a)
          real.rectangle("fill", ubx, uby, cur.w * U, item.bottom * Uy)
          real.setBlendMode("alpha", "alphamultiply")
        elseif item.canvas then
          real.setScissor()
          real.setShader()
          real.setColor(1, 1, 1, 1)
          real.setBlendMode("alpha", "premultiplied")
          picture(item.canvas)
        end
      end
    end
    cardRim()
    cs.cur, cs.blit, cs.soft, cs.flat = nil, nil, nil, nil
    real.pop()
    restoreShaders()
    self.stats.composites = self.stats.composites + 1
    return true
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
    -- (the battlers at the world's scale when this pass drew the 3D world: worldSize)
    self.worldScene = cur.pass == "battle" and cur.world or nil
    -- a whole screen over the battle (uiCovers), the caught scene, which has no scene or UI of
    -- a battle (no seam), a screen before the game starts or one over the field: the picture
    -- fills the screen
    if view ~= nil and fit.enabled and fit.fill
      and (cur.pass == "boot" or cur.pass == "screen"
           or (cur.pass == "battle" and (cur.uiCovers or not cur.hasUI))) then
      -- (the Renderer may blit the canvas again in parts, a docked text box apart: the card,
      -- the whole picture, is drawn once)
      if cur.carded then return true end
      cur.carded = true
      return compositeCard(cur, blit, bsx, bsy, view)
    end
    local fitted = cur.pass == "battle" and cur.hasUI and fit.enabled
    local fx, fy = fit.focus[1], fit.focus[2]
    -- the scene's frame on screen: where canvas (fx, fy) lands and how big a canvas pixel is;
    -- the UI's origin and scale. Without fill both are the Renderer's letterbox.
    local cx, cy, S, Sy = bx + fx * bsx, by + fy * bsy, bsx, bsy
    local ubx, uby, U, Uy = bx, by, bsx, bsy
    local sceneBox, uiBox = box, box
    local filling = fitted and fit.fill and view ~= nil
    local stacked, dyTop, top = false, 0, nil
    -- the top band's highest row that must stay on the screen when it is moved up: the enemy's HP
    -- box's top, or in a double battle the band's own (fit.chipRowsDouble: WoobleDex's stat chips
    -- stand in columns beside the foes' boxes from the band's first row, above the upper box)
    local bandTop = fit.ui.enemy[2]
    if fit.double and tonumber(fit.chipRowsDouble) then bandTop = math.min(bandTop, fit.chipRowsDouble) end
    fit.wantW = nil
    fit.sceneUp = 0
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
        -- a double battle: with the rows to spare, the scene stands above the player's two HP
        -- boxes instead of behind them (the foes' boxes still need their rows above it)
        if fit.double then
          local e = fit.ui.enemy
          local spare = (uby - top) / Uy - (e[4] - e[2])
          fit.sceneUp = round2(math.max(0, math.min(spare, fy - fit.ui.player[2] + fit.doublesGap)))
        end
        cy = uby + (fy - fit.sceneUp) * Uy
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
        elseif gt > g and not fit.turn then
          -- (back in only between turns, as the zoom is: see fit.turn)
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
        -- the enemy's HP box (the foes' two in a double battle): its top stackGap UI px under the scene's top (its canvas
        -- row 0 at the scene's scale; the screen's top when the scene reaches it), as a wide
        -- screen has it. Never the art's: the fit sees it there, the most the player's Pokemon
        -- may rise to. Held while a turn plays (a lunge may pull the scene out a little) and
        -- eased to the scene's top between turns (fit.anchor, UI px); set afresh each battle
        do
          local sceneTop = math.max(top, cy - fy * Sy)
          local want = math.min(0, (sceneTop - uby) / Uy + fit.stackGap - bandTop)
          local a = fit.anchor
          if not a or fit.idle > 2 then
            a = want
          elseif not fit.turn and a ~= want then
            local step = math.max(math.abs(want - a) * fit.inRate, 0.1)
            a = want > a and math.min(want, a + step) or math.max(want, a - step)
          end
          fit.anchor = a
          dyTop = math.min(0, round2(math.max(a, (top - uby) / Uy - bandTop)))
        end
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
      sceneBox = compScene
      sceneBox[1], sceneBox[2], sceneBox[3], sceneBox[4] = vx, vy, vw, vh
      uiBox = clipRect(ubx, uby, cur.w * U, cur.h * Uy, sceneBox, compUi)
    end
    -- the enemy's HP box (a double battle's foes' two, moved up as one) raised to fit.topGap UI
    -- px under the screen's top when the battle fills a wide screen, so the Pokemon have the rows
    -- under it. Fill Screen off keeps the game's own frame
    local raised = filling and not stacked and type(fit.topGap) == "number"
    if raised then
      dyTop = math.min(dyTop, round2((top - uby) / Uy + fit.topGap - bandTop))
    end
    -- the 3D world filling the screen: the foe's HP box (both, in a double battle) over the
    -- highest head
    -- (fitStep places it), eased there
    local headBox = filling and tuned() and not (fit.double and fit.doublesOwnSize)
    fit.headBox = headBox
    fit.screenTopUI = filling and round2((top - uby) / Uy) or 0
    if headBox and fit.boxBottom and fit.idle <= 2 then
      local want = fit.boxBottom - fit.ui.enemy[4]
      local d = fit.boxDy
      if not d then
        d = want
      elseif d ~= want then
        local step = math.max(math.abs(want - d) * fit.boxEase, 0.25)
        d = want > d and math.min(want, d + step) or math.max(want, d - step)
      end
      fit.boxDy = d
      dyTop = round2(d)
    else
      fit.boxDy = nil
    end
    -- (a mod holding the HUD - a Pokemon drawn giant for a while, Galar Rising's Dynamax: the
    -- camera still pulls back for it, the foe's HP box stays where it was; let go, it eases on
    -- from there)
    -- (the frame it is let go it still stands there - else it jumped to where the anchor had
    -- eased meanwhile for a frame - and eases on from the next)
    if self.hudHeld > 0 and filling then
      if self.heldDyTop == nil then self.heldDyTop = dyTop end
      dyTop = self.heldDyTop
    elseif self.heldDyTop ~= nil then
      if filling then dyTop = self.heldDyTop end
      if fit.anchor then fit.anchor = self.heldDyTop end
      if fit.boxDy then fit.boxDy = self.heldDyTop end
      self.heldDyTop = nil
    end
    -- the UI over the scene, in the scene's canvas pixels: shrunk about the line by the
    -- ratio of their scales; the enemy's HP box moved with the top band; the screen's top
    fit.uiK = U / S
    fit.uiTopDy = dyTop
    fit.topY = filling and math.min(0, round2(fy - (cy - top) / Sy)) or 0
    -- (and the canvas columns at the scene's left and right edges: a world-sized battler's art
    -- fits between them, worldSize / fitStep)
    local vb = sceneBox or box
    if vb then
      fit.viewL, fit.viewR = fx + (vb[1] - cx) / S, fx + (vb[1] + vb[3] - cx) / S
    else
      fit.viewL, fit.viewR = 0, 240
    end
    self.stats.topY, self.stats.uiK, self.stats.sceneUp = fit.topY, fit.uiK, fit.sceneUp
    local z, lift = 1, 0
    if fitted then
      z = fitStep(cur)
      lift = fitLift(z) + fit.extra
    end
    local moved = z ~= 1 or lift ~= 0 or filling
    local zb = 1 - (1 - z) * fit.parallax
    -- filling a screen taller than the wallpaper (sky above the battle): the wallpaper is scaled
    -- up, about the text box's line, until its top row reaches the screen's top (it wraps
    -- sideways, so it never shows an end)
    if filling then
      zb = math.max(zb, (cy - sceneBox[2]) / (fy * Sy))
    end
    -- canvas pixels -> screen, zoomed by k about the focus and raised by `up` canvas pixels
    local sx0, sy0, ssx, ssy = cx - fx * z * S, cy - (fy * z + lift) * Sy, S * z, Sy * z
    -- the player's Pokemon's feet (the bottom of its art where it rests, hd.prefit, as this
    -- frame draws it: its scale, its side's drop) and the screen's bottom, in UI canvas rows:
    -- the adapter stands the player's HP boxes on those feet when no bottom UI is drawn under
    -- them (src/gen3.lua noteDrop). The lowest of a side's two; nil with none out
    do
      local feet
      if cur.pass == "battle" and cur.hasUI then
        local dy = fitted and ((cur.shift.playerY or 0) - (cur.shift.playerRaise or 0)) or 0
        for _, rec in pairs(cur.prefit) do
          local spec = rec.spec
          if spec.side == "player" and not spec.trainer and rec.out ~= false then
            local ok, _, Y, _, hpy, k, tex, quad = pcall(place, rec)
            if ok and Y then
              -- (its art's last row, in its frame: else the frame's bottom)
              local rows = type(spec.art) == "table" and tonumber(spec.art[4])
              if not rows and quad then
                local _
                _, _, _, rows = quad:getViewport()
              elseif not rows and tex and tex.getHeight then
                rows = tex:getHeight()
              end
              if rows then
                local y = sy0 + (Y + (rows - hpy) * math.abs(rec.sy * k * rec.tsy) + dy) * ssy
                local row = (y - uby) / Uy
                if not feet or row > feet then feet = row end
              end
            end
          end
        end
      end
      fit.playerFeetUI = feet
      local vb = sceneBox or box
      fit.screenBottomUI = vb and (vb[2] + vb[4] - uby) / Uy or cur.h
      self.stats.playerFeetUI, self.stats.screenBottomUI = feet, fit.screenBottomUI
    end
    -- the far wallpaper does not rise: its rows below the text box's top are not scenery
    -- (the cart hides them), so the text box's line stays its bottom edge
    local bkx, bky, bksx, bksy = cx - fx * zb * S, cy - fy * zb * Sy, S * zb, Sy * zb
    -- the screen rect a wallpaper covers (canvas size at scale 1)
    local canvasBox = compCanvas
    canvasBox[1], canvasBox[2], canvasBox[3], canvasBox[4] = bx, by, cur.w * bsx, cur.h * bsy
    local cover = filling and sceneBox or canvasBox
    -- the stacked UI in two bands (one when a draw crosses the split this frame)
    local split = fit.split
    -- centred when nothing is below: the sky over the HP box and the ground under the text
    -- box made equal (halving the difference each frame)
    if stacked and view.bottom == nil then
      local gapTop = uby + dyTop * Uy - top
      fit.raise = round2(math.max(0, (gapTop + (fit.raise or 0)) / 2))
    else
      fit.raise = 0
    end
    -- the enemy's HUD drawn as a layer of its own this frame (hd.seam("uiTop") ... "uiTopEnd"):
    -- that layer is the top band, moved whole, and the rest of the UI stays where it is, so a
    -- draw across the split row (a chip by the player's box, a window) tears nothing; else the
    -- rows above `split` are the top band, and a draw across them keeps the UI in one piece
    local topLayer = false
    for _, item in ipairs(cur.items) do
      if item.kind == "seam" and item.name == "uiTop" then
        topLayer = true
        break
      end
    end
    local banded = ((stacked or raised) and dyTop < 0 or headBox and dyTop ~= 0) and (topLayer or not cur.uiStraddle)
    local topBy = uby + dyTop * Uy
    local topBox, lowBox
    -- (unfilled: the Renderer's clip, else its letterbox)
    local clipTo = sceneBox or canvasBox
    local topAll
    if banded then
      topBox = clipRect(ubx, topBy, cur.w * U, split * Uy, clipTo, compTop)
      lowBox = clipRect(ubx, uby + split * Uy, cur.w * U, (cur.h - split) * Uy, clipTo, compLow)
      if topLayer then topAll = clipRect(ubx, topBy, cur.w * U, cur.h * Uy, clipTo, compTopAll) end
    end
    local byLayer = banded and topLayer
    local k = filling and U ~= math.floor(U) and math.ceil(U) or 1
    if filling or banded then noteUi(cur, ubx, uby, U, Uy, uiBox or clipTo, split, topBy, topBox, lowBox) end
    self.stats.lift = lift
    self.stats.fill = S / bsx
    self.stats.uiScale = U
    self.stats.uiTopDy = banded and dyTop or 0
    local scissor = scissorBox
    local inScene = true
    local inTop = false
    local worldShown
    if not moved then blit(cur.base) else blit(cur.base, sx0, sy0, ssx, ssy, sceneBox) end
    -- (a bar across the screen's bottom, hd.paint / hd.bar: the view's sides, the UI's margins)
    local barView = sceneBox or clipTo
    local extraL = math.max(0, ubx - barView[1])
    local extraR = math.max(0, barView[1] + barView[3] - (ubx + cur.w * U))
    -- the UI's layers before a paint that hides rows are cut off at its row
    local hideAt, hideRow
    for i, item in ipairs(cur.items) do
      if item.kind == "paint" and item.hide then hideAt, hideRow = i, item.hide break end
    end
    local function cutBox(b, i)
      if not (hideAt and i < hideAt and b) then return b end
      local y1 = math.min(b[2] + b[4], uby + hideRow * Uy)
      local o = cutScratch
      o[1], o[2], o[3], o[4] = b[1], b[2], b[3], math.max(0, y1 - b[2])
      return o
    end
    real.push("all")
    for i, item in ipairs(cur.items) do
      if item.kind == "paint" then
        if not inScene or cur.cardUi then
          real.setShader()
          -- (a whole screen with the battle's text box: its picture's row above the panel's run
          -- on down to the bar, as compositeCard does)
          if cur.cardUi and item.hide and item.runTo and item.runTo > item.hide then
            local src = flattenCard(cur, blit)
            if src then
              real.setColor(1, 1, 1, 1)
              real.setBlendMode("alpha", "premultiplied")
              local o = cutScratch
              o[1], o[2], o[3], o[4] = barView[1], uby + item.hide * Uy, barView[3], (item.runTo - item.hide) * Uy
              runDown(src, ubx, uby, U, Uy, item.hide, o)
            end
          end
          real.setColor(1, 1, 1, 1)
          real.setBlendMode("alpha", "alphamultiply")
          scissorOver(barView[1], barView[2], barView[3], barView[4])
          local c = paintCtx
          c.x, c.y, c.sx, c.sy = ubx, uby, U, Uy
          c.l, c.r, c.extraL, c.extraR = barView[1], barView[1] + barView[3], extraL, extraR
          local ok, err = pcall(item.fn, item.a, c)
          if not ok then self.stats.paintError = tostring(err) end
          real.setScissor()
        end
      elseif item.kind == "seam" then
        if item.name == "ui" then
          inScene = false
        elseif item.name == "uiTop" then
          inTop = true
        elseif item.name == "uiTopEnd" then
          inTop = false
        end
      elseif item.kind == "wash" then
        -- (a wash over the field: from the view's top down to the text box's line on the screen
        -- when it reaches the cart's, else to its own row there, across the view)
        real.setShader()
        real.setBlendMode("alpha", item.premultiplied and "premultiplied" or "alphamultiply")
        real.setColor(item.r, item.g, item.b, item.a)
        local v = sceneBox or uiBox or clipTo
        local row = item.bottom
        if math.abs(row - fy) < 0.5 and fit.ui and fit.ui.text then row = math.max(row, fit.ui.text[2]) end
        local b = math.min(v[2] + v[4], uby + row * Uy)
        scissorOver(v[1], v[2], v[3], v[4])
        if b > v[2] then real.rectangle("fill", v[1], v[2], v[3], b - v[2]) end
        real.setScissor()
        real.setBlendMode("alpha", "alphamultiply")
        real.setColor(1, 1, 1, 1)
      elseif item.kind == "win0" then
        real.setShader()
        real.setBlendMode("alpha", "alphamultiply")
        local c = item.color
        real.setColor(c[1], c[2], c[3], c[4])
        if filling then
          -- across the whole view, opening about the scene's middle row in the view's proportions:
          -- shut, the whole screen is black; open, the bars reach the view's edges together
          scissor(sceneBox)
          local v = sceneBox
          local vTop, vBot = v[2], v[2] + v[4]
          local mid = cur.h / 2
          local yc = math.max(vTop, math.min(vBot, cy + (mid - fy) * Sy))
          local t = yc - math.max(0, mid - item.top) / mid * (yc - vTop)
          local b = yc + math.max(0, item.bottom - mid) / (cur.h - mid) * (vBot - yc)
          if t > vTop then real.rectangle("fill", v[1], vTop, v[3], t - vTop) end
          if b < vBot then real.rectangle("fill", v[1], b, v[3], vBot - b) end
        else
          -- the cart's: over the UI's box
          scissor(uiBox)
          real.rectangle("fill", ubx, uby, cur.w * U, item.top * Uy)
          real.rectangle("fill", ubx, uby + item.bottom * Uy, cur.w * U, (cur.h - item.bottom) * Uy)
        end
      elseif item.kind == "wide" then
        -- a move's background band: across the whole view with fill, else in the canvas's box
        drawWide(item, sx0, sy0, ssx, ssy, sceneBox or cover)
      elseif item.kind == "row" then
        -- a row of copies, on past the canvas's sides
        drawRow(item, sx0, sy0, ssx, ssy, sceneBox or cover)
      elseif item.kind == "free" then
        -- a move's effect crossing the canvas's edges, uncut
        drawFree(item, sx0, sy0, ssx, ssy, sceneBox or cover)
      elseif item.kind == "world" then
        -- the battle scene's world: the ground under the battlers, so zoomed with them (no
        -- parallax), over the whole view; told where the UI's box is (the world shows beside a
        -- text box narrower than the view)
        item.ui = uiBox
        if worldDraw(item, sx0, sy0, ssx, ssy, sceneBox or cover) then
          worldShown = item
        else
          scissor(sceneBox)
          drawBackdrop(item.rec, cover[3], cover[4], bkx, bky, bksx, bksy, cover[1], cover[2], 1, 1)
        end
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
            -- zoomed with the scene but not raised: its rows stay on the text box's line, where
            -- the cart puts them. A band that ends on a solid row (grass, sand, waves) runs on
            -- down to the view's bottom, so beside a text box that no longer spans the screen it
            -- still covers the field; any other (speed lines) is hidden below that line, as the
            -- cart's text box (the whole screen's width) hides it
            local gx, gy = cx - fx * z * S, cy - fy * z * Sy
            local v = sceneBox or cover
            if not item.fill then
              real.setScissor(v[1], v[2], v[3], math.max(0, math.min(v[4], cy - v[2])))
            end
            drawBackdrop(item.rec, cover[3], cover[4], gx, gy, ssx, ssy, cover[1], cover[2], 1, 1,
              "clampzero", item.fill)
          else
            drawBackdrop(item.rec, cur.w, cur.h, ubx, uby, U, Uy, ubx, uby, U, Uy, "clampzero")
          end
        elseif item.kind == "stage" then
          local d = (fitted and cur.shift[item.side]) or 0
          local dy = (fitted and item.side == "player" and cur.shift.playerY) or 0
          -- (in the 3D world: the scene's shadow scaled about its middle to the Pokemon's body)
          local k = tuned() and self.worldShadow[item.side]
          local sh = k and type(self.scene) == "table" and type(self.scene.SHADOW) == "table"
            and self.scene.SHADOW[item.side]
          if sh then
            -- (its middle in the pass canvas's pixels, through the draw's own transform)
            local r = item.rec
            local mx = r.tx + (r.x + sh[1] * r.sx) * r.tsx
            local my = r.ty + (r.y + sh[2] * r.sy) * r.tsy
            imageDraw(r, sx0 + (d + mx * (1 - k)) * ssx, sy0 + (dy + my * (1 - k)) * ssy, ssx * k, ssy * k)
          else
            imageDraw(item.rec, sx0 + d * ssx, sy0 + dy * ssy, ssx, ssy)
          end
        elseif inScene then
          -- a battler drawn by the battle itself moves with its side's shift; one drawn by a
          -- move animation is already where the shifted coordinates put it
          local spec = item.rec.spec
          local side = spec.side
          local d = (fitted and side and not item.rec.inAnim and cur.shift[side]) or 0
          -- (a double battle in the 3D world: its spot spread apart)
          if fitted and side and not item.rec.inAnim and not spec.trainer then
            d = d + spreadDx((place(item.rec)), spec)
          end
          -- (a trainer is anchored to the text box instead: pinBottom below)
          local dy = (fitted and side == "player" and not item.rec.inAnim and not spec.trainer
            and cur.shift.playerY) or 0
          -- the Pokemon itself, not its trainer, stands raised above a small back's pad
          if fitted and side == "player" and not item.rec.inAnim and not spec.trainer then
            dy = dy - (cur.shift.playerRaise or 0)
          end
          -- pinBottom (canvas y): the text box's line, under the unzoomed mapping
          local pin = fitted and spec.pinBottom and (cy + (spec.pinBottom - fy) * Sy + fit.sceneUp * Uy) or nil
          -- (where its body lands on the window this frame: exports.battlerRect)
          noteBattler(cur, item.rec, sx0 + d * ssx, sy0 + dy * ssy, ssx, ssy)
          tagDraw(item.rec, cur, blit, sx0 + d * ssx, sy0 + dy * ssy, ssx, ssy, sceneBox, pin)
        elseif byLayer then
          -- (the enemy's HUD's layer moved whole; the rest where it is)
          if inTop then
            scissor(topAll)
            tagDraw(item.rec, cur, blit, ubx, topBy, U, Uy, topAll)
          else
            scissor(uiBox)
            tagDraw(item.rec, cur, blit, ubx, uby, U, Uy, uiBox)
          end
        elseif banded and item.rec.ty + item.rec.y * item.rec.tsy < split then
          scissor(topBox)
          tagDraw(item.rec, cur, blit, ubx, topBy, U, Uy, topBox)
        else
          if banded then scissor(lowBox) end
          tagDraw(item.rec, cur, blit, ubx, uby, U, Uy, banded and lowBox or uiBox)
        end
      else
        real.setScissor()
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "premultiplied")
        if item.bar and (not inScene or cur.cardUi) then
          -- drawn for the bar (hd.bar): moved down into it, the part left of its split to the
          -- screen's left (the UI's left margin), the rest to its right
          local b = item.bar
          local c, kk = item.canvas, 1
          if k > 1 then c, kk = sharpen(item.canvas, cur.w, cur.h, k) end
          local v = barView
          local y0 = math.max(uby + b.top * Uy, v[2])
          local y1 = math.min(uby + b.bottom * Uy, v[2] + v[4])
          local oy = uby + b.dy * Uy
          if y1 > y0 then
            local cut = b.split and (ubx - extraL + b.split * U) or (v[1] + v[3])
            local o = cutScratch
            o[1], o[2], o[3], o[4] = v[1], y0, cut - v[1], y1 - y0
            blit(c, ubx - extraL, oy, U / kk, Uy / kk, o, kk)
            if b.split then
              local d = ubx + b.split * U + extraR
              o[1], o[2], o[3], o[4] = d, y0, v[1] + v[3] - d, y1 - y0
              blit(c, ubx + extraR, oy, U / kk, Uy / kk, o, kk)
            end
          end
        elseif item.screen and filling then
          -- a whole-scene draw (a move's background, a flash) or a whole-UI one (a fade) covers
          -- the whole screen
          local v = sceneBox
          local sc = math.max(v[3] / cur.w, v[4] / cur.h)
          local lx, ly = v[1] + (v[3] - cur.w * sc) / 2, v[2] + (v[4] - cur.h * sc) / 2
          blit(item.canvas, lx, ly, sc, sc, sceneBox)
          if inScene and item.toLine and not item.below then runDown(item.canvas, lx, ly, sc, sc, fy, sceneBox) end
        elseif item.edge and inScene and filling and drawEdge(item.canvas, sx0, sy0, ssx, ssy, sceneBox) then
          -- (drawn: zoomed with the scene, its edge pixels run on out to the screen's sides, and
          -- one that stops on the text box's line on down beside it)
          if item.toLine and not item.below then runDown(item.canvas, sx0, sy0, ssx, ssy, fy, sceneBox) end
          self.stats.edgeDrawn = (self.stats.edgeDrawn or 0) + 1
        elseif inScene and not item.screen and moved then
          blit(item.canvas, sx0, sy0, ssx, ssy, sceneBox)
        elseif not inScene and (filling or banded) then
          local c, kk = item.canvas, 1
          if k > 1 then c, kk = sharpen(item.canvas, cur.w, cur.h, k) end
          if byLayer then
            if inTop then
              blit(c, ubx, topBy, U / kk, Uy / kk, topAll, kk)
            else
              blit(c, ubx, uby, U / kk, Uy / kk, cutBox(uiBox, i), kk)
            end
          elseif banded then
            blit(c, ubx, topBy, U / kk, Uy / kk, topBox, kk)
            blit(c, ubx, uby, U / kk, Uy / kk, cutBox(lowBox, i), kk)
          else
            blit(c, ubx, uby, U / kk, Uy / kk, cutBox(uiBox, i), kk)
          end
        elseif hideAt and i < hideAt and not inScene then
          blit(item.canvas, nil, nil, nil, nil, cutBox(clipTo, i))
        else
          blit(item.canvas)
        end
        real.setBlendMode("alpha", "alphamultiply")
      end
    end
    -- over everything, when the world was drawn: what the scene lays over the whole shot (the
    -- entrance's cinema bars)
    if worldShown and self.sceneOverlay then
      local v = sceneBox or cover
      scissorOver(v[1], v[2], v[3], v[4])
      local ok, err = pcall(self.sceneOverlay, worldShown, v)
      if not ok then self.stats.sceneError = tostring(err) end
      real.setBlendMode("alpha", "alphamultiply")
      real.setColor(1, 1, 1, 1)
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
    local hideAt, hideRow
    for i, item in ipairs(cur.items) do
      if item.kind == "paint" and item.hide then hideAt, hideRow = i, item.hide break end
    end
    local inUi = false
    for i, item in ipairs(cur.items) do
      if item.kind == "seam" and item.name == "ui" then inUi = true end
      -- (the battle scene's world goes back as the wallpaper it stands in for)
      if item.kind == "hd" or item.kind == "backdrop" or item.kind == "stage" or item.kind == "band"
          or item.kind == "wide" or item.kind == "world" or item.kind == "free" then
        local rec = item.rec
        real.push()
        real.translate(rec.tx, rec.ty)
        real.scale(rec.tsx, rec.tsy)
        real.setColor(rec.color[1], rec.color[2], rec.color[3], rec.color[4])
        useShader(rec)
        real.setBlendMode(rec.blend[1], rec.blend[2])
        -- a tagged draw at its own size (a flattened field under a weather's colour pass, such as
        -- Petalburg Woods' shade, keeps its sized sprites); a slice of a full-resolution frame, and
        -- the stage and backdrop, as recorded
        local drawn = false
        if item.kind == "hd" then
          if rec.quad then
            drawn = drawAtScale(rec.shader ~= nil, rec.image, rec.spec, viewOf(rec), rec.x, rec.y, rec.r, rec.sx, rec.sy,
              rec.ox, rec.oy)
          else
            drawn = drawAtScale(rec.shader ~= nil, rec.image, rec.spec, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
          end
        end
        if not drawn and (item.kind == "wide" or (item.kind == "free" and item.qx)) then
          -- (through the quad's viewport as it was drawn: the engine has moved its quad since)
          local iw, ih = rec.image:getWidth(), rec.image:getHeight()
          if wideQuad then
            wideQuad:setViewport(item.qx, item.qy, item.qw, item.qh, iw, ih)
          else
            wideQuad = real.newQuad(item.qx, item.qy, item.qw, item.qh, iw, ih)
          end
          real.draw(rec.image, wideQuad, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
          drawn = true
        end
        if not drawn then
          if rec.quad then
            real.draw(rec.image, viewOf(rec), rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
          else
            real.draw(rec.image, rec.x, rec.y, rec.r, rec.sx, rec.sy, rec.ox, rec.oy)
          end
        end
        real.pop()
      elseif item.kind == "layer" then
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "premultiplied")
        if item.bar then
          -- (moved down into the bar, inside the canvas)
          local b = item.bar
          real.setScissor(0, b.top, cur.w, b.bottom - b.top)
          real.draw(item.canvas, 0, b.dy)
          real.setScissor()
        elseif inUi and hideAt and i < hideAt then
          real.setScissor(0, 0, cur.w, hideRow)
          real.draw(item.canvas, 0, 0)
          real.setScissor()
        else
          real.draw(item.canvas, 0, 0)
        end
        real.setBlendMode("alpha", "alphamultiply")
      elseif item.kind == "paint" then
        real.setShader()
        real.setColor(1, 1, 1, 1)
        real.setBlendMode("alpha", "alphamultiply")
        local c = paintCtx
        c.x, c.y, c.sx, c.sy, c.l, c.r, c.extraL, c.extraR = 0, 0, 1, 1, 0, cur.w, 0, 0
        local ok, err = pcall(item.fn, item.a, c)
        if not ok then self.stats.paintError = tostring(err) end
      elseif item.kind == "wash" and real.rectangle then
        -- a wash over the field, the cart's way
        real.setShader()
        real.setBlendMode("alpha", item.premultiplied and "premultiplied" or "alphamultiply")
        real.setColor(item.r, item.g, item.b, item.a)
        real.rectangle("fill", 0, 0, cur.w, item.bottom)
        real.setBlendMode("alpha", "alphamultiply")
        real.setColor(1, 1, 1, 1)
      elseif item.kind == "win0" and real.rectangle then
        -- the intro's black bars, the cart's way
        real.setShader()
        real.setBlendMode("alpha", "alphamultiply")
        local c = item.color
        real.setColor(c[1], c[2], c[3], c[4])
        real.rectangle("fill", 0, 0, cur.w, item.top)
        real.rectangle("fill", 0, item.bottom, cur.w, cur.h - item.bottom)
      end
    end
    real.pop()
    restoreShaders()
    -- a colour-mapped field that is not composited: the weather's colour map done here, the
    -- flattened field through it into the new canvas, under what the weather drew over it
    local cm = cur.cm
    if cm and cm.shader then
      self.done[cm.to] = nil
      local keep = self.mapTargets(cur.w, cur.h)
      real.push("all")
      real.origin()
      real.setScissor()
      real.setShader()
      real.setColor(1, 1, 1, 1)
      real.setCanvas(keep)
      real.clear(0, 0, 0, 0)
      real.setBlendMode("replace", "premultiplied")
      real.draw(cm.to, 0, 0)
      real.pop()
      self.drawMapped(cm, cur.base, cm.to)
      real.push("all")
      real.origin()
      real.setScissor()
      real.setCanvas(cm.to)
      real.setColor(1, 1, 1, 1)
      real.setBlendMode("alpha", "premultiplied")
      real.draw(keep, 0, 0)
      real.pop()
      cur.cm = nil
    end
    -- flattened in the middle of a pass: the engine carries on drawing into its own canvas
    if midPass then real.setCanvas(cur.base) end
    self.stats.flattened = self.stats.flattened + 1
  end

  --- The frame is over: anything still waiting for a blit that never came is dropped
  --- (it was flattened when that could be known in time).
  function self.endFrame()
    -- (emptied, not made anew: a frame's passes are let go here)
    for k in pairs(self.done) do self.done[k] = nil end
    poolsTurn()
    self.giantTick()
    if self.asideTick then self.asideTick() end
    -- (frames counted: the scene's drawnFrame, exports.battleWeatherDrawn)
    self.frames = (self.frames or 0) + 1
    self.recover()
    -- frames since a battle was last fitted: a gap means the next battle starts afresh
    self.fit.idle = self.fit.idle + 1
  end

  return self
end

return HD
