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
--   isActive()            the engine seams were found and wrapped
--   enabled(pass)         "battle", "field" or "dex" (the Pokedex screens): is it on (the
--                         player's options)
--   setEnabled(pass, on)
--   cap(pass)             most tagged draws (layers) a pass may use before the rest are drawn
--                         low-res: battle 8, field 12, dex 8. Each layer is one window-sized canvas.
--   setCap(pass, n)       change it (1..32)
--   stats()               counters for debugging: splits, composites, flattened, overCap
--   features              { quadPivots = true, dex = true, battleFit = true }: what this
--                         version supports
--   fitEnabled()          Battle Fit is on: the battle scene zooms out so tall sprites fit
--                         under the top of the screen (the UI is never zoomed)
--   setFit(mode)          "off", "fit" (zoom out to 50% at most) or "tall" (40%)
--   sceneZoom()           the battle scene's zoom this frame (1 = none)

return function(mod, hd, state)
  local exports = {}
  exports.version = 2
  exports.features = { quadPivots = true, dex = true, battleFit = true }
  exports.tag = function(image, spec) return hd.tag(image, spec) end
  exports.untag = function(image) return hd.untag(image) end
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
  exports.setFit = function(mode)
    if mode == "off" then
      hd.fit.enabled = false
    elseif hd.fit.modes[mode] then
      hd.fit.enabled = hd.fit.available == true
      hd.fit.zMin = hd.fit.modes[mode]
    end
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
