// Mode 3: the same 16 samples a pixel as modes 1 and 2, with every number an f64 on
// ASTROLABE (on the board: the ARM Cortex-A9's VFPv3; in the browser: the machine
// standing in for it, the same kernels). A chunk of BATCH samples is one batch of
// primary rays; rays.zig traces it in vector descriptors, a few calls for the floor
// and the shading, and ONE call a step for each lockstep march (march.zig): the
// primary rays, their shadow rays, the chrome sphere's reflections and theirs.
//
// What hwAstro lacks, and what stands in for it (docs/ARM_FPU_COPROC.md has the ABI):
//   VMIN    the union of five spheres: min(a, b) = b + (d - |d|)/2, |d| = sqrt(d^2)
//           (5 descriptors a merge instead of 1)
//   VDIV    1/x as exp(-log x) (3 instead of 1): the floor's oy / -dy, a ray's 1/|d|
//   compare / select / convert: ZIGGY reads the f64 bits between calls (bits.zig)
// Per-frame f64 is allowed here on purpose (CLAUDE.md "float math": mode 3 is the f64
// benchmark): all of it is in the descriptors; ZIGGY itself does no float op.
const abi = @import("hardware").astro;
const T = @import("../trace.zig");
const samples = @import("../samples.zig");
const Item = @import("../work.zig").Item;
const Shade = @import("../shade.zig").Shade;
const vq = @import("vq.zig");
const B = @import("bits.zig");
const L = @import("level.zig");
const rays = @import("rays.zig");
const March = @import("march.zig").March;

/// Rays a batch. The board's cost is per element (glass stages each array through
/// uncached DDR) plus ~18 us a call; 64 keeps a batch near a frame or two there.
pub const BATCH: u32 = 64;

// The primary rays' pieces, as f64 bits: (x - 160) * PIXEL, (62 - y) * PIXEL, each
// sample's jitter * PIXEL (y negated: rows go down), each sample's light direction.
const XS = table(T.IMG_W, 160, 1);
const YS = table(T.IMG_H, T.HORIZON_ROW, -1);
const JX = jitter(0, 1);
const JY = jitter(1, -1);
const LB = blk: {
    var o: [samples.N][3]u64 = undefined;
    for (0..samples.N) |j| o[j] = .{ B.of(samples.LIGHT[j][0]), B.of(samples.LIGHT[j][1]), B.of(samples.LIGHT[j][2]) };
    break :blk o;
};

fn table(comptime n: u32, comptime c: i32, comptime sign: i32) [n]u64 {
    var o: [n]u64 = undefined;
    for (0..n) |i| o[i] = B.of(@as(f64, @floatFromInt(sign * (@as(i32, @intCast(i)) - c))) * T.PIXEL_F);
    return o;
}

fn jitter(comptime axis: usize, comptime sign: f64) [samples.N]u64 {
    var o: [samples.N]u64 = undefined;
    for (0..samples.N) |j| o[j] = B.of(sign * samples.JIT[j][axis] * T.PIXEL_F);
    return o;
}

pub const Engine = struct {
    q: vq.Q,
    march: March,
    top: L.Level,
    child: L.Level,
    sh: L.Shadow,
    ones: vq.F,

    pub fn init(self: *Engine) void {
        self.q = .{};
        self.march.init(BATCH);
        self.top.init(BATCH);
        self.child.init(BATCH);
        self.sh.init(BATCH);
        self.ones = L.alloc(BATCH);
        for (0..BATCH) |k| B.words(self.ones)[k] = B.of(1.0);
    }

    pub fn side(self: *const Engine) vq.Side {
        return self.q.side;
    }

    /// The Shades of `items`' samples into `out`; counts the rays as trace.zig does.
    pub fn trace(self: *Engine, items: []const Item, out: []Shade, st: *T.Stats) void {
        const n: u32 = @intCast(items.len);
        if (n == 0) return;
        self.primary(items);
        const cx = rays.Ctx{ .q = &self.q, .march = &self.march, .sh = &self.sh, .ones = self.ones, .st = st };
        rays.trace(cx, &self.top, &self.child, n);
        @memcpy(out, self.top.out[0..n]);
    }

    /// d = unit(u, v, 1), 1/|.| as exp(-log(|.|^2) / 2); o = the camera; l = the sample's.
    fn primary(self: *Engine, items: []const Item) void {
        const lv = &self.top;
        const r = &lv.r;
        const u = lv.fx;
        const ju = lv.fz;
        const v = lv.qs;
        const jv = lv.fog;
        for (items, 0..) |it, k| {
            B.words(u)[k] = XS[it.x];
            B.words(ju)[k] = JX[it.j];
            B.words(v)[k] = YS[it.y];
            B.words(jv)[k] = JY[it.j];
            inline for (0..3) |a| B.words(r.l[a])[k] = LB[it.j][a];
        }
        const q = &self.q;
        q.n = @intCast(items.len);
        q.add(u, ju, r.d[0]);
        q.add(v, jv, r.d[1]);
        q.mul(r.d[0], r.d[0], lv.s);
        q.mul(r.d[1], r.d[1], lv.tf);
        q.add(lv.s, lv.tf, lv.s);
        q.axpy(1.0, self.ones, lv.s);
        q.map(abi.FN_LOG, lv.s, lv.s);
        q.scal(-0.5, lv.s, lv.s);
        q.map(abi.FN_EXP, lv.s, r.d[2]);
        q.mul(r.d[0], r.d[2], r.d[0]);
        q.mul(r.d[1], r.d[2], r.d[1]);
        inline for (0..3) |a| q.scal(T.CAM_F[a], self.ones, r.o[a]);
    }
};

comptime {
    if (BATCH > 256) @compileError("march.zig keeps a ray's slot in a u8");
}
