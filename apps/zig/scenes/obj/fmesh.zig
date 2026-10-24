// --------------------------------------------------------------------------
// OBJ demo: a mesh in Q14 integers, ready for the per-frame fixed-point path.
//
// Built when a model is chosen (init, or a key press), never per frame:
// vertices from the OBJ loader's f32 (or sphere.zig's integers), the face and
// vertex normals (float here is fine: this runs once a model), and the edge
// list (each edge once, with the two faces that share it) for hidden-line.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const fx = @import("fixed3d.zig");

pub const MAX_VERTS = 2048;
pub const MAX_FACES = 4096;
pub const MAX_EDGES = MAX_FACES * 3 / 2 + 64;
pub const NO_FACE: u16 = 0xFFFF;

/// 16 bytes, word-aligned: the vertices, the winding flag and the outward
/// normal side by side, so the per-frame cull reads one cache line for both.
pub const Face = struct { a: u16, b: u16, c: u16, inward: u16 = 0, n: V3 = .{ 0, 0, 0, 0 } };
pub const Edge = struct { a: u16, b: u16, f0: u16, f1: u16 };
pub const V3 = fx.V;

pub const Mesh = struct {
    nverts: u16 = 0,
    nfaces: u16 = 0,
    nedges: u16 = 0,
    verts: [MAX_VERTS]V3 align(8) = undefined,
    vnorm: [MAX_VERTS]V3 align(8) = undefined,
    faces: [MAX_FACES]Face align(8) = undefined,
    edges: [MAX_EDGES]Edge = undefined,
    half: [MAX_FACES * 3]u64 = undefined, // scratch: (vertex pair << 16 | half-edge id), sorted
    acc: [MAX_VERTS][3]i32 = undefined, // scratch: summed face normals

    /// Normals and edges, once the vertices and faces are in.
    pub fn finish(self: *Mesh) void {
        self.normals();
        self.buildEdges();
    }

    fn normals(self: *Mesh) void {
        const acc = &self.acc;
        for (acc[0..self.nverts]) |*a| a.* = .{ 0, 0, 0 };
        for (self.faces[0..self.nfaces], 0..) |f, i| {
            self.orient(i, unit(faceCross(self.verts[f.a], self.verts[f.b], self.verts[f.c])));
            for ([3]u16{ f.a, f.b, f.c }) |v| {
                for (0..3) |k| acc[v][k] += self.faces[i].n[k];
            }
        }
        for (acc[0..self.nverts], 0..) |a, i| {
            self.vnorm[i] = unit(.{ @floatFromInt(a[0]), @floatFromInt(a[1]), @floatFromInt(a[2]) });
        }
    }

    /// The models are star-shaped around their centre (the loader recentres),
    /// so outward is away from it. The faces keep their vertex order (WIRE's
    /// lines run a -> b -> c as in the file); culling reads `inward` instead.
    fn orient(self: *Mesh, i: usize, n: V3) void {
        const f = self.faces[i];
        var away: i64 = 0;
        for (0..3) |k| away += @as(i64, n[k]) * (@as(i32, self.verts[f.a][k]) + self.verts[f.b][k] + self.verts[f.c][k]);
        self.faces[i].inward = @intFromBool(away < 0); // wound clockwise seen from outside
        self.faces[i].n = if (away < 0) .{ -n[0], -n[1], -n[2], 0 } else n;
    }

    /// Each edge once: sort the 3F half-edges by their vertex pair (packed
    /// with the half-edge id into one u64, so the sort compares plain integers
    /// and reads no face twice), then a run of equal pairs is one edge (two
    /// faces on a closed mesh, one on a rim).
    fn buildEdges(self: *Mesh) void {
        const nh: usize = @as(usize, self.nfaces) * 3;
        for (self.faces[0..self.nfaces], 0..) |f, i| {
            const vs = [3]u16{ f.a, f.b, f.c };
            for (0..3) |k| {
                const x = vs[k];
                const y = vs[(k + 1) % 3];
                const pair = (@as(u64, @min(x, y)) << 16) | @max(x, y);
                self.half[i * 3 + k] = (pair << 16) | (i * 3 + k);
            }
        }
        std.sort.pdq(u64, self.half[0..nh], {}, std.sort.asc(u64));
        self.nedges = 0;
        var i: usize = 0;
        while (i < nh and self.nedges < MAX_EDGES) {
            const pair = self.half[i] >> 16;
            const face = struct {
                fn of(h: u64) u16 {
                    return @intCast((h & 0xFFFF) / 3);
                }
            }.of;
            var e = Edge{ .a = @intCast(pair >> 16), .b = @intCast(pair & 0xFFFF), .f0 = face(self.half[i]), .f1 = NO_FACE };
            i += 1;
            if (i < nh and self.half[i] >> 16 == pair) {
                e.f1 = face(self.half[i]);
                i += 1;
            }
            while (i < nh and self.half[i] >> 16 == pair) i += 1; // non-manifold extras
            self.edges[self.nedges] = e;
            self.nedges += 1;
        }
    }
};

/// A coordinate at radius <= 1 (the loader normalises) as Q14. Load time only.
pub fn q14(v: f32) i16 {
    return @intFromFloat(@round(@max(-1.0, @min(v, 1.0)) * 16384.0));
}

fn faceCross(a: V3, b: V3, c: V3) [3]f32 {
    var e1: [3]f32 = undefined;
    var e2: [3]f32 = undefined;
    for (0..3) |k| {
        e1[k] = @floatFromInt(@as(i32, b[k]) - a[k]);
        e2[k] = @floatFromInt(@as(i32, c[k]) - a[k]);
    }
    return .{ e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
}

fn unit(n: [3]f32) V3 {
    const l = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    if (l < 1e-6) return .{ 0, 0, 0, 0 };
    var r: V3 = .{ 0, 0, 0, 0 };
    for (0..3) |k| r[k] = @intFromFloat(@round(n[k] / l * 16383.0));
    return r;
}
