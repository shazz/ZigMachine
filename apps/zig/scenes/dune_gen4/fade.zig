// DUNE.PRG's palette fade-in ($3CD2). Eight steps, d7 = 8 down to 1: every gun
// whose target is >= d7 goes up by one, so after s steps a gun stands at
// max(0, target - 8 + s). Each step waits 161 x 256 dbra loops and then copies
// the working palette to the registers; the true palette is written after the
// eighth, which already equals it.
//
// The step rate is MEASURED in Hatari (prototypes/dune_gen4_re/fadesteps.py on
// the frames of every fade-in), and it depends on what else interrupts the busy
// wait: a step every 3.12 VBLs before the main part (the dbra count alone, 161 x
// 256 at 12 cycles, says 3.09), but 3.5 to 3.75 for the title, the menu and F1,
// because the last part's Timer B is never stopped and keeps interrupting on
// every line -- and there the steps land a VBL earlier or later from one run to
// the next (two Hatari runs, frame by frame), so one rate, 3.6, stands for them.
// The phase is where the first step lands in its VBL.
const std = @import("std");

pub const STEPS: u32 = 8;

pub const Rate = struct {
    step_x100: u32, // VBLs a step, x100
    phase_x100: u32,

    /// VBLs from the fade's start to the true palette.
    pub fn frames(comptime r: Rate) u32 {
        return (r.phase_x100 + STEPS * r.step_x100 + 99) / 100;
    }
};

/// Before the main part: nothing but the VBL interrupts the wait.
pub const MAIN = Rate{ .step_x100 = 312, .phase_x100 = 26 };
/// The title, the menu and F1 (a part's Timer B still running).
pub const SCREEN = Rate{ .step_x100 = 360, .phase_x100 = 30 };

/// The registers `n` VBLs after the fade started.
pub fn at(target: *const [16]u16, n: u32, comptime r: Rate) [16]u16 {
    const t = n * 100;
    if (t < r.phase_x100) return [_]u16{0} ** 16;
    const s: u16 = @intCast(@min(STEPS, (t - r.phase_x100) / r.step_x100)); // steps shown
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
    for (at(&target, 0, MAIN)) |c| try std.testing.expectEqual(@as(u16, 0), c);
    // seven steps (frame 23: 2274 / 312): a 7 is 6, a 3 is 2, a 1 still 0
    const seven = at(&target, 23, MAIN);
    try std.testing.expectEqual(@as(u16, 0x666), seven[0]);
    try std.testing.expectEqual(@as(u16, 0x600), seven[1]);
    try std.testing.expectEqual(@as(u16, 0x012), seven[4]);
    try std.testing.expectEqual(target, at(&target, MAIN.frames(), MAIN));
    try std.testing.expect(!std.meta.eql(target, at(&target, MAIN.frames() - 1, MAIN)));
}

test "the fades end when Hatari shows the true palette" {
    try std.testing.expectEqual(@as(u32, 26), MAIN.frames());
    try std.testing.expectEqual(@as(u32, 30), SCREEN.frames());
}
