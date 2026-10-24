// --------------------------------------------------------------------------
// OBJ demo: one frame's geometry, integers only. transform() turns and
// projects every vertex (and, for Gouraud, lights it); cullSort() keeps the
// faces turned to the eye and orders them far first with a one-pass counting
// sort into 512 depth buckets (stable, so faces in a bucket keep the file
// order; O(n), where the old insertion sort was O(n^2) at 4000 faces). The
// sort moves 8-byte face records (vertices + flat shade), so the draw loop
// reads them in order instead of chasing face ids around the mesh.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const fx = @import("fixed3d.zig");
const fmesh = @import("fmesh.zig");

pub const P = [2]i16;
pub const FLAT_LEVELS = 12; // palette 1..12 (the old LEVELS)
pub const GOURAUD_TOP = 31; // palette 1..32
const MAXV = fmesh.MAX_VERTS;
const MAXF = fmesh.MAX_FACES;
const BUCKETS = 512;

/// A face to draw: its vertices and, for the flat modes, its colour.
/// A projected vertex: where it lands and its rotated z, side by side.
pub const PV = struct { s: P, z: i32 };

pub const Rec = struct { a: u16, b: u16, c: u16, shade: u16 };

pub const Frame = struct {
    pv: [MAXV]PV align(8) = undefined, // screen point + depth, one 8-byte record
    lev: [MAXV]i32 = undefined, // Gouraud light level, Q12
    vis: [MAXF]bool = undefined,
    recs: [MAXF]Rec align(8) = undefined, // sorted, far first: recs[0..nvis]
    tmp: [MAXF]Rec align(8) = undefined, // in file order
    bkt: [MAXF]u16 = undefined, // tmp[i]'s depth bucket
    nvis: u16 = 0,
    lobj: fx.Vec3 = .{ 0, 0, 0 }, // the light in object space
    box: [4]i32 = .{ 0, 0, 0, 0 }, // x0, y0, x1, y1 (inclusive) of the projected vertices

    pub fn transform(self: *Frame, m: *const fmesh.Mesh, mat: *const fx.Mat, gouraud: bool) void {
        self.lobj = fx.lightInObject(mat, fx.LIGHT);
        var box = [4]i32{ 9999, 9999, -9999, -9999 };
        for (m.verts[0..m.nverts], 0..) |v, i| {
            const p = fx.apply(mat, v);
            const s = fx.project(p);
            self.pv[i] = .{ .s = s, .z = p[2] };
            box = .{ @min(box[0], s[0]), @min(box[1], s[1]), @max(box[2], s[0]), @max(box[3], s[1]) };
        }
        self.box = box;
        if (gouraud) {
            for (m.vnorm[0..m.nverts], 0..) |n, i| {
                self.lev[i] = (@as(i32, @intCast(@abs(fx.dot(n, self.lobj)))) * GOURAUD_TOP) >> 2;
            }
        }
    }

    /// The old brightness(): |n . L| over the light ramp, 0..FLAT_LEVELS-2.
    pub fn flatLevel(self: *const Frame, m: *const fmesh.Mesh, f: u16) u8 {
        const d: i32 = @intCast(@abs(fx.dot(m.faces[f].n, self.lobj)));
        return @intCast(@min((d * (FLAT_LEVELS - 1)) >> fx.Q, FLAT_LEVELS - 2));
    }

    pub inline fn facing(self: *const Frame, m: *const fmesh.Mesh, i: usize) bool {
        const f = m.faces[i];
        return (fx.area2(self.pv[f.a].s, self.pv[f.b].s, self.pv[f.c].s) > 0) != (f.inward != 0);
    }

    /// recs[0..nvis] = the faces seen (all of them when !cull), far first,
    /// with their flat shade when `shade`.
    pub fn cullSort(self: *Frame, m: *const fmesh.Mesh, cull: bool, shade: bool) void {
        var count = [_]u16{0} ** (BUCKETS + 1);
        var n: u16 = 0;
        for (m.faces[0..m.nfaces], 0..) |f, i| {
            if (cull and !self.facing(m, i)) continue;
            const zsum = self.pv[f.a].z + self.pv[f.b].z + self.pv[f.c].z;
            // far (large z) first = a small bucket; |zsum| <= ~49200
            const b: u16 = @intCast(@min(@max((60000 - zsum) >> 8, 0), BUCKETS - 1));
            self.bkt[n] = b;
            count[b + 1] += 1;
            self.tmp[n] = .{ .a = f.a, .b = f.b, .c = f.c, .shade = if (shade) 1 + self.flatLevel(m, @intCast(i)) else 0 };
            n += 1;
        }
        self.nvis = n;
        for (1..BUCKETS + 1) |b| count[b] += count[b - 1];
        for (self.tmp[0..n], self.bkt[0..n]) |r, b| {
            self.recs[count[b]] = r;
            count[b] += 1;
        }
    }

    /// Marks vis[] without sorting (hidden-line needs only which faces are seen).
    pub fn cullOnly(self: *Frame, m: *const fmesh.Mesh) void {
        for (0..m.nfaces) |i| self.vis[i] = self.facing(m, i);
    }
};
