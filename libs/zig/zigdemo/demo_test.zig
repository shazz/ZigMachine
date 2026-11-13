//! Tests for demo.zig: the per-frame flow over a small cart. Part starts and ends
//! with the draw cursor, local time, once items on the load track, a seek replays
//! the loads, a seek back does not un-load, deinit ends what is active.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const clock = @import("clock.zig");
const timeline = @import("timeline.zig");
const part = @import("part.zig");
const demo = @import("demo.zig");

const Ctx = struct {
    inits: u32 = 0,
    deinits: u32 = 0,
    loads: u32 = 0,
    updates: u32 = 0,
    renders: u32 = 0,
    last_t: u32 = 0,
    last_arg: u16 = 0,
};

const Fade = struct {
    pub fn init(_: *Fade, ctx: *Ctx, arg: u16) void {
        ctx.inits += 1;
        ctx.last_arg = arg;
    }

    pub fn update(_: *Fade, ctx: *Ctx, t: u32) void {
        ctx.updates += 1;
        ctx.last_t = t;
    }

    pub fn render(_: *Fade, ctx: *Ctx, _: u32) void {
        ctx.renders += 1;
    }

    pub fn deinit(_: *Fade, ctx: *Ctx) void {
        ctx.deinits += 1;
    }

    pub fn once(ctx: *Ctx, arg: u16) void {
        ctx.loads += arg;
    }
};

const Bar = struct {
    pub fn update(_: *Bar, ctx: *Ctx, t: u32) void {
        ctx.updates += 10;
        ctx.last_t = t;
    }

    pub fn render(_: *Bar, ctx: *Ctx, _: u32) void {
        ctx.renders += 10;
    }
};

const Parts = union(enum) { fade: Fade, bar: Bar };

const draw_items = [_]timeline.Item{
    .{ .start_ms = 0, .part = 0, .kind = .draw, .arg = 5 },
    .{ .start_ms = 1000, .part = 1, .kind = .draw },
};
const load_items = [_]timeline.Item{
    .{ .start_ms = 100, .part = 0, .kind = .once, .arg = 3 },
    .{ .start_ms = 2000, .part = 0, .kind = .once, .arg = 4 },
};
const cart_tracks = [_]timeline.Track{
    .{ .items = &draw_items },
    .{ .items = &load_items, .replay_once = true },
};

const Demo = demo.Demo(Parts, Ctx, &cart_tracks);

test "the first draw starts its part with the item's arg, and updates it at local time" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.update(.{ .song_ms = 0 }, &ctx);
    try expectEqual(@as(u32, 1), ctx.inits);
    try expectEqual(@as(u16, 5), ctx.last_arg);
    try expectEqual(@as(u32, 1), ctx.updates);
    d.render(&ctx);
    try expectEqual(@as(u32, 1), ctx.renders);
}

test "playing forward fires a load once, and the next draw ends the old part and starts the new" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.update(.{ .song_ms = 0 }, &ctx);
    d.update(.{ .song_ms = 1200 }, &ctx);
    try expectEqual(@as(u32, 3), ctx.loads);
    try expectEqual(@as(u32, 1), ctx.deinits);
    try expectEqual(@as(u32, 200), ctx.last_t); // the bar's local time: 1200 - its start 1000
}

test "a seek back to the start restarts the first part, and does not fire the loads again" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.update(.{ .song_ms = 0 }, &ctx);
    d.update(.{ .song_ms = 1200 }, &ctx);
    d.clock.jump(50);
    d.update(.{ .song_ms = 1200 }, &ctx);
    try expectEqual(@as(u32, 2), ctx.inits);
    try expectEqual(@as(u32, 50), ctx.last_t);
    try expectEqual(@as(u32, 3), ctx.loads);
}

test "a seek forward replays the load track up to the new time: the same assets as playing there" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.update(.{ .song_ms = 0 }, &ctx);
    d.clock.jump(2500);
    d.update(.{ .song_ms = 0 }, &ctx);
    try expectEqual(@as(u32, 7), ctx.loads); // 3 (at 100) and 4 (at 2000), each once
    try expectEqual(@as(u32, 2500 - 1000), ctx.last_t);
}

test "a seek before any load replays nothing" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.clock.jump(50);
    d.update(.{ .song_ms = 0 }, &ctx);
    try expectEqual(@as(u32, 0), ctx.loads);
}

test "deinit ends the active part once and leaves nothing active" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.update(.{ .song_ms = 0 }, &ctx);
    d.deinit(&ctx);
    try expectEqual(@as(u32, 1), ctx.deinits);
    d.render(&ctx);
    try expectEqual(@as(u32, 0), ctx.renders);
}

test "a paused clock holds the part's time and still runs its update" {
    var ctx = Ctx{};
    var d = Demo.init();
    d.update(.{ .song_ms = 0 }, &ctx);
    d.update(.{ .song_ms = 500 }, &ctx);
    d.clock.setPaused(true);
    d.update(.{ .song_ms = 900 }, &ctx);
    try expectEqual(@as(u32, 500), ctx.last_t);
    try expectEqual(@as(u32, 3), ctx.updates);
}
