// --------------------------------------------------------------------------
// RACER: real-time pacing for the player's race (Matt 27 Nov on the board: a 32X course at 17 fps ran the race at
// ~28 % speed (36 fps in the bench: ~60 %), the physics being one 30 Hz tick every second frame BY COUNT). The by-count tick stays (so a race at
// 60 fps, and every harness that runs faster than real time, is unchanged tick for tick); this adds the ticks the
// real clock still owes when frames come slower than 60 a second. Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");

pub const TICK_US: u32 = 33_333; // one 30 Hz physics tick
pub const MAX_EXTRA: u32 = 3; // catch-up ticks in one frame (the slowest frame paced: ~7.5 fps)
pub const MAX_DT_US: u32 = (MAX_EXTRA + 1) * TICK_US; // a pause, a track load: one long frame, not a burst

pub const Pace = struct {
    last: ?u32 = null,
    owed: u32 = 0, // microseconds of race time the clock has given and the ticks have not taken yet

    /// The extra ticks to run this frame, after the `counted` by-count ticks it already runs.
    pub fn extra(self: *Pace, now: u32, counted: u32) u32 {
        const dt: u32 = if (self.last) |l| @min(now -% l, MAX_DT_US) else 0;
        self.last = now;
        self.owed = (self.owed + dt) -| counted * TICK_US;
        const n = @min(self.owed / TICK_US, MAX_EXTRA);
        self.owed -= n * TICK_US;
        return n;
    }

    /// `extra` while `paced`; otherwise none, and the clock forgotten (a paced race starts owing nothing).
    pub fn step(self: *Pace, paced: bool, now: u32, counted: u32) u32 {
        if (paced) return self.extra(now, counted);
        self.* = .{};
        return 0;
    }
};

fn run(p: *Pace, frame_us: u32, frames: u32) u32 {
    var t: u32 = 1000;
    var ticks: u32 = 0;
    for (0..frames) |f| {
        const counted: u32 = if (f % 2 == 0) 1 else 0;
        ticks += counted + p.extra(t, counted);
        t +%= frame_us;
    }
    return ticks;
}

test "60 fps: no extra tick (by count only)" {
    var p = Pace{};
    try std.testing.expectEqual(@as(u32, 300), run(&p, 16_667, 600));
}

test "faster than real time (a harness): no extra tick" {
    var p = Pace{};
    try std.testing.expectEqual(@as(u32, 50), run(&p, 2_000, 100));
}

test "36 fps: 30 ticks a second, not 18" {
    var p = Pace{};
    const ticks = run(&p, 27_778, 360); // 10 s
    try std.testing.expect(ticks >= 298 and ticks <= 300);
}

test "17 fps: about 30 ticks a second of real time" {
    var p = Pace{};
    const ticks = run(&p, 58_824, 170); // 10 s
    try std.testing.expect(ticks >= 298 and ticks <= 300);
}

test "a long stall is one capped frame, not a burst" {
    var p = Pace{};
    _ = p.extra(0, 1);
    try std.testing.expectEqual(MAX_EXTRA, p.extra(5_000_000, 0));
    try std.testing.expectEqual(@as(u32, 0), p.extra(5_000_000 + 16_667, 1));
}

test "not paced: none, and the clock forgotten" {
    var p = Pace{};
    _ = p.extra(0, 1);
    try std.testing.expectEqual(@as(u32, 0), p.step(false, 1_000_000, 0));
    try std.testing.expectEqual(@as(u32, 0), p.step(true, 2_000_000, 0)); // the first paced frame owes nothing
}

test "the clock wrapping past 2^32 us" {
    var p = Pace{};
    _ = p.extra(0xFFFF_FFF0, 1);
    try std.testing.expectEqual(@as(u32, 2), p.extra(@as(u32, 0xFFFF_FFF0) +% 66_666, 0));
}
