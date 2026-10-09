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
--                           filter   = "nearest" (default) or "linear"
--   untag(image)
--   isActive()            the engine seams were found and wrapped
--   enabled(pass)         "battle" or "field": is it on (the player's options)
--   setEnabled(pass, on)
--   stats()               counters for debugging: splits, composites, flattened, overCap

return function(mod, hd, state)
  local exports = {}
  exports.version = 1
  exports.tag = function(image, spec) return hd.tag(image, spec) end
  exports.untag = function(image) return hd.untag(image) end
  exports.isActive = function() return state.active == true end
  exports.enabled = function(pass) return state.active == true and hd.enabled[pass] == true end
  exports.setEnabled = function(pass, on)
    if hd.enabled[pass] ~= nil then hd.enabled[pass] = on and true or false end
  end
  exports.stats = function()
    local s = {}
    for k, v in pairs(hd.stats) do s[k] = v end
    return s
  end
  mod.exports = exports
end
