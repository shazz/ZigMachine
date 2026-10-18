// --------------------------------------------------------------------------
// XM pitch and vibrato tables. Built at COMPILE time (comptime float is the
// one place float is used: the tables are constants, and no per-frame or
// per-tick code touches a float; the board has no FPU, see docs/MUSIC.md).
//
// A pitch is an XM "period". Linear songs (the default): 768 periods an
// octave, the frequency 8363 * 2^((4608 - period) / 768) Hz, a semitone = 64
// periods. Amiga songs: FT2's Amiga periods, ProTracker's x 4 (C-4 = 1712,
// C-0 = 27392), the frequency 8363 * 1712 / period Hz: either way C-4 plays a
// sample at its own rate (ProTracker's 428-for-C-2 scale played them two
// octaves high). The output is a 16.16 step: source frames per output frame
// at SAMPLE_RATE, the same unit mod.zig's periodToStep returns.
// Pure: no chip. Tested natively (xm_format_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const RATE: f64 = 44100.0;
const LIN_BASE: f64 = 8363.0; // Hz at period 4608 (C-4, the linear table's zero)
const AMIGA_C4: f64 = 1712.0; // FT2's Amiga period of C-4, the note that plays at LIN_BASE
pub const PERIOD_MIN: i32 = 1;
pub const PERIOD_MAX: i32 = 32000; // past the Amiga C-0 (27392): the widest a tune reaches

/// 16.16 step for a linear period: LIN_BASE / RATE * 2^((4608 - p) / 768).
const LIN_STEP_BASE: u32 = @intFromFloat(@round(LIN_BASE / RATE * 65536.0));
/// 2^(r / 768) as Q16, r = 0..767. Q16 (not Q24) keeps base * frac inside a u32:
/// BARD has no 64-bit multiply in the per-tick path.
const LIN_FRAC: [768]u32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [768]u32 = undefined;
    for (&t, 0..) |*v, r| v.* = @intFromFloat(@round(std.math.pow(f64, 2.0, @as(f64, @floatFromInt(r)) / 768.0) * 65536.0));
    break :blk t;
};
/// 16.16 step * period for an Amiga period: 8363 * 1712 / RATE * 65536.
const AMIGA_STEP_K: i32 = @intFromFloat(@round(LIN_BASE * AMIGA_C4 / RATE * 65536.0));
/// FT2's Amiga C-0 period (1712 x 16) and the periods of the semitones after it,
/// k = semitone + 1 (index 0 is one below C, index 13 is C one octave up).
const AMIGA_PT: [14]i32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [14]i32 = undefined;
    for (&t, 0..) |*v, k| {
        const semi = @as(f64, @floatFromInt(k)) - 1.0;
        v.* = @intFromFloat(@round(AMIGA_C4 * 16.0 * std.math.pow(f64, 2.0, -semi / 12.0)));
    }
    break :blk t;
};
/// One vibrato cycle: 64 steps of +-64 (sine, rounded).
const SINE: [64]i32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [64]i32 = undefined;
    for (&t, 0..) |*v, i| v.* = @intFromFloat(@round(std.math.sin(2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / 64.0) * 64.0));
    break :blk t;
};

/// The step of linear period `p`: 2^((4608 - p) / 768) split into a whole
/// octave shift and a Q24 fraction from LIN_FRAC.
pub fn linearStep(p: i32) u32 {
    const m: i32 = 4608 - clampPeriod(p);
    const q: i32 = @divFloor(m, 768);
    const r: usize = @intCast(m - q * 768);
    const base: u32 = (LIN_STEP_BASE * LIN_FRAC[r]) >> 16;
    if (q <= -32) return 0; // 32 octaves down: no u32 shift reaches it, and it is silence anyway
    return if (q >= 0) base << @as(u5, @intCast(q)) else base >> @as(u5, @intCast(-q));
}

/// The step of Amiga period `p`: AMIGA_STEP_K / p.
pub fn amigaStep(p: i32) u32 {
    return @intCast(@divTrunc(AMIGA_STEP_K, clampPeriod(p)));
}

pub fn stepOf(p: i32, linear: bool) u32 {
    return if (linear) linearStep(p) else amigaStep(p);
}

/// The period of a note: `semi` is its semitone from C-0 (relnote already
/// added), `ft` the sample's finetune in 1/128 semitone (-128..127). Linear:
/// the XM formula. Amiga: the ProTracker period for the semitone, the octave
/// shift applied, and the finetune as a linear step toward the next semitone.
pub fn periodOf(semi: i32, ft: i32, linear: bool) i32 {
    if (linear) return clampPeriod(7680 - semi * 64 - @divTrunc(ft, 2));
    const s = @max(semi, 0);
    const oct: u5 = @intCast(@min(@divTrunc(s, 12), 31));
    const k: usize = @intCast(@rem(s, 12) + 1);
    const base = AMIGA_PT[k] >> oct;
    const next = AMIGA_PT[if (ft >= 0) k + 1 else k - 1] >> oct;
    const frac = @divTrunc(@as(i32, @intCast(@abs(ft))) * (next - base), 128);
    return clampPeriod(base + frac);
}

pub fn clampPeriod(p: i32) i32 {
    return std.math.clamp(p, PERIOD_MIN, PERIOD_MAX);
}

/// Vibrato offset at phase `pos` (0..63), in periods: FT2's (sine * depth) >> 5
/// with its sine at +-255, i.e. this +-64 sine x 4. Depth F is then +-119
/// periods, near two semitones (a semitone is 64 linear periods): FT2's periods
/// are ProTracker's x 4, so is its vibrato.
pub fn vibratoDelta(pos: u32, depth: u8) i32 {
    return @divTrunc(SINE[pos & 63] * 4 * @as(i32, depth), 32);
}
