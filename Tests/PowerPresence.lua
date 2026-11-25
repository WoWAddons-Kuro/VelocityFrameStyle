-- Run from repository root: lua5.1 Tests/PowerPresence.lua
local ns = {}
for _, file in ipairs({'Core/Util.lua','Client/Client.lua','Client/Client_Forever.lua'}) do
  assert(loadfile('VelocityFrameStyle/' .. file))('VelocityFrameStyle', ns)
end
local secret = {}
function issecretvalue(v) return rawequal(v, secret) end
local powerType, result = 1, false
function UnitPowerType() return powerType end
function UnitHasPowerType(unit, kind) assert(unit == 'pettarget' and kind == 1); return result end
function UnitPowerMax() return secret end
local has = ns.ClientFlavours.forever.HasPowerResource
assert(has('pettarget') == false, 'no resource despite secret capacity')
result = true; assert(has('pettarget') == true, 'resource present even at zero current')
result = secret; assert(has('pettarget') == nil, 'never branch on secret presence')
powerType = secret; assert(has('pettarget') == nil, 'never pass secret type into restricted API')
powerType = 1; UnitHasPowerType = nil
assert(has('pettarget') == nil, 'missing API and secret max are unknown')
function UnitPowerMax() return 0 end
assert(has('pettarget') == false, 'readable fallback supports old clients')
function UnitPowerMax() return 100 end
assert(has('pettarget') == true)
print('PASS: guarded resource presence, secret capacity/result/type, readable fallback')