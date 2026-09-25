// --------------------------------------------------------------------------
// P16 plasma blocks. Kernel $19286: 25 rows x 8 lines of 52 x 8 px cells from
// rel 336+512L; cells 0,1,50,51 = d0. Registers d0..a5 = 14 words from palette
// group G at ofs (three groups of 48 sets, 13 words apart).
//   cell = OPC[((T + W1 (+ W2)) & $FFFF) / 2 mod 4096]
// OPC the 64x64 map as register numbers, W1/W2 word windows into the 96-wide
// table WT moved by four sines (47/69/47/70); entry 92 uses W1 only, with its
// own pair of phases. Rendered into the back buffer and shown from the next
// frame: the render overruns Timer A, so the swap lands after the kernel.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

var group: usize = 0; // $3AC88: $AC4E0, $AC9C0, $ACEA0
var ofs: u32 = 0; // $3AC8C
var T: u32 = 0; // $19C9E
var pa: [4]u32 = undefined; // $19AF6: p7, p6, p5, p4
var pb: [2]u32 = undefined; // $19C96: entry 92's own p7, p6
var c191c4: u16 = 0;
var c191ec: u16 = 0;
var c1922e: u32 = 0;
var c1925a: u32 = 0;
var c19284: u32 = 0;
var groups: [3][48][13]u16 = undefined;
var bufs: [2][25][52]u8 = undefined;
var back: usize = 0;
var front: usize = 1;

pub fn reset() void {
    group = rip.P16_PTR;
    ofs = rip.P16_OFS;
    T = rip.P16_T;
    for (&pa, rip.P16_PA) |*p, v| p.* = v;
    for (&pb, rip.P16_PB) |*p, v| p.* = v;
    c191c4 = rip.P16_C191C4;
    c191ec = rip.P16_C191EC;
    c1922e = rip.P16_C1922E;
    c1925a = rip.P16_C1925A;
    c19284 = rip.P16_C19284;
}

pub fn init() void {
    core.colour = 0;
    for (&groups, [_][]const u16{ &rip.P16_TGT_3ACA8, &rip.P16_TGT_3ACC2, &rip.P16_TGT_3ACDC }) |*g, tgt| {
        core.palSets(g, &.{ .{ .tgt = tgt, .n = 23 }, .{ .tgt = &rip.P16_TGT_3AC8E, .n = 24 } });
    }
    for (&bufs) |*b| for (b) |*row| @memset(row, 0);
    back = 0;
    front = 1;
}

pub fn vbl() void {
    core.colour = 0;
}

fn offset(p: *u32, step: u32, amp: i32, scale: i32) i32 {
    p.* = (p.* + step) & 0x7FF;
    return core.sinMul(p.* >> 1, amp) * scale;
}

fn render(two: bool) void {
    var a2: usize = undefined;
    var a3: usize = 0;
    if (two) {
        const d7 = offset(&pa[0], 8, 0x2F, 2);
        const d6 = offset(&pa[1], 6, 0x45, 0xC0);
        const d5 = offset(&pa[2], 12, 0x2F, 2);
        const d4 = offset(&pa[3], 4, 0x46, 0xC0);
        a2 = @intCast(@as(i32, rip.P16_W0) + ((d7 + d6) >> 1));
        a3 = @intCast(@as(i32, rip.P16_W0) + ((d5 + d4) >> 1));
    } else {
        const d7 = offset(&pb[0], 8, 0x2F, 2);
        const d6 = offset(&pb[1], 6, 0x45, 0xC0);
        a2 = @intCast(@as(i32, rip.P16_W0) + ((d7 + d6) >> 1));
    }
    for (&bufs[back], 0..) |*row, r| {
        for (row[2..50], 0..) |*cell, c| {
            var v: u32 = core.le16(assets.p16_wt, a2 + r * 96 + c);
            if (two) v += core.le16(assets.p16_wt, a3 + r * 96 + c);
            cell.* = assets.p16_opc[(((T + v) & 0xFFFF) >> 1) & 0xFFF];
        }
    }
    core.later(.p16_show, 0);
}

/// Deferred: the new render becomes the one the kernel shows.
pub fn show() void {
    front = back;
    back = 1 - back;
}

pub fn post92() void {
    T = (T + 2) & 0x1FFF;
}

pub fn post93() void {
    group = 1;
    T = 0x810;
    c191ec -%= 1;
    if (c191ec & 0x8000 == 0) ofs = 0x38E; // bpl: only on the first call
}

pub fn post94() void {
    group = 2;
    T = (T + 0x82) & 0x1FFF;
    c191c4 -%= 1;
    if (c191c4 & 0x8000 == 0) ofs = 0x38E;
}

pub fn m92() void {
    render(false);
    core.later(.p16_m92b, 0);
}

pub fn m92b() void {
    c1922e -= 1;
    if (c1922e == 0) {
        c1922e = 2;
        if (ofs < 0x256) ofs += 0x1A;
    }
}

pub fn m93() void {
    render(true);
    core.later(.p16_m93b, 0);
}

pub fn m93b() void {
    c1925a -= 1;
    if (c1925a == 0) {
        c1925a = 4;
        if (ofs > 0x256) ofs -= 0x1A;
    }
}

pub fn m95() void {
    render(true);
    core.later(.p16_m95b, 0);
}

pub fn m95b() void {
    c19284 -= 1;
    if (c19284 == 0) {
        c19284 = 2;
        if (core.sw(ofs) > 0) ofs -= 0x1A;
    }
}

pub fn kernel(l0: u32) void {
    const flat: *const [48 * 13]u16 = @ptrCast(&groups[group]);
    const o = ofs >> 1;
    var regs: [14]u16 = undefined;
    for (&regs, 0..) |*r, i| r.* = if (o + i < flat.len) flat[o + i] else 0; // 13 zero words follow the group
    for (bufs[front], 0..) |cells, ri| {
        var row: [52]u16 = undefined;
        for (&row, cells) |*v, n| v.* = regs[n];
        for (0..8) |l| {
            const base: u32 = 336 + 512 * @as(u32, @intCast(8 * ri + l));
            for (row, 0..) |v, j| out.emit(l0, base + 8 * @as(u32, @intCast(j)), v);
        }
    }
    out.emit(l0, 102720, 0);
    core.colour = 0;
}
