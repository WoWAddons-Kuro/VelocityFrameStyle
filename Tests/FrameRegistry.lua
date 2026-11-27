-- Run from repository root: lua5.1 Tests/FrameRegistry.lua
local ns = {Client={}, TextLayout={}}
local function load(path) assert(loadfile('VelocityFrameStyle/' .. path))('VelocityFrameStyle',ns) end
load('Core/Util.lua'); load('Core/DB.lua'); load('Frames/Chrome.lua'); load('Frames/FrameBase.lua')
-- Existing v2 installations must get the newly registered ToT record without a reset.
VelocityFrameStyleDB = {version=2, flatBarSurfaces=true, frames={player={
  enabled=true, dimensions={barWidth=220}, elements={{id='health',valueFormat='percent',format='[hp%]'}}
}}}
ns.DB.Init()
for _, id in ipairs({'player','target','pet','pettarget','tot','focus','focustarget'}) do
  assert(ns.DB.Frame(id) and ns.DB.Frame(id).enabled ~= nil, 'missing settings: '..id)
  assert(type(ns.DB.Elements(id))=='table', 'missing elements: '..id)
  assert(ns.Chrome.LAYOUT[id], 'missing geometry: '..id)
end
assert(#ns.DB.Elements('tot')==4 and ns.DB.Frame('tot').enabled)
assert(ns.DB.Frame('player').dimensions.barWidth==220)
assert(ns.DB.Elements('player')[1].valueFormat=='percent')
function UnitExists() return false end
local alpha
local st = {id='tot',unit='targettarget',host={text={}},chrome={glow={
  anim={IsPlaying=function() return false end}, frame={SetAlpha=function(_,v) alpha=v end}
}}}
ns.FrameBase.ApplyTexts(st) -- reported nil dereference in text update
ns.Chrome.UpdateCombat(st) -- reported nil dereference in combat event
assert(alpha==0)
ns.DB.Frame('tot').enabled=false; ns.DB.Init()
assert(ns.DB.Frame('tot').enabled==false, 'login must preserve existing settings')
ns.DB.ResetFrame('tot'); assert(ns.DB.Frame('tot').enabled and #ns.DB.Elements('tot')==4)
print('PASS: all frame settings exist, ToT added to v2 saves, text/combat paths and settings preservation')