-- The battle scene's cells (Battle Scene: Overworld): the map around where the battle started,
-- read once per battle into a window of cells, each with its kind and, for what stands up, its
-- place in an upright run.
--
-- Kinds: "floor", "grass" (tall or long grass), "sand" (sand, deep sand), "water" (surfable or deep
-- water), "blocked" (a wall, a tree, a house, a fence, a rock: anything that blocks a step and is
-- not water) and "void" (outside every map, indoors: black on the cart).
--
-- What stands up: nothing without a model, as in Emerald 3DS - a rock, a cliff, a sign or a house
-- no model rebuilds lies flat as the game draws it - but trees (Kanto's: Hoenn's are models,
-- src/scene/trees.lua). The overworld's art is drawn in an oblique view, a crown above its trunk,
-- so each column's run of blocked cells drawn as leaves (env.stands), read from the south up,
-- stands as a stack of cards on the run's southern edge: the run's first cell at height 0, the
-- next one north at height 1, and so on (at most RUN_MAX).
--
-- The game's data comes in through `env` (src/scene/init.lua reads the engine), so this file
-- is plain Lua:
--   env.mid(cx, cy)   -> mid, pair (the metatile and its tileset pair)
--   env.cell(cx, cy)  -> coll, behavior of the cell in whichever map holds it, or nil outside
--                         every map
--   env.isWall(coll), env.isWater(coll), env.isSurfable(behavior)
--   env.indoor        the battle's map is indoors (or underground): outside the maps is void
--   env.stands(mid, pair)   whether a metatile is a tree's (leaves, a crown over the player); without
--                     it every blocked run stands

local Cells = {}

Cells.RUN_MAX = 6

-- pokefirered/pokeemerald metatile behaviours (include/constants/metatile_behaviors.h)
local MB_TALL_GRASS, MB_LONG_GRASS = 0x02, 0x03
local MB_DEEP_SAND = 0x06
local MB_FAST_WATER, MB_DEEP_WATER, MB_OCEAN_WATER = 0x11, 0x12, 0x15
local MB_SAND = 0x21
local MB_CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1    -- (pokefirered only)

--- The kind of one cell.
function Cells.kindOf(env, coll, beh)
  -- (past every map: a room's black filler, or the border - a cave's too)
  if coll == nil then
    local walled = env.walled
    if walled == nil then walled = env.indoor end
    return walled and "void" or "blocked"
  end
  local b = tonumber(beh)
  -- (Emerald 3DS's KindOf: the game's IsTallGrass or IsLongGrass - Kanto's tall grass is also
  -- the Cycling Road's, pokefirered's own test; 0xD1 is Hoenn's bumpy slope - then
  -- IsSandOrDeepSand; shallow water is plain ground)
  if b == MB_TALL_GRASS or b == MB_LONG_GRASS or (env.kanto and b == MB_CYCLING_ROAD_PULL_DOWN_GRASS) then
    return "grass"
  end
  if b == MB_SAND or b == MB_DEEP_SAND then return "sand" end
  if (env.isWater and env.isWater(coll)) or (b and env.isSurfable and env.isSurfable(b))
      or (b and ((b >= MB_FAST_WATER and b <= MB_DEEP_WATER) or b == MB_OCEAN_WATER)) then
    return "water"
  end
  if env.isWall and env.isWall(coll) then return "blocked" end
  return "floor"
end

--- The window x0..x0+w-1, y0..y0+h-1 (map cells). Returns a grid:
---   grid.x0, grid.y0, grid.w, grid.h
---   grid.at(cx, cy) -> the cell, or nil outside the window
--- each cell: { cx, cy, mid, pair, coll, beh, kind, up (height in its upright run, or nil), base
--- (the run's southern row) }
function Cells.build(env, x0, y0, w, h)
  local rows = {}
  for j = 0, h - 1 do
    local cy = y0 + j
    local row = {}
    for i = 0, w - 1 do
      local cx = x0 + i
      local mid, pair = env.mid(cx, cy)
      local coll, beh = env.cell(cx, cy)
      row[i] = { cx = cx, cy = cy, mid = mid, pair = pair, coll = coll, beh = beh,
                 kind = Cells.kindOf(env, coll, beh) }
    end
    rows[j] = row
  end
  -- the upright runs, column by column from the south: only a run with a cell env.stands stands
  for i = 0, w - 1 do
    local j = h - 1
    while j >= 0 do
      local c = rows[j][i]
      if c.kind == "blocked" then
        local base = c.cy
        local n = 0
        local run, stands = {}, not env.stands
        while j >= 0 and rows[j][i].kind == "blocked" and n < Cells.RUN_MAX do
          local r = rows[j][i]
          run[#run + 1] = r
          r.up, r.base = n, base
          if not stands and env.stands(r.mid, r.pair) then stands = true end
          n = n + 1
          j = j - 1
        end
        if not stands then
          for _, r in ipairs(run) do r.up, r.base = nil, nil end
        end
      else
        j = j - 1
      end
    end
  end
  local grid = { x0 = x0, y0 = y0, w = w, h = h, rows = rows }
  function grid.at(cx, cy)
    local row = rows[cy - y0]
    return row and row[cx - x0] or nil
  end
  return grid
end

return Cells
