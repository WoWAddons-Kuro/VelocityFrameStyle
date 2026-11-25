-- Velocity Frame Style: Edit Mode integration (vendored LibEditMode) for the pet-target frame only - Blizzard's own
-- frames are already Edit Mode systems (R10). Placement is saved into the active layout's record (Core\LayoutProfile);
-- the Edit Mode dialog carries the Scale slider. While Edit Mode is open the frame is forced visible with sample data.
local ADDON_NAME, VFS = ...
local Util, DB = VFS.Util, VFS.DB

local EditMode = {}
VFS.EditMode = EditMode

local lib, editing, registered = nil, false, false

local function OnMoved(frame)
  -- LibEditMode anchors UIParent-relative with the same point both sides. Read what it set, persist into the ACTIVE
  -- layout record. Guard: before LayoutProfile has resolved the layout name the record is the "Default" placeholder;
  -- writing there is why the frame "kept appearing somewhere else" (owner 2026-11-25) - the real layout never got it.
  if VFS.LayoutProfile and VFS.LayoutProfile.IsResolved and not VFS.LayoutProfile.IsResolved() then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  if not point then return end
  local p = DB.Profile().petTargetPlacement
  p.anchorTo = nil
  p.relPoint = relPoint or point
  p.point, p.x, p.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
  -- immediately re-apply through our own path so what the lib set and what we persist can never differ
  VFS.PetTarget.ApplyPlacement()
end

local function Register()
  if registered then return end
  local frame = VFS.PetTarget.frame
  if not frame then return end
  local fb = DB.FALLBACK_PLACEMENT
  lib:AddFrame(frame, OnMoved, { point = fb.point, x = fb.x, y = fb.y }, "Pet Target")
  lib:AddFrameSettings(frame, {
    {
      kind = lib.SettingType.Slider, name = "Scale", desc = "Size of the pet-target frame.",
      default = DB.DEFAULT_GLOBAL.petTargetScale, minValue = 0.5, maxValue = 1.5, valueStep = 0.05,
      formatter = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
      get = function() return DB.Global().petTargetScale end,
      set = function(_, value)
        DB.Global().petTargetScale = value
        VFS.PetTarget.ApplyPlacement()
        if VFS.Options and VFS.Options.Refresh then VFS.Options.Refresh() end
      end,
    },
  })
  registered = true
end

local function OnEnter() editing = true; Register(); VFS.PetTargetVisibility.EnterEditMode() end
local function OnExit() editing = false; VFS.PetTargetVisibility.ExitEditMode(); VFS.PetTarget.ApplyPlacement() end

function EditMode.IsActive() return editing end

function EditMode.OnProfileChanged()
  if not VFS.PetTarget.ApplyPlacement() then VFS.PetTargetVisibility.MarkPending() end
end

function EditMode.Setup()
  if lib then return true end
  local found = LibStub and LibStub("LibEditMode", true)
  if not found or type(found.AddFrame) ~= "function" or type(found.RegisterCallback) ~= "function" then
    VFS.features["EditMode"] = false
    return false
  end
  lib = found
  lib:RegisterCallback("enter", OnEnter)
  lib:RegisterCallback("exit", OnExit)
  Register()
  VFS.features["EditMode"] = true
  return true
end

function EditMode.Open()
  if EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
end

function EditMode.Status()
  local profile = VFS.LayoutProfile and VFS.LayoutProfile.Status() or "no layout profile"
  if not lib then return "LibEditMode not found; pet-target frame fixed at its saved position | " .. profile end
  return "LibEditMode" .. (editing and " (editing now)" or "") .. " | " .. profile
end