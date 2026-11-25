-- Velocity Frame Style: show/hide rules for the pet-target frame (ported from VelocityPetTargetFrame UI\Visibility.lua).
--
-- Existence ("pet has a target") is a SECURE state-visibility driver: Blizzard's SecureStateDriverManager calls
-- Show/Hide itself every 0.2 s, legal in combat on this protected unit button.
-- "Hide when the pet's target is my target" cannot be secure (no UnitIsUnit in the restricted environment, see
-- AddonManagement\_EXTERNAL_APIS\wow_secure_visibility_pettarget.md): it is an insecure SOFT-HIDE (alpha 0 + mouse off).
local ADDON_NAME, VFS = ...
local Util, Client, DB = VFS.Util, VFS.Client, VFS.DB

local Visibility = {}
VFS.PetTargetVisibility = Visibility

local DRIVER = "[@pettarget,exists] show; hide"
local driverOn, softHidden, pending = false, false, false

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

function Visibility.ApplySoftHide()
  local f = F(); if not f then return end
  if VFS.PetTarget.IsSample() then
    if softHidden then softHidden = false; f:SetAlpha(1); pcall(f.EnableMouse, f, true) end
    return
  end
  local same = false
  if DB.Global().petTargetHideWhenSame and UnitExists("pettarget") and UnitExists("target") then
    same = Client.UnitIsSameUnit("pettarget", "target") == true
  end
  if same ~= softHidden then
    softHidden = same
    f:SetAlpha(same and 0 or 1)
    if not Visibility.mouseBlocked then
      local ok = pcall(f.EnableMouse, f, not same)
      if not ok then Visibility.mouseBlocked = true end
    end
  end
end

function Visibility.EnterEditMode()
  local f = F(); if not f or InCombatLockdown() then return end
  Visibility.DisableDriver()
  VFS.PetTarget.SetSample(true)
  Visibility.ApplySoftHide()
  f:Show()
end

function Visibility.ExitEditMode()
  local f = F(); if not f then return end
  VFS.PetTarget.SetSample(false)
  if InCombatLockdown() then pending = true return end
  Visibility.EnableDriver()
  VFS.PetTarget.OnPetTargetChanged()
  Visibility.ApplySoftHide()
end

function Visibility.OnRegenEnabled()
  if not pending then return end
  pending = false
  if VFS.EditMode and VFS.EditMode.IsActive() then Visibility.EnterEditMode() else Visibility.EnableDriver() end
  VFS.PetTarget.ApplyPlacement()
end

function Visibility.MarkPending() pending = true end
function Visibility.Status()
  return string.format("pet-target driver %s | soft-hidden %s | pending %s | mouse %s", driverOn and "on" or "off",
    tostring(softHidden), tostring(pending), Visibility.mouseBlocked and "blocked" or "ok")
end