#!/usr/bin/env dotnet run
// Velocity Frame Style: generates the geometric chrome textures the addon ships (spec §Chrome: GEOMETRIC, no art).
// Pure alpha shapes (white RGB, shape in alpha) so the addon tints them at runtime with SetVertexColor / SetBackdropColor.
//
// Usage: dotnet run Scripts/GenerateChromeAssets.cs [outDir]
// Default outDir: VelocityFrameStyle/Assets  (the addon folder, one level down - packager-style repo)
//
// Outputs (uncompressed 32-bit TGA, top-left origin):
//   rounded_mask.tga   32x32  rounded rect r=6   -> MaskTexture on each stock bar fill (rounded bar corners)
//   rounded_edge.tga   64x64  rounded rect r=12  -> BackdropTemplate edgeFile+bgFile 9-slice for the VFS_BarPlate
//   soft_disc.tga      64x64  feathered disc     -> VFS_PortraitDisc soft rim and the ADD-blend combat glow
//   soft_plate.tga    128x64  feathered rounded rect r=16 -> soft outer edge behind the plate (long tail)

using System.Buffers.Binary;

string outDir = args.Length > 0 ? args[0] : Path.Combine("VelocityFrameStyle", "Assets");
Directory.CreateDirectory(outDir);
Console.WriteLine($"Writing chrome assets to {Path.GetFullPath(outDir)}");

WriteTga(Path.Combine(outDir, "rounded_mask.tga"), 32, 32, (x, y) => RoundedRectCoverage(x, y, 32, 32, 6, 0.5));
WriteTga(Path.Combine(outDir, "rounded_edge.tga"), 64, 64, (x, y) => RoundedRectCoverage(x, y, 64, 64, 12, 0.5));
WriteTga(Path.Combine(outDir, "soft_disc.tga"), 64, 64, (x, y) => FeatheredDisc(x, y, 64, 0.78));
WriteTga(Path.Combine(outDir, "soft_plate.tga"), 128, 64, (x, y) => RoundedRectCoverage(x, y, 128, 64, 16, 6.0));
Console.WriteLine("SUCCESS");

// Signed-distance coverage of a rounded rectangle filling a w x h box with corner radius r.
// feather = half-width of the anti-alias / soft band in pixels (0.5 = crisp 1px AA, larger = soft edge).
static double RoundedRectCoverage(int x, int y, int w, int h, double r, double feather)
{
    double px = x + 0.5, py = y + 0.5;
    // distance from the point to the inner rectangle (the rect shrunk by r)
    double dx = Math.Max(Math.Max(r - px, px - (w - r)), 0);
    double dy = Math.Max(Math.Max(r - py, py - (h - r)), 0);
    double outside = Math.Sqrt(dx * dx + dy * dy) - r;           // <0 inside the rounded rect, >0 outside
    double a = 0.5 - outside / (2 * feather);                     // linear ramp across the feather band
    return Math.Clamp(a, 0, 1);
}

// Disc of diameter d: fully opaque to `solid` of the radius, fading to 0 at the edge.
static double FeatheredDisc(int x, int y, int d, double solid)
{
    double cx = x + 0.5 - d / 2.0, cy = y + 0.5 - d / 2.0;
    double t = Math.Sqrt(cx * cx + cy * cy) / (d / 2.0);
    if (t >= 1) return 0;
    if (t <= solid) return 1;
    return (1 - t) / (1 - solid);
}

static void WriteTga(string path, int w, int h, Func<int, int, double> alphaAt)
{
    var header = new byte[18];
    header[2] = 2;                                                 // uncompressed true-colour
    BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(12), (ushort)w);
    BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(14), (ushort)h);
    header[16] = 32;                                               // bits per pixel
    header[17] = 0x28;                                             // 8 alpha bits, top-left origin
    var data = new byte[w * h * 4];
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            int i = (y * w + x) * 4;
            data[i] = data[i + 1] = data[i + 2] = 255;              // BGR white; tinted in game
            data[i + 3] = (byte)Math.Round(Math.Clamp(alphaAt(x, y), 0, 1) * 255);
        }
    using var fs = File.Create(path);
    fs.Write(header);
    fs.Write(data);
    Console.WriteLine($"  {Path.GetFileName(path),-18} {w}x{h}  {header.Length + data.Length:N0} bytes");
}