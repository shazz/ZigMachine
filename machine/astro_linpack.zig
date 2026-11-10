// --------------------------------------------------------------------------
// ASTROLABE's LINPACK step (SPIKE): netlib linpack.c's dgefa and dgesl (job 0), rolled
// BLAS, the same operations in the same order, on a column-major A (A[lda * col + row]).
// --------------------------------------------------------------------------
const abi = @import("sdk/astro.zig");
const ops = @import("astro_ops.zig");
const blas = @import("astro_blas.zig");
const Mem = ops.Mem;

/// idamax over n elements of column `col` from row `row`: the index of the first largest |x|.
fn idamax(m: Mem, a: u32, f: bool, at: u32, n: u32) u32 {
    if (n <= 1) return 0;
    var dmax = @abs(m.el(a, at, f));
    var best: u32 = 0;
    for (1..n) |k| {
        const v = @abs(m.el(a, at + @as(u32, @intCast(k)), f));
        if (v > dmax) {
            best = @intCast(k);
            dmax = v;
        }
    }
    return best;
}

fn swap(m: Mem, a: u32, f: bool, i: u32, j: u32) void {
    const t = m.el(a, i, f);
    m.setEl(a, i, f, m.el(a, j, f));
    m.setEl(a, j, f, t);
}

/// LU-factors A in place, pivots into `ipvt`. Answers 0, or 1 + a column whose pivot is zero
/// (the last one met, as linpack.c's info).
pub fn gefa(m: Mem, a: u32, lda: u32, n: u32, ipvt: u32, f: bool) u32 {
    if (n == 0) return 0;
    var info: u32 = 0;
    for (0..n - 1) |kk| {
        const k: u32 = @intCast(kk);
        const col = lda * k;
        const l = idamax(m, a, f, col + k, n - k) + k;
        m.st32(ipvt + 4 * k, l);
        if (m.el(a, col + l, f) == 0) {
            info = k + 1;
            continue;
        }
        if (l != k) swap(m, a, f, col + l, col + k);
        const t = -1.0 / m.el(a, col + k, f);
        for (k + 1..n) |i| m.setEl(a, col + @as(u32, @intCast(i)), f, t * m.el(a, col + @as(u32, @intCast(i)), f));
        for (k + 1..n) |jj| {
            const cj = lda * @as(u32, @intCast(jj));
            const tj = m.el(a, cj + l, f);
            if (l != k) {
                m.setEl(a, cj + l, f, m.el(a, cj + k, f));
                m.setEl(a, cj + k, f, tj);
            }
            blas.axpy(m, n - (k + 1), tj, a, f, col + k + 1, a, f, cj + k + 1);
        }
    }
    m.st32(ipvt + 4 * (n - 1), n - 1);
    if (m.el(a, lda * (n - 1) + (n - 1), f) == 0) info = n;
    return info;
}

/// Solves A x = b with gefa's factors; b (at `bv`) becomes x. Every pivot is checked first:
/// a cart's pivot table past the matrix is ST_RANGE, with nothing written.
pub fn gesl(m: Mem, a: u32, lda: u32, n: u32, ipvt: u32, bv: u32, fa: bool, fb: bool) ops.Result {
    if (n == 0) return .{};
    for (0..n - 1) |k| {
        const l = m.ld32(ipvt + 4 * @as(u32, @intCast(k)));
        if (l < k or l >= n) return .{ .status = abi.ST_RANGE };
    }
    for (0..n - 1) |kk| {
        const k: u32 = @intCast(kk);
        const l = m.ld32(ipvt + 4 * k);
        const t = m.el(bv, l, fb);
        if (l != k) {
            m.setEl(bv, l, fb, m.el(bv, k, fb));
            m.setEl(bv, k, fb, t);
        }
        blas.axpy(m, n - (k + 1), t, a, fa, lda * k + k + 1, bv, fb, k + 1);
    }
    for (0..n) |kb| {
        const k: u32 = n - 1 - @as(u32, @intCast(kb));
        m.setEl(bv, k, fb, m.el(bv, k, fb) / m.el(a, lda * k + k, fa));
        blas.axpy(m, k, -m.el(bv, k, fb), a, fa, lda * k, bv, fb, 0);
    }
    return .{};
}
