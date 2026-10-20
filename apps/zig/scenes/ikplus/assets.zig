// --------------------------------------------------------------------------
// IK+ assets: the layout of the five .dat files and the one palette.
// (tools/private_tools/ikplus_assets.py)
//
// All of it is 2x art from the Go remake, halved to ST pixels on a clean grid,
// so an ST pixel is canvas pixel (2X, 2Y) exactly.  Nothing is quantized
// except the two raster colour tables, which are snapped to the ST's 3-bit
// channels (see the script).
//
//   font.dat   20x944   59 glyphs of 20x16, 1 = ink (colour index 1)
//   logo.dat   320x62   1 = ink (index 2), the "THE REPLICANTS" outline
//   stars.dat  320x23   10 frames of 32x23; 0 = clear, 3/4/5 = the grey
//   rast1.dat  200 RGBAs   the rainbow of the scrolltext, one a row
//   rast2.dat  690 RGBAs   the background rasters, one a (2x) row
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

/// The 320x200 content window inside the 400x280 overscan buffer, at the
/// visible window's origin.  All drawing is clipped to it.
pub const CONTENT_X: usize = zg.HORIZONTAL_BORDERS_WIDTH; // 40
pub const CONTENT_Y: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40
pub const CONTENT_W: usize = zg.WIDTH; // 320
pub const CONTENT_H: usize = zg.HEIGHT; // 200

// --- palette indices -------------------------------------------------------
pub const IDX_BG: u8 = 0; // per-line: rast2, or black
pub const IDX_TEXT: u8 = 1; // per-line: rast1 rainbow
pub const IDX_LOGO: u8 = 2; // 160,160,160
pub const IDX_STAR_DARK: u8 = 3; // 128
pub const IDX_STAR_MID: u8 = 4; // 192
pub const IDX_STAR_BRIGHT: u8 = 5; // 224

pub const BLACK: u32 = 0xFF00_0000;
pub const LOGO_RGBA: u32 = 0xFFA0_A0A0; // logo.png's (160,160,160)
pub const STAR_DARK_RGBA: u32 = 0xFF80_8080;
pub const STAR_MID_RGBA: u32 = 0xFFC0_C0C0;
pub const STAR_BRIGHT_RGBA: u32 = 0xFFE0_E0E0;

// --- font ------------------------------------------------------------------
pub const FONT_W: usize = 20;
pub const FONT_H: usize = 944; // 59 * 16
pub const GLYPH_W: usize = 20;
pub const GLYPH_H: usize = 16;
pub const GLYPH_COUNT: usize = FONT_H / GLYPH_H; // 59, ASCII ' '..'Z'

// --- logo ------------------------------------------------------------------
pub const LOGO_W: usize = 320;
pub const LOGO_H: usize = 62;
pub const LOGO_Y: usize = 18; // content row (the remake's 60+36, halved)

// --- stars -----------------------------------------------------------------
pub const STAR_W: usize = 32;
pub const STAR_H: usize = 23;
pub const STAR_FRAMES: usize = 10;
pub const STAR_COUNT: usize = 8;

pub const font: []const u8 = @embedFile("../../assets/screens/ikplus/font.dat");
pub const logo: []const u8 = @embedFile("../../assets/screens/ikplus/logo.dat");
pub const stars: []const u8 = @embedFile("../../assets/screens/ikplus/stars.dat");
pub const rast1_bytes: []const u8 = @embedFile("../../assets/screens/ikplus/rast1.dat");
pub const rast2_bytes: []const u8 = @embedFile("../../assets/screens/ikplus/rast2.dat");

/// The .dat files hold RGBA bytes; Color.toRGBA() is exactly the little-endian
/// u32 of them (a<<24 | b<<16 | g<<8 | r), so the HBL can write fb.palette
/// directly with no conversion.
fn rgbs(comptime bytes: []const u8) [bytes.len / 4]u32 {
    @setEvalBranchQuota(8 * bytes.len + 1000);
    var out: [bytes.len / 4]u32 = undefined;
    for (&out, 0..) |*v, i| v.* = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
    return out;
}

pub const rast1: [200]u32 = rgbs(rast1_bytes);
pub const rast2: [690]u32 = rgbs(rast2_bytes);

comptime {
    std.debug.assert(font.len == FONT_W * FONT_H);
    std.debug.assert(logo.len == LOGO_W * LOGO_H);
    std.debug.assert(stars.len == STAR_W * STAR_FRAMES * STAR_H);
    std.debug.assert(rast1_bytes.len == 200 * 4);
    std.debug.assert(rast2_bytes.len == 690 * 4);
}
