-- Run from repository root: lua5.1 Tests/Predictions.lua
local ns = {Client={}, DB={}, TextLayout={}, features={}}
assert(loadfile('VelocityFrameStyle/Core/Util.lua'))('VelocityFrameStyle', ns)
local enabled = true
ns.DB.Frame = function() return {enabled=enabled} end
local selectedTexture='selected-bar-texture'
ns.DB.Effective = function() return selectedTexture end
ns.Util.StatusBarPath = function(key) return key end
local methods = {}
local function widget() return setmetatable({level=10,strata='LOW',alpha=1,masks={},coords={0,1,0,1}}, {__index=methods}) end
function methods:GetAlpha() return self.alpha end
function methods:SetAlpha(a) self.alpha=a end
function methods:GetBlendMode() return self.blend or 'BLEND' end
function methods:SetBlendMode(v) self.blend=v end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(v) self.level=v end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameStrata(v) self.strata=v end
function methods:GetAtlas() return self.atlas end
function methods:SetAtlas(v) self.atlas=v; self.texture=nil end
function methods:GetTexture() return self.texture end
function methods:SetTexture(v) self.texture=v; self.atlas=nil end
function methods:GetTexCoord() return unpack(self.coords) end
function methods:SetTexCoord(...) self.coords={...} end
function methods:ClearAllPoints() self.relative=nil end
function methods:SetAllPoints(v) self.relative=v end
function methods:CreateMaskTexture() return widget() end
function methods:GetNumMaskTextures() return #self.masks end
function methods:GetMaskTexture(i) return self.masks[i] end
function methods:AddMaskTexture(v) self.masks[#self.masks+1]=v end
function methods:RemoveMaskTexture(v)
  for i=#self.masks,1,-1 do if self.masks[i]==v then table.remove(self.masks,i) end end
end
function hooksecurefunc(object, method, callback)
  local original = object[method]
  object[method] = function(self, ...) original(self, ...); callback(self, ...) end
end
local function forbidden() error('must not inspect or write prediction values/visibility/colours') end
methods.GetValue, methods.SetValue, methods.GetMinMaxValues = forbidden, forbidden, forbidden
methods.SetMinMaxValues, methods.Show, methods.Hide = forbidden, forbidden, forbidden
function methods:SetVertexColor(...) self.color={...} end
function methods:GetVertexColor() return unpack(self.color or {0,0.8,0.7,0.5}) end
local bar, segment, artMask, valueMask = widget(), widget(), widget(), {}
setmetatable(valueMask,{__index=forbidden}) -- even querying FillMask geometry is forbidden
bar.vfsBackdrop = {ring=widget()}
segment.Fill, segment.FillMask = widget(), valueMask
segment.Fill.atlas='native-prediction-art'
segment.Fill.alpha=0.4; segment.alpha=0.5; segment.Fill.blend='ADD'
segment.Fill.masks={valueMask,artMask}
local updates=0
function segment:UpdateFillPosition(...) updates=updates+1 end
function segment:SetFillColor(color) self.Fill:SetVertexColor(unpack(color)) end
local entries={{key='manaCost',bar=bar,segment=segment,artMask=artMask}}
ns.Client.PredictionSegments=function() return entries end
assert(loadfile('VelocityFrameStyle/Frames/FrameBase.lua'))('VelocityFrameStyle',ns)
local st={id='player',host={top=widget()}}
ns.FrameBase.ApplyPredictions(st)
assert(ns.features['prediction:player:manaCost'])
assert(segment.Fill.alpha==1 and segment.alpha==1 and segment.Fill.blend=='BLEND')
assert(segment.Fill.masks[1]==valueMask and #segment.Fill.masks==2)
assert(segment.Fill.masks[2]==segment.vfsPredictionStyle.clip)
assert(segment.vfsPredictionStyle.clip.relative==bar and segment.Fill.relative==bar)
assert(segment.level==bar.level+1 and bar.vfsBackdrop.ring.level==bar.level+2)
assert(st.host.top.level > bar.vfsBackdrop.ring.level)
segment:UpdateFillPosition(valueMask, {}, {}) -- opaque native arguments ignored by our hook
assert(segment.Fill.texture=='Interface\\Buttons\\WHITE8x8')
assert(segment.Fill.color[1]==1 and segment.Fill.color[2]==0.9 and segment.Fill.color[3]==0.1 and segment.Fill.color[4]==1)
segment:SetFillColor({0.2,0.3,0.4,0.5})
assert(segment.Fill.color[1]==1 and segment.Fill.color[2]==0.9, 'native recolour must retain yellow while styled')
selectedTexture='different-bar-texture'
ns.FrameBase.ApplyPredictions(st)
assert(segment.Fill.texture=='Interface\\Buttons\\WHITE8x8', 'diagnostic prediction texture stays independent of main-bar texture')
assert(updates==1 and segment.Fill.masks[1]==valueMask)
bar:SetFrameLevel(20)
assert(segment.level==21 and bar.vfsBackdrop.ring.level==22 and st.host.top.level==23)
bar:SetFrameStrata('MEDIUM'); assert(segment.strata=='MEDIUM')
-- Native art reattached: cosmetic post-hook removes only the art mask again.
segment.Fill:AddMaskTexture(artMask); segment:UpdateFillPosition()
assert(#segment.Fill.masks==2 and segment.Fill.masks[1]==valueMask)
enabled=false; ns.FrameBase.ApplyPredictions(st)
assert(segment.Fill.atlas=='native-prediction-art')
assert(segment.Fill.color[2]==0.3 and segment.Fill.color[4]==0.5)
assert(segment.Fill.alpha==0.4 and segment.alpha==0.5 and segment.Fill.blend=='ADD')
assert(segment.Fill.relative==segment)
assert(segment.Fill.masks[1]==valueMask and segment.Fill.masks[2]==artMask)
assert(segment.level==bar.level and bar.vfsBorderLevelOffset==nil)
enabled=true; ns.FrameBase.ApplyPredictions(st); assert(#segment.Fill.masks==2)
entries={{key='missing'}}; ns.FrameBase.ApplyPredictions(st)
assert(ns.features['prediction:player:missing']==false)
-- Repeated Blizzard status pulses cannot resurrect suppressed chrome.
local chrome=widget()
ns.FrameBase.SetChromeSuppressed(chrome,'player',true); assert(chrome.alpha==0)
chrome:SetAlpha(0.7); assert(chrome.alpha==0)
ns.FrameBase.SetChromeSuppressed(chrome,'player',true)
enabled=false; ns.FrameBase.SetChromeSuppressed(chrome,'player',false); assert(chrome.alpha==0.7)
chrome:SetAlpha(0.4); assert(chrome.alpha==0.4)
enabled=true; ns.FrameBase.SetChromeSuppressed(chrome,'player',true); assert(chrome.alpha==0)
print('PASS: prediction masks/geometry/layers, ignored secret inputs, native ownership, restore, chrome alpha suppression')