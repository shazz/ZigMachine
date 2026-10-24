// The palette's layout and the dithered quantiser that picks an index in it.
// Pure (no machine imports), so dither_test.zig runs it natively; palette.zig
// fills the colours and re-exports all of this.
//
// Layout (index ranges):
//   0..3     HUD: panel, text, bar, dim bar
//   4..43    sky ramp, 40 levels, deep blue (top) -> peach (horizon)
//   44..123  floor: 2 tones x 5 fog levels x 8 shade levels
//   124..233 five sphere ramps of 22 levels (shadow -> colour -> white-hot)
// A ramp holds one colour per intensity step, so the picture is as smooth as
// the ordered dither (4x4 Bayer) can make 8..40 levels: the tracer quantises
// each pixel's 0..256 intensity against the Bayer threshold for its position.

pub const PANEL: u8 = 0;
pub const TEXT: u8 = 1;
pub const BAR: u8 = 2;
pub const BAR_DIM: u8 = 3;

pub const SKY_BASE: u8 = 4;
pub const SKY_LV = 40;
pub const FLOOR_BASE: u8 = 44;
pub const FOG_LV = 5;
pub const SHADE_LV = 8;
pub const MAT_BASE: u8 = 124;
pub const MAT_LV = 22;

/// Ordered-dither threshold 0..255 for a pixel position.
pub fn bayer(x: u32, y: u32) u32 {
    const m = [16]u8{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    return @as(u32, m[(y & 3) * 4 + (x & 3)]) * 16 + 8;
}

/// Quantise intensity q8 (0..256) onto `lv` levels, rounding up when the
/// fractional part beats the pixel's Bayer threshold.
pub fn quant(q8: u32, comptime lv: u32, bay: u32) u8 {
    const v = q8 * (lv - 1);
    return @intCast((v >> 8) + @intFromBool((v & 255) > bay));
}

/// A shaded sample before dithering: its ramp class, its 0..256 intensity and,
/// on the floor, its 0..256 fog. index() is the only place it becomes a colour.
pub const Shade = struct { cls: u8, q: u16, fog: u16 };
pub const CLS_SKY: u8 = 0;
pub const CLS_FLOOR: u8 = 1; // + tone (0, 1)
pub const CLS_MAT: u8 = 3; // + sphere id (0..4)

/// The palette index for a Shade under Bayer threshold `bay` (the fog level
/// dithers on the inverted threshold so the two ramps do not move together).
pub fn index(s: Shade, bay: u32) u8 {
    if (s.cls == CLS_SKY) return SKY_BASE + quant(s.q, SKY_LV, bay);
    if (s.cls < CLS_MAT) {
        const ramp = (s.cls - CLS_FLOOR) * FOG_LV + quant(s.fog, FOG_LV, 255 - bay);
        return FLOOR_BASE + ramp * SHADE_LV + quant(s.q, SHADE_LV, bay);
    }
    return MAT_BASE + (s.cls - CLS_MAT) * MAT_LV + quant(s.q, MAT_LV, bay);
}
