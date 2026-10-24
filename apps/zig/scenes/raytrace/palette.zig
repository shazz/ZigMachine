// The 256-entry palette's colours. Its layout and the dithered quantiser that
// indexes it are in dither.zig, re-exported here.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const D = @import("dither.zig");
pub const PANEL = D.PANEL;
pub const TEXT = D.TEXT;
pub const BAR = D.BAR;
pub const BAR_DIM = D.BAR_DIM;
pub const SKY_BASE = D.SKY_BASE;
pub const SKY_LV = D.SKY_LV;
pub const FLOOR_BASE = D.FLOOR_BASE;
pub const FOG_LV = D.FOG_LV;
pub const SHADE_LV = D.SHADE_LV;
pub const MAT_BASE = D.MAT_BASE;
pub const MAT_LV = D.MAT_LV;
pub const bayer = D.bayer;
pub const quant = D.quant;
pub const Shade = D.Shade;
pub const CLS_SKY = D.CLS_SKY;
pub const CLS_FLOOR = D.CLS_FLOOR;
pub const CLS_MAT = D.CLS_MAT;
pub const index = D.index;

const Rgb = [3]u8;
const HORIZON: Rgb = .{ 255, 168, 112 };
const MIDSKY: Rgb = .{ 168, 92, 150 };
const ZENITH: Rgb = .{ 36, 56, 170 };
const TONES = [2]Rgb{ .{ 236, 226, 204 }, .{ 128, 28, 48 } };
const MATS = [5]Rgb{ .{ 200, 208, 226 }, .{ 226, 36, 36 }, .{ 240, 178, 36 }, .{ 40, 96, 240 }, .{ 40, 200, 90 } };

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
