-- Velocity Frame Style: WoW Forever (16001) client. Mainline frame structure (parentKeys) with Camelot OnLoad
-- overrides; unit numbers may be secret. Paths from _EXTERNAL_APIS\wow_unitframe_regions_forever_vs_era.md.
-- Every region goes through Client.Path so a Blizzard rename degrades to nil (= stock), never a Lua error.
local ADDON_NAME, VFS = ...
local Client, Util = VFS.Client, VFS.Util
local P = Client.Path

local UNITS = { player = "player", target = "target", pet = "pet", pettarget = "pettarget", tot = "targettarget",
  focus = "focus", focustarget = "focustarget" }

-- pettarget, tot, focus and focustarget are OUR frames (Frames\OwnedUnitFrame.lua, specs 11/12); every resolver returns
-- their regions. Focus is owned, NOT a restyle of Blizzard's FocusFrame (spec 12 "why owned"): FocusFrame is suppressed whole.
local function Owned(id)
  local o = VFS.OwnedUnitFrame and VFS.OwnedUnitFrame.Get(id)
  return o and o.frame
end
local OWNED = { pettarget = true, tot = true, focus = true, focustarget = true }
local function IsOwned(id) return OWNED[id] == true end

local function TargetLike(id) if id == "target" then return TargetFrame end end

local function Root(id)
  if id == "player" then return PlayerFrame
  elseif id == "pet" then return PetFrame
  elseif IsOwned(id) then return Owned(id)
  else return TargetLike(id) end
end

-- Mainline containers
local function PlayerMain() return P(PlayerFrame, "PlayerFrameContent.PlayerFrameContentMain") end
local function TargetMain(id) return P(TargetLike(id), "TargetFrameContent.TargetFrameContentMain") end
local function TargetContextual(id) return P(TargetLike(id), "TargetFrameContent.TargetFrameContentContextual") end
-- Blizzard's ToT child of Target and the owned id that replaces it
local function BlizzToT(id) if id == "target" then return TargetFrameToT, "tot" end end

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
  -- The FRAME exists on every client (TargetFrame.xml ships FocusFrame even on Era); the UNIT only exists where /focus
  -- is a real command (TBC+ rulesets). Owner dump on Era 2026-11-26: FocusFrame non-nil, SlashCmdList.FOCUS nil,
  -- UnitExists("focus") false after /focus. Test the command, not the frame.
  HasFocusFrame = function() return FocusFrame ~= nil and (SlashCmdList and SlashCmdList.FOCUS ~= nil or FocusUnit ~= nil) end,
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
    elseif TargetLike(id) then return P(TargetMain(id), "HealthBarsContainer.HealthBar")
    elseif id == "pet" then return PetFrameHealthBar
    elseif IsOwned(id) then local f = Root(id); return f and f.health end
  end,
  PowerBar = function(id)
    if id == "player" then return P(PlayerMain(), "ManaBarArea.ManaBar")
    elseif TargetLike(id) then return P(TargetMain(id), "ManaBar")
    elseif id == "pet" then return PetFrameManaBar
    elseif IsOwned(id) then local f = Root(id); return f and f.power end
  end,
  -- Geometric chrome (spec): every Blizzard art region we alpha-zero. The frame texture, flashes, status glow, level
  -- circle, reaction strip, the health container's black Background and the loss bars. Masks are not regions we touch.
  -- Blizzard's own ToT (replaced by our owned frame, spec 11) is suppressed as Target chrome: never Hide() it.
  ChromeRegions = function(id)
    if id == "player" then
      local c, m = P(PlayerFrame, "PlayerFrameContainer"), PlayerMain()
      local hc = P(m, "HealthBarsContainer")
      return List(c and c.FrameTexture, c and c.FrameFlash, c and c.VehicleFrameTexture, c and c.AlternatePowerFrameTexture,
        m and m.StatusTexture, m and m.LevelBackgroundCircle,
        hc and hc.Background, hc and hc.HealthBar and hc.HealthBar.Background,
        hc and hc.PlayerFrameTempMaxHealthLoss, hc and hc.PlayerFrameHealthBarAnimatedLoss,
        P(PlayerFrame, "PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon"))
    elseif TargetLike(id) then
      local c, m = P(TargetLike(id), "TargetFrameContainer"), TargetMain(id)
      local hc = P(m, "HealthBarsContainer")
      local out = List(c and c.FrameTexture, c and c.Flash, c and c.BossPortraitFrameTexture,
        m and m.ReputationColor, m and m.LevelBackgroundCircle,
        hc and hc.Background, hc and hc.HealthBar and hc.HealthBar.Background, hc and hc.TempMaxHealthLoss)
      -- Blizzard's ToT child (TargetFrameToT / FocusFrameToT) is only chrome while OUR owned frame replaces it; with
      -- "Use Velocity Frame Style" off for that owned id, it must draw. Suppress the FRAME, not its textures: Blizzard
      -- keeps the frame shown and SetPortraitTexture (C side) repaints .Portrait at alpha 1 past any texture hook
      -- (owner, Forever 2026-11-26: FocusFrameToT:SetAlpha(0) killed the "double portrait"; .FrameTexture at 0 had not).
      -- Frame alpha is cosmetic and unprotected; Hide() would be protected and re-shown by Blizzard's Update.
      local t, ownedId = BlizzToT(id)
      if t and VFS.DB.Frame(ownedId).enabled then
        out[#out + 1] = t
      end
      return out
    elseif id == "pet" then
      return List(PetFrameTexture, PetFrameFlash, PetAttackModeTexture)
    elseif id == "focus" then
      -- Owned Focus (spec 12): Blizzard's FocusFrame is ONE chrome region, suppressed whole - frame alpha 0 cascades to
      -- every child incl. FocusFrameToT and holds (owner experiment 2026-11-26); a restyle failed because
      -- FocusFrameMixin:SetSmallSize rescales/re-anchors it. Never Hide() FocusFrame: protected and an Edit Mode system.
      local f = Root(id)
      return List(FocusFrame, f and f.texture, f and f.nameBackground)
    elseif IsOwned(id) then
      local f = Root(id); return List(f and f.texture, f and f.nameBackground)
    end
    return {}
  end,
  -- Blizzard art that STAYS (owner keep-list): rest zzz, combat swords, classification skull / dragons.
  KeepRegions = function(id)
    if id == "player" then
      local x = P(PlayerFrame, "PlayerFrameContent.PlayerFrameContentContextual")
      return List(x and x.PlayerRestLoop, x and x.AttackIcon)
    elseif TargetLike(id) then
      local x = TargetContextual(id)
      return List(x and x.HighLevelTexture, x and x.BossIcon)
    elseif id == "pet" then
      return List(VFS.Client.PetHappinessFrame())
    end
    return {}
  end,
  ClassificationIcon = function(id)
    if TargetLike(id) then return P(TargetContextual(id), "HighLevelTexture") end
    if IsOwned(id) then local f = Root(id); return f and f.skull end
  end,
  -- Forever (Camelot) keeps hunter-pet happiness and loyalty (owner screenshot 2026-11-26: "Happy - 125% damage -
  -- Gaining Loyalty" on the pet frame). Mainline_PetFrame.xml has no happiness region; Camelot injects it in code we
  -- have not fetched, so resolve the Era global first, then the plausible parentKeys. nil = no happiness on this build.
  -- The icon is re-anchored beside our bars (Frames\Pet.lua) but its stock tooltip is left alone: see below.
  PetHappinessFrame = function()
    return PetFrameHappiness or P(PetFrame, "Happiness") or P(PetFrame, "HappinessIcon") or P(PetFrame, "PetHappiness")
  end,
  -- /vfs pethappiness on Forever 2026-11-26: Enum.PowerType.Happiness=27, UnitPowerMax(pet,27)=1000 plain but
  -- UnitPower(pet,27) is SECRET. No drain, floors or countdown can be computed, so the happiness model is off here;
  -- the hover panel (level badge only) shows pet XP, and Blizzard's own icon tooltip keeps the mood/damage/diet text.
  HasReadablePetHappiness = function() return false end,
  PetExperience = function()
    if not GetPetExperience or not UnitExists("pet") then return nil end
    local _, isHunterPet = HasPetUI()
    if not isHunterPet then return nil end
    local cur, max = GetPetExperience()
    cur, max = Util.PlainNumber(cur, nil), Util.PlainNumber(max, nil)
    if cur and max and max > 0 then return cur, max end
    return nil
  end,
  Portrait = function(id)
    if id == "player" then return P(PlayerFrame, "PlayerFrameContainer.PlayerPortrait")
    elseif TargetLike(id) then return P(TargetLike(id), "TargetFrameContainer.Portrait")
    elseif id == "pet" then return PetPortrait
    elseif IsOwned(id) then local f = Root(id); return f and f.portrait end
  end,
  NameText = function(id)
    if id == "player" then return PlayerName
    elseif TargetLike(id) then return P(TargetMain(id), "Name")
    elseif id == "pet" then return PetName
    elseif IsOwned(id) then local f = Root(id); return f and f.name end
  end,
  HealthTexts = function(id)
    if id == "player" then local c = P(PlayerMain(), "HealthBarsContainer"); return List(c and c.HealthBarText, c and c.LeftText, c and c.RightText)
    elseif TargetLike(id) then local c = P(TargetMain(id), "HealthBarsContainer"); return List(c and c.HealthBarText, c and c.LeftText, c and c.RightText, c and c.DeadText)
    elseif id == "pet" then return List(PetFrameHealthBarText, PetFrameHealthBarTextLeft, PetFrameHealthBarTextRight)
    elseif IsOwned(id) then local f = Root(id); return List(f and f.healthText, f and f.deadText) end
    return {}
  end,
  PowerTexts = function(id)
    if id == "player" then local m = P(PlayerMain(), "ManaBarArea.ManaBar"); return List(m and m.ManaBarText, m and m.LeftText, m and m.RightText)
    elseif TargetLike(id) then local m = P(TargetMain(id), "ManaBar"); return List(m and m.ManaBarText, m and m.LeftText, m and m.RightText)
    elseif id == "pet" then return List(PetFrameManaBarText, PetFrameManaBarTextLeft, PetFrameManaBarTextRight)
    elseif IsOwned(id) then local f = Root(id); return List(f and f.powerText) end
    return {}
  end,
  StockLevelRegions = function(id)
    if id == "player" then return List(PlayerLevelText)
    elseif TargetLike(id) then return List(P(TargetMain(id), "LevelText"), P(TargetMain(id), "LevelBackgroundCircle"))
    elseif IsOwned(id) then local f = Root(id); return List(f and f.level) end
    return {}   -- pet: Blizzard has no level region
  end,
  NameBackground = function(id)
    if TargetLike(id) then return P(TargetMain(id), "ReputationColor")
    elseif IsOwned(id) then local f = Root(id); return f and f.nameBackground end
  end,
  -- Geometric chrome (spec): the stock bars are ours to size and anchor on Forever too. SetHeight/SetPoint on the
  -- bar frames is unprotected (EasyFrames-Forever does exactly this); only MEASURING a few restricted regions is not.
  -- Owned-frame bars (pettarget, tot) are ours already and are placed by Frames\OwnedUnitFrame.lua.
  MovableBars = function(id)
    local out = {}
    if not IsOwned(id) then
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
    if TargetLike(id) then return kind == "health" and P(TargetMain(id), "HealthBarsContainer.HealthBarText") or P(TargetMain(id), "ManaBar.ManaBarText") end
    if id == "pet" then return kind == "health" and PetFrameHealthBarText or PetFrameManaBarText end
    return nil   -- owned frames (pettarget, tot, focustarget): values are ours
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
  DifficultyColor = Client.CommonDifficultyColor,
}