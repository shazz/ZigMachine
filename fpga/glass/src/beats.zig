// The cart's frame count (CART_BEAT) over the last minute, one sample a watchdog tick
// (~10 a second), so the control channel's `stats N` measures the frame rate over any
// window up to SPAN_S seconds, not only the overlay's last second, and can tell a cart
// that stopped finishing frames (a hang: CART_STATE still says RUNNING) from one that
// is slow. Pure: the caller passes the time.
const std = @import("std");

pub const SLOTS = 512; // 51 s at 10 Hz
pub const SPAN_S = 50;
/// The output's refresh (800x600 at 60 Hz, the 40 MHz pixel clock): a frame a VBL is full speed.
pub const VBL_HZ = 60;

pub const Sample = struct { ms: i64, beat: u32 };

pub const Rate = struct {
    frames: u32, // frames finished in the window
    ms: i64, // the window's length
    missed: u32, // VBLs in the window that showed no new frame

    pub fn fpsX10(self: Rate) u32 {
        return @intCast(@divTrunc(@as(i64, self.frames) * 10_000, self.ms));
    }

    /// The mean wall time of a frame, in tenths of a ms; null when no frame finished.
    pub fn frameMsX10(self: Rate) ?u32 {
        if (self.frames == 0) return null;
        return @intCast(@divTrunc(self.ms * 10, self.frames));
    }
};

pub const Beats = struct {
    ring: [SLOTS]Sample = undefined,
    n: usize = 0, // samples held, up to SLOTS
    head: usize = 0, // where the next goes
    changed_ms: i64 = 0, // when the beat last moved

    pub fn reset(self: *Beats) void {
        self.n = 0;
        self.head = 0;
    }

    pub fn push(self: *Beats, ms: i64, beat: u32) void {
        if (self.n == 0 or self.newest().beat != beat) self.changed_ms = ms;
        self.ring[self.head] = .{ .ms = ms, .beat = beat };
        self.head = (self.head + 1) % SLOTS;
        self.n = @min(self.n + 1, SLOTS);
    }

    fn at(self: *const Beats, age: usize) Sample {
        return self.ring[(self.head + SLOTS - 1 - age) % SLOTS];
    }

    pub fn newest(self: *const Beats) Sample {
        return self.at(0);
    }

    /// The rate over the last `secs` seconds of samples (or as many as there are);
    /// null under half a second of them.
    pub fn rate(self: *const Beats, secs: u32) ?Rate {
        if (self.n < 2) return null;
        const last = self.newest();
        var first = last;
        for (1..self.n) |age| {
            const s = self.at(age);
            if (last.ms - s.ms > @as(i64, secs) * 1000) break;
            first = s;
        }
        const ms = last.ms - first.ms;
        if (ms < 500) return null;
        const frames = last.beat -% first.beat;
        const vbls: i64 = @divTrunc(ms * VBL_HZ + 500, 1000);
        return .{ .frames = frames, .ms = ms, .missed = @intCast(@max(0, vbls - frames)) };
    }

    /// How long the beat has not moved, at `now`.
    pub fn stillMs(self: *const Beats, now: i64) i64 {
        if (self.n == 0) return 0;
        return now - self.changed_ms;
    }
};

test "the rate is taken over the window asked for, and a stopped beat shows" {
    var b = Beats{};
    try std.testing.expectEqual(@as(?Rate, null), b.rate(5));
    var ms: i64 = 1000;
    var beat: u32 = 0;
    for (0..100) |i| { // 10 s: 60 fps for 5 s, then 30 fps
        b.push(ms, beat);
        ms += 100;
        beat += if (i < 49) 6 else 3;
    }
    const r5 = b.rate(5).?;
    try std.testing.expectEqual(@as(u32, 300), r5.fpsX10());
    try std.testing.expectEqual(@as(?u32, 333), r5.frameMsX10());
    try std.testing.expectEqual(@as(u32, 150), r5.missed); // half the 300 VBLs
    const r50 = b.rate(50).?; // all 9.9 s there are
    try std.testing.expectEqual(@as(i64, 9900), r50.ms);
    try std.testing.expectEqual(@as(u32, 448), r50.fpsX10());
    for (0..30) |_| { // hung: 3 s without a frame
        b.push(ms, beat);
        ms += 100;
    }
    try std.testing.expectEqual(@as(i64, 3000), b.stillMs(ms));
    try std.testing.expectEqual(@as(?u32, null), b.rate(2).?.frameMsX10());
}

test "the ring wraps and keeps the newest SLOTS samples" {
    var b = Beats{};
    for (0..SLOTS + 10) |i| b.push(@intCast(i * 100), @intCast(i));
    try std.testing.expectEqual(@as(usize, SLOTS), b.n);
    try std.testing.expectEqual(@as(u32, SLOTS + 9), b.newest().beat);
    try std.testing.expectEqual(@as(i64, (SLOTS - 1) * 100), b.rate(SPAN_S + 10).?.ms);
}
