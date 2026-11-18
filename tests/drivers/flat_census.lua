-- Every cell of the game's layouts that nothing stands (src/scene/init.lua Scene._layoutCover):
-- drawing on its upper layer or blocking the player, yet no building, room, prop, bridge,
-- component or tree of it. Writes one line a cell to SHOT_DIR/flat.tsv: layout, x, y, metatile,
-- upper-layer pixels, blocked, raised (the relief lifts or slopes it). And one line a layout to
-- SHOT_DIR/flat_layouts.tsv: layout, size, the cells that draw on their upper layer or block,
-- modelled, trees, raised, flat (none of those), the flat share, whether it has a relief.
-- FLAT_IDS: a file of the layout ids to read (one a line; default every layout). FLAT_RELIEF=1:
-- the relief built first, so the cells it raises are told apart.
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
    if env("FLAT_RELIEF") and hd._reliefStep then
      local st, why
      for _ = 1, 200000 do
        st, why = hd._reliefStep()
        if st ~= "running" and st ~= "idle" then break end
        U.wait(1)
      end
      log("relief: " .. tostring(st) .. " " .. tostring(why))
    end
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
    local dir = env("SHOT_DIR") or "."
    local out = io.open(dir .. "/flat.tsv", "wb")
    local sum = io.open(dir .. "/flat_layouts.tsv", "wb")
    sum:write("layout\tw\th\tcells\tmodelled\ttrees\traised\tflat\tflat_share\trelief\n")
    local cells = 0
    for _, id in ipairs(ids) do
      local L = ctx.inp.layouts[id]
      local okC, list, why, tally = pcall(hd._layoutCover, L.name)
      if okC and list then
        for _, c in ipairs(list) do
          out:write(("%s\t%d\t%d\t%d\t%d\t%s\t%s\n"):format(L.name, c[1], c[2], c[3], c[4], c[5] and "1" or "0",
            c[6] and "1" or "0"))
          cells = cells + 1
        end
        if tally then
          local flat = tally.cells - tally.modelled - tally.trees - tally.raised
          sum:write(("%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%.3f\t%s\n"):format(L.name, L.w or 0, L.h or 0, tally.cells,
            tally.modelled, tally.trees, tally.raised, flat, tally.cells > 0 and flat / tally.cells or 0,
            tally.relief and "1" or "0"))
        end
      else
        log(("%s: %s"):format(L.name, tostring(okC and why or list)))
      end
      U.wait(1)
    end
    out:close()
    sum:close()
    log(("%d layouts, %d cells"):format(#ids, cells))
  end, debug.traceback)
  if not ok then print("[driver]", "DRIVER ERROR " .. tostring(err)) end
  love.event.quit()
end
