// Native tests for acc.zig, the f32 cart's per-pixel refinement state:
//   zig test apps/zig/scenes/raytrace/acc_test.zig (the gate: apps/zig/scene_tests.zig)
const std = @import("std");
const A = @import("acc.zig");
const D = @import("dither.zig");

const classes = [_]u8{ D.CLS_SKY, D.CLS_FLOOR, D.CLS_FLOOR + 1, D.CLS_MAT, D.CLS_MAT + 4 };

test "one sample resolves to the first pass's own index, everywhere" {
    for (classes) |cls| {
        var q: u16 = 0;
        while (q <= 256) : (q += 1) for (0..4) |y| for (0..4) |x| {
            const s = D.Shade{ .cls = cls, .q = q, .fog = 256 - q };
            const bay = D.bayer(@intCast(x), @intCast(y));
            try std.testing.expectEqual(D.index(s, bay), A.resolve(A.first(s), @intCast(x), @intCast(y)));
        };
    }
}

test "samples of one class average their intensities" {
    var a = A.first(.{ .cls = D.CLS_MAT + 1, .q = 0, .fog = 0 });
    A.add(&a, .{ .cls = D.CLS_MAT + 1, .q = 256, .fog = 0 });
    try std.testing.expectEqual(@as(u8, 2), a.n[0]);
    try std.testing.expectEqual(@as(u8, 0), a.n[1]);
    // mean 128 over 22 levels is level 10.5: 10 and 11 across the Bayer cell
    var lo: u32 = 0;
    for (0..4) |y| for (0..4) |x| {
        const i = A.resolve(a, @intCast(x), @intCast(y)) - D.MAT_BASE - D.MAT_LV;
        try std.testing.expect(i == 10 or i == 11);
        lo += @intFromBool(i == 10);
    };
    try std.testing.expectEqual(@as(u32, 8), lo);
}

test "two classes dither by coverage; a third is dropped" {
    var a = A.first(.{ .cls = D.CLS_SKY, .q = 128, .fog = 0 });
    for (0..3) |_| A.add(&a, .{ .cls = D.CLS_MAT + 2, .q = 128, .fog = 0 });
    A.add(&a, .{ .cls = D.CLS_FLOOR, .q = 256, .fog = 0 }); // a third class
    try std.testing.expectEqual(@as(u8, 1), a.n[0]);
    try std.testing.expectEqual(@as(u8, 3), a.n[1]);
    var mat: u32 = 0;
    for (0..4) |y| for (0..4) |x| {
        const i = A.resolve(a, @intCast(x), @intCast(y));
        try std.testing.expect(i < D.FLOOR_BASE or i >= D.MAT_BASE); // never the floor
        mat += @intFromBool(i >= D.MAT_BASE);
    };
    try std.testing.expectEqual(@as(u32, 12), mat); // 3/4 coverage: 12 of the 16 cells
}

test "the converged state does not depend on the sample order" {
    const s = [_]D.Shade{
        .{ .cls = D.CLS_FLOOR, .q = 256, .fog = 40 },
        .{ .cls = D.CLS_FLOOR + 1, .q = 80, .fog = 41 },
        .{ .cls = D.CLS_FLOOR, .q = 80, .fog = 39 },
        .{ .cls = D.CLS_FLOOR + 1, .q = 256, .fog = 42 },
    };
    var a = A.first(s[0]);
    for (s[1..]) |v| A.add(&a, v);
    var b = A.first(s[0]);
    var i: usize = s.len - 1;
    while (i > 0) : (i -= 1) A.add(&b, s[i]);
    try std.testing.expectEqual(a, b);
}

test "the sums hold 32 full-scale samples" {
    var a = A.first(.{ .cls = D.CLS_SKY, .q = 256, .fog = 256 });
    for (1..32) |_| A.add(&a, .{ .cls = D.CLS_SKY, .q = 256, .fog = 256 });
    try std.testing.expectEqual(@as(u16, 32 * 256), a.q[0]);
    try std.testing.expectEqual(D.index(.{ .cls = D.CLS_SKY, .q = 256, .fog = 0 }, 8), A.resolve(a, 0, 0));
}
