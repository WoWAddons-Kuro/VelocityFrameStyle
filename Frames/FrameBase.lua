-- Velocity Frame Style: the VFS_FrameModule contract shared by every restyled Blizzard frame.
--
-- One VFS_FrameState per frame (player/target/pet):
--   { id, unit, button, bars = { health = VFS_Bar, power = VFS_Bar }, host = VFS_TextHost, slots = VFS_TextSlots }
-- VFS_Bar = { stock = StatusBar, draw = StatusBar (the one we texture: stock on Era, overlay on Forever), backdrop = Frame }
--
-- Strategy (spec §Frame strategies): where Client.MovableBars lists the stock bar (Era) we texture/resize it in place
-- (Geometry). Elsewhere (Forever: masked, restricted) we create a VFS_OverlayBar on top sized to the stock bar, drive
-- its value from the STOCK bar's GetValue/GetMinMaxValues (never UnitHealth - R5), and alpha-zero the stock fill.
-- All stock texts we replace are alpha-zeroed (R2); our text lives on a TextLayout host one level above the bars.
local ADDON_NAME, VFS = ...
local Util, Client, DB, TextLayout = VFS.Util, VFS.Client, VFS.DB, VFS.TextLayout

local FrameBase = {}
VFS.FrameBase = FrameBase
VFS.Frames = {}     -- VFS_FrameID -> VFS_FrameState

local WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- Backdrop: black texture on a holder one level under the drawn bar ------------------------------
function FrameBase.AcquireBackdrop(bar)
  if bar.vfsBackdrop then return bar.vfsBackdrop end
  local h = CreateFrame("Frame", nil, bar:GetParent())
  h:SetAllPoints(bar)
  h.tex = h:CreateTexture(nil, "BACKGROUND", nil, -8)
  h.tex:SetAllPoints()
  h.tex:SetTexture(WHITE8)
  local function Sync() h:SetFrameStrata(bar:GetFrameStrata()); h:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1)) end
  Sync()
  hooksecurefunc(bar, "SetFrameLevel", Sync)
  bar.vfsBackdrop = h
  return h
end

-- Overlay bar: our own StatusBar over the stock one, mirroring its value -----------------------------
-- Colour policy (owner, 2026-11-24): health is GREEN (or class colour when classColorHealth and the unit is a player);
-- power is PowerBarColor[token] (blue mana, red rage, yellow energy...). We own the colour; never copy Blizzard's.
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

local function AcquireOverlay(state, kind, stock)
  if stock.vfsOverlay then return stock.vfsOverlay end
  -- The slot is the masked container on Forever (Camelot sizes the bar taller than its container and clips it);
  -- our overlay fills the CONTAINER rect so it sits exactly in the art's bar window.
  local slot = Client.BarSlot(state.id, kind) or stock
  local ov = CreateFrame("StatusBar", nil, slot:GetParent())
  ov:SetAllPoints(slot)
  ov:SetFrameStrata(stock:GetFrameStrata())
  ov:SetFrameLevel(stock:GetFrameLevel() + 1)
  ov:EnableMouse(false)
  ov:SetMinMaxValues(0, 1)
  ov:SetValue(1)
  stock.vfsOverlay = ov
  -- Mirror value/range/visibility from the stock bar. Reads are widget queries, not unit values (R5). Colour is ours.
  local function Mirror()
    local lo, hi = stock:GetMinMaxValues()
    ov:SetMinMaxValues(lo or 0, hi or 1)
    ov:SetValue(stock:GetValue() or 0)
    ov:SetShown(stock:IsShown())
    if kind == "health" then ApplyHealthColor(ov, state.unit) else ApplyPowerColor(ov, state.unit) end
  end
  Client.HookBarUpdate(state.id, kind, Mirror)
  stock:HookScript("OnShow", Mirror)
  stock:HookScript("OnHide", Mirror)
  hooksecurefunc(stock, "SetValue", Mirror)
  ov.vfsMirror = Mirror
  Mirror()
  return ov
end

-- Apply the stock mask to our overlay's fill so it is clipped to the art's rounded window like Blizzard's own.
local function ApplyOverlayMask(state, kind, ov)
  local mask = Client.BarMask(state.id, kind)
  local tex = ov:GetStatusBarTexture()
  if not tex or ov.vfsMaskedTex == tex then return end
  if ov.vfsMaskedTex and ov.vfsMask then pcall(ov.vfsMaskedTex.RemoveMaskTexture, ov.vfsMaskedTex, ov.vfsMask) end
  if mask and tex.AddMaskTexture then
    local ok = pcall(tex.AddMaskTexture, tex, mask)
    if ok then ov.vfsMaskedTex, ov.vfsMask = tex, mask end
  end
end

-- Hide the stock fill so only the overlay shows (alpha, never Hide - R2; re-asserted on texture changes)
local function SuppressStockFill(stock)
  local tex = stock:GetStatusBarTexture()
  if tex then tex:SetAlpha(0) end
  if not stock.vfsFillHooked then
    stock.vfsFillHooked = true
    hooksecurefunc(stock, "SetStatusBarTexture", function(b) local t = b:GetStatusBarTexture(); if t and b.vfsSuppressed then t:SetAlpha(0) end end)
  end
  stock.vfsSuppressed = true
end

local function RestoreStockFill(stock)
  stock.vfsSuppressed = nil
  local tex = stock:GetStatusBarTexture()
  if tex then tex:SetAlpha(1) end
end

-- Create / fetch the state for a frame ------------------------------------------------------------------
function FrameBase.Acquire(id)
  local st = VFS.Frames[id]
  if st then return st end
  local button = Client.UnitButton(id)
  if not button then return nil end
  st = { id = id, unit = Client.Unit(id), button = button, bars = {}, slots = {} }
  for _, kind in ipairs({ "health", "power" }) do
    local stock = kind == "health" and Client.HealthBar(id) or Client.PowerBar(id)
    if stock then
      local movable = Client.MovableBars(id)[stock] == true
      local draw = movable and stock or AcquireOverlay(st, kind, stock)
      st.bars[kind] = { stock = stock, draw = draw, backdrop = FrameBase.AcquireBackdrop(draw), inPlace = movable }
      if not movable then SuppressStockFill(stock) end
    end
  end
  -- Text host: must sit ABOVE whatever draws the bars. On Forever the bars live on nested content frames several
  -- levels above the button, so base the host level on the highest drawn bar, not on the button.
  local top = button:GetFrameLevel()
  for _, bar in pairs(st.bars) do top = math.max(top, bar.draw:GetFrameLevel()) end
  st.host = TextLayout.CreateHost(button, 1)
  st.host.top:SetFrameStrata(button:GetFrameStrata())
  st.host.top:SetFrameLevel(top + 3)
  st.hostLevel = top + 3
  -- Secret-value clients: the health/power ELEMENTS adopt Blizzard's own centre value strings (their content is
  -- secret; we only place/font/colour them). Other clients compute [hp]/[power] from Format tokens.
  if Client.HasSecretValues() then
    TextLayout.AdoptStock(st.host, "health", Client.StockValueText(id, "health"))
    TextLayout.AdoptStock(st.host, "power",  Client.StockValueText(id, "power"))
  end
  VFS.Frames[id] = st
  return st
end

-- The 'nameplate' slot on frames with no reaction strip: an invisible row region the height of a text line,
-- sitting ROW px above `bar` and spanning its width. TextLayout lays the name/level row inside it.
function FrameBase.NameRowAbove(st, bar, rowHeight, gap)
  if st.nameRow then return st.nameRow end
  local row = CreateFrame("Frame", nil, st.host.top)
  row:SetHeight(rowHeight or 12)
  row:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, gap or 2)
  row:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, gap or 2)
  st.nameRow = row
  return row
end

-- Portrait style: default (unit model), class_old (UI-Classes-Circles), class_new (Icons-Classes). Class styles apply
-- only when the unit is a player; otherwise the stock portrait stays. Blizzard redraws portraits in
-- UnitFramePortrait_Update, so this is also called from that hook (see HookCommon).
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

-- Appearance (cosmetic; legal in combat) -------------------------------------------------------------------
function FrameBase.ApplyAppearance(st)
  local id = st.id
  local fs = DB.Frame(id)
  local enabled = fs.enabled
  local texPath = Util.StatusBarPath(DB.Effective(id, "barTexture"))
  local backing = DB.Effective(id, "backingAlpha")
  local darken = DB.Effective(id, "borderDarken")
  for kind, bar in pairs(st.bars) do
    if enabled then
      bar.draw:SetStatusBarTexture(texPath)
      local t = bar.draw:GetStatusBarTexture(); if t then t:SetAlpha(1); t:SetHorizTile(false); t:SetVertTile(false) end
      if not bar.inPlace then ApplyOverlayMask(st, kind, bar.draw) end
      bar.backdrop.tex:SetColorTexture(0, 0, 0, backing)
      bar.backdrop:Show()
      if not bar.inPlace then SuppressStockFill(bar.stock); bar.draw:Show(); if bar.draw.vfsMirror then bar.draw.vfsMirror() end end
    else
      bar.backdrop:Hide()
      if not bar.inPlace then RestoreStockFill(bar.stock); bar.draw:Hide() end
    end
  end
  local art = Client.FrameArt(id)
  if art then local d = enabled and darken or 1; art:SetVertexColor(d, d, d) end
  FrameBase.ApplyPortrait(st)
  -- Stock texts: alpha 0 while we draw our own
  local a = enabled and 0 or 1
  local name = Client.NameText(id); if name then name:SetAlpha(a) end
  for _, t in ipairs(Client.HealthTexts(id)) do t:SetAlpha(a) end
  for _, t in ipairs(Client.PowerTexts(id)) do t:SetAlpha(a) end
  for _, r in ipairs(Client.StockLevelRegions(id)) do r:SetAlpha(a) end
  -- Fonts for every element
  local font, style = DB.Effective(id, "font"), DB.Effective(id, "fontStyle")
  local elements = DB.Elements(id)
  for _, e in ipairs(elements) do TextLayout.ApplyFont(TextLayout.AcquireText(st.host, e.id), font, e.size, style) end
  TextLayout.PruneTexts(st.host, elements)
  if not enabled then for _, t in pairs(st.host.text) do t:Hide() end end
end

-- Values (texts) ------------------------------------------------------------------------------------------
function FrameBase.ApplyTexts(st, filter)
  if not DB.Frame(st.id).enabled then return end
  if not UnitExists(st.unit) then for _, t in pairs(st.host.text) do t:Hide() end return end
  TextLayout.ApplyTexts(st.host, DB.Elements(st.id), st.unit, Client.NameText(st.id), filter)
  TextLayout.Layout(st.host, DB.Elements(st.id), st.slots)
end

local function UsesHealth(e) return VFS.Format.UsesHealth(e.format) end
local function UsesPower(e) return VFS.Format.UsesPower(e.format) end
function FrameBase.ApplyHealthTexts(st) FrameBase.ApplyTexts(st, UsesHealth) end
function FrameBase.ApplyPowerTexts(st) FrameBase.ApplyTexts(st, UsesPower) end

-- Hooks common to every frame: refresh texts when Blizzard updates the bars ---------------------------------
function FrameBase.HookCommon(st)
  if st.hooked then return end
  st.hooked = true
  Client.HookBarUpdate(st.id, "health", function() FrameBase.ApplyHealthTexts(st) end)
  Client.HookBarUpdate(st.id, "power", function() FrameBase.ApplyPowerTexts(st) end)
  st.button:HookScript("OnShow", function() FrameBase.ApplyAppearance(st); FrameBase.ApplyTexts(st) end)
  -- Blizzard redraws the portrait from the unit model here; re-apply the class style after it (once, globally)
  if not FrameBase.portraitHooked and UnitFramePortrait_Update then
    FrameBase.portraitHooked = true
    hooksecurefunc("UnitFramePortrait_Update", function(frame)
      for _, s in pairs(VFS.Frames) do if s.button == frame then FrameBase.ApplyPortrait(s) end end
    end)
  end
end

-- Full refresh (settings change) for one frame or all
function FrameBase.Restyle(id)
  local st = VFS.Frames[id]
  if not st then return end
  FrameBase.ApplyAppearance(st)
  FrameBase.ApplyTexts(st)
end

function FrameBase.RestyleAll()
  for id in pairs(VFS.Frames) do FrameBase.Restyle(id) end
end