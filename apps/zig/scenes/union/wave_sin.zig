// --------------------------------------------------------------------------
// Union scrolltext -- the wave's rounded sine, without the sine (most of the time).
//
// scroller.zig's FX.siny needs round(0 + 10 * sin(p)) for 134 column groups a frame,
// the f32 libm sine and @round of zg.wave.SineSum: ~400 cycles a group on the board,
// a twentieth of a megacycle a frame for 134 small integers. The answer only depends
// on which side of a half-integer 10 sin(p) falls, so it is first worked out with
// integers: p / 2pi in 32-bit turns (the f32's mantissa times 2^64 / 2pi), then a
// 4096-step sine table, linear between steps. That is within 2e-6 of sin(p); libm's
// sine is within 1.1 ulp (libm_f32_test.zig) and 10 * it rounds once more, so where
// the table puts 10 sin(p) more than MARGIN from every half-integer, the f32 sum
// rounds to the same integer. Nearer than that, or for |p| outside 2^-12 .. 2^20
// (where libm's bound is measured), the f32 sum itself is computed: the result is
// always the f32 one (wave_sin_test.zig holds the two against an f64 sine).
// --------------------------------------------------------------------------
const std = @import("std");

pub const AMP: f32 = 10.0;
const STEPS_LOG2 = 12;
const STEPS = 1 << STEPS_LOG2;
const ONE: i64 = 1 << 30; // Q30
/// Distance from a half-integer (in units of 10 sin) under which the f32 sum is computed.
pub const MARGIN: f64 = 1e-4;
const MARGIN_Q: i64 = @intFromFloat(MARGIN * @as(f64, ONE));

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

// 2^64 / (2 pi), split in 32-bit halves.
const INV_2PI: u64 = @intFromFloat(18446744073709551616.0 / (2.0 * std.math.pi));
const K_HI: u64 = INV_2PI >> 32;
const K_LO: u64 = INV_2PI & 0xFFFF_FFFF;

/// What zg.wave.SineSum(f32, 1) (base 0, amp AMP, .round) yields at phase `p`.
pub fn rounded(p: f32) i32 {
    return fast(p) orelse slow(p);
}

/// The f32 sum, as SineSum computes it.
pub fn slow(p: f32) i32 {
    var v: f32 = 0;
    v += AMP * @sin(p);
    return @intFromFloat(@round(v));
}

/// The integer answer, or null when it is not certain (near a half-integer, or |p| out of range).
pub fn fast(p: f32) ?i32 {
    const bits: u32 = @bitCast(p);
    const e: i32 = @as(i32, @intCast((bits >> 23) & 0xFF)) - 127;
    if (e < -12 or e > 19) return null; // tiny, huge, NaN and inf: libm's bound is not measured there
    const m: u64 = (bits & 0x7F_FFFF) | 0x80_0000;
    // |p| / 2pi = m * 2^(e-23) * INV_2PI / 2^64: its fraction in Q32 is bits 55-e .. 87-e of
    // m * INV_2PI = hi * 2^32 + lo, i.e. bits 23-e .. 55-e of hi (55 - e >= 36 here).
    const hi = m * K_HI + ((m * K_LO) >> 32);
    const turns: u32 = @truncate(hi >> @intCast(23 - e));
    const i = turns >> (32 - STEPS_LOG2);
    const fr: i32 = @intCast((turns >> (32 - STEPS_LOG2 - 10)) & 0x3FF);
    var s: i64 = TABLE[i] + @divFloor((TABLE[i + 1] - TABLE[i]) * fr, 1024);
    if (bits >> 31 != 0) s = -s;
    const v = 10 * s; // 10 sin(p), Q30
    const below = v >> 30; // floor
    const frac = v - below * ONE; // 0 .. ONE-1
    if (@abs(frac - ONE / 2) <= MARGIN_Q) return null;
    return @intCast(if (frac > ONE / 2) below + 1 else below);
}

comptime {
    if (AMP != 10.0) @compileError("wave_sin: fast() multiplies by 10");
}
