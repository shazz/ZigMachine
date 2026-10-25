// wave_sin.rounded against an f64 sine: it is round(10 sin p) wherever 10 sin p is further
// than the table's error (2e-6 * 10, rounded up to 1e-4) from a half-integer, and never more
// than half a step plus that error off anywhere -- over a sample of every angle, and over the
// phases scroller.zig's accumulators take in two hours of frames.
const std = @import("std");
const ws = @import("wave_sin.zig");
const fixsin = @import("fixsin.zig");

const MARGIN: f64 = 1e-4;

fn check(p: u32, near: *usize) !void {
    const got = ws.rounded(p);
    const v = 10.0 * @sin(@as(f64, @floatFromInt(p)) / 4294967296.0 * 2.0 * std.math.pi);
    if (@abs(v - (@floor(v) + 0.5)) <= MARGIN) {
        near.* += 1;
        try std.testing.expect(@abs(@as(f64, @floatFromInt(got)) - v) <= 0.5 + MARGIN);
        return;
    }
    try std.testing.expectEqual(@as(i32, @intFromFloat(@round(v))), got);
}

test "rounded is round(10 sin p) away from the half-integers" {
    var near: usize = 0;
    var p: u32 = 0;
    for (0..4_000_000) |_| {
        try check(p, &near);
        p +%= 1073; // odd: every table interval at many fractions
    }
    try std.testing.expect(near * 100 < 4_000_000); // the uncertain band is thin
}

test "the scroller's own phases" {
    var near: usize = 0;
    const D = fixsin.rad(0.03);
    var wave_v: u32 = 0;
    for (0..432_000) |frame| { // two hours at 60 Hz
        if (frame % 7 == 0) {
            var p = wave_v;
            for (0..134) |_| {
                try check(p, &near);
                p +%= D;
            }
        }
        wave_v -%= D;
    }
}

test "the extremes and the zeros" {
    try std.testing.expectEqual(@as(i32, 0), ws.rounded(0));
    try std.testing.expectEqual(@as(i32, 10), ws.rounded(1 << 30));
    try std.testing.expectEqual(@as(i32, -10), ws.rounded(3 << 30));
    try std.testing.expectEqual(@as(i32, 0), ws.rounded(1 << 31));
}
