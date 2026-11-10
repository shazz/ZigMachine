// --------------------------------------------------------------------------
// ASTROLABE in the machine (HW 1.18.0, SPIKE: docs/ARM_FPU_COPROC.md): env.hwAstro.
//
// hwAstro(desc, count) runs `count` descriptors (machine/sdk/astro.zig) laid end to end at
// cart address `desc`, in order, synchronously: each one's W_STATUS and W_R are written
// back, W_CYCLES is left 0 (only the board's firmware counts), and the answer is the first
// non-OK status, else ST_OK. A descriptor that is refused writes nothing but its status;
// the next ones still run (a batch is not a transaction).
//
// This is the reference every host shares: the browser's machine-video.wasm, the native
// host's wasm2c of it, and the board's fallback when the ARM does not answer.
// --------------------------------------------------------------------------
const abi = @import("sdk/astro.zig");
const ops = @import("astro_ops.zig");

/// One descriptor at `at`: its words read once, run, its status and result written back.
pub fn runOne(m: ops.Mem, at: u32) u32 {
    var d: ops.Desc = undefined;
    for (&d.w, 0..) |*w, i| w.* = m.ld32(at + 4 * @as(u32, @intCast(i)));
    const res = ops.run(m, d);
    m.st32(at + 4 * abi.W_STATUS, res.status);
    m.st32(at + 4 * abi.W_CYCLES, 0);
    if (res.status == abi.ST_OK) m.st64(at + 4 * abi.W_R, res.r);
    return res.status;
}

/// The descriptor list itself: inside the memory, 8-aligned, at most MAX_COUNT long.
pub fn listOk(m: ops.Mem, desc: u32, count: u32) bool {
    if (count > abi.MAX_COUNT or desc % 8 != 0 or desc < 8) return false;
    return @as(u64, desc) + @as(u64, count) * abi.DESC_BYTES <= m.size;
}

pub fn run(m: ops.Mem, desc: u32, count: u32) u32 {
    if (!listOk(m, desc, count)) return abi.ST_BAD_DESC;
    var first: u32 = abi.ST_OK;
    for (0..count) |i| {
        const st = runOne(m, desc + @as(u32, @intCast(i)) * abi.DESC_BYTES);
        if (first == abi.ST_OK) first = st;
    }
    return first;
}
