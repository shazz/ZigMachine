// --------------------------------------------------------------------------
// Blitter demo — RUBBER's per-row X offset, the ST way: a sine table in fixed
// point instead of a soft-float sinf() per row (ZIGGY has no FPU; ~200 sinf a
// frame were most of the effect's CPU time).
//
// The pixels must not move, and they are defined by the f32 formula kept here
// as dxF32 (the twin):  dx = trunc(14 * sinf(fl(fl(y * 0.11) + wob))).
// So the angle is still that f32 sum (one soft add a row, the row term from a
// table); only the sine changes. The angle's exact bits become a phase in
// turns (Q32, integer maths), a 2048-step table interpolated in Q16.16 gives
// 14*sin to better than 1/30000 px, and the integer part is taken from it —
// unless the value lies within 1/2000 px of an integer, where the table's error
// could decide the truncation: those rows (well under 1 %) ask dxF32 itself.
// The tests compare the two over 10 minutes of frames plus random angles (a
// one-off ReleaseFast run of 2.16M frames = 10 hours: 432M rows equal, 0.6 %
// of them through the fallback).
// std only: `zig test` runs it natively (build.sh NATIVE_TESTS).
// --------------------------------------------------------------------------
const std = @import("std");

pub const AMP: f32 = 14.0;
pub const FREQ: f32 = 0.11;
pub const ROWS = 200;

const TBITS = 11;
const TN = 1 << TBITS;
const EPS: u32 = 32; // Q16.16 guard band around each integer (~0.0005 px)
const INV_2PI_Q64: u128 = 2935890503282001226; // floor(2^64 / 2pi)

// AMP * sin(2pi i / TN) in Q16.16, one extra entry so i + 1 never wraps.
const SIN: [TN + 1]i32 = blk: {
    @setEvalBranchQuota(100000);
    var t: [TN + 1]i32 = undefined;
    for (&t, 0..) |*v, i| {
        const a = @as(f64, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f64, TN));
        v.* = @intFromFloat(@round(@sin(a) * @as(f64, AMP) * 65536.0));
    }
    break :blk t;
};

// The original per-row formula: the reference, and the fallback near an integer.
pub fn dxF32(y: i32, wob: f32) i16 {
    return @intFromFloat(AMP * @sin(@as(f32, @floatFromInt(y)) * FREQ + wob));
}

pub const Wobble = struct {
    row: [ROWS]f32 = undefined, // fl(y * FREQ), the f32 product the formula starts with

    pub fn init(self: *Wobble) void {
        for (&self.row, 0..) |*r, y| r.* = @as(f32, @floatFromInt(y)) * FREQ;
    }

    // dxF32(y, wob), the same integer, without a sinf on almost every row.
    pub fn dx(self: *const Wobble, y: usize, wob: f32) i16 {
        const theta = self.row[y] + wob;
        return fromTable(theta) orelse @intFromFloat(AMP * @sin(theta));
    }
};

// trunc(AMP * sin(theta)) off the table, or null when the table cannot be sure.
fn fromTable(theta: f32) ?i16 {
    const ph = turns(theta) orelse return null;
    const idx = ph >> (32 - TBITS);
    const frac: i64 = (ph >> (32 - TBITS - 16)) & 0xFFFF;
    const lo = SIN[idx];
    const v: i32 = lo + @as(i32, @intCast((@as(i64, SIN[idx + 1] - lo) * frac) >> 16));
    const a: u32 = @abs(v);
    const k = a >> 16;
    const f = a & 0xFFFF;
    if (f > 0x10000 - EPS or (k > 0 and f < EPS)) return null; // too close to call
    const d: i16 = @intCast(k);
    return if (v < 0) -d else d;
}

// theta / 2pi mod 1 as a Q32 fraction, from theta's exact bits: theta = m * 2^(e-150).
fn turns(theta: f32) ?u32 {
    const bits: u32 = @bitCast(theta);
    const e: i32 = @intCast((bits >> 23) & 0xFF);
    if (bits >> 31 != 0 or e == 0 or e == 255) return null; // negative, denormal, inf/NaN: not RUBBER's
    const m: u128 = (bits & 0x7FFFFF) | 0x800000;
    const shift = 182 - e; // turns * 2^32 = m * INV_2PI_Q64 * 2^(e - 182)
    if (shift <= 0 or shift >= 128) return null;
    return @truncate((m * INV_2PI_Q64) >> @intCast(shift));
}

const FRAMES = 36_000; // 10 minutes at 60 Hz: a Debug `zig test` in the gate stays quick

test "the table gives dxF32's integer, frame by frame as the scene steps wob" {
    var w = Wobble{};
    w.init();
    var wob: f32 = 0;
    var asked: u64 = 0;
    for (0..FRAMES) |_| {
        wob += 0.14; // effects.zig Fx.step
        for (0..ROWS) |y| {
            try std.testing.expectEqual(dxF32(@intCast(y), wob), w.dx(y, wob));
            if (fromTable(w.row[y] + wob) == null) asked += 1;
        }
    }
    try std.testing.expect(asked * 100 < FRAMES * ROWS); // the fallback stays rare (< 1 %)
}

test "random angles, and the cases the table refuses" {
    var w = Wobble{};
    w.init();
    var prng = std.Random.DefaultPrng.init(0x5EED);
    const r = prng.random();
    for (0..200_000) |_| {
        const wob = r.float(f32) * 2_000_000.0;
        const y = r.uintLessThan(usize, ROWS);
        try std.testing.expectEqual(dxF32(@intCast(y), wob), w.dx(y, wob));
    }
    try std.testing.expectEqual(@as(?i16, null), fromTable(-1.0));
    try std.testing.expectEqual(@as(?u32, null), turns(std.math.inf(f32)));
    const q = turns(std.math.pi / 2.0).?; // f32(pi/2) is 4.4e-8 past a quarter turn: +30 in Q32
    try std.testing.expect(q > 0x40000000 and q < 0x40000000 + 64);
}
