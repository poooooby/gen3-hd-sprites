-- Takes FireRed 3DS's relief out of its pak (Emerald 3DS's pak format, "EM3DPAK": the VXL4
-- section) into assets/scene/firered_relief.bin, the levels the FireRed relief build lays over its
-- own wherever they give a layout one (src/scene/relief_run.lua Run.borrow).
--   luajit tools/fr3ds_relief.lua <firered3ds.pak> [out]
local path, out = arg[1], arg[2] or "assets/scene/firered_relief.bin"
assert(path, "usage: luajit tools/fr3ds_relief.lua <firered3ds.pak> [out]")
local f = assert(io.open(path, "rb"))
local s = f:read("*a")
f:close()
assert(s:sub(1, 7) == "EM3DPAK", "not an Emerald 3DS-format pak")
local function u32(at) local a, b, c, d = s:byte(at + 1, at + 4); return a + b * 256 + c * 65536 + d * 16777216 end
local count, index = u32(36), u32(40)
for i = 0, count - 1 do
  local e = index + 40 * i
  local off, size = u32(e + 16), u32(e + 24)
  local data = s:sub(off + 1, off + size)
  if data:sub(1, 4) == "VXL4" then
    local o = assert(io.open(out, "wb"))
    o:write(data)
    o:close()
    print(("relief: %d bytes -> %s"):format(#data, out))
    return
  end
end
error("no VXL4 relief in " .. path)
