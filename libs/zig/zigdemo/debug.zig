//! zigdemo debug: the scrub keys, as pure logic on the clock and the draw track.
//!
//! This is TBL's TimeControl (pause, scroll, from/to, restart) as keys for a
//! debug cart. The clock does the seeking, so every key lands through the same
//! jump a timeline replay uses. Drawing the overlay is the cart's job, and
//! formatTime gives it the text.

const std = @import("std");
const clock = @import("clock.zig");
const timeline = @import("timeline.zig");

pub const Key = enum {
    pause,
    back_1s,
    fwd_1s,
    back_10s,
    fwd_10s,
    prev_item,
    next_item,
    mark_a,
    mark_b,
    loop_clear,
};

/// TBL's from/to marks. The loop is on only while both marks are set and a < b.
pub const Scrub = struct {
    mark_a: ?u32 = null,
    mark_b: ?u32 = null,

    /// `items` is the draw track: prev_item and next_item step to its item starts.
    pub fn press(self: *Scrub, clk: *clock.Clock, items: []const timeline.Item, key: Key) void {
        const now = clk.t;
        switch (key) {
            .pause => clk.setPaused(!clk.paused),
            .back_1s => clk.jump(stepMs(now, -1000)),
            .fwd_1s => clk.jump(stepMs(now, 1000)),
            .back_10s => clk.jump(stepMs(now, -10000)),
            .fwd_10s => clk.jump(stepMs(now, 10000)),
            .prev_item => if (timeline.prevDraw(items, now)) |ms| clk.jump(ms),
            .next_item => if (timeline.nextDraw(items, now)) |ms| clk.jump(ms),
            .mark_a => self.mark_a = now,
            .mark_b => self.mark_b = now,
            .loop_clear => {
                self.mark_a = null;
                self.mark_b = null;
            },
        }
        self.applyLoop(clk);
    }

    /// The loop follows the marks, so it is re-derived after every key rather
    /// than set in place: a mark moved past the other one simply turns it off.
    fn applyLoop(self: *const Scrub, clk: *clock.Clock) void {
        const a = self.mark_a orelse return clk.clearLoop();
        const b = self.mark_b orelse return clk.clearLoop();
        if (a < b) clk.setLoop(a, b) else clk.clearLoop();
    }
};

/// "mm:ss.cc", the overlay's time. Errors when buf is too small.
pub fn formatTime(ms: u32, buf: []u8) ![]u8 {
    const s = ms / 1000;
    const cs = (ms % 1000) / 10;
    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}.{d:0>2}", .{ s / 60, s % 60, cs });
}

/// `now` moved by `delta` ms, clamped at 0 (a scrub back never goes before the start).
fn stepMs(now: u32, delta: i32) u32 {
    const v = @as(i64, now) + delta;
    return @intCast(std.math.clamp(v, 0, std.math.maxInt(u32)));
}
