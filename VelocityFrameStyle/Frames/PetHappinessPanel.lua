-- Velocity Frame Style: the hunter-pet happiness hover panel (SPECS/10_Pet_Happiness_Panel.md).
-- Shown OUT OF COMBAT while the mouse is over Blizzard's PetFrameHappiness icon or the Pet frame's level badge; hidden
-- the moment combat starts. Data comes from Core/PetHappiness.lua (exact tier on Era: the Happiness power type, a
-- measured drain and learned mood floors; learned tier otherwise). Method credit: HunterPetHappiness by Beleriand.
-- Era only: nothing here runs unless Client.PetHappinessFrame() exists and the pet is a hunter pet.
local ADDON_NAME, VFS = ...
local Util, Client, DB, PH = VFS.Util, VFS.Client, VFS.DB, VFS.PetHappiness

local Panel = {}
VFS.PetHappinessPanel = Panel

local HAPPINESS_TEX = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
-- Layout grid (owner, Era 2026-11-25: first cut had a wrapped detail line clipped by the bar, bars flush to the edge,
-- a floating value). Everything hangs off one left margin; bars are inset by their own border width so the rounded
-- border never touches the panel border; rows are fixed-height so nothing overlaps.
-- Second pass (owner): every bar draws its FULL extent in a medium grey under the fill so a partial fill never reads
-- as a broken bar; the happiness bar carries the time-to-next-segment INSIDE the segment currently draining (no
-- separate percent/eta line); the reading tier rides the mood line; the XP bar is full width with 5 divisions.
local WIDTH, PAD, GAP = 260, 12, 6
local FACE = 26
local BAR_H, XP_H, ROW = 14, 10, 13
local TRACK = { 0.28, 0.28, 0.30, 0.9 }   -- the unfilled extent of every bar: medium-dark grey, not black
local XP_COLOR = { 0.25, 0.45, 1.0 }       -- owner: XP fills blue
local frame, state, ticker, hovering
local persistKey

-- Persistence: learned values per pet name under VelocityFrameStyleDB.petHappiness ------------------------
local function Store()
  local db = VFS.db; if not db then return nil end
  db.petHappiness = type(db.petHappiness) == "table" and db.petHappiness or {}
  return db.petHappiness
end
local function LoadState(petName)
  local store = Store()
  local rec = store and petName and store[petName] or nil
  local st = PH.New(rec)
  -- restore wall-clock stamps if this is the same pet and less than 2 h have passed (HPH pattern)
  if rec and rec.fedEpoch and time() - rec.fedEpoch < 7200 then st.lastFedAt = GetTime() - (time() - rec.fedEpoch) end
  if rec and rec.happyEpoch and time() - rec.happyEpoch < 7200 then st.happySince = GetTime() - (time() - rec.happyEpoch) end
  return st
end
local function SaveState()
  local store = Store(); if not store or not persistKey or not state then return end
  local rec = PH.Persist(state)
  if state.lastFedAt then rec.fedEpoch = time() - (GetTime() - state.lastFedAt) end
  if state.happySince then rec.happyEpoch = time() - (GetTime() - state.happySince) end
  store[persistKey] = rec
end

-- Build ---------------------------------------------------------------------------------------------
-- A themed bar: grey full-extent track under the fill, our rounded border, `divisions` thin marks at fixed fractions
-- (nil = none; the happiness bar places its own marks at the learned floors) and an optional centred text.
local function Bar(parent, height, divisions)
  local sb = CreateFrame("StatusBar", nil, parent)
  sb:SetHeight(height)
  sb:SetMinMaxValues(0, 1); sb:SetValue(0)
  sb.bg = sb:CreateTexture(nil, "BACKGROUND", nil, -8); sb.bg:SetAllPoints(); sb.bg:SetColorTexture(unpack(TRACK))
  sb.border = VFS.FrameBase.CreateSurfaceBorder(parent, sb, VFS.FrameBase.BAR_BORDER_WIDTH)
  sb.border:SetFrameLevel(sb:GetFrameLevel() + 1)
  sb.marks = {}
  if divisions then
    for i = 1, divisions - 1 do
      local m = sb:CreateTexture(nil, "OVERLAY"); m:SetColorTexture(0, 0, 0, 0.6); m:SetSize(1, height)
      m:SetPoint("CENTER", sb, "LEFT", 0, 0)   -- x set once the bar has a width (Refresh)
      sb.marks[i] = { tex = m, frac = i / divisions }
    end
  end
  return sb
end

local function Build()
  if frame then return frame end
  frame = CreateFrame("Frame", "VelocityFrameStylePetHappinessPanel", UIParent)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetClampedToScreen(true)
  frame:SetWidth(WIDTH)
  frame:EnableMouse(false)
  frame:Hide()
  -- plate: our rounded border around a plate-coloured surface, like the bars
  frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8); frame.bg:SetAllPoints()
  frame.border = VFS.FrameBase.CreateSurfaceBorder(frame, frame, VFS.FrameBase.BAR_BORDER_WIDTH)

  local inner = WIDTH - 2 * PAD                       -- content width
  local barInset = VFS.FrameBase.BAR_BORDER_WIDTH     -- bars sit inside their own border width
  -- Row 1: face | mood name  (tier, dim) ........ value   (one line)
  frame.face = frame:CreateTexture(nil, "ARTWORK"); frame.face:SetTexture(HAPPINESS_TEX); frame.face:SetSize(FACE, FACE)
  frame.face:SetPoint("TOPLEFT", PAD, -PAD)
  frame.mood = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.mood:SetPoint("LEFT", frame.face, "RIGHT", GAP + 2, 0); frame.mood:SetJustifyH("LEFT")
  frame.tier = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.tier:SetPoint("BOTTOMLEFT", frame.mood, "BOTTOMRIGHT", GAP, 1); frame.tier:SetJustifyH("LEFT")
  frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.value:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0); frame.value:SetPoint("TOP", frame.face, "TOP", 0, 0); frame.value:SetJustifyH("RIGHT")
  -- Row 2: happiness bar. Floor ticks at the learned mood boundaries; the eta text sits INSIDE the draining segment.
  frame.happy = Bar(frame, BAR_H)
  frame.happy:SetPoint("TOPLEFT", frame.face, "BOTTOMLEFT", barInset, -(GAP + barInset))
  frame.happy:SetPoint("RIGHT", frame, "RIGHT", -(PAD + barInset), 0)
  frame.happy.floorMarks = {}
  for i = 1, 2 do
    local m = frame.happy:CreateTexture(nil, "OVERLAY"); m:SetColorTexture(0, 0, 0, 0.8); m:SetSize(1, BAR_H)
    frame.happy.floorMarks[i] = m
  end
  frame.eta = frame.happy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.eta:SetJustifyH("CENTER"); frame.eta:SetWordWrap(false)
  -- Row 3: full-width XP bar, blue fill on the grey track, 5 divisions, "cur / max (pct)" centred inside
  frame.xp = Bar(frame, XP_H, 5)
  frame.xp:SetPoint("TOPLEFT", frame.happy, "BOTTOMLEFT", 0, -(GAP + 2 * barInset))
  frame.xp:SetPoint("RIGHT", frame, "RIGHT", -(PAD + barInset), 0)
  frame.xpText = frame.xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.xpText:SetPoint("CENTER"); frame.xpText:SetJustifyH("CENTER"); frame.xpText:SetWordWrap(false)
  -- Row 4: training points (left) ........ damage % (right). The loyalty rate is dropped (owner).
  frame.tp = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.tp:SetPoint("TOPLEFT", frame.xp, "BOTTOMLEFT", -barInset, -(GAP + barInset)); frame.tp:SetJustifyH("LEFT"); frame.tp:SetWordWrap(false)
  frame.damage = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.damage:SetPoint("TOPRIGHT", frame, "RIGHT", -PAD, 0); frame.damage:SetPoint("TOP", frame.tp, "TOP", 0, 0); frame.damage:SetJustifyH("RIGHT")
  return frame
end

local function ApplyTheme()
  local g = DB.Global()
  local c = g.plateColor or { 0.02, 0.02, 0.02 }
  frame.bg:SetColorTexture(c[1], c[2], c[3], 0.72)   -- owner: 20% more see-through than the first 0.92
  local tex = Util.StatusBarPath(DB.Effective("pet", "barTexture"))
  frame.happy:SetStatusBarTexture(tex); frame.xp:SetStatusBarTexture(tex)
  frame.xp:SetStatusBarColor(unpack(XP_COLOR))
  local font, style = DB.Effective("pet", "font"), DB.Effective("pet", "fontStyle")
  for _, fs in ipairs({ frame.mood, frame.tier, frame.value, frame.eta, frame.xpText, frame.tp, frame.damage }) do
    local _, size = fs:GetFont()
    fs:SetFont(Util.FontPath(font), size or 10, style)
  end
end

-- Refresh ---------------------------------------------------------------------------------------
local function TrainingPointsLine()
  if not GetPetTrainingPoints then return nil end
  local total, spent = GetPetTrainingPoints()
  total, spent = Util.PlainNumber(total, 0), Util.PlainNumber(spent, 0)
  local unspent = total - spent
  if unspent <= 0 then return nil end
  -- Tiered colour (spec 10): BTT.Kuro's opt-in API when present, else green = "you have points to spend".
  local api = _G.BeastTrainingTrackerKuro_API
  if api and api.TeachableNow then
    local ok, count, cheapest = pcall(api.TeachableNow)
    if ok and type(count) == "number" then
      if count > 0 and (not cheapest or cheapest <= unspent) then return string.format("|cff40ff40%d training points - %d upgrade%s to teach|r", unspent, count, count == 1 and "" or "s") end
      return string.format("|cff9d9d9d%d training points - nothing to teach yet|r", unspent)
    end
  end
  return string.format("|cff40ff40%d training points unspent|r", unspent)
end

local function XpOnly() return not Client.HasReadablePetHappiness() end

-- Pet XP: blue fill on the grey track, 5 divisions, text centred. Shared by the full panel and the XP-only panel.
local function RefreshXp()
  local cur, max = Client.PetExperience()
  local xw = frame.xp:GetWidth() or 0
  for _, m in ipairs(frame.xp.marks) do m.tex:ClearAllPoints(); m.tex:SetPoint("CENTER", frame.xp, "LEFT", xw * m.frac, 0) end
  if cur then
    frame.xp:SetValue(cur / max)
    local fmt = BreakUpLargeNumbers or tostring
    frame.xpText:SetText(string.format("%s / %s   %d%%", fmt(cur), fmt(max), math.floor(cur / max * 100 + 0.5)))
  else
    frame.xp:SetValue(0); frame.xpText:SetText("XP unavailable")
  end
  if XpOnly() then
    local barInset = VFS.FrameBase.BAR_BORDER_WIDTH
    frame:SetHeight(PAD + barInset + XP_H + barInset + PAD)
  end
end

local function Refresh()
  if not frame or not frame:IsShown() or not state then return end
  local now = GetTime()
  PH.Update(state, PH.Read(now), now)
  local d = PH.Describe(state, now)
  -- No global "loading" gate (owner 2026-11-25: it stalled for ages because the background UNIT_PET handler kept
  -- re-arming the 5 s summon settle). Every row draws whatever it has; a row with nothing shows a quiet placeholder.
  frame.face:SetTexCoord(unpack(d.moodCoords))
  frame.mood:SetText(state.mood and d.moodName or "..."); frame.mood:SetTextColor(unpack(d.moodColor))
  frame.tier:SetText(d.tier == "exact" and "exact" or d.tier == "learned" and "learned" or "")
  frame.value:SetText(d.valueText or ""); frame.value:SetTextColor(unpack(d.moodColor))
  frame.damage:SetText(d.damageText or "")
  -- Happiness bar: fill on the grey track; floor ticks; the eta sits INSIDE the segment currently draining. Segment i
  -- spans [floor_i, floor_{i-1}) with floors { happy(2/3), content(1/3) } and the top at 1. "~m:ss" is the time until
  -- the fill drops to this segment's bottom edge = SecondsToNextMood (that IS the next mood boundary).
  local w = frame.happy:GetWidth() or 0
  if d.barFraction then
    frame.happy:SetValue(d.barFraction); frame.happy:SetStatusBarColor(unpack(d.moodColor))
    for i, m in ipairs(frame.happy.floorMarks) do
      local f = d.floorFractions and d.floorFractions[i]
      m:SetShown(f ~= nil)
      if f then m:ClearAllPoints(); m:SetPoint("CENTER", frame.happy, "LEFT", w * f, 0) end
    end
    -- segment bounds for the current mood
    local hi, lo = 1, 0
    if state.mood == 3 then lo = d.floorFractions[1]
    elseif state.mood == 2 then hi, lo = d.floorFractions[1], d.floorFractions[2]
    elseif state.mood == 1 then hi = d.floorFractions[2] end
    local eta = PH.SecondsToNextMood(state, now)
    local text = state.mood == 1 and "feed" or (eta and ("~" .. PH.FormatShort(eta))) or ""
    frame.eta:SetText(text)
    frame.eta:ClearAllPoints()
    frame.eta:SetPoint("CENTER", frame.happy, "LEFT", w * (lo + hi) / 2, 0)
    frame.eta:SetWidth(math.max(20, w * (hi - lo) - 4))
  else
    frame.happy:SetValue(state.mood == 3 and 1 or state.mood == 2 and 0.5 or 0.15); frame.happy:SetStatusBarColor(unpack(d.moodColor))
    for _, m in ipairs(frame.happy.floorMarks) do m:Hide() end
    frame.eta:ClearAllPoints(); frame.eta:SetPoint("CENTER"); frame.eta:SetWidth(w)
    frame.eta:SetText(d.etaText or "")
  end
  -- Pet XP: blue fill on the grey track, 5 divisions, text centred
  local cur, max = Client.PetExperience()
  local xw = frame.xp:GetWidth() or 0
  for _, m in ipairs(frame.xp.marks) do m.tex:ClearAllPoints(); m.tex:SetPoint("CENTER", frame.xp, "LEFT", xw * m.frac, 0) end
  if cur then
    frame.xp:SetValue(cur / max)
    local fmt = BreakUpLargeNumbers or tostring
    frame.xpText:SetText(string.format("%s / %s   %d%%", fmt(cur), fmt(max), math.floor(cur / max * 100 + 0.5)))
  else
    frame.xp:SetValue(0); frame.xpText:SetText("XP unavailable")
  end
  frame.tp:SetText(TrainingPointsLine() or "")
  local hasRow4 = frame.tp:GetText() ~= "" or frame.damage:GetText() ~= ""
  -- Height = stacked rows. barInset appears where a bar's rounded border needs clearance above/below it.
  local barInset = VFS.FrameBase.BAR_BORDER_WIDTH
  local h = PAD + FACE                                   -- row 1
    + GAP + barInset + BAR_H + barInset                  -- row 2 happiness bar
    + GAP + barInset + XP_H + barInset                   -- row 3 xp bar
    + (hasRow4 and (GAP + ROW) or 0)                     -- row 4 tp | damage
    + PAD
  frame:SetHeight(h)
end

-- Show / hide --------------------------------------------------------------------------------------
local function CanShow()
  if InCombatLockdown() then return false end
  if DB.Global().petHappinessPanel == false then return false end
  -- Optional gate: only while Shift is held, so a casual mouse-over of the pet frame does not pop the panel.
  if DB.Global().petHappinessPanelShiftOnly and not IsShiftKeyDown() then return false end
  if not Client.PetHappinessFrame() then return false end
  if XpOnly() then return Client.PetExperience() ~= nil end
  local r = PH.Read(GetTime())
  return r ~= nil
end

local function StartTicker()
  if ticker then return end
  ticker = C_Timer.NewTicker(1, function() Util.Safe("pethappiness-tick", Refresh) end)
end
local function StopTicker() if ticker then ticker:Cancel(); ticker = nil end end

function Panel.ShowAt(anchor)
  if not CanShow() then return end
  Build()
  ApplyTheme()
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  if XpOnly() then
    frame.face:Hide(); frame.mood:Hide(); frame.tier:Hide(); frame.value:Hide()
    frame.happy:Hide(); frame.happy.border:Hide(); frame.tp:Hide(); frame.damage:Hide()
    frame.xp:ClearAllPoints()
    frame.xp:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + VFS.FrameBase.BAR_BORDER_WIDTH, -(PAD + VFS.FrameBase.BAR_BORDER_WIDTH))
    frame.xp:SetPoint("RIGHT", frame, "RIGHT", -(PAD + VFS.FrameBase.BAR_BORDER_WIDTH), 0)
    frame:Show(); RefreshXp(); StartTicker()
    return
  end
  local petName = Util.Plain(UnitName("pet"))
  if not state or persistKey ~= petName then
    if state then SaveState() end
    state = LoadState(petName); persistKey = petName
    PH.MarkSummoned(state, GetTime() - PH.SUMMON_SETTLE_SEC)   -- hover is never mid-summon; read now
  end
  frame:Show()
  Refresh()
  StartTicker()
end

function Panel.Hide()
  if frame and frame:IsShown() then frame:Hide() end
  StopTicker()
  SaveState()
end

-- Wiring ----------------------------------------------------------------------------------------------
-- Shift-only mode: the panel must also appear when Shift is pressed AFTER the mouse is already over a trigger, and
-- vanish when it is released. MODIFIER_STATE_CHANGED fires on every Shift/Ctrl/Alt press and release; while a trigger
-- is hovered we re-evaluate CanShow against it. The event frame is registered once in Setup.
local function OnModifierChanged(key, down)
  if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
  if not hovering or not DB.Global().petHappinessPanelShiftOnly then return end
  if down == 1 then Panel.ShowAt(hovering) else Panel.Hide() end
end

local function HookTrigger(region)
  if not region or region.vfsHappinessHooked then return end
  region.vfsHappinessHooked = true
  if region.EnableMouse then region:EnableMouse(true) end
  region:HookScript("OnEnter", function(self) hovering = self; if GameTooltip:IsOwned(self) then GameTooltip:Hide() end; Panel.ShowAt(self) end)
  region:HookScript("OnLeave", function(self) if hovering == self then hovering = nil end; Panel.Hide() end)
end

-- Background model upkeep so the learned tier and the drain measurement progress while the panel is closed.
local events = CreateFrame("Frame")
-- arg2 is event-specific: MODIFIER_STATE_CHANGED -> down (1/0); UNIT_SPELLCAST_SUCCEEDED -> castGUID (spellID is arg3).
local function OnEvent(_, event, arg1, arg2, spellID)
  if event == "MODIFIER_STATE_CHANGED" then OnModifierChanged(arg1, arg2); return end
  if not state then
    local petName = Util.Plain(UnitName("pet"))
    if not petName or not Client.PetHappinessFrame() then return end
    state = LoadState(petName); persistKey = petName
  end
  local now = GetTime()
  if event == "UNIT_PET" then
    local petName = Util.Plain(UnitName("pet"))
    if petName and petName ~= persistKey then SaveState(); state = LoadState(petName); persistKey = petName end
    -- Only a NEW pet appearance starts the 5 s settle. UNIT_PET also fires for pet level-ups, stance changes etc.
    -- while the pet stays out; re-arming the settle on those is what stalled the panel.
    if UnitExists("pet") and not state.petWasOut then PH.MarkSummoned(state, now) end
    state.petWasOut = UnitExists("pet") and true or nil
  elseif event == "UNIT_HAPPINESS" or event == "UNIT_PET_EXPERIENCE" then
    PH.Update(state, PH.Read(now), now)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
    if spellID == 6991 then PH.MarkFed(state, now) elseif spellID == 2641 then PH.MarkDismissed(state) end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    PH.MarkZoned(state, now)
  elseif event == "PLAYER_REGEN_DISABLED" then
    Panel.Hide()
  elseif event == "PLAYER_LOGOUT" then
    SaveState()
  end
  if frame and frame:IsShown() then Refresh() end
end

function Panel.Setup()
  if not Client.PetHappinessFrame then return false end
  local icon = Client.PetHappinessFrame()
  if not icon then VFS.features["PetHappinessPanel"] = false; return false end
  local pet = VFS.Frames.pet
  -- Where the happiness value is secret (Forever) Blizzard's icon tooltip stays the only mood display; our panel is
  -- reached from the level badge only and shows pet XP alone.
  if XpOnly() then
    if pet and pet.portraitBadge then HookTrigger(pet.portraitBadge) end
    VFS.features["PetHappinessPanel"] = "xp-only"
    return true
  end
  HookTrigger(icon)
  if pet and pet.portraitBadge then HookTrigger(pet.portraitBadge) end
  events:SetScript("OnEvent", function(...) local ok, err = pcall(OnEvent, ...); if not ok then Util.Raise("pethappiness", err) end end)
  events:RegisterUnitEvent("UNIT_PET", "player")
  events:RegisterEvent("UNIT_HAPPINESS")
  events:RegisterEvent("UNIT_PET_EXPERIENCE")
  events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_LOGOUT")
  events:RegisterEvent("MODIFIER_STATE_CHANGED")   -- Shift-only mode: show/hide while a trigger is hovered
  -- a 10 s background poll keeps the drain measurement honest between events
  C_Timer.NewTicker(10, function() if state and not (frame and frame:IsShown()) then Util.Safe("pethappiness-poll", function() PH.Update(state, PH.Read(GetTime()), GetTime()) end) end end)
  VFS.features["PetHappinessPanel"] = true
  return true
end

function Panel.Status()
  if not state then return "pet happiness: no state" end
  local d = PH.Describe(state, GetTime())
  local xc, xm = Client.PetExperience()
  return string.format("pet happiness: %s tier=%s rate=%s floors=%s/%s samples=%d | xp=%s/%s", d.moodName, tostring(d.tier),
    state.decayRatePerSec and string.format("%.4f/s", state.decayRatePerSec) or "unmeasured",
    state.happyFloor and string.format("%.2f", state.happyFloor) or "def", state.contentFloor and string.format("%.2f", state.contentFloor) or "def", #state.samples, tostring(xc), tostring(xm))
end