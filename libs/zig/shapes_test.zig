// Tests for effects/shapes.zig fillFlatTriangle: exact coverage, independence
// from vertex order (the rotating Shapes screen reorders vertices in y), and
// degenerate / off-plane triangles. Rooted in libs/zig/, not effects/, because
// shapes.zig imports ../zigos.zig and zig test forbids imports above the root.
const std = @import("std");
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;
const shapes = @import("effects/shapes.zig");
const Coord = shapes.Coord;

const W = 8;
const H = 8;

fn fill(buf: *[W * H]u8, a: Coord, b: Coord, c: Coord) void {
    @memset(buf, 0);
    shapes.fillTriangle(.{ .px = buf, .stride = W, .w = W, .h = H }, a, b, c, 1);
}

fn count(buf: *const [W * H]u8) usize {
    var n: usize = 0;
    for (buf) |p| n += p;
    return n;
}

// Rows [0,4), columns [0, 4-y): the half-open fill of (0,0) (4,0) (0,4).
const RIGHT_ANGLE = [W * H]u8{
    1, 1, 1, 1, 0, 0, 0, 0,
    1, 1, 1, 0, 0, 0, 0, 0,
    1, 1, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};

test "a right-angle triangle covers exactly the expected pixels" {
    var buf: [W * H]u8 = undefined;
    fill(&buf, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, .{ .x = 0, .y = 4 });
    try expectEqualSlices(u8, &RIGHT_ANGLE, &buf);
}

test "coverage does not depend on vertex order" {
    const v = [3]Coord{ .{ .x = 1, .y = 1 }, .{ .x = 7, .y = 3 }, .{ .x = 2, .y = 7 } };
    var ref: [W * H]u8 = undefined;
    fill(&ref, v[0], v[1], v[2]);
    try std.testing.expect(count(&ref) > 10);
    const orders = [_][3]usize{ .{ 0, 2, 1 }, .{ 1, 0, 2 }, .{ 1, 2, 0 }, .{ 2, 0, 1 }, .{ 2, 1, 0 } };
    for (orders) |o| {
        var buf: [W * H]u8 = undefined;
        fill(&buf, v[o[0]], v[o[1]], v[o[2]]);
        try expectEqualSlices(u8, &ref, &buf);
    }
}

test "the long edge may be the last one and point upwards" {
    // (0,4) -> (0,0) closes the loop bottom-to-top: the case that drew nothing.
    var buf: [W * H]u8 = undefined;
    fill(&buf, .{ .x = 4, .y = 0 }, .{ .x = 0, .y = 4 }, .{ .x = 0, .y = 0 });
    try expectEqualSlices(u8, &RIGHT_ANGLE, &buf);
}

test "zero-height and collinear triangles draw nothing" {
    var buf: [W * H]u8 = undefined;
    fill(&buf, .{ .x = 0, .y = 3 }, .{ .x = 7, .y = 3 }, .{ .x = 4, .y = 3 });
    try expectEqual(@as(usize, 0), count(&buf));
    fill(&buf, .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 2 });
    try expectEqual(@as(usize, 0), count(&buf));
}

test "a triangle overhanging every edge is clipped, not wrapped" {
    var buf: [W * H]u8 = undefined;
    fill(&buf, .{ .x = -20, .y = -20 }, .{ .x = 40, .y = -20 }, .{ .x = 4, .y = 40 });
    try expectEqual(@as(usize, W * H), count(&buf));
    fill(&buf, .{ .x = -9, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = -5, .y = 7 });
    try expectEqual(@as(usize, 0), count(&buf));
    fill(&buf, .{ .x = 0, .y = 8 }, .{ .x = 7, .y = 8 }, .{ .x = 3, .y = 20 });
    try expectEqual(@as(usize, 0), count(&buf));
}
