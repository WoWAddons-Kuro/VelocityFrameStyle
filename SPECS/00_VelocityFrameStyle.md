# SPEC-VelocityFrameStyle: Restyle Blizzard's unit frames, one addon for Era + Forever

- **Status:** Draft v1 (2026-11-24). Decisions marked **[D]** came from the owner during the VelocityPetTargetFrame /
  EasyFrames debugging session that produced this spec.
- **Name:** `VelocityFrameStyle`. Repo `VelocityFrameStyle\`, TOC `VelocityFrameStyle.toc` (+ `_Vanilla`, `_Camelot`),
  SavedVariables `VelocityFrameStyleDB`, slash `/vfs` and `/velocityframestyle`, namespace `VFS` (`local ADDON, VFS = ...`).
- **Clients:** **WoW Forever (16001) first [D 2026-11-24]** — the more restrictive target (secret values, restricted regions,
  Mainline frame paths, overlay bars); Classic Era (11509) second as the relaxation. Camelot TOC ships untested.
- **Lineage:** PlateStyle's architecture applied to unit frames. EasyFrames (BSD, Mirmidonis/Usoltsev) is the **reference
  for frame geometry only**; no EasyFrames code or format subsystem is ported. `VelocityPetTargetFrame` is **absorbed**
  as the `PetTarget` frame module **[D]**; its standalone repo stays published but frozen (README points here).
- **Why this exists (owner, 2026-11-24):** every unit-frame addon in use was written for a WoW where Lua could read any
  value and set any text. Forever's secret values and Era's restricted regions broke that contract; EasyFrames' per-bar
  *format-string* model (`%CURRENT% / %MAX%`, seven threshold formulas, abbreviation toggles) cannot be made compliant,
  and its Era tree has structural defects (13 px pet bars in a 17 px slot, fonts lost after `UpdateTextString`, no
  bar backdrop). PlateStyle's *token-element* model is already compliant and simpler with more configurability. Reuse it.
- **References:**
  - `VelocityPlateStyle\SPECS\SPEC-VelocityPlateStyle.md` — invariants R1–R8, text-element grid, `Client` resolver pattern.
  - `VelocityPlateStyle\Format.lua`, `Skin.lua` (`LayoutTexts`, `ApplyTexts`, `ReapplyStockTexts`) — code to lift into shared modules.
  - `VelocityPetTargetFrame\SPECS\00_VelocityPetTargetFrame.md` — the pet-target frame, secure visibility findings.
  - `AddonManagement\_EXTERNAL_APIS\wow_secure_visibility_pettarget.md` — what secure code can and cannot do.
  - `_ref\blizzard\classic_era\{PlayerFrame,TargetFrame,PetFrame}.xml` — Era region names. `_ref\blizzard\forever\UnitFrame.Mainline.lua` — Forever.
  - EasyFrames Era `Modules\Core.lua` (`MovePlayerFrameBars` 27 px, `MovePetFrameBars` 13 px…) and Forever `Modules\Core.lua`
    (`CreateHealthBarFor`, `CreateBarBackground`, `ForceHiddenFill`) — measured geometry and the two restyle strategies.
  - `AddonManagement\PROJECT_STRUCTURE.md` — Client file layout, two-name rule, commit/publish rules.

## Milestones

- [ ] **M0 — Forever bring-up: Player, Target, Pet, PetTarget [D: Forever first].** Repo, three TOCs, Client layout,
      shared `TextLayout` + `Format` lifted from PlateStyle, `Frames\*.lua` for the four frames with text grid + bar
      texture/backing/border using the **overlay-bar strategy** (§Frame strategies) and secret-safe token degradation
      from day one, PetTarget module ported from VPTF (frame, secure visibility, soft-hide, LibEditMode placement, pet
      bar backdrop), GotJunk-style options page with one section per frame, R7 stand-down when EasyFrames is loaded.
      Region paths confirmed with `/fstack` on Forever before any `Client_Forever.lua` resolver is trusted.
      **Exit:** owner plays Forever with EasyFrames disabled and nothing is worse than before.
- [ ] **M1 — Era adaptor** for the same four frames: flat region globals, `UNIT_HEALTH`/`UNIT_POWER_UPDATE`
      registration (no secrets), and the **restyle-in-place** bar strategy via `Geometry` (the R2 exception). Era is
      the relaxation of Forever: nothing Forever does is removed, Era only gains the number tokens and in-place bars.
- [ ] **M0b — Visual media pickers (REQUIRED in M0, not optional) [D 2026-11-24].** The bar-texture dropdown and the
      font dropdown are the **visual** pickers EasyFrames has (each row drawn in its texture / font). See §Visual media pickers.
- [ ] **M2 — Options page in PlateStyle layout**: per-frame text grid with reorder arrows + custom element box, visual
      texture picker (shared with PlateStyle M2b when it lands). "Copy text layout from Target" on PetTarget **[D]**.
- [ ] **M3 — Remaining frames**: Target-of-Target, Party (+ party pets), Focus and Boss (Forever only; `Client.HasFocusFrame()`).
- [ ] **M4 — Modern look styles**: flat bars, square portraits, optional art swaps — a `VFS_FrameStyle` enum per frame,
      classic art stays the default. Deferred until M0–M2 are stable **[D]**.
- [ ] **M5 — Polish**: icon (`AddonManagement\Scripts\MakeAddonIcon.cs`), README, `.pkgmeta`, webhooks row, first release;
      VPTF README marked "included in VelocityFrameStyle".

## Overview

VelocityFrameStyle changes how Blizzard's own unit frames look: textures, sizes, anchors, fonts, and a small number of
added regions. It never creates replacement frames, never decides which units get frames, and never owns a frame's
existence or visibility — with exactly one exception, the **pet-target frame**, which Blizzard does not have and which
we therefore create ourselves (as VelocityPetTargetFrame already does).

Three criteria, inherited from PlateStyle:

1. **One thing.** Restyle stock unit frames (and supply the one missing frame).
2. **Native settings.** One category in Options > AddOns, GotJunk canvas style, in PlateStyle's section layout.
3. **One addon, all clients.** Era and Forever from one folder via `Client\`.

## Design rules (invariants)

| # | Rule | Consequence |
|---|---|---|
| R1 | Never writes a CVar on its own initiative | Status-text CVars (`statusText`, `statusTextDisplay`) are never touched. Our own FontStrings make them irrelevant. |
| R2 | Never shows, hides, moves or reparents a Blizzard frame, or any child it did not create | Stock regions we replace are **alpha-zeroed**, never hidden. **Exception [D, audited]:** the Era bar-geometry path (§Frame strategies, Era) needs `SetHeight`/`SetPoint` on stock `StatusBar` children — allowed only on the non-secure bar children listed in the Client `MovableBars()` resolver, only out of combat, only through `VFS.Geometry.Move()` which logs once if blocked. Never on the unit button itself. |
| R3 | Level and classification information is never removable | Every frame keeps a visible level and elite/rare/boss marker; options choose *how*. |
| R4 | Event-driven only | No `OnUpdate`, no tickers — **except** the documented 0.2 s tick for `pettarget` (the client fires no `UNIT_*` events for that unit; see VPTF spec §3.2). |
| R5 | Secret-value-safe where secret values exist (Forever) | Unit values used in Lua pass through `VFS.Plain(v)`; a secret token expands to `""` and the element takes no room. Health/power **fill** is always Blizzard's own bar (restyled, not re-driven) so fills never need the number. |
| R6 | Forbidden frames are skipped | n/a for unit frames today; kept for parity. |
| R7 | Stand down when another frame owner is present | If `EasyFrames`, `ShadowedUnitFrames`, `ElvUI`, `PitBull4`, `oUF`-based frame addons or `LazyThom_PetTarget` is loaded, skip styling and print one line naming it. `VelocityPetTargetFrame` standalone also triggers stand-down of our PetTarget module only. |
| R8 | Unit values used in Lua pass through `VFS.Plain(v)` | Same as PlateStyle R8. |
| R9 | **Text is the element grid, never a format string per bar [D]** | No `healthFormat` / `%CURRENT%` / threshold-formula settings exist anywhere in this addon. |
| R10 | Placement and scale are Edit Mode's | Blizzard frames: we never position them (Edit Mode does on both clients). PetTarget: LibEditMode + per-layout record, as VPTF. |

## Files

```
VelocityFrameStyle/
  VelocityFrameStyle.toc / _Vanilla.toc / _Camelot.toc
  .pkgmeta (package-as: VelocityFrameStyle; ignore: *.md, SPECS, Assets/Screenshots)  .gitignore  LICENSE  README.md
  Bindings.xml                      CLICK VelocityFrameStylePetTarget:LeftButton
  Libs/LibStub, Libs/LibEditMode    (vendored, unmodified; only for PetTarget placement)
  Client/Client.lua                 Client.INTERFACE (region resolvers + capability flags + value shims), VFS.ClientFlavours = {}
  Client/Client_ClassicEra.lua      Era flat globals: PlayerFrameHealthBar, PetFrameTexture, TargetFrameNameBackground ...
  Client/Client_Forever.lua         Mainline paths: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar ...
  Client/Client_Select.lua          picks flavour, binds VFS.Client, warns on interface mismatch (copy of VPTF/VST)
  Core/Util.lua                     Print, WarnOnce, Raise, Safe, DeepCopy, ApplyDefaults, Plain/PlainNumber, FontPath, StatusBarPath
  Core/DB.lua                       VelocityFrameStyleDB = { version, global = VFS_GlobalSettings, frames = { [VFS_FrameID] = VFS_FrameSettings }, profiles = { [layoutName] = VFS_ProfileRecord } }
  Core/LayoutProfile.lua            Edit Mode layout -> record (copy of VST/VPTF)
  Core/Format.lua                   token expander (lifted from PlateStyle Format.lua, + power tokens)
  Core/TextLayout.lua               element grid flow engine (lifted from PlateStyle Skin.LayoutTexts/ApplyTexts, parameterised by slot geometry)
  Core/Geometry.lua                 VFS.Geometry.Move/SetHeight — the one audited R2-exception helper (Era bar moves)
  Core/Textures.lua                 built-in bar textures/fonts; opportunistic LSM discovery (as PlateStyle)
  Frames/FrameBase.lua              VFS_FrameModule contract: Create(), Restyle(), OnUnitChanged(), slots for TextLayout
  Frames/Player.lua  Frames/Target.lua  Frames/Pet.lua          M0
  Frames/PetTarget.lua  Frames/PetTargetVisibility.lua         M0 (ported from VPTF UI/Frame.lua + UI/Visibility.lua)
  Frames/ToT.lua  Frames/Party.lua  Frames/Focus.lua  Frames/Boss.lua   M3
  UI/Options.lua                    GotJunk canvas, PlateStyle section layout; one section per frame + shared sections
  UI/EditMode.lua                   PetTarget registration with LibEditMode (ported from VPTF)
  VelocityFrameStyle.lua            bootstrap: DB, events, slash, stand-down, feature flags
  Assets/  VelocityFrameStyle_Icon.tga, hatch.tga (shared with PlateStyle if a danger cue is ever wanted here)
  SPECS/00_VelocityFrameStyle.md    this file
```

TOC load order: Libs, `Client\Client.lua`, `Client_*.lua`, `Client_Select.lua`, `Core\*` (Util first), `Frames\FrameBase.lua`,
`Frames\*.lua`, `UI\*.lua`, `VelocityFrameStyle.lua`.

## Architecture

```
  PLAYER_LOGIN / UNIT_PET / PLAYER_TARGET_CHANGED / UNIT_LEVEL / UNIT_FACTION / UNIT_CLASSIFICATION_CHANGED
  hooksecurefunc(stock update fns per frame)     UNIT_HEALTH / UNIT_POWER_UPDATE (Era only)     Options change
                     |                                        |                                   |
                     v                                        v                                   v
              +-------------+        Restyle(frameID) / RestyleAll()          +--------------+
              |  Frames/*   | <-----------------------------------------------|   Options    |
              +-------------+                                                 +--------------+
               |    |    |
     +---------+    |    +-----------+
     v              v                v
 +----------+  +------------+  +-----------+
| TextLayout|  |  Geometry  |  |  Client   |   per-client region resolvers, capability flags, value shims
 +----------+  +------------+  +-----------+
     |
     v
 +----------+
|  Format  |   [name] [level] [hp] [hp%] [hpmax] [power] [power%] [powermax] [class] [class+] [creature]
 +----------+
```

### Client (per-flavour resolvers)

Every resolver takes the Blizzard frame (or a `VFS_FrameID`) and returns the region or `nil` (= degrade to stock for that
feature). Field names below are from `_ref\blizzard\classic_era\*.xml` (Era) and `UnitFrame.Mainline.lua` (Forever) and are
**confirmed by `/fstack` during M0/M1**, not before.

```lua
-- Client/Client.lua
VFS_FrameID = "player" | "target" | "tot" | "pet" | "pettarget" | "party1".."party4" | "focus" | "boss1".."boss5"

Client.INTERFACE = {
  -- Capabilities
  "HasFocusFrame",        -- () -> bool            Era false, Forever true
  "HasBossFrames",        -- () -> bool
  "HasSecretValues",      -- () -> bool            Era false, Forever true (R5 gate)
  "EditModeHint",         -- () -> string          how to open Edit Mode on this client
  -- Frame roots
  "UnitButton",           -- (frameID) -> Button   PlayerFrame / TargetFrame / PetFrame / ...
  "Unit",                 -- (frameID) -> unitToken
  -- Regions (Era examples; Forever returns the Mainline equivalents)
  "HealthBar",            -- (frameID) -> StatusBar     PlayerFrameHealthBar
  "PowerBar",             -- (frameID) -> StatusBar     PlayerFrameManaBar
  "FrameArt",             -- (frameID) -> Texture       PlayerFrameTexture / TargetFrameTextureFrameTexture / PetFrameTexture
  "Portrait",             -- (frameID) -> Texture       PlayerPortrait / TargetFramePortrait / PetPortrait
  "NameText",             -- (frameID) -> FontString    PlayerName / TargetFrameTextureFrameName / PetName
  "HealthTexts",          -- (frameID) -> { FontString, ... }   TextString, LeftText, RightText of the health bar
  "PowerTexts",           -- (frameID) -> { FontString, ... }
  "StockLevelRegions",    -- (frameID) -> { Region, ... }      PlayerLevelText + PlayerFrameLevel ring art; TargetFrame LevelText + HighLevelTexture
  "NameBackground",       -- (frameID) -> Texture|nil   TargetFrameNameBackground (target/focus only)
  "BarSlot",              -- (frameID, "health"|"power") -> { x, y, w, h } relative to UnitButton: where the art's bar slot is (measured, per flavour)
  "MovableBars",          -- (frameID) -> { StatusBar, ... }  the bars R2-exception may move (Era: both; Forever: none)
  -- Values
  "UnitDisplayName",      -- (unit) -> string   two-name aware (PROJECT_STRUCTURE rule)
  "HealthValues",         -- (unit) -> cur|nil, max|nil, pct|nil
  "PowerValues",          -- (unit) -> cur|nil, max|nil, pct|nil, token|nil
  "UnitIsSameUnit",       -- (a, b) -> true|false|nil
  "DifficultyColor",      -- (level) -> {r,g,b}
}
```

### Frame strategies — Era restyles in place, Forever overlays

This is the one place the two clients differ in *approach*, and it is the lesson from EasyFrames' two trees:

| | Era (11509) | Forever (16001) |
|---|---|---|
| Stock bar children | Plain `StatusBar`s, non-secure, measurable | Inside `HealthBarsContainer` with masks; several regions restricted; heal-prediction/absorb overlays |
| Bar geometry | **Restyle in place**: `Geometry.SetHeight/Move` on `Client.MovableBars()` to fill `Client.BarSlot()`. EasyFrames-Era proves this is stable (`MoveRegion` + a `SetPoint` re-assert hook). Player health 27 px; pet health **17 px / power 8 px** (fills the slot — fixes EF's 13 px bug). | **Overlay**: our own `StatusBar` per bar (`VFS_OverlayBar`) sized to `BarSlot()`, fill driven by `hooksecurefunc` on `UnitFrameHealthBar_Update` / `UnitFrameManaBar_Update` reading the **stock bar's `GetValue()/GetMinMaxValues()`** (never `UnitHealth` — R5), stock fill alpha-zeroed (EF-Forever's `ForceHiddenFill`). |
| Backdrop | `VFS_BarBackdrop` holder one level under the bar, black at `backingAlpha` (VPTF's implementation) | Same holder under the overlay bar |
| Fill texture | `SetStatusBarTexture(path)` on the stock bar | on the overlay bar |
| Fill colour | **never set** (stock reaction/class colouring stays) — option `classColorHealth` re-applies via `hooksecurefunc("UnitFrameHealthBar_Update")` with `Plain(UnitClass)` | same |
| Text | our FontStrings via TextLayout; stock texts alpha-zeroed | same |
| Frame art | `FrameArt():SetVertexColor(d,d,d)` for `borderDarken`; classification swaps left to Blizzard | same |

The frame module code is identical on both clients; only `Client.MovableBars()` (Era: bars, Forever: `{}`) and
`FrameBase.AcquireBar(frameID, kind)` (returns the stock bar when movable, else creates/returns the overlay) differ.

### Text elements — the grid (R9)

Identical to PlateStyle's `VPS_TextElement`, per frame, with unit-frame slots:

```lua
-- VFS_TextElement (one row of VelocityFrameStyleDB.frames[frameID].elements, in display order)
{ id = "health", label = "Health", format = "[hp]",
  anchor = "health",   -- VFS_TextAnchor: health | power | nameplate | above | below | hidden
                       --   health/power = inside that bar; nameplate = the name strip (target/focus) or the name row (others)
  align  = "center",   -- left | center | right
  size   = 10, color = "white" }   -- VFS_ColorMode: stock | white | difficulty | class | reaction | custom (customColor {r,g,b})
```

Built-ins per frame: `name [name]`, `level [level]`, `health [hp]`, `healthpct [hp%]`, `power [power]`, `powerpct [power%]`.
Defaults (every frame): name → nameplate/center/10/stock; level → nameplate/right/10/difficulty **(fix for the
level-badge wish: level lives on the frame, not a separate ring, on every frame including Pet)**; health → health/center/10/white;
power → power/center/10/white; the two percents hidden. Custom elements as PlateStyle (`c<n>`, player-entered format).

`Format.Expand` is PlateStyle's with three added tokens: `[power]`, `[power%]`, `[powermax]` (via `Client.PowerValues`,
secret → `""`). `Format.UsesHealth/UsesPower` gate the Era-only `UNIT_HEALTH`/`UNIT_POWER_UPDATE` registrations.
PetTarget's elements refresh on its 0.2 s tick (R4 exception) instead.

**Shared engine:** `Core/TextLayout.lua` is PlateStyle `Skin.LayoutTexts` + `ApplyTexts` with the slot rectangles supplied by
the caller (`slots = { health = bar, power = bar, nameplate = region, above = ..., below = ... }`). Once stable it is
copied back into PlateStyle so both addons run one implementation (tracked in PlateStyle's spec, not here).

### PetTarget module

Ported from `VelocityPetTargetFrame` with these changes **[D]**:
- `healthTextFormat`/`powerTextFormat` radios removed; the frame uses the grid like every other frame.
- Frame global renamed `VelocityFrameStylePetTarget`; binding `CLICK VelocityFrameStylePetTarget:LeftButton`.
- `petFrameLevel` becomes the Pet frame's `level` element (grid), `petFrameBarBackdrop` becomes the Pet frame's `backingAlpha`.
- Everything in VPTF spec §3–§4 (secure `state-visibility` driver, soft-hide for same-target, Edit Mode forced-visible
  sample, per-layout placement, default anchor right of PetFrame) is unchanged.

## Settings model

```lua
VelocityFrameStyleDB = {
  version = 1,
  global = {                                  -- VFS_GlobalSettings (account-wide appearance)
    barTexture = "Blizzard",                  -- VFS_TextureKey (built-ins + LSM)
    borderDarken = 1.0,                       -- 0.0 (black) .. 1.0 (stock); EasyFrames' "bright frames border" equivalent
    backingAlpha = 0.6,                       -- VFS_BarBackdrop opacity, all frames
    classColorHealth = false,                 -- players only
    portraitStyle = "default",                -- default | class_old | class_new
    petTargetHideWhenSame = false, petTargetFlashOnNew = true, petTargetScale = 0.8,
  },
  frames = {                                  -- [VFS_FrameID] = VFS_FrameSettings
    player = { enabled = true, elements = { ...VFS_TextElement... } },
    target = { ... }, pet = { ... }, pettarget = { ... },
  },
  profiles = { [layoutName] = { petTargetPlacement = VFS_Placement } },   -- per Edit Mode layout (LayoutProfile)
}
```

Nothing is per character. Keys, where any ever become per-character, are `UnitGUID("player")` (workspace rule).

## Options — one GotJunk-style page (M0) [D 2026-11-24]

**Start with ONE canvas page**, PlateStyle/GotJunk style (scroll frame, bordered `Section`s, `InterfaceOptionsCheckButtonTemplate`,
`OptionsSliderTemplate`, radio rows, `VFS_MediaPicker`). Section order: **About** · **Theme** (the global defaults below) ·
one **section per frame** (Player / Target / Pet / Pet Target: Enabled, overrides, Text grid, extras) · **Blizzard** · **Reset**.
Rationale: with the element-grid model the per-frame settings are small (a handful of rows + 3–4 overrides), so a single page
is expected to fit; EasyFrames' sub-page tree existed to hold its format-string sprawl, which we don't have.

Code is written so the split is a **one-function change**: every frame section is produced by `UI/FramePage.lua`'s
`BuildFrameSection(parent, frameID)` returning a `Section`; the page builder just places them. Shared builders live in
`UI/Widgets.lua` (Check, Slider, Radios, Section, Place — lifted from GotJunk/VPTF). `/vfs` opens the page.

### Back-pocket: EasyFrames-style sub-page tree (NOT in M0)

If the single page grows past comfortable scrolling (M3 adds ToT / Party / Focus / Boss), switch to **one parent category
with one sub-page per frame**, as EasyFrames does. Registration: `Settings.RegisterCanvasLayoutCategory(parentFrame, name)`
then `Settings.RegisterCanvasLayoutSubcategory(parentCategory, childFrame, name)` per frame, `Settings.RegisterAddOnCategory(parent)`;
legacy `InterfaceOptions_AddCategory(child)` with `child.parent = parentName` where the new API is absent. `BuildFrameSection`
then targets a child canvas instead of the main page; `/vfs <frame>` deep-links via `Settings.OpenToCategory(childCategory:GetID())`.
The content below is written page-agnostically for that reason.

**Theme section (parent page in the tree variant) — global defaults:**
- About: stand-down status, Edit Mode hint (`Client.EditModeHint()`), *Open Edit Mode* button.
- Theme: `VFS_FrameStyle` (M4; classic only until then), bar texture (`VFS_MediaPicker` statusbar), backing alpha,
  border darkness, class-coloured health, portrait style, default text font (`VFS_MediaPicker` font) — these are the
  **defaults every frame inherits**.
- Blizzard: button to the game's own Edit Mode / unit-frame settings. Reset-all.

**Frame sub-page (one `UI/FramePage.lua` builder, parameterised by `VFS_FrameID`):**
- Enabled.
- Overrides: *Use theme bar texture / backing / border / font* checkboxes; unticked reveals that frame's own picker.
  (Settings model: `frames[id].override = { barTexture = nil|key, backingAlpha = nil|n, ... }`, `nil` = inherit.)
- **Text** grid (the `VFS_TextElement` rows; M0 fixed rows, M2 reorder + custom-element box). Same widget code as
  PlateStyle's grid so it back-ports with `TextLayout`.
- Frame-specific extras: Pet Target → hide-when-same, flash on new target, scale, *Copy text layout from Target*;
  Pet → nothing extra in M0 (level and backdrop are now grid/theme).
- Reset this frame.

Shared builders live in `UI/Widgets.lua` (Check, Slider, Radios, Section, Place — lifted from GotJunk/VPTF Options.lua);
`UI/Options.lua` creates the parent and iterates `Frames/*` to create sub-pages. `/vfs` opens the parent; `/vfs <frame>`
(`player|target|pet|pettarget`) opens that sub-page via `Settings.OpenToCategory(childCategory:GetID())`.

Settings model addition (replaces the single `frames[id] = { enabled, elements }` shape above):
```lua
frames[VFS_FrameID] = {
  enabled  = true,
  override = {},            -- VFS_FrameOverrides: barTexture, backingAlpha, borderDarken, font, portraitStyle; nil = theme
  elements = { ...VFS_TextElement... },
}
```

## Visual media pickers — REQUIRED [D 2026-11-24]

**Owner directive, verbatim intent:** *bring up the EasyFrames-style VISUAL bar-texture selector; it will then be ported
into PlateStyle (which was supposed to have it and does not). It may be an internal copied/vendored module.*

What EasyFrames shows (screenshot 2026-11-24): a dropdown whose every row is **drawn in that statusbar texture** with the
name on top; the font picker likewise draws each row in that font. These are the `LSM30_Statusbar` / `LSM30_Font` widgets
from **AceGUI-3.0-SharedMediaWidgets** (`StatusbarWidget.lua` 6.7 KB, `FontWidget.lua` 6.2 KB, `prototypes.lua` 8.9 KB;
MIT-style "AceGUI widgets" licence), which require AceGUI-3.0 and LibSharedMedia-3.0.

**Decision: do not vendor Ace.** We have no AceGUI (PlateStyle/GotJunk canvas pages are plain frames). Instead:

- `UI/MediaPicker.lua` — **`VFS_MediaPicker`**, a self-contained plain-frame reimplementation of the two widgets:
  a button showing the current choice *rendered in its own texture/font*, opening a scrollable list (`UIPanelScrollFrameTemplate`
  + row pool) where each `VFS_MediaPickerRow` is a `StatusBar` filled with that texture (statusbar mode) or a `FontString`
  set to that font (font mode), name overlaid, checkmark on the current value. Mouse-wheel scroll, Esc/click-outside closes.
  Structure and behaviour cloned from `StatusbarWidget.lua`/`FontWidget.lua` (read them in M0b; credit in the header).
- Media sources: `Core/Textures.lua` built-ins **plus** `LibStub("LibSharedMedia-3.0", true)` when any addon loaded it
  (EasyFrames registers its 13 textures; Details etc. register theirs — the long list in the screenshot). Without LSM the
  picker still works on built-ins. We do **not** ship LSM; we never register media into it.
- API: `MediaPicker.Create(parent, kind, get, set)` with `kind = "statusbar" | "font"`; `:Update()` like every other
  options widget. Zero dependencies beyond `Core/Textures.lua`, so the file can be **copied unchanged into PlateStyle**
  (`VelocityPlateStyle\MediaPicker.lua`) to close PlateStyle's M2b. One source of truth: PlateStyle's copy is overwritten
  from VFS, never edited independently (note in both files' headers).
- Used by: Bars section (bar texture), every font dropdown in the text grid (M2) and the pet-target fonts (M0).

Rejected: vendoring AceGUI-3.0 + the widget pack (drags in ~250 KB of Ace for two controls, and AceGUI widgets cannot be
placed on our canvas without an AceGUI container); a plain `UIDropDownMenuTemplate` text list (what VPTF does today —
exactly the thing the owner does not want).

**Acceptance:** the Bars section dropdown looks like the EasyFrames screenshot — each row drawn in its texture — on Forever,
with LSM-registered textures listed when EasyFrames or Details is also loaded.

## Open questions

- Era `TargetFrameNameBackground` is the reaction-coloured strip; our `nameplate` slot sits on it. Forever's equivalent is
  `TargetFrameContentMain.ReputationColor` — confirm during M1 whether it may be alpha-zeroed without Blizzard re-showing it each update.
- Does Era re-assert bar anchors anywhere other than `PlayerFrame_ToPlayerArt` / `PetFrame:Update`? (EF-Era hooks `SetPoint`
  to win; we prefer a post-hook on the known re-anchor functions. Confirm via `/fstack` + `hooksecurefunc` tracing in M0.)
- `TextLayout` back-port to PlateStyle: do it as soon as M0 is stable, or wait for PlateStyle M2b (texture picker) so both
  land together? Owner's call when M0 ships.
- PetTarget frame art is the full 232×100 TargetFrame look (VPTF decision). With VFS also restyling the real Target frame,
  should PetTarget inherit Target's *bar* settings automatically (not just the copy button)? Leaning no — independent, copy on demand.