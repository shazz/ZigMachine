// Tests for the desk mode's picture (HW 1.17.0, machine/video_desk.zig): the two halves meet at
// row 240, a base's low three bits are ignored, alpha is always 255, the mode's test.
const std = @import("std");
const desk = @import("video_desk.zig");
const memmap = @import("sdk/memmap.zig");
const expectEqual = std.testing.expectEqual;

const BASE: usize = 64; // a region offset for plane 0 in the fake region below
var region: [BASE + desk.W * desk.H + 8]u8 = undefined;
var palette: [256]u32 = undefined;
var out: [desk.HALF_PIXELS]u32 = undefined;

// A byte per pixel that names its row and column: no two rows of a half are alike.
fn fill() void {
    for (&region, 0..) |*b, i| b.* = @truncate(i *% 7 +% i / desk.W);
    // the palette word's alpha is 0, its R, G, B the index three ways
    for (&palette, 0..) |*p, i| p.* = @as(u32, @intCast(i)) | @as(u32, @intCast(255 - i)) << 8 | @as(u32, @intCast(i ^ 0x5A)) << 16;
}

fn want(base: usize, x: usize, y: usize) u32 {
    return palette[region[base + y * desk.W + x]] | 0xFF00_0000;
}

test "half 0 is rows 0..239, half 1 rows 240..479: the seam" {
    fill();
    for ([_]u32{ 0, 1 }) |half| {
        desk.renderHalf(&out, &region, BASE, &palette, half);
        for ([_]usize{ 0, 1, 238, 239 }) |y| for ([_]usize{ 0, 1, 7, 8, 639 }) |x| {
            try expectEqual(want(BASE, x, half * 240 + y), out[y * desk.W + x]);
        };
    }
}

test "every pixel of half 1, against its row of the plane" {
    fill();
    desk.renderHalf(&out, &region, BASE, &palette, 1);
    for (0..desk.HALF_ROWS) |y| for (0..desk.W) |x| try expectEqual(want(BASE, x, 240 + y), out[y * desk.W + x]);
}

test "FB_BASE & ~7: the board fetches whole beats" {
    fill();
    var ref: [desk.HALF_PIXELS]u32 = undefined;
    desk.renderHalf(&ref, &region, BASE, &palette, 0);
    desk.renderHalf(&out, &region, BASE + 5, &palette, 0);
    try std.testing.expectEqualSlices(u32, &ref, &out);
    try expectEqual(@as(usize, 1000), desk.baseOf(1007));
}

test "alpha is 255 whatever the palette word says, R in the low byte" {
    try expectEqual(@as(u32, 0xFF332211), desk.colour(0x0033_2211));
    try expectEqual(@as(u32, 0xFF332211), desk.colour(0x8033_2211));
}

test "only RES_DESK is the desk mode" {
    try std.testing.expect(desk.active(memmap.RES_DESK));
    for ([_]u8{ memmap.RES_PLANES, memmap.RES_TRUECOLOR, memmap.RES_MEDIUM, 4, 255 }) |r| try std.testing.expect(!desk.active(r));
}

test "half a picture fits in the PFB, a whole one does not" {
    try std.testing.expect(desk.HALF_PIXELS * 4 <= memmap.PFB_BYTES);
    try std.testing.expect(desk.HALF_PIXELS * 8 > memmap.PFB_BYTES);
}
