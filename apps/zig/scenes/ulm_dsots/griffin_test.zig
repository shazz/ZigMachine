// Native tests for the griffin's physics against values the remake printed in
// Chrome (apps/ulm_dsots_ref.mjs; the harness compares every step).
const std = @import("std");
const g = @import("griffin.zig");

/// A 64x64-cell test map (32 px tiles): a floor on row 20, a platform on row
/// 10, a wall in column 2.
const Map = struct {
    pub fn cellAt(_: *const Map, px: f64, py: f64) u8 {
        const x = @trunc(px);
        const y = @trunc(py);
        if (x < 0 or y < 0 or x >= 64 * 32 or y >= 64 * 32) return 0;
        const col = @floor(x / 32);
        const row = @floor(y / 32);
        if (row == 20 or col == 2) return g.SOLID;
        if (row == 10) return g.PLATFORM;
        return 0;
    }
    pub fn width(_: *const Map) f64 {
        return 64 * 32;
    }
    pub fn tile(_: *const Map) f64 {
        return 32;
    }
};

fn standing(x: f64) g.Griffin {
    var b: g.Griffin = undefined;
    b.init(x, 19 * 32, 32); // Tiled object on row 19: bottom on the floor at 640
    return b;
}

test "walking accelerates by 6 less 0.5 friction, capped at 6, and coasts down" {
    const map = Map{};
    var b = standing(512);
    b.update(.{ .right = true }, &map);
    try std.testing.expectEqual(@as(f64, 5.5), b.vx); // trace step 20: x +5.5
    b.update(.{ .right = true }, &map);
    try std.testing.expectEqual(@as(f64, 6), b.vx);
    b.update(.{}, &map);
    try std.testing.expectEqual(@as(f64, 5.5), b.vx);
    try std.testing.expectEqual(@as(f64, 576), b.y); // still standing
}

test "flying gains 2 less 0.98 gravity a step, capped at 4" {
    const map = Map{};
    var b = standing(512);
    const want = [_]f64{ -1.02, -2.04, -3.06, -4, -4 }; // trace steps 3..7
    for (want) |vy| {
        b.update(.{ .fly = true }, &map);
        try std.testing.expectApproxEqAbs(vy, b.vy, 1e-12);
    }
    try std.testing.expectEqual(g.Anim.fly, b.anim);
}

test "a platform lets the griffin up through it and lands it from above" {
    const map = Map{};
    var b = standing(512);
    var n: usize = 0;
    while (b.y + g.SIZE > 10 * 32 and n < 200) : (n += 1) b.update(.{ .fly = true }, &map);
    try std.testing.expect(n < 200); // rose through row 10
    n = 0;
    while (n < 100) : (n += 1) b.update(.{}, &map);
    try std.testing.expectEqual(@as(f64, 10 * 32 - g.SIZE), b.y); // resting on it
}

test "a solid wall stops the walk, an edge of the map too" {
    const map = Map{};
    var b = standing(100);
    for (0..40) |_| b.update(.{ .left = true }, &map);
    // column 2 ends at 96: a step that would cross it is cancelled, not
    // snapped to the wall (updateMovement zeroes vel.x), so 100 - 5.5 never moves
    try std.testing.expectEqual(@as(f64, 100), b.x);
    try std.testing.expect(b.flip);
    var e = standing(64 * 32 - g.SIZE - 3);
    for (0..10) |_| e.update(.{ .right = true }, &map);
    try std.testing.expect(e.x + g.SIZE < 64 * 32);
}
