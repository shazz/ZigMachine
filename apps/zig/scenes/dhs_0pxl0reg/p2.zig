// --------------------------------------------------------------------------
// P2 "presents" / "0 pixels 0 regrets" + copper bars. Kernel $1118C, 200 lines,
// one generated routine per line (jsr list $1125A). Registers d0..a4 = the 13
// palette words; d0 is then the per-line colour LC[k] streamed with (a5)+.
//   'A' / 'C': 32 x 8 px cells from rel 428+512k, then d0 = LC[k] at +360
//   'B'      : the same, plus d0 (still LC[k-1]) written at +256
// Cell register 0 = the current d0. The bars: 16 copies of a 16-line bar,
// their tops read from a ring of sine positions ($10F76).
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const Kind = enum(u8) { a, b, c };
const Routine = struct { kind: Kind, row: u8 };
const ROW_B = 200; // p2_rows: A rows 0..199, then B 0..66, then C 0..26
const ROW_C = 267;

var pal: [16]u16 = undefined;
var bar: [16]u16 = undefined;
var phase: u32 = 0;
var amp: u32 = 0;
var c11022: u16 = 0;
var ring: [2048]i32 = undefined; // longs by byte offset / 4
var rp: u32 = 0;
var t10eb8: u16 = 0;
var t10ed8: u16 = 0;
var c10efc: u32 = 0;
var t10f54: u16 = 0;
var n_open: u32 = 0;
var a5: i32 = 0;
var a4: i32 = 0;
var rev_b: u32 = 0;
var lc: [200]u16 = undefined;
var jsr: [200]Routine = undefined;

pub fn reset() void {
    pal = rip.P2_PAL;
    bar = rip.P2_BAR;
    phase = rip.P2_PHASE;
    amp = rip.P2_AMP;
    c11022 = rip.P2_C11022;
    @memset(&ring, 0);
    rp = 0;
    t10eb8 = 0;
    t10ed8 = 0;
    c10efc = 1;
    t10f54 = 0;
    n_open = rip.P2_N_OPEN;
    a5 = rip.P2_A5;
    a4 = rip.P2_A4;
    rev_b = rip.P2_REVB0;
    @memset(&lc, 0);
    @memset(&jsr, .{ .kind = .a, .row = 0 });
}

pub fn init() void {
    core.colour = 0;
    @memset(&jsr, .{ .kind = .a, .row = 0 });
    for (0..27) |k| jsr[86 + k] = .{ .kind = .c, .row = @intCast(k) };
    rp = 0x800;
    @memset(&lc, 0);
}

pub fn vbl() void {
    core.colour = 0;
}

/// $10F76 (post-music): push this frame's sine position into the ring, then
/// stamp 16 bars at the positions 5 longs apart behind it.
pub fn bars() void {
    @memset(&lc, 0);
    phase = (phase + 10) & 0x7FF;
    const v = core.sinMul(phase >> 1, core.sw(amp)) * 2;
    ring[rp >> 2] = v;
    const pos = rp;
    rp += 4;
    if (rp >= 0x1FFC) rp = 0x800;
    var a = pos - 0x140;
    for (0..16) |_| {
        const top: usize = @intCast(92 + @divFloor(ring[a >> 2], 2));
        a += 0x14;
        @memcpy(lc[top..][0..16], &bar);
    }
    c11022 -%= 1;
    if (c11022 & 0x8000 != 0 and amp != 0xB7) amp += 1;
}

fn fadeBar(tgt: *const [16]u16) void {
    core.step1(&bar, tgt);
}

pub fn m10e7a() void {
    t10eb8 ^= 0xFFFF;
    if (t10eb8 == 0) fadeBar(&rip.P2_TGT_10E98);
}

pub fn m10eba() void {
    t10ed8 ^= 0xFFFF;
    if (t10ed8 == 0) fadeBar(&rip.P2_TGT_11066);
}

pub fn m10eda() void {
    c10efc -= 1;
    if (c10efc == 0) {
        c10efc = 6;
        fadeBar(&rip.P2_TGT_11046);
    }
}

pub fn m10efe() void {
    core.step1(&pal, &rip.P2_TGT_10F14);
}

pub fn m10f34() void {
    t10f54 ^= 0xFFFF;
    if (t10f54 == 0) core.step1(&pal, &rip.P2_TGT_22C0A);
}

/// $1108C: open picture A from the middle, one more line each way a frame.
pub fn m1108c() void {
    const n = n_open;
    const r0 = @divFloor(a5 - 0x2F2E, 0x7A) + 99;
    for (0..n + 1) |k| jsr[k] = .{ .kind = .a, .row = @intCast(r0 + @as(i32, @intCast(k))) };
    const e0: usize = @intCast(@divFloor(a4, 6));
    for (0..n + 1) |k| jsr[e0 + k] = .{ .kind = .a, .row = @intCast(100 + k) };
    if (n != 0x63) {
        n_open += 1;
        a5 -= 0x7A;
        a4 -= 6;
    }
}

/// $1111C: the next row of picture B, in the order of the table at $22C3E.
fn revealB() void {
    const r = rip.P2_REVB[rev_b];
    jsr[73 + @as(usize, r)] = .{ .kind = .b, .row = r };
    if (rev_b != 0x42) rev_b += 1;
}

pub fn m110e8() void {
    revealB();
    fadeBar(&rip.P2_TGT_11046);
}

pub fn m11102() void {
    revealB();
    fadeBar(&rip.P2_TGT_11066);
}

pub fn kernel(l0: u32) void {
    var regs = pal;
    var d0 = regs[0];
    for (0..200) |k| {
        const rt = jsr[k];
        const first: usize = switch (rt.kind) {
            .a => 0,
            .b => ROW_B,
            .c => ROW_C,
        };
        const row = assets.p2_rows[(first + rt.row) * 32 ..][0..32];
        const base: u32 = 428 + 512 * @as(u32, @intCast(k));
        regs[0] = d0;
        for (row, 0..) |n, j| out.emit(l0, base + 8 * @as(u32, @intCast(j)), regs[n]);
        if (rt.kind == .b) out.emit(l0, base + 256, d0);
        d0 = lc[k];
        out.emit(l0, base + 360, d0);
    }
    out.emit(l0, 408 + 200 * 512 + 4, 0);
    core.colour = 0;
}
