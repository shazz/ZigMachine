// --------------------------------------------------------------------------
// EQUINOX's one plane (equinox.zig). The screen was four overscan planes stacked
// roads < backdrop (with the fading logo) < dragons < scrolltext, and FRESCO paints
// every enabled plane (~1.09 Mc each), so they are composited into ONE palette:
//
//   0..5     road_pal 0..5 (road1/road2 and the black field, BLACK = 5)
//   8+b      backtop_pal b, b != 5 (backtop and backscroll; 5 was the clear: road shows)
//   32+8k+p  the logo's colour k blended over road colour p at the logo's alpha, the
//            way the canvases stack (source-over); rewritten when the alpha steps
//   71..76   bobs_pal 1..6 (the dragons), 81..95 fonts_pal 1..15 (the scrolltext)
//   255      transparent, outside the 320x228 screen
//
// A pixel's index comes from what was under it, so the road under the logo is part
// of the logo's index: each road row shows road1 or road2, so the band has exactly
// two possible pictures (band[0], band[1]), built once at init.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const Color = zg.Color;

const DIR = "../assets/screens/equinox/";
pub const W: usize = 320;
pub const H: usize = 228;
pub const BAND_Y: usize = 113; // ROAD_Y
pub const BAND_ROWS: usize = 85; // ROAD_ROWS
pub const BLACK: u8 = 5;
pub const CLEAR: u8 = 255;

const road_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "road_pal.dat"));
const backtop_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "backtop_pal.dat"));
const logo_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "logo_pal.dat"));
const bob_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "bobs_pal.dat"));
const font_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "fonts_pal.dat"));
const road_rows = [2][]const u8{ @embedFile(DIR ++ "road1.raw"), @embedFile(DIR ++ "road2.raw") };
const backtop = @embedFile(DIR ++ "backtop.raw"); // rows 0..121
const backscroll = @embedFile(DIR ++ "backscroll.raw"); // rows 188..226
const logo = @embedFile(DIR ++ "logo.raw"); // 203x23 at (55, 145), index 1 the field
const BACKSCROLL_Y = 188;
const LOGO_X = 55;
const LOGO_Y = 145;
const LOGO_W = 203;
const LOGO_H = 23;
const LOGO_FIELD = 1;
const BACK_CLEAR = 5;
const PAIR = 32;
const DRAGON = 70;
const FONT = 80;

/// The index of screen pixel (x, y) with road image `road` (0 = road1, 1 = road2)
/// under the band, before any dragon or letter.
pub fn pixel(x: usize, y: usize, road: usize) u8 {
    const in_band = y >= BAND_Y and y < BAND_Y + BAND_ROWS;
    const p: u8 = if (in_band) road_rows[road][(y - BAND_Y) * W + x] else BLACK;
    const b: u8 = if (y < backtop.len / W) backtop[y * W + x] else if (y >= BACKSCROLL_Y and y < BACKSCROLL_Y + backscroll.len / W)
        backscroll[(y - BACKSCROLL_Y) * W + x]
    else
        BACK_CLEAR;
    if (b != BACK_CLEAR) return b + 8;
    if (y >= LOGO_Y and y < LOGO_Y + LOGO_H and x >= LOGO_X and x < LOGO_X + LOGO_W) {
        const k = logo[(y - LOGO_Y) * LOGO_W + x - LOGO_X];
        if (k != LOGO_FIELD) return PAIR + 8 * k + p;
    }
    return p;
}

pub fn setPalette(pal: [*]u32) void {
    for (0..256) |i| pal[i] = 0; // CLEAR and every unused entry: transparent
    for (0..6) |p| pal[p] = road_pal[p].toRGBA();
    for (0..24) |b| if (b != BACK_CLEAR) {
        pal[8 + b] = backtop_pal[b].toRGBA();
    };
    for (1..7) |b| pal[DRAGON + b] = bob_pal[b].toRGBA();
    for (1..16) |f| pal[FONT + f] = font_pal[f].toRGBA();
}

/// The logo's colours over each road colour, at alpha step `tenths` (0..10).
pub fn setLogoPairs(pal: [*]u32, tenths: usize) void {
    for (0..5) |k| for (0..5) |p| {
        pal[PAIR + 8 * k + p] = pairs[tenths][k][p];
    };
}

// Source-over, as the canvases composite: road R (opaque) then logo L at alpha
// A/255 gives L*a + R*(1-a) per channel, rounded once. Evaluated in f64 exactly as
// the browser does, so the merged plane is the same picture; zero runtime float.
const pairs: [11][5][5]u32 = blk: {
    @setEvalBranchQuota(20000);
    var t: [11][5][5]u32 = undefined;
    for (0..11) |s| {
        const A: u8 = @intCast((255 * s + 5) / 10); // equinox.zig LOGO_ALPHA_BYTE
        const a: f64 = @as(f64, @floatFromInt(A)) / 255.0;
        const ia: f64 = 1.0 - a;
        for (0..5) |k| for (0..5) |p| {
            const L = logo_pal[k];
            const R = road_pal[p];
            const c = Color{ .r = mix(L.r, R.r, a, ia), .g = mix(L.g, R.g, a, ia), .b = mix(L.b, R.b, a, ia), .a = 255 };
            t[s][k][p] = c.toRGBA();
        };
    }
    break :blk t;
};

fn mix(l: u8, r: u8, a: f64, ia: f64) u8 {
    const v: f64 = @as(f64, @floatFromInt(l)) * a + @as(f64, @floatFromInt(r)) * ia;
    return @intFromFloat(@round(v));
}

/// `raw` with every non-zero index moved up by `base` (0 stays the key).
fn shifted(comptime raw: []const u8, comptime base: u8) [raw.len]u8 {
    @setEvalBranchQuota(raw.len * 4);
    var out: [raw.len]u8 = undefined;
    for (raw, 0..) |v, i| out[i] = if (v == 0) 0 else v + base;
    return out;
}

pub const font_strip = shifted(@embedFile(DIR ++ "fonts.raw"), FONT);
pub const dragon_frames = [8][832]u8{
    shifted(@embedFile(DIR ++ "bob1.raw"), DRAGON), shifted(@embedFile(DIR ++ "bob2.raw"), DRAGON),
    shifted(@embedFile(DIR ++ "bob3.raw"), DRAGON), shifted(@embedFile(DIR ++ "bob4.raw"), DRAGON),
    shifted(@embedFile(DIR ++ "bob5.raw"), DRAGON), shifted(@embedFile(DIR ++ "bob6.raw"), DRAGON),
    shifted(@embedFile(DIR ++ "bob7.raw"), DRAGON), shifted(@embedFile(DIR ++ "bob8.raw"), DRAGON),
};
