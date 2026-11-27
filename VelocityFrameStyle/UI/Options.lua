-- Velocity Frame Style: the options pages under Settings > AddOns. A ROOT canvas (About, Theme, Reset) plus one
-- SUB-PAGE per frame (UI\FramePage.lua draws the section onto it) via Settings.RegisterCanvasLayoutSubcategory - the
-- EasyFrames tree the owner asked for 2026-11-26 after the single page grew unwieldy. On clients without the Settings
-- API every page is its own InterfaceOptions category, which the legacy panel nests under the root by .parent.
local ADDON_NAME, VFS = ...
local Util, Client, DB, Widgets, MediaPicker = VFS.Util, VFS.Client, VFS.DB, VFS.Widgets, VFS.MediaPicker

local Options = {}
VFS.Options = Options

local page, category          -- root
local pages = {}              -- every page (root + frame sub-pages): Refresh / banner / reload-on-close apply to all
local subcategories = {}      -- [VFS_FrameID] = Settings category (for Options.OpenFrame)

local function RestyleAll() VFS.FrameBase.RestyleAll() end
local function Pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

-- Reload banner (owner 2026-11-26). Toggling "Use Velocity Frame Style" cannot be applied in place: hooks, the
-- reparented portrait and stripped bar masks stay. The frame is left as-is, the user keeps twiddling, and this bar
-- at the bottom of EVERY page does the /reload when they are done; closing Settings with it pending reloads too.
local function AttachReloadBanner(p)
  local banner = CreateFrame("Frame", nil, p)
  banner:SetHeight(44); banner:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0); banner:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  banner:SetFrameLevel(p:GetFrameLevel() + 20)
  local bg = banner:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.6, 0.1, 0.1, 0.85)
  local msg = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); msg:SetPoint("LEFT", 16, 0)
  msg:SetText("A frame's styling was changed. The interface needs to reload for it to take effect.")
  local btn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate"); btn:SetSize(120, 24); btn:SetPoint("RIGHT", -16, 0)
  btn:SetText("Reload UI"); btn:SetScript("OnClick", function() ReloadUI() end)
  banner:Hide()
  p.reloadBanner = banner
  -- OnHide fires when Settings closes AND when switching category; only the former reloads. Checked a frame later
  -- because a category switch hides this page before the next one shows.
  p:HookScript("OnHide", function()
    if not Options.reloadNeeded then return end
    C_Timer.After(0, function()
      if Options.reloadNeeded and not (SettingsPanel and SettingsPanel:IsShown()) and not (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown()) then ReloadUI() end
    end)
  end)
end

local function RegisterPage(p, label, parentCategory)
  pages[#pages + 1] = p
  p:SetScript("OnShow", Options.Refresh)
  AttachReloadBanner(p)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    if parentCategory and Settings.RegisterCanvasLayoutSubcategory then return Settings.RegisterCanvasLayoutSubcategory(parentCategory, p, label) end
    local cat = Settings.RegisterCanvasLayoutCategory(p, label)
    Settings.RegisterAddOnCategory(cat)
    return cat
  elseif InterfaceOptions_AddCategory then
    if parentCategory then p.parent = page.name end
    InterfaceOptions_AddCategory(p)
  end
end

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

  -- Reset
  local reset = Widgets.Section(content, "Reset")
  reset:Add(Widgets.Button(reset, "Reset everything to defaults", function() DB.ResetAll(); RestyleAll(); Widgets.RefreshAll() end, 220), 22)
  reset:Finish(); page:Place(reset)

  category = RegisterPage(page, page.name)

  -- One SUB-PAGE per frame. Focus + Focus Target share ONE page (spec 12) and exist only where the client has a focus unit.
  for _, id in ipairs(DB.FRAME_IDS) do
    if id == "focus" then
      if Client.HasFocusFrame() then
        local sub = Widgets.Page("VelocityFrameStyleOptions_focus", "Focus and Focus Target",
          "Settings for the Focus frame and its Focus Target. One switch styles both. Theme values are inherited from the main page unless overridden here.")
        sub:Place(VFS.FramePage.BuildFocusSection(sub.content))
        subcategories.focus = RegisterPage(sub, "Focus and Focus Target", category)
        subcategories.focustarget = subcategories.focus
      end
    elseif id ~= "focustarget" then
      local label = VFS.FramePage.LABELS[id] or id
      local sub = Widgets.Page("VelocityFrameStyleOptions_" .. id, label,
        "Settings for the " .. label .. " frame. Theme values are inherited from the main Velocity Frame Style page unless overridden here.")
      sub:Place(VFS.FramePage.BuildFrameSection(sub.content, id))
      subcategories[id] = RegisterPage(sub, label, category)
    end
  end
end

function Options.Refresh()
  if not page then return end
  Widgets.RefreshAll()
  for _, p in ipairs(pages) do
    p:FitHeight()
    if p.reloadBanner then p.reloadBanner:SetShown(Options.reloadNeeded == true) end
  end
end

-- Called by FramePage when "Use Velocity Frame Style" changes on any frame.
function Options.RequestReload()
  Options.reloadNeeded = true
  for _, p in ipairs(pages) do if p.reloadBanner then p.reloadBanner:Show() end end
end

function Options.Open()
  if not page then return end
  if Settings and Settings.OpenToCategory and category then Settings.OpenToCategory(category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then InterfaceOptionsFrame_OpenToCategory(page); InterfaceOptionsFrame_OpenToCategory(page) end
end

-- Open straight to one frame's sub-page (e.g. /vfs target)
function Options.OpenFrame(id)
  local cat = subcategories[id]
  if cat and Settings and Settings.OpenToCategory then Settings.OpenToCategory(cat:GetID()) else Options.Open() end
end