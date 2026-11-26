-- Velocity Frame Style: Classic Era (11509) client. Flat classic globals (PlayerFrameHealthBar, TargetFrameTextureFrameName...),
-- one-name characters, no secret values. Bars are plain unmasked StatusBars, so the in-place geometry strategy applies
-- (MovableBars returns them). Paths from _EXTERNAL_APIS\wow_unitframe_regions_forever_vs_era.md.
local ADDON_NAME, VFS = ...
local Client, Util = VFS.Client, VFS.Util
local P = Client.Path

local UNITS = { player = "player", target = "target", pet = "pet", pettarget = "pettarget" }

local function Root(id)
  if id == "player" then return PlayerFrame
  elseif id == "target" then return TargetFrame
  elseif id == "pet" then return PetFrame
  elseif id == "pettarget" then return VFS.PetTarget and VFS.PetTarget.frame end
end

local function List(...)
  local out = {}
  for i = 1, select("#", ...) do local r = select(i, ...); if r then out[#out + 1] = r end end
  return out
end

-- Era TargetFrame keeps its texts on the textureFrame child (TargetFrame.textureFrame.HealthBarText etc.)
local function TargetTF() return TargetFrame and TargetFrame.textureFrame end

VFS.ClientFlavours.classic_era = {
  HasFocusFrame = function() return false end,
  HasBossFrames = function() return Boss1TargetFrame ~= nil end,
  HasSecretValues = function() return false end,
  PredictionSegments = function() return {} end, -- Era prediction adaptation is not yet audited
  EditModeHint = function() return "Press Escape and choose Edit Mode from the game menu." end,

  UnitButton = Root,
  Unit = function(id) return UNITS[id] end,

  HealthBar = function(id)
    if id == "player" then return PlayerFrameHealthBar
    elseif id == "target" then return TargetFrameHealthBar
    elseif id == "pet" then return PetFrameHealthBar
    elseif id == "pettarget" then local f = Root(id); return f and f.health end
  end,
  PowerBar = function(id)
    if id == "player" then return PlayerFrameManaBar
    elseif id == "target" then return TargetFrameManaBar
    elseif id == "pet" then return PetFrameManaBar
    elseif id == "pettarget" then local f = Root(id); return f and f.power end
  end,
  -- Geometric chrome: everything Blizzard draws as frame art, alpha-zeroed. Era flat names.
  ChromeRegions = function(id)
    if id == "player" then return List(PlayerFrameTexture, PlayerFrameFlash, PlayerStatusTexture, PlayerFrameBackground)
    elseif id == "target" then return List(TargetFrameTextureFrameTexture, TargetFrameFlash, TargetFrameNameBackground, TargetFrameBackground)
    elseif id == "pet" then return List(PetFrameTexture, PetFrameFlash, PetAttackModeTexture)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.texture, f and f.nameBackground) end
    return {}
  end,
  -- Keep-list: rest zzz, combat swords, skull, hunter-pet happiness (functional UI; placed by Frames\Pet.lua)
  KeepRegions = function(id)
    if id == "player" then return List(PlayerRestIcon, PlayerAttackIcon)
    elseif id == "target" then return List(TargetFrameTextureFrameHighLevelTexture)
    elseif id == "pet" then return List(PetFrameHappiness) end
    return {}
  end,
  ClassificationIcon = function(id)
    if id == "target" then return TargetFrameTextureFrameHighLevelTexture end
    if id == "pettarget" then local f = Root(id); return f and f.skull end
  end,
  PetHappinessFrame = function() return PetFrameHappiness end,
  Portrait = function(id)
    if id == "player" then return PlayerPortrait
    elseif id == "target" then return TargetFramePortrait
    elseif id == "pet" then return PetPortrait
    elseif id == "pettarget" then local f = Root(id); return f and f.portrait end
  end,
  NameText = function(id)
    if id == "player" then return PlayerName
    elseif id == "target" then return TargetFrameTextureFrameName or P(TargetTF(), "Name")
    elseif id == "pet" then return PetName
    elseif id == "pettarget" then local f = Root(id); return f and f.name end
  end,
  HealthTexts = function(id)
    if id == "player" then return List(PlayerFrameHealthBarText, PlayerFrameHealthBarTextLeft, PlayerFrameHealthBarTextRight, PlayerFrameHealthBar and PlayerFrameHealthBar.TextString)
    elseif id == "target" then local t = TargetTF(); return List(t and t.HealthBarText, t and t.HealthBarTextLeft, t and t.HealthBarTextRight, TargetFrameTextureFrameDeadText)
    elseif id == "pet" then return List(PetFrameHealthBarText, PetFrameHealthBarTextLeft, PetFrameHealthBarTextRight)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.healthText, f and f.deadText) end
    return {}
  end,
  PowerTexts = function(id)
    if id == "player" then return List(PlayerFrameManaBarText, PlayerFrameManaBarTextLeft, PlayerFrameManaBarTextRight, PlayerFrameManaBar and PlayerFrameManaBar.TextString)
    elseif id == "target" then local t = TargetTF(); return List(t and t.ManaBarText, t and t.ManaBarTextLeft, t and t.ManaBarTextRight)
    elseif id == "pet" then return List(PetFrameManaBarText, PetFrameManaBarTextLeft, PetFrameManaBarTextRight)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.powerText) end
    return {}
  end,
  StockLevelRegions = function(id)
    if id == "player" then return List(PlayerLevelText)
    elseif id == "target" then return List(TargetFrameTextureFrameLevelText)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.level) end
    return {}   -- pet: Blizzard has no level region
  end,
  NameBackground = function(id)
    if id == "target" then return TargetFrameNameBackground
    elseif id == "pettarget" then local f = Root(id); return f and f.nameBackground end
  end,
  -- Era: stock bars are plain children; the audited R2 exception may resize/re-anchor them (Core\Geometry.lua).
  MovableBars = function(id)
    local out = {}
    if id ~= "pettarget" then
      local h, p = VFS.Client.HealthBar(id), VFS.Client.PowerBar(id)
      if h then out[h] = true end
      if p then out[p] = true end
    end
    return out
  end,
  -- Era: no secret values; the grid computes [hp]/[power] itself, so there is no stock string to adopt.
  StockValueText = function() return nil end,
  HasPowerResource = function(unit) return UnitPowerMax(unit) > 0 end,
  HookBarUpdate = function(id, kind, fn)
    local bar = (kind == "health") and VFS.Client.HealthBar(id) or VFS.Client.PowerBar(id)
    Client.CommonHookBarUpdate(bar, fn)
  end,

  UnitDisplayName = function(unit) return UnitName(unit) or "" end,
  HealthValues = Client.CommonHealth,
  FormatBarValue = function(unit, kind, mode)
    local tokens = VFS.Format.FORMAT_TOKENS[kind]
    local text = VFS.Format.ExpandOrEmpty(tokens[mode] or tokens.current, unit)
    local maximum = kind == "health" and UnitHealthMax(unit) or UnitPowerMax(unit)
    if kind == "power" and maximum <= 0 then return "", false end
    return text, text ~= ""
  end,
  PowerValues = Client.CommonPower,
  DifficultyColor = Client.CommonDifficultyColor,
}