// --------------------------------------------------------------------------
// P15 wobbling picture. Kernel $1D20A, top border open: 270 lines, line L runs
// the routine of picture row R[L] (0..127): 52 x 8 px cells from rel
// 332+512L, register[nibble], registers d0..a5 = 14 words from palette set
// ofs/26 (the sets are 13 words apart, so a5 is the next set's first word).
//   R[L] = (1024 + (C + TA[A/2 + L] + TB[B/2 + L]) / 4) mod 128
//   TA[i] = (sin(2i) * 350 >> 15) * 4,  TB[i] = (sin(i) * 250 >> 15) * 4
// A += 8 a frame; C runs $200 -> 0 in steps of 8 and back. The palette walks
// 120 sets: black -> $4329A -> $43266 -> $43280 -> $4324C -> black.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const LINES = 270;
const SETS = 120;

var A: u32 = 0;
var B: u32 = 0;
var C: u32 = 0;
var ofs: u32 = 0; // $4324A, bytes (26 a set)
var t1d1be: u16 = 0;
var c1d1e2: u32 = 0;
var t1d202: u16 = 0;
var rows: [LINES]u8 = undefined;
var flat: [SETS * 13 + 13]u16 = undefined; // the sets end to end, then 13 zero words

pub fn reset() void {
    A = rip.P15_A;
    B = rip.P15_B;
    C = rip.P15_C;
    ofs = rip.P15_OFS;
    t1d1be = rip.P15_T1D1BE;
    c1d1e2 = rip.P15_C1D1E2;
    t1d202 = rip.P15_T1D202;
    @memset(&rows, 0);
}

pub fn init() void {
    core.colour = 0;
    var p = [_]u16{0} ** 13;
    @memset(&flat, 0);
    var n: usize = 1;
    const zero = [_]u16{0} ** 13;
    for ([_]*const [13]u16{ &rip.P15_TGT_4329A, &rip.P15_TGT_43266, &rip.P15_TGT_43280, &rip.P15_TGT_4324C, &zero }, [_]u32{ 23, 24, 24, 24, 24 }) |tgt, steps| {
        for (0..steps) |_| {
            core.step1(&p, tgt);
            @memcpy(flat[13 * n ..][0..13], &p);
            n += 1;
        }
    }
    frame(); // the init ends with one $1DCB0 call
}

pub fn vbl() void {
    core.colour = 0;
}

/// $1DCB0
pub fn frame() void {
    const a2 = A >> 1;
    const b2 = B >> 1;
    for (&rows, 0..) |*r, li| {
        const L: u32 = @intCast(li);
        const ta = core.sinMul((2 * (a2 + L)) % 1024, 0x15E) * 4;
        const tb = core.sinMul((b2 + L) % 1024, 0xFA) * 4;
        r.* = @intCast(@mod(1024 + @divFloor(core.sw(C) + ta + tb, 4), 128));
    }
    A = (A + 8) % 0x1000;
    if (core.sw(C) > 0) C -= 8 else C = 0x200;
}

pub fn p1() void {
    t1d1be ^= 0xFFFF;
    if (t1d1be == 0 and ofs < 0x256) ofs += 0x1A;
}

pub fn p2() void {
    c1d1e2 -= 1;
    if (c1d1e2 == 0) {
        c1d1e2 = 8;
        if (ofs < 0x9A6) ofs += 0x1A;
    }
}

pub fn p3() void {
    t1d202 ^= 0xFFFF;
    if (t1d202 == 0 and ofs < 0xC16) ofs += 0x1A;
}

pub fn kernel(l0: u32) void {
    const regs = flat[ofs >> 1 ..][0..14];
    for (rows, 0..) |r, li| {
        const L: u32 = @intCast(li);
        const row = assets.p15_img[@as(usize, r) * 52 ..][0..52];
        for (row, 0..) |n, j| out.emit(l0, 332 + 512 * L + 8 * @as(u32, @intCast(j)), regs[@min(n, 13)]);
    }
    out.emit(l0, 138556, 0);
    core.colour = 0;
}
