-- The Scene Workshop: Battle Scene's world around a spot, to look round freely and tune its models
-- by eye. Its settings are kept as data (src/scene/tune.lua): the game's tune file, written into
-- the mod (src/scene/games/<game>_tune.lua), which ships and which every battle reads.
--
-- Boots a new game, stands the player at WORKSHOP_SPOT (MAP:x:y; default by game), starts a wild
-- battle with Battle Scene on and opens the world it built. Run from the engine root:
--   POKEPORT_GAME=firered POKEPORT_VERSION=firered WORKSHOP_SPOT=FR_ROUTE_2:5:5 \
--   POKEPORT_DRIVER=mods/gen3-hd-sprites/tests/drivers/workshop.lua love .
-- (tools/workshop.ps1 does this from PowerShell.) WORKSHOP_SELECT=x,y selects that cell and opens
-- its proof. The keys are on its panel. Battle Scene is turned
-- on for the session only; FireRed's land needs its 3D cache built (Build 3D Cache), its trees do not.

local function env(name)
  local v = os.getenv(name)
  if v == "" then return nil end
  return v
end

local SPOTS = { firered = "FR_ROUTE_2:5:5", leafgreen = "FR_ROUTE_2:5:5", emerald = "EM_ROUTE104:15:40" }
local PANEL_W = 400

local function body(game, log)
  local U = require("tests.drivers.util")
  local G = love.graphics
  love.window.setMode(1600, 900, { resizable = true, highdpi = false, vsync = 1 })
  love.window.setTitle("Scene Workshop")
  U.wait(2)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "HD", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local gameId = env("POKEPORT_GAME") or "emerald"
  local C = require("src.core.game3.constants").of(gameId)
  local loader = game.mods
  local hd = loader and loader.exports and loader.exports["gen3-hd-sprites"]
  if not (hd and hd._workshop) then log("FAIL WoobleView's workshop hooks are missing"); return end
  -- (no option is changed: the engine saves its options on the way out, and this is your install)
  local spot = env("WORKSHOP_SPOT") or SPOTS[gameId] or SPOTS.emerald
  local mapId, sx, sy = spot:match("([^:]+):(%d+):(%d+)")
  local px, py = tonumber(sx), tonumber(sy)
  pcall(Map.load, nil, game, mapId, { x = px, y = py, facing = "up" })
  local s0 = Runtime.getSession()
  if s0 then s0.x, s0.y = px, py end
  Player.cellX, Player.cellY, Player.px, Player.py = px, py, px * 16, py * 16
  Player.targetX, Player.targetY, Player.facing = px, py, "up"
  if s0 and #(s0.party or {}) == 0 then Party.giveMon(s0, C:require("species", "SPECIES_PIDGEY"), 12) end
  U.wait(30)
  hd.setScene(true)
  local BattleBridge = require("src.core.game3.battle_bridge")
  local ok, err = BattleBridge.startWild(Runtime._mod, game,
    { species = C:require("species", "SPECIES_PIDGEY"), level = 3 }, { fade = false })
  if not ok then log("FAIL startWild", tostring(err)); return end
  local ws = hd._workshop()
  for _ = 1, 600 do
    if ws.last() then break end
    U.wait(1)
  end
  U.wait(60)
  local scene = ws.last()
  if not scene then log("FAIL no scene was built here:", tostring(hd.stats().scene), tostring(hd.stats().sceneError)); return end
  log("workshop open at", spot)

  local Camera, Tune, Trees = ws.Camera, ws.Tune, ws.Trees
  local tuneGame = ws.game()
  local tuneFile = os.getenv("WORKSHOP_TUNE_FILE") or ws.path .. "/src/scene/games/" .. Tune.fileOf(tuneGame) .. "_tune.lua"

  -- ── the camera: orbiting a target on the ground ──
  local cam = { tx = scene.to.tx, tz = scene.to.tz, ty = scene.to.ty or 0,
                pitch = math.deg(scene.to.pitch), dist = scene.to.dist, yaw = 0 }
  local function pose()
    return Camera.pose(cam.tx, cam.tz, math.rad(cam.pitch), cam.dist, cam.ty, math.rad(cam.yaw))
  end
  local function battleView()
    local t = scene.to
    cam.tx, cam.tz, cam.ty, cam.pitch, cam.dist, cam.yaw = t.tx, t.tz, t.ty or 0, math.deg(t.pitch), t.dist, 0
  end

  -- ── what is selected ──
  local sel          -- { cells = { cell... }, tree = bool, prop = name?, label }
  -- the settings the panel shows: the trees' group, or the selected prop's own (Tune.propGroup)
  local GROUP = "trees"
  local defs = Tune.DEFS[GROUP]
  local function useGroup(g)
    if g == GROUP or not Tune.DEFS[g] then return end
    GROUP, defs = g, Tune.DEFS[g]
  end
  local scope = "all"   -- "all" (the game's settings) or "one" (the selection's mark)
  local row = 1
  local status, statusT = "", 0
  local dirty, dirtyAt = false, 0
  local unsaved = false
  local function say(msg) status, statusT = msg, love.timer.getTime(); log(msg) end

  local function placeOf(c)
    local d, lx, ly, id = scene.where(c.cx, c.cy)
    if not (d and id) then return nil end
    return id, lx, ly
  end
  local function treePart(c)
    if not (c and c.pair and c.mid and Trees) then return nil end
    local sec, general = Trees.tilesets(c.pair)
    if not general then return nil end
    local p = Trees.part(sec, c.mid)
    if p == nil or p == Trees.GRASS or p == Trees.SMALL then return nil end
    return p
  end
  local function selectCell(c)
    if not c then sel = nil; return end
    local p = treePart(c)
    if p then
      -- the whole tree: its four cells, from the part's place in it
      local x0, y0 = c.cx - p % 2, c.cy - math.floor(p / 2)
      local cells = {}
      for dy = 0, 1 do
        for dx = 0, 1 do
          local o = scene.grid.at(x0 + dx, y0 + dy)
          if o and treePart(o) == dy * 2 + dx then cells[#cells + 1] = o end
        end
      end
      local id, lx, ly = placeOf(c)
      sel = { cells = cells, tree = true, label = ("Tree at %s (%s,%s)"):format(tostring(id), tostring(lx and lx - p % 2),
        tostring(ly and ly - math.floor(p / 2))) }
      if GROUP ~= "trees" then useGroup("trees"); row = 1 end
    else
      local id, lx, ly = placeOf(c)
      local md = c.model and c.model.model
      local prop = md and md.prop
      local what = prop and ("prop " .. prop) or md and md.spec and ("building " .. md.spec.name)
        or (c.up and "upright cut-out") or tostring(c.kind)
      sel = { cells = { c }, tree = false, prop = prop, label = ("Cell %s (%s,%s): %s, metatile %s"):format(tostring(id),
        tostring(lx), tostring(ly), what, c.mid and ("0x%03X"):format(c.mid) or "-") }
      scope = "all"
      if prop and Tune.DEFS[Tune.propGroup(prop)] then
        if GROUP ~= Tune.propGroup(prop) then useGroup(Tune.propGroup(prop)); row = 1 end
      end
    end
  end

  local function current(d)
    local all = Tune.group(tuneGame, GROUP)
    local base = all[d.key]
    if scope == "one" and sel and sel.tree then
      local id, lx, ly = placeOf(sel.cells[1])
      local m = id and Tune.markAt(tuneGame, id, lx, ly)
      local v = m and m[GROUP] and m[GROUP][d.key]
      if v ~= nil then return v, "this tree" end
      return base, base == nil and "the art's own" or "all trees"
    end
    local d0 = Tune.data[Tune.fileOf(tuneGame)]
    local set = d0 and d0.groups[GROUP] and d0.groups[GROUP][d.key]
    if set ~= nil then return set, "set" end
    return base, base == nil and "the art's own" or "default"
  end
  local function hidden()
    if not (sel and sel.tree) then return false end
    local id, lx, ly = placeOf(sel.cells[1])
    local m = id and Tune.markAt(tuneGame, id, lx, ly)
    return m and m.hide == true or false
  end
  local function change(d, v)
    if scope == "one" and sel and sel.tree then
      for _, c in ipairs(sel.cells) do
        local id, lx, ly = placeOf(c)
        if id then Tune.setMark(tuneGame, id, lx, ly, GROUP, d.key, v) end
      end
    else
      Tune.set(tuneGame, GROUP, d.key, v)
    end
    dirty, dirtyAt, unsaved = true, love.timer.getTime(), true
  end
  local function nudge(dir, big)
    local d = defs[row]
    if not d then return end
    local v = current(d)
    if v == nil then
      v = d.key == "foot" and 0.70 or d.default or 0
    end
    change(d, v + dir * d.step * (big and 5 or 1))
  end
  local function toggleHide()
    if not (sel and sel.tree) then say("Pick a tree first (click it)"); return end
    local on = not hidden()
    for _, c in ipairs(sel.cells) do
      local id, lx, ly = placeOf(c)
      if id then Tune.setMark(tuneGame, id, lx, ly, "trees", "hide", on or nil) end
    end
    dirty, dirtyAt, unsaved = true, love.timer.getTime(), true
  end
  local function save()
    local f, e = io.open(tuneFile, "wb")
    if not f then say("Could not save: " .. tostring(e)); return end
    f:write(Tune.source(tuneGame)); f:close()
    unsaved = false
    say("Saved " .. tuneFile)
  end
  local function revert()
    local chunk = loadfile(tuneFile)
    local okR, t = pcall(function() return chunk and chunk() or nil end)
    Tune.data[Tune.fileOf(tuneGame)] = nil
    if okR and type(t) == "table" then Tune.put(Tune.fileOf(tuneGame), t) end
    dirty, dirtyAt, unsaved = true, 0, false
    say(chunk and "Back to the saved file" or "No saved file: back to the defaults")
  end
  -- ── the proof: the selection against the game's own drawing in the GBA's projection, as the
  -- review sheet proves it (tests/model_check.lua): a tree's species alone on grass under the
  -- settings being tuned, a building's spec, or the room the spot is in ──
  local Check = dofile(ws.path .. "/tests/model_check.lua")
  local proof, proofView = nil, 1
  local VIEWS = { "drawing | model | marks", "the model over the drawing", "the marks" }
  local ctx, rooms
  local function panels(sheet)
    local pw, h = math.floor(sheet.w / 3), sheet.h
    local out = {}
    for i = 0, 2 do
      local d = love.image.newImageData(math.max(1, pw), math.max(1, h))
      for y = 0, h - 1 do
        for x = 0, pw - 1 do
          local c = sheet.at(i * pw + x, y) or 0
          -- (the model's empty pixels clear, so it lies over the drawing)
          local a = (i == 1 and c == 0) and 0 or 1
          d:setPixel(x, y, math.floor(c / 65536) % 256 / 255, math.floor(c / 256) % 256 / 255, c % 256 / 255, a)
        end
      end
      local img = G.newImage(d)
      img:setFilter("nearest", "nearest")
      out[i + 1] = img
    end
    return out, pw, h
  end
  local function prove(quiet)
    if not sel then if not quiet then say("Pick a tree or a building first (click it)") end; return end
    local c = sel.cells[1]
    local res, why, title
    local okP, errP = xpcall(function()
      local part = sel.tree and treePart(c)
      local spec = c.model and c.model.model and c.model.model.spec
      local specs = {}
      for _, n in ipairs(hd._sceneSpecNames and hd._sceneSpecNames() or {}) do specs[n] = true end
      local md = c.model and c.model.model
      if md and md.prop then
        res = Check.prop(md)
        why = res == nil and ("no texture kept for " .. md.prop) or nil
        title = "its drawn subtiles, under these settings"
      elseif part and not Trees.kanto then
        why = "the proof reads Kanto's tree models (Hoenn's trees are Emerald 3DS's cards)"
      elseif part then
        local _, _, _, k = Trees.partCell(part)
        ctx = ctx or Check.layoutsOf(gameId, ws.path .. "/")
        if not ctx then why = "the game's layouts could not be read"; return end
        res, why = Check.tree(ctx, Trees, k)
        title = "its species alone on grass, under these settings"
      elseif spec and not specs[spec.name] then
        why = tostring(spec.name) .. " is a part of the scene's own (a fence, a curb): no spec to prove"
      elseif spec then
        res = Check.building(hd, spec.name)
        why = res == nil and ("no model " .. tostring(spec.name)) or nil
        title = "its spec's rectangles"
      else
        rooms = rooms or (hd._rooms and hd._rooms()) or {}
        for _, r in ipairs(rooms) do
          if r.pieces and Check.mapIdOf(gameId, r.layout) == mapId then
            res = Check.room(hd, rooms, r)
            title = "every piece standing in the room"
            break
          end
        end
        if not res then why = "nothing modelled here to prove: pick a tree or a building" end
      end
    end, debug.traceback)
    if not okP then why = tostring(errP); log(why) end
    if not res then proof = nil; say("No proof: " .. tostring(why)); return end
    local imgs, pw, ph = panels(res.sheet)
    local stretched = type(res.stretched) == "table" and #res.stretched or 0
    local counts = ("wrong %d, missing %d%s%s%s, stretched faces %d, of %d pixels judged"):format(res.wrong or 0,
      res.missing or 0, res.extra and (", extra " .. res.extra) or "", res.over and (", over " .. res.over) or "",
      res.flat and res.flat > 0 and (", flat " .. res.flat) or "",
      stretched, res.judged or 0)
    proof = { res = res, imgs = imgs, w = pw, h = ph, title = ("%s: %s"):format(res.name or "?", title), counts = counts }
    if not quiet then say(("%s %s: %s"):format(res.ok and "Matches the drawing" or "Off the drawing", res.name or "", counts)) end
  end

  local function rebuild()
    local t0 = love.timer.getTime()
    local s, why = ws.rebuild()
    if not s then say("Rebuild failed: " .. tostring(why)); return end
    scene = s
    -- (the selection's cells, in the new grid)
    if sel then
      local c = scene.grid.at(sel.cells[1].cx, sel.cells[1].cy)
      local keep = scope
      selectCell(c)
      scope = keep
    end
    say(("Rebuilt in %d ms"):format((love.timer.getTime() - t0) * 1000))
    if proof then prove(true) end
  end

  -- ── picking: the cell under the mouse ──
  local view = { u0 = 0, v0 = 0, k = 1 }
  local function toCanvas(mx, my) return view.u0 + mx / view.k, view.v0 + my / view.k end
  local function toScreen(u, v) return (u - view.u0) * view.k, (v - view.v0) * view.k end
  local function pick(mx, my)
    local p = pose()
    local u, v = toCanvas(mx, my)
    -- the ground under the ray (a lifted cell stands as high as its lift and as far south again)
    local best
    local h = 0
    for _ = 1, 3 do
      local x, z = Camera.ground(p, u, v, h)
      if not x then break end
      local c = scene.grid.at(math.floor(x), math.floor(z - h))
      best = c
      local dy = c and c.dy or 0
      if math.abs(dy - h) < 0.01 then break end
      h = dy
    end
    -- a tree whose crown card the mouse is on (the nearest such, as the camera sees them) over the
    -- ground: its card's corners from the settings it is drawn with (src/scene/trees.lua)
    local set = Tune.group(tuneGame, "trees")
    local function inside(pts, x, y)
      local n, hit = #pts, false
      local j = n
      for i = 1, n do
        local xi, yi, xj, yj = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then hit = not hit end
        j = i
      end
      return hit
    end
    local nearest
    for jj = 0, scene.grid.h - 1 do
      for ii = 0, scene.grid.w - 1 do
        local c = scene.grid.rows[jj][ii]
        if treePart(c) == 0 then
          local id, lx, ly = placeOf(c)
          local m = id and Tune.markAt(tuneGame, id, lx, ly)
          local mt = m and m.trees or {}
          local lean = math.rad(mt.lean or set.lean or 50)
          -- (two rows and the tip's: three tiles along the card)
          local len = 3 * (mt.height or set.height or 1)
          local foot = mt.foot or set.foot or 0.7
          local dy = c.dy or 0
          local z0 = c.cy + 1 + foot + dy
          local y1, z1 = dy + math.sin(lean) * len, z0 - math.cos(lean) * len
          local pts = {}
          for _, q in ipairs({ { c.cx, dy, z0 }, { c.cx + 2, dy, z0 }, { c.cx + 2, y1, z1 }, { c.cx, y1, z1 } }) do
            local u2, v2 = Camera.project(p, q[1], q[2], q[3])
            if not u2 then pts = nil; break end
            local sx2, sy2 = toScreen(u2, v2)
            pts[#pts + 1] = { sx2, sy2 }
          end
          if pts and inside(pts, mx, my) then
            local _, _, depth = Camera.view(p, c.cx + 1, dy + 0.5, z0)
            if not nearest or depth < nearest then nearest, best = depth, c end
          end
        end
      end
    end
    return best
  end

  -- ── input ──
  local drag
  local saved = {}
  local function hook(name, fn)
    saved[name] = love[name]
    love[name] = fn
  end
  local quit = false
  local function panelRowAt(mx, my)
    local W = G.getWidth()
    if mx < W - PANEL_W then return nil end
    for i = 1, #defs do
      local y = 150 + (i - 1) * 52
      if my >= y and my < y + 48 then return i end
    end
    return nil
  end
  hook("keypressed", function(key)
    local ctrl = love.keyboard.isDown("lctrl", "rctrl")
    local shift = love.keyboard.isDown("lshift", "rshift")
    if key == "escape" then quit = true
    elseif ctrl and key == "s" then save()
    elseif ctrl and key == "r" then revert()
    elseif key == "tab" then
      if sel and sel.tree then scope = scope == "all" and "one" or "all" else scope = "all"; say("Pick a tree for 'This tree'") end
    elseif key == "up" then row = (row - 2) % #defs + 1
    elseif key == "down" then row = row % #defs + 1
    elseif key == "left" then nudge(-1, shift)
    elseif key == "right" then nudge(1, shift)
    elseif key == "backspace" or key == "delete" then if defs[row] then change(defs[row], nil) end
    elseif key == "h" then toggleHide()
    elseif key == "home" or key == "b" then battleView()
    elseif key == "o" then cam.pitch, cam.yaw = 45, 0
    elseif key == "t" then cam.pitch, cam.yaw = 89, 0
    elseif key == "f5" then rebuild()
    elseif key == "g" then if proof then proof = nil else prove() end
    elseif key == "v" then if proof then proofView = proofView % #VIEWS + 1; say("Proof: " .. VIEWS[proofView]) end
    elseif key == "f12" then
      local path = ("%s/workshop_%d.png"):format(env("SHOT_DIR") or ".", os.time())
      G.captureScreenshot(function(data)
        local f = io.open(path, "wb")
        if f then f:write(data:encode("png"):getString()); f:close() end
      end)
      say("Screenshot: " .. path)
    end
  end)
  hook("keyreleased", function() end)
  hook("textinput", function() end)
  hook("mousepressed", function(x, y, button)
    local r = panelRowAt(x, y)
    if r then
      row = r
      local W = G.getWidth()
      if button == 1 and x > W - 70 then nudge(1, love.keyboard.isDown("lshift", "rshift"))
      elseif button == 1 and x > W - 130 then nudge(-1, love.keyboard.isDown("lshift", "rshift")) end
      return
    end
    if x >= G.getWidth() - PANEL_W then return end
    drag = { button = button, x = x, y = y, moved = false }
  end)
  hook("mousemoved", function(x, y, dx, dy)
    if not drag then return end
    if math.abs(x - drag.x) + math.abs(y - drag.y) > 4 then drag.moved = true end
    if drag.button == 2 and not love.keyboard.isDown("lshift", "rshift") then
      cam.yaw = cam.yaw + dx * 0.3
      cam.pitch = math.max(5, math.min(89, cam.pitch + dy * 0.2))
    elseif drag.button == 3 or drag.button == 2 or (drag.button == 1 and drag.moved) then
      -- pan along the ground, as the view faces
      local yw = math.rad(cam.yaw)
      local s = cam.dist * 0.004
      cam.tx = cam.tx - (math.cos(yw) * dx - math.sin(yw) * dy) * s
      cam.tz = cam.tz - (math.sin(yw) * dx + math.cos(yw) * dy) * s
    end
  end)
  hook("mousereleased", function(x, y, button)
    if drag and button == drag.button and button == 1 and not drag.moved then
      selectCell(pick(x, y))
      if sel then say(sel.label) end
    end
    drag = nil
  end)
  hook("wheelmoved", function(_, wy)
    local mx, my = love.mouse.getPosition()
    local r = panelRowAt(mx, my)
    if r then row = r; nudge(wy > 0 and 1 or -1, love.keyboard.isDown("lshift", "rshift")); return end
    cam.dist = math.max(1.5, math.min(60, cam.dist * (wy > 0 and 0.9 or 1.1)))
  end)
  hook("touchpressed", function() end)
  hook("touchreleased", function() end)
  hook("touchmoved", function() end)
  hook("gamepadpressed", function() end)

  -- ── drawing ──
  local font = G.newFont(15)
  local small = G.newFont(12)
  local function outline(c)
    local p = pose()
    local dy = c.dy or 0
    local pts = {}
    for _, q in ipairs({ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }) do
      local u, v = Camera.project(p, c.cx + q[1], dy, c.cy + q[2] + dy)
      if not u then return end
      local x, y = toScreen(u, v)
      pts[#pts + 1], pts[#pts + 2] = x, y
    end
    G.polygon("line", pts)
  end
  local function drawProof(W, H)
    if not proof then return end
    local AW, AH = W - PANEL_W - 32, H * 0.62
    local pw, ph, gap = proof.w, proof.h, 10
    local n = proofView == 1 and 3 or 1
    local k = math.min(AW / (n * pw + (n - 1) * gap), (AH - 52) / ph)
    if k >= 1 then k = math.floor(k) end
    local bw, bh = n * pw * k + (n - 1) * gap + 24, ph * k + 64
    local bx, by = 16, H - bh - 16
    G.setColor(0.06, 0.07, 0.09, 0.94)
    G.rectangle("fill", bx, by, bw, bh, 6)
    G.setColor(proof.res.ok and 0.55 or 1, proof.res.ok and 1 or 0.55, 0.55, 1)
    G.setFont(small)
    G.print((proof.res.ok and "MATCHES  " or "OFF  ") .. proof.title, bx + 12, by + 8)
    G.setColor(0.85, 0.88, 0.92, 1)
    G.print(proof.counts .. "   (" .. VIEWS[proofView] .. "; V: next view, G: close)", bx + 12, by + 26)
    local x, y = bx + 12, by + 48
    G.setColor(1, 1, 1, 1)
    if proofView == 1 then
      for i = 1, 3 do G.draw(proof.imgs[i], x + (i - 1) * (pw * k + gap), y, 0, k, k) end
    elseif proofView == 2 then
      G.draw(proof.imgs[1], x, y, 0, k, k)
      G.setColor(1, 1, 1, 0.5 + 0.5 * math.sin(love.timer.getTime() * 3))
      G.draw(proof.imgs[2], x, y, 0, k, k)
    else
      G.draw(proof.imgs[3], x, y, 0, k, k)
    end
  end
  local function drawPanel(W, H)
    local x0 = W - PANEL_W
    G.setColor(0.08, 0.09, 0.11, 0.92)
    G.rectangle("fill", x0, 0, PANEL_W, H)
    G.setColor(1, 1, 1, 1)
    G.setFont(font)
    G.print(("Scene Workshop: %s"):format(tuneGame), x0 + 16, 14)
    G.setFont(small)
    G.setColor(0.7, 0.75, 0.8, 1)
    G.print(Tune.fileOf(tuneGame) .. "_tune.lua" .. (unsaved and "  (unsaved changes)" or ""), x0 + 16, 36)
    G.setColor(1, 1, 1, 1)
    G.printf(sel and sel.label or "Click a tree (or any cell) to select it", x0 + 16, 58, PANEL_W - 32)
    -- scope
    local function tab(label, on, x)
      G.setColor(on and 0.25 or 0.15, on and 0.45 or 0.17, on and 0.75 or 0.2, 1)
      G.rectangle("fill", x, 100, 176, 30, 4)
      G.setColor(1, 1, 1, on and 1 or 0.6)
      G.printf(label, x, 108, 176, "center")
    end
    if GROUP == "trees" then
      tab("All trees (Tab)", scope == "all", x0 + 16)
      tab(sel and sel.tree and "This tree" or "This tree (pick one)", scope == "one", x0 + 208)
    else
      tab("Every " .. GROUP:gsub("^prop_", ""), true, x0 + 16)
      tab("(click a tree for trees)", false, x0 + 208)
    end
    for i, d in ipairs(defs) do
      local y = 150 + (i - 1) * 52
      if i == row then
        G.setColor(0.2, 0.3, 0.45, 1)
        G.rectangle("fill", x0 + 8, y, PANEL_W - 16, 48, 4)
      end
      local v, from = current(d)
      G.setColor(1, 1, 1, 1)
      G.setFont(font)
      G.print(d.label, x0 + 16, y + 4)
      G.print(v ~= nil and (("%g %s"):format(v, d.unit)) or "-", x0 + 170, y + 4)
      G.setFont(small)
      G.setColor(0.65, 0.7, 0.75, 1)
      G.print(from, x0 + 16, y + 27)
      G.setColor(0.3, 0.33, 0.38, 1)
      G.rectangle("fill", W - 126, y + 8, 48, 30, 4)
      G.rectangle("fill", W - 66, y + 8, 48, 30, 4)
      G.setColor(1, 1, 1, 1)
      G.setFont(font)
      G.printf("-", W - 126, y + 13, 48, "center")
      G.printf("+", W - 66, y + 13, 48, "center")
    end
    local y = 150 + #defs * 52 + 6
    G.setFont(small)
    G.setColor(0.8, 0.85, 0.9, 1)
    local d = defs[row]
    if d then G.printf(d.help, x0 + 16, y, PANEL_W - 32) end
    y = y + 44
    if sel and sel.tree then
      G.setColor(1, 1, 1, 1)
      G.print(hidden() and "This tree is HIDDEN (H to show it)" or "H: hide this tree", x0 + 16, y)
    end
    -- the keys
    local keys = {
      "Left click: select   Right drag: orbit   Middle / left drag: pan",
      "Wheel: zoom (over a setting: change it)",
      "Up / Down: setting   Left / Right: change (Shift: x5)",
      "Backspace: back to default   Tab: all trees / this tree",
      "B: battle camera   O: 45 degrees   T: from above",
      "G: check against the drawing (V: its view)",
      "Ctrl+S: save   Ctrl+R: back to saved   F5: rebuild   F12: shot",
      "Esc: quit",
    }
    G.setColor(0.6, 0.65, 0.7, 1)
    for i, line in ipairs(keys) do G.print(line, x0 + 16, H - 16 - (#keys - i + 1) * 17) end
    if status ~= "" and love.timer.getTime() - statusT < 6 then
      G.setColor(1, 0.9, 0.5, 1)
      G.printf(status, x0 + 16, H - 16 - (#keys + 2) * 17, PANEL_W - 32)
    end
  end
  hook("draw", function()
    local W, H = G.getDimensions()
    G.setCanvas()
    G.origin()
    G.clear(0.5, 0.6, 0.7, 1)
    -- the world at the camera's own lens, its 160 rows spanning the window's height
    local k = H / 160
    local c, u0, v0 = ws.view(pose(), W, H, k)
    view.u0, view.v0, view.k = u0 or 0, v0 or 0, k
    G.setShader()
    G.setBlendMode("alpha")
    G.setColor(1, 1, 1, 1)
    if c then G.draw(c, 0, 0) end
    if sel then
      G.setLineWidth(2)
      G.setColor(1, 0.85, 0.2, 1)
      for _, cell in ipairs(sel.cells) do outline(cell) end
    end
    drawProof(W, H)
    drawPanel(W, H)
  end)

  -- ── the loop: the game held still meanwhile ──
  local update = rawget(game, "update")
  game.update = function() end
  -- WORKSHOP_SELECT=x,y (map cells): that cell selected, the camera on it and its proof open (the
  -- review page's "Open in workshop" buttons)
  local selX, selY = (env("WORKSHOP_SELECT") or ""):match("(%-?%d+),(%-?%d+)")
  if selX and scene then
    local c = scene.grid.at(tonumber(selX), tonumber(selY))
    if c then
      selectCell(c)
      cam.tx, cam.tz = c.cx + 0.5, c.cy + 0.5
      prove()
    else
      say(("Cell %s,%s is outside the scene built here"):format(selX, selY))
    end
  end
  -- (dev: WORKSHOP_SCRIPT=file runs the workshop unattended - its own check - with these hooks)
  if env("WORKSHOP_SCRIPT") then
    return { select = selectCell, pick = pick, change = change, nudge = nudge, save = save, rebuild = rebuild,
             toggleHide = toggleHide, cam = cam, defs = function() return defs end, group = function() return GROUP end,
             setRow = function(r) row = r end,
             prove = prove, proof = function() return proof end, setView = function(v) proofView = v end, hd = hd,
             setScope = function(v) scope = v end, scene = function() return scene end, sel = function() return sel end,
             current = current, toScreen = toScreen, pose = pose, Camera = Camera, treePart = treePart,
             tuneFile = tuneFile, Tune = Tune, tuneGame = tuneGame, U = U, game = game,
             restore = function()
               for name, fn in pairs(saved) do love[name] = fn end
               game.update = update
             end }
  end
  while not quit do
    if dirty and love.timer.getTime() - dirtyAt > 0.25 then
      dirty = false
      rebuild()
    end
    -- (held keys move the camera)
    local kb = love.keyboard
    local step = cam.dist * 0.02
    local yw = math.rad(cam.yaw)
    local fx, fz = math.sin(yw), -math.cos(yw)
    local rx, rz = math.cos(yw), math.sin(yw)
    if kb.isDown("w") then cam.tx, cam.tz = cam.tx + fx * step, cam.tz + fz * step end
    if kb.isDown("s") and not kb.isDown("lctrl", "rctrl") then cam.tx, cam.tz = cam.tx - fx * step, cam.tz - fz * step end
    if kb.isDown("a") then cam.tx, cam.tz = cam.tx - rx * step, cam.tz - rz * step end
    if kb.isDown("d") then cam.tx, cam.tz = cam.tx + rx * step, cam.tz + rz * step end
    if kb.isDown("q") then cam.yaw = cam.yaw - 1.5 end
    if kb.isDown("e") then cam.yaw = cam.yaw + 1.5 end
    if kb.isDown("r") and not kb.isDown("lctrl", "rctrl") then cam.pitch = math.min(89, cam.pitch + 0.8) end
    if kb.isDown("f") then cam.pitch = math.max(5, cam.pitch - 0.8) end
    if kb.isDown("z") then cam.dist = math.max(1.5, cam.dist * 0.98) end
    if kb.isDown("x") then cam.dist = math.min(60, cam.dist * 1.02) end
    U.wait(1)
  end
  if unsaved then log("quit with unsaved changes (not written)") end
  for name, fn in pairs(saved) do love[name] = fn end
  game.update = update
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "."
  local logFile = io.open(dir .. "/workshop.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[workshop]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function()
    local hooks = body(game, log)
    -- (WORKSHOP_SCRIPT=file: a script run with the workshop's hooks, then the workshop's loop ends)
    if hooks then
      local fn = assert(loadfile(os.getenv("WORKSHOP_SCRIPT")))
      fn(hooks, log)
      hooks.restore()
    end
  end, debug.traceback)
  if not ok then log("ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
