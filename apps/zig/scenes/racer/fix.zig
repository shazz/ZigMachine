// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; his itch.io page states "Code license: MIT"): his physics runs on PICO-8's
// 16.16 numbers, so the port needs the same ones, bit for bit. Copyright (c) freds72, MIT (the
// licence text is at the head of frame.zig).
//
// RACER: PICO-8's 16.16 fixed point as raw i32 (value * 65536). The rules, which the Lua
// reference (z8lua, tools/racer/ref_harness.py) pins:
//   + - wrap; mul = (a*b) >> 16 through 64 bits, floor; div = a * 65536 / b truncating toward
//   zero, saturating to +-0x7fffffff (b = 0 included); % is the always-positive modulo;
//   sin/cos/atan2 are integer table functions (turns, 1.0 = a full turn, Y up like PICO-8's
//   `-sin`); sqrt (and `^0.5`) is floor(sqrt(x << 16)).
// The two tables are built at compile time: the cart never runs a float op. They are the
// rounded sin / atan values (the 4,097 + 2,049 entries the PICO-8 interpreter shows), and
// fix_test.zig pins the whole of sin, cos, atan2 and sqrt against z8lua by a CRC.
// No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ONE: i32 = 0x10000;
pub const MAX: i32 = 0x7fff_ffff;

/// A decimal literal the way the PICO-8 lexer reads it: truncated toward zero. Comptime only.
pub fn lit(comptime d: comptime_float) i32 {
    return @intFromFloat(d * 65536.0);
}

pub inline fn mul(a: i32, b: i32) i32 {
    return @truncate((@as(i64, a) * b) >> 16);
}

/// The same integer as trunc(a * 65536 / b) through 64 bits, saturated; in 32-bit divides (ZIGGY's divide unit; the
/// 64-bit divide is a libgcc call on rv32. Board optimisation: fix_test.zig compares it with the 64-bit formula).
pub fn div(a: i32, b: i32) i32 {
    if (b == ONE) return a;
    if (b == 0) return if (a >= 0) MAX else -MAX;
    if (a > -0x8000 and a < 0x8000) return @divTrunc(a << 16, b); // |a << 16| < 2^31: no overflow, |q| <= MAX
    const neg = (a < 0) != (b < 0);
    const q = udiv16(@abs(a), @abs(b)) orelse return if (neg) -MAX else MAX;
    return if (neg) -q else q;
}

/// floor(a * 2^16 / b) for b > 0, or null past MAX: long division, the high part then the 16 low bits in one, two or
/// sixteen steps as b leaves room in a word.
fn udiv16(a: u32, b: u32) ?i32 {
    const qh = a / b;
    if (qh >= 0x8000) return null; // q >= 2^31
    var r = a - qh * b;
    var lo: u32 = 0;
    if (b <= 0xFFFF) {
        lo = (r << 16) / b; // r < b < 2^16
    } else if (b <= 0xFF_FFFF) {
        const n1 = r << 8; // r < 2^24: two base-256 digits
        const d1 = n1 / b;
        r = n1 - d1 * b;
        lo = d1 << 8 | (r << 8) / b;
    } else {
        for (0..16) |_| { // r < b < 2^32 and r < 2^31 after the high part: r << 1 fits
            r <<= 1;
            lo <<= 1;
            if (r >= b) {
                r -= b;
                lo |= 1;
            }
        }
    }
    return @intCast(qh << 16 | lo);
}

pub fn abs(a: i32) i32 {
    if (a >= 0) return a;
    return if (a == std.math.minInt(i32)) MAX else -a;
}

pub fn mod(a: i32, b: i32) i32 {
    const m = abs(b);
    const r = if (m != 0) @rem(a, m) else 0;
    return if (r >= 0) r else r + m;
}

pub inline fn min(a: i32, b: i32) i32 {
    return if (a < b) a else b;
}

pub inline fn max(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}

/// PICO-8's mid: the median of three.
pub fn mid(x: i32, y: i32, z: i32) i32 {
    if (x > y) return if (y > z) y else min(x, z);
    return if (x > z) x else min(y, z);
}

pub fn floor(a: i32) i32 {
    return a & ~@as(i32, 0xffff);
}

pub fn lerp(a: i32, b: i32, t: i32) i32 {
    return mul(a, ONE - t) +% mul(b, t);
}

/// floor(sqrt(x << 16)), the PICO-8 abacus root. A negative input gives 0. Digit by digit, two bits of x a step, in
/// 32-bit words (board optimisation: the 64-bit abacus cost ~700 cycles on rv32; the remainder stays under 2^27):
/// the same floor root, pinned by fix_test.zig's CRC and a comparison with the 64-bit loop.
pub fn sqrt(a: i32) i32 {
    if (a <= 0) return 0;
    const ua: u32 = @intCast(a);
    var rem: u32 = 0;
    var root: u32 = 0;
    var i: u5 = 0;
    while (i < 24) : (i += 1) { // x = a << 16: bit pairs 47..16 are a's, the last eight pairs zero
        const pair: u32 = if (i < 16) (ua >> (30 - 2 * @as(u5, @intCast(i)))) & 3 else 0;
        rem = (rem << 2) | pair;
        root <<= 1;
        const t = (root << 1) | 1;
        if (rem >= t) {
            rem -= t;
            root |= 1;
        }
    }
    return @intCast(root);
}

const SIN_N = 4097;
const ATAN_N = 2049;

const SIN_T: [SIN_N]i32 = blk: {
    @setEvalBranchQuota(2_000_000);
    var t: [SIN_N]i32 = undefined;
    for (&t, 0..) |*e, i| {
        const a = @as(f64, @floatFromInt(i)) * (2.0 * std.math.pi / 16384.0);
        e.* = @as(i32, @intFromFloat(@round(@sin(a) * 65536.0))) - 16 * @as(i32, @intCast(i));
    }
    break :blk t;
};

const ATAN_T: [ATAN_N]i32 = blk: {
    @setEvalBranchQuota(2_000_000);
    var t: [ATAN_N]i32 = undefined;
    for (&t, 0..) |*e, i| {
        const q = @as(f64, @floatFromInt(i * 32)) / 65536.0;
        e.* = @intFromFloat(@round(std.math.atan(q) / (2.0 * std.math.pi) * 65536.0));
    }
    break :blk t;
};

fn sinHelper(x: i32) i32 {
    const r = if (x & 0x4000 != 0) ~x else x;
    const a: u32 = @intCast((r & 0x3fff) + 2);
    const ret = @as(i32, @intCast((a >> 2) << 4)) + SIN_T[a >> 2];
    return if (x & 0x8000 != 0) ret else -ret;
}

/// PICO-8 sin: the angle is in turns (a full turn = 1.0) and the result is `-sin(2 pi x)`.
pub fn sin(x: i32) i32 {
    return sinHelper(x);
}

pub fn cos(x: i32) i32 {
    return sinHelper(x -% 0x4000);
}

/// PICO-8 atan2(dx, dy), in turns.
pub fn atan2(x: i32, y: i32) i32 {
    var bits: i32 = 0x4000;
    if (x != 0) {
        const ay: i64 = @intCast(@abs(@as(i64, y)));
        const ax: i64 = @intCast(@abs(@as(i64, x)));
        const q = @divTrunc(ay << 16, ax);
        if (q > 0x10000) {
            bits -= ATAN_T[@intCast(@divTrunc(@as(i64, 1) << 32, q) >> 5)];
        } else bits = ATAN_T[@intCast(q >> 5)];
    }
    if (x < 0) bits = 0x8000 - bits;
    if (y > 0) bits = -bits & 0xffff;
    // a PICO-8 quirk, e.g. atan2(1, 0x8000)
    if (x != 0 and y == std.math.minInt(i32)) bits = -bits & 0xffff;
    return bits;
}
