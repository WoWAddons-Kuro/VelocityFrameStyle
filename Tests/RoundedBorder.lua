-- Run from repository root: lua5.1 Tests/RoundedBorder.lua
local ns = {Util={IsSecret=function() return false end}, Client={}, DB={}, TextLayout={}}
local methods={}
local function region(parent) return setmetatable({parent=parent,points={},level=5,strata='LOW'}, {__index=methods}) end
function CreateFrame(_,_,parent) return region(parent) end
function methods:EnableMouse(v) self.mouse=v end
function methods:GetParent() return self.parent end
function methods:SetPoint(point,relative,relativePoint,x,y) self.points[point]={relative,relativePoint,x or 0,y or 0} end
function methods:SetAllPoints(relative) self:SetPoint('TOPLEFT',relative,'TOPLEFT'); self:SetPoint('BOTTOMRIGHT',relative,'BOTTOMRIGHT') end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:SetScript(name,fn) self[name]=fn end
function methods:SetShown(v) self.shown=v end
function methods:CreateTexture() return region(self) end
function methods:SetTexture(v) self.texture=v end
function methods:SetTexCoord(...) self.uv={...} end
function methods:SetVertexColor(...) self.color={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetHorizTile(v) self.hTile=v end
function methods:SetVertTile(v) self.vTile=v end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(v) self.level=v end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameStrata(v) self.strata=v end
function hooksecurefunc(object,name,fn) local original=object[name]; object[name]=function(self,...) original(self,...); fn(self,...) end end
local function point(object, name)
  if object.rect then
    local r=object.rect
    return name:find('LEFT') and r[1] or r[3], name:find('TOP') and r[2] or r[4]
  end
  local anchor=object.points[name]
  local x,y=point(anchor[1],anchor[2]); return x+anchor[3],y+anchor[4]
end
function methods:GetSize()
  local l,t=point(self,'TOPLEFT'); local r,b=point(self,'BOTTOMRIGHT'); return r-l,t-b
end
for _,file in ipairs({'Assets/RoundedBorderAtlas.lua','Frames/RoundedBorder.lua','Frames/FrameBase.lua'}) do
  assert(loadfile('VelocityFrameStyle/'..file))('VelocityFrameStyle',ns)
end
local atlas=ns.RoundedBorderAtlas
assert(atlas.thickness==6 and atlas.cornerSize==9 and atlas.minimumInnerSize==6)
local bar=region(region()); bar.rect={0,0,113,-24}
local backdrop=ns.FrameBase.AcquireBackdrop(bar)
for _,size in ipairs({{113,24},{113,12},{70,10},{70,7},{40,6},{200,40}}) do
  bar.rect={0,0,size[1],-size[2]}
  for _,border in ipairs({backdrop.border,backdrop.ring}) do
    border.OnSizeChanged()
    local w,h=border:GetSize(); assert(w==size[1]+12 and h==size[2]+12)
    assert(border.edges.center==nil, 'no centre texture may cover the fill')
    local count=0
    for name,piece in pairs(border.edges) do
      count=count+1; assert(piece.texture==atlas.texture and piece.color[4]==1)
      for i=1,4 do assert(piece.uv[i]==atlas.slices[name][i]) end
    end
    assert(count==8)
    for name,anchor in pairs({topLeft='TOPLEFT',topRight='TOPRIGHT',bottomLeft='BOTTOMLEFT',bottomRight='BOTTOMRIGHT'}) do
      local piece=border.edges[name]
      assert(piece.width==9 and piece.height==9 and piece.points[anchor][1]==border)
      assert(piece.shown)
    end
    assert(border.edges.top.shown and border.edges.bottom.shown)
    assert(border.edges.left.shown==(size[2]>6) and border.edges.right.shown==(size[2]>6))
    assert(border.edges.top.points.TOPLEFT[1]==border.edges.topLeft)
    assert(border.edges.top.points.BOTTOMRIGHT[1]==border.edges.topRight)
    assert(border.edges.left.points.TOPLEFT[1]==border.edges.topLeft)
    assert(border.edges.left.points.BOTTOMRIGHT[1]==border.edges.bottomLeft)
  end
end
assert(backdrop:GetFrameLevel()<bar:GetFrameLevel() and backdrop.ring:GetFrameLevel()>bar:GetFrameLevel())
local glow=ns.FrameBase.CreateSurfaceBorder(bar.parent,bar,2)
assert(glow.edges.topLeft==nil, '2-unit combat outline must stay flat')
print('PASS: generated UVs, eight border-only pieces, both layers, fixed corners, resizing/minimum span and flat glow')