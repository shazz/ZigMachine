// --------------------------------------------------------------------------
// The screen's art, halved from the CODEF PNGs by
// tools/private_tools/replicants_arkanoid2_assets.py, and the one operation
// every moving part needs: put bg.png back under a box.
//
// go() redraws bg.png over the whole canvas every frame. Here it is painted
// once and only the boxes that moved are copied back, from the embedded bg in
// cart RAM (zg.blit's .copy goes through CHISEL when the box is big enough).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

pub const W: usize = zg.WIDTH;
pub const H: usize = zg.HEIGHT;

const DIR = "../../assets/screens/replicants_arkanoid2/";

// align(4): CHISEL and word copies read these; never a misaligned load
const bg_b: [W * H]u8 align(4) = @embedFile(DIR ++ "bg.raw").*;
const bg2_b: [W * 16]u8 align(4) = @embedFile(DIR ++ "bg2.raw").*;
const font_b: [160 * 96]u8 align(4) = @embedFile(DIR ++ "font.raw").*;
const hofa_b: [60 * 15]u8 align(4) = @embedFile(DIR ++ "hofa.raw").*;
const shogun_b: [90 * 15]u8 align(4) = @embedFile(DIR ++ "shogun.raw").*;
const ateam_b: [90 * 15]u8 align(4) = @embedFile(DIR ++ "ateam.raw").*;

pub const palette = zg.convertU8ArraytoColors(@embedFile(DIR ++ "palette.dat"));

pub const bg = blit.Image.init(&bg_b, W);
/// bg2.png, the 'source-in' image laid over the scroll strip.
pub const bg2 = blit.Image.init(&bg2_b, W);
/// font.png: 10x6 glyphs of 16x16 from ' ', 1 = ink.
pub const font = blit.Image.init(&font_b, 160);
pub const hofa = blit.Image.init(&hofa_b, 60);
pub const shogun = blit.Image.init(&shogun_b, 90);
pub const ateam = blit.Image.init(&ateam_b, 90);

/// Copy bg back over the w x h box at signed (x, y), clipped to the screen.
pub fn restore(dst: blit.Dst, x: i32, y: i32, w: usize, h: usize) void {
    const x0: i32 = @max(x, 0);
    const y0: i32 = @max(y, 0);
    const x1: i32 = @min(x + @as(i32, @intCast(w)), @as(i32, W));
    const y1: i32 = @min(y + @as(i32, @intCast(h)), @as(i32, H));
    if (x1 <= x0 or y1 <= y0) return;
    const part = blit.Rect{
        .x = @intCast(x0),
        .y = @intCast(y0),
        .w = @intCast(x1 - x0),
        .h = @intCast(y1 - y0),
    };
    blit.blit(dst, bg, part, x0, y0, null, .copy);
}

comptime {
    // bg is opaque and black is index 0: the border (colour 0 on an ST) matches
    std.debug.assert(palette[0].r == 0 and palette[0].g == 0 and palette[0].b == 0 and palette[0].a == 255);
}
