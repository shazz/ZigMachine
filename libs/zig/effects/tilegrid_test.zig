// Tests for effects/tilegrid.zig against the melonJS 0.9.8 behaviour it ports.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const tg = @import("tilegrid.zig");

const cells = [_]u8{
    0, 0, 0,
    1, 0, 2,
};
const grid = tg.Grid{ .cells = &cells, .cols = 3, .rows = 2, .tw = 32, .th = 16 };

test "cellAt finds the cell under a pixel" {
    try expectEqual(@as(?u8, 1), grid.cellAt(0, 16));
    try expectEqual(@as(?u8, 2), grid.cellAt(95.9, 31.9));
    try expectEqual(@as(?u8, 0), grid.cellAt(40, 20));
}

test "cellAt truncates toward zero like ~~ and refuses the outside" {
    try expectEqual(@as(?u8, 0), grid.cellAt(-0.5, 0)); // ~~(-0.5/32) == 0
    try expectEqual(@as(?u8, null), grid.cellAt(-32, 0));
    try expectEqual(@as(?u8, null), grid.cellAt(96, 0));
    try expectEqual(@as(?u8, null), grid.cellAt(0, 32));
}

test "deadzone(0) on a 640 view is the centre line, as setDeadzone(0,0)" {
    const dz = tg.deadzone(640, 0);
    try expectEqual(@as(i32, 320), dz.lo);
    try expectEqual(@as(i32, 320), dz.hi);
}

test "followAxis keeps the target on the dead line and clamps to the map" {
    // target right of the line: view = ~~min(target - hi, limit)
    try expectEqual(@as(i32, 180), tg.followAxis(0, 500.5, 320, 320, 4960));
    // target left of the line: view = ~~max(target - lo, 0)
    try expectEqual(@as(i32, 0), tg.followAxis(100, 268, 320, 320, 4960));
    try expectEqual(@as(i32, 4960), tg.followAxis(4900, 5500, 320, 320, 4960));
    // exactly on the line: no move
    try expectEqual(@as(i32, 180), tg.followAxis(180, 500, 320, 320, 4960));
}

test "RatioScroll follows the camera at its ratio and wraps both ways" {
    var s = tg.RatioScroll{ .pos = 0, .last = 0, .ratio = 0.5, .w = 640 };
    s.update(5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), s.pos, 1e-6);
    s.update(5); // unchanged view: no move
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), s.pos, 1e-6);
    s.update(0); // back left past zero wraps to the image's end
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.pos, 1e-6);
    s.update(-10);
    try std.testing.expectApproxEqAbs(@as(f32, 635), s.pos, 1e-6);
}
