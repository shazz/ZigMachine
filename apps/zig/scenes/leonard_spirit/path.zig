// --------------------------------------------------------------------------
// The Lissajous chain of the 2005 record (the `leonard` cart, after Dyno's
// CODEF remake of Leonard's screen):
//
//   x = 152 + ((76 cos(a1) + 76 sin(a2)) >> 15)
//   y =  92 + ((44 cos(b1) + 44 sin(b2)) >> 15)
//
// ball to ball the angles step by (+7, -4, +6, -3) t, frame to frame by
// (+3, +2, -1, +2) degrees, t = 1 degree. So ball 360 lands exactly on ball
// 0: a longer chain only redraws itself. More balls need more curves: here
// SNAKES snakes, each the 2005 record's own 312-ball snake, snake k on the
// family's curve with a2 and b2 advanced by k * 11.25 and k * 5.625 degrees
// (2^32/32 and 2^32/64 turns: exact). Side by side they weave into a ribbon
// of distinct shaded balls (2,371 distinct positions of 2,496 in frame 0).
// Tried and dropped: one curve with t = 360/N (a solid brown tube, every ball
// hides the next one's highlight) or t = 1.15 (8 laps nearly on top of each
// other: ball i+313 within a pixel of ball i, the chain redrawn again).
//
// Integer only per frame: angles are u32 turns (2^32 = 360 degrees, wrapping
// is the modulo), the sine is a 1,024-step Q15 table (2 KB, stays in the D$),
// and the frame's start angles come from a 360-entry degree table, so the
// motion repeats exactly every 360 frames. Tables built at COMPILE TIME.
// --------------------------------------------------------------------------
const std = @import("std");

pub const SIN_LEN = 1024;
pub const PERIOD = 360; // frames: every frame step is a whole number of degrees

/// round(32767 sin(2 pi i / 1024)), evaluated in f64 by the compiler.
pub const SIN: [SIN_LEN]i16 = blk: {
    @setEvalBranchQuota(50_000);
    var t: [SIN_LEN]i16 = undefined;
    for (0..SIN_LEN) |i| {
        const a = @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / SIN_LEN;
        t[i] = @intFromFloat(@round(32767.0 * @sin(a)));
    }
    break :blk t;
};

/// d degrees as a u32 turn: floor(d * 2^32 / 360).
pub const DEG: [PERIOD]u32 = blk: {
    var t: [PERIOD]u32 = undefined;
    for (0..PERIOD) |d| t[d] = @intCast((@as(u64, d) << 32) / PERIOD);
    break :blk t;
};

inline fn sin(a: u32) i32 {
    return SIN[a >> 22];
}
inline fn cos(a: u32) i32 {
    return SIN[((a >> 22) + SIN_LEN / 4) & (SIN_LEN - 1)];
}

pub const SNAKES = 8;
pub const SNAKE_LEN = 312; // Leonard's record, once per snake
const STEP: u32 = DEG[1]; // t
const PHASE_A: u32 = 1 << 27; // 11.25 degrees: snake k's a2 offset
const PHASE_B: u32 = 1 << 26; // 5.625 degrees: snake k's b2 offset

/// Walks snake k (0..SNAKES-1) of frame f (0..359), in drawing order.
pub const Chain = struct {
    a1: u32,
    a2: u32,
    b1: u32,
    b2: u32,

    pub fn start(f: u32, k: u32) @This() {
        return .{
            .a1 = DEG[(3 * f) % PERIOD],
            .a2 = DEG[(2 * f) % PERIOD] +% k *% PHASE_A,
            .b1 = DEG[(PERIOD - f) % PERIOD],
            .b2 = DEG[(2 * f) % PERIOD] +% k *% PHASE_B,
        };
    }

    pub inline fn x(self: *const @This()) u32 {
        return @intCast(152 + ((76 * (cos(self.a1) + sin(self.a2))) >> 15));
    }
    pub inline fn y(self: *const @This()) u32 {
        return @intCast(92 + ((44 * (cos(self.b1) + sin(self.b2))) >> 15));
    }

    pub inline fn next(self: *@This()) void {
        self.a1 +%= 7 *% STEP;
        self.a2 -%= 4 *% STEP;
        self.b1 +%= 6 *% STEP;
        self.b2 -%= 3 *% STEP;
    }
};
