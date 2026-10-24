// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER letters on a paired row: each glyph run of the row, in
// the half-resolution columns spanfont gives (the same columns slowrow's ink
// mask marks), is copied from the row's LI image (layers.zig), whose byte at x
// is already the entry of "ink under this pixel's overlay taps". Source and
// destination rows share their alignment, so a run is whole u32 words, its two
// edge words merged: on the board a store is a bus write whatever its width.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const M = @import("motion.zig");

const W_I: i32 = A.W;

pub fn row(dst: *[A.W]u8, src: *const [A.W]u8, img: *const A.Images, m: *const M.Motion, glyph_row: u8) void {
    for (m.ring.x, m.ring.c) |pos, ch| {
        if (pos >= 2 * W_I or pos + M.TILE_W <= 0) continue;
        for (img.font.runs(ch - A.FIRST_CHAR, glyph_row)) |run| {
            const cols = zg.spanfont.halfColumns(pos, run);
            const x0: usize = @intCast(std.math.clamp(cols[0], 0, W_I));
            const x1: usize = @intCast(std.math.clamp(cols[1], 0, W_I));
            if (x1 > x0) copyRun(dst, src, x0, x1);
        }
    }
}

fn copyRun(dst: *[A.W]u8, src: *const [A.W]u8, x0: usize, x1: usize) void {
    const dw: *[A.W / 4]u32 = @ptrCast(@alignCast(dst));
    const sw: *const [A.W / 4]u32 = @ptrCast(@alignCast(src));
    var w0 = x0 >> 2;
    var w1 = (x1 + 3) >> 2; // words touched: [w0, w1)
    if (w0 + 1 == w1) return merge(dw, sw, w0, lanes(x0 & 3, x1 - 4 * w0));
    if (x0 & 3 != 0) {
        merge(dw, sw, w0, lanes(x0 & 3, 4));
        w0 += 1;
    }
    if (x1 & 3 != 0) {
        w1 -= 1;
        merge(dw, sw, w1, lanes(0, x1 & 3));
    }
    for (dw[w0..w1], sw[w0..w1]) |*d, s| d.* = s;
}

/// Bytes lo..hi (exclusive) of a little-endian word.
fn lanes(lo: usize, hi: usize) u32 {
    var m: u32 = 0;
    for (lo..hi) |k| m |= @as(u32, 0xFF) << @intCast(8 * k);
    return m;
}

/// The lanes of `src`'s word into `dst`'s: one bus write where three byte
/// stores would be, and a read of what the blitter just put there.
fn merge(dw: *[A.W / 4]u32, sw: *const [A.W / 4]u32, i: usize, mask: u32) void {
    dw[i] = (dw[i] & ~mask) | (sw[i] & mask);
}
