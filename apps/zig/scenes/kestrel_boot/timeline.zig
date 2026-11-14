// --------------------------------------------------------------------------
// KESTREL BOOT (WINDHOVER): the frame plan, 60 Hz frames from the cart's start.
// prototypes/boot_screen/STUDY.md §2 concept 1 has the storyboard this encodes.
// The fade coefficient follows the machine's TC_FADE: 0 = the picture, 31 = black.
// No ZigOS import: it tests natively (timeline_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const SKY_IN: u32 = 20; // the sky starts fading up (and the first call note)
pub const SKY_UP: u32 = 80; // ... and is fully up
pub const STOOP: u32 = 50; // the bird enters
pub const STOOP_FRAMES: u32 = 45;
pub const ARRIVE: u32 = STOOP + STOOP_FRAMES; // 95: the bird stops dead, the chord
pub const FLASH_FRAMES: u32 = 14; // the sky's flash after the arrival
pub const GLINT_FRAMES: u32 = 24; // the highlight running down the bird
pub const WORD: u32 = 108; // the first letter of the wordmark lights
pub const LETTER_STEP: u32 = 6; // ... and each next one this much later
pub const LETTER_FRAMES: u32 = 10; // a letter's own fade-in
pub const SUB: u32 = 150; // "ZIGMACHINE" under it
pub const FADE_OUT: u32 = 250; // the fade to black starts
pub const BLACK: u32 = 290; // ... and is complete: the black hold from here on
pub const SILENT: u32 = 260; // the YM is silent from here on

/// The fade coefficient (0..31, the TC_FADE rule) shared by both planes at frame `f`.
pub fn fade(f: u32) u5 {
    if (f < SKY_IN) return 31;
    if (f < SKY_UP) return @intCast(31 - (f - SKY_IN) * 31 / (SKY_UP - SKY_IN));
    if (f < FADE_OUT) return 0;
    if (f < BLACK) return @intCast((f - FADE_OUT) * 31 / (BLACK - FADE_OUT));
    return 31;
}

/// The sky's flash at the arrival: a positive offset on every channel, decaying to 0.
pub fn flash(f: u32) i8 {
    if (f < ARRIVE or f >= ARRIVE + FLASH_FRAMES) return 0;
    return @intCast((ARRIVE + FLASH_FRAMES - f) * 4);
}

/// One channel through the TC fade's formula (docs/HW_API.md "True-colour fade"), toward black.
pub fn fadeChannel(x: u8, c: u5) u8 {
    const w: u32 = @as(u32, c) + (c >> 4);
    return @intCast((@as(u32, x) * (32 - w) + 16) >> 5);
}

/// The stoop's ease: 0 .. ONE over STOOP_FRAMES, braking past the mark and settling back
/// ("ease out back", overshoot 1.2). Built at compile time and rounded, so the cart runs no
/// float; the last entry is exactly ONE, so the bird lands at exactly 1:1.
pub const ONE: i32 = 1 << 16;
pub const EASE: [STOOP_FRAMES + 1]i32 = blk: {
    @setEvalBranchQuota(10_000);
    var t: [STOOP_FRAMES + 1]i32 = undefined;
    const c1: f64 = 1.2;
    const c3: f64 = c1 + 1.0;
    for (&t, 0..) |*v, i| {
        const x = @as(f64, @floatFromInt(i)) / @as(f64, STOOP_FRAMES) - 1.0;
        v.* = @intFromFloat(@round((1.0 + c3 * x * x * x + c1 * x * x) * 65536.0));
    }
    t[0] = 0;
    t[STOOP_FRAMES] = ONE;
    break :blk t;
};

test "fade runs black, up, held, black" {
    try std.testing.expectEqual(@as(u5, 31), fade(0));
    try std.testing.expectEqual(@as(u5, 0), fade(SKY_UP));
    try std.testing.expectEqual(@as(u5, 0), fade(FADE_OUT - 1));
    try std.testing.expectEqual(@as(u5, 31), fade(BLACK));
    try std.testing.expectEqual(@as(u8, 0), fadeChannel(255, 31));
    try std.testing.expectEqual(@as(u8, 255), fadeChannel(255, 0));
}

test "ease starts at 0, overshoots, lands on ONE" {
    try std.testing.expectEqual(@as(i32, 0), EASE[0]);
    try std.testing.expectEqual(ONE, EASE[STOOP_FRAMES]);
    var peak: i32 = 0;
    for (EASE) |e| peak = @max(peak, e);
    try std.testing.expect(peak > ONE);
}
