# Client refactor → Classic Era: implementation handoff

**Owner-approved direction, 2026-11-25.** Implement incrementally; checkboxes below are not yet complete.
**Start here next session.** Detailed findings: [07_Client_Interface_Era_Readiness_Review.md](07_Client_Interface_Era_Readiness_Review.md).

## Baseline and decisions

- Working repo: `VelocityFrameStyle/`; shipped addon: `VelocityFrameStyle/VelocityFrameStyle/`. Baseline commit: **`2d4c402`**.
- **Approved:** same geometric appearance and default bar dimensions on Era; only native anchor offsets/region mappings differ.
- **Approved:** preserve and explicitly position Era hunter-pet happiness (`PetFrameHappiness`), above chrome and clear of portrait/text.
- Keep separate `Client_ClassicEra.lua` / `Client_Forever.lua`; select once. No flavour branches in frame/rendering/UI modules.
- Keep the rounded atlas, six-unit borders, independent bar dimensions, four text rows and opaque yellow predictions. Native values/events stay Blizzard-owned.
- Keep Pet Target health-only **on by default**, per-Edit-Mode-layout placement, and no same-target hiding. Do not revive deferred secret-capacity investigation.
- Owner publishes/tests; assistant **never installs into game folders** and commits only after owner confirms the phase in game.
- Read `AddonManagement/PROJECT_STRUCTURE.md` first. Inspect `git status` before edits; review/plan documents may still be uncommitted.

## Phase E0 — Establish the contract and baseline

- [ ] Run the eight existing `Tests/*.lua` scripts with `lua5.1`; syntax-check shipped Lua with `luac5.1 -p`. Record current Era build/project ID and test characters.
- [ ] Audit references; remove unused `StockValueText`, `AdoptStock` / `vfsAdopted` paths and unused capability methods (`HasSecretValues`, focus/boss flags, `NameBackground`) only after confirming no active consumer. Preserve the keep-list contract.
- [ ] In `Client.lua` / `Client_Select.lua`, define required methods versus optional capabilities. Missing required implementation or unknown client must stop styling with a useful message—not silently select Forever or install nil-returning stubs.
- [ ] Define return shapes: missing optional region = nil; region collection = table; unsupported feature = explicit reason; formatted text may be secret, with a separate ordinary availability flag.
- [ ] Add selector and adapter contract tests. Correct stale comments (notably Geometry's claim that Forever MovableBars is empty). **Gate: Forever appearance unchanged.**

## Phase E1 — Move native hooks and legal anchors behind adapters

- [ ] Extract hook-name/function selection from `Frames/Player.lua`, `Target.lua`, `Pet.lua`, `ToT.lua` into `Client.InstallFrameHooks(binding, callbacks)`. Callbacks report appearance invalidation, value changes and native visibility changes. Register once per native object.
- [ ] Replace the blanket `MovableBars` assumption with audited bar capabilities and `Client.GetNativeAnchorSpec(binding, barKind)`. Return **Frame-relative** anchors; never anchor a protected StatusBar to a portrait Texture.
- [ ] Fix `Core/Geometry.lua`: validate before clearing points; store the new desired spec before reassert hooks run; use a reentrancy guard; preserve/restore previous safe placement if applying the new one fails.
- [ ] Queue complete anchor/size changes during combat; apply after regen. Do not merely queue dimensions while dropping position changes.
- [ ] Connect the actual ToT refresh lifecycle; either dispatch `ToT.OnEvent` appropriately or remove that unused handler in favour of tested native hooks.
- [ ] Test new-spec-over-old-spec ordering, failed-anchor safety, combat deferral and idempotent hooks. **Gate: Forever targeting/pet updates and ToT produce no new errors or blocked anchors.**

## Phase E2 — Consolidate bindings; complete Era frame coverage

- [ ] Introduce `Client.ResolveFrameBinding(VFS_FrameID)` → `VFS_FrameBinding` + availability/reason. Record unit token, button, portrait, name/level regions, health/power bindings, chrome and keep-list. Use semantic field/type names, not anonymous positional tuples.
- [ ] Migrate existing getters/call sites in small steps; remove superseded accessors after all consumers move. Do not leave duplicate sources of truth.
- [ ] Construct addon-owned Pet Target binding once in shared code; native adapters must not duplicate its region lookups.
- [ ] Complete Era mappings for **Player, Target, Pet, ToT, Pet Target**. Add the missing `tot → targettarget` mapping and all ToT regions. Cross-check XML parentKeys/global names and in-game `/vfs status`.
- [ ] Preserve current Era Target `textureFrame.HealthBarText/HealthBarTextLeft/HealthBarTextRight` and corresponding mana fields; do not substitute Forever's hierarchy.
- [ ] Use shared style dimensions plus adapter-native anchor references. Keep frame zoom separate; do not resize portraits/fonts/borders when changing bar dimensions.
- [ ] Add Era happiness to preserved functional regions and give it an explicit, non-overlapping placement. Never suppress it as decorative chrome.
- [ ] Add real-shaped Era/Forever frame-tree fixtures, including absent optional regions and late-created ToT. **Gate: both clients boot and all five frames update, retain functional icons and expose correct settings.**

## Phase E3 — Verify value, visibility and Edit Mode semantics

- [ ] Retain `Client.FormatBarValue` → opaque display text + availability. Test Current, Current / Max, Percent and Hidden independently per frame/bar; no global CVar writes and no arithmetic/comparisons on secret outputs.
- [ ] Replace misleading `HasPowerResource` semantics with `Client.GetPowerRowState(binding)` → visible / hidden / unknown plus source. Native Target follows its native bar; Era may use verified readable capacity. Unknown is not zero. Pet Target manual health-only takes precedence, including preview.
- [ ] Verify the installed Era APIs rather than assuming all data is non-secret or all frames unprotected. Shared identical APIs need not be wrapped merely for abstraction's sake.
- [ ] Preserve existing `Core/LayoutProfile.lua` and LibEditMode flow: current Era reference XML includes Edit Mode. Adapt only demonstrated differences.
- [ ] Test drag → exit → reload; switch layouts away/back; rename/create/delete layouts; dimensions persist independently of placement. **Gate: no regression of the previously fixed pet-target anchor-default bug.**

## Phase E4 — Era prediction parity

- [ ] Audit Era native prediction widgets against actual source/runtime. Reference XML already defines incoming-heal segments on Player/Target/Pet; `PredictionSegments()` currently returns empty.
- [ ] Expose explicit prediction-binding kinds through the adapter. Shared styling currently expects `segment.Fill`, `FillMask` and `UpdateFillPosition`; only reuse that strategy when the actual widget satisfies it.
- [ ] Keep native segment values, width calculations, FillMask anchors and Show/Hide untouched. Replace only the audited art-window mask and cosmetic fill; retain prediction < border < text layering.
- [ ] Add Era incoming heals; verify whether player mana-cost prediction exists on the tested Era build. If absent, document it and obtain owner agreement before declaring parity—not a fake or silently missing feature.
- [ ] Test cast/start/cancel/complete, receiving heals while injured, resizing and texture changes. **Gate: correct segments, no overflow or new taint errors on either client.**

## Phase E5 — Regression pass and handoff completion

- [ ] Run all existing and new Lua tests, parse every shipped Lua file, check all three TOC load orders and `git diff --check`. Regenerate atlas only if its generator/data changed.
- [ ] In game on both clients: target swaps; pet summon/dismiss; ToT changing units; rest/combat transitions; skull/classification/happiness; health-only toggle; text formats; texture reapplication; short/tall/wide rounded bars.
- [ ] Exercise settings and Edit Mode outside combat, and permitted cosmetic updates/deferred geometry during combat. Check fresh BugJar entries after reload.
- [ ] Verify disabling styling restores the intended native regions without leaving opaque overlays or active suppression behind.
- [ ] Update adapter/API notes with **observed build-specific results**, close only confirmed items, and commit owner-approved phases individually.

## Visual cleanup list — AFTER E0–E5 are confirmed on Classic Era

Owner-requested polish, 2026-11-25. **Not part of the refactor gates**; start only once E5 has passed on both clients. Each item is its own
publish → play-test → commit round. Items marked *(spec first)* need a short decision note (or a new numbered SPEC) before code.

- [ ] **Combat glow = tinted duplicate of every bar outline** *(implemented 2026-11-25, awaiting owner in-game confirmation; pulled forward
      from the cleanup list because the Era test exposed it)*. Was a 2-unit flat square envelope around the stack. Now `Chrome.Create` builds
      one rounded-atlas ring per bar (`glow.rings[kind]`, same inner rect, one level above that bar's black ring), tinted `combatGlowColor`,
      all on the throbbing `glowFrame`. `FrameBase.RefreshPowerVisibility` zeroes `glow.rings.power` with the power bar on Target / Pet Target.
      Open: if 0.7-alpha red hides the black outline at peak throb, lower it; a feathered soft-glow atlas variant remains a later option.
- [ ] **"Portrait adornment" position for text elements.** Keep the existing per-element *Position* setting (nameplate / health / power /
      above / below / hidden) and add one more anchor value, **portrait adornment**: a small gold-ringed circle (our own disc + ring art, not
      Blizzard's alpha-zeroed `LevelBackgroundCircle`) overlapping the portrait disc's **lower-left** edge, as the old VelocityPetTargetFrame
      drew its level (owner reference, Era 2026-11-25). Anchored to the portrait, so bar dimensions never move it. Intended for the Level
      element (default it there on Player and Pet; Pet level is our text from `UnitLevel`, Blizzard has no pet level region) but any single
      element may select it. When the Level sits there the badge becomes the Target skull/classification anchor instead of the row text.
- [ ] **Elite / rare / boss / skull (`??`) verification.** Test the Target level row against each classification: normal, elite, rareelite, rare, worldboss,
      and over-level `-1` → skull / `??`. Confirm the kept `HighLevelTexture` / `BossIcon` and our level text agree on every client; record findings in 03_Text_Template.md.
- [ ] **Danger cues from VelocityPlateStyle** *(spec first)*. Port the VPS M2c/M2d behaviours to the Target (and Pet Target) frame: over-level threshold turns
      the level text skull-red, inline `UI-TargetingFrame-Skull` per level above the player (`skullAtLevelsAbove`), friendly/non-attackable units get no cue.
      Reuse the `SkullCount` / `IsHostileThreat` logic (shared via copy, not a cross-addon dependency). Whether the animated bar sweep is wanted on unit frames is an open owner decision.
- [ ] **Border picks** *(spec first)*. Extend `Scripts/GenerateRoundedBorderAtlas.cs` / 06_Rounded_Border_Atlas.md to produce variants: thinner border
      thickness and smaller corner radius. Expose as a theme setting (with per-frame override, like texture/font). Keep the six-unit layout contract.
- [ ] **Alternate rectangular layout** *(spec first)*. A square-portrait / straight-bar layout option as an alternative to the current rounded look;
      decide whether this is a border variant (radius 0) plus portrait mask swap, or a distinct layout preset. Default remains the rounded layout.

## References and remaining boundaries

- Ground truth: `AddonManagement/_EXTERNAL_APIS/wow_unitframe_regions_forever_vs_era.md`, `wow_edit_mode_layouts_api.md`; `_ref/blizzard/classic_era/{PlayerFrame,TargetFrame,PetFrame}.xml`; `_ref/blizzard/forever/unitframe/`. Some prose is historical: check current source before trusting capability claims.
- Current behavior specs: `03_Text_Template.md`, `05_Player_Prediction_Overlays.md`, `06_Rounded_Border_Atlas.md`. Deferred issue: `AddonManagement/_BUGFIX/14_BUG_VelocityFrameStyle_PetTarget_Empty_Power_Row.md`.
- **TBD at session start:** actual Era build and available test characters; exact happiness anchor chosen during layout verification; native Era mana-cost prediction availability.
- Do not add focus/party/boss support, resurrect target-equality hiding, or fold in the pending black connector. Those are separate tasks.
- Mock tests do not prove live API permissions, secret-value behavior or rendering. Each phase requires the owner's game check.

**First implementation action:** inspect repository state, run the baseline tests, then begin E0. Do not start by copying Forever's frame paths into the Era adapter.