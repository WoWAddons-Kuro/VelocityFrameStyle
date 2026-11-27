-- Velocity Frame Style: the Target-of-Target frame WE own (SPECS/11_Owned_ToT_Frame.md). Blizzard's TargetFrameToT is
-- a child of TargetFrame with no Edit Mode system, so it cannot be dragged; ours is a SecureUnitButtonTemplate on
-- unit "targettarget" built by Frames\OwnedUnitFrame.lua, placed per Edit Mode layout, default at Blizzard's own
-- spot. Blizzard's ToT art is alpha-zeroed through Client.ChromeRegions("target") - never Hide() (protected, and
-- Blizzard's Update would re-show it).
--
-- Refresh: targettarget DOES fire UNIT_TARGET for unit "target" (unlike pettarget), so there is no poller; the
-- bootstrap routes PLAYER_TARGET_CHANGED, UNIT_TARGET(target) and the targettarget UNIT_* events here.
-- The optional "hide when it is me" rule lives in OwnedUnitFrame (spec.hideWhenMeGlobalKey), shared with Focus Target.
local ADDON_NAME, VFS = ...
local DB = VFS.DB

local ToT = {}
VFS.ToT = ToT

ToT.SPEC = {
  id = "tot", unit = "targettarget", globalName = "VelocityFrameStyleToT",
  editModeLabel = "Target of Target", placementKey = "totPlacement",
  defaultPlacement = DB.DEFAULT_TOT_PLACEMENT, anchorFrameName = "TargetFrame",
  flashGlobalKey = "totFlashOnNew", healthOnlyGlobalKey = "totHealthOnly", hideWhenMeGlobalKey = "totHideWhenMe",
  small = { w = 93, h = 45, portrait = 35 },   -- Blizzard's Era TargetofTargetFrameTemplate footprint (button is re-fitted to the bars)
  needsPoller = false,
  sample = { name = "Target's Target", level = "60", health = "2.1K", healthpct = "88%", power = "1.2K", powerpct = "65%" },
  sampleIcon = "Interface\\Icons\\Ability_Warrior_Charge",
  safeTag = "tot",
}

local owned   -- VFS_OwnedUnitFrame

function ToT.Create()
  if owned then return owned.frame end
  owned = VFS.OwnedUnitFrame.Create(ToT.SPEC)
  ToT.owned = owned
  ToT.frame = owned.frame
  ToT.state = owned.state
  return owned.frame
end

-- Public surface ----------------------------------------------------------------------------------------
function ToT.ApplyPlacement() return owned ~= nil and VFS.OwnedUnitFrame.ApplyPlacement(owned) end

-- Master switch (DB.Global().totEnabled, options page). Off: the secure driver is unregistered and the frame hidden,
-- so no ToT frame of ours exists on screen; Blizzard's is governed by the CVar the same checkbox sets.
function ToT.IsEnabled() return DB.Global().totEnabled ~= false end
function ToT.SetEnabled(on)
  if not owned then return end
  if on then VFS.OwnedVisibility.EnableDriver("tot"); ToT.OnTargetChanged()
  else VFS.OwnedVisibility.DisableDriver("tot"); if not InCombatLockdown() then owned.frame:Hide() else VFS.OwnedVisibility.MarkPending("tot") end end
end

function ToT.Update() if owned then VFS.OwnedUnitFrame.Update(owned) end end
function ToT.OnTargetChanged() if owned then VFS.OwnedUnitFrame.OnUnitChanged(owned); VFS.OwnedUnitFrame.ApplyHideWhenMe(owned) end end
function ToT.SetSample(on) if owned then VFS.OwnedUnitFrame.SetSample(owned, on); VFS.OwnedUnitFrame.ApplyHideWhenMe(owned) end end
function ToT.IsSample() return owned ~= nil and owned.sample end

-- Called by the bootstrap for every event it routes to this frame.
function ToT.OnEvent(event, unit)
  if not owned then return end
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" or (event == "UNIT_TARGET" and unit == "target") then
    ToT.OnTargetChanged()
  elseif unit == "targettarget" or event == "RAID_TARGET_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
    ToT.Update()
  end
end