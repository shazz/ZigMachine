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
//   canvas    Q14 (i32, math.PX): 1/16384 px, held to +-65536 px. Q14 because
//             union_tnt3 replays three.js pixel for pixel (Q12 left one ball
//             pixel off in its 21 checked frames); the range because a vertex just
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
pub const sortFarToNear = poly.sortFarToNear;

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
    alias: ?[]const u16 = null, // zig3d.Mesh.alias: twins copy the first copy's Screen
};

/// A zig3d mesh converted at run time (init): `verts` and `centroids` need
/// as many entries as the mesh has.
pub fn fromMesh(m: *const c3.Mesh, verts: []Vec, centroids: []Vec) Mesh {
    for (m.verts, verts[0..m.verts.len]) |v, *o| o.* = q16(v);
    for (m.centroids, centroids[0..m.centroids.len]) |c, *o| o.* = q16(c);
    return .{ .verts = verts[0..m.verts.len], .faces = m.faces, .centroids = centroids[0..m.centroids.len], .radius = toQ16(m.radius), .alias = m.alias };
}

/// A zig3d mesh known at compile time, converted at compile time.
pub fn comptimeMesh(comptime m: c3.Mesh) Mesh {
    const T = struct { // container constants: global, so a run-time Mesh may point at them
        const verts = convert(m.verts);
        const centroids = convert(m.centroids);
    };
    return .{ .verts = &T.verts, .faces = m.faces, .centroids = &T.centroids, .radius = toQ16(m.radius), .alias = m.alias };
}

fn convert(comptime in: []const c3.Vec3) [in.len]Vec {
    @setEvalBranchQuota(100_000);
    var out: [in.len]Vec = undefined;
    for (in, &out) |x, *o| o.* = q16(x);
    return out;
}

/// A frustum plane through the camera's origin frame: Q30 normal, Q16 offset.
const Plane = struct { n: [3]i32, d: i32 };

/// Everything the projection needs from zig3d's Lens, derived once.
pub const Lens = struct {
    kx: i64, // P[0] * half width, Q20
    ky: i64, // P[5] * half height, Q20
    half_w: i32, // canvas pixels, 1 px = fm.ONE_PX
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
            .half_w = @intFromFloat(l.half_w * fm.ONE_PX),
            .half_h = @intFromFloat(l.half_h * fm.ONE_PX),
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
/// `out` m.faces.len. Returns the faces to fill, far to near, in fixed-point canvas
/// pixels. Every coordinate here stays inside +-32767 world units.
pub fn project(lens: *const Lens, camera: Vec, position: Vec, rot: [3]Angle, m: *const Mesh, screen: []Screen, out: []Poly, opts: Options) []Poly {
    const r = fm.rotation(rot);
    const rel = sub(position, camera);
    if (!inside(lens, rel, m.radius)) return out[0..0];
    for (m.verts, screen[0..m.verts.len], 0..) |v, *s, i| {
        if (m.alias) |al| if (al[i] != i) {
            s.* = screen[al[i]];
            continue;
        };
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
        const p = &out[n];
        p.* = .{ .pts = undefined, .n = f.n, .ink = f.ink, .depth = -(fm.dotWide(r[2], c.x, c.y, c.z) + (@as(i64, rel.z) << 30)) };
        for (0..f.n) |i| p.pts[i] = .{ screen[f.v[i]].x, screen[f.v[i]].y };
        if (opts.overdraw) poly.overdraw(p);
        n += 1;
    }
    poly.sortFarToNear(out[0..n]);
    return out[0..n];
}

/// k * coordinate / w, k in Q20 and the coordinate and w in Q16: Q20 canvas
/// pixels, rounded to PX bits and held to +-2^(30-PX) px so the sum with the half
/// width cannot overflow.
fn perspective(num: i64, w: i64) i32 {
    const q = std.math.clamp(@divTrunc(num, w), -(1 << (50 - fm.PX)), 1 << (50 - fm.PX));
    return @intCast((q + (1 << (19 - fm.PX))) >> (20 - fm.PX));
}
