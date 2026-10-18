// Native tests for the XM mixer's block ring (xm_ring.zig): `zig test` this file.
const std = @import("std");
const ring = @import("xm_ring.zig");

/// The machine's largest render (machine/sdk/audio.zig MAX_FRAMES), which bounds a block.
const MAX_BLOCK: u32 = 4096;

/// Play blocks of `sizes` (cycled) through the ring; for each, count the frames
/// written after it before any write lands on one of its frames again.
fn minSurvival(comptime place: fn (u32, u32) u32, sizes: []const u32, blocks: usize) u32 {
    var owner = [_]i32{-1} ** ring.FRAMES; // which block last wrote each frame
    var written_after = [_]u32{0} ** 4096; // frames written since each block, while it is intact
    var intact = [_]bool{false} ** 4096;
    var worst: u32 = std.math.maxInt(u32);
    var pos: u32 = 0;
    for (0..blocks) |b| {
        const n = sizes[b % sizes.len];
        const start = place(pos, n);
        for (start..start + n) |f| {
            const o = owner[f];
            if (o >= 0 and intact[@intCast(o)]) {
                intact[@intCast(o)] = false;
                worst = @min(worst, written_after[@intCast(o)]);
            }
            owner[f] = @intCast(b);
        }
        for (0..b) |k| if (intact[k]) {
            written_after[k] += n;
        };
        intact[b] = true;
        pos = start + n;
    }
    return worst;
}

test "a block is never overwritten before the board's lead has played it" {
    // Ticks of 125 BPM (882) cut by 735-sample frames, the largest blocks, and odd sizes.
    const cases = [_][]const u32{
        &.{ 735, 147, 588, 294, 441 },
        &.{ MAX_BLOCK, MAX_BLOCK, 1 },
        &.{ 3445, 2000, 4095, 7 },
        &.{1},
    };
    for (cases) |sizes| {
        try std.testing.expect(minSurvival(ring.place, sizes, 4000) >= ring.BOARD_LEAD + MAX_BLOCK);
    }
}

test "a block that would run past the ring's end starts again at 0, contiguous" {
    try std.testing.expectEqual(@as(u32, 100), ring.place(100, 735));
    try std.testing.expectEqual(@as(u32, 0), ring.place(ring.FRAMES - 10, 11));
    try std.testing.expectEqual(ring.FRAMES - 10, ring.place(ring.FRAMES - 10, 10));
}

/// The old mixer's layout: every block at the buffer's start.
fn oneBuffer(pos: u32, block: u32) u32 {
    _ = pos;
    _ = block;
    return 0;
}

test "one shared buffer (the old mixer) fails the lead: the check sees the bug" {
    try std.testing.expect(minSurvival(oneBuffer, &.{ 735, 147 }, 100) < ring.BOARD_LEAD);
}
