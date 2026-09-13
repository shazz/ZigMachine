// Tests for effects/wave.zig: each port's hand-written sine loop is reproduced
// value for value (accumulate/multiply, rounding, base inside the rounding),
// and siny draws every column group at its offset, clipped and keyed.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const wave = @import("wave.zig");
const blit = @import("blit.zig");

test "accumulate, two terms, base inside trunc: supplex_fs2's loop" {
    const a0: f32 = 1.234;
    const b0: f32 = -0.5;
    const W = wave.SineSum(f32, 2){ .base = 170, .amp = .{ 15, 50 }, .phase = .{ a0, b0 }, .inc = .{ 0.06, 0.02 } };
    var it = W.sweep(0);
    var a = a0;
    var b = b0;
    for (0..320) |_| {
        const want: i32 = @intFromFloat(@as(f32, 170.0) + 15.0 * @sin(a) + 50.0 * @sin(b));
        try expectEqual(want, it.next());
        a += 0.06;
        b += 0.02;
    }
}

test "accumulate, one term, round, no base: union scroller's loop" {
    const W = wave.SineSum(f32, 1){ .amp = .{10}, .phase = .{-7.77}, .inc = .{0.03}, .rounding = .round };
    var it = W.sweep(0);
    var v: f32 = -7.77;
    for (0..134) |_| {
        const want: i16 = @intFromFloat(@round(@sin(v) * 10.0));
        try expectEqual(@as(i32, want), it.next());
        v += 0.03;
    }
}

test "multiply with a negative origin: noextra's glyph columns" {
    const wav: f32 = 3.21;
    const W = wave.SineSum(f32, 1){ .base = 100, .amp = .{50}, .phase = .{wav}, .inc = .{0.001}, .step = .multiply };
    const bx: i32 = 40;
    var it = W.sweep(0 - bx);
    for (0..400) |px| {
        const fsx: f32 = @floatFromInt(@as(i32, @intCast(px)) - bx);
        const base: f32 = 100.0 + 50.0 * @sin(wav + 0.001 * fsx);
        try expectEqual(@as(i32, @intFromFloat(base)), it.next());
    }
}

test "floor rounds negative values down" {
    const W = wave.SineSum(f64, 1){ .base = -0.5, .amp = .{0}, .phase = .{0}, .inc = .{0}, .rounding = .floor };
    var it = W.sweep(0);
    try expectEqual(@as(i32, -1), it.next());
}

test "NaN and out-of-range sums saturate instead of hitting @intFromFloat UB" {
    const huge = wave.SineSum(f64, 1){ .base = 3e9, .amp = .{0}, .phase = .{0}, .inc = .{0} };
    var a = huge.sweep(0);
    try expectEqual(@as(i32, 0x7FFF_FFFF), a.next());
    const nan = wave.SineSum(f32, 1){ .amp = .{1}, .phase = .{std.math.nan(f32)}, .inc = .{0} };
    var b = nan.sweep(0);
    try expectEqual(@as(i32, -0x8000_0000), b.next());
    // a saturated offset draws nothing and does not overflow
    const src_px = [_]u8{1};
    var buf = [_]u8{0};
    wave.siny(blit.Dst.buffer(&buf, 1), blit.Image.init(&src_px, 1), null, 0, 5, 1, &a, null, .copy);
    try expectEqual(@as(u8, 0), buf[0]);
}

test "accumulate ignores origin; f64 accumulates like the hand loop" {
    const W = wave.SineSum(f64, 1){ .amp = .{3}, .phase = .{0.25}, .inc = .{0.1} };
    var x = W.sweep(0);
    var y = W.sweep(1000);
    var p: f64 = 0.25;
    for (0..50) |_| {
        const want: i32 = @intFromFloat(3.0 * @sin(p));
        try expectEqual(want, x.next());
        try expectEqual(want, y.next());
        p += 0.1;
    }
}

const Fixed = struct {
    vals: []const i32,
    i: usize = 0,
    pub fn next(self: *Fixed) i32 {
        defer self.i += 1;
        return self.vals[self.i];
    }
};

test "siny draws each column group at its own offset, keyed and clipped" {
    // 4x2 source: columns 0-1 group A, 2-3 group B; pixel value 0 is the key
    const src_px = [_]u8{ 1, 2, 3, 0, 5, 6, 7, 8 };
    const src = blit.Image.init(&src_px, 4);
    var buf = [_]u8{9} ** (4 * 5);
    const dst = blit.Dst.buffer(&buf, 4);
    var offs = Fixed{ .vals = &.{ 0, 3 } };
    wave.siny(dst, src, null, 0, 1, 2, &offs, 0, .copy);
    // group A at y 1..2, group B at y 4..5 (row 5 clipped away)
    try expectEqual([_]u8{ 9, 9, 9, 9 }, buf[0..4].*);
    try expectEqual([_]u8{ 1, 2, 9, 9 }, buf[4..8].*);
    try expectEqual([_]u8{ 5, 6, 9, 9 }, buf[8..12].*);
    try expectEqual([_]u8{ 9, 9, 3, 9 }, buf[16..20].*); // 0 is keyed out
    try expectEqual(@as(usize, 2), offs.i);
}

test "siny with a partial last group and a flat ink" {
    const src_px = [_]u8{ 1, 1, 1, 1, 1 };
    const src = blit.Image.init(&src_px, 5);
    var buf = [_]u8{0} ** 5;
    var offs = Fixed{ .vals = &.{ 0, 0 } };
    wave.siny(blit.Dst.buffer(&buf, 5), src, null, 0, 0, 3, &offs, 0, .{ .flat = 4 });
    try expectEqual([_]u8{ 4, 4, 4, 4, 4 }, buf);
    try expectEqual(@as(usize, 2), offs.i);
}

test "siny of a sub-rectangle (one glyph of a font sheet), one column at a time" {
    // 6x2 sheet, glyph = columns 2..3 rows 0..1
    const sheet = [_]u8{ 7, 7, 1, 2, 7, 7, 7, 7, 3, 0, 7, 7 };
    const src = blit.Image.init(&sheet, 6);
    var buf = [_]u8{9} ** (3 * 3);
    var offs = Fixed{ .vals = &.{ 1, 0 } };
    wave.siny(blit.Dst.buffer(&buf, 3), src, .{ .x = 2, .y = 0, .w = 2, .h = 2 }, 1, 0, 1, &offs, 0, .copy);
    try expectEqual([_]u8{ 9, 9, 2 }, buf[0..3].*);
    try expectEqual([_]u8{ 9, 1, 9 }, buf[3..6].*); // row 1 of col 3 is the key
    try expectEqual([_]u8{ 9, 3, 9 }, buf[6..9].*);
    try expectEqual(@as(usize, 2), offs.i);
}
