// DUNE.PRG's palette fade-in ($3CD2), bug and all. Eight steps, d7 = 8 down to
// 1: every gun whose target is >= d7 goes up by one, so after s steps a gun
// stands at max(0, target - 8 + s). Each step waits 160 x 256 dbra loops
// (about 2.56 VBLs) and then copies the working palette to the registers --
// from $11A8, ONE WORD BEFORE it ($11AA): colour 0 gets a zero and colour n gets
// the working colour n-1 for the whole fade. Only after the eighth step is the
// true palette written. So every fade-in in the demo starts on the wrong colours
// and snaps right at the end; it is reproduced, not fixed.
const std = @import("std");

/// One step's delay in hundredths of a VBL: 160 x 256 dbra at 10 cycles, on a
/// 160256-cycle frame.
const STEP_X100: u32 = 256;
pub const STEPS: u32 = 8;
/// VBLs from the first step to the true palette.
pub const FRAMES: u32 = (STEPS * STEP_X100 + 99) / 100; // 21

/// The registers `n` VBLs into a fade towards `target`.
pub fn at(target: *const [16]u16, n: u32) [16]u16 {
    if (n * 100 >= STEPS * STEP_X100) return target.*;
    const s: u16 = @intCast(n * 100 / STEP_X100); // steps already shown
    var work: [16]u16 = undefined;
    for (&work, target) |*w, t| w.* = gun(t, 8, s) | gun(t, 4, s) | gun(t, 0, s);
    var out: [16]u16 = undefined;
    out[0] = 0;
    for (1..16) |i| out[i] = work[i - 1];
    return out;
}

fn gun(t: u16, comptime shift: u4, s: u16) u16 {
    const v = (t >> shift) & 7;
    const up = (v + s) -| 8;
    return up << shift;
}

test "the fade is black first, shifted by one entry, then exact" {
    const target = [16]u16{ 0x777, 0x700, 0x070, 0x007, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x123 };
    const first = at(&target, 0);
    for (first) |c| try std.testing.expectEqual(@as(u16, 0), c);
    // after 7 steps a 7 is 6, and it shows one entry to the right
    const seven = at(&target, 18);
    try std.testing.expectEqual(@as(u16, 0), seven[0]);
    try std.testing.expectEqual(@as(u16, 0x666), seven[1]);
    try std.testing.expectEqual(@as(u16, 0x600), seven[2]);
    try std.testing.expectEqual(target, at(&target, FRAMES));
}
