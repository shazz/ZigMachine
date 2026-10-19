// --------------------------------------------------------------------------
// grodan_kvack assets. Every byte here comes from tools/grodan_kvack/
// gk_assets.py, which rips the olivierh59500 Go/Ebitengine demo's own PNGs at
// HALF their size: the Go screen is 640x400, this cart is 320x200, so each
// layer is the Go art sampled at every even pixel/row (verified: the processed
// art's opaque mask matches the Go art's even-pixel mask byte for byte).
//
//   1-bit masks (MSB first, row-major, `get` below):
//     bg_green/bg_pink  320x199  the two tiled background line-art layers
//     sprite            204x10   12 frames, 17 apart, 16x10 drawn (Go Scale(2,2))
//     bsfont            240x200  the big font cell grid, drawn at Scale(4,3)
//     upfont            330x227  the vertical font cell grid, sampled 2x (Scale(0.5))
//     lfont             80x56    the small font cell grid, drawn 1:1
//   raster tables (one verbatim RGB row per line, as the ST colour registers
//   were written per scanline):
//     bigraster.pal     96 rows   the big canvas rows 0..95 (Go crop 160x96)
//     upraster.pal      200 rows  the vertical canvas rows 0..199, and rows
//                                 16..19/64..67 of them are the two small rasters
//   glyph-cell streams (0xFF = advance with no glyph), exactly the Go's
//   NewScrollText output for each font map:
//     main.cells vert.cells small1.cells small2.cells
//
// The four rasters are PURE VERTICAL GRADIENTS (one colour a row), i.e. an ST
// per-scanline colour register: this cart plays them from zg.copper (CLAUDE.md:
// a fake raster must become a real one).
// --------------------------------------------------------------------------
const zg = @import("zigos");

const DIR = "../../assets/screens/grodan_kvack/";

pub const BG_W = 320;
pub const BG_H = 199;
pub const SPRITE_W = 204;
pub const SPRITE_H = 10;
pub const SPRITE_STRIDE = 17;
pub const BSF_W = 240;
pub const BSF_H = 200;
pub const UPF_W = 330;
pub const UPF_H = 227;
pub const LF_W = 80;
pub const LF_H = 56;

pub const bg_green = @embedFile(DIR ++ "bg_green.raw");
pub const bg_pink = @embedFile(DIR ++ "bg_pink.raw");
pub const sprite = @embedFile(DIR ++ "sprite.raw");
pub const bsfont = @embedFile(DIR ++ "bsfont.raw");
pub const upfont = @embedFile(DIR ++ "upfont.raw");
pub const lfont = @embedFile(DIR ++ "lfont.raw");
pub const big_raster = @embedFile(DIR ++ "bigraster.pal"); // 96 * RGBA
pub const up_raster = @embedFile(DIR ++ "upraster.pal"); // 200 * RGBA

pub const main_cells = @embedFile(DIR ++ "main.cells");
pub const vert_cells = @embedFile(DIR ++ "vert.cells");
pub const small1_cells = @embedFile(DIR ++ "small1.cells");
pub const small2_cells = @embedFile(DIR ++ "small2.cells");

/// The .pal files are r,g,b,a little-endian per row, which is exactly the
/// RGBA word a palette entry holds (Color.toRGBA). Read them at comptime.
fn pal32(comptime raw: []const u8) [@divExact(raw.len, 4)]u32 {
    const n = @divExact(raw.len, 4);
    var t: [n]u32 = undefined;
    for (&t, 0..) |*o, i| o.* = @as(u32, raw[i * 4]) | (@as(u32, raw[i * 4 + 1]) << 8) |
        (@as(u32, raw[i * 4 + 2]) << 16) | (@as(u32, raw[i * 4 + 3]) << 24);
    return t;
}

pub const BIG_ROWS: [96]u32 = pal32(big_raster);
pub const UP_ROWS: [200]u32 = pal32(up_raster);

// ---- palette -----------------------------------------------------------------
// The Go PNGs carry these literal colours (all multiples of 32, i.e. exactly
// what an ST 3-bit-per-channel colour register can show). Entries 4/5/6 are the
// three raster entries: colour 0 here is a base the per-line copper overwrites.
pub const BLACK: u8 = 0;
pub const GREEN: u8 = 1;
pub const PINK: u8 = 2;
pub const SPRITE: u8 = 3;
pub const BIG: u8 = 4;
pub const VERT: u8 = 5;
pub const SMALL: u8 = 6;
pub const WHITE: u8 = 7;

pub const PALETTE = [8]zg.Color{
    .{ .r = 0, .g = 0, .b = 0, .a = 255 }, // 0 black
    .{ .r = 64, .g = 96, .b = 32, .a = 255 }, // 1 Grodan_green.png's ink
    .{ .r = 160, .g = 96, .b = 160, .a = 255 }, // 2 Grodan_pink.png's ink
    .{ .r = 0, .g = 224, .b = 224, .a = 255 }, // 3 sprite.png's ink
    .{ .r = 0, .g = 0, .b = 0, .a = 255 }, // 4..6 raster bases (copper)
    .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    .{ .r = 255, .g = 255, .b = 255, .a = 255 }, // 7 white (glyphs past the raster)
};

/// One bit of a packed 1-bit mask, MSB first, row-major.
pub inline fn bit(mask: []const u8, x: usize, y: usize, w: usize) u1 {
    const o = y * w + x;
    return @intCast((mask[o >> 3] >> @intCast(7 - (o & 7))) & 1);
}
