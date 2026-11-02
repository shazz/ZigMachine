// Native tests for cart_paula_queue.zig: the cart's writes land at their own
// sample, a lead after the first batch, and a late or runaway clock re-anchors.
const std = @import("std");
const q_mod = @import("cart_paula_queue.zig");
const Queue = q_mod.Queue;
const Entry = q_mod.Entry;

fn e(t: u32, value: u32) Entry {
    return .{ .t = t, .addr = 0xDFF096, .value = value };
}

test "the first batch anchors a lead ahead, and writes keep their spacing" {
    var q: Queue = .{};
    q.reset(1000);
    q.advance(5000); // the audio side has rendered a while before the claim's first write
    try std.testing.expectEqual(@as(u32, 3), q.push(&.{ e(70_000, 1), e(70_100, 2), e(70_350, 3) }));
    try std.testing.expectEqual(@as(u32, 1000), q.untilNext(4096));
    try std.testing.expect(q.due() == null);
    q.advance(1000);
    try std.testing.expectEqual(@as(u32, 1), q.due().?.value);
    try std.testing.expectEqual(@as(u32, 100), q.untilNext(4096));
    q.advance(100);
    try std.testing.expectEqual(@as(u32, 2), q.due().?.value);
    try std.testing.expectEqual(@as(u32, 250), q.untilNext(4096));
    try std.testing.expectEqual(@as(u32, 0), q.resyncs);
}

test "a batch that keeps time is not re-anchored" {
    var q: Queue = .{};
    q.reset(1000);
    _ = q.push(&.{e(0, 1)});
    q.advance(735);
    _ = q.push(&.{e(735, 2)}); // a frame later on both clocks
    try std.testing.expectEqual(@as(u32, 1000), q.untilNext(4096) + 735);
    try std.testing.expectEqual(@as(u32, 0), q.resyncs);
}

test "a late batch re-anchors a lead ahead and is counted" {
    var q: Queue = .{};
    q.reset(1000);
    _ = q.push(&.{e(0, 1)});
    q.advance(1000);
    _ = q.due();
    q.advance(3000); // the cart stalled: its next write would land 2000 samples in the past
    _ = q.push(&.{e(1000, 2)});
    try std.testing.expectEqual(@as(u32, 1), q.resyncs);
    try std.testing.expectEqual(@as(u32, 1000), q.untilNext(4096));
}

test "a clock far ahead re-anchors; the clock may wrap" {
    var q: Queue = .{};
    q.reset(1000);
    _ = q.push(&.{e(0xFFFF_FF00, 1)});
    q.advance(1000);
    try std.testing.expectEqual(@as(u32, 1), q.due().?.value);
    _ = q.push(&.{e(0x0000_0100, 2)}); // 512 samples later, across the wrap
    try std.testing.expectEqual(@as(u32, 512), q.untilNext(4096));
    _ = q.push(&.{e(0x0100_0000, 3)}); // a jump of millions: queued behind, and counted
    try std.testing.expectEqual(@as(u32, 1), q.resyncs);
}

test "a full queue drops the rest of a batch and counts it" {
    var q: Queue = .{};
    q.reset(1000);
    var big: [q_mod.CAP + 5]Entry = undefined;
    for (&big, 0..) |*x, i| x.* = e(@intCast(i), 0);
    try std.testing.expectEqual(q_mod.CAP, q.push(&big));
    try std.testing.expectEqual(@as(u32, 5), q.dropped);
}

test "the lead is clamped" {
    var q: Queue = .{};
    q.reset(1);
    try std.testing.expectEqual(q_mod.LEAD_MIN, q.lead);
    q.reset(1 << 30);
    try std.testing.expectEqual(q_mod.LEAD_MAX, q.lead);
}
