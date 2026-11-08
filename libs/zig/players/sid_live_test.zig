// Native tests for sid_live.zig: writes land at the engine sample of their stamp, the queue's own
// commands say themselves back as events, and an unknown address is refused.
const std = @import("std");
const live_mod = @import("sid_live.zig");
const Live = live_mod.Live;
const Entry = live_mod.Entry;

fn w(t: u32, addr: u32, value: u32) Entry {
    return .{ .t = t, .addr = addr, .value = value };
}

test "a write waits ceil(d / 2) engine samples, then is due" {
    var l: Live = .{};
    l.reset(1000);
    _ = l.push(&.{ w(0, live_mod.OP_RESET, 6581), w(7, 0xD418, 15) });
    try std.testing.expect(l.take() == null);
    try std.testing.expectEqual(@as(u32, 500), l.chunk(4096)); // the lead, in engine samples
    l.advance(500);
    try std.testing.expectEqual(Live.Do.reset, l.classify(l.take().?));
    try std.testing.expectEqual(@as(u32, 4), l.chunk(4096)); // 7 output samples ahead: 4 engine samples
    l.advance(3);
    try std.testing.expect(l.take() == null);
    l.advance(1);
    try std.testing.expectEqual(Live.Do.sid, l.classify(l.take().?));
    try std.testing.expectEqual(@as(u32, 128), l.chunk(128)); // nothing waits: the whole chunk
}

test "reset and mark come back as events with their stamps; a bad address is refused" {
    var l: Live = .{};
    l.reset(256);
    _ = l.push(&.{ w(100, live_mod.OP_RESET, 8580), w(300, live_mod.OP_MARK, 42), w(300, 0xDFF096, 1) });
    l.advance(1000);
    while (l.take()) |e| _ = l.classify(e);
    try std.testing.expectEqual(@as(u32, 2), l.ev_count);
    try std.testing.expectEqual(@as(u32, @intFromEnum(live_mod.Kind.reset)), l.events[0].kind);
    try std.testing.expectEqual(@as(u32, 8580), l.events[0].arg);
    try std.testing.expectEqual(@as(u32, 300), l.events[1].t);
    try std.testing.expectEqual(@as(u32, 42), l.events[1].arg);
    try std.testing.expectEqual(@as(u32, 1), l.refused);
    try std.testing.expectEqual(@as(u32, 2), l.applied);
    try std.testing.expect(l.engine_on);
}

test "the position is on the cart's clock, and a late batch re-anchors and says so" {
    var l: Live = .{};
    l.reset(1000);
    try std.testing.expectEqual(@as(u32, 0), l.position());
    _ = l.push(&.{w(5000, 0xD400, 1)});
    try std.testing.expectEqual(@as(u32, 4000), l.position()); // a lead before the first stamp
    l.advance(2000); // 4000 output samples: past the next batch's stamp
    _ = l.take();
    _ = l.push(&.{w(6000, 0xD401, 2)}); // its stamp is behind: late
    try std.testing.expectEqual(@as(u32, 1), l.ev_count);
    try std.testing.expectEqual(@as(u32, @intFromEnum(live_mod.Kind.resync)), l.events[0].kind);
    try std.testing.expectEqual(@as(u32, 5000), l.position()); // re-anchored a lead ahead of it
}

test "a full queue drops the rest, counted and said once a batch" {
    var l: Live = .{};
    l.reset(1000);
    var batch: [live_mod.Queue.CAP_N + 3]Entry = undefined;
    for (&batch, 0..) |*e, i| e.* = w(@intCast(i), 0xD400, 0);
    try std.testing.expectEqual(live_mod.Queue.CAP_N, l.push(&batch));
    try std.testing.expectEqual(@as(u32, 3), l.queue.dropped);
    try std.testing.expectEqual(@as(u32, @intFromEnum(live_mod.Kind.dropped)), l.events[0].kind);
    try std.testing.expectEqual(@as(u32, 3), l.events[0].arg);
}
