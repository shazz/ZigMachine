// --------------------------------------------------------------------------
// RACER: the x bench's round (lap v2) counted in physics TICKS, not frames (R82 board batch, item 8: the bench is a race
// at real-time speed). Since the real-time pacing (pace.zig) a frame under 60 fps runs extra ticks, so the old round of
// 2,880 FRAMES ran up to ~2x its 1,440 ticks on the board: the recorded driver (data.race_v2) ran out and the car coasted
// for the rest. The grid's start and the round's end are now at tick 30 and tick 1,440 since the round's reset, checked
// on even frames only: with no clock (every harness) the ticks are frames / 2 and both land on frames 60 and 2,880 as
// before, so every bench pin holds. Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ROUND_TICKS: u32 = 1440; // game.ROUND_FRAMES / 2: 30 ticks of grid, 90 of countdown, 1,320 of racing
pub const GRID_TICKS: u32 = 30; // game.GRID_FRAMES / 2

pub const Act = enum { none, reset, start };

/// What the bench does at the start of frame `frames` of the round, `ticks` ticks into it, the session `on_grid` or not.
pub fn act(frames: u32, ticks: u32, on_grid: bool) Act {
    if (frames % 2 != 0) return .none;
    if (ticks >= ROUND_TICKS) return .reset;
    if (on_grid and ticks >= GRID_TICKS) return .start;
    return .none;
}

fn round(ticks_a_frame: []const u32) [2]u32 {
    var ticks: u32 = 0;
    var started: u32 = 0;
    var f: u32 = 0;
    while (true) : (f += 1) {
        switch (act(f, ticks, started == 0)) {
            .reset => return .{ started, f },
            .start => started = f,
            .none => {},
        }
        ticks += if (f % 2 == 0) 1 else 0;
        ticks += ticks_a_frame[f % ticks_a_frame.len];
    }
}

test "no clock (a harness): the start on frame 60 and the reset on frame 2,880, as the frame-counted round" {
    try std.testing.expectEqual([2]u32{ 60, 2880 }, round(&.{0}));
}

test "17 fps paced (~0.76 extra ticks a frame): the round is 1,440 ticks, far fewer frames" {
    const r = round(&.{ 1, 1, 1, 0 }); // 0.75 extra a frame on top of the counted 0.5
    try std.testing.expect(r[1] < 2880 and r[1] >= 1440 / 2);
    try std.testing.expect(r[0] < 60);
}

test "odd frames never act, a round past its ticks resets, a started grid never starts again" {
    try std.testing.expectEqual(Act.none, act(61, 5000, true));
    try std.testing.expectEqual(Act.reset, act(62, ROUND_TICKS + 3, false));
    try std.testing.expectEqual(Act.none, act(62, 100, false));
    try std.testing.expectEqual(Act.none, act(40, GRID_TICKS - 1, true));
}
