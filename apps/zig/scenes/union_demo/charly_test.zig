// Charly's physics and the door check, pinned to a trace of the ORIGINAL remake
// run in Chrome (melonJS 0.9.8, one rAF per step; ref frame numbers in comments).
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const c = @import("charly.zig");
const doors = @import("doors.zig");

// The real collision layer, looked up like melonJS's getTile (~~ truncation).
const Map = struct {
    cells: []const u8 = @embedFile("../../assets/screens/union_demo/collision.dat"),
    pub fn cellAt(self: *const Map, px: f32, py: f32) ?u8 {
        const col = @trunc(px / 32);
        const row = @trunc(py / 16);
        if (col < 0 or row < 0 or col >= 175 or row >= 25) return null;
        return self.cells[@as(usize, @intFromFloat(row)) * 175 + @as(usize, @intFromFloat(col))];
    }
};
const map = Map{};

fn run(ch: *c.Charly, in: c.Input, n: usize) void {
    for (0..n) |_| ch.update(in, &map);
}

test "walking right accelerates to 5 px a frame and coasts to a stop" {
    var ch: c.Charly = undefined;
    ch.init(268, 180);
    run(&ch, .{ .right = true }, 1);
    try expectEqual(@as(f32, 272.5), ch.x); // ref f60: vx 4.5
    run(&ch, .{ .right = true }, 69);
    try expectEqual(@as(f32, 617.5), ch.x); // ref f129
    try expectEqual(@as(f32, 5), ch.vx);
    run(&ch, .{}, 1);
    try expectEqual(@as(f32, 622), ch.x); // ref f130: friction 0.5
    run(&ch, .{}, 9);
    try expectEqual(@as(f32, 640), ch.x); // ref f139
    try expectEqual(@as(f32, 0), ch.vx);
}

test "the walk animation steps every 4th moving frame" {
    var ch: c.Charly = undefined;
    ch.init(268, 180);
    run(&ch, .{ .right = true }, 3);
    try expectEqual(@as(u8, 0), ch.frame); // ref f62
    run(&ch, .{ .right = true }, 1);
    try expectEqual(@as(u8, 1), ch.frame); // ref f63
    run(&ch, .{ .right = true }, 4);
    try expectEqual(@as(u8, 2), ch.frame); // ref f67
}

test "walking up stops under the wall, walking down stops above the kerb" {
    var ch: c.Charly = undefined;
    ch.init(640, 180);
    run(&ch, .{ .up = true }, 2);
    try expectEqual(@as(f32, 176.5), ch.y); // ref f151
    run(&ch, .{ .up = true }, 48);
    try expectEqual(@as(f32, 126.5), ch.y); // ref f180..f199
    try expectEqual(true, ch.falling); // bumping the ceiling sets it
    run(&ch, .{ .down = true }, 40);
    try expectEqual(@as(f32, 206), ch.y); // ref f759
    run(&ch, .{}, 1);
    try expectEqual(@as(f32, 207.5), ch.y); // ref f760
    run(&ch, .{}, 19);
    try expectEqual(@as(f32, 209), ch.y); // ref f779
}

test "the map's left edge stops Charly dead" {
    var ch: c.Charly = undefined;
    ch.init(3, 180);
    run(&ch, .{ .left = true }, 5);
    try expectEqual(@as(f32, 3), ch.x);
    try expectEqual(true, ch.flip);
}

test "F1 speeds the walk up to 8 px a frame for good" {
    var ch: c.Charly = undefined;
    ch.init(268, 180);
    run(&ch, .{ .fast = true }, 1);
    run(&ch, .{ .right = true }, 3);
    try expectEqual(@as(f32, 8), ch.vx);
}

test "fire reaches the first door only from right in front of it" {
    var ch: c.Charly = undefined;
    ch.init(640, 126.5); // ref f230: entered BEATDIS_LOADER (ScreenID 103)
    try expectEqual(@as(?usize, 0), doors.touching(ch.box()));
    try expectEqual(@as(u16, 103), @intFromEnum(doors.DOORS[0].loader));
    ch.init(640, 180); // further down the street: the box is below the door
    try expectEqual(@as(?usize, null), doors.touching(ch.box()));
}
