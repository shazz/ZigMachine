// --------------------------------------------------------------------------
// High-precision integer trig for carts whose pinned output came from float
// maths: zig3d_fixed's Q30 sine (within a few 2^-30) instead of fixtrig's
// Q16 (2.6e-5), so rounding a result to a pixel agrees with the float original.
// A value that lands within MARGIN of a rounding tie is reported as null: the
// caller re-evaluates it with the original float expression (rare).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const m = zg.zig3d_fixed.math;

/// A u64 phase (one turn = 2^64) as the u32 angle sinCos takes (rounded).
pub fn top(p: u64) u32 {
    return @truncate((p +% (1 << 31)) >> 32);
}

pub fn sinQ(a: u32) i32 {
    return m.sinCos(a).s;
}
pub fn cosQ(a: u32) i32 {
    return m.sinCos(a).c;
}

/// Radians of a phase, for the float fallback only.
pub fn rad(p: u64) f64 {
    return @as(f64, @floatFromInt(p)) * (2.0 * std.math.pi / 18446744073709551616.0);
}

/// A comptime phase (u64 turns) of `r` radians, any sign.
pub fn phase(comptime r: f64) u64 {
    const t = r / (2.0 * std.math.pi);
    const x = (t - @floor(t)) * 18446744073709551616.0;
    return @intFromFloat(@min(@round(x), 18446744073709549568.0));
}

const MARGIN: i64 = 1 << 15; // 3e-5 of a pixel: well over the sine's error times any amplitude here

/// floor(v + 0.5) for a Q`frac` value (JS Math.round), or null within MARGIN of a tie.
pub fn roundQ(v: i64, comptime frac: u6) ?i32 {
    const one: i64 = @as(i64, 1) << frac;
    const w = v + (one >> 1);
    const r = w & (one - 1);
    const margin = (MARGIN << frac) >> 30;
    if (r < margin or r > one - margin) return null;
    return @intCast(w >> frac);
}

// 2^64 / 2pi, so mantissa * C >> shift is the angle in u32 turns.
const C: u64 = @intFromFloat(@round(4294967296.0 * 4294967296.0 / (2.0 * std.math.pi)) );

/// A non-negative f32 radian argument as a u32 angle (its exact value, reduced mod 2pi).
pub fn f32Angle(x: f32) u32 {
    const bits: u32 = @bitCast(x);
    const e: i32 = @intCast((bits >> 23) & 0xff);
    if (e == 0) return 0;
    const man: u128 = (bits & 0x7fffff) | 0x800000;
    const prod = man * C; // = value * 2^(150 - e) * 2^32/2pi * 2^32 ... see shift
    const s = 182 - e; // angle = prod >> s
    const a: u32 = if (s <= 0) @truncate(prod << @intCast(-s)) else @truncate((prod + (@as(u128, 1) << @intCast(s - 1))) >> @intCast(s));
    return if (bits >> 31 != 0) 0 -% a else a;
}

/// Q30 cosine/sine to f32, exactly (a power-of-two scale).
pub fn toF32(q: i32) f32 {
    return @as(f32, @floatFromInt(q)) * (1.0 / 1073741824.0);
}
