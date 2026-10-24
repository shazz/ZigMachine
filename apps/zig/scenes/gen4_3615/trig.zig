// --------------------------------------------------------------------------
// Sine and cosine of a u32 angle (2^32 = one turn) in Q30, for the frame's
// moving parts (the FATE logo, the floor's sway, the motif's bounce): no
// float per frame on ZIGGY. A 1024-entry table, built at compile time, gives
// the angle's top 10 bits; the rest (under 2 PI / 1024 = 6.2e-3 rad) is
// turned by its Taylor series. Error under 2^-28 (fate_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

const ONE: i64 = 1 << 32;

/// A rotor (cos, sin) in Q30.
pub const R30 = struct { c: i32, s: i32 };

/// cos and sin of a: the table's angle (a >> 22) turned by the rest, whose
/// sine and cosine (under 2 PI / 1024 = 6.2e-3 rad) are their Taylor series.
pub fn sincos(a: u32) R30 {
    const t = COARSE[a >> 22];
    const lo: i64 = @intCast(((@as(u64, a) & 0x3F_FFFF) * TWO_PI_Q30) >> 30); // radians, Q32
    const lo2 = (lo * lo) >> 32;
    const cl = ONE - (lo2 >> 1); // + lo^4/24 < 6e-11
    const sl = lo - @divTrunc((lo2 * lo) >> 32, 6); // + lo^5/120 < 8e-14
    const tc: i64 = t.c;
    const ts: i64 = t.s;
    return .{ .c = @intCast((tc * cl - ts * sl) >> 32), .s = @intCast((ts * cl + tc * sl) >> 32) };
}
const TWO_PI_Q30: u64 = @intFromFloat(@round(2 * std.math.pi * (1 << 30)));
const COARSE: [1024]R30 = blk: {
    @setEvalBranchQuota(100000);
    var t: [1024]R30 = undefined;
    for (&t, 0..) |*r, k| {
        const x = 2 * std.math.pi * @as(f64, @floatFromInt(k)) / 1024;
        r.* = .{ .c = q30(@cos(x)), .s = q30(@sin(x)) };
    }
    break :blk t;
};

/// The u32 angle nearest to a u64 phase (2^64 = one turn). Rounded, not cut:
/// a phase a few units under a whole turn is angle 0, whose cosine is exactly 1,
/// as the JS's doubles land there (the floor's sway peaks at 800, not 799).
pub fn angle(p: u64) u32 {
    return @intCast((p +% (1 << 31)) >> 32);
}

/// A u64 phase step (2^64 = one turn) for `rad` radians a frame.
pub fn phase(comptime rad: f64) u64 {
    return @intFromFloat(@round(rad / (2 * std.math.pi) * 18446744073709551616.0));
}

fn q30(v: f64) i32 {
    return @intFromFloat(@round(v * (1 << 30)));
}
