// --------------------------------------------------------------------------
// P14 wobbling texture scroller, 12 px true-colour cells. Kernel $1A83A, top
// border open: 273 lines, line L runs one of 26 x 3 chained routines: 36 cells
// from BUF[L][S/2 + k] at rel 512L + (324, 320, 316)[variant]. The variant is
// where the routine's nop sits (0 / -4 / -8 px), k a word shift: together a
// 4 px wobble step, from q = PT[512 + v + L] (PT = 38 + sin(10i) * 76).
// Each line also writes the texture word at a6 + 2L into BUF[L] at S/2 + 63
// and + 127, so a new column scrolls in from the right of a circular row.
// a6 may point below the texture, into the routines' own code, as it did.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const LINES = 273;

var col: u32 = 0; // $3CF9E, texture column (bytes)
var vofs: i32 = 0; // $3CFA2
var S: u32 = 0; // $3CFA6
var ph2: u32 = 0;
var ph: u32 = 0;
var c1a820: u32 = 0;
var c1a838: u32 = 0;
var buf: [LINES * 128 + 256]u16 = undefined; // $92EEE, 128 words a line
var rt: [LINES]u8 = undefined;

pub fn reset() void {
    col = rip.P14_COL;
    vofs = @bitCast(rip.P14_VOFS);
    S = rip.P14_S;
    ph2 = rip.P14_PH2;
    ph = rip.P14_PH;
    c1a820 = rip.P14_C1A820;
    c1a838 = rip.P14_C1A838;
    @memset(&buf, 0);
    @memset(&rt, 0);
}

pub fn init() void {
    core.colour = 0;
}

pub fn vbl() void {
    core.colour = 0;
}

/// $1A7FC
pub fn frame() void {
    ph = (ph + 8) & 0x7FF; // $1AC3C
    const v = core.sinMul(ph >> 1, 0x190);
    for (&rt, 0..) |*q, L| {
        const i: u32 = @intCast(512 + v + @as(i32, @intCast(L)));
        q.* = @intCast(38 + core.sinMul((10 * i) % 1024, 0x4C));
    }
    ph2 = (ph2 + 0xA) & 0x7FF; // $1AA84
    vofs = core.sinMul(ph2 >> 1, 0xED) * 2;
    S = if (S >= 0xFE) 0 else S + 2; // $1AAAE
}

/// Entry 84: every 10 frames the texture one column back.
pub fn m1a80a() void {
    frame();
    c1a820 -= 1;
    if (c1a820 == 0) {
        c1a820 = 0xA;
        if (col == 0) col = 0x400;
        col -= 0x400;
    }
}

/// Entry 86: every 5 frames one column on, wrapping $7C00 -> $7800.
pub fn m1a822() void {
    frame();
    c1a838 -= 1;
    if (c1a838 == 0) {
        c1a838 = 5;
        if (col >= 0x7C00) col = 0x7800;
        col += 0x400;
    }
}

pub fn kernel(l0: u32) void {
    const c0 = S >> 1;
    const a6: u32 = @intCast(@as(i32, @intCast(rip.P14_TEX0 + 0xEE + col)) + vofs);
    for (rt, 0..) |q, L| {
        const k = q / 3;
        const r0 = L * 128 + c0;
        const v = core.le16(assets.p14_mem, (a6 >> 1) + L);
        buf[r0 + 63] = v;
        buf[r0 + 127] = v;
        const lu: u32 = @intCast(L);
        const t = 512 * lu + @as(u32, switch (q % 3) {
            0 => 324,
            1 => 320,
            else => 316,
        });
        for (0..36) |j| out.emit(l0, t + 12 * @as(u32, @intCast(j)), buf[r0 + k + j]);
    }
    out.emit(l0, 512 * LINES + 264, 0);
    core.colour = 0;
}
