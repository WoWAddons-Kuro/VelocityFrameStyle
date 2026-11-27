-- Velocity Frame Style: show/hide rules for the frames we own (ported from VelocityPetTargetFrame UI\Visibility.lua;
-- generalised from PetTargetVisibility for spec 11). One record per VFS_OwnedUnitFrame.
--
-- Existence ("the unit exists") is a SECURE state-visibility driver: Blizzard's SecureStateDriverManager calls
-- Show/Hide itself every 0.2 s, legal in combat on this protected unit button.
-- No target-equality soft hide here: that result can be secret on Forever (ToT's optional "on me" rule is GUID-based
-- and cosmetic, inside Frames\ToT.lua).
local ADDON_NAME, VFS = ...

local Visibility = {}
VFS.OwnedVisibility = Visibility

local records = {}   -- [spec.id] = { owned, driver, driverOn, pending }

function Visibility.Register(owned)
  local r = { owned = owned, driver = "[@" .. owned.spec.unit .. ",exists] show; hide", driverOn = false, pending = false }
  records[owned.spec.id] = r
  return r
end

local function R(id) return records[id] end

function Visibility.EnableDriver(id)
  local r = R(id); if not r then return end
  if InCombatLockdown() then r.pending = true return end
  if not r.driverOn then RegisterAttributeDriver(r.owned.frame, "state-visibility", r.driver); r.driverOn = true end
end

function Visibility.DisableDriver(id)
  local r = R(id); if not r then return end
  if InCombatLockdown() then r.pending = true return end
  if r.driverOn then UnregisterAttributeDriver(r.owned.frame, "state-visibility"); r.driverOn = false end
end

function Visibility.EnterEditMode(id)
  local r = R(id); if not r or InCombatLockdown() then return end
  Visibility.DisableDriver(id)
  VFS.OwnedUnitFrame.SetSample(r.owned, true)
  r.owned.frame:Show()
end

function Visibility.ExitEditMode(id)
  local r = R(id); if not r then return end
  VFS.OwnedUnitFrame.SetSample(r.owned, false)
  if InCombatLockdown() then r.pending = true return end
  Visibility.EnableDriver(id)
  VFS.OwnedUnitFrame.OnUnitChanged(r.owned)
end

function Visibility.OnRegenEnabled()
  for id, r in pairs(records) do
    if r.pending then
      r.pending = false
      if VFS.EditMode and VFS.EditMode.IsActive() then Visibility.EnterEditMode(id) else Visibility.EnableDriver(id) end
      VFS.OwnedUnitFrame.ApplyPlacement(r.owned)
    end
  end
end

function Visibility.MarkPending(id) local r = R(id); if r then r.pending = true end end

function Visibility.Each(fn) for id, r in pairs(records) do fn(id, r.owned) end end

function Visibility.Status()
  local parts = {}
  for id, r in pairs(records) do
    parts[#parts + 1] = string.format("%s driver %s | pending %s", id, r.driverOn and "on" or "off", tostring(r.pending))
  end
  table.sort(parts)
  return #parts > 0 and table.concat(parts, " || ") or "no owned frames"
end

-- Compatibility shim for the pet-target call sites (VelocityFrameStyle.lua, UI\EditMode.lua)
VFS.PetTargetVisibility = {
  EnableDriver = function() Visibility.EnableDriver("pettarget") end,
  DisableDriver = function() Visibility.DisableDriver("pettarget") end,
  EnterEditMode = function() Visibility.EnterEditMode("pettarget") end,
  ExitEditMode = function() Visibility.ExitEditMode("pettarget") end,
  OnRegenEnabled = Visibility.OnRegenEnabled,
  MarkPending = function() Visibility.MarkPending("pettarget") end,
  Status = Visibility.Status,
}