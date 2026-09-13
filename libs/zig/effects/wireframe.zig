// --------------------------------------------------------------------------
// Wireframe pipeline: the old-school 3D line object, shared by the scenes that
// used to carry their own copy (maxi, empire, ancool, fallen_angels).
//
//   vertices (Vec4, w = 1) --model--> camera --> projection --> 1/w --> screen
//   --> truncate to i16 --> a line for every edge
//
// The MODEL step differs per scene (sequential X/Y/Z rotations, a scale plus
// one Euler matrix...), so the scene passes it as a function; the tail is the
// same everywhere and lives here. The float op order is the scenes' original
// one, so a migrated scene renders byte-identical frames.
//
// Geometry comes from a .obj (utils/obj_loader.zig parseWire, at comptime).
// The math library and the line primitive are injected: zigos.zig binds
// zalgebra (`zg.wireframe`), scenes pass shapes.drawLine. That keeps this file
// natively testable (zalgebra's own vendored tests do not build on Zig 0.16).
// --------------------------------------------------------------------------

// `math` provides Vec3, Vec4 and Mat4 with zalgebra's API.
pub fn With(comptime math: type) type {
    const Vec3 = math.Vec3;
    const Vec4 = math.Vec4;
    const Mat4 = math.Mat4;

    return struct {
        pub const Edge = [2]u16;

        // The .obj vertices as homogeneous points (w = 1), for a scene-owned
        // array: `var verts = wf.vec4s(logo.verts.len, logo.verts);`
        pub fn vec4s(comptime n: usize, comptime verts: [n][3]f32) [n]Vec4 {
            var out: [n]Vec4 = undefined;
            for (verts, 0..) |v, i| out[i] = Vec4.new(v[0], v[1], v[2], 1.0);
            return out;
        }

        // Rotate about X, then Y, then Z, one matrix at a time (maxi, fallen_angels).
        pub fn rotateXYZ(v: Vec4, angle_x: f32, angle_y: f32, angle_z: f32) Vec4 {
            const after_x = Mat4.fromEulerAngles(Vec3.new(angle_x, 0, 0)).vec4mulByMat4(v);
            const after_y = Mat4.fromEulerAngles(Vec3.new(0, angle_y, 0)).vec4mulByMat4(after_x);
            return Mat4.fromEulerAngles(Vec3.new(0, 0, angle_z)).vec4mulByMat4(after_y);
        }

        pub const Camera = struct {
            camera: Mat4,
            projection: Mat4,
            screen: Mat4,

            // camera -> projection -> divide by w -> screen, truncated toward zero.
            pub fn toScreen(self: Camera, v: Vec4) [2]i16 {
                const after_cam = self.camera.vec4mulByMat4(v);
                const after_proj = self.projection.vec4mulByMat4(after_cam);
                const after_norm = after_proj.mul(Vec4.set(1 / after_proj.w()));
                const s = self.screen.vec4mulByMat4(after_norm);
                return .{ @intFromFloat(s.x()), @intFromFloat(s.y()) };
            }

            // Project every vertex into `out` (any slice of {x: i16, y: i16}).
            // `model(ctx, v)` is the scene's own object transform.
            pub fn project(self: Camera, verts: []const Vec4, out: anytype, ctx: anytype, comptime model: fn (@TypeOf(ctx), Vec4) Vec4) void {
                for (verts, 0..) |v, i| {
                    const p = self.toScreen(model(ctx, v));
                    out[i].x = p[0];
                    out[i].y = p[1];
                }
            }
        };

        // Draw each edge between two projected points, in edge order.
        // `line(target, a, b, color)` is the line primitive (shapes.drawLine).
        pub fn drawEdges(target: anytype, edges: []const [2]u16, pts: anytype, color: u8, comptime line: anytype) void {
            for (edges) |e| line(target, pts[e[0]], pts[e[1]], color);
        }
    };
}
