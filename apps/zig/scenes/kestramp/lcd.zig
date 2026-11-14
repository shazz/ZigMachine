// --------------------------------------------------------------------------
// KESTRAMP: the LCD parts of the window. The time is seven-segment digits
// (lit segments bright, the rest a dim ghost); the title scrolls in its box
// by whole pixels; the rate and stereo line sits under it. Integers only.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Clip = zg.Clip;

pub const LCD_BG: u8 = 10;
pub const LIT: u8 = 2;
pub const GHOST: u8 = 3;
pub const TIME_X: i32 = 6;
pub const TIME_Y: i32 = 14;
pub const TIME_W: usize = 93;
pub const TIME_H: usize = 27;
pub const TITLE_X0: i16 = 102; // the title box as the clip wants it: exclusive right and bottom
pub const TITLE_Y0: i16 = 14;
pub const TITLE_X1: i16 = TITLE_X0 + 210;
pub const TITLE_Y1: i16 = TITLE_Y0 + 11;
pub const TITLE_X: i32 = TITLE_X0;
pub const TITLE_Y: i32 = TITLE_Y0;
pub const TITLE_W: usize = 210;
pub const TITLE_H: usize = 11;
pub const INFO_Y: i32 = 27;

const DIGIT_Y: i32 = 17;
const GAP_PX: i16 = 24; // between two copies of a scrolling title
// Segment bits: a=1 b=2 c=4 d=8 e=16 f=32 g=64.
const DIGITS = [10]u8{ 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F };
// Each segment's rectangle inside a 14 x 21 digit cell: x, y, w, h.
const SEG_RECT = [7][4]i32{
    .{ 2, 0, 10, 2 }, // a
    .{ 12, 2, 2, 9 }, // b
    .{ 12, 11, 2, 9 }, // c
    .{ 2, 19, 10, 2 }, // d
    .{ 0, 11, 2, 9 }, // e
    .{ 0, 2, 2, 9 }, // f
    .{ 2, 10, 10, 2 }, // g
};

/// The elapsed time as mm:ss in the time box (minutes past 99 clamp).
pub fn drawTime(fb: *LogicalFB, secs: u32) void {
    fb.fillRect(TIME_X, TIME_Y, TIME_W, TIME_H, LCD_BG);
    const mm = @min(secs / 60, 99);
    const ss = secs % 60;
    const v = [4]u32{ mm / 10, mm % 10, ss / 10, ss % 10 };
    const xs = [4]i32{ 10, 28, 52, 70 };
    for (v, xs) |d, x| digit(fb, x, DIGIT_Y, d);
    fb.fillRect(46, 22, 3, 3, LIT);
    fb.fillRect(46, 30, 3, 3, LIT);
}

fn digit(fb: *LogicalFB, x0: i32, y0: i32, v: u32) void {
    const lit = DIGITS[v];
    for (SEG_RECT, 0..) |r, k| {
        const on = lit & (@as(u8, 1) << @intCast(k)) != 0;
        fb.fillRect(x0 + r[0], y0 + r[1], @intCast(r[2]), @intCast(r[3]), if (on) LIT else GHOST);
    }
}

/// The title in its box, scrolled left by `px` (wrapping) when it is wider than the box.
pub fn drawTitle(os: *ZigOS, fb: *LogicalFB, title: []const u8, px: u32) void {
    fb.fillRect(TITLE_X, TITLE_Y, TITLE_W, TITLE_H, LCD_BG);
    const clip = Clip{ .x0 = TITLE_X0, .y0 = TITLE_Y0, .x1 = TITLE_X1, .y1 = TITLE_Y1 };
    const text_w: i16 = @intCast(title.len * 8);
    const y: i16 = TITLE_Y0 + 1;
    if (text_w <= @as(i16, TITLE_W)) return os.printTextClipped(fb, title, TITLE_X0, y, LIT, LCD_BG, clip);
    const period: i16 = text_w + GAP_PX;
    const off: i16 = @intCast(px % @as(u32, @intCast(period)));
    var x: i16 = TITLE_X0 - off;
    while (x < TITLE_X1) : (x += period) os.printTextClipped(fb, title, x, y, LIT, LCD_BG, clip);
}

/// "44.1 KHZ STEREO" (rate in tenths of a kHz; 0 is nothing playing) under the title.
pub fn drawInfo(os: *ZigOS, fb: *LogicalFB, rate: u32, stereo: bool) void {
    fb.fillRect(TITLE_X, INFO_Y, TITLE_W, 9, LCD_BG);
    if (rate == 0) return;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}.{d} KHZ {s}", .{ rate / 10, rate % 10, if (stereo) "STEREO" else "MONO" }) catch return;
    os.printText(fb, s, TITLE_X0, @intCast(INFO_Y + 1), LIT, LCD_BG);
}
