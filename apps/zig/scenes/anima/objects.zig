// --------------------------------------------------------------------------
// The glenz objects, built at compile time: vertices scaled to radius 1 (f32),
// triangles wound counter-clockwise seen from outside (the builder checks each
// one against its centroid and swaps the ones that are not).
//
//   cube          8 vertices, 12 triangles
//   octahedron    6 vertices,  8 triangles
//   icosahedron  12 vertices, 20 triangles
//   star          an octahedron with a spike raised on every face:
//                14 vertices, 24 triangles (not convex: front faces overlap
//                there, and the glenz shows it)
// --------------------------------------------------------------------------
pub const MAX_V = 14;
pub const MAX_T = 24;

pub const Object = struct {
    nv: usize,
    nt: usize,
    per_face: usize, // triangles a face (2 for the cube's quads): one glenz lane a face
    v: [MAX_V][3]f32,
    t: [MAX_T][3]u8,
};

fn make(comptime verts: []const [3]f64, comptime tris: []const [3]u8, comptime per_face: usize) Object {
    @setEvalBranchQuota(100_000);
    var o: Object = .{ .nv = verts.len, .nt = tris.len, .per_face = per_face, .v = undefined, .t = undefined };
    var r: f64 = 0;
    for (verts) |p| r = @max(r, @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]));
    for (verts, 0..) |p, i| o.v[i] = .{ @floatCast(p[0] / r), @floatCast(p[1] / r), @floatCast(p[2] / r) };
    for (tris, 0..) |t, i| {
        const a = verts[t[0]];
        const b = verts[t[1]];
        const c = verts[t[2]];
        const u = [3]f64{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
        const w = [3]f64{ c[0] - a[0], c[1] - a[1], c[2] - a[2] };
        const n = [3]f64{ u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0] };
        const g = [3]f64{ a[0] + b[0] + c[0], a[1] + b[1] + c[1], a[2] + b[2] + c[2] };
        o.t[i] = if (n[0] * g[0] + n[1] * g[1] + n[2] * g[2] >= 0) t else .{ t[0], t[2], t[1] };
    }
    return o;
}

const CUBE_V = [_][3]f64{ .{ -1, -1, -1 }, .{ 1, -1, -1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 }, .{ -1, -1, 1 }, .{ 1, -1, 1 }, .{ 1, 1, 1 }, .{ -1, 1, 1 } };
const CUBE_T = [_][3]u8{ .{ 0, 1, 2 }, .{ 0, 2, 3 }, .{ 4, 6, 5 }, .{ 4, 7, 6 }, .{ 0, 4, 5 }, .{ 0, 5, 1 }, .{ 3, 2, 6 }, .{ 3, 6, 7 }, .{ 0, 3, 7 }, .{ 0, 7, 4 }, .{ 1, 5, 6 }, .{ 1, 6, 2 } };

const OCTA_V = [_][3]f64{ .{ 1, 0, 0 }, .{ -1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, -1, 0 }, .{ 0, 0, 1 }, .{ 0, 0, -1 } };
const OCTA_T = [_][3]u8{ .{ 0, 2, 4 }, .{ 2, 1, 4 }, .{ 1, 3, 4 }, .{ 3, 0, 4 }, .{ 2, 0, 5 }, .{ 1, 2, 5 }, .{ 3, 1, 5 }, .{ 0, 3, 5 } };

const PHI = 1.618033988749895;
const ICO_V = [_][3]f64{
    .{ -1, PHI, 0 }, .{ 1, PHI, 0 }, .{ -1, -PHI, 0 }, .{ 1, -PHI, 0 },
    .{ 0, -1, PHI }, .{ 0, 1, PHI }, .{ 0, -1, -PHI }, .{ 0, 1, -PHI },
    .{ PHI, 0, -1 }, .{ PHI, 0, 1 }, .{ -PHI, 0, -1 }, .{ -PHI, 0, 1 },
};
const ICO_T = [_][3]u8{
    .{ 0, 11, 5 }, .{ 0, 5, 1 },  .{ 0, 1, 7 },   .{ 0, 7, 10 }, .{ 0, 10, 11 },
    .{ 1, 5, 9 },  .{ 5, 11, 4 }, .{ 11, 10, 2 }, .{ 10, 7, 6 }, .{ 7, 1, 8 },
    .{ 3, 9, 4 },  .{ 3, 4, 2 },  .{ 3, 2, 6 },   .{ 3, 6, 8 },  .{ 3, 8, 9 },
    .{ 4, 9, 5 },  .{ 2, 4, 11 }, .{ 6, 2, 10 },  .{ 8, 6, 7 },  .{ 9, 8, 1 },
};

// The star: each octahedron face gets an apex at 1.9x its centroid's direction.
const STAR = blk: {
    var v: [14][3]f64 = undefined;
    var t: [24][3]u8 = undefined;
    for (OCTA_V, 0..) |p, i| v[i] = p;
    for (OCTA_T, 0..) |f, i| {
        var g = [3]f64{ 0, 0, 0 };
        for (f) |k| for (0..3) |a| {
            g[a] += OCTA_V[k][a];
        };
        const apex: u8 = 6 + i;
        for (0..3) |a| v[apex][a] = g[a] / 3.0 * 1.9 * 1.732;
        t[3 * i + 0] = .{ f[0], f[1], apex };
        t[3 * i + 1] = .{ f[1], f[2], apex };
        t[3 * i + 2] = .{ f[2], f[0], apex };
    }
    break :blk .{ v, t };
};

pub const ALL = [_]Object{
    make(&CUBE_V, &CUBE_T, 2),
    make(&OCTA_V, &OCTA_T, 1),
    make(&ICO_V, &ICO_T, 1),
    make(&STAR[0], &STAR[1], 1),
};
