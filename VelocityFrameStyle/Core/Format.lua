-- Velocity Frame Style: VFS_FormatString expansion for text elements.
-- Lifted from VelocityPlateStyle\Format.lua (keep the two in step; VFS is the source of truth from 2026-11-24).
--
-- A format string is player (or default) text containing tokens in square brackets. Every unit read goes through
-- VFS.Util.Plain (R8); a secret or missing value makes the token "" and an element whose whole expansion is ""
-- is hidden for that pass (Core\TextLayout.lua). Colour codes the player types (|cAARRGGBB ... |r) pass through.
--
-- Tokens:  [name] [level] [hp] [hp%] [hpmax] [power] [power%] [powermax] [class] [class+] [creature]
local ADDON_NAME, VFS = ...
local Util = VFS.Util
local Plain = Util.Plain

local Format = {}
VFS.Format = Format

Format.VALUE_FORMATS = { { "current", "Current" }, { "current_max", "Current / Max" }, { "percent", "Percent" } }
Format.FORMAT_TOKENS = {
  health = { current = "[hp]", current_max = "[hp] / [hpmax]", percent = "[hp%]" },
  power = { current = "[power]", current_max = "[power] / [powermax]", percent = "[power%]" },
  mana = { current = "[mana]", current_max = "[mana] / [manamax]", percent = "[mana%]" },   -- SPECS/14 druid forms
}
function Format.SetValueFormat(element, mode)
  local tokens = Format.FORMAT_TOKENS[element.id]
  if not tokens or not tokens[mode] then return end
  element.valueFormat, element.format = mode, tokens[mode]
end
function Format.SampleValue(kind, mode)
  local values = kind == "health" and { current = "1500", current_max = "1500 / 2000", percent = "75%" }
    or { current = "400", current_max = "400 / 1000", percent = "40%" }
  return values[mode] or values.current
end

Format.TOKENS = { "[name]", "[level]", "[hp]", "[hp%]", "[hpmax]", "[power]", "[power%]", "[powermax]", "[mana]", "[mana%]", "[manamax]",
  "[class]", "[class+]", "[creature]" }
Format.SKULL_TEXT = "??"
Format.SKULL_ICON = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t"

-- 709000 -> "709K", 1234567 -> "1.2M", 999 -> "999"
local function Abbreviate(n)
  if n >= 1e6 then return (string.format("%.1fM", n / 1e6):gsub("%.0M", "M")) end
  if n >= 1e4 then return string.format("%dK", math.floor(n / 1e3 + 0.5)) end
  if n >= 1e3 then return (string.format("%.1fK", n / 1e3):gsub("%.0K", "K")) end
  return tostring(math.floor(n + 0.5))
end
Format.Abbreviate = Abbreviate

local CLASSIFICATION_WORD = { elite = "elite", rare = "rare", rareelite = "rare elite", worldboss = "boss" }
local CLASSIFICATION_SUFFIX = { elite = "+", rare = "r", rareelite = "r+", worldboss = "??" }

-- Per-token resolvers: (unit) -> string. Always return a string ("" when unavailable).
local resolvers = {
  ["[name]"] = function(unit)
    local v = Plain(VFS.Client.UnitDisplayName(unit))
    return v or ""
  end,
  ["[level]"] = function(unit)
    local v = Util.PlainNumber(UnitLevel(unit), nil)
    if v == nil then return "" end
    if v < 0 then return Format.SKULL_TEXT end
    return tostring(v)
  end,
  ["[hp]"] = function(unit)
    local cur, _, pct = VFS.Client.HealthValues(unit)
    if cur then return Abbreviate(cur) end
    return ""
  end,
  ["[hpmax]"] = function(unit)
    local _, max = VFS.Client.HealthValues(unit)
    return max and Abbreviate(max) or ""
  end,
  ["[hp%]"] = function(unit)
    local _, _, pct = VFS.Client.HealthValues(unit)
    if not pct then return "" end
    return tostring(math.floor(pct * 100 + 0.5)) .. "%"
  end,
  ["[power]"] = function(unit)
    local cur, max = VFS.Client.PowerValues(unit)
    if not max or max <= 0 or not cur then return "" end
    return Abbreviate(cur)
  end,
  ["[powermax]"] = function(unit)
    local _, max = VFS.Client.PowerValues(unit)
    if not max or max <= 0 then return "" end
    return Abbreviate(max)
  end,
  ["[power%]"] = function(unit)
    local _, max, pct = VFS.Client.PowerValues(unit)
    if not max or max <= 0 or not pct then return "" end
    return tostring(math.floor(pct * 100 + 0.5)) .. "%"
  end,
  ["[class]"] = function(unit)
    local c = Plain(UnitClassification(unit))
    return c and CLASSIFICATION_WORD[c] or ""
  end,
  ["[class+]"] = function(unit)
    local c = Plain(UnitClassification(unit))
    return c and CLASSIFICATION_SUFFIX[c] or ""
  end,
  ["[creature]"] = function(unit)
    local v = Plain(UnitCreatureType(unit))
    return v or ""
  end,
  -- Druid mana pool regardless of display power (SPECS/14). Plain-only: Forever's current mana is a secret and
  -- these resolvers return "" for it; the Forever grid goes through Client.FormatBarValue("mana") instead.
  ["[mana]"] = function(unit)
    local cur = VFS.Client.ManaValues(unit)
    return cur and Abbreviate(cur) or ""
  end,
  ["[manamax]"] = function(unit)
    local _, max = VFS.Client.ManaValues(unit)
    return max and Abbreviate(max) or ""
  end,
  ["[mana%]"] = function(unit)
    local _, _, pct = VFS.Client.ManaValues(unit)
    if not pct then return "" end
    return tostring(math.floor(pct * 100 + 0.5)) .. "%"
  end,
}

-- Expands `format` for `unit`. Unknown [tokens] are left as typed.
function Format.Expand(format, unit)
  if type(format) ~= "string" or format == "" then return "" end
  return (format:gsub("%[[%w%%%+]+%]", function(token)
    local r = resolvers[token]
    if r then return r(unit) end
    return token
  end))
end

local function Has(format, ...)
  if type(format) ~= "string" then return false end
  for i = 1, select("#", ...) do if format:find(select(i, ...), 1, true) then return true end end
  return false
end

-- True when the format reads health (refresh on UNIT_HEALTH) / power (refresh on UNIT_POWER_UPDATE).
function Format.UsesHealth(format) return Has(format, "[hp]", "[hp%]", "[hpmax]") end
function Format.UsesPower(format) return Has(format, "[power]", "[power%]", "[powermax]") end
function Format.UsesMana(format) return Has(format, "[mana]", "[mana%]", "[manamax]") end

-- Exactly one [name] token: the only case where a secret name may be handed straight to SetText.
function Format.IsBareName(format) return format == "[name]" end

-- Expand but treat a whitespace-only result as empty.
function Format.ExpandOrEmpty(format, unit)
  local s = Format.Expand(format, unit)
  if s:match("^%s*$") then return "" end
  return s
end