// Tests for effects/blit.zig: clipping on every edge, negative coordinates, key
// transparency, each ink mode, windows, and degenerate views.
const std = @import("std");
const b = @import("blit.zig");
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

const BG: u8 = 0xEE;
const W = 6;
const H = 4;

// 3x2 source, values 1..6
const src_px = [_]u8{ 1, 2, 3, 4, 5, 6 };
const src = b.Image.init(&src_px, 3);

fn fresh(buf: *[W * H]u8) b.Dst {
    @memset(buf, BG);
    return b.Dst.buffer(buf, W);
}

fn expectUntouched(buf: *const [W * H]u8) !void {
    for (buf) |p| try expectEqual(BG, p);
}

test "copy fully inside" {
    var buf: [W * H]u8 = undefined;
    b.blit(fresh(&buf), src, null, 1, 1, null, .copy);
    try expectEqualSlices(u8, &.{ BG, BG, BG, BG, BG, BG, BG, 1, 2, 3, BG, BG, BG, 4, 5, 6, BG, BG, BG, BG, BG, BG, BG, BG }, &buf);
}

test "fully off-screen on each side draws nothing" {
    var buf: [W * H]u8 = undefined;
    const d = fresh(&buf);
    b.blit(d, src, null, -3, 0, null, .copy); // left: last column at -1
    b.blit(d, src, null, W, 0, null, .copy); // right
    b.blit(d, src, null, 0, -2, null, .copy); // top
    b.blit(d, src, null, 0, H, null, .copy); // bottom
    b.blit(d, src, null, std.math.minInt(i32), std.math.maxInt(i32), null, .copy); // no overflow
    try expectUntouched(&buf);
}

test "partial on each edge" {
    var buf: [W * H]u8 = undefined;
    const d = fresh(&buf);
    b.blit(d, src, null, -1, -1, null, .copy); // top-left: only 5, 6
    try expectEqualSlices(u8, &.{ 5, 6, BG }, buf[0..3]);
    _ = fresh(&buf);
    b.blit(d, src, null, W - 1, H - 1, null, .copy); // bottom-right: only 1
    try expectEqual(@as(u8, 1), buf[W * H - 1]);
    try expectEqual(BG, buf[W * H - 2]);
    try expectEqual(BG, buf[(H - 2) * W + W - 1]);
}

test "destination smaller than source" {
    var small: [2 * 1]u8 = .{ BG, BG };
    b.blit(b.Dst.buffer(&small, 2), src, null, -1, 0, null, .copy);
    try expectEqualSlices(u8, &.{ 2, 3 }, &small);
}

test "part rect, clipped to the source" {
    var buf: [W * H]u8 = undefined;
    b.blit(fresh(&buf), src, .{ .x = 1, .y = 1, .w = 10, .h = 10 }, 0, 0, null, .copy);
    try expectEqualSlices(u8, &.{ 5, 6, BG }, buf[0..3]);
    try expectEqual(BG, buf[W]);
    var buf2: [W * H]u8 = undefined;
    b.blit(fresh(&buf2), src, .{ .x = 3, .y = 0, .w = 1, .h = 1 }, 0, 0, null, .copy); // outside
    try expectUntouched(&buf2);
}

test "key transparency" {
    var buf: [W * H]u8 = undefined;
    b.blit(fresh(&buf), src, null, 0, 0, 2, .copy);
    try expectEqualSlices(u8, &.{ 1, BG, 3 }, buf[0..3]);
    b.blit(fresh(&buf), src, null, 0, 0, 5, .{ .flat = 9 });
    try expectEqualSlices(u8, &.{ 9, 9, 9, BG, BG, BG, 9, BG, 9 }, buf[0..9]);
}

test "flat, offset, lut" {
    var buf: [W * H]u8 = undefined;
    b.blit(fresh(&buf), src, null, 0, 0, null, .{ .offset = 254 });
    try expectEqualSlices(u8, &.{ 255, 0, 1 }, buf[0..3]); // wraps
    var lut: [256]u8 = undefined;
    for (&lut, 0..) |*e, i| e.* = @intCast(100 + (i % 100));
    b.blit(fresh(&buf), src, null, 0, 0, null, .{ .lut = &lut });
    try expectEqualSlices(u8, &.{ 101, 102, 103 }, buf[0..3]);
}

test "row ink is per destination row, and stops at the table's end" {
    var buf: [W * H]u8 = undefined;
    const rows = [_]u8{ 10, 20 }; // destination rows 0 and 1 only
    b.blit(fresh(&buf), src, null, 0, 1, null, .{ .row = &rows });
    try expectEqualSlices(u8, &.{ 20, 20, 20 }, buf[W .. W + 3]);
    try expectEqual(BG, buf[2 * W]); // row 2: past the table
}

test "pattern colours by destination position and clips to its extent" {
    var buf: [W * H]u8 = undefined;
    const pat_px = [_]u8{ 70, 71, 72, 73 }; // 2x2 at dst (1, 0)
    const pat = b.Pattern{ .img = b.Image.init(&pat_px, 2), .ox = 1, .oy = 0 };
    b.blit(fresh(&buf), src, null, 0, 0, 3, .{ .pattern = pat });
    // col 0 is outside the pattern; col 2's source pixel is the key (3)
    try expectEqualSlices(u8, &.{ BG, 70, BG, BG }, buf[0..4]);
    try expectEqualSlices(u8, &.{ BG, 72, 73, BG }, buf[W .. W + 4]);
}

test "window clips and relocates the origin" {
    var buf: [W * H]u8 = undefined;
    const win = fresh(&buf).window(2, 1, 2, 2);
    try expectEqual(@as(usize, 2), win.w);
    b.blit(win, src, null, -1, 0, null, .copy);
    try expectEqualSlices(u8, &.{ BG, BG, 2, 3, BG, BG }, buf[W .. 2 * W]);
    try expectEqualSlices(u8, &.{ BG, BG, 5, 6, BG, BG }, buf[2 * W .. 3 * W]);
    try expectEqual(BG, buf[3 * W + 2]);
}

test "degenerate views draw nothing" {
    var buf: [W * H]u8 = undefined;
    const d = fresh(&buf);
    b.blit(d.window(W, 0, 4, 4), src, null, 0, 0, null, .copy);
    b.blit(d.window(0, 0, 0, 3), src, null, 0, 0, null, .copy);
    b.blit(b.Dst.buffer(&buf, 0), src, null, 0, 0, null, .copy);
    b.blit(d, b.Image.init(&src_px, 0), null, 0, 0, null, .copy);
    try expectUntouched(&buf);
}

test "stretchY: scale 1 is a plain blit, -1 flips, 0.5 keeps every other row, 0 draws nothing" {
    // a 1x4 source, values 1..4, centred on row 2 of a 1-wide, 4-high view
    const col = b.Image.init(&[_]u8{ 1, 2, 3, 4 }, 1);
    var buf: [4]u8 = undefined;
    @memset(&buf, BG);
    b.stretchY(b.Dst.buffer(&buf, 1), col, 0, 2, 1, null, .copy);
    try expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &buf);
    @memset(&buf, BG);
    b.stretchY(b.Dst.buffer(&buf, 1), col, 0, 2, -1, null, .copy);
    try expectEqualSlices(u8, &.{ 4, 3, 2, 1 }, &buf);
    @memset(&buf, BG);
    b.stretchY(b.Dst.buffer(&buf, 1), col, 0, 2, 0.5, null, .copy);
    try expectEqualSlices(u8, &.{ BG, 2, 4, BG }, &buf); // rows 1, 2 sample v = 1, 3
    @memset(&buf, BG);
    b.stretchY(b.Dst.buffer(&buf, 1), col, 0, 2, 0, null, .copy);
    try expectEqualSlices(u8, &.{ BG, BG, BG, BG }, &buf);
    @memset(&buf, BG);
    b.stretchY(b.Dst.buffer(&buf, 1), col, 0, -10, 1, null, .copy); // fully above the view
    try expectEqualSlices(u8, &.{ BG, BG, BG, BG }, &buf);
}

test "plane view uses the plane's stride" {
    const Plane = struct { fb: [*]u8, stride: u16, fb_w: u16, fb_h: u16 };
    var mem = [_]u8{BG} ** (8 * 3);
    const p = Plane{ .fb = &mem, .stride = 8, .fb_w = 4, .fb_h = 3 };
    const d = b.Dst.plane(p);
    b.blit(d, src, null, 2, 1, null, .copy);
    try expectEqualSlices(u8, &.{ BG, BG, 1, 2, BG }, mem[8..13]); // col 4 is outside fb_w
    try expectEqualSlices(u8, &.{ BG, BG, 4, 5, BG }, mem[16..21]);
}
