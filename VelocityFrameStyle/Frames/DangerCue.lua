-- Velocity Frame Style: the Target danger bar effects (SPECS/13 Q3) - port of VelocityPlateStyle Skin.ApplyOverLevel.
--
-- Over-level (Danger.IsOverLevel) and overLevelMode ~= "none":
--   * red modes (red | animatedRed): the health bar's black border ring (both copies) turns Danger.RED;
--   * animated modes (animated | animatedRed): a FULL-BAR sweep layer over the fill - leftgrad.tga tiled along the bar
--     and scrolled left-to-right by the XML TextureCoordTranslation in VFS_SweepTextureTemplate (Templates.xml; no
--     per-frame Lua) - over a 50% black dimmer so the wave stands out. "animated" = fixed yellow wave; "animatedRed" =
--     the CONTRAST of the bar's own fill colour: red over a green/yellow bar, yellow over a red (reactionHealth) bar.
-- The fill colour itself is never written here (that is FrameBase.ApplyHealthColor's job). Combat glow is independent.
--
-- Levels: the sweep frame is a child of the health bar at bar + vfsBorderLevelOffset - above the fill and any
-- prediction segment (bar + 1 when predictions are styled), level with the black ring. It never overlaps the ring
-- (SetAllPoints(hb) = the inner surface only) so the tie is irrelevant. The text host is floored above both by
-- FrameBase.SyncAdornmentLevels. Re-synced on the bar's SetFrameLevel/SetFrameStrata like Chrome's glow rings.
local ADDON_NAME, VFS = ...
local Util, DB = VFS.Util, VFS.DB

local DangerCue = {}
VFS.DangerCue = DangerCue

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local SWEEP_TILE_PX = 96          -- on-screen px per repeat of the gradient (wave length); the asset is 256 wide
local SWEEP_DIM_ALPHA = 0.5       -- black dimmer under the wave

local function Danger() return VFS.Danger end

local function Acquire(st)
  if st.dangerCue then return st.dangerCue end
  local hb = st.bars.health and st.bars.health.stock
  if not hb then return nil end
  local frame = CreateFrame("Frame", nil, hb)
  frame:EnableMouse(false)
  frame:SetAllPoints(hb)
  local function SyncLevel()
    frame:SetFrameStrata(hb:GetFrameStrata())
    frame:SetFrameLevel(hb:GetFrameLevel() + (hb.vfsBorderLevelOffset or 1))
  end
  SyncLevel()
  hooksecurefunc(hb, "SetFrameLevel", SyncLevel)
  hooksecurefunc(hb, "SetFrameStrata", SyncLevel)
  local dim = frame:CreateTexture(nil, "ARTWORK", nil, -1)
  dim:SetTexture(WHITE8); dim:SetVertexColor(0, 0, 0, SWEEP_DIM_ALPHA); dim:SetAllPoints(frame); dim:Hide()
  local tex = frame:CreateTexture(nil, "ARTWORK", "VFS_SweepTextureTemplate")
  if not tex or not tex.Sweep then
    Util.WarnOnce("dangercue:template", "VFS_SweepTextureTemplate did not load (Templates.xml missing from the TOC?)")
    frame:Hide()
    st.dangerCue = { frame = frame, dim = dim, tex = nil, hb = hb }
    return st.dangerCue
  end
  tex:SetAllPoints(frame)
  tex:Hide()
  st.dangerCue = { frame = frame, dim = dim, tex = tex, sweep = tex.Sweep, hb = hb }
  return st.dangerCue
end

local function LayoutSweep(cue)
  local w = Util.PlainNumber(cue.hb:GetWidth(), nil)
  if not w or w <= 0 then return end
  cue.tex:SetTexCoord(0, math.max(1, w / SWEEP_TILE_PX), 0, 1)
end

-- "animated" => fixed yellow. "animatedRed" => contrast of the fill: green-ish/yellow-ish bar (g > 0.5) => red wave;
-- red bar => yellow wave. Reading the StatusBar colour is a widget query, not a unit read.
local function SweepColor(mode, hb)
  local D = Danger()
  if mode ~= "animatedRed" then return D.YELLOW[1], D.YELLOW[2], D.YELLOW[3] end
  local ok, r, g = pcall(hb.GetStatusBarColor, hb)
  if ok and r and g and g > 0.5 then return D.RED[1], D.RED[2], D.RED[3] end
  return D.YELLOW[1], D.YELLOW[2], D.YELLOW[3]
end

function DangerCue.Apply(st)
  if not st or st.id ~= "target" then return end
  local hb = st.bars.health and st.bars.health.stock
  if not hb then return end
  -- A dead target is no danger: no sweep over a corpse (owner 2026-11-27). A secret flag counts as alive.
  local dead = Util.Plain(UnitIsDeadOrGhost(st.unit)) == true
  local enabled = DB.Frame(st.id).enabled and UnitExists(st.unit) and not dead
  local mode = DB.Danger().overLevelMode or "none"
  local on = enabled and mode ~= "none" and Danger().IsOverLevel(st.unit)
  -- The border stays BLACK in every mode (owner 2026-11-27). "red" is therefore row + red Level only, no bar effect.
  local wantSweep = on and (mode == "animated" or mode == "animatedRed")
  local cue = st.dangerCue or (wantSweep and Acquire(st))
  if not cue or not cue.tex then return end
  if wantSweep then
    cue.tex:SetVertexColor(SweepColor(mode, hb))
    LayoutSweep(cue)
    cue.dim:Show(); cue.tex:Show()
    if not cue.sweep:IsPlaying() then cue.sweep:Play() end
  elseif cue.tex:IsShown() then
    cue.sweep:Stop()
    cue.tex:Hide(); cue.dim:Hide()
  end
end