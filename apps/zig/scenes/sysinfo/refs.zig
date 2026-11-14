// --------------------------------------------------------------------------
// SysInfo — the speed tests' reference machines. SysInfo shows a stock ST as
// 100 %; here the reference can be switched (page 5: Up / Down or C) and every
// percentage is recomputed against it from the results already measured.
//
// The ST's time for each test is stref.zig's: the 68000 cycle count of the ST
// programmer's loop at 8 MHz. Every other machine's time is the ST's divided
// by that machine's CPU speed against the ST, and that factor is a PUBLISHED
// result: CoreMark 1.0 on real machines, the Atari port's results table
// (github.com/czietz/coremark/wiki/Results, iterations a second; each row
// links the forum post it came from). One factor for every test is an
// estimate: CoreMark is an integer and memory mix, the tests are pure loops,
// so the per-test reference times of every machine but the ST are marked
// estimated on the page. Nothing here is invented: a machine missing from the
// table says so (`note`) and carries the score of the machine it equals.
//
// Pure: tested natively (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Ref = struct {
    name: []const u8, // the page's line
    cpu: []const u8,
    /// CoreMark iterations a second x100 (the table's figure, two decimals).
    coremark100: u32,
    /// Where the score comes from, as the page prints it.
    source: []const u8,
};

/// CoreMark x100 of a stock ST (68000 at 8 MHz): the table's "Stock ST / MegaST / MegaSTE @ 8 MHz", 1.92.
pub const ST_COREMARK100: u32 = 192;

pub const REFS = [_]Ref{
    // "Stock ST / MegaST / MegaSTE @ 8 MHz | 1.92"
    .{ .name = "ST", .cpu = "68000 8 MHZ", .coremark100 = 192, .source = "COREMARK 1.92 (STOCK ST, 8 MHZ)" },
    // Not in the table: an STE has the ST's 68000 at 8 MHz on the same bus, so it scores the ST's 1.92.
    .{ .name = "STE", .cpu = "68000 8 MHZ", .coremark100 = 192, .source = "AS ST: SAME 68000 AND BUS (NOT IN TABLE)" },
    // "MegaSTE @ 16 MHz, cache on | 3.62"
    .{ .name = "MEGA STE", .cpu = "68000 16 MHZ + CACHE", .coremark100 = 362, .source = "COREMARK 3.62 (16 MHZ, CACHE ON)" },
    // "TT, ran from ST-RAM | 8.70" (a stock TT: 68030 at 32 MHz, no Fast-RAM fitted)
    .{ .name = "TT030", .cpu = "68030 32 MHZ", .coremark100 = 870, .source = "COREMARK 8.70 (TT, FROM ST-RAM)" },
    // "Falcon @ 16 MHz in ST high | 6.49" (5.38 in true colour: the video steals bus time)
    .{ .name = "FALCON030", .cpu = "68030 16 MHZ", .coremark100 = 649, .source = "COREMARK 6.49 (16 MHZ, ST HIGH)" },
    // "Falcon CT60 @ 85 MHz | 192.74"
    .{ .name = "CT60", .cpu = "68060 85 MHZ", .coremark100 = 19274, .source = "COREMARK 192.74 (FALCON CT60 85 MHZ)" },
};
pub const COUNT = REFS.len;

/// The reference machine's time for one rep (us), from the ST's (stref.zig): the ST's time
/// scaled by the two CoreMark scores. The ST itself comes back unchanged.
pub fn refMicros(st_us: u64, r: Ref) u64 {
    return st_us * ST_COREMARK100 / r.coremark100;
}

/// SysInfo's "% of the reference": 100 = as fast; null with no clock or no reps.
pub fn percent(ref_us_per_rep: u64, reps: u32, us: u32) ?u64 {
    if (us == 0 or reps == 0) return null;
    return ref_us_per_rep * reps * 100 / us;
}

/// The next (step +1) or previous (-1) reference, wrapping.
pub fn step(i: u8, by: i8) u8 {
    const n: i16 = COUNT;
    return @intCast(@mod(@as(i16, i) + by, n));
}

// --- native tests ------------------------------------------------------------
test "the ST is its own reference: its time is unchanged" {
    try std.testing.expectEqual(@as(u64, 48_000), refMicros(48_000, REFS[0]));
    try std.testing.expectEqual(@as(u64, 48_000), refMicros(48_000, REFS[1]));
}

test "a faster reference takes less time: the CT60 is 192.74 / 1.92 the ST" {
    // 48 ms on the ST -> 48000 * 192 / 19274 = 478 us on the CT60
    try std.testing.expectEqual(@as(u64, 478), refMicros(48_000, REFS[5]));
}

test "a machine as fast as the reference reads 100 percent" {
    try std.testing.expectEqual(@as(?u64, 100), percent(48_000, 2, 96_000));
    try std.testing.expectEqual(@as(?u64, 250), percent(1000, 5, 2000));
}

test "no clock means no percentage" {
    try std.testing.expectEqual(@as(?u64, null), percent(48_000, 1, 0));
    try std.testing.expectEqual(@as(?u64, null), percent(48_000, 0, 5));
}

test "the reference wraps both ways" {
    try std.testing.expectEqual(@as(u8, COUNT - 1), step(0, -1));
    try std.testing.expectEqual(@as(u8, 0), step(COUNT - 1, 1));
}

test "every reference has a source and a score" {
    for (REFS) |r| {
        try std.testing.expect(r.source.len > 0 and r.coremark100 > 0);
        try std.testing.expect(r.source.len <= 40); // the page's right column
    }
}
