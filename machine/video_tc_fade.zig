// --------------------------------------------------------------------------
// The true-colour fade (HW 1.16.0, docs/HW_API.md "True-colour fade"): a TRUECOLOR plane's pixel,
// after the 565 -> 888 expansion (video_tc.zig expand), goes through a brightness fade toward
// black or white (GBA BLDY / SNES INIDISP) then a signed per-channel offset (Saturn colour
// offset), clamped. A fade or a flash is one register write: the pixels are never rewritten.
// FRESCO's painter (fpga/rtl/video/zm_video_paint.v) computes exactly this, channel by channel:
//
//   w  = coef + (coef >> 4)            coef 0..31 -> weight 0..15, 17..32 (31 is full)
//   m  = 32 - w
//   black: y = (x * m + 16) >> 5                  white: y = 255 - (((255 - x) * m + 16) >> 5)
//   out = clamp(y + ofs, 0, 255)                  ofs a signed byte, -128..127
//
// Toward white is toward black of the complement (255 - x is ~x on 8 bits), so the two
// directions round the same way. Alpha stays 255.
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");

/// One plane's fade registers.
pub const Fade = struct {
    ctl: u8 = 0, // REG_TC_FADE: bits 0..4 coef, bit 5 toward white
    r: i8 = 0,
    g: i8 = 0,
    b: i8 = 0,

    pub fn identity(self: Fade) bool {
        return self.ctl & 0x1F == 0 and self.r == 0 and self.g == 0 and self.b == 0;
    }
};

/// Plane p's fade as the registers hold it now (`regs` is the register block).
pub fn read(regs: []const u8, p: usize) Fade {
    return .{
        .ctl = regs[memmap.REG_TC_FADE + p],
        .r = @bitCast(regs[memmap.REG_TC_OFS_R + p]),
        .g = @bitCast(regs[memmap.REG_TC_OFS_G + p]),
        .b = @bitCast(regs[memmap.REG_TC_OFS_B + p]),
    };
}

/// The multiplier of a control byte: 32 - w, 32 (coef 0) .. 0 (coef 31).
pub inline fn mult(ctl: u8) u32 {
    const c: u32 = ctl & 0x1F;
    return 32 - (c + (c >> 4));
}

/// One 8-bit channel.
pub inline fn channel(x: u8, m: u32, white: bool, ofs: i8) u8 {
    const in: u32 = if (white) 255 - @as(u32, x) else x;
    const t: u32 = (in * m + 16) >> 5;
    const y: i32 = @intCast(if (white) 255 - t else t);
    return @intCast(@max(0, @min(255, y + ofs)));
}

/// An expanded pixel (R in the low byte, alpha 255) through the fade.
pub fn apply(c: u32, f: Fade) u32 {
    const m = mult(f.ctl);
    const white = f.ctl & memmap.TC_FADE_WHITE != 0;
    const r: u32 = channel(@truncate(c), m, white, f.r);
    const g: u32 = channel(@truncate(c >> 8), m, white, f.g);
    const b: u32 = channel(@truncate(c >> 16), m, white, f.b);
    return 0xFF00_0000 | (b << 16) | (g << 8) | r;
}
