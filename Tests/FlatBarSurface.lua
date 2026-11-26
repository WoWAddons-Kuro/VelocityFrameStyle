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
-- No rounded atlas is loaded here, so the flat renderer is exercised at the real border width.
local T = ns.FrameBase.BAR_BORDER_WIDTH
assert(T == 4, 'border width contract (owner 2026-11-25)')
for _, size in ipairs({ {113,24}, {113,12}, {70,10}, {70,7}, {200,40} }) do
  bar.rect = {20, 100, 20 + size[1], 100 - size[2]}
  local l, t, r, b = unpack(bar.rect)
  equals(rect(backdrop.tex), bar.rect)
  for _, border in ipairs({ backdrop.border, backdrop.ring }) do
    equals(rect(border), {l-T, t+T, r+T, b-T})
    equals(rect(border.edges.top), {l-T, t+T, r+T, t})
    equals(rect(border.edges.bottom), {l-T, b, r+T, b-T})
    equals(rect(border.edges.left), {l-T, t, l, b})
    equals(rect(border.edges.right), {r, t, r+T, b})
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
VelocityFrameStyleDB = { global = { backingAlpha = 0.6, petTargetHideWhenSame = true } }
ns.DB.Init()
assert(ns.DB.Global().backingAlpha == 0.3)
assert(ns.DB.Global().petTargetHealthOnly == true)
assert(ns.DB.Global().petTargetHideWhenSame == nil, 'retired setting must be removed')
ns.DB.Global().petTargetHealthOnly = false -- test automatic policy separately below
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
function methods:IsShown() return self.shown ~= false end
local capacity = 0
ns.Client.HasPowerResource = function()
  if capacity == nil then return nil end
  return capacity > 0
end
function UnitPowerMax() error('Visibility must follow the controller, not inspect capacity') end
local preview = false
ns.PetTarget = { IsSample = function() return preview end }
for _, id in ipairs({'target', 'pettarget'}) do
  local power = { stock = region(), backdrop = region() }
  power.backdrop.ring = region()
  local health = region()
  local st = {id=id, unit=id, bars={power=power, health={stock=health}}, slots={}}
  capacity = 0
  power.stock.shown = false
  ns.FrameBase.RefreshPowerVisibility(st)
  assert(st.powerAbsent and power.stock.alpha == 0 and power.backdrop.alpha == 0)
  assert(power.backdrop.ring.alpha == 0 and st.slots.power == nil and st.slots.below == health)
  capacity = 100 -- even if current power is zero, capacity means the bar remains
  power.stock.shown = true
  ns.FrameBase.RefreshPowerVisibility(st)
  assert(not st.powerAbsent and power.stock.alpha == 1 and st.slots.power == power.stock)
  capacity = nil -- unknown/secret is not evidence of no resource
  ns.FrameBase.RefreshPowerVisibility(st)
  assert(not st.powerAbsent)
  if id == 'target' then
    power.stock.shown = false
    ns.FrameBase.RefreshPowerVisibility(st)
    assert(st.powerAbsent and power.backdrop.alpha == 0 and power.backdrop.ring.alpha == 0,
      'native hidden bar must collapse even with unreadable capacity')
    power.stock.shown = true
  end
  if id == 'pettarget' then
    power.stock.shown = false; preview = true; ns.FrameBase.RefreshPowerVisibility(st)
    assert(not st.powerAbsent, 'Edit Mode retains sample power')
    ns.DB.Global().petTargetHealthOnly = true
    ns.Client.HasPowerResource = function() error('health-only must not query secret resource data') end
    ns.FrameBase.RefreshPowerVisibility(st)
    assert(st.powerAbsent and st.slots.power == nil and st.slots.below == health)
    assert(power.stock.alpha == 0 and power.backdrop.alpha == 0 and power.backdrop.ring.alpha == 0)
    preview = false; ns.FrameBase.RefreshPowerVisibility(st); assert(st.powerAbsent)
    ns.DB.Global().petTargetHealthOnly = false
    ns.Client.HasPowerResource = function() return true end
    ns.FrameBase.RefreshPowerVisibility(st)
    assert(not st.powerAbsent and st.slots.power == power.stock and power.stock.alpha == 1)
    ns.DB.Init(); assert(ns.DB.Global().petTargetHealthOnly == false, 'explicit opt-out must persist')
  end
end
print('PASS: flat borders, five sizes, layer sync, opacity, placement and power visibility')