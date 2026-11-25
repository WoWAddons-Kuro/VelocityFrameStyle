-- Velocity Frame Style: the TargetFrame module. Stock bars styled in place and sized to the fixed M0 layout
-- (EF-Forever: health 113x24, power 129x12; bars LEFT of the portrait). Blizzard's reaction strip is chrome (alpha 0);
-- the name row sits on our plate. Skull (HighLevelTexture) is kept and re-anchored onto the level element.
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase, Chrome, Geometry = VFS.Client, VFS.DB, VFS.FrameBase, VFS.Chrome, VFS.Geometry

local Target = {}
VFS.Target = Target

local function PlaceBars(st)
  local L = Chrome.LAYOUT.target
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  if hb then Geometry.PlaceBar("target", hb, { point = "RIGHT", relTo = st.button, relPoint = "RIGHT", x = -86, y = 6, width = L.health.w, height = L.health.h }) end
  if pb and hb then Geometry.PlaceBar("target", pb, { point = "TOPRIGHT", relTo = hb, relPoint = "BOTTOMRIGHT", x = 0, y = -FrameBase.BAR_BORDER_WIDTH, width = L.power.w, height = L.power.h }) end
end

local function PlaceSkull(st)
  local skull = Client.ClassificationIcon("target")
  local level = st.host.text.level
  if skull and level then skull:ClearAllPoints(); skull:SetPoint("CENTER", level, "CENTER", 0, 0) end
end

function Target.Create()
  local st = FrameBase.Acquire("target")
  if not st then return end
  PlaceBars(st)
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb), above = hb, below = pb or hb }
  FrameBase.HookCommon(st)
  if TargetFrame.CheckClassification then hooksecurefunc(TargetFrame, "CheckClassification", function() PlaceBars(st); FrameBase.Restyle("target"); PlaceSkull(st) end) end
  if TargetFrame.UpdateHealthBarVisuals then hooksecurefunc(TargetFrame, "UpdateHealthBarVisuals", function() PlaceBars(st) end) end
  if TargetFrame_CheckClassification then hooksecurefunc("TargetFrame_CheckClassification", function() PlaceBars(st); FrameBase.Restyle("target"); PlaceSkull(st) end) end
  FrameBase.Restyle("target")
  PlaceSkull(st)
  return st
end

function Target.OnEvent(event, unit)
  local st = VFS.Frames.target
  if not st then return end
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    PlaceBars(st); FrameBase.Restyle("target"); PlaceSkull(st); FrameBase.OnCombatChanged(st)
  elseif event == "UNIT_FLAGS" and unit == "target" then
    FrameBase.OnCombatChanged(st)
  elseif (event == "UNIT_LEVEL" or event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" or event == "UNIT_NAME_UPDATE") and unit == "target" then
    FrameBase.ApplyTexts(st); PlaceSkull(st)
  end
end