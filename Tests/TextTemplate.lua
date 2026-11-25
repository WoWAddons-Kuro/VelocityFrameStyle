-- Run from repository root: lua5.1 Tests/TextTemplate.lua
local ns = {}
local function load(path) assert(loadfile('VelocityFrameStyle/' .. path))('VelocityFrameStyle', ns) end
load('Core/Util.lua'); load('Client/Client.lua'); load('Core/Format.lua'); load('Core/DB.lua')
load('Client/Client_ClassicEra.lua'); load('Client/Client_Forever.lua')
function SetCVar() error('Text formats must not write CVars') end
local health, healthMax, power, powerMax = 873, 1000, 400, 800
function UnitHealth() return health end
function UnitHealthMax() return healthMax end
function UnitPower() return power end
function UnitPowerMax() return powerMax end
function UnitPowerType() return 0, 'MANA' end
function AbbreviateNumbers(v) return tostring(v) end
CurveConstants = {ScaleTo100={}}
function UnitHealthPercent(unit, predicted, curve)
  assert(predicted and curve == CurveConstants.ScaleTo100); return 87.3
end
function UnitPowerPercent(unit, kind, unmodified, curve)
  assert(kind == nil and unmodified == false and curve == CurveConstants.ScaleTo100); return 50
end
C_StringUtil = {RoundToNearestString=function(v) return tostring(math.floor(v + 0.5)) end}
local forever, era = ns.ClientFlavours.forever, ns.ClientFlavours.classic_era
for _, impl in ipairs({forever, era}) do
  ns.Client.HealthValues, ns.Client.PowerValues = impl.HealthValues, impl.PowerValues
  assert(impl.FormatBarValue('target', 'health', 'current') == '873')
  assert(impl.FormatBarValue('target', 'health', 'current_max') == (impl == era and '873 / 1K' or '873 / 1000'))
  assert(impl.FormatBarValue('target', 'health', 'percent') == '87%')
  assert(impl.FormatBarValue('target', 'power', 'current') == '400')
  assert(impl.FormatBarValue('target', 'power', 'percent') == '50%')
  power = 0
  assert(impl.FormatBarValue('target', 'power', 'current') == '0')
  powerMax = 0
  local _, available = impl.FormatBarValue('target', 'power', 'current')
  assert(not available)
  power, powerMax = 400, 800
end
-- A fake secret rejects arithmetic and inspection; only trusted stubs can format it.
local secretMeta = {}
local function secret(value) return setmetatable({value=value}, secretMeta) end
local function forbidden() error('secret inspected or used in Lua arithmetic') end
secretMeta.__add, secretMeta.__div, secretMeta.__lt, secretMeta.__le = forbidden, forbidden, forbidden, forbidden
secretMeta.__eq, secretMeta.__tostring = forbidden, forbidden
local function trusted(v) if type(v)=='table' then return rawget(v, 'value') end return v end
secretMeta.__concat = function(a,b) return secret(trusted(a) .. trusted(b)) end
function issecretvalue(v) return type(v)=='table' and getmetatable(v)==secretMeta end
health, healthMax = secret(873), secret(1000)
function AbbreviateNumbers(v) return secret(tostring(trusted(v))) end
function UnitHealthPercent() return secret(87.3) end
C_StringUtil.RoundToNearestString = function(v) return secret(tostring(math.floor(trusted(v)+0.5))) end
local text, available = forever.FormatBarValue('target', 'health', 'current_max')
assert(available and trusted(text)=='873 / 1000')
text = forever.FormatBarValue('target', 'health', 'percent')
assert(trusted(text)=='87%')
-- Grid passes secret output straight to its owned string without width/content inspection.
ns.Client.FormatBarValue = forever.FormatBarValue
load('Core/TextLayout.lua')
local fs = {SetText=function(self,v) self.value=v end, SetTextColor=function() end,
  SetShown=function(self,v) self.shown=v end, SetAlpha=function() end, GetStringWidth=forbidden}
local host = {text={health=fs}}
local element = {id='health', format='[hp]', valueFormat='current', anchor='health', color='white'}
ns.TextLayout.ApplyTexts(host, {element}, 'target')
assert(trusted(fs.value)=='873' and fs.shown)
element.anchor='hidden'; ns.TextLayout.ApplyTexts(host, {element}, 'target'); assert(not fs.shown)
element.anchor='health'; ns.Format.SetValueFormat(element,'current_max')
ns.TextLayout.ApplyTexts(host, {element}, 'target'); assert(trusted(fs.value)=='873 / 1000' and fs.shown)
-- Migration: four rows, Current defaults, preserve name/level styles, sizes/positions untouched.
VelocityFrameStyleDB = {version=1, frames={pet={dimensions={barWidth=180}, elements={
  {id='name',anchor='above',align='right',size=14,color='custom',customColor={1,0,0}},
  {id='level',anchor='hidden',size=12}, {id='healthpct'}, {id='powerpct'}
}}}, profiles={Test={petTargetPlacement={point='CENTER', x=100,y=20}}}}
ns.DB.Init()
local elements = ns.DB.Elements('pet')
assert(#elements==4 and ns.db.version==2)
assert(elements[1].anchor=='above' and elements[1].size==14 and elements[1].customColor[1]==1)
assert(elements[2].anchor=='hidden' and elements[2].size==12)
assert(elements[3].valueFormat=='current' and elements[4].valueFormat=='current')
assert(ns.DB.Frame('pet').dimensions.barWidth==180 and ns.db.profiles.Test.petTargetPlacement.x==100)
ns.Format.SetValueFormat(elements[3], 'percent'); ns.DB.Init()
assert(ns.DB.Elements('pet')[3].valueFormat=='percent', 'migration must not repeat')
assert(ns.DB.Elements('player')[3].valueFormat=='current', 'per-frame independence')
assert(ns.DB.Elements('pet')[4].valueFormat=='current', 'per-bar independence')
assert(ns.Format.SampleValue('health','percent')=='75%')
print('PASS: both clients, secret-safe grid formatting, hidden/restore, four-row migration, independent formats, no CVars')