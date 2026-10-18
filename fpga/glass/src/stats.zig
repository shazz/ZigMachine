// The live numbers the debug page shows: loads, how long the last one took, the
// last trap, and the cart's frame rate measured from CART_BEAT (the firmware's
// frame count) against the ARM's clock, its last minute (beats.zig), and why no cart
// runs (the control channel's ZMSTAT state). Pure: the caller passes the time.
const std = @import("std");
const Beats = @import("beats.zig").Beats;

/// Why the cart CPU is not running a cart, when it is not.
pub const Stop = enum { idle, trapped, failed, quit };

const WINDOW_MS = 1000; // the frame rate is re-measured once a second

pub const Stats = struct {
    start_ms: i64 = 0,
    loads: u32 = 0,
    last_load_ms: i64 = 0,
    last_trap: ?u32 = null,
    fw: u32 = 0, // the firmware version the cart CPU last reported (CART_STATE 31:8)
    fps_x10: ?u32 = null, // null until a whole window was seen
    beat0: u32 = 0,
    t0: i64 = 0,
    beats: Beats = .{},
    stop: Stop = .idle,
    last_err: ?anyerror = null, // the last load's error (a load that worked clears it)

    pub fn loaded(self: *Stats, took_ms: i64, fw: u32) void {
        self.loads += 1;
        self.last_load_ms = took_ms;
        self.fw = fw;
        self.last_err = null;
        self.restart(0, 0);
    }

    fn restart(self: *Stats, now: i64, beat: u32) void {
        self.beat0 = beat;
        self.t0 = now;
        self.fps_x10 = null;
        self.beats.reset();
    }

    /// A load or a request that failed: what the ZMSTAT line reports until the next load.
    pub fn failed(self: *Stats, err: anyerror) void {
        self.last_err = err;
        self.stop = if (err == error.CartTrapped) .trapped else .failed;
    }

    /// One look at CART_BEAT. A beat that went backwards (the CPU was reset) or
    /// a first sample starts a new window.
    pub fn sample(self: *Stats, now: i64, beat: u32) void {
        if (self.t0 == 0 or beat < self.beat0) self.restart(now, beat);
        self.beats.push(now, beat);
        if (self.t0 == now) return;
        const dt = now - self.t0;
        if (dt < WINDOW_MS) return;
        const frames: i64 = beat - self.beat0;
        self.fps_x10 = @intCast(@divTrunc(frames * 10_000, dt));
        self.beat0 = beat;
        self.t0 = now;
    }

    pub fn uptimeS(self: *const Stats, now: i64) i64 {
        return @divTrunc(now - self.start_ms, 1000);
    }
};

test "the frame rate comes from the beat over a second, and restarts on a reset" {
    var s = Stats{ .start_ms = 1000 };
    s.sample(2000, 10);
    try std.testing.expectEqual(@as(?u32, null), s.fps_x10);
    s.sample(2500, 35);
    try std.testing.expectEqual(@as(?u32, null), s.fps_x10); // half a window
    s.sample(3000, 70);
    try std.testing.expectEqual(@as(?u32, 600), s.fps_x10); // 60 frames in 1 s
    s.sample(3100, 2); // the cart CPU was reset
    try std.testing.expectEqual(@as(?u32, null), s.fps_x10);
    s.sample(5100, 102);
    try std.testing.expectEqual(@as(?u32, 500), s.fps_x10);
    s.loaded(412, 0x000100);
    try std.testing.expectEqual(@as(u32, 1), s.loads);
    try std.testing.expectEqual(@as(i64, 4), s.uptimeS(5100));
}
