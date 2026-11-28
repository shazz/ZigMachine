// --------------------------------------------------------------------------
// RACER: the integer maths of the renderer. Q16.16 everywhere (freds72's PICO-8 numbers are
// 16.16 too), no float at run time.
//
//   mulsh16  (a * b) >> 16 through a 64-bit product: ONE custom-0 instruction on the board when
//            the cart image is built ZM_ZMX=1 (the ROM's zmMulsh16 import), the plain twin
//            below everywhere else and in the native tests: the same integer on every host.
//            `use_zmx` is the A/B knob of the debug HUD (same pixels, other cost); `use_f32` moves the
//            vertex transform to the FPU (xform.zig) to measure what mulsh saves.
//   rcp      2^32 / d without a divide (libs/zig/zmx.zig's table + one Newton step, copied: a
//            cart cannot import libs/ files, and the table is 512 bytes).
//   sin/cos  a 1024-entry table built at compile time, u32 angles (a turn = 2^32), Q16.
// No ZigOS import: the native tests run it.
// --------------------------------------------------------------------------
const std = @import("std");
const builtin = @import("builtin");

pub const ONE: i32 = 1 << 16;
extern fn zmMulsh16(a: i32, b: i32) i32;

/// The knob: the instruction (true) or its twin. On a host without the ROM import only the twin exists.
pub var use_zmx: bool = true;
/// The other A/B: the vertex transform in f32 (the plan's "FPU loses here" check). Slightly different pixels.
pub var use_f32: bool = false;

pub inline fn mulsh16(a: i32, b: i32) i32 {
    if (comptime builtin.cpu.arch == .wasm32) {
        if (use_zmx) return zmMulsh16(a, b);
    }
    return @truncate((@as(i64, a) * b) >> 16);
}

/// mulsh16 with the knob read once by the caller (board optimisation: `use_zmx` is a global, reloaded at each of a
/// vertex's fifteen multiplies; xform.get reads it once). The same integer either way.
pub inline fn mulshK(zmx: bool, a: i32, b: i32) i32 {
    if (comptime builtin.cpu.arch == .wasm32) {
        if (zmx) return zmMulsh16(a, b);
    }
    return @truncate((@as(i64, a) * b) >> 16);
}

/// @clz of a non-zero word in five compares (board optimisation: rv32im has no clz, so @clz is a libgcc call, one a
/// vertex through rcp). The same count; fix_test.zig compares it with @clz.
pub inline fn clz32(x: u32) u5 {
    var v = x;
    var n: u32 = 0;
    if (v <= 0x0000_FFFF) {
        n += 16;
        v <<= 16;
    }
    if (v <= 0x00FF_FFFF) {
        n += 8;
        v <<= 8;
    }
    if (v <= 0x0FFF_FFFF) {
        n += 4;
        v <<= 4;
    }
    if (v <= 0x3FFF_FFFF) {
        n += 2;
        v <<= 2;
    }
    if (v <= 0x7FFF_FFFF) n += 1;
    return @intCast(n);
}

/// rcp with the knob read once (mulshK).
pub inline fn rcpK(zmx: bool, d: u32) u32 {
    if (d < 2) return 0xFFFF_FFFF;
    const n: u5 = clz32(d);
    const m = d << n;
    const y0: i32 = RCP[(m >> 23) & 255];
    const t = mulshK(zmx, @intCast(m >> 15), y0);
    const y1: u32 = @intCast(mulshK(zmx, y0, (2 << 16) - t));
    const r = (@as(u64, y1) << (@as(u6, n) + 1)) >> 16;
    return @intCast(@min(r, 0xFFFF_FFFF));
}

const RCP: [256]u16 = blk: {
    var t: [256]u16 = undefined;
    for (&t, 0..) |*e, i| {
        const den = 512 + 2 * i + 1;
        e.* = @intCast((2 * (1 << 25) + den) / (2 * den));
    }
    break :blk t;
};

/// ~2^32 / d for d >= 2 (the Q16 of 1 / z when d is a Q16 z), 14+ bits good.
pub fn rcp(d: u32) u32 {
    return rcpK(use_zmx, d);
}

const N = 1024;
const TABLE: [N + 1]i32 = blk: {
    @setEvalBranchQuota(N * 200);
    var t: [N + 1]i32 = undefined;
    for (&t, 0..) |*v, i| {
        const a = @as(f64, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f64, N));
        v.* = @intFromFloat(@round(@sin(a) * 65536.0));
    }
    t[0] = 0;
    t[N / 4] = ONE;
    t[N / 2] = 0;
    t[3 * N / 4] = -ONE;
    t[N] = 0;
    break :blk t;
};

/// sin of a u32 angle (a turn = 2^32), Q16, interpolated between table entries.
pub fn sin(a: u32) i32 {
    const i = a >> 22;
    const f: i32 = @intCast((a >> 6) & 0xFFFF);
    const s0 = TABLE[i];
    return s0 + (((TABLE[i + 1] - s0) * f) >> 16);
}

pub fn cos(a: u32) i32 {
    return sin(a +% (1 << 30));
}
