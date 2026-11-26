# Owned Target-of-Target frame (handoff)

**Status:** spec + first implementation started 2026-11-26; **continue in a new session**. Owner decisions recorded below.
**Test order:** Classic Era first (owner is playing there), then Forever. Nothing is committed until the owner confirms in game.

## Why an owned frame, not a restyle of Blizzard's

Ground truth, both clients (`_ref/blizzard/classic_era/TargetFrame.{xml,lua}`, `_ref/blizzard/forever/unitframe/Mainline_TargetFrame.{xml,lua}`):

| Fact | Era | Forever | Consequence |
|---|---|---|---|
| `TargetFrameToT` is built by `TargetFrame:CreateTargetofTarget("targettarget")` as a **child of TargetFrame** | yes | yes (+ `frame:SetFrameLevel(parent+5)`) | it moves with Target; cannot be detached without fighting Blizzard |
| It is **not an Edit Mode system** (no `EditModeUnitFrameSystemTemplate`, no `systemIndex`) | yes | yes | cannot be dragged on its own in Edit Mode - the owner's requirement |
| `TargetOfTargetMixin:Update` shows it only when CVar `showTargetOfTarget` **and** target exists **and** target's target exists **and** target's target is **not the player** **and** target alive | yes | yes | the "sometimes" the owner sees is correct behaviour: a mob targeting YOU shows no ToT |
| `TargetFrame:UpdateAuras` switches to `TOT_AURA_ROW_WIDTH` and re-flows aura rows when ToT is shown | yes | yes (`ConfigureAuraContainer`) | restyling in place must also fight the aura layout |
| Template inherits `PingableUnitFrameTemplate`, `frame:SetRolesets("unitFrames")` | no | **yes** | an owned frame will not be pingable on Forever unless we inherit it too (accepted gap, see Open) |
| Regions are flat globals `TargetFrameToT{Portrait,HealthBar,ManaBar,TextureFrameName,TextureFrameTexture,Debuff1..4}` | yes | parentKeys `HealthBar/ManaBar/Portrait/Name/FrameTexture` | our Era adapter has **no** `tot` mappings today (spec 07 P1) |

**Decision (owner 2026-11-26): addon-owned frame, the Pet Target pattern.** Blizzard's `TargetFrameToT` is hidden (alpha 0 via
`ChromeRegions`, never `Hide()` - it is protected) and left to Blizzard. Ours is a `SecureUnitButtonTemplate` with `unit="targettarget"`,
clickable (`type1=target`, `type2=togglemenu`), secure visibility driver `[@targettarget,exists] show; hide`, registered with LibEditMode
as "Target of Target", per-layout placement, **default anchored to TargetFrame's bottom-right** where Blizzard's sits.

## What is already proven (do not re-research)

- Secure unit button + `type1/type2` clicks: hardware-event targeting, no protected Lua. **Working on Forever** (our Pet Target, Lazy Thom's PetTarget).
- `RegisterAttributeDriver(frame, "state-visibility", "[@unit,exists] show; hide")`: secure Show/Hide in combat, 0.2 s poll. Working on Forever.
  `AddonManagement/_EXTERNAL_APIS/wow_secure_visibility_pettarget.md`.
- Protected in combat on the secure button: Show/Hide/SetPoint/ClearAllPoints/SetParent/SetScale/SetSize/SetAttribute/RegisterForClicks/
  SetFrameStrata/Level/RegisterAttributeDriver. Cosmetic calls are fine. `Frames\PetTargetVisibility.lua` already queues on `pending`.
- `targettarget` **does** fire `UNIT_TARGET` for unit `target`, so unlike `pettarget` the owned ToT needs **no OnUpdate poller**;
  refresh on `PLAYER_TARGET_CHANGED` + `UNIT_TARGET(target)` + `UNIT_HEALTH/UNIT_POWER_UPDATE(targettarget)`.
- Secret values on Forever: health/power/name go through `Client.FormatBarValue` / `Client.UnitDisplayName` as every frame does. No
  `UnitIsUnit` logic (can be secret) - there is no "hide when same as X" rule, same as Pet Target.
- The stack: portrait group on `BACKGROUND` strata, bars on their own, badge/text above (`a050880`). Owned frames use `Chrome.Create` /
  `FrameBase.PortraitBadge` exactly like Pet Target already does.

## Design: `Frames\OwnedUnitFrame.lua` (new, shared) + two thin users

Extract the frame-building half of `Frames\PetTarget.lua` into a factory; `PetTarget.lua` and the new `Frames\ToT.lua` become
configuration + their own update logic. **Behaviour of Pet Target must not change** - that is the regression gate for the extraction.

```
VFS_OwnedUnitFrameSpec = {
  id = "pettarget" | "tot",            -- VFS_FrameID (DB.FRAME_IDS already has both)
  unit = "pettarget" | "targettarget",
  globalName = "VelocityFrameStylePetTarget" | "VelocityFrameStyleToT",
  layout = Chrome.LAYOUT[id],         -- bar sizes; tot uses the small (pet-sized) layout, side = "right"
  portraitSide = "left" | "right",     -- tot: portrait LEFT, bars right (Blizzard's ToT orientation); pettarget keeps right
  hitRectInsets = {l, r, t, b},
  visibilityDriver = "[@pettarget,exists] show; hide" | "[@targettarget,exists] show; hide",
  editModeLabel = "Pet Target" | "Target of Target",
  defaultPlacement = DB.DEFAULT_PLACEMENT | DB.DEFAULT_TOT_PLACEMENT,   -- anchorTo PetFrame / TargetFrame
  needsPoller = true | false,          -- pettarget: 0.2 s OnUpdate (no events); tot: false
}
OwnedUnitFrame.Create(spec) -> frame, st        -- button, stock-equivalent regions (name/level/texts alpha 0), bars, art, skull,
                                                --   raid icon, pulse, FrameBase registration, Chrome.Create, badge, slots
OwnedUnitFrame.ApplyPlacement(spec, frame)      -- the PetTarget.ApplyPlacement logic, parameterised on spec/profile key
OwnedUnitFrame.UpdateBars(spec, frame)          -- SetMinMax/SetValue from Unit* (secret-safe), colours
OwnedUnitFrame.UpdatePortrait(spec, frame, force), UpdateMisc(spec, frame)  -- classification art, reaction, skull, raid icon
OwnedUnitFrame.SetSample(spec, frame, on)       -- Edit Mode preview
```

`PetTargetVisibility.lua` generalises to `Frames\OwnedVisibility.lua` keyed by spec (driver string, pending flag, enter/exit Edit Mode).
`UI\EditMode.lua` registers every owned frame from a list, not just Pet Target; `OnMoved` writes to `profile[spec.placementKey]`.
`Core\DB.lua`: `DEFAULT_TOT_PLACEMENT = { anchorTo = "TargetFrame", point = "TOPLEFT", relPoint = "BOTTOMRIGHT", x = -16, y = -14 }`
(Blizzard's own offset) and `DEFAULT_PROFILE.totPlacement`; `DB.Profile()` fills it like `petTargetPlacement`.

## Client adapter changes (both flavours, same INTERFACE)

- `UNITS.tot = "targettarget"` on Era (Forever already has it). `Root("tot")` = `VFS.ToT and VFS.ToT.frame` on **both** (ours), like pettarget.
- Every region resolver gains a `tot` branch returning OUR frame's regions (`f.health`, `f.power`, `f.portrait`, `f.name`, `f.level`,
  `f.healthText`, `f.powerText`, `f.deadText`, `f.texture`, `f.nameBackground`, `f.skull`) - copy the pettarget branches.
- **Blizzard's ToT becomes chrome to suppress:** add to `ChromeRegions("target")` the stock ToT art so it goes alpha 0 while Target styling
  is enabled: Era `TargetFrameToTTextureFrameTexture`, `TargetFrameToTBackground`, `TargetFrameToTPortrait`, its bars' regions, name,
  debuffs 1-4; Forever `TargetFrameToT.FrameTexture`, `.Portrait`, `.Name`, bars, debuffs. **Never Hide() TargetFrameToT** (protected,
  and Blizzard's Update would re-show it). Restoring on disable follows the existing `SetChromeSuppressed` path.
- `Client.MovableBars("tot")` -> {} (our bars; placed by the owned frame, like pettarget).
- Remove the dead `hooksecurefunc(TargetFrame, "UpdateTargetOfTarget")` / `TargetFrameToT.Update` hooks and `ToT.OnEvent`'s
  restyle-of-Blizzard path from the current `ToT.lua` - they target the frame we are replacing.

## Plan (checkboxes; continue here)

- [ ] T0 — **Read before touching:** `Frames\PetTarget.lua` (263 lines), `PetTargetVisibility.lua`, `UI\EditMode.lua`, `Core\DB.lua` placement
      bits, `VelocityFrameStyle.lua` Stage() order and the `UNIT_TARGET`/`UNIT_PET` dispatch. Confirm `DB.FRAME_IDS` has `tot` and
      `Chrome.LAYOUT.tot` exists (both do).
- [ ] T1 — **Extract `OwnedUnitFrame.lua`** from PetTarget with ZERO behaviour change. Pet Target spec = today's constants. Run all tests,
      publish, owner checks Pet Target on Era: placement persists, drag in Edit Mode, health-only, flash on new target, combat show/hide.
      Commit alone: "Pet target frame code made reusable (no visible change)".
- [ ] T2 — **ToT via the factory**: `ToT.lua` = spec + event refresh (no poller). `OwnedVisibility` for `[@targettarget,exists]`.
      Era adapter `tot` branches + Blizzard ToT chrome suppression. Stage("ToT") after Target. `DEFAULT_TOT_PLACEMENT`.
- [ ] T3 — **Edit Mode**: register "Target of Target" with LibEditMode; dimension sliders like Pet Target; sample data; drag -> exit -> reload
      persists per layout; no regression of the pet-target anchor-default bug (placement is atomic, `anchorTo = nil` after a drag).
- [ ] T4 — **Era play-test** (owner): target a mob that is fighting the pet (ToT = pet) / another player; target a mob fighting you (ToT = you,
      should show - unlike Blizzard's, ours has no "not the player" rule; **owner to decide if we want that rule**, see Open); click-target,
      right-click menu; combat enter/exit; Edit Mode drag; `/vfs stack tot`, `/vfs status`. Blizzard's ToT must be invisible, never re-appearing.
- [ ] T5 — **Forever** (owner flips): same matrix. Watch for secret-value errors in `/vfs values tot`; verify clicks target; verify the
      driver shows/hides in combat; confirm `TargetFrameToT` art stays alpha 0 across target changes. Commit per confirmed step.
- [ ] T6 — Options: ToT section already exists via `DB.FRAME_IDS` (FramePage builds one per id); add "Only show health bar" like Pet Target?
      (Open.) Update `09_TODO.md`, spec 07 P1, spec 08 E2 (ToT mapping) as done.

## Open questions (decide in the new session, default in bold)

- Mirror Blizzard's "hide when the target's target is the player"? **No by default** - it needs `UnitIsUnit("targettarget","player")`, secret
  on Forever; and seeing "it's on me" is useful. Could offer as an Era-only option later.
- Pingable on Forever (`PingableUnitFrameTemplate`)? **Skip in v1**; note as a known gap.
- Health-only toggle for ToT like Pet Target? **Yes, default off** (ToT power is informative).
- Does the owned ToT carry Blizzard's 4 debuff slots? **No in v1**; auras are a separate feature.
- Should the extraction also absorb a future Focus frame? Design for it (spec-driven), **do not build it**.

## First implementation step taken this session

- [x] Spec written (this file). Nothing else changed yet: `ToT.lua`, `PetTarget.lua`, adapters untouched. Start the new session at **T0**.