-- Velocity Frame Style: the VFS_FrameModule contract shared by every restyled Blizzard frame.
--
-- One VFS_FrameState per frame (player/target/pet/pettarget):
--   { id, unit, button, bars = { health = VFS_Bar, power = VFS_Bar }, host = VFS_TextHost, slots = VFS_TextSlots, chrome = VFS_Chrome }
-- VFS_Bar = { stock = StatusBar, backdrop = Frame, movable = bool }
--
-- Strategy (spec §Chrome: GEOMETRIC): Blizzard's STOCK bars are styled in place on every client - texture, colour, and
-- (where Client.MovableBars allows) size/anchor via Geometry. There are no overlay bars. Blizzard's frame art is
-- alpha-zeroed (Client.ChromeRegions) except the keep-list (Client.KeepRegions: rest zzz, combat swords, skull);
-- Frames\Chrome.lua draws our near-black disc + rounded plate under the bars. Stock texts are alpha-zeroed (R2); our
-- text lives on a TextLayout host above everything. Only bar VALUES are Blizzard's (R5).
local ADDON_NAME, VFS = ...
local Util, Client, DB, TextLayout = VFS.Util, VFS.Client, VFS.DB, VFS.TextLayout

local FrameBase = {}
VFS.FrameBase = FrameBase
VFS.Frames = {}     -- VFS_FrameID -> VFS_FrameState

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local ROUNDED_MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\rounded_mask.tga"

-- Backdrop: black texture on a holder one level under the bar, inset 1 px (anti-aliased bar corners) --------
function FrameBase.AcquireBackdrop(bar)
  if bar.vfsBackdrop then return bar.vfsBackdrop end
  local h = CreateFrame("Frame", nil, bar:GetParent())
  h:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  h:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
  h.tex = h:CreateTexture(nil, "BACKGROUND", nil, -8)
  h.tex:SetAllPoints()
  h.tex:SetTexture(WHITE8)
  local function Sync() h:SetFrameStrata(bar:GetFrameStrata()); h:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1)) end
  Sync()
  hooksecurefunc(bar, "SetFrameLevel", Sync)
  hooksecurefunc(bar, "SetFrameStrata", Sync)
  bar.vfsBackdrop = h
  return h
end

-- Colour policy (owner): health GREEN or class colour (players, when classColorHealth); power = PowerBarColor[token].
local function ApplyHealthColor(bar, unit)
  local cc
  if DB.Global().classColorHealth and UnitIsPlayer(unit) then
    local _, class = UnitClass(unit)
    class = Util.Plain(class)
    cc = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
  end
  if cc then bar:SetStatusBarColor(cc.r, cc.g, cc.b) else bar:SetStatusBarColor(0, 1, 0) end
end

local function ApplyPowerColor(bar, unit)
  local _, token = UnitPowerType(unit)
  token = Util.Plain(token)
  local c = token and PowerBarColor and PowerBarColor[token]
  if c then bar:SetStatusBarColor(c.r, c.g, c.b) else bar:SetStatusBarColor(0, 0, 1) end
end
FrameBase.ApplyHealthColor, FrameBase.ApplyPowerColor = ApplyHealthColor, ApplyPowerColor

-- Blizzard recolours its bar on every update; keep ours after it. Reentrancy-guarded.
local function HookColor(st, kind, bar)
  if bar.vfsColorHooked then return end
  bar.vfsColorHooked = true
  hooksecurefunc(bar, "SetStatusBarColor", function(b)
    if b.vfsRecolouring or not DB.Frame(st.id).enabled then return end
    b.vfsRecolouring = true
    if kind == "health" then ApplyHealthColor(b, st.unit) else ApplyPowerColor(b, st.unit) end
    b.vfsRecolouring = nil
  end)
end

-- Blizzard's bar masks are shaped for Blizzard's art window (a 32x32 rounded mask stretched to 113x24 went elliptical,
-- owner 2026-11-25). With the geometric chrome the BARS ARE PLAIN RECTANGLES inside the rounded plate (the EasyFrames
-- look); we only strip Blizzard's own masks off the fill.
local function ApplyFillMask(bar)
  local tex = bar:GetStatusBarTexture()
  if not tex or bar.vfsUnmaskedTex == tex then return end
  if tex.GetNumMaskTextures then
    for i = tex:GetNumMaskTextures(), 1, -1 do local m = tex:GetMaskTexture(i); if m then pcall(tex.RemoveMaskTexture, tex, m) end end
  end
  bar.vfsUnmaskedTex = tex
end

-- Create / fetch the state for a frame -------------------------------------------------------------------
function FrameBase.Acquire(id)
  local st = VFS.Frames[id]
  if st then return st end
  local button = Client.UnitButton(id)
  if not button then return nil end
  st = { id = id, unit = Client.Unit(id), button = button, bars = {}, slots = {} }
  local movable = Client.MovableBars(id)
  for _, kind in ipairs({ "health", "power" }) do
    local stock = kind == "health" and Client.HealthBar(id) or Client.PowerBar(id)
    if stock then
      st.bars[kind] = { stock = stock, backdrop = FrameBase.AcquireBackdrop(stock), movable = movable[stock] == true }
      HookColor(st, kind, stock)
    end
  end
  -- Text host above bars and chrome
  local top = button:GetFrameLevel()
  for _, bar in pairs(st.bars) do top = math.max(top, bar.stock:GetFrameLevel()) end
  st.host = TextLayout.CreateHost(button, 1)
  st.host.top:SetFrameStrata(button:GetFrameStrata())
  st.host.top:SetFrameLevel(top + 3)
  -- Secret-value clients: health/power elements adopt Blizzard's secure value strings
  if Client.HasSecretValues() then
    TextLayout.AdoptStock(st.host, "health", Client.StockValueText(id, "health"))
    TextLayout.AdoptStock(st.host, "power",  Client.StockValueText(id, "power"))
  end
  VFS.Frames[id] = st
  if VFS.Chrome then VFS.Chrome.Create(st) end
  return st
end

-- Convenience: the bar we draw on (always the stock bar now)
function FrameBase.Bar(st, kind) local b = st.bars[kind]; return b and b.stock end

-- The 'nameplate' slot: a row region above the health bar for name + level
function FrameBase.NameRowAbove(st, bar, rowHeight, gap)
  if st.nameRow then return st.nameRow end
  local row = CreateFrame("Frame", nil, st.host.top)
  row:SetHeight(rowHeight or 12)
  row:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, gap or 2)
  row:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, gap or 2)
  st.nameRow = row
  return row
end

-- Portrait style: default / class_old / class_new (players only) ------------------------------------------
local TEX = "Interface\\TargetingFrame\\"
function FrameBase.ApplyPortrait(st)
  local portrait = Client.Portrait(st.id)
  if not portrait or not UnitExists(st.unit) then return end
  local style = DB.Frame(st.id).enabled and DB.Effective(st.id, "portraitStyle") or "default"
  local _, class = UnitClass(st.unit)
  class = Util.Plain(class)
  if style ~= "default" and UnitIsPlayer(st.unit) and class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
    portrait:SetTexture(style == "class_old" and (TEX .. "UI-Classes-Circles") or "Interface\\WorldStateFrame\\Icons-Classes")
    portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    st.portraitStyled = true
  elseif st.portraitStyled then
    portrait:SetTexCoord(0, 1, 0, 1)
    SetPortraitTexture(portrait, st.unit)
    st.portraitStyled = nil
  end
end

-- Appearance (cosmetic; legal in combat) ----------------------------------------------------------------
function FrameBase.ApplyAppearance(st)
  local id = st.id
  local enabled = DB.Frame(id).enabled
  local texPath = Util.StatusBarPath(DB.Effective(id, "barTexture"))
  local backing = DB.Effective(id, "backingAlpha")
  for kind, bar in pairs(st.bars) do
    if enabled then
      bar.stock:SetStatusBarTexture(texPath)
      local t = bar.stock:GetStatusBarTexture(); if t then t:SetAlpha(1); t:SetHorizTile(false); t:SetVertTile(false) end
      ApplyFillMask(bar.stock)
      if kind == "health" then ApplyHealthColor(bar.stock, st.unit) else ApplyPowerColor(bar.stock, st.unit) end
      bar.backdrop.tex:SetColorTexture(0, 0, 0, backing)
      bar.backdrop:Show()
    else
      bar.backdrop:Hide()
    end
  end
  -- Blizzard chrome: alpha 0 while enabled; keep-list never touched
  local a = enabled and 0 or 1
  for _, r in ipairs(Client.ChromeRegions(id)) do
    if r.GetObjectType and r:GetObjectType() == "StatusBar" then
      for i = 1, select("#", r:GetRegions()) do local t = select(i, r:GetRegions()); if t.SetAlpha then t:SetAlpha(a) end end
    elseif r.SetAlpha then r:SetAlpha(a) end
  end
  FrameBase.ApplyPortrait(st)
  -- Stock texts: alpha 0 while we draw our own (adopted value strings are ours now and are skipped)
  local name = Client.NameText(id); if name then name:SetAlpha(a) end
  for _, t in ipairs(Client.HealthTexts(id)) do if not t.vfsAdopted then t:SetAlpha(a) end end
  for _, t in ipairs(Client.PowerTexts(id)) do if not t.vfsAdopted then t:SetAlpha(a) end end
  for _, r in ipairs(Client.StockLevelRegions(id)) do r:SetAlpha(a) end
  -- Fonts for every element
  local font, style = DB.Effective(id, "font"), DB.Effective(id, "fontStyle")
  local elements = DB.Elements(id)
  for _, e in ipairs(elements) do TextLayout.ApplyFont(TextLayout.AcquireText(st.host, e.id), font, e.size, style) end
  TextLayout.PruneTexts(st.host, elements)
  if not enabled then for _, t in pairs(st.host.text) do if not t.vfsAdopted then t:Hide() end end end
  if VFS.Chrome then VFS.Chrome.SetShown(st, enabled); VFS.Chrome.Layout(st); VFS.Chrome.ApplyColors(st); VFS.Chrome.UpdateCombat(st) end
end

-- Values (texts) -----------------------------------------------------------------------------------------
function FrameBase.ApplyTexts(st, filter)
  if not DB.Frame(st.id).enabled then return end
  if not UnitExists(st.unit) then for _, t in pairs(st.host.text) do if not t.vfsAdopted then t:Hide() end end return end
  TextLayout.ApplyTexts(st.host, DB.Elements(st.id), st.unit, Client.NameText(st.id), filter)
  TextLayout.Layout(st.host, DB.Elements(st.id), st.slots)
end

local function UsesHealth(e) return VFS.Format.UsesHealth(e.format) end
local function UsesPower(e) return VFS.Format.UsesPower(e.format) end
function FrameBase.ApplyHealthTexts(st) FrameBase.ApplyTexts(st, UsesHealth) end
function FrameBase.ApplyPowerTexts(st) FrameBase.ApplyTexts(st, UsesPower) end

-- Hooks common to every frame -----------------------------------------------------------------------------
function FrameBase.HookCommon(st)
  if st.hooked then return end
  st.hooked = true
  Client.HookBarUpdate(st.id, "health", function() FrameBase.ApplyHealthTexts(st) end)
  Client.HookBarUpdate(st.id, "power", function() FrameBase.ApplyPowerTexts(st) end)
  st.button:HookScript("OnShow", function() FrameBase.ApplyAppearance(st); FrameBase.ApplyTexts(st) end)
  if not FrameBase.portraitHooked and UnitFramePortrait_Update then
    FrameBase.portraitHooked = true
    hooksecurefunc("UnitFramePortrait_Update", function(frame)
      for _, s in pairs(VFS.Frames) do if s.button == frame then FrameBase.ApplyPortrait(s) end end
    end)
  end
end

-- Combat state changed for a unit (our own glow replaces Blizzard's flash)
function FrameBase.OnCombatChanged(st)
  if st and VFS.Chrome then VFS.Chrome.UpdateCombat(st) end
end

function FrameBase.Restyle(id)
  local st = VFS.Frames[id]
  if not st then return end
  FrameBase.ApplyAppearance(st)
  FrameBase.ApplyTexts(st)
end

function FrameBase.RestyleAll()
  for id in pairs(VFS.Frames) do FrameBase.Restyle(id) end
end