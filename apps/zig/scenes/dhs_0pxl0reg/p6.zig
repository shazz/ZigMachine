// --------------------------------------------------------------------------
// P6 plasma, 8-line rows, a palette per row. Kernel $18272: 25 blocks x 8
// lines; lines 0..6 of block b are 52 x 8 px cells from rel 332+4096b+512l,
// then d1 at +416; line 7 is the gap that reloads 13 colours from (a6)+.
// Registers d1..a5 = palette set s0+b of the 60 at $9BEDC.
// Cell = OPT[(m[A+o] + m[B+o]) & 255], two windows into one 128x128 map moved
// by four sines ($1848A). Double-buffered: the kernel shows the buffer that was
// front at VBL time, so frame F shows F-1's render.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

var ofs: u32 = 0; // $26C4A, 26 bytes a set
var ph: [4]u32 = undefined; // $186CE: p7, p6, p5, p4
var c18270: u32 = 0;
var buf: [2][25][52]u8 = undefined;
var rendered: [2]bool = undefined; // a never-rendered buffer shows d2 in every cell
var front: usize = 0;
var show: usize = 0;

// A cell sums two map bytes (all even, at most 30), so OPT is only ever read
// at even indices up to 60; every one of those must name d0..a5 (regs[14]).
// OPT itself holds 14 and 15 elsewhere, which would read past the registers.
comptime {
    @setEvalBranchQuota(100_000);
    var seen = [_]bool{false} ** 256;
    for (assets.p6_map) |v| seen[v] = true;
    for (0..256) |x| if (seen[x]) for (0..256) |y| {
        if (seen[y] and rip.P6_OPT[(x + y) & 0xFF] > 13) @compileError("dhs P6: a reachable OPT entry is past a5");
    };
}

pub fn reset() void {
    ofs = rip.P6_OFS;
    for (&ph, rip.P6_PH) |*p, v| p.* = v;
    c18270 = rip.P6_C18270;
    rendered = .{ false, false };
    front = 0;
    show = 0;
}

pub fn init() void {
    core.colour = 0;
    rendered = .{ false, false };
    front = 0;
}

/// $18210: the kernel jumps to the buffer that is front now.
pub fn vbl() void {
    core.colour = 0;
    show = front;
}

pub fn postUp() void {
    if (ofs < 0x374) ofs += 0x1A;
}

pub fn postDown() void {
    c18270 -= 1;
    if (c18270 == 0) {
        c18270 = 3;
        if (core.sw(ofs) > 0) ofs -= 0x1A;
    }
}

/// $1848A, then the swap at $18228.
pub fn render() void {
    ph[0] = (ph[0] + 8) & 0x7FF;
    const d7 = core.sinMul(ph[0] >> 1, 0x4B);
    ph[1] = (ph[1] + 6) & 0x7FF;
    const d6 = core.sinMul(ph[1] >> 1, 0x32) << 7;
    ph[2] = (ph[2] + 12) & 0x7FF;
    const d5 = core.sinMul(ph[2] >> 1, 0x4B);
    ph[3] = (ph[3] + 4) & 0x7FF;
    const d4 = core.sinMul(ph[3] >> 1, 0x32) << 7;
    const a: usize = @intCast(0x19A6 + d6 + d7);
    const b: usize = @intCast(0x19A6 + d5 + d4);
    const m = assets.p6_map;
    const back = 1 - front;
    for (&buf[back], 0..) |*row, r| {
        for (row, 0..) |*cell, c| {
            const o = r * 128 + c;
            cell.* = rip.P6_OPT[(@as(u32, m[a + o]) + m[b + o]) & 0xFF];
        }
    }
    rendered[back] = true;
    front = back;
}

pub fn kernel(l0: u32) void {
    const s0 = ofs / 26;
    var d1: u16 = 0;
    const blank = [_]u8{2} ** 52;
    for (0..25) |bi| {
        const b: u32 = @intCast(bi);
        var regs: [14]u16 = undefined;
        regs[0] = 0;
        for (0..13) |i| regs[1 + i] = core.le16(assets.p6_sets, (s0 + b) * 13 + i);
        d1 = regs[1];
        const cells: *const [52]u8 = if (rendered[show]) &buf[show][bi] else &blank;
        for (0..7) |l| {
            const base = 332 + 4096 * b + 512 * @as(u32, @intCast(l));
            for (cells, 0..) |n, j| out.emit(l0, base + 8 * @as(u32, @intCast(j)), regs[n]);
            out.emit(l0, base + 416, d1);
        }
    }
    core.colour = d1;
}
