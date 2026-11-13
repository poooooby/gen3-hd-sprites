-- luajit tests/relief_terraces_test.lua: the terraces pass's pieces (src/scene/relief_terraces*.lua)
-- on synthetic data. (Its exactness against Emerald 3DS is checked by the dev driver
-- tests/drivers/relief_dump.lua against the generator's own output.)
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local Art = dofile("src/scene/relief_art.lua")
local Solve = dofile("src/scene/relief_solve.lua")
local S = { Solve = Solve, Art = Art, opt = {}, tick = function() end,
            input = { byName = {}, layouts = {}, behaviours = {}, maps = {} }, DRAWN = {}, DRAWN_BY = {},
            alternates = {}, outdoor = {} }
dofile("src/scene/relief_terraces.lua")(S)
dofile("src/scene/relief_terraces_fit.lua")(S)
dofile("src/scene/relief_terraces_out.lua")(S)
local T = S.T
local N = T.N

-- pieces: a face falls a level south, a band towards its low side, a corner the nearer of the two
local g = T.pieceGrid("S", 32)
check(g[0][0] == 32 and g[N][0] == 16 and g[2][3] == 24, "a face: one level down its rows")
g = T.pieceGrid("W", 32)
check(g[0][N] == 32 and g[0][0] == 16 and g[N][2] == 24, "a band falling west: high on its east side")
g = T.pieceGrid("E2", 32)
check(g[0][0] == 32 and g[0][N] == 0, "a band falling two levels east")
g = T.pieceGrid("cSE", 32)
check(g[0][0] == 32 and g[N][N] == 16 and g[0][N] == 16 and g[N][0] == 16, "a convex corner: its south-east quarter down")
g = T.pieceGrid("vSE", 32)
check(g[0][0] == 32 and g[N][N] == 16 and g[0][N] == 32 and g[N][0] == 32, "a concave corner: only the diagonal falls")
g = T.pieceGrid("S:8", 32)
check(g[N][0] == 24, "a face falling a share of a level (S:8)")
check(T.pieceGrid("F", 5) == T.pieceGrid("F", 5), "piece grids are cached, never two of one piece")
local k, d = T.splitKind("W:5.33")
check(k == "W" and math.abs(d - 5.33) < 1e-9 and select(2, T.splitKind("S")) == nil, "a piece's kind and its drop")
check(T.fmtG(16 / 3) == "5.33333" and T.fmtG(8) == "8", "%g as Python formats a share")
local e = T.edge(T.pieceGrid("S", 16), "S")
check(e[0] == 0 and e[N] == 0 and T.edge(T.pieceGrid("S", 16), "N")[2] == 16, "the heights along an edge")

-- the union-find keeping offsets: a contradiction is refused
local off = T.newOffsets()
check(off:join(1, 2, 16) and off:join(2, 3, 16), "levels joined")
local r1, o1 = off:find(1)
local r3, o3 = off:find(3)
check(r1 == r3 and o1 - o3 == 32, "...a is two levels over c")
check(not off:join(1, 3, 16), "...and a vote against it is dropped")

-- Python's (x, y) order of cells, and its set order
local K = Solve.K
local cells = { K(3, 1), K(1, 2), K(1, 1), K(2, 0) }
T.sortXY(cells)
check(cells[1] == K(1, 1) and cells[2] == K(1, 2) and cells[3] == K(2, 0) and cells[4] == K(3, 1), "cells sorted x first, as Python sorts tuples")
local ps = T.pySetCells({ K(1, 1), K(2, 2), K(1, 1) })
check(#ps == 2, "a set of cells drops its doubles")

-- the diagonal of face ends counts one level, not two
local fakeC = { role_id = function(self, cell) return cell == K(0, 0) and 0x074 or 0x07d end }
local out, n = T.steps(fakeC, { K(0, 0), K(0, 1) }, "S")
check(n == 1 and out[1] == 0 and out[2] == 0, "an upper end over a lower end: one diagonal wall")
out, n = T.steps(fakeC, { K(0, 0), K(0, 1) }, "E")
check(n == 2, "...but across a row each band is a level")

-- the facing edge of a flat cell is level at its level; of a piece, that piece's edge
local flatC = { kind = { [K(0, 0)] = T.GROUND } }
local f = T.facingNs(flatC, {}, { [K(0, 0)] = 48 }, {}, K(0, 0), "N")
check(f[0] == 48 and f[N] == 48, "a flat cell faces at its level")
f = T.facingNs({ kind = {} }, { [K(0, 0)] = { "S", 32 } }, {}, {}, K(0, 0), "N")
check(f[0] == 16, "a face's south edge, seen from the cell south of it")

print(("%d/%d checks passed (relief terraces)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
