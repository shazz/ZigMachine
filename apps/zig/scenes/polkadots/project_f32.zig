// --------------------------------------------------------------------------
// polkadots_f32's projection: zig3d.project (three.js r49's Projector, as
// codef3D drives it) for this one scene, in f32 — the planned FPU is single
// precision, and zig3d itself is f64. The camera sits on the z axis with no
// rotation and the torus at the origin, so the view matrix is a translation and
// three.js's matrix chain is written out as the products it reduces to; every
// per-vertex and per-face step of the original is kept (clip, usable test,
// facing test, centroid depth, CanvasRenderer's 1 px overdraw, the depth sort).
// The frustum test is not: the torus never leaves the view.
// --------------------------------------------------------------------------
const std = @import("std");
const c3 = @import("zigos").zig3d;
const shade = @import("shade.zig");
const torus = @import("torus.zig");

pub const V3 = struct { x: f32, y: f32, z: f32 };
pub const Poly = struct { pts: [4][2]f32, n: u8, ink: u8, z: f32 };
const Screen = struct { x: f32, y: f32, usable: bool };

/// The lens's entries the camera reaches (perspective: P0, P5, P10, P14).
pub const Lens = struct {
    p0: f32,
    p5: f32,
    p10: f32,
    p14: f32,
    half_w: f32,
    half_h: f32,

    pub fn init() Lens {
        const l = c3.Lens.init(shade.CELLS_X, shade.CELLS_Y, shade.FOV, shade.NEAR, shade.FAR);
        const e = l.projection.e;
        return .{ .p0 = e[0], .p5 = e[5], .p10 = e[10], .p14 = e[14], .half_w = @floatCast(l.half_w), .half_h = @floatCast(l.half_h) };
    }
};

/// Object3D.updateMatrix's rotation (Euler XYZ, z = 0) as its 3x3 rows.
pub fn rotation(rx: f32, ry: f32) [3]V3 {
    const g = @cos(rx);
    const d = @sin(rx);
    const h = @cos(ry);
    const e = @sin(ry);
    return .{
        .{ .x = h, .y = 0, .z = e },
        .{ .x = d * e, .y = g, .z = -d * h },
        .{ .x = -g * e, .y = d, .z = g * h },
    };
}

fn apply(m: *const [3]V3, v: V3) V3 {
    return .{
        .x = m[0].x * v.x + m[0].y * v.y + m[0].z * v.z,
        .y = m[1].x * v.x + m[1].y * v.y + m[1].z * v.z,
        .z = m[2].x * v.x + m[2].y * v.y + m[2].z * v.z,
    };
}

/// The faces to fill this frame, in small-canvas pixels: `out` holds them in
/// mesh order and the returned indices put them far to near. Sorting the
/// 2-byte indices (the same insertion sort, so the same order) moves a u16 a
/// step where sorting the 44-byte Polys moved eleven words.
pub fn project(lens: *const Lens, m: *const [3]V3, verts: []const V3, centroids: []const V3, faces: []const c3.Face, screen: []Screen, out: []Poly, order: []u16) []const u16 {
    for (verts, screen[0..verts.len]) |v, *s| {
        const w = apply(m, v);
        const cw = shade.CAM_Z - w.z;
        const cz = lens.p10 * (w.z - shade.CAM_Z) + lens.p14;
        s.* = .{ .x = lens.p0 * w.x / cw, .y = lens.p5 * w.y / cw, .usable = cz > shade.NEAR and cz < shade.FAR };
    }
    var n: usize = 0;
    for (faces, centroids) |f, centroid| {
        const s = screen;
        if (!s[f.v[0]].usable or !s[f.v[1]].usable or !s[f.v[2]].usable or !s[f.v[3]].usable) continue;
        if (!clockwise(f, s)) continue;
        const c = apply(m, centroid);
        const depth = (lens.p10 * (c.z - shade.CAM_Z) + lens.p14) / (shade.CAM_Z - c.z);
        var p = Poly{ .pts = undefined, .n = 4, .ink = f.ink, .z = depth };
        for (0..4) |i| p.pts[i] = .{ s[f.v[i]].x * lens.half_w, s[f.v[i]].y * lens.half_h };
        overdraw(&p);
        for (&p.pts) |*pt| pt.* = .{ pt[0] + lens.half_w, -pt[1] + lens.half_h };
        out[n] = p;
        order[n] = @intCast(n);
        n += 1;
    }
    std.sort.insertion(u16, order[0..n], @as([]const Poly, out), farther);
    return order[0..n];
}

pub const ScreenBuf = [torus.VERTS]Screen;

fn farther(polys: []const Poly, a: u16, b: u16) bool {
    return polys[b].z - polys[a].z < 0;
}

/// Projector's facing test, in divided clip space (a Face4).
fn clockwise(f: c3.Face, s: []const Screen) bool {
    const v1 = s[f.v[0]];
    const v2 = s[f.v[1]];
    const v3 = s[f.v[2]];
    const v4 = s[f.v[3]];
    return (v4.x - v1.x) * (v2.y - v1.y) - (v4.y - v1.y) * (v2.x - v1.x) < 0 or
        (v2.x - v3.x) * (v4.y - v3.y) - (v2.y - v3.y) * (v4.x - v3.x) < 0;
}

/// CanvasRenderer's overdraw for a Face4: pushes (1,2) (2,4) (4,1), then moves
/// 3 away from the un-pushed 2 and 4.
fn overdraw(p: *Poly) void {
    const pt = &p.pts;
    var v2 = pt[1];
    var v4 = pt[3];
    push(&pt[0], &pt[1]);
    push(&pt[1], &pt[3]);
    push(&pt[3], &pt[0]);
    push(&pt[2], &v2);
    push(&pt[2], &v4);
}

/// a and b each move 1 px apart along their line.
fn push(a: *[2]f32, b: *[2]f32) void {
    var cx = b[0] - a[0];
    var cy = b[1] - a[1];
    var e = cx * cx + cy * cy;
    if (e == 0) return;
    e = 1.0 / @sqrt(e);
    cx *= e;
    cy *= e;
    b[0] += cx;
    b[1] += cy;
    a[0] -= cx;
    a[1] -= cy;
}
