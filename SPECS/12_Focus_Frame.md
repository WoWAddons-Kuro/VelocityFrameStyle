# Focus frame + Focus Target (spec 12) - OWNED frames

**Status:** rewritten 2026-11-26 after a failed first attempt (below). **Design: both frames are OWNED** via `Frames\OwnedUnitFrame.lua`,
the Pet Target pattern, exactly as spec 11 anticipated ("design for a future Focus frame"). Forever first; Era has no `focus` unit.
Nothing is committed until the owner confirms in game.

## Why owned, not a restyle (the lesson of attempt 1)

Attempt 1 restyled Blizzard's `FocusFrame` with the Target.lua pattern because `FocusFrame` inherits `TargetFrameTemplate` and is an
Edit Mode system. It failed, and every fix chased a new face of the same cause:

| Blizzard behaviour (`FocusFrameMixin:SetSmallSize`, Mainline_TargetFrame.lua 1113-1164; active when Edit Mode "Use larger frame" is OFF, the owner's state) | Effect on a restyle |
|---|---|
| `self:SetScale(0.75)` on the whole frame | Target's absolute bar offsets land away from the portrait chrome |
| `self.totFrame:SetScale(1.333)` + re-anchor `TOPRIGHT -> BOTTOMRIGHT (20, 8)` | Blizzard's ToT child is scaled UP and parked over the Focus bar area |
| `UnitFrame_Update` -> `SetPortraitTexture` repaints `.Portrait` at alpha 1 (C side) | per-texture alpha-0 chrome suppression is silently defeated |
| frame alpha 0 on `FocusFrameToT` (owner's experiment) does hide it | ...but the Focus health bar vanished with it: the mutated geometry overlaps |
| unregisters `UNIT_CLASSIFICATION_CHANGED`/`PLAYER_FLAGS_CHANGED`, swaps fonts, hides icons | more divergence from Target to patch |

Owner 2026-11-26: "whatever you are doing is fragile as hell" - correct. A restyle inherits Blizzard's mutation; an owned frame has none.
**Owned Focus:** our geometry at scale 1, our anchors, our ToT; Blizzard's `FocusFrame` (and its ToT child inside it) is suppressed
as ONE chrome region (frame alpha 0, cosmetic, never `Hide()` - protected and re-shown by Blizzard). Era keeps the frame-level ToT
suppression that fell out of this (TargetFrameToT as the chrome region) - the owner proved frame alpha is the mechanism that holds.

## Ground truth (Forever; owner dumps 2026-11-26)

| Fact | Consequence |
|---|---|
| `/focus` works; `UnitExists("focus")` true; `FocusFrame:IsShown()` true | the unit is real; `PLAYER_FOCUS_CHANGED` fires on change |
| `FocusFrame` is an Edit Mode system (Focus index) and a secure unit button | we never Hide()/move it; alpha 0 is legal and sticks |
| `FocusFrameToT` = `CreateTargetofTarget("focustarget")`, child of FocusFrame | alpha 0 on the PARENT covers it; nothing else to suppress |
| `focustarget` fires `UNIT_TARGET` for unit `focus` | event refresh, no poller (same as tot) |
| `focus` fires UNIT_HEALTH/UNIT_POWER_UPDATE/... for unit `focus` | event refresh, no poller |
| Era: no focus unit (`HasFocusFrame = false`) | feature absent, no options page |

## Design

### Two specs on the factory (no new frame code)

```
Focus.SPEC = { id = "focus", unit = "focus", globalName = "VelocityFrameStyleFocus",
  editModeLabel = "Focus", placementKey = "focusPlacement", anchorFrameName = "FocusFrame",
  defaultPlacement = DB.DEFAULT_FOCUS_PLACEMENT,          -- TOPLEFT -> FocusFrame TOPLEFT (0, 0): sits where Blizzard's is
  flashGlobalKey = "focusFlashOnNew", healthOnlyGlobalKey = nil, hideWhenMeGlobalKey = nil,
  small = nil,                                             -- full Pet-Target geometry (portrait right, bars left, Chrome.LAYOUT.focus)
  needsPoller = false, sample = {...}, sampleIcon = ..., safeTag = "fo" }
FocusTarget.SPEC = (as built) { id = "focustarget", unit = "focustarget", anchorFrameName = "VelocityFrameStyleFocus",
  defaultPlacement = TOPRIGHT -> our Focus BOTTOMRIGHT (12, 10), small = {...}, hideWhenMe/flash/healthOnly keys }
```

`OwnedUnitFrame.ApplyPlacement` resolves `anchorFrameName` via `_G[...]`; our Focus frame has a global name, so Focus Target
anchors to **our** Focus frame and moves with it when dragged. Both are LibEditMode entries ("Focus", "Focus Target").

### Suppressing Blizzard's FocusFrame

- `Client.ChromeRegions("focus")` returns `{ FocusFrame }` when `DB.Frame("focus").enabled` (the frame itself; alpha 0 cascades to
  every child incl. `FocusFrameToT`, spellbar excluded - see Open). Applied by `FrameBase.ApplyAppearance` for the owned `focus` state
  like any other chrome list: `SetChromeSuppressed(FocusFrame, "focus", true)`.
- NO hooks on FocusFrame methods, NO SetSmallSize handling, NO Target-like adapter resolvers for focus. The Forever adapter's
  `TargetLike` refactor from attempt 1 is reverted; `focus` and `focustarget` are both in the OWNED set.
- Blizzard's FocusFrame still exists for Edit Mode (its own entry keeps working, moving an invisible frame - acceptable; the
  owner drags OUR Focus entry).

### Options: one page "Focus and Focus Target" (as built, kept)

Single `Use Velocity Frame Style` box writes both records; Focus body (sliders, overrides, grid, flash-on-new); Focus Target body
(sliders, grid, health-only / flash / hide-when-me). Page exists only when `Client.HasFocusFrame()`.

### Events (bootstrap)

`PLAYER_FOCUS_CHANGED` -> Focus.OnUnitChanged + FocusTarget.OnUnitChanged; `UNIT_TARGET(focus)` -> FocusTarget; `UNIT_HEALTH /
MAXHEALTH / POWER_UPDATE / MAXPOWER / DISPLAYPOWER` registered for `focus` and `focustarget`; LEVEL/NAME/FACTION/FLAGS/
CLASSIFICATION already include both.

## Plan

- [x] R0 - Revert attempt-1 pieces: `Frames\Focus.lua` restyle body, adapter `TargetLike`/`BlizzToT` refactor (Target resolvers back
      to `id == "target"`), the portrait-anchored PlaceBars. Keep: DB ids/globals, Chrome layouts, labels, FocusTarget.lua, options
      page, frame-level ToT suppression on Era/Forever, pulse alpha reset, OwnedUnitFrame.ApplyHideWhenMe.
- [x] R1 - `Focus.lua` = spec on the factory; `DB.DEFAULT_FOCUS_PLACEMENT`, `focusPlacement` in profile, `focusFlashOnNew` global;
      FocusTarget anchorFrameName -> `VelocityFrameStyleFocus`.
- [x] R2 - Adapter: `focus` in OWNED; `ChromeRegions("focus")` = `{ FocusFrame }` gated on enabled; `Root("focus")` = our frame.
- [x] R3 - Bootstrap: Stage Focus (owned) + visibility + placement; drivers; `focus` value events.
- [x] R4 - Owner test on Forever 2026-11-26: Focus + Focus Target shown, aggro->pet scenario clean, Blizzard's FocusFrame invisible.
      One follow-up fix landed in the same commit: `OwnedUnitFrame.ApplyPlacement` treats a saved `anchorTo` that is not the spec's
      anchor (attempt-1 records said "FocusFrame") as "use the spec default" instead of the screen-centre fallback. **Committed `3b06674`.**
- [ ] R5 - Era: nothing to do (no focus unit); confirm the page is absent and `/vfs status` rows show `-` when the owner next plays Era.

## Open

- Focus **cast bar** (`FocusFrameSpellBar`) is a child of FocusFrame and goes invisible with it. v1 accepts that; a later option could
  re-parent nothing (protected) but exclude the spellbar from suppression by alpha-1-ing it back (it is a plain StatusBar, unprotected).
- Pingable on Forever: skipped, as for ToT.