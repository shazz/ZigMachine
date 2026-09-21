// --------------------------------------------------------------------------
// THREE.TorusGeometry(70, 25, 10, 16), built exactly as codef_3d.js's copy of
// three.js r49 builds it (lib/codef_3d.js:835):
//
//   f = d / segmentsT * 2pi          g = c / segmentsR * 2pi
//   v = ((R + r cos g) cos f, (R + r cos g) sin f, r sin g)
//   the vertex normal is v minus the ring centre (R cos f, R sin f, 0),
//   normalised; a face's normal is the sum of its four, normalised.
//
// Vertices need trigonometry, so they are built at run time: comptime float
// functions are the compiler's, not the fdlibm-equivalent ones the machine
// runs (zig3d.zig's own note on `mesh` vs `build`).
// --------------------------------------------------------------------------
const c3 = @import("zigos").zig3d;

pub const RADIUS: f64 = 70.0;
pub const TUBE: f64 = 25.0;
pub const SEG_R: usize = 10; // rings around the tube
pub const SEG_T: usize = 16; // steps around the hole

pub const VERTS = (SEG_R + 1) * (SEG_T + 1); // 187
pub const FACES = SEG_R * SEG_T; // 160, every one a Face4

const TAU: f64 = 6.283185307179586;

/// Vertex positions, vertex normals and the face table, filled once.
pub const Geometry = struct {
    verts: [VERTS]c3.Vec3,
    normals: [FACES]c3.Vec3, // per FACE, in model space
    faces: [FACES]c3.Face,
    centroids: [FACES]c3.Vec3,

    pub fn build(self: *Geometry) c3.Mesh {
        var vn: [VERTS]c3.Vec3 = undefined;
        self.ring(&vn);
        self.quads(&vn);
        return c3.build(&self.verts, &self.faces, &self.centroids);
    }

    fn ring(self: *Geometry, vn: *[VERTS]c3.Vec3) void {
        for (0..SEG_R + 1) |c| for (0..SEG_T + 1) |d| {
            const f = @as(f64, @floatFromInt(d)) / @as(f64, @floatFromInt(SEG_T)) * TAU;
            const g = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(SEG_R)) * TAU;
            const ring_r = RADIUS + TUBE * @cos(g);
            const i = (SEG_T + 1) * c + d;
            self.verts[i] = .{ .x = ring_r * @cos(f), .y = ring_r * @sin(f), .z = TUBE * @sin(g) };
            vn[i] = norm(.{
                .x = self.verts[i].x - RADIUS * @cos(f),
                .y = self.verts[i].y - RADIUS * @sin(f),
                .z = self.verts[i].z,
            });
        };
    }

    // The winding three.js pushes: (c,d-1) (c-1,d-1) (c-1,d) (c,d). `ink`
    // carries the face's own index, which is how the scene finds its normal
    // again after zig3d has sorted the projected polygons.
    fn quads(self: *Geometry, vn: *const [VERTS]c3.Vec3) void {
        var n: usize = 0;
        for (1..SEG_R + 1) |c| for (1..SEG_T + 1) |d| {
            const v = [4]u16{
                @intCast((SEG_T + 1) * c + d - 1),
                @intCast((SEG_T + 1) * (c - 1) + d - 1),
                @intCast((SEG_T + 1) * (c - 1) + d),
                @intCast((SEG_T + 1) * c + d),
            };
            self.faces[n] = .{ .v = v, .n = 4, .ink = @intCast(n) };
            var s = c3.Vec3{ .x = 0, .y = 0, .z = 0 };
            for (v) |i| s = .{ .x = s.x + vn[i].x, .y = s.y + vn[i].y, .z = s.z + vn[i].z };
            self.normals[n] = norm(s);
            n += 1;
        };
    }
};

fn norm(v: c3.Vec3) c3.Vec3 {
    const l = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (l == 0) return v;
    return .{ .x = v.x / l, .y = v.y / l, .z = v.z / l };
}
