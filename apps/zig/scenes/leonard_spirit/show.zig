// --------------------------------------------------------------------------
// The choreography (Matt, 2026-10-24), as compile-time tables:
//
//   0 .. 179     a normal screen: borders closed, the background still
//   180 ..       the borders open one stage at a time, each with an on/off
//                shake that speeds up until the border stays open: the SIDES
//                (left and right together: the machine opens both from one
//                flicker on a visible line), then the BOTTOM, then the TOP
//   OPEN_END ..  the hardware scroll starts slowly and eases in to cruise
//   CRUISE ..    cruise for good: the picture loops every 360 frames
// Until the scroll starts only Leonard's 312 balls fly (one snake); then
// the other snakes fade in under the record's (fadeLevel, fadeRows).
//
// A closed frame is a real closed border: the plane's HBL does not flicker
// the resolution on that line (scene: borderHbl). The balls fly the whole
// 400x280 path from frame 0; the closed borders hide what is behind them, so
// their area grows as each side opens.
// --------------------------------------------------------------------------
const std = @import("std");
const path = @import("path.zig");

pub const STATIC_END = 180;
pub const GAP = 30; // frames between two stages
/// One stage's shake: the border toggles at the end of each interval, then
/// stays open: closed for 30 frames, open 24, closed 19 ... the last
/// (1-frame, open) interval runs into for good. Even count, so it ends open.
pub const SHAKE = [_]u32{ 30, 24, 19, 15, 12, 9, 7, 5, 4, 3, 2, 2, 1, 1, 1, 1 };
pub const SHAKE_LEN: u32 = blk: {
    var n: u32 = 0;
    for (SHAKE) |d| n += d;
    break :blk n; // 137
};
pub const Side = enum(u2) { sides = 0, bottom = 1, top = 2 };
pub fn stageStart(s: Side) u32 {
    return STATIC_END + @as(u32, @intFromEnum(s)) * (SHAKE_LEN + GAP);
}
pub const OPEN_END = stageStart(.top) + SHAKE_LEN; // every border open from here
pub const EASE_START = OPEN_END + GAP;
pub const EASE_LEN = 240; // frames from still to cruise
pub const CRUISE = EASE_START + EASE_LEN;
/// The record's 312 balls alone until the scroll starts; then the other
/// snakes fade in, FADE_LEVELS steps FADE_STEP frames apart (~2 s at 60 fps).
/// Matt, 6 Nov: from BLACK (the first cut) they did not fade, they popped:
/// 1,872 near-black balls over a bright picture show at once. A palette
/// can't blend a ball into the four picture colours under it, so the fade
/// is the ST's other one, a DISSOLVE: level n draws n of the ball's 16 rows
/// (fadeRows, the picture shows through the others), and their colours run
/// from the picture's main blue to the ball's (the scene's setFade).
pub const FADE_START = EASE_START;
pub const FADE_STEP = 8;
pub const FADE_LEVELS = 16;
/// The order the rows come in: bit-reversed, so each level adds one row
/// spread as evenly as the ones before allow.
pub const ROW_ORDER = [16]u4{ 0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15 };

/// The rows a fading ball draws at `level` (bit r = row r): the first
/// `level` of ROW_ORDER.
pub fn fadeRows(level: u32) u32 {
    return ROWS_AT[@min(level, FADE_LEVELS)];
}
const ROWS_AT = blk: {
    var t = [_]u32{0} ** (FADE_LEVELS + 1);
    for (1..FADE_LEVELS + 1) |n| t[n] = t[n - 1] | @as(u32, 1) << ROW_ORDER[n - 1];
    break :blk t;
};

/// The extra snakes' brightness on frame t, 0 (not drawn) .. FADE_LEVELS.
pub fn fadeLevel(t: u32) u32 {
    if (t < FADE_START) return 0;
    return @min(FADE_LEVELS, (t - FADE_START) / FADE_STEP + 1);
}

/// Is side s open on frame t?
pub fn isOpen(s: Side, t: u32) bool {
    const t0 = stageStart(s);
    if (t < t0) return false;
    var at: u32 = t0;
    var open = false;
    for (SHAKE) |d| {
        if (t < at + d) return open;
        at += d;
        open = !open;
    }
    return true;
}

/// The open borders of frame t: bit 0 sides, 1 bottom, 2 top.
pub fn openMask(t: u32) u8 {
    if (t >= OPEN_END) return 7;
    var m: u8 = 0;
    inline for (.{ Side.sides, Side.bottom, Side.top }) |s| {
        if (isOpen(s, t)) m |= @as(u8, 1) << @intFromEnum(s);
    }
    return m;
}

/// The scroll's speed on frame t, Q16 path frames per frame: 0 until
/// EASE_START, then (n / EASE_LEN)^2 (an ease-in), then 1.
pub fn scrollSpeed(t: u32) u32 {
    if (t < EASE_START) return 0;
    if (t >= CRUISE) return 1 << 16;
    const n: u64 = t - EASE_START;
    return @intCast((n * n << 16) / (EASE_LEN * EASE_LEN));
}

/// The scroll phase (Q16 path frames, mod 360) after frame t's step.
pub fn stepPhase(phase: u32, t: u32) u32 {
    const p = phase + scrollSpeed(t);
    return if (p >= path.PERIOD << 16) p - (path.PERIOD << 16) else p;
}
