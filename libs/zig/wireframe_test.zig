// Tests for effects/wireframe.zig and the comptime wireframe parser in
// utils/obj_loader.zig: `l` polylines to edges, exact float round trip, the
// order of the model/projection steps, and edge drawing order.
//
// The pipeline runs on a tiny fake math library whose transforms do NOT
// commute, so a wrong step order changes the numbers. (Real zalgebra is not
// imported: its vendored tests do not build on Zig 0.16. The scenes' framebuffer
// hashes, apps/scene_hash.mjs, prove the real op order byte for byte.)
const std = @import("std");
const obj = @import("utils/obj_loader.zig");
const expectEqual = std.testing.expectEqual;

const FakeMath = struct {
    pub const Vec3 = struct {
        d: [3]f32,
        pub fn new(a: f32, b: f32, c: f32) Vec3 {
            return .{ .d = .{ a, b, c } };
        }
    };
    pub const Vec4 = struct {
        d: [4]f32,
        pub fn new(a: f32, b: f32, c: f32, e: f32) Vec4 {
            return .{ .d = .{ a, b, c, e } };
        }
        pub fn set(v: f32) Vec4 {
            return .{ .d = .{ v, v, v, v } };
        }
        pub fn mul(a: Vec4, b: Vec4) Vec4 {
            return .{ .d = .{ a.d[0] * b.d[0], a.d[1] * b.d[1], a.d[2] * b.d[2], a.d[3] * b.d[3] } };
        }
        pub fn x(v: Vec4) f32 {
            return v.d[0];
        }
        pub fn y(v: Vec4) f32 {
            return v.d[1];
        }
        pub fn z(v: Vec4) f32 {
            return v.d[2];
        }
        pub fn w(v: Vec4) f32 {
            return v.d[3];
        }
    };
    // Row-major like zalgebra's vec4mulByMat4.
    pub const Mat4 = struct {
        m: [4][4]f32,
        pub fn identity() Mat4 {
            return .{ .m = .{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } } };
        }
        // Fake "rotations": X scales x, Y shifts x, Z scales y.
        pub fn fromEulerAngles(e: Vec3) Mat4 {
            var r = identity();
            if (e.d[0] != 0) r.m[0][0] = e.d[0];
            if (e.d[1] != 0) r.m[0][3] = e.d[1];
            if (e.d[2] != 0) r.m[1][1] = e.d[2];
            return r;
        }
        pub fn vec4mulByMat4(self: Mat4, v: Vec4) Vec4 {
            var out: [4]f32 = undefined;
            for (0..4) |i| out[i] = self.m[i][0] * v.d[0] + self.m[i][1] * v.d[1] + self.m[i][2] * v.d[2] + self.m[i][3] * v.d[3];
            return .{ .d = out };
        }
    };
};

const wf = @import("effects/wireframe.zig").With(FakeMath);
const V4 = FakeMath.Vec4;
const M4 = FakeMath.Mat4;

const square =
    \\# a unit square, closed
    \\o square
    \\v 0 0 0
    \\v 1 0 0
    \\v 1 1 0.5
    \\v 0 1 -0.155
    \\l 1 2 3
    \\l 3 4 1
    \\f 1 2 3
;

test "parseWire: vertices kept as written, polylines split into edges in order" {
    const w = comptime obj.parseWire(square);
    try expectEqual(4, w.verts.len);
    try expectEqual(4, w.edges.len);
    try expectEqual([3]f32{ 1, 1, 0.5 }, w.verts[2]);
    const want = [_]obj.Edge{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 } };
    for (want, w.edges) |a, b| try expectEqual(a, b);
}

test "parseWire: CRLF, tabs and v/vt slashes in indices" {
    const w = comptime obj.parseWire("v 1 2 3\r\nv\t4 5 6\r\nl 2/1 1/1\r\n");
    try expectEqual([3]f32{ 4, 5, 6 }, w.verts[1]);
    try expectEqual(obj.Edge{ 1, 0 }, w.edges[0]);
}

test "parseWire: a file with no edges is just points" {
    const w = comptime obj.parseWire("v 1 2 3\n");
    try expectEqual(1, w.verts.len);
    try expectEqual(0, w.edges.len);
}

test "shortest-digit floats parse back to the same f32 bits" {
    // the maxi tables held comptime expressions like 0.97-0.13, exported with {d}
    const values = [_]f32{ 0.97 - 0.13, 1.20 - 0.13, 1.73 - 0.10, -0.155, 0.06, 2.8 };
    for (values) |v| {
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{d}", .{v});
        const back = try std.fmt.parseFloat(f32, s);
        try expectEqual(@as(u32, @bitCast(v)), @as(u32, @bitCast(back)));
    }
}

test "vec4s: homogeneous points with w = 1" {
    const w = comptime obj.parseWire(square);
    const v = wf.vec4s(w.verts.len, w.verts);
    try expectEqual(@as(f32, -0.155), v[3].z());
    try expectEqual(@as(f32, 1.0), v[3].w());
}

test "rotateXYZ: X, then Y, then Z" {
    const r = wf.rotateXYZ(V4.new(3, 5, 0, 1), 2, 1, 4);
    try expectEqual(@as(f32, 3 * 2 + 1), r.x()); // (x * 2) + 1, not (x + 1) * 2
    try expectEqual(@as(f32, 20), r.y());
}

const P = struct { x: i16 = 0, y: i16 = 0 };

fn shiftX(dx: f32, v: V4) V4 {
    return V4.new(v.x() + dx, v.y(), v.z(), v.w());
}

// camera: x += 1 | projection: w = z | screen: x * 10
fn fakeCamera() wf.Camera {
    var camera = M4.identity();
    camera.m[0][3] = 1;
    var projection = M4.identity();
    projection.m[3] = .{ 0, 0, 1, 0 };
    var screen = M4.identity();
    screen.m[0][0] = 10;
    return .{ .camera = camera, .projection = projection, .screen = screen };
}

test "project: model, camera, projection, divide by w, screen, truncate" {
    const verts = [_]V4{ V4.new(1, 3, 2, 1), V4.new(-2.5, 0, 4, 1) };
    var out: [2]P = undefined;
    fakeCamera().project(&verts, &out, @as(f32, 0.5), shiftX);
    // ((1 + 0.5 + 1) / 2) * 10 = 12.5 -> 12 ; y = 3 / 2 = 1.5 -> 1
    try expectEqual(P{ .x = 12, .y = 1 }, out[0]);
    // ((-2.5 + 0.5 + 1) / 4) * 10 = -2.5 -> -2 (toward zero)
    try expectEqual(P{ .x = -2, .y = 0 }, out[1]);
}

const Rec = struct {
    n: usize = 0,
    got: [8][2]P = undefined,
    color: u8 = 0,
    fn line(self: *Rec, a: P, b: P, color: u8) void {
        self.got[self.n] = .{ a, b };
        self.color = color;
        self.n += 1;
    }
};

test "drawEdges: one line per edge, in edge order, with the colour" {
    const pts = [_]P{ .{ .x = 1 }, .{ .x = 2 }, .{ .x = 3 } };
    const edges = [_]obj.Edge{ .{ 2, 0 }, .{ 0, 1 } };
    var rec: Rec = .{};
    wf.drawEdges(&rec, &edges, &pts, 7, Rec.line);
    try expectEqual(2, rec.n);
    try expectEqual(@as(u8, 7), rec.color);
    try expectEqual(@as(i16, 3), rec.got[0][0].x);
    try expectEqual(@as(i16, 2), rec.got[1][1].x);
}

test "drawEdges: no edges draws nothing" {
    const pts = [_]P{.{}};
    var rec: Rec = .{};
    wf.drawEdges(&rec, &.{}, &pts, 7, Rec.line);
    try expectEqual(0, rec.n);
}
