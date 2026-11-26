# VelocityFrameStyle — tracking TODO

Concise laundry list. One line per item; tick when the owner has confirmed it in game and it is committed.
Detail lives in the numbered specs (07 review, 08 Era plan, 06 atlas). Started 2026-11-25.

## Classic Era refactor (spec 08, phases E0–E5)

- [ ] E0 — contract + baseline: run tests, syntax-check, record Era build; remove dead client surface (`StockValueText`, `AdoptStock`/`vfsAdopted`, unused capability flags); required-vs-optional client methods, no silent Forever fallback
- [ ] **NEXT SESSION: owned Target-of-Target frame** — handoff spec [11_Owned_ToT_Frame.md](11_Owned_ToT_Frame.md). Extract `OwnedUnitFrame` from PetTarget (T1, zero behaviour change), then ToT via the factory (T2–T3), Era test first, then Forever. Blizzard's ToT is not an Edit Mode system and is hidden when the target targets you — "sometimes" is correct behaviour, not a bug.
- [ ] E1 — native hooks + legal anchors behind adapters; Geometry validate-before-clear, reentrancy guard, combat queue; connect or remove `ToT.OnEvent`
- [ ] E2 — `Client.ResolveFrameBinding`; complete Era mappings for Player/Target/Pet/ToT/Pet Target (ToT missing on Era today); real-shaped fixtures
- [ ] E3 — `GetPowerRowState` (visible/hidden/unknown) replaces `HasPowerResource`; verify Era APIs; Edit Mode layout matrix
- [ ] E4 — Era predictions: incoming heals wired; mana-cost existence verified or documented
- [ ] E5 — regression pass both clients; disable-styling restores natives; adapter notes updated with observed results

## Era fixes done this session (confirmed + committed 2026-11-25)

- [x] Target auras below the styled bars (`74ba68c`)
- [x] Pet happiness anchored to the bars, size untouched (`74b3658`)
- [x] Combat glow = per-bar rounded outline; power ring hides with the bar (`829ba66`)
- [x] 4px border + Gaussian halo glow, generated atlases (`01b59a3`)
- [x] Level badge on the portrait rim, bar side, default + migration (`5352221`)
- [x] Black portrait rim clips class icons; one explicit frame-level stack (`d255cf1`)

## Visual cleanup (post-refactor, spec 08 list)

- [ ] **NEXT: Player portrait elements still draw ON TOP of the health bar.** Everything in the portrait group (portrait, rim, plate disc) must be UNDER both bars and their borders. `d255cf1` fixed the pet; the player portrait layer still lands above. Likely cause: on Era `PlayerFrame`'s bars are children of a lower-level subframe than the portrait, so `LowestBarLevel()` finds a level the portrait layer cannot get beneath without sinking holder/glow further - verify with `/fstack` levels, then fix the "no room" branch in `Chrome.Create`.
- [ ] Elite / rare / rareelite / worldboss / `??` verification on Target level + kept skull/boss icons, both clients; record in 03
- [ ] Danger cues from VelocityPlateStyle on Target / Pet Target: skull-red level at threshold, inline skulls per level above, none for friendly *(spec first)*
- [ ] Border variants: thinner / smaller-radius atlases as a theme setting + per-frame override *(spec first)*
- [ ] Alternate rectangular layout preset (radius-0 border + square portrait) *(spec first)*
- [ ] Combat glow runtime non-uniformity: second copy with offset throb and/or `TextureCoordTranslation` wave
- [ ] Badge tuning after more play: `PORTRAIT_BADGE_SCALE/_RING/_OFFSET`; pet badge vs size-10 font at 13px
- [x] **Pet level colour** (`71eb89a`): `difficulty` mode special-cases `UnitIsUnit(unit,"pet")` → yellow at player level or −1, red further behind, never green/grey.
- [x] **Pet happiness hover panel** (`c12fed7`) — [10_Pet_Happiness_Panel.md](10_Pet_Happiness_Panel.md). Exact value via `UnitPower("pet", 27)` + measured drain + learned mood floors; XP via `Client.PetExperience()`; training points; Shift-only option. **Owner retired HunterPetHappiness and BTT's pet XP bar 2026-11-25.** Open: P3b (BTT API for teachable-now colour).

## Loose ends noticed along the way

- [ ] Spec 07 phase names/numbering out of sync with spec 08 (E0–E4 vs E0–E5); re-sync or mark 07 historical
- [ ] Spec 08 baseline line still says `2d4c402`; now many commits later
- [ ] `Tests/` has no fixture for the portrait badge / adornment stack or the `portrait` text slot
- [ ] `Client.PetHappinessFrame` is Era-only by nature; confirm it belongs in INTERFACE vs. an optional capability once E0 defines required/optional
- [ ] Forever check of everything landed today (badge, rim, 4px border, glow) — all verified on Era only
- [ ] `_ref/blizzard/classic_era/PetFrame.lua` + `TargetFrame.lua` fetched this session; note them in the `_ref` index if one exists
- [ ] Old VelocityPetTargetFrame SavedVariables still on disk in WTF (harmless); decide whether to archive the workspace repo

## Extreme polish

- [ ] Use shaped mask textures to prevent bleed around (e.g. for portraits): mask the portrait texture itself to a disc instead of relying on the rim to cover square-icon corners
- [ ] Rim width exactly = bar border (4 units): generator `rimInner` 54 → 55.4, or a per-portrait-size rim atlas
- [ ] Soft glow atlas variant with a wider/looser falloff selectable per theme
- [ ] Pixel-snap badge and rim positions at non-integer UI scales (PixelUtil) so 1px seams never appear
- [ ] Badge text auto-size: shrink the level font one step when the number is wider than the badge disc
- [ ] Combat glow colour per frame override (currently global `combatGlowColor` only)