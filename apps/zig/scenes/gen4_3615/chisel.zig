// --------------------------------------------------------------------------
// The one CHISEL op zg.Blitter has no call for: D = A & B, both sources read
// from cart RAM (CON2.SRC_ABS). The scroller's glyphs are unpacked to 0x00 /
// 0xFF masks (channel A) and the box behind them is channel B, so one blit a
// glyph writes the box where the glyph is opaque and black everywhere else:
// canvas 'destination-in' in hardware, where the CPU used to clear the box and
// pattern-blit each glyph over it a word at a time.
// --------------------------------------------------------------------------
const std = @import("std");
const hw = @import("hardware");
const LogicalFB = @import("zigos").LogicalFB;

/// Minterm D = A & B: the truth table index is A<<2 | B<<1 | C, set at 6 and 7.
const MT_A_AND_B: u8 = 0xC0;

fn reg(comptime T: type, off: usize) *align(1) volatile T {
    return @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())) + off);
}

/// D(dx + i, dy + j) = a[j * a_stride + i] & b[j * b_stride + i] for the w x h
/// box; both sources must lie in cart RAM (the machine refuses the op otherwise).
pub fn andBlit(fb: *LogicalFB, dx: i16, dy: i16, a: [*]const u8, a_stride: u16, b: [*]const u8, b_stride: u16, w: u16, h: u16) void {
    if (w == 0 or h == 0) return;
    const base: usize = @intCast(hw.hwVideoBase());
    reg(u32, hw.BLIT_D_BASE).* = @intCast(@intFromPtr(fb.fb) - base);
    reg(u16, hw.BLIT_D_STRIDE).* = fb.stride;
    reg(u8, hw.BLIT_CON2).* = hw.CON2_SRC_ABS;
    reg(u32, hw.BLIT_A_BASE).* = @intCast(@intFromPtr(a));
    reg(u16, hw.BLIT_A_STRIDE).* = a_stride;
    reg(u32, hw.BLIT_B_BASE).* = @intCast(@intFromPtr(b));
    reg(u16, hw.BLIT_B_STRIDE).* = b_stride;
    reg(u8, hw.BLIT_CON).* = hw.CON_USEA | hw.CON_USEB;
    reg(u8, hw.BLIT_MINTERM).* = MT_A_AND_B;
    reg(i16, hw.BLIT_X0).* = dx;
    reg(i16, hw.BLIT_Y0).* = dy;
    reg(u16, hw.BLIT_W).* = w;
    reg(u16, hw.BLIT_H).* = h;
    reg(u8, hw.BLIT_COMMAND).* = hw.BLIT_CMD_BLIT;
    hw.hwBlit();
}

comptime {
    std.debug.assert(@import("builtin").cpu.arch.endian() == .little); // the registers are little-endian
}
