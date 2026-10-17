// --------------------------------------------------------------------------
// codef3D: CODEF's flat-shaded 3D object (codef_3d_v2.js), which is three.js
// r49's Projector + CanvasRenderer with no lights, replayed exactly.
//
// What one `codef3D.draw()` of a `faces`/`faces4` mesh does (codef_3d_v2.js):
//   - model: position, then Euler XYZ rotation (Object3D.updateMatrix);
//   - camera: a translation, inverted by the cofactor formula (getInverse);
//   - projection: makePerspective(fov, aspect, near, far) (a frustum);
//   - the whole mesh is skipped when its bounding sphere is outside a frustum
//     plane (Frustum.contains; the mesh keeps frustumCulled = true);
//   - a vertex is usable while its CLIP z (not divided by w) is in
//     (near, far); a face needs all of its vertices usable;
//   - a face is kept when it winds clockwise on screen (Face4: either of its
//     two triangles does), since doubleSided and flipSided are false;
//   - faces sort far to near by their projected centroid z (a stable sort,
//     Array.prototype.sort), then render in that order;
//   - with no lights, MeshBasic and MeshLambert both fill the face colour;
//   - overdraw pushes each edge's ends 1 px apart (the Nb() helper) before
//     the path is built in canvas pixels: (x*w/2 + w/2, h/2 - y*h/2).
//
// Precision is part of the port: Matrix4 stores its elements in a
// Float32Array, so matrices here hold f32 and every product reads them as f64,
// in three.js's own operation order. Vertices and vectors are f64 (JS numbers).
// Zig's sin/cos/tan are musl's, which are fdlibm's, as V8's Math is.
//
// No ZigOS import: zig3d_test.zig runs it natively. The scene owns every
// buffer (project() takes scratch slices), so this file weighs no cart.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Vec3 = struct { x: f64, y: f64, z: f64 };
const Vec4 = struct { x: f64, y: f64, z: f64, w: f64 };

/// THREE.Matrix4, column-major: e[row + 4 * column].
pub const Mat4 = struct {
    e: [16]f32,

    pub const identity = Mat4{ .e = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } };

    fn at(m: *const Mat4, i: usize) f64 {
        return m.e[i];
    }

    /// this.multiply(a, b): a * b, each sum left to right.
    pub fn mul(a: *const Mat4, b: *const Mat4) Mat4 {
        var out: Mat4 = undefined;
        for (0..4) |c| for (0..4) |r| {
            var s: f64 = a.at(r) * b.at(4 * c);
            for (1..4) |k| s += a.at(r + 4 * k) * b.at(k + 4 * c);
            out.e[r + 4 * c] = @floatCast(s);
        };
        return out;
    }

    /// Object3D.updateMatrix on a fresh identity: setPosition, then
    /// setRotationFromEuler(rotation, "XYZ") (its default branch).
    pub fn compose(pos: Vec3, rot: Vec3) Mat4 {
        var m = identity;
        const g = @cos(rot.x);
        const d = @sin(rot.x);
        const h = @cos(rot.y);
        const e = @sin(rot.y);
        const j = @cos(rot.z);
        const f = @sin(rot.z);
        const l = g * j;
        const k = g * f;
        const p = d * j;
        const q = d * f;
        m.e[12] = @floatCast(pos.x);
        m.e[13] = @floatCast(pos.y);
        m.e[14] = @floatCast(pos.z);
        m.e[0] = @floatCast(h * j);
        m.e[4] = @floatCast(-h * f);
        m.e[8] = @floatCast(e);
        m.e[1] = @floatCast(k + p * e);
        m.e[5] = @floatCast(l - q * e);
        m.e[9] = @floatCast(-d * h);
        m.e[2] = @floatCast(q - l * e);
        m.e[6] = @floatCast(p + k * e);
        m.e[10] = @floatCast(g * h);
        return m;
    }

    /// PerspectiveCamera.updateProjectionMatrix: makePerspective -> makeFrustum.
    pub fn perspective(fov: f64, aspect: f64, near: f64, far: f64) Mat4 {
        const top = near * @tan(fov * std.math.pi / 360.0);
        const bottom = -top;
        const left = bottom * aspect;
        const right = top * aspect;
        var m = Mat4{ .e = [_]f32{0} ** 16 };
        m.e[0] = @floatCast(2 * near / (right - left));
        m.e[8] = @floatCast((right + left) / (right - left));
        m.e[5] = @floatCast(2 * near / (top - bottom));
        m.e[9] = @floatCast((top + bottom) / (top - bottom));
        m.e[10] = @floatCast(-(far + near) / (far - near));
        m.e[14] = @floatCast(-2 * far * near / (far - near));
        m.e[11] = -1;
        return m;
    }

    /// getInverse(a): the cofactors stored (as f32), then multiplyScalar(1/det).
    /// Transliterated with three.js's own letters so the products keep its order.
    pub fn inverse(a: *const Mat4) Mat4 {
        const d = a.at(0);
        const e = a.at(4);
        const f = a.at(8);
        const g = a.at(12);
        const h = a.at(1);
        const j = a.at(5);
        const l = a.at(9);
        const k = a.at(13);
        const p = a.at(2);
        const m = a.at(6);
        const o = a.at(10);
        const q = a.at(14);
        const n = a.at(3);
        const r = a.at(7);
        const u = a.at(11);
        const c = a.at(15);
        const cof = [16]f64{
            l * q * r - k * o * r + k * m * u - j * q * u - l * m * c + j * o * c,
            k * o * n - l * q * n - k * p * u + h * q * u + l * p * c - h * o * c,
            j * q * n - k * m * n + k * p * r - h * q * r - j * p * c + h * m * c,
            l * m * n - j * o * n - l * p * r + h * o * r + j * p * u - h * m * u,
            g * o * r - f * q * r - g * m * u + e * q * u + f * m * c - e * o * c,
            f * q * n - g * o * n + g * p * u - d * q * u - f * p * c + d * o * c,
            g * m * n - e * q * n - g * p * r + d * q * r + e * p * c - d * m * c,
            e * o * n - f * m * n + f * p * r - d * o * r - e * p * u + d * m * u,
            f * k * r - g * l * r + g * j * u - e * k * u - f * j * c + e * l * c,
            g * l * n - f * k * n - g * h * u + d * k * u + f * h * c - d * l * c,
            e * k * n - g * j * n + g * h * r - d * k * r - e * h * c + d * j * c,
            f * j * n - e * l * n - f * h * r + d * l * r + e * h * u - d * j * u,
            g * l * m - f * k * m - g * j * o + e * k * o + f * j * q - e * l * q,
            f * k * p - g * l * p + g * h * o - d * k * o - f * h * q + d * l * q,
            g * j * p - e * k * p - g * h * m + d * k * m + e * h * q - d * j * q,
            e * l * p - f * j * p + f * h * m - d * l * m - e * h * o + d * j * o,
        };
        const s = 1.0 / a.determinant();
        var out: Mat4 = undefined;
        for (&out.e, cof) |*x, v| {
            const stored: f32 = @floatCast(v);
            x.* = @floatCast(@as(f64, stored) * s);
        }
        return out;
    }

    /// determinant(), with three.js's letters (its `m` is `w` here).
    fn determinant(self: *const Mat4) f64 {
        const b = self.at(0);
        const c = self.at(4);
        const d = self.at(8);
        const e = self.at(12);
        const f = self.at(1);
        const g = self.at(5);
        const h = self.at(9);
        const j = self.at(13);
        const l = self.at(2);
        const k = self.at(6);
        const p = self.at(10);
        const w = self.at(14);
        const o = self.at(3);
        const q = self.at(7);
        const n = self.at(11);
        const a = self.at(15);
        return e * h * k * o - d * j * k * o - e * g * p * o + c * j * p * o + d * g * w * o - c * h * w * o -
            e * h * l * q + d * j * l * q + e * f * p * q - b * j * p * q - d * f * w * q + b * h * w * q +
            e * g * l * n - c * j * l * n - e * f * k * n + b * j * k * n + c * f * w * n - b * g * w * n -
            d * g * l * a + c * h * l * a + d * f * k * a - b * h * k * a - c * f * p * a + b * g * p * a;
    }

    /// multiplyVector3: the point, divided by its w.
    pub fn point(m: *const Mat4, v: Vec3) Vec3 {
        const f = 1.0 / (m.at(3) * v.x + m.at(7) * v.y + m.at(11) * v.z + m.at(15));
        return .{
            .x = (m.at(0) * v.x + m.at(4) * v.y + m.at(8) * v.z + m.at(12)) * f,
            .y = (m.at(1) * v.x + m.at(5) * v.y + m.at(9) * v.z + m.at(13)) * f,
            .z = (m.at(2) * v.x + m.at(6) * v.y + m.at(10) * v.z + m.at(14)) * f,
        };
    }

    /// point(m, v).z alone, the same operations in the same order: the depth
    /// sort reads nothing else, and x and y cost 14 soft-float operations.
    fn pointZ(m: *const Mat4, v: Vec3) f64 {
        const f = 1.0 / (m.at(3) * v.x + m.at(7) * v.y + m.at(11) * v.z + m.at(15));
        return (m.at(2) * v.x + m.at(6) * v.y + m.at(10) * v.z + m.at(14)) * f;
    }

    /// point() for a matrix whose last row is (0, 0, 0, 1), as every compose()
    /// is. There w = 0*x + 0*y + 0*z + 1 is exactly 1 for finite x, y, z (each
    /// product is +-0) and a product by 1/w = 1 is exact, so this IS point(), bit
    /// for bit, without its five soft-float operations a coordinate.
    fn affinePoint(m: *const Mat4, v: Vec3) Vec3 {
        return .{
            .x = m.at(0) * v.x + m.at(4) * v.y + m.at(8) * v.z + m.at(12),
            .y = m.at(1) * v.x + m.at(5) * v.y + m.at(9) * v.z + m.at(13),
            .z = m.at(2) * v.x + m.at(6) * v.y + m.at(10) * v.z + m.at(14),
        };
    }

    /// multiplyVector4 of (v, 1).
    fn clip(m: *const Mat4, v: Vec3) Vec4 {
        return .{
            .x = m.at(0) * v.x + m.at(4) * v.y + m.at(8) * v.z + m.at(12) * 1,
            .y = m.at(1) * v.x + m.at(5) * v.y + m.at(9) * v.z + m.at(13) * 1,
            .z = m.at(2) * v.x + m.at(6) * v.y + m.at(10) * v.z + m.at(14) * 1,
            .w = m.at(3) * v.x + m.at(7) * v.y + m.at(11) * v.z + m.at(15) * 1,
        };
    }

    fn maxScaleOnAxis(m: *const Mat4) f64 {
        const x = m.at(0) * m.at(0) + m.at(1) * m.at(1) + m.at(2) * m.at(2);
        const y = m.at(4) * m.at(4) + m.at(5) * m.at(5) + m.at(6) * m.at(6);
        const z = m.at(8) * m.at(8) + m.at(9) * m.at(9) + m.at(10) * m.at(10);
        return @sqrt(@max(x, @max(y, z)));
    }
};

/// A Face3 (n = 3, v[3] unused) or Face4, with the palette index it fills.
pub const Face = struct { v: [4]u16, n: u8, ink: u8 };

/// Geometry after computeCentroids and computeBoundingSphere.
pub const Mesh = struct {
    verts: []const Vec3,
    faces: []const Face,
    centroids: []const Vec3,
    radius: f64,
    /// alias[i] = the first vertex bit-for-bit equal to vertex i (i itself
    /// when none is). A projected vertex is a pure function of its bits, so
    /// projecting each distinct one once and copying it to its twins changes
    /// nothing on screen; a sphere built facet by facet holds each point
    /// three or four times. See aliases().
    alias: ?[]const u16 = null,
};

/// Fill `out` (verts.len entries) with the alias table Mesh.alias describes.
/// Bits are compared as integers: no soft-float compare, and -0 stays apart
/// from +0, as it must for "bit for bit".
pub fn aliases(verts: []const Vec3, out: []u16) []const u16 {
    for (verts, out[0..verts.len], 0..) |v, *a, i| {
        a.* = @intCast(i);
        for (verts[0..i], 0..) |u, j| if (same(u, v)) {
            a.* = @intCast(j);
            break;
        };
    }
    return out[0..verts.len];
}

fn same(a: Vec3, b: Vec3) bool {
    const B = u64;
    return @as(B, @bitCast(a.x)) == @as(B, @bitCast(b.x)) and @as(B, @bitCast(a.y)) == @as(B, @bitCast(b.y)) and
        @as(B, @bitCast(a.z)) == @as(B, @bitCast(b.z));
}

/// A mesh built at compile time from its vertices and faces. Vertices that
/// need trigonometry belong in `build` instead: comptime float functions are
/// the compiler's, not the fdlibm-equivalent ones the machine runs.
pub fn mesh(comptime verts: []const Vec3, comptime faces: []const Face) Mesh {
    const centroids = comptime blk: {
        var out: [faces.len]Vec3 = undefined;
        computeCentroids(verts, faces, &out);
        break :blk out;
    };
    return .{ .verts = verts, .faces = faces, .centroids = &centroids, .radius = comptime boundingRadius(verts) };
}

/// A mesh from run-time vertices; `centroids` needs faces.len entries.
pub fn build(verts: []const Vec3, faces: []const Face, centroids: []Vec3) Mesh {
    computeCentroids(verts, faces, centroids);
    return .{ .verts = verts, .faces = faces, .centroids = centroids[0..faces.len], .radius = boundingRadius(verts) };
}

/// Geometry.computeCentroids: 0, plus each vertex, divided by the count.
fn computeCentroids(verts: []const Vec3, faces: []const Face, out: []Vec3) void {
    for (faces, out[0..faces.len]) |f, *c| {
        var s = Vec3{ .x = 0, .y = 0, .z = 0 };
        for (f.v[0..f.n]) |i| s = .{ .x = s.x + verts[i].x, .y = s.y + verts[i].y, .z = s.z + verts[i].z };
        const div: f64 = @floatFromInt(f.n);
        c.* = .{ .x = s.x / div, .y = s.y / div, .z = s.z / div };
    }
}

/// Geometry.computeBoundingSphere: the longest vertex.
fn boundingRadius(verts: []const Vec3) f64 {
    var r: f64 = 0;
    for (verts) |v| r = @max(r, @sqrt(v.x * v.x + v.y * v.y + v.z * v.z));
    return r;
}

/// new codef3D(dst, camZ, fov, near, far) on a `width` x `height` canvas.
pub const Lens = struct {
    projection: Mat4,
    near: f64,
    far: f64,
    half_w: f64, // Math.floor(width / 2)
    half_h: f64,

    pub fn init(width: u32, height: u32, fov: f64, near: f64, far: f64) Lens {
        const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
        return .{
            .projection = Mat4.perspective(fov, aspect, near, far),
            .near = near,
            .far = far,
            .half_w = @floatFromInt(width / 2),
            .half_h = @floatFromInt(height / 2),
        };
    }
};

/// One vertex in clip space: positionScreen with x and y divided by w.
pub const Screen = struct { x: f64, y: f64, usable: bool };

/// A face ready to fill: its path in canvas pixels.
pub const Poly = struct { pts: [4][2]f64, n: u8, ink: u8, z: f64 };

/// What `codef3D.faces(vertices, object, doubleSided, overdraw)` was given.
/// three.js r49's Projector skips the facing test entirely when the mesh is
/// doubleSided (`if (O.doubleSided || i != O.flipSided)`), and CanvasRenderer
/// only pushes an edge's ends apart when the material's overdraw is set.
/// The defaults are what every caller before screen 417 passed.
pub const Options = struct { double_sided: bool = false, overdraw: bool = true };

/// One draw of `m` placed at `position`/`rotation`, seen from a camera at
/// `camera` (no rotation). `screen` needs m.verts.len entries, `out`
/// m.faces.len. Returns the faces to fill, far to near.
pub fn project(lens: *const Lens, camera: Vec3, position: Vec3, rotation: Vec3, m: *const Mesh, screen: []Screen, out: []Poly) []Poly {
    return projectEx(lens, camera, position, rotation, m, screen, out, .{});
}

/// project() for a mesh whose `faces()` call did not take the defaults.
pub fn projectEx(lens: *const Lens, camera: Vec3, position: Vec3, rotation: Vec3, m: *const Mesh, screen: []Screen, out: []Poly, opts: Options) []Poly {
    return projectView(&View.init(lens, camera), position, rotation, m, screen, out, opts);
}

/// Everything a draw derives from the lens and the camera alone: the camera's
/// inverse, view . projection and the frustum's six normalised planes. three.js
/// rebuilds them every draw; they are the same numbers each time, so a screen
/// whose camera holds still builds a View once and calls projectView().
pub const View = struct {
    lens: Lens,
    vp: Mat4,
    planes: [6][4]f64,
    sparse: bool, // vp has a translating camera's zeros: see clipSparse

    pub fn init(lens: *const Lens, camera: Vec3) View {
        const view = Mat4.compose(camera, .{ .x = 0, .y = 0, .z = 0 }).inverse();
        const vp = lens.projection.mul(&view);
        return .{ .lens = lens.*, .vp = vp, .planes = frustumPlanes(&vp), .sparse = isSparse(&vp) };
    }
};

/// A symmetric frustum seen from a camera that only translates leaves vp
/// with zeros at 1, 2, 3, 4, 6, 7, 8, 9 and -1 at 11.
fn isSparse(vp: *const Mat4) bool {
    for ([_]usize{ 1, 2, 3, 4, 6, 7, 8, 9 }) |i| if (vp.e[i] != 0) return false;
    return vp.e[11] == -1;
}

/// clip() on a sparse vp, without the products by 0 and by 1. A product by
/// 0 of a finite coordinate is +-0 and adding it leaves a sum unchanged but
/// for the sign of a zero; the products by 1 and -1 are exact. A zero's sign
/// cannot reach the screen: x/w and y/w only meet + half_w and differences,
/// and z/w only comparisons. So the faces and their paths are bit for bit
/// clip()'s, for 12 fewer soft-float operations a vertex.
fn clipSparse(m: *const Mat4, v: Vec3) Vec4 {
    return .{
        .x = m.at(0) * v.x + m.at(12),
        .y = m.at(5) * v.y + m.at(13),
        .z = m.at(10) * v.z + m.at(14),
        .w = -v.z + m.at(15),
    };
}

/// projectEx() through a View built beforehand: the same numbers, bit for bit.
pub fn projectView(view: *const View, position: Vec3, rotation: Vec3, m: *const Mesh, screen: []Screen, out: []Poly, opts: Options) []Poly {
    const lens = &view.lens;
    const vp = &view.vp;
    const model = Mat4.compose(position, rotation);
    if (!insideFrustum(&view.planes, &model, m.radius)) return out[0..0];

    for (m.verts, screen[0..m.verts.len], 0..) |v, *s, i| {
        if (m.alias) |al| if (al[i] != i) {
            s.* = screen[al[i]]; // a twin of a vertex already projected
            continue;
        };
        const p = model.affinePoint(v);
        const c = if (view.sparse) clipSparse(vp, p) else vp.clip(p);
        s.* = .{ .x = c.x / c.w, .y = c.y / c.w, .usable = c.z > lens.near and c.z < lens.far };
    }
    var n: usize = 0;
    for (m.faces, m.centroids) |f, centroid| {
        const s = screen;
        if (!s[f.v[0]].usable or !s[f.v[1]].usable or !s[f.v[2]].usable) continue;
        if (f.n == 4 and !s[f.v[3]].usable) continue;
        if (!opts.double_sided and !clockwise(f, s)) continue;
        var p = Poly{ .pts = undefined, .n = f.n, .ink = f.ink, .z = vp.pointZ(model.affinePoint(centroid)) };
        for (0..f.n) |i| p.pts[i] = .{ s[f.v[i]].x * lens.half_w, s[f.v[i]].y * lens.half_h };
        if (opts.overdraw) overdraw(&p);
        for (p.pts[0..f.n]) |*pt| {
            const x = pt[0] + lens.half_w;
            const y = -pt[1] + lens.half_h;
            pt.* = .{ x, y };
        }
        out[n] = p;
        n += 1;
    }
    std.sort.insertion(Poly, out[0..n], {}, farther);
    return out[0..n];
}

fn farther(_: void, a: Poly, b: Poly) bool {
    return b.z - a.z < 0;
}

/// One THREE.Particle of a CODEF `vectorball_dot`/`vectorball_img` group, placed
/// as CanvasRenderer draws a ParticleCanvasMaterial (its `r()`): `x`/`y` are
/// canvas pixels and `sx`/`sy` the scale its program runs under. The renderer
/// leaves the canvas transform at (1, 0, 0, -1, o, q) and does NOT undo the flip
/// for this material (only ParticleBasicMaterial passes -j), so a program point
/// (px, py) lands at (x + sx*px, y - sy*py) and the program's image comes out
/// MIRRORED vertically.
pub const Particle = struct { x: f64, y: f64, sx: f64, sy: f64, z: f64 };

/// Projector's RenderableParticle branch for a group of particles at the origin,
/// Euler-rotated by `rotation` and scaled by `scale` (Object3D.updateMatrix ends
/// with Matrix4.scale), seen from a camera at `camera` with no rotation.
/// `out` needs points.len entries; the visible ones come back far to near.
/// A Particle's own scale stays THREE's default 1, which is what both CODEF
/// vectorball helpers leave it at.
pub fn projectParticles(lens: *const Lens, camera: Vec3, rotation: Vec3, scale: f64, points: []const Vec3, out: []Particle) []Particle {
    const origin = Vec3{ .x = 0, .y = 0, .z = 0 };
    var group = Mat4.compose(origin, rotation);
    for (0..3) |c| for (0..4) |r| { // Matrix4.scale: each of the first three columns
        group.e[r + 4 * c] = @floatCast(@as(f64, group.e[r + 4 * c]) * scale);
    };
    const vp = lens.projection.mul(&Mat4.compose(camera, origin).inverse());
    var n: usize = 0;
    for (points) |p| {
        const world = group.mul(&Mat4.compose(p, origin)); // the particle's matrixWorld
        const e = vp.clip(.{ .x = world.at(12), .y = world.at(13), .z = world.at(14) });
        out[n] = place(lens, e) orelse continue;
        n += 1;
    }
    std.sort.insertion(Particle, out[0..n], {}, fartherParticle);
    return out[0..n];
}

/// A projected particle's canvas placement, or null where the Projector drops it
/// (clip z outside (0, 1)) or the renderer's viewport test does.
fn place(lens: *const Lens, e: Vec4) ?Particle {
    const z = e.z / e.w;
    if (!(z > 0 and z < 1)) return null;
    const ax = e.x / e.w * lens.half_w;
    const ay = e.y / e.w * lens.half_h;
    const sx = @abs(e.x / e.w - (e.x + lens.projection.at(0)) / (e.w + lens.projection.at(12))) * lens.half_w;
    const sy = @abs(e.y / e.w - (e.y + lens.projection.at(5)) / (e.w + lens.projection.at(13))) * lens.half_h;
    // the renderer's box is sx/sy wide, NOT the program's image, so a particle
    // whose centre leaves the canvas is dropped whole however big it draws
    if (ax + sx < -lens.half_w or ax - sx > lens.half_w) return null;
    if (ay + sy < -lens.half_h or ay - sy > lens.half_h) return null;
    return .{ .x = ax + lens.half_w, .y = -ay + lens.half_h, .sx = sx, .sy = sy, .z = z };
}

fn fartherParticle(_: void, a: Particle, b: Particle) bool {
    return b.z - a.z < 0;
}

/// Frustum.setFromMatrix(vp): row 3 minus/plus rows 0, 0, 1, 1, 2, 2 of vp,
/// each normalised.
fn frustumPlanes(vp: *const Mat4) [6][4]f64 {
    const Plane = struct { row: usize, minus: bool };
    const rows = [6]Plane{
        .{ .row = 0, .minus = true },  .{ .row = 0, .minus = false },
        .{ .row = 1, .minus = false }, .{ .row = 1, .minus = true },
        .{ .row = 2, .minus = true },  .{ .row = 2, .minus = false },
    };
    var planes: [6][4]f64 = undefined;
    for (rows, &planes) |plane, *pl| {
        for (0..4) |c| {
            const w = vp.at(3 + 4 * c);
            const v = vp.at(plane.row + 4 * c);
            pl[c] = if (plane.minus) w - v else w + v;
        }
        const len = @sqrt(pl[0] * pl[0] + pl[1] * pl[1] + pl[2] * pl[2]);
        if (len != 0) for (pl) |*x| {
            x.* /= len;
        };
    }
    return planes;
}

/// Frustum.contains(mesh), against the planes of frustumPlanes().
fn insideFrustum(planes: *const [6][4]f64, model: *const Mat4, radius: f64) bool {
    const limit = -radius * model.maxScaleOnAxis();
    for (planes) |pl| {
        const d = pl[0] * model.at(12) + pl[1] * model.at(13) + pl[2] * model.at(14) + pl[3];
        if (d <= limit) return false;
    }
    return true;
}

/// @intFromFloat(@round(@max(-limit, @min(limit, v)))) for a power-of-two
/// `limit` (a NaN gives +limit, as @min/@max return the non-NaN operand),
/// bit for bit, in 32-bit integer operations: a soft-float core spends a few
/// hundred cycles on the float chain and this is a dozen instructions.
/// Rounding half away from zero is floor(|v| + 1/2) on the magnitude. Below the
/// limit |v| = M / 2^S, M the 53-bit mantissa and S = 1075 - e >= 53 -
/// log2(limit) >= 39, so the half (2^(S-1)) and the result both sit in the
/// high word and the low word cannot carry into them: floor(|v| + 1/2) =
/// (m + 2^(s-1)) >> s exactly, m the high word's 21 mantissa bits with the
/// hidden one and s = S - 32. |v| < 1/2 (e < 1022, zeros and subnormals) is 0,
/// and -0 rounds to 0 as @round(-0.0) does.
pub fn roundClamped(v: f64, comptime limit: u16) i16 {
    comptime std.debug.assert(std.math.isPowerOfTwo(limit) and limit <= 1 << 14);
    const top_e: u32 = 1023 + @as(u32, std.math.log2_int(u16, limit)); // |v| >= limit from here
    const hi: u32 = @truncate(@as(u64, @bitCast(v)) >> 32);
    const e = (hi >> 20) & 0x7FF;
    const mag: i16 = if (e < 1022) 0 else if (e < top_e) blk: {
        const s: u5 = @intCast(1043 - e);
        const m = (hi & 0xFFFFF) | 0x100000;
        break :blk @intCast((m + (@as(u32, 1) << (s - 1))) >> s);
    } else if (std.math.isNan(v)) return limit else limit;
    return if (hi >> 31 != 0) -mag else mag;
}

/// Projector's facing test, in divided clip space.
fn clockwise(f: Face, s: []const Screen) bool {
    const v1 = s[f.v[0]];
    const v2 = s[f.v[1]];
    const v3 = s[f.v[2]];
    if (f.n == 3) return (v3.x - v1.x) * (v2.y - v1.y) - (v3.y - v1.y) * (v2.x - v1.x) < 0;
    const v4 = s[f.v[3]];
    return (v4.x - v1.x) * (v2.y - v1.y) - (v4.y - v1.y) * (v2.x - v1.x) < 0 or
        (v2.x - v3.x) * (v4.y - v3.y) - (v2.y - v3.y) * (v4.x - v3.x) < 0;
}

/// CanvasRenderer's overdraw: Face3 pushes (1,2) (2,3) (3,1); Face4 pushes
/// (1,2) (2,4) (4,1), then moves 3 away from the un-pushed 2 and 4.
fn overdraw(p: *Poly) void {
    const pt = &p.pts;
    if (p.n == 3) {
        push(&pt[0], &pt[1]);
        push(&pt[1], &pt[2]);
        push(&pt[2], &pt[0]);
        return;
    }
    var v2 = pt[1];
    var v4 = pt[3];
    push(&pt[0], &pt[1]);
    push(&pt[1], &pt[3]);
    push(&pt[3], &pt[0]);
    push(&pt[2], &v2);
    push(&pt[2], &v4);
}

/// Nb(a, b): a and b each move 1 px apart along their line.
fn push(a: *[2]f64, b: *[2]f64) void {
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
