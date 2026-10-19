// --------------------------------------------------------------------------
// SysInfo — the speed tests' reference: a stock 8 MHz ST doing the same work
// with its 68000, as the ST benchmarks of the day reported "% of a stock ST".
//
// The ST's time is not measured anywhere: it is the 68000 cycle count of the
// loop an ST programmer would write for each test (Motorola's execution
// tables, every instruction rounded up to 4 cycles as the ST's bus does; see
// the m68000-cycles notes), at 8 MHz. Each loop is written out next to its
// number so it can be checked:
//
//   INTEGER   add.l d1,d0 (8) + eor.l d0,d1 (8) + dbra (10->12)      = 28 / iteration
//   CLEAR     move.l d0,(a0)+ (12) + dbra (12)                         = 24 / 4 bytes
//   COPY      move.l (a0)+,(a1)+ (20) + dbra (12)                      = 32 / 4 bytes
//   SCATTER   add.w d1,d2 (4) + and.w d3,d2 (4)
//             + move.b d0,0(a0,d2.w) (14->16) + dbra (12)              = 36 / store
//
// The blitter rows use the CLEAR and COPY loops too: a stock ST has no
// blitter, so its CPU is what a clear or a copy costs there. The two
// multiply-add tests have no ST row (mulu is 38..70 cycles, data-dependent,
// and an ST has no FPU): the f32 test is reported against the integer one on
// the SAME machine, which is the number that says whether f32 is in hardware.
//
// Pure: tested natively (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const ST_MHZ: u64 = 8;

pub const ST_INT_CYCLES: u32 = 28;
pub const ST_CLEAR_CYCLES: u32 = 24; // per 4 bytes
pub const ST_COPY_CYCLES: u32 = 32; // per 4 bytes
pub const ST_SCATTER_CYCLES: u32 = 36;

/// One test's measurement: `reps` runs of its kernel took `us` microseconds.
/// us == 0 means the host has no clock (hostMicros answered 0): "n/a".
pub const Result = struct { reps: u32 = 0, us: u32 = 0 };

/// What a stock ST takes for `units` loop iterations of `cycles` each, in us.
pub fn stMicros(cycles: u32, units: u32) u64 {
    return @as(u64, cycles) * units / ST_MHZ;
}

/// How many times faster than the ST, x10 (one decimal), or null with no clock.
pub fn timesSt(st_us_per_rep: u64, r: Result) ?u64 {
    if (r.us == 0 or r.reps == 0) return null;
    return st_us_per_rep * r.reps * 10 / r.us;
}

/// How fast `r` is against `ref` on the same machine, x100 (two decimals: a
/// soft-float f32 runs at a few hundredths of the integer speed), or null.
pub fn timesRef(r: Result, ref: Result) ?u64 {
    if (r.us == 0 or ref.us == 0 or r.reps == 0 or ref.reps == 0) return null;
    return @as(u64, ref.us) * r.reps * 100 / (@as(u64, r.us) * ref.reps);
}

/// Microseconds a rep, x10.
pub fn perRep10(r: Result) ?u64 {
    if (r.us == 0 or r.reps == 0) return null;
    return @as(u64, r.us) * 10 / r.reps;
}

// --- native tests ------------------------------------------------------------
test "a stock ST clears 64000 bytes in 48 ms with a move.l loop" {
    try std.testing.expectEqual(@as(u64, 48_000), stMicros(ST_CLEAR_CYCLES, 64000 / 4));
}

test "the integer loop is 28 cycles: 65536 iterations take an ST 229 ms" {
    try std.testing.expectEqual(@as(u64, 229_376), stMicros(ST_INT_CYCLES, 65536));
}

test "twice the ST's speed reads 2.0" {
    // the ST takes 48 ms a rep; this machine did 4 reps in 96 ms
    try std.testing.expectEqual(@as(?u64, 20), timesSt(48_000, .{ .reps = 4, .us = 96_000 }));
}

test "no clock means no ratio, never a guess" {
    try std.testing.expectEqual(@as(?u64, null), timesSt(48_000, .{ .reps = 1, .us = 0 }));
    try std.testing.expectEqual(@as(?u64, null), timesRef(.{ .reps = 1, .us = 5 }, .{ .reps = 1, .us = 0 }));
    try std.testing.expectEqual(@as(?u64, null), perRep10(.{}));
}

test "a test three times slower than its reference reads 0.33" {
    // ref: 30 reps in 3000 us (100 us each); r: 10 reps in 3000 us (300 us each)
    try std.testing.expectEqual(@as(?u64, 33), timesRef(.{ .reps = 10, .us = 3000 }, .{ .reps = 30, .us = 3000 }));
}

test "per-rep time keeps one decimal" {
    try std.testing.expectEqual(@as(?u64, 125), perRep10(.{ .reps = 8, .us = 100 }));
}
