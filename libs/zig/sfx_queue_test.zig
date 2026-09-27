// Native tests for the zg.sfxPlay / sfxStop / ymWrite queue (sfx_queue.zig).
const std = @import("std");
const q = @import("sfx_queue.zig");

const pcm = [_]u8{ 1, 2, 3, 4 };

test "a frame's commands reach the host in order, then the queue is empty" {
    var s: q.Queue = .{};
    try std.testing.expect(s.ym(8, 16));
    try std.testing.expect(s.play(&pcm, 12517, true));
    try std.testing.expect(s.stop(true));
    try std.testing.expectEqual(@as(usize, 3), s.take());
    try std.testing.expectEqual(@as(u8, 3), s.entries[0].op);
    try std.testing.expectEqual(@as(u8, 8), s.entries[0].a);
    try std.testing.expectEqual(@as(u8, 16), s.entries[0].b);
    const p = s.entries[1];
    try std.testing.expectEqual(@as(u8, 1), p.op);
    try std.testing.expectEqual(@as(u8, 1), p.a);
    try std.testing.expectEqual(@as(u32, 4), p.len);
    try std.testing.expectEqual(@as(u32, 12517), p.rate);
    try std.testing.expectEqual(@as(u32, @truncate(@intFromPtr(&pcm))), p.ptr);
    try std.testing.expectEqual(@as(u8, 2), s.entries[2].op);
    try std.testing.expectEqual(@as(usize, 0), s.take());
    try std.testing.expectEqual(@as(u32, 0), s.dropped);
}

test "the entry is the 16-byte layout the host reads" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(q.Entry));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(q.Entry, "ptr"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(q.Entry, "len"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(q.Entry, "rate"));
}

test "a full queue refuses and counts; the next frame takes commands again" {
    var s: q.Queue = .{};
    for (0..q.CAP) |_| try std.testing.expect(s.ym(7, 0));
    try std.testing.expect(!s.stop(false));
    try std.testing.expectEqual(@as(u32, 1), s.dropped);
    try std.testing.expectEqual(q.CAP, s.take());
    try std.testing.expect(s.stop(false));
}

test "empty or oversized PCM, a rate out of range and register 14+ are refused and counted" {
    var s: q.Queue = .{};
    try std.testing.expect(!s.play(&.{}, 12517, false));
    const big = [_]u8{0} ** (q.PCM_MAX + 1);
    try std.testing.expect(!s.play(&big, 12517, false));
    try std.testing.expect(!s.play(&pcm, 0, false));
    try std.testing.expect(!s.play(&pcm, q.RATE_MAX + 1, false));
    try std.testing.expect(!s.ym(14, 0));
    try std.testing.expectEqual(@as(u32, 5), s.dropped);
    try std.testing.expectEqual(@as(usize, 0), s.take());
}
