// --------------------------------------------------------------------------
// The torus projected in INTEGERS, for the default cart: the same steps as
// project_f32.zig (which says what each one is in three.js), Q16.16 throughout.
//
//   rotation   the Euler XYZ matrix from two fixtrig angles: 4 table lookups
//   vertex     3x3 widening multiplies, then canvas x = Kx x'/w and
//              y = Ky y'/w with w = 400 - z' (one 32-bit divide a vertex)
//   face       the facing test as two integer cross products; its depth is the
//              rotated centroid's z' (NDC z only re-orders it), sorted by
//              insertion on a byte index instead of moving 80-byte polygons
//   overdraw   CanvasRenderer's 1 px push, with a 32-bit integer square root
// --------------------------------------------------------------------------
const zg = @import("zigos");
const c3 = zg.zig3d;
const trig = zg.fixtrig;
const shade = @import("shade.zig");
const torus = @import("torus.zig");

const ONE: i32 = 1 << 16;
pub const V3 = struct { x: i32, y: i32, z: i32 };
/// A face ready to fill: four corners in small-canvas pixels, Q16.
pub const Quad = [4][2]i32;
const Screen = struct { x: i32, y: i32 };

/// Kx = P0 * half width and Ky = P5 * half height, in Q16, from three.js's
/// perspective matrix (built once, in float, by zig3d's Lens).
pub const Lens = struct {
    kx: i64,
    ky: i64,
    half_w: i32,
    half_h: i32,

    pub fn init() Lens {
        const l = c3.Lens.init(shade.CELLS_X, shade.CELLS_Y, shade.FOV, shade.NEAR, shade.FAR);
        const e = l.projection.e;
        return .{
            .kx = @intFromFloat(@round(@as(f64, e[0]) * l.half_w * 65536.0)),
            .ky = @intFromFloat(@round(@as(f64, e[5]) * l.half_h * 65536.0)),
            .half_w = @intFromFloat(l.half_w),
            .half_h = @intFromFloat(l.half_h),
        };
    }
};

pub fn q16(v: c3.Vec3) V3 {
    return .{ .x = @intFromFloat(@round(v.x * 65536.0)), .y = @intFromFloat(@round(v.y * 65536.0)), .z = @intFromFloat(@round(v.z * 65536.0)) };
}

/// Object3D.updateMatrix's rotation (Euler XYZ, z = 0) as its 3x3 rows, Q16.
pub fn rotation(rx: trig.Angle, ry: trig.Angle) [3]V3 {
    const g = trig.cos(rx);
    const d = trig.sin(rx);
    const h = trig.cos(ry);
    const e = trig.sin(ry);
    return .{
        .{ .x = h, .y = 0, .z = e },
        .{ .x = trig.mul(d, e), .y = g, .z = -trig.mul(d, h) },
        .{ .x = -trig.mul(g, e), .y = d, .z = trig.mul(g, h) },
    };
}

pub fn dot(a: V3, b: V3) i32 {
    const s = @as(i64, a.x) * b.x + @as(i64, a.y) * b.y + @as(i64, a.z) * b.z;
    return @intCast(s >> 16);
}

var screen: [torus.VERTS]Screen = undefined;
var depth: [torus.FACES]i32 = undefined;
var order: [torus.FACES]u8 = undefined;

/// The visible faces, far to near, as indices into `faces`; quads[i] is face
/// i's corners (only the visible ones are written).
pub fn project(lens: *const Lens, m: *const [3]V3, verts: []const V3, centroids: []const V3, faces: []const c3.Face, quads: []Quad) []const u8 {
    const cam: i64 = @as(i64, shade.CAM_Z) << 16;
    for (verts, screen[0..verts.len]) |v, *s| {
        const w: i32 = @intCast(cam - dot(m[2], v)); // always 305..495 px: never near the camera
        // 1/w as 2^41 / w: one 32-bit divide (w in Q6 is 19,500..31,700, so
        // the quotient keeps 17 bits) instead of two 64-bit ones
        const inv: i64 = @divTrunc(@as(i32, 0x7FFF_FFFF), w >> 10);
        s.* = .{ .x = persp(lens.kx, dot(m[0], v), inv), .y = persp(lens.ky, dot(m[1], v), inv) };
    }
    var n: usize = 0;
    for (faces, centroids, 0..) |f, c, i| {
        if (!clockwise(f)) continue;
        depth[i] = dot(m[2], c); // larger = nearer the camera
        var q: Quad = undefined;
        for (0..4) |k| q[k] = .{ screen[f.v[k]].x, screen[f.v[k]].y };
        overdraw(&q);
        for (&q) |*pt| pt.* = .{ pt[0] + lens.half_w * ONE, -pt[1] + lens.half_h * ONE };
        quads[i] = q;
        // insertion by depth, far first; equal depths keep mesh order
        var j = n;
        while (j > 0 and depth[order[j - 1]] > depth[i]) : (j -= 1) order[j] = order[j - 1];
        order[j] = @intCast(i);
        n += 1;
    }
    return order[0..n];
}

/// k * c / w in Q16, given inv = 2^41 / w.
fn persp(k: i64, c: i32, inv: i64) i32 {
    return @intCast(((k * c) >> 16) * inv >> 25);
}

/// Projector's facing test (a Face4), on the projected corners.
fn clockwise(f: c3.Face) bool {
    const v1 = screen[f.v[0]];
    const v2 = screen[f.v[1]];
    const v3 = screen[f.v[2]];
    const v4 = screen[f.v[3]];
    return cross(v4.x - v1.x, v2.y - v1.y, v4.y - v1.y, v2.x - v1.x) < 0 or
        cross(v2.x - v3.x, v4.y - v3.y, v2.y - v3.y, v4.x - v3.x) < 0;
}

fn cross(a: i32, b: i32, c: i32, d: i32) i64 {
    return @as(i64, a) * b - @as(i64, c) * d;
}

/// CanvasRenderer's overdraw for a Face4: pushes (1,2) (2,4) (4,1), then moves
/// 3 away from the un-pushed 2 and 4.
fn overdraw(q: *Quad) void {
    var v2 = q[1];
    var v4 = q[3];
    push(&q[0], &q[1]);
    push(&q[1], &q[3]);
    push(&q[3], &q[0]);
    push(&q[2], &v2);
    push(&q[2], &v4);
}

/// a and b each move 1 px apart along their line, in 32-bit integers only.
/// The edge is scaled to keep 14 significant bits (an edge near the torus's
/// silhouette projects to a hundredth of a pixel, and a FIXED scale loses its
/// direction: that cost a hundred cells their size against the f32 cart), so
/// the squares fit a u32 and the unit vector is one 32-bit divide per axis.
fn push(a: *[2]i32, b: *[2]i32) void {
    const cx = b[0] - a[0];
    const cy = b[1] - a[1];
    const m = @max(@abs(cx), @abs(cy));
    if (m == 0) return;
    const shift: u5 = @intCast(@max(14, 32 - @as(u32, @clz(m))) - 14);
    const x = cx >> shift; // |x|, |y| < 2^14
    const y = cy >> shift;
    const len: i32 = @intCast(isqrt(@intCast(x * x + y * y)));
    if (len == 0) return;
    const ux = @divTrunc(x << 16, len);
    const uy = @divTrunc(y << 16, len);
    b[0] += ux;
    b[1] += uy;
    a[0] -= ux;
    a[1] -= uy;
}

/// floor(sqrt(n)): one result bit per step, no multiply and no divide.
fn isqrt(n: u32) u32 {
    var rem = n;
    var root: u32 = 0;
    var bit: u32 = 1 << 30;
    while (bit > rem) bit >>= 2;
    while (bit != 0) : (bit >>= 2) {
        if (rem >= root + bit) {
            rem -= root + bit;
            root = (root >> 1) + bit;
        } else root >>= 1;
    }
    return root;
}
