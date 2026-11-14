// Mode 3's sphere tracing: a batch of rays marches in LOCKSTEP, one ASTROLABE call a
// step for all of them. The same march as sdf.zig's (up to 64 steps, a hit under EPS,
// a miss past the ray's tmax), as vectors:
//
//   setup, once (60 ops, 2 calls), per ray and sphere i:
//       dd = |d|^2,  b2_i = 2 d.(o - c_i),  qq_i = |o - c_i|^2
//   so that |o + t d - c_i|^2 = dd t^2 + b2_i t + qq_i, and each step is
//       t += m                       1 AXPY  (the last step's distance: 0 at first)
//       T = dd t^2                   2 VMUL
//       d_i = sqrt(b2_i t + T + qq_i) - r_i     5 spheres x (VMUL, 2 VADD, MAP SQRT, AXPY)
//       m = min_i d_i                4 merges x 5 ops
//   = exactly 48 descriptors: one call. hwAstro has no VMIN, so the union is merged
//   EXACTLY with |x| = sqrt(x^2): min(a, b) = b + (d - |d|) / 2, d = a - b
//   (AXPY, VMUL, SQRT, AXPY, AXPY); d - |d| is exactly 0 when b is the nearer.
//
// Between calls ZIGGY reads each live ray's t and m by their bits (bits.zig): past
// tmax = a miss, m under EPS = a hit at this t (whose sphere is the last merge that
// left a 0), else it stays; finished rays are compacted out, so each call's vectors
// hold only the rays still marching. A ray's answer does not depend on its batch.
const sdf = @import("../sdf.zig");
const abi = @import("hardware").astro;
const zg = @import("zigos");
const vq = @import("vq.zig");
const B = @import("bits.zig");
const F = vq.F;

pub const NONE: u8 = 255;
pub const Hit = struct { id: u8, t: u64 }; // id NONE: a miss
const NS = sdf.SPHERES.len;
const EPS = B.of(sdf.EPS_F);

pub const March = struct {
    t: F,
    tmax: F,
    dd: F,
    b2: [NS]F,
    qq: [NS]F,
    d: [NS]F, // the step's distances; after the merges d[NS-1] is the min
    tt: F, // dd t^2, then the merges' scratch
    slot: []u8, // a live row's ray
    rows: [2 + 2 * NS + 2]F = undefined, // what a compaction moves

    pub fn init(self: *March, cap: u32) void {
        inline for (.{ "t", "tmax", "dd", "tt" }) |f| @field(self, f) = alloc(cap);
        inline for (0..NS) |i| {
            self.b2[i] = alloc(cap);
            self.qq[i] = alloc(cap);
            self.d[i] = alloc(cap);
        }
        self.slot = zg.mem.mustAlloc(u8, cap);
        self.rows = [4]F{ self.t, self.tmax, self.dd, self.d[NS - 1] } ++ self.b2 ++ self.qq;
    }

    /// Marches n rays o + t d, each to its own tmax (bits, `tmax`) or to sdf's TMAX
    /// (null); out[k] is ray k's hit. `ones` is an array of 1.0.
    pub fn run(self: *March, q: *vq.Q, n: u32, o: [3]F, d: [3]F, tmax: ?[*]const u64, ones: F, out: []Hit) void {
        if (n == 0) return;
        q.n = n;
        self.setup(q, o, d, ones);
        const tw = B.words(self.t);
        const mw = B.words(self.tmax);
        for (0..n) |k| {
            tw[k] = 0;
            B.words(self.d[NS - 1])[k] = 0;
            mw[k] = if (tmax) |m| m[k] else B.of(sdf.TMAX_F);
            self.slot[k] = @intCast(k);
            out[k] = .{ .id = NONE, .t = 0 };
        }
        var live = n;
        var steps: u32 = 0;
        while (live > 0 and steps < sdf.MAX_STEPS) : (steps += 1) {
            q.n = live;
            self.step(q, ones);
            q.flush();
            live = self.scan(live, out);
        }
    }

    fn setup(self: *March, q: *vq.Q, o: [3]F, d: [3]F, ones: F) void {
        const od = self.d[0];
        const oo = self.d[1];
        const s = self.tt;
        q.dot3(d, o, od, s);
        q.dot3(o, o, oo, s);
        q.dot3(d, d, self.dd, s);
        inline for (sdf.SPHERES, 0..) |c, i| {
            q.scal(2.0, od, self.b2[i]);
            inline for (0..3) |a| q.axpy(-2.0 * c[a], d[a], self.b2[i]);
            q.scal(1.0, oo, self.qq[i]);
            inline for (0..3) |a| q.axpy(-2.0 * c[a], o[a], self.qq[i]);
            q.axpy(c[0] * c[0] + c[1] * c[1] + c[2] * c[2], ones, self.qq[i]);
        }
        q.flush();
    }

    /// One step's 48 descriptors (see the top).
    fn step(self: *March, q: *vq.Q, ones: F) void {
        const m = self.d[NS - 1];
        q.axpy(1.0, m, self.t);
        q.mul(self.t, self.t, self.tt);
        q.mul(self.tt, self.dd, self.tt);
        inline for (sdf.SPHERES, 0..) |c, i| {
            q.mul(self.b2[i], self.t, self.d[i]);
            q.add(self.d[i], self.tt, self.d[i]);
            q.add(self.d[i], self.qq[i], self.d[i]);
            q.map(abi.FN_SQRT, self.d[i], self.d[i]);
            q.axpy(-c[3], ones, self.d[i]);
        }
        inline for (1..NS) |i| { // the running min is in d[i - 1]: it moves to d[i]
            q.axpy(-1.0, self.d[i], self.d[i - 1]);
            q.mul(self.d[i - 1], self.d[i - 1], self.tt);
            q.map(abi.FN_SQRT, self.tt, self.tt);
            q.axpy(-1.0, self.tt, self.d[i - 1]);
            q.axpy(0.5, self.d[i - 1], self.d[i]);
        }
    }

    /// Settles the rays that hit or left; compacts the rest. Returns how many march on.
    fn scan(self: *March, live: u32, out: []Hit) u32 {
        const t = B.words(self.t);
        const m = B.words(self.d[NS - 1]);
        const tmax = B.words(self.tmax);
        var w: u32 = 0;
        for (0..live) |k| {
            if (B.lt(tmax[k], t[k])) continue; // left: a miss
            if (B.lt(m[k], EPS)) {
                out[self.slot[k]] = .{ .id = self.nearest(k), .t = t[k] };
                continue;
            }
            if (w != k) {
                for (self.rows) |a| B.words(a)[w] = B.words(a)[k];
                self.slot[w] = self.slot[k];
            }
            w += 1;
        }
        return w;
    }

    /// The sphere this step's min came from: the last merge whose difference was 0.
    fn nearest(self: *const March, k: usize) u8 {
        var id: u8 = 0;
        inline for (1..NS) |i| {
            if (B.isZero(B.words(self.d[i - 1])[k])) id = i;
        }
        return id;
    }
};

fn alloc(cap: u32) F {
    return zg.mem.mustAlloc(f64, cap).ptr;
}
