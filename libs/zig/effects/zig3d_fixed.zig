// --------------------------------------------------------------------------
// zig3d's projector in integers: the same three.js r49 steps (Euler XYZ model
// matrix, a camera that only translates, clip-z usability, facing test,
// centroid depth sort, overdraw), with no float at run time.
//
// Why: on KESTREL the cart CPU (ZIGGY, rv32im) has no FPU, and zig3d's f64
// matrices, divides and fdlibm sines are all soft-float calls; a glenz cube
// pair cost ~2.5 Mcycles a frame that way. Float stays where it is cheap and
// exact enough: Lens.init and the mesh conversions run once (from zig3d's own
// Lens and meshes), so the projection matrix is three.js's to the bit.
//
//   world     Q16.16 (i32): vertices, positions, the camera
//   matrix    Q30 (zig3d_fixed_math.rotation, from u32 angles)
//   canvas    Q12 (i32): 1/4096 px, range +-262144 px, because a vertex just
//             in front of the camera projects far off the canvas and the fill
//             still needs its true position
//
// What is NOT carried over: Mat4.maxScaleOnAxis (a rotation's is 1, and no
// caller scales a mesh) and the f32 storage of the model and view matrices
// (their rounding moves a vertex ~1e-5 px).
//
// No ZigOS import: zig3d_fixed_test.zig runs it natively against zig3d.
// --------------------------------------------------------------------------
const std = @import("std");
const c3 = @import("zig3d.zig");
const fm = @import("zig3d_fixed_math.zig");
const poly = @import("zig3d_fixed_poly.zig");

pub const math = fm;
pub const Angle = fm.Angle;
pub const Face = c3.Face;
pub const Options = c3.Options;
pub const Vec = struct { x: i32, y: i32, z: i32 };
pub const Screen = poly.Screen;
pub const Poly = poly.Poly;

/// A float vector in Q16 (init or comptime only).
pub fn q16(v: c3.Vec3) Vec {
    return .{ .x = toQ16(v.x), .y = toQ16(v.y), .z = toQ16(v.z) };
}
fn toQ16(v: f64) i32 {
    return @intFromFloat(@round(v * 65536.0));
}

/// zig3d's Mesh in Q16: the same faces, centroids and bounding radius.
pub const Mesh = struct {
    verts: []const Vec,
    faces: []const Face,
    centroids: []const Vec,
    radius: i32,
};

/// A zig3d mesh converted at run time (init): `verts` and `centroids` need
/// as many entries as the mesh has.
pub fn fromMesh(m: *const c3.Mesh, verts: []Vec, centroids: []Vec) Mesh {
    for (m.verts, verts[0..m.verts.len]) |v, *o| o.* = q16(v);
    for (m.centroids, centroids[0..m.centroids.len]) |c, *o| o.* = q16(c);
    return .{ .verts = verts[0..m.verts.len], .faces = m.faces, .centroids = centroids[0..m.centroids.len], .radius = toQ16(m.radius) };
}

/// A zig3d mesh known at compile time, converted at compile time.
pub fn comptimeMesh(comptime m: c3.Mesh) Mesh {
    const conv = comptime blk: {
        @setEvalBranchQuota(100_000);
        var v: [m.verts.len]Vec = undefined;
        var c: [m.centroids.len]Vec = undefined;
        for (m.verts, &v) |x, *o| o.* = q16(x);
        for (m.centroids, &c) |x, *o| o.* = q16(x);
        break :blk .{ v, c };
    };
    return .{ .verts = &conv[0], .faces = m.faces, .centroids = &conv[1], .radius = toQ16(m.radius) };
}

/// A frustum plane through the camera's origin frame: Q30 normal, Q16 offset.
const Plane = struct { n: [3]i32, d: i32 };

/// Everything the projection needs from zig3d's Lens, derived once.
pub const Lens = struct {
    kx: i64, // P[0] * half width, Q20
    ky: i64, // P[5] * half height, Q20
    half_w: i32, // Q12
    half_h: i32,
    zr_lo: i32, // camera-space z (Q16) strictly between these: clip z in (near, far)
    zr_hi: i32,
    planes: [6]Plane,

    pub fn init(l: *const c3.Lens) Lens {
        const p = l.projection.e;
        const p10: f64 = p[10];
        const p14: f64 = p[14];
        var out = Lens{
            .kx = @intFromFloat(@round(@as(f64, p[0]) * l.half_w * 1048576.0)),
            .ky = @intFromFloat(@round(@as(f64, p[5]) * l.half_h * 1048576.0)),
            .half_w = @intFromFloat(l.half_w * 4096.0),
            .half_h = @intFromFloat(l.half_h * 4096.0),
            // c.z = P10 Zr + P14 with P10 < 0: c.z > near <=> Zr < (near - P14) / P10
            .zr_lo = @intFromFloat(@floor((l.far - p14) / p10 * 65536.0)),
            .zr_hi = @intFromFloat(@ceil((l.near - p14) / p10 * 65536.0)),
            .planes = undefined,
        };
        // The planes of projection . translate(-camera) are the projection's,
        // evaluated at (point - camera): build them for a camera at the origin.
        const at_origin = c3.View.init(l, .{ .x = 0, .y = 0, .z = 0 });
        for (at_origin.planes, &out.planes) |pl, *o| o.* = .{
            .n = .{ toQ30(pl[0]), toQ30(pl[1]), toQ30(pl[2]) },
            .d = toQ16(pl[3]),
        };
        return out;
    }
};
fn toQ30(v: f64) i32 {
    return @intFromFloat(@round(v * 1073741824.0));
}

fn sub(a: Vec, b: Vec) Vec {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

/// Frustum.contains: the bounding sphere, at `rel` from the camera.
fn inside(lens: *const Lens, rel: Vec, radius: i32) bool {
    for (lens.planes) |pl| {
        if (fm.dot(pl.n, rel.x, rel.y, rel.z) + pl.d <= -radius) return false;
    }
    return true;
}

/// zig3d.projectEx in integers: `m` placed at `position`, turned by `rot`,
/// seen from `camera` (no rotation). `screen` needs m.verts.len entries,
/// `out` m.faces.len. Returns the faces to fill, far to near, in Q12 canvas
/// pixels. Every coordinate here stays inside +-32767 world units.
pub fn project(lens: *const Lens, camera: Vec, position: Vec, rot: [3]Angle, m: *const Mesh, screen: []Screen, out: []Poly, opts: Options) []Poly {
    const r = fm.rotation(rot);
    const rel = sub(position, camera);
    if (!inside(lens, rel, m.radius)) return out[0..0];
    for (m.verts, screen[0..m.verts.len]) |v, *s| {
        const zr = fm.dot(r[2], v.x, v.y, v.z) + rel.z;
        if (zr <= lens.zr_lo or zr >= lens.zr_hi) {
            s.usable = false;
            continue;
        }
        const w: i64 = -zr; // > 0: zr_hi is below -near
        s.* = .{
            .x = lens.half_w + perspective(lens.kx * (fm.dot(r[0], v.x, v.y, v.z) + rel.x), w),
            .y = lens.half_h - perspective(lens.ky * (fm.dot(r[1], v.x, v.y, v.z) + rel.y), w),
            .usable = true,
        };
    }
    var n: usize = 0;
    for (m.faces, m.centroids) |f, c| {
        if (!poly.usable(f, screen)) continue;
        if (!opts.double_sided and !poly.clockwise(f, screen)) continue;
        var p = Poly{ .pts = undefined, .n = f.n, .ink = f.ink, .depth = -(fm.dot(r[2], c.x, c.y, c.z) + rel.z) };
        for (0..f.n) |i| p.pts[i] = .{ screen[f.v[i]].x, screen[f.v[i]].y };
        if (opts.overdraw) poly.overdraw(&p);
        poly.insert(out[0 .. n + 1], p);
        n += 1;
    }
    return out[0..n];
}

/// k * coordinate / w, k in Q20 and the coordinate and w in Q16: Q20 canvas
/// pixels, rounded to Q12 and held to +-2^18 px so the sum with the half
/// width cannot overflow.
fn perspective(num: i64, w: i64) i32 {
    const q = std.math.clamp(@divTrunc(num, w), -(1 << 38), 1 << 38);
    return @intCast((q + 128) >> 8);
}
