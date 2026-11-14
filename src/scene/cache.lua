-- Where the engine keeps its cache of the player's cartridge, for the scene's reads (the maps, their
-- layouts and tilesets: Battle Scene builds its world from them at runtime).
--
-- The roots come from the engine's own constants (src.core.game3.cache_paths: CACHE_ROOT and
-- NATIVE_ROOT, which follow the cache when it moves), never spelt out here. WoobleView ships none of
-- the cache's data: it reads the player's own, through engine_internals, as the engine does.
--
--   Cache.root()            the cache's root, or nil (no engine module)
--   Cache.native()          its native tree (the engine's baked layouts and tile banks), or nil
--   Cache.path(rel)         root() .. "/" .. rel, or nil
--   Cache.read(rel)         the bytes at path(rel) in the engine's cache (Dataset.cache()), or nil
--   Cache.readNative(rel)   the bytes at native() .. "/" .. rel, or nil

local Cache = {}

local function req(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == "table" and m or nil
end

local function paths() return req("src.core.game3.cache_paths") end

function Cache.root()
  local P = paths()
  local r = P and P.CACHE_ROOT
  return type(r) == "string" and r ~= "" and r or nil
end

function Cache.native()
  local P = paths()
  local r = P and P.NATIVE_ROOT
  if type(r) == "string" and r ~= "" then return r end
  local root = Cache.root()
  return root and root .. "/native" or nil
end

function Cache.path(rel)
  local root = Cache.root()
  return root and rel and root .. "/" .. rel or nil
end

local function store()
  local Dataset = req("src.core.game3.dataset")
  if not (Dataset and Dataset.cache) then return nil end
  local ok, c = pcall(Dataset.cache)
  return ok and c or nil
end

function Cache.read(rel)
  local c, p = store(), Cache.path(rel)
  if not (c and p) then return nil end
  local ok, bytes = pcall(c.read, c, p)
  return ok and bytes or nil
end

function Cache.readNative(rel)
  local c, root = store(), Cache.native()
  if not (c and root and rel) then return nil end
  local ok, bytes = pcall(c.read, c, root .. "/" .. rel)
  return ok and bytes or nil
end

return Cache
