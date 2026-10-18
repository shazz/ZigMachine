// --------------------------------------------------------------------------
// STNICCC fills on the CHISEL blitter. The CPU filler spent a byte store per
// pixel (@memset, ~3 cycles each) on a 400x280 plane, which is what dropped
// the fullscreen act to ~10 fps; a FILL is one setup and then ~1 clock a pixel.
// The destination registers (base, stride, CON) are written once per frame in
// begin(); a span then only rewrites colour, x, y, w, h and the command.
// Pixel-identical to the memset: both write the same [x, x+w) of the same row.
// --------------------------------------------------------------------------
const std = @import("std");
const hw = @import("hardware");
const polyfill = @import("polyfill.zig");

var base: usize = 0;

inline fn w8(off: usize, v: u8) void {
    @as(*u8, @ptrFromInt(base + off)).* = v;
}
inline fn w16(off: usize, v: u16) void {
    std.mem.writeInt(u16, @as(*[2]u8, @ptrFromInt(base + off)), v, .little);
}

/// Point the blitter at `t`'s window and return the target with fills routed to it.
pub fn begin(t: polyfill.Target) polyfill.Target {
    base = @intCast(hw.hwVideoBase());
    std.mem.writeInt(u32, @as(*[4]u8, @ptrFromInt(base + hw.BLIT_D_BASE)), @intCast(@intFromPtr(t.px.ptr) - base), .little);
    w16(hw.BLIT_D_STRIDE, @intCast(t.stride));
    w8(hw.BLIT_CON, 0);
    w8(hw.BLIT_CON2, 0); // never stale: no SRC_ABS, FILL_MT or halftone from an earlier user
    var out = t;
    out.rect = fillRect;
    return out;
}

fn fillRect(x: usize, y: usize, w: usize, h: usize, color: u8) void {
    w8(hw.BLIT_COLOR, color);
    w16(hw.BLIT_X0, @intCast(x));
    w16(hw.BLIT_Y0, @intCast(y));
    w16(hw.BLIT_W, @intCast(w));
    w16(hw.BLIT_H, @intCast(h));
    w8(hw.BLIT_COMMAND, hw.BLIT_CMD_FILL);
    hw.hwBlit();
}

/// Clear a whole plane (stride x rows, as LogicalFB.clearFrameBuffer does, but not a byte loop).
pub fn clearPlane(px: []u8, stride: usize, rows: usize, color: u8) void {
    const t = begin(.{ .px = px, .stride = stride, .w = stride, .h = rows, .ox = 0 });
    t.rect.?(0, 0, stride, rows, color);
}
