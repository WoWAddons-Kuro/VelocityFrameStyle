-- Velocity Frame Style: the Focus-Target frame WE own (SPECS/12_Focus_Frame.md) - the ToT of OUR owned Focus frame.
-- A SecureUnitButtonTemplate on unit "focustarget" built by Frames\OwnedUnitFrame.lua, anchored by default to our
-- Focus frame's bottom-right (so it follows a drag), the same relative spot Blizzard uses. Blizzard's FocusFrameToT is a
-- child of FocusFrame and vanishes with it (FocusFrame is suppressed whole as Focus chrome). No master switch of its own:
-- Focus Target exists whenever Focus does (owner 2026-11-26).
--
-- Refresh: focustarget fires UNIT_TARGET for unit "focus"; PLAYER_FOCUS_CHANGED on a new focus. No poller.
local ADDON_NAME, VFS = ...
local DB = VFS.DB

local FocusTarget = {}
VFS.FocusTarget = FocusTarget

FocusTarget.SPEC = {
  id = "focustarget", unit = "focustarget", globalName = "VelocityFrameStyleFocusTarget",
  editModeLabel = "Focus Target", placementKey = "focusTargetPlacement",
  defaultPlacement = DB.DEFAULT_FOCUSTARGET_PLACEMENT, anchorFrameName = "VelocityFrameStyleFocus",
  flashGlobalKey = "focusTargetFlashOnNew", healthOnlyGlobalKey = "focusTargetHealthOnly", hideWhenMeGlobalKey = "focusTargetHideWhenMe",
  small = { w = 93, h = 45, portrait = 35 },
  needsPoller = false,
  sample = { name = "Focus's Target", level = "60", health = "1.8K", healthpct = "80%", power = "900", powerpct = "50%" },
  sampleIcon = "Interface\\Icons\\Ability_Hunter_SniperShot",
  safeTag = "ft",
}

local owned   -- VFS_OwnedUnitFrame

function FocusTarget.Create()
  if owned then return owned.frame end
  if not VFS.Client.HasFocusFrame() then return end
  owned = VFS.OwnedUnitFrame.Create(FocusTarget.SPEC)
  FocusTarget.owned = owned
  FocusTarget.frame = owned.frame
  FocusTarget.state = owned.state
  return owned.frame
end

function FocusTarget.ApplyPlacement() return owned ~= nil and VFS.OwnedUnitFrame.ApplyPlacement(owned) end
function FocusTarget.Update() if owned then VFS.OwnedUnitFrame.Update(owned) end end
function FocusTarget.OnFocusChanged() if owned then VFS.OwnedUnitFrame.OnUnitChanged(owned); VFS.OwnedUnitFrame.ApplyHideWhenMe(owned) end end
function FocusTarget.SetSample(on) if owned then VFS.OwnedUnitFrame.SetSample(owned, on); VFS.OwnedUnitFrame.ApplyHideWhenMe(owned) end end
function FocusTarget.IsSample() return owned ~= nil and owned.sample end

-- Called by the bootstrap for every event it routes to this frame.
function FocusTarget.OnEvent(event, unit)
  if not owned then return end
  if event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_ENTERING_WORLD" or (event == "UNIT_TARGET" and unit == "focus") then
    FocusTarget.OnFocusChanged()
  elseif unit == "focustarget" or event == "RAID_TARGET_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
    FocusTarget.Update()
  end
end