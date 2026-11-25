# Player prediction overlays and stock status-art suppression

**Current diagnostic experiment:** predictions temporarily use WHITE8x8 with yellow tint and full texture/segment alpha, rather than the selected bar texture. Main bars remain unchanged. Installed Details `images/BantoBar.tga` inspected: 256×32, alpha 255 throughout, RGB range 69–159; right-edge interior is approximately 69/255 grey. Multiplicative yellow tint on that dark slice produces olive even at full opacity. Await owner confirmation that the solid-white control renders bright yellow before choosing a final textured style.

The `/vfs predictions` capture reported all three segments hidden, so that capture alone did not diagnose an active cast; use a snapshot during a longer cast if further evidence is needed.

Status: owner confirmed predictions working on Forever player. Yellow/theme-texture visibility adjustment implemented; visual confirmation pending. Mock tests and Lua syntax pass.

## Scope and ownership

- Player MyHealPredictionBar, OtherHealPredictionBar and ManaCostPredictionBar.
- Blizzard still computes values, segment widths/positions and visibility using its existing events.
- VFS never calls the native prediction updater with secret values, reads prediction amounts, or changes the value-controlled FillMask.
- No custom pet-target predictions. Era, Target/Pet prediction adaptation, absorbs and health-loss styling are outside this first pass.

## Geometry / layering

The native Fill has two kinds of masks: a per-segment FillMask controlled by Blizzard (preserved), and a fixed art-window mask sized for Blizzard's original artwork (removed only from the selected prediction Fill). A new rectangular clip mask is anchored to the resized underlying bar, with no numeric geometry reads.

Owner requested a more visible temporary style: both prediction types use the frame's selected bar texture with yellow vertex tint (1, 0.9, 0.1, 1). Their anchors cover the underlying bar; the native FillMask still exposes only the predicted segment. Native SetFillColor calls are tracked for restoration and the yellow styling is reapplied afterward.

Draw order: main fill at N; prediction segment N+1; VFS border N+2; text at least N+3. Cosmetics are reapplied after native UpdateFillPosition without reading its arguments and when the bar's level/strata changes. Disabling styling restores the saved texture/atlas, texcoords and relative frame level, removes the VFS clip mask and restores the removed native art mask.

## Red streak through player health

PlayerFrame_OnUpdate repeatedly writes StatusTexture:SetAlpha. One-time alpha suppression was overwritten. FrameBase.SetChromeSuppressed now gates subsequent alpha writes for ChromeRegions only, retaining the last native alpha for restoring disabled styling. Keep-list and prediction regions are excluded.

## Diagnostics and validation

- `/vfs status` feature entries: prediction:player:myHeal, otherHeal, manaCost. False means missing required regions or an adaptation failure (warning once).
- `lua5.1 Tests/Predictions.lua`: preserves value mask, no value/visibility writes, checks yellow tint and theme texture updates, aligns clip/fill, layers, ignores opaque callback arguments, avoids duplicate masks, restores native appearance/colour, and suppresses repeated stock alpha pulses.
- Six regression scripts and Lua parsing pass.

Owner acceptance:
1. Cast a mana-spending cast-time spell; the pending-cost segment appears, then clears on completion/cancel.
2. Receive an incoming cast-time heal while injured; see the prediction beyond current health and bounded by the health surface.
3. Change bar width/height outside combat and repeat.
4. Confirm text and border remain above the overlays, and the old red horizontal status streak no longer returns in combat.
5. Confirm no new Lua/taint errors. Do not commit before confirmation.