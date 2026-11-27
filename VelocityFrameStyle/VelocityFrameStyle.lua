-- Velocity Frame Style: bootstrap. Saved variables, stand-down (R7), events, slash, keybinding names.
local ADDON_NAME, VFS = ...
local Util, Client, DB = VFS.Util, VFS.Client, VFS.DB

_G.VelocityFrameStyleAddon = VFS

BINDING_HEADER_VELOCITYFRAMESTYLE = "Velocity Frame Style"
_G["BINDING_NAME_CLICK VelocityFrameStylePetTarget:LeftButton"] = "Target your pet's target"

-- R7: other owners of the unit frames. If one is loaded we style nothing and say so once.
local FRAME_OWNERS = { "EasyFrames", "ShadowedUnitFrames", "ElvUI", "PitBull4", "oUF", "Tukui", "VelocityPetTargetFrame", "LazyThom_PetTarget" }
local PETTARGET_ONLY = { VelocityPetTargetFrame = true, LazyThom_PetTarget = true }

local function IsLoaded(name)
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  return f and f(name) == true
end

local function StandDownCheck()
  for _, name in ipairs(FRAME_OWNERS) do
    if IsLoaded(name) then
      if PETTARGET_ONLY[name] then VFS.standDownPetTarget = name else VFS.standDown = name end
    end
  end
end

-- Slash -------------------------------------------------------------------------------
local function Status()
  Util.DumpHeader("/vfs status")
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
  local ci = Util.ClientInfo()
  Util.Print("version %s | client %s %s (build %s, interface %s) | character %s", tostring(version), Client.flavour, ci.Version, ci.Build, tostring(ci.Interface), tostring(UnitGUID("player")))
  Util.Print("stand-down: %s | pet-target stand-down: %s", tostring(VFS.standDown), tostring(VFS.standDownPetTarget))
  for _, id in ipairs(DB.FRAME_IDS) do
    local st = VFS.Frames[id]
    local hb, pb = Client.HealthBar(id), Client.PowerBar(id)
    Util.Print("%-9s %s | health %s%s | power %s%s | chrome %d regions | keep %d | name %s", id, st and "styled" or "-",
      hb and "ok" or "MISSING", (st and st.bars.health and st.bars.health.movable) and " (sized)" or "",
      pb and "ok" or "MISSING", (st and st.bars.power and st.bars.power.movable) and " (sized)" or "",
      #Client.ChromeRegions(id), #Client.KeepRegions(id), Client.NameText(id) and "ok" or "MISSING")
  end
  Util.Print(VFS.EditMode.Status())
  Util.Print(VFS.OwnedVisibility.Status())
  if VFS.PetHappinessPanel and VFS.features["PetHappinessPanel"] then Util.Print(VFS.PetHappinessPanel.Status()) end
  local feats = {}
  for k, v in pairs(VFS.features) do feats[#feats + 1] = k .. "=" .. tostring(v) end
  table.sort(feats)
  Util.Print("features: %s | LSM %s", table.concat(feats, ", "), VFS.Textures.HasLSM() and "yes" or "no")
  Util.DumpFooter("/vfs status")
end

-- /vfs text <frame>: every text element's state (shown / alpha / content / width) and the host vs bar frame levels.
local function DumpText(id)
  local st = VFS.Frames[id]
  if not st then Util.Print("no frame state for %s", tostring(id)) return end
  Util.DumpHeader("/vfs text " .. id)
  Util.Print("unit %s exists %s | enabled %s | host shown %s level %d strata %s", st.unit, tostring(UnitExists(st.unit)),
    tostring(DB.Frame(id).enabled), tostring(st.host.top:IsShown()), st.host.top:GetFrameLevel(), st.host.top:GetFrameStrata())
  for kind, bar in pairs(st.bars) do
    Util.Print("bar %s level %d strata %s shown %s | movable %s", kind, bar.stock:GetFrameLevel(), bar.stock:GetFrameStrata(),
      tostring(bar.stock:IsShown()), tostring(bar.movable))
  end
  for slot, region in pairs(st.slots) do
    local w, h = region:GetSize()
    Util.Print("slot %-9s %dx%d shown %s", slot, math.floor(w or 0), math.floor(h or 0), tostring(region:IsShown()))
  end
  for _, e in ipairs(DB.Elements(id)) do
    local fs = st.host.text[e.id]
    if fs then
      local p, rel = fs:GetPoint(1)
      Util.Print("%-9s anchor=%s shown=%s alpha=%.1f vis=%s w=%d text=|%s| point=%s rel=%s", e.id, e.anchor, tostring(fs:IsShown()),
        fs:GetAlpha(), tostring(fs.vfsVisible), math.floor(fs:GetStringWidth() or 0), tostring(fs:GetText()), tostring(p), tostring(rel and rel:GetName() or rel))
    else
      Util.Print("%-9s NO FONTSTRING", e.id)
    end
  end
  Util.DumpFooter("/vfs text " .. id)
end

-- /vfs rects <frame>: on-screen size of the stock bars, portrait and our chrome shapes.
local function DumpRects(id)
  local st = VFS.Frames[id]
  if not st then Util.Print("no frame state for %s", tostring(id)) return end
  Util.DumpHeader("/vfs rects " .. id)
  local function R(label, f)
    if not f then Util.Print("%-14s nil", label) return end
    local _, _, w, h = f:GetRect()
    local scale = f.GetEffectiveScale and f:GetEffectiveScale() or f:GetParent():GetEffectiveScale()
    Util.Print("%-14s local=%.2fx%.2f effectiveScale=%.3f scaled=%.2fx%.2f", label,
      w or 0, h or 0, scale, (w or 0) * scale, (h or 0) * scale)
  end
  R("button", st.button)
  for kind, bar in pairs(st.bars) do
    R(kind .. ".bar", bar.stock); R(kind .. ".backdrop", bar.backdrop)
    R(kind .. ".border", bar.backdrop.ring)
  end
  R("portrait", Client.Portrait(id))
  if st.chrome then R("chrome.disc", st.chrome.disc); R("chrome.plate", st.chrome.plate) end
  Util.DumpFooter("/vfs rects " .. id)
end

-- /vfs values <frame>: are this unit's numbers secret on this client? Decides adopt-vs-compute for the grid.
local function DumpValues(id)
  local unit = Client.Unit(id)
  Util.DumpHeader("/vfs values " .. id .. " (" .. tostring(unit) .. ")")
  local function S(label, v) Util.Print("%-14s secret=%s type=%s plain=%s", label, tostring(Util.IsSecret(v)), type(v), tostring(Util.Plain(v))) end
  S("UnitHealth", UnitHealth(unit)); S("UnitHealthMax", UnitHealthMax(unit))
  S("UnitPower", UnitPower(unit)); S("UnitPowerMax", UnitPowerMax(unit))
  S("UnitLevel", UnitLevel(unit)); S("UnitName", (UnitName(unit)))
  local cur, max, pct = Client.HealthValues(unit)
  Util.Print("Client.HealthValues -> cur=%s max=%s pct=%s", tostring(cur), tostring(max), tostring(pct))
  Util.Print("Format [hp]=|%s| [hp%%]=|%s| [power]=|%s|", VFS.Format.Expand("[hp]", unit), VFS.Format.Expand("[hp%]", unit), VFS.Format.Expand("[power]", unit))
  Util.DumpFooter("/vfs values " .. id)
end

-- /vfs layers <frame>: every region/frame under the unit button that overlaps the health bar rect, in draw order
-- (strata, frame level, layer, sublevel), with alpha/shown. Finds "what is drawn over our bar".
local LAYER_ORDER = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }
local function DumpLayers(id)
  local st = VFS.Frames[id]
  if not st or not st.bars.health then Util.Print("no health bar for %s", tostring(id)) return end
  local hb = st.bars.health.stock
  local l, b, w, h = hb:GetRect()
  if not l then Util.Print("bar has no rect") return end
  local r, t = l + w, b + h
  local rows = {}
  local visited, visits = {}, 0
  local function Overlaps(x) local xl, xb, xw, xh = x:GetRect(); if not xl or not xw or xw == 0 then return false end return xl < r and xl + xw > l and xb < t and xb + xh > b end
  local function Walk(frame, depth)
    if depth > 6 or visited[frame] or visits > 400 then return end
    visited[frame] = true; visits = visits + 1
    -- skip our own frames (overlay, backdrop, text host): we know what they draw
    if frame == hb or frame == st.bars.health.backdrop or frame == st.host.top or (st.bars.power and (frame == st.bars.power.stock or frame == st.bars.power.backdrop)) then return end
    for i = 1, select("#", frame:GetRegions()) do
      local reg = select(i, frame:GetRegions())
      if reg:IsShown() and Overlaps(reg) and reg:GetObjectType() ~= "MaskTexture" then
        local layer, sub = reg:GetDrawLayer()
        local what
        if reg:GetObjectType() == "FontString" then what = "text:" .. tostring(reg:GetText()):sub(1, 12)
        else
          local okA, atlas = pcall(reg.GetAtlas, reg); local okT, tex = pcall(reg.GetTexture, reg)
          what = (okA and atlas) or (okT and tostring(tex)) or reg:GetObjectType()
        end
        local vr, vg, vb, va = 1, 1, 1, 1; if reg.GetVertexColor then vr, vg, vb, va = reg:GetVertexColor() end
        rows[#rows + 1] = { k = frame:GetFrameLevel() * 10 + (LAYER_ORDER[layer] or 0) + (sub or 0) / 10, s = string.format("L%d %s%+d a=%.2f vc=%.1f,%.1f,%.1f,%.1f %s <%s>", frame:GetFrameLevel(), layer, sub or 0, reg:GetAlpha(), vr or 1, vg or 1, vb or 1, va or 1, what, (frame:GetName() or reg:GetName() or (frame.GetDebugName and frame:GetDebugName()) or "?")) }
      end
    end
    for i = 1, select("#", frame:GetChildren()) do
      local c = select(i, frame:GetChildren())
      if c:IsShown() and c:GetFrameStrata() == hb:GetFrameStrata() then Walk(c, depth + 1) end
    end
  end
  Walk(st.button, 0)
  table.sort(rows, function(x, y) return x.k < y.k end)
  Util.DumpHeader(string.format("/vfs layers %s (health bar level %d, backdrop level %d)", id, hb:GetFrameLevel(), st.bars.health.backdrop:GetFrameLevel()))
  for _, row in ipairs(rows) do Util.Print(row.s) end
  Util.DumpFooter("/vfs layers " .. id)
end

-- /vfs stack <frame>: the frame levels of every piece of OUR portrait/adornment stack vs the bars, with each frame's
-- parent chain to the button. Answers "why is X under Y" with numbers instead of guesses (owner 2026-11-25: Target
-- badge still under the bars after the audited stack).
local function DumpStack(id)
  local st = VFS.Frames[id]
  if not st then Util.Print("no frame state for %s", tostring(id)) return end
  local portrait = Client.Portrait(id)
  local function Chain(f)
    local parts = {}
    local p = f
    for _ = 1, 6 do
      if not p then break end
      parts[#parts + 1] = string.format("%s[%s L%d]", (p:GetName() or p.GetDebugName and p:GetDebugName() or "?"):sub(-28), p:GetFrameStrata(), p:GetFrameLevel())
      if p == st.button or p == UIParent then break end
      p = p:GetParent()
    end
    return table.concat(parts, " < ")
  end
  Util.DumpHeader("/vfs stack " .. id)
  Util.Print("button        %s", Chain(st.button))
  if st.chrome then Util.Print("holder        %s", Chain(st.chrome.holder)); Util.Print("glowFrame     %s", Chain(st.chrome.glow.frame)) end
  if st.portraitLayer then Util.Print("portraitLayer %s", Chain(st.portraitLayer)) end
  if portrait then Util.Print("portrait tex  parent=%s layer=%s", Chain(portrait:GetParent()), (portrait:GetDrawLayer())) end
  for kind, bar in pairs(st.bars) do
    Util.Print("bar %-7s   %s", kind, Chain(bar.stock))
    Util.Print("  backdrop    %s", Chain(bar.backdrop)); Util.Print("  ring        %s", Chain(bar.backdrop.ring))
    if st.chrome and st.chrome.glow.rings[kind] then Util.Print("  glow ring   %s", Chain(st.chrome.glow.rings[kind])) end
  end
  if st.adornment then Util.Print("adornment     %s", Chain(st.adornment)) end
  if st.portraitBadge then Util.Print("badge         %s shown=%s", Chain(st.portraitBadge), tostring(st.portraitBadge:IsShown())) end
  Util.Print("host.top      %s", Chain(st.host.top))
  Util.DumpFooter("/vfs stack " .. id)
end

-- Read-only: distinguish secret capacity from stale/independent power visuals.
local function DumpPower(id)
  local st = VFS.Frames[id]
  if not st or not st.bars.power then Util.Print("no power bar for %s", tostring(id)); return end
  local bar = st.bars.power
  local function S(v)
    if Util.IsSecret(v) then return "<secret>" end
    return tostring(v)
  end
  local maximum = UnitPowerMax(st.unit)
  local plain = Util.PlainNumber(maximum, nil)
  local powerType, token = UnitPowerType(st.unit)
  local low, high = bar.stock:GetMinMaxValues()
  Util.DumpHeader("/vfs power " .. id)
  Util.Print("unit=%s exists=%s type=%s token=%s", st.unit, S(UnitExists(st.unit)), S(powerType), S(token))
  if UnitHasPowerType and not Util.IsSecret(powerType) then
    local ok, present = pcall(UnitHasPowerType, st.unit, powerType)
    Util.Print("UnitHasPowerType ok=%s result=%s | client presence=%s", tostring(ok), S(present), S(Client.HasPowerResource(st.unit)))
  end
  Util.Print("current=%s max=%s maxSecret=%s plainMax=%s", S(UnitPower(st.unit)), S(maximum),
    tostring(Util.IsSecret(maximum)), tostring(plain))
  Util.Print("stock shown=%s visible=%s alpha=%s range=%s..%s", S(bar.stock:IsShown()),
    S(bar.stock:IsVisible()), S(bar.stock:GetAlpha()), S(low), S(high))
  Util.Print("stock controlsShownState=%s alwaysShow=%s pauseUpdates=%s", S(bar.stock.controlsShownState),
    S(bar.stock.alwaysShow), S(bar.stock.pauseUpdates))
  Util.Print("VFS powerAbsent=%s slotPresent=%s backingShown=%s backingAlpha=%s borderAlpha=%s",
    S(st.powerAbsent), tostring(st.slots.power ~= nil), S(bar.backdrop:IsShown()),
    S(bar.backdrop:GetAlpha()), S(bar.backdrop.ring:GetAlpha()))
  local text = st.host.text.power
  if text then
    Util.Print("text shown=%s alpha=%s layoutVisible=%s", S(text:IsShown()), S(text:GetAlpha()), S(text.vfsVisible))
  end
  Util.DumpFooter("/vfs power " .. id)
end

local powerComparePanel
local function ComparePower()
  if not powerComparePanel then
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(460, 300); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG")
    local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.95)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12); title:SetText("Power comparison (snapshot; rerun to refresh)")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT"); close:SetScript("OnClick", function() panel:Hide() end)
    panel.rows = {}
    for i = 1, 10 do
      local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("TOPLEFT", 12, -42 - (i-1)*23)
      local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      value:SetPoint("TOPRIGHT", -18, -42 - (i-1)*23)
      panel.rows[i] = { label = label, value = value }
    end
    powerComparePanel = panel
  end
  local row = 0
  local function Add(label, value)
    row = row + 1
    local r = powerComparePanel.rows[row]
    r.label:SetText(label)
    -- Direct widget sink only: no comparison, tostring, arithmetic or chat logging.
    r.value:SetText(value)
  end
  for _, id in ipairs({ "target", "pettarget" }) do
    local st = VFS.Frames[id]
    local bar = st and st.bars.power and st.bars.power.stock
    if bar then
      local low, high = bar:GetMinMaxValues()
      local powerType = UnitPowerType(st.unit)
      Add(id .. " API max (default type)", UnitPowerMax(st.unit))
      Add(id .. " API max (explicit type)", UnitPowerMax(st.unit, powerType))
      Add(id .. " widget minimum", low)
      Add(id .. " widget maximum", high)
      Add(id .. " widget current", bar:GetValue())
      Util.Print("%s TextString=%s nativeUpdater=%s", id, tostring(bar.TextString ~= nil),
        tostring(TextStatusBarMixin and bar.UpdateTextString == TextStatusBarMixin.UpdateTextString))
    else
      for i = 1, 5 do Add(id .. " unavailable", "-") end
    end
  end
  powerComparePanel:Show()
end

local function DumpPredictions()
  local function S(v) if Util.IsSecret(v) then return "<secret>" end return tostring(v) end
  Util.DumpHeader("/vfs predictions player")
  Util.Print("selected texture: %s", Util.StatusBarPath(DB.Effective("player", "barTexture")))
  for _, entry in ipairs(Client.PredictionSegments("player")) do
    local segment = entry.segment
    local fill = segment and segment.Fill
    if fill then
      local r, g, b, a = fill:GetVertexColor()
      Util.Print("%s styled=%s shown=%s level=%s fillAlpha=%s rgba=%s,%s,%s,%s blend=%s", entry.key,
        tostring(segment.vfsPredictionStyle and segment.vfsPredictionStyle.active), S(segment:IsShown()),
        S(segment:GetFrameLevel()), S(fill:GetAlpha()), S(r), S(g), S(b), S(a), S(fill:GetBlendMode()))
      Util.Print("texture=%s atlas=%s masks=%s", S(fill:GetTexture()), S(fill:GetAtlas()), S(fill:GetNumMaskTextures()))
      local parent = fill:GetParent()
      for depth = 1, 4 do
        if not parent then break end
        Util.Print("  parent%d %s alpha=%s", depth, parent:GetName() or "anonymous", S(parent:GetAlpha()))
        parent = parent:GetParent()
      end
    else
      Util.Print("%s MISSING", entry.key)
    end
  end
  Util.DumpFooter("/vfs predictions player")
end

local function Slash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd, arg = msg:match("^(%S+)%s*(%S*)$")
  if msg == "status" then Status()
  elseif msg == "ptpos" then
    local frame = VFS.PetTarget.frame
    Util.Print(VFS.LayoutProfile.Status())
    local saved = DB.Profile().petTargetPlacement
    Util.Print("saved: anchorTo=%s point=%s relPoint=%s x=%s y=%s", tostring(saved.anchorTo),
      tostring(saved.point), tostring(saved.relPoint), tostring(saved.x), tostring(saved.y))
    if frame then
      local point, relative, relPoint, x, y = frame:GetPoint(1)
      Util.Print("actual: relative=%s point=%s relPoint=%s x=%s y=%s scale=%s", tostring(relative and relative:GetName()),
        tostring(point), tostring(relPoint), tostring(x), tostring(y), tostring(frame:GetScale()))
    end
  elseif cmd == "text" then DumpText(arg ~= "" and arg or "player")
  elseif cmd == "rects" then DumpRects(arg ~= "" and arg or "player")
  elseif cmd == "values" then DumpValues(arg ~= "" and arg or "player")
  elseif cmd == "power" then DumpPower(arg ~= "" and arg or "target")
  elseif msg == "powercompare" then ComparePower()
  elseif cmd == "predictions" then
    local delay = tonumber(arg) or 0
    if delay > 0 then
      Util.Print("Prediction snapshot in %.1f seconds; start casting now.", math.min(delay, 10))
      C_Timer.After(math.min(delay, 10), DumpPredictions)
    else DumpPredictions() end
  elseif cmd == "layers" then DumpLayers(arg ~= "" and arg or "player")
  elseif cmd == "stack" then DumpStack(arg ~= "" and arg or "target")
  elseif msg == "pethappiness" or msg == "pethappy" then VFS.PetHappinessPanel.Dump()
  elseif msg == "editmode" or msg == "edit" then VFS.EditMode.Open()
  elseif msg == "restyle" then VFS.FrameBase.RestyleAll(); Util.Print("restyled")
  else VFS.Options.Open() end
end

-- Events ------------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

local function Stage(name, fn)
  local ok, err = pcall(fn)
  if not ok then Util.Raise("init stage " .. name, err) end
end

local function OnEvent(_, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    Stage("DB", DB.Init)
    SLASH_VELOCITYFRAMESTYLE1 = "/vfs"
    SLASH_VELOCITYFRAMESTYLE2 = "/velocityframestyle"
    SlashCmdList.VELOCITYFRAMESTYLE = Slash
  elseif event == "PLAYER_LOGIN" then
    StandDownCheck()
    Stage("LayoutProfile", function()
      VFS.LayoutProfile.Init(DB.DEFAULT_PROFILE)
      VFS.LayoutProfile.OnChanged(function() VFS.EditMode.OnProfileChanged(); VFS.Options.Refresh() end)
    end)
    if VFS.standDown then
      Util.Print("standing down: %s owns the unit frames. Nothing is restyled.", VFS.standDown)
    else
      -- "Use Velocity Frame Style" OFF is honoured HERE, at load: the frame is never acquired or hooked, so Blizzard's
      -- frame is untouched. Unticking it live only asks for a /reload (UI\Options.lua banner); nothing is undone in place.
      local function Styled(id) return DB.Frame(id).enabled end
      if Styled("player") then Stage("Player", VFS.Player.Create) end
      if Styled("target") then Stage("Target", VFS.Target.Create) end
      if Styled("pet") then Stage("Pet", VFS.Pet.Create) end
      -- Owned Target-of-Target (spec 11), after Target so Blizzard's ToT is already suppressed as Target chrome.
      if Styled("tot") then
        Stage("ToT", VFS.ToT.Create)
        Stage("ToTVisibility", function() VFS.OwnedVisibility.Register(VFS.ToT.owned) end)
        Stage("ToTPlacement", function() if not VFS.ToT.ApplyPlacement() then VFS.OwnedVisibility.MarkPending("tot") end end)
      end
      -- Era hunter pets only; Setup is a no-op where Client.PetHappinessFrame() is nil (Forever).
      Stage("PetHappinessPanel", VFS.PetHappinessPanel.Setup)
    end
    if VFS.standDownPetTarget or not DB.Frame("pettarget").enabled then
      Util.Print("pet-target frame off: %s already provides one.", VFS.standDownPetTarget)
    else
      Stage("PetTarget", VFS.PetTarget.Create)
      Stage("PetTargetVisibility", function() VFS.OwnedVisibility.Register(VFS.PetTarget.owned) end)
      Stage("PetTargetPlacement", function() if not VFS.PetTarget.ApplyPlacement() then VFS.PetTargetVisibility.MarkPending() end end)
    end
    -- Edit Mode is needed by every owned frame (ToT too), not only Pet Target
    Stage("EditMode", VFS.EditMode.Setup)
    if VFS.PetTarget.frame then Stage("PetTargetDriver", VFS.PetTargetVisibility.EnableDriver) end
    if VFS.ToT.frame and VFS.ToT.IsEnabled() then Stage("ToTDriver", function() VFS.OwnedVisibility.EnableDriver("tot") end) end
    Stage("Options", VFS.Options.Create)
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("RAID_TARGET_UPDATE")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:RegisterUnitEvent("UNIT_TARGET", "pet", "target")
    f:RegisterUnitEvent("UNIT_PET", "player")
    f:RegisterUnitEvent("UNIT_LEVEL", "player", "target", "pet", "pettarget", "targettarget")
    f:RegisterUnitEvent("UNIT_NAME_UPDATE", "player", "target", "pet", "pettarget", "targettarget")
    f:RegisterUnitEvent("UNIT_FACTION", "target", "pettarget", "targettarget")
    f:RegisterUnitEvent("UNIT_FLAGS", "player", "target", "pet", "pettarget", "targettarget")   -- in-combat flag -> our glow
    f:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "pettarget", "targettarget")
    -- owned ToT value events (pettarget fires none and polls instead)
    f:RegisterUnitEvent("UNIT_HEALTH", "targettarget")
    f:RegisterUnitEvent("UNIT_MAXHEALTH", "targettarget")
    f:RegisterUnitEvent("UNIT_POWER_UPDATE", "targettarget")
    f:RegisterUnitEvent("UNIT_MAXPOWER", "targettarget")
    f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "targettarget")
    Util.Print("loaded (%s). /vfs for options, /vfs status for details", Client.flavour)
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if arg1 == ADDON_NAME then
      Util.WarnOnce("blocked:" .. tostring(arg2), "the game blocked " .. tostring(arg2) .. " (in combat)")
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    VFS.OwnedVisibility.OnRegenEnabled()
    for id, st in pairs(VFS.Frames) do
      if st.dimensionsPending then VFS.FrameBase.Restyle(id) end
    end
    -- our combat glow follows the player's combat state on every frame we style
    for _, st in pairs(VFS.Frames) do VFS.FrameBase.OnCombatChanged(st) end
    if VFS.ToT.frame then VFS.ToT.OnEvent(event) end
  elseif event == "PLAYER_REGEN_DISABLED" then
    for _, st in pairs(VFS.Frames) do VFS.FrameBase.OnCombatChanged(st) end
  elseif event == "UNIT_TARGET" then
    if arg1 == "pet" and VFS.PetTarget.frame then VFS.PetTarget.OnPetTargetChanged() end
    if arg1 == "target" and VFS.ToT.frame then VFS.ToT.OnEvent(event, arg1) end
  elseif event == "UNIT_PET" then
    if VFS.PetTarget.frame then VFS.PetTarget.OnPetTargetChanged() end
    if VFS.Frames.pet then VFS.Pet.OnEvent(event, arg1) end
  elseif event == "PLAYER_TARGET_CHANGED" then
    if VFS.Frames.target then VFS.Target.OnEvent(event) end
    if VFS.ToT.frame then VFS.ToT.OnEvent(event) end
  elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
    -- registered for targettarget only: the owned ToT has no poller (pettarget does, it fires no events)
    if VFS.ToT.frame then VFS.ToT.OnEvent(event, arg1) end
  else
    if VFS.Frames.player then VFS.Player.OnEvent(event, arg1) end
    if VFS.Frames.target then VFS.Target.OnEvent(event, arg1) end
    if VFS.Frames.pet then VFS.Pet.OnEvent(event, arg1) end
    if VFS.PetTarget.frame and (arg1 == "pettarget" or event == "PLAYER_ENTERING_WORLD" or event == "RAID_TARGET_UPDATE") then VFS.PetTarget.Update() end
    if VFS.ToT.frame and (arg1 == "targettarget" or event == "PLAYER_ENTERING_WORLD" or event == "RAID_TARGET_UPDATE") then VFS.ToT.OnEvent(event, arg1) end
  end
end

f:SetScript("OnEvent", function(...)
  local ok, err = pcall(OnEvent, ...)
  if not ok then Util.Raise("event", err) end
end)