-- Driver (dev only): writes src/scene/games/emerald_prints.lua, the prints of Emerald's maps
-- (src/scene/prints.lua) that Ruby and Sapphire are checked against: every layout's 8x8 blocks
-- under each of its names, and every reference rectangle a building model reads (each spec built
-- afresh, the prints checker recording). Run in Emerald, from the engine root:
--   OUT=<file> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/emerald_prints.lua love .
-- (OUT defaults to the mod's own src/scene/games/emerald_prints.lua)

local function body(game, log)
  local U = require("tests.drivers.util")
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._scenePrints and hd._layoutPrints) then log("FAIL exports missing"); return end
  local C = hd._scenePrints()
  if not C then log("FAIL no prints checker"); return end
  local layouts, aliases = hd._layoutPrints()
  if not layouts then log("FAIL no layouts"); return end
  C.record(true)
  local built = 0
  for _, name in ipairs(hd._sceneSpecNames()) do
    if hd._sceneModel(name) then built = built + 1 end
  end
  local rects = C.recorded
  C.record(false)
  local function sorted(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
  end
  local out = { "-- Prints of Emerald's maps (src/scene/prints.lua): Ruby and Sapphire hold Emerald's models, rooms",
                "-- and hand marks where they draw the same. Written by tests/drivers/emerald_prints.lua; do not edit.",
                "return {", ("  chunk = %d,"):format(8), "  layouts = {" }
  local nl, nr = 0, 0
  for _, k in ipairs(sorted(layouts)) do
    out[#out + 1] = ("    [%q] = %q,"):format(k, layouts[k])
    nl = nl + 1
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "  rects = {"
  for _, k in ipairs(sorted(rects)) do
    out[#out + 1] = ("    [%q] = %q,"):format(k, rects[k])
    nr = nr + 1
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "  aliases = {"
  for _, k in ipairs(sorted(aliases or {})) do
    local q = {}
    for _, n in ipairs(aliases[k]) do q[#q + 1] = ("%q"):format(n) end
    out[#out + 1] = ("    [%q] = { %s },"):format(k, table.concat(q, ", "))
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  local path = os.getenv("OUT") or "mods/gen3-hd-sprites/src/scene/games/emerald_prints.lua"
  local f = io.open(path, "wb")
  if not f then log("FAIL cannot write " .. path); return end
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  log(("%d layout names, %d reference rectangles (%d models built) -> %s"):format(nl, nr, built, path))
end

return function(game)
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(parts, " "))
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  love.event.quit()
end
