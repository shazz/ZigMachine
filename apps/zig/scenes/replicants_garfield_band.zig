// --------------------------------------------------------------------------
// REPLICANTS GARFIELD: the scrolltext band composed a word at a time.
//
// The band is 16 rows x 288 columns of the mask's hole. Every pixel there is
// either the frame (frame_px) or, where a glyph covers it, the mask's colour at
// that pixel ('source-atop'), so restoring the band and then blitting ~18 keyed,
// pattern-inked glyphs (a byte decision per pixel) is the same as writing each
// word once:
//     word = (mask_word & cover) | (frame_word & ~cover)
// where `cover` has 0xFF in each byte a glyph pixel lands on. The glyphs become
// 1-bit rows at comptime (bit b = pixel b, so a nibble of coverage expands to a
// word through a 16-entry table), are ORed into a coverage line per row, and
// the plane gets 72 word stores a row, each a 4-aligned address: no restore
// pass, no read of the plane.
//
// It reproduces blit.blit(hole, font, cell, gx, text_y, key 0, .pattern mask)
// over a restored band exactly: the glyph rows are clipped to the hole the same
// way, and overlapping glyphs both write the mask's colour, which an OR keeps.
// --------------------------------------------------------------------------

pub const Geometry = struct {
    glyph: usize, // glyph size (square)
    font_cols: usize, // glyphs per row of the font image
    first: u8, // the font's first character
    w: usize, // band width = mask width (the hole)
    mask_y: usize, // the band's first row within the mask
    stride: usize, // plane and frame stride
    x_frac: u5, // a letter's x carries this many fraction bits (floored away)
};

pub fn Band(comptime g: Geometry, comptime font: []const u8, comptime n_glyphs: usize) type {
    if (g.glyph != 16) @compileError("band: glyph rows are u16");
    if (g.w % 32 != 0) @compileError("band: the width must be whole coverage words");
    const PAD = 32; // coverage bit = pixel + PAD: x > -16 never shifts negative, and pixel 0 is bit 0 of word 1
    const COVER_WORDS = (g.w + 2 * PAD) / 32 + 1;
    return struct {
        /// Each glyph's rows as bits: bit b set where pixel b is not the key 0.
        const bits: [n_glyphs][g.glyph]u16 = blk: {
            @setEvalBranchQuota(200_000);
            var t: [n_glyphs][g.glyph]u16 = undefined;
            const fw = g.font_cols * g.glyph;
            for (0..n_glyphs) |n| for (0..g.glyph) |r| {
                var v: u16 = 0;
                const at = ((n / g.font_cols) * g.glyph + r) * fw + (n % g.font_cols) * g.glyph;
                for (0..g.glyph) |b| if (font[at + b] != 0) {
                    v |= 1 << b;
                };
                t[n][r] = v;
            };
            break :blk t;
        };
        /// A coverage nibble -> the byte mask of those four pixels (little-endian).
        const expand: [16]u32 = blk: {
            var t: [16]u32 = undefined;
            for (0..16) |m| {
                var v: u32 = 0;
                for (0..4) |b| if (m & (1 << b) != 0) {
                    v |= @as(u32, 0xFF) << (8 * b);
                };
                t[m] = v;
            }
            break :blk t;
        };

        /// `plane` and `frame` point at the band's top-left pixel (stride g.stride),
        /// `ink` at the mask's row 0 (stride g.w); xs/cs are the letters' x in the
        /// band (with g.x_frac fraction bits) and their characters.
        pub fn draw(plane: [*]align(4) u8, frame: [*]align(4) const u8, ink: [*]align(4) const u8, xs: []const i32, cs: []const u8) void {
            for (0..g.glyph) |r| {
                var cover = [_]u32{0} ** COVER_WORDS;
                for (xs, cs) |x, c| orGlyph(&cover, x >> g.x_frac, bits[c - g.first][r]);
                const o = r * g.stride;
                composeRow(@ptrCast(@alignCast(plane + o)), @ptrCast(@alignCast(frame + o)), @ptrCast(@alignCast(ink + (g.mask_y + r) * g.w)), &cover);
            }
        }

        fn orGlyph(cover: *[COVER_WORDS]u32, x: i32, row: u16) void {
            if (x <= -@as(i32, g.glyph) or x >= g.w or row == 0) return; // outside the hole
            const pos: u32 = @intCast(x + PAD);
            const sh: u5 = @truncate(pos);
            const wd = pos >> 5;
            cover[wd] |= @as(u32, row) << sh;
            if (sh > 32 - g.glyph) cover[wd + 1] |= @as(u32, row) >> @intCast(32 - @as(u32, sh));
        }

        fn composeRow(out: [*]u32, frame: [*]const u32, ink: [*]const u32, cover: *const [COVER_WORDS]u32) void {
            // one coverage word = 32 pixels = 8 plane words, a nibble each
            for (0..g.w / 32) |w| {
                var c = cover[w + PAD / 32];
                inline for (0..8) |k| {
                    const i = 8 * w + k;
                    const m = expand[c & 0xF];
                    c >>= 4;
                    out[i] = (ink[i] & m) | (frame[i] & ~m);
                }
            }
        }
    };
}
