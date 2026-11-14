// --------------------------------------------------------------------------
// ASTROLABE's array kernels (SPIKE): vectors, GEMV and LINPACK's dgefa/dgesl.
//
// dgefa and dgesl are netlib linpack.c's, rolled BLAS, in its exact order of operations, so
// a cart's own soft-f64 LINPACK and ASTROLABE's agree bit for bit. Column-major: element
// (row i, column j) of A is A[lda * j + i]. Read-only arrays have the TYPE_F32_IN element
// type, arrays written (or updated in place) TYPE_F32_OUT; pivots are i32.
// --------------------------------------------------------------------------
const abi = @import("sdk/astro.zig");
const ops = @import("astro_ops.zig");
const Mem = ops.Mem;
const Desc = ops.Desc;
const Result = ops.Result;

pub const Span = struct { addr: u32 = 0, bytes: u32 = 0, el: u32 = 8 };
pub const Spans = struct { in: [3]Span = .{ .{}, .{}, .{} }, out: [2]Span = .{ .{}, .{} } };

fn esz(f32_: bool) u32 {
    return if (f32_) 4 else 8;
}

/// Elements of a column-major array: `cols` columns of `rows`, `lda` apart.
fn matEls(lda: u32, rows: u32, cols: u32) u64 {
    return if (cols == 0 or rows == 0) 0 else @as(u64, lda) * (cols - 1) + rows;
}

fn span(addr: u32, els: u64, size: u32) Span {
    return .{ .addr = addr, .bytes = @intCast(@min(els * size, 0xFFFF_FFFF)), .el = size };
}

/// Every array the descriptor names, with what it reads and writes. Assumes the sizes passed check().
pub fn spans(d: Desc) Spans {
    const w = d.w;
    const n = w[abi.W_N];
    const ei, const eo = .{ esz(d.inF32()), esz(d.outF32()) };
    const a, const b, const c = .{ w[abi.W_A], w[abi.W_B], w[abi.W_C] };
    return switch (d.op()) {
        abi.OP_VADD, abi.OP_VMUL => .{ .in = .{ span(a, n, ei), span(b, n, ei), .{} }, .out = .{ span(c, n, eo), .{} } },
        abi.OP_AXPY => .{ .in = .{ span(a, n, ei), span(b, n, eo), .{} }, .out = .{ span(b, n, eo), .{} } },
        abi.OP_DOT => .{ .in = .{ span(a, n, ei), span(b, n, ei), .{} } },
        abi.OP_SCAL, abi.OP_MAP => .{ .in = .{ span(a, n, ei), .{}, .{} }, .out = .{ span(c, n, eo), .{} } },
        abi.OP_GEMV => .{
            .in = .{ span(a, matEls(w[abi.W_LDA], w[abi.W_M], n), ei), span(b, n, ei), .{} },
            .out = .{ span(c, w[abi.W_M], eo), .{} },
        },
        abi.OP_GEFA => .{
            .in = .{ span(a, matEls(w[abi.W_LDA], n, n), eo), .{}, .{} },
            .out = .{ span(a, matEls(w[abi.W_LDA], n, n), eo), span(b, n, 4) },
        },
        abi.OP_GESL => .{
            .in = .{ span(a, matEls(w[abi.W_LDA], n, n), ei), span(b, n, 4), span(c, n, eo) },
            .out = .{ span(c, n, eo), .{} },
        },
        else => .{},
    };
}

fn sizesOk(d: Desc) bool {
    const n, const m, const lda = .{ d.w[abi.W_N], d.w[abi.W_M], d.w[abi.W_LDA] };
    return switch (d.op()) {
        abi.OP_VADD, abi.OP_VMUL, abi.OP_AXPY, abi.OP_DOT, abi.OP_SCAL, abi.OP_MAP => n <= abi.MAX_N,
        abi.OP_GEMV => n <= abi.MAX_ORDER and m <= abi.MAX_ORDER and lda >= m and lda <= abi.MAX_N,
        abi.OP_GEFA, abi.OP_GESL => n <= abi.MAX_ORDER and lda >= n and lda <= abi.MAX_N,
        else => true,
    };
}

fn spanOk(m: Mem, s: Span) u32 {
    if (s.bytes == 0) return abi.ST_OK;
    if (s.addr % s.el != 0) return abi.ST_ALIGN;
    if (s.addr < 8 or @as(u64, s.addr) + s.bytes > m.size) return abi.ST_RANGE;
    return abi.ST_OK;
}

/// ST_OK, or why the descriptor is refused (before anything is written).
pub fn check(m: Mem, d: Desc) u32 {
    const op = d.op();
    const known = (op >= abi.OP_VADD and op <= abi.OP_MAP) or (op >= abi.OP_GEMV and op <= abi.OP_GESL);
    if (!known or (op == abi.OP_MAP and d.w[abi.W_M] >= abi.FN_COUNT)) return abi.ST_BAD_OP;
    if (!sizesOk(d)) return abi.ST_RANGE;
    const sp = spans(d);
    for (sp.in ++ sp.out) |s| {
        const st = spanOk(m, s);
        if (st != abi.ST_OK) return st;
    }
    return abi.ST_OK;
}

pub fn run(m: Mem, d: Desc) Result {
    const w = d.w;
    const n = w[abi.W_N];
    const a, const b, const c = .{ w[abi.W_A], w[abi.W_B], w[abi.W_C] };
    const fi, const fo = .{ d.inF32(), d.outF32() };
    const s0 = d.s(abi.W_S0);
    var r: f64 = 0;
    switch (d.op()) {
        abi.OP_VADD => for (0..n) |k| m.setEl(c, @intCast(k), fo, m.el(a, @intCast(k), fi) + m.el(b, @intCast(k), fi)),
        abi.OP_VMUL => for (0..n) |k| m.setEl(c, @intCast(k), fo, m.el(a, @intCast(k), fi) * m.el(b, @intCast(k), fi)),
        abi.OP_AXPY => axpy(m, n, s0, a, fi, 0, b, fo, 0),
        abi.OP_DOT => for (0..n) |k| {
            r += m.el(a, @intCast(k), fi) * m.el(b, @intCast(k), fi);
        },
        abi.OP_SCAL => for (0..n) |k| m.setEl(c, @intCast(k), fo, s0 * m.el(a, @intCast(k), fi)),
        abi.OP_MAP => for (0..n) |k| m.setEl(c, @intCast(k), fo, ops.mapFn(w[abi.W_M], m.el(a, @intCast(k), fi))),
        abi.OP_GEMV => gemv(m, d),
        abi.OP_GEFA => r = @floatFromInt(@import("astro_linpack.zig").gefa(m, a, w[abi.W_LDA], n, b, fo)),
        abi.OP_GESL => return @import("astro_linpack.zig").gesl(m, a, w[abi.W_LDA], n, b, c, fi, fo),
        else => unreachable, // check() refused it
    }
    return .{ .r = r };
}

/// dy[oy + i] += da * dx[ox + i], netlib's rolled daxpy (nothing when da is 0).
pub fn axpy(m: Mem, n: u32, da: f64, x: u32, fx: bool, ox: u32, y: u32, fy: bool, oy: u32) void {
    if (da == 0) return;
    for (0..n) |k| {
        const i: u32 = @intCast(k);
        m.setEl(y, oy + i, fy, m.el(y, oy + i, fy) + da * m.el(x, ox + i, fx));
    }
}

fn gemv(m: Mem, d: Desc) void {
    const w = d.w;
    for (0..w[abi.W_M]) |i| {
        var acc: f64 = 0;
        for (0..w[abi.W_N]) |j| {
            const at: u32 = @intCast(w[abi.W_LDA] * j + i);
            acc += m.el(w[abi.W_A], at, d.inF32()) * m.el(w[abi.W_B], @intCast(j), d.inF32());
        }
        m.setEl(w[abi.W_C], @intCast(i), d.outF32(), acc);
    }
}
