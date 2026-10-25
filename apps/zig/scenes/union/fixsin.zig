// --------------------------------------------------------------------------
// Union main -- the sine the main screen runs on: integers only.
//
// An angle is a u32 of turns (2^32 = 2 pi, so it wraps for free, as the
// accumulators' @mod 2 pi did); sin() reads a 4096-step Q30 table built at
// compile time from the f64 sine and interpolates linearly between steps:
// within 2e-6 of the true sine. Used by the dragonballs (rotation, bounce,
// squash) and the scrolltext's wave; no float runs per frame on ZIGGY.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ONE: i32 = 1 << 30; // Q30
const STEPS_LOG2 = 12;
const STEPS = 1 << STEPS_LOG2;

/// sin(2 pi i / STEPS) in Q30, i = 0 .. STEPS (the last one closes the interpolation).
const TABLE: [STEPS + 1]i32 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [STEPS + 1]i32 = undefined;
    for (&t, 0..) |*v, i| {
        const a = 2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / STEPS;
        v.* = @intFromFloat(@round(@sin(a) * @as(f64, ONE)));
    }
    break :blk t;
};

/// `r` radians as an angle (compile time: the constants of the f32 code it replaces).
pub fn rad(comptime r: comptime_float) u32 {
    const turns = r / (2.0 * std.math.pi);
    const frac = turns - @floor(turns);
    const v: u64 = @intFromFloat(@round(frac * 4294967296.0));
    return @truncate(v); // 2^32 (a frac that rounds up) is angle 0
}

/// sin(a) in Q30.
pub fn sin(a: u32) i32 {
    const i = a >> (32 - STEPS_LOG2);
    const fr: i32 = @intCast((a >> (32 - STEPS_LOG2 - 10)) & 0x3FF);
    return TABLE[i] + @divFloor((TABLE[i + 1] - TABLE[i]) * fr, 1024);
}

/// cos(a) in Q30.
pub fn cos(a: u32) i32 {
    return sin(a +% (1 << 30));
}

test "sin and cos within 2e-6 of f64" {
    var a: u32 = 0;
    for (0..1 << 20) |_| {
        const x = @as(f64, @floatFromInt(a)) / 4294967296.0 * 2.0 * std.math.pi;
        const s = @as(f64, @floatFromInt(sin(a))) / ONE;
        const c = @as(f64, @floatFromInt(cos(a))) / ONE;
        try std.testing.expect(@abs(s - @sin(x)) < 2e-6);
        try std.testing.expect(@abs(c - @cos(x)) < 2e-6);
        a +%= 4099; // odd step: every table interval, many fractions
    }
    try std.testing.expectEqual(rad(0.0), 0);
    try std.testing.expectEqual(rad(std.math.pi), 1 << 31);
}
