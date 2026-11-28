// --------------------------------------------------------------------------
// RACER: probe timers for the board (R82 board optimisation, OPTIMIZE.md). Up to SLOTS named spans of code are
// timed on env.hostMicros (begin / end around them, summed over the bench's 32-frame window); key ` shows the window's
// averages a frame, in units of 10 us, on the OSD's top line ("P0 12 P1 3 ..."), instead of the state line (a second press the probes 6..11, a third off). The
// probes cost two clock reads each: they stay in the code only where a measurement asked for them. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");

pub const SLOTS = 12;
pub const PAGE = 6; // probes a line
pub var page: u8 = 0; // key `: 0 off, 1 the probes 0..5, 2 the probes 6..11
pub var now: *const fn () u32 = zero;
var t0: [SLOTS]u32 = @splat(0);
var sum: [SLOTS]u32 = @splat(0);
pub var avg: [SLOTS]u32 = @splat(0); // the last window's, us a frame

fn zero() u32 {
    return 0;
}

pub inline fn begin(k: usize) void {
    if (page != 0) t0[k] = now(); // no clock read while the probes are not shown
}

pub inline fn end(k: usize) void {
    if (page != 0) sum[k] +%= now() -% t0[k];
}

/// The bench's window closed (`frames` frames): the averages kept, the sums restarted.
pub fn window(frames: u32) void {
    for (&avg, &sum) |*a, *s| {
        a.* = if (frames == 0) 0 else s.* / frames;
        s.* = 0;
    }
}

pub fn shown() bool {
    return page != 0;
}

pub fn nextPage() void {
    page = (page + 1) % 3;
}

pub fn line(buf: []u8) []const u8 {
    var n: usize = 0;
    const first: usize = if (page == 2) PAGE else 0;
    for (avg[first..][0..PAGE], first..) |a, k| n += (std.fmt.bufPrint(buf[n..], "P{} {} ", .{ k, a / 10 }) catch return buf[0..n]).len;
    return buf[0..n];
}

test "a window's averages, in the line" {
    page = 1;
    sum = .{ 100, 2000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    window(10);
    try std.testing.expectEqual(@as(u32, 200), avg[1]);
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("P0 1 P1 20 P2 0 P3 0 P4 0 P5 0 ", line(&b));
    page = 2;
    try std.testing.expectEqualStrings("P6 0 P7 0 P8 0 P9 0 P10 0 P11 0 ", line(&b));
    page = 0;
}
