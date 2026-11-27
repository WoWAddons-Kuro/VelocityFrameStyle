# 13 - Target frame danger cues (Hardcore) - port of VelocityPlateStyle's Danger Highlight

**Status:** spec approved by owner 2026-11-27 (structured Q&A); implementation pending.
**Source:** `VelocityPlateStyle\Core.lua` (`IsHostileThreat`, `SkullCount`, `Danger()`), `Skin.lua` (`IsOverLevel`,
`ApplyOverLevel`, `AcquireGlow`, `GlowColor`), `Format.lua` (`[level]` skull glyphs), `Templates.xml` (`VPS_SweepTextureTemplate`).
Workspace rule: **copy, never cross-addon dependency.**

## Owner decisions (2026-11-27)

| # | Question | Decision |
|---|---|---|
| Q1 | Where do skulls + red level go? | **New `danger` row ABOVE the name row**, right-aligned, shown only while the target is dangerous. The Level element stays where the user put it (portrait badge by default). Matches the VPS screenshot: `💀💀 13` over `Blackmoss th...  273`. |
| Q2 | Health bar colour? | Blizzard does **not** reaction-colour the stock TargetFrame health bar (only the name strip, which VFS alpha-zeros). So: **Hardcore option `reactionHealth`** - red hostile / yellow neutral / green friendly NPC bar on Target, independent of danger. Players keep green / class colour. |
| Q3 | Animation? | **Port the VPS sweep** - `leftgrad.tga` tiled over the health fill, XML `TextureCoordTranslation`, 50% black dimmer, contrast colour (yellow over red, red over yellow/green). ~~Red modes also turn the border ring red~~ - **owner 2026-11-27 after test: border stays black; sweep off while the target is dead.** |
| Q4 | Scope / frames? | **Account-wide** (`DB.Global().danger`), **Target frame only** in v1. Owner 2026-11-27: "keep it simple". No scope switch; moving to the per-layout profile record is a later, separate decision. |

## Data

```lua
-- VFS_DangerSettings (account-wide: DB.Global().danger)
DB.DEFAULT_DANGER = {
  overLevelMode      = "animatedRed", -- VFS_OverLevelMode: none | animated | red | animatedRed
  overLevelThreshold = 2,             -- unitLevel >= playerLevel + N (or skull) => dangerous
  skullAtLevelsAbove = 10,            -- one skull glyph per level above from +N; 10 = game rule (-1 only)
  reactionHealth     = false,         -- Target health bar: red hostile / yellow neutral / green friendly (NPCs)
}
DB.DEFAULT_GLOBAL.danger = DB.DEFAULT_DANGER        -- Util.ApplyDefaults deep-fills missing keys at DB.Init
function DB.Danger() return DB.Global().danger end  -- the ONLY read-site accessor (so a later scope move is one line)
```

- `VFS.SKULL_GAME_LEVELS = 10` (constant, Core\Danger.lua).
- No migration: the key is simply absent on old saves and gets the default.

## Logic - `Core\Danger.lua` (new; pure functions, unit-testable)

```lua
Danger.IsHostileThreat(unit)        -- Util.Plain(UnitCanAttack("player", unit)) ~= false  (secret => hostile)
Danger.SkullCount(level, unit)      -- VFS_SkullCount: -1 = "??", 0 = none, N = N glyphs; friendlies 0; level already Plain()
                                    --   diff > SKULL_GAME_LEVELS => -1 ; diff < DB.Danger().skullAtLevelsAbove => 0 ; else diff
Danger.IsOverLevel(unit)            -- hostile and (level < 0 or level >= player + threshold); secret level => false
Danger.IsDangerous(unit)            -- IsOverLevel(unit) or SkullCount(level, unit) ~= 0
Danger.RowText(unit)                -- "" | "??" | rep(SKULL_ICON, n) .. level  (what the danger row shows; "" = hide)
Danger.ReactionColor(unit)          -- r,g,b for reactionHealth: UnitReaction <= 3 red (1,0.2,0.2) | 4 yellow (1,1,0) | >= 5 green (0,1,0);
                                    --   players => nil (caller falls back to ApplyHealthColor's green/class rule)
```

Red used everywhere: `Danger.RED = { 1, 0.15, 0.1 }`, yellow `Danger.YELLOW = { 1, 0.85, 0.1 }` (VPS constants).
`Format.[level]` is **unchanged** (the Level element never grows skulls; the danger row does).

## Drawing - `Frames\Target.lua` + new `Frames\DangerCue.lua`

### Danger row (Q1)
- `st.dangerText` = FontString on `st.host.top` (OVERLAY), created in `Target.Create`. **Not** a grid element: no
  Position/Align/Colour cells; it is a cue, not a value.
- Anchor: `BOTTOMRIGHT -> st.nameRow TOPRIGHT (0, 1)`. Font = frame font/style, size = Level element size + 2.
- Colour always `Danger.RED`. Text = `Danger.RowText(unit)`; hidden when `""` or `overLevelMode == "none"`... **no** -
  the row follows `skullAtLevelsAbove` / threshold only; `overLevelMode` governs bar effects. Row hidden when text is `""`.
- Level element colour: `TextLayout.ColorFor` difficulty mode on the **target** frame returns `Danger.RED` when
  `Danger.IsDangerous(unit)` (VPS R: number goes skull-red at the threshold). Pet rule untouched.

### Health bar colour (Q2)
- `FrameBase.ApplyHealthColor(bar, unit, st)`: if `st.id == "target"` and `DB.Danger().reactionHealth` and
  `Danger.ReactionColor(unit)` ~= nil -> that colour; else existing green/class rule. `HookColor` passes `st`.
- Secret `UnitReaction` (Forever) => nil => green. Never compare the secret.

### Sweep + dimmer + red ring (Q3)
- Assets: copy `VelocityPlateStyle\Assets\leftgrad.tga` -> `VelocityFrameStyle\Assets\leftgrad.tga`.
- `Templates.xml` (new, all three TOCs, before `Frames\`): `VFS_SweepTextureTemplate` = VPS template with the VFS path.
  XML is mandatory: Era 1.15.9 `TextureCoordTranslation` has no Lua offset setter (VPS finding 2026-11-23).
- `DangerCue.Acquire(st)`: frame `st.sweepFrame` parented to the health bar, `SetAllPoints(hb)`, level = `hb level +
  (hb.vfsBorderLevelOffset or 1)` (above fill and prediction segments, below the border ring at +offset... **ring is at
  bar + offset; sweep must be BELOW the ring and ABOVE the fill** => sweep level = bar + offset, ring re-pinned to +offset+1
  via the existing `vfsBorderLevelOffset` audit; `SyncAdornmentLevels` already floors text above rings). Re-sync on
  `hb SetFrameLevel/SetFrameStrata` hooks like Chrome's glow rings.
  - `dim` texture ARTWORK -1, WHITE8x8, (0,0,0,0.5).
  - `tex` = `CreateTexture(nil, "ARTWORK", "VFS_SweepTextureTemplate")`, `SetTexCoord(0, max(1, width/96), 0, 1)`.
- `DangerCue.Apply(st)`:
  - `on = mode ~= "none" and Danger.IsOverLevel(unit)`; `isRed = mode == "red" or "animatedRed"`;
    `wantSweep = on and (mode == "animated" or "animatedRed")`.
  - Ring: `st.bars.health.backdrop.ring:SetBorderColor(RED or black)`; also `backdrop.border` (lower copy) for symmetry.
  - Sweep colour: `animated` => YELLOW; `animatedRed` => contrast of `hb:GetStatusBarColor()` (g > 0.5 => RED else YELLOW).
    With `reactionHealth` off the bar is green => RED wave over green; hostile red bar => YELLOW wave. Same rule as VPS.
  - Play/Stop `tex.Sweep`; Show/Hide `tex`, `dim`.
- Interaction with combat glow: independent layers (glow = ADD ring one level above the black ring; sweep = fill overlay).
  Both may be on at once; no priority rule needed.

### Refresh points
`Target.OnEvent`: `PLAYER_TARGET_CHANGED`, `PLAYER_ENTERING_WORLD`, `UNIT_LEVEL` (target **and player**), `PLAYER_LEVEL_UP`,
`UNIT_FACTION` target, `UNIT_FLAGS` target (UnitCanAttack flips), `UNIT_CLASSIFICATION_CHANGED` => `DangerCue.Apply(st)` +
row text + `ApplyHealthColor`. `FrameBase.Restyle("target")` also calls `DangerCue.Apply`. `LayoutProfile.OnChanged` =>
`FrameBase.Restyle("target")` (bootstrap, next to the EditMode listener). `UNIT_LEVEL` for `player` must be added to
the `RegisterUnitEvent` list check (already registered: yes, `"player"` is in the list).

## Options - Target sub-page (`UI\FramePage.lua` `AddFrameExtras`, `id == "target"`)

```
 Danger Highlight (Hardcore)            saved with Edit Mode layout: "Modern"
 Over-leveled highlight   [Pulsing glow (red) v]        none | animated | red | animatedRed
 Over-leveled when the mob is 2+ levels above you (skull always counts)   [slider 1..10]
 Show skulls when the enemy is +10 levels above you (one per level; 10 = the game's own rule)  [slider 1..10]
 [x] Reaction-coloured health bar (red hostile / yellow neutral / green friendly NPCs)
```
Widgets: `Widgets.Dropdown`, `Widgets.Slider` x2, `Widgets.Check`, `Widgets.Text` for the layout note (Update() refreshes
the name). Every setter writes `DB.Danger()[key]` then `Restyle("target")`.

## Tests - `Tests\Danger.lua` (pure Lua, stub `UnitLevel`/`UnitCanAttack`/`UnitReaction`)
- [ ] SkullCount: -1 level => -1; diff 11 => -1; diff 3 with skullAt 3 => 3; diff 2 with skullAt 3 => 0; friendly => 0
- [ ] IsOverLevel: threshold 2, player 10: mob 12 true, 11 false, -1 true, friendly 12 false, secret level false
- [ ] RowText: 0 => ""; -1 => "??"; 2 => two glyphs .. "12"
- [ ] ReactionColor: reaction 2 red, 4 yellow, 5 green, player nil, secret nil

## Implementation checklist
- [x] M1 `Core\Danger.lua` + `DB.Danger()` + `Tests\Danger.lua` green (3225f55)
- [x] M2 danger row + red Level on Target - owner verified on Era 2026-11-27
- [x] M3 `reactionHealth` colour + refresh; attacked neutral reads red via `UnitAffectingCombat(unit)`, same test as the combat glow (0cc6c28)
- [x] M4 `leftgrad.tga`, `Templates.xml`, `Frames\DangerCue.lua` sweep + dimmer. **Amended in test:** border stays BLACK in every mode; sweep stops when the target is dead
- [x] M5 Options block (slider `fmt` kept short - it prints under both track ends); `09_TODO.md`; `00` file list. No LayoutProfile hook (account-wide)

## Open questions
- Danger row font size: Level size + 2 (proposed) - owner may want a fixed size. TBD after M2 screenshot.
- Pet Target / Focus: out of scope v1; `DangerCue` is written against `st` so extending is `Apply(st)` per frame + the
  owned frames' own skull textures.
- Era `TargetFrameTextureFrameHighLevelTexture` (stock skull on the badge) coexists with our glyph row; if it reads as
  doubled, alpha-zero it only while the row shows `??`.