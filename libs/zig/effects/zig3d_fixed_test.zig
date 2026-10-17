// Tests for effects/zig3d_fixed.zig: the integer projector against zig3d (the
// f64, three.js-exact one) on the same meshes and the same spins, frame after
// frame. The bar is what a screen can see: every vertex within 1/1000 px.
const std = @import("std");
const c3 = @import("zig3d.zig");
const zf = @import("zig3d_fixed.zig");
const fm = zf.math;

test "sinCos is within 4e-9 of the true sine over a whole turn" {
    var worst: f64 = 0;
    var a: u64 = 0;
    while (a < 1 << 32) : (a += 999_983) { // a prime stride: every table cell, every remainder
        const sc = fm.sinCos(@intCast(a));
        const rad = @as(f64, @floatFromInt(a)) * (2.0 * std.math.pi / 4294967296.0);
        worst = @max(worst, @abs(@as(f64, @floatFromInt(sc.s)) / 1073741824.0 - @sin(rad)));
        worst = @max(worst, @abs(@as(f64, @floatFromInt(sc.c)) / 1073741824.0 - @cos(rad)));
    }
    try std.testing.expect(worst < 4e-9);
}

test "phase: a step accumulates to the radians it was given" {
    var spin = fm.Spin{};
    const step = fm.phase(0.01);
    for (0..1000) |_| spin.add(.{ step, step, step });
    const want: u32 = @intFromFloat(@round(10.0 / (2.0 * std.math.pi) * 4294967296.0) - 4294967296.0);
    try std.testing.expect(@abs(@as(i64, spin.top()[0]) - want) <= 1);
    try std.testing.expectEqual(@as(u64, 1 << 63), fm.phase(std.math.pi));
    try std.testing.expectEqual(@as(u64, 3 << 62), fm.phase(-std.math.pi / 2.0));
}

test "roundPx rounds half away from zero and clamps" {
    try std.testing.expectEqual(@as(i16, 3), fm.roundPx(3 * 4096 + 2047, 4096));
    try std.testing.expectEqual(@as(i16, 4), fm.roundPx(3 * 4096 + 2048, 4096));
    try std.testing.expectEqual(@as(i16, -4), fm.roundPx(-(3 * 4096 + 2048), 4096));
    try std.testing.expectEqual(@as(i16, 0), fm.roundPx(-2047, 4096));
    try std.testing.expectEqual(@as(i16, -16), fm.roundPx(-1 << 30, 16));
}

const Case = struct {
    w: u32,
    h: u32,
    fov: f64,
    camera: c3.Vec3,
    position: c3.Vec3,
    start: c3.Vec3,
    step: c3.Vec3,
    opts: c3.Options,
};

/// `frames` frames of `m` under both projectors: the same faces, in the same
/// order, every corner within `tol` px. Returns the worst corner error.
fn compare(case: Case, m: *const c3.Mesh, comptime nv: usize, comptime nf: usize, frames: usize) !f64 {
    const lens = c3.Lens.init(case.w, case.h, case.fov, 1, if (case.w == 176) 3000 else 10000);
    const zl = zf.Lens.init(&lens);
    var vq: [nv]zf.Vec = undefined;
    var cq: [nf]zf.Vec = undefined;
    const zm = zf.fromMesh(m, &vq, &cq);
    var s64: [nv]c3.Screen = undefined;
    var p64: [nf]c3.Poly = undefined;
    var s32: [nv]zf.Screen = undefined;
    var p32: [nf]zf.Poly = undefined;
    var rot = case.start;
    var spin = fm.Spin{ .p = .{ phaseOf(case.start.x), phaseOf(case.start.y), phaseOf(case.start.z) } };
    const step = [3]u64{ phaseOf(case.step.x), phaseOf(case.step.y), phaseOf(case.step.z) };
    var worst: f64 = 0;
    for (0..frames) |_| {
        const want = c3.projectEx(&lens, case.camera, case.position, rot, m, &s64, &p64, case.opts);
        const got = zf.project(&zl, zf.q16(case.camera), zf.q16(case.position), spin.top(), &zm, &s32, &p32, case.opts);
        try std.testing.expectEqual(want.len, got.len);
        for (want, got) |a, b| {
            try std.testing.expectEqual(a.ink, b.ink);
            for (a.pts[0..a.n], b.pts[0..a.n]) |pa, pb| for (0..2) |k| {
                worst = @max(worst, @abs(pa[k] - @as(f64, @floatFromInt(pb[k])) / 4096.0));
            };
        }
        rot = .{ .x = rot.x + case.step.x, .y = rot.y + case.step.y, .z = rot.z + case.step.z };
        spin.add(step);
    }
    return worst;
}

/// fm.phase for a run-time angle (tests only).
fn phaseOf(rad: f64) u64 {
    const turns = rad / (2.0 * std.math.pi);
    return @intFromFloat(@min(@round((turns - @floor(turns)) * 18446744073709551616.0), 18446744073709549568.0));
}

fn v(x: f64, y: f64, z: f64) c3.Vec3 {
    return .{ .x = x, .y = y, .z = z };
}
fn tri(a: u16, b: u16, c: u16, ink: u8) c3.Face {
    return .{ .v = .{ a, b, c, 0 }, .n = 3, .ink = ink };
}
const SPIKE = [14]c3.Vec3{
    v(0, 0, 200),       v(-150, 150, 150), v(150, 150, 150),  v(150, -150, 150),
    v(-150, -150, 150), v(200, 0, 0),      v(150, 150, -150), v(150, -150, -150),
    v(-200, 0, 0),      v(-150, 150, -150), v(-150, -150, -150), v(0, 0, -200),
    v(0, 200, 0),       v(0, -200, 0),
};
const GLENZ_FACES = [24]c3.Face{
    tri(0, 2, 1, 1),   tri(0, 3, 2, 2),   tri(0, 4, 3, 1),   tri(0, 1, 4, 2),
    tri(5, 6, 2, 2),   tri(5, 7, 6, 1),   tri(5, 3, 7, 2),   tri(5, 2, 3, 1),
    tri(8, 1, 9, 2),   tri(8, 9, 10, 1),  tri(8, 10, 4, 2),  tri(8, 4, 1, 1),
    tri(11, 6, 7, 2),  tri(11, 7, 10, 1), tri(11, 10, 9, 2), tri(11, 9, 6, 1),
    tri(12, 1, 2, 2),  tri(12, 2, 6, 1),  tri(12, 6, 9, 2),  tri(12, 9, 1, 1),
    tri(13, 7, 3, 1),  tri(13, 10, 7, 2), tri(13, 4, 10, 1), tri(13, 3, 4, 2),
};

test "tsl_hybridglenz's spiked glenz: 3000 frames, every corner within 1/1000 px" {
    const m = c3.mesh(&SPIKE, &GLENZ_FACES);
    const case = Case{
        .w = 176, .h = 176, .fov = 40, .camera = v(0, 0, 900), .position = v(0, 0, 0),
        .start = v(0, 0, 0), .step = v(0.01, 0.022, 0.028), .opts = .{ .double_sided = true, .overdraw = false },
    };
    try std.testing.expect(try compare(case, &m, 14, 24, 3000) < 1e-3);
}

const SQUARE = [_]c3.Vec3{ v(-50, -50, 0), v(50, -50, 0), v(50, 50, 0), v(-50, 50, 0) };
const QUADS = [_]c3.Face{ .{ .v = .{ 0, 1, 2, 3 }, .n = 4, .ink = 7 }, .{ .v = .{ 3, 2, 1, 0 }, .n = 4, .ink = 9 } };

test "a culled, overdrawn quad pair (TNT3's lens): the same faces kept, corners within 1/1000 px" {
    const m = c3.mesh(&SQUARE, &QUADS);
    const case = Case{
        .w = 640, .h = 400, .fov = 25, .camera = v(0, 70, 100), .position = v(0, 0, -700),
        .start = v(-std.math.pi / 2.0, 0, std.math.pi / 3.0), .step = v(0.033, 0.032, 0.031), .opts = .{},
    };
    try std.testing.expect(try compare(case, &m, 4, 2, 2000) < 1e-3);
}

test "a mesh behind the camera is culled whole, as zig3d culls it" {
    const lens = c3.Lens.init(640, 400, 25, 1, 10000);
    const zl = zf.Lens.init(&lens);
    const m = c3.mesh(&SQUARE, &QUADS);
    var vq: [4]zf.Vec = undefined;
    var cq: [2]zf.Vec = undefined;
    const zm = zf.fromMesh(&m, &vq, &cq);
    var s: [4]zf.Screen = undefined;
    var out: [2]zf.Poly = undefined;
    const got = zf.project(&zl, zf.q16(v(0, 0, 10)), zf.q16(v(0, 0, 500)), .{ 0, 0, 0 }, &zm, &s, &out, .{});
    try std.testing.expectEqual(@as(usize, 0), got.len);
}
