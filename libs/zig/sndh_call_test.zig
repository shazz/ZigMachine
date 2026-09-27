// Native tests for the zg.sndhCall queue (sndh_call.zig): `zig test` this file.
const std = @import("std");
const sc = @import("sndh_call.zig");

test "every call of a frame is kept, in order" {
    var q: sc.Queue = .{};
    try std.testing.expect(q.push("rick.sndh", 0x8009));
    try std.testing.expect(q.push("rick.sndh", 0x8038));
    try std.testing.expectEqual(@as(usize, 2), q.take());
    try std.testing.expectEqual(@as(u32, 0x8009), q.d0At(0));
    try std.testing.expectEqual(@as(u32, 0x8038), q.d0At(1));
    try std.testing.expectEqualStrings("rick.sndh", q.name[0..q.name_len]);
    try std.testing.expectEqual(@as(usize, 0), q.take()); // taken once
}

test "a song request or a stop discards the queued calls" {
    var q: sc.Queue = .{};
    _ = q.push("a.sndh", 1);
    q.clear();
    try std.testing.expectEqual(@as(usize, 0), q.take());
    try std.testing.expectEqual(@as(u32, 0), q.dropped); // superseded, not refused
}

test "a call on another image starts a new queue" {
    var q: sc.Queue = .{};
    _ = q.push("a.sndh", 1);
    _ = q.push("b.sndh", 2);
    try std.testing.expectEqual(@as(usize, 1), q.take());
    try std.testing.expectEqual(@as(u32, 2), q.d0At(0));
    try std.testing.expectEqualStrings("b.sndh", q.name[0..q.name_len]);
}

test "a full queue and a bad name are refused and counted" {
    var q: sc.Queue = .{};
    for (0..sc.CAP) |i| try std.testing.expect(q.push("a.sndh", @intCast(i)));
    try std.testing.expect(!q.push("a.sndh", 99));
    try std.testing.expect(!q.push("", 1));
    try std.testing.expect(!q.push("x" ** (sc.NAME_MAX + 1), 1));
    try std.testing.expectEqual(@as(u32, 3), q.dropped);
    try std.testing.expectEqual(sc.CAP, q.take());
    try std.testing.expectEqual(@as(u32, 0), q.d0At(sc.CAP)); // out of range reads 0
}
