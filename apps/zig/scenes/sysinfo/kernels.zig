// --------------------------------------------------------------------------
// SysInfo — the speed tests' kernels: one rep each, the same work every time.
// bench.zig times them; stref.zig holds what a stock ST takes for each.
//
// The CPU loops store through VOLATILE pointers so the compiler cannot turn
// them into a memset/memcpy (which would time the host's library, not the
// cart CPU's own word loop). The blitter rows go through the machine's
// blitter registers (zg.Blitter), which is CHISEL on the board.
//
// The clear and copy work on planes 1 and 2: VRAM the machine allocated at
// boot, never enabled on this screen, so the tests touch real video memory (the
// only memory the blitter writes) and nothing on the glass changes.
//
// No float here except in f32MulAdd, which is the f32 test's whole point.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const INT_N: u32 = 65536; // iterations of the integer and f32 loops
pub const PLANE_BYTES: u32 = 64000; // one 320 x 200 plane
pub const SCATTER_N: u32 = 16384; // byte stores spread over the 64 KB buffer
pub const SCATTER_BYTES: usize = 65536;
const SCATTER_STEP: u32 = 4099; // odd: walks the whole 64 KB before repeating

/// add.l / eor.l: a dependency chain no compiler can fold into a closed form.
pub fn intAdd(seed: u32) u32 {
    var a: u32 = seed;
    var b: u32 = seed ^ 0x9E37_79B9;
    var i: u32 = 0;
    while (i < INT_N) : (i += 1) {
        a +%= b;
        b ^= a;
    }
    return a ^ b;
}

/// The integer twin of f32MulAdd: the same chain, x = x * a + b.
pub fn intMul(seed: u32) u32 {
    var x: u32 = seed;
    const a: u32 = seed | 1;
    const b: u32 = seed >> 3;
    var i: u32 = 0;
    while (i < INT_N) : (i += 1) x = x *% a +% b;
    return x;
}

/// x = x * a + b in f32: a hardware FPU, or soft-float on a CPU without one.
pub fn f32MulAdd(seed: u32) u32 {
    const a: f32 = 0.5 + @as(f32, @floatFromInt(seed & 0xFF)) / 1024.0; // in [0.5, 0.75): converges
    // b >= 1: x settles near b / (1 - a), never into the denormals, where x86
    // hosts take a hundred cycles an operation and the test would time that
    const b: f32 = 1.0 + @as(f32, @floatFromInt(seed >> 24));
    var x: f32 = 1.0;
    var i: u32 = 0;
    while (i < INT_N) : (i += 1) x = x * a + b;
    return @bitCast(x);
}

/// A 32-bit store loop over a whole plane.
pub fn clearCpu(fb: *zg.LogicalFB, v: u32) void {
    const p: [*]volatile u32 = @ptrCast(@alignCast(fb.fb));
    var i: u32 = 0;
    while (i < PLANE_BYTES / 4) : (i += 1) p[i] = v;
}

pub fn clearBlit(blit: *zg.Blitter, fb: *zg.LogicalFB, v: u8) void {
    blit.fill(fb, 0, 0, zg.WIDTH, zg.HEIGHT, v);
}

/// A 32-bit load + store loop, plane to plane.
pub fn copyCpu(dst: *zg.LogicalFB, src: *zg.LogicalFB) void {
    const d: [*]volatile u32 = @ptrCast(@alignCast(dst.fb));
    const s: [*]volatile u32 = @ptrCast(@alignCast(src.fb));
    var i: u32 = 0;
    while (i < PLANE_BYTES / 4) : (i += 1) d[i] = s[i];
}

pub fn copyBlit(blit: *zg.Blitter, dst: *zg.LogicalFB, src: *zg.LogicalFB) void {
    blit.blitCopy(dst, 0, 0, src, 0, 0, zg.WIDTH, zg.HEIGHT);
}

/// Byte stores spread over 64 KB: no two neighbours, so nothing coalesces.
pub fn scatter(buf: *[SCATTER_BYTES]u8, seed: u32) void {
    const p: [*]volatile u8 = buf;
    var at: u32 = seed & (SCATTER_BYTES - 1);
    var i: u32 = 0;
    while (i < SCATTER_N) : (i += 1) {
        at = (at + SCATTER_STEP) & (SCATTER_BYTES - 1);
        p[at] = @truncate(i);
    }
}
