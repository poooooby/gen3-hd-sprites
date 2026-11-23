-- OmniUI (mod id omni_ui) redraws the game's screens in its own high-resolution style: the
-- battle's HP boxes and text box, the party, the bag, the Pokedex, the menus, the title. On a
-- screen it draws WoobleView steps aside: no Battle Fit, no Fill Screen, no Battle Text Box, no
-- 3D battle and no HD pass there, so the game draws that screen its own way under OmniUI's
-- picture. The field goes on as usual: OmniUI only lays its menus and dialogue over it.
--
-- Which screen OmniUI draws is its own answer, ModernOverlay.getActiveScreen (nil when it
-- yields the screen), asked only while OmniUI runs (mod:find: then require hands back the module
-- it loaded - a mod's package.loaded is not the engine's) with its MODERN HIGH-RES UI option on.
-- Asked once a frame.
--
-- A screen it claims stays stepped aside until that kind of pass stops coming (a frame without
-- it): OmniUI's message box over an evolution comes and goes, and the screen would otherwise
-- switch between filled and not with it.

return function(mod)
  local Omni = {}
  local ID = "omni_ui"
  local MODULE = "mods.omni_ui.core.ModernOverlay"

  local frame = 1
  local askedAt, kindAt = 0, nil
  -- [pass] = the last frame it was asked, and whether it was stepped aside then
  local lastAsked, held = {}, {}

  local function overlayOn()
    local ok, v = pcall(function()
      local o = mod.game and mod.game.mods and mod.game.mods.modOptions
      return o and o[ID] and o[ID].overlay
    end)
    -- (its default is on: no stored value reads as on)
    return not (ok and v == false)
  end

  local function installed()
    local ok, found = pcall(function() return mod:find(ID) end)
    return ok and found ~= nil
  end

  --- OmniUI's screen kind this frame ("battle", "party", "dialogue", ...), or nil when it draws
  --- nothing of its own (not installed, its overlay off, or it yields the screen).
  function Omni.kind()
    if askedAt == frame then return kindAt end
    askedAt, kindAt = frame, nil
    if not (installed() and overlayOn()) then return nil end
    -- (OmniUI running has loaded it: require hands back its own copy)
    local okR, O = pcall(require, MODULE)
    if not (okR and type(O) == "table" and type(O.getActiveScreen) == "function") then return nil end
    local game = mod.game or O.currentGame
    local ok, kind = pcall(O.getActiveScreen, game)
    if ok and type(kind) == "string" then kindAt = kind end
    return kindAt
  end

  --- Does WoobleView step aside from this pass this frame? Never the field's.
  function Omni.aside(pass)
    if pass == "field" or pass == nil then return false end
    if lastAsked[pass] == frame then return held[pass] end
    local was = lastAsked[pass] == frame - 1 and held[pass]
    lastAsked[pass] = frame
    held[pass] = Omni.kind() ~= nil or was == true
    return held[pass]
  end

  --- A frame is over (hd.endFrame).
  function Omni.tick()
    frame = frame + 1
  end

  return Omni
end
