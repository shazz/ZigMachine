//! Tests for timeline.zig: cursors forward and back, once firing, jump replay,
//! same-start items, the last item, empty tracks, validation, the debug steps.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const tl = @import("timeline.zig");

const Item = tl.Item;

/// Records the once items a gather or jump fires: (track, part, arg).
const Rec = struct {
    buf: [32]struct { track: usize, part: u16, arg: u16 } = undefined,
    n: usize = 0,

    pub fn once(self: *Rec, track: usize, item: Item) void {
        self.buf[self.n] = .{ .track = track, .part = item.part, .arg = item.arg };
        self.n += 1;
    }
};

const draw_items = [_]Item{
    .{ .start_ms = 0, .part = 1, .kind = .draw },
    .{ .start_ms = 1000, .part = 2, .kind = .draw },
    .{ .start_ms = 5000, .part = 3, .kind = .draw },
};
const load_items = [_]Item{
    .{ .start_ms = 100, .part = 10, .kind = .once, .arg = 7 },
    .{ .start_ms = 300, .part = 11, .kind = .once },
    .{ .start_ms = 2000, .part = 12, .kind = .once },
};

test "draw cursor: the item playing is the last draw at or before now" {
    const tracks = [_]tl.Track{.{ .items = &draw_items }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(500, &rec);
    try expectEqual(@as(?usize, 0), t.active(0));
    t.gather(1000, &rec);
    try expectEqual(@as(?usize, 1), t.active(0));
    t.gather(4999, &rec);
    try expectEqual(@as(?usize, 1), t.active(0));
}

test "a draw track before its first item plays nothing" {
    const late = [_]Item{.{ .start_ms = 500, .part = 1, .kind = .draw }};
    const tracks = [_]tl.Track{.{ .items = &late }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(100, &rec);
    try expectEqual(@as(?usize, null), t.active(0));
}

test "a once item fires when crossed forward, and only once" {
    const tracks = [_]tl.Track{.{ .items = &load_items, .replay_once = true }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(50, &rec);
    try expectEqual(@as(usize, 0), rec.n);
    t.gather(100, &rec);
    try expectEqual(@as(usize, 1), rec.n);
    try expectEqual(@as(u16, 10), rec.buf[0].part);
    try expectEqual(@as(u16, 7), rec.buf[0].arg);
    t.gather(200, &rec);
    try expectEqual(@as(usize, 1), rec.n);
}

test "a backward move fires nothing, and crossing forward again fires again" {
    const tracks = [_]tl.Track{.{ .items = &load_items }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(350, &rec);
    try expectEqual(@as(usize, 2), rec.n);
    t.gather(50, &rec);
    try expectEqual(@as(usize, 2), rec.n);
    t.gather(350, &rec);
    try expectEqual(@as(usize, 4), rec.n);
}

test "one big gather fires every once item crossed, in order: a hitch drops none" {
    const tracks = [_]tl.Track{.{ .items = &load_items }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(10_000, &rec);
    try expectEqual(@as(usize, 3), rec.n);
    try expectEqual(@as(u16, 10), rec.buf[0].part);
    try expectEqual(@as(u16, 11), rec.buf[1].part);
    try expectEqual(@as(u16, 12), rec.buf[2].part);
}

test "two items at the same start both fire, in array order; the later draw wins" {
    const same = [_]Item{
        .{ .start_ms = 100, .part = 1, .kind = .draw },
        .{ .start_ms = 100, .part = 2, .kind = .draw },
        .{ .start_ms = 100, .part = 20, .kind = .once },
        .{ .start_ms = 100, .part = 21, .kind = .once },
    };
    const tracks = [_]tl.Track{.{ .items = &same }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(100, &rec);
    try expectEqual(@as(usize, 2), rec.n);
    try expectEqual(@as(u16, 20), rec.buf[0].part);
    try expectEqual(@as(u16, 21), rec.buf[1].part);
    try expectEqual(@as(?usize, 1), t.active(0));
}

test "the last item: after it, its draw keeps playing and its once has fired" {
    const tracks = [_]tl.Track{ .{ .items = &draw_items }, .{ .items = &load_items } };
    var t = try tl.Timeline(2).init(&tracks);
    var rec = Rec{};
    t.gather(999_999, &rec);
    try expectEqual(@as(?usize, 2), t.active(0));
    try expectEqual(@as(usize, 3), rec.n);
}

test "a once item never plays as the draw: a draw cursor steps over it" {
    const mixed = [_]Item{
        .{ .start_ms = 0, .part = 1, .kind = .draw },
        .{ .start_ms = 50, .part = 9, .kind = .once },
    };
    const tracks = [_]tl.Track{.{ .items = &mixed }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(60, &rec);
    try expectEqual(@as(?usize, 0), t.active(0));
}

test "an empty track is inert" {
    const none = [_]Item{};
    const tracks = [_]tl.Track{.{ .items = &none, .replay_once = true }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.gather(1000, &rec);
    t.jump(1000, &rec);
    try expectEqual(@as(usize, 0), rec.n);
    try expectEqual(@as(?usize, null), t.active(0));
}

test "jump: draw cursors move without firing; a load track replays its once items up to now" {
    const tracks = [_]tl.Track{ .{ .items = &draw_items }, .{ .items = &load_items, .replay_once = true } };
    var t = try tl.Timeline(2).init(&tracks);
    var rec = Rec{};
    t.jump(1500, &rec);
    try expectEqual(@as(?usize, 1), t.active(0));
    try expectEqual(@as(usize, 2), rec.n); // parts 10 and 11, not 12 (at 2000)
    try expectEqual(@as(u16, 10), rec.buf[0].part);
    try expectEqual(@as(u16, 11), rec.buf[1].part);
    for (rec.buf[0..rec.n]) |r| try expectEqual(@as(usize, 1), r.track);
}

test "jump backward past a once item: the load is not replayed, and the draw steps back" {
    const tracks = [_]tl.Track{ .{ .items = &draw_items }, .{ .items = &load_items, .replay_once = true } };
    var t = try tl.Timeline(2).init(&tracks);
    var rec = Rec{};
    t.gather(2500, &rec);
    try expectEqual(@as(usize, 3), rec.n);
    rec.n = 0;
    t.jump(50, &rec);
    try expectEqual(@as(usize, 0), rec.n);
    try expectEqual(@as(?usize, 0), t.active(0));
    t.gather(120, &rec); // a forward move from the jump fires the item it crosses
    try expectEqual(@as(usize, 1), rec.n);
}

test "jump to 0 on a track whose first item starts later replays nothing" {
    const tracks = [_]tl.Track{.{ .items = &load_items, .replay_once = true }};
    var t = try tl.Timeline(1).init(&tracks);
    var rec = Rec{};
    t.jump(0, &rec);
    try expectEqual(@as(usize, 0), rec.n);
}

test "init refuses unsorted items and accepts equal starts" {
    const bad = [_]Item{
        .{ .start_ms = 200, .part = 1, .kind = .draw },
        .{ .start_ms = 100, .part = 2, .kind = .draw },
    };
    const tracks = [_]tl.Track{.{ .items = &bad }};
    try std.testing.expectError(error.Unsorted, tl.Timeline(1).init(&tracks));
    const ok = [_]Item{
        .{ .start_ms = 100, .part = 1, .kind = .draw },
        .{ .start_ms = 100, .part = 2, .kind = .draw },
    };
    try tl.validate(&ok);
}

test "localMs is now minus the item's start" {
    const it = Item{ .start_ms = 1000, .part = 0, .kind = .draw };
    try expectEqual(@as(u32, 250), tl.localMs(it, 1250));
    try expectEqual(@as(u32, 0), tl.localMs(it, 1000));
}

test "nextDraw and prevDraw skip once items and stop at the ends" {
    try expectEqual(@as(?u32, 1000), tl.nextDraw(&draw_items, 0));
    try expectEqual(@as(?u32, 5000), tl.nextDraw(&draw_items, 1000));
    try expectEqual(@as(?u32, null), tl.nextDraw(&draw_items, 5000));
    try expectEqual(@as(?u32, 1000), tl.prevDraw(&draw_items, 5000));
    try expectEqual(@as(?u32, 0), tl.prevDraw(&draw_items, 1000));
    try expectEqual(@as(?u32, null), tl.prevDraw(&draw_items, 0));
}
