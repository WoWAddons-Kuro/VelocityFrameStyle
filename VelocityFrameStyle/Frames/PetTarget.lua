-- Velocity Frame Style: the pet-target unit frame - the one frame Blizzard does not have, so we create it.
-- Ported from VelocityPetTargetFrame UI\Frame.lua; since spec 11 the frame itself is built by Frames\OwnedUnitFrame.lua
-- and this file is only the spec plus the public PetTarget.* surface other modules call. Behaviour is unchanged.
-- Protected calls (Show/Hide/SetPoint/SetScale) only out of combat; Frames\OwnedVisibility.lua owns show/hide.
local ADDON_NAME, VFS = ...
local DB = VFS.DB

local PetTarget = {}
VFS.PetTarget = PetTarget

PetTarget.SPEC = {
  id = "pettarget", unit = "pettarget", globalName = "VelocityFrameStylePetTarget",
  editModeLabel = "Pet Target", placementKey = "petTargetPlacement",
  defaultPlacement = DB.DEFAULT_PLACEMENT, anchorFrameName = "PetFrame",
  flashGlobalKey = "petTargetFlashOnNew", healthOnlyGlobalKey = "petTargetHealthOnly",
  needsPoller = true,   -- pettarget fires no UNIT_* events of its own
  sample = { name = "Pet's Target", level = "60", health = "1.5K", healthpct = "73%", power = "400", powerpct = "40%" },
  sampleIcon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
  safeTag = "pt",
}

local owned   -- VFS_OwnedUnitFrame

function PetTarget.Create()
  if owned then return owned.frame end
  owned = VFS.OwnedUnitFrame.Create(PetTarget.SPEC)
  PetTarget.owned = owned
  PetTarget.frame = owned.frame
  PetTarget.state = owned.state
  return owned.frame
end

function PetTarget.ApplyPlacement() return owned ~= nil and VFS.OwnedUnitFrame.ApplyPlacement(owned) end
function PetTarget.Update() if owned then VFS.OwnedUnitFrame.Update(owned) end end
function PetTarget.OnPetTargetChanged() if owned then VFS.OwnedUnitFrame.OnUnitChanged(owned) end end
function PetTarget.SetSample(on) if owned then VFS.OwnedUnitFrame.SetSample(owned, on) end end
function PetTarget.IsSample() return owned ~= nil and owned.sample end