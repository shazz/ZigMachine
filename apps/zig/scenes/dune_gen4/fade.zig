// DUNE.PRG's palette fade-in ($3CD2). Eight steps, d7 = 8 down to 1: every gun
// whose target is >= d7 goes up by one, so after s steps a gun stands at
// max(0, target - 8 + s). Each step waits 161 x 256 dbra loops and then copies
// the working palette to the registers; the true palette is written after the
// eighth, which already equals it.
//
// The step rate is MEASURED in Hatari (the frames of the main part's fade-in,
// prototypes/dune_gen4_re/fadesteps.py): a step every 3.12 VBLs -- the dbra
// count alone (161 x 256 at 12 cycles) says 3.09 -- and the first lands 0.26
// VBL into the VBL the fade starts in.
const std = @import("std");

const STEP_X100: u32 = 312;
const PHASE_X100: u32 = 26;
pub const STEPS: u32 = 8;
/// VBLs from the fade's start to the true palette.
pub const FRAMES: u32 = (PHASE_X100 + STEPS * STEP_X100 + 99) / 100; // 26

/// The registers `n` VBLs after the fade started.
pub fn at(target: *const [16]u16, n: u32) [16]u16 {
    const t = n * 100;
    if (t < PHASE_X100) return [_]u16{0} ** 16;
    const s: u16 = @intCast(@min(STEPS, (t - PHASE_X100) / STEP_X100)); // steps shown
    var out: [16]u16 = undefined;
    for (&out, target) |*w, c| w.* = gun(c, 8, s) | gun(c, 4, s) | gun(c, 0, s);
    return out;
}

fn gun(t: u16, comptime shift: u4, s: u16) u16 {
    const v = (t >> shift) & 7;
    const up = (v + s) -| 8;
    return up << shift;
}

test "the fade raises the brightest guns first and ends on the palette" {
    const target = [16]u16{ 0x777, 0x700, 0x070, 0x007, 0x123, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x765 };
    for (at(&target, 0)) |c| try std.testing.expectEqual(@as(u16, 0), c);
    // seven steps (frame 23: 2274 / 312): a 7 is 6, a 3 is 2, a 1 still 0
    const seven = at(&target, 23);
    try std.testing.expectEqual(@as(u16, 0x666), seven[0]);
    try std.testing.expectEqual(@as(u16, 0x600), seven[1]);
    try std.testing.expectEqual(@as(u16, 0x012), seven[4]);
    try std.testing.expectEqual(target, at(&target, FRAMES));
    try std.testing.expect(!std.meta.eql(target, at(&target, FRAMES - 1)));
}
