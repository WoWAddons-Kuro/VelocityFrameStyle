# Four-row text template — 2026-11-25

Status: implemented, Lua tests pass; in-game acceptance pending.

## Decisions

- Four rows: Name, Level, Health, Power.
- Health and Power each select Current (default), Current / Max, Percent. Position = Hidden remains the hide control.
- Independent per bar and frame on both clients. No global Status Text CVar reads/writes for our format selection.
- Own grid FontStrings replace adoption of Blizzard's centre strings. Stock value strings remain alpha-zeroed; Blizzard still owns the bars and their updates.

## Client formatting boundary

`Client.FormatBarValue(unit, kind, mode)` returns text (potentially secret) and a normal availability boolean.
Forever follows the installed EasyFrames API path: AbbreviateNumbers (fallback BreakUpLargeNumbers), UnitHealthPercent/UnitPowerPercent with ScaleTo100, C_StringUtil.RoundToNearestString. Concatenate formatting results and pass straight to SetText. Never compare, parse, or measure the secret output; never divide secret numbers.
Era expands the mapped tokens with the existing non-secret formatter.

The initial handoff's Current=NUMERIC / Current-Max=BOTH mapping was wrong. Owner confirmed NUMERIC already displayed current/max. No CVar exception is needed.

## Persistence

DB version 2 replaces old six-row element lists once. Name/Level anchor, alignment, size and colour settings survive. Health/Power reset to centred Current defaults. Frame dimensions, placements and other theme settings remain unchanged.
Edit Mode preview text follows each selected format.

## Acceptance

- Default bars show current health/power only.
- Change Target Health to Current / Max; other frames and Target Power stay unchanged.
- Choose Percent, Hidden, then restore a visible position and Current.
- Target switching, resource updates, combat, reload, and pet-target previews refresh correctly.
- `lua5.1 Tests/TextTemplate.lua` covers both clients, opaque mock secret output, hidden/restore, one-time migration, independence and no CVar writes.
- Existing surface/dimension regression tests and all Lua syntax checks pass.