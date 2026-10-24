// --------------------------------------------------------------------------
// The trefoil knot's mesh, built at compile time (a few hundred vertices: the
// compiler's float maths is fine at this size). A tube of SIDES sides swept
// along the knot p(s) = (sin s + 2 sin 2s, cos s - 2 cos 2s, -sin 3s), with a
// rotation-minimising frame so it does not twist. Each quad carries its
// outward normal for the lighting (knot.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const SEGS = 40;
pub const SIDES = 5;
pub const NV = SEGS * SIDES;
pub const NQ = SEGS * SIDES;
const R_TUBE = 0.55;
const SCALE = 1.0 / 3.6; // the knot spans about +-3.5: fit radius ~1

pub const Quad = struct { v: [4]u16, n: [3]f32 };

fn knot(s: f64) [3]f64 {
    return .{ @sin(s) + 2 * @sin(2 * s), @cos(s) - 2 * @cos(2 * s), -@sin(3 * s) };
}

fn sub(a: [3]f64, b: [3]f64) [3]f64 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

fn cross(a: [3]f64, b: [3]f64) [3]f64 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn norm(a: [3]f64) [3]f64 {
    const l = @sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    return .{ a[0] / l, a[1] / l, a[2] / l };
}

const Mesh = struct { v: [NV][3]f32, q: [NQ]Quad };

pub const MESH: Mesh = blk: {
    @setEvalBranchQuota(2_000_000);
    var m: Mesh = undefined;
    var nrm = [3]f64{ 0, 0, 1 };
    var ring: [SEGS][3]f64 = undefined; // centres
    for (0..SEGS) |i| ring[i] = knot(@as(f64, @floatFromInt(i)) * 2 * std.math.pi / SEGS);
    for (0..SEGS) |i| {
        const t = norm(sub(ring[(i + 1) % SEGS], ring[(i + SEGS - 1) % SEGS]));
        nrm = norm(cross(cross(t, nrm), t)); // project the last normal: no twist
        const b = cross(t, nrm);
        for (0..SIDES) |j| {
            const a = @as(f64, @floatFromInt(j)) * 2 * std.math.pi / SIDES;
            var p: [3]f32 = undefined;
            for (0..3) |k| p[k] = @floatCast((ring[i][k] + R_TUBE * (@cos(a) * nrm[k] + @sin(a) * b[k])) * SCALE);
            m.v[i * SIDES + j] = p;
        }
    }
    for (0..SEGS) |i| for (0..SIDES) |j| {
        const a = i * SIDES + j;
        const b = i * SIDES + (j + 1) % SIDES;
        const c = ((i + 1) % SEGS) * SIDES + (j + 1) % SIDES;
        const d = ((i + 1) % SEGS) * SIDES + j;
        var ctr = [3]f64{ 0, 0, 0 };
        for ([_]usize{ a, b, c, d }) |k| for (0..3) |x| {
            ctr[x] += m.v[k][x] / 4.0;
        };
        const axis = ring[i];
        const n = norm(sub(ctr, .{ axis[0] * SCALE, axis[1] * SCALE, axis[2] * SCALE }));
        m.q[i * SIDES + j] = .{ .v = .{ a, b, c, d }, .n = .{ @floatCast(n[0]), @floatCast(n[1]), @floatCast(n[2]) } };
    };
    break :blk m;
};
