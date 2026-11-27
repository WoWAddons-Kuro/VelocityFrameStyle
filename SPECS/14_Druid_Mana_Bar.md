# 14 - Druid mana bar: mana stays visible in Bear / Cat on the Player frame

**Status:** approved by owner 2026-11-27 ("yes and then build it"); implementation in progress.
**API ground truth:** `AddonManagement\_EXTERNAL_APIS\wow_druid_mana_in_forms.md` (owner dumps on BOTH clients).
**Reference:** installed `DruidBarClassic` 2.5.5 on Era - two API calls, no regen simulation.

## Problem

A shapeshifted druid's Player frame shows RAGE / ENERGY as its power bar; the mana pool, which decides whether you can
shift out and heal, is invisible. Vanilla-era addons had to SIMULATE mana regen. Modern clients expose the pool:

```lua
UnitPower("player", Enum.PowerType.Mana)      -- Era: 373 (plain)   Forever: <secret>
UnitPowerMax("player", Enum.PowerType.Mana)   -- Era: 490 (plain)   Forever: 862 (plain)
```

So: one extra bar, fed straight from the API. **Forever's current mana is a SECRET VALUE** - it may be handed to
`StatusBar:SetValue` and to Blizzard's formatters, never compared, divided or formatted by Lua (R5 / BUG 12).

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Player frame only, druids only.** Bar exists only when `select(2, UnitClass("player")) == "DRUID"`; nothing is created for other classes. | The only class whose mana hides behind another resource on these clients. |
| D2 | **Shown while `UnitPowerType("player") ~= Enum.PowerType.Mana`** (Bear, Cat, ...); hidden in caster / Moonkin / Tree where the ordinary power bar already IS mana. | No duplicate blue bar. `UnitPowerType` is plain on both clients (we already read it in `ApplyPowerColor`). |
| D3 | **Our own `StatusBar`** (`VFS_Bar` with `owned = true`), not a Blizzard region. Flush under the power bar, same width, height `Chrome.LAYOUT.player.mana.h = 8`, `PowerBarColor.MANA` blue, same backdrop / ring / fill texture through `FrameBase.AcquireBackdrop` / `ApplyBarFill`. | Neither client ships a stock alternate-power bar for Camelot/Era (`PlayerFrame_GetAlternatePowerBar()` is nil on Forever; Era has none). |
| D4 | **No "hide when full" option.** | `cur >= max` is a comparison on a secret on Forever. Era-only options are not offered (one UI for both clients). |
| D5 | **Account-wide toggle `DB.Global().druidManaBar = true`** on the Player page. | Owner 2026-11-27: keep settings simple for now (same as spec 13). |
| D6 | **Text:** a `mana` element in Player's grid (`VFS_TextAnchor "mana"`), tokens `[mana]` `[mana%]` `[manamax]`, value-format dropdown like health/power, default `[mana]` centred, white. Routed through `Client.FormatBarValue(unit, "mana", mode)`. | Forever formats the secret through `AbbreviateNumbers` / `UnitPowerPercent(unit, Mana, false, ScaleTo100)` + `C_StringUtil.RoundToNearestString` exactly like health/power. |
| D7 | **Events:** `UNIT_POWER_UPDATE` / `UNIT_POWER_FREQUENT` / `UNIT_MAXPOWER` (player), `UNIT_DISPLAYPOWER player` (form change), `UPDATE_SHAPESHIFT_FORM`, `UNIT_ENTERED/EXITED_VEHICLE`. | From DruidBarClassic + BorneDruidMana + Blizzard UnitFrame. `UNIT_DISPLAYPOWER` is the show/hide trigger. |
| D8 | **Hide when Blizzard shows its own alternate bar:** `PlayerFrame.activeAlternatePowerBar ~= nil` -> ours off. | Owner fstack 2026-11-27 + BorneDruidMana header: Forever wires `ALT_POWER_BAR_PAIR_DISPLAY_INFO` for **LunarPower only**, so in Moonkin Blizzard draws a mana bar itself; in Cat/Bear it is nil. Era has no such field (always nil). |
| D9 | **Hide in vehicles** (`UnitHasVehicleUI("player")`). | Player frame swaps to vehicle art; Borne does the same. |
| D10 | **R7 stand-down, mana-bar only:** if `BorneDruidManaForEasyFrames` or `DruidBarClassic` is loaded, our bar is not created and `/vfs status` says why. | Owner has BOTH installed today (Era: DruidBarClassic; Forever: Borne - the "mystery bar" in the 2026-11-27 screenshot was Borne's, `BorneDruidMana.lua:199`). No double bars; uninstall them to use ours. |

**Not a Blizzard bar on Forever either.** The bar in the owner's Cat-form screenshot was `BorneDruidManaForEasyFrames`, not stock. Camelot has the `activeAlternatePowerBar` plumbing but only Moonkin registers one. So the "owned bar on both clients" design is correct; D8 handles the Moonkin case.

## Data

```lua
-- Core\DB.lua
DB.DEFAULT_GLOBAL.druidManaBar = true          -- VFS_DruidManaBarEnabled
-- Player default elements gain:
E("mana", "Mana (forms)", "[mana]", "mana", "center", 9, "white")   -- valueFormat = "current"; row exists on EVERY frame's
                                                                     -- list (grid is uniform) but only Player has a `mana` slot;
                                                                     -- elsewhere the element is simply never laid out.
-- Core\Format.lua
Format.FORMAT_TOKENS.mana = { current = "[mana]", current_max = "[mana] / [manamax]", percent = "[mana%]" }
resolvers["[mana]"] / ["[manamax]"] / ["[mana%]"]  -> via Client.ManaValues (Era) ; "" on secret
Format.UsesMana(format)

-- Chrome.LAYOUT.player.mana = { w = 113, h = 8 }

-- VFS_FrameState.bars.mana = { stock = StatusBar (OURS), backdrop, movable = true, owned = true }
-- VFS_TextSlots.mana = that StatusBar | nil (nil while hidden -> elements anchored there hide, like power)
```

## Client interface additions (`Client\Client.lua` INTERFACE + both flavours)

```lua
"ManaValues",        -- (unit) -> cur|nil, max|nil, pct|nil   Plain()-ed mana pool regardless of display power. Forever: cur nil.
"ManaBarValues",     -- (unit) -> cur (may be SECRET), max (plain)   for StatusBar:SetMinMaxValues / SetValue ONLY
-- FormatBarValue(unit, kind, mode) gains kind == "mana": Era via Format tokens; Forever via
--   UnitPower(unit, Enum.PowerType.Mana) -> AbbreviateNumbers, UnitPowerPercent(unit, Enum.PowerType.Mana, false, ScaleTo100).
-- UnitPowerType / UnitClass are read in Frames\Player.lua directly: plain on both clients (no flavour difference).
```

## Frames\Player.lua

```
CreateManaBar(st)        druid only; CreateFrame("StatusBar", nil, st.button); SetStatusBarTexture placeholder; MinMax 0..1
                         st.bars.mana = { stock = bar, backdrop = FrameBase.AcquireBackdrop(bar), movable = true, owned = true }
                         HookColor is NOT installed (nothing else recolours our bar); colour set in ApplyManaBar
PlaceBars(st)            + mana: TOPLEFT -> power BOTTOMLEFT (0, -BAR_BORDER_WIDTH), width = health width, h = LAYOUT.player.mana.h
                         (Geometry.PlaceBar with movable = true)
Player.ApplyManaBar(st)  show = DB.Global().druidManaBar and druid and UnitPowerType("player") ~= Enum.PowerType.Mana
                         bar/backdrop/ring/glow-ring SetAlpha(show and 1 or 0)  (same pattern as RefreshPowerVisibility)
                         st.slots.mana = show and bar or nil ; st.slots.below = show and bar or (power or health)
                         if show: cur, max = Client.ManaBarValues("player"); bar:SetMinMaxValues(0, max or 1); bar:SetValue(cur or 0)
                                  bar:SetStatusBarColor(PowerBarColor.MANA)
                         if changed: Chrome.Layout(st); FrameBase.ApplyTexts(st)
Player.OnEvent           + UNIT_POWER_UPDATE/UNIT_MAXPOWER (player) -> ApplyManaBar + ApplyTexts(UsesMana filter)
                         + UNIT_DISPLAYPOWER (player), UPDATE_SHAPESHIFT_FORM -> ApplyManaBar (show/hide) + ApplyTexts
```

`FrameBase.ApplyAppearance` already iterates `st.bars` for fill / backdrop / colour; the `mana` kind needs its own colour
branch (`kind == "mana"` -> `PowerBarColor.MANA`) so the generic loop does not call `ApplyPowerColor` (which reads the
DISPLAY power type - rage red - for our mana bar). `Chrome.Create` builds a glow ring per `st.bars` entry, so the mana bar
gets a combat ring for free - provided `CreateManaBar` runs BEFORE `Chrome.Create` (i.e. inside `FrameBase.Acquire` via a
new optional hook `Client.ExtraBars(id)` ... **simpler:** Player.Create calls `CreateManaBar` and then `Chrome.AddBarRing(st, "mana")`.
`Chrome.Layout` uses `st.slots.below` for the plate envelope; `TextLayout.Layout` gets `mana` in its rows table.

## Events (bootstrap)

`VelocityFrameStyle.lua`: `RegisterUnitEvent("UNIT_POWER_UPDATE", "player")`, `("UNIT_MAXPOWER", "player")`,
`("UNIT_DISPLAYPOWER", "player")` (the owned-unit loop already registers these for other units - add `player`),
`RegisterEvent("UPDATE_SHAPESHIFT_FORM")`; they fall through to `Player.OnEvent` via the default branch.
Only registered when the player is a druid (checked at PLAYER_LOGIN).

## Options (Player page, `FramePage.AddFrameExtras` id == "player")

```
 [x] Druid: show mana while shapeshifted   (a third bar under the power bar in Bear / Cat form)
```
Shown only for druids (`UnitClass`). The `mana` grid row is always present; its anchor dropdown gains `{ "mana", "Mana bar" }`.

## Tests - `Tests\DruidMana.lua`
- [ ] Era FormatBarValue("player","mana",current/current_max/percent) with plain stubs
- [ ] Forever FormatBarValue mana with SECRET current: result is secret-wrapped, never inspected (forbidden-metatable stubs)
- [ ] Format.UsesMana; `[mana]` resolver returns "" for secret
- [ ] ManaBarValues: Forever returns secret cur untouched + plain max

## Implementation checklist
- [x] M1 Client INTERFACE + both flavours (`ManaValues`, `ManaBarValues`, `FormatBarValue` mana) + Format tokens + `Tests\DruidMana.lua` green
- [x] M2 `Frames\Player.lua`: CreateManaBar / PlaceBars / ApplyManaBar; `FrameBase.ApplyManaColor`; `Chrome.CreateBarRing` / `AddBarRing`
- [x] M3 TextLayout `mana` row + DB default element (appended to existing saves) + FramePage anchor entry + value-format dropdown
- [x] M4 events in bootstrap (only when the bar exists); Player options toggle + stand-down note; `/vfs status` line
- [ ] **Owner play-test:** Era in Bear/Cat with DruidBarClassic DISABLED; Forever in Cat with Borne DISABLED; Moonkin on Forever (ours must hide); vehicle; `/vfs status`

## Open questions
- Bar height 8 vs power 12: owner to eyeball on Era. Knob: `Chrome.LAYOUT.player.mana.h` (+ a `manaHeight` dimension slider later if wanted).
- Should the bar also show for non-druid classes that temporarily lose mana display (none known on these clients)? No - D1.
- Pet Target / other frames: out of scope; only the player can shapeshift here.