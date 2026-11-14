// Mode 3's tracer: trace.zig's trace() for a whole Level of rays at once. The maths is
// ASTROLABE's (vector descriptors: the floor's distance, the lockstep march, the
// shading terms); ZIGGY only moves bits between calls: it decides with integer
// compares (bits.zig) which rays met the floor, a sphere or the sky, which need a
// shadow ray, which reflect, and makes each ray's Shade (shade.zig). The shading terms
// are computed for every ray of the level (a ray that did not hit a sphere just gets
// numbers nobody reads): no select exists, and a smaller vector would cost a gather.
const abi = @import("hardware").astro;
const sdf = @import("../sdf.zig");
const T = @import("../trace.zig");
const Shade = @import("../shade.zig");
const vq = @import("vq.zig");
const B = @import("bits.zig");
const L = @import("level.zig");
const March = @import("march.zig").March;
const NONE = @import("march.zig").NONE;
const F = vq.F;

pub const Ctx = struct { q: *vq.Q, march: *March, sh: *L.Shadow, ones: F, st: *T.Stats };

const TMAX = B.of(sdf.TMAX_F);
const LIT_Q: f64 = 256.0 * T.DIFFUSE_F;
const Q_AMB: u16 = @intFromFloat(@floor(256.0 * T.AMB_F * T.DIFFUSE_F)); // unlit: ambient only

/// Traces lv's n rays into lv.out; `child` takes the chrome sphere's reflections
/// (the primary level), null at depth 1, where chrome is shaded as a material.
pub fn trace(cx: Ctx, lv: *L.Level, child: ?*L.Level, n: u32) void {
    if (n == 0) return;
    floor(cx, lv, n);
    cx.march.run(cx.q, n, lv.r.o, lv.r.d, lv.tmax.ptr, cx.ones, lv.hits);
    cx.st.rays += n;
    gather(lv, n);
    shade(cx, lv, n, child != null);
    shadows(cx, lv, n, child != null);
    resolve(lv, n, child != null);
    if (child) |ch| reflections(cx, lv, ch, n);
}

/// tf = oy / -dy as exp(log oy - log -dy) (no vector divide), the floor point, the sky's
/// and the fog's intensities; then each ray's tmax and its first guess, floor or sky.
fn floor(cx: Ctx, lv: *L.Level, n: u32) void {
    const q = cx.q;
    const o = lv.r.o;
    const d = lv.r.d;
    q.n = n;
    q.scal(-1.0, d[1], lv.tf);
    q.map(abi.FN_LOG, lv.tf, lv.tf);
    q.map(abi.FN_LOG, o[1], lv.fog);
    q.axpy(-1.0, lv.tf, lv.fog);
    q.map(abi.FN_EXP, lv.fog, lv.tf);
    q.scal(256.0 * T.SKY_F, d[1], lv.qs);
    q.scal(256.0 * T.FOG_F, lv.tf, lv.fog);
    q.mul(d[0], lv.tf, lv.fx);
    q.add(lv.fx, o[0], lv.fx);
    q.mul(d[2], lv.tf, lv.fz);
    q.add(lv.fz, o[2], lv.fz);
    q.flush();
    const oy = B.words(o[1]);
    const dy = B.words(d[1]);
    const tf = B.words(lv.tf);
    for (0..n) |k| {
        const meets = !B.notPositive(oy[k]) and !B.lt(B.of(-sdf.FLOOR_DY_F), dy[k]) and B.lt(tf[k], TMAX);
        lv.tmax[k] = if (meets) tf[k] else TMAX;
        lv.kind[k] = if (meets) L.K_FLOOR else L.K_SKY;
    }
}

/// A sphere hit's t, centre and 1/r by its id (zeros for the other rays).
fn gather(lv: *L.Level, n: u32) void {
    const S = comptime blk: {
        var s: [sdf.SPHERES.len][4]u64 = undefined;
        for (sdf.SPHERES, 0..) |c, i| s[i] = .{ B.of(c[0]), B.of(c[1]), B.of(c[2]), B.of(1.0 / c[3]) };
        break :blk s;
    };
    for (0..n) |k| {
        const h = lv.hits[k];
        const s: [4]u64 = if (h.id == NONE) .{ 0, 0, 0, 0 } else S[h.id];
        if (h.id != NONE) lv.kind[k] = L.K_SPHERE;
        B.words(lv.ht)[k] = h.t;
        inline for (0..3) |a| B.words(lv.c[a])[k] = s[a];
        B.words(lv.ir)[k] = s[3];
    }
}

/// trace.zig's sphere() and lightAt() terms, x256: the lifted point po, the normal,
/// diff = n.l, the lit intensity, the highlight (l.d - 2 diff n.d)^16, the reflection.
fn shade(cx: Ctx, lv: *L.Level, n: u32, reflect: bool) void {
    const q = cx.q;
    const r = lv.r;
    q.n = n;
    inline for (0..3) |a| {
        q.mul(r.d[a], lv.ht, lv.p[a]);
        q.add(lv.p[a], r.o[a], lv.p[a]);
        q.scal(1.0, lv.p[a], lv.n[a]);
        q.axpy(-1.0, lv.c[a], lv.n[a]);
        q.mul(lv.n[a], lv.ir, lv.n[a]);
        q.axpy(sdf.SELF_F, lv.n[a], lv.p[a]);
    }
    q.dot3(lv.n, r.l, lv.diff, lv.s);
    q.dot3(lv.n, r.d, lv.nd, lv.s);
    q.dot3(r.l, r.d, lv.sp, lv.s);
    q.scal(LIT_Q * (1.0 - T.AMB_F), lv.diff, lv.litf);
    q.axpy(LIT_Q * T.AMB_F, cx.ones, lv.litf);
    q.mul(lv.diff, lv.nd, lv.s);
    q.axpy(-2.0, lv.s, lv.sp);
    q.mul(lv.sp, lv.sp, lv.s);
    inline for (0..3) |_| q.mul(lv.s, lv.s, lv.s);
    q.scal(1.0, lv.litf, lv.lits);
    q.axpy(256.0 * T.SPEC_F, lv.s, lv.lits);
    if (reflect) inline for (0..3) |a| {
        q.mul(lv.n[a], lv.nd, lv.s);
        q.scal(1.0, r.d[a], lv.refl[a]);
        q.axpy(-2.0, lv.s, lv.refl[a]);
    };
    q.flush();
}

/// Is a sphere ray shaded here (not the primary level's chrome, which reflects)?
fn matte(lv: *const L.Level, k: usize, reflect: bool) bool {
    return lv.kind[k] == L.K_SPHERE and !(reflect and lv.hits[k].id == 0);
}

/// One shadow ray toward the light from every floor point and every sphere point that
/// faces it; marched as one more lockstep batch.
fn shadows(cx: Ctx, lv: *L.Level, n: u32, reflect: bool) void {
    const sh = cx.sh;
    var ns: u32 = 0;
    for (0..n) |k| {
        lv.lit[k] = false;
        const on_floor = lv.kind[k] == L.K_FLOOR;
        if (!on_floor and !(matte(lv, k, reflect) and !B.notPositive(B.words(lv.diff)[k]))) continue;
        const o = [3]u64{ if (on_floor) B.words(lv.fx)[k] else B.words(lv.p[0])[k], if (on_floor) B.of(sdf.SELF_F) else B.words(lv.p[1])[k], if (on_floor) B.words(lv.fz)[k] else B.words(lv.p[2])[k] };
        inline for (0..3) |a| {
            B.words(sh.o[a])[ns] = o[a];
            B.words(sh.d[a])[ns] = B.words(lv.r.l[a])[k];
        }
        sh.owner[ns] = @intCast(k);
        ns += 1;
    }
    cx.st.rays += ns;
    cx.march.run(cx.q, ns, sh.o, sh.d, null, cx.ones, sh.hits);
    for (0..ns) |s| lv.lit[sh.owner[s]] = sh.hits[s].id == NONE;
}

/// Each ray's Shade from the bits (the primary level's chrome rays: reflect() overwrites).
fn resolve(lv: *L.Level, n: u32, reflect: bool) void {
    for (0..n) |k| {
        lv.out[k] = switch (lv.kind[k]) {
            L.K_SKY => .{ .cls = Shade.CLS_SKY, .q = B.q8(B.words(lv.qs)[k]), .fog = 0 },
            L.K_FLOOR => .{
                .cls = Shade.CLS_FLOOR + @as(u8, @intCast((B.floor(B.words(lv.fx)[k]) +% B.floor(B.words(lv.fz)[k])) & 1)),
                .q = if (lv.lit[k]) 256 else T.SHADOW_Q,
                .fog = B.q8(B.words(lv.fog)[k]),
            },
            else => .{ .cls = Shade.CLS_MAT + lv.hits[k].id, .q = sphereQ(lv, k, reflect), .fog = 0 },
        };
    }
}

fn sphereQ(lv: *const L.Level, k: usize, reflect: bool) u16 {
    if (!matte(lv, k, reflect) or !lv.lit[k]) return Q_AMB;
    const sp = B.words(lv.sp)[k];
    return B.q8(if (B.notPositive(sp)) B.words(lv.litf)[k] else B.words(lv.lits)[k]);
}

/// The chrome sphere's rays go on from po along the reflection, in the child level.
fn reflections(cx: Ctx, lv: *L.Level, ch: *L.Level, n: u32) void {
    var nc: u32 = 0;
    for (0..n) |k| {
        if (lv.kind[k] != L.K_SPHERE or lv.hits[k].id != 0) continue;
        inline for (0..3) |a| {
            B.words(ch.r.o[a])[nc] = B.words(lv.p[a])[k];
            B.words(ch.r.d[a])[nc] = B.words(lv.refl[a])[k];
            B.words(ch.r.l[a])[nc] = B.words(lv.r.l[a])[k];
        }
        ch.owner[nc] = @intCast(k);
        nc += 1;
    }
    trace(cx, ch, null, nc);
    for (0..nc) |c| lv.out[ch.owner[c]] = ch.out[c];
}
