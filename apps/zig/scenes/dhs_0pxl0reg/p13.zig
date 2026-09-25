// --------------------------------------------------------------------------
// P13 rotozoom + three text strips. Kernel $1C428: 25 blocks x 8 lines (7
// drawn), 53 x 8 px cells from rel D+4096b+512l; cells 0..15 a text strip,
// 16..51 the rotozoom (p13_roto.zig), 52 = d1. D = 720 + 4 x (or.l words
// among the 32 delay words at $1C444): three modes 64 px apart, whose rows
// wrap into the next line. Registers d1..a5 = palette set ofs/26 of the group
// the mode selects. Double-buffered, swapped at VBL.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");
const roto = @import("p13_roto.zig");

// Palette groups by the mode that shows them: A ($A925C), B ($A862C), C ($A79FC).
const MODES = [3]struct { or_l: u32, cnt: usize, tab: []const u8 }{
    .{ .or_l = 0, .cnt = 0, .tab = &rip.P13_MODE_1C2F6 },
    .{ .or_l = 16, .cnt = 2, .tab = &rip.P13_MODE_1C380 },
    .{ .or_l = 32, .cnt = 4, .tab = &rip.P13_MODE_1C3FC },
};

var t: u32 = 0; // $40FD4
var group: usize = 0; // palette group ($40FCE)
var ofs: u32 = 0; // $40FD2
var or_l: u32 = 32; // or.l words in the delay field
var cnt: [6]u32 = undefined; // $1C2F2.. : per mode, a 3-frame counter and a table index
var sofs: [3]u32 = undefined; // the three strips' scroll offsets
var sets: [3][48][13]u16 = undefined;
var bufs: [2][25][54]u8 = undefined; // register numbers; [0] is the unused $8080 word
var back: usize = 0;
var front: usize = 1;

pub fn reset() void {
    t = rip.P13_T;
    group = rip.P13_PTR;
    ofs = rip.P13_OFS;
    or_l = 32;
    for (&cnt, rip.P13_CNT) |*c, v| c.* = v;
    for (&sofs, rip.P13_SOFS) |*s, v| s.* = v;
}

pub fn init() void {
    // in the demo's order ($A79FC, $A862C, $A925C): the fader's rotation is global
    inline for (.{ 2, 1, 0 }, .{ &rip.P13_TGT_41462, &rip.P13_TGT_4147C, &rip.P13_TGT_41496 }) |g, tgt| {
        core.palSets(48, &sets[g], &.{ .{ .tgt = tgt, .n = 23 }, .{ .tgt = &rip.P13_TGT_41448, .n = 24 } });
    }
    var tpl: [54]u8 = undefined;
    tpl[0] = 0;
    @memset(tpl[1..18], 1);
    for (0..12) |k| tpl[18 + k] = @intCast(2 + k);
    for (0..13) |k| tpl[30 + k] = @intCast(1 + k);
    for (0..10) |k| tpl[43 + k] = @intCast(1 + k);
    tpl[53] = 1;
    for (&bufs) |*b| @memset(b, tpl);
    back = 0;
    front = 1;
}

pub fn vbl() void {
    core.colour = 0;
    const x = back;
    back = front;
    front = x;
}

pub fn m1c6b8() void {
    t +%= 2;
    roto.render(t, &bufs[back]);
}

pub fn dec() void {
    if (ofs != 0) ofs -= 0x1A;
}

/// Entries mA/mB/mC: the delay mode, and every third frame the next palette
/// set from the mode's byte table.
pub fn mode(m: usize) void {
    const md = MODES[m];
    or_l = md.or_l;
    group = m;
    cnt[md.cnt] -= 1;
    if (cnt[md.cnt] == 0) {
        cnt[md.cnt] = 3;
        const i = cnt[md.cnt + 1];
        ofs = @as(u32, md.tab[i]) * 0x1A;
        if (i != 0x2B) cnt[md.cnt + 1] += 1;
    }
}

/// $1CB10 / $1CB4C / $1CB8A: strip k into cells 1..16, scrolling 2 rows a frame.
pub fn strip(k: usize) void {
    const mem = assets.p13_strips[rip.P13_STRIP_AT[k]..][0..rip.P13_STRIP_LEN[k]];
    const o = sofs[k] >> 1;
    for (&bufs[back], 0..) |*row, r| @memcpy(row[1..17], mem[o + 16 * r ..][0..16]);
    if (k != 1) {
        if (core.sw(sofs[k]) > 0) sofs[k] -= 0x20;
    } else if (sofs[k] < 0x1180) sofs[k] += 0x20;
}

pub fn kernel(l0: u32) void {
    const D = 720 + 4 * or_l;
    const pal = &sets[group][ofs / 26];
    for (bufs[front], 0..) |cells, bi| {
        const b: u32 = @intCast(bi);
        var row: [53]u16 = undefined;
        for (&row, cells[1..54]) |*v, n| v.* = pal[n - 1];
        for (0..7) |l| {
            const base = D + 4096 * b + 512 * @as(u32, @intCast(l));
            for (row, 0..) |v, j| out.emit(l0, base + 8 * @as(u32, @intCast(j)), v);
        }
    }
    out.emit(l0, D + 102396, 0);
    core.colour = 0;
}
