// --------------------------------------------------------------------------
// AURORA BOOT: the star plane's colours. Entries 1..15 are the star's levels (an opaque
// ramp), LINE the falcon's wire, WORD the name, WORD_BASE..255 the baked script name: those keep their full colour and fade in by the palette
// ALPHA (FRESCO blends a partial alpha over the planes below), as the lab's rgba strokes do, so a faint line
// is the aurora under it tinted toward the colour, never darker than it (an opaque ramp from the night sky
// drew the wire BLACK over the bright aurora before it turned white: Matt, 25 Nov). Their colours are rewritten when their level changes
// (a palette write is ~free), and the global fade runs the machine's own TC_FADE rule over them so both
// planes reach black together. No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const LEVELS: u32 = 15;
pub const LINE: u8 = 16;
pub const WORD: u8 = 17;
pub const WORD_BASE: u8 = 128; // entries 128..255 are the baked script name, ink at alpha = coverage (word.bin)

pub const Rgb = struct { r: u8, g: u8, b: u8 };
const FLOOR = Rgb{ .r = 56, .g = 68, .b = 104 };
const STAR = Rgb{ .r = 225, .g = 236, .b = 255 };
const WIRE = Rgb{ .r = 150, .g = 215, .b = 255 }; // the lab's rgba(150,215,255,0.5 * level)
const INK = Rgb{ .r = 232, .g = 240, .b = 255 };

fn mix(a: u8, b: u8, num: u32, den: u32) u8 {
    return @intCast((@as(u32, a) * (den - num) + @as(u32, b) * num) / den);
}

/// A star at level 1..15. The lab blends a faint star over what is behind it; an opaque entry cannot, and one
/// that starts at the dark sky's colour shows as a black speck over the bright aurora, so the ramp starts
/// at FLOOR (a dim blue-grey) instead.
pub fn star(level: u32) Rgb {
    const n = level -| 1;
    return .{ .r = mix(FLOOR.r, STAR.r, n, LEVELS - 1), .g = mix(FLOOR.g, STAR.g, n, LEVELS - 1), .b = mix(FLOOR.b, STAR.b, n, LEVELS - 1) };
}

/// A colour and its palette alpha (0 = invisible, 255 = opaque).
pub const Rgba = struct { rgb: Rgb, a: u8 };

/// The falcon's wire at baked level 0..15: WIRE at the lab's alpha 0.5 * level / 15.
pub fn wire(level: u32) Rgba {
    return .{ .rgb = WIRE, .a = @intCast(@as(u32, @min(level, LEVELS)) * 255 / (2 * LEVELS)) };
}

/// The name at level 0..15: INK at alpha level / 15.
pub fn ink(level: u32) Rgba {
    return .{ .rgb = INK, .a = @intCast(@as(u32, @min(level, LEVELS)) * 255 / LEVELS) };
}

/// The baked name: palette entry WORD_BASE + k holds coverage ~2k; at name level 0..15 its alpha is
/// coverage * level / 15, so the word fades in as a whole, anti-aliased edges included.
pub fn wordAlpha(entry: u8, level: u32) u8 {
    const cov: u32 = @as(u32, entry - WORD_BASE) * 255 / 127;
    return @intCast(cov * @as(u32, @min(level, LEVELS)) / LEVELS);
}

/// One channel through TC_FADE's formula toward black (docs/hardware/HW_API.md "True-colour fade").
pub fn fadeChannel(x: u8, c: u5) u8 {
    const w: u32 = @as(u32, c) + (c >> 4);
    return @intCast((@as(u32, x) * (32 - w) + 16) >> 5);
}

test "the star ramp runs from FLOOR to the full colour" {
    try std.testing.expectEqual(FLOOR, star(1));
    try std.testing.expectEqual(STAR, star(LEVELS));
    try std.testing.expectEqual(@as(u8, 127), wire(LEVELS).a); // the wire tops out at half
    try std.testing.expectEqual(@as(u8, 255), ink(LEVELS).a);
}

test "the wire and the name fade in by alpha, never from a dark colour" {
    try std.testing.expectEqual(@as(u8, 0), wire(0).a);
    try std.testing.expectEqual(@as(u8, 0), ink(0).a);
    var lv: u32 = 0;
    while (lv <= LEVELS) : (lv += 1) {
        try std.testing.expectEqual(WIRE, wire(lv).rgb);
        try std.testing.expectEqual(INK, ink(lv).rgb);
        if (lv > 0) try std.testing.expect(wire(lv).a > wire(lv - 1).a);
    }
}

test "the baked name's alpha is its coverage scaled by the level" {
    try std.testing.expectEqual(@as(u8, 255), wordAlpha(255, LEVELS));
    try std.testing.expectEqual(@as(u8, 0), wordAlpha(255, 0));
    try std.testing.expectEqual(@as(u8, 0), wordAlpha(WORD_BASE, LEVELS));
    try std.testing.expect(wordAlpha(200, 8) < wordAlpha(200, 9));
}

test "the fade is the machine's rule: 0 = the colour, 31 = black" {
    try std.testing.expectEqual(@as(u8, 255), fadeChannel(255, 0));
    try std.testing.expectEqual(@as(u8, 0), fadeChannel(255, 31));
    try std.testing.expectEqual(@as(u8, 120), fadeChannel(255, 16));
}
