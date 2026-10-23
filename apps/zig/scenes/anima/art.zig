// --------------------------------------------------------------------------
// ANIMA's two pictures: their geometry (shared by the cart and the generator)
// and how they are built (run only by gen_anima.zig, on the host, at build
// time; build.zig hands the results to the cart as packed_assets.anima_logo /
// packed_assets.anima_font).
//
//   LOGO  "ANIMA" in the 16x16 font, EPX-doubled twice to 64-pixel letters,
//         bevel 3, outline 1, drop shadow 3, padded with WOB blank columns
//         each side (logo.zig's wobble margin): LH rows of LW indices
//   FONT  all 60 glyphs EPX-doubled once to 32x32, bevel 2, outline 1, one
//         strip of CELL_W x CELL_H cells (scroller.zig)
// --------------------------------------------------------------------------
const gen = @import("gen.zig");
const P = @import("palette.zig");

pub const WORD = "ANIMA";
const GW = 64; // a logo glyph after two EPX passes
const GAP = 2;
const PAD = 6; // room for the outline and the drop shadow
pub const WOB = 16;
pub const LW = 2 * WOB + 2 * PAD + WORD.len * GW + (WORD.len - 1) * GAP; // 372
pub const LH = GW + 2 * PAD; // 76

pub const CELL_W = 32;
pub const CELL_H = 34; // 32 + the outline above and below
pub const GLYPHS = gen.GLYPHS;
pub const STRIP_W = GLYPHS * CELL_W; // 1920

pub fn buildLogo(font: *const [gen.SHEET_BYTES]u8, out: *[LH * LW]u8) void {
    var m: [LH][LW]u1 = @splat(@splat(0));
    for (WORD, 0..) |c, k| {
        const g = gen.epx(32, 32, gen.epx(16, 16, gen.glyph16(font, c)));
        const ox = WOB + PAD + k * (GW + GAP);
        for (0..GW) |y| for (0..GW) |x| {
            if (g[y][x] != 0) m[PAD + y][ox + x] = 1;
        };
    }
    gen.shade(LH, LW, &m, 3, 3, .{
        .outline = P.LOGO_OUTLINE,
        .shadow = P.LOGO_SHADOW,
        .hi = P.LOGO_HI,
        .lo = P.LOGO_LO,
        .body = P.LOGO_BODY,
    }, out);
}

pub fn buildFont(font: *const [gen.SHEET_BYTES]u8, out: *[CELL_H * STRIP_W]u8) void {
    var m: [CELL_H][STRIP_W]u1 = @splat(@splat(0));
    for (0..GLYPHS) |i| {
        const g = gen.epx(16, 16, gen.glyph16(font, 32 + i));
        for (0..32) |y| for (0..30) |x| {
            if (g[y][x] != 0) m[1 + y][i * CELL_W + 1 + x] = 1;
        };
    }
    gen.shade(CELL_H, STRIP_W, &m, 2, 0, .{
        .outline = P.FONT_OUTLINE,
        .shadow = 0,
        .hi = P.FONT_HI,
        .lo = P.FONT_LO,
        .body = P.FONT_BODY,
    }, out);
}
