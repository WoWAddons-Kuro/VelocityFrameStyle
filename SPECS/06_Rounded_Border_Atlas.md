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
- `Assets/rounded_border_preview.tga`: unshipped 4× composite preview reconstructed from the atlas.
- `Assets/rounded_border_preview.png`: inspection copy converted from the TGA using Pillow; not required at runtime.

## Geometry contract

- Border thickness: 6 UI units.
- Inner corner radius: 3 UI units; outer radius: 9 UI units.
- Each fixed corner covers 9×9 UI units: 6 outside the inner surface plus 3 inside it.
- Source resolution: 4 pixels per UI unit, with 8×8 supersampling per source pixel.
- Explicit 3×3 slice grid in 40-pixel cells; each tile has two extruded gutter pixels. Use UVs from metadata, not the whole image.
- Centre is completely transparent. Straight edges are opaque black after runtime tinting; inner/outer curved boundaries have coverage antialiasing.
- Minimum inner width/height is 6 UI units. At that minimum, the corresponding middle span is zero: omit that edge/centre piece rather than setting a texture width/height to zero (WoW can interpret zero specially).
- Corners must NEVER stretch when the bar changes aspect ratio. Only middle edges stretch.
- This is NOT a BackdropTemplate edgeFile atlas. Its pieces must be assigned explicitly through texture UVs / a custom nine-slice layout.

## Runtime integration

Keep the existing inner StatusBar geometry authoritative. Outer rect = inner rect expanded by 6 units. Draw the same border geometry below and above the bar; the upper inner-corner cut-outs cover square fill corners. Do not change value handling or prediction FillMasks.

`Frames/RoundedBorder.lua` renders eight pieces (no centre). `FrameBase.CreateSurfaceBorder` dispatches to it only for the atlas's 6-unit thickness; the 2-unit combat outline retains the flat renderer. Both the lower and upper bar borders use the same atlas/anchors. All three TOCs load the generated metadata and renderer before FrameBase.

The renderer hides zero-span edges at the minimum supported dimensions. A size-change handler updates visibility; corners never stretch. `Tests/RoundedBorder.lua` checks both border layers, fixed corners, generated UVs, resize/minimum handling and the flat combat-outline fallback.

## Validation

The generator asserts: transparent centre, opaque straight edge, intermediate AA pixels, horizontal/vertical symmetry, and exact pixel-for-pixel agreement between atlas reconstruction and direct rounded-annulus rasterization at inner sizes 113×24, 113×12, 70×10, 70×7, 200×40 and 40×6.

Preview rows are player/target health, player/target power, pet health and pet power at 4×. The checkerboard demonstrates transparent exterior and the 30%-alpha empty interior. It includes both border copies and a 72%-full square fill. Owner approved the initial in-game appearance; exhaustive size/client combinations remain future regression checks.