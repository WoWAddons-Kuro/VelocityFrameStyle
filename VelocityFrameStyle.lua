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
    Util.Print("%-9s %s | health %s%s | power %s%s | art %s | name %s", id, st and "styled" or "-",
      hb and "ok" or "MISSING", (st and st.bars.health and st.bars.health.inPlace) and " (in place)" or (st and st.bars.health and " (overlay)" or ""),
      pb and "ok" or "MISSING", (st and st.bars.power and st.bars.power.inPlace) and " (in place)" or (st and st.bars.power and " (overlay)" or ""),
      Client.FrameArt(id) and "ok" or "MISSING", Client.NameText(id) and "ok" or "MISSING")
  end
  Util.Print(VFS.EditMode.Status())
  Util.Print(VFS.PetTargetVisibility.Status())
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
    Util.Print("bar %s draw level %d strata %s shown %s | stock level %d", kind, bar.draw:GetFrameLevel(), bar.draw:GetFrameStrata(),
      tostring(bar.draw:IsShown()), bar.stock:GetFrameLevel())
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

-- /vfs rects <frame>: on-screen size of the stock bar, its container slot and our overlay, per bar.
local function DumpRects(id)
  local st = VFS.Frames[id]
  if not st then Util.Print("no frame state for %s", tostring(id)) return end
  Util.DumpHeader("/vfs rects " .. id)
  local function R(label, f) if not f then Util.Print("%-14s nil", label) return end local _, _, w, h = f:GetRect() Util.Print("%-14s %dx%d", label, math.floor((w or 0) + 0.5), math.floor((h or 0) + 0.5)) end
  R("button", st.button)
  for kind, bar in pairs(st.bars) do
    R(kind .. ".stock", bar.stock); R(kind .. ".slot", Client.BarSlot(id, kind)); R(kind .. ".draw", bar.draw); R(kind .. ".mask", Client.BarMask(id, kind))
  end
  R("nameBackground", Client.NameBackground(id)); R("art", Client.FrameArt(id)); R("portrait", Client.Portrait(id))
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

local function Slash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd, arg = msg:match("^(%S+)%s*(%S*)$")
  if msg == "status" then Status()
  elseif cmd == "text" then DumpText(arg ~= "" and arg or "player")
  elseif cmd == "rects" then DumpRects(arg ~= "" and arg or "player")
  elseif cmd == "values" then DumpValues(arg ~= "" and arg or "player")
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
      Stage("Player", VFS.Player.Create)
      Stage("Target", VFS.Target.Create)
      Stage("Pet", VFS.Pet.Create)
    end
    if VFS.standDownPetTarget then
      Util.Print("pet-target frame off: %s already provides one.", VFS.standDownPetTarget)
    else
      Stage("PetTarget", VFS.PetTarget.Create)
      Stage("PetTargetPlacement", function() if not VFS.PetTarget.ApplyPlacement() then VFS.PetTargetVisibility.MarkPending() end end)
      Stage("EditMode", VFS.EditMode.Setup)
      Stage("PetTargetVisibility", VFS.PetTargetVisibility.EnableDriver)
    end
    Stage("Options", VFS.Options.Create)
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("RAID_TARGET_UPDATE")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:RegisterUnitEvent("UNIT_TARGET", "pet")
    f:RegisterUnitEvent("UNIT_PET", "player")
    f:RegisterUnitEvent("UNIT_LEVEL", "player", "target", "pet", "pettarget")
    f:RegisterUnitEvent("UNIT_NAME_UPDATE", "player", "target", "pet", "pettarget")
    f:RegisterUnitEvent("UNIT_FACTION", "target", "pettarget")
    f:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "pettarget")
    Util.Print("loaded (%s). /vfs for options, /vfs status for details", Client.flavour)
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if arg1 == ADDON_NAME then
      if tostring(arg2):find("EnableMouse") then VFS.PetTargetVisibility.mouseBlocked = true end
      Util.WarnOnce("blocked:" .. tostring(arg2), "the game blocked " .. tostring(arg2) .. " (in combat)")
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    VFS.PetTargetVisibility.OnRegenEnabled()
  elseif event == "UNIT_TARGET" then
    if VFS.PetTarget.frame then VFS.PetTarget.OnPetTargetChanged(); VFS.PetTargetVisibility.ApplySoftHide() end
  elseif event == "UNIT_PET" then
    if VFS.PetTarget.frame then VFS.PetTarget.OnPetTargetChanged(); VFS.PetTargetVisibility.ApplySoftHide() end
    if VFS.Frames.pet then VFS.Pet.OnEvent(event, arg1) end
  elseif event == "PLAYER_TARGET_CHANGED" then
    if VFS.PetTarget.frame then VFS.PetTargetVisibility.ApplySoftHide() end
    if VFS.Frames.target then VFS.Target.OnEvent(event) end
  else
    if VFS.Frames.player then VFS.Player.OnEvent(event, arg1) end
    if VFS.Frames.target then VFS.Target.OnEvent(event, arg1) end
    if VFS.Frames.pet then VFS.Pet.OnEvent(event, arg1) end
    if VFS.PetTarget.frame and (arg1 == "pettarget" or event == "PLAYER_ENTERING_WORLD" or event == "RAID_TARGET_UPDATE") then VFS.PetTarget.Update() end
  end
end

f:SetScript("OnEvent", function(...)
  local ok, err = pcall(OnEvent, ...)
  if not ok then Util.Raise("event", err) end
end)