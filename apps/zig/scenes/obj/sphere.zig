// --------------------------------------------------------------------------
// OBJ demo: the procedural UV sphere, LEVELS resolutions from 36 faces up to
// what the mesh arrays hold (3968). Built into a Mesh when the sphere is
// chosen or + / - changes its level, never per frame, from the integer sine
// table (fixed3d.sin16): `lon` meridians, `lat` bands, two poles.
// V = 2 + lon * (lat - 1), F = 2 * lon * (lat - 1). Faces wind like the OBJ
// files (counter-clockwise seen from outside), so the same cull works.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const fx = @import("fixed3d.zig");
const fmesh = @import("fmesh.zig");

pub const Level = struct { lon: u16, lat: u16 };

pub const LEVELS = [_]Level{
    .{ .lon = 6, .lat = 4 },   .{ .lon = 8, .lat = 5 },   .{ .lon = 10, .lat = 6 },
    .{ .lon = 12, .lat = 8 },  .{ .lon = 16, .lat = 10 }, .{ .lon = 20, .lat = 12 },
    .{ .lon = 24, .lat = 14 }, .{ .lon = 28, .lat = 16 }, .{ .lon = 32, .lat = 18 },
    .{ .lon = 40, .lat = 20 }, .{ .lon = 48, .lat = 24 }, .{ .lon = 56, .lat = 28 },
    .{ .lon = 64, .lat = 32 },
};

pub fn verts(l: Level) u16 {
    return 2 + l.lon * (l.lat - 1);
}
pub fn faces(l: Level) u16 {
    return 2 * l.lon * (l.lat - 1);
}

comptime {
    const last = LEVELS[LEVELS.len - 1];
    if (verts(last) > fmesh.MAX_VERTS or faces(last) > fmesh.MAX_FACES) @compileError("sphere level too big");
}

/// A fraction n / d of a turn as an Angle.
fn turnFrac(n: u32, d: u32) fx.Angle {
    return @truncate((@as(u64, n) << 32) / d);
}

fn q14(v16: i32) i16 {
    return @intCast((v16 + 2) >> 2);
}

/// Vertex 0 is the north pole (+y), then the rings top-down, then the south pole.
fn ring(m: *fmesh.Mesh, l: Level) void {
    m.verts[0] = .{ 0, fx.ONE, 0 };
    var n: u16 = 1;
    for (1..l.lat) |i| {
        const th = turnFrac(@intCast(i), 2 * @as(u32, l.lat)); // i / lat of a half turn
        const r = fx.sin16(th);
        const y = q14(fx.cos16(th));
        for (0..l.lon) |j| {
            const ph = turnFrac(@intCast(j), l.lon);
            m.verts[n] = .{ q14(@truncate((@as(i64, r) * fx.cos16(ph)) >> 16)), y, q14(@truncate((@as(i64, r) * fx.sin16(ph)) >> 16)) };
            n += 1;
        }
    }
    m.verts[n] = .{ 0, -fx.ONE, 0 };
    m.nverts = n + 1;
}

fn tri(m: *fmesh.Mesh, a: u16, b: u16, c: u16) void {
    m.faces[m.nfaces] = .{ .a = a, .b = b, .c = c };
    m.nfaces += 1;
}

/// The sphere at level `l` into `m`, normals and edges included.
pub fn build(m: *fmesh.Mesh, l: Level) void {
    ring(m, l);
    m.nfaces = 0;
    const south: u16 = m.nverts - 1;
    for (0..l.lon) |jj| {
        const j: u16 = @intCast(jj);
        const j1: u16 = (j + 1) % l.lon;
        tri(m, 0, 1 + j1, 1 + j); // north cap
        var i: u16 = 0;
        while (i + 2 < l.lat) : (i += 1) { // the band between ring i and ring i+1
            const a = 1 + i * l.lon;
            const b = a + l.lon;
            tri(m, a + j, a + j1, b + j);
            tri(m, a + j1, b + j1, b + j);
        }
        const last = 1 + (l.lat - 2) * l.lon;
        tri(m, south, last + j, last + j1); // south cap
    }
    m.finish();
}
