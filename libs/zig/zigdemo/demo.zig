//! zigdemo Demo: the per-frame flow of TBL's player, over a comptime cart type.
//!
//! Demo(Parts, Ctx, tracks): `tracks` is the cart's timeline, comptime so an
//! unsorted item or a part id past the union is a compile error. `Parts` is the
//! cart's part union (part.zig). `Ctx` is the state every part shares: the
//! palette, the buffers, the asset and audio mocks.
//!
//! Per frame, update(source, ctx) moves the clock. A seek or a loop wrap (a
//! discontinuity) replays the load tracks; otherwise gather fires the once items
//! crossed. Then the active parts start, end, and update. render(ctx) draws the
//! active parts in track order: track 0 at the back, a later track over it.

const std = @import("std");
const clock = @import("clock.zig");
const timeline = @import("timeline.zig");
const part = @import("part.zig");

pub fn Demo(comptime Parts: type, comptime Ctx: type, comptime tracks: []const timeline.Track) type {
    comptime checkTracks(Parts, tracks);
    const D = part.Dispatch(Ctx, Parts);
    const N = tracks.len;
    return struct {
        const Self = @This();
        /// Local time is `now - start`: a part's clock starts with its item,
        /// as TBL's scene time did from the first draw.
        const Active = struct { index: usize, start: u32, state: Parts };
        const Sink = struct {
            ctx: *Ctx,

            pub fn once(self: Sink, _: usize, item: timeline.Item) void {
                D.once(self.ctx, item.part, item.arg);
            }
        };

        clock: clock.Clock = .{},
        seen: clock.Reader = .{},
        tl: timeline.Timeline(N) = .{ .tracks = tracks },
        active: [N]?Active = [_]?Active{null} ** N,

        pub fn init() Self {
            return .{};
        }

        pub fn update(self: *Self, source: clock.Source, ctx: *Ctx) void {
            self.clock.update(source);
            const sink = Sink{ .ctx = ctx };
            if (self.seen.changed(&self.clock)) {
                self.tl.jump(self.clock.t, sink);
            } else {
                self.tl.gather(self.clock.t, sink);
            }
            self.sync(ctx);
            const now = self.clock.t;
            for (&self.active) |*slot| {
                if (slot.*) |*a| D.update(&a.state, ctx, now - a.start);
            }
        }

        pub fn render(self: *Self, ctx: *Ctx) void {
            const now = self.clock.t;
            for (&self.active) |*slot| {
                if (slot.*) |*a| D.render(&a.state, ctx, now - a.start);
            }
        }

        /// Ends every active part. The cart calls it when it leaves the demo.
        pub fn deinit(self: *Self, ctx: *Ctx) void {
            for (&self.active) |*slot| {
                if (slot.*) |*a| D.deinit(&a.state, ctx);
                slot.* = null;
            }
        }

        /// Makes each track's active part match its cursor: the old part ends,
        /// and the new one starts with its item's arg.
        fn sync(self: *Self, ctx: *Ctx) void {
            for (&self.active, 0..) |*slot, ti| {
                const want = self.tl.active(ti);
                if (sameIndex(slot.*, want)) continue;
                if (slot.*) |*a| D.deinit(&a.state, ctx);
                slot.* = if (want) |i| start(ti, i, ctx) else null;
            }
        }

        fn start(ti: usize, index: usize, ctx: *Ctx) Active {
            const it = tracks[ti].items[index];
            var state = D.make(it.part);
            D.init(&state, ctx, it.arg);
            return .{ .index = index, .start = it.start_ms, .state = state };
        }

        fn sameIndex(a: ?Active, want: ?usize) bool {
            const have: ?usize = if (a) |x| x.index else null;
            return have == want;
        }
    };
}

/// Refuses at compile time a timeline that is not sorted, or a part id past the union.
fn checkTracks(comptime Parts: type, comptime tracks: []const timeline.Track) void {
    const count = @typeInfo(Parts).@"union".fields.len;
    for (tracks) |tr| {
        timeline.validate(tr.items) catch @compileError("zigdemo: a track's items are not sorted by start_ms");
        for (tr.items) |it| {
            if (it.part >= count) @compileError("zigdemo: an item names a part id past the Parts union");
        }
    }
}
