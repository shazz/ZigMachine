// wave_sin.fast against an f64 sine: whenever it answers, its integer is round(10 sin p)
// with 10 sin p further than 2e-6 from a half-integer -- more than libm_f32's 1.1 ulp plus
// the f32 product's rounding -- so the f32 sum the cart would compute (libm sine, 10 *, @round)
// rounds to the same integer. Over a sample of every f32 in its range, and over the phases
// scroller.zig's accumulators take in two hours of frames.
const std = @import("std");
const ws = @import("wave_sin.zig");

const LIBM_AND_PRODUCT: f64 = 2e-6; // 10 * (1.1 ulp of a sine <= 1) + half an ulp of 10, rounded up

fn check(p: f32, declined: *usize) !void {
    const got = ws.fast(p) orelse {
        declined.* += 1;
        return;
    };
    const v = 10.0 * @sin(@as(f64, p));
    const half = @floor(v) + 0.5;
    try std.testing.expect(@abs(v - half) > LIBM_AND_PRODUCT);
    try std.testing.expectEqual(@as(i32, @intFromFloat(@round(v))), got);
}

test "fast answers only where the f32 sum cannot round the other way" {
    var declined: usize = 0;
    var n: usize = 0;
    // Every 61st f32 from 2^-12 to 2^20, both signs.
    var bits: u32 = 0x39800000;
    while (bits < 0x49800000) : (bits += 61) {
        const p: f32 = @bitCast(bits);
        try check(p, &declined);
        try check(-p, &declined);
        n += 2;
    }
    try std.testing.expect(declined * 100 < n); // the fast path answers almost always
}

test "the scroller's own phases" {
    var declined: usize = 0;
    var wave_v: f32 = 0;
    for (0..432_000) |frame| { // two hours at 60 Hz
        if (frame % 7 == 0) { // a sample of the frames, every column group
            var p = wave_v;
            for (0..134) |_| {
                try check(p, &declined);
                p += 0.03;
            }
        }
        wave_v += -0.03;
    }
}

test "out of range and NaN go to the f32 sum" {
    try std.testing.expectEqual(@as(?i32, null), ws.fast(0.0));
    try std.testing.expectEqual(@as(?i32, null), ws.fast(1e-5));
    try std.testing.expectEqual(@as(?i32, null), ws.fast(3e6));
    try std.testing.expectEqual(@as(?i32, null), ws.fast(std.math.nan(f32)));
    try std.testing.expectEqual(ws.slow(1e-5), ws.rounded(1e-5));
}
