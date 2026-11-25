-- Run from repository root: lua5.1 Tests/FlatBarSurface.lua
-- Anchor-math tests, not a substitute for in-game rendering verification.
local methods = {}
local function region(parent)
  return setmetatable({ parent = parent, points = {}, level = 5, strata = 'LOW' }, { __index = methods })
end
function CreateFrame(_, _, parent) return region(parent) end
function methods:GetParent() return self.parent end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetPoint(point, relative, relativePoint, x, y)
  self.points[point] = { relative, relativePoint, x or 0, y or 0 }
end
function methods:SetAllPoints(relative)
  self:SetPoint('TOPLEFT', relative, 'TOPLEFT')
  self:SetPoint('BOTTOMRIGHT', relative, 'BOTTOMRIGHT')
end
function methods:CreateTexture() return region(self) end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameStrata(value) self.strata = value end
function hooksecurefunc(object, method, callback)
  local original = object[method]
  object[method] = function(self, ...) original(self, ...); callback(self, ...) end
end
local corner
corner = function(object, point)
  if object.rect then
    local r = object.rect
    return point:find('LEFT') and r[1] or r[3], point:find('TOP') and r[2] or r[4]
  end
  local anchor = assert(object.points[point], point)
  local x, y = corner(anchor[1], anchor[2])
  return x + anchor[3], y + anchor[4]
end
local function rect(object)
  local l, t = corner(object, 'TOPLEFT')
  local r, b = corner(object, 'BOTTOMRIGHT')
  return { l, t, r, b }
end
local function equals(actual, expected)
  for i = 1, #expected do assert(actual[i] == expected[i], i .. ': ' .. tostring(actual[i]) .. ' ~= ' .. tostring(expected[i])) end
end
local ns = { Util = {}, Client = {}, DB = {}, TextLayout = {} }
assert(loadfile('VelocityFrameStyle/Frames/FrameBase.lua'))('VelocityFrameStyle', ns)
local bar = region(region())
bar.rect = { 20, 100, 133, 76 }
local backdrop = ns.FrameBase.AcquireBackdrop(bar)
assert(ns.FrameBase.AcquireBackdrop(bar) == backdrop, 'must reuse existing stack')
for _, size in ipairs({ {113,24}, {113,12}, {70,10}, {70,7}, {200,40} }) do
  bar.rect = {20, 100, 20 + size[1], 100 - size[2]}
  local l, t, r, b = unpack(bar.rect)
  equals(rect(backdrop.tex), bar.rect)
  for _, border in ipairs({ backdrop.border, backdrop.ring }) do
    equals(rect(border), {l-6, t+6, r+6, b-6})
    equals(rect(border.edges.top), {l-6, t+6, r+6, t})
    equals(rect(border.edges.bottom), {l-6, b, r+6, b-6})
    equals(rect(border.edges.left), {l-6, t, l, b})
    equals(rect(border.edges.right), {r, t, r+6, b})
    for _, edge in pairs(border.edges) do equals(edge.color, {0,0,0,1}) end
  end
end
ns.FrameBase.ColorBackdrop(bar, 0.3)
equals(backdrop.tex.color, {0,0,0,0.3})
bar:SetFrameLevel(12)
assert(backdrop:GetFrameLevel() == 11)
assert(backdrop.border:GetFrameLevel() == 11)
assert(backdrop.ring:GetFrameLevel() == 13)
bar:SetFrameStrata('MEDIUM')
assert(backdrop:GetFrameStrata() == 'MEDIUM' and backdrop.ring:GetFrameStrata() == 'MEDIUM')
-- DB baseline migration is one-shot and must not reattach a dragged frame.
assert(loadfile('VelocityFrameStyle/Core/Util.lua'))('VelocityFrameStyle', ns)
assert(loadfile('VelocityFrameStyle/Core/DB.lua'))('VelocityFrameStyle', ns)
VelocityFrameStyleDB = { global = { backingAlpha = 0.6 } }
ns.DB.Init()
assert(ns.DB.Global().backingAlpha == 0.3)
ns.DB.Global().backingAlpha = 0.45
ns.DB.Init()
assert(ns.DB.Global().backingAlpha == 0.45)
local saved = { petTargetPlacement = {point='CENTER', relPoint='CENTER', x=123, y=456} }
ns.LayoutProfile = { Current = function() return saved end }
assert(ns.DB.Profile().petTargetPlacement.anchorTo == nil)
assert(ns.DB.Profile().petTargetPlacement.x == 123)
-- Reload with the real Util/DB tables captured for visibility policy tests.
assert(loadfile('VelocityFrameStyle/Frames/FrameBase.lua'))('VelocityFrameStyle', ns)
function methods:SetAlpha(value) self.alpha = value end
local capacity = 0
function UnitPowerMax() return capacity end
local preview = false
ns.PetTarget = { IsSample = function() return preview end }
for _, id in ipairs({'target', 'pettarget'}) do
  local power = { stock = region(), backdrop = region() }
  power.backdrop.ring = region()
  local health = region()
  local st = {id=id, unit=id, bars={power=power, health={stock=health}}, slots={}}
  capacity = 0
  ns.FrameBase.RefreshPowerVisibility(st)
  assert(st.powerAbsent and power.stock.alpha == 0 and power.backdrop.alpha == 0)
  assert(power.backdrop.ring.alpha == 0 and st.slots.power == nil and st.slots.below == health)
  capacity = 100 -- even if current power is zero, capacity means the bar remains
  ns.FrameBase.RefreshPowerVisibility(st)
  assert(not st.powerAbsent and power.stock.alpha == 1 and st.slots.power == power.stock)
  capacity = nil -- unknown/secret is not evidence of no resource
  ns.FrameBase.RefreshPowerVisibility(st)
  assert(not st.powerAbsent)
  if id == 'pettarget' then
    capacity = 0; preview = true; ns.FrameBase.RefreshPowerVisibility(st)
    assert(not st.powerAbsent, 'Edit Mode retains sample power')
  end
end
print('PASS: flat borders, five sizes, layer sync, opacity, placement and power visibility')