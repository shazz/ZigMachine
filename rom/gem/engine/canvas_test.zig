// Native tests of canvas.zig: every primitive stays inside the clip.
const std = @import("std");
const canvas = @import("canvas.zig");
const Canvas = canvas.Canvas;
const Rect = @import("rect.zig").Rect;
const expectEqual = std.testing.expectEqual;

const W = 32;
const H = 24;
const BG: u8 = 9;

fn fresh(buf: *[W * H]u8) Canvas {
    @memset(buf, BG);
    return Canvas.init(buf, W, W, H);
}
fn count(buf: *const [W * H]u8, outside: Rect) usize {
    var n: usize = 0;
    for (buf, 0..) |v, i| {
        const x: i32 = @intCast(i % W);
        const y: i32 = @intCast(i / W);
        if (v != BG and !outside.contains(x, y)) n += 1;
    }
    return n;
}

// A 2-glyph font: 'A' is a full 3x2 block, everything else blank.
const font_data = blk: {
    var d = [_]u8{0} ** (256 * 2);
    d['A' * 2] = 0b11100000;
    d['A' * 2 + 1] = 0b11100000;
    break :blk d;
};
const FONT: canvas.Font = .{ .w = 3, .h = 2, .data = &font_data };

test "fill, frame, text, bits and dotted never write outside the clip" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    const clip: Rect = .{ .x = 4, .y = 3, .w = 10, .h = 8 };
    c.setClip(clip);
    c.fill(.{ .x = -5, .y = -5, .w = 100, .h = 100 }, 1);
    c.frame(.{ .x = 0, .y = 0, .w = 20, .h = 20 }, -3, 2);
    c.text(&FONT, "AAAAAAAA", 0, 4, 3, 4);
    c.bits(&[_]u8{ 0xFF, 0xFF }, 1, 8, 2, 10, 9, 5, 6);
    c.dotted(.{ .x = 2, .y = 2, .w = 20, .h = 12 }, 7);
    c.plot(30, 20, 8);
    try expectEqual(@as(usize, 0), count(&buf, clip));
    try expectEqual(@as(u8, 3), buf[4 * W + 6]); // the text's ink, inside
}

test "frame thickness: positive inside, negative outside" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    const r: Rect = .{ .x = 10, .y = 8, .w = 6, .h = 6 };
    c.frame(r, 1, 1);
    try expectEqual(@as(u8, 1), buf[8 * W + 10]);
    try expectEqual(BG, buf[9 * W + 11]);
    c.frame(r, -2, 2);
    try expectEqual(@as(u8, 2), buf[6 * W + 8]);
    try expectEqual(@as(u8, 1), buf[8 * W + 10]); // the inside frame untouched
    try expectEqual(@as(usize, 0), count(&buf, r.grow(2)));
}

test "text in a font: ink, paper, and a transparent paper" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    c.text(&FONT, "AB", 1, 1, 3, null);
    try expectEqual(@as(u8, 3), buf[1 * W + 1]);
    try expectEqual(BG, buf[1 * W + 4]); // 'B' is blank and the paper transparent
    c.text(&FONT, "B", 10, 1, 3, 4);
    try expectEqual(@as(u8, 4), buf[1 * W + 10]);
    const raw = [_]u8{0} ** (256 * 6); // a byte-a-pixel font (ZigOS's raw): all blank
    const f2: canvas.Font = .{ .w = 3, .h = 2, .data = &raw, .packed_rows = false };
    c.text(&f2, "A", 20, 10, 3, 5);
    try expectEqual(@as(u8, 5), buf[10 * W + 20]);
}

test "pattern is aligned to the screen, chunky draws under its mask only" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    var pat = [_]u16{0} ** 16;
    pat[2] = 0x8000; // column 0 of every 16th row 2
    c.pattern(.{ .x = 0, .y = 0, .w = W, .h = H }, &pat, 1, null);
    try expectEqual(@as(u8, 1), buf[2 * W + 0]);
    try expectEqual(@as(u8, 1), buf[18 * W + 16]);
    try expectEqual(BG, buf[2 * W + 1]);
    const col = [_]u8{ 11, 12, 13, 14 };
    const mask = [_]u8{ 0b10000000, 0b01000000 };
    c.chunky(&col, &mask, 1, 2, 2, 5, 5);
    try expectEqual(@as(u8, 11), buf[5 * W + 5]);
    try expectEqual(BG, buf[5 * W + 6]);
    try expectEqual(@as(u8, 14), buf[6 * W + 6]);
}

var calls: usize = 0;
fn countFill(ctx: *anyopaque, at: [*]u8, stride: u32, w: u32, h: u32, v: u8) void {
    _ = ctx;
    calls += 1;
    var r: u32 = 0;
    while (r < h) : (r += 1) @memset(at[r * stride ..][0..w], v);
}

test "a big fill goes to the blitter hook, a small one is stores" {
    var big: [128 * 64]u8 = undefined;
    var c = Canvas.init(&big, 128, 128, 64);
    c.fill_fn = countFill;
    c.fill_ctx = @ptrCast(&big);
    calls = 0;
    c.fill(.{ .w = 8, .h = 8 }, 1);
    try expectEqual(@as(usize, 0), calls);
    c.fill(.{ .w = 128, .h = 64 }, 2);
    try expectEqual(@as(usize, 1), calls);
    try expectEqual(@as(u8, 2), big[127 + 63 * 128]);
}
