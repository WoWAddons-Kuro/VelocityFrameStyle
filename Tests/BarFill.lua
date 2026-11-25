-- Run from repository root: lua5.1 Tests/BarFill.lua
local enabled, selected = true, 'BantoBar'
local ns={Util={StatusBarPath=function(key) return key end},Client={},TextLayout={},DB={
  Frame=function() return {enabled=enabled} end, Effective=function() return selected end}}
assert(loadfile('VelocityFrameStyle/Frames/FrameBase.lua'))('VelocityFrameStyle',ns)
function hooksecurefunc(object, method, callback)
  local original=object[method]
  object[method]=function(self, ...) original(self, ...); callback(self, ...) end
end
local function texture()
  return {masks={}, SetTexture=function(self,v) self.path=v; self.atlas=nil end,
    SetAtlas=function(self,v) self.atlas=v end,
    SetAlpha=function(self,v) self.alpha=v end,
    SetHorizTile=function(self,v) self.hTile=v end,
    SetVertTile=function(self,v) self.vTile=v end,
    AddMaskTexture=function(self,m) self.masks[#self.masks+1]=m end,
    GetNumMaskTextures=function(self) return #self.masks end,
    GetMaskTexture=function(self,i) return self.masks[i] end,
    RemoveMaskTexture=function(self,m) for i=#self.masks,1,-1 do if self.masks[i]==m then table.remove(self.masks,i) end end end}
end
local t=texture()
t.masks={{}}
local calls=0
local bar={GetStatusBarTexture=function() return t end, SetStatusBarTexture=function(_,path)
  calls=calls+1; assert(calls<100, 'recursive texture hook'); t:SetTexture(path)
end}
local st={id='pet'}
ns.FrameBase.ApplyBarFill(st,bar)
assert(t.path==selected and #t.masks==0 and t.alpha==1)
bar:SetStatusBarTexture('BlizzardRoundedManaAtlas')
assert(t.path==selected, 'native bar texture change must not win')
t:SetAtlas('BlizzardRoundedManaAtlas')
assert(t.path==selected and t.atlas==nil)
t:AddMaskTexture({})
assert(#t.masks==0, 'mask re-added to SAME texture must be removed')
t:SetTexture('AnotherRoundedTexture'); assert(t.path==selected)
selected='NewSelectedTexture'; ns.FrameBase.ApplyBarFill(st,bar); assert(t.path==selected)
t=texture(); t.masks={{}}
bar:SetStatusBarTexture('replacement texture object'); assert(t.path==selected and #t.masks==0)
t:AddMaskTexture({}); assert(#t.masks==0)
enabled=false
bar:SetStatusBarTexture('Native'); assert(t.path=='Native')
t:AddMaskTexture({}); assert(#t.masks==1, 'disabled styling must not strip native masks')
assert(not bar.vfsApplyingFill)
print('PASS: selected square fill survives native texture/atlas/mask changes, new objects and disable; no recursion')