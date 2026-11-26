// RACER: the per-track race clock (clock.zig, M5 step 4). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const clock = @import("clock.zig");
const data = @import("data.zig");
const fsm = @import("fsm.zig");
const rules = @import("rules.zig");
const session = @import("session.zig");
const trk = @import("trk.zig");

test "the oval keeps freds72's clock: 75 s at the start, 10 s a checkpoint (its estimated lap is under the floors)" {
    const t = try trk.parse(data.oval);
    const c = clock.of(&t);
    try std.testing.expectEqual(@as(u32, 75 * 30), c.start);
    try std.testing.expectEqual(@as(u32, 10 * 30), c.extend);
    try std.testing.expect(c.computed);
    try std.testing.expectEqual(@as(u32, 448), clock.lapLength(&t)); // = tools: the racing line's length, units
    try std.testing.expectEqual(@as(u32, 360), clock.turning(&t)); // one loop
    const r = try rules.Rules.init(&t);
    try std.testing.expectEqual(@as(i32, rules.START_TICKS), r.remaining);
    try std.testing.expectEqual(@as(u32, rules.EXTEND_TICKS), r.extend_ticks);
}

test "a longer lap gets a longer clock: Salt Flats from its line (no clock in its file)" {
    const t = try trk.parse(data.salt);
    const c = clock.of(&t);
    try std.testing.expectEqual(@as(u32, 684), clock.lapLength(&t));
    const p = clock.lapTenths(&t); // (684 x 100 + 15 x 391) / 105 = 707 tenths
    try std.testing.expectEqual(@as(u32, 707), p);
    try std.testing.expectEqual(@as(u32, 107 * 30), c.start); // ceil(1.5 x 70.7)
    try std.testing.expectEqual(@as(u32, 15 * 30), c.extend); // ceil(0.8 x 70.7 / 4)
}

test "the file's clock wins over the computed one, each byte on its own; a checkpoint adds the track's extension" {
    var t = try trk.parse(data.oval);
    t.mood.clock = .{ 200, 0 };
    var c = clock.of(&t);
    try std.testing.expectEqual(@as(u32, 200 * 30), c.start);
    try std.testing.expectEqual(@as(u32, 10 * 30), c.extend);
    t.mood.clock = .{ 90, 25 };
    c = clock.of(&t);
    try std.testing.expect(!c.computed);
    var r = try rules.Rules.init(&t);
    try std.testing.expectEqual(@as(i32, 90 * 30), r.remaining);
    const before = r.remaining;
    try std.testing.expectEqual(rules.Result.checkpoint, r.tick(@as(i32, @intCast(t.checkpoints[0] + 1)) << 16));
    try std.testing.expectEqual(before - 1 + 25 * 30, r.remaining);
}

test "the grid's HUD clock is the track's, and a session's reset keeps it" {
    var t = try trk.parse(data.oval);
    t.mood.clock = .{ 120, 20 };
    var s = try session.Session.init(&t);
    try s.start();
    s.reset();
    try std.testing.expectEqual(fsm.State.grid, s.fsm.state);
    try std.testing.expectEqual(@as(u32, 120 * 30), s.rules.start_ticks);
}
