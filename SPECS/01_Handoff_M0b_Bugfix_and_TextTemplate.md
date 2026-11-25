# VelocityFrameStyle — Handoff: M0b bug list + text template

- **Written:** 2026-11-25 01:10, end of the first Forever bring-up day. Last commit `6bc0a31`; one UNCOMMITTED change on
  top (rounded bar inset rings, `FrameBase.AcquireBackdrop/ColorBackdrop`, new `Assets\bar_edge.tga`) — publish-test it
  first; commit if the rings look right, revert if not.
- **Read first:** `00_VelocityFrameStyle.md` §Chrome (GEOMETRIC, FINAL) and its keep-list; `AddonManagement\PROJECT_STRUCTURE.md`
  rules (commit only after owner confirms in game; owner publishes; no long `/run`s — add diagnostics to the addon instead).
- **Client:** Forever (16001) is the test client. Owner plays a Hunter (pet always present). Owner disables EasyFrames +
  VelocityPetTargetFrame while testing (VFS stands down otherwise, `/vfs status` says so).
- **Diagnostics that exist:** `/vfs status`, `/vfs text <frame>`, `/vfs rects <frame>`, `/vfs values <frame>`,
  `/vfs layers <frame>` (`<frame>` = player | target | pet | tot | pettarget).
- **Repo layout (packager-style):** addon at `VelocityFrameStyle\VelocityFrameStyle\`; repo root has `Scripts\` (C#,
  `dotnet run Scripts/GenerateChromeAssets.cs` regenerates the `.tga` set), `SPECS\`, unshipped `Assets\`.

## State of play (what works, owner-confirmed 2026-11-25 01:00 screenshots)

Player and Target: geometric chrome renders — near-black disc behind portrait, rounded plate behind tall bars
(113×24 health, 113×12 power), name + level floating above, health green / power blue, combat glow pulses red and
now clears on leaving combat, zzz + swords kept. "VERY close" (owner). Rounded bar insets are the uncommitted change.

## Bug list — in priority order (owner's), each with located cause where known

### B1 — Pet-target frame does NOT remember its Edit Mode position (TOP PRIORITY, owner: capitals + expletive)

**Session update:** owner confirms the frame now stays where placed. Located cause: `DB.Profile()` recursively
filled placement defaults, restoring `anchorTo = "PetFrame"` after `OnMoved` deliberately cleared it. Placement
is now defaulted only when the entire record is missing; `ApplyPlacement` also honours saved `relPoint`.
`/vfs ptpos` prints saved and actual placement. Reload and layout-switch acceptance still needs explicit confirmation.
The earlier hypotheses below are retained as investigation history, not the confirmed cause.

**Symptom:** move it in Edit Mode → it reappears somewhere else; moving again doesn't stick.

**What is known (code path, `UI\EditMode.lua`, `Frames\PetTarget.lua`, `Core\LayoutProfile.lua`):**
- `OnMoved(frame)` is LibEditMode's callback after a drag. It now early-returns while `LayoutProfile.IsResolved()` is false
  (placeholder `"Default"` record), reads `frame:GetPoint(1)`, writes `DB.Profile().petTargetPlacement`, then calls
  `PetTarget.ApplyPlacement()`. That guard + re-apply was added in the last round and is **untested in game**.
- `ApplyPlacement()` anchors `point, UIParent, point, x, y` when `anchorTo == nil`, else `LEFT, PetFrame, RIGHT, 8, 0`
  (the un-moved default), else `FALLBACK_PLACEMENT`.
- `LayoutProfile.Current()` keys records by the active Edit Mode layout name; records are created lazily as a copy of
  the previous layout's record or defaults.

**Hypotheses to test, in order (one `/vfs` diagnostic each — add them, don't `/run`):**
1. **`OnMoved` is never called.** LibEditMode calls the callback only when its own drag ends on the registered frame.
   Our frame is a `SecureUnitButtonTemplate` Button; LibEditMode's `AddFrame` wraps it in an `EditModeSystemSelectionTemplate`
   child. Check VelocitySwingTimers (works) — its frames are plain Frames. **Diag:** `/vfs ptpos` prints
   `OnMoved` call count, last saved placement, `LayoutProfile.Name()/IsResolved()`, and the frame's current `GetPoint(1)`.
2. **Saved under the wrong key.** `IsResolved()` false during the drag → early return → nothing saved. `/vfs ptpos`
   shows it. If so: queue the write and flush it on `LayoutProfile.OnChanged`.
3. **Something re-anchors after us.** `Visibility.ExitEditMode` → `OnExit` → `ApplyPlacement()` (reads the record — fine
   if 1/2 are OK). `PLAYER_REGEN_ENABLED` → `OnRegenEnabled` → `ApplyPlacement()`. `LayoutProfile.OnChanged` →
   `EditMode.OnProfileChanged` → `ApplyPlacement()`. Any of these with a stale record reverts the move. Also
   `Visibility.EnterEditMode` calls `f:Show()` but **not** `ApplyPlacement()`; LibEditMode may `SetPoint` the frame to its
   `default` arg (`FALLBACK_PLACEMENT`) on enter if it thinks the frame has no saved position — **check `lib:AddFrame`'s
   `default` semantics in `Libs\LibEditMode\LibEditMode.lua`** (VST passes the saved point as default, we pass FALLBACK).
   Likely fix: pass the *current saved placement* as `default`, and re-register / update it when the layout changes.
4. **Scale.** `ApplyPlacement` does `SetScale` then `SetPoint`; a UIParent-relative point saved at scale 0.8 is in
   scaled coordinates. Lib reads `GetPoint` in the frame's own scale too, so consistent — but verify with `/vfs ptpos`.

**Acceptance:** move in Edit Mode → exit → `/reload` → frame is where it was dropped; switch Edit Mode layout → frame
moves to that layout's saved spot; switch back → returns.

### B2 — Pet-target frame renders broken ("buggered")

**Symptom (screenshot):** plate drawn, bars drawn, but a wrong/second name row, misaligned portrait, odd black block.

**Known:** `Frames\PetTarget.lua` was ported from VPTF's classic-art frame and then had geometric chrome bolted on in
the last round: bars re-anchored `RIGHT → portrait LEFT` at `Chrome.LAYOUT.pettarget` sizes, `f.texture`/`f.nameBackground`
listed in `ChromeRegions` (alpha 0), `VFS.Chrome.Create(st)` called. **Untested in game.** Suspects:
- The frame is still 232×100 with the portrait at classic `TOPRIGHT -24,-16` (64 px) while bars are now laid out
  target-style; the hit-rect insets (96,40,10,9) are classic too. Rebuild its geometry from scratch to mirror Target:
  button size ≈ 200×60, portrait 58 px right, bars 113×24 / 113×12 left of it, name row above health. Reuse
  `Chrome.LAYOUT.target` with `side="left"`.
- Our own `f.name`/`f.level`/`f.healthText` stand-ins (alpha 0) are fine; the visible duplicate "Pet's Target" strings in
  Edit Mode come from `SetSample` → `TextLayout.ApplySample` **plus** `FrameBase.ApplyAppearance` re-showing adopted
  text — check `PetTarget.SetSample` ordering.
- `Chrome.Layout` uses `Client.Portrait("pettarget")` = `f.portrait`; its disc is sized from `portrait:GetWidth()` = 64 →
  disc radius 37; the Target's real portrait is 58. Pick one.

**Acceptance:** pet-target looks like a mirrored Target frame (portrait right, bars left), one name row, no black
block, scales with the Edit Mode slider.

### B3 — Target-of-Target not styled

`Frames\ToT.lua` + Forever `tot` resolvers + `Chrome.LAYOUT.tot` were added last round, **untested**. It is NOT in
`DB.FRAME_IDS` (so no options section, and `DB.Frame("tot")` returns nil → `ApplyAppearance` will error on
`DB.Frame(id).enabled`). **Fix:** add `"tot"` to `DB.FRAME_IDS`, add `LABELS.tot = "Target of Target"` in
`UI\FramePage.lua`, confirm `TargetFrameToT.Portrait/HealthBar/ManaBar/Name/FrameTexture` exist with `/vfs status`
(prints MISSING per region). Camelot `TargetOfTargetMixin:OnLoad` re-anchors health (11 px) and mana (78×7); our
`PlaceBars` post-hooks `TargetFrame.UpdateTargetOfTarget` — verify the hook name exists on Forever (`/fstack` or
`/vfs status` MISSING), else hook `TargetFrameToT:HookScript("OnShow")`.

### B4 — Black alpha chunk over the top of the Pet portrait (screenshots 2/3)

**Symptom:** on the Pet frame a dark rectangle covers the upper portion of the portrait disc, as if a bar/plate corner
or a stock region sits above the portrait.

**Candidates (in order):**
1. Our **plate** on the pet: `Chrome.Layout` anchors `plate LEFT → portrait CENTER` and `TOP → health TOP + pad`. The pet
   health bar is anchored `BOTTOMLEFT → portrait RIGHT (2, -3.5)` so the bar's top is well above the portrait's
   centre-line — the plate therefore extends up over the portrait's upper-right quadrant, and the plate draws ABOVE the
   disc but BELOW the portrait… unless the pet portrait is on a lower frame level than our holder. On Forever `PetPortrait`
   is a BACKGROUND texture of `PetFrame` itself (level N); our chrome holder is `PetFrame` child at `hb level - 3`;
   `PetFrameHealthBar` is a child at level N+1 → holder at N-2 → **holder level is clamped to ≥ 0 but may equal PetFrame's
   level**, in which case the plate (holder+1) draws above the portrait. **Diag:** `/vfs layers pet` (exists) shows the
   order. **Fix:** on frames whose portrait is a region of the unit button itself (pet, tot), the chrome holder must be
   a *sibling parented to the button's parent* at `button level - 1`, or the plate must not overlap the disc (set
   `plateOverlap = 0` for small frames so the plate butts against the disc instead of tucking under).
2. Blizzard's `PetFrameTexture` / `PetFrameFlash` not actually alpha-zeroed (`ChromeRegions` lists them; `/vfs layers pet`
   will show `a=1.00` if so).
3. The stock `PetFrameHealthBar.Background`-equivalent — Forever's pet bar inherits `TextStatusBar` and may own a black
   `Background` like the player's. Add to `ChromeRegions.pet` if `/vfs layers pet` shows a black texture above the disc.

### B5 — Target frame: Level sits in the name row at a different size than Player's (minor)

Visible in screenshot: Target `15` is larger. Both frames share `DefaultElements()` (level size 10); the Target's
stock `LevelText` is **kept** via `KeepRegions`? No — `StockLevelRegions.target` alpha-zeroes `LevelText` and
`LevelBackgroundCircle`. Check whether Camelot's `TargetFrameMixin:CheckBattlePet` re-shows `LevelText` after us
(`SetShown(not isBattlePet …)`) — alpha stays 0 so no. More likely: the skull `HighLevelTexture` re-anchor in
`Target.PlaceSkull` is fine but `KeepRegions.target` includes `HighLevelTexture` *and* `BossIcon`; nothing sizes
the level text. Verify with `/vfs text target` (size per element). Low priority.

### B6 — Power bar width (Target mana) — likely fixed, verify

Last round set power width = health width (113) on all frames and dropped EF's wider values. Confirm with the eye.

---

## Feature: text template — Name / Level / Health / Power rows + Format column [D, owner 2026-11-25]

**Superseded implementation details:** see `03_Text_Template.md`. Installed Forever EasyFrames confirms direct Blizzard formatting APIs support independent per-bar text. The CVar mapping below was incorrect; no CVar writes are needed. Four-row UI and migration goals remain.


**Replaces** the current six fixed rows (`name, level, health, healthpct, power, powerpct`) with **four**:

| id | label | default anchor | align | size | colour | Format (new column) |
|---|---|---|---|---|---|---|
| `name`   | Name   | nameplate | left   | 10 | stock      | — |
| `level`  | Level  | nameplate | right  | 10 | difficulty | — |
| `health` | Health | health    | center | 10 | white      | **Current** / Current / Max / Percent / Hidden |
| `power`  | Power  | power     | center | 10 | white      | **Current** / Current / Max / Percent / Hidden |

Owner's words: *"I want to be able to put ONLY current health and current mana on the bar."*

**How Format is implemented per client (the whole reason for the design):**

| | Era (no secret values) | Forever (secret values) |
|---|---|---|
| Source of the number | our `Format.Expand` tokens | Blizzard's secure `HealthBarText` / `ManaBarText`, **adopted** into the grid (`TextLayout.AdoptStock`, already built) |
| `Current`        | `[hp]`            | Status Text CVar `statusTextDisplay = "NUMERIC"` (shows current only) |
| `Current / Max`  | `[hp] / [hpmax]`  | `statusTextDisplay = "BOTH"` |
| `Percent`        | `[hp%]`           | `statusTextDisplay = "PERCENT"` |
| `Hidden`         | anchor = hidden   | anchor = hidden (alpha 0 on the adopted string) |

- **R1 exception, deliberate and documented:** on Forever the Format column **writes `statusTextDisplay`** (and
  `statusText = 1`) because Blizzard's string is the only legal source of the number and that CVar is the only lever
  on its format. It is written **only** when the user changes the column (user-initiated), never at login. One CVar
  governs **all** of Blizzard's unit frames → Health and Power share the value on Forever, and changing it on one frame
  changes every frame; the column's tooltip says so, and the UI shows the same value on every frame's rows. Era has
  per-frame, per-bar independence (token per element).
- **Verify the CVar values on Forever first** (M0 of this feature): `/dump GetCVar("statusTextDisplay")` after flipping
  Options → Interface → Status Text between Numeric / Percent / Both. Record in
  `AddonManagement\_EXTERNAL_APIS\wow_status_text_cvars.md`. Known Mainline values: `"NUMERIC"`, `"PERCENT"`, `"BOTH"`,
  `"NONE"`; Classic Era had `statusText` 0/1 + `statusTextDisplay`. Confirm which Forever honours.
- **Data model change** (`Core\DB.lua`): `VFS_TextElement` gains `format = "[hp]" | "[hp] / [hpmax]" | "[hp%]"` as
  today (string) **plus** `valueFormat = "current" | "current_max" | "percent"` (the dropdown value) for health/power
  rows. `DefaultElements()` → 4 rows. Migration: existing saved `elements` tables with 6 rows are replaced by the
  4-row default **once** (bump `DB_VERSION` to 2; keep anchor/align/size/colour of `name`/`level` if present).
- **Options** (`UI\FramePage.lua` `ElementRow`): add a 5th dropdown **Format** shown only for `health`/`power`:
  `{ current = "Current", current_max = "Current / Max", percent = "Percent" }` + `Hidden` is the existing Position=Hidden.
  On change: Era → set `e.format` from `valueFormat`; Forever → `SetCVar("statusTextDisplay", MAP[valueFormat])` +
  `SetCVar("statusText", "1")`, then `Restyle`. Tooltip on Forever: *"Uses the game's Status Text setting; applies to
  all frames."*
- **Format.lua:** add `Format.FORMAT_TOKENS = { current = "[hp]", current_max = "[hp] / [hpmax]", percent = "[hp%]" }`
  and the power equivalents; `Format.UsesHealth/UsesPower` unchanged.
- **TextLayout.ApplyTexts:** no change — adopted strings are already handled; Era strings expand tokens.
- **Acceptance:** Forever: set Health → Current → bar shows `873` (not `873 / 873`), Power follows (shared CVar), tooltip
  explains. Era: Health Current + Power Percent independently. Switching back to Current / Max restores.

---

## Also pending (carry-over, lower priority)

- `UI\Options.lua` Theme still shows the dead **Border brightness** slider (`borderDarken` removed from DB) → replace with
  **Plate colour** swatch + **Plate opacity** slider + **Combat glow** checkbox/colour (`plateColor/plateAlpha/showCombatGlow/combatGlowColor`).
- `UI\FramePage.lua` `OverrideRow` for `borderDarken` → same replacement per frame (or drop the override).
- Dead code: `Core\Geometry.lua` header comment still says "On Forever MovableBars() is empty" — now false; update.
  `rounded_mask.tga` is unused since bars are rectangles (ring does the rounding) — delete from generator + Assets.
- Pet-target: `CLASSIFICATION_ART` / `f.texture` classic-art swaps are dead with geometric chrome; remove.
- Spec `00_…md` §Files lists `Frames/ToT.lua` under M3 — it is in M0 now.
- Soft outer edge of plate/disc (long tail): `discSoft`/`plateSoft` exist at alpha ×0.35; owner hasn't judged yet.
- Era (M1) untested entirely.

## Order of work for the next session

1. Publish-test the uncommitted bar-inset rings → commit or revert.
2. **B1** pet-target position (add `/vfs ptpos`, test hypotheses 1→4). Commit when it sticks.
3. **B2** rebuild pet-target geometry as mirrored Target. **B4** pet portrait black chunk (`/vfs layers pet`). **B3** ToT
   into `FRAME_IDS` + verify. One commit per confirmed fix.
4. Text template: verify CVar values → DB migration → Format dropdown → Forever CVar path → Era token path. Commit.
5. Options cleanup (plate controls replace border slider). Commit.
6. Then Era (M1).