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
  -- Holder for the plate disc. Its level (and the portrait layer's and the glow's) is set by SyncPortraitLayer below,
  -- stacked DOWN from the lowest bar backdrop; the initial value here is a placeholder.
  local holder = CreateFrame("Frame", nil, button)
  holder:SetAllPoints(button)
  holder:SetFrameStrata(hb:GetFrameStrata())
  holder:SetFrameLevel(0)

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
  glowFrame:SetFrameLevel(2)   -- placeholder; SyncPortraitLayer sets the real level
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

  -- THE FRAME-LEVEL STACK (owner, Era 2026-11-25, measured with /vfs stack). Texture draw layers cannot beat a higher
  -- frame level, so order is fixed with frame levels, lowest first:
  --   holder (plate disc)  <  portraitLayer (portrait + black rim)  <  glowFrame (portrait rim glow)
  --   <  LOWEST BAR BACKDROP  <  bars  <  bar rings  <  bar glow rings  <  adornment (badge)  <  host.top (text)
  -- EVERYTHING in the portrait group - plate disc, portrait, its rim, its glow - lives BELOW the lowest bar backdrop,
  -- so the bars and the name banner always cover it. The earlier rule "portrait above glow, glow above holder" let the
  -- portrait float ABOVE the bars whenever Blizzard's bar level was low (Era: bars L1, backdrops L0): the pin was a
  -- no-op. Now the ceiling is the bar backdrop and the group is stacked DOWN from it. Levels can't go below 0, so when
  -- the backdrop is at 0 the group collapses onto 0 and relies on draw layers (plate BACKGROUND-8/-7, portrait BORDER,
  -- rim ARTWORK+7, glow disc ARTWORK on its own frame) - still under the backdrop's BACKGROUND-8 surface? No: equal
  -- frame level, so we raise the BARS instead: FrameBase.EnsureBarHeadroom lifts every bar (and its backdrop/ring) by
  -- the shortfall ONCE at creation, before anything else measures them. That is the only Blizzard level we touch and it
  -- is a relative bump, not an absolute value. The portrait keeps its original visibility parent and anchors.
  if portrait then
    local originalParent = portrait:GetParent()
    local portraitLayer = CreateFrame("Frame", nil, originalParent)
    portraitLayer:SetAllPoints(originalParent)
    portraitLayer:EnableMouse(false)
    st.portraitLayer = portraitLayer
    local function LowestBarBackdropLevel()
      local lowest
      for _, bar in pairs(st.bars) do
        local lvl = bar.stock.vfsBackdrop and bar.stock.vfsBackdrop:GetFrameLevel() or bar.stock:GetFrameLevel()
        if not lowest or lvl < lowest then lowest = lvl end
      end
      return lowest
    end
    -- The portrait group needs 3 levels under the lowest bar backdrop: holder, portraitLayer, glowFrame.
    local GROUP = 3
    local syncing = false
    local function SyncPortraitLayer()
      -- Re-entrancy: EnsureBarHeadroom lifts the bars one by one and each SetFrameLevel fires this hook again while
      -- the others are still at the old level, so a mid-lift read gave ceiling 0..2 and ceiling-3 went negative ->
      -- SetFrameLevel threw -> Target.Create aborted with no slots (owner, Era 2026-11-25). One pass at a time.
      if syncing then return end
      syncing = true
      local ceiling = LowestBarBackdropLevel() or (hb:GetFrameLevel())
      if ceiling < GROUP then
        VFS.FrameBase.EnsureBarHeadroom(st, GROUP - ceiling)
        ceiling = LowestBarBackdropLevel() or hb:GetFrameLevel()
      end
      -- Frame levels are unsigned. If a client leaves us no room even after the lift (headroom already applied for a
      -- different reason, or a bar parented where it cannot move) clamp at 0 rather than throw: a flat stack is a
      -- cosmetic fault, an aborted Create loses the whole frame.
      local base = math.max(0, ceiling - GROUP)
      local strata = hb:GetFrameStrata()
      holder:SetFrameStrata(strata);        holder:SetFrameLevel(base)
      portraitLayer:SetFrameStrata(strata); portraitLayer:SetFrameLevel(base + 1)
      glowFrame:SetFrameStrata(strata);     glowFrame:SetFrameLevel(base + 2)
      -- Everything painted over the portrait (rim, level badge) must follow it up: one audited sync in FrameBase.
      VFS.FrameBase.SyncAdornmentLevels(st)
      syncing = false
    end
    SyncPortraitLayer()
    portrait:SetParent(portraitLayer)
    -- The black rim rides the same layer as the portrait so it tucks under the bars with it.
    VFS.FrameBase.AttachPortraitRim(st, portraitLayer)
    VFS.FrameBase.SyncAdornmentLevels(st)
    st.syncPortraitLayer = SyncPortraitLayer
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