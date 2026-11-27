-- Velocity Frame Style: the PlayerFrame module. Stock bars styled in place; Geometry sizes them to the fixed M0
-- layout (EasyFrames-Forever constants: health 113x24, power 117x12) when the client lets us move them.
local ADDON_NAME, VFS = ...
local Client, DB, FrameBase, Chrome, Geometry = VFS.Client, VFS.DB, VFS.FrameBase, VFS.Chrome, VFS.Geometry

local Player = {}
VFS.Player = Player

local function PlaceBars(st)
  local L = Chrome.LAYOUT.player
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  -- EF-Forever puts the health bar CENTERed in the frame at (-30, 8) mirrored for the player (bars right of portrait)
  if hb then Geometry.PlaceBar("player", hb, { point = "LEFT", relTo = st.button, relPoint = "LEFT", x = 86, y = 6, width = L.health.w, height = L.health.h }) end
  if pb and hb then Geometry.PlaceBar("player", pb, { point = "TOPLEFT", relTo = hb, relPoint = "BOTTOMLEFT", x = 0, y = -FrameBase.BAR_BORDER_WIDTH, width = L.power.w, height = L.power.h }) end
  local mb = FrameBase.Bar(st, "mana")
  if mb and pb then Geometry.PlaceBar("player", mb, { point = "TOPLEFT", relTo = pb, relPoint = "BOTTOMLEFT", x = 0, y = -FrameBase.BAR_BORDER_WIDTH, width = L.power.w, height = L.mana.h }) end
end

-- Druid mana bar (SPECS/14). A third, VFS-OWNED StatusBar under the power bar that shows the MANA pool while a druid's
-- displayed power is rage/energy (Bear/Cat). Fed straight from UnitPower(unit, Mana): plain on Era, a SECRET current
-- on Forever - which a StatusBar accepts; Lua never compares it (Client.ManaBarValues). Hidden in caster/Tree (the
-- normal power bar IS mana), in Moonkin on Forever (Blizzard registers its own alternate bar there, D8), in vehicles
-- (D9), and never created for other classes (D1) or while a dedicated druid-mana addon is loaded (D10 stand-down).
local MANA_BAR_STANDDOWN_ADDONS = { "BorneDruidManaForEasyFrames", "DruidBarClassic" }
local function IsDruid() local _, class = UnitClass("player"); return VFS.Util.Plain(class) == "DRUID" end
local function IsAddOnLoadedSafe(name)
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  return f and f(name) == true
end

function Player.ManaBarStandDown()
  for _, name in ipairs(MANA_BAR_STANDDOWN_ADDONS) do if IsAddOnLoadedSafe(name) then return name end end
  return nil
end

local function CreateManaBar(st)
  if st.bars.mana or not IsDruid() then return end
  local pb = FrameBase.Bar(st, "power")
  if not pb then return end
  st.manaBarStandDown = Player.ManaBarStandDown()
  if st.manaBarStandDown then return end
  local bar = CreateFrame("StatusBar", nil, st.button)
  bar.vfsOwned = true     -- Core\Geometry.lua: ours to place; not in Client.MovableBars (that list is Blizzard's stock bars)
  bar:SetFrameStrata(pb:GetFrameStrata()); bar:SetFrameLevel(pb:GetFrameLevel())
  bar:EnableMouse(false)
  bar:SetMinMaxValues(0, 1); bar:SetValue(0)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  st.bars.mana = { stock = bar, backdrop = FrameBase.AcquireBackdrop(bar), movable = true, owned = true }
  VFS.Chrome.AddBarRing(st, "mana")
  -- Text anchored to the mana bar ('mana' slot) refreshes with its value, like health/power
  Client.CommonHookBarUpdate(bar, function() FrameBase.ApplyTexts(st, function(e) return VFS.Format.UsesMana(e.format) end) end)
end

local function ManaBarWanted(st)
  if not st.bars.mana or not DB.Frame("player").enabled or not DB.Global().druidManaBar then return false end
  if UnitHasVehicleUI and VFS.Util.Plain(UnitHasVehicleUI("player")) == true then return false end
  if PlayerFrame and PlayerFrame.activeAlternatePowerBar then return false end                      -- D8: Blizzard's own (Moonkin)
  local powerType = VFS.Util.PlainNumber(UnitPowerType("player"), nil)
  return powerType ~= nil and powerType ~= Client.MANA_POWER_TYPE
end

-- Show/hide + value. Returns true when visibility changed (caller re-lays out chrome and text).
function Player.ApplyManaBar(st)
  st = st or VFS.Frames.player
  local mana = st and st.bars.mana
  if not mana then return false end
  local show = ManaBarWanted(st)
  local changed = st.manaShown ~= show
  st.manaShown = show
  local a = show and 1 or 0
  mana.stock:SetAlpha(a); mana.backdrop:SetAlpha(a); mana.backdrop.ring:SetAlpha(a)
  local glowRing = st.chrome and st.chrome.glow and st.chrome.glow.rings and st.chrome.glow.rings.mana
  if glowRing then glowRing:SetAlpha(a) end
  if show then
    local cur, max = Client.ManaBarValues("player")
    mana.stock:SetMinMaxValues(0, (max and max > 0) and max or 1)
    mana.stock:SetValue(cur or 0)                       -- cur may be a secret: widget sink only
    FrameBase.ApplyManaColor(mana.stock)
  end
  if changed then
    st.slots.mana = show and mana.stock or nil
    local pb = FrameBase.Bar(st, "power")
    st.slots.below = show and mana.stock or (pb or FrameBase.Bar(st, "health"))
    if VFS.Chrome then VFS.Chrome.Layout(st) end
    FrameBase.ApplyTexts(st)
  end
  return changed
end

function Player.Create()
  local st = FrameBase.Acquire("player")
  if not st then return end
  CreateManaBar(st)
  PlaceBars(st)
  local hb, pb = FrameBase.Bar(st, "health"), FrameBase.Bar(st, "power")
  st.slots = { health = hb, power = pb, nameplate = hb and FrameBase.NameRowAbove(st, hb), above = hb, below = pb or hb, portrait = st.portraitBadge }
  FrameBase.HookCommon(st)
  -- Blizzard re-applies art and bar geometry here; re-assert ours after it
  for _, fn in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_UpdateArt", "PlayerFrame_UpdateHealthBarVisuals", "PlayerFrame_UpdateManaBarVisuals" }) do
    if _G[fn] then hooksecurefunc(fn, function() PlaceBars(st); FrameBase.Restyle("player"); Player.ApplyManaBar(st) end) end
  end
  -- The stock level text comes back after Blizzard's own level refresh on BOTH clients, by different routes:
  --   Forever: PlayerFrame_UpdateLevel resets text alpha to 1 without calling SetAlpha (verified in game).
  --   Era:     PlayerFrame_Update (UNIT_LEVEL / PLAYER_ENTERING_WORLD / ToPlayerArt) does
  --            PlayerLevelText:SetVertexColor(r, g, b, 1.0) - a vertex-alpha write our SetAlpha hook never sees
  --            (owner 2026-11-27: "12" under the badge on Era). Re-suppress after either. Visibility untouched.
  local function ResuppressLevel()
    if not DB.Frame("player").enabled then return end
    for _, region in ipairs(Client.StockLevelRegions("player")) do
      FrameBase.SetChromeSuppressed(region, "player", true)
    end
  end
  for _, fn in ipairs({ "PlayerFrame_UpdateLevel", "PlayerFrame_Update" }) do
    if _G[fn] then hooksecurefunc(fn, ResuppressLevel) end
  end
  FrameBase.Restyle("player")
  Player.ApplyManaBar(st)
  return st
end

function Player.OnEvent(event, unit)
  local st = VFS.Frames.player
  if not st then return end
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then FrameBase.OnCombatChanged(st) end
  if event == "UNIT_LEVEL" or event == "PLAYER_LEVEL_UP" or event == "UNIT_NAME_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    FrameBase.ApplyTexts(st)
  end
  -- Druid mana bar (SPECS/14 D7): value events while shown; form / vehicle / entering-world decide visibility.
  if st.bars.mana then
    if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER") and unit == "player" then
      if st.manaShown then Player.ApplyManaBar(st) end
    elseif (event == "UNIT_DISPLAYPOWER" and unit == "player") or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD"
        or ((event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and unit == "player") then
      Player.ApplyManaBar(st)
    end
  end
end