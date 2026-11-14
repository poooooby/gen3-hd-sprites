-- Tuning for the battle scene's models (Battle Scene: Overworld), set by eye in the Scene Workshop
-- (tests/drivers/workshop.lua) and kept as data: numbers and map cells, never anything of the
-- cartridge's. Each game's values live in src/scene/games/<game>_tune.lua (FireRed's serve
-- LeafGreen too: the same maps), written by the workshop.
--
--   * a group's settings (Tune.DEFS: what each is, its default, its range) hold for every model of
--     that kind - the general rule;
--   * a mark holds for one cell of one map ("FR_ROUTE2:3:14"), over its group's settings: a hand
--     mark, for the one tree that needs it.
--
-- The defaults are the models' own constants (Emerald 3DS's for Hoenn's trees), so a game with no
-- tune file draws exactly as before.

local Tune = {}

-- each group's settings, in the workshop's order: key, label, default, min, max, step, unit
Tune.DEFS = {
  trees = {
    { key = "lean", label = "Crown lean", default = 50, min = 15, max = 90, step = 1, unit = "deg",
      help = "how far the crown card stands up from the ground (90: upright)" },
    { key = "height", label = "Crown height", default = 1, min = 0.5, max = 2, step = 0.05, unit = "x",
      help = "the crown card's length, as a share of the drawing's" },
    { key = "foot", label = "Foot", default = nil, min = -0.5, max = 1.5, step = 0.05, unit = "tiles",
      help = "how far south of its trunk row's top edge the crown's foot stands (each tree art's own by default)" },
    { key = "sink", label = "Sink", default = 0.10, min = -0.5, max = 0.5, step = 0.02, unit = "tiles",
      help = "how far the crown's foot sinks into the ground" },
    -- (Kanto's trees stand as models, exact at 45 degrees whatever these are: they shape the tree
    -- seen from elsewhere; the whole game's only, not a tree's mark)
    { key = "depth", label = "Kanto crown depth", default = 1, min = 0.25, max = 2, step = 0.05, unit = "x",
      help = "a Kanto tree's crown, front to back, as a share of its own reading" },
    { key = "stand", label = "Kanto stand", default = 0, min = -8, max = 8, step = 1, unit = "px",
      help = "how far south of its own reading a Kanto tree stands (its trunk and the crown's axis)" },
  },
}
-- the keys a mark may hold besides a group's settings
Tune.MARK_FLAGS = { hide = true }

-- the game's tune file each game reads
Tune.FILE_OF = { emerald = "emerald", ruby = "emerald", sapphire = "emerald", firered = "firered", leafgreen = "firered" }

-- [file] = { groups = { [group] = { [key] = value } }, marks = { ["MAP:x:y"] = { [group] = {...}, hide } } }
Tune.data = {}

local function fileOf(game) return Tune.FILE_OF[tostring(game)] or tostring(game) end
Tune.fileOf = fileOf

--- A tune file's table (the chunk's return), taken for a game's file.
function Tune.put(file, t)
  if type(t) ~= "table" then return end
  Tune.data[file] = { groups = type(t.groups) == "table" and t.groups or {},
                      marks = type(t.marks) == "table" and t.marks or {} }
end

local function entry(game)
  local f = fileOf(game)
  local d = Tune.data[f]
  if not d then d = { groups = {}, marks = {} }; Tune.data[f] = d end
  return d
end

local function def(group, key)
  for _, d in ipairs(Tune.DEFS[group] or {}) do if d.key == key then return d end end
  return nil
end
Tune.def = def

--- A group's settings for a game: { [key] = value }, each the file's or its default (nil where
--- the default is the model's own).
function Tune.group(game, group)
  local d = Tune.data[fileOf(game)]
  local set = d and d.groups[group] or nil
  local out = {}
  for _, s in ipairs(Tune.DEFS[group] or {}) do
    local v = set and set[s.key]
    if v == nil then v = s.default end
    out[s.key] = v
  end
  return out
end

--- Whether a game has any marks (a scene skips looking them up without).
function Tune.hasMarks(game)
  local d = Tune.data[fileOf(game)]
  return d ~= nil and next(d.marks) ~= nil
end

function Tune.markKey(mapId, x, y) return ("%s:%d:%d"):format(tostring(mapId), x, y) end

--- One cell's mark, or nil: { [group] = { [key] = value }, hide = true? }.
function Tune.markAt(game, mapId, x, y)
  local d = Tune.data[fileOf(game)]
  return d and d.marks[Tune.markKey(mapId, x, y)] or nil
end

local function clamp(d, v)
  if d.min and v < d.min then v = d.min end
  if d.max and v > d.max then v = d.max end
  -- (kept to the step's places: the file stays readable)
  local places = 10 ^ 4
  return math.floor(v * places + 0.5) / places
end

--- Set a group's setting (nil: back to its default).
function Tune.set(game, group, key, v)
  local d = def(group, key)
  if not d then return end
  local e = entry(game)
  e.groups[group] = e.groups[group] or {}
  e.groups[group][key] = v ~= nil and clamp(d, v) or nil
  if next(e.groups[group]) == nil then e.groups[group] = nil end
end

--- Set one cell's mark: a group's setting (key, value), or a flag (hide). nil clears it.
function Tune.setMark(game, mapId, x, y, group, key, v)
  local e = entry(game)
  local k = Tune.markKey(mapId, x, y)
  local m = e.marks[k] or {}
  if Tune.MARK_FLAGS[key] then
    m[key] = v and true or nil
  else
    local d = def(group, key)
    if not d then return end
    m[group] = m[group] or {}
    m[group][key] = v ~= nil and clamp(d, v) or nil
    if next(m[group]) == nil then m[group] = nil end
  end
  e.marks[k] = next(m) and m or nil
end

-- a value as Lua source
local function lit(v)
  if type(v) == "number" then
    if v == math.floor(v) then return ("%d"):format(v) end
    return (("%.4f"):format(v):gsub("0+$", ""))
  elseif type(v) == "boolean" then return tostring(v)
  else return ("%q"):format(tostring(v)) end
end
local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  return ks
end
local function tableSrc(t)
  local parts = {}
  for _, k in ipairs(sortedKeys(t)) do
    local v = t[k]
    parts[#parts + 1] = ("%s = %s"):format(k, type(v) == "table" and tableSrc(v) or lit(v))
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

--- A game's tune file, as Lua source.
function Tune.source(game)
  local d = Tune.data[fileOf(game)] or { groups = {}, marks = {} }
  local out = {
    "-- The battle scene's tuning for this game (src/scene/tune.lua), set by eye in the Scene Workshop",
    "-- (tests/drivers/workshop.lua). Numbers and map cells only. Written by the workshop: edits by",
    "-- hand are kept, comments are not.",
    "return {",
    "  groups = {",
  }
  for _, g in ipairs(sortedKeys(d.groups)) do
    out[#out + 1] = ("    %s = %s,"):format(g, tableSrc(d.groups[g]))
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "  marks = {"
  for _, k in ipairs(sortedKeys(d.marks)) do
    out[#out + 1] = ("    [%q] = %s,"):format(k, tableSrc(d.marks[k]))
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

return Tune
