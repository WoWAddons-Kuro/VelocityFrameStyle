-- Run from repository root: lua5.1 Tests/PetHappiness.lua
-- Pure-model tests for Core/PetHappiness.lua with a fake clock and a fake pet. No frames.
local ns = {}
assert(loadfile('VelocityFrameStyle/Core/Util.lua'))('VelocityFrameStyle', ns)
assert(loadfile('VelocityFrameStyle/Core/PetHappiness.lua'))('VelocityFrameStyle', ns)
local PH = ns.PetHappiness

-- Fake game ---------------------------------------------------------------------------------
local game = { petExists = true, hunterPet = true, mood = 3, dmg = 125, loyalty = 20, power = { [27] = { 976, 1000 }, [4] = { 0, 5 } }, combat = false, dead = false, name = 'Owl' }
function UnitExists(u) return u == 'pet' and game.petExists end
function HasPetUI() return game.petExists, game.hunterPet end
function UnitName() return game.name end
function InCombatLockdown() return game.combat end
function UnitIsDead() return game.dead end
function GetPetHappiness() return game.mood, game.dmg, game.loyalty end
function UnitPower(_, idx) local p = game.power[idx]; return p and p[1] or 0 end
function UnitPowerMax(_, idx) local p = game.power[idx]; return p and p[2] or 0 end
Enum = { PowerType = { Happiness = 27 } }

-- Index resolution + dead-slot rejection (Era ground truth: 27 -> 976/1000; 4 -> 0/5) ---------------
assert(PH.PowerIndex() == 27)
local r = PH.Read(0)
assert(r.mood == 3 and r.damagePct == 125 and r.loyaltyRate == 20, 'GetPetHappiness fields')
assert(r.value == 976 and r.max == 1000, 'exact value from index 27')
Enum.PowerType.Happiness = 4
r = PH.Read(0)
assert(r.value == nil and r.max == nil, 'a 0/5 slot must not be taken as happiness')
Enum.PowerType.Happiness = 27
game.hunterPet = false; assert(PH.Read(0) == nil, 'non-hunter pet: no reading'); game.hunterPet = true
game.petExists = false; assert(PH.Read(0) == nil, 'no pet: no reading'); game.petExists = true

-- Exact tier: drain measured over >= 60 s, gains and big hits reset the window --------------------
local st = PH.New()
local now = 1000
local function feed(value, mood, dt)
  now = now + (dt or 0)
  game.power[27][1] = value; game.mood = mood or game.mood
  return PH.Update(st, PH.Read(now), now)
end
feed(976, 3, 0)
assert(PH.Tier(st) == 'exact' and st.mood == 3 and st.happySince == 1000)
assert(st.decayRatePerSec == nil, 'no rate before 60 s of data')
-- 1 point per 7.25 s for 72.5 s -> 10 points
for i = 1, 10 do feed(976 - i, nil, 7.25) end
assert(st.decayRatePerSec and math.abs(st.decayRatePerSec - 1 / 7.25) < 1e-6, 'measured rate ~ 1/7.25')
local before = st.decayRatePerSec
feed(990, nil, 7.25)        -- a feed (gain) must reset the window, not change the rate
assert(st.decayRatePerSec == before and st.accSeconds == 0)
feed(600, nil, 7.25)        -- a hit > 2% of max resets too
assert(st.decayRatePerSec == before and st.accSeconds == 0)

-- ETA math: exact -> (value - floor*max) / rate; default floors 2/3 and 1/3 ----------------------
feed(800, 3, 1)
local eta, measured = PH.SecondsToNextMood(st, now)
assert(measured == true)
assert(math.abs(eta - (800 - 1000 * 2 / 3) / (1 / 7.25)) < 1e-6, 'eta to Content from 800')
local d = PH.Describe(st, now)
assert(d.tier == 'exact' and d.pct == 80 and d.valueText == '800' and d.moodName == 'Happy')
assert(d.etaText:sub(1, 1) == '~' and d.etaText:find('to Content'), d.etaText)
assert(d.damageText == '125% damage' and d.loyaltyText == 'loyalty +20')
assert(d.floorFractions[1] > 0.66 and d.floorFractions[2] < 0.34)

-- Floor learning at a transition; the value at the drop becomes the learned floor ------------------
feed(640, 2, 1)
assert(st.mood == 2 and math.abs(st.happyFloor - 0.64) < 1e-9, 'Happy->Content learns happyFloor from the value')
feed(300, 1, 1)
assert(math.abs(st.contentFloor - 0.30) < 1e-9, 'Content->Unhappy learns contentFloor')
assert(PH.Describe(st, now).etaText == 'feed now', 'Unhappy says feed now')
-- A transition right after zoning must NOT teach a floor
local st2 = PH.New(); now = 5000
game.power[27][1] = 900; game.mood = 3; PH.Update(st2, PH.Read(now), now)
PH.MarkZoned(st2, now)
now = now + 5; game.power[27][1] = 500; game.mood = 2; PH.Update(st2, PH.Read(now), now)
assert(st2.happyFloor == nil, 'drop within 20 s of a zone teaches nothing')

-- Summon settle: readings inside the first 5 s are ignored ------------------------------------
local st3 = PH.New(); now = 9000
PH.MarkSummoned(st3, now)
game.power[27][1] = 1; game.mood = 1
PH.Update(st3, PH.Read(now + 2), now + 2)
assert(st3.mood == nil, 'garbage during settle is ignored')
PH.Update(st3, PH.Read(now + 6), now + 6)
assert(st3.mood == 1, 'read after settle')

-- Learned tier (no exact value): median of samples, rejection rules, ETA ------------------------
game.power[27] = nil   -- pretend the power is unreadable
local st4 = PH.New(); now = 20000
game.mood = 3; PH.Update(st4, PH.Read(now), now)
assert(PH.Tier(st4) == 'learned' and st4.happySince == now)
assert(PH.Describe(st4, now).etaText == 'learning...', 'no samples yet')
PH.MarkFed(st4, now)
now = now + 1800; game.mood = 2; PH.Update(st4, PH.Read(now), now)
assert(#st4.samples == 1 and st4.samples[1] == 1800, 'fed->dropped adds a sample')
assert(select(2, PH.AddSample(st4, 10)) == 'under 20 seconds')
assert(select(2, PH.AddSample(st4, 4000)) == 'over an hour')
PH.AddSample(st4, 1700); PH.AddSample(st4, 1900)
assert(select(2, PH.AddSample(st4, 600)) == 'much sooner than usual', 'freak reading rejected once 3 exist')
for _ = 1, 10 do PH.AddSample(st4, 1800) end
assert(#st4.samples == 5, 'keeps the last five')
-- back to Happy after a feed: ETA = median - elapsed
now = now + 10; game.mood = 3; PH.Update(st4, PH.Read(now), now)
assert(st4.lastFedAt == now, 'going up without a seen feed counts as fed')
now = now + 600
local eta2, known = PH.SecondsToNextMood(st4, now)
assert(known and math.abs(eta2 - (1800 - 600)) < 1e-6, 'learned eta')
assert(PH.Describe(st4, now).etaText == '~20:00 left')

-- Dismissal adds its cost back into the learned spell; a death marks the spell unclean --------------
local st5 = PH.New(); now = 40000
game.mood = 3; PH.Update(st5, PH.Read(now), now); PH.MarkFed(st5, now)
PH.MarkDismissed(st5)
now = now + 1000; game.mood = 2; PH.Update(st5, PH.Read(now), now)
assert(math.abs(st5.samples[1] - (1000 + 50 * 7.25)) < 1e-6, 'dismiss cost added back')
local st6 = PH.New(); now = 50000
game.mood = 3; PH.Update(st6, PH.Read(now), now); PH.MarkFed(st6, now)
PH.MarkDied(st6)
now = now + 1000; game.mood = 2; PH.Update(st6, PH.Read(now), now)
assert(#st6.samples == 0, 'a spell with a death is not a sample')

-- Persistence round-trip keeps only the learned parts ----------------------------------------------
local p = PH.Persist(st4)
assert(p.samples and #p.samples == 5 and p.decayRatePerSec == nil and p.happyFloor == nil)
local st7 = PH.New(p)
assert(#st7.samples == 5 and st7.mood == nil and st7.lastFedAt == nil)

-- FormatTime
assert(PH.FormatTime(59) == '0:59' and PH.FormatTime(3661) == '1:01:01')
print('PASS: enum index + dead-slot rejection, measured drain EMA with resets, floor learning + zone guard, settle, learned-tier samples/ETA, dismiss/death, persistence')