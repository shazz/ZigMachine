// The screenshot's thread (app_shot.zig): the copy out of the cart window (shot_grab.zig, the
// cart frozen for the copy only) and the PNG encode (shot_png.zig), off glass's loop, which never
// waits on it: start() refuses while a shot is under way, poll() only looks at a flag. The card
// write is the main thread's (app_shot.tick), as every other card write is. Shaped as wifi_worker.
const std = @import("std");
const grab = @import("shot_grab.zig");
const png = @import("shot_png.zig");

pub const Fail = grab.Error || png.Error || error{NoThread};

pub const Result = union(enum) {
    png: []u8, // the file, owned by the worker's allocator; the taker frees it
    fail: Fail,
};

pub const Worker = struct {
    gpa: std.mem.Allocator,
    env: grab.Env,
    desk: bool = false,
    res: Result = .{ .fail = error.NoThread },
    frozen_ms: i64 = 0, // the last shot's stall of the cart (shot_grab.Shot.frozen_ms), for the log
    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = .init(false),

    /// Shoot on the thread; error.Busy while the last shot runs. `desk`: the cart shows the desk mode.
    pub fn start(self: *Worker, desk: bool) error{ Busy, NoThread }!void {
        if (self.thread != null) return error.Busy;
        self.desk = desk;
        self.done.store(false, .release);
        self.thread = std.Thread.spawn(.{}, body, .{self}) catch return error.NoThread;
    }

    fn body(self: *Worker) void {
        self.res = shoot(self.gpa, self.env, self.desk, &self.frozen_ms);
        self.done.store(true, .release);
    }

    pub fn busy(self: *const Worker) bool {
        return self.thread != null;
    }

    /// The finished shot (the caller owns a .png), or null while it runs or none ran.
    pub fn poll(self: *Worker) ?Result {
        const t = self.thread orelse return null;
        if (!self.done.load(.acquire)) return null;
        t.join();
        self.thread = null;
        defer self.res = .{ .fail = error.NoThread }; // handed over: deinit must not free it too
        return self.res;
    }

    /// Waits for a shot under way (glass exiting, a test's end) and drops a file nobody took.
    pub fn deinit(self: *Worker) void {
        if (self.thread) |t| t.join();
        self.thread = null;
        if (self.res == .png) self.gpa.free(self.res.png);
        self.res = .{ .fail = error.NoThread };
    }
};

/// One shot, start to file bytes.
pub fn shoot(gpa: std.mem.Allocator, env: grab.Env, desk: bool, frozen_ms: *i64) Result {
    const s = grab.grab(gpa, env, desk) catch |e| return .{ .fail = e };
    defer s.deinit(gpa);
    frozen_ms.* = s.frozen_ms;
    const img: png.Image = if (s.desk)
        .{ .w = s.w, .h = s.h, .kind = .indexed, .px = s.px, .pal = &s.pal }
    else
        .{ .w = s.w, .h = s.h, .kind = .rgb, .px = s.px };
    const file = png.encode(gpa, img) catch |e| return .{ .fail = e };
    return .{ .png = file };
}
