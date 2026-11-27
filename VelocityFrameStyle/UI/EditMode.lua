-- Velocity Frame Style: Edit Mode integration (vendored LibEditMode) for the frames WE own (Pet Target, ToT) - Blizzard's
-- own frames are already Edit Mode systems (R10). Placement is saved into the active layout's record (Core\LayoutProfile)
-- under spec.placementKey; the Edit Mode dialog carries bar width/height sliders, not zoom. Edit Mode forces sample data.
local ADDON_NAME, VFS = ...
local Util, DB = VFS.Util, VFS.DB

local EditMode = {}
VFS.EditMode = EditMode

local lib, editing = nil, false
local registered = {}   -- [VFS_FrameID] = true

local function OnMoved(owned)
  -- LibEditMode anchors UIParent-relative with the same point both sides. Read what it set, persist into the ACTIVE
  -- layout record. Guard: before LayoutProfile has resolved the layout name the record is the "Default" placeholder;
  -- writing there is why the frame "kept appearing somewhere else" (owner 2026-11-25) - the real layout never got it.
  if VFS.LayoutProfile and VFS.LayoutProfile.IsResolved and not VFS.LayoutProfile.IsResolved() then return end
  local point, _, relPoint, x, y = owned.frame:GetPoint(1)
  if not point then return end
  local p = DB.Profile()[owned.spec.placementKey]
  p.anchorTo = nil
  p.relPoint = relPoint or point
  p.point, p.x, p.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
  -- immediately re-apply through our own path so what the lib set and what we persist can never differ
  VFS.OwnedUnitFrame.ApplyPlacement(owned)
end

local function RegisterOne(id, owned)
  if registered[id] then return end
  local frame = owned.frame
  local fb = DB.FALLBACK_PLACEMENT
  lib:AddFrame(frame, function() OnMoved(owned) end, { point = fb.point, x = fb.x, y = fb.y }, owned.spec.editModeLabel)
  local settings = {}
  for _, definition in ipairs(DB.DIMENSION_CONTROLS) do
    local key = definition.key
    local layout = VFS.Chrome.LAYOUT[id]
    local default = key == "barWidth" and layout.health.w
      or (key == "healthHeight" and layout.health.h or layout.power.h)
    settings[#settings + 1] = {
      kind = lib.SettingType.Slider, name = definition.label,
      desc = "Changes bar dimensions only, not portrait, text or border size.",
      default = default, minValue = definition.min, maxValue = definition.max, valueStep = 1,
      formatter = function(v) return string.format("%d UI px", v) end,
      get = function() return DB.BarDimension(id, key) end,
      set = function(_, value)
        DB.SetBarDimension(id, key, value)
        VFS.FrameBase.Restyle(id)
        if VFS.Options and VFS.Options.Refresh then VFS.Options.Refresh() end
      end,
    }
  end
  lib:AddFrameSettings(frame, settings)
  registered[id] = true
end

local function Register() VFS.OwnedUnitFrame.Each(RegisterOne) end

local function OnEnter() editing = true; Register(); VFS.OwnedVisibility.Each(function(id) VFS.OwnedVisibility.EnterEditMode(id) end) end
local function OnExit()
  editing = false
  VFS.OwnedVisibility.Each(function(id, owned) VFS.OwnedVisibility.ExitEditMode(id); VFS.OwnedUnitFrame.ApplyPlacement(owned) end)
end

function EditMode.IsActive() return editing end

function EditMode.OnProfileChanged()
  VFS.OwnedVisibility.Each(function(id, owned) if not VFS.OwnedUnitFrame.ApplyPlacement(owned) then VFS.OwnedVisibility.MarkPending(id) end end)
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
  if not lib then return "LibEditMode not found; owned frames fixed at their saved positions | " .. profile end
  return "LibEditMode" .. (editing and " (editing now)" or "") .. " | " .. profile
end