-- Border-only explicit nine-slice renderer. Generated UVs keep fixed corner radii
-- independent of bar width/height; there is deliberately no centre texture.
local ADDON_NAME, VFS = ...
local RoundedBorder = {}
VFS.RoundedBorder = RoundedBorder

function RoundedBorder.Create(parent, surface)
  local atlas = VFS.RoundedBorderAtlas
  local border = CreateFrame("Frame", nil, parent)
  border:EnableMouse(false)
  border:SetPoint("TOPLEFT", surface, "TOPLEFT", -atlas.thickness, atlas.thickness)
  border:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", atlas.thickness, -atlas.thickness)
  border.edges = {}
  for name, uv in pairs(atlas.slices) do
    if name ~= "center" then
      local piece = border:CreateTexture(nil, "BORDER")
      piece:SetTexture(atlas.texture)
      piece:SetTexCoord(unpack(uv))
      piece:SetVertexColor(0, 0, 0, 1)
      piece:SetHorizTile(false); piece:SetVertTile(false)
      border.edges[name] = piece
    end
  end
  local pieces, corner = border.edges, atlas.cornerSize
  for name, anchor in pairs({topLeft="TOPLEFT", topRight="TOPRIGHT", bottomLeft="BOTTOMLEFT", bottomRight="BOTTOMRIGHT"}) do
    pieces[name]:SetSize(corner, corner)
    pieces[name]:SetPoint(anchor, border, anchor)
  end
  pieces.top:SetPoint("TOPLEFT", pieces.topLeft, "TOPRIGHT")
  pieces.top:SetPoint("BOTTOMRIGHT", pieces.topRight, "BOTTOMLEFT")
  pieces.bottom:SetPoint("TOPLEFT", pieces.bottomLeft, "TOPRIGHT")
  pieces.bottom:SetPoint("BOTTOMRIGHT", pieces.bottomRight, "BOTTOMLEFT")
  pieces.left:SetPoint("TOPLEFT", pieces.topLeft, "BOTTOMLEFT")
  pieces.left:SetPoint("BOTTOMRIGHT", pieces.bottomLeft, "TOPRIGHT")
  pieces.right:SetPoint("TOPLEFT", pieces.topRight, "BOTTOMLEFT")
  pieces.right:SetPoint("BOTTOMRIGHT", pieces.bottomRight, "TOPRIGHT")
  local function UpdateEdgeVisibility()
    local width, height = border:GetSize()
    if VFS.Util.IsSecret(width) or VFS.Util.IsSecret(height) then return end
    local valid = width >= 2*corner and height >= 2*corner
    for _, piece in pairs(pieces) do piece:SetShown(valid) end
    -- At the minimum inner dimension, the middle span is zero. Hide it rather
    -- than relying on WoW's special zero-sized Texture behavior.
    pieces.top:SetShown(valid and width > 2*corner)
    pieces.bottom:SetShown(valid and width > 2*corner)
    pieces.left:SetShown(valid and height > 2*corner)
    pieces.right:SetShown(valid and height > 2*corner)
  end
  border:SetScript("OnSizeChanged", UpdateEdgeVisibility)
  UpdateEdgeVisibility()
  function border:SetBorderColor(r, g, b, a)
    for _, piece in pairs(self.edges) do piece:SetVertexColor(r, g, b, a) end
  end
  return border
end