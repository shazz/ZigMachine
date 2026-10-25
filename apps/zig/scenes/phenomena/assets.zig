// --------------------------------------------------------------------------
// The remake's assets, converted by tools/private_tools/phenomena_assets.py
// from prototypes/codef/560 (logo.png, font.png, photon.png, rasterbar.png and
// screen.js's msg), and every colour the screen computes AS CHROME RESOLVES IT
// (tools/private_tools/phenomena_codef_ref.mjs): the four canvas gradients, a
// row each, and the hsl() families. Taking Chrome's values, rather than
// re-deriving canvas gradient maths, is what makes them the remake's colours.
// --------------------------------------------------------------------------
const G = @import("geom.zig");

const DIR = "../../assets/screens/phenomena/";

/// 640x64: logo.png rows 1,3..127; 0 = transparent, else the palette index.
pub const logo: *const [G.W * G.LOGO_LINES]u8 = @embedFile(DIR ++ "logo.raw");
const logo_pal: *const [G.LOGO_N * 3]u8 = @embedFile(DIR ++ "logo_pal.dat");
const font_dat: *const [45 * 26 * 2]u8 = @embedFile(DIR ++ "font.dat");
/// photon.png, 15 rows of 70: 1 = ink.
pub const photon: *const [G.PHOTON_H * G.PHOTON_W]u8 = @embedFile(DIR ++ "photon.dat");
/// rasterbar.png: 80 rows, one grey each.
pub const bar_intro: *const [80]u8 = @embedFile(DIR ++ "bar_intro.dat");
const colours: *const [650 * 3]u8 = @embedFile(DIR ++ "colours.dat");
/// screen.js's msg.
pub const MESSAGE: *const [2119]u8 = @embedFile(DIR ++ "scrolltext.txt");

pub const GLYPHS: usize = 45;
pub const GLYPH_W: usize = 16;
pub const GLYPH_H: usize = 26;

/// The charset (screen.js), index = glyph number in font.png.
pub const CHARSET = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!'?/,.-$";

/// font.png as one u16 a glyph row: bit x = ink (white) at column x.
pub const FONT: [GLYPHS][GLYPH_H]u16 = blk: {
    @setEvalBranchQuota(20_000);
    var f: [GLYPHS][GLYPH_H]u16 = undefined;
    for (0..GLYPHS) |g| {
        for (0..GLYPH_H) |y| {
            const o = (g * GLYPH_H + y) * 2;
            f[g][y] = @as(u16, font_dat[o]) | (@as(u16, font_dat[o + 1]) << 8);
        }
    }
    break :blk f;
};

pub fn glyphOf(comptime ch: u8) u8 {
    for (CHARSET, 0..) |c, i| if (c == ch) return @intCast(i);
    @compileError("not in the charset: " ++ [_]u8{ch});
}

/// charset.indexOf as a table (every character the screen prints is in it).
pub const GLYPH_OF: [128]u8 = blk: {
    var t = [_]u8{0} ** 128;
    for (CHARSET, 0..) |c, i| t[c] = @intCast(i);
    break :blk t;
};

// --- colours (offsets into colours.dat, in triples) ------------------------
pub const BAR_ROWS = 0; // cnvRasterBar, 12 rows
pub const RED_ROWS = 12; // cnvRedBar, 9 rows
pub const SILVER_ROWS = 21; // cnvSilverBar, 33 rows
pub const PURPLE_ROWS = 54; // cnvPurpleBar, 33 rows
pub const GREY = 87; // hsl(0 0% p%), p = 0..100
pub const REDFADE = 188; // hsl(0 100% p%), p = 0..100
pub const HUE = 289; // hsl(h 100% 50%), h = 0..359
pub const PANEL_RGB = 649; // #000111

/// A colour as 0x00BBGGRR (the palette word's channel order, alpha left out). A
/// [3]u8 went through memory at odd addresses (an rgb() return, blend's result),
/// which LLVM moved as u16 + u8: ~50 misaligned accesses a frame, each a trap on
/// the board. A u32 stays in a register.
pub const Rgb = u32;

pub inline fn rgb3(r: u8, g: u8, b: u8) Rgb {
    return (@as(u32, b) << 16) | (@as(u32, g) << 8) | r;
}

inline fn channel(c: Rgb, k: u5) u32 {
    return (c >> (8 * k)) & 0xFF;
}

/// The triples of a .dat as Rgb words, built at compile time.
fn words(comptime n: usize, comptime bytes: *const [n * 3]u8) [n]Rgb {
    @setEvalBranchQuota(10 * n);
    var out: [n]Rgb = undefined;
    for (&out, 0..) |*w, i| w.* = rgb3(bytes[i * 3], bytes[i * 3 + 1], bytes[i * 3 + 2]);
    return out;
}
const colour_words = words(650, colours);
const logo_words = words(G.LOGO_N, logo_pal);

pub inline fn rgb(table: usize, i: usize) Rgb {
    return colour_words[table + i];
}

pub inline fn logoRgb(i: usize) Rgb {
    return logo_words[i];
}

/// A palette word (the machine's little-endian RGBA, opaque).
pub inline fn word(c: Rgb) u32 {
    return 0xFF00_0000 | c;
}

/// Canvas globalAlpha drawing of `src` over `dst`: alpha a/100 is an 8-bit
/// coverage in the canvas, and each channel rounds.
pub fn blend(src: Rgb, dst: Rgb, a100: u32) Rgb {
    const a: u32 = (a100 * 255 + 50) / 100;
    var o: Rgb = 0;
    inline for (0..3) |k| o |= ((channel(src, k) * a + channel(dst, k) * (255 - a) + 127) / 255) << (8 * k);
    return o;
}
