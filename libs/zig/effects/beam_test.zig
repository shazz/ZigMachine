// Tests for effects/beam.zig against a fake register block: entries land in the
// table as x<<16 | colour, COUNT grows past 64 without a slot (so the machine
// counts the overflow), cells(), and the drop counter.
const std = @import("std");
const beam_lib = @import("beam.zig");
const expectEqual = std.testing.expectEqual;

var mem: [0x240]u8 = undefined; // table + one guard slot past it

const FakeHW = struct {
    pub fn r16(off: usize) u16 {
        return std.mem.readInt(u16, mem[off..][0..2], .little);
    }
    pub fn w16(off: usize, v: u16) void {
        std.mem.writeInt(u16, mem[off..][0..2], v, .little);
    }
    pub fn r32(off: usize) u32 {
        return std.mem.readInt(u32, mem[off..][0..4], .little);
    }
    pub fn w32(off: usize, v: u32) void {
        std.mem.writeInt(u32, mem[off..][0..4], v, .little);
    }
};

const COUNT = 0x04;
const DROPPED = 0x08;
const TABLE = 0x100;
const beam = beam_lib.Beam(FakeHW, .{ .count = COUNT, .dropped = DROPPED, .table = TABLE, .max = 64 });

fn entry(i: usize) u32 {
    return FakeHW.r32(TABLE + i * 4);
}

test "write() appends x<<16 | colour and bumps COUNT" {
    @memset(&mem, 0xAA);
    beam.begin();
    try expectEqual(@as(u16, 0), beam.queued());
    beam.write(40, 0x700);
    beam.write(360, 0x000);
    try expectEqual(@as(u16, 2), beam.queued());
    try expectEqual(@as(u32, 0x0028_0700), entry(0));
    try expectEqual(@as(u32, 0x0168_0000), entry(1));
}

test "begin() restarts the line's list" {
    beam.begin();
    beam.write(8, 0x111);
    beam.begin();
    beam.write(16, 0x222);
    try expectEqual(@as(u16, 1), beam.queued());
    try expectEqual(@as(u32, 0x0010_0222), entry(0));
}

test "past 64 a write has no slot but still counts, so the machine drops it" {
    @memset(&mem, 0);
    beam.begin();
    for (0..70) |i| beam.write(@intCast(i), 0x123);
    try expectEqual(@as(u16, 70), beam.queued());
    try expectEqual(@as(u32, 0x003F_0123), entry(63));
    try expectEqual(@as(u32, 0), FakeHW.r32(TABLE + 64 * 4)); // nothing written past the table
}

test "cells() writes one entry per cell, w apart" {
    beam.begin();
    beam.cells(0, 8, &.{ 0x700, 0x070, 0x007 });
    try expectEqual(@as(u16, 3), beam.queued());
    try expectEqual(@as(u32, 0x0000_0700), entry(0));
    try expectEqual(@as(u32, 0x0008_0070), entry(1));
    try expectEqual(@as(u32, 0x0010_0007), entry(2));
}

test "dropped() reads the machine's counter, clearDropped() zeroes it" {
    FakeHW.w32(DROPPED, 5);
    try expectEqual(@as(u32, 5), beam.dropped());
    beam.clearDropped();
    try expectEqual(@as(u32, 0), beam.dropped());
}
