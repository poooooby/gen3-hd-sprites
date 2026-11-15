-- Every cell of the game's layouts that nothing stands (src/scene/init.lua Scene._layoutCover):
-- drawing on its upper layer or blocking the player, yet no building, room, prop, bridge,
-- component or tree of it. Writes one line a cell to SHOT_DIR/flat.tsv: layout, x, y, metatile,
-- upper-layer pixels, blocked. FLAT_IDS: a file of the layout ids to read (one a line; default
-- every layout).
--   POKEPORT_GAME=firered POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/flat_census.lua
local MOD = "mods/gen3-hd-sprites/"
local function env(name)
  local v = os.getenv(name)
  if v == nil or v == "" then return nil end
  return v
end

return function(game)
  local U = require("tests.drivers.util")
  local log = function(s) print("[driver]", s) end
  local ok, err = xpcall(function()
    U.wait(2)
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
    U.wait(30)
    local hd = game.mods and game.mods.exports and game.mods.exports["gen3-hd-sprites"]
    if not (hd and hd._layoutCover) then log("FAIL gen3-hd-sprites exports missing"); return end
    local gameName = env("POKEPORT_GAME") or "emerald"
    local Check = dofile(MOD .. "tests/model_check.lua")
    local ctx = Check.layoutsOf(gameName, MOD)
    if not ctx then log("FAIL no layouts"); return end
    local only
    local f = env("FLAT_IDS") and io.open(env("FLAT_IDS"), "rb")
    if f then
      only = {}
      for line in f:lines() do local n = tonumber(line); if n then only[n] = true end end
      f:close()
    end
    local ids = {}
    for id in pairs(ctx.inp.layouts) do if not only or only[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    local out = io.open((env("SHOT_DIR") or ".") .. "/flat.tsv", "wb")
    local cells = 0
    for _, id in ipairs(ids) do
      local L = ctx.inp.layouts[id]
      local okC, list, why = pcall(hd._layoutCover, L.name)
      if okC and list then
        for _, c in ipairs(list) do
          out:write(("%s\t%d\t%d\t%d\t%d\t%s\n"):format(L.name, c[1], c[2], c[3], c[4], c[5] and "1" or "0"))
          cells = cells + 1
        end
      else
        log(("%s: %s"):format(L.name, tostring(okC and why or list)))
      end
      U.wait(1)
    end
    out:close()
    log(("%d layouts, %d cells"):format(#ids, cells))
  end, debug.traceback)
  if not ok then print("[driver]", "DRIVER ERROR " .. tostring(err)) end
  love.event.quit()
end
