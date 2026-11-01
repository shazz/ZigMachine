// --------------------------------------------------------------------------
// polyfill.zig tests: the window, clipping, non-convex shapes, and the filler
// against its divide-per-row reference, CPU spans and blitter rects alike.
// --------------------------------------------------------------------------
const std = @import("std");
const polyfill = @import("polyfill.zig");
const monotone = @import("monotone.zig");
const Target = polyfill.Target;
const Point = polyfill.Point;
const MAX_VERTS = polyfill.MAX_VERTS;
const fill = polyfill.fill;
const clip = polyfill.clip;
const expectEqual = std.testing.expectEqual;

fn count(px: []const u8, color: u8) usize {
    var n: usize = 0;
    for (px) |p| n += @intFromBool(p == color);
    return n;
}

test "a 3x3 square covers exactly its 9 pixel centres" {
    var px = [_]u8{0} ** (8 * 8);
    const t = Target{ .px = &px, .stride = 8, .w = 8, .h = 8, .ox = 0 };
    fill(t, &.{ .{ .x = 1, .y = 1 }, .{ .x = 4, .y = 1 }, .{ .x = 4, .y = 4 }, .{ .x = 1, .y = 4 } }, 5);
    try expectEqual(@as(usize, 9), count(&px, 5));
    try expectEqual(@as(u8, 5), px[1 * 8 + 1]);
    try expectEqual(@as(u8, 5), px[3 * 8 + 3]);
    try expectEqual(@as(u8, 0), px[4 * 8 + 4]);
}

test "a non-convex U leaves its notch empty" {
    var px = [_]u8{0} ** (8 * 8);
    const t = Target{ .px = &px, .stride = 8, .w = 8, .h = 8, .ox = 0 };
    fill(t, &.{
        .{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 4 }, .{ .x = 4, .y = 4 },
        .{ .x = 4, .y = 0 }, .{ .x = 6, .y = 0 }, .{ .x = 6, .y = 6 }, .{ .x = 0, .y = 6 },
    }, 1);
    try expectEqual(@as(u8, 0), px[2 * 8 + 3]); // inside the notch
    try expectEqual(@as(u8, 1), px[2 * 8 + 1]); // left arm
    try expectEqual(@as(u8, 1), px[5 * 8 + 3]); // base
    try expectEqual(@as(usize, 36 - 8), count(&px, 1));
}

test "a vertex count outside 3..MAX_VERTS draws nothing" {
    var px = [_]u8{0} ** (8 * 8);
    const t = Target{ .px = &px, .stride = 8, .w = 8, .h = 8, .ox = 0 };
    fill(t, &.{}, 3);
    fill(t, &.{ .{ .x = 0, .y = 0 }, .{ .x = 8, .y = 8 } }, 3);
    const many = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 8, .y = 0 }, .{ .x = 8, .y = 8 } } ** 6;
    fill(t, &many, 3);
    try expectEqual(@as(usize, 0), count(&px, 3));
}

test "a polygon larger than the window is clipped to it, offset included" {
    var px = [_]u8{0} ** (10 * 4);
    const t = Target{ .px = &px, .stride = 10, .w = 6, .h = 4, .ox = 2 };
    fill(t, &.{ .{ .x = -50, .y = -50 }, .{ .x = 300, .y = -50 }, .{ .x = 300, .y = 300 } }, 7);
    for (0..4) |y| {
        try expectEqual(@as(u8, 0), px[y * 10 + 0]); // left of the window
        try expectEqual(@as(u8, 0), px[y * 10 + 9]); // right of the window
    }
    try expectEqual(@as(u8, 7), px[0 * 10 + 7]); // top-right corner of the window is inside
}

// The filler as it was (an i64 divide per edge per row, one span at a time), kept as
// the reference the stepped edges and the merged rows must reproduce pixel for pixel.
fn refFill(t: Target, pts: []const Point, color: u8) void {
    var ymin: i32 = std.math.maxInt(i32);
    var ymax: i32 = std.math.minInt(i32);
    for (pts) |p| {
        ymin = @min(ymin, p.y);
        ymax = @max(ymax, p.y);
    }
    var y = @max(ymin, 0);
    const y_end = @min(ymax, @as(i32, @intCast(t.h)));
    while (y < y_end) : (y += 1) {
        const cy2 = 2 * y + 1;
        var xs: [MAX_VERTS]i32 = undefined;
        var n: usize = 0;
        var j = pts.len - 1;
        for (pts, 0..) |a, i| {
            defer j = i;
            const b = pts[j];
            if (a.y == b.y) continue;
            const lo = if (a.y < b.y) a else b;
            const hi = if (a.y < b.y) b else a;
            if (cy2 < 2 * lo.y or cy2 >= 2 * hi.y) continue;
            const num = @as(i64, hi.x - lo.x) * (cy2 - 2 * lo.y) * 65536;
            const x = lo.x * 65536 + @as(i32, @intCast(@divFloor(num, 2 * (hi.y - lo.y))));
            var m = n;
            while (m > 0 and xs[m - 1] > x) : (m -= 1) xs[m] = xs[m - 1];
            xs[m] = x;
            n += 1;
        }
        var k: usize = 0;
        while (k + 1 < n) : (k += 2) {
            const sp = clip(t, xs[k], xs[k + 1]);
            if (sp.start >= sp.end) continue;
            const row = @as(usize, @intCast(y)) * t.stride + t.ox;
            @memset(t.px[row + @as(usize, @intCast(sp.start)) .. row + @as(usize, @intCast(sp.end))], color);
        }
    }
}

test "stepped edges and merged rows draw what the divide-per-row filler drew" {
    var prng = std.Random.DefaultPrng.init(0x57a1c);
    const rnd = prng.random();
    var a = [_]u8{0} ** (64 * 48);
    var b = [_]u8{0} ** (64 * 48);
    for (0..4000) |_| {
        var pts: [MAX_VERTS]Point = undefined;
        const n = 3 + rnd.uintLessThan(usize, MAX_VERTS - 2);
        for (pts[0..n]) |*p| p.* = .{ .x = rnd.intRangeAtMost(i32, -20, 90), .y = rnd.intRangeAtMost(i32, -20, 70) };
        if (rnd.boolean()) { // vertical sides, as a rectangle: rows that repeat
            pts[1] = .{ .x = pts[0].x, .y = pts[1].y };
            pts[2] = .{ .x = pts[3 % n].x, .y = pts[2].y };
        }
        @memset(&a, 0);
        @memset(&b, 0);
        const ta = Target{ .px = &a, .stride = 64, .w = 56, .h = 48, .ox = 4 };
        const tb = Target{ .px = &b, .stride = 64, .w = 56, .h = 48, .ox = 4 };
        fill(ta, pts[0..n], 9);
        refFill(tb, pts[0..n], 9);
        try expectEqual(b, a);
    }
}

// A blitter stand-in: the rect hook writes the bytes itself, as CHISEL would.
var hook_px: []u8 = &.{};
var hook_stride: usize = 0;
fn hookRect(x: usize, y: usize, w: usize, h: usize, color: u8) void {
    for (0..h) |r| @memset(hook_px[(y + r) * hook_stride + x ..][0..w], color);
}

test "fills routed to a rect hook draw what the CPU spans draw" {
    var prng = std.Random.DefaultPrng.init(0xb117);
    const rnd = prng.random();
    var a = [_]u8{0} ** (64 * 48);
    var b = [_]u8{0} ** (64 * 48);
    hook_px = &b;
    hook_stride = 64;
    for (0..2000) |_| {
        var pts: [MAX_VERTS]Point = undefined;
        const n = 3 + rnd.uintLessThan(usize, MAX_VERTS - 2);
        for (pts[0..n]) |*p| p.* = .{ .x = rnd.intRangeAtMost(i32, -20, 90), .y = rnd.intRangeAtMost(i32, -20, 70) };
        const ta = Target{ .px = &a, .stride = 64, .w = 55, .h = 47, .ox = 3 };
        const tb = Target{ .px = &b, .stride = 64, .w = 55, .h = 47, .ox = 3, .rect = hookRect, .blit_min = 0 };
        polyfill.rect(ta, 1, 1, 9, 5, 0); // a clear of part of the window, as player.clear
        polyfill.rect(tb, 1, 1, 9, 5, 0);
        fill(ta, pts[0..n], 4);
        fill(tb, pts[0..n], 4);
        try expectEqual(a, b);
    }
}

test "the two-chain path draws what the divide-per-row filler drew, when it takes a polygon" {
    var prng = std.Random.DefaultPrng.init(0x2c4a1);
    const rnd = prng.random();
    var a = [_]u8{0} ** (64 * 48);
    var b = [_]u8{0} ** (64 * 48);
    var taken: usize = 0;
    for (0..20000) |_| {
        var pts: [6]Point = undefined;
        const n = 3 + rnd.uintLessThan(usize, 4);
        for (pts[0..n]) |*p| p.* = .{ .x = rnd.intRangeAtMost(i32, -20, 90), .y = rnd.intRangeAtMost(i32, -20, 70) };
        if (rnd.uintLessThan(u8, 4) == 0) pts[1].y = pts[0].y; // flat tops and sides
        @memset(&a, 0);
        @memset(&b, 0);
        const ta = Target{ .px = &a, .stride = 64, .w = 56, .h = 48, .ox = 4 };
        const tb = Target{ .px = &b, .stride = 64, .w = 56, .h = 48, .ox = 4 };
        var ymin: i32 = 1000;
        var ymax: i32 = -1000;
        for (pts[0..n]) |p| {
            ymin = @min(ymin, p.y);
            ymax = @max(ymax, p.y);
        }
        const y0 = @max(ymin, 0);
        const y1 = @min(ymax, 48);
        if (y0 >= y1 or !monotone.fill(ta, pts[0..n], y0, y1, 9)) continue;
        taken += 1;
        refFill(tb, pts[0..n], 9);
        try expectEqual(b, a);
    }
    try std.testing.expect(taken > 8000); // every triangle, and many of the rest
}
