// --------------------------------------------------------------------------
// Pixel-art tools for the build-time generator (gen_anima.zig): the ANIMA logo
// and the scroller font are BUILT from the 16x16 bitmap font
// apps/zig/assets/fonts/font16.raw (320x48, 20x3 cells, ASCII from space, one
// byte a pixel 0/1; the 16X16-F5 sheet Matt supplied for music_debug).
//
//   epx      Eric's Pixel Expansion (Scale2x): doubles a 1-bit mask and rounds
//            its diagonals, so a 16-pixel glyph grows to 32 or 64 smooth pixels
//   shade    turns a mask into the five-colour metal look: a one-pixel outline,
//            a drop shadow, a bevel lit from the top left and dark at the bottom
//            right, and the body (a copper slot)
//
// It runs on the HOST at build time: Zig's compile-time interpreter needed
// minutes for these ~100K pixels. The cart holds only the finished pictures.
// --------------------------------------------------------------------------
const SHEET_W = 320;
pub const SHEET_BYTES = SHEET_W * 48;
pub const GLYPHS = 60; // ' ' .. '['

pub const Inks = struct { outline: u8, shadow: u8, hi: u8, lo: u8, body: u8 };

/// Glyph c of the 16x16 font as a mask (a char outside the sheet is blank).
pub fn glyph16(font: *const [SHEET_BYTES]u8, c: usize) [16][16]u1 {
    var g: [16][16]u1 = @splat(@splat(0));
    if (c < 32 or c >= 32 + GLYPHS) return g;
    const i = c - 32;
    const cx = (i % 20) * 16;
    const cy = (i / 20) * 16;
    for (0..16) |y| for (0..16) |x| {
        g[y][x] = @intFromBool(font[(cy + y) * SHEET_W + cx + x] != 0);
    };
    return g;
}

pub fn epx(comptime h: usize, comptime w: usize, src: [h][w]u1) [2 * h][2 * w]u1 {
    var o: [2 * h][2 * w]u1 = undefined;
    for (0..h) |y| for (0..w) |x| {
        const p = src[y][x];
        const a = if (y > 0) src[y - 1][x] else 0;
        const b = if (x + 1 < w) src[y][x + 1] else 0;
        const c = if (x > 0) src[y][x - 1] else 0;
        const d = if (y + 1 < h) src[y + 1][x] else 0;
        o[2 * y][2 * x] = if (c == a and c != d and a != b) a else p;
        o[2 * y][2 * x + 1] = if (a == b and a != c and b != d) b else p;
        o[2 * y + 1][2 * x] = if (d == c and d != b and c != a) c else p;
        o[2 * y + 1][2 * x + 1] = if (b == d and b != a and d != c) d else p;
    };
    return o;
}

/// The whole mask shaded into `out` (row-major, 0 where nothing is): one loop
/// over a zero-padded copy, so no neighbour read needs a bounds test.
pub fn shade(comptime h: usize, comptime w: usize, m: *const [h][w]u1, comptime bevel: usize, comptime drop: usize, k: Inks, out: *[h * w]u8) void {
    const M = bevel + drop + 1;
    var p: [h + 2 * M][w + 2 * M]u1 = @splat(@splat(0));
    for (0..h) |y| for (0..w) |x| {
        p[y + M][x + M] = m[y][x];
    };
    for (0..h) |y| for (0..w) |x| {
        const Y = y + M;
        const X = x + M;
        var v: u8 = 0;
        if (p[Y][X] != 0) {
            var up = false;
            var lf = false;
            var dn = false;
            var rt = false;
            for (1..bevel + 1) |d| {
                up = up or p[Y - d][X] == 0;
                lf = lf or p[Y][X - d] == 0;
                dn = dn or p[Y + d][X] == 0;
                rt = rt or p[Y][X + d] == 0;
            }
            const lit = up or lf;
            const dark = dn or rt;
            v = if (lit and !dark) k.hi else if (dark and !lit) k.lo else if (lit) (if (up) k.hi else k.lo) else k.body;
        } else if ((p[Y - 1][X - 1] | p[Y - 1][X] | p[Y - 1][X + 1] | p[Y][X - 1] | p[Y][X + 1] |
            p[Y + 1][X - 1] | p[Y + 1][X] | p[Y + 1][X + 1]) != 0)
        {
            v = k.outline;
        } else if (drop > 0 and (p[Y - drop][X - drop] | p[Y - drop + 1][X - drop]) != 0) {
            v = k.shadow;
        }
        out[y * w + x] = v;
    };
}
