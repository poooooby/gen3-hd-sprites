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
--   untag(image)
--   isActive()            the engine seams were found and wrapped
--   enabled(pass)         "battle" or "field": is it on (the player's options)
--   setEnabled(pass, on)
--   cap(pass)             most tagged draws (layers) a pass may use before the rest are drawn
--                         low-res: battle 8, field 12. Each layer is one window-sized canvas.
--   setCap(pass, n)       change it (1..32)
--   stats()               counters for debugging: splits, composites, flattened, overCap
--   features              { quadPivots = true }: what this version supports

return function(mod, hd, state)
  local exports = {}
  exports.version = 1
  exports.features = { quadPivots = true }
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
  exports.stats = function()
    local s = {}
    for k, v in pairs(hd.stats) do s[k] = v end
    return s
  end
  mod.exports = exports
end
