// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER, one row per pixel: the general path, for the rows where
// the copies overlap (two overlays, or a back from another copy than the
// overlay's) and the paired tables (layers.zig) do not apply. One or two rows a
// frame. A pixel's sources pack into a 17-bit key; the row's key cache finds
// the palette entry once per key (colour() + LinePalette.entry otherwise), and
// the row is written four pixels to a u32.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const M = @import("motion.zig");
const ink = @import("inkmask.zig");
const compose = @import("compose.zig");

const W_I: i32 = A.W; // for the signed letter positions
const ZERO_ROW: [A.W]u8 align(4) = @splat(0);

/// Image row `tap` (a canvas row, so halved) of an image, or zeros where no copy is drawn.
fn srcRow(image: []const u8, row: ?u16) *const [A.W]u8 {
    const r = row orelse return &ZERO_ROW;
    return image[(r >> 1) * A.W ..][0..A.W];
}

/// A pixel's sources packed: back taps 2 bits each, ink 1 bit, each overlay tap 3 bits.
inline fn keyAt(src: *const [6]*const [A.W]u8, ink_bit: u32, x: usize) u32 {
    return @as(u32, src[0][x]) | (@as(u32, src[1][x]) << 2) | (ink_bit << 4) |
        (@as(u32, src[2][x]) << 5) | (@as(u32, src[3][x]) << 8) | (@as(u32, src[4][x]) << 11) | (@as(u32, src[5][x]) << 14);
}

pub fn draw(row: *[A.W]u8, y: usize, img: *const A.Images, cache: *ink.KeyCache, m: *const M.Motion, l: compose.Layers, pal: *compose.Palette) void {
    const cy: i32 = @intCast(2 * y);
    var mask: ink.Mask = [_]u32{0} ** ink.WORDS;
    if (l.raster != null) markInk(&mask, img, m, cy - compose.SCROLL_Y);
    const src = [6]*const [A.W]u8{
        srcRow(img.back, if (l.back) |t| t.top else null),
        srcRow(img.back, if (l.back) |t| t.bottom else null),
        srcRow(img.overlay, if (l.overs[0]) |t| t.top else null),
        srcRow(img.overlay, if (l.overs[0]) |t| t.bottom else null),
        srcRow(img.overlay, if (l.overs[1]) |t| t.top else null),
        srcRow(img.overlay, if (l.overs[1]) |t| t.bottom else null),
    };
    pal.beginRow(y);
    cache.nextRow();
    const words: *[A.W / 4]u32 = @ptrCast(@alignCast(row));
    var last_key: u32 = std.math.maxInt(u32);
    var entry: u8 = 0;
    for (words, 0..) |*word, wi| {
        var packed_px: u32 = 0;
        inline for (0..4) |k| {
            const x = wi * 4 + k;
            const key = keyAt(&src, ink.bit(&mask, x), x);
            if (key != last_key) {
                last_key = key;
                entry = entryFor(key, img, l, cache, pal);
            }
            packed_px |= @as(u32, entry) << (8 * k);
        }
        word.* = packed_px;
    }
}

/// The row's palette entry for a pixel key: remembered per row, else made from its colour.
fn entryFor(key: u32, img: *const A.Images, l: compose.Layers, cache: *ink.KeyCache, pal: *compose.Palette) u8 {
    if (cache.find(key)) |e| return e;
    const e = pal.entry(compose.colour(img, l, compose.sampleOf(key)));
    cache.put(key, e);
    return e;
}

/// The columns of scroll-canvas row `s` (even) that a letter's ink covers.
fn markInk(m_ink: *ink.Mask, img: *const A.Images, m: *const M.Motion, s: i32) void {
    const glyph_row: usize = @intCast(@divExact(s, 2));
    for (m.ring.x, m.ring.c) |pos, ch| {
        if (pos >= 2 * W_I or pos + M.TILE_W <= 0) continue;
        for (img.font.runs(ch - A.FIRST_CHAR, glyph_row)) |run| {
            const cols = zg.spanfont.halfColumns(pos, run);
            const x0: usize = @intCast(std.math.clamp(cols[0], 0, W_I));
            const x1: usize = @intCast(std.math.clamp(cols[1], 0, W_I));
            if (x1 > x0) ink.setRange(m_ink, x0, x1);
        }
    }
}
