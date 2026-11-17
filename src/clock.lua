-- The time of day the battle scene (Battle Scene: Overworld) is lit by: the minute of the day,
-- 0..1440, or nil (no time of day: the light as by day).
--
-- Whose clock: WoobleDex's (national_dex_gen3), when it is installed, so a battle is lit as its
-- Day & Night look tints the overworld around it: its Clock Source (exports.clockSource, else its
-- stored clock_source option), and none at all while its Day & Night option is off. Without it,
-- the game's: Ruby, Sapphire and Emerald their own clock (src/core/game3/rtc.lua
-- calcLocalTime, the device's time shifted by what the player set in the game), FireRed and
-- LeafGreen, which have none, the device's. Read at most once a second.
return function(mod)
  local Clock = {}
  Clock.DEX = "national_dex_gen3"
  Clock.EVERY = 1.0

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  local function dexOption(key)
    local ok, v = pcall(function()
      local o = mod.game.mods.modOptions
      return o and o[Clock.DEX] and o[Clock.DEX][key]
    end)
    if ok then return v end
    return nil
  end

  --- WoobleDex, when it is installed (its loader entry), else nil.
  function Clock.dex()
    local ok, d = pcall(function() return mod:find(Clock.DEX) end)
    return ok and type(d) == "table" and d or nil
  end

  --- "game" or "device": WoobleDex's Clock Source, else the game's.
  function Clock.source()
    local d = Clock.dex()
    if not d then return "game" end
    local fn = type(d.exports) == "table" and d.exports.clockSource
    if type(fn) == "function" then
      local ok, v = pcall(fn)
      if ok and (v == "game" or v == "device") then return v end
    end
    local stored = dexOption("clock_source")
    return (stored == "game" or stored == "device") and stored or "game"
  end

  --- false while WoobleDex is installed with its Day & Night option off.
  function Clock.allowed()
    return not (Clock.dex() and dexOption("day_night") == false)
  end

  local function session()
    local ok, s = pcall(function() return mod.game and mod.game.session end)
    if ok and type(s) == "table" then return s end
    local Runtime = engine("src.core.game3.runtime")
    if Runtime and type(Runtime.getSession) == "function" then
      local okS, live = pcall(Runtime.getSession)
      if okS and type(live) == "table" then return live end
    end
    return nil
  end

  --- The minute of the day by the clock `source` ("game": the cart's own where it has one).
  function Clock.read(source)
    local Rtc = engine("src.core.game3.rtc")
    if not Rtc then
      local t = os.date("*t")
      return t.hour * 60 + t.min + t.sec / 60
    end
    if source ~= "device" and type(Rtc.enabled) == "function" and type(Rtc.calcLocalTime) == "function" then
      local s = session()
      local okE, on = pcall(Rtc.enabled, s)
      if okE and on then
        local ok, t = pcall(Rtc.calcLocalTime, s)
        if ok and type(t) == "table" and tonumber(t.hours) then
          return (tonumber(t.hours) % 24) * 60 + (tonumber(t.minutes) or 0) + (tonumber(t.seconds) or 0) / 60
        end
      end
    end
    local ok, info = pcall(Rtc.hostInfo, nil)
    if ok and type(info) == "table" and tonumber(info.hour) then
      return tonumber(info.hour) * 60 + (tonumber(info.minute) or 0) + (tonumber(info.second) or 0) / 60
    end
    local t = os.date("*t")
    return t.hour * 60 + t.min + t.sec / 60
  end

  local last, lastAt = nil, nil
  --- The minute of the day the scene is lit by now, or nil (WoobleDex's Day & Night off).
  function Clock.minute()
    local now = love and love.timer and love.timer.getTime() or os.clock()
    if lastAt and now - lastAt < Clock.EVERY then return last end
    lastAt = now
    if not Clock.allowed() then
      last = nil
    else
      local ok, m = pcall(Clock.read, Clock.source())
      last = ok and m or nil
    end
    return last
  end

  return Clock
end
