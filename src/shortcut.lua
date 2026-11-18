-- A WOOBLEVIEW row on the game's own OPTION screen: A opens this mod's settings page in the
-- Mod Manager (OPTIONS -> MODS -> WoobleView), and B there comes straight back to OPTION.
-- The settings stay on the Manager's page (options.lua is still the one schema); this is a
-- shortcut to it, the same as WoobleSpawns' row.
--
-- ui.options.rows is shared by every generation (Gen 1 OptionsMenu, Gen 2 OptionsMenu, Gen 3
-- option_rows bridging); a row's activate gets the game. Gen 1/2 open the Manager with
-- Screens.push(game, "ManagerState"), Gen 3 with its own overlay (src/ui/game3/mod_manager.lua);
-- both run the same ManagerState, whose openOptions is what the Manager's SETTINGS entry calls.
-- Any failure leaves the Manager on its list, or does nothing.
return function(deps)
  local mod, generation = deps.mod, deps.generation
  local S = {}

  local function engine(name)
    local ok, module = pcall(require, name)
    return ok and module or nil
  end

  -- Jump an opened ManagerState to this mod's settings page, with nothing under it: B (goBack
  -- with an empty history) closes the Manager.
  function S.focus(state)
    if type(state) ~= "table" or type(state.openOptions) ~= "function" then return false end
    local m = state.byId and state.byId[mod.id]
    if not m then return false end
    state.currentMod = m
    state:openOptions(m)
    if state.screen ~= "options" then return false end
    state.backStack = {}
    return true
  end

  function S.open(game)
    if not game then return false end
    local ok, result = pcall(function()
      if generation() == 3 then
        local Manager = engine("src.ui.game3.mod_manager")
        if not Manager then return false end
        Manager.show({ game = game })
        return S.focus(Manager._mgr)
      end
      local Screens = engine("src.ui.Screens")
      if not Screens then return false end
      return S.focus(Screens.push(game, "ManagerState"))
    end)
    if not ok then mod.log:warn("OPTION shortcut: %s", tostring(result)) end
    return ok and result == true
  end

  function S.row()
    return {
      id = mod.id .. ":settings",
      label = "WOOBLEVIEW",
      value = function() return "OPEN" end,
      activate = function(game) S.open(game) end,
    }
  end

  function S.install()
    mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
      local out = nextFn(game, rows)
      if type(out) ~= "table" then return out end
      out[#out + 1] = S.row()
      return out
    end)
  end

  return S
end
