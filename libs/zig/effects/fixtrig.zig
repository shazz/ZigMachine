// --------------------------------------------------------------------------
// Fixed-point trigonometry for the cart CPU, the way an ST coder did it: a
// sine TABLE and an integer angle, no float anywhere at run time.
//
// The cart CPU on the board (VexRiscv rv32im) has no FPU, so every @sin of a
// CODEF port is a soft-float libm call costing thousands of cycles; this costs
// two loads, a multiply and a shift.
//
//   Angle   u32, one full turn = 2^32, so an accumulator wraps exactly where
//           2*pi does and never drifts out of range (a float phase does both).
//   sin/cos Q16.16 (65536 = 1.0), linearly interpolated between the 1024
//           entries of a one-turn table: worst error 1.7 LSB = 2.6e-5
//           (table rounding + interpolation, fixtrig_test.zig), far under
//           what a screen pixel can show.
//
// The table is built at COMPILE time: its values are rounded to integers, so
// the compiler's float functions (not the machine's) cannot leak into a
// result, and the cart pays 4 KB of data for it and no init code.
//
// No ZigOS import: it tests natively (fixtrig_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const ONE: i32 = 1 << 16;
pub const Angle = u32;

const BITS = 10; // 1024 entries a turn
const N = 1 << BITS;
const FRAC = 32 - BITS; // angle bits below the table index

const TABLE: [N + 1]i32 = blk: {
    @setEvalBranchQuota(N * 200);
    var t: [N + 1]i32 = undefined;
    for (&t, 0..) |*v, i| {
        const a = @as(f64, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f64, N));
        v.* = @intFromFloat(@round(@sin(a) * 65536.0));
    }
    // exact at the quarters, so sin(0) = 0 and cos(0) = 1.0 bit for bit
    t[0] = 0;
    t[N / 4] = ONE;
    t[N / 2] = 0;
    t[3 * N / 4] = -ONE;
    t[N] = 0;
    break :blk t;
};

/// A compile-time angle in radians, as an Angle (negative ones wrap).
pub fn angle(comptime rad: f64) Angle {
    const turns = rad / (2.0 * std.math.pi);
    const raw: i64 = @intFromFloat(@round(turns * 4294967296.0));
    return @truncate(@as(u64, @bitCast(raw)));
}

/// sin(a), Q16.16.
pub fn sin(a: Angle) i32 {
    const i = a >> FRAC;
    const f: i32 = @intCast((a >> (FRAC - 16)) & 0xFFFF);
    const s0 = TABLE[i];
    return s0 + ((TABLE[i + 1] - s0) * f >> 16);
}

/// cos(a), Q16.16.
pub fn cos(a: Angle) i32 {
    return sin(a +% (1 << 30));
}

/// a * b for two Q16.16 values, through a 64-bit product (mul + mulh on rv32im).
pub fn mul(a: i32, b: i32) i32 {
    return @truncate((@as(i64, a) * b) >> 16);
}
