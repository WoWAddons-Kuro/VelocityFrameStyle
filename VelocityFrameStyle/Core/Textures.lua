-- Velocity Frame Style: media catalogue. Built-in bar textures and fonts, plus everything LibSharedMedia-3.0 knows
-- when some other addon loaded it (we never ship or register into LSM). Consumed by UI\MediaPicker.lua and
-- Util.StatusBarPath / Util.FontPath. Keys are display names (VFS_TextureKey / VFS_FontKey).
local ADDON_NAME, VFS = ...
local Util = VFS.Util

local Textures = {}
VFS.Textures = Textures

Textures.BUILTIN_STATUSBAR = {
  ["Blizzard"]          = "Interface\\TargetingFrame\\UI-StatusBar",
  ["Blizzard Raid Bar"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
  ["Flat"]              = "Interface\\Buttons\\WHITE8x8",
  ["Smooth (Blizzard)"] = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
}

Textures.BUILTIN_FONT = Util.BLIZZARD_FONTS   -- name -> path

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- Sorted list of keys for a media kind: "statusbar" | "font"
function Textures.List(kind)
  local seen, out = {}, {}
  local builtin = kind == "font" and Textures.BUILTIN_FONT or Textures.BUILTIN_STATUSBAR
  for k in pairs(builtin) do seen[k] = true; out[#out + 1] = k end
  local lsm = LSM()
  if lsm then
    for _, k in ipairs(lsm:List(kind) or {}) do
      if not seen[k] then seen[k] = true; out[#out + 1] = k end
    end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

-- Path for a key; falls back to the built-in default when unknown.
function Textures.Path(kind, key)
  local builtin = kind == "font" and Textures.BUILTIN_FONT or Textures.BUILTIN_STATUSBAR
  if builtin[key] then return builtin[key] end
  local lsm = LSM()
  if lsm and key then
    local p = lsm:Fetch(kind, key, true)
    if p then return p end
  end
  return kind == "font" and Textures.BUILTIN_FONT["Friz Quadrata TT"] or Textures.BUILTIN_STATUSBAR["Blizzard"]
end

function Textures.HasLSM() return LSM() ~= nil end

-- Util hooks (Util loads first; wire the real catalogue in now)
function Util.StatusBarPath(key) return Textures.Path("statusbar", key) end
function Util.FontPath(key) return Textures.Path("font", key) end