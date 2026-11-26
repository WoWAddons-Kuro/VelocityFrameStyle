-- Velocity Frame Style: BuildFrameSection(content, frameID) -> Section. One function builds the per-frame settings
-- block (Enabled, overrides, the text-element grid, frame extras). Today every section goes on the single options page;
-- the back-pocket sub-page tree (spec) would call this with a child canvas instead - nothing else changes.
local ADDON_NAME, VFS = ...
local Util, Client, DB, Widgets, MediaPicker, Format = VFS.Util, VFS.Client, VFS.DB, VFS.Widgets, VFS.MediaPicker, VFS.Format

local FramePage = {}
VFS.FramePage = FramePage

local LABELS = { player = "Player", target = "Target", pet = "Pet", pettarget = "Pet Target", tot = "Target of Target" }
FramePage.LABELS = LABELS

local ANCHORS = { { "nameplate", "Name row" }, { "health", "Health bar" }, { "power", "Power bar" }, { "above", "Above" }, { "below", "Below" }, { "portrait", "Portrait badge" }, { "hidden", "Hidden" } }
local ALIGNS  = { { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }
local COLORS  = { { "stock", "Stock" }, { "white", "White" }, { "difficulty", "Difficulty" }, { "class", "Class" }, { "reaction", "Reaction" }, { "custom", "Custom" } }
local SIZES = {}
for s = 6, 20 do SIZES[#SIZES + 1] = { s, tostring(s) } end

local function Restyle(id) VFS.FrameBase.Restyle(id) end

-- One override row: [x] Use theme <label>   (when unticked, the frame's own control appears to the right)
local function OverrideRow(box, id, key, label, makeControl)
  local holder = CreateFrame("Frame", nil, box); holder:SetSize(Widgets.BOX_W - 2 * Widgets.PAD, 26)
  local cb = CreateFrame("CheckButton", nil, holder, "InterfaceOptionsCheckButtonTemplate")
  cb:SetPoint("LEFT", 0, 0)
  cb.Text:SetText("Use theme " .. label)
  local control = makeControl(holder)
  control:SetPoint("LEFT", cb.Text, "RIGHT", 16, 0)
  cb:SetScript("OnClick", function(self)
    local f = DB.Frame(id)
    if self:GetChecked() then f.override[key] = nil else f.override[key] = DB.Global()[key] end
    Restyle(id); Widgets.RefreshAll()
  end)
  holder.Update = function()
    local inherit = DB.Frame(id).override[key] == nil
    cb:SetChecked(inherit)
    control:SetShown(not inherit)
    if control.Update then control:Update() end
  end
  return Widgets.Track(holder)
end

-- The text-element grid: one row per element --------------------------------------------------------
local function ElementRow(box, id, index)
  local row = CreateFrame("Frame", nil, box); row:SetSize(Widgets.BOX_W - 2 * Widgets.PAD, 26)
  local function E() return DB.Elements(id)[index] end
  row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); row.label:SetPoint("LEFT", 6, 0); row.label:SetWidth(60); row.label:SetJustifyH("LEFT")
  local anchor = Widgets.Dropdown(row, ANCHORS, function() return E() and E().anchor end, function(v) if E() then E().anchor = v; Restyle(id) end end, 85)
  anchor:SetPoint("LEFT", row, "LEFT", 55, -2)
  local align = Widgets.Dropdown(row, ALIGNS, function() return E() and E().align end, function(v) if E() then E().align = v; Restyle(id) end end, 55)
  align:SetPoint("LEFT", row, "LEFT", 165, -2)
  local size = Widgets.Dropdown(row, SIZES, function() return E() and E().size end, function(v) if E() then E().size = v; Restyle(id) end end, 40)
  size:SetPoint("LEFT", row, "LEFT", 245, -2)
  local color = Widgets.Dropdown(row, COLORS, function() return E() and E().color end, function(v) if E() then E().color = v; Restyle(id) end end, 65)
  color:SetPoint("LEFT", row, "LEFT", 310, -2)
  local valueFormat = Widgets.Dropdown(row, Format.VALUE_FORMATS,
    function() return E() and E().valueFormat or "current" end,
    function(v)
      if E() then Format.SetValueFormat(E(), v); Restyle(id) end
    end, 95)
  valueFormat:SetPoint("LEFT", row, "LEFT", 425, -2)
  -- custom colour swatch, visible only in custom mode
  row.swatch = CreateFrame("Button", nil, row); row.swatch:SetSize(16, 16); row.swatch:SetPoint("LEFT", row, "LEFT", 410, 0)
  row.swatch.tex = row.swatch:CreateTexture(nil, "ARTWORK"); row.swatch.tex:SetAllPoints(); row.swatch.tex:SetColorTexture(1, 1, 1)
  row.swatch:SetScript("OnClick", function()
    local e = E(); if not e then return end
    local c = e.customColor or { 1, 1, 1 }
    local function Changed() local r, g, b = ColorPickerFrame:GetColorRGB(); e.customColor = { r, g, b }; Restyle(id); Widgets.RefreshAll() end
    if ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], swatchFunc = Changed, cancelFunc = function() end })
    else ColorPickerFrame.func = Changed; ColorPickerFrame:SetColorRGB(c[1], c[2], c[3]); ColorPickerFrame:Show() end
  end)
  row.Update = function()
    local e = E()
    row:SetShown(e ~= nil)
    if not e then return end
    row.label:SetText(e.label or e.id)
    valueFormat:SetShown(e.id == "health" or e.id == "power")
    local c = e.customColor or { 1, 1, 1 }
    row.swatch.tex:SetColorTexture(c[1], c[2], c[3])
    row.swatch:SetShown(e.color == "custom")
  end
  return Widgets.Track(row)
end

-- The section ----------------------------------------------------------------------------------------------
function FramePage.BuildFrameSection(content, id)
  local box = Widgets.Section(content, LABELS[id] or id)
  box:Add(Widgets.Check(box, "Enabled", "Restyle this frame.", function() return DB.Frame(id).enabled end,
    function(v) DB.Frame(id).enabled = v; Restyle(id) end), 26)
  box:Add(Widgets.Text(box, "Bar dimensions only; text, portrait and borders do not zoom. Changes made in combat apply afterward."), 28)
  for _, definition in ipairs(DB.DIMENSION_CONTROLS) do
    local key = definition.key
    box:Add(Widgets.Slider(box, definition.label, definition.min, definition.max, 1,
      function() return DB.BarDimension(id, key) end,
      function(v) DB.SetBarDimension(id, key, v); Restyle(id) end,
      function(v) return string.format("%d UI px", v) end), 44, -10)
  end

  -- Overrides
  box:Add(OverrideRow(box, id, "barTexture", "bar texture", function(h) return MediaPicker.Create(h, "statusbar", function() return DB.Effective(id, "barTexture") end, function(v) DB.Frame(id).override.barTexture = v; Restyle(id) end, 180) end), 26)
  box:Add(OverrideRow(box, id, "font", "font", function(h) return MediaPicker.Create(h, "font", function() return DB.Effective(id, "font") end, function(v) DB.Frame(id).override.font = v; Restyle(id) end, 180) end), 26)
  box:Add(OverrideRow(box, id, "backingAlpha", "bar background", function(h)
    local s = Widgets.Slider(h, "Background", 0, 1, 0.05, function() return DB.Effective(id, "backingAlpha") end, function(v) DB.Frame(id).override.backingAlpha = v; Restyle(id) end, function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    s:SetSize(260, 44); return s end), 44)

  -- Text grid
  local hdr = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); hdr:SetText("Text")
  box:Add(hdr, 14, -10)
  local cols = CreateFrame("Frame", nil, box); cols:SetSize(560, 14)
  for _, column in ipairs({ {"Element",6}, {"Position",75}, {"Align",185}, {"Size",265}, {"Colour",330}, {"Format",445} }) do
    local label = cols:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    label:SetPoint("LEFT", column[2], 0); label:SetText(column[1])
  end
  box:Add(cols, 14, -2)
  local maxRows = #DB.DefaultElements()
  for i = 1, maxRows do box:Add(ElementRow(box, id, i), 26, -2) end

  -- Frame extras
  if id == "pet" and Client.PetHappinessFrame and Client.PetHappinessFrame() then
    box:Add(Widgets.Check(box, "Pet info panel on mouse-over",
      "Hover the happiness icon or the pet's level badge (out of combat) for happiness, time to the next mood, XP and training points.",
      function() return DB.Global().petHappinessPanel ~= false end, function(v) DB.Global().petHappinessPanel = v end), 26, -8)
    box:Add(Widgets.Check(box, "Only show the pet info panel while Shift is held", nil,
      function() return DB.Global().petHappinessPanelShiftOnly == true end, function(v) DB.Global().petHappinessPanelShiftOnly = v end), 26)
  end
  if id == "pettarget" then
    box:Add(Widgets.Check(box, "Only show health bar",
      "Hide the pet-target power bar and its text, background and border, including in Edit Mode.",
      function() return DB.Global().petTargetHealthOnly end, function(v) DB.Global().petTargetHealthOnly = v; Restyle(id) end), 26, -8)
    box:Add(Widgets.Check(box, "Flash when the pet picks a new target", nil,
      function() return DB.Global().petTargetFlashOnNew end, function(v) DB.Global().petTargetFlashOnNew = v end), 26)
    box:Add(Widgets.Button(box, "Copy text layout from Target", function()
      DB.Frame("pettarget").elements = Util.DeepCopy(DB.Elements("target")); Restyle("pettarget"); Widgets.RefreshAll()
    end, 220), 22, -8)
  end

  box:Add(Widgets.Button(box, "Reset " .. (LABELS[id] or id), function() DB.ResetFrame(id); Restyle(id); Widgets.RefreshAll() end, 160), 22, -10)
  box:Finish()
  return box
end