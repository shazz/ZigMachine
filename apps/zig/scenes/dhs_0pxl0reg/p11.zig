// --------------------------------------------------------------------------
// P11 plasma map + vertical text scroller. Kernel $1BB98: 25 blocks x 8 lines
// (7 drawn + 1 empty); each drawn line is 53 x move.w Rn,(a7) = 8 px cells from
// rel D+4096b+512l, D = 180 + the delay field at $1BBB4 (16 x or.l + 23 x nop).
// A cell's colour is palette set ofs/26 at the register its opcode names.
// No clr at the end: colour 0 keeps the last cell (d1) to the next VBL.
//   cells 0..35  T[(TOFS + MAP[row0+b][col0+c]) / 2]: a 64x64 texture seen
//                through a 70x96 map that two sines move ($1BDAE)
//   cells 36..51 the 16-wide scroller (entry 65), cell 52 = d1
// Entry 64 turns one or.l into a nop every third frame (4 px left a step),
// entry 66 turns them back (right). Double-buffered, swapped at VBL.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

var ofs: u32 = 0; // $3E3B4, 26 bytes a palette set
var p1: u32 = 0;
var p2: u32 = 0;
var tofs: u32 = 0; // $1BF00
var sofs: u32 = 0; // $1C192, scroller position (32 bytes a row)
var delay: [39]u8 = undefined; // cycles of each delay word: or.l 8, nop 4
var c1bae4: u32 = 0;
var c1bb1e: u32 = 0;
var i1bb20: u32 = 0;
var i1bb74: u32 = 0;
var c1bb76: u32 = 0;
var c1bb78: u16 = 0;
var sets: [72][13]u16 = undefined;
var bufs: [2][25][53]u8 = undefined; // register number of each cell's opcode
var back: usize = 0;
var front: usize = 1;

pub fn reset() void {
    ofs = rip.P11_OFS;
    p1 = rip.P11_P1;
    p2 = rip.P11_P2;
    tofs = rip.P11_TOFS;
    sofs = rip.P11_SOFS;
    @memset(delay[0..16], 8);
    @memset(delay[16..], 4);
    c1bae4 = rip.P11_C1BAE4;
    c1bb1e = rip.P11_C1BB1E;
    i1bb20 = rip.P11_I1BB20;
    i1bb74 = rip.P11_I1BB74;
    c1bb76 = rip.P11_C1BB76;
    c1bb78 = rip.P11_C1BB78;
}

pub fn init() void {
    core.palSets(&sets, &.{
        .{ .tgt = &rip.P11_TGT_40F78, .n = 23 },
        .{ .tgt = &rip.P11_TGT_40F5E, .n = 24 },
        .{ .tgt = &rip.P11_TGT_40F92, .n = 24 },
    });
    for (&bufs) |*b| for (b) |*row| {
        for (row, 0..) |*c, k| c.* = if (k < 36) @intCast(1 + k % 13) else 1;
    };
    back = 0;
    front = 1;
}

pub fn vbl() void {
    core.colour = 0;
    const t = back;
    back = front;
    front = t;
}

/// $1BDAE
fn render() void {
    p1 = (p1 + 8) & 0x7FF;
    const dx = core.sinMul(p1 >> 1, 0x3B) * 2;
    p2 = (p2 + 0xA) & 0x7FF;
    const dy = core.sinMul(p2 >> 1, 0x2C) * 0xC0;
    const base: usize = @intCast((0x10BC + dx + dy) >> 1);
    for (&bufs[back], 0..) |*row, r| {
        for (row[0..36], 0..) |*c, col| {
            const v: u32 = core.le16(assets.p11_map, base + r * 96 + col);
            c.* = assets.p11_tex[((tofs + v) >> 1) & 4095];
        }
    }
    tofs = (tofs + 0x82) & 0x1FFF;
}

/// $1BF76
fn scroller() void {
    const k0 = sofs >> 5;
    for (&bufs[back], 0..) |*row, r| @memcpy(row[36..52], assets.p11_scr[(k0 + r) * 16 ..][0..16]);
    if (sofs < 0x8000) sofs += 0x20;
}

pub fn m1bac2() void {
    render();
    c1bae4 -= 1;
    if (c1bae4 == 0) {
        c1bae4 = 5;
        if (ofs != 0x256) ofs += 0x1A;
    }
}

pub fn m1bb22() void {
    render();
}

pub fn m1bb28() void {
    render();
    scroller();
}

/// Entry 64: or.l -> nop, one delay word every third frame.
pub fn m1bb32() void {
    render();
    c1bb76 -= 1;
    if (c1bb76 != 0) return;
    c1bb76 = 3;
    c1bb78 -%= 1;
    if (c1bb78 & 0x8000 != 0 and ofs != 0x4C6) ofs += 0x1A;
    delay[i1bb74 >> 1] = 4;
    if (i1bb74 != 0x1E) i1bb74 += 2;
}

/// Entry 66: back to or.l, and the palette fades down.
pub fn m1bae6() void {
    render();
    c1bb1e -= 1;
    if (c1bb1e != 0) return;
    c1bb1e = 3;
    if (ofs != 0) ofs -= 0x1A;
    delay[i1bb20 >> 1] = 8;
    if (i1bb20 != 0x3E) i1bb20 += 2;
}

pub fn kernel(l0: u32) void {
    var D: u32 = 180;
    for (delay) |d| D += d;
    const pal = &sets[ofs / 26];
    var row: [53]u16 = undefined;
    for (bufs[front], 0..) |cells, bi| {
        const b: u32 = @intCast(bi);
        for (&row, cells) |*v, n| v.* = pal[n - 1]; // d1..a5 = palette words 0..12
        for (0..7) |l| {
            const base = D + 4096 * b + 512 * @as(u32, @intCast(l));
            for (row, 0..) |v, j| out.emit(l0, base + 8 * @as(u32, @intCast(j)), v);
        }
    }
    core.colour = row[52];
}
