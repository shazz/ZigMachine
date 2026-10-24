// --------------------------------------------------------------------------
// OBJ demo: one frame's geometry, integers only. transform() turns and
// projects every vertex (and, for Gouraud, lights it); cullSort() keeps the
// faces turned to the eye and orders them far first with a two-pass LSD radix
// sort of 16-bit depth keys (stable, so equal depths keep the file order, as
// the old insertion sort did; O(n), where that was O(n^2) at 4000 faces).
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const fx = @import("fixed3d.zig");
const fmesh = @import("fmesh.zig");

pub const P = [2]i16;
pub const FLAT_LEVELS = 12; // palette 1..12 (the old LEVELS)
pub const GOURAUD_TOP = 31; // palette 1..32
const MAXV = fmesh.MAX_VERTS;
const MAXF = fmesh.MAX_FACES;

pub const Frame = struct {
    scr: [MAXV]P = undefined,
    z: [MAXV]i32 = undefined,
    lev: [MAXV]i32 = undefined, // Gouraud light level, Q12
    vis: [MAXF]bool = undefined,
    order: [MAXF]u16 = undefined,
    tmp: [MAXF]u16 = undefined,
    keys: [MAXF]u16 = undefined,
    keys2: [MAXF]u16 = undefined,
    nvis: u16 = 0,
    lobj: fx.Vec3 = .{ 0, 0, 0 }, // the light in object space
    box: [4]i32 = .{ 0, 0, 0, 0 }, // x0, y0, x1, y1 (inclusive) of the projected vertices

    pub fn transform(self: *Frame, m: *const fmesh.Mesh, mat: fx.Mat, gouraud: bool) void {
        self.lobj = fx.lightInObject(mat, fx.LIGHT);
        var box = [4]i32{ 9999, 9999, -9999, -9999 };
        for (m.verts[0..m.nverts], 0..) |v, i| {
            const p = fx.apply(mat, v);
            const s = fx.project(p);
            self.scr[i] = s;
            self.z[i] = p[2];
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
        const d: i32 = @intCast(@abs(fx.dot(m.fnorm[f], self.lobj)));
        return @intCast(@min((d * (FLAT_LEVELS - 1)) >> fx.Q, FLAT_LEVELS - 2));
    }

    pub fn facing(self: *const Frame, m: *const fmesh.Mesh, i: usize) bool {
        const f = m.faces[i];
        return (fx.area2(self.scr[f.a], self.scr[f.b], self.scr[f.c]) > 0) != m.inward[i];
    }

    /// order[0..nvis] = the faces seen (all of them when !cull), far first.
    pub fn cullSort(self: *Frame, m: *const fmesh.Mesh, cull: bool) void {
        var n: u16 = 0;
        for (m.faces[0..m.nfaces], 0..) |f, i| {
            const seen = !cull or self.facing(m, i);
            self.vis[i] = seen;
            if (!seen) continue;
            const zsum = self.z[f.a] + self.z[f.b] + self.z[f.c];
            // far (large z) first = a small key; |zsum| <= ~49200
            self.keys[n] = @intCast(@min(@max((60000 - zsum) >> 1, 0), 65535));
            self.order[n] = @intCast(i);
            n += 1;
        }
        self.nvis = n;
        radixPass(self.order[0..n], self.tmp[0..n], self.keys[0..n], self.keys2[0..n], 0);
        radixPass(self.tmp[0..n], self.order[0..n], self.keys2[0..n], null, 8);
    }

    /// Marks vis[] without sorting (hidden-line needs only which faces are seen).
    pub fn cullOnly(self: *Frame, m: *const fmesh.Mesh) void {
        for (0..m.nfaces) |i| self.vis[i] = self.facing(m, i);
    }
};

/// One stable counting pass on byte `shift/8` of the keys: src -> dst, with the
/// keys carried along into `kout` (first pass) so the second reads them in order.
fn radixPass(src: []const u16, dst: []u16, kin: []const u16, kout: ?[]u16, comptime shift: u4) void {
    var count = [_]u16{0} ** 257;
    for (kin) |k| count[((k >> shift) & 0xFF) + 1] += 1;
    for (1..257) |b| count[b] += count[b - 1];
    for (src, 0..) |id, i| {
        const b = (kin[i] >> shift) & 0xFF;
        const at = count[b];
        count[b] += 1;
        dst[at] = id;
        if (kout) |ko| ko[at] = kin[i];
    }
}
