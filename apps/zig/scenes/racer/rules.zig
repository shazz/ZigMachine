// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// play_state's clock, checkpoints and laps.
//
// RACER: the player's race rules, one `tick` per physics tick of the race state. The clock starts
// at 75 s (M5 step 4: the track's own clock, clock.zig; the oval's is still 75 s + 10 s); each
// checkpoint (the track's, in lap order) adds 10 s and shows "extend time" for
// 5 s; passing the last checkpoint closes the lap (its time is kept, the best lap noted), and the
// last lap (the third, or the options screen's count) is a win; the clock reaching 0 is a loss (it is judged first, as in the original).
// A checkpoint is passed when the player's track u is past `lap * segments + checkpoint`.
// Times are ticks (30 Hz). Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const clock = @import("clock.zig");
const trk = @import("trk.zig");

pub const LAPS = 3; // the reference race's (every bench lap and pin); the options screen picks 1, 3 or 5 for a race
pub const MAX_LAPS = 5;
pub const LAP_CHOICES = [3]u32{ 1, 3, 5 };
pub var race_laps: u32 = LAPS; // the options screen's, for the session (Game.setMode gives it to a race)
pub const HZ = 30;
pub const START_TICKS = 75 * HZ;
pub const EXTEND_TICKS = 10 * HZ;
pub const MESSAGE_TICKS = 5 * HZ;
const NO_BEST: u32 = 32000;

pub const Result = enum { none, checkpoint, lap, win, timeout };

pub const Rules = struct {
    segments: i32,
    checkpoints: []const u32,
    remaining: i32 = START_TICKS,
    start_ticks: u32 = START_TICKS, // this track's clock (clock.zig: the file's, or computed from its line)
    extend_ticks: u32 = EXTEND_TICKS,
    total: u32 = 0,
    lap_t: u32 = 0,
    extend_t: i32 = 0,
    checkpoint: u32 = 0,
    goal: u32 = LAPS, // the laps this race is run over (Session.laps; M5 finish: the options screen)
    laps: [MAX_LAPS]u32 = [_]u32{0} ** MAX_LAPS,
    nlaps: u32 = 0,
    best_t: u32 = NO_BEST,
    best_i: u32 = 0, // 1-based index of the best lap, 0 before the first

    pub fn init(t: *const trk.Track) error{NoCheckpoints}!Rules {
        if (t.checkpoints.len == 0) return error.NoCheckpoints;
        const c = clock.of(t);
        return .{ .segments = @intCast(t.line.len), .checkpoints = t.checkpoints, .remaining = @intCast(c.start), .start_ticks = c.start, .extend_ticks = c.extend };
    }

    /// One tick of the race clock with the player's track `u` (16.16, unwrapped: it grows over laps).
    pub fn tick(self: *Rules, u: i32) Result {
        self.extend_t -= 1;
        self.total += 1;
        self.remaining -= 1;
        self.lap_t += 1;
        if (self.remaining == 0) return .timeout;
        const gate = (@as(i32, @intCast(self.nlaps)) * self.segments + @as(i32, @intCast(self.checkpoints[self.checkpoint]))) << 16;
        if (u <= gate) return .none;
        self.checkpoint += 1;
        self.remaining += @intCast(self.extend_ticks);
        self.extend_t = MESSAGE_TICKS;
        if (self.checkpoint < self.checkpoints.len) return .checkpoint;
        return self.closeLap();
    }

    fn closeLap(self: *Rules) Result {
        self.laps[self.nlaps] = self.lap_t;
        self.nlaps += 1;
        if (self.lap_t < self.best_t) {
            self.best_t = self.lap_t;
            self.best_i = self.nlaps;
        }
        self.checkpoint = 0;
        self.lap_t = 0;
        return if (self.nlaps == self.goal) .win else .lap;
    }

    /// The u past which the player has finished all the laps (the last checkpoint of the last lap).
    pub fn finishU(self: *const Rules) i32 {
        const last: i32 = @intCast(self.checkpoints[self.checkpoints.len - 1]);
        return ((@as(i32, @intCast(self.goal)) - 1) * self.segments + last) << 16;
    }

    /// Seconds left on the clock, rounded up (the HUD's number).
    pub fn seconds(self: *const Rules) i32 {
        return @divFloor(self.remaining + HZ - 1, HZ);
    }
};

/// The options screen's next lap count of LAP_CHOICES after (step 1) or before (-1) `laps` (an unknown count: from 3).
pub fn nextLaps(laps: u32, step: i32) u32 {
    const n: i32 = LAP_CHOICES.len;
    const at: i32 = for (LAP_CHOICES, 0..) |c, i| {
        if (c == laps) break @intCast(i);
    } else 1;
    return LAP_CHOICES[@intCast(@mod(at + step, n))];
}
