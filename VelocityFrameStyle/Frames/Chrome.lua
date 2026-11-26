-- Velocity Frame Style: portrait disc and combat glow. FrameBase owns each bar's
-- four-layer surface stack. No opaque card plate may cover those translucent surfaces.
--
-- The portrait stays above the glow. Combat glow = tinted duplicate of each bar's upper outline + portrait rim.
--
-- VFS_Chrome = { holder, disc, discSoft, plate (invisible stack envelope), glow = { frame, disc, rings = { [kind] = border }, anim } }
local ADDON_NAME, VFS = ...
local Util, Client, DB = VFS.Util, VFS.Client, VFS.DB

local Chrome = {}
VFS.Chrome = Chrome

local A = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"   -- feathered-edge disc (ships in the client)
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
  pettarget = { health = { w = 113, h = 24 }, power = { w = 113, h = 12 }, nameRow = 12, platePad = 4, discPad = 5, plateOverlap = 1.0, side = "left" },
}
-- side = which side of the portrait the bars sit on: "right" (player/pet: portrait left) | "left" (target: portrait right)

-- Combat outline thickness = the black border's thickness, so FrameBase.CreateSurfaceBorder picks the rounded atlas
-- renderer and the red ring has exactly the border's corner radii. (Was 2 = the square flat fallback.)
Chrome.COMBAT_OUTLINE_THICKNESS = VFS.FrameBase and VFS.FrameBase.BAR_BORDER_WIDTH or 6

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

  -- Geometry only: each bar now owns its border and translucent surface.
  -- This envelope remains solely to anchor the outer combat outline.
  local plate = CreateFrame("Frame", nil, holder)
  plate:EnableMouse(false)

  -- Circular portrait glow plus a throbbing tinted DUPLICATE of every bar's upper outline (owner, Era 2026-11-25): one
  -- glow ring per bar, same rounded atlas, same inner rect, drawn one level above that bar's black ring. Not an envelope
  -- around the whole stack - the glow matches the outlines that clip the bars. Rings are created per bar below; all of
  -- them live on glowFrame, whose alpha the bounce animation drives.
  local glowFrame = CreateFrame("Frame", nil, holder)
  glowFrame:SetAllPoints(holder)
  glowFrame:SetFrameLevel(holder:GetFrameLevel() + 2)
  local gDisc = glowFrame:CreateTexture(nil, "ARTWORK"); gDisc:SetTexture(SOFT_DISC); gDisc:SetBlendMode("ADD")
  glowFrame:SetAlpha(0)
  local anim = glowFrame:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local a1 = anim:CreateAnimation("Alpha"); a1:SetFromAlpha(0.35); a1:SetToAlpha(1); a1:SetDuration(0.8)
  -- Per-bar glow rings. Parented to glowFrame (inherits its alpha) but levelled with the bar so each sits just above
  -- that bar's upper black ring, which FrameBase keeps at bar level + vfsBorderLevelOffset (1, or 2 with predictions).
  local rings = {}
  for kind, bar in pairs(st.bars) do
    local stock = bar.stock
    local ring = VFS.FrameBase.CreateSurfaceBorder(glowFrame, stock, Chrome.COMBAT_OUTLINE_THICKNESS)
    local function SyncLevel()
      ring:SetFrameStrata(stock:GetFrameStrata())
      ring:SetFrameLevel(stock:GetFrameLevel() + (stock.vfsBorderLevelOffset or 1) + 1)
    end
    SyncLevel()
    hooksecurefunc(stock, "SetFrameLevel", SyncLevel)
    hooksecurefunc(stock, "SetFrameStrata", SyncLevel)
    rings[kind] = ring
  end

  -- Texture draw layers cannot beat a higher FRAME level. In particular pet and
  -- pet-target portraits belonged to the button itself, below our glow child.
  -- Keep the original visibility parent and anchors, but give the portrait its
  -- own layer above both glow shapes so only the exposed circular rim glows.
  if portrait then
    local originalParent = portrait:GetParent()
    local portraitLayer = CreateFrame("Frame", nil, originalParent)
    portraitLayer:SetAllPoints(originalParent)
    portraitLayer:EnableMouse(false)
    local function SyncPortraitLayer()
      portraitLayer:SetFrameStrata(glowFrame:GetFrameStrata())
      portraitLayer:SetFrameLevel(math.max(originalParent:GetFrameLevel() + 1, glowFrame:GetFrameLevel() + 1))
    end
    SyncPortraitLayer()
    portrait:SetParent(portraitLayer)
    hooksecurefunc(glowFrame, "SetFrameLevel", SyncPortraitLayer)
    hooksecurefunc(glowFrame, "SetFrameStrata", SyncPortraitLayer)
    hooksecurefunc(originalParent, "SetFrameLevel", SyncPortraitLayer)
  end

  st.chrome = { holder = holder, disc = disc, discSoft = discSoft, plate = plate,
                glow = { frame = glowFrame, disc = gDisc, rings = rings, anim = anim } }
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

  -- Invisible envelope for the combat outline: the actual bar stack plus its border.
  -- No opaque card-sized background behind the 30%-alpha individual bar surfaces.
  local pad = VFS.FrameBase.BAR_BORDER_WIDTH
  local lowest = (not st.powerAbsent and pb) or hb
  c.plate:ClearAllPoints()
  c.plate:SetPoint("TOPLEFT", hb, "TOPLEFT", -pad, pad)
  c.plate:SetPoint("BOTTOMRIGHT", lowest, "BOTTOMRIGHT", pad, -pad)
end

function Chrome.ApplyColors(st)
  local c = st.chrome; if not c then return end
  local r, g, b, a = PlateColor()
  c.disc:SetVertexColor(r, g, b, a)
  c.discSoft:SetVertexColor(r, g, b, a * 0.35)
  local gc = DB.Global().combatGlowColor or { 1, 0.1, 0.1 }
  c.glow.disc:SetVertexColor(gc[1], gc[2], gc[3], 0.7)
  for _, ring in pairs(c.glow.rings) do ring:SetBorderColor(gc[1], gc[2], gc[3], 0.7) end
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