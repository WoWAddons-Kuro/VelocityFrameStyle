# Client interface cleanup and Classic Era readiness review

**Status:** review completed, 2026-11-25. Owner approved same geometric defaults and preservation of Era pet happiness; no implementation changes made yet.
**Implementation handoff:** [08_Client_Refactor_Era_Implementation_Plan.md](08_Client_Refactor_Era_Implementation_Plan.md).
**Baseline:** `2d4c402` (rounded borders). Target clients: Forever 16001 and Classic Era 11509; verify actual installed builds during smoke testing.

## Preserve the working architecture

- Keep separate `Client_ClassicEra.lua` / `Client_Forever.lua`, selected once; no scattered flavour branches in shared modules.
- Keep shared border atlas/rendering, bar dimensions, settings, text grid and appearance policy.
- Keep native bar values/events/predictions under Blizzard ownership.
- Keep `FormatBarValue` as the client boundary for value rendering; do not return to global CVar formatting or stock-string adoption.
- Pet Target is addon-owned: its frame binding should be shared, not duplicated in each native adapter.
- Preserve health-only default and removed same-target hiding. Deferred secret capacity issue remains deferred.

## Findings (priority order)

| Priority | Finding / evidence | Consequence / correction |
|---|---|---|
| P1 | `Client_ClassicEra.lua:8–15` omits tot; all corresponding region resolvers omit it too. DB now registers tot. | ToT.Create returns early; status has missing regions. Add complete Era ToT bindings and lifecycle hooks, not just a DB entry. |
| P1 | `Frames/Player.lua:24–27`, `Target.lua:30–32`, `Pet.lua:25–26`, `ToT.lua:27–28` choose native global functions/methods directly. | Client adaptation is leaking into frame modules. Move native hook selection into adapters and expose semantic callbacks. |
| P1 | `Frames/ToT.lua:14` and `Pet.lua:14` anchor a StatusBar to a portrait Texture. Owner already captured a protected ToT anchor failure. `MovableBars` simply returns every resolved bar. | Existence does not prove a legal anchor/capability. Adapters must supply frame-relative legal anchor specs. Validate before ClearAllPoints. |
| P1 | `Geometry.lua:28–32` clears points before a potentially rejected SetPoint; failure can leave a bar unanchored. Its reassert hook is installed before later new specs are assigned (`:38–45`). | Make geometry application guarded and ordered: validate, store new desired spec, apply, restore previous safe state on failure. Defer complete placements as well as dimensions in combat. |
| P1 | `Client_Select.lua:14–16` falls back to Forever for unknown clients. `:26–34` installs nil-returning stubs for missing methods and still advertises success. | Wrong clients/contracts fail much later. Stop unsupported client initialization with a useful diagnostic; distinguish required/optional methods and give optional collection methods typed empty results. |
| P2 | `Client_ClassicEra.lua:30` returns no PredictionSegments. Era PlayerFrame.xml:286–287, TargetFrame.xml:300–301 and PetFrame.xml:107–108 define native heal segments. | Wire existing Era overlays after confirming runtime shape. Do not reimplement heal arithmetic. Era mana-cost availability requires separate verification. |
| P2 | Shared StylePrediction in FrameBase requires segment.Fill, segment.FillMask, frame-level methods and UpdateFillPosition. | This is a specific widget contract, not generic prediction support. Describe the supported segment kind in the adapter; provide another strategy only when verified necessary. |
| P2 | HasPowerResource has a stronger name than its proven semantics. Forever UnitHasPowerType returned true with max=0. | Separate 'native row shown', 'known usable capacity', and 'unknown'; never conflate resource association with capacity. Preserve manual health-only policy. |
| P2 | StockValueText has no active consumer; AdoptStock and vfsAdopted branches are remnants. HasSecretValues, HasFocusFrame, HasBossFrames and NameBackground have no meaningful current use beyond definitions/interface. | Remove unused interface surface and adoption branches after reference search; keep deliberate keep-list metadata as diagnostics/invariant checks. |
| P2 | Core bootstrap does not dispatch ToT.OnEvent; current live refresh relies on native hooks. | Explicitly connect ToT lifecycle or remove misleading dead event handler. Test the actual refresh path on each client. |
| P2 | Text/value tests cover numeric formatting but do not exercise complete Era frame trees or native hook registration. | Add adapter fixtures and boot/event tests; current tests are not evidence of Era rendering correctness. |

## Era-specific source evidence and cautions

- `_ref/blizzard/classic_era/PlayerFrame.xml`, `TargetFrame.xml` and `PetFrame.xml` contain current Edit Mode templates. Preserve shared LayoutProfile logic unless an actual API difference is found.
- Era Target text fields in `textureFrame` use HealthBarText / HealthBarTextLeft / HealthBarTextRight and corresponding ManaBar names. Current adapter matches these; preserve them during restructuring.
- Era ToT uses flat named regions such as TargetFrameToTPortrait and TargetFrameToTHealthBar rather than Forever's parent-key paths. Confirm exact names against XML plus in-game diagnostics.
- Era pet happiness (`PetFrameHappiness`) needs an explicit keep/position decision so it is not obscured by our portrait layer.
- The reference XML also contains a FocusFrame definition although the Era adapter hardcodes HasFocusFrame=false. This is a reason to avoid broad capability claims; adding focus support is not part of this port.
- Header claims like 'Era has no secret values' and 'all bars are movable' should not be treated as global API guarantees. Verify the APIs actually used on the installed build; keep value opacity separate from protected frame operations.
- Shared use of a genuinely identical API (e.g. SetStatusBarTexture or UnitGUID) is not inherently a boundary violation. Move divergent behavior, not every function call, into adapters.

## Proposed smaller, explicit contract

Names are proposals, not a request for a large rewrite:

- `Client.ResolveFrameBinding(VFS_FrameID)` -> `VFS_FrameBinding` or an explicit unavailable reason.
  - Unit token, native button, portrait, name/level regions, health/power bindings, suppressed chrome, keep-list.
  - Bar binding distinguishes native StatusBar from the addon-owned pet-target bar.
  - Optional regions are nil; region collections are always tables.
- `Client.GetNativeAnchorSpec(binding, barKind)` -> legal frame-relative placement, or unsupported reason.
  - Appearance dimensions stay in shared settings; adapter supplies native geometry references/offsets only.
- `Client.InstallFrameHooks(binding, callbacks)` -> hook/capability report.
  - Callbacks such as appearance invalidated, values changed, and native visibility changed.
  - Adapter owns native global/method names; shared handlers own style application.
- `Client.FormatBarValue(unit, kind, format)` remains -> opaque text + ordinary availability flag.
- `Client.GetPowerRowState(binding)` -> visible / hidden / unknown, with a documented source.
- `Client.GetPredictionBindings(binding)` -> descriptors with an explicit verified widget kind.

Do not replace the existing resolvers wholesale in one commit. First extract hooks/anchor specs using existing accessors, stabilize Forever, then consolidate repeated region lookups into bindings.

## Incremental implementation and acceptance

- [ ] **E0 — Contract/test baseline:** remove dead APIs and misleading comments; introduce required/optional validation; snapshot current Forever mappings. No visual changes.
- [ ] **E1 — Native hooks and safe geometry:** adapters own hook names and legal anchors; fix ToT anchor failure and stale geometry reassertion. Confirm Forever unchanged in game before commit.
- [ ] **E2 — Era bring-up:** complete five-frame mappings (Player, Target, Pet, ToT, Pet Target); status reports missing required regions explicitly; test load, target changes, pet summon/dismiss, health/power updates and disabling styling.
- [ ] **E3 — Era parity:** attach verified native heal predictions and, if available, mana-cost predictions; preserve rest/swords/skull/happiness; validate rounded borders and dimensions at minimum/maximum settings.
- [ ] **E4 — Profile/combat matrix:** drag/save/reload/switch layouts on both clients, resize before/during/after combat, cast/cancel, health-only on/off, text format changes, texture replacement/reapplication and no new blocked-action errors.

Testing additions:
- [ ] Fixture tables representing actual Era and Forever region trees; every registered frame has settings and a valid native binding or explicit unsupported status.
- [ ] Hook registration tests for each flavour, no duplicate hooks, and ToT updates.
- [ ] Geometry tests: reject protected-frame-to-texture anchors before mutation; new desired anchor wins over prior cached anchor; combat-deferred placement applies after regen.
- [ ] Client selector tests: Era, Forever, unknown project/build, missing required methods, optional predictions absent.
- [ ] Prediction descriptor tests with absent optional regions, masks and client-specific widget forms.
- [ ] In-game testing remains required: mocks cannot establish secret-value semantics or protected-operation permissions.

## Owner decisions and remaining questions

- **Approved:** same geometric appearance and default bar dimensions on Era; adapt only native anchor references/offsets as necessary.
- **Approved:** preserve and explicitly position Era hunter-pet happiness as functional kept UI.
- Sequencing and actionable checkboxes are in `08_Client_Refactor_Era_Implementation_Plan.md`; use that as the next-session entry point.
- Exact installed Era build, test characters/classes, happiness placement and native mana-cost prediction availability remain to be verified.

Related: SPECS/00_VelocityFrameStyle.md, 03_Text_Template.md, 05_Player_Prediction_Overlays.md, 06_Rounded_Border_Atlas.md; AddonManagement/_EXTERNAL_APIS/wow_unitframe_regions_forever_vs_era.md; _BUGFIX/14_BUG_VelocityFrameStyle_PetTarget_Empty_Power_Row.md.
The black portrait-to-bar connector is separate pending work, not a dependency of this port.