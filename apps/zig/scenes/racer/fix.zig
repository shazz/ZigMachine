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

pub fn div(a: i32, b: i32) i32 {
    if (b == ONE) return a;
    if (b != 0) {
        const r = @divTrunc(@as(i64, a) * 65536, b);
        if (r <= MAX and r >= -MAX) return @intCast(r);
    }
    return if ((a ^ b) >= 0) MAX else -MAX;
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

/// floor(sqrt(x << 16)), the PICO-8 abacus root. A negative input gives 0.
pub fn sqrt(a: i32) i32 {
    var x: i64 = @as(i64, a) << 16;
    var root: i64 = 0;
    if (x <= 0) return 0;
    var bit: i64 = 1 << 46;
    while (bit != 0) : ({
        bit >>= 2;
        root >>= 1;
    }) {
        if (x >= bit + root) {
            x -= bit + root;
            root += bit << 1;
        }
    }
    return @truncate(root);
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
