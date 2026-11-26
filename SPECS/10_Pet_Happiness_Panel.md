# Pet happiness panel

**Status:** spec, 2026-11-25. Owner request: a hover panel in the HunterPetHappiness (HPH) style showing happiness detail plus
the pet XP bar, shown only out of combat when hovering the happiness icon or the pet level badge. Method lifted from HPH
(installed, `Interface\AddOns\HunterPetHappiness\HunterPetHappiness.lua`, author Beleriand) with credit; nothing copied verbatim.

## What Era exposes (ground truth from HPH + Blizzard `Classic/PetFrame.lua`)

| Datum | API | Nature |
|---|---|---|
| Mood 1/2/3, damage %, loyalty rate (plain number, e.g. 20) | `GetPetHappiness()` (Forever: `C_PetInfo.GetPetHappiness`) | direct; `UNIT_HAPPINESS` on change |
| **Exact happiness 0..1000** | `UnitPower("pet", Enum.PowerType.Happiness)` — **27 on Era** (`976/1000` plain, verified); index 4 is a dead `0/5` slot | direct on Era; secret on Forever |
| Pet XP | `GetPetExperience()` -> cur, max; `UNIT_PET_EXPERIENCE` | direct |
| Hunter pet? | `HasPetUI()` 2nd return | direct |
| Feed cast | `UNIT_SPELLCAST_SUCCEEDED` player, spell 6991; aura 1539 "Feed Pet Effect" on pet | direct |
| Training points | `GetPetTrainingPoints()` -> total, spent (unspent = total - spent) | direct, Era only; `PET_UI_UPDATE` / `UNIT_PET_TRAINING_POINTS` |
| Learnable pet skills | `C_PetJournal`? no - Era: Beast Training window (`GetNumTrainerServices` while at a trainer) is not available remotely. **TBD**: whether "can learn something now" is knowable away from a trainer; see Open questions | unknown |
| Time to next mood | **not exposed** | estimated (below) |

HPH-measured constants: drain ~1 pt / 7.25 s everywhere (no combat multiplier); Dismiss Pet costs 50; death ~330; feed ticks 35 / 17 / 8
by food level gap (within 5 / 6-10 / 11+ below pet), up to 10 ticks over 20 s. The game reports a wrong value for ~5 s after a summon.

## Decisions

- Gate: `Client.PetHappinessFrame()` non-nil **and** `HasPetUI()` reports a hunter pet. **Forever (owner 2026-11-26):** the icon
  exists (resolved by the Forever adapter and re-anchored beside our bars) but `UnitPower("pet", 27)` is **secret** (`/vfs pethappiness`:
  max 1000 plain, value `<secret>`; `GetPetHappiness()` -> 3, 125, 20 plain). No drain/floors/countdown is computable, so there
  `Client.HasReadablePetHappiness()` is false: Blizzard's icon tooltip is left alone (mood, damage, diet) and our panel, from the
  level badge only, shows the **pet XP bar alone**. The happiness model and its events do not run on Forever.
- Our own frame (`VFS_PetHappinessPanel`), not GameTooltip - it holds two status bars and tick marks. Blizzard's
  `PetFrameHappiness` OnEnter/OnLeave are **HookScript**ed; inside we hide GameTooltip and show ours.
- Triggers: hover the happiness icon OR the Pet frame's level badge (`st.portraitBadge`, EnableMouse(true) + OnEnter/OnLeave).
- Never in combat: no show while `InCombatLockdown()`; `PLAYER_REGEN_DISABLED` hides an open panel. Cosmetic-only frame, so
  this is policy not protection, but it keeps the HUD clean in fights.
- Two tiers, picked at runtime like HPH: **exact** when `UnitPower` returns a plain number, else **learned** (median of the last
  five fed->dropped-from-Happy durations). The panel labels which it is using.
- Stock Blizzard pet XP bar is hidden while Pet styling is enabled (Era `ChromeRegions("pet")`), restored on disable. Its
  information moves into the panel.
- No alerts, sounds, minimap button or options page in v1. One global toggle `petHappinessPanel = true` in DB.DEFAULT_GLOBAL.
- Learned state persists in `VelocityFrameStyleDB.petHappiness`, keyed by pet name (HPH pattern), restored only if the
  same pet is out and the wall-clock gap is under 2 h.

## Model (Core\PetHappiness.lua, pure data, testable)

```
VFS_PetHappinessState = {
  mood = 1|2|3|nil, damagePct, loyaltyRate,          -- from GetPetHappiness
  exact = { value, max } | nil,                       -- from UnitPower when plain
  decayRatePerSec = number|nil,                       -- EMA 0.7/0.3 over >=60 s windows; reset on gain or hit > 2% of max
  happyFloor = fraction (default 2/3), contentFloor = fraction (default 1/3),   -- learned from mood transitions with exact value
  lastFedAt = GetTime()|nil, happySince = GetTime()|nil,
  samples = { sec, ... } (max 5; reject < 20 s, > 1 h, or < 0.5 x median once 3 exist),
  summonedAt, lastZoneAt,                             -- settle 5 s after summon; ignore drops within 20 s of a zone / in BG or arena
}

PetHappiness.Update(now)           -- poll + reconcile; called on events and a 1 s ticker while the panel is shown
PetHappiness.TimeToNextMood(state) -- exact: (value - floor*max) / decayRate; learned: median - (now - happyStart); nil = unknown
PetHappiness.Describe(state)       -- -> { moodName, moodColor, pct, valueText, etaText, dmgText, loyaltyText, fedText, tier }
```

Events: `UNIT_HAPPINESS`, `UNIT_PET` (player), `UNIT_PET_EXPERIENCE`, `UNIT_SPELLCAST_SUCCEEDED` (player; Feed 6991, Dismiss 2641),
`UNIT_AURA` (pet; Feed Pet Effect 1539 -> lastFedAt), `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED_NEW_AREA` (lastZoneAt),
`PLAYER_REGEN_DISABLED` (hide panel).

## Panel (Frames\PetHappinessPanel.lua)

Layout per the owner mock, rounded-border look from the atlas, plate colour background:

```
[face] Happy                                   582
       58%   ~12:40 to Content   dmg 125%  loyalty +
       [happiness bar ====|=====|===== ]   (ticks at happyFloor / contentFloor)
       XP  [=============           ]  1,240 / 3,400
       Fed 14:02 ago         (exact / learned)
```

- Face: `Interface\PetPaperDollFrame\UI-PetHappiness` with HPH/Blizzard tex coords per mood.
- Mood colours (HPH): Unhappy 0.90/0.20/0.20, Content 0.95/0.80/0.20, Happy 0.25/0.85/0.35.
- Bars: our `CreateSurfaceBorder` (4-unit atlas) around plain StatusBars; fill textures from the theme.
- Anchored TOPLEFT -> happiness icon BOTTOMLEFT (or badge) with the frame kept on screen (`SetClampedToScreen`).
- Estimates prefixed `~`; when the drain is unmeasured show `measuring drain...`; learned tier shows `~m:ss left` or `learning...`.
- **Training points row** (owner 2026-11-25): `TP  12 unspent` shown in **green** when unspent > 0 **and** there is a skill the pet can learn
  with them; plain/grey when unspent > 0 but nothing to buy; row hidden when 0. Knowing "a skill is learnable" is the hard part - see Open questions.

## Plan

- [x] P0 — Verified on Era 2026-11-25 (hunter pet out). **`UnitPower("pet", 27)` -> `976 / 1000`, plain.** The exact tier works.
      Also learned: `Enum.PowerType.Happiness == 27`; index 4 is a dead `0 / 5` slot (HPH's `or 4` fallback is wrong for Era); power
      dump 0..9 shows only Focus (2) live. `GetPetHappiness()` -> `3, 125, 20`: mood, damage %, **loyalty rate as a plain number**
      (HPH only uses its sign). Max is **1000** on Era (HPH's window said 0-1000 on Forever too); mood floors therefore default to
      667 / 333 and are still learned from transitions. Implementation: resolve the index via the enum first, never a bare `4`;
      treat `max <= 5` as "not a happiness value" and fall through to the learned tier.
- [x] P1 — `Core\PetHappiness.lua` model + `Tests\PetHappiness.lua` (decay EMA, floor learning, sample rejection, ETA math, settle/zone guards) with a fake clock.
- [x] P2 — `Frames\PetHappinessPanel.lua`: frame, hooks on `PetFrameHappiness` + badge, combat gating, 1 s ticker while shown.
      Layout after owner passes: face / mood + dim tier / value · happiness bar on a grey track with floor ticks and `~5m 12s` INSIDE the
      draining segment · full-width blue XP bar, 5 divisions, `cur / max  pct%` inside · training points (left) + damage % (right).
      No loading gate (it stalled: UNIT_PET re-armed the 5 s settle on every pet event; settle now arms only on no-pet → pet).
      Background alpha 0.72. Settings on the Pet frame section: panel on/off, **Shift-only** (MODIFIER_STATE_CHANGED shows/hides while hovered).
- [x] P3 — XP row via **`Client.PetExperience()`** (INTERFACE method; Era = `GetPetExperience()` cur,max gated on `HasPetUI()` hunter pet, as
      Blizzard's `Vanilla/PetPaperDollFrame.lua` reads it; Forever = nil). The green bar under the pet frame was BTT.Kuro's `PetXP.lua`, not
      Blizzard's; owner turned it off in BTT's settings. VFS does not touch other addons' frames (a BTT-side defer hook was tried and reverted).
- [ ] P3b — Training points row: unspent count always; green/grey via optional `BeastTrainingTrackerKuro_API.TeachableNow()` (add to the fork), else green when unspent >= 1 with a hint.
- [x] P4 — Persistence in `VelocityFrameStyleDB.petHappiness` per pet name; `/vfs status` line with tier, decay rate, floors, samples, xp.
- [ ] P5 — Owner play-test: summon, feed low/high food, dismiss, zone, enter combat with panel open; then commit (HPH credit already in all three TOCs).

## Open questions

- Tick marks: band floors only (HPH), or also a "feed now" warning position? Default: floors only.
- Include loyalty level name / training points (`GetPetLoyalty`, `GetPetTrainingPoints`)? Default: no in v1.
- Should the panel also open from hovering the pet portrait? Default: no - icon + badge only, as requested.
- If Era hides the exact value after all (P0), is the learned tier alone good enough to ship, or wait? Default: ship learned, label it.
- **Training points: how do we know a skill is learnable away from the trainer?** Researched 2026-11-25:
  - `BeastTrainingTracker.Kuro/Core.lua` has exactly the computation: `ns.Upgrades()` = abilities the pet has where the HUNTER knows a
    better rank, split into teachable-now (`needLevel == nil`) vs needs a pet level; data in `Data.lua` carries `trainingPoints` per rank.
    BUT it is all on the addon-private `ns` table - **no public API**, and BTT is a fork we don't want VFS to depend on.
  - Decision: **tier the colour by what VFS can know alone, offer better data optionally.** (1) Always: `GetPetTrainingPoints()` unspent
    count, white. (2) If `BeastTrainingTrackerKuro` is loaded and exposes a tiny opt-in API we add to the fork
    (`BeastTrainingTrackerKuro_API.TeachableNow()` -> count, cost), green when count > 0 and cheapest cost <= unspent; grey when nothing is
    teachable. (3) Without BTT: green when unspent >= 1 (TP are only ever useful for teaching), tooltip says "install Beast Training Tracker
    for exact upgrades". No vendored rank table in VFS - that data already lives in BTT and would drift.
  - Spec change needed in BTT.Kuro: `SPECS_FOR_UNOWNED_REPOS` does not apply (we own the fork); add a one-function public API there.