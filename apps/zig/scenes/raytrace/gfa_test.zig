// Native tests for gfa.zig (the GfA Punch listing's functions), through apps/zig/scene_tests.zig.
const std = @import("std");
const G = @import("gfa.zig");

const expectEqual = std.testing.expectEqual;

test "RAND(10) is the JS oracle's stream (apps/gfa_punch_lib.mjs)" {
    var r = G.Rand{ .s = G.SEED };
    for ([_]u32{ 7, 3, 0, 4, 7, 5, 5, 7 }) |want| try expectEqual(want, r.next(10));
}

test "FN d rounds to nearest, halves up (INT(v) - TRUE)" {
    try expectEqual(@as(i32, 3), G.fnD(2.5));
    try expectEqual(@as(i32, 2), G.fnD(2.49));
    try expectEqual(@as(i32, -2), G.fnD(-2.5));
    try expectEqual(@as(i32, 159), G.fnD(159));
}

test "FN c: TRUE = -1 keeps the dither in 0..15" {
    var r = G.Rand{ .s = 1 };
    for (0..200) |_| try expectEqual(@as(u8, 15), G.fnC(1.0, &r)); // d = 159: always 15
    for (0..200) |_| try expectEqual(@as(u8, 0), G.fnC(0.0, &r)); // MAX(0, 0 - 1)
    var sum: u32 = 0; // d = 105: 10, minus one when RAND(10) > 5 (4 in 10)
    for (0..1000) |_| sum += G.fnC(105.0 / 159.0, &r);
    try std.testing.expect(sum > 9400 and sum < 9800);
}

test "FN a: full light is clamped to 1, ambient alone when facing away" {
    try std.testing.expectApproxEqAbs(@as(f32, 1), G.fnA(80, 80, -80, 0, 0, 0, 0.15), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), G.fnA(-80, -80, 80, 0, 0, 0, 0.15), 1e-6);
}

test "line 7: a ray toward the sphere hits, one at the top-left corner misses" {
    try std.testing.expect(G.sphereZ(30, 0) != null);
    try std.testing.expect(G.sphereZ(-159, 53) == null);
}

test "an ST colour word, c * 255 / 7" {
    try expectEqual([3]u8{ 255, 255, 72 }, G.stRgb(0x772));
}
