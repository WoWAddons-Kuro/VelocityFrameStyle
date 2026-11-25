-- Velocity Frame Style: shared option-page widgets in the GotJunk / PlateStyle style. Every widget returns a frame
-- with :Update() that re-reads its value; Options.Refresh calls Update on everything in VFS_WidgetRegistry.
-- Builders take get()/set(v) closures so nested keys (frames[id].override.x) stay out of the widget code.
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local Widgets = {}
VFS.Widgets = Widgets

Widgets.BOX_W, Widgets.PAD = 580, 10
local BOX_W, PAD = Widgets.BOX_W, Widgets.PAD

local registry = {}   -- VFS_WidgetRegistry: every widget with an Update()
function Widgets.Track(w) registry[#registry + 1] = w; return w end
function Widgets.RefreshAll() for _, w in ipairs(registry) do if w.Update then w:Update() end end end

-- Checkbox -----------------------------------------------------------------------------------
function Widgets.Check(parent, label, tip, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb.Text:SetText(label)
  cb.tooltipText = tip
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Widgets.RefreshAll() end)
  cb.Update = function(self) self:SetChecked(get() and true or false) end
  return Widgets.Track(cb)
end

-- Slider with its label above-left -------------------------------------------------------------
local sliderN = 0
function Widgets.Slider(parent, label, minV, maxV, step, get, set, fmt)
  sliderN = sliderN + 1
  local name = "VelocityFrameStyleSlider" .. sliderN
  fmt = fmt or function(v) return tostring(v) end
  local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 44)
  local l = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); l:SetPoint("TOPLEFT", 4, 0)
  local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -6); s:SetWidth(220)
  s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
  _G[name .. "Low"]:SetText(fmt(minV)); _G[name .. "High"]:SetText(fmt(maxV)); _G[name .. "Text"]:SetText("")
  local updating = false
  s:SetScript("OnValueChanged", function(_, v)
    if updating then return end
    v = math.floor(v / step + 0.5) * step
    set(v); l:SetText(label .. ": " .. fmt(v))
  end)
  holder.Update = function() updating = true; s:SetValue(get()); updating = false; l:SetText(label .. ": " .. fmt(get())) end
  return Widgets.Track(holder)
end

-- Horizontal radio row: choices = { {value, label}, ... } ------------------------------------------
function Widgets.Radios(parent, label, choices, get, set, labelWidth)
  local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 20)
  local l = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); l:SetPoint("LEFT", 4, 0); l:SetText(label)
  local rs, x = {}, labelWidth or 150
  for _, c in ipairs(choices) do
    local r = CreateFrame("CheckButton", nil, holder, "UIRadioButtonTemplate"); r:SetSize(16, 16)
    r:SetPoint("LEFT", x, 0)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r, "RIGHT", 4, 0); r.text:SetText(c[2])
    r.value = c[1]
    r:SetScript("OnClick", function() set(c[1]); Widgets.RefreshAll() end)
    rs[#rs + 1] = r
    x = x + 20 + r.text:GetStringWidth() + 14
  end
  holder.Update = function() local v = get(); for _, r in ipairs(rs) do r:SetChecked(r.value == v) end end
  return Widgets.Track(holder)
end

-- Compact dropdown over a value list: choices = { {value, label}, ... } -----------------------------
local ddN = 0
function Widgets.Dropdown(parent, choices, get, set, width)
  ddN = ddN + 1
  local dd = CreateFrame("Frame", "VelocityFrameStyleDropdown" .. ddN, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width or 90)
  UIDropDownMenu_Initialize(dd, function(_, level)
    for _, c in ipairs(choices) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.value, info.checked = c[2], c[1], (c[1] == get())
      info.func = function() set(c[1]); Widgets.RefreshAll() end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  dd.Update = function()
    local v = get()
    for _, c in ipairs(choices) do if c[1] == v then UIDropDownMenu_SetText(dd, c[2]) return end end
    UIDropDownMenu_SetText(dd, tostring(v))
  end
  return Widgets.Track(dd)
end

-- Colour swatch + reset ------------------------------------------------------------------------------
function Widgets.ColorSwatch(parent, label, get, set, default)
  local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 22)
  local l = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); l:SetPoint("LEFT", 4, 0); l:SetText(label)
  local b = CreateFrame("Button", nil, holder); b:SetSize(18, 18); b:SetPoint("LEFT", 150, 0)
  b.sw = b:CreateTexture(nil, "ARTWORK"); b.sw:SetAllPoints(); b.sw:SetColorTexture(1, 1, 1)
  b.border = b:CreateTexture(nil, "BACKGROUND"); b.border:SetPoint("TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", 1, -1); b.border:SetColorTexture(0.6, 0.6, 0.6)
  b:SetScript("OnClick", function()
    local r, g, bl = unpack(get())
    local function Changed() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); set({ nr, ng, nb }); Widgets.RefreshAll() end
    local function Cancel(prev) if prev then set({ prev.r, prev.g, prev.b }); Widgets.RefreshAll() end end
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = bl, swatchFunc = Changed, cancelFunc = Cancel })
    else
      ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Changed, Cancel
      ColorPickerFrame.previousValues = { r = r, g = g, b = bl }
      ColorPickerFrame:SetColorRGB(r, g, bl); ColorPickerFrame:Show()
    end
  end)
  if default then
    local reset = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate"); reset:SetSize(60, 20); reset:SetPoint("LEFT", b, "RIGHT", 10, 0); reset:SetText("Reset")
    reset:SetScript("OnClick", function() set(Util.DeepCopy(default)); Widgets.RefreshAll() end)
  end
  holder.Update = function() b.sw:SetColorTexture(unpack(get())) end
  return Widgets.Track(holder)
end

function Widgets.Button(parent, label, onClick, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetSize(width or 160, 22); b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

function Widgets.Text(parent, text, font)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
  fs:SetWidth(BOX_W - 2 * PAD); fs:SetJustifyH("LEFT"); fs:SetText(text)
  return fs
end

-- Bordered section with a running vertical layout ------------------------------------------------
function Widgets.Section(content, header)
  local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
  box:SetWidth(BOX_W)
  if box.SetBackdrop then
    box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0, 0, 0, 0.25); box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
  end
  local h = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); h:SetPoint("TOPLEFT", PAD, -PAD); h:SetText(header)
  box.header = h
  box.inner_last, box.inner_h = h, PAD + 14
  function box:Add(w, height, dy, dx)
    dy = dy or -6
    w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
    self.inner_last, self.inner_h = w, self.inner_h - dy + height
    return w
  end
  function box:Finish() self:SetHeight(self.inner_h + PAD) end
  return box
end

-- Page: scroll frame + content; Place() stacks sections ------------------------------------------
function Widgets.Page(name, title, subtitle)
  local page = CreateFrame("Frame", name)
  page.name = title
  local scroll = CreateFrame("ScrollFrame", name .. "Scroll", page, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4); scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(620, 2000)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(math.max(620, w)) end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)
  local t = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); t:SetPoint("TOPLEFT", 16, -16); t:SetText(title)
  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT"); sub:SetText(subtitle or "")
  page.content, page.scroll, page.last, page.lastDy = content, scroll, sub, -14
  function page:Place(w, dy, dx)
    w:SetPoint("TOPLEFT", self.last, "BOTTOMLEFT", dx or 0, dy or self.lastDy)
    self.last, self.lastDy = w, -14
    return w
  end
  function page:FitHeight()
    local top, bottom = self.content:GetTop(), self.last:GetBottom()
    if top and bottom then self.content:SetHeight(top - bottom + 30) end
  end
  return page
end