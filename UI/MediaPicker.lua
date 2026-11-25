-- Velocity Frame Style: VFS_MediaPicker - a VISUAL media dropdown. The closed button shows the current choice drawn in
-- its own texture (statusbar) or font; the open list draws every row the same way, with a checkmark on the current
-- value. This is the EasyFrames look (AceGUI-3.0-SharedMediaWidgets LSM30_Statusbar / LSM30_Font) rebuilt on plain
-- frames so it needs no AceGUI. Structure follows StatusbarWidget.lua / FontWidget.lua (credit: the AceGUI widget
-- authors). Media comes from Core\Textures.lua (built-ins + LibSharedMedia when present).
--
-- SINGLE SOURCE OF TRUTH: this file is copied unchanged into VelocityPlateStyle. Edit it here only.
-- Dependencies: VFS.Textures.List(kind) -> {key...}, VFS.Textures.Path(kind, key) -> path. Nothing else.
--
-- API:  local picker = MediaPicker.Create(parent, kind, get, set [, width])   kind = "statusbar" | "font"
--       picker:Update()   -- re-read get()
local ADDON_NAME, VFS = ...
local Textures = VFS.Textures

local MediaPicker = {}
VFS.MediaPicker = MediaPicker

local ROW_H, ROWS_VISIBLE, LIST_W = 20, 12, 220
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- One shared popup list (only one picker is open at a time) -------------------------------------------
local popup

local function RenderRow(row, kind, key, path, selected)
  row.key = key
  row.label:SetText(key)
  if kind == "statusbar" then
    row.bar:Show()
    row.bar:SetStatusBarTexture(path)
    row.bar:SetStatusBarColor(0.45, 0.65, 0.95)
    row.label:SetFontObject("GameFontHighlightSmall")
    local f, s = row.label:GetFont(); if f then row.label:SetFont(f, s or 11, "OUTLINE") end
    row.plate:Show()
  else
    row.bar:Hide()
    row.plate:Hide()
    local ok = row.label:SetFont(path, 12, "OUTLINE")
    if not ok then row.label:SetFontObject("GameFontHighlightSmall") end
  end
  row.label:SetTextColor(1, 1, 1)
  row.label:SetShadowColor(0, 0, 0, 1); row.label:SetShadowOffset(1, -1)
  -- the dark plate hugs the text so the texture stays visible either side of it
  row.plate:SetWidth((row.label:GetStringWidth() or 0) + 10)
  row.check:SetShown(selected)
end

local function AcquirePopup()
  if popup then return popup end
  popup = CreateFrame("Frame", "VelocityFrameStyleMediaPickerPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:SetSize(LIST_W + 24, ROW_H * ROWS_VISIBLE + 12)
  if popup.SetBackdrop then
    popup:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  end
  popup:EnableMouse(true)
  popup:Hide()
  tinsert(UISpecialFrames, popup:GetName())   -- Esc closes

  local scroll = CreateFrame("ScrollFrame", popup:GetName() .. "Scroll", popup, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 6)
  popup.scroll = scroll
  popup.rows = {}
  for i = 1, ROWS_VISIBLE do
    local row = CreateFrame("Button", nil, popup)
    row:SetSize(LIST_W - 4, ROW_H)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, -(i - 1) * ROW_H)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", 1, -1); row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    row.bar:SetMinMaxValues(0, 1); row.bar:SetValue(1)
    row.bar:EnableMouse(false)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints(); row.bg:SetTexture(WHITE8); row.bg:SetVertexColor(0, 0, 0, 0.5)
    -- dark plate behind the name so it reads over any texture (bar fill draws above the row's own regions,
    -- so the plate and label live on a child frame one level up)
    row.textFrame = CreateFrame("Frame", nil, row); row.textFrame:SetAllPoints(); row.textFrame:SetFrameLevel(row.bar:GetFrameLevel() + 1)
    row.plate = row.textFrame:CreateTexture(nil, "ARTWORK"); row.plate:SetTexture(WHITE8); row.plate:SetVertexColor(0, 0, 0, 0.65); row.plate:SetPoint("LEFT", 18, 0); row.plate:SetHeight(ROW_H - 4)
    row.label = row.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.label:SetPoint("LEFT", 22, 0); row.label:SetPoint("RIGHT", -4, 0); row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
    row.check = row.textFrame:CreateTexture(nil, "OVERLAY", nil, 3); row.check:SetSize(14, 14); row.check:SetPoint("LEFT", 4, 0); row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.hl = row:CreateTexture(nil, "HIGHLIGHT"); row.hl:SetAllPoints(); row.hl:SetTexture(WHITE8); row.hl:SetVertexColor(1, 1, 1, 0.15)
    row:SetScript("OnClick", function(self) if popup.owner and self.key then popup.owner:Select(self.key) end popup:Hide() end)
    popup.rows[i] = row
  end

  function popup:Refresh()
    local owner = self.owner; if not owner then return end
    local list, kind, current = owner.list, owner.kind, owner.get()
    FauxScrollFrame_Update(self.scroll, #list, ROWS_VISIBLE, ROW_H)
    local offset = FauxScrollFrame_GetOffset(self.scroll)
    for i, row in ipairs(self.rows) do
      local key = list[offset + i]
      if key then RenderRow(row, kind, key, Textures.Path(kind, key), key == current); row:Show() else row:Hide() end
    end
  end
  scroll:SetScript("OnVerticalScroll", function(self, off) FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, function() popup:Refresh() end) end)
  popup:SetScript("OnMouseWheel", function(_, delta) local s = popup.scroll; FauxScrollFrame_OnVerticalScroll(s, math.max(0, s:GetVerticalScroll() - delta * ROW_H), ROW_H, function() popup:Refresh() end) end)
  popup:EnableMouseWheel(true)
  -- click outside closes
  popup:SetScript("OnUpdate", function(self)
    if IsMouseButtonDown("LeftButton") and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
  end)
  popup:SetScript("OnHide", function(self) self.owner = nil end)
  return popup
end

-- The picker button -----------------------------------------------------------------------------------
function MediaPicker.Create(parent, kind, get, set, width)
  width = width or LIST_W
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(width, 24)
  if b.SetBackdrop then
    b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    b:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
  end
  b.kind, b.get, b.set = kind, get, set
  b.preview = CreateFrame("StatusBar", nil, b)
  b.preview:SetPoint("TOPLEFT", 4, -4); b.preview:SetPoint("BOTTOMRIGHT", -24, 4)
  b.preview:SetMinMaxValues(0, 1); b.preview:SetValue(1); b.preview:EnableMouse(false)
  b.preview:SetStatusBarColor(0.45, 0.65, 0.95)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetPoint("TOPLEFT", 4, -4); b.bg:SetPoint("BOTTOMRIGHT", -24, 4); b.bg:SetTexture(WHITE8); b.bg:SetVertexColor(0, 0, 0, 0.6)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.label:SetPoint("LEFT", 8, 0); b.label:SetPoint("RIGHT", -26, 0); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
  b.label:SetDrawLayer("OVERLAY", 2)
  b.arrow = b:CreateTexture(nil, "ARTWORK"); b.arrow:SetSize(20, 20); b.arrow:SetPoint("RIGHT", -2, 0); b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(b.preview); b.hl:SetTexture(WHITE8); b.hl:SetVertexColor(1, 1, 1, 0.1)

  function b:Update()
    local key = self.get()
    local path = Textures.Path(self.kind, key)
    self.label:SetText(key or "")
    if self.kind == "statusbar" then
      self.preview:Show(); self.preview:SetStatusBarTexture(path)
      self.label:SetFontObject("GameFontHighlightSmall")
    else
      self.preview:Hide()
      if not self.label:SetFont(path, 12, "") then self.label:SetFontObject("GameFontHighlightSmall") end
    end
  end
  function b:Select(key) self.set(key); self:Update(); if VFS.Widgets then VFS.Widgets.RefreshAll() end end
  function b:Open()
    local p = AcquirePopup()
    if p:IsShown() and p.owner == self then p:Hide() return end
    self.list = Textures.List(self.kind)
    p.owner = self
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    -- scroll so the current value is visible
    local idx = 1
    for i, k in ipairs(self.list) do if k == self.get() then idx = i break end end
    FauxScrollFrame_SetOffset(p.scroll, math.max(0, math.min(idx - 1, #self.list - ROWS_VISIBLE)))
    p.scroll:SetVerticalScroll(FauxScrollFrame_GetOffset(p.scroll) * ROW_H)
    p:Show()
    p:Refresh()
  end
  b:SetScript("OnClick", b.Open)
  if VFS.Widgets then VFS.Widgets.Track(b) end
  b:Update()
  return b
end