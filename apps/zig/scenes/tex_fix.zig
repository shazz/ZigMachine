// TEX's maths in integers. The screen follows screen.js's doubles; the board has no
// f64, so the phases are u64 turns (2^64 = one revolution: no drift at any run
// length, like the JS doubles) and sin/cos are a Q30 Taylor series (error ~1e-9),
// so every rounded canvas coordinate lands where the double version's did.
const std = @import("std");

pub const ONE: i64 = 1 << 30;
// 2^30 / n: the board has no divider, so the Taylor terms multiply
const R156: i64 = 6882960;
const R110: i64 = 9761289;
const R72: i64 = 14913081;
const R42: i64 = 25565282;
const R20: i64 = 53687091;
const R6: i64 = 178956971;
const PIO2_Q30: i64 = 1686629713; // round(pi/2 * 2^30)

fn mulq(a: i64, b: i64) i64 {
    return (a * b) >> 30;
}

/// sin of an angle in u32 turns (2^32 = 2 pi), Q30.
pub fn sin(a: u32) i64 {
    const q = a >> 30;
    var r: i64 = a & 0x3FFFFFFF;
    if (q & 1 != 0) r = ONE - r;
    const x = mulq(r, PIO2_Q30);
    const x2 = mulq(x, x);
    // x(1 - x2/6(1 - x2/20(1 - x2/42(1 - x2/72(1 - x2/110(1 - x2/156))))))
    var t: i64 = ONE - mulq(x2, R156);
    t = ONE - mulq(mulq(x2, t), R110);
    t = ONE - mulq(mulq(x2, t), R72);
    t = ONE - mulq(mulq(x2, t), R42);
    t = ONE - mulq(mulq(x2, t), R20);
    t = ONE - mulq(mulq(x2, t), R6);
    const s = mulq(x, t);
    return if (q >= 2) -s else s;
}

pub fn cos(a: u32) i64 {
    return sin(a +% (1 << 30));
}

/// radians -> u64 turns, at comptime (a constant, not per-frame float).
pub fn turns(comptime rad: comptime_float) u64 {
    const t: comptime_float = rad / (2.0 * std.math.pi);
    return @intFromFloat(t * 18446744073709551616.0);
}

pub fn hi(a: u64) u32 {
    return @truncate(a >> 32);
}

/// Math.round(c + k*v) for integer c, k and v in Q30: floor(x + 1/2).
pub fn roundQ30(c: i64, k: i64, v: i64) i32 {
    return @intCast((((c << 30) + k * v) + (ONE >> 1)) >> 30);
}
