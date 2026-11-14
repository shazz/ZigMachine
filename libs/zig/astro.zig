// --------------------------------------------------------------------------
// zg.astro — ASTROLABE, the f64 coprocessor (HW 1.18.0, SPIKE: docs/ARM_FPU_COPROC.md).
//
// The rule: ZIGGY's own f32 (and fixed point) for fast, good-enough maths every frame; ASTRO for
// f64 and for BATCHES. One call costs a round trip on the board (a mailbox to the ARM and back),
// so a single add is slower than ZIGGY's soft f64; sin/exp/pow/div/sqrt and anything over an
// array win. In the browser and the native host the machine computes it (no round trip).
//
//     var d = [_]zg.astro.Desc{ zg.astro.daxpy(n, 2.0, &x, &y), zg.astro.dot(n, &x, &y) };
//     _ = zg.astro.run(&d);          // in order; d[1].r is the dot product
//     const s = zg.astro.sin(0.5);   // one op, one call
//
// Arrays live in the cart's memory and are read and written in place; a call is synchronous.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const abi = hw.astro;

pub const Desc = extern struct {
    op: u32 = abi.OP_NOP,
    n: u32 = 0,
    m: u32 = 0,
    lda: u32 = 0,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
    rsvd: u32 = 0,
    status: u32 = 0, // written: ST_* | SERVED_ARM
    cycles: u32 = 0, // written: ZIGGY cycles of the call (the board only)
    s0: f64 = 0,
    s1: f64 = 0,
    s2: f64 = 0,
    r: f64 = 0, // written: a scalar op's or DOT's result, GEFA's info
    pad: [2]u32 = .{ 0, 0 },

    comptime {
        if (@sizeOf(Desc) != abi.DESC_BYTES or @offsetOf(Desc, "s0") != 4 * abi.W_S0 or @offsetOf(Desc, "r") != 4 * abi.W_R)
            @compileError("zg.astro.Desc is not machine/sdk/astro.zig's descriptor");
    }
};

fn addr(p: anytype) u32 {
    return @intCast(@intFromPtr(p));
}

/// Runs the descriptors in order: ST_OK, or the first one's failure (each keeps its own status).
pub fn run(d: []Desc) u32 {
    return hw.hwAstro(addr(d.ptr), @intCast(d.len));
}

pub fn scalarOp(op: u32, a: f64, b: f64) f64 {
    var d = [_]Desc{.{ .op = op, .s0 = a, .s1 = b }};
    _ = run(&d);
    return d[0].r;
}
pub fn div(a: f64, b: f64) f64 {
    return scalarOp(abi.OP_DIV, a, b);
}
pub fn sqrt(a: f64) f64 {
    return scalarOp(abi.OP_SQRT, a, 0);
}
pub fn sin(a: f64) f64 {
    return scalarOp(abi.OP_SIN, a, 0);
}
pub fn pow(a: f64, b: f64) f64 {
    return scalarOp(abi.OP_POW, a, b);
}

// --- descriptors for run(): f64 arrays (OR TYPE_F32_IN / _OUT into .op for f32 ones) ---
pub fn daxpy(n: u32, alpha: f64, x: [*]const f64, y: [*]f64) Desc {
    return .{ .op = abi.OP_AXPY, .n = n, .a = addr(x), .b = addr(y), .s0 = alpha };
}
pub fn dot(n: u32, x: [*]const f64, y: [*]const f64) Desc {
    return .{ .op = abi.OP_DOT, .n = n, .a = addr(x), .b = addr(y) };
}
/// y[m] = A[m x n, column-major, lda] * x[n]
pub fn dgemv(m: u32, n: u32, a: [*]const f64, lda: u32, x: [*]const f64, y: [*]f64) Desc {
    return .{ .op = abi.OP_GEMV, .n = n, .m = m, .lda = lda, .a = addr(a), .b = addr(x), .c = addr(y) };
}
/// out[i] = f(in[i]), f one of abi.FN_*
pub fn map(f: u32, n: u32, in: [*]const f64, out: [*]f64) Desc {
    return .{ .op = abi.OP_MAP, .n = n, .m = f, .a = addr(in), .c = addr(out) };
}
/// LINPACK: factor A[n x n, lda] in place (pivots into ipvt), then solve A x = b (b becomes x).
pub fn dgefa(n: u32, a: [*]f64, lda: u32, ipvt: [*]i32) Desc {
    return .{ .op = abi.OP_GEFA, .n = n, .lda = lda, .a = addr(a), .b = addr(ipvt) };
}
pub fn dgesl(n: u32, a: [*]const f64, lda: u32, ipvt: [*]const i32, b: [*]f64) Desc {
    return .{ .op = abi.OP_GESL, .n = n, .lda = lda, .a = addr(a), .b = addr(ipvt), .c = addr(b) };
}

/// Served by the ARM (the board's ASTROLABE), not the machine's own code?
pub fn servedByArm(d: Desc) bool {
    return d.status & abi.SERVED_ARM != 0;
}
