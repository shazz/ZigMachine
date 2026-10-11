// Tests for effects/zig3d.zig. Expected numbers were printed by three.js r49
// itself (the remake's lib/codef_3d_v2.js, run in node): Float32Array storage
// makes them exact, so they compare with ==.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const c3 = @import("zig3d.zig");

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
    // wound clockwise on screen, (0,0) -> (10,0) -> (0,10): the other way is culled
    const faces = [_]c3.Face{
        .{ .v = .{ 0, 2, 1, 0 }, .n = 3, .ink = 1 },
        .{ .v = .{ 3, 5, 4, 0 }, .n = 3, .ink = 2 },
        .{ .v = .{ 0, 2, 1, 0 }, .n = 3, .ink = 3 },
    };
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    const m = c3.mesh(&verts, &faces);
    var screen: [6]c3.Screen = undefined;
    var out: [3]c3.Poly = undefined;
    const polys = c3.project(&lens, .{ .x = 0, .y = 0, .z = 10 }, .{ .x = 0, .y = 0, .z = -300 }, .{ .x = 0, .y = 0, .z = 0 }, &m, &screen, &out);
    try expectEqual(@as(usize, 3), polys.len);
    try expectEqual([3]u8{ 2, 1, 3 }, [3]u8{ polys[0].ink, polys[1].ink, polys[2].ink });
}

// screen 17's vectorballs: codef3D(canvas 640x480, camZ 800, fov 50, near 1,
// far 1600) with group.scale 60 and rotation.x 0.04. The x/y/scale three.js's
// own Projector printed for three of the twelve particles, in ITS draw order
// (far to near). All three sit at x = 0, so they share the canvas midline.
const RING = [_]c3.Vec3{ .{ .x = 0, .y = 1, .z = -5 }, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0, .y = -1, .z = 5 } };

test "a scaled group of particles lands where three.js r49 puts them" {
    const lens = c3.Lens.init(640, 480, 50, 1, 1600);
    var out: [RING.len]c3.Particle = undefined;
    const ps = c3.projectParticles(&lens, .{ .x = 0, .y = 0, .z = 800 }, .{ .x = 0.04, .y = 0, .z = 0 }, 60, &RING, &out);
    try expectEqual(@as(usize, 3), ps.len);
    const want = [3]c3.Particle{
        .{ .x = 320, .y = 206.25473102648283, .sx = 0.46901777099399683, .sy = 0.469017770993998, .z = 0.999427034940785 },
        .{ .x = 320, .y = 240, .sx = 0.6433520793914794, .sy = 0.6433520793914795, .z = 0.9987491607666016 },
        .{ .x = 320, .y = 313.67257318223824, .sx = 1.0239582349882228, .sy = 1.0239582349882248, .z = 0.9972692278389645 },
    };
    try expectEqual(want, ps[0..3].*);
}

test "projectView through a View built once is projectEx, bit for bit" {
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    const m = c3.mesh(&SQUARE, &FACES);
    const camera = c3.Vec3{ .x = 0, .y = 0, .z = 10 };
    const view = c3.View.init(&lens, camera);
    var s1: [4]c3.Screen = undefined;
    var s2: [4]c3.Screen = undefined;
    var o1: [2]c3.Poly = undefined;
    var o2: [2]c3.Poly = undefined;
    for (0..64) |i| {
        const t: f64 = @floatFromInt(i);
        const pos = c3.Vec3{ .x = t * 3 - 90, .y = 40 - t, .z = -700 + t * 20 };
        const rot = c3.Vec3{ .x = t * 0.1, .y = t * 0.07, .z = t * 0.13 };
        const a = c3.projectEx(&lens, camera, pos, rot, &m, &s1, &o1, .{ .double_sided = i % 2 == 0 });
        const b = c3.projectView(&view, pos, rot, &m, &s2, &o2, .{ .double_sided = i % 2 == 0 });
        try expectEqual(a.len, b.len);
        for (a, b) |p, q| try expectEqual(p, q);
    }
}

fn refRound(v: f64) i16 {
    return @intFromFloat(@round(@max(-4096.0, @min(4096.0, v))));
}

test "roundClamped is the float chain on ties, their neighbours, NaN and the limits" {
    const specials = [_]f64{ 0, -0.0, std.math.nan(f64), -std.math.nan(f64), std.math.inf(f64), -std.math.inf(f64), 4096, -4096, 4095.5, -4095.5, 1e300, -1e300, 5e-324, 0.49999999999999994, -0.49999999999999994 };
    for (specials) |v| try expectEqual(refRound(v), c3.roundClamped(v, 4096));
    var k: f64 = -4200;
    while (k <= 4200) : (k += 0.25) {
        try expectEqual(refRound(k), c3.roundClamped(k, 4096));
        try expectEqual(refRound(std.math.nextAfter(f64, k, std.math.inf(f64))), c3.roundClamped(std.math.nextAfter(f64, k, std.math.inf(f64)), 4096));
        try expectEqual(refRound(std.math.nextAfter(f64, k, -std.math.inf(f64))), c3.roundClamped(std.math.nextAfter(f64, k, -std.math.inf(f64)), 4096));
    }
    var prng = std.Random.DefaultPrng.init(417);
    const rnd = prng.random();
    for (0..200_000) |_| {
        const v: f64 = @bitCast(rnd.int(u64));
        try expectEqual(refRound(v), c3.roundClamped(v, 4096));
    }
}
