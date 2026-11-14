//! Tests for assets.zig (the mock): unknown ids, the queue, the two slots, release,
//! the queue's bound.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const assets = @import("assets.zig");

test "an unknown id is refused" {
    const known = [_]u16{ 1, 2 };
    var a = assets.Assets{ .known = &known };
    try std.testing.expectError(error.UnknownAsset, a.request(9));
}

test "a request is ready only after update loads it" {
    const known = [_]u16{ 1, 2 };
    var a = assets.Assets{ .known = &known };
    try a.request(1);
    try std.testing.expect(!a.ready(1));
    a.update();
    try std.testing.expect(a.ready(1));
}

test "a repeated request is a no-op: loaded or queued, it takes no second place" {
    const known = [_]u16{ 1, 2 };
    var a = assets.Assets{ .known = &known };
    try a.request(1);
    try a.request(1);
    try expectEqual(@as(usize, 1), a.queued);
    a.update();
    try a.request(1);
    try expectEqual(@as(usize, 0), a.queued);
}

test "two slots hold two assets; a third waits until a release frees one" {
    const known = [_]u16{ 1, 2, 3 };
    var a = assets.Assets{ .known = &known };
    try a.request(1);
    try a.request(2);
    try a.request(3);
    a.update();
    try std.testing.expect(a.ready(1) and a.ready(2));
    try std.testing.expect(!a.ready(3));
    a.release(1);
    a.update();
    try std.testing.expect(!a.ready(1));
    try std.testing.expect(a.ready(3));
}

test "the queue is bounded: a ninth pending request is refused" {
    const known = [_]u16{ 0, 1, 2, 3, 4, 5, 6, 7, 8 };
    var a = assets.Assets{ .known = &known };
    for (known[0..assets.queue_max]) |id| try a.request(id);
    try std.testing.expectError(error.QueueFull, a.request(8));
}

test "releasing an id that is not loaded changes nothing" {
    const known = [_]u16{1};
    var a = assets.Assets{ .known = &known };
    try a.request(1);
    a.update();
    a.release(7);
    try std.testing.expect(a.ready(1));
}
