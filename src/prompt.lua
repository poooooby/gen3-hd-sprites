-- WoobleView's own prompts: the first-run question about 3D battles (Emerald), building the 3D
-- cache with a progress bar, and short notices. Drawn at the window's own resolution over
-- everything (the engine's render.hud hook), WoobleView's name in the panel's corner so the
-- player knows which mod is asking. While a prompt is up, an empty layer on the game's screen
-- stack pauses the field and takes the buttons (keys, pad, the touch pad's); a click or a touch
-- on a button works too (input.pointer).
--
-- The engine has no prompt, progress or option-setting API for mods: the layer is the screen
-- stack's (src.ui.game3.stack), an option is set through the Mod Manager's own setter
-- (src.mods.ManagerState.setOption, as the Gen 3 manager calls it), and "asked already" is a
-- file in the mod's cache (P.FLAG), kept apart from what Clear 3D Cache deletes.
--
-- deps = { mod, Scene (src/scene/init.lua: cacheJob, cacheClear) }.

return function(deps)
  local mod, Scene = deps.mod, deps.Scene
  local P = {}
  local G = love.graphics
  local floor, min, max, sin, pi = math.floor, math.min, math.max, math.sin, math.pi

  P.FLAG = "state/first_run_asked"
  P.LAYER = "woobleview_prompt"
  P.BUDGET = 0.028            -- seconds of building a frame while the progress bar is up
  P.QUIET_FRAMES = 45         -- frames of a still field before the first-run question

  -- colours
  local INK = { 0.95, 0.96, 0.98 }
  local SOFT = { 0.68, 0.72, 0.78 }
  local FAINT = { 0.50, 0.55, 0.62 }
  local PANEL = { 0.075, 0.085, 0.11 }
  local ACCENT = { 0.42, 0.74, 1.00 }
  local ACCENT2 = { 0.37, 0.90, 0.77 }

  local game
  local state             -- the prompt up: { phase, t, focus, job, shown, ... }
  local notice            -- a short notice: { text, t }
  local buttons = {}      -- this frame's buttons on screen: { x, y, w, h, i }

  -- ── options ──────────────────────────────────────────────────────────

  local function option(key, default)
    local ok, v = pcall(function() return mod.options and mod.options:get(key) end)
    if ok and v ~= nil then return v end
    return default
  end

  --- Set one of WoobleView's options as the Mod Manager does (saved, and mod.options_changed
  --- emitted). Returns true when it was set.
  function P.setOption(key, value)
    local g = game or mod.game
    local okM, MS = pcall(require, "src.mods.ManagerState")
    if not (g and okM and type(MS) == "table" and MS.setOption) then return false end
    -- (Gen 3 keeps its saved options in game.options: the manager's own proxy)
    local proxy = setmetatable({ save = type(g.options) == "table" and { options = g.options } or g.save },
      { __index = g })
    local m = setmetatable({ game = proxy, notify = function() end }, { __index = MS })
    local ok = pcall(MS.setOption, m, mod.id, key, value)
    return ok
  end

  local function asked()
    local ok, yes = pcall(function() return mod.cache:exists(P.FLAG) end)
    return ok and yes
  end
  local function markAsked()
    pcall(function() mod.cache:write(P.FLAG, "asked") end)
  end

  local function isEmerald()
    local ok, GV = pcall(require, "src.core.GameVersion")
    return ok and type(GV) == "table" and GV.get and GV.get() == "emerald"
  end

  -- ── the layer that pauses the field and takes the buttons ─────────────

  local layer = {}
  local function Stack()
    local ok, S = pcall(require, "src.ui.game3.stack")
    return ok and type(S) == "table" and S or nil
  end
  local function close()
    state = nil
    local S = Stack()
    if S then pcall(S.pop, P.LAYER) end
    -- (the Build 3D Cache row back to PRESS A, however the build ended)
    if option("scene_build", "idle") == "go" then P.setOption("scene_build", "idle") end
  end
  local function open(phase, extra)
    state = { phase = phase, t = 0, focus = 1, shown = 0 }
    for k, v in pairs(extra or {}) do state[k] = v end
    local S = Stack()
    if S then pcall(S.push, P.LAYER, layer, { isMenu = true, hideBelow = false }) end
  end

  -- each phase's words and buttons
  local PHASES = {
    ask3d = {
      title = "Battle in the world around you?",
      body = "WoobleView can stage Emerald's battles in 3D, right where they start: the paths, "
        .. "trees, houses and water around you, with a camera that sweeps down into the fight. "
        .. "You can change this any time in OPTIONS > MODS > WoobleView.",
      buttons = { "Turn on 3D battles", "No thanks" },
    },
    askBuild = {
      title = "Build the 3D world now?",
      body = "It takes a minute or two, and every battle loads its world straight away from then "
        .. "on. Or skip it, and it builds a little at a time in the background while you play.",
      buttons = { "Build now", "Later" },
    },
    building = { title = "Building the 3D world", progress = true,
      foot = "Kept on this device, so it only happens once." },
    done = { title = "All set", body = "The 3D world is ready. Enjoy your battles!", buttons = { "Done" } },
    failed = { title = "Couldn't build it", buttons = { "OK" } },
  }

  local function startBuild()
    -- (what is built is kept and read back: Scene Cache on)
    if option("scene_cache", true) == false then P.setOption("scene_cache", true) end
    local ok, job = pcall(Scene.cacheJob)
    if not (ok and job) then
      open("failed", { body = "Something went wrong: " .. tostring(job) })
      return
    end
    if state then
      state.phase, state.t, state.job, state.shown = "building", 0, job, 0
    else
      open("building", { job = job })
    end
  end

  local function choose(i)
    if not state then return end
    local ph = state.phase
    if ph == "ask3d" then
      markAsked()
      if i == 1 then
        P.setOption("battle_scene", "overworld")
        state.phase, state.t, state.focus = "askBuild", 0, 1
      else
        close()
      end
    elseif ph == "askBuild" then
      if i == 1 then startBuild() else close() end
    elseif ph == "done" or ph == "failed" then
      close()
    end
  end

  function layer.handleInput(input)
    if not (state and input) then return end
    local def = PHASES[state.phase]
    local n = def and def.buttons and #def.buttons or 0
    if n == 0 then return end
    local function pressed(b) return input.wasPressed and input:wasPressed(b) end
    if pressed("left") or pressed("up") then state.focus = max(1, state.focus - 1) end
    if pressed("right") or pressed("down") then state.focus = min(n, state.focus + 1) end
    if pressed("a") or pressed("start") then choose(state.focus)
    elseif pressed("b") then choose(n) end
  end

  function layer.update(dt)
    if not state then return end
    if state.phase == "building" and state.job then
      local job = state.job
      local ok, done = pcall(job.step, P.BUDGET)
      if not ok then
        state.phase, state.t, state.body = "failed", 0, "Something went wrong: " .. tostring(done)
      elseif done then
        local why = job.failed()
        if why then
          state.phase, state.t, state.body = "failed", 0, "The land could not be built: " .. why
        else
          state.phase, state.t, state.focus = "done", 0, 1
        end
      end
    end
  end

  function layer.draw() end

  -- ── drawing ──────────────────────────────────────────────────────────

  local fonts = {}
  local function font(size)
    size = max(8, floor(size + 0.5))
    local f = fonts[size]
    if not f then
      f = G.newFont(size)
      fonts[size] = f
    end
    return f
  end

  local function col(c, a) G.setColor(c[1], c[2], c[3], a or 1) end

  --- The time left in words: nil (not yet known), seconds.
  function P.timeLeft(sec)
    if not sec then return "Working out the time left" end
    if sec < 8 then return "Almost done" end
    if sec < 50 then return ("About %d seconds left"):format(max(10, floor(sec / 5 + 0.5) * 5)) end
    local m = floor(sec / 60 + 0.5)
    if m <= 1 then return "About a minute left" end
    return ("About %d minutes left"):format(m)
  end
  local function easeOut(t) t = min(1, max(0, t)); return 1 - (1 - t) ^ 3 end

  -- a horizontal gradient bar (rounded by drawing its caps)
  local gradMesh
  local function gradient(x, y, w, h, a, b, alpha)
    if w <= 0 then return end
    local verts = {
      { x, y, 0, 0, a[1], a[2], a[3], alpha }, { x + w, y, 0, 0, b[1], b[2], b[3], alpha },
      { x + w, y + h, 0, 0, b[1], b[2], b[3], alpha }, { x, y + h, 0, 0, a[1], a[2], a[3], alpha },
    }
    if not gradMesh then gradMesh = G.newMesh(verts, "fan", "stream") else gradMesh:setVertices(verts) end
    G.setColor(1, 1, 1, 1)
    G.draw(gradMesh)
  end

  -- a soft band of light: clear at its sides, `alpha` white in its middle
  local shineMesh
  local function shine(x, y, w, h, alpha)
    local m = x + w / 2
    local verts = {
      { x, y, 0, 0, 1, 1, 1, 0 }, { m, y, 0, 0, 1, 1, 1, alpha }, { m, y + h, 0, 0, 1, 1, 1, alpha },
      { x, y + h, 0, 0, 1, 1, 1, 0 },
      { m, y, 0, 0, 1, 1, 1, alpha }, { x + w, y, 0, 0, 1, 1, 1, 0 }, { x + w, y + h, 0, 0, 1, 1, 1, 0 },
      { m, y + h, 0, 0, 1, 1, 1, alpha },
    }
    if not shineMesh then
      shineMesh = G.newMesh(8, "triangles", "stream")
      shineMesh:setVertexMap(1, 2, 3, 1, 3, 4, 5, 6, 7, 5, 7, 8)
    end
    shineMesh:setVertices(verts)
    G.setColor(1, 1, 1, 1)
    G.draw(shineMesh)
  end

  local function chip(x, y, s, alpha)
    local f = font(12 * s)
    local text = "WoobleView"
    local h = 24 * s
    local dot = 6 * s
    local w = 12 * s + dot + 7 * s + f:getWidth(text) + 12 * s
    col(ACCENT, 0.16 * alpha)
    G.rectangle("fill", x, y, w, h, h / 2, h / 2)
    col(ACCENT, alpha)
    G.circle("fill", x + 12 * s + dot / 2, y + h / 2, dot / 2)
    G.setFont(f)
    col(ACCENT, alpha)
    G.print(text, floor(x + 12 * s + dot + 7 * s), floor(y + (h - f:getHeight()) / 2))
    return w, h
  end

  local function drawPrompt(W, H)
    local def = PHASES[state.phase]
    if not def then return end
    local s = max(0.75, min(2.2, min(W / 1280, H / 720)))
    local a = easeOut(state.shown / 0.22)
    -- the world dimmed behind it
    G.setColor(0.02, 0.04, 0.08, 0.55 * a)
    G.rectangle("fill", 0, 0, W, H)
    local pad = 28 * s
    local pw = min(W - 32 * s, 560 * s)
    local inner = pw - 2 * pad
    local titleF, bodyF, smallF = font(24 * s), font(15 * s), font(13 * s)
    local body = state.body or def.body
    local lines = {}
    if body then
      local _, l = bodyF:getWrap(body, inner)
      lines = l
    end
    local bodyH = body and #lines * bodyF:getHeight() * 1.25 or 0
    local btnH = 42 * s
    local ph = pad + 24 * s + 16 * s + titleF:getHeight() + (body and (12 * s + bodyH) or 0)
    if def.progress then
      ph = ph + 22 * s + bodyF:getHeight() + 10 * s + 8 * s + 12 * s + smallF:getHeight()
        + (def.foot and 6 * s + smallF:getHeight() or 0)
    end
    if def.buttons then ph = ph + 26 * s + btnH end
    ph = ph + pad
    local px = floor((W - pw) / 2)
    local py = floor((H - ph) / 2 + (1 - a) * 18 * s)
    local r = 18 * s
    -- a soft shadow, the panel, its hairline edge
    for k = 3, 1, -1 do
      G.setColor(0, 0, 0, 0.10 * a)
      G.rectangle("fill", px - k * 4 * s, py - k * 3 * s + 8 * s, pw + k * 8 * s, ph + k * 6 * s, r + k * 4 * s)
    end
    col(PANEL, 0.96 * a)
    G.rectangle("fill", px, py, pw, ph, r, r)
    G.setColor(1, 1, 1, 0.08 * a)
    G.setLineWidth(max(1, s))
    G.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, r, r)
    -- WoobleView in the corner
    local y = py + pad
    chip(px + pad, y, s, a)
    y = y + 24 * s + 16 * s
    G.setFont(titleF)
    col(INK, a)
    G.print(def.title, px + pad, floor(y))
    y = y + titleF:getHeight()
    if body then
      y = y + 12 * s
      G.setFont(bodyF)
      col(SOFT, a)
      for _, line in ipairs(lines) do
        G.print(line, px + pad, floor(y))
        y = y + bodyF:getHeight() * 1.25
      end
    end
    if def.progress and state.job then
      local okP, target = pcall(state.job.progress)
      target = okP and target or 0
      state.bar = (state.bar or 0) + (target - (state.bar or 0)) * min(1, (state.dt or 0) * 6)
      local okS, stage = pcall(state.job.stage)
      y = y + 22 * s
      G.setFont(bodyF)
      col(SOFT, a)
      local dots = ("..."):sub(1, 1 + floor(state.t * 2) % 3)
      G.print((okS and stage or "Working") .. dots, px + pad, floor(y))
      local pct = ("%d%%"):format(floor(state.bar * 100 + 0.5))
      col(INK, a)
      G.print(pct, floor(px + pw - pad - bodyF:getWidth(pct)), floor(y))
      y = y + bodyF:getHeight() + 10 * s
      local th = 8 * s
      G.setColor(1, 1, 1, 0.08 * a)
      G.rectangle("fill", px + pad, y, inner, th, th / 2, th / 2)
      local fw = max(th, inner * state.bar)
      -- the fill: a gradient from the accent to the second accent across the whole bar, so it
      -- deepens as it grows, with round caps; and a light running along it
      local x0, rr = px + pad, th / 2
      local k = fw / inner
      local endC = { ACCENT[1] + (ACCENT2[1] - ACCENT[1]) * k, ACCENT[2] + (ACCENT2[2] - ACCENT[2]) * k,
                     ACCENT[3] + (ACCENT2[3] - ACCENT[3]) * k }
      col(ACCENT, a)
      G.circle("fill", x0 + rr, y + rr, rr)
      col(endC, a)
      G.circle("fill", x0 + fw - rr, y + rr, rr)
      gradient(x0 + rr, y, fw - th, th, ACCENT, endC, a)
      local sweep = (love.timer.getTime() * 0.6) % 1.4 - 0.2
      local sx = x0 + sweep * fw
      G.setScissor(floor(x0 + rr), floor(y), max(0, floor(fw - th)), math.ceil(th))
      shine(sx - 40 * s, y, 80 * s, th, 0.32 * a)
      G.setScissor()
      y = y + th
      -- the time left: the time so far over the share done, counting down between frames and
      -- settling gently on the estimate so it does not jump about
      -- (by the real clock: a frame of building is longer than the game's step)
      local now = love.timer.getTime()
      state.since = state.since or now
      local dt = now - (state.lastNow or now)
      state.lastNow = now
      local spent = now - state.since
      -- (the bar's pace over the last 20 seconds: its phases are not all alike)
      local smp = state.samples or {}
      state.samples = smp
      if #smp == 0 or now - smp[#smp][1] >= 0.5 then smp[#smp + 1] = { now, target } end
      while #smp > 2 and now - smp[1][1] > 20 do table.remove(smp, 1) end
      local first = smp[1]
      local rate = now - first[1] > 4 and (target - first[2]) / (now - first[1]) or 0
      if spent > 6 and rate > 0 then
        local remain = (1 - target) / rate
        if not state.eta then
          state.eta = remain
        else
          state.eta = max(0, state.eta - dt)
          state.eta = state.eta + (remain - state.eta) * min(1, dt * 0.8)
        end
      end
      y = y + 12 * s
      G.setFont(smallF)
      col(SOFT, a)
      G.print(P.timeLeft(state.eta), px + pad, floor(y))
      y = y + smallF:getHeight()
      if def.foot then
        y = y + 6 * s
        col(FAINT, a)
        G.print(def.foot, px + pad, floor(y))
        y = y + smallF:getHeight()
      end
    end
    -- the buttons, right-aligned, the first the main one
    buttons = {}
    if def.buttons then
      y = y + 26 * s
      local f = font(15 * s)
      G.setFont(f)
      local x = px + pw - pad
      for i = #def.buttons, 1, -1 do
        local label = def.buttons[i]
        local bw = max(116 * s, f:getWidth(label) + 44 * s)
        x = x - bw
        local focus = state.focus == i
        local primary = i == 1
        if focus then
          col(ACCENT, 0.55 * a)
          G.setLineWidth(2 * s)
          G.rectangle("line", x - 3 * s, y - 3 * s, bw + 6 * s, btnH + 6 * s, (btnH + 6 * s) / 2)
        end
        if primary then
          col(ACCENT, a)
          G.rectangle("fill", x, y, bw, btnH, btnH / 2, btnH / 2)
          G.setColor(0.04, 0.07, 0.12, a)
        else
          G.setColor(1, 1, 1, (focus and 0.12 or 0.06) * a)
          G.rectangle("fill", x, y, bw, btnH, btnH / 2, btnH / 2)
          col(INK, a)
        end
        G.print(label, floor(x + (bw - f:getWidth(label)) / 2), floor(y + (btnH - f:getHeight()) / 2))
        buttons[#buttons + 1] = { x = x, y = y, w = bw, h = btnH, i = i }
        x = x - 12 * s
      end
    end
  end

  local function drawNotice(W, H)
    local s = max(0.75, min(2.2, min(W / 1280, H / 720)))
    local t = notice.t
    local a = min(easeOut(t / 0.2), easeOut((P.NOTICE_TIME - t) / 0.3))
    if a <= 0 then return end
    local f = font(14 * s)
    local cw = 12 * s + 6 * s + 7 * s + font(12 * s):getWidth("WoobleView") + 12 * s
    local h = 44 * s
    local w = 10 * s + cw + 12 * s + f:getWidth(notice.text) + 18 * s
    local x = floor((W - w) / 2)
    local y = floor(H - h - 28 * s + (1 - a) * 12 * s)
    G.setColor(0, 0, 0, 0.18 * a)
    G.rectangle("fill", x - 4 * s, y + 4 * s, w + 8 * s, h + 4 * s, h / 2 + 4 * s)
    col(PANEL, 0.96 * a)
    G.rectangle("fill", x, y, w, h, h / 2, h / 2)
    G.setColor(1, 1, 1, 0.08 * a)
    G.setLineWidth(max(1, s))
    G.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, h / 2, h / 2)
    chip(x + 10 * s, y + (h - 24 * s) / 2, s, a)
    G.setFont(f)
    col(INK, a)
    G.print(notice.text, floor(x + 10 * s + cw + 12 * s), floor(y + (h - f:getHeight()) / 2))
  end

  -- ── the engine's hooks ───────────────────────────────────────────────

  P.NOTICE_TIME = 2.6
  --- A short notice at the foot of the screen, WoobleView's name beside it.
  function P.notify(text)
    notice = { text = text, t = 0 }
  end

  --- Build the 3D cache now, the progress bar up (Build 3D Cache). False when a prompt is up.
  function P.build()
    if state then return false end
    startBuild()
    return true
  end

  --- Clear the 3D cache (Clear 3D Cache).
  function P.clear()
    if state and state.phase == "building" then return false end
    local ok = pcall(Scene.cacheClear)
    P.notify(ok and "3D cache cleared" or "Couldn't clear the 3D cache")
    return ok
  end

  local quiet = 0
  -- (through require: a mod's package.loaded is not the engine's)
  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local function fieldQuiet()
    local F = engine("src.core.game3.field")
    local B = engine("src.core.game3.battle")
    if not (F and F.running) then return false end
    if B and B.isActive and B.isActive() then return false end
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    return okR and Runtime.uiBusy and not Runtime.uiBusy()
  end

  local function tick(dt)
    if notice then
      notice.t = notice.t + dt
      if notice.t >= P.NOTICE_TIME then notice = nil end
    end
    if state then
      state.t, state.shown, state.dt = state.t + dt, state.shown + dt, dt
      -- (the layer was taken off by something else: back on)
      local S = Stack()
      if S and S.top and (not S.top() or S.top().id ~= P.LAYER) then
        local up = false
        for _, l in ipairs(S._layers or {}) do if l.id == P.LAYER then up = true end end
        if not up then pcall(S.push, P.LAYER, layer, { isMenu = true, hideBelow = false }) end
      end
      if state.phase == "done" and state.t > 2.4 then close() end
      return
    end
    -- the first-run question and a build asked for before the game started, once the field is
    -- still: Emerald only
    if fieldQuiet() then quiet = quiet + 1 else quiet = 0 end
    if quiet < P.QUIET_FRAMES or not isEmerald() then return end
    if option("scene_build", "idle") == "go" then
      quiet = 0
      startBuild()
    elseif not asked() then
      quiet = 0
      if option("battle_scene", "classic") == "overworld" then
        markAsked()       -- (already chosen: nothing to ask)
      else
        open("ask3d")
      end
    end
  end

  -- (dev: the drivers' frames skip core.update - a tick by hand, and the phase up or nil)
  function P._tick(dt) tick(dt or 1 / 60) end
  function P.phase() return state and state.phase or nil end
  function P._why()
    local F = engine("src.core.game3.field")
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    return ("field %s, busy %s, emerald %s, asked %s, quiet %d, scene %s"):format(tostring(F and F.running),
      tostring(okR and Runtime.uiBusy and Runtime.uiBusy()), tostring(isEmerald()), tostring(asked()), quiet,
      tostring(option("battle_scene", "classic")))
  end

  function P.install()
    mod.hooks:wrap("core.update", function(next, g, dt)
      next(g, dt)
      game = g
      local ok, err = pcall(tick, dt or 1 / 60)
      if not ok then mod.log:warn("prompt: %s", tostring(err)) end
    end)
    mod.hooks:wrap("render.hud", function(next, g, viewport)
      next(g, viewport)
      if not (state or notice) then return end
      local W = viewport and viewport.width or G.getWidth()
      local H = viewport and viewport.height or G.getHeight()
      G.push("all")
      G.origin()
      G.setScissor()
      if state then pcall(drawPrompt, W, H) end
      if notice then pcall(drawNotice, W, H) end
      G.pop()
    end)
    -- a click or a touch on a button
    mod.hooks:wrap("input.pointer", function(next, g, ev)
      if state and ev then
        if ev.phase == "released" then
          for _, b in ipairs(buttons) do
            if ev.x >= b.x and ev.x <= b.x + b.w and ev.y >= b.y and ev.y <= b.y + b.h then
              state.focus = b.i
              choose(b.i)
              break
            end
          end
        end
        return true
      end
      return next(g, ev)
    end)
  end

  return P
end
