-- Velocity Frame Style: shared helpers. Loads first.
local ADDON_NAME, NS = ...
NS.ADDON_NAME = ADDON_NAME
NS.features = {}

local Util = {}
NS.Util = Util

local PREFIX = "|cff7fd4ffVFS|r: "

function Util.Print(fmt, ...)
  if select("#", ...) > 0 then fmt = string.format(fmt, ...) end
  print(PREFIX .. tostring(fmt))
end

function Util.DumpHeader(title) print("|cffabd473====== " .. tostring(title) .. " ======|r") end
function Util.DumpFooter(title) print("|cffabd473====== end " .. tostring(title) .. " ======|r") end

local warned = {}
function Util.WarnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  Util.Print("|cffff4040warning|r " .. tostring(msg))
end

-- Report a caught error through the client's error handler (BugSack etc.) without unwinding the caller.
function Util.Raise(context, err)
  local msg = string.format("%s: %s: %s", ADDON_NAME, tostring(context), tostring(err))
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(msg) else error(msg, 0) end
end

-- pcall wrapper that reports once per context key and returns ok.
function Util.Safe(context, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then Util.WarnOnce("safe:" .. context, context .. ": " .. tostring(err)) end
  return ok
end

function Util.Clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function Util.DeepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Util.DeepCopy(v) end
  return out
end

-- Fill dst from defaults where missing (deep for nested tables).
function Util.ApplyDefaults(dst, defaults)
  for k, v in pairs(defaults) do
    if dst[k] == nil then
      dst[k] = Util.DeepCopy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" then
      Util.ApplyDefaults(dst[k], v)
    end
  end
  return dst
end

-- true when the value is a Forever secret value (hidden unit info); false everywhere else, including nil.
function Util.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

-- The value, or nil when it is secret.
function Util.Plain(v)
  if v == nil or Util.IsSecret(v) then return nil end
  return v
end

-- A number that is safe to do arithmetic on, or the fallback.
function Util.PlainNumber(v, fallback)
  if Util.IsSecret(v) or type(v) ~= "number" or v ~= v then return fallback end
  return v
end

function Util.ClientInfo()
  local version, build, _, interface = GetBuildInfo()
  return { Version = version, Build = build, Interface = tonumber(interface) or 0, Project = WOW_PROJECT_ID }
end

-- Blizzard font-family name -> file path. LibSharedMedia extends this at runtime when present.
Util.BLIZZARD_FONTS = {
  ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
  ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
  ["Skurri"]           = "Fonts\\SKURRI.TTF",
  ["Morpheus"]         = "Fonts\\MORPHEUS.TTF",
}

function Util.FontPath(family)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then
    local p = LSM:Fetch("font", family, true)
    if p then return p end
  end
  return Util.BLIZZARD_FONTS[family] or Util.BLIZZARD_FONTS["Friz Quadrata TT"]
end

function Util.StatusBarPath(key)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM and key and key ~= "Blizzard" then
    local p = LSM:Fetch("statusbar", key, true)
    if p then return p end
  end
  return "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Apply a {family,size,style} record to a FontString.
function Util.ApplyFont(fs, rec)
  local ok = fs:SetFont(Util.FontPath(rec.family), rec.size or 10, rec.style or "")
  if not ok then fs:SetFont(Util.BLIZZARD_FONTS["Friz Quadrata TT"], rec.size or 10, rec.style or "") end
end