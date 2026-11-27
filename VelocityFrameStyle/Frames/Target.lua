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

-- Danger row (SPECS/13, owner Q1): a cue string ABOVE the name row, right-aligned, shown only while the target
-- is dangerous: "??" or one skull glyph per level above the player followed by the level (Danger.RowText).
-- Not a grid element - it has no Position/Align/Colour cells - so it lives beside host.text, not inside it.
-- Always skull-red. Font: the frame's font/style at the Level element's size + DANGER_ROW_SIZE_BONUS.
local DANGER_ROW_SIZE_BONUS = 2
local DANGER_ROW_GAP = 1
local ApplyDanger   -- forward (defined below as Target.ApplyDanger)

local function CreateDangerRow(st)
  if st.dangerText or not st.nameRow then return end
  local fs = st.host.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetWordWrap(false)
  fs:SetJustifyH("RIGHT")
  fs:SetPoint("BOTTOMRIGHT", st.nameRow, "TOPRIGHT", 0, DANGER_ROW_GAP)
  fs:Hide()
  st.dangerText = fs
end

local function DangerRowFontSize(st)
  for _, e in ipairs(DB.Elements("target")) do
    if e.id == "level" then return (e.size or 10) + DANGER_ROW_SIZE_BONUS end
  end
  return 10 + DANGER_ROW_SIZE_BONUS
end

local function ApplyDangerRow(st)
  local fs = st.dangerText
  if not fs then return end
  if not DB.Frame("target").enabled or not UnitExists(st.unit) then fs:Hide(); return end
  local text = VFS.Danger.RowText(st.unit)
  if text == "" then fs:Hide(); return end
  fs:SetFont(VFS.Util.FontPath(DB.Effective("target", "font")), DangerRowFontSize(st), DB.Effective("target", "fontStyle") or "")
  local c = VFS.Danger.RED
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetText(text)
  fs:Show()
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
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb), above = hb, below = pb or hb, portrait = st.portraitBadge }
  CreateDangerRow(st)
  FrameBase.HookCommon(st)
  if TargetFrame.CheckClassification then hooksecurefunc(TargetFrame, "CheckClassification", function() PlaceBars(st); FrameBase.Restyle("target"); PlaceSkull(st); ApplyDanger(st) end) end
  if TargetFrame.UpdateHealthBarVisuals then hooksecurefunc(TargetFrame, "UpdateHealthBarVisuals", function() PlaceBars(st) end) end
  if TargetFrame_CheckClassification then hooksecurefunc("TargetFrame_CheckClassification", function() PlaceBars(st); FrameBase.Restyle("target"); PlaceSkull(st); ApplyDanger(st) end) end
  if TargetFrame.UpdateAuras then hooksecurefunc(TargetFrame, "UpdateAuras", function() ReanchorAuraRowStarts(st) end) end
  if TargetFrame_UpdateAuras then hooksecurefunc("TargetFrame_UpdateAuras", function(frame) if frame == TargetFrame then ReanchorAuraRowStarts(st) end end) end
  FrameBase.Restyle("target")
  PlaceSkull(st)
  ApplyDanger(st)
  ReanchorAuraRowStarts(st)
  return st
end

-- Everything the danger settings drive, in one place: the row text, the red Level (TextLayout.ColorFor reads
-- Danger.IsDangerous), the bar colour (ApplyHealthColor reads reactionHealth) and, once M4 lands, the sweep/ring.
function Target.ApplyDanger(st)
  st = st or VFS.Frames.target
  if not st then return end
  ApplyDangerRow(st)
  local hb = FrameBase.Bar(st, "health")
  if hb and DB.Frame("target").enabled then FrameBase.ApplyHealthColor(hb, st.unit, "target") end
  if VFS.DangerCue then VFS.DangerCue.Apply(st) end
end
ApplyDanger = Target.ApplyDanger

function Target.OnEvent(event, unit)
  local st = VFS.Frames.target
  if not st then return end
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    PlaceBars(st); FrameBase.Restyle("target"); PlaceSkull(st); FrameBase.OnCombatChanged(st); ApplyDanger(st)
  elseif event == "UNIT_FLAGS" and unit == "target" then
    FrameBase.OnCombatChanged(st); ApplyDanger(st)        -- UnitCanAttack can flip with the flags
  elseif (event == "UNIT_LEVEL" and unit == "player") or event == "PLAYER_LEVEL_UP" then
    FrameBase.ApplyTexts(st); ApplyDanger(st)              -- our level moved: thresholds are relative to it
  elseif (event == "UNIT_LEVEL" or event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" or event == "UNIT_NAME_UPDATE") and unit == "target" then
    FrameBase.ApplyTexts(st); PlaceSkull(st); ApplyDanger(st)
  end
end