// --------------------------------------------------------------------------
// The true-colour plane (HW 1.15.0, FB_MODE_TRUECOLOR / FB_MODE_TRUECOLOR_FULL;
// fpga/review/TRUECOLOR_PLANE.md option A0): a pixel is a little-endian u16
// R5 G6 B5, no palette. It goes through the same line loop as every plane mode
// (video.zig renderPlaneTruecolor: handler, copper record, LBASE, HSCROLL per
// line), so planes over and under it, dirty lines and the PFB oracle all hold.
// FRESCO's painter (fpga/rtl/video/zm_video_paint.v) does exactly this per column.
// --------------------------------------------------------------------------
const std = @import("std");

/// 565 -> the PFB's RGBA word (R in the low byte, alpha 255), by bit replication: 0xFFFF is
/// white, 0x0000 black. The RTL's expansion is the same wiring; Hatari's Videl hi-colour
/// conversion (ScreenConv_HiColorTo32bppNoZoom) is the same formula.
pub inline fn expand(px: u16) u32 {
    const r: u32 = px >> 11;
    const g: u32 = (px >> 5) & 0x3F;
    const b: u32 = px & 0x1F;
    const r8 = (r << 3) | (r >> 2);
    const g8 = (g << 2) | (g >> 4);
    const b8 = (b << 3) | (b >> 2);
    return 0xFF00_0000 | (b8 << 16) | (g8 << 8) | r8;
}

/// A line's first byte: bit 0 of a true-colour line address is ignored on both machines
/// (the STE's $FF820D has no bit 0): an odd FB_BASE, LBASE, HSCROLL or stride lands on the
/// even pixel below. `row` is the line's start (lb.at), `hs` its live HSCROLL.
pub inline fn lineAt(row: usize, hs: usize) usize {
    return (row + hs) & ~@as(usize, 1);
}

/// One line: `n` pixels from `src` (byte offset `at` in the region), each written doubled
/// into the raster row `out64` (one u64 a logical pixel) from logical column 0.
pub fn line(out64: []u64, src: [*]const u8, at: usize, n: usize) void {
    for (out64[0..n], 0..) |*o, lx| {
        const c = expand(std.mem.readInt(u16, src[at + 2 * lx ..][0..2], .little));
        o.* = @as(u64, c) | (@as(u64, c) << 32);
    }
}
