// --------------------------------------------------------------------------
// ASTROLABE's kernels (SPIKE, docs/ARM_FPU_COPROC.md): what one descriptor does.
//
// ONE source, compiled for every host: into machine-video.wasm (the browser; wasm2c'd into
// the native host and the board's system, where it is ZIGGY's soft-f64 fallback) and into
// glass for the ARM's VFPv3 (fpga/glass/src/astro.zig). @sin & co. come from Zig's
// compiler_rt on all of them (no host libm), so a result is the same bits everywhere the
// arithmetic is IEEE. Addresses are the cart's; `Mem` is its memory seen from byte 0.
// --------------------------------------------------------------------------
pub const abi = @import("sdk/astro.zig"); // for glass, which imports this file as a module
const blas = @import("astro_blas.zig");

pub const Mem = struct {
    ptr: [*]allowzero u8, // cart address 0
    size: u32,

    pub fn ld64(m: Mem, a: u32) f64 {
        const p: *allowzero align(1) const u64 = @ptrCast(m.ptr + a);
        return @bitCast(p.*);
    }
    pub fn st64(m: Mem, a: u32, v: f64) void {
        const p: *allowzero align(1) u64 = @ptrCast(m.ptr + a);
        p.* = @bitCast(v);
    }
    pub fn ld32(m: Mem, a: u32) u32 {
        const p: *allowzero align(1) const u32 = @ptrCast(m.ptr + a);
        return p.*;
    }
    pub fn st32(m: Mem, a: u32, v: u32) void {
        const p: *allowzero align(1) u32 = @ptrCast(m.ptr + a);
        p.* = v;
    }
    /// Element `i` of the array at `a`: f32 (widened) or f64.
    pub fn el(m: Mem, a: u32, i: u32, f32_: bool) f64 {
        return if (f32_) @as(f64, @as(f32, @bitCast(m.ld32(a + 4 * i)))) else m.ld64(a + 8 * i);
    }
    pub fn setEl(m: Mem, a: u32, i: u32, f32_: bool, v: f64) void {
        if (f32_) m.st32(a + 4 * i, @bitCast(@as(f32, @floatCast(v)))) else m.st64(a + 8 * i, v);
    }
};

/// A descriptor's words, read once (the cart may rewrite its memory meanwhile).
pub const Desc = struct {
    w: [abi.DESC_WORDS]u32,

    pub fn op(d: Desc) u32 {
        return d.w[abi.W_OP] & abi.OP_MASK;
    }
    pub fn s(d: Desc, word: u32) f64 {
        return @bitCast(@as(u64, d.w[word + 1]) << 32 | d.w[word]);
    }
    pub fn inF32(d: Desc) bool {
        return d.w[abi.W_OP] & abi.TYPE_F32_IN != 0;
    }
    pub fn outF32(d: Desc) bool {
        return d.w[abi.W_OP] & abi.TYPE_F32_OUT != 0;
    }
};

/// What a descriptor leaves: its status code and the scalar result.
pub const Result = struct { status: u32 = abi.ST_OK, r: f64 = 0 };

pub fn scalar(op: u32, a: f64, b: f64, c: f64) ?f64 {
    return switch (op) {
        abi.OP_NOP => 0,
        abi.OP_ADD => a + b,
        abi.OP_SUB => a - b,
        abi.OP_MUL => a * b,
        abi.OP_DIV => a / b,
        abi.OP_SQRT => @sqrt(a),
        abi.OP_FMA => @mulAdd(f64, a, b, c),
        abi.OP_SIN => @sin(a),
        abi.OP_COS => @cos(a),
        abi.OP_TAN => @tan(a),
        abi.OP_ATAN2 => std.math.atan2(a, b),
        abi.OP_EXP => @exp(a),
        abi.OP_LOG => @log(a),
        abi.OP_POW => std.math.pow(f64, a, b),
        else => null,
    };
}

pub fn mapFn(f: u32, x: f64) f64 {
    return switch (f) {
        abi.FN_SIN => @sin(x),
        abi.FN_COS => @cos(x),
        abi.FN_TAN => @tan(x),
        abi.FN_EXP => @exp(x),
        abi.FN_LOG => @log(x),
        abi.FN_SQRT => @sqrt(x),
        else => std.math.atan(x),
    };
}

/// Runs one descriptor on `m`. Every array is bounds- and alignment-checked first, so a
/// refused descriptor writes nothing.
pub fn run(m: Mem, d: Desc) Result {
    const op = d.op();
    if (scalar(op, d.s(abi.W_S0), d.s(abi.W_S1), d.s(abi.W_S2))) |r| return .{ .r = r };
    const st = blas.check(m, d);
    if (st != abi.ST_OK) return .{ .status = st };
    return blas.run(m, d);
}

/// The byte spans a descriptor reads and writes, for a host that stages them (glass copies
/// the inputs out of DDR and the outputs back). Valid only once blas.check passed.
pub const Span = blas.Span;
pub const spans = blas.spans;
pub const check = blas.check;

const std = @import("std");
