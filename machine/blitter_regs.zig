// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter: the register block, the clip and the minterm,
// shared by every op (machine/blitter.zig dispatches, blitter_ops.zig and
// blitter_tex.zig draw). See docs/BLITTER_HW_SPEC.md.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("sdk/memmap.zig");

pub inline fn region() [*]u8 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE);
}
pub inline fn r8(off: usize) u8 {
    return region()[off];
}
pub inline fn w8(off: usize, v: u8) void {
    region()[off] = v;
}
pub inline fn r16(off: usize) u16 {
    return std.mem.readInt(u16, region()[off .. off + 2][0..2], .little);
}
pub inline fn ri16(off: usize) i16 {
    return std.mem.readInt(i16, region()[off .. off + 2][0..2], .little);
}
pub inline fn r32(off: usize) u32 {
    return std.mem.readInt(u32, region()[off .. off + 4][0..4], .little);
}
pub inline fn w32(off: usize, v: u32) void {
    std.mem.writeInt(u32, region()[off .. off + 4][0..4], v, .little);
}

// Destination plane height is implied by its stride (same rule the video
// machine uses to size a plane), so a blit can never spill into a neighbour's
// VRAM slot when the clip rect is left disabled.
inline fn dstHeight(stride: u16) u16 {
    return if (stride == memmap.STRIDE_FULLSCREEN) memmap.PHYSICAL_HEIGHT else memmap.HEIGHT;
}

pub const Clip = struct {
    x0: i32,
    y0: i32,
    x1: i32, // exclusive
    y1: i32, // exclusive
};

// The effective clip: the destination-buffer bounds, further restricted by the
// CLIP rect when CON.CLIP_EN is set.
pub fn clipRect(con: u8, d_stride: u16) Clip {
    var c = Clip{ .x0 = 0, .y0 = 0, .x1 = d_stride, .y1 = dstHeight(d_stride) };
    if (con & memmap.CON_CLIP_EN != 0) {
        const cx: i32 = r16(memmap.BLIT_CLIP_X);
        const cy: i32 = r16(memmap.BLIT_CLIP_Y);
        c.x0 = @max(c.x0, cx);
        c.y0 = @max(c.y0, cy);
        c.x1 = @min(c.x1, cx + r16(memmap.BLIT_CLIP_W));
        c.y1 = @min(c.y1, cy + r16(memmap.BLIT_CLIP_H));
    }
    return c;
}

pub inline fn inClip(c: Clip, x: i32, y: i32) bool {
    return x >= c.x0 and x < c.x1 and y >= c.y0 and y < c.y1;
}

pub inline fn plot(d: [*]u8, stride: u16, c: Clip, x: i32, y: i32, v: u8) void {
    if (inClip(c, x, y)) d[@as(usize, @intCast(y)) * stride + @as(usize, @intCast(x))] = v;
}

// D = LF(A,B,C): the 8-bit minterm is a truth table indexed by (a<<2|b<<1|c),
// applied independently to each of the 8 bits of the chunky palette index.
pub fn applyMinterm(a: u8, b: u8, c: u8, mt: u8) u8 {
    var out: u8 = 0;
    var bit: u3 = 0;
    while (true) : (bit += 1) {
        const idx: u3 = @intCast((((a >> bit) & 1) << 2) | (((b >> bit) & 1) << 1) | ((c >> bit) & 1));
        out |= @as(u8, (mt >> idx) & 1) << bit;
        if (bit == 7) break;
    }
    return out;
}

// --------------------------------------------------------------------------
// Halftone (16x16 1-bit pattern selecting COLOR / BG_COLOR)
// --------------------------------------------------------------------------
// Explicit when the program says so (CON2.HALFTONE_EN), which is the only way
// to ask for an ALL-ZERO pattern — density 0, every pixel BG_COLOR. With the bit
// clear the machine sniffs for a non-zero row, as it did before 1.5.0, so a
// caller that only loads a pattern still gets a halftone.
pub fn haveHalftone(con2: u8) bool {
    if (con2 & memmap.CON2_HALFTONE_EN != 0) return true;
    var i: usize = 0;
    while (i < 16) : (i += 1) if (r16(memmap.BLIT_HALFTONE + i * 2) != 0) return true;
    return false;
}

pub inline fn halftoneBit(x: i32, y: i32) bool {
    const row = r16(memmap.BLIT_HALFTONE + @as(usize, @intCast(@mod(y, 16))) * 2);
    return (row >> @as(u4, @intCast(@mod(x, 16)))) & 1 != 0;
}
