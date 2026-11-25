-- Velocity Frame Style: WoW Forever (16001) client. Mainline frame structure (parentKeys) with Camelot OnLoad
-- overrides; unit numbers may be secret. Paths from _EXTERNAL_APIS\wow_unitframe_regions_forever_vs_era.md.
-- Every region goes through Client.Path so a Blizzard rename degrades to nil (= stock), never a Lua error.
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

-- Mainline containers
local function PlayerMain() return P(PlayerFrame, "PlayerFrameContent.PlayerFrameContentMain") end
local function TargetMain() return P(TargetFrame, "TargetFrameContent.TargetFrameContentMain") end
local function TargetContextual() return P(TargetFrame, "TargetFrameContent.TargetFrameContentContextual") end

local function List(...)
  local out = {}
  for i = 1, select("#", ...) do local r = select(i, ...); if r then out[#out + 1] = r end end
  return out
end

local function JoinName(name, surname)
  if name and surname and surname ~= "" then return name .. " " .. surname end
  return name or ""
end

local function HealthValues(unit)
  local cur, max, pct = Client.CommonHealth(unit)
  if pct then return cur, max, pct end
  if UnitHealthPercent and CurveConstants and CurveConstants.ZeroToOne then
    local ok, p = pcall(UnitHealthPercent, unit, true, CurveConstants.ZeroToOne)
    if ok then p = Util.PlainNumber(p, nil); if p then return nil, nil, p end end
  end
  return cur, max, nil
end

VFS.ClientFlavours.forever = {
  HasFocusFrame = function() return FocusFrame ~= nil end,
  HasBossFrames = function() return Boss1TargetFrame ~= nil end,
  HasSecretValues = function() return true end,
  EditModeHint = function() return "Right-click your portrait and choose Edit Mode, or press Escape > Edit Mode." end,

  UnitButton = Root,
  Unit = function(id) return UNITS[id] end,

  HealthBar = function(id)
    if id == "player" then return P(PlayerMain(), "HealthBarsContainer.HealthBar")
    elseif id == "target" then return P(TargetMain(), "HealthBarsContainer.HealthBar")
    elseif id == "pet" then return PetFrameHealthBar
    elseif id == "pettarget" then local f = Root(id); return f and f.health end
  end,
  PowerBar = function(id)
    if id == "player" then return P(PlayerMain(), "ManaBarArea.ManaBar")
    elseif id == "target" then return P(TargetMain(), "ManaBar")
    elseif id == "pet" then return PetFrameManaBar
    elseif id == "pettarget" then local f = Root(id); return f and f.power end
  end,
  FrameArt = function(id)
    if id == "player" then return P(PlayerFrame, "PlayerFrameContainer.FrameTexture")
    elseif id == "target" then return P(TargetFrame, "TargetFrameContainer.FrameTexture")
    elseif id == "pet" then return PetFrameTexture
    elseif id == "pettarget" then local f = Root(id); return f and f.texture end
  end,
  Portrait = function(id)
    if id == "player" then return P(PlayerFrame, "PlayerFrameContainer.PlayerPortrait")
    elseif id == "target" then return P(TargetFrame, "TargetFrameContainer.Portrait")
    elseif id == "pet" then return PetPortrait
    elseif id == "pettarget" then local f = Root(id); return f and f.portrait end
  end,
  NameText = function(id)
    if id == "player" then return PlayerName
    elseif id == "target" then return P(TargetMain(), "Name")
    elseif id == "pet" then return PetName
    elseif id == "pettarget" then local f = Root(id); return f and f.name end
  end,
  HealthTexts = function(id)
    if id == "player" then local c = P(PlayerMain(), "HealthBarsContainer"); return List(c and c.HealthBarText, c and c.LeftText, c and c.RightText)
    elseif id == "target" then local c = P(TargetMain(), "HealthBarsContainer"); return List(c and c.HealthBarText, c and c.LeftText, c and c.RightText, c and c.DeadText)
    elseif id == "pet" then return List(PetFrameHealthBarText, PetFrameHealthBarTextLeft, PetFrameHealthBarTextRight)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.healthText, f and f.deadText) end
    return {}
  end,
  PowerTexts = function(id)
    if id == "player" then local m = P(PlayerMain(), "ManaBarArea.ManaBar"); return List(m and m.ManaBarText, m and m.LeftText, m and m.RightText)
    elseif id == "target" then local m = P(TargetMain(), "ManaBar"); return List(m and m.ManaBarText, m and m.LeftText, m and m.RightText)
    elseif id == "pet" then return List(PetFrameManaBarText, PetFrameManaBarTextLeft, PetFrameManaBarTextRight)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.powerText) end
    return {}
  end,
  StockLevelRegions = function(id)
    if id == "player" then return List(PlayerLevelText)
    elseif id == "target" then return List(P(TargetMain(), "LevelText"), P(TargetMain(), "LevelBackgroundCircle"))
    elseif id == "pettarget" then local f = Root(id); return List(f and f.level) end
    return {}   -- pet: Blizzard has no level region
  end,
  NameBackground = function(id)
    if id == "target" then return P(TargetMain(), "ReputationColor")
    elseif id == "pettarget" then local f = Root(id); return f and f.nameBackground end
  end,
  MovableBars = function() return {} end,   -- Forever: never move stock bars (masked, restricted); overlay strategy
  -- Camelot overrides size the HEALTH BAR taller than its container and clip it with a mask (PlayerFrame: 20 px bar
  -- in a 15 px container, TargetFrame: bar +3 px). The visible slot is the CONTAINER rect; our overlay fills that.
  BarSlot = function(id, kind)
    if kind == "health" then
      if id == "player" then return P(PlayerMain(), "HealthBarsContainer") end
      if id == "target" then return P(TargetMain(), "HealthBarsContainer") end
    end
    return (kind == "health") and VFS.Client.HealthBar(id) or VFS.Client.PowerBar(id)
  end,
  BarMask = function(id, kind)
    if kind == "health" then
      if id == "player" then return P(PlayerMain(), "HealthBarsContainer.HealthBarMask") end
      if id == "target" then return P(TargetMain(), "HealthBarsContainer.HealthBarMask") end
      if id == "pet" then return PetFrameHealthBarMask end
    else
      if id == "player" then return P(PlayerMain(), "ManaBarArea.ManaBar.ManaBarMask") end
      if id == "target" then return P(TargetMain(), "ManaBar.ManaBarMask") end
      if id == "pet" then return PetFrameManaBarMask end
    end
  end,
  -- Blizzard writes these from secure code with the game's own abbreviation; their content is a secret on Forever,
  -- so we never read it - we re-anchor and re-font the string itself (R5 coping pattern from PlateStyle).
  StockValueText = function(id, kind)
    if id == "player" then return kind == "health" and P(PlayerMain(), "HealthBarsContainer.HealthBarText") or P(PlayerMain(), "ManaBarArea.ManaBar.ManaBarText") end
    if id == "target" then return kind == "health" and P(TargetMain(), "HealthBarsContainer.HealthBarText") or P(TargetMain(), "ManaBar.ManaBarText") end
    if id == "pet" then return kind == "health" and PetFrameHealthBarText or PetFrameManaBarText end
    return nil   -- pettarget: our own frame, values are ours
  end,
  HookBarUpdate = function(id, kind, fn)
    local bar = (kind == "health") and VFS.Client.HealthBar(id) or VFS.Client.PowerBar(id)
    Client.CommonHookBarUpdate(bar, fn)
  end,

  UnitDisplayName = function(unit)
    if UnitIsPlayer(unit) and UnitNameUnmodified then
      local name, surname = UnitNameUnmodified(unit)
      if not Util.IsSecret(name) then return JoinName(name, Util.Plain(surname)) end
    end
    return UnitName(unit) or ""
  end,
  HealthValues = HealthValues,
  PowerValues = Client.CommonPower,
  UnitIsSameUnit = function(a, b)
    local same = UnitIsUnit(a, b)
    if Util.IsSecret(same) then return nil end
    return same == true
  end,
  DifficultyColor = Client.CommonDifficultyColor,
}