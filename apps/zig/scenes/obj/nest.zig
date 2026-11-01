// --------------------------------------------------------------------------
// OBJ demo: GLENZ NEST, object 4. Four convex shells, one inside the other:
// a dodecahedron (radius 1.4, the skin), an icosahedron (1.09), a dodecahedron
// again (0.84) and the cube (0.64) on its corners. Dodecahedron and
// icosahedron are duals in these coordinates, so each shell's corners point
// at the middle of the faces around it and none pokes out (each radius is
// under the inradius around it, 0.795 of that shell's radius).
//
// It exists to make key C's CPU/CHISEL split show on the board: in GLENZ every
// face of every shell ORs its bit, four shells give up to eight layers over a
// ~130 px object, so the frame is per-pixel work, not per-face setup. 1.4 is
// as big as it gets: a corner then projects at most 73 rows from the centre,
// inside rows 24..175 (the object's; the HUD has the rest), and fixed3d's
// projection stays in 32 bits (|p| <= 22938, depth >= 1.8). The CPU's OR
// reads every byte it writes; CHISEL's TRIANGLE does it in the blitter.
// The solid modes (FLAT, SOFT, GOURAUD, HIDDEN) draw the skin only: it hides
// the inner shells, and a painter's sort of all four would let an inner front
// face through a sideways outer one (Mesh.nskin).
//
// The meshes are built at compile time: each shell's corners from the
// textbook coordinates (f64, comptime only), its faces as the convex hull
// (every plane through three corners with all the others on one side, its
// corners in angle order, fanned into triangles). fmesh.finish() then turns
// the faces outward, as for the OBJ files. No ZigOS import (obj/tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const fmesh = @import("fmesh.zig");

const P3 = [3]f64;
const PHI: f64 = (1.0 + @sqrt(5.0)) / 2.0;
const IPHI: f64 = 1.0 / PHI;

const DODECA = blk: {
    var p: [20]P3 = undefined;
    var n: usize = 0;
    for ([2]f64{ -1, 1 }) |x| for ([2]f64{ -1, 1 }) |y| for ([2]f64{ -1, 1 }) |z| {
        p[n] = .{ x, y, z };
        n += 1;
    };
    for ([2]f64{ -1, 1 }) |a| for ([2]f64{ -1, 1 }) |b| {
        p[n] = .{ 0, a * IPHI, b * PHI };
        p[n + 1] = .{ a * IPHI, b * PHI, 0 };
        p[n + 2] = .{ a * PHI, 0, b * IPHI };
        n += 3;
    };
    break :blk p;
};

const ICOSA = blk: {
    var p: [12]P3 = undefined;
    var n: usize = 0;
    for ([2]f64{ -1, 1 }) |a| for ([2]f64{ -1, 1 }) |b| {
        p[n] = .{ 0, a, b * PHI };
        p[n + 1] = .{ a, b * PHI, 0 };
        p[n + 2] = .{ b * PHI, 0, a };
        n += 3;
    };
    break :blk p;
};

const CUBE = DODECA[0..8].*; // the dodecahedron's (+-1, +-1, +-1) corners

/// The skin's radius (Q14 units of the other objects' 1.0).
pub const RADIUS: f64 = 1.4;
/// Each shell's radius, outer first (obj/nest_tests.zig checks the corners).
pub const RADII = [4]f64{ RADIUS, RADIUS * 0.78, RADIUS * 0.6, RADIUS * 0.46 };

const Shell = struct { pts: []const P3, radius: f64 };
/// Outer first: the skin's faces are the mesh's first SKIN faces.
const SHELLS = [_]Shell{
    .{ .pts = &DODECA, .radius = RADII[0] },
    .{ .pts = &ICOSA, .radius = RADII[1] },
    .{ .pts = &DODECA, .radius = RADII[2] },
    .{ .pts = &CUBE, .radius = RADII[3] },
};

fn sub(a: P3, b: P3) P3 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn dot(a: P3, b: P3) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: P3, b: P3) P3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

const Tris = struct { n: usize = 0, t: [64][3]u16 = undefined };

/// The hull's faces through corners i < j < k, each plane once (when i, j, k
/// are its three lowest corners), fanned in angle order around the centroid.
fn hull(comptime pts: []const P3) Tris {
    @setEvalBranchQuota(2_000_000);
    var out = Tris{};
    for (0..pts.len) |i| for (i + 1..pts.len) |j| for (j + 1..pts.len) |k| {
        const nrm = cross(sub(pts[j], pts[i]), sub(pts[k], pts[i]));
        if (dot(nrm, nrm) < 1e-9) continue;
        var on: [8]usize = undefined;
        var non: usize = 0;
        var pos = false;
        var neg = false;
        for (pts, 0..) |q, m| {
            const d = dot(nrm, sub(q, pts[i]));
            if (@abs(d) < 1e-6) {
                on[non] = m;
                non += 1;
            } else if (d > 0) pos = true else neg = true;
        }
        if ((pos and neg) or on[0] != i or on[1] != j or on[2] != k) continue;
        fan(&out, pts, on[0..non], nrm);
    };
    return out;
}

fn fan(out: *Tris, pts: []const P3, on: []usize, nrm: P3) void {
    var c: P3 = .{ 0, 0, 0 };
    for (on) |m| c = .{ c[0] + pts[m][0], c[1] + pts[m][1], c[2] + pts[m][2] };
    const inv = 1.0 / @as(f64, @floatFromInt(on.len));
    c = .{ c[0] * inv, c[1] * inv, c[2] * inv };
    const u = sub(pts[on[0]], c);
    const w = cross(nrm, u);
    var ang: [8]f64 = undefined;
    for (on, 0..) |m, a| ang[a] = std.math.atan2(dot(sub(pts[m], c), w), dot(sub(pts[m], c), u));
    for (1..on.len) |a| { // insertion sort by angle
        var b = a;
        while (b > 0 and ang[b] < ang[b - 1]) : (b -= 1) {
            std.mem.swap(f64, &ang[b], &ang[b - 1]);
            std.mem.swap(usize, &on[b], &on[b - 1]);
        }
    }
    for (1..on.len - 1) |a| {
        out.t[out.n] = .{ @intCast(on[0]), @intCast(on[a]), @intCast(on[a + 1]) };
        out.n += 1;
    }
}

const Built = struct { nv: usize, nf: usize, skin: usize, v: [96]fmesh.V3, f: [160][3]u16 };

const BUILT: Built = blk: {
    var b = Built{ .nv = 0, .nf = 0, .skin = 0, .v = undefined, .f = undefined };
    for (SHELLS, 0..) |s, si| {
        const base = b.nv;
        for (s.pts) |p| {
            const scale = s.radius / @sqrt(dot(p, p)) * 16384.0;
            b.v[b.nv] = .{ @intFromFloat(@round(p[0] * scale)), @intFromFloat(@round(p[1] * scale)), @intFromFloat(@round(p[2] * scale)), 0 };
            b.nv += 1;
        }
        const h = hull(s.pts);
        for (h.t[0..h.n]) |t| {
            b.f[b.nf] = .{ base + t[0], base + t[1], base + t[2] };
            b.nf += 1;
        }
        if (si == 0) b.skin = b.nf;
    }
    break :blk b;
};

pub const VERTS = BUILT.nv; // 20 + 12 + 20 + 8
pub const FACES = BUILT.nf; // 36 + 20 + 36 + 12
pub const SKIN = BUILT.skin; // the dodecahedron's 12 pentagons, 3 triangles each

comptime {
    if (VERTS != 60 or FACES != 104 or SKIN != 36) @compileError("GLENZ NEST: unexpected hull");
}

/// The nest into `m`, normals and edges included; only the skin is solid.
pub fn build(m: *fmesh.Mesh) void {
    m.nverts = VERTS;
    for (BUILT.v[0..VERTS], 0..) |v, i| m.verts[i] = v;
    m.nfaces = FACES;
    for (BUILT.f[0..FACES], 0..) |f, i| m.faces[i] = .{ .a = f[0], .b = f[1], .c = f[2] };
    m.finish();
    m.nskin = SKIN;
}
