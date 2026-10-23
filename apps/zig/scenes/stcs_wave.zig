// --------------------------------------------------------------------------
// STCS STARGOOSE — the big fonts' letter-distortion wave (the "double sine").
//
// The scroller has two waves in its big-font periods: the first is the bounce
// (yp, stcs.zig), the second moves each 16-px column group by a fixed number of
// lines. CONFO.S (STCS.RAT), scroller types 1 and 7 (`loobi1`/`loobi7`, labels
// `sinus1`/`sinus2`): after each 16-px column group (d0 counts 19..0) the next
// group's start moves
//   d0 = 19..15 and 5..0 : +1 line   (gg1/gg2 at d0 = 14 and 6: no change)
//   d0 = 13..7           : -1 line
// a triangle fixed to the SCREEN columns (not the letters, no phase step: it
// never moves), +1 line per step in type 1 (big_font, the doubled big font) and
// +2 in type 7 (interlaced_big_font, `160*2`). First ported in b920acf0 on the
// CPU strip; here it is the table the CHISEL blits read (stcs_strip.zig).
//
// Pure (no zigos): its native test runs from apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");

pub const GROUPS = 20; // 320 / 16

/// Line offset of each column group (left to right), in type-1 steps.
pub const wave: [GROUPS]i16 = blk: {
    var t: [GROUPS]i16 = undefined;
    var off: i16 = 0;
    for (0..GROUPS) |g| {
        t[g] = off;
        const d0 = GROUPS - 1 - g;
        off += if (d0 == 14 or d0 == 6) 0 else if (d0 > 5 and d0 < 14) -1 else 1;
    }
    break :blk t;
};

/// Neighbouring groups with the same offset: one blit each (w = 16 * n).
pub const Run = struct { g: i16, n: i16, off: i16 };

pub const runs: []const Run = blk: {
    var out: [GROUPS]Run = undefined;
    var len: usize = 0;
    for (0..GROUPS) |g| {
        if (len > 0 and out[len - 1].off == wave[g]) {
            out[len - 1].n += 1;
        } else {
            out[len] = .{ .g = g, .n = 1, .off = wave[g] };
            len += 1;
        }
    }
    const fixed = out[0..len].*;
    break :blk &fixed;
};

test "the wave is CONFO.S's triangle" {
    const want = [GROUPS]i16{ 0, 1, 2, 3, 4, 5, 5, 4, 3, 2, 1, 0, -1, -2, -2, -1, 0, 1, 2, 3 };
    try std.testing.expectEqualSlices(i16, &want, &wave);
}

test "the runs cover every group once, each at its own offset, merged" {
    try std.testing.expectEqual(@as(usize, 18), runs.len); // groups 5-6 and 13-14 merge
    var next: i16 = 0;
    for (runs, 0..) |r, i| {
        try std.testing.expectEqual(next, r.g);
        for (0..@intCast(r.n)) |k| try std.testing.expectEqual(r.off, wave[@intCast(r.g + @as(i16, @intCast(k)))]);
        if (i > 0) try std.testing.expect(runs[i - 1].off != r.off);
        next += r.n;
    }
    try std.testing.expectEqual(@as(i16, GROUPS), next);
}

test "the wave is not flat: 17 group edges step, 7 lines from top to bottom" {
    var steps: usize = 0;
    var lo: i16 = wave[0];
    var hi: i16 = wave[0];
    for (1..GROUPS) |g| {
        if (wave[g] != wave[g - 1]) steps += 1;
        lo = @min(lo, wave[g]);
        hi = @max(hi, wave[g]);
    }
    try std.testing.expectEqual(@as(usize, 17), steps);
    try std.testing.expectEqual(@as(i16, 7), hi - lo); // 14 lines in interlaced_big_font
    // the lowest line any big font reaches stays below the logo (stcs_logo.ROWS = 73)
    try std.testing.expect(78 + 2 * lo >= 73);
}
