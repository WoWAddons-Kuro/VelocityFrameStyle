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

-- Era TargetFrame auras: Blizzard pins the FIRST buff/debuff row at TOPLEFT -> TargetFrame BOTTOMLEFT (21, 28), a
-- fixed height sized for its stock bars; our taller stack ends lower, so row 1 ran into the power bar. After every
-- UpdateAuras re-anchor only the auras that are anchored to the TargetFrame itself (row starts) to hang below our
-- lowest bar's border instead. Later rows chain off row 1 and follow. Aura buttons are unprotected: legal in combat.
-- Forever's TargetFrame lays auras out differently (no buttons anchored to the frame bottom) so this finds nothing there.
local AURA_GAP_BELOW_BORDER = 2
local function ReanchorAuraRowStarts(st)
  local lowest = st.slots and st.slots.below
  if not lowest or not TargetFrame then return end
  local y = -(FrameBase.BAR_BORDER_WIDTH + AURA_GAP_BELOW_BORDER)
  for _, prefix in ipairs({ "TargetFrameBuff", "TargetFrameDebuff" }) do
    local i = 1
    while true do
      local aura = _G[prefix .. i]
      if not aura then break end
      if aura:IsShown() and aura:GetNumPoints() > 0 then
        local point, relTo, relPoint, x = aura:GetPoint(1)
        if relTo == TargetFrame and point == "TOPLEFT" and relPoint == "BOTTOMLEFT" then
          aura:ClearAllPoints()
          aura:SetPoint("TOPLEFT", lowest, "BOTTOMLEFT", 0, y)
        end
      end
      i = i + 1
    end
  end
end
Target.ReanchorAuraRowStarts = ReanchorAuraRowStarts

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
  if TargetFrame.UpdateAuras then hooksecurefunc(TargetFrame, "UpdateAuras", function() ReanchorAuraRowStarts(st) end) end
  if TargetFrame_UpdateAuras then hooksecurefunc("TargetFrame_UpdateAuras", function(frame) if frame == TargetFrame then ReanchorAuraRowStarts(st) end end) end
  FrameBase.Restyle("target")
  PlaceSkull(st)
  ReanchorAuraRowStarts(st)
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