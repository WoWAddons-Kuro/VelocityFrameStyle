-- Velocity Frame Style: factory for the unit frames WE own (Blizzard has none, or we replace Blizzard's): today Pet Target,
-- next Target-of-Target (SPECS/11_Owned_ToT_Frame.md). Extracted from Frames\PetTarget.lua with zero behaviour change.
-- Classic TargetFrame art geometry, a SecureUnitButtonTemplate (left-click targets, right-click menu), bars/text through
-- FrameBase + Chrome like every other frame. Protected calls (Show/Hide/SetPoint/SetScale) only out of combat; the
-- secure visibility driver lives in Frames\OwnedVisibility.lua.
--
-- VFS_OwnedUnitFrameSpec = {
--   id            = VFS_FrameID ("pettarget" | "tot"),   unit = unitToken,   globalName = frame global name,
--   editModeLabel = string,            placementKey = profile field ("petTargetPlacement"),
--   defaultPlacement = VFS_Placement,  anchorFrameName = the global the default placement anchors to ("PetFrame"),
--   flashGlobalKey = DB.Global() boolean controlling the new-unit portrait pulse (nil = never),
--   healthOnlyGlobalKey = DB.Global() boolean "only show health bar" (nil = never),
--   hideWhenMeGlobalKey = DB.Global() boolean "soft-hide when the unit is the player" (nil = never),
--   small         = nil | { w, h, portrait }  small frame (ToT): no classic art, portrait top-left, bars right,
--   needsPoller   = bool (pettarget: no UNIT_* events of its own -> 0.2 s OnUpdate),
--   sample        = text-sample values for Edit Mode,   sampleIcon = portrait texture in Edit Mode,
--   safeTag       = short prefix for Util.Safe labels ("pt"),
-- }
-- VFS_OwnedUnitFrame (returned by Create) = { spec, frame, state (FrameBase st), sample, lastPortraitGUID, lastUnitGUID }
local ADDON_NAME, VFS = ...
local Util, Client, DB, FrameBase, TextLayout = VFS.Util, VFS.Client, VFS.DB, VFS.FrameBase, VFS.TextLayout

local OwnedUnitFrame = {}
VFS.OwnedUnitFrame = OwnedUnitFrame

local TEX = "Interface\\TargetingFrame\\"
local CLASSIFICATION_ART = {
  elite = TEX .. "UI-TargetingFrame-Elite", rareelite = TEX .. "UI-TargetingFrame-Rare-Elite",
  rare = TEX .. "UI-TargetingFrame-Rare", worldboss = TEX .. "UI-TargetingFrame-Elite",
}
OwnedUnitFrame.TEX = TEX

local function G() return DB.Global() end

local registry = {}   -- [VFS_FrameID] = VFS_OwnedUnitFrame
function OwnedUnitFrame.Get(id) return registry[id] end
function OwnedUnitFrame.Each(fn) for id, o in pairs(registry) do fn(id, o) end end

-- Small frame geometry (ToT). The BUTTON is sized to what we draw - disc + name row + bars + borders - not to Blizzard's
-- 93x45 art footprint: LibEditMode draws its selection box around the button rect, so the two must agree (owner,
-- Forever 2026-11-26). Re-run on every bar-dimension change (Geometry.ApplyBarDimensions) so the box follows the bars.
-- Protected (SetSize/SetPoint on the secure button): the caller guarantees not InCombatLockdown().
function OwnedUnitFrame.FitSmall(o, barW, healthH, powerH)
  local spec, f = o.spec, o.frame
  if not spec.small or not f then return end
  local L = VFS.Chrome.LAYOUT[spec.id]
  local P, pad, border = spec.small.portrait, L.discPad, FrameBase.BAR_BORDER_WIDTH
  local discD = P + 2 * pad                               -- Chrome disc diameter around the portrait
  local healthOnly = spec.healthOnlyGlobalKey and DB.Global()[spec.healthOnlyGlobalKey]
  local barsH = healthH + 2 * border + ((not healthOnly) and (powerH + border) or 0)
  local w = discD + 2 + barW + 2 * border
  local h = math.max(discD, L.nameRow + barsH) + 2 * border
  f:SetSize(w, h)
  f.portrait:ClearAllPoints(); f.portrait:SetPoint("LEFT", f, "LEFT", pad + border, 0)
  -- Health bar: left edge just past the disc; name row above it, power bar below it, all inside the button.
  f.health:ClearAllPoints()
  f.health:SetPoint("TOPLEFT", f, "TOPLEFT", discD + 2 + border, -(border + L.nameRow))
  f.health:SetSize(barW, healthH)
  f.power:SetSize(barW, powerH)
  -- LibEditMode's selection frame is SetAllPoints() on the button, so it follows this rect by itself.
end

-- Build ------------------------------------------------------------------------------------------
-- Classic TargetFrame geometry (Era TargetFrame.xml): 232x100 button, portrait top-right, bars left of it.
function OwnedUnitFrame.Create(spec)
  local o = { spec = spec, sample = false }
  local UNIT = spec.unit
  local f = CreateFrame("Button", spec.globalName, UIParent, "SecureUnitButtonTemplate")
  o.frame = f
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
  -- Reserve levels below the bars for chrome/glow. At the default child level
  -- Chrome's level clamp put its plate and glow ABOVE our fills.
  f.health:SetFrameLevel(f:GetFrameLevel() + 4)
  f.health:SetSize(119, 12)
  f.health:SetPoint("TOPRIGHT", -90, -45)
  f.health:SetMinMaxValues(0, 1); f.health:SetValue(1); f.health:EnableMouse(false)

  -- Plain widget: TextStatusBar's Lua updater cannot compare secret capacities
  -- when invoked by an addon. FrameBase queries resource presence instead.
  f.power = CreateFrame("StatusBar", nil, f)
  f.power.unit = UNIT
  f.power:SetFrameLevel(f:GetFrameLevel() + 4)
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
  -- Stop() mid-pulse leaves the texture at the interrupted alpha (owner, Forever 2026-11-26: a "doubled portrait" on
  -- Focus Target was this ADD-blended mask frozen half-lit after two rapid unit changes). Always land on 0.
  f.pulseAnim:SetScript("OnFinished", function() f.pulse:SetAlpha(0) end)
  f.pulseAnim:SetScript("OnStop", function() f.pulse:SetAlpha(0) end)

  f:SetScript("OnEnter", function(self)
    if o.sample then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    if UnitExists(UNIT) then GameTooltip:SetUnit(UNIT) GameTooltip:Show() end
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)

  if spec.needsPoller then
    -- R4 exception: pettarget fires no UNIT_* events of its own
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + elapsed
      if acc < 0.2 then return end
      acc = 0
      OwnedUnitFrame.Update(o)
    end)
  end

  -- Register with FrameBase so appearance/text come from the shared machinery (bars are ours). Geometric chrome:
  -- bars sized to Chrome.LAYOUT[id] and laid on the side the layout says (side = "left": bars left of the portrait,
  -- Pet Target / Target style; side = "right": portrait left, bars right, ToT / Pet style); texture/nameBackground
  -- are ChromeRegions and go to alpha 0, the plate/disc replace them.
  local st = { id = spec.id, unit = UNIT, button = f, bars = {}, slots = {} }
  st.bars.health = { stock = f.health, backdrop = FrameBase.AcquireBackdrop(f.health), movable = true }
  st.bars.power  = { stock = f.power,  backdrop = FrameBase.AcquireBackdrop(f.power),  movable = true }
  local L = VFS.Chrome.LAYOUT[spec.id]
  if spec.small then
    -- Small owned frame (ToT): portrait at the left, bars to its right. No classic art; the plate is the chrome.
    local P = spec.small.portrait
    f:SetHitRectInsets(0, 0, 0, 0)
    f.portrait:SetSize(P, P)
    f.texture:Hide(); f.nameBackground:Hide(); f.flash:Hide()
    f.raidIcon:ClearAllPoints(); f.raidIcon:SetSize(16, 16); f.raidIcon:SetPoint("CENTER", f.portrait, "TOP", 0, 0)
    f.pulse:SetSize(P + 8, P + 8)
    f.power:ClearAllPoints(); f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -FrameBase.BAR_BORDER_WIDTH)
    OwnedUnitFrame.FitSmall(o, L.health.w, L.health.h, L.power.h)   -- button size + portrait/health anchors
  else
    f.health:ClearAllPoints(); f.health:SetPoint("RIGHT", f.portrait, "LEFT", -8, 4); f.health:SetSize(L.health.w, L.health.h)
    f.power:ClearAllPoints();  f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -FrameBase.BAR_BORDER_WIDTH); f.power:SetSize(L.power.w, L.power.h)
  end
  st.host = TextLayout.CreateHost(f, 7)
  f.art:SetFrameLevel(f:GetFrameLevel() + 6)
  FrameBase.PortraitBadge(st)
  st.slots = { health = f.health, power = f.power, nameplate = FrameBase.NameRowAbove(st, f.health), above = f.health, below = f.power, portrait = st.portraitBadge }
  VFS.Frames[spec.id] = st
  o.state = st
  registry[spec.id] = o
  VFS.Chrome.Create(st)
  FrameBase.ApplyAppearance(st)
  return o
end

-- Protected placement/scale: caller ensures not InCombatLockdown() -----------------------------------
function OwnedUnitFrame.ApplyPlacement(o)
  local f = o.frame
  if not f or InCombatLockdown() then return false end
  -- No zoom: dimensions change the bars; frame stays at its natural scale.
  local p = DB.Profile()[o.spec.placementKey]
  local anchorName = o.spec.anchorFrameName
  local anchor = anchorName and _G[anchorName]
  -- A saved record anchored to a frame other than the spec's (a renamed/retired anchor, e.g. Focus Target records from
  -- before the owned Focus existed said "FocusFrame") is treated as "use the spec default", never the screen-centre
  -- fallback - the user never chose that spot (owner, Forever 2026-11-26). nil anchorTo still means "dragged: UIParent".
  if p.anchorTo and anchorName and p.anchorTo ~= anchorName then
    local d = o.spec.defaultPlacement
    p.anchorTo, p.point, p.relPoint, p.x, p.y = d.anchorTo, d.point, d.relPoint, d.x, d.y
  end
  f:ClearAllPoints()
  if p.anchorTo == anchorName and anchor then
    f:SetPoint(p.point, anchor, p.relPoint, p.x, p.y)
  elseif p.anchorTo then
    local fb = DB.FALLBACK_PLACEMENT
    f:SetPoint(fb.point, UIParent, fb.point, fb.x, fb.y)
  else
    f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x, p.y)
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

local function UpdatePortrait(o, force)
  local f, UNIT = o.frame, o.spec.unit
  local style = DB.Effective(o.spec.id, "portraitStyle")
  local guid = Util.Plain(UnitGUID(UNIT))
  if not force and guid and guid == o.lastPortraitGUID then return end
  o.lastPortraitGUID = guid
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

local function UpdateBars(o)
  local f, UNIT = o.frame, o.spec.unit
  -- Widget setters accept secret numbers. Do not discard them via PlainNumber,
  -- divide them in Lua, or turn an unavailable computed percentage into zero.
  f.health:SetMinMaxValues(0, UnitHealthMax(UNIT))
  f.health:SetValue(UnitHealth(UNIT))
  f.power:SetMinMaxValues(0, UnitPowerMax(UNIT))
  f.power:SetValue(UnitPower(UNIT))
  FrameBase.ApplyHealthColor(f.health, UNIT)
  FrameBase.ApplyPowerColor(f.power, UNIT)
  f.deadText:Hide()
end

local function UpdateMisc(o)
  local f, UNIT = o.frame, o.spec.unit
  local c = Util.Plain(UnitClassification(UNIT))
  f.texture:SetTexture(CLASSIFICATION_ART[c] or (TEX .. "UI-TargetingFrame"))
  f.nameBackground:SetVertexColor(ReactionColor(UNIT))
  local lvl = Util.PlainNumber(UnitLevel(UNIT), nil)
  f.skull:SetShown(lvl ~= nil and lvl < 0)
  local idx = Util.PlainNumber(GetRaidTargetIndex(UNIT), nil)
  if idx and idx >= 1 and idx <= 8 then SetRaidTargetIconTexture(f.raidIcon, idx); f.raidIcon:Show() else f.raidIcon:Hide() end
  -- The legacy full-frame flash must not overlay the geometric bars.
  f.flash:Hide()
  VFS.Chrome.UpdateCombat(o.state)
end

function OwnedUnitFrame.Update(o)
  if not o.frame or o.sample or not UnitExists(o.spec.unit) then return end
  local tag = o.spec.safeTag
  Util.Safe(tag .. "-portrait", UpdatePortrait, o)
  Util.Safe(tag .. "-bars", UpdateBars, o)
  Util.Safe(tag .. "-misc", UpdateMisc, o)
  FrameBase.ApplyTexts(o.state)
  OwnedUnitFrame.ApplyHideWhenMe(o)
end

-- Optional "hide when the watched unit is me" (spec.hideWhenMeGlobalKey, e.g. totHideWhenMe; nil = never). Compares
-- UnitGUIDs, which are plain on both clients (UnitIsUnit may be secret on Forever). Cosmetic only: SetAlpha(0) -
-- Hide() is protected in combat. Out of combat the hit rect is also collapsed so the invisible frame cannot eat clicks.
local HIT_COLLAPSED = 10000
function OwnedUnitFrame.ApplyHideWhenMe(o)
  local key, f = o.spec.hideWhenMeGlobalKey, o.frame
  if not key or not f then return end
  local hide = false
  if G()[key] and not o.sample then
    local g = Util.Plain(UnitGUID(o.spec.unit))
    hide = g ~= nil and g == Util.Plain(UnitGUID("player"))
  end
  f:SetAlpha(hide and 0 or 1)
  if not InCombatLockdown() then
    if hide then f:SetHitRectInsets(HIT_COLLAPSED, HIT_COLLAPSED, HIT_COLLAPSED, HIT_COLLAPSED)
    elseif o.spec.small then f:SetHitRectInsets(0, 0, 0, 0)
    else f:SetHitRectInsets(96, 40, 10, 9) end
  end
end

-- The watched unit may have changed (new GUID): refresh the portrait at once and pulse if the option is on.
function OwnedUnitFrame.OnUnitChanged(o)
  if not o.frame or o.sample then return end
  local guid = Util.Plain(UnitGUID(o.spec.unit))
  if guid ~= o.lastUnitGUID then
    o.lastUnitGUID = guid
    Util.Safe(o.spec.safeTag .. "-portrait", UpdatePortrait, o, true)
    if guid and o.spec.flashGlobalKey and G()[o.spec.flashGlobalKey] then o.frame.pulseAnim:Stop(); o.frame.pulseAnim:Play() end
  end
  OwnedUnitFrame.Update(o)
end

-- Edit Mode sample ---------------------------------------------------------------------------------------
function OwnedUnitFrame.SetSample(o, on)
  o.sample = on and true or false
  local f, st, id = o.frame, o.state, o.spec.id
  if not f then return end
  if not o.sample then o.lastPortraitGUID = nil; OwnedUnitFrame.Update(o); return end
  f.texture:SetTexture(TEX .. "UI-TargetingFrame")
  f.portrait:SetTexCoord(0, 1, 0, 1)
  f.portrait:SetTexture(o.spec.sampleIcon)
  f.nameBackground:SetVertexColor(1, 0, 0)
  f.deadText:Hide(); f.skull:Hide(); f.raidIcon:Hide(); f.flash:Hide()
  f.health:SetMinMaxValues(0, 1); f.health:SetValue(0.73); f.health:SetStatusBarColor(0, 1, 0)
  f.power:SetMinMaxValues(0, 1); f.power:SetValue(0.4); f.power:SetStatusBarColor(0, 0, 1)
  FrameBase.ApplyAppearance(st)
  TextLayout.ApplySample(st.host, DB.Elements(id), o.spec.sample)
  if st.powerAbsent then
    local powerText = st.host.text.power
    if powerText then powerText.vfsVisible = false; powerText:Hide() end
  end
  TextLayout.Layout(st.host, DB.Elements(id), st.slots)
end

function OwnedUnitFrame.IsSample(o) return o.sample end