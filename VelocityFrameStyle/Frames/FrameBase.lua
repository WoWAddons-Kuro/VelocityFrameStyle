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

-- Border renderer contract: reference region = INNER surface; thickness grows OUTWARD.
-- Both copies use these exact anchors. Replacing this renderer with a rounded atlas
-- later must not change any bar sizing, placement, background or value handling.
FrameBase.BAR_BORDER_WIDTH = 6
function FrameBase.CreateSurfaceBorder(parent, surface, thickness)
  local border = CreateFrame("Frame", nil, parent)
  border:EnableMouse(false)
  border:SetPoint("TOPLEFT", surface, "TOPLEFT", -thickness, thickness)
  border:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", thickness, -thickness)
  border.edges = {}
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    local edge = border:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(0, 0, 0, 1)
    border.edges[side] = edge
  end
  local e = border.edges
  e.top:SetPoint("TOPLEFT", border, "TOPLEFT")
  e.top:SetPoint("BOTTOMRIGHT", surface, "TOPRIGHT", thickness, 0)
  e.bottom:SetPoint("TOPLEFT", surface, "BOTTOMLEFT", -thickness, 0)
  e.bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT")
  e.left:SetPoint("TOPLEFT", surface, "TOPLEFT", -thickness, 0)
  e.left:SetPoint("BOTTOMRIGHT", surface, "BOTTOMLEFT")
  e.right:SetPoint("TOPLEFT", surface, "TOPRIGHT")
  e.right:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", thickness, 0)
  function border:SetBorderColor(r, g, b, a)
    for _, edge in pairs(self.edges) do edge:SetColorTexture(r, g, b, a) end
  end
  return border
end

-- Four layers, all anchored to the SAME inner rect (the stock StatusBar):
-- opaque border below / translucent black surface / stock fill / identical border above.
-- Flat borders have an empty centre; the later rounded renderer adds corner cut-outs.
function FrameBase.AcquireBackdrop(bar)
  if bar.vfsBackdrop then return bar.vfsBackdrop end
  local h = CreateFrame("Frame", nil, bar:GetParent())
  h:EnableMouse(false)
  h:SetAllPoints(bar)
  h.border = FrameBase.CreateSurfaceBorder(h, bar, FrameBase.BAR_BORDER_WIDTH)
  h.tex = h:CreateTexture(nil, "BACKGROUND", nil, -8)
  h.tex:SetAllPoints(bar)
  h.tex:SetColorTexture(0, 0, 0, 0.3)
  local ring = FrameBase.CreateSurfaceBorder(bar:GetParent(), bar, FrameBase.BAR_BORDER_WIDTH)
  h.ring = ring
  local function Sync()
    h:SetFrameStrata(bar:GetFrameStrata()); h:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    h.border:SetFrameLevel(h:GetFrameLevel())
    ring:SetFrameStrata(bar:GetFrameStrata()); ring:SetFrameLevel(bar:GetFrameLevel() + (bar.vfsBorderLevelOffset or 1))
  end
  Sync()
  hooksecurefunc(bar, "SetFrameLevel", Sync)
  hooksecurefunc(bar, "SetFrameStrata", Sync)
  bar.vfsBackdrop = h
  return h
end

-- Background alpha is independent of the two always-opaque black border copies.
function FrameBase.ColorBackdrop(bar, backingAlpha)
  local h = bar.vfsBackdrop; if not h then return end
  h.tex:SetColorTexture(0, 0, 0, backingAlpha)
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
  -- Own value strings on both clients. The client formatter handles secret values
  -- through Blizzard's APIs, independently of the global status-text setting.
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
  local clearance = FrameBase.BAR_BORDER_WIDTH + (gap or 2)
  row:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, clearance)
  row:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, clearance)
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
-- Target follows its native controller; our pet-target uses the client's explicit
-- resource-presence query. Never run native Lua comparisons on secret capacity.
function FrameBase.RefreshPowerVisibility(st)
  if st.id ~= "target" and st.id ~= "pettarget" then return false end
  local power = st.bars.power
  if not power then return false end
  local absent = false
  if DB.Frame(st.id).enabled then
    if st.id == "pettarget" then
      absent = not VFS.PetTarget.IsSample() and Client.HasPowerResource(st.unit) == false
    else
      -- IsShown is local to the bar: hiding the whole target frame is not
      -- evidence of no resource. Do not use IsVisible here.
      absent = not power.stock:IsShown()
    end
  end
  local changed = st.powerAbsent ~= absent
  st.powerAbsent = absent
  power.stock:SetAlpha(absent and 0 or 1)
  power.backdrop:SetAlpha(absent and 0 or 1)
  power.backdrop.ring:SetAlpha(absent and 0 or 1)
  if absent then
    st.slots.power = nil
    st.slots.below = st.bars.health and st.bars.health.stock
  else
    st.slots.power = power.stock
    st.slots.below = power.stock
  end
  if changed and VFS.Chrome then VFS.Chrome.Layout(st) end
  return changed
end

-- Prediction fills retain Blizzard's value-controlled FillMask. Only the extra
-- fixed art-window mask is replaced with a rectangle bound to our resized bar.
local function HasMask(texture, mask)
  if not mask then return false end
  for i = 1, texture:GetNumMaskTextures() do
    if texture:GetMaskTexture(i) == mask then return true end
  end
  return false
end

local function StylePrediction(st, entry)
  local bar, segment = entry.bar, entry.segment
  local fill = segment and segment.Fill
  if not bar or not fill or not segment.FillMask or not fill.GetNumMaskTextures then return false end
  local enabled = DB.Frame(st.id).enabled
  local saved = segment.vfsPredictionStyle
  if not enabled and not saved then return true end
  if not saved then
    saved = { atlas = fill:GetAtlas(), texture = fill:GetTexture(), coords = { fill:GetTexCoord() },
      nativeColor = { fill:GetVertexColor() },
      fillAlpha = fill:GetAlpha(), segmentAlpha = segment:GetAlpha(), blendMode = fill:GetBlendMode(),
      levelOffset = segment:GetFrameLevel() - bar:GetFrameLevel(), active = false }
    segment.vfsPredictionStyle = saved
    saved.clip = segment:CreateMaskTexture(nil, "OVERLAY")
    saved.clip:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    saved.clip:SetAllPoints(bar)
    local function Sync()
      Util.Safe("prediction:" .. st.id .. ":" .. entry.key, StylePrediction, st, entry)
    end
    if segment.UpdateFillPosition then hooksecurefunc(segment, "UpdateFillPosition", Sync) end
    if segment.SetFillColor then
      hooksecurefunc(segment, "SetFillColor", function()
        saved.nativeColor = { fill:GetVertexColor() }
        Sync()
      end)
    end
    hooksecurefunc(bar, "SetFrameLevel", Sync)
    hooksecurefunc(bar, "SetFrameStrata", Sync)
  end
  if enabled then
    if HasMask(fill, entry.artMask) then
      fill:RemoveMaskTexture(entry.artMask)
      saved.removedArtMask = entry.artMask
    end
    if not HasMask(fill, saved.clip) then fill:AddMaskTexture(saved.clip) end
    -- Diagnostic control: BantoBar fades to RGB 69/255 on the right, so tinting
    -- its full-width texture yellow yields an olive slice under the FillMask.
    -- Keep main bars unchanged; use white here to isolate that pixel shading.
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetVertexColor(1, 0.9, 0.1, 1)
    -- Vertex alpha alone does not override native texture/frame opacity.
    fill:SetAlpha(1)
    segment:SetAlpha(1)
    fill:SetBlendMode("BLEND")
    fill:SetTexCoord(0, 1, 0, 1)
    fill:ClearAllPoints(); fill:SetAllPoints(bar)
    segment:SetFrameStrata(bar:GetFrameStrata())
    segment:SetFrameLevel(bar:GetFrameLevel() + 1)
    bar.vfsBorderLevelOffset = 2
    if bar.vfsBackdrop then bar.vfsBackdrop.ring:SetFrameLevel(bar:GetFrameLevel() + 2) end
    st.host.top:SetFrameLevel(math.max(st.host.top:GetFrameLevel(), bar:GetFrameLevel() + 3))
    saved.active = true
  elseif saved.active then
    if HasMask(fill, saved.clip) then fill:RemoveMaskTexture(saved.clip) end
    if saved.removedArtMask and not HasMask(fill, saved.removedArtMask) then fill:AddMaskTexture(saved.removedArtMask) end
    if saved.atlas then fill:SetAtlas(saved.atlas, false) else fill:SetTexture(saved.texture) end
    fill:SetTexCoord(unpack(saved.coords))
    fill:SetVertexColor(unpack(saved.nativeColor))
    fill:SetAlpha(saved.fillAlpha)
    segment:SetAlpha(saved.segmentAlpha)
    fill:SetBlendMode(saved.blendMode)
    fill:ClearAllPoints(); fill:SetAllPoints(segment)
    segment:SetFrameLevel(bar:GetFrameLevel() + saved.levelOffset)
    bar.vfsBorderLevelOffset = nil
    if bar.vfsBackdrop then bar.vfsBackdrop.ring:SetFrameLevel(bar:GetFrameLevel() + 1) end
    saved.active = false
  end
  return true
end

function FrameBase.ApplyPredictions(st)
  for _, entry in ipairs(Client.PredictionSegments(st.id)) do
    local ok, supported = pcall(StylePrediction, st, entry)
    VFS.features["prediction:" .. st.id .. ":" .. entry.key] = ok and supported or false
    if not ok then Util.WarnOnce("prediction:" .. st.id .. ":" .. entry.key, tostring(supported)) end
  end
end

-- Stock status/threat art can reset its alpha every frame (notably Player's
-- StatusTexture). Gate ONLY ChromeRegions, never keep-list or prediction regions.
-- Save native alpha writes so disabling styling restores the intended opacity.
function FrameBase.SetChromeSuppressed(region, id, suppressed)
  local state = region.vfsChromeAlphaState
  if not state then
    state = { nativeAlpha = region:GetAlpha(), setting = false }
    region.vfsChromeAlphaState = state
    hooksecurefunc(region, "SetAlpha", function(_, alpha)
      if state.setting then return end
      state.nativeAlpha = alpha -- may be secret: store/pass through only
      if DB.Frame(id).enabled then
        state.setting = true
        region:SetAlpha(0)
        state.setting = false
      end
    end)
  end
  state.setting = true
  if suppressed then region:SetAlpha(0) else region:SetAlpha(state.nativeAlpha) end
  state.setting = false
end

function FrameBase.ApplyAppearance(st)
  local id = st.id
  local enabled = DB.Frame(id).enabled
  if enabled then VFS.Geometry.ApplyBarDimensions(st) end
  local texPath = Util.StatusBarPath(DB.Effective(id, "barTexture"))
  local backing = DB.Effective(id, "backingAlpha")
  for kind, bar in pairs(st.bars) do
    if enabled then
      bar.stock:SetStatusBarTexture(texPath)
      local t = bar.stock:GetStatusBarTexture(); if t then t:SetAlpha(1); t:SetHorizTile(false); t:SetVertTile(false) end
      ApplyFillMask(bar.stock)
      if kind == "health" then ApplyHealthColor(bar.stock, st.unit) else ApplyPowerColor(bar.stock, st.unit) end
      FrameBase.ColorBackdrop(bar.stock, backing)
      bar.backdrop:Show()
      bar.backdrop.ring:Show()
    else
      bar.backdrop:Hide()
      bar.backdrop.ring:Hide()
    end
  end
  -- Blizzard chrome: alpha 0 while enabled; keep-list never touched
  local a = enabled and 0 or 1
  for _, r in ipairs(Client.ChromeRegions(id)) do
    if r.GetObjectType and r:GetObjectType() == "StatusBar" then
      for i = 1, select("#", r:GetRegions()) do local t = select(i, r:GetRegions()); if t.SetAlpha then FrameBase.SetChromeSuppressed(t, id, enabled) end end
    elseif r.SetAlpha then FrameBase.SetChromeSuppressed(r, id, enabled) end
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
  FrameBase.RefreshPowerVisibility(st)
  FrameBase.ApplyPredictions(st)
  if VFS.Chrome then VFS.Chrome.SetShown(st, enabled); VFS.Chrome.Layout(st); VFS.Chrome.ApplyColors(st); VFS.Chrome.UpdateCombat(st) end
end

-- Values (texts) -----------------------------------------------------------------------------------------
function FrameBase.ApplyTexts(st, filter)
  if not DB.Frame(st.id).enabled then return end
  if not UnitExists(st.unit) then for _, t in pairs(st.host.text) do if not t.vfsAdopted then t:Hide() end end return end
  local powerChanged = FrameBase.RefreshPowerVisibility(st)
  if powerChanged then filter = nil end
  TextLayout.ApplyTexts(st.host, DB.Elements(st.id), st.unit, Client.NameText(st.id), filter)
  if st.powerAbsent then
    for _, e in ipairs(DB.Elements(st.id)) do
      local fs = st.host.text[e.id]
      if fs and (e.anchor == "power" or VFS.Format.UsesPower(e.format)) then
        fs.vfsVisible = false
        if fs.vfsAdopted then fs:SetAlpha(0) else fs:Hide() end
      end
    end
  end
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
  if st.id == "target" and st.bars.power then
    local function SyncPowerVisibility() FrameBase.ApplyTexts(st) end
    st.bars.power.stock:HookScript("OnShow", SyncPowerVisibility)
    st.bars.power.stock:HookScript("OnHide", SyncPowerVisibility)
  end
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
  if id == "pettarget" and VFS.PetTarget.IsSample() then
    VFS.PetTarget.SetSample(true)
    return
  end
  FrameBase.ApplyAppearance(st)
  FrameBase.ApplyTexts(st)
end

function FrameBase.RestyleAll()
  for id in pairs(VFS.Frames) do FrameBase.Restyle(id) end
end