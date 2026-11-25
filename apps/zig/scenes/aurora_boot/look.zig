// --------------------------------------------------------------------------
// AURORA BOOT: the star plane's colours and the wordmark. The plane has binary alpha, so what the lab
// blends (a star at alpha a over the sky) is an opaque palette ramp here: entries 1..15 are the star's
// levels, LINE the falcon's wire, WORD the name. Their colours are rewritten when their level changes
// (a palette write is ~free), and the global fade runs the machine's own TC_FADE rule over them so both
// planes reach black together. No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");
const plot = @import("plot.zig");

pub const LEVELS: u32 = 15;
pub const LINE: u8 = 16;
pub const WORD: u8 = 17;
pub const GLINT: u8 = 5; // the glint cross: the lab's alpha .35 of a full star is level 5 of 15

pub const Rgb = struct { r: u8, g: u8, b: u8 };
const NIGHT = Rgb{ .r = 8, .g = 12, .b = 24 }; // what a faint element fades from: the dark sky
const FLOOR = Rgb{ .r = 56, .g = 68, .b = 104 };
const STAR = Rgb{ .r = 225, .g = 236, .b = 255 };
const WIRE = Rgb{ .r = 150, .g = 215, .b = 255 }; // the lab's rgba(150,215,255,0.5 * level)
const INK = Rgb{ .r = 232, .g = 240, .b = 255 };

fn mix(a: u8, b: u8, num: u32, den: u32) u8 {
    return @intCast((@as(u32, a) * (den - num) + @as(u32, b) * num) / den);
}

fn toward(c: Rgb, num: u32, den: u32) Rgb {
    return .{ .r = mix(NIGHT.r, c.r, num, den), .g = mix(NIGHT.g, c.g, num, den), .b = mix(NIGHT.b, c.b, num, den) };
}

/// A star at level 1..15. The lab blends a faint star over what is behind it; an opaque entry cannot, and one
/// that starts at the dark sky's colour shows as a black speck over the bright aurora, so the ramp starts
/// at FLOOR (a dim blue-grey) instead.
pub fn star(level: u32) Rgb {
    const n = level -| 1;
    return .{ .r = mix(FLOOR.r, STAR.r, n, LEVELS - 1), .g = mix(FLOOR.g, STAR.g, n, LEVELS - 1), .b = mix(FLOOR.b, STAR.b, n, LEVELS - 1) };
}

/// The falcon's wire at baked level 0..15 (15 = the lab's alpha 0.5).
pub fn wire(level: u32) Rgb {
    return toward(WIRE, level, 2 * LEVELS);
}

pub fn ink(level: u32) Rgb {
    return toward(INK, level, LEVELS);
}

/// One channel through TC_FADE's formula toward black (docs/hardware/HW_API.md "True-colour fade").
pub fn fadeChannel(x: u8, c: u5) u8 {
    const w: u32 = @as(u32, c) + (c >> 4);
    return @intCast((@as(u32, x) * (32 - w) + 16) >> 5);
}

// The wordmark: KESTREL in wide capitals (a 5x7 grid, cells 4 x 3 pixels), one u8 a row, bit 4 = leftmost.
const K = [7]u8{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 };
const E = [7]u8{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 };
const S = [7]u8{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 };
const T = [7]u8{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 };
const R = [7]u8{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 };
const L = [7]u8{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 };
const WORDMARK = [7]*const [7]u8{ &K, &E, &S, &T, &R, &E, &L };
pub const CELL_W: i32 = 4;
pub const CELL_H: i32 = 3;
const ADVANCE: i32 = 5 * CELL_W + 6;
pub const X: i32 = 160 - (7 * ADVANCE - 6) / 2;
pub const Y: i32 = 162; // the lab centres the name at 0.86 of the height

/// Draws KESTREL into the star plane in palette entry WORD.
pub fn drawWord(plane: [*]u8) void {
    for (WORDMARK, 0..) |glyph, i| {
        const x0 = X + @as(i32, @intCast(i)) * ADVANCE;
        for (glyph, 0..) |bits, row| {
            for (0..5) |col| {
                if (bits & (@as(u8, 0x10) >> @intCast(col)) == 0) continue;
                plot.rect(plane, x0 + @as(i32, @intCast(col)) * CELL_W, Y + @as(i32, @intCast(row)) * CELL_H, CELL_W, CELL_H, WORD);
            }
        }
    }
}

test "the ramps run from the night sky to the full colour" {
    try std.testing.expectEqual(FLOOR, star(1));
    try std.testing.expectEqual(STAR, star(LEVELS));
    try std.testing.expect(wire(LEVELS).b < WIRE.b); // the wire tops out at half
    try std.testing.expectEqual(ink(LEVELS), INK);
}

test "the fade is the machine's rule: 0 = the colour, 31 = black" {
    try std.testing.expectEqual(@as(u8, 255), fadeChannel(255, 0));
    try std.testing.expectEqual(@as(u8, 0), fadeChannel(255, 31));
    try std.testing.expectEqual(@as(u8, 120), fadeChannel(255, 16));
}

test "the wordmark draws seven letters inside the plane, in the WORD entry" {
    var p = [_]u8{0} ** (320 * 200);
    drawWord(&p);
    var lit: u32 = 0;
    var min_x: usize = 320;
    var max_x: usize = 0;
    for (p, 0..) |v, i| {
        if (v != WORD) continue;
        lit += 1;
        min_x = @min(min_x, i % 320);
        max_x = @max(max_x, i % 320);
    }
    try std.testing.expect(lit > 500);
    try std.testing.expect(min_x >= 60 and max_x <= 260);
}
