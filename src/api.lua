-- mod.exports: what other mods use.
--
--   local hd = mod:find("gen3-hd-sprites")
--   if hd and hd.exports.isActive() then ... end
--
--   tag(image, spec)      draw this image at window resolution wherever a battle or the
--                         field draws it. spec (all optional):
--                           scale    = k        size multiplier (1 = the size it is drawn at)
--                           anchor   = "feet"   scale about the bottom-centre of the drawn quad
--                                               (field sprites); otherwise about `lowPivot`
--                           texture  = img      draw this image instead (a full-resolution
--                           quad     = q        frame of the low-res image that is tagged), its
--                           pivot    = {x, y}   pivot standing where the low-res image's
--                           lowPivot = {x, y}   lowPivot (default {32, 32}, the engine's pic origin)
--                           quadPivots = { [quad] = {x, y, scale} }  a draw through one of these
--                                               quads scales about its own point (quad-local)
--                                               instead of lowPivot / the feet, e.g. a sprite
--                                               drawn cut short; `scale` (optional) replaces the
--                                               spec's scale for it (1 = a slice already drawn at
--                                               its final size). Read at draw time, so it may grow.
--                           filter   = "nearest" (default) or "linear"
--                           top      = n        the first row of art in the frame (quad pixels),
--                                               the highest over the animation; Battle Fit fits
--                                               the art, not the frame's empty margin (default 0)
--                           side     = "enemy" (default) or "player": whose Pokemon it is
--                           body     = {x0, y0, x1, y1}  (side "player") its resting body box
--                                               (quad pixels): Battle Fit keeps its top at or
--                                               below the tallest cart back sprite's (y 52) and,
--                                               when it can, at most 30% of it under the
--                                               player's HP box and text box
--   untag(image)
--   tagOf(image)          the spec an image was tagged with, or nil: a mod that draws a tagged
--                         pic outside the battle, field and Pokedex passes (PlayNav's Super
--                         Training rides the player's back pic on its own top screen) can draw
--                         the full-resolution texture itself instead of the low-res stand-in
--   isActive()            the engine seams were found and wrapped
--   enabled(pass)         "battle", "field" or "dex" (the Pokedex screens): is it on (the
--                         player's options)
--   setEnabled(pass, on)
--   cap(pass)             most tagged draws (layers) a pass may use before the rest are drawn
--                         on the game's pixels, at their own size: battle 8, field 12, dex 8. Each
--                         layer is one window-sized canvas. On the field a tagged draw wholly off
--                         the screen takes none.
--   setCap(pass, n)       change it (1..32)
--   stats()               counters for debugging: splits, composites, flattened, overCap,
--                         offCanvas
--   features              { quadPivots = true, dex = true, battleFit = true, flip = true,
--                         shades = true }: what this version supports
--   fitEnabled()          Battle Fit is on: the battle scene zooms out so tall sprites fit
--                         under the top of the screen (the UI is never zoomed)
--   setFit(on)            turn Battle Fit on or off (it pulls back to 40% at most); the old
--                         "off" / "fit" / "tall" still work, "fit" and "tall" meaning on
--   sceneZoom()           the battle scene's zoom this frame (1 = none)
--   sceneEnabled() / setScene(on)   Battle Scene (Gen 3): battles over the overworld in 2.5D
--                         (needs Battle Fit)
--   fillEnabled() / setFill(on)   Fill Screen: the battle scene fills the screen, its UI
--                         docked to the bottom at its own scale (needs Battle Fit)

return function(mod, hd, state)
  local exports = {}
  exports.version = 2
  exports.features = { quadPivots = true, dex = true, battleFit = true, tagOf = true, flip = true,
                       shades = true }
  exports.tag = function(image, spec) return hd.tag(image, spec) end
  exports.untag = function(image) return hd.untag(image) end
  exports.tagOf = function(image) return hd.tagOf(image) end
  exports.isActive = function() return state.active == true end
  exports.enabled = function(pass) return state.active == true and hd.enabled[pass] == true end
  exports.setEnabled = function(pass, on)
    if hd.enabled[pass] ~= nil then hd.enabled[pass] = on and true or false end
  end
  exports.cap = function(pass) return hd.caps[pass] end
  exports.setCap = function(pass, n)
    n = tonumber(n)
    if hd.caps[pass] ~= nil and n then hd.caps[pass] = math.max(1, math.min(32, math.floor(n))) end
    return hd.caps[pass]
  end
  exports.fitEnabled = function()
    return state.active == true and hd.enabled.battle == true and hd.fit.enabled == true
  end
  exports.setFit = function(on)
    hd.fit.enabled = hd.fit.available == true and on ~= nil and on ~= false and on ~= "off"
  end
  exports.fillEnabled = function()
    return exports.fitEnabled() and hd.fit.fill == true
  end
  exports.setFill = function(on) hd.fit.fill = on and true or false end
  -- Battle Scene (Gen 3): the battle over the overworld in 2.5D
  exports.sceneEnabled = function()
    return exports.fitEnabled() and hd.scene ~= nil and hd.scene.enabled == true
  end
  exports.setScene = function(on)
    if hd.scene then hd.scene.enabled = on and true or false end
  end
  -- (tests: aim the current battle scene's settled camera at map cell (tx, tz), pitch in
  -- degrees, distance in tiles; nil to leave the stage's)
  exports._sceneLook = function(tx, tz, pitch, dist, yaw)
    local s = hd.scene and hd.scene.last
    local Camera = hd.scene and hd.scene.Camera
    if not (s and Camera) then return false end
    s.to = Camera.pose(tx, tz, pitch and math.rad(pitch) or nil, dist, s.to and s.to.ty or 0,
      yaw and math.rad(yaw) or 0)
    s.progress = 1
    return true
  end
  -- (dev: a relief.bin's bytes for the scene to draw, src/scene/relief.lua; read by the driver)
  exports._sceneRelief = function(bytes)
    return hd.scene and hd.scene.setReliefBytes and hd.scene.setReliefBytes(bytes) or false
  end
  -- (dev: one slice of the relief's background build, as the frame hook runs it; the drivers
  -- call it since their frames skip the engine's update hook) -> state, detail, phases
  exports._sceneWarm = function(mapId)
    local s = hd.scene
    if not (s and s.warm) then return nil end
    local n = mapId == "all" and s.warmAll() or s.warm(mapId)
    while s.warmStep() > 0 do end
    return n
  end
  -- (dev: a readied model's parts and their bounds, by spec name) -> { { tag, n, x0, y0, z0, x1, y1, z1 } }
  exports._sceneModelBounds = function(name)
    local s = hd.scene
    local md = s and s.modelOf and s.modelOf(name)
    if not md then return nil end
    local by, order = {}, {}
    for _, t in ipairs(md.tris) do
      local tag = tostring(t.tag or "?"):gsub("%..*$", "")
      local b = by[tag]
      if not b then b = { tag = tag, n = 0, 1e9, 1e9, 1e9, -1e9, -1e9, -1e9 }; by[tag] = b; order[#order + 1] = b end
      b.n = b.n + 1
      for k = 1, 3 do
        local p = t[k]
        b[1], b[2], b[3] = math.min(b[1], p[1]), math.min(b[2], p[2]), math.min(b[3], p[3])
        b[4], b[5], b[6] = math.max(b[4], p[1]), math.max(b[5], p[2]), math.max(b[6], p[3])
      end
    end
    return order
  end
  -- (dev: a model's art as rows of '#' (drawn) and '.' (cleared ground))
  exports._sceneModelArt = function(name)
    local s = hd.scene
    local md = s and s.modelOf and s.modelOf(name)
    if not md then return nil end
    local art, rows = md.art, {}
    for y = 0, art.h - 1 do
      local r = {}
      for x = 0, art.w - 1 do r[#r + 1] = art.px[(y * art.w + x) * 4 + 4] >= 0.5 and "#" or "." end
      rows[#rows + 1] = table.concat(r)
    end
    return rows
  end
  -- (dev: a model's art itself, { w, h, px }, built afresh)
  exports._sceneModelArtRaw = function(name)
    local s = hd.scene
    local md = s and s.modelOf and s.modelOf(name)
    return md and md.art or nil
  end
  -- (dev: false lays the ground under buildings by the old rule - the commonest spec ground round
  -- each, the map's paint in every cell it paints otherwise - for before-and-after shots)
  exports._sceneGroundPlan = function(on)
    if hd.scene then hd.scene.groundPlanOff = on == false end
  end
  -- (dev: a metatile's two layers at a pixel, through the scene's pixel source) -> r,g,b,a, r,g,b,a
  exports._scenePixel = function(pair, mid, x, y)
    local s = hd.scene
    local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
    local src = s and s._pixelSource and okN and NativeTileset and s._pixelSource(NativeTileset, pair)
    if not src then return nil end
    local r0, g0, b0, a0 = src.under(mid, x, y)
    local r1, g1, b1, a1 = src.over(mid, x, y)
    return r0, g0, b0, a0, r1, g1, b1, a1
  end
  exports._reliefStep = function(watch)
    local run = hd.scene and hd.scene.reliefRun
    if not run then return nil end
    -- (dev: watch = seconds, the stretches between ticks longer than that, in run.gaps)
    if watch and not run.watch then run.watch, run.gaps = watch, {} end
    local st = run.state()
    if st == "idle" then run.start() end
    run.step()
    return run.state()
  end
  -- (dev: a layout's bridge read afresh - its blocks, the curb's height, the read - and a block's
  -- triangles)
  exports._bridgeBlocks = function(name)
    if not (hd.scene and hd.scene._bridgeBlocks) then return nil end
    return hd.scene._bridgeBlocks(name)
  end
  -- (a layout's deck table, for an overworld that lifts its walkers; dev: the models standing in a
  -- layout, their footprints and tops)
  exports.sceneDecks = function(name)
    return hd.scene and hd.scene.decks and hd.scene.decks(name) or nil
  end
  exports._layoutModels = function(name)
    return hd.scene and hd.scene._layoutModels and hd.scene._layoutModels(name) or nil
  end
  -- (dev: the rooms read afresh up to `upto`, and a piece's model)
  exports._rooms = function(upto)
    if not (hd.scene and hd.scene._rooms) then return nil end
    return hd.scene._rooms(upto)
  end
  exports._roomsJob = function(budget, fresh, watch)
    return hd.scene and hd.scene._roomsJob and hd.scene._roomsJob(budget, fresh, watch)
  end
  exports._roomBuild = function(piece, bare)
    return hd.scene and hd.scene._roomBuild and hd.scene._roomBuild(piece, bare)
  end
  exports._bridgeJob = function(name, budget, fresh, watch)
    return hd.scene and hd.scene._bridgeJob and hd.scene._bridgeJob(name, budget, fresh, watch)
  end
  exports._bridgeMesh = function(block, curbHeight)
    return hd.scene and hd.scene._bridgeMesh and hd.scene._bridgeMesh(block, curbHeight)
  end
  -- (tests: the current battle scene alone, as image data w x h)
  exports._sceneShot = function(w, h)
    return hd.scene and hd.scene.snapshot and hd.scene.snapshot(w, h) or nil
  end
  exports.sceneZoom = function()
    if not exports.fitEnabled() then return 1 end
    return hd.fit.z
  end
  exports.stats = function()
    local s = {}
    for k, v in pairs(hd.stats) do s[k] = v end
    return s
  end
  mod.exports = exports
end
