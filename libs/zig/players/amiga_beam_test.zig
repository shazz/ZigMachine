// Native tests for amiga_beam.zig: `zig test` this file.
const std = @import("std");
const beam = @import("amiga_beam.zig");

test "the vertical blank is line 0, clock 0" {
    try std.testing.expectEqual(@as(u16, 0), beam.vhposr(0));
    try std.testing.expectEqual(@as(u16, 0), beam.vposr(0));
}

test "two CPU cycles a colour clock: the horizontal byte moves inside a busy-wait" {
    // move.b 6(a6),d6 (12 cycles) then cmp.b 6(a6),d6: the second read sees a later clock.
    try std.testing.expectEqual(@as(u16, 6), beam.vhposr(12) - beam.vhposr(0));
    try std.testing.expectEqual(beam.vhposr(0), beam.vhposr(1)); // under a clock: unchanged
}

test "a line is 227 clocks: the next line starts at clock 0" {
    try std.testing.expectEqual(@as(u16, 226), beam.vhposr(beam.CYCLES_PER_LINE - 1));
    try std.testing.expectEqual(@as(u16, 0x0100), beam.vhposr(beam.CYCLES_PER_LINE));
}

test "line 256 and over: V8 in VPOSR bit 0, V7-V0 in VHPOSR" {
    const c = 300 * beam.CYCLES_PER_LINE + 10;
    try std.testing.expectEqual(@as(u16, 1), beam.vposr(c));
    try std.testing.expectEqual(@as(u16, ((300 & 0xFF) << 8) | 5), beam.vhposr(c));
}

test "313 lines a frame: the beam wraps to line 0" {
    try std.testing.expectEqual(@as(u16, 0), beam.vhposr(beam.CYCLES_PER_FRAME));
    try std.testing.expectEqual(@as(u16, 0), beam.vposr(beam.CYCLES_PER_FRAME));
    try std.testing.expectEqual(@as(u16, 312), beam.at(beam.CYCLES_PER_FRAME - 1).line);
}
