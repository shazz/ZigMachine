// Mode 3's descriptor queue: vector ops over the batch's f64 arrays, queued and sent
// to ASTROLABE (env.hwAstro) up to abi.MAX_COUNT (48, the board's mailbox) a call.
// One call costs a round trip on the board (~18 us measured from ZIGGY, ASTRO BENCH),
// so the march sends ONE call a step for the whole batch (march.zig: exactly 48 ops).
//
// The scalars (S0) are compile-time constants: storing them is a word store, never a
// float op on ZIGGY. Per-frame f64 here is the point of mode 3, and it all runs on the
// ARM (or, in the browser, in the machine standing in for it).
const zg = @import("zigos");
const abi = @import("hardware").astro;
const Desc = zg.astro.Desc;

pub const F = [*]f64;

/// Who served the last call: the ARM, ZIGGY's fallback on a board without it (the
/// machine's code, W_CYCLES set), the host (the browser / native machine), or a refusal.
pub const Side = enum { host, arm, soft, failed };

pub const Q = struct {
    d: [abi.MAX_COUNT]Desc = undefined,
    k: u32 = 0, // descriptors queued
    n: u32 = 0, // elements of the ops queued next: the batch's live rays
    side: Side = .host,
    fails: u32 = 0,
    calls: u32 = 0,

    pub fn flush(q: *Q) void {
        if (q.k == 0) return;
        const st = zg.astro.run(q.d[0..q.k]);
        q.calls += 1;
        if (st != abi.ST_OK) q.fails += 1;
        q.side = if (q.fails != 0) .failed else if (zg.astro.servedByArm(q.d[0])) .arm else if (q.d[0].cycles != 0) .soft else .host;
        q.k = 0;
    }

    fn push(q: *Q, d: Desc) void {
        if (q.n == 0) return;
        if (q.k == abi.MAX_COUNT) q.flush();
        q.d[q.k] = d;
        q.k += 1;
    }

    /// C = A + B
    pub fn add(q: *Q, a: F, b: F, c: F) void {
        q.push(.{ .op = abi.OP_VADD, .n = q.n, .a = addr(a), .b = addr(b), .c = addr(c) });
    }
    /// C = A * B
    pub fn mul(q: *Q, a: F, b: F, c: F) void {
        q.push(.{ .op = abi.OP_VMUL, .n = q.n, .a = addr(a), .b = addr(b), .c = addr(c) });
    }
    /// B += s * A (nothing at all when s is 0: netlib's daxpy)
    pub fn axpy(q: *Q, comptime s: f64, a: F, b: F) void {
        if (s == 0) return;
        q.push(.{ .op = abi.OP_AXPY, .n = q.n, .a = addr(a), .b = addr(b), .s0 = s });
    }
    /// C = s * A
    pub fn scal(q: *Q, comptime s: f64, a: F, c: F) void {
        q.push(.{ .op = abi.OP_SCAL, .n = q.n, .a = addr(a), .c = addr(c), .s0 = s });
    }
    /// C = f(A), f one of abi.FN_*
    pub fn map(q: *Q, comptime f: u32, a: F, c: F) void {
        q.push(.{ .op = abi.OP_MAP, .n = q.n, .m = f, .a = addr(a), .c = addr(c) });
    }
    /// C = A . B per element, for 3-vectors in three arrays each; `t` is scratch.
    pub fn dot3(q: *Q, a: [3]F, b: [3]F, c: F, t: F) void {
        q.mul(a[0], b[0], c);
        q.mul(a[1], b[1], t);
        q.add(c, t, c);
        q.mul(a[2], b[2], t);
        q.add(c, t, c);
    }
};

fn addr(p: F) u32 {
    return @intCast(@intFromPtr(p));
}
