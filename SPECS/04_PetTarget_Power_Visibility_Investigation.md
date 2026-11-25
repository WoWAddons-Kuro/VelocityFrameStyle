# Pet-target empty power row — unresolved, 2026-11-25 02:19

**DEFERRED by owner.** Tracking note: `AddonManagement/_BUGFIX/14_BUG_VelocityFrameStyle_PetTarget_Empty_Power_Row.md`.
Do not resume this investigation unless requested; prediction overlays and other cleanup remain pending.

## Confirmed runtime evidence

- Native Target hides its power bar; mirroring IsShown correctly collapses VFS Target.
- Same enemy: target and pettarget current/max are secret. On-screen widget-sink diagnostic shows both API maxima and both widget ranges/current are all zero.
- Custom TextStatusBar updater fails at Blizzard_TextStatusBar/TextStatusBar.lua:110: comparing secret number under VelocityFrameStyle taint.
- That failed template/updater experiment has been removed; custom pet-target uses a plain StatusBar again.
- UnitHasPowerType(pettarget, 1) returns ordinary true for the same zero-max RAGE NPC. It is NOT sufficient for this visibility decision. Current guarded HasPowerResource implementation consequently keeps the row visible.
- NativeUpdater=false in diagnostics does not prove a different implementation: VFS hooks the target UpdateTextString method, wrapping it.
- No evidence for a safe general 'hide NPC rage' rule. Do not add that heuristic.

## Source/API findings

- Forever branch UnitDocumentation.lua marks UnitPowerMax secret under restrictions; UnitHasPowerType has a bool return without a secret annotation, but runtime disproves its suitability here.
- Generic TextStatusBar Lua checks valueMax > 0. Calling it from addon code does not make the call trusted.
- Forever LuaCurveObject.Evaluate and region SetHeight/SetWidth documentation allow secret arguments only when untainted. Do not assume arbitrary curve-driven layout works in addon code.
- Reviewed public SimpleStatusBar API documentation has no SetUnit/SetPowerTextFontString binding methods.
- EasyFrames retains Blizzard's native Target mana bar; its CreateBarBackground keepWhenHidden flag intentionally preserves an empty art slot. It does not demonstrate custom pet-target capacity detection.

## Open issues / next investigations

- Need a documented engine-controlled resource-visibility mechanism for arbitrary custom units, or explicitly limited behavior accepted by owner.
- Mirroring native Target is only possible when UnitIsUnit returns a readable true. That boolean can itself be secret; this is NOT reliable combat automation and does not solve independently targeted enemies.
- Lazy Thom's installed PetTarget.lua:396–409 explicitly retains an empty dark slot; it offers no automatic collapse solution.
- The supplied blocked-action stack shows Blizzard Settings/gamepad navigation during category interaction in combat, while the owner was collecting diagnostics. It does not identify VFS as the taint source; keep this separate.
- Separate confirmed ToT geometry warning: protected StatusBar cannot anchor to portrait Texture; change its reference to an appropriate Frame after reading exact geometry.
- Prediction overlays remain pending. Research found the native full-bar art masks need refitting while preserving per-segment FillMasks; no implementation yet.

No further visibility behavior change was made after the true/zero-capacity diagnostic. Tests of mocks do not establish actual API semantics.