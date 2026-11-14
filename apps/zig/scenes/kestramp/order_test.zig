const std = @import("std");
const Order = @import("order.zig").Order;

test "next steps through name order and ends without repeat" {
    var o = Order{};
    try std.testing.expectEqual(@as(?usize, 0), o.next(3, null));
    try std.testing.expectEqual(@as(?usize, 1), o.next(3, 0));
    try std.testing.expectEqual(@as(?usize, 2), o.next(3, 1));
    try std.testing.expectEqual(@as(?usize, null), o.next(3, 2));
}

test "repeat wraps next and prev at the ends" {
    var o = Order{ .repeat = true };
    try std.testing.expectEqual(@as(?usize, 0), o.next(3, 2));
    try std.testing.expectEqual(@as(?usize, 2), o.prev(3, 0));
    try std.testing.expectEqual(@as(?usize, 1), o.prev(3, 2));
}

test "prev from the first track without repeat stays on the first" {
    var o = Order{};
    try std.testing.expectEqual(@as(?usize, 0), o.prev(3, 0));
    try std.testing.expectEqual(@as(?usize, 0), o.prev(3, null));
}

test "an empty list has no next and no prev" {
    var o = Order{ .repeat = true, .shuffle = true };
    try std.testing.expectEqual(@as(?usize, null), o.next(0, null));
    try std.testing.expectEqual(@as(?usize, null), o.prev(0, null));
}

test "shuffle plays every track once, then the list ends without repeat" {
    var o = Order{ .shuffle = true };
    var seen = [_]bool{false} ** 4;
    var cur: ?usize = null;
    for (0..4) |_| {
        const i = o.next(4, cur) orelse return error.EndedEarly;
        try std.testing.expect(!seen[i]);
        seen[i] = true;
        o.markStarted(i);
        cur = i;
    }
    try std.testing.expectEqual(@as(?usize, null), o.next(4, cur));
}

test "shuffle with repeat starts a new round" {
    var o = Order{ .shuffle = true, .repeat = true };
    for (0..2) |_| {
        const i = o.next(2, null) orelse return error.NoRound;
        o.markStarted(i);
    }
    const again = o.next(2, 0);
    try std.testing.expect(again != null);
}
