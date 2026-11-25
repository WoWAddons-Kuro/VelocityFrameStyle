-- Velocity Frame Style: GEOMETRIC chrome (spec §Chrome). No frame art: a near-black disc behind the portrait and a
-- near-black rounded plate behind the name row and bars, plus our own combat glow. Blizzard's art is alpha-zeroed
-- except the keep-list (rest zzz, combat swords, classification skull/dragons).
--
-- Draw order (EasyFrames look, owner 2026-11-25): disc < plate < portrait < bars < text. The disc tucks UNDER the
-- plate: the plate's left end overlaps the disc's right half; the portrait (Blizzard's masked texture) is above both.
--
-- VFS_Chrome = { holder = Frame, disc = Texture, discSoft = Texture, plate = Frame(BackdropTemplate), plateSoft = Frame,
--               glow = { disc = Texture, plate = Texture, anim = AnimationGroup } }
local ADDON_NAME, VFS = ...
local Util, Client, DB = VFS.Util, VFS.Client, VFS.DB

local Chrome = {}
VFS.Chrome = Chrome

local A = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\"
local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"   -- feathered-edge disc (ships in the client)
local ROUNDED_EDGE = A .. "rounded_edge.tga"                           -- 64x64 radius-12 rounded square: 9-slice edge+bg
local SOFT_DISC = A .. "soft_disc.tga"

-- Fixed M0 geometry per frame (EasyFrames-Forever constants; spec table). All relative to the unit button.
-- health/power: { width, height }; platePad: plate padding beyond the bars; nameRow: height of the name row above health.
-- discPad: disc radius beyond the portrait's half-size. plateOverlap: how far the plate's left end reaches into the disc
-- (as a fraction of the disc radius; 1.0 = to the disc centre).
-- With geometric chrome there is no art slot to fill, so power bars are the SAME width as the health bar and flush
-- under it (EF's wider power bars - 117 / 125 / 76 - were sized to EF's painted slots and read as misaligned here).
Chrome.LAYOUT = {
  player    = { health = { w = 113, h = 24 }, power = { w = 113, h = 12 }, nameRow = 12, platePad = 4, discPad = 5, plateOverlap = 1.0, side = "right" },
  target    = { health = { w = 113, h = 24 }, power = { w = 113, h = 12 }, nameRow = 12, platePad = 4, discPad = 5, plateOverlap = 1.0, side = "left" },
  pet       = { health = { w = 70,  h = 10 }, power = { w = 70,  h = 7 },  nameRow = 11, platePad = 3, discPad = 3, plateOverlap = 1.0, side = "right" },
  tot       = { health = { w = 70,  h = 10 }, power = { w = 70,  h = 7 },  nameRow = 11, platePad = 3, discPad = 3, plateOverlap = 1.0, side = "right" },
  pettarget = { health = { w = 119, h = 16 }, power = { w = 119, h = 10 }, nameRow = 12, platePad = 4, discPad = 5, plateOverlap = 1.0, side = "left" },
}
-- side = which side of the portrait the bars sit on: "right" (player/pet: portrait left) | "left" (target: portrait right)

local function PlateColor()
  local g = DB.Global()
  local c = g.plateColor or { 0.02, 0.02, 0.02 }
  return c[1], c[2], c[3], g.plateAlpha or 0.9
end

-- Build ------------------------------------------------------------------------------------------------
function Chrome.Create(st)
  if st.chrome then return st.chrome end
  local button = st.button
  local portrait = Client.Portrait(st.id)
  local hb = st.bars.health and st.bars.health.stock
  if not hb then return nil end
  -- Holder BELOW the stock bars (bar level - 2) so bars and their backdrops draw above the plate
  local holder = CreateFrame("Frame", nil, button)
  holder:SetAllPoints(button)
  holder:SetFrameStrata(hb:GetFrameStrata())
  holder:SetFrameLevel(math.max(0, hb:GetFrameLevel() - 3))

  -- Disc (BACKGROUND) and soft rim behind it
  local discSoft = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
  discSoft:SetTexture(SOFT_DISC)
  local disc = holder:CreateTexture(nil, "BACKGROUND", nil, -7)
  disc:SetTexture(CIRCLE)

  -- Plate: rounded rect, one frame level above the disc so it overlaps it (EF look); still under the bars
  local plate = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
  plate:SetFrameLevel(holder:GetFrameLevel() + 1)
  if plate.SetBackdrop then
    plate:SetBackdrop({ bgFile = WHITE8, edgeFile = ROUNDED_EDGE, edgeSize = 12, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  end
  local plateSoft = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
  plateSoft:SetFrameLevel(holder:GetFrameLevel())
  if plateSoft.SetBackdrop then
    plateSoft:SetBackdrop({ bgFile = WHITE8, edgeFile = ROUNDED_EDGE, edgeSize = 14, insets = { left = 7, right = 7, top = 7, bottom = 7 } })
  end

  -- Combat glow: ADD-blend copies of both shapes, animated alpha
  local glowFrame = CreateFrame("Frame", nil, holder)
  glowFrame:SetAllPoints(holder)
  glowFrame:SetFrameLevel(holder:GetFrameLevel() + 2)
  local gDisc = glowFrame:CreateTexture(nil, "ARTWORK"); gDisc:SetTexture(SOFT_DISC); gDisc:SetBlendMode("ADD")
  local gPlate = glowFrame:CreateTexture(nil, "ARTWORK"); gPlate:SetTexture(ROUNDED_EDGE); gPlate:SetBlendMode("ADD")
  glowFrame:SetAlpha(0)
  local anim = glowFrame:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local a1 = anim:CreateAnimation("Alpha"); a1:SetFromAlpha(0.35); a1:SetToAlpha(1); a1:SetDuration(0.8)

  st.chrome = { holder = holder, disc = disc, discSoft = discSoft, plate = plate, plateSoft = plateSoft,
                glow = { frame = glowFrame, disc = gDisc, plate = gPlate, anim = anim } }
  Chrome.Layout(st)
  Chrome.ApplyColors(st)
  return st.chrome
end

-- Layout --------------------------------------------------------------------------------------------------
function Chrome.Layout(st)
  local c = st.chrome; if not c then return end
  local L = Chrome.LAYOUT[st.id]; if not L then return end
  local portrait = Client.Portrait(st.id)
  local hb = st.bars.health and st.bars.health.stock
  local pb = st.bars.power and st.bars.power.stock
  if not portrait or not hb then return end

  -- Disc around the portrait
  local pw = portrait:GetWidth() or 60
  local r = pw / 2 + L.discPad
  c.disc:ClearAllPoints(); c.disc:SetPoint("CENTER", portrait, "CENTER"); c.disc:SetSize(r * 2, r * 2)
  c.discSoft:ClearAllPoints(); c.discSoft:SetPoint("CENTER", portrait, "CENTER"); c.discSoft:SetSize(r * 2 + 6, r * 2 + 6)
  c.glow.disc:ClearAllPoints(); c.glow.disc:SetPoint("CENTER", portrait, "CENTER"); c.glow.disc:SetSize(r * 2 + 10, r * 2 + 10)

  -- Plate: from the disc centre (overlap) to the bars' far edge, from the HEALTH BAR top to the lowest bar bottom.
  -- The name row sits ABOVE the plate on transparent background (owner 2026-11-25: "just the text above the fat
  -- healthbar's black border") - the plate never extends up through it.
  local pad = L.platePad
  local lowest = pb or hb
  c.plate:ClearAllPoints()
  local overlapX = r * (1 - L.plateOverlap)   -- 0 = reach the disc centre
  if L.side == "right" then
    c.plate:SetPoint("LEFT", portrait, "CENTER", overlapX, 0)
    c.plate:SetPoint("RIGHT", hb, "RIGHT", pad, 0)
  else
    c.plate:SetPoint("RIGHT", portrait, "CENTER", -overlapX, 0)
    c.plate:SetPoint("LEFT", hb, "LEFT", -pad, 0)
  end
  c.plate:SetPoint("TOP", hb, "TOP", 0, pad)
  c.plate:SetPoint("BOTTOM", lowest, "BOTTOM", 0, -pad)
  c.plateSoft:ClearAllPoints()
  c.plateSoft:SetPoint("TOPLEFT", c.plate, "TOPLEFT", -2, 2)
  c.plateSoft:SetPoint("BOTTOMRIGHT", c.plate, "BOTTOMRIGHT", 2, -2)
  c.glow.plate:ClearAllPoints()
  c.glow.plate:SetPoint("TOPLEFT", c.plate, "TOPLEFT", -4, 4)
  c.glow.plate:SetPoint("BOTTOMRIGHT", c.plate, "BOTTOMRIGHT", 4, -4)
end

function Chrome.ApplyColors(st)
  local c = st.chrome; if not c then return end
  local r, g, b, a = PlateColor()
  c.disc:SetVertexColor(r, g, b, a)
  c.discSoft:SetVertexColor(r, g, b, a * 0.35)
  if c.plate.SetBackdropColor then c.plate:SetBackdropColor(r, g, b, a); c.plate:SetBackdropBorderColor(r, g, b, a) end
  if c.plateSoft.SetBackdropColor then c.plateSoft:SetBackdropColor(r, g, b, a * 0.35); c.plateSoft:SetBackdropBorderColor(r, g, b, a * 0.35) end
  local gc = DB.Global().combatGlowColor or { 1, 0.1, 0.1 }
  c.glow.disc:SetVertexColor(gc[1], gc[2], gc[3], 0.7)
  c.glow.plate:SetVertexColor(gc[1], gc[2], gc[3], 0.7)
end

-- Combat glow: shown while the unit is in combat (same signal Blizzard's flash uses) -----------------------
function Chrome.UpdateCombat(st)
  local c = st.chrome; if not c then return end
  local on = DB.Frame(st.id).enabled and DB.Global().showCombatGlow ~= false and UnitExists(st.unit) and UnitAffectingCombat(st.unit) == true
  if on then
    if not c.glow.anim:IsPlaying() then c.glow.frame:SetAlpha(1); c.glow.anim:Play() end
  else
    if c.glow.anim:IsPlaying() then c.glow.anim:Stop() end
    c.glow.frame:SetAlpha(0)
  end
end

function Chrome.SetShown(st, shown)
  if st.chrome then st.chrome.holder:SetShown(shown) end
end