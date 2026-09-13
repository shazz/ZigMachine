// --------------------------------------------------------------------------
// TEX LOADER: the Union Demo's loader screen, as a depack effect (zx0.Fx.tex_loader).
//
// Source: shazz's melonJS remake, Union-Demo-HTML5-Remake-0.9.8/loader.js (the
// TEXLoader base class) with its panels in menuloader.js and screens/*/loader.js.
// On a black 640x400 canvas, a panel of text rows in the 16x16 loader.png font
// assembles letter by letter: each letter flies up from y 500 to its cell in
// 50 ms, letter k starting at 30*k ms, column by column (left to right) and,
// inside a column, from the bottom row up. The last letter lands at
// 30*(n-1) + 50 ms. Cell centres (resetScroller, the one onResetEvent runs):
// x = 168 + 16*col, y = 376 - 16*rows_below, drawn from the centre (midhandle).
//
// Halved to the 320x200 window: 8x8 cells, top-left x = 80 + 8*col, the bottom
// row's top at y 184, the flight starting at top y 246 (below the window). The
// font is loader.png halved: its glyphs are pixel-doubled, 12 of them on an odd
// row or column phase, so each is sampled at its own phase and loses no pixel
// (tex_loader/loader.raw, 80x48, one 0/1 byte a pixel; packed to 480 bytes of
// rows here). Ink is the PNG's one colour, #C0A000.
//
// Driven by the depack, not a clock: the JS advanced its tweens 140 ms a frame
// (createjs.Tween.tick(140)); here the tween clock is written/total of the way
// through the timeline, so the last letter lands with the last byte.
// --------------------------------------------------------------------------
const std = @import("std");
const zx0 = @import("zx0.zig");

pub const GLYPH = 8;
pub const LETTER_WAIT_MS = 30;
pub const FLIGHT_MS = 50;
pub const LEFT = 80;
pub const BOTTOM_TOP = 184;
pub const START_TOP = 246;
pub const INK = struct { pub const r = 0xC0; pub const g = 0xA0; pub const b = 0x00; };

const GLYPHS = zx0.PANEL_LAST_CHAR - zx0.PANEL_FIRST_CHAR + 1;

/// 60 glyphs of 8 rows, bit 7 = leftmost pixel.
pub const font: [GLYPHS][GLYPH]u8 = blk: {
    const raw = @embedFile("tex_loader/loader.raw");
    if (raw.len != 10 * GLYPH * 6 * GLYPH) @compileError("loader.raw is not 80x48");
    @setEvalBranchQuota(4 * raw.len + 1000);
    var f: [GLYPHS][GLYPH]u8 = undefined;
    for (0..GLYPHS) |g| for (0..GLYPH) |y| {
        var row: u8 = 0;
        for (0..GLYPH) |x| {
            const p = raw[((g / 10) * GLYPH + y) * 10 * GLYPH + (g % 10) * GLYPH + x];
            if (p > 1) @compileError("loader.raw pixel is not 0 or 1");
            row |= @as(u8, p) << @intCast(7 - x);
        }
        f[g][y] = row;
    };
    break :blk f;
};

/// The ms at which the last of `letters` letters lands.
pub fn timelineEnd(letters: u32) u32 {
    return if (letters == 0) 0 else (letters - 1) * LETTER_WAIT_MS + FLIGHT_MS;
}

/// The tween clock, in ms, after `written` of `total` bytes.
pub fn clock(written: u32, total: u32, letters: u32) u32 {
    const end = timelineEnd(letters);
    if (total == 0 or written >= total) return end;
    return @intCast(@as(u64, written) * end / total);
}

/// Letter `num`'s top row at clock `t`: at START_TOP until it starts, then a
/// linear 50 ms flight to its cell `below` rows above the bottom one.
pub fn letterTop(num: u32, below: u32, t: u32) i32 {
    const start = num * LETTER_WAIT_MS;
    const target: i32 = BOTTOM_TOP - @as(i32, @intCast(below * GLYPH));
    if (t <= start) return START_TOP;
    if (t >= start + FLIGHT_MS) return target;
    const k: i32 = @intCast(t - start);
    return START_TOP + @divTrunc((target - START_TOP) * k, FLIGHT_MS);
}

/// One frame: clear the plane, then every letter at clock `t`, placed in the
/// 320x200 window centred on the plane and clipped to it, in palette `ink`.
pub fn draw(fb: anytype, chars: []const u8, cols: u8, t: u32, ink: u8) void {
    const w: usize = fb.fb_w;
    const h: usize = fb.fb_h;
    @memset(fb.fb[0 .. @as(usize, fb.stride) * h], 0);
    const rows = chars.len / cols;
    const ox = (w - 320) / 2;
    const oy = (h - 200) / 2;
    for (0..cols) |col| for (0..rows) |below| {
        const num: u32 = @intCast(col * rows + below);
        const c = chars[(rows - 1 - below) * cols + col];
        const top = letterTop(num, @intCast(below), t);
        const x = ox + LEFT + col * GLYPH;
        for (font[c - zx0.PANEL_FIRST_CHAR], 0..) |bits, gy| {
            const y = top + @as(i32, @intCast(gy));
            if (y < 0 or y >= 200 or bits == 0) continue;
            const line = fb.fb[(oy + @as(usize, @intCast(y))) * fb.stride + x ..][0..GLYPH];
            for (line, 0..) |*p, gx| if (bits >> @intCast(7 - gx) & 1 == 1) {
                p.* = ink;
            };
        }
    };
}

test "the font keeps loader.png's glyphs: 'A', '!' and '7' halved" {
    try std.testing.expectEqualSlices(u8, &.{ 0x3C, 0x24, 0x24, 0x7E, 0x66, 0x6E, 0x6E, 0x00 }, &font['A' - 0x20]);
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00 }, &font['!' - 0x20]);
    try std.testing.expectEqualSlices(u8, &.{ 0xFE, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00 }, &font['7' - 0x20]);
    try std.testing.expectEqual([_]u8{0} ** GLYPH, font[0]); // space
}

test "the timeline: letter k starts at 30k ms, flies 50 ms, and the clock ends on the last byte" {
    try std.testing.expectEqual(@as(u32, 13_820), timelineEnd(460));
    try std.testing.expectEqual(@as(u32, 0), clock(0, 1000, 460));
    try std.testing.expectEqual(@as(u32, 6_910), clock(500, 1000, 460));
    try std.testing.expectEqual(@as(u32, 13_819), clock(999_999, 1_000_000, 460)); // not landed one byte short
    try std.testing.expectEqual(@as(u32, 13_820), clock(1000, 1000, 460));
    try std.testing.expectEqual(timelineEnd(460), clock(0, 0, 460)); // an empty asset shows the panel
    // letter 3 (column 0, 4th row from the bottom) at 90 ms: not yet; 115 ms: half way; 140: landed
    try std.testing.expectEqual(@as(i32, START_TOP), letterTop(3, 3, 90));
    try std.testing.expectEqual(@as(i32, START_TOP + @divTrunc((160 - START_TOP) * 25, 50)), letterTop(3, 3, 115));
    try std.testing.expectEqual(@as(i32, 160), letterTop(3, 3, 140));
    // 23 rows: the top row lands at y 8, as the JS's 376 - 16*22 - 8 halved
    try std.testing.expectEqual(@as(i32, 8), letterTop(22, 22, 10_000));
}
