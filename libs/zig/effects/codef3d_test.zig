// Tests for effects/codef3d.zig. Expected numbers were printed by three.js r49
// itself (the remake's lib/codef_3d_v2.js, run in node): Float32Array storage
// makes them exact, so they compare with ==.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const c3 = @import("codef3d.zig");

test "perspective(25, 640/400, 1, 10000) is three.js's projectionMatrix" {
    const m = c3.Mat4.perspective(25, 1.6, 1, 10000);
    const want = [16]f32{ 2.819192886352539, 0, 0, 0, 0, 4.510708332061768, 0, 0, 0, 0, -1.0002000331878662, -1, 0, 0, -2.000200033187866, 0 };
    try expectEqual(want, m.e);
}

test "a camera translation inverts by cofactors to its negation" {
    const m = c3.Mat4.compose(.{ .x = 0, .y = 70, .z = 100 }, .{ .x = 0, .y = 0, .z = 0 });
    const want = [16]f32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -70, -100, 1 };
    try expectEqual(want, m.inverse().e);
}

test "Euler XYZ rotation matches setRotationFromEuler" {
    const m = c3.Mat4.compose(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = -std.math.pi / 2.0, .y = 0.3, .z = std.math.pi / 3.0 });
    const want = [16]f32{
        0.47766825556755066,  -0.14776010811328888, -0.8660253882408142,   0,
        -0.8273456692695618,  0.25592800974845886,  -0.5,                  0,
        0.29552021622657776,  0.9553365111351013,   5.849749161825597e-17, 0,
        0,                    0,                    0,                     1,
    };
    try expectEqual(want, m.e);
}

const SQUARE = [_]c3.Vec3{ .{ .x = -50, .y = -50, .z = 0 }, .{ .x = 50, .y = -50, .z = 0 }, .{ .x = 50, .y = 50, .z = 0 }, .{ .x = -50, .y = 50, .z = 0 } };
const FACES = [_]c3.Face{ .{ .v = .{ 0, 1, 2, 3 }, .n = 4, .ink = 7 }, .{ .v = .{ 3, 2, 1, 0 }, .n = 4, .ink = 9 } };

test "a square at z -700, turned by pi: one face kept, its overdrawn path in canvas pixels" {
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    const m = c3.mesh(&SQUARE, &FACES);
    var screen: [4]c3.Screen = undefined;
    var out: [2]c3.Poly = undefined;
    const polys = c3.project(&lens, .{ .x = 0, .y = 0, .z = 10 }, .{ .x = 0, .y = 0, .z = -700 }, .{ .x = 0, .y = 0, .z = std.math.pi }, &m, &screen, &out);
    try expectEqual(@as(usize, 1), polys.len);
    try expectEqual(@as(u8, 7), polys[0].ink);
    // three.js moveTo/lineTo, then the canvas transform setTransform(1,0,0,-1,320,200)
    const js = [4][2]f64{
        .{ 64.53337805140417, 64.53110069031196 },   .{ -65.24098026382902, 64.23543300127577 },
        .{ -64.53107632981225, -64.53897318507435 }, .{ 64.23870951051025, -65.23543042311212 },
    };
    for (js, polys[0].pts) |p, got| try expectEqual([2]f64{ p[0] + 320, -p[1] + 200 }, got);
}

test "a mesh behind the camera is culled whole" {
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    const m = c3.mesh(&SQUARE, &FACES);
    var screen: [4]c3.Screen = undefined;
    var out: [2]c3.Poly = undefined;
    const polys = c3.project(&lens, .{ .x = 0, .y = 0, .z = 10 }, .{ .x = 0, .y = 0, .z = 500 }, .{ .x = 0, .y = 0, .z = 0 }, &m, &screen, &out);
    try expectEqual(@as(usize, 0), polys.len);
}

test "faces sort far to near, ties keeping their order" {
    const verts = [_]c3.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },   .{ .x = 0, .y = 10, .z = 0 },   .{ .x = 10, .y = 0, .z = 0 }, // near
        .{ .x = 0, .y = 0, .z = -50 }, .{ .x = 0, .y = 10, .z = -50 }, .{ .x = 10, .y = 0, .z = -50 }, // far
    };
    const faces = [_]c3.Face{
        .{ .v = .{ 0, 1, 2, 0 }, .n = 3, .ink = 1 },
        .{ .v = .{ 3, 4, 5, 0 }, .n = 3, .ink = 2 },
        .{ .v = .{ 0, 1, 2, 0 }, .n = 3, .ink = 3 },
    };
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    const m = c3.mesh(&verts, &faces);
    var screen: [6]c3.Screen = undefined;
    var out: [3]c3.Poly = undefined;
    const polys = c3.project(&lens, .{ .x = 0, .y = 0, .z = 10 }, .{ .x = 0, .y = 0, .z = -300 }, .{ .x = 0, .y = 0, .z = 0 }, &m, &screen, &out);
    try expectEqual(@as(usize, 3), polys.len);
    try expectEqual([3]u8{ 2, 1, 3 }, [3]u8{ polys[0].ink, polys[1].ink, polys[2].ink });
}
