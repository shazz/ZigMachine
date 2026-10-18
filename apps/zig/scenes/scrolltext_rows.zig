// --------------------------------------------------------------------------
// Whole-row letter copy for a zg.Scrolltext strip. The library's Sprite.render
// walks the letter a pixel at a time (clamp tests, a divide, a narrow store each);
// on ZIGGY every store is a blocking bus write, so this copies each letter's rows
// with @memcpy instead. The letters of a Scrolltext sit edge to edge, zero pixels
// included, so over a strip they cover it completely and the strip needs no clear
// first. Pixel-identical to Sprite.render onto a cleared strip whose colour 0 is
// transparent (a letter clipped by the strip's edges is cut the same way).
// --------------------------------------------------------------------------
const std = @import("std");

/// Copy every letter of `st` (a zg.Scrolltext) into `dst`, whose rows are `stride`
/// bytes apart and `width` pixels wide; letters are `gw` x `gh`.
pub fn draw(st: anytype, dst: [*]u8, stride: usize, width: i32, gw: usize, gh: usize) void {
    for (&st.fonts) |*f| {
        const from_i: i32 = @max(0, -f.pos_x);
        const to_i: i32 = @min(@as(i32, @intCast(gw)), width - f.pos_x);
        if (from_i >= to_i) continue;
        const from: usize = @intCast(from_i);
        const n: usize = @intCast(to_i - from_i);
        const x: usize = @intCast(f.pos_x + from_i);
        for (0..gh) |r| {
            @memcpy(dst[r * stride + x ..][0..n], f.sprite.data[r * gw + from ..][0..n]);
        }
    }
}
