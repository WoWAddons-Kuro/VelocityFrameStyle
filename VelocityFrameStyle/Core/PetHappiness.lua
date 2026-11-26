-- Velocity Frame Style: hunter-pet happiness model (SPECS/10_Pet_Happiness_Panel.md). Pure data: no frames, no events of
-- its own; the panel feeds it readings and asks it to describe the state. Method lifted from HunterPetHappiness (Beleriand)
-- with credit: exact tier from the Happiness power type with a MEASURED drain rate and LEARNED mood floors; learned tier
-- (median of recent fed->dropped-from-Happy durations) when the exact value is not readable.
--
-- Era ground truth 2026-11-25: Enum.PowerType.Happiness == 27, UnitPower("pet", 27) -> 976 / 1000 plain. Index 4 is a dead
-- 0/5 slot on Era, so the index is ALWAYS resolved through the enum and a max <= 5 is treated as "not happiness".
--
-- VFS_PetHappinessReading  = { mood = 1|2|3|nil, damagePct, loyaltyRate, value, max, petName, inCombat, zoned }  (one poll)
-- VFS_PetHappinessState    = see PetHappiness.New()
-- VFS_PetHappinessSummary  = PetHappiness.Describe(state) -> display-ready fields, all strings/numbers, nothing secret
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local PetHappiness = {}
VFS.PetHappiness = PetHappiness

-- HPH-measured constants
PetHappiness.DRAIN_SEC_PER_POINT = 7.25   -- fallback drain until measured: ~1 point every 7.25 s, everywhere
PetHappiness.DISMISS_COST = 50
PetHappiness.DEATH_COST = 330
PetHappiness.SUMMON_SETTLE_SEC = 5        -- the game reports a wrong value for a few seconds after a summon
PetHappiness.ZONE_IGNORE_SEC = 20         -- drops within this of a zone change say nothing about the drain
PetHappiness.DEFAULT_HAPPY_FLOOR = 2 / 3  -- learned from transitions; defaults are the 667/333 cut-offs on a 1000 scale
PetHappiness.DEFAULT_CONTENT_FLOOR = 1 / 3
PetHappiness.NOT_HAPPINESS_MAX = 5        -- a power max at or below this is a dead slot, not the happiness scale
PetHappiness.MOOD = {
  [1] = { name = "Unhappy", color = { 0.90, 0.20, 0.20 }, coords = { 0.375, 0.5625, 0, 0.359375 } },
  [2] = { name = "Content", color = { 0.95, 0.80, 0.20 }, coords = { 0.1875, 0.375, 0, 0.359375 } },
  [3] = { name = "Happy",   color = { 0.25, 0.85, 0.35 }, coords = { 0, 0.1875, 0, 0.359375 } },
}

-- State ------------------------------------------------------------------------------------
function PetHappiness.New(persisted)
  local p = persisted or {}
  return {
    mood = nil, damagePct = nil, loyaltyRate = nil,
    value = nil, max = nil,                       -- exact tier when both are plain numbers and max > NOT_HAPPINESS_MAX
    decayRatePerSec = p.decayRatePerSec,          -- points per second, EMA 0.7/0.3 over windows >= 60 s
    happyFloor = p.happyFloor, contentFloor = p.contentFloor,   -- fractions of max, learned at mood transitions
    samples = p.samples or {},                    -- learned tier: seconds each Happy spell lasted (max 5)
    lastFedAt = nil, happySince = nil,            -- GetTime() clocks; restored from epochs by the caller
    summonedAt = nil, lastZoneAt = nil,
    accPoints = 0, accSeconds = 0,                -- drain measurement window
    lastValue = nil, lastValueAt = nil,
    spellHit = nil,                               -- "died" | "dismissed": this Happy spell is not a clean sample
  }
end

-- Persisted subset (the panel stores this under VelocityFrameStyleDB.petHappiness[petName])
function PetHappiness.Persist(state)
  return { decayRatePerSec = state.decayRatePerSec, happyFloor = state.happyFloor, contentFloor = state.contentFloor,
    samples = Util.DeepCopy(state.samples) }
end

-- Reading the game (thin; everything through Util so secrets never reach arithmetic) --------------------
function PetHappiness.PowerIndex()
  return Enum and Enum.PowerType and Enum.PowerType.Happiness or nil
end

-- -> VFS_PetHappinessReading or nil when there is no hunter pet
function PetHappiness.Read(now)
  if not UnitExists("pet") then return nil end
  local hasUI, isHunterPet = HasPetUI()
  if not isHunterPet then return nil end
  local r = { petName = Util.Plain(UnitName("pet")), inCombat = InCombatLockdown() == true, dead = UnitIsDead("pet") == true }
  local fn = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness
  if fn then
    local ok, mood, dmg, loyalty = pcall(fn)
    if ok then
      r.mood = Util.PlainNumber(mood, nil)
      r.damagePct = Util.PlainNumber(dmg, nil)
      r.loyaltyRate = Util.PlainNumber(loyalty, nil)
    end
  end
  local idx = PetHappiness.PowerIndex()
  if idx then
    local v = Util.PlainNumber(UnitPower("pet", idx), nil)
    local m = Util.PlainNumber(UnitPowerMax("pet", idx), nil)
    if v and m and m > PetHappiness.NOT_HAPPINESS_MAX then r.value, r.max = v, m end
  end
  return r
end

-- Model update --------------------------------------------------------------------------------
local function Median(list)
  if not list or #list == 0 then return nil end
  local t = {}; for i, v in ipairs(list) do t[i] = v end
  table.sort(t)
  local n = #t
  if n % 2 == 1 then return t[(n + 1) / 2] end
  return (t[n / 2] + t[n / 2 + 1]) / 2
end
PetHappiness.Median = Median

-- A fed->dropped duration is kept unless it is clearly a freak reading.
function PetHappiness.AddSample(state, sec)
  if sec < 20 then return false, "under 20 seconds" end
  if sec > 3600 then return false, "over an hour" end
  local typical = Median(state.samples)
  if #state.samples >= 3 and typical and sec < typical * 0.5 then return false, "much sooner than usual" end
  table.insert(state.samples, sec)
  while #state.samples > 5 do table.remove(state.samples, 1) end
  return true
end

function PetHappiness.MarkFed(state, now)
  state.lastFedAt = now
  state.spellHit = nil
  state.dismissals = 0
end

function PetHappiness.MarkSummoned(state, now) state.summonedAt = now end
function PetHappiness.MarkZoned(state, now) state.lastZoneAt = now end
function PetHappiness.MarkDied(state) state.spellHit = "died"; state.accPoints, state.accSeconds = 0, 0 end
function PetHappiness.MarkDismissed(state) state.dismissals = (state.dismissals or 0) + 1; state.accPoints, state.accSeconds = 0, 0 end

local function JustZoned(state, now)
  return state.lastZoneAt ~= nil and now - state.lastZoneAt < PetHappiness.ZONE_IGNORE_SEC
end

-- Exact tier: measure the normal drain. Steps are small, so average over >= 60 s; a gain (feed) or a hit > 2% of max
-- (death, zoning, dismiss) resets the window rather than polluting the rate.
local function TrackDrain(state, value, max, now)
  if state.lastValue and state.lastValueAt then
    local dt, dv = now - state.lastValueAt, state.lastValue - value
    if dt > 0 then
      if dv < 0 or dv > max * 0.02 then
        state.accPoints, state.accSeconds = 0, 0
      else
        state.accPoints, state.accSeconds = state.accPoints + dv, state.accSeconds + dt
      end
      if state.accSeconds >= 60 and state.accPoints > 0 then
        local rate = state.accPoints / state.accSeconds
        state.decayRatePerSec = state.decayRatePerSec and (state.decayRatePerSec * 0.7 + rate * 0.3) or rate
        state.accPoints, state.accSeconds = 0, 0
      end
    end
  end
  state.lastValue, state.lastValueAt = value, now
end

-- Apply one reading. Returns the previous mood when the mood changed (so the caller can react), else nil.
function PetHappiness.Update(state, reading, now)
  if not reading then
    state.mood, state.value, state.max = nil, nil, nil
    state.lastValue, state.lastValueAt, state.accPoints, state.accSeconds = nil, nil, 0, 0
    return nil
  end
  if state.summonedAt and now - state.summonedAt < PetHappiness.SUMMON_SETTLE_SEC then return nil end
  state.damagePct, state.loyaltyRate = reading.damagePct, reading.loyaltyRate
  local prev, mood = state.mood, reading.mood
  local changed = prev ~= nil and mood ~= nil and mood ~= prev
  -- exact value first so a transition can learn its floor from the value that produced it
  if reading.value and reading.max then
    state.value, state.max = reading.value, reading.max
    if changed and mood < prev and not JustZoned(state, now) and not state.spellHit then
      local frac = reading.value / reading.max
      if prev == 3 and mood == 2 then state.happyFloor = frac end
      if prev == 2 and mood == 1 then state.contentFloor = frac end
    end
    TrackDrain(state, reading.value, reading.max, now)
  else
    state.value, state.max = nil, nil
  end
  if changed then
    if mood < prev then
      -- it dropped: a drop FROM Happy closes a spell whose length teaches the learned tier
      local start = state.lastFedAt and state.happySince and math.max(state.lastFedAt, state.happySince) or state.lastFedAt or state.happySince
      if prev == 3 and start and not state.spellHit and not JustZoned(state, now) then
        local nd = state.dismissals or 0
        PetHappiness.AddSample(state, now - start + nd * PetHappiness.DISMISS_COST * PetHappiness.DRAIN_SEC_PER_POINT)
      end
    elseif not state.lastFedAt or now - state.lastFedAt > 30 then
      PetHappiness.MarkFed(state, now)   -- it went up without a seen feed: count that as one
    end
    if mood == 3 then state.happySince = now; state.spellHit = nil; state.dismissals = 0 end
  elseif prev == nil and mood == 3 and not state.happySince then
    state.happySince = now
  end
  state.mood = mood
  return changed and prev or nil
end

-- Derived ------------------------------------------------------------------------------------
function PetHappiness.Tier(state)
  if state.value and state.max then return "exact" end
  if state.mood then return "learned" end
  return nil
end

-- Seconds until the next lower mood, or nil when unknown. Exact: distance to the current mood's floor at the measured
-- (or default) drain. Learned: typical Happy length minus elapsed; only defined while Happy.
function PetHappiness.SecondsToNextMood(state, now)
  if PetHappiness.Tier(state) == "exact" then
    local floorFrac = (state.mood == 3 and (state.happyFloor or PetHappiness.DEFAULT_HAPPY_FLOOR))
      or (state.mood == 2 and (state.contentFloor or PetHappiness.DEFAULT_CONTENT_FLOOR)) or nil
    if not floorFrac then return nil end
    local rate = state.decayRatePerSec or (1 / PetHappiness.DRAIN_SEC_PER_POINT)
    if rate <= 0 then return nil end
    return math.max(0, state.value - floorFrac * state.max) / rate, state.decayRatePerSec ~= nil
  end
  if state.mood == 3 then
    local typical = Median(state.samples)
    local start = state.lastFedAt and state.happySince and math.max(state.lastFedAt, state.happySince) or state.lastFedAt or state.happySince
    if typical and start then return math.max(0, typical - (now - start)), true end
  end
  return nil
end

function PetHappiness.FormatTime(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec >= 3600 then return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60) end
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Compact in-bar form: "5m 12s", "1h 02m", "42s" (owner: the segment reads "~5m 12s").
function PetHappiness.FormatShort(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec >= 3600 then return string.format("%dh %02dm", math.floor(sec / 3600), math.floor(sec / 60) % 60) end
  if sec >= 60 then return string.format("%dm %02ds", math.floor(sec / 60), sec % 60) end
  return string.format("%ds", sec)
end

-- -> VFS_PetHappinessSummary (display-ready). Every estimate carries a leading "~".
function PetHappiness.Describe(state, now)
  local mood = PetHappiness.MOOD[state.mood or 0]
  local s = {
    tier = PetHappiness.Tier(state),
    moodName = mood and mood.name or "Unknown",
    moodColor = mood and mood.color or { 0.6, 0.6, 0.65 },
    moodCoords = mood and mood.coords or PetHappiness.MOOD[3].coords,
    pct = nil, valueText = nil, barFraction = nil, floorFractions = nil,
    etaText = nil, damageText = nil, loyaltyText = nil, fedText = nil,
  }
  if state.damagePct then s.damageText = string.format("%d%% damage", state.damagePct) end
  if state.loyaltyRate then
    if state.loyaltyRate > 0 then s.loyaltyText = string.format("loyalty +%d", state.loyaltyRate)
    elseif state.loyaltyRate < 0 then s.loyaltyText = string.format("loyalty %d", state.loyaltyRate)
    else s.loyaltyText = "loyalty steady" end
  end
  if state.lastFedAt then s.fedText = "fed " .. PetHappiness.FormatTime(now - state.lastFedAt) .. " ago" end
  if s.tier == "exact" then
    s.pct = math.floor(state.value / state.max * 100 + 0.5)
    s.valueText = tostring(state.value)
    s.barFraction = state.value / state.max
    s.floorFractions = { state.happyFloor or PetHappiness.DEFAULT_HAPPY_FLOOR, state.contentFloor or PetHappiness.DEFAULT_CONTENT_FLOOR }
    local eta, measured = PetHappiness.SecondsToNextMood(state, now)
    if state.mood == 1 then s.etaText = "feed now"
    elseif eta then s.etaText = "~" .. PetHappiness.FormatTime(eta) .. " to " .. (state.mood == 3 and "Content" or "Unhappy") .. (measured and "" or " (est.)")
    end
  elseif s.tier == "learned" then
    local eta, known = PetHappiness.SecondsToNextMood(state, now)
    if state.mood == 1 or state.mood == 2 then s.etaText = "feed now"
    elseif eta and known then s.etaText = eta > 0 and ("~" .. PetHappiness.FormatTime(eta) .. " left") or "overdue"
    else s.etaText = "learning..." end
  end
  return s
end