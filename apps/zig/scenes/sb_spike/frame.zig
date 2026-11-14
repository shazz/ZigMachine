// --------------------------------------------------------------------------
// SB SPIKE: one frame of mix3, as the four costs the spike measures.
//
//   animate    the 30 Hz keys -> a model-view an item (anim.zig)
//   transform  every vertex of the LOD -> screen Q4, texel, depth (xform.zig)
//   cullBin    triangles: near-plane reject, off-screen reject, back-face cull; a
//              kept one is copied out (its three 8-byte vertices) with a depth bucket
//   sort       a counting sort: the records copied again, in bucket order (no Z buffer:
//              painter's order a triangle; all textures sit in one atlas, so the
//              order needs no texture switch). Then emit reads them in sequence,
//              not three random vertices a triangle (the 4 KB D$).
//   emit       far to near: setup + spans (raster.zig) into a Sink; the Sink fires
//              a CHISEL AFFINE op each CHUNK spans (sink.zig)
// Each is its own noinline function so apps/frame_cost.mjs bills it by name.
// No ZigOS import: the Sink is a parameter.
// --------------------------------------------------------------------------
const anim = @import("anim.zig");
const data = @import("data.zig");
const xform = @import("xform.zig");
const raster = @import("raster.zig");

const L = data.layout;
pub const BUCKETS = 1024;
const DEPTH_SHIFT = 4; // depth sum (3 x Q8) >> 4: 1/16 unit a bucket, 63 units deep
pub const Y_MIN = 10;
pub const Y_MAX = 190;
/// Triangles kept a frame at most (mix3 at 1x keeps ~6,000); past it they are dropped, counted.
pub const MAX_KEPT = 7168;

pub const Rec = [3]xform.PV;
pub const Stats = struct { submitted: u32 = 0, near: u32 = 0, off: u32 = 0, culled: u32 = 0, drawn: u32 = 0, dropped: u32 = 0 };

pub const Frame = struct {
    pv: []xform.PV, // data.MAX_VERTS
    depth: []u16, // data.MAX_VERTS
    kept: []Rec, // MAX_KEPT, in mesh order
    sorted: []Rec, // MAX_KEPT, far to near
    key: []u16, // MAX_KEPT
    count: *[BUCKETS + 1]u32,
    mv: [data.ITEMS]anim.ModelView = undefined,
    base: [data.ITEMS]u16 = undefined,
    stats: Stats = .{},

    pub noinline fn animate(self: *Frame, time: u32) void {
        const view = anim.camera(time);
        for (L.items, 0..) |it, i| self.mv[i] = anim.modelView(it.node, time, &view);
    }

    pub noinline fn transform(self: *Frame, lod: usize, env: bool) void {
        var n: usize = 0;
        for (L.items, 0..) |it, i| {
            self.base[i] = @intCast(n);
            const vs = data.verts(lod, i);
            if (it.env and !env) {
                @memset(self.depth[n..][0..vs.len], 0);
            } else xform.item(self.pv[n..], self.depth[n..], vs, &self.mv[i], it);
            n += vs.len;
        }
    }

    pub noinline fn cullBin(self: *Frame, lod: usize) void {
        var st = Stats{};
        @memset(self.count, 0);
        var n: u32 = 0;
        for (L.items, 0..) |it, i| {
            const pv = self.pv[self.base[i]..];
            const dz = self.depth[self.base[i]..];
            const ts = data.tris(lod, i);
            st.submitted += @intCast(ts.len);
            for (ts) |t| {
                const za = dz[t[0]];
                const zb = dz[t[1]];
                const zc = dz[t[2]];
                if (za == 0 or zb == 0 or zc == 0) {
                    st.near += 1;
                    continue;
                }
                const a = pv[t[0]];
                const b = pv[t[1]];
                const c = pv[t[2]];
                if (offScreen(a, b, c)) {
                    st.off += 1;
                    continue;
                }
                // Q2 (|x| < 2^15 Q4): the products stay inside an i32
                const area = ((@as(i32, b.x) - a.x) >> 2) * ((@as(i32, c.y) - a.y) >> 2) - ((@as(i32, c.x) - a.x) >> 2) * ((@as(i32, b.y) - a.y) >> 2);
                if (area >= 0) {
                    st.culled += 1;
                    continue;
                }
                if (n == MAX_KEPT) {
                    st.dropped += 1;
                    continue;
                }
                const k: u32 = if (it.layer < 2) it.layer else BUCKETS - 1 - @min((@as(u32, za) + zb + zc) >> DEPTH_SHIFT, BUCKETS - 3);
                self.kept[n] = .{ a, b, c };
                self.key[n] = @intCast(k);
                self.count[k + 1] += 1;
                n += 1;
            }
        }
        st.drawn = n;
        self.stats = st;
    }

    inline fn offScreen(a: xform.PV, b: xform.PV, c: xform.PV) bool {
        return @max(a.x, b.x, c.x) < 0 or @min(a.x, b.x, c.x) >= 320 * 16 or
            @max(a.y, b.y, c.y) < Y_MIN * 16 or @min(a.y, b.y, c.y) >= Y_MAX * 16;
    }

    pub noinline fn sort(self: *Frame) void {
        const n = self.stats.drawn;
        for (1..BUCKETS + 1) |k| self.count[k] += self.count[k - 1];
        for (self.kept[0..n], self.key[0..n]) |r, k| {
            self.sorted[self.count[k]] = r;
            self.count[k] += 1;
        }
    }

    pub noinline fn emit(self: *Frame, comptime Sink: type, sink: *Sink) void {
        var e = raster.Emitter(Sink){ .sink = sink, .y_min = Y_MIN, .y_max = Y_MAX, .w = 320 };
        for (self.sorted[0..self.stats.drawn]) |*r| e.tri(p(r[0]), p(r[1]), p(r[2]));
    }

    inline fn p(v: xform.PV) raster.P {
        return .{ .x = v.x, .y = v.y, .u = @as(u32, v.u) << 8, .v = @as(u32, v.v) << 11 };
    }
};
