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
local WIDTH, PAD, GAP = 260, 12, 6
local FACE = 26
local BAR_H, XP_H, ROW = 10, 6, 13
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
local function Bar(parent, height)
  local sb = CreateFrame("StatusBar", nil, parent)
  sb:SetHeight(height)
  sb:SetMinMaxValues(0, 1); sb:SetValue(0)
  sb.bg = sb:CreateTexture(nil, "BACKGROUND", nil, -8); sb.bg:SetAllPoints(); sb.bg:SetColorTexture(0, 0, 0, 0.5)
  sb.border = VFS.FrameBase.CreateSurfaceBorder(parent, sb, VFS.FrameBase.BAR_BORDER_WIDTH)
  sb.border:SetFrameLevel(sb:GetFrameLevel() + 1)
  sb.marks = {}
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
  -- Row 1: face | mood name ........ value   (one line, baseline-aligned)
  frame.face = frame:CreateTexture(nil, "ARTWORK"); frame.face:SetTexture(HAPPINESS_TEX); frame.face:SetSize(FACE, FACE)
  frame.face:SetPoint("TOPLEFT", PAD, -PAD)
  frame.mood = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.mood:SetPoint("LEFT", frame.face, "RIGHT", GAP + 2, 0); frame.mood:SetJustifyH("LEFT")
  frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.value:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0); frame.value:SetPoint("TOP", frame.face, "TOP", 0, 0); frame.value:SetJustifyH("RIGHT")
  -- Row 2: percent + eta (left) ........ (right: nothing; keep one line, truncate)
  frame.detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.detail:SetPoint("TOPLEFT", frame.face, "BOTTOMLEFT", 0, -GAP); frame.detail:SetWidth(inner); frame.detail:SetJustifyH("LEFT")
  frame.detail:SetWordWrap(false); frame.detail:SetHeight(ROW)
  -- Row 3: happiness bar with floor ticks
  frame.happy = Bar(frame, BAR_H)
  frame.happy:SetPoint("TOPLEFT", frame.detail, "BOTTOMLEFT", barInset, -(GAP + barInset))
  frame.happy:SetPoint("RIGHT", frame, "RIGHT", -(PAD + barInset), 0)
  for i = 1, 2 do
    local m = frame.happy:CreateTexture(nil, "OVERLAY"); m:SetColorTexture(1, 1, 1, 0.7); m:SetSize(1, BAR_H)
    frame.happy.marks[i] = m
  end
  -- Row 4: damage / loyalty (left) ........ fed ago (right)
  frame.stats = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.stats:SetPoint("TOPLEFT", frame.happy, "BOTTOMLEFT", -barInset, -(GAP + barInset)); frame.stats:SetJustifyH("LEFT"); frame.stats:SetWordWrap(false)
  frame.fed = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.fed:SetPoint("TOPRIGHT", frame, "RIGHT", -PAD, 0); frame.fed:SetPoint("TOP", frame.stats, "TOP", 0, 0); frame.fed:SetJustifyH("RIGHT")
  -- Row 5: XP label | xp bar ........ xp text under the bar's right end
  frame.xpLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); frame.xpLabel:SetText("XP")
  frame.xpLabel:SetPoint("TOPLEFT", frame.stats, "BOTTOMLEFT", 0, -GAP)
  frame.xpLabel:SetWidth(22); frame.xpLabel:SetJustifyH("LEFT"); frame.xpLabel:SetHeight(ROW)
  frame.xp = Bar(frame, XP_H)
  frame.xp:SetPoint("LEFT", frame.xpLabel, "RIGHT", barInset, 0)
  frame.xp:SetPoint("RIGHT", frame, "RIGHT", -(PAD + barInset), 0)
  frame.xpText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.xpText:SetPoint("TOPRIGHT", frame.xp, "BOTTOMRIGHT", barInset, -(GAP + barInset) + 2); frame.xpText:SetJustifyH("RIGHT")
  -- Row 6: training points (full width, own row, hidden when zero)
  frame.tp = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.tp:SetPoint("TOPLEFT", frame.xpLabel, "BOTTOMLEFT", 0, -(GAP + barInset)); frame.tp:SetWidth(inner); frame.tp:SetJustifyH("LEFT"); frame.tp:SetWordWrap(false)
  -- Row 7: footer = reading tier, right-aligned, dim
  frame.foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.foot:SetJustifyH("RIGHT"); frame.foot:SetWordWrap(false)
  return frame
end

local function ApplyTheme()
  local g = DB.Global()
  local c = g.plateColor or { 0.02, 0.02, 0.02 }
  frame.bg:SetColorTexture(c[1], c[2], c[3], 0.92)
  local tex = Util.StatusBarPath(DB.Effective("pet", "barTexture"))
  frame.happy:SetStatusBarTexture(tex); frame.xp:SetStatusBarTexture(tex)
  frame.xp:SetStatusBarColor(0.67, 0.83, 0.45)   -- hunter green
  local font, style = DB.Effective("pet", "font"), DB.Effective("pet", "fontStyle")
  for _, fs in ipairs({ frame.mood, frame.value, frame.detail, frame.stats, frame.fed, frame.xpLabel, frame.xpText, frame.tp, frame.foot }) do
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

local function Refresh()
  if not frame or not frame:IsShown() or not state then return end
  local now = GetTime()
  PH.Update(state, PH.Read(now), now)
  local d = PH.Describe(state, now)
  frame.face:SetTexCoord(unpack(d.moodCoords))
  frame.mood:SetText(d.moodName); frame.mood:SetTextColor(unpack(d.moodColor))
  frame.value:SetText(d.valueText or ""); frame.value:SetTextColor(unpack(d.moodColor))
  -- Row 2: percent + eta only (one line). Row 4: damage + loyalty (left), fed-ago (right).
  local line2 = {}
  if d.pct then line2[#line2 + 1] = d.pct .. "%" end
  if d.etaText then line2[#line2 + 1] = d.etaText end
  frame.detail:SetText(table.concat(line2, "    "))
  local line4 = {}
  if d.damageText then line4[#line4 + 1] = d.damageText end
  if d.loyaltyText then line4[#line4 + 1] = d.loyaltyText end
  frame.stats:SetText(table.concat(line4, "    "))
  frame.fed:SetText(d.fedText or "")
  -- happiness bar
  if d.barFraction then
    frame.happy:SetValue(d.barFraction); frame.happy:SetStatusBarColor(unpack(d.moodColor))
    local w = frame.happy:GetWidth() or 0
    for i, m in ipairs(frame.happy.marks) do
      local f = d.floorFractions and d.floorFractions[i]
      m:SetShown(f ~= nil)
      if f then m:ClearAllPoints(); m:SetPoint("CENTER", frame.happy, "LEFT", w * f, 0) end
    end
  else
    frame.happy:SetValue(state.mood == 3 and 1 or state.mood == 2 and 0.5 or 0.15); frame.happy:SetStatusBarColor(unpack(d.moodColor))
    for _, m in ipairs(frame.happy.marks) do m:Hide() end
  end
  -- pet XP
  local cur, max = GetPetExperience and GetPetExperience()
  cur, max = Util.PlainNumber(cur, nil), Util.PlainNumber(max, nil)
  if cur and max and max > 0 then
    frame.xp:SetValue(cur / max)
    frame.xpText:SetText(string.format("%s / %s  (%d%%)", BreakUpLargeNumbers and BreakUpLargeNumbers(cur) or cur, BreakUpLargeNumbers and BreakUpLargeNumbers(max) or max, math.floor(cur / max * 100 + 0.5)))
  else
    frame.xp:SetValue(0); frame.xpText:SetText("")
  end
  frame.tp:SetText(TrainingPointsLine() or "")
  local hasTP = frame.tp:GetText() ~= ""
  frame.tp:SetShown(hasTP)
  frame.foot:SetText(d.tier == "exact" and "exact reading" or d.tier == "learned" and "learned from past feedings" or "")
  -- Footer hangs under whichever row is last (TP when shown, else the XP text), right-aligned to the panel.
  frame.foot:ClearAllPoints()
  frame.foot:SetPoint("TOPRIGHT", frame, "RIGHT", -PAD, 0)
  frame.foot:SetPoint("TOP", hasTP and frame.tp or frame.xpText, "BOTTOM", 0, -GAP)
  -- Height = stacked rows. barInset appears where a bar's rounded border needs clearance above/below it.
  local barInset = VFS.FrameBase.BAR_BORDER_WIDTH
  local h = PAD + FACE                                   -- row 1
    + GAP + ROW                                          -- row 2 detail
    + GAP + barInset + BAR_H + barInset + GAP + ROW      -- row 3 bar, row 4 stats
    + GAP + ROW                                          -- row 5 xp label/bar line
    + barInset + ROW                                     -- xp text under bar
    + (hasTP and (GAP + ROW) or 0)                       -- row 6
    + GAP + ROW + PAD                                    -- footer
  frame:SetHeight(h)
end

-- Show / hide --------------------------------------------------------------------------------------
local function CanShow()
  if InCombatLockdown() then return false end
  if DB.Global().petHappinessPanel == false then return false end
  if not Client.PetHappinessFrame() then return false end
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
  local petName = Util.Plain(UnitName("pet"))
  if not state or persistKey ~= petName then
    if state then SaveState() end
    state = LoadState(petName); persistKey = petName
    PH.MarkSummoned(state, GetTime() - PH.SUMMON_SETTLE_SEC)   -- hover is never mid-summon; read now
  end
  ApplyTheme()
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
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
local function HookTrigger(region)
  if not region or region.vfsHappinessHooked then return end
  region.vfsHappinessHooked = true
  if region.EnableMouse then region:EnableMouse(true) end
  region:HookScript("OnEnter", function(self) hovering = self; if GameTooltip:IsOwned(self) then GameTooltip:Hide() end; Panel.ShowAt(self) end)
  region:HookScript("OnLeave", function(self) if hovering == self then hovering = nil end; Panel.Hide() end)
end

-- Background model upkeep so the learned tier and the drain measurement progress while the panel is closed.
local events = CreateFrame("Frame")
local function OnEvent(_, event, arg1, _, spellID)
  if not state then
    local petName = Util.Plain(UnitName("pet"))
    if not petName or not Client.PetHappinessFrame() then return end
    state = LoadState(petName); persistKey = petName
  end
  local now = GetTime()
  if event == "UNIT_PET" then
    local petName = Util.Plain(UnitName("pet"))
    if petName and petName ~= persistKey then SaveState(); state = LoadState(petName); persistKey = petName end
    if UnitExists("pet") then PH.MarkSummoned(state, now) end
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
  HookTrigger(icon)
  local pet = VFS.Frames.pet
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
  -- a 10 s background poll keeps the drain measurement honest between events
  C_Timer.NewTicker(10, function() if state and not (frame and frame:IsShown()) then Util.Safe("pethappiness-poll", function() PH.Update(state, PH.Read(GetTime()), GetTime()) end) end end)
  VFS.features["PetHappinessPanel"] = true
  return true
end

function Panel.Status()
  if not state then return "pet happiness: no state" end
  local d = PH.Describe(state, GetTime())
  return string.format("pet happiness: %s tier=%s rate=%s floors=%s/%s samples=%d", d.moodName, tostring(d.tier),
    state.decayRatePerSec and string.format("%.4f/s", state.decayRatePerSec) or "unmeasured",
    state.happyFloor and string.format("%.2f", state.happyFloor) or "def", state.contentFloor and string.format("%.2f", state.contentFloor) or "def", #state.samples)
end