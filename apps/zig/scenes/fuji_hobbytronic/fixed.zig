// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: the per-frame 3D, in integers only.
//
// The board's cart CPU is an RV32IM with no FPU, where every f32 operation is a
// soft-float library call. So the frame path is fixed point end to end: a
// 1024-step Q14 sine table (built at compile time), Q14 rotation, one integer
// divide per vertex for the perspective, and the cull, light and depth keys
// as i32 dot products. Nothing here may allocate or touch a float at run time.
// --------------------------------------------------------------------------
const std = @import("std");
const mesh = @import("mesh.zig");

pub const STEPS = 1024; // angle units in a full turn
pub const Q = 14;

pub const SIN: [STEPS]i16 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [STEPS]i16 = undefined;
    for (&t, 0..) |*s, i| s.* = @intFromFloat(@round(@sin(@as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / STEPS) * 16384.0));
    break :blk t;
};

pub fn sin(a: i32) i32 {
    return SIN[@as(u32, @bitCast(a)) % STEPS];
}
pub fn cos(a: i32) i32 {
    return sin(a +% STEPS / 4);
}

/// Where the camera sits and how it projects: the logo's centre is Z0 units in
/// front of the eye, and FOCAL is the screen distance in pixels.
pub const Z0 = 360;
pub const FOCAL = 200;

/// A yaw (about y) then a pitch (about x), both in angle units, as Q14 factors.
pub const Rot = struct {
    cy: i32,
    sy: i32,
    cp: i32,
    sp: i32,

    pub fn init(yaw: i32, pitch: i32) Rot {
        return .{ .cy = cos(yaw), .sy = sin(yaw), .cp = cos(pitch), .sp = sin(pitch) };
    }

    pub fn apply(r: Rot, v: [3]i32) [3]i32 {
        const x1 = (v[0] * r.cy + v[2] * r.sy) >> Q;
        const z1 = (v[2] * r.cy - v[0] * r.sy) >> Q;
        const y2 = (v[1] * r.cp - z1 * r.sp) >> Q;
        const z2 = (v[1] * r.sp + z1 * r.cp) >> Q;
        return .{ x1, y2, z2 };
    }
};

/// Perspective onto the screen, centre (cx, cy): one divide, two multiplies.
pub fn project(p: [3]i32, cx: i32, cy: i32) [2]i16 {
    const inv = @divTrunc(@as(i32, FOCAL) << 16, p[2] + Z0);
    return .{ @intCast(cx + ((p[0] * inv) >> 16)), @intCast(cy + ((p[1] * inv) >> 16)) };
}

/// A face is seen when its normal points back at the eye: n . (P - eye) < 0,
/// with P the face's vertex SUM (4x its centre) so no divide is needed. The
/// eye is at z = -Z0 in the rotated frame.
pub fn facing(n: [3]i32, sum: [3]i32) bool {
    return n[0] * sum[0] + n[1] * sum[1] + n[2] * (sum[2] + 4 * Z0) < 0;
}

/// The light's travel direction, Q14: from the upper left, in front.
pub const LIGHT = [3]i32{ 6144, 8192, 12288 };

/// Lambert term of a rotated normal in 0..levels-1, with one level of ambient.
pub fn shade(n: [3]i32, levels: i32) i32 {
    const lam = -((n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]) >> Q);
    return 1 + (@max(lam, 0) * (levels - 2) >> Q);
}

test "the table is a sine and the quadrants line up" {
    try std.testing.expectEqual(@as(i32, 0), sin(0));
    try std.testing.expectEqual(@as(i32, 16384), sin(256));
    try std.testing.expectEqual(@as(i32, -16384), sin(768));
    try std.testing.expectEqual(@as(i32, 16384), cos(0));
    try std.testing.expectEqual(sin(-100), -sin(100)); // negative angles wrap
}

test "unrotated, the front faces are seen and the back faces are not" {
    const r = Rot.init(0, 0);
    var front: usize = 0;
    for (mesh.MODEL.faces) |f| {
        var sum = [3]i32{ 0, 0, 0 };
        for (f.v) |vi| {
            const v = mesh.MODEL.verts[vi];
            const p = r.apply(.{ v[0], v[1], v[2] });
            for (0..3) |k| sum[k] += p[k];
        }
        const n = r.apply(.{ f.n[0], f.n[1], f.n[2] });
        const seen = facing(n, sum);
        if (f.kind == .back) try std.testing.expect(!seen);
        if (f.kind == .front) {
            try std.testing.expect(seen);
            front += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1 + 2 * mesh.ROWS), front);
}

test "projection: the centre maps to the screen centre, and nearer is bigger" {
    try std.testing.expectEqual([2]i16{ 160, 100 }, project(.{ 0, 0, 0 }, 160, 100));
    const far = project(.{ 100, 0, 50 }, 0, 0);
    const near = project(.{ 100, 0, -50 }, 0, 0);
    try std.testing.expect(near[0] > far[0]);
}

test "a face turned to the light is brighter than one turned away" {
    try std.testing.expect(shade(.{ 0, 0, -16384 }, 8) > shade(.{ 0, 0, 16384 }, 8));
    try std.testing.expect(shade(.{ 16384, 0, 0 }, 8) >= 1);
}
