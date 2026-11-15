-- Fingerprints of Emerald's maps, for Battle Scene in Ruby and Sapphire.
--
-- Ruby and Sapphire draw most of Hoenn as Emerald does, but not all of it: Emerald redrew its gyms,
-- reshaped parts of routes and towns (Route 111's desert, Mossdeep's shore, the Safari Zone's new
-- corners) and added buildings (Slateport's Battle Tent). Emerald's own data - Emerald 3DS's
-- building specs, rooms and hand marks, read off Emerald's drawing - holds in Ruby and Sapphire only
-- where their maps draw the same metatiles. Fingerprints, not the maps themselves, are kept of
-- Emerald's (src/scene/games/emerald_prints.lua, written by tests/drivers/emerald_prints.lua):
--
--   layouts = { LAYOUT_X = "WxH:" .. one 8-hex print per CHUNK x CHUNK block, row by row }
--   rects   = { ["LAYOUT_X@x,y,w,h"] = 8-hex print of a model's reference rectangle }
--
-- A print is FNV-1a (32 bits) over the metatile ids (each its u16, little end) read row by row.
--
--   Prints.fnv(s, h)                 FNV-1a over a string (continuing h)
--   Prints.ids(list, n)              the print of ids list[1..n]
--   Prints.chunks(w, h, at)          a layout's prints: "WxH:" .. hexes, at(x, y) -> metatile id
--   Prints.rectKey(layout, rect)     "LAYOUT_X@x,y,w,h"
--   Prints.checker(T)                a checker over Emerald's table T (nil: everything holds):
--     C.rect(layout, rect, ids)      whether a reference rectangle draws Emerald's metatiles
--     C.layout(name, w, h, at)       its record: { same (the whole layout), size (the same size),
--                                    ok(x, y) (the cell's block is Emerald's), share (of its blocks,
--                                    the part Emerald's: 0..1) }, cached by name
--     C.record(on)                   (dev) record every rect asked about instead: C.recorded
--
-- Plain Lua (LuaJIT's bit library, or plain arithmetic without it).

local Prints = {}

Prints.CHUNK = 8

local bxor = bit and bit.bxor
if not bxor then
  bxor = function(a, b)
    local r, p = 0, 1
    while a > 0 or b > 0 do
      local x, y = a % 2, b % 2
      if x ~= y then r = r + p end
      a, b, p = (a - x) / 2, (b - y) / 2, p * 2
    end
    return r
  end
end

function Prints.fnv(s, h)
  h = h or 2166136261
  for i = 1, #s do
    h = bxor(h, s:byte(i))
    h = (h * 16777619) % 4294967296
  end
  return h
end

local char = string.char
local function u16(m) return char(m % 256, math.floor(m / 256) % 256) end

function Prints.ids(list, n)
  local parts = {}
  for i = 1, n or #list do parts[i] = u16((list[i] or 0) % 1024) end
  return ("%08x"):format(Prints.fnv(table.concat(parts)))
end

function Prints.chunks(w, h, at)
  local C = Prints.CHUNK
  local out = { ("%dx%d:"):format(w, h) }
  for cy = 0, math.ceil(h / C) - 1 do
    for cx = 0, math.ceil(w / C) - 1 do
      local parts = {}
      for y = cy * C, math.min(h, cy * C + C) - 1 do
        for x = cx * C, math.min(w, cx * C + C) - 1 do parts[#parts + 1] = u16((at(x, y) or 0) % 1024) end
      end
      out[#out + 1] = ("%08x"):format(Prints.fnv(table.concat(parts)))
    end
  end
  return table.concat(out)
end

function Prints.rectKey(layout, rect)
  return ("%s@%d,%d,%d,%d"):format(tostring(layout), rect[1], rect[2], rect[3], rect[4])
end

local ALL = { same = true, size = true, ok = function() return true end }

function Prints.checker(T)
  local C = { recorded = nil }
  local byName = {}
  function C.record(on) C.recorded = on and {} or nil end
  function C.rect(layout, rect, ids)
    if C.recorded then
      C.recorded[Prints.rectKey(layout, rect)] = Prints.ids(ids, rect[3] * rect[4])
      return true
    end
    if not T then return true end
    local want = T.rects and T.rects[Prints.rectKey(layout, rect)]
    return want ~= nil and want == Prints.ids(ids, rect[3] * rect[4])
  end
  function C.layout(name, w, h, at)
    if not T then return ALL end
    local r = byName[name]
    if r then return r end
    local want = T.layouts and T.layouts[name]
    local mine = Prints.chunks(w, h, at)
    local size = want ~= nil and want:match("^[^:]*:") == mine:match("^[^:]*:")
    local N = Prints.CHUNK
    local cols = math.ceil(w / N)
    local okChunk, n, alike = {}, 0, 0
    if size then
      local head = #mine:match("^[^:]*:")
      for k = 0, (#mine - head) / 8 - 1 do
        local a = head + k * 8 + 1
        okChunk[k] = mine:sub(a, a + 7) == want:sub(a, a + 7)
        n = n + 1
        if okChunk[k] then alike = alike + 1 end
      end
    end
    r = { same = size and mine == want, size = size, share = n > 0 and alike / n or 0,
          ok = function(x, y)
            if not size or x < 0 or y < 0 or x >= w or y >= h then return false end
            return okChunk[math.floor(y / N) * cols + math.floor(x / N)] == true
          end }
    byName[name] = r
    return r
  end
  return C
end

return Prints
