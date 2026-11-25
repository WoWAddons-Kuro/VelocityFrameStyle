-- Velocity Frame Style: the pet-target unit frame - the one frame Blizzard does not have, so we create it.
-- Ported from VelocityPetTargetFrame UI\Frame.lua. Classic TargetFrame art (Era TargetFrame.xml geometry), a
-- SecureUnitButtonTemplate (left-click targets, right-click menu). Text is the element grid like every other frame
-- (no per-bar format setting). Protected calls (Show/Hide/SetPoint/SetScale) only out of combat;
-- Frames\PetTargetVisibility.lua owns show/hide.
local ADDON_NAME, VFS = ...
local Util, Client, DB, FrameBase, TextLayout = VFS.Util, VFS.Client, VFS.DB, VFS.FrameBase, VFS.TextLayout

local PetTarget = {}
VFS.PetTarget = PetTarget

local UNIT = "pettarget"
local TEX = "Interface\\TargetingFrame\\"
local CLASSIFICATION_ART = {
  elite = TEX .. "UI-TargetingFrame-Elite", rareelite = TEX .. "UI-TargetingFrame-Rare-Elite",
  rare = TEX .. "UI-TargetingFrame-Rare", worldboss = TEX .. "UI-TargetingFrame-Elite",
}
local SAMPLE = { name = "Pet's Target", level = "60", health = "1.5K", healthpct = "73%", power = "400", powerpct = "40%" }

local f
local sample = false
local lastPortraitGUID, lastTargetGUID

local function G() return DB.Global() end

-- Build ------------------------------------------------------------------------------------------
function PetTarget.Create()
  if f then return f end
  f = CreateFrame("Button", "VelocityFrameStylePetTarget", UIParent, "SecureUnitButtonTemplate")
  PetTarget.frame = f
  f:SetSize(232, 100)
  f:SetFrameStrata("LOW")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetHitRectInsets(96, 40, 10, 9)
  f:SetAttribute("unit", UNIT)
  f:SetAttribute("type1", "target")
  f:SetAttribute("type2", "togglemenu")
  f:RegisterForClicks("AnyUp")
  f:Hide()

  f.flash = f:CreateTexture(nil, "BACKGROUND")
  f.flash:SetTexture(TEX .. "UI-TargetingFrame-Flash")
  f.flash:SetSize(242, 93)
  f.flash:SetPoint("TOPLEFT", -6, -3)
  f.flash:SetTexCoord(0, 0.9453125, 0, 0.181640625)
  f.flash:Hide()

  f.nameBackground = f:CreateTexture(nil, "BORDER")
  f.nameBackground:SetTexture(TEX .. "UI-TargetingFrame-LevelBackground")
  f.nameBackground:SetSize(119, 19)
  f.nameBackground:SetPoint("TOPRIGHT", -90, -26)

  f.portrait = f:CreateTexture(nil, "BORDER")
  f.portrait:SetSize(64, 64)
  f.portrait:SetPoint("TOPRIGHT", -24, -16)

  f.health = CreateFrame("StatusBar", nil, f)
  f.health:SetSize(119, 12)
  f.health:SetPoint("TOPRIGHT", -90, -45)
  f.health:SetMinMaxValues(0, 1); f.health:SetValue(1); f.health:EnableMouse(false)

  f.power = CreateFrame("StatusBar", nil, f)
  f.power:SetSize(119, 12)
  f.power:SetPoint("TOPRIGHT", -90, -56)
  f.power:SetMinMaxValues(0, 1); f.power:SetValue(0); f.power:EnableMouse(false)

  f.art = CreateFrame("Frame", nil, f)
  f.art:SetAllPoints()
  f.art:SetFrameLevel(f:GetFrameLevel() + 2)
  f.texture = f.art:CreateTexture(nil, "BACKGROUND")
  f.texture:SetTexture(TEX .. "UI-TargetingFrame")
  f.texture:SetSize(230, 99)
  f.texture:SetPoint("CENTER", 18.5, -4)
  f.texture:SetTexCoord(0.1015625, 1.0, 0.0078125, 0.78125)

  -- Stock-equivalent texts exist only so the Client resolvers have something to alpha-zero; the grid draws real text.
  f.name = f.art:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall"); f.name:SetPoint("CENTER", -34, 15); f.name:SetAlpha(0)
  f.level = f.art:CreateFontString(nil, "BACKGROUND", "GameNormalNumberFont"); f.level:SetPoint("CENTER", f, "BOTTOMRIGHT", -35.25, 30); f.level:SetAlpha(0)
  f.healthText = f.art:CreateFontString(nil, "BACKGROUND", "TextStatusBarText"); f.healthText:SetPoint("CENTER", f.health); f.healthText:SetAlpha(0)
  f.powerText = f.art:CreateFontString(nil, "BACKGROUND", "TextStatusBarText"); f.powerText:SetPoint("CENTER", f.power); f.powerText:SetAlpha(0)
  f.deadText = f.art:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall"); f.deadText:SetPoint("CENTER", f.health); f.deadText:SetText(DEAD or "DEAD"); f.deadText:Hide()

  f.skull = f.art:CreateTexture(nil, "ARTWORK")
  f.skull:SetTexture(TEX .. "UI-TargetingFrame-Skull")
  f.skull:SetSize(16, 16)
  f.skull:SetPoint("CENTER", f.nameBackground, "RIGHT", -10, 0)
  f.skull:Hide()

  f.raidIcon = f.art:CreateTexture(nil, "ARTWORK")
  f.raidIcon:SetTexture(TEX .. "UI-RaidTargetingIcons")
  f.raidIcon:SetSize(26, 26)
  f.raidIcon:SetPoint("CENTER", f, "TOPRIGHT", -57, -18)
  f.raidIcon:Hide()

  f.pulse = f.art:CreateTexture(nil, "OVERLAY")
  f.pulse:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  f.pulse:SetSize(72, 72)
  f.pulse:SetPoint("CENTER", f.portrait, "CENTER")
  f.pulse:SetBlendMode("ADD")
  f.pulse:SetVertexColor(1, 0.8, 0.1, 0.8)
  f.pulse:SetAlpha(0)
  f.pulseAnim = f.pulse:CreateAnimationGroup()
  local a1 = f.pulseAnim:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.1); a1:SetOrder(1)
  local a2 = f.pulseAnim:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.5); a2:SetOrder(2)

  f:SetScript("OnEnter", function(self)
    if sample then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    if UnitExists(UNIT) then GameTooltip:SetUnit(UNIT) GameTooltip:Show() end
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- R4 exception: pettarget fires no UNIT_* events of its own
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    PetTarget.Update()
    VFS.PetTargetVisibility.ApplySoftHide()
  end)

  -- Register with FrameBase so appearance/text come from the shared machinery (bars are ours: in place)
  local st = { id = "pettarget", unit = UNIT, button = f, bars = {}, slots = {} }
  st.bars.health = { stock = f.health, draw = f.health, backdrop = FrameBase.AcquireBackdrop(f.health), inPlace = true }
  st.bars.power  = { stock = f.power,  draw = f.power,  backdrop = FrameBase.AcquireBackdrop(f.power),  inPlace = true }
  st.host = TextLayout.CreateHost(f, 5)
  st.slots = { health = f.health, power = f.power, nameplate = f.nameBackground, above = f.health, below = f.power }
  VFS.Frames.pettarget = st
  PetTarget.state = st
  FrameBase.ApplyAppearance(st)
  return f
end

-- Protected placement/scale: caller ensures not InCombatLockdown() -----------------------------------
function PetTarget.ApplyPlacement()
  if not f or InCombatLockdown() then return false end
  f:SetScale(G().petTargetScale)
  local p = DB.Profile().petTargetPlacement
  f:ClearAllPoints()
  if p.anchorTo == "PetFrame" and PetFrame then
    f:SetPoint(p.point, PetFrame, p.relPoint, p.x, p.y)
  elseif p.anchorTo then
    local fb = DB.FALLBACK_PLACEMENT
    f:SetPoint(fb.point, UIParent, fb.point, fb.x, fb.y)
  else
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
  end
  return true
end

-- Update (values Blizzard would normally drive) ---------------------------------------------------------
local function ReactionColor(unit)
  if UnitIsPlayer(unit) and UnitIsFriend("player", unit) then return 0, 0, 1 end
  local r = Util.PlainNumber(UnitReaction(unit, "player"), nil)
  if not r then return 1, 0, 0 end
  if r >= 5 then return 0, 1, 0 elseif r == 4 then return 1, 1, 0 end
  return 1, 0, 0
end

local function ClassColor(unit)
  if not UnitIsPlayer(unit) then return nil end
  local _, class = UnitClass(unit)
  class = Util.Plain(class)
  return class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
end

local function UpdatePortrait(force)
  local style = DB.Effective("pettarget", "portraitStyle")
  local guid = Util.Plain(UnitGUID(UNIT))
  if not force and guid and guid == lastPortraitGUID then return end
  lastPortraitGUID = guid
  local _, class = UnitClass(UNIT)
  class = Util.Plain(class)
  if style ~= "default" and UnitIsPlayer(UNIT) and class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
    f.portrait:SetTexture(style == "class_old" and (TEX .. "UI-Classes-Circles") or "Interface\\WorldStateFrame\\Icons-Classes")
    f.portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
  else
    f.portrait:SetTexCoord(0, 1, 0, 1)
    SetPortraitTexture(f.portrait, UNIT)
  end
end

local function UpdateBars()
  local g = G()
  if UnitIsDeadOrGhost(UNIT) then
    f.health:SetMinMaxValues(0, 1); f.health:SetValue(0); f.deadText:Show()
  else
    f.deadText:Hide()
    local _, _, pct = Client.HealthValues(UNIT)
    f.health:SetMinMaxValues(0, 1); f.health:SetValue(pct or 0)
    local cc = g.classColorHealth and ClassColor(UNIT)
    if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b) else f.health:SetStatusBarColor(0, 1, 0) end
  end
  local _, pmax, ppct, token = Client.PowerValues(UNIT)
  f.power:SetMinMaxValues(0, 1)
  if not pmax or pmax <= 0 then f.power:SetValue(0) else
    f.power:SetValue(ppct or 0)
    local c = token and PowerBarColor and PowerBarColor[token]
    if c then f.power:SetStatusBarColor(c.r, c.g, c.b) else f.power:SetStatusBarColor(0, 0, 1) end
  end
end

local function UpdateMisc()
  local c = Util.Plain(UnitClassification(UNIT))
  f.texture:SetTexture(CLASSIFICATION_ART[c] or (TEX .. "UI-TargetingFrame"))
  f.nameBackground:SetVertexColor(ReactionColor(UNIT))
  local lvl = Util.PlainNumber(UnitLevel(UNIT), nil)
  f.skull:SetShown(lvl ~= nil and lvl < 0)
  local idx = Util.PlainNumber(GetRaidTargetIndex(UNIT), nil)
  if idx and idx >= 1 and idx <= 8 then SetRaidTargetIconTexture(f.raidIcon, idx); f.raidIcon:Show() else f.raidIcon:Hide() end
  f.flash:SetShown(UnitAffectingCombat(UNIT) == true)
end

function PetTarget.Update()
  if not f or sample or not UnitExists(UNIT) then return end
  Util.Safe("pt-portrait", UpdatePortrait)
  Util.Safe("pt-bars", UpdateBars)
  Util.Safe("pt-misc", UpdateMisc)
  FrameBase.ApplyTexts(PetTarget.state)
end

function PetTarget.OnPetTargetChanged()
  if not f or sample then return end
  local guid = Util.Plain(UnitGUID(UNIT))
  if guid ~= lastTargetGUID then
    lastTargetGUID = guid
    Util.Safe("pt-portrait", UpdatePortrait, true)
    if guid and G().petTargetFlashOnNew then f.pulseAnim:Stop(); f.pulseAnim:Play() end
  end
  PetTarget.Update()
end

-- Edit Mode sample ---------------------------------------------------------------------------------------
function PetTarget.SetSample(on)
  sample = on and true or false
  if not f then return end
  if not sample then lastPortraitGUID = nil; PetTarget.Update(); return end
  f.texture:SetTexture(TEX .. "UI-TargetingFrame")
  f.portrait:SetTexCoord(0, 1, 0, 1)
  f.portrait:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Wolf")
  f.nameBackground:SetVertexColor(1, 0, 0)
  f.deadText:Hide(); f.skull:Hide(); f.raidIcon:Hide(); f.flash:Hide()
  f.health:SetMinMaxValues(0, 1); f.health:SetValue(0.73); f.health:SetStatusBarColor(0, 1, 0)
  f.power:SetMinMaxValues(0, 1); f.power:SetValue(0.4); f.power:SetStatusBarColor(0, 0, 1)
  FrameBase.ApplyAppearance(PetTarget.state)
  TextLayout.ApplySample(PetTarget.state.host, DB.Elements("pettarget"), SAMPLE)
  TextLayout.Layout(PetTarget.state.host, DB.Elements("pettarget"), PetTarget.state.slots)
end

function PetTarget.IsSample() return sample end