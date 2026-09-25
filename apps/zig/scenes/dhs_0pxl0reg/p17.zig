// --------------------------------------------------------------------------
// P17 end part: vertical text scroller over rasters. Kernel $2053A, top border
// open: 272 lines, line L runs routine RT[L] (440 routines of 52 cells): cells
// from rel 336+512L are d1 where the text bit is 1, else d0. Then d1 = A4[B/2+L]
// is written at 760+512L (in the blank: it colours the next line's start), and
// d0 = A5[A/2+L] is loaded. The pointer table ($20DE4) alternates between a
// 2-line phase and a whole step, so the text climbs 2 lines a frame; a new text
// row goes into routines R and R+220 every second call ($20D50).
// The demo ends here and runs this part forever.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const LINES = 272;
const ALL_ON: u64 = 0xFFFF_FFFF_FFFF_F000; // an untouched routine: 52 x d1

var A: u32 = 0; // $20CDE
var B: u32 = 0; // $20CE0
var R: u32 = 0; // next routine to receive a text row
var tofs: u32 = 0; // $20DDE
var tog: u16 = 0;
var ofs: u32 = 0; // $217A0
var variant: u16 = 0; // $217A2
var rt: [LINES]u16 = undefined;
var rout: [440]u64 = undefined; // bit 63-j = cell j

pub fn reset() void {
    A = rip.P17_A;
    B = rip.P17_B;
    R = rip.P17_R;
    tofs = rip.P17_TOFS;
    tog = rip.P17_TOG;
    ofs = rip.P17_OFS;
    variant = rip.P17_VAR;
    @memset(&rt, 0);
}

pub fn init() void {
    core.colour = 0;
    @memset(&rout, ALL_ON);
    for (0..301) |_| patch();
    for (0..2) |_| {
        textRow();
        patch();
    }
}

pub fn vbl() void {
    core.colour = 0;
}

/// $20DE4
fn patch() void {
    variant ^= 0xFFFF;
    const base = ofs >> 2;
    if (variant != 0) {
        for (&rt, 0..) |*r, L| r.* = @intCast(base + (L + 2) / 4);
        ofs = if (ofs >= 0x36C) 0 else ofs + 4;
    } else {
        for (&rt, 0..) |*r, L| r.* = @intCast(base + L / 4);
    }
}

/// $20D50
fn textRow() void {
    tog ^= 0xFFFF;
    if (tog != 0) return;
    const bits = std.mem.readInt(u64, assets.p17_text[tofs..][0..8], .big);
    rout[R] = bits;
    rout[R + 220] = bits;
    R = if (R >= 219) 0 else R + 1;
    if (tofs < 0x3898) tofs += 8;
}

pub fn m20530() void {
    textRow();
    patch();
}

/// $20CA6 (post-music): A and B step; the wrap frame resets A and skips B.
pub fn pAB() void {
    if (A >= 0x3FA) {
        A = 0;
        return;
    }
    A += 6;
    pB();
}

/// $20CCA
pub fn pB() void {
    B = if (B >= 0x692) 0x294 else B + 2;
}

pub fn kernel(l0: u32) void {
    var d0: u16 = rip.P17_PAL[0];
    var d1: u16 = rip.P17_PAL[1];
    const a4 = B >> 1;
    const a5 = A >> 1;
    for (rt, 0..) |r, li| {
        const L: u32 = @intCast(li);
        const row = rout[r];
        for (0..52) |j| {
            const on = (row >> @intCast(63 - j)) & 1 != 0;
            out.emit(l0, 336 + 512 * L + 8 * @as(u32, @intCast(j)), if (on) d1 else d0);
        }
        d1 = core.le16(assets.p17_a4, a4 + L);
        out.emit(l0, 760 + 512 * L, d1);
        d0 = core.le16(assets.p17_a5, (a5 + L) % 512);
    }
    out.emit(l0, 139584, 0);
    core.colour = 0;
}

const std = @import("std");
