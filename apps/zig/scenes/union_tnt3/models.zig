// --------------------------------------------------------------------------
// TNT3's five objects, from screen.js's own tables: vertices, faces (vertex
// indices and material colour, in the source's order) and the camera, start
// rotation and spin each key sets (screen.js:720-788).
//
// Vertex arithmetic keeps the source's order ((262-71)*1.2, x/4, z*150/4...),
// so the doubles are the ones three.js got. Only the sphere needs cos/sin: its
// vertices are built at run time (Ball.build), where the machine's trigonometry
// is fdlibm's, as the browser's is.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const c3 = zg.codef3d;
const A = @import("assets.zig");
const Vec3 = c3.Vec3;
const Face = c3.Face;

pub const Model = struct {
    parts: []const c3.Mesh, // one codef3D engine each, drawn in order
    camera: Vec3, // nextCamPosition
    rotation: Vec3, // nextObjRotation
    speed: Vec3, // nextObjRotSpeed
};

const PI = std.math.pi;
const TURN = Vec3{ .x = 0.02, .y = 0.02, .z = 0.02 };
const ORIGIN = Vec3{ .x = 0, .y = 0, .z = 0 };

pub const UNION = Model{ .parts = &.{c3.mesh(&uv2_verts, &UV2_FACES)}, .camera = ORIGIN, .rotation = .{ .x = 0, .y = 0, .z = PI }, .speed = TURN };
pub const TNT = Model{ .parts = &.{c3.mesh(&tnt_verts, &TNT_FACES)}, .camera = .{ .x = 0, .y = 0, .z = 100 }, .rotation = .{ .x = 0, .y = 0, .z = PI }, .speed = TURN };
// BALL is built at run time: see Ball below.
pub const GLIDER = Model{
    .parts = &.{ c3.mesh(&glider_verts, &GLIDER_BASE), c3.mesh(&glider_verts, &GLIDER_TOP) },
    .camera = ORIGIN,
    .rotation = .{ .x = -PI / 2.0, .y = 0, .z = 0 },
    .speed = .{ .x = 0.033, .y = 0.032, .z = 0.031 },
};
pub const CARRIER = Model{
    .parts = &.{ c3.mesh(&carrier_verts, &CARRIER_BOTTOM), c3.mesh(&carrier_verts, &CARRIER_PLANE), c3.mesh(&carrier_verts, &CARRIER_TOP) },
    .camera = .{ .x = 0, .y = 70, .z = 100 },
    .rotation = .{ .x = -PI / 2.0, .y = 0, .z = PI / 3.0 },
    .speed = .{ .x = 0, .y = 0, .z = 0.02 },
};

pub const MAX_PARTS = 3;
pub const MAX_VERTS = SPHERE_VERTS;
pub const MAX_FACES = SPHERE_FACES;

fn quad(a: u16, b: u16, c: u16, d: u16, comptime rgb: u24) Face {
    return .{ .v = .{ a, b, c, d }, .n = 4, .ink = A.ink(rgb) };
}
fn tri(a: u16, b: u16, c: u16, comptime rgb: u24) Face {
    return .{ .v = .{ a, b, c, 0 }, .n = 3, .ink = A.ink(rgb) };
}

// ---- TNT logo (screen.js:121-255): (262 - x, y - 87) * 1.2 at z = +-50 ----
const TNT_OUTLINE = [22][2]i32{
    .{ 71, 6 },    .{ 32, 45 },   .{ 596, 45 },  .{ 634, 6 },   .{ 138, 45 },  .{ 3, 179 },
    .{ 61, 179 },  .{ 194, 44 },  .{ 469, 44 },  .{ 336, 179 }, .{ 393, 179 }, .{ 527, 44 },
    .{ 226, 67 },  .{ 114, 179 }, .{ 172, 179 }, .{ 225, 126 }, .{ 225, 179 }, .{ 282, 179 },
    .{ 282, 67 },  .{ 394, 67 },  .{ 336, 67 },  .{ 283, 121 },
};
const TNT_CUTS = [2][2]i32{ .{ 194, 6 }, .{ 469, 6 } }; // "decoupage des grandes faces"
fn tntVert(p: [2]i32, z: f64) Vec3 {
    return .{ .x = @as(f64, @floatFromInt(262 - p[0])) * 1.2, .y = @as(f64, @floatFromInt(p[1] - 87)) * 1.2, .z = z };
}
const tnt_verts = blk: {
    var v: [48]Vec3 = undefined;
    for (TNT_OUTLINE, 0..) |p, i| {
        v[i] = tntVert(p, 50);
        v[22 + i] = tntVert(p, -50);
    }
    v[44] = tntVert(TNT_CUTS[0], 50);
    v[45] = tntVert(TNT_CUTS[1], 50);
    v[46] = tntVert(TNT_CUTS[0], -50);
    v[47] = tntVert(TNT_CUTS[1], -50);
    break :blk v;
};
const RED = 0xE00000; // tntcol1
const GREY = 0x616263; // tntcol2
const MID = 0x7F8083; // tntcol3
const LIGHT = 0xA09FA3; // tntcol4
const TNT_FACES = [_]Face{
    quad(0, 1, 7, 44, RED),      quad(44, 7, 8, 45, RED),     quad(45, 8, 2, 3, RED),
    quad(4, 5, 6, 7, RED),       quad(8, 9, 10, 11, RED),     quad(12, 13, 14, 15, RED),
    quad(12, 16, 17, 18, RED),   quad(19, 20, 21, 17, RED),   quad(22, 46, 29, 23, RED),
    quad(46, 47, 30, 29, RED),   quad(47, 25, 24, 30, RED),   quad(26, 29, 28, 27, RED),
    quad(30, 33, 32, 31, RED),   quad(34, 37, 36, 35, RED),   quad(34, 40, 39, 38, RED),
    quad(41, 39, 43, 42, RED),   quad(0, 44, 46, 22, GREY),   quad(44, 45, 47, 46, GREY),
    quad(45, 3, 25, 47, GREY),   quad(0, 22, 23, 1, MID),     quad(1, 23, 26, 4, GREY),
    quad(4, 26, 27, 5, MID),     quad(5, 27, 28, 6, GREY),    quad(6, 28, 29, 7, MID),
    quad(7, 29, 30, 8, GREY),    quad(8, 30, 31, 9, MID),     quad(9, 31, 32, 10, GREY),
    quad(10, 32, 33, 11, MID),   quad(11, 33, 24, 2, GREY),   quad(2, 24, 25, 3, MID),
    quad(18, 40, 34, 12, GREY),  quad(12, 34, 35, 13, MID),   quad(13, 35, 36, 14, GREY),
    quad(14, 36, 37, 15, LIGHT), quad(15, 37, 38, 16, MID),   quad(16, 38, 39, 17, GREY),
    quad(17, 39, 41, 19, MID),   quad(19, 41, 42, 20, GREY),  quad(20, 42, 43, 21, LIGHT),
    quad(21, 43, 40, 18, MID),
};

// ---- glider (screen.js:347-393): scaled by 1.9, Face3s ---------------------
const glider_verts = blk: {
    const raw = [7][3]f64{ .{ 0, 70, 0 }, .{ -38, 0, -3 }, .{ -8, 0, 0 }, .{ 0, 10, 20 }, .{ 8, 0, 0 }, .{ 38, 0, -3 }, .{ 0, 0, -15 } };
    var v: [7]Vec3 = undefined;
    for (raw, &v) |r, *o| o.* = .{ .x = r[0] * 1.9, .y = r[1] * 1.9, .z = r[2] * 1.9 };
    break :blk v;
};
const GLIDER_BASE = [_]Face{
    tri(0, 1, 2, 0xA00000), tri(0, 2, 3, 0xA0A0A0), tri(0, 3, 4, 0x606060), tri(3, 2, 4, 0x808080),
    tri(0, 4, 5, 0xA00000), tri(2, 1, 6, 0x606000), tri(2, 6, 4, 0x4040C0), tri(4, 6, 5, 0x606000),
};
const GLIDER_TOP = [_]Face{ tri(1, 0, 6, 0x808000), tri(6, 0, 5, 0xA0A000) };

// ---- carrier (screen.js:396-502): (62 - x, y - 127) * 2, z * 2 * 3 ---------
const carrier_verts = blk: {
    const raw = [29][3]i32{
        .{ 5, 134, 0 },   .{ 129, 134, 0 },  .{ 129, 256, 0 },   .{ 5, 256, 0 },    .{ 27, 53, 0 },   .{ 107, 53, 0 },
        .{ 44, 78, 0 },   .{ 90, 78, 0 },    .{ 90, 124, 0 },    .{ 44, 124, 0 },   .{ 28, 222, 0 },  .{ 28, 176, 0 },
        .{ 44, 159, 0 },  .{ 90, 159, 0 },   .{ 106, 176, 0 },   .{ 106, 222, 0 },  .{ 5, 4, 0 },     .{ 129, 4, 0 },
        .{ 5, 256, -10 }, .{ 5, 134, -10 },  .{ 129, 134, -10 }, .{ 129, 256, -10 }, .{ 27, 53, -10 }, .{ 107, 53, -10 },
        .{ 44, 176, 5 },  .{ 90, 176, 5 },   .{ 90, 222, 5 },    .{ 44, 222, 5 },   .{ 67, 21, 0 },
    };
    var v: [29]Vec3 = undefined;
    for (raw, &v) |r, *o| o.* = .{ .x = @floatFromInt((62 - r[0]) * 2), .y = @floatFromInt((r[1] - 127) * 2), .z = @floatFromInt(r[2] * 2 * 3) };
    break :blk v;
};
const GRIS = 0x808080;
const ORANGE = 0xC0A000;
const ROUGE = 0xA00000;
const VERT = 0x00A000;
const BLEU = 0x80A0E0;
const CARRIER_BOTTOM = [_]Face{ // DESSOUS
    quad(0, 19, 18, 3, ORANGE), quad(2, 21, 20, 1, ORANGE),  quad(19, 20, 21, 18, ORANGE),
    quad(4, 22, 19, 0, ROUGE),  quad(1, 20, 23, 5, ROUGE),   quad(22, 23, 20, 19, ROUGE),
    quad(3, 18, 21, 2, ROUGE),  quad(28, 22, 4, 4, VERT),    quad(5, 23, 28, 28, VERT),
    quad(28, 23, 22, 22, BLEU),
};
const CARRIER_PLANE = [_]Face{ quad(3, 2, 17, 16, GRIS), quad(3, 2, 1, 16, GRIS) }; // PLAN GRIS
const CARRIER_TOP = [_]Face{ // DESSUS
    quad(6, 9, 8, 7, VERT),       quad(24, 27, 26, 25, GRIS),   quad(24, 11, 10, 27, ROUGE),
    quad(25, 13, 12, 24, ROUGE),  quad(25, 26, 15, 14, ROUGE),  quad(24, 12, 11, 11, ORANGE),
    quad(25, 14, 13, 13, ORANGE), quad(27, 10, 15, 26, BLEU),
};

// ---- Union "U v2" (screen.js:505-573): (539 - x) / 4, (y - 595) / 4, z * 150 / 4
const uv2_verts = blk: {
    const raw = [12][2]i32{ .{ 25, 50 }, .{ 25, 789 }, .{ 337, 789 }, .{ 337, 50 }, .{ 99, 987 }, .{ 487, 937 }, .{ 239, 1150 }, .{ 422, 1238 }, .{ 788, 937 }, .{ 1101, 1237 }, .{ 788, 50 }, .{ 1101, 50 } };
    var v: [24]Vec3 = undefined;
    for (raw, 0..) |r, i| for ([2]f64{ 1, -1 }, 0..) |z, side| {
        v[side * 12 + i] = .{ .x = @as(f64, @floatFromInt(539 - r[0])) / 4, .y = @as(f64, @floatFromInt(r[1] - 595)) / 4, .z = z * 150 / 4 };
    };
    break :blk v;
};
const UV2_FACES = [_]Face{
    quad(0, 1, 2, 3, 0xE0A000),     quad(1, 4, 5, 2, 0xE0A000),     quad(4, 6, 7, 5, 0xE0A000), // U face
    quad(5, 7, 9, 8, 0xE0A000),     quad(8, 9, 11, 10, 0xE0A000),
    quad(12, 15, 14, 13, 0xE0A000), quad(14, 17, 16, 13, 0xE0A000), quad(17, 19, 18, 16, 0xE0A000), // U arriere
    quad(17, 20, 21, 19, 0xE0A000), quad(20, 22, 23, 21, 0xE0A000),
    quad(3, 2, 14, 15, 0x606000),   quad(2, 5, 17, 14, 0x808000),   quad(5, 8, 20, 17, 0xA0A000), // interieur
    quad(8, 10, 22, 20, 0xE0E000),
    quad(0, 3, 15, 12, 0xA0A000),   quad(10, 11, 23, 22, 0xA0A000), quad(0, 12, 13, 1, 0xE0E000), // exterieur
    quad(1, 13, 16, 4, 0xC0C000),   quad(4, 16, 18, 6, 0xA0A000),   quad(6, 18, 19, 7, 0x808000),
    quad(7, 19, 21, 9, 0x606060),   quad(11, 9, 21, 23, 0x606000),
};

// ---- ball: CreateUnitSphere(22.5, 22.5, 80) (screen.js:9-93) ---------------
const STEP = 22.5;
const RADIUS = 80.0;
const DTOR = PI / 180.0;
const ROWS = 8; // theta -90 .. 67.5
const COLS = 16; // phi 0 .. 337.5
const SPHERE_VERTS = ROWS * COLS * 4; // four per facet, poles included
const SPHERE_FACES = 96 + 16; // facets 16..111 (the closing rows dropped), then the tube

/// Facet colours: col1/col2 alternate along a row, the pattern flipping each row.
const SPHERE_FACE_TABLE = blk: {
    var f: [SPHERE_FACES]Face = undefined;
    for (16..112) |nbf| {
        const b: u16 = @intCast(nbf * 4);
        const pair_one = (nbf / COLS) % 2 == 0;
        const odd = (nbf & 1) == 1;
        f[nbf - 16] = quad(b, b + 1, b + 2, b + 3, if (odd == pair_one) 0xFF0000 else 0xFFFFFF);
    }
    for (0..16) |k| { // "sphere interior tube", green and blue
        const i: u16 = @intCast(k * 4);
        const rgb: u24 = if (k % 2 == 0) 0x00FF00 else 0x0000FF;
        f[96 + k] = if (k == 15) quad(61, 1, 448, 508, 0x0000FF) else quad(1 + i, 2 + i, 452 + i, 448 + i, rgb);
    }
    break :blk f;
};

/// The ball's run-time half, ~15 KB: the scene keeps it in free cart RAM, since
/// a module-scope array is written into the cart's data segment as zeros.
pub const Ball = struct {
    verts: [SPHERE_VERTS]Vec3,
    centroids: [SPHERE_FACES]Vec3,
    parts: [1]c3.Mesh,
    model: Model,

    /// Builds the ball in place; the other objects are compile-time data.
    pub fn build(self: *Ball) void {
        for (0..ROWS) |row| for (0..COLS) |col| {
            const theta = -90.0 + STEP * @as(f64, @floatFromInt(row)); // theta += dtheta from -90: exact
            const phi = STEP * @as(f64, @floatFromInt(col));
            const v = self.verts[(row * COLS + col) * 4 ..][0..4];
            v[0] = spherePoint(theta, phi);
            v[1] = spherePoint(theta + STEP, phi);
            v[2] = spherePoint(theta + STEP, phi + STEP);
            v[3] = if (theta > -90 and theta < 90) spherePoint(theta, phi + STEP) else v[2];
        };
        self.parts[0] = c3.build(&self.verts, &SPHERE_FACE_TABLE, &self.centroids);
        self.model = .{ .parts = &self.parts, .camera = ORIGIN, .rotation = ORIGIN, .speed = TURN };
    }
};

fn spherePoint(theta: f64, phi: f64) Vec3 {
    return .{
        .x = RADIUS * @cos(theta * DTOR) * @cos(phi * DTOR),
        .y = RADIUS * @cos(theta * DTOR) * @sin(phi * DTOR),
        .z = -RADIUS * @sin(theta * DTOR),
    };
}
