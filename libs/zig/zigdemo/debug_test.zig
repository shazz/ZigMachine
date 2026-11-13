//! Tests for debug.zig: the scrub keys on the clock and the draw track, the A-B
//! marks, the clamp at 0, and the time text.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const clock = @import("clock.zig");
const timeline = @import("timeline.zig");
const debug = @import("debug.zig");

const draw = [_]timeline.Item{
    .{ .start_ms = 0, .part = 0, .kind = .draw },
    .{ .start_ms = 1000, .part = 1, .kind = .draw },
    .{ .start_ms = 3000, .part = 2, .kind = .once },
    .{ .start_ms = 5000, .part = 3, .kind = .draw },
};

test "pause toggles the clock's pause" {
    var c = clock.Clock{};
    var s = debug.Scrub{};
    s.press(&c, &draw, .pause);
    try std.testing.expect(c.paused);
    s.press(&c, &draw, .pause);
    try std.testing.expect(!c.paused);
}

test "1 s and 10 s steps move t both ways" {
    var c = clock.Clock{ .t = 2000 };
    var s = debug.Scrub{};
    s.press(&c, &draw, .fwd_1s);
    try expectEqual(@as(u32, 3000), c.t);
    s.press(&c, &draw, .back_10s);
    try expectEqual(@as(u32, 0), c.t);
    s.press(&c, &draw, .fwd_10s);
    try expectEqual(@as(u32, 10000), c.t);
}

test "a step back never goes before 0" {
    var c = clock.Clock{ .t = 500 };
    var s = debug.Scrub{};
    s.press(&c, &draw, .back_1s);
    try expectEqual(@as(u32, 0), c.t);
}

test "next and previous item step to draw starts; at the ends they do nothing" {
    var c = clock.Clock{ .t = 0 };
    var s = debug.Scrub{};
    s.press(&c, &draw, .next_item);
    try expectEqual(@as(u32, 1000), c.t);
    s.press(&c, &draw, .next_item);
    try expectEqual(@as(u32, 5000), c.t);
    s.press(&c, &draw, .next_item);
    try expectEqual(@as(u32, 5000), c.t);
    s.press(&c, &draw, .prev_item);
    try expectEqual(@as(u32, 1000), c.t);
    s.press(&c, &draw, .prev_item);
    s.press(&c, &draw, .prev_item);
    try expectEqual(@as(u32, 0), c.t);
}

test "marks a and b set a loop; a loop is on only while a < b" {
    var c = clock.Clock{ .t = 1000 };
    var s = debug.Scrub{};
    s.press(&c, &draw, .mark_a);
    try std.testing.expect(c.loop == null);
    c.t = 2000;
    s.press(&c, &draw, .mark_b);
    try expectEqual(@as(u32, 1000), c.loop.?.a);
    try expectEqual(@as(u32, 2000), c.loop.?.b);
    c.t = 2500;
    s.press(&c, &draw, .mark_a);
    try std.testing.expect(c.loop == null); // a moved past b: no loop
}

test "loop_clear forgets the marks and the loop" {
    var c = clock.Clock{ .t = 1000 };
    var s = debug.Scrub{ .mark_a = 1000, .mark_b = 2000 };
    s.press(&c, &draw, .loop_clear);
    try std.testing.expect(c.loop == null);
    try std.testing.expect(s.mark_a == null and s.mark_b == null);
}

test "formatTime is mm:ss.cc, and a short buffer is an error" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("01:32.17", try debug.formatTime(92170, &buf));
    try std.testing.expectEqualStrings("00:00.00", try debug.formatTime(0, &buf));
    var small: [4]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, debug.formatTime(92170, &small));
}
