-- Run from repository root: lua5.1 Tests/DruidMana.lua   (SPECS/14_Druid_Mana_Bar.md)
-- The mana POOL by explicit power type while a druid shows rage/energy. Era: plain. Forever: current is a SECRET.
local ns = {}
local function load(path) assert(loadfile('VelocityFrameStyle/' .. path))('VelocityFrameStyle', ns) end
load('Core/Util.lua'); load('Client/Client.lua'); load('Core/Format.lua')
load('Client/Client_ClassicEra.lua'); load('Client/Client_Forever.lua')

Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3 } }
ns.Client.MANA_POWER_TYPE = 0   -- Enum was defined after Client.lua loaded; pin it as the client would at load

-- Bear-form druid: display power RAGE, mana pool 373/490 (owner's Era dump 2026-11-27)
local rage, rageMax, mana, manaMax = 40, 100, 373, 490
function UnitPowerType() return 1, 'RAGE' end
function UnitPower(u, t) if t == 0 then return mana end return rage end
function UnitPowerMax(u, t) if t == 0 then return manaMax end return rageMax end
function UnitHealth() return 1 end
function UnitHealthMax() return 1 end

local era, forever = ns.ClientFlavours.classic_era, ns.ClientFlavours.forever

-- Era: plain numbers through the token resolvers
ns.Client.ManaValues, ns.Client.PowerValues = era.ManaValues, era.PowerValues
local cur, max, pct = era.ManaValues('player')
assert(cur == 373 and max == 490 and math.floor(pct * 100 + 0.5) == 76, 'Era ManaValues plain')
assert(ns.Format.Expand('[mana]', 'player') == '373')
assert(ns.Format.Expand('[manamax]', 'player') == '490')
assert(ns.Format.Expand('[mana%]', 'player') == '76%')
assert(era.FormatBarValue('player', 'mana', 'current') == '373')
assert(era.FormatBarValue('player', 'mana', 'current_max') == '373 / 490')
assert(era.FormatBarValue('player', 'mana', 'percent') == '76%')
assert(ns.Format.UsesMana('[mana]') and ns.Format.UsesMana('[mana%]') and not ns.Format.UsesMana('[power]'))
-- the ordinary power path is untouched by the mana type
assert(ns.Format.Expand('[power]', 'player') == '40')
manaMax = 0
local _, available = era.FormatBarValue('player', 'mana', 'current'); assert(not available, 'no pool => unavailable')
manaMax = 490

-- Forever: current mana is a secret. Any inspection errors; only widgets/formatters may receive it.
local secretMeta = {}
local function secret(v) return setmetatable({ value = v }, secretMeta) end
local function forbidden() error('secret inspected or used in Lua arithmetic') end
secretMeta.__add, secretMeta.__div, secretMeta.__lt, secretMeta.__le, secretMeta.__eq, secretMeta.__tostring = forbidden, forbidden, forbidden, forbidden, forbidden, forbidden
local function trusted(v) if type(v) == 'table' then return rawget(v, 'value') end return v end
secretMeta.__concat = function(a, b) return secret(trusted(a) .. trusted(b)) end
function issecretvalue(v) return type(v) == 'table' and getmetatable(v) == secretMeta end
mana = secret(373)                       -- owner's Forever dump: <secret> 862, 862 -> cur secret, max plain
function AbbreviateNumbers(v) return secret(tostring(trusted(v))) end
CurveConstants = { ScaleTo100 = {} }
function UnitPowerPercent(unit, kind, unmodified, curve)
  assert(kind == 0 and unmodified == false and curve == CurveConstants.ScaleTo100, 'mana percent must pass the MANA type')
  return secret(76.1)
end
C_StringUtil = { RoundToNearestString = function(v) return secret(tostring(math.floor(trusted(v) + 0.5))) end }

ns.Client.ManaValues = forever.ManaValues
cur, max = forever.ManaValues('player')
assert(cur == nil and max == 490, 'Forever ManaValues: secret cur -> nil, plain max')
assert(ns.Format.Expand('[mana]', 'player') == '', 'token resolver never touches a secret')
local bcur, bmax = forever.ManaBarValues('player')
assert(issecretvalue(bcur) and bmax == 490, 'ManaBarValues hands the secret through untouched for SetValue')
local text, ok = forever.FormatBarValue('player', 'mana', 'current'); assert(ok and trusted(text) == '373')
text = forever.FormatBarValue('player', 'mana', 'current_max'); assert(trusted(text) == '373 / 490')
text = forever.FormatBarValue('player', 'mana', 'percent'); assert(trusted(text) == '76%')

print('PASS: druid mana pool by type - Era plain tokens, Forever secret-safe formatting, bar values, UsesMana')