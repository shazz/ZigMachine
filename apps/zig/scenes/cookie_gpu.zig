// --------------------------------------------------------------------------
// The CHISEL cookie-cut with a MASK: D = (A & B) | (~A & D), minterm 0xCA over a
// w x h rectangle of a plane. A is a mask picture (0xFF where B shows, 0 where the
// destination stays), B the picture; both are read from cart RAM (SRC_ABS), the
// destination is read back (channel C is the destination itself).
//
// zg.Blitter has a key (B == key skips) but no mask channel; this is the register
// sequence of Blitter.blitAbs plus A and the minterm, shared by the scenes that
// need it (tex's letters, the Union main scroller's glyphs).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");

inline fn w8(base: usize, off: usize, v: u8) void {
    @as(*u8, @ptrFromInt(base + off)).* = v;
}
inline fn w16(base: usize, off: usize, v: u16) void {
    std.mem.writeInt(u16, @as(*[2]u8, @ptrFromInt(base + off)), v, .little);
}
inline fn w32(base: usize, off: usize, v: u32) void {
    std.mem.writeInt(u32, @as(*[4]u8, @ptrFromInt(base + off)), v, .little);
}

/// The w x h rectangle at (x, y) of `dst` takes B where A is set. `a` and `b` point at the
/// rectangle's first pixel in their pictures (row strides given); the rectangle must lie
/// inside the plane (clip it first) and inside both pictures.
pub fn masked(dst: *zg.LogicalFB, x: usize, y: usize, w: usize, h: usize, a: [*]const u8, a_stride: u16, b: [*]const u8, b_stride: u16) void {
    const base: usize = @intCast(hw.hwVideoBase());
    w32(base, hw.BLIT_D_BASE, @intCast(@intFromPtr(dst.fb) - base));
    w16(base, hw.BLIT_D_STRIDE, dst.stride);
    w32(base, hw.BLIT_C_BASE, @intCast(@intFromPtr(dst.fb) - base)); // C is the background: the destination itself
    w16(base, hw.BLIT_C_STRIDE, dst.stride);
    w8(base, hw.BLIT_CON2, hw.CON2_SRC_ABS);
    w32(base, hw.BLIT_A_BASE, @intCast(@intFromPtr(a)));
    w16(base, hw.BLIT_A_STRIDE, a_stride);
    w32(base, hw.BLIT_B_BASE, @intCast(@intFromPtr(b)));
    w16(base, hw.BLIT_B_STRIDE, b_stride);
    w8(base, hw.BLIT_CON, hw.CON_USEA | hw.CON_USEB | hw.CON_USEC);
    w8(base, hw.BLIT_MINTERM, hw.MT_COOKIE);
    w16(base, hw.BLIT_X0, @intCast(x));
    w16(base, hw.BLIT_Y0, @intCast(y));
    w16(base, hw.BLIT_W, @intCast(w));
    w16(base, hw.BLIT_H, @intCast(h));
    w8(base, hw.BLIT_COMMAND, hw.BLIT_CMD_BLIT);
    hw.hwBlit();
}
