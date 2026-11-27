-- Velocity Frame Style: the Focus frame WE own (SPECS/12_Focus_Frame.md), the Pet Target pattern on Frames\OwnedUnitFrame.lua.
-- Blizzard's FocusFrame is NOT restyled: FocusFrameMixin:SetSmallSize rescales and re-anchors it (and its ToT child) when
-- Edit Mode's "Use larger frame" is off, and a restyle chased that mutation endlessly (attempt 1, 2026-11-26). Instead
-- FocusFrame is suppressed whole as our chrome (frame alpha 0 via Client.ChromeRegions("focus"); never Hide() - protected
-- and an Edit Mode system) and this owned frame draws the focus: full Pet-Target geometry (portrait right, bars left),
-- SecureUnitButtonTemplate on unit "focus", placed per Edit Mode layout, default where Blizzard's frame sits.
--
-- Refresh: focus fires its own UNIT_* events; PLAYER_FOCUS_CHANGED on a new focus. No poller. Our owned Focus Target
-- (Frames\FocusTarget.lua) anchors to THIS frame's global name, so it follows a drag.
-- Forever only: Client.HasFocusFrame(); Era has no focus unit.
local ADDON_NAME, VFS = ...
local DB = VFS.DB

local Focus = {}
VFS.Focus = Focus

Focus.SPEC = {
  id = "focus", unit = "focus", globalName = "VelocityFrameStyleFocus",
  editModeLabel = "Focus", placementKey = "focusPlacement",
  defaultPlacement = DB.DEFAULT_FOCUS_PLACEMENT, anchorFrameName = "FocusFrame",
  flashGlobalKey = "focusFlashOnNew",
  needsPoller = false,
  sample = { name = "Focus", level = "60", health = "3.2K", healthpct = "91%", power = "2.0K", powerpct = "77%" },
  sampleIcon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
  safeTag = "fo",
}

local owned   -- VFS_OwnedUnitFrame

function Focus.Create()
  if owned then return owned.frame end
  if not VFS.Client.HasFocusFrame() then return end
  owned = VFS.OwnedUnitFrame.Create(Focus.SPEC)
  Focus.owned = owned
  Focus.frame = owned.frame
  Focus.state = owned.state
  return owned.frame
end

function Focus.ApplyPlacement() return owned ~= nil and VFS.OwnedUnitFrame.ApplyPlacement(owned) end
function Focus.Update() if owned then VFS.OwnedUnitFrame.Update(owned) end end
function Focus.OnFocusChanged() if owned then VFS.OwnedUnitFrame.OnUnitChanged(owned) end end
function Focus.SetSample(on) if owned then VFS.OwnedUnitFrame.SetSample(owned, on) end end
function Focus.IsSample() return owned ~= nil and owned.sample end

-- Called by the bootstrap for every event it routes to this frame.
function Focus.OnEvent(event, unit)
  if not owned then return end
  if event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    Focus.OnFocusChanged()
  elseif unit == "focus" or event == "RAID_TARGET_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
    Focus.Update()
  end
end