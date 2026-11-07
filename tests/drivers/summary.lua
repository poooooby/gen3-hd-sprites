-- Driver: the Pokemon summary screen. Boots a game, gives the party a few Pokemon, opens the
-- summary on each and screenshots every page, in each window size. Run from the engine root:
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/summary.lua love .
-- HD_SIZES=WxH,WxH,... (default 1920x1080,540x1200).

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_summary"
  local sizes = {}
  for w, h in (os.getenv("HD_SIZES") or "1920x1080,540x1200"):gmatch("(%d+)x(%d+)") do
    sizes[#sizes + 1] = { tonumber(w), tonumber(h) }
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(sizes[1][1], sizes[1][2], { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local version = os.getenv("POKEPORT_VERSION") or "emerald"
  local C = require("src.core.game3.constants").of(version)
  local s = Runtime.getSession()
  for _, name in ipairs({ "SPECIES_WAILORD", "SPECIES_TORCHIC", "SPECIES_RAYQUAZA" }) do
    pcall(Party.giveMon, s, C:require("species", name), 30)
  end
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not hd then log("FAIL gen3-hd-sprites exports missing"); return end
  for _, id in ipairs({ "play_nav", "ds_touch" }) do
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id].display = "off"
  end
  local SummaryMenu = require("src.ui.game3.summary_menu")
  for i, sz in ipairs(sizes) do
    if i > 1 then
      love.window.setMode(sz[1], sz[2], { resizable = true, highdpi = true })
      U.wait(10)
    end
    local name = sz[1] .. "x" .. sz[2]
    for slot = 1, math.min(3, #s.party) do
      local before = hd.stats().dexPasses or 0
      local fp = require("src.core.game3.pokemon").monFrontPic(s.party[slot])
      log(("  slot %d pic tagged %s"):format(slot, tostring(fp and hd.tagOf(fp.image) ~= nil)))
      SummaryMenu.openMenu(s.party, slot)
      U.wait(90)
      U.shot(game, ("%s/%s_mon%d_info.png"):format(dir, name, slot))
      U.tap(game, "right")
      U.wait(40)
      U.shot(game, ("%s/%s_mon%d_skills.png"):format(dir, name, slot))
      local st = hd.stats()
      log(("%s mon %d: open %s dex passes %d -> %d composites %d flattened %d failed %s"):format(name, slot,
        tostring(SummaryMenu.isOpen()), before, st.dexPasses or 0, st.composites or 0, st.flattened or 0,
        tostring(st.failed)))
      SummaryMenu.close()
      U.wait(30)
    end
  end
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/hd_summary"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
