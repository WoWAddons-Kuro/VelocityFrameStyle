# Rounded border atlas and renderer

Status: owner approved the first cut in game on 2026-11-25. Atlas generated, software-validated and connected to both black-border layers. Eight Lua regression tests and syntax checks pass. No fill or translucent background is baked into this atlas.

## Reproduce

From the VelocityFrameStyle repository root:

```powershell
dotnet run Scripts/GenerateRoundedBorderAtlas.cs
```

Pure C#/.NET 10 file-based program; no NuGet graphics dependency. Uses explicit Utf8JsonWriter metadata output (works with file-app AOT defaults).

Outputs:
- `VelocityFrameStyle/Assets/rounded_border_atlas.tga`: shipped 128×128, uncompressed 32-bit BGRA TGA, top-left origin, white RGB with shape in alpha.
- `VelocityFrameStyle/Assets/RoundedBorderAtlas.lua`: generated runtime geometry and UV metadata; loaded before the renderer.
- `Assets/rounded_border_atlas.json`: unshipped slice rectangles and normalized UVs.
- `VelocityFrameStyle/Assets/disc.tga`, `portrait_rim.tga`, `soft_disc.tga` (2026-11-25): 128×128 white/alpha round shapes, listed in
  `VFS.RoundedShapes`. **Every disc the addon draws is generated and tinted at runtime** — portrait plate, soft halo, combat rim glow,
  level badge, and the portrait rim (an annulus 54→62 px painted OVER the portrait edge; it clips square class-icon portraits and gives every
  portrait the bar-border edge). No dependency on Blizzard's `TempPortraitAlphaMask`. White-with-alpha art tints to any colour, black included.
- `Assets/rounded_border_preview.tga`: unshipped 4× composite preview reconstructed from the atlas.
- `Assets/rounded_border_preview.png`: inspection copy converted from the TGA using Pillow; not required at runtime.

## Geometry contract

Two rings measured by `d` = distance outward from the bar edge (negative = inside the bar; inner corner radius 3 UI units), each its own 128×128 atlas:

| Ring | File / Lua table | Span in `d` | Corner tile | Alpha |
|---|---|---|---|---|
| Black border | `rounded_border_atlas.tga` / `VFS.RoundedBorderAtlas` | **[0, 4]** (was 6 until 2026-11-25) | 7×7 | 1 across the annulus, AA on both curves |
| Combat halo | `rounded_glow_atlas.tga` / `VFS.RoundedGlowAtlas` | **[−2, 6]** (8 wide) | 9×9 | `(1 − |d − 2| / 4)²`: peak 1 at the border midline `d = 2`, 0 at both ends |

- The halo is tinted `combatGlowColor`, ADD-blended, one copy per bar on Chrome's throbbing frame. Owner decision 2026-11-25: a "halo glow" of the border itself — strongest at its centre, feathering symmetrically 2 units into the bar and 2 units past the border. Lua `thickness` for a ring = its outer extent in `d` (the frame offset).
- Each fixed corner covers outer extent + 3 UI units: the ring outside the inner surface plus 3 inside it (the halo's inner feather ends at the same offset).
- Source resolution: 4 pixels per UI unit, with 8×8 supersampling per source pixel.
- Explicit 3×3 slice grid in 40-pixel cells; each tile has two extruded gutter pixels. Use UVs from metadata, not the whole image.
- Centre is completely transparent. Straight edges are opaque black after runtime tinting; inner/outer curved boundaries have coverage antialiasing.
- Minimum inner width/height is 6 UI units. At that minimum, the corresponding middle span is zero: omit that edge/centre piece rather than setting a texture width/height to zero (WoW can interpret zero specially).
- Corners must NEVER stretch when the bar changes aspect ratio. Only middle edges stretch.
- This is NOT a BackdropTemplate edgeFile atlas. Its pieces must be assigned explicitly through texture UVs / a custom nine-slice layout.

## Runtime integration

Keep the existing inner StatusBar geometry authoritative. Outer rect = inner rect expanded by the ring's thickness. Draw the same border geometry below and above the bar; the upper inner-corner cut-outs cover square fill corners. Do not change value handling or prediction FillMasks.

`Frames/RoundedBorder.lua` renders eight pieces (no centre) for whichever atlas it is given. `FrameBase.CreateSurfaceBorder` dispatches by thickness: `BAR_BORDER_WIDTH` (4) → border atlas, `COMBAT_GLOW_WIDTH` (6) → glow atlas, anything else → flat four-edge fallback. Both the lower and upper bar borders use the border atlas; Chrome's per-bar glow rings use the glow atlas with `SetBorderBlendMode("ADD")`. All three TOCs load the generated metadata and renderer before FrameBase.

The renderer hides zero-span edges at the minimum supported dimensions. A size-change handler updates visibility; corners never stretch. `Tests/RoundedBorder.lua` checks both border layers and the glow ring against their atlases, fixed corners, generated UVs, resize/minimum handling and the flat fallback.

## Validation

The generator asserts per ring: transparent centre, opaque straight edge (border) or monotone falloff bright-at-bar / near-zero-at-edge (glow), intermediate AA pixels, horizontal/vertical symmetry, and exact pixel-for-pixel agreement between atlas reconstruction and direct rasterization at inner sizes 113×24, 113×12, 70×10, 70×7, 200×40 and 40×6.

Preview rows are player/target health, player/target power, pet health and pet power at 4×; the first two rows add the glow at peak throb. The checkerboard demonstrates transparent exterior and the 30%-alpha empty interior. It includes both border copies and a 72%-full square fill. Owner approved the 6-unit border in game 2026-11-25; the 4-unit border + glow awaits the next in-game check.