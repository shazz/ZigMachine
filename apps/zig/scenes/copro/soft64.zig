// --------------------------------------------------------------------------
// COPRO: ZIGGY's soft f64, the A side of the ASTROLABE pages. The same
// descriptors the cart hands hwAstro, run here in the cart, op for op in the
// order machine/astro_blas.zig and astro_linpack.zig use (netlib's dgefa /
// dgesl, rolled BLAS), so every result is the same bits as ASTROLABE's (IEEE
// ops, each rounded once; Zig never fuses a * b + c). apps/copro_check.mjs
// holds the two pages to the same pixels.
// FLOAT ON PURPOSE: this is the soft-f64 baseline the A/B measures (CLAUDE.md
// "Float math": no FPU for f64 on ZIGGY, every op here is compiler_rt).
// Only the ops the pages use (f64 arrays): VADD VMUL AXPY SCAL GEMV GEFA GESL.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const abi = @import("hardware").astro;
const Desc = zg.astro.Desc;

fn f(a: u32) [*]f64 {
    return @ptrFromInt(a);
}

/// Runs `d` in order, as hwAstro does (the pages' descriptors are well formed: no checks).
pub fn run(d: []Desc) void {
    for (d) |*x| {
        x.status = abi.ST_OK;
        x.r = one(x.*);
    }
}

fn one(d: Desc) f64 {
    const n = d.n;
    switch (d.op & abi.OP_MASK) {
        abi.OP_VADD => for (0..n) |k| {
            f(d.c)[k] = f(d.a)[k] + f(d.b)[k];
        },
        abi.OP_VMUL => for (0..n) |k| {
            f(d.c)[k] = f(d.a)[k] * f(d.b)[k];
        },
        abi.OP_AXPY => axpy(n, d.s0, f(d.a), f(d.b)),
        abi.OP_SCAL => for (0..n) |k| {
            f(d.c)[k] = d.s0 * f(d.a)[k];
        },
        abi.OP_GEMV => for (0..d.m) |i| {
            var acc: f64 = 0;
            for (0..n) |j| acc += f(d.a)[d.lda * j + i] * f(d.b)[j];
            f(d.c)[i] = acc;
        },
        abi.OP_GEFA => return @floatFromInt(gefa(f(d.a), d.lda, n, @ptrFromInt(d.b))),
        abi.OP_GESL => gesl(f(d.a), d.lda, n, @ptrFromInt(d.b), f(d.c)),
        else => {},
    }
    return 0;
}

fn axpy(n: usize, da: f64, x: [*]const f64, y: [*]f64) void {
    if (da == 0) return;
    for (0..n) |k| y[k] = y[k] + da * x[k];
}

fn gefa(a: [*]f64, lda: u32, n: u32, ipvt: [*]u32) u32 {
    if (n == 0) return 0;
    var info: u32 = 0;
    for (0..n - 1) |k| {
        const col = lda * k;
        var l: usize = k; // idamax: the first largest |x| from row k
        var dmax = @abs(a[col + k]);
        for (k + 1..n) |i| if (@abs(a[col + i]) > dmax) {
            l = i;
            dmax = @abs(a[col + i]);
        };
        ipvt[k] = @intCast(l);
        if (a[col + l] == 0) {
            info = @intCast(k + 1);
            continue;
        }
        if (l != k) std.mem.swap(f64, &a[col + l], &a[col + k]);
        const t = -1.0 / a[col + k];
        for (k + 1..n) |i| a[col + i] = t * a[col + i];
        for (k + 1..n) |j| {
            const cj = lda * j;
            const tj = a[cj + l];
            if (l != k) {
                a[cj + l] = a[cj + k];
                a[cj + k] = tj;
            }
            axpy(n - (k + 1), tj, a + col + k + 1, a + cj + k + 1);
        }
    }
    ipvt[n - 1] = n - 1;
    if (a[lda * (n - 1) + (n - 1)] == 0) info = n;
    return info;
}

fn gesl(a: [*]const f64, lda: u32, n: u32, ipvt: [*]const u32, b: [*]f64) void {
    if (n == 0) return;
    for (0..n - 1) |k| {
        const l = ipvt[k];
        const t = b[l];
        if (l != k) {
            b[l] = b[k];
            b[k] = t;
        }
        axpy(n - (k + 1), t, a + lda * k + k + 1, b + k + 1);
    }
    for (0..n) |kb| {
        const k = n - 1 - kb;
        b[k] = b[k] / a[lda * k + k];
        axpy(k, -b[k], a + lda * k, b);
    }
}

const std = @import("std");
