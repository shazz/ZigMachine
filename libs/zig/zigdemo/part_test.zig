//! Tests for part.zig: the tag is the id, the hooks are optional, dispatch reaches the
//! active variant, a once item reaches its hook, a transition renders two parts.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const part = @import("part.zig");

const Ctx = struct {
    inits: u32 = 0,
    updates: u32 = 0,
    renders: u32 = 0,
    deinits: u32 = 0,
    loads: u32 = 0,
    last_t: u32 = 0,
    last_arg: u16 = 0,
};

/// A part with every hook.
const Fade = struct {
    arg: u16 = 0,

    pub fn init(self: *Fade, ctx: *Ctx, arg: u16) void {
        self.arg = arg;
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

/// A part with only the required hooks: init, deinit and once are absent.
const Bar = struct {
    pub fn update(_: *Bar, ctx: *Ctx, t: u32) void {
        ctx.updates += 10;
        ctx.last_t = t;
    }

    pub fn render(_: *Bar, ctx: *Ctx, _: u32) void {
        ctx.renders += 10;
    }
};

/// A transition: renders its two parts, as the crossfades in a timeline do.
const Cross = struct {
    a: Fade = .{},
    b: Bar = .{},

    pub fn update(self: *Cross, ctx: *Ctx, t: u32) void {
        self.a.update(ctx, t);
        self.b.update(ctx, t);
    }

    pub fn render(self: *Cross, ctx: *Ctx, t: u32) void {
        self.a.render(ctx, t);
        self.b.render(ctx, t);
    }
};

const Parts = union(enum) { fade: Fade, bar: Bar, cross: Cross };
const D = part.Dispatch(Ctx, Parts);

test "the tag order is the part id, and count is the number of variants" {
    try expectEqual(@as(usize, 3), D.count);
    try std.testing.expectEqual(std.meta.Tag(Parts).fade, std.meta.activeTag(D.make(0)));
    try std.testing.expectEqual(std.meta.Tag(Parts).bar, std.meta.activeTag(D.make(1)));
    try std.testing.expectEqual(std.meta.Tag(Parts).cross, std.meta.activeTag(D.make(2)));
}

test "init reaches a part that has it, with the item's arg" {
    var ctx = Ctx{};
    var p = D.make(0);
    D.init(&p, &ctx, 42);
    try expectEqual(@as(u32, 1), ctx.inits);
    try expectEqual(@as(u16, 42), ctx.last_arg);
    try expectEqual(@as(u16, 42), p.fade.arg);
}

test "init of a part without the hook does nothing and is not an error" {
    var ctx = Ctx{};
    var p = D.make(1);
    D.init(&p, &ctx, 9);
    try expectEqual(@as(u32, 0), ctx.inits);
}

test "update and render go to the active variant, with its time" {
    var ctx = Ctx{};
    var f = D.make(0);
    D.update(&f, &ctx, 42);
    try expectEqual(@as(u32, 1), ctx.updates);
    try expectEqual(@as(u32, 42), ctx.last_t);
    D.render(&f, &ctx, 42);
    try expectEqual(@as(u32, 1), ctx.renders);
    var b = D.make(1);
    D.update(&b, &ctx, 7);
    try expectEqual(@as(u32, 11), ctx.updates);
    try expectEqual(@as(u32, 7), ctx.last_t);
}

test "a part keeps its state between frames" {
    var ctx = Ctx{};
    var p = D.make(0);
    D.init(&p, &ctx, 5);
    D.update(&p, &ctx, 1);
    D.update(&p, &ctx, 2);
    try expectEqual(@as(u16, 5), p.fade.arg);
    try expectEqual(@as(u32, 2), ctx.updates);
}

test "deinit reaches a part that has it; a part without it is left alone" {
    var ctx = Ctx{};
    var f = D.make(0);
    D.deinit(&f, &ctx);
    try expectEqual(@as(u32, 1), ctx.deinits);
    var b = D.make(1);
    D.deinit(&b, &ctx);
    try expectEqual(@as(u32, 1), ctx.deinits);
}

test "once runs the load hook of its part, and a part without one is a no-op" {
    var ctx = Ctx{};
    D.once(&ctx, 0, 7);
    try expectEqual(@as(u32, 7), ctx.loads);
    D.once(&ctx, 1, 7);
    try expectEqual(@as(u32, 7), ctx.loads);
}

test "a transition renders both of its parts" {
    var ctx = Ctx{};
    var c = D.make(2);
    D.render(&c, &ctx, 0);
    try expectEqual(@as(u32, 11), ctx.renders); // Fade's 1 and Bar's 10
}
