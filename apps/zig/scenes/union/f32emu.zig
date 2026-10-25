// --------------------------------------------------------------------------
// Union intro -- the f32 accumulators the CODEF port kept (scroll position, frame
// counters, fades), stepped with integers and rounded exactly as an f32 would be.
//
// A value is a non-negative f32 held in fixed point, units of 2^-40 (every f32 the
// counters take, from 2^-17 to 2^23, is exact there). add() and mul() round their
// exact result to the f32 grid at its magnitude (24 significant bits, ties to even),
// so a counter steps through the very values the f32 code produced: no float runs a
// frame on ZIGGY (2026-10-25) and the screen keeps the f32 version's timing to the bit.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Value = u64;
pub const FRAC_BITS = 40;
pub const ONE: Value = 1 << FRAC_BITS;

/// An f32 constant as a Value (compile time; it must be >= 2^-17, or 0).
pub fn of(comptime f: f32) Value {
    if (f < 0) @compileError("f32emu: values are non-negative");
    const v = @as(f64, f) * @as(f64, ONE);
    if (v != @floor(v)) @compileError("f32emu: the constant is finer than 2^-40");
    return @intFromFloat(v);
}

/// The f32 nearest to the exact `s` (units 2^-40), ties to even: round to 24 significant bits.
fn round(s: u64) Value {
    if (s == 0) return 0;
    const msb: u6 = @intCast(63 - @clz(s));
    if (msb < 24) return s; // already 24 bits or fewer
    const drop: u6 = msb - 23;
    const spacing: u64 = @as(u64, 1) << drop;
    const half = spacing >> 1;
    const r = s & (spacing - 1);
    var t = s - r;
    if (r > half or (r == half and (t >> drop) & 1 == 1)) t += spacing;
    return t;
}

/// fl(x + d) (d a signed or unsigned integer in Value units), clamped at 0 (the callers' @max(0, ...)).
pub fn add(x: Value, d: anytype) Value {
    const s: i64 = @as(i64, @intCast(x)) + @as(i64, @intCast(d));
    return if (s <= 0) 0 else round(@intCast(s));
}

/// fl(x - y) for x >= y (Sterbenz: exact when y <= x <= 2y, rounded otherwise).
pub fn sub(x: Value, y: Value) Value {
    return round(x - y);
}

/// fl(x * k) for a whole k < 256 and x < 2^16 (as an f32).
pub fn mul(x: Value, k: u32) Value {
    return round(x * k); // x < 2^56 (an f32 under 2^16), k < 2^8: no overflow
}

/// fl(x + d) for a signed value (sign and magnitude: f32 rounding is symmetric).
pub fn sadd(x: i64, d: i64) i64 {
    const s = x + d;
    return if (s >= 0) @intCast(round(@intCast(s))) else -@as(i64, @intCast(round(@intCast(-s))));
}

/// 2 pi in Value units (the true 2 pi, as the sine sees it).
pub const TWO_PI: i64 = @intFromFloat(@round(2.0 * std.math.pi * @as(f64, ONE)));
const TURN_M: u64 = @intFromFloat(@round(@as(f64, 1 << 32) * (1 << 11) * (1 << 29) / @as(f64, TWO_PI)));

/// An angle r in [0, TWO_PI) as a fixsin.zig angle (u32 turns).
pub fn turns(r: i64) u32 {
    return @truncate(((@as(u64, @intCast(r)) >> 11) * TURN_M) >> 29);
}

/// A non-negative value's angle (mod 2 pi) as a fixsin.zig angle.
pub fn angle(x: Value) u32 {
    var r: i64 = @intCast(x);
    while (r >= TWO_PI) r -= TWO_PI;
    return turns(r);
}

/// @intFromFloat (truncation) of a value.
pub fn int(x: Value) u64 {
    return x >> FRAC_BITS;
}

test "add and mul round as f32 does" {
    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    const steps = [_]f32{ 0.3, 0.6, 1.0 / 30.0, 0.005, 0.02, 17.0 * 0.08, 1.5 };
    inline for (steps) |st| {
        var f: f32 = 0;
        var v: Value = 0;
        for (0..5000) |_| {
            f += st;
            v = add(v, of(st));
            try std.testing.expectEqual(@as(f64, f) * @as(f64, ONE), @as(f64, @floatFromInt(v)));
            const k = rnd.intRangeAtMost(u32, 1, 255);
            try std.testing.expectEqual(@as(u64, @intFromFloat(f * @as(f32, @floatFromInt(k)))), int(mul(v, k)));
        }
        while (f > 0) {
            f = @max(0.0, f - st);
            v = add(v, -@as(i64, @intCast(of(st))));
            try std.testing.expectEqual(@as(f64, f) * @as(f64, ONE), @as(f64, @floatFromInt(v)));
        }
    }
}
