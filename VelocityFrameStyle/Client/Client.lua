-- Velocity Frame Style: the client interface. Flavour files fill VFS.ClientFlavours; Client_Select binds one onto
-- VFS.Client. Everything that differs between Classic Era and WoW Forever lives behind these methods: frame region
-- paths (Era flat globals vs Forever Mainline parentKeys), capability flags, and unit-value shims (secret values).
-- Ground truth: AddonManagement\_EXTERNAL_APIS\wow_unitframe_regions_forever_vs_era.md
local ADDON_NAME, VFS = ...

local Client = {}
VFS.Client = Client
VFS.ClientFlavours = {}

-- VFS_FrameID: "player" | "target" | "pet" | "pettarget"   (M3: "tot", "party1".."party4", "focus", "boss1".."boss5")
-- VFS_BarKind:  "health" | "power"

Client.INTERFACE = {
  -- Capabilities ---------------------------------------------------------------------------
  "HasFocusFrame",        -- () -> bool
  "HasBossFrames",        -- () -> bool
  "HasSecretValues",      -- () -> bool     Forever true: unit numbers may be secret (R5 gate)
  "EditModeHint",         -- () -> string   how to open Edit Mode on this client
  -- Frame roots ------------------------------------------------------------------------------
  "UnitButton",           -- (frameID) -> Button|nil      the secure unit button (PlayerFrame, TargetFrame, PetFrame)
  "Unit",                 -- (frameID) -> unitToken       "player" | "target" | "pet" | "pettarget"
  -- Regions (nil = this client has no such region; the feature degrades to stock) -------------
  "HealthBar",            -- (frameID) -> StatusBar|nil
  "PowerBar",             -- (frameID) -> StatusBar|nil
  "ChromeRegions",        -- (frameID) -> { Region, ... } every Blizzard art region we alpha-zero: frame texture, flash,
                          --                                status glow, level circle, reaction strip, container background, loss bars
  "KeepRegions",          -- (frameID) -> { Region, ... } Blizzard art that STAYS visible (spec keep-list): rest zzz,
                          --                                combat swords, skull / classification dragons
  "ClassificationIcon",   -- (frameID) -> Texture|nil     skull (HighLevelTexture) - re-anchored onto our level badge
  "Portrait",             -- (frameID) -> Texture|nil
  "NameText",             -- (frameID) -> FontString|nil  stock name (alpha-zeroed when our name element is active)
  "HealthTexts",          -- (frameID) -> { FontString, ... }  stock health strings (alpha-zeroed)
  "PowerTexts",           -- (frameID) -> { FontString, ... }  stock power strings (alpha-zeroed)
  "StockLevelRegions",    -- (frameID) -> { Region, ... }      stock level text + its circle art (alpha-zeroed)
  "NameBackground",       -- (frameID) -> Texture|nil     reaction-coloured strip (target); our 'nameplate' slot
  "MovableBars",          -- (frameID) -> { [StatusBar]=true }  stock bars Geometry may SetHeight/SetPoint (both clients;
                          --                                SetHeight/SetPoint on the bar frames is unprotected)
  "StockValueText",       -- (frameID, kind) -> FontString|nil  Blizzard's own centre value string for that bar. On
                          --   secret-value clients our health/power elements ADOPT it (its content is secure-written),
                          --   re-anchored and re-fonted. nil on clients where we compute the number ourselves.
  "HookBarUpdate",        -- (frameID, kind, fn) register fn(stockBar) after Blizzard updates that bar's value
  -- Values ------------------------------------------------------------------------------------
  "UnitDisplayName",      -- (unit) -> string      two-name aware (PROJECT_STRUCTURE two-names rule)
  "HealthValues",         -- (unit) -> cur|nil, max|nil, pct|nil
  "PowerValues",          -- (unit) -> cur|nil, max|nil, pct|nil, token|nil
  "UnitIsSameUnit",       -- (a, b) -> true|false|nil (nil = secret)
  "DifficultyColor",      -- (level) -> r, g, b
}

-- Shared helpers for the flavour files ---------------------------------------------------------

function Client.CommonHealth(unit)
  local Util = VFS.Util
  local cur = Util.PlainNumber(UnitHealth(unit), nil)
  local max = Util.PlainNumber(UnitHealthMax(unit), nil)
  local pct = (cur and max and max > 0) and (cur / max) or nil
  return cur, max, pct
end

function Client.CommonPower(unit)
  local Util = VFS.Util
  local cur = Util.PlainNumber(UnitPower(unit), nil)
  local max = Util.PlainNumber(UnitPowerMax(unit), nil)
  local pct = (cur and max and max > 0) and (cur / max) or nil
  local _, token = UnitPowerType(unit)
  return cur, max, pct, Util.Plain(token)
end

function Client.CommonDifficultyColor(level)
  local c = (GetCreatureDifficultyColor or GetRelativeDifficultyColor) and GetCreatureDifficultyColor(level)
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end

-- Walk a dotted path from a root table; nil on any missing step. Used by the flavour files so a Blizzard rename
-- degrades to 'stock' instead of a Lua error.
function Client.Path(root, dotted)
  local v = root
  for key in dotted:gmatch("[^.]+") do
    if type(v) ~= "table" then return nil end
    v = v[key]
  end
  return v
end

-- Generic 'after Blizzard updated this bar' hook: TextStatusBar bars call UpdateTextString from their OnValueChanged
-- on both clients, so hooking it per bar object gives a value-change notification without reading unit numbers.
function Client.CommonHookBarUpdate(bar, fn)
  if not bar or bar.vfsHooked then return end
  bar.vfsHooked = true
  if bar.UpdateTextString then
    hooksecurefunc(bar, "UpdateTextString", function(b) fn(b) end)
  else
    bar:HookScript("OnValueChanged", function(b) fn(b) end)
  end
  bar:HookScript("OnMinMaxChanged", function(b) fn(b) end)
end