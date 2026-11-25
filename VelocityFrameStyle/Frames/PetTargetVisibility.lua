-- Velocity Frame Style: show/hide rules for the pet-target frame (ported from VelocityPetTargetFrame UI\Visibility.lua).
--
-- Existence ("pet has a target") is a SECURE state-visibility driver: Blizzard's SecureStateDriverManager calls
-- Show/Hide itself every 0.2 s, legal in combat on this protected unit button.
-- No target-equality soft hide: that result can be secret on Forever.
local ADDON_NAME, VFS = ...

local Visibility = {}
VFS.PetTargetVisibility = Visibility

local DRIVER = "[@pettarget,exists] show; hide"
local driverOn, pending = false, false

local function F() return VFS.PetTarget.frame end

function Visibility.EnableDriver()
  local f = F(); if not f then return end
  if InCombatLockdown() then pending = true return end
  if not driverOn then RegisterAttributeDriver(f, "state-visibility", DRIVER); driverOn = true end
end

function Visibility.DisableDriver()
  local f = F(); if not f then return end
  if InCombatLockdown() then pending = true return end
  if driverOn then UnregisterAttributeDriver(f, "state-visibility"); driverOn = false end
end


function Visibility.EnterEditMode()
  local f = F(); if not f or InCombatLockdown() then return end
  Visibility.DisableDriver()
  VFS.PetTarget.SetSample(true)
  f:Show()
end

function Visibility.ExitEditMode()
  local f = F(); if not f then return end
  VFS.PetTarget.SetSample(false)
  if InCombatLockdown() then pending = true return end
  Visibility.EnableDriver()
  VFS.PetTarget.OnPetTargetChanged()
end

function Visibility.OnRegenEnabled()
  if not pending then return end
  pending = false
  if VFS.EditMode and VFS.EditMode.IsActive() then Visibility.EnterEditMode() else Visibility.EnableDriver() end
  VFS.PetTarget.ApplyPlacement()
end

function Visibility.MarkPending() pending = true end
function Visibility.Status()
  return string.format("pet-target driver %s | pending %s", driverOn and "on" or "off",
    tostring(pending))
end