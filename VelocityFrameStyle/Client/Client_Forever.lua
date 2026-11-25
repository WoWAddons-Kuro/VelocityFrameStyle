-- Velocity Frame Style: WoW Forever (16001) client. Mainline frame structure (parentKeys) with Camelot OnLoad
-- overrides; unit numbers may be secret. Paths from _EXTERNAL_APIS\wow_unitframe_regions_forever_vs_era.md.
-- Every region goes through Client.Path so a Blizzard rename degrades to nil (= stock), never a Lua error.
local ADDON_NAME, VFS = ...
local Client, Util = VFS.Client, VFS.Util
local P = Client.Path

local UNITS = { player = "player", target = "target", pet = "pet", pettarget = "pettarget", tot = "targettarget" }

local function Root(id)
  if id == "player" then return PlayerFrame
  elseif id == "target" then return TargetFrame
  elseif id == "pet" then return PetFrame
  elseif id == "tot" then return TargetFrameToT
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
  PredictionSegments = function(id)
    if id ~= "player" then return {} end -- first pass: player mana cost and incoming healing
    local container = P(PlayerMain(), "HealthBarsContainer")
    local health = container and container.HealthBar
    local power = P(PlayerMain(), "ManaBarArea.ManaBar")
    return {
      { key = "myHeal", kind = "health", bar = health, segment = health and health.MyHealPredictionBar, artMask = container and container.HealthBarMask },
      { key = "otherHeal", kind = "health", bar = health, segment = health and health.OtherHealPredictionBar, artMask = container and container.HealthBarMask },
      { key = "manaCost", kind = "power", bar = power, segment = power and power.ManaCostPredictionBar, artMask = power and power.ManaBarMask },
    }
  end,

  UnitButton = Root,
  Unit = function(id) return UNITS[id] end,

  HealthBar = function(id)
    if id == "player" then return P(PlayerMain(), "HealthBarsContainer.HealthBar")
    elseif id == "target" then return P(TargetMain(), "HealthBarsContainer.HealthBar")
    elseif id == "pet" then return PetFrameHealthBar
    elseif id == "tot" then return TargetFrameToT and TargetFrameToT.HealthBar
    elseif id == "pettarget" then local f = Root(id); return f and f.health end
  end,
  PowerBar = function(id)
    if id == "player" then return P(PlayerMain(), "ManaBarArea.ManaBar")
    elseif id == "target" then return P(TargetMain(), "ManaBar")
    elseif id == "pet" then return PetFrameManaBar
    elseif id == "tot" then return TargetFrameToT and TargetFrameToT.ManaBar
    elseif id == "pettarget" then local f = Root(id); return f and f.power end
  end,
  -- Geometric chrome (spec): every Blizzard art region we alpha-zero. The frame texture, flashes, status glow, level
  -- circle, reaction strip, the health container's black Background and the loss bars. Masks are not regions we touch.
  ChromeRegions = function(id)
    if id == "player" then
      local c, m = P(PlayerFrame, "PlayerFrameContainer"), PlayerMain()
      local hc = P(m, "HealthBarsContainer")
      return List(c and c.FrameTexture, c and c.FrameFlash, c and c.VehicleFrameTexture, c and c.AlternatePowerFrameTexture,
        m and m.StatusTexture, m and m.LevelBackgroundCircle,
        hc and hc.Background, hc and hc.HealthBar and hc.HealthBar.Background,
        hc and hc.PlayerFrameTempMaxHealthLoss, hc and hc.PlayerFrameHealthBarAnimatedLoss,
        P(PlayerFrame, "PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon"))
    elseif id == "target" then
      local c, m = P(TargetFrame, "TargetFrameContainer"), TargetMain()
      local hc = P(m, "HealthBarsContainer")
      return List(c and c.FrameTexture, c and c.Flash, c and c.BossPortraitFrameTexture,
        m and m.ReputationColor, m and m.LevelBackgroundCircle,
        hc and hc.Background, hc and hc.HealthBar and hc.HealthBar.Background, hc and hc.TempMaxHealthLoss)
    elseif id == "pet" then
      return List(PetFrameTexture, PetFrameFlash, PetAttackModeTexture)
    elseif id == "tot" then
      local t = TargetFrameToT; return List(t and t.FrameTexture)
    elseif id == "pettarget" then
      local f = Root(id); return List(f and f.texture, f and f.nameBackground)
    end
    return {}
  end,
  -- Blizzard art that STAYS (owner keep-list): rest zzz, combat swords, classification skull / dragons.
  KeepRegions = function(id)
    if id == "player" then
      local x = P(PlayerFrame, "PlayerFrameContent.PlayerFrameContentContextual")
      return List(x and x.PlayerRestLoop, x and x.AttackIcon)
    elseif id == "target" then
      local x = TargetContextual()
      return List(x and x.HighLevelTexture, x and x.BossIcon)
    end
    return {}
  end,
  ClassificationIcon = function(id)
    if id == "target" then return P(TargetContextual(), "HighLevelTexture") end
    if id == "pettarget" then local f = Root(id); return f and f.skull end
  end,
  Portrait = function(id)
    if id == "player" then return P(PlayerFrame, "PlayerFrameContainer.PlayerPortrait")
    elseif id == "target" then return P(TargetFrame, "TargetFrameContainer.Portrait")
    elseif id == "pet" then return PetPortrait
    elseif id == "tot" then return TargetFrameToT and TargetFrameToT.Portrait
    elseif id == "pettarget" then local f = Root(id); return f and f.portrait end
  end,
  NameText = function(id)
    if id == "player" then return PlayerName
    elseif id == "target" then return P(TargetMain(), "Name")
    elseif id == "pet" then return PetName
    elseif id == "tot" then return TargetFrameToT and TargetFrameToT.Name
    elseif id == "pettarget" then local f = Root(id); return f and f.name end
  end,
  HealthTexts = function(id)
    if id == "player" then local c = P(PlayerMain(), "HealthBarsContainer"); return List(c and c.HealthBarText, c and c.LeftText, c and c.RightText)
    elseif id == "target" then local c = P(TargetMain(), "HealthBarsContainer"); return List(c and c.HealthBarText, c and c.LeftText, c and c.RightText, c and c.DeadText)
    elseif id == "pet" then return List(PetFrameHealthBarText, PetFrameHealthBarTextLeft, PetFrameHealthBarTextRight)
    elseif id == "tot" then local t = TargetFrameToT; return List(t and t.DeadText, t and t.HealthBar and t.HealthBar.TextString)
    elseif id == "pettarget" then local f = Root(id); return List(f and f.healthText, f and f.deadText) end
    return {}
  end,
  PowerTexts = function(id)
    if id == "player" then local m = P(PlayerMain(), "ManaBarArea.ManaBar"); return List(m and m.ManaBarText, m and m.LeftText, m and m.RightText)
    elseif id == "target" then local m = P(TargetMain(), "ManaBar"); return List(m and m.ManaBarText, m and m.LeftText, m and m.RightText)
    elseif id == "pet" then return List(PetFrameManaBarText, PetFrameManaBarTextLeft, PetFrameManaBarTextRight)
    elseif id == "tot" then local t = TargetFrameToT; return List(t and t.ManaBar and t.ManaBar.TextString)
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
  -- Geometric chrome (spec): the stock bars are ours to size and anchor on Forever too. SetHeight/SetPoint on the
  -- bar frames is unprotected (EasyFrames-Forever does exactly this); only MEASURING a few restricted regions is not.
  -- pettarget bars are ours already and are placed by Frames\PetTarget.lua.
  MovableBars = function(id)
    local out = {}
    if id ~= "pettarget" then
      local h, p = VFS.Client.HealthBar(id), VFS.Client.PowerBar(id)
      if h then out[h] = true end
      if p then out[p] = true end
    end
    return out
  end,
  -- Blizzard writes these from secure code with the game's own abbreviation; their content is a secret on Forever,
  -- so we never read it - we re-anchor and re-font the string itself (R5 coping pattern from PlateStyle).
  StockValueText = function(id, kind)
    if id == "player" then return kind == "health" and P(PlayerMain(), "HealthBarsContainer.HealthBarText") or P(PlayerMain(), "ManaBarArea.ManaBar.ManaBarText") end
    if id == "target" then return kind == "health" and P(TargetMain(), "HealthBarsContainer.HealthBarText") or P(TargetMain(), "ManaBar.ManaBarText") end
    if id == "pet" then return kind == "health" and PetFrameHealthBarText or PetFrameManaBarText end
    return nil   -- pettarget: our own frame, values are ours
  end,
  HasPowerResource = function(unit)
    local powerType = Util.PlainNumber(UnitPowerType(unit), nil)
    if UnitHasPowerType and powerType then
      local ok, hasPower = pcall(UnitHasPowerType, unit, powerType)
      if ok and not Util.IsSecret(hasPower) and type(hasPower) == "boolean" then return hasPower end
    end
    -- Older client builds may lack the presence API. Only use readable capacity;
    -- never feed secrets to the generic Lua TextStatusBar updater.
    local maximum = Util.PlainNumber(UnitPowerMax(unit), nil)
    if maximum ~= nil then return maximum > 0 end
    return nil
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
  -- Same API path as the installed Forever EasyFrames: secret numbers go only
  -- through Blizzard formatters, then straight to SetText. Never inspect the result.
  FormatBarValue = function(unit, kind, mode)
    local isHealth = kind == "health"
    local maximum
    if isHealth then maximum = UnitHealthMax(unit) else maximum = UnitPowerMax(unit) end
    local plainMax = Util.PlainNumber(maximum, nil)
    if not isHealth and plainMax and plainMax <= 0 then return "", false end
    if mode == "percent" then
      if plainMax and plainMax <= 0 then return "0%", true end
      if not (CurveConstants and CurveConstants.ScaleTo100 and C_StringUtil and C_StringUtil.RoundToNearestString) then return "", false end
      local percent
      if isHealth then
        if not UnitHealthPercent then return "", false end
        percent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
      else
        if not UnitPowerPercent then return "", false end
        percent = UnitPowerPercent(unit, nil, false, CurveConstants.ScaleTo100)
      end
      return C_StringUtil.RoundToNearestString(percent) .. "%", true
    end
    local current
    if isHealth then current = UnitHealth(unit) else current = UnitPower(unit) end
    local numberText = AbbreviateNumbers or BreakUpLargeNumbers
    if mode == "current_max" then return numberText(current) .. " / " .. numberText(maximum), true end
    return numberText(current), true
  end,
  PowerValues = Client.CommonPower,
  UnitIsSameUnit = function(a, b)
    local same = UnitIsUnit(a, b)
    if Util.IsSecret(same) then return nil end
    return same == true
  end,
  DifficultyColor = Client.CommonDifficultyColor,
}