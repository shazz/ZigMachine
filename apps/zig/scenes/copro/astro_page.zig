// --------------------------------------------------------------------------
// COPRO: what the ASTROLABE pages share. A batch of descriptors runs either
// on ASTROLABE (env.hwAstro: the ARM's VFPv3 on an ASTRO bitstream; the
// machine's own code elsewhere, and ZIGGY's soft f64 on a board without the
// ARM) or, for the A side, in the cart (soft64.zig, the same bits). And the
// integer side: an f64 read by its bits, never by an FPU op, so ZIGGY's
// per-frame code (the scan, the drawing) stays integer.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const C = @import("common.zig");
const soft64 = @import("soft64.zig");
const abi = @import("hardware").astro;
const Desc = zg.astro.Desc;

/// Runs `d` on the side the A/B asks for; counts what ZIGGY spent (µs) and what the call reported.
pub fn run(ctx: *C.Ctx, d: []Desc) void {
    const t0 = C.micros();
    if (ctx.asked == .ziggy) {
        soft64.run(d);
    } else {
        _ = zg.astro.run(d);
        ctx.astro_arm = zg.astro.servedByArm(d[0]);
        var cyc: u32 = 0;
        for (d) |x| cyc +%= x.cycles;
        ctx.job_cycles = cyc; // the board's ZIGGY cycles over the call (0 in the page and the native host)
    }
    ctx.post_us +%= C.micros() -% t0;
}

/// The high word of an f64 (its sign, exponent and top mantissa bits).
pub fn hi(x: *const f64) u32 {
    return @truncate(@as(*const u64, @ptrCast(x)).* >> 32);
}

/// trunc(x) for |x| < 2^30, from the bits: integer ops only.
pub fn toInt(x: *const f64) i32 {
    const b = @as(*const u64, @ptrCast(x)).*;
    const e: i32 = @intCast((b >> 52) & 0x7FF);
    if (e < 1023) return 0;
    const sh = e - 1023;
    if (sh > 29) return if (b >> 63 != 0) -(1 << 29) else 1 << 29;
    const m = (b & ((1 << 52) - 1)) | (1 << 52);
    const v: i32 = @intCast(m >> @intCast(52 - sh));
    return if (b >> 63 != 0) -v else v;
}

/// An f64 array in the cart's RAM arena (8-aligned: hwAstro refuses less).
pub fn f64s(n: usize) []f64 {
    return zg.mem.mustAlloc(f64, n);
}

/// C = s * A (s = 1: a copy).
pub fn scal(n: u32, s: f64, a: [*]const f64, c: [*]f64) Desc {
    return .{ .op = abi.OP_SCAL, .n = n, .a = addr(a), .c = addr(c), .s0 = s };
}
/// C = A + B, or C = A * B.
pub fn vadd(n: u32, a: [*]const f64, b: [*]const f64, c: [*]f64) Desc {
    return .{ .op = abi.OP_VADD, .n = n, .a = addr(a), .b = addr(b), .c = addr(c) };
}
pub fn vmul(n: u32, a: [*]const f64, b: [*]const f64, c: [*]f64) Desc {
    return .{ .op = abi.OP_VMUL, .n = n, .a = addr(a), .b = addr(b), .c = addr(c) };
}

pub fn addr(p: anytype) u32 {
    return @intCast(@intFromPtr(p));
}
