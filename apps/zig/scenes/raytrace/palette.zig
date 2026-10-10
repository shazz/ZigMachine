// The 256-entry palette and the dithered quantiser that fills it.
//
// Layout (index ranges):
//   0..3     HUD: panel, text, bar, dim bar
//   4..43    sky ramp, 40 levels, deep blue (top) -> peach (horizon)
//   44..123  floor: 2 tones x 5 fog levels x 8 shade levels
//   124..233 five sphere ramps of 22 levels (shadow -> colour -> white-hot)
// A ramp holds one colour per intensity step, so the picture is as smooth as
// the ordered dither (4x4 Bayer) can make 8..40 levels: the tracer quantises
// each pixel's 0..256 intensity against the Bayer threshold for its position.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

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

const Rgb = [3]u8;
const HORIZON: Rgb = .{ 255, 168, 112 };
const MIDSKY: Rgb = .{ 168, 92, 150 };
const ZENITH: Rgb = .{ 36, 56, 170 };
const TONES = [2]Rgb{ .{ 236, 226, 204 }, .{ 128, 28, 48 } };
const MATS = [5]Rgb{ .{ 200, 208, 226 }, .{ 226, 36, 36 }, .{ 240, 178, 36 }, .{ 40, 96, 240 }, .{ 40, 200, 90 } };

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

fn mix(a: Rgb, b: Rgb, num: u32, den: u32) Rgb {
    var o: Rgb = undefined;
    for (&o, 0..) |*c, i| {
        const av: i32 = a[i];
        const bv: i32 = b[i];
        c.* = @intCast(av + @divTrunc((bv - av) * @as(i32, @intCast(num)), @as(i32, @intCast(den))));
    }
    return o;
}

fn scaled(c: Rgb, num: u32, den: u32) Rgb {
    return mix(.{ 0, 0, 0 }, c, num, den);
}

fn put(fb: *LogicalFB, idx: usize, c: Rgb) void {
    fb.setPaletteEntry(@intCast(idx), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
}

/// A lit ramp: black -> colour by 78 %, then toward white for the highlight.
fn ramp(c: Rgb, i: u32, lv: u32) Rgb {
    const n = i * 100 / (lv - 1);
    if (n <= 78) return scaled(c, n, 78);
    return mix(c, .{ 255, 255, 255 }, n - 78, 22);
}

pub fn install(fb: *LogicalFB) void {
    put(fb, PANEL, .{ 12, 12, 28 });
    put(fb, TEXT, .{ 235, 235, 255 });
    put(fb, BAR, .{ 255, 168, 112 });
    put(fb, BAR_DIM, .{ 52, 52, 96 });
    for (0..SKY_LV) |i| {
        const n: u32 = @intCast(i);
        const c = if (n < SKY_LV / 2) mix(HORIZON, MIDSKY, n, SKY_LV / 2) else mix(MIDSKY, ZENITH, n - SKY_LV / 2, SKY_LV / 2);
        put(fb, SKY_BASE + i, c);
    }
    for (0..2) |tone| for (0..FOG_LV) |fog| for (0..SHADE_LV) |sh| {
        const lit = scaled(TONES[tone], @intCast(sh + 0), SHADE_LV - 1);
        put(fb, FLOOR_BASE + (tone * FOG_LV + fog) * SHADE_LV + sh, mix(lit, HORIZON, @intCast(fog), FOG_LV - 1));
    };
    for (0..5) |m| for (0..MAT_LV) |i| put(fb, MAT_BASE + m * MAT_LV + i, ramp(MATS[m], @intCast(i), MAT_LV));
}
