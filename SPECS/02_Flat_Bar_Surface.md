# Flat bar surface stack — 2026-11-25

Owner decision: implement flat rectangles first; add rounded border rendering later without changing the layout contract.
This supersedes the filled plate and stretched/invalid backdrop-edge experiments described in earlier specs.

## Geometry contract

- The stock StatusBar rectangle is the **inner surface** and sole sizing/placement authority.
- `FrameBase.CreateSurfaceBorder(parent, surface, thickness)` grows outward from that surface.
- Flat renderer: four solid-colour strips, empty centre, no custom image or backdrop atlas.
- Both border copies use the same renderer and anchors; resizing the StatusBar automatically moves every layer.
- Current border thickness: 6 UI units, with a matching six-unit inter-bar gap as a shared black separator. Name-row clearance includes the border thickness. Native frame zoom still scales these units.
- Later rounded renderer replaces the four strips with fixed-radius corner pieces and stretchable edges; it must keep the same inner/outer bounds.

## Layers, bottom to top

1. Opaque black border outside the inner surface.
2. Black interior at 30% alpha.
3. Blizzard StatusBar fill (or our pet-target StatusBar), unchanged value handling.
4. Identical opaque border above the fill. Flat version has no corner cut-outs yet.
5. Text.

The old opaque card plate is removed so it cannot defeat the interior's transparency. An invisible bar-stack envelope anchors an empty-centred, flat combat outline. The portrait disc/glow remains circular and the portrait stays above its glow.
Player/Target power-bar horizontal offsets are now zero, matching their health bars.

## Settings and validation

On first load of this change, existing background opacity and per-frame background-opacity overrides reset to the owner's 30% baseline. Later edits via the existing options persist. Placements and text settings are not reset.

`lua5.1 Tests/FlatBarSurface.lua` checks anchor bounds at five sizes, identical border copies, opaque borders, interior opacity, frame-level sync, one-shot opacity migration, and the pet-target nil-anchor persistence regression.
All addon Lua files must pass `luac5.1 -p`. In-game rendering/scale/combat/layout-switch checks remain owner-tested before commit.

## Dimensions instead of zoom

Each frame's `/vfs` section now has Bar width, Health height and Power height (inner sizes in UI units). The pet-target Edit Mode dialog has the same controls instead of Scale. Text, portraits and border width do not change with these controls. Changes made in combat are deferred until combat ends.

VFS no longer scales its pet-target button. Old UIParent-relative placement offsets are converted once from the saved zoom to scale 1, preserving the anchor's screen offset (not the old magnified footprint). Dimensions persist per frame, account-wide, like appearance; placement remains per Edit Mode layout.

**Still pending:** Blizzard's native Edit Mode Frame Size slider has NOT been removed or overridden. Set native frame scale to 100% before using bar dimensions; otherwise that native zoom still magnifies the entire frame. Safe replacement of the native slider is separate integration work.
`lua5.1 Tests/BarDimensions.lua` tests independent dimensions, no scale calls, combat deferral, resetting dimensions, and one-shot placement conversion.