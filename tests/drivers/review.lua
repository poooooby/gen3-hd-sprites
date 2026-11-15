-- Driver (dev only): the review sheet. Every model Battle Scene stands - buildings, rooms, trees,
-- caves - proved against the game's own drawing at 45 degrees, in the game over the player's own
-- cartridge, and gathered into one page to look through (index.html, with a PNG sheet an item):
--   buildings  tests/model_check.lua Check.building: wrong / missing / extra pixels over the spec's
--              exact rectangles, and faces that stretch a texel
--   rooms      Check.room: every piece standing in the room, wrong / missing pixels (over: a top
--              rising over what is drawn behind it, not a fault)
--   trees      each tree species alone on grass, its model against its three drawn rows
--   caves      the levels the cave reader counts, tinted over the drawing; disagreements (an edge
--              whose two sides draw it at different levels) marked
-- Each item's sheet is three panels: the drawing | the model at 45 degrees | the marks.
--   SHOT_DIR       where index.html and the sheets go
--   REVIEW_KINDS   kinds to review, comma separated (default every kind)
--   REVIEW_SHOTS   in-game shots (default all; a number: that many of the worst; 0 none): a battle
--                  just south of each item (where its faults gather, else its middle), as played
--                  and aimed at it
--   REVIEW_PAK     (FireRed) the FireRed 3DS build's pak, read to compare (never copied): whether it
--                  models each building where we do, what it models that we don't, and how its
--                  relief's levels meet ours in each cave
-- Run from the engine root (tools/review.ps1 does this and opens the page):
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/review.lua love .
-- The sheets show the game's own art: they stay on this machine (never shipped, never shared).

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local MOD = "mods/gen3-hd-sprites/"
local floor = math.floor

-- ── JSON (the page's data) ──
local function json(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local out = {}
      for i = 1, #v do out[i] = json(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = json(k) .. ":" .. json(v[k] == nil and v[tonumber(k)] or v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      return c == '"' and '\\"' or c == "\\" and "\\\\" or ("\\u%04x"):format(c:byte())
    end):gsub("</", "<\\/") .. '"'
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    return v == floor(v) and ("%d"):format(v) or ("%.4f"):format(v)
  elseif t == "boolean" then return tostring(v) end
  return "null"
end

-- ── a sheet as a PNG ──
local function writePNG(path, sheet)
  local img = love.image.newImageData(math.max(1, sheet.w), math.max(1, sheet.h))
  for y = 0, sheet.h - 1 do
    for x = 0, sheet.w - 1 do
      local c = sheet.at(x, y) or 0
      img:setPixel(x, y, floor(c / 65536) % 256 / 255, floor(c / 256) % 256 / 255, c % 256 / 255, 1)
    end
  end
  local data = img:encode("png")
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data:getString())
  f:close()
  return true
end

-- ── the game's layouts and their art, read as the relief reads them (trees, caves) ──
-- ── trees: each species alone on grass, its model against its drawn rows (Check.tree) ──
local function treeResults(ctx, Check, log)
  local Trees = ctx.load("src/scene/trees.lua")
  if not (ctx.G.trees and Trees.useGame) then return {} end
  Trees.useGame(ctx.G)
  if not Trees.species then return {} end
  local out = {}
  local ks = {}
  for k in pairs(Trees.species) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, K in ipairs(ks) do
    local res, why = Check.tree(ctx, Trees, K)
    if res then
      -- (where one stands, for the shots: its trunk's first cell in its layout)
      local SP = Trees.species[K]
      local lname = K == 0 and "LAYOUT_PALLET_TOWN" or (SP.layouts and SP.layouts[1])
      local L = lname and ctx.inp.byName[lname]
      local trunk = SP.alone and SP.alone.trunk and SP.alone.trunk[1]
      if L and trunk then
        for i = 0, L.w * L.h - 1 do
          if L.blocks[i] % 1024 == trunk then res.layout, res.focus = lname, { i % L.w, floor(i / L.w) }; break end
        end
      end
      out[#out + 1] = res
    else log(why) end
  end
  return out
end

-- ── caves: the levels counted, and where the drawing disagrees ──
local TINT = { [-2] = 0xFF0000, [-1] = 0xFF8000, [1] = 0x008CFF, [2] = 0x00DC5A, [3] = 0xDC00DC, [4] = 0xFFFF00 }
local function caveResults(ctx, Check, log, pakRelief)
  local C = ctx.G.caves
  if not C then return {} end
  local Caves = ctx.load("src/scene/relief_caves.lua")
  local names = {}
  local src = io.open(MOD .. "src/scene/roles.lua", "rb")
  local text = src and src:read("*a") or ""
  if src then src:close() end
  local waterNames = {}
  for n in (text:match("Roles.WATER_NAMES = (%b{})") or ""):gmatch('"(MB_[%w_]+)"') do waterNames[#waterNames + 1] = n end
  for _, n in ipairs(C.water or {}) do waterNames[#waterNames + 1] = n end
  for _, L in pairs(ctx.inp.layouts) do if Caves.covers(C, L.name) then names[#names + 1] = L.name end end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    local L = ctx.inp.byName[name]
    local P = ctx.pairOf(L)
    local A = ctx.Art.layoutArt(L, P)
    local ok, lv, kinds, conf = pcall(Caves.read, L, C, nil, Caves.waterTest(ctx.inp, waterNames))
    if not ok then
      log(("cave %s: %s"):format(name, tostring(lv)))
    else
      local W, H = L.w * 16, L.h * 16
      local function drawn(x, y)
        return P.cellImage(A.metatile(floor(x / 16), floor(y / 16)))[(y % 16) * 16 + x % 16] or 0
      end
      local function tinted(x, y)
        local c = drawn(x, y)
        local i = floor(y / 16) * L.w + floor(x / 16)
        local t = TINT[lv[i]] or (lv[i] ~= 0 and 0xFFFFFF) or nil
        if kinds[i] == "water" and x % 4 == 0 and y % 4 == 0 then c = 0xFFFFFF end
        if not t then return c end
        local function mix(s) return floor(floor(c / s) % 256 * 0.55 + floor(t / s) % 256 * 0.45) end
        return mix(65536) * 65536 + mix(256) * 256 + mix(1)
      end
      -- (each disagreement: its edge drawn red, 2 pixels either side)
      local marks = {}
      for _, c in ipairs(conf) do
        local x, y = c[1], c[2]
        if c[3] == "e" then
          for v = 0, 15 do for d = -2, 1 do marks[(y * 16 + v) * W + (x + 1) * 16 + d] = 0xFF0000 end end
        else
          for u = 0, 15 do for d = -2, 1 do marks[((y + 1) * 16 + d) * W + x * 16 + u] = 0xFF0000 end end
        end
      end
      local per = {}
      for _, c in ipairs(conf) do per[c[2] * 4096 + c[1]] = (per[c[2] * 4096 + c[1]] or 0) + 1 end
      -- (no disagreement: the shot aimed where most rock stands)
      if #conf == 0 then
        for i = 0, L.w * L.h - 1 do if lv[i] ~= 0 then per[floor(i / L.w) * 4096 + i % L.w] = 1 end end
      end
      -- (the FireRed 3DS build's levels here, aligned with ours by the commonest difference)
      local cmp
      local pt = pakRelief and pakRelief.layouts[L.id]
      if pakRelief then
        local function theirs(i)
          local g = pt and pt.cells[i]
          if not g then return floor((pt and pt.base or 0) / 16 + 0.5) end
          local m = -1e9
          for k = 0, 24 do m = math.max(m, g[k]) end
          return floor((m + (pt.base or 0)) / 16 + 0.5)
        end
        local function ours(i)
          local f, hi = Caves.SHAPES[kinds[i]], 0
          if f then for t = 0, 4 do for u = 0, 4 do hi = math.max(hi, f(u, t)) end end end
          return floor(lv[i] + hi + 0.5)
        end
        local diffs, best, bn = {}, 0, -1
        for i = 0, L.w * L.h - 1 do local d = theirs(i) - ours(i); diffs[d] = (diffs[d] or 0) + 1 end
        for d, c in pairs(diffs) do if c > bn then best, bn = d, c end end
        local theirsLv = {}
        for i = 0, L.w * L.h - 1 do theirsLv[i] = theirs(i) - best end
        local base = theirsLv
        local zero = {}
        for i = 0, L.w * L.h - 1 do zero[base[i]] = (zero[base[i]] or 0) + 1 end
        local z, zn = 0, -1
        for k, c in pairs(zero) do if c > zn then z, zn = k, c end end
        cmp = { agree = 100 * bn / (L.w * L.h), raised = pt ~= nil,
          sheet = { w = W, h = H, at = function(x, y)
            local c = drawn(x, y)
            local i = floor(y / 16) * L.w + floor(x / 16)
            local t = TINT[theirsLv[i] - z] or (theirsLv[i] ~= z and 0xFFFFFF) or nil
            if not t then return c end
            local function mix(sh) return floor(floor(c / sh) % 256 * 0.55 + floor(t / sh) % 256 * 0.45) end
            return mix(65536) * 65536 + mix(256) * 256 + mix(1)
          end } }
      end
      local levels = {}
      for i = 0, L.w * L.h - 1 do levels[lv[i]] = (levels[lv[i]] or 0) + 1 end
      local stood = 0
      for k, n in pairs(levels) do if k ~= 0 then stood = stood + n end end
      out[#out + 1] = { name = name:gsub("^LAYOUT_", ""):lower(), kind = "cave", ok = #conf == 0,
        unsettled = #conf > 0, cmp = cmp,
        disagree = #conf, judged = L.w * L.h, raised = stood, layout = name, focus = Check.focus(per),
        sheet = Check.sheet(W, H, drawn, tinted,
          function(x, y) return marks[y * W + x] or tinted(x, y) end) }
    end
  end
  return out
end

-- ── every layout's relief, ours against another build's: the drawing, ours tinted by level, theirs
-- tinted (each by its levels over its commonest), the layouts that differ most first ──
local function reliefResults(ctx, Check, log, ours, theirs, limit)
  local function level(t, i)
    local g = t and t.cells[i]
    local m = 0
    if g then m = -1e9; for k = 0, 24 do m = math.max(m, g[k]) end end
    return floor((m + (t and t.base or 0)) / 16 + 0.5)
  end
  local rows = {}
  for _, L in pairs(ctx.inp.layouts) do
    local a, b = ours.layouts[L.id], theirs.layouts[L.id]
    if (a or b) and not (a and b and (a.w ~= b.w or a.h ~= b.h)) and L.w * L.h > 0 then
      local la, lb, diffs = {}, {}, {}
      for i = 0, L.w * L.h - 1 do
        la[i], lb[i] = level(a, i), level(b, i)
        local d = lb[i] - la[i]
        diffs[d] = (diffs[d] or 0) + 1
      end
      local bn = -1
      for _, c in pairs(diffs) do if c > bn then bn = c end end
      rows[#rows + 1] = { L = L, la = la, lb = lb, bad = L.w * L.h - bn }
    end
  end
  table.sort(rows, function(x, y) return x.bad > y.bad end)
  local out = {}
  for n = 1, math.min(limit, #rows) do
    local r = rows[n]
    local L = r.L
    local P = ctx.pairOf(L)
    local A = ctx.Art.layoutArt(L, P)
    local W, H = L.w * 16, L.h * 16
    local function drawn(x, y)
      return P.cellImage(A.metatile(floor(x / 16), floor(y / 16)))[(y % 16) * 16 + x % 16] or 0
    end
    local function tintBy(lv)
      local zero, z, zn = {}, 0, -1
      for i = 0, L.w * L.h - 1 do zero[lv[i]] = (zero[lv[i]] or 0) + 1 end
      for k, c in pairs(zero) do if c > zn then z, zn = k, c end end
      return function(x, y)
        local c = drawn(x, y)
        local i = floor(y / 16) * L.w + floor(x / 16)
        local t = TINT[lv[i] - z] or (lv[i] ~= z and 0xFFFFFF) or nil
        if not t then return c end
        local function mix(s) return floor(floor(c / s) % 256 * 0.55 + floor(t / s) % 256 * 0.45) end
        return mix(65536) * 65536 + mix(256) * 256 + mix(1)
      end
    end
    out[#out + 1] = { name = L.name:gsub("^LAYOUT_", ""):lower(), kind = "relief", ok = r.bad == 0,
      disagree = r.bad, judged = L.w * L.h, layout = L.name,
      captions = { "drawn", "ours", "FireRed 3DS" },
      sheet = Check.sheet(W, H, drawn, tintBy(r.la), tintBy(r.lb)) }
    log(("relief %s: %d cells differ"):format(L.name, r.bad))
  end
  return out
end

-- ── another build's pak (Emerald 3DS's format, "EM3DPAK"), read to compare: its relief and the
-- buildings it places ──
local function u32(s, at) local a, b, c, d = s:byte(at + 1, at + 4); return a + b * 256 + c * 65536 + d * 16777216 end
local function u16(s, at) local a, b = s:byte(at + 1, at + 2); return a + b * 256 end
local function readPak(path)
  local f = path and io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  if s:sub(1, 7) ~= "EM3DPAK" then return nil end
  local count, io_ = u32(s, 36), u32(s, 40)
  local out = {}
  for i = 0, count - 1 do
    local e = io_ + 40 * i
    if u32(s, e + 8) == 6 then
      local off, size = u32(s, e + 16), u32(s, e + 24)
      local data = s:sub(off + 1, off + size)
      if data:sub(1, 4) == "VXL4" then out.relief = data
      elseif data:sub(1, 3) == "VXB" then out.buildings = data end
    end
  end
  return out
end

-- its buildings' placements: { [layout id] = { { x, y, w, h }, ... } } (VXB7: the header's counts,
-- then pages, models, page-model links, placements)
local function pakPlacements(b)
  if not b or b:sub(1, 4) ~= "VXB7" then return nil end
  local npages, nmodels, npm, nplace = u16(b, 4), u16(b, 6), u16(b, 8), u16(b, 10)
  local o = 4 + 20
  o = o + 8 * npages
  local models = {}
  for i = 0, nmodels - 1 do models[i] = { b:byte(o + 1), b:byte(o + 2) }; o = o + 16 end
  local pms = {}
  for i = 0, npm - 1 do pms[i] = u16(b, o); o = o + 8 end
  local out, n = {}, 0
  for _ = 1, nplace do
    local L, pmi, x, y = u16(b, o), u16(b, o + 2), u16(b, o + 4), u16(b, o + 6)
    local m = models[pms[pmi] or -1]
    if m then
      out[L] = out[L] or {}
      table.insert(out[L], { x, y, m[1], m[2] })
      n = n + 1
    end
    o = o + 16
  end
  return out, n
end

-- how much of rectangle a (x, y, w, h) another covers
local function overlap(a, b)
  local w = math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1])
  local h = math.min(a[2] + a[4], b[2] + b[4]) - math.max(a[2], b[2])
  if w <= 0 or h <= 0 then return 0 end
  return w * h / (a[3] * a[4])
end

-- ── the page ──
local PAGE = [[<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Battle Scene Review</title>
<style>
:root{--bg:#f6f5f2;--card:#fff;--ink:#1d1d1f;--mute:#6b6b70;--line:#e2e0db;--bad:#c8312b;--ok:#2f7d4a;--warn:#b7791f;--chip:#efeee9}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--card:#1e1e21;--ink:#ececef;--mute:#9a9aa2;--line:#2e2e33;--bad:#ff6b61;--ok:#5fcf86;--warn:#e8b04a;--chip:#2a2a2e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 16px}
h1{margin:0 0 4px;font-size:18px}.sub{color:var(--mute);font-size:13px}
.bar{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px;align-items:center}
.bar button,.bar select,.bar input{font:inherit;color:inherit;background:var(--chip);border:1px solid var(--line);border-radius:6px;padding:4px 10px}
.bar button.on{background:var(--ink);color:var(--bg)}
.bar label{display:flex;gap:4px;align-items:center;color:var(--mute)}
.tot{display:flex;flex-wrap:wrap;gap:14px;margin-top:8px;font-size:13px}
.tot b{font-variant-numeric:tabular-nums}
main{padding:12px 16px;display:grid;gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;min-width:0}
.card.bad{border-left:4px solid var(--bad)}.card.good{border-left:4px solid var(--ok)}.card.warn{border-left:4px solid var(--warn)}
.badge.warn{background:color-mix(in srgb,var(--warn) 18%,transparent);color:var(--warn)}
.top{display:flex;flex-wrap:wrap;gap:8px;align-items:baseline}
.name{font-weight:600;font-size:15px}.kind{color:var(--mute);font-size:12px;text-transform:uppercase;letter-spacing:.04em}
.badge{font-size:12px;padding:1px 8px;border-radius:10px;font-weight:600}
.badge.bad{background:color-mix(in srgb,var(--bad) 18%,transparent);color:var(--bad)}
.badge.good{background:color-mix(in srgb,var(--ok) 18%,transparent);color:var(--ok)}
.nums{color:var(--mute);font-size:13px;font-variant-numeric:tabular-nums}
.nums b{color:var(--ink)}
.pieces{color:var(--mute);font-size:12px;margin-top:4px}
.sheet{margin-top:8px;overflow:auto;max-width:100%;background:#000;border-radius:6px}
.sheet img{display:block;image-rendering:pixelated;cursor:zoom-in}
.panes{display:flex;color:#bbb;background:#000;font-size:11px;padding:2px 0 4px}.panes span{flex:1;padding-left:4px}
.shots{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}.shots figure{margin:0;flex:1 1 300px;max-width:600px}
.shots img{width:100%;display:block;border-radius:6px;cursor:zoom-in}.shots figcaption{color:var(--mute);font-size:11px;margin-top:2px}
.verdict{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px;align-items:center}
.verdict button{font:inherit;font-size:12px;background:var(--chip);color:inherit;border:1px solid var(--line);border-radius:6px;padding:2px 8px;cursor:pointer}
.verdict button.on.fine{background:var(--ok);color:#fff}.verdict button.on.fix{background:var(--bad);color:#fff}
.verdict a.open{font-size:12px;background:var(--chip);color:inherit;border:1px solid var(--line);border-radius:6px;padding:2px 8px;text-decoration:none}
.verdict input{flex:1;min-width:160px;font:inherit;font-size:12px;color:inherit;background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:3px 8px}
.legend{display:flex;flex-wrap:wrap;gap:12px;font-size:12px;color:var(--mute);margin-top:8px}
.sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
.flat{background:var(--card);border:1px dashed var(--line);border-radius:10px;padding:12px}
.flat ul{margin:6px 0 0;padding-left:18px}
#out{width:100%;min-height:120px;font:12px ui-monospace,monospace;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px;display:none}
</style></head><body>
<header><h1>Battle Scene Review</h1>
<div class="sub" id="sub"></div>
<div class="tot" id="tot"></div>
<div class="bar" id="kinds"></div>
<div class="bar">
<label><input type="checkbox" id="onlyBad" checked> only mismatches</label>
<label><input type="checkbox" id="hideMarked"> hide ones I've marked</label>
<select id="sort"><option value="pct">worst share first</option><option value="px">most pixels off</option><option value="name">by name</option></select>
<input id="q" type="search" placeholder="filter by name">
<button id="copy">copy my notes</button>
</div>
<div class="legend"><span><i class="sw" style="background:#f00"></i>wrong colour</span><span><i class="sw" style="background:#f0f"></i>missing (nothing covers it)</span><span><i class="sw" style="background:#0ff"></i>extra (covers ground)</span><span><i class="sw" style="background:#ffc000"></i>over (a top rising over what's behind; not a fault)</span><span>caves: red edge = the drawing disagrees on the level; tint = level (blue 1, green 2, violet 3, yellow 4, orange/red below)</span></div>
<textarea id="out" readonly></textarea>
</header>
<main id="list"></main>
<script>
const R = __DATA__;
const KEY = "bs-review-" + R.game;
let notes = {};
try { notes = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) { notes = {}; }
function save(){ try { localStorage.setItem(KEY, JSON.stringify(notes)); } catch (e) {} }
const KINDS = { building: "Buildings", room: "Rooms", tree: "Trees", cave: "Caves" };
const PANES = { model: ["drawing", "model at 45 degrees", "marks"], room: ["drawing", "room at 45 degrees", "marks"],
  cave: ["drawing", "levels read", "disagreements"] };
let kind = "all";
const $ = id => document.getElementById(id);
function off(it){ return it.kind === "cave" ? it.disagree : (it.wrong||0) + (it.missing||0) + (it.extra||0) + (it.stretched||0); }
function pct(it){ return it.judged ? 100 * off(it) / it.judged : 0; }
$("sub").textContent = R.game + " - " + R.when + " - each sheet: the game's drawing | the model at 45 degrees | the marks. Click a sheet to zoom. Mark items, then copy your notes.";
function totals(){
  const t = $("tot"); t.innerHTML = "";
  for (const k of Object.keys(KINDS)) {
    const all = R.items.filter(i => i.kind === k); if (!all.length) continue;
    const bad = all.filter(i => !i.ok && !i.unsettled).length, unsettled = all.filter(i => i.unsettled).length;
    const s = document.createElement("span");
    s.innerHTML = KINDS[k] + ": <b>" + (all.length - bad - unsettled) + "</b> exact, " + (unsettled ? "<b>" + unsettled + "</b> unsettled, " : "") + "<b>" + bad + "</b> off";
    t.appendChild(s);
  }
  const marked = Object.values(notes).filter(n => n.v).length;
  const s = document.createElement("span"); s.innerHTML = "marked by you: <b>" + marked + "</b>"; t.appendChild(s);
}
function kinds(){
  const b = $("kinds"); b.innerHTML = "";
  for (const [k, label] of [["all","All"], ...Object.entries(KINDS)]) {
    if (k !== "all" && !R.items.some(i => i.kind === k)) continue;
    const e = document.createElement("button"); e.textContent = label; if (k === kind) e.className = "on";
    e.onclick = () => { kind = k; kinds(); render(); }; b.appendChild(e);
  }
}
function numbers(it){
  if (it.kind === "cave") return "<b>" + it.disagree + "</b> disagreeing edges" + (it.unsettled ? " (the drawing allows either level there; checked in game)" : "") + " - " + it.raised + " of " + it.judged + " cells raised" + (it.pakAgree != null ? " - FireRed 3DS's levels agree on " + it.pakAgree.toFixed(0) + "% of cells (it lifts rock a single level)" : "");
  const p = [];
  p.push("<b>" + (it.wrong||0) + "</b> wrong");
  p.push("<b>" + (it.missing||0) + "</b> missing");
  if (it.kind === "building") p.push("<b>" + (it.extra||0) + "</b> extra");
  if (it.kind === "room") p.push((it.over||0) + " over");
  if (it.stretched) p.push("<b>" + it.stretched + "</b> stretched faces");
  p.push(pct(it).toFixed(2) + "% of " + it.judged + " px");
  if (it.pak) p.push(it.pak);
  return p.join(" - ");
}
function render(){
  const q = $("q").value.toLowerCase(), onlyBad = $("onlyBad").checked, hide = $("hideMarked").checked;
  let items = R.items.filter(i => (kind === "all" || i.kind === kind) && (!onlyBad || !i.ok)
    && (!q || i.name.toLowerCase().includes(q)) && !(hide && notes[i.id] && notes[i.id].v));
  const s = $("sort").value;
  items.sort((a, b) => s === "name" ? a.name.localeCompare(b.name) : s === "px" ? off(b) - off(a) : pct(b) - pct(a));
  const L = $("list"); L.innerHTML = "";
  if (!items.length) { const e = document.createElement("div"); e.className = "card"; e.textContent = "Nothing to show with these filters."; L.appendChild(e); }
  for (const it of items) {
    const st = it.ok ? "good" : it.unsettled ? "warn" : "bad";
    const c = document.createElement("div"); c.className = "card " + st;
    const n = notes[it.id] || {};
    c.innerHTML = '<div class="top"><span class="name"></span><span class="kind"></span><span class="badge ' + st + '">' + (it.ok ? "exact" : it.unsettled ? "unsettled" : "off") + '</span></div>'
      + '<div class="nums">' + numbers(it) + '</div>'
      + (it.pieces ? '<div class="pieces"></div>' : "")
      + '<div class="sheet"><img loading="lazy" alt=""><div class="panes">' + (PANES[it.kind] || PANES.model).map(t => "<span>" + t + "</span>").join("") + '</div></div>'
      + (it.cmpPng ? '<div class="shots"><figure><img class="cmp" alt="" loading="lazy"><figcaption>FireRed 3DS levels, tinted as ours</figcaption></figure></div>' : "")
      + (it.shots && it.shots.length ? '<div class="shots"></div>' : "")
      + '<div class="verdict"><button class="fine">looks fine</button><button class="fix">needs work</button>'
      + (it.open ? '<a class="open" title="Opens the Scene Workshop at this item (once: tools/register-workshop-link.ps1)">open in workshop</a>' : "")
      + '<input placeholder="note (what is wrong)"></div>';
    c.querySelector(".name").textContent = it.name;
    c.querySelector(".kind").textContent = it.kind;
    if (it.pieces) c.querySelector(".pieces").textContent = it.pieces;
    if (it.open) c.querySelector("a.open").href = it.open;
    if (it.cmpPng) { const ci = c.querySelector("img.cmp"); ci.src = it.cmpPng; ci.style.imageRendering = "pixelated"; }
    if (it.shots && it.shots.length) {
      const box = c.querySelectorAll(".shots")[it.cmpPng ? 1 : 0];
      it.shots.forEach((f, k) => {
        const fig = document.createElement("figure"), im = document.createElement("img"), cap = document.createElement("figcaption");
        im.src = f; im.loading = "lazy"; im.alt = ""; cap.textContent = (it.captions && it.captions[k]) || (k === 0 ? "in battle" : "aimed at it");
        im.onclick = () => window.open(f, "_blank"); fig.append(im, cap); box.appendChild(fig);
      });
    }
    const img = c.querySelector("img"), panes = c.querySelector(".panes"); img.src = it.png; let z = it.zoom;
    function size(){ img.style.width = panes.style.width = (it.w * z) + "px"; }
    size(); img.onclick = () => { z = z >= 4 ? 1 : z + 1; size(); };
    const fine = c.querySelector(".fine"), fix = c.querySelector(".fix"), inp = c.querySelector("input");
    function paint(){ fine.className = "fine" + (n.v === "fine" ? " on" : ""); fix.className = "fix" + (n.v === "fix" ? " on" : ""); }
    paint(); inp.value = n.t || "";
    function set(v){ n.v = n.v === v ? undefined : v; notes[it.id] = n; save(); paint(); totals(); }
    fine.onclick = () => set("fine"); fix.onclick = () => set("fix");
    inp.oninput = () => { n.t = inp.value; notes[it.id] = n; save(); };
    L.appendChild(c);
  }
  if (R.pakOnly && R.pakOnly.length && (kind === "all" || kind === "building") && !q) {
    const f = document.createElement("div"); f.className = "flat";
    f.innerHTML = "<b>FireRed 3DS models a building here, and we don't</b><ul></ul>";
    for (const t of R.pakOnly) { const li = document.createElement("li"); li.textContent = t; f.querySelector("ul").appendChild(li); }
    L.appendChild(f);
  }
  if (R.flat.length && (kind === "all") && !q) {
    const f = document.createElement("div"); f.className = "flat";
    f.innerHTML = "<b>Left flat (no model yet)</b><ul></ul>";
    for (const t of R.flat) { const li = document.createElement("li"); li.textContent = t; f.querySelector("ul").appendChild(li); }
    L.appendChild(f);
  }
}
$("copy").onclick = () => {
  const lines = [];
  for (const it of R.items) { const n = notes[it.id]; if (n && (n.v || n.t)) lines.push("- " + it.kind + " " + it.name + ": " + (n.v === "fine" ? "looks fine" : n.v === "fix" ? "needs work" : "note") + (n.t ? " - " + n.t : "")); }
  const o = $("out"); o.style.display = "block"; o.value = lines.length ? "Battle Scene review (" + R.game + "):\n" + lines.join("\n") : "(no notes yet: mark items with looks fine / needs work)";
  o.select(); try { navigator.clipboard.writeText(o.value); } catch (e) {}
};
for (const id of ["onlyBad", "hideMarked", "sort", "q"]) $(id).addEventListener("input", render);
kinds(); totals(); render();
</script></body></html>
]]

-- what still lies flat (no model yet), for the page's foot
local FLAT = {
  firered = {
    "Rooms no battle is fought in (houses, the Dept. Store, the Museum, the Fan Club, ...): drawn flat",
    "Caves marked unsettled: where the drawing's two sides disagree on the level the rock steps (checked in game)",
  },
}

-- -- in-game shots of the worst items: a battle started just south of where the faults gather,
-- the battle as played and the camera aimed at them (REVIEW_SHOTS: how many, default 10; 0 none) --
local function shoot(game, hd, items, dir, gameName, log)
  local Check = dofile(MOD .. "tests/model_check.lua")
  -- (REVIEW_SHOTS: "all" (the default) or how many of the worst)
  local all = (env("REVIEW_SHOTS") or "all") == "all"
  local want = all and math.huge or (tonumber(env("REVIEW_SHOTS")) or 10)
  if want <= 0 then return end
  local U = require("tests.drivers.util")
  local function off(it) return it.disagree or ((it.wrong or 0) + (it.missing or 0) + (it.extra or 0)) end
  local list = {}
  for _, it in ipairs(items) do
    if it.layout and it.focus and (all or (not it.ok and off(it) > 0)) then list[#list + 1] = it end
  end
  if all then
    -- (map by map, a map's items together)
    table.sort(list, function(a, b) if a.layout ~= b.layout then return a.layout < b.layout end return a.name < b.name end)
  else
    table.sort(list, function(a, b) return off(a) / math.max(1, a.judged) > off(b) / math.max(1, b.judged) end)
  end
  if #list == 0 then return end
  -- (the relief first, as play builds it: a cached one is served at once)
  if hd._reliefStep then
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 900 do
      local st = hd._reliefStep()
      if st ~= "running" and st ~= "idle" then break end
      U.wait(1)
    end
  end
  love.window.setMode(1440, 960, { resizable = true })
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of(gameName)
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local n = 0
  for _, it in ipairs(list) do
    if n >= want then break end
    local mapId = Check.mapIdOf(gameName, it.layout)
    if not mapId then
      log(("shot %s: no map for %s"):format(it.name, it.layout))
    else
      local fx, fy = it.focus[1], it.focus[2]
      local px, py = math.floor(fx), math.floor(fy) + 3
      -- (a building: the player on the ground two rows south of its rectangle, the shots aimed at
      -- its middle from the front, both front corners and behind)
      if it.rect then px, py = math.floor(it.rect[1] + it.rect[3] / 2), it.rect[2] + it.rect[4] + 1 end
      pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "up" })
      local s = Runtime.getSession()
      if s then s.x, s.y = px, py end
      Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
      Player.targetX, Player.targetY, Player.facing = px, py, "up"
      if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
      U.wait(30)
      hd.setScene(true)
      local ok, why = BattleBridge.startWild(Runtime._mod, game,
        { species = C:require("species", "SPECIES_WURMPLE"), level = 3 }, { fade = false })
      if ok then
        for _ = 1, 3000 do
          if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
          if Ui._mode == "menu" and not Anim.busy() then break end
          U.wait(1)
        end
        hd.setFill(true)
        U.wait(30)
        local base = ("shot_%s_%s"):format(it.kind, it.name):gsub("[^%w_%-]", "_")
        it.shots = {}
        if U.shot(game, dir .. "/" .. base .. "_battle.png") then it.shots[#it.shots + 1] = base .. "_battle.png" end
        local looks = it.looks or { { 45, 10, 0, "aimed at it" } }
        it.captions = { "in battle" }
        for li, lk in ipairs(looks) do
          if hd._sceneLook and hd._sceneLook(fx + 0.5, fy + 0.5, lk[1], lk[2], lk[3]) then
            U.wait(4)
            local data = hd._sceneShot and hd._sceneShot(960, 640)
            if data then
              local name = ("%s_look%d.png"):format(base, li)
              local f = io.open(dir .. "/" .. name, "wb")
              if f then
                f:write(data:encode("png"):getString()); f:close()
                it.shots[#it.shots + 1] = name
                it.captions[#it.shots] = lk[4]
              end
            end
          end
        end
        n = n + 1
        log(("shot %s at %s (%d,%d)"):format(it.name, mapId, fx, fy))
        -- (the battle ended, for the next)
        pcall(BattleBridge.finishPending, "win")
        local Battle = require("src.core.game3.battle")
        for _ = 1, 600 do
          if not (Battle.isActive and Battle.isActive()) then break end
          if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") end
          U.wait(1)
        end
        U.wait(30)
      else
        log(("shot %s: no battle at %s (%s)"):format(it.name, mapId, tostring(why)))
      end
    end
  end
end

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = env("SHOT_DIR") or "/tmp/hd_review"
  local gameName = env("POKEPORT_GAME") or "emerald"
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._sceneModel and hd._rooms) then log("FAIL gen3-hd-sprites exports missing"); return end
  local Check = dofile(MOD .. "tests/model_check.lua")
  local want
  for k in (env("REVIEW_KINDS") or ""):gmatch("[^,]+") do want = want or {}; want[k] = true end
  -- (REVIEW_PAK: another build's pak, read to compare - its relief, its buildings' places)
  local pak = readPak(env("REVIEW_PAK"))
  local pakRelief, pakPlaces, pakPlaceCount
  if pak then
    local Relief = dofile(MOD .. "src/scene/relief.lua")
    pakRelief = pak.relief and Relief.decode(pak.relief) or nil
    pakPlaces, pakPlaceCount = pakPlacements(pak.buildings)
    log(("pak: relief %s, %s building placements"):format(pakRelief and "read" or "none", tostring(pakPlaceCount)))
  end
  local items = {}
  local function add(res)
    local id = res.kind .. ":" .. res.name
    local file = (res.kind .. "_" .. res.name):gsub("[^%w_%-]", "_") .. ".png"
    writePNG(dir .. "/" .. file, res.sheet)
    if res.cmp then writePNG(dir .. "/cmp_" .. file, res.cmp.sheet) end
    local W = floor(res.sheet.w / 3)
    items[#items + 1] = { id = id, name = res.name, kind = res.kind, ok = res.ok, wrong = res.wrong,
      missing = res.missing, extra = res.extra, over = res.over, judged = res.judged,
      stretched = type(res.stretched) == "table" and #res.stretched or nil, disagree = res.disagree,
      raised = res.raised, pieces = res.piecesText, png = file, w = res.sheet.w,
      captions = res.captions, pak = res.pak, pakAgree = res.cmp and res.cmp.agree or nil,
      layout = type(res.layout) == "string" and res.layout or nil, focus = res.focus, rect = res.rect,
      looks = res.looks, unsettled = res.unsettled,
      zoom = W <= 64 and 4 or W <= 160 and 2 or 1, cmpPng = res.cmp and ("cmp_" .. file) or nil }
    U.wait(1)
  end
  if not want or want.building then
    local names = hd._sceneSpecNames()
    log(("buildings: %d"):format(#names))
    for _, name in ipairs(names) do
      local ok, res = xpcall(Check.building, debug.traceback, hd, name)
      if ok and res then
        -- (where it stands in its reference layout, for the shots)
        local md = hd._sceneModel(name)
        local sp = md and md.spec
        if sp and sp.layout and sp.rect then
          local r = sp.rect
          res.layout, res.rect = sp.layout, r
          res.focus = { r[1] + r[3] / 2 - 0.5, r[2] + r[4] / 2 - 0.5 }
          local d = math.max(r[3], r[4]) + 5
          res.looks = { { 15, d, 0, "front" }, { 20, d, 45, "from the south-west" }, { 20, d, -45, "from the south-east" },
                        { 25, d, 180, "from behind" } }
        end
        add(res)
      else log(("building %s: %s"):format(name, tostring(res))) end
    end
  end
  if not want or want.room then
    local okR, rooms = xpcall(hd._rooms, debug.traceback, nil)
    if okR and rooms then
      log(("rooms: %d"):format(#rooms))
      for _, r in ipairs(rooms) do
        if r.pieces then
          local ok, res = xpcall(Check.room, debug.traceback, hd, rooms, r)
          if ok and res then
            local worst = {}
            for pn, n in pairs(res.byPiece) do worst[#worst + 1] = { pn, n.wrong + n.missing } end
            table.sort(worst, function(a, b) return a[2] > b[2] end)
            local t = {}
            for i = 1, math.min(5, #worst) do t[#t + 1] = ("%s %d px"):format(worst[i][1], worst[i][2]) end
            res.piecesText = res.pieces .. " pieces" .. (#t > 0 and ("; worst: " .. table.concat(t, ", ")) or "")
            add(res)
          else log(("room %s: %s"):format(r.name, tostring(res))) end
        end
      end
    else log("rooms: " .. tostring(rooms)) end
  end
  if not want or want.tree or want.cave or want.relief then
    local ctx = Check.layoutsOf(gameName, MOD)
    if ctx then
      if not want or want.tree then
        local ok, res = xpcall(treeResults, debug.traceback, ctx, Check, log)
        if ok then for _, r in ipairs(res) do add(r) end else log("trees: " .. tostring(res)) end
      end
      if not want or want.cave then
        local ok, res = xpcall(caveResults, debug.traceback, ctx, Check, log, pakRelief)
        if ok then for _, r in ipairs(res) do add(r) end else log("caves: " .. tostring(res)) end
      end
      -- (REVIEW_OURS: our relief cache, to set against the pak's on every layout)
      local oursFile = env("REVIEW_OURS")
      if pakRelief and oursFile and want and want.relief then
        local f = io.open(oursFile, "rb")
        local s = f and f:read("*a")
        if f then f:close() end
        local Relief = dofile(MOD .. "src/scene/relief.lua")
        local oursRelief = s and Relief.decode(s)
        if oursRelief then
          local ok, res = xpcall(reliefResults, debug.traceback, ctx, Check, log, oursRelief, pakRelief,
            tonumber(env("REVIEW_RELIEF_TOP") or "") or 40)
          if ok then for _, r in ipairs(res) do add(r) end else log("relief: " .. tostring(res)) end
        else log("relief: our cache unreadable: " .. tostring(oursFile)) end
      end
    else log("trees, caves: no layouts read for " .. gameName) end
  end
  -- (the other build's buildings against ours: where each of ours stands, whether it models a
  -- building there too; and what it models where we model nothing)
  local pakOnly
  if pakPlaces and (not want or want.building) then
    local okC, ctx2 = pcall(Check.layoutsOf, gameName, MOD)
    if okC and ctx2 then
      local per, only = {}, {}
      for id, L in pairs(ctx2.inp.layouts) do
        local okM, ours = pcall(hd._layoutModels, L.name)
        ours = okM and ours or {}
        local theirs = pakPlaces[id] or {}
        for _, m in ipairs(ours) do
          local a, hit = { m.x, m.y, m.w, m.h }, false
          for _, t in ipairs(theirs) do if overlap(a, t) >= 0.5 then hit = true; break end end
          local e = per[m.name] or { n = 0, hit = 0 }
          per[m.name] = e
          e.n = e.n + 1
          if hit then e.hit = e.hit + 1 end
        end
        for _, t in ipairs(theirs) do
          local any = false
          for _, m in ipairs(ours) do if overlap(t, { m.x, m.y, m.w, m.h }) >= 0.5 then any = true; break end end
          if not any then only[#only + 1] = ("%s at %d,%d (%d x %d cells)"):format(L.name:gsub("^LAYOUT_", ""), t[1], t[2], t[3], t[4]) end
        end
      end
      for _, it in ipairs(items) do
        local e = it.kind == "building" and per[it.name]
        if e then it.pak = ("FireRed 3DS models it in %d of our %d places"):format(e.hit, e.n) end
      end
      table.sort(only)
      pakOnly = only
      log(("pak: %d placements of theirs where we model nothing"):format(#only))
    end
  end
  -- (each item's workshop link: its map, the spot the shots stand at, the cell to select)
  for _, it in ipairs(items) do
    local mapId = it.layout and it.focus and Check.mapIdOf(gameName, it.layout)
    if mapId then
      local fx, fy = math.floor(it.focus[1] + 0.5), math.floor(it.focus[2] + 0.5)
      local px, py = fx, fy + 3
      if it.rect then
        px, py = math.floor(it.rect[1] + it.rect[3] / 2), it.rect[2] + it.rect[4] + 1
        fx, fy = px, it.rect[2] + it.rect[4] - 1
      end
      it.open = ("woobleview-workshop:%s/%s:%d:%d/%d,%d"):format(gameName, mapId, px, py, fx, fy)
    end
  end
  local okS, errS = xpcall(shoot, debug.traceback, game, hd, items, dir, gameName, log)
  if not okS then log("shots: " .. tostring(errS)) end
  local bad = 0
  for _, it in ipairs(items) do if not it.ok then bad = bad + 1 end end
  local data = { game = gameName, when = os.date("%Y-%m-%d %H:%M"), items = items, pakOnly = pakOnly or {},
    flat = FLAT[gameName == "leafgreen" and "firered" or gameName] or {} }
  local f = io.open(dir .. "/index.html", "wb")
  if f then
    local page = PAGE:gsub("__DATA__", function() return json(data) end)
    f:write(page); f:close()
  end
  log(("%d items, %d off: %s/index.html"):format(#items, bad, dir))
end

return function(game)
  local dir = env("SHOT_DIR") or "/tmp/hd_review"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
