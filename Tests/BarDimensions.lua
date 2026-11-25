-- Run from repository root: lua5.1 Tests/BarDimensions.lua
local ns = { Client = {} }
for _, path in ipairs({'Core/Util.lua', 'Core/DB.lua', 'Frames/Chrome.lua', 'Core/Geometry.lua'}) do
  assert(loadfile('VelocityFrameStyle/' .. path))('VelocityFrameStyle', ns)
end
VelocityFrameStyleDB = {global={petTargetScale=0.8}, profiles={Test={petTargetPlacement={point='CENTER', x=100, y=-50}}}}
ns.DB.Init()
assert(ns.db.profiles.Test.petTargetPlacement.x == 80)
assert(ns.db.profiles.Test.petTargetPlacement.y == -40)
assert(ns.DB.Global().petTargetScale == nil)
ns.DB.Init()
assert(ns.db.profiles.Test.petTargetPlacement.x == 80, 'migration must run once')
assert(ns.DB.BarDimension('pet', 'barWidth') == 70)
ns.DB.SetBarDimension('pet', 'barWidth', 180)
ns.DB.SetBarDimension('pet', 'healthHeight', 24)
ns.DB.SetBarDimension('pet', 'powerHeight', 12)
local function bar()
  return {SetWidth=function(self,v) self.w=v end, SetHeight=function(self,v) self.h=v end,
    SetScale=function() error('dimensions must never change scale') end}
end
local health, power = bar(), bar()
health.vfsGeometrySpec = {}
ns.Client.MovableBars = function() return {[health]=true, [power]=true} end
local combat = false
function InCombatLockdown() return combat end
local st = {id='pet', bars={health={stock=health},power={stock=power}}}
assert(ns.Geometry.ApplyBarDimensions(st))
assert(health.w == 180 and health.h == 24 and power.w == 180 and power.h == 12)
assert(health.vfsGeometrySpec.width == 180 and health.vfsGeometrySpec.height == 24)
combat = true
ns.DB.SetBarDimension('pet', 'barWidth', 220)
assert(not ns.Geometry.ApplyBarDimensions(st) and st.dimensionsPending)
assert(health.w == 180, 'must defer resize in combat')
combat = false
assert(ns.Geometry.ApplyBarDimensions(st) and not st.dimensionsPending)
assert(health.w == 220 and power.w == 220)
ns.DB.ResetFrame('pet')
assert(ns.DB.BarDimension('pet', 'barWidth') == 70)
print('PASS: dimensions without scaling, deferred combat resize, reset, one-shot zoom migration')