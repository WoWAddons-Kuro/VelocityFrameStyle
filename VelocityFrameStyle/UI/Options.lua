-- Velocity Frame Style: the options page - ONE GotJunk/PlateStyle-style canvas under Settings > AddOns.
-- Sections: About, Theme (global defaults every frame inherits), one section per frame (UI\FramePage.lua),
-- Blizzard shortcuts, Reset. The spec's back-pocket sub-page tree would only change where BuildFrameSection draws.
local ADDON_NAME, VFS = ...
local Util, Client, DB, Widgets, MediaPicker = VFS.Util, VFS.Client, VFS.DB, VFS.Widgets, VFS.MediaPicker

local Options = {}
VFS.Options = Options

local page, category

local function RestyleAll() VFS.FrameBase.RestyleAll() end
local function Pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

function Options.Create()
  if page then return end
  page = Widgets.Page("VelocityFrameStyleOptions", "Velocity Frame Style",
    "Restyles Blizzard's own unit frames and adds a pet-target frame. Text on every frame is a small grid of elements: "
    .. "choose where each one sits, its alignment, size and colour. Frames inherit the Theme below unless overridden. "
    .. "Set bar width and heights below; these do not zoom text, portraits or borders. "
    .. "For consistent sizing, leave Blizzard's Edit Mode frame scale at 100%. " .. Client.EditModeHint())
  local content = page.content

  -- About
  local about = Widgets.Section(content, "About")
  local status = Widgets.Text(about, "")
  status.Update = function(self)
    local sd = VFS.standDown and ("|cffff4040Standing down:|r " .. VFS.standDown .. " is loaded.") or "Active."
    self:SetText(sd .. "  Layout: |cffffffff" .. tostring(VFS.LayoutProfile.Name()) .. "|r")
  end
  about:Add(Widgets.Track(status), 14)
  about:Add(Widgets.Button(about, "Open Edit Mode", function() VFS.EditMode.Open() end), 22, -8)
  about:Finish(); page:Place(about)

  -- Theme
  local theme = Widgets.Section(content, "Theme (defaults for every frame)")
  local texRow = CreateFrame("Frame", nil, theme); texRow:SetSize(Widgets.BOX_W - 2 * Widgets.PAD, 26)
  local texLabel = texRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); texLabel:SetPoint("LEFT", 4, 0); texLabel:SetText("Bar texture")
  local texPick = MediaPicker.Create(texRow, "statusbar", function() return DB.Global().barTexture end, function(v) DB.Global().barTexture = v; RestyleAll() end, 240)
  texPick:SetPoint("LEFT", 150, 0)
  theme:Add(texRow, 26)
  local fontRow = CreateFrame("Frame", nil, theme); fontRow:SetSize(Widgets.BOX_W - 2 * Widgets.PAD, 26)
  local fontLabel = fontRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); fontLabel:SetPoint("LEFT", 4, 0); fontLabel:SetText("Font")
  local fontPick = MediaPicker.Create(fontRow, "font", function() return DB.Global().font end, function(v) DB.Global().font = v; RestyleAll() end, 240)
  fontPick:SetPoint("LEFT", 150, 0)
  theme:Add(fontRow, 26)
  theme:Add(Widgets.Radios(theme, "Font outline", { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } },
    function() return DB.Global().fontStyle end, function(v) DB.Global().fontStyle = v; RestyleAll() end), 20)
  theme:Add(Widgets.Slider(theme, "Bar background", 0, 1, 0.05, function() return DB.Global().backingAlpha end, function(v) DB.Global().backingAlpha = v; RestyleAll() end, Pct), 44, -10)
  theme:Add(Widgets.Check(theme, "Class-coloured health bars (players)", nil, function() return DB.Global().classColorHealth end, function(v) DB.Global().classColorHealth = v; RestyleAll() end), 26)
  theme:Add(Widgets.Radios(theme, "Portraits", { { "default", "Default" }, { "class_old", "Class (old)" }, { "class_new", "Class (new)" } },
    function() return DB.Global().portraitStyle end, function(v) DB.Global().portraitStyle = v; RestyleAll() end), 20)
  theme:Finish(); page:Place(theme)

  -- One section per frame
  for _, id in ipairs(DB.FRAME_IDS) do
    page:Place(VFS.FramePage.BuildFrameSection(content, id))
  end

  -- Reset
  local reset = Widgets.Section(content, "Reset")
  reset:Add(Widgets.Button(reset, "Reset everything to defaults", function() DB.ResetAll(); RestyleAll(); Widgets.RefreshAll() end, 220), 22)
  reset:Finish(); page:Place(reset)

  page:SetScript("OnShow", Options.Refresh)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(page, page.name)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(page)
  end
end

function Options.Refresh()
  if not page then return end
  Widgets.RefreshAll()
  page:FitHeight()
end

function Options.Open()
  if not page then return end
  if Settings and Settings.OpenToCategory and category then Settings.OpenToCategory(category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then InterfaceOptionsFrame_OpenToCategory(page); InterfaceOptionsFrame_OpenToCategory(page) end
end