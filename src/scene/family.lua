-- The tileset family of the game being played, for the scene's reads of its maps (Battle Scene).
-- Ruby, Sapphire and Emerald draw with one family, FireRed and LeafGreen with another, and the two
-- cut their tilesets differently (pokeemerald/include/fieldmap.h and pokefirered/include/fieldmap.h,
-- NUM_*_IN_PRIMARY; pokefirered/include/global.fieldmap.h, the 32-bit metatile attributes):
--
--                        RSE        FRLG
--   primary metatiles    512        640      (a metatile id past them is the secondary's)
--   primary tiles        512        640      (likewise an 8x8 tile id)
--   primary palettes     6          7        (a palette id past them is the secondary's)
--   attribute            u16        u32      (a metatile's behaviour and layer type)
--   behaviour            bits 0-7   bits 0-8
--   layer type           bits 12-15 bits 29-30
--
-- A family:  F.name ("rse" / "frlg"), F.primaryMetatiles, F.primaryTiles, F.primaryPals,
-- F.attrBytes, F.behaviour(attr), F.layer(attr), F.attribute(bytes, i) (the i-th (0-based)
-- attribute of an attributes table, or 0 past it), F.split(m) (tileset 0 primary / 1 secondary and
-- the id within it).
--
--   Family.of(gameId)   the family of a game id ("emerald", "firered", ...; RSE for anything else)
--   Family.game()       the id of the game being played (the engine's), or nil
--   Family.active()     Family.of(Family.game())
--
-- Plain Lua: it reads the engine (src.core.GameVersion) when there is one and is RSE without it, so
-- the solver's tests run as before.

local floor = math.floor

local Family = {}

local function u16(s, at)
  local a, b = s:byte(at + 1, at + 2)
  if not b then return 0 end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return 0 end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- the engine's names for FireRed's tileset pairs that name no tilesets ("pallet_outdoor": General and
-- Pallet Town's), or {}
local namedPairs
local function frlgPairs()
  if namedPairs then return namedPairs end
  local ok, V = pcall(require, "src.import.gba.versions_frlg")
  namedPairs = ok and type(V) == "table" and type(V.TILESET_PAIRS) == "table" and V.TILESET_PAIRS or {}
  return namedPairs
end

local function make(t)
  local P = t.primaryMetatiles
  function t.split(m)
    if m < P then return 0, m end
    return 1, m - P
  end
  --- A tileset pair's two tilesets' names ("general__petalburg": "general", "petalburg"), read with
  --- `pattern` (the caller's own; default "^([^_]+)__(.+)$"). FireRed's are its family's own
  --- (t.namespace before each: "fr:general"), so that nothing read off Hoenn's tilesets, which are
  --- named alike, is ever taken for them; a pair the engine names otherwise ("pallet_outdoor") is
  --- looked up.
  function t.pairNames(pair, pattern)
    pair = tostring(pair or "")
    local p, s = pair:match(pattern or "^([^_]+)__(.+)$")
    if t.namespace then
      if not p then
        local row = frlgPairs()[pair]
        if type(row) == "table" then p, s = row.primary, row.secondary end
      end
      if p then p, s = t.namespace .. p, t.namespace .. tostring(s) end
    end
    return p, s
  end
  return t
end

-- (F.prefixes: the engine's names for the game's maps and baked layouts start with one of them;
-- FireRed's Sevii Islands keep their own)
Family.RSE = make({
  name = "rse", primaryMetatiles = 512, primaryTiles = 512, primaryPals = 6, attrBytes = 2,
  prefixes = { "EM_" },
  behaviour = function(a) return a % 256 end,
  layer = function(a) return floor(a / 4096) % 16 end,
  attribute = function(s, i)
    if not s or (i + 1) * 2 > #s then return 0 end
    return u16(s, i * 2)
  end,
})

Family.FRLG = make({
  name = "frlg", primaryMetatiles = 640, primaryTiles = 640, primaryPals = 7, attrBytes = 4,
  prefixes = { "FR_", "SEVII_" }, namespace = "fr:",
  behaviour = function(a) return a % 512 end,
  layer = function(a) return floor(a / 536870912) % 4 end,
  attribute = function(s, i)
    if not s or (i + 1) * 4 > #s then return 0 end
    return u32(s, i * 4)
  end,
})

Family.GAMES = {
  emerald = Family.RSE, ruby = Family.RSE, sapphire = Family.RSE,
  firered = Family.FRLG, leafgreen = Family.FRLG,
}

function Family.of(gameId)
  return Family.GAMES[gameId] or Family.RSE
end

function Family.game()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not (ok and type(GV) == "table" and GV.get) then return nil end
  local okG, id = pcall(GV.get)
  return okG and type(id) == "string" and id or nil
end

function Family.active()
  return Family.of(Family.game())
end

--- The prefix a name of the family's starts with ("FR_"), or nil.
function Family.prefixOf(F, name)
  for _, p in ipairs(F.prefixes) do
    if name:sub(1, #p) == p then return p end
  end
  return nil
end

--- A map's or layout's name without its prefix, upper case, letters and digits only: the engine's
--- own match between its baked names ("FR_ROUTE_2_VIRIDIAN_FOREST_NORTH_ENTRANCE") and pret's
--- ("Route2_ViridianForest_NorthEntrance"; src/core/game3/rse Rse.mapGroupNum).
function Family.normal(F, name)
  local p = Family.prefixOf(F, name)
  local s = p and name:sub(#p + 1) or name
  return (s:upper():gsub("[^A-Z0-9]", ""))
end

--- Whether a game is Kanto's (FireRed / LeafGreen).
function Family.kanto(gameId)
  return Family.of(gameId) == Family.FRLG
end

return Family
