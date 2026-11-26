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

-- Every disc here is a GENERATED white/alpha shape (Scripts\GenerateRoundedBorderAtlas.cs -> VFS.RoundedShapes), tinted
-- at runtime. No Blizzard-owned art (TempPortraitAlphaMask) so colours are ours to change without new assets.
local function CIRCLE() return VFS.RoundedShapes.disc end
local function SOFT_DISC() return VFS.RoundedShapes.softDisc end

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

-- Combat glow thickness selects the FEATHERED glow atlas in FrameBase.CreateSurfaceBorder: same inner rounded rect as
-- the 4-unit black border, alpha fading to zero at 6 units, ADD-blended so it brightens the border and bleeds past it.
Chrome.COMBAT_OUTLINE_THICKNESS = VFS.FrameBase and VFS.FrameBase.COMBAT_GLOW_WIDTH or 6

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
  discSoft:SetTexture(SOFT_DISC())
  local disc = holder:CreateTexture(nil, "BACKGROUND", nil, -7)
  disc:SetTexture(CIRCLE())

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
  local gDisc = glowFrame:CreateTexture(nil, "ARTWORK"); gDisc:SetTexture(SOFT_DISC()); gDisc:SetBlendMode("ADD")
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
    if ring.SetBorderBlendMode then ring:SetBorderBlendMode("ADD") end
    local function SyncLevel()
      ring:SetFrameStrata(stock:GetFrameStrata())
      ring:SetFrameLevel(stock:GetFrameLevel() + (stock.vfsBorderLevelOffset or 1) + 1)
    end
    SyncLevel()
    hooksecurefunc(stock, "SetFrameLevel", SyncLevel)
    hooksecurefunc(stock, "SetFrameStrata", SyncLevel)
    rings[kind] = ring
  end

  -- THE FRAME-LEVEL STACK (owner, Era 2026-11-25). Texture draw layers cannot beat a higher frame level, so order is
  -- fixed with frame levels, lowest first:
  --   holder (plate disc)  <  glowFrame (portrait rim glow)  <  portraitLayer (portrait)  <  BARS + their borders
  --   <  bar glow rings  <  adornment (portrait rim + level badge)  <  host.top (text)
  -- The portrait therefore tucks UNDER the health/power bars where they overlap it, and the level badge sits above
  -- everything including both glows. Blizzard owns the bars' levels, so the portrait layer is pinned BELOW the lowest
  -- bar (and above the glow), and FrameBase.SyncAdornmentLevels pins the adornment above the highest glow ring.
  -- The portrait keeps its original visibility parent and anchors; only its drawing parent moves.
  if portrait then
    local originalParent = portrait:GetParent()
    local portraitLayer = CreateFrame("Frame", nil, originalParent)
    portraitLayer:SetAllPoints(originalParent)
    portraitLayer:EnableMouse(false)
    st.portraitLayer = portraitLayer
    local function LowestBarLevel()
      local lowest
      for _, bar in pairs(st.bars) do
        local lvl = bar.stock:GetFrameLevel()
        -- A bar's lower border (backdrop) sits at bar - 1; the portrait must be under THAT too.
        if bar.stock.vfsBackdrop then lvl = math.min(lvl, bar.stock.vfsBackdrop:GetFrameLevel()) end
        if not lowest or lvl < lowest then lowest = lvl end
      end
      return lowest
    end
    local function SyncPortraitLayer()
      portraitLayer:SetFrameStrata(glowFrame:GetFrameStrata())
      local above = math.max(originalParent:GetFrameLevel() + 1, glowFrame:GetFrameLevel() + 1)
      local below = LowestBarLevel()
      -- Prefer just under the bars; never drop below the glow (then the glow would cover the portrait).
      portraitLayer:SetFrameLevel(below and math.max(above, below - 1) or above)
      if below and portraitLayer:GetFrameLevel() >= below then
        -- No room between glow and bars: push the bars' stack up by raising nothing of Blizzard's - instead sink
        -- holder+glow one step so the portrait fits under the bars.
        holder:SetFrameLevel(math.max(0, holder:GetFrameLevel() - 1))
        glowFrame:SetFrameLevel(holder:GetFrameLevel() + 2)
        portraitLayer:SetFrameLevel(math.max(glowFrame:GetFrameLevel() + 1, below - 1))
      end
      -- Everything painted over the portrait (rim, level badge) must follow it up: one audited sync in FrameBase.
      VFS.FrameBase.SyncAdornmentLevels(st)
    end
    SyncPortraitLayer()
    portrait:SetParent(portraitLayer)
    -- The black rim rides the same layer as the portrait so it tucks under the bars with it.
    VFS.FrameBase.AttachPortraitRim(st, portraitLayer)
    VFS.FrameBase.SyncAdornmentLevels(st)
    hooksecurefunc(glowFrame, "SetFrameLevel", SyncPortraitLayer)
    hooksecurefunc(glowFrame, "SetFrameStrata", SyncPortraitLayer)
    hooksecurefunc(originalParent, "SetFrameLevel", SyncPortraitLayer)
    for _, bar in pairs(st.bars) do hooksecurefunc(bar.stock, "SetFrameLevel", SyncPortraitLayer) end
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
  -- Full alpha: the atlas carries the falloff and the frame animation carries the throb.
  for _, ring in pairs(c.glow.rings) do ring:SetBorderColor(gc[1], gc[2], gc[3], 1) end
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