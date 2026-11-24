// The capability word (HW 1.19.0, system table 1.28): which OPTIONAL units this machine has.
// docs/hardware/ABI_RULES.md is the contract; this file is the bit table.
//
// A cart that uses an optional unit asks first (`zg.caps.has(.astro)`) and falls back when the bit is
// clear. A bit is only ever ADDED (the next free one), never moved or reused.
// The word is the machine's: the browser and the native host report every unit they emulate, the board's
// firmware declares what its bitstream has (hwSetCaps). A bit the machine does not know reads 0.

pub const Cap = enum(u5) {
    /// ASTROLABE, the f64 coprocessor, is served by hardware (the board's ARM). Clear: hwAstro still
    /// answers, from ZIGGY's soft f64 (slow); a cart that can does its own f64 instead.
    astro = 0,
    /// The desk mode, RES_DESK 640x480 (HW 1.17.0). Mirrors hwDeskAvailable().
    desk = 1,
    /// CHISEL v2's ops: QUEUE, AFFINE, MAP, mirror, collision, area fill (HW 1.11.0).
    chisel_v2 = 2,
    /// A coprocessor serves hostBardJob (BARD on the board); clear: zg.bard.job runs the job in the cart.
    bard_jobs = 3,
    /// An f32 FPU on ZIGGY (the board's cart CPU has none unless the bitstream adds one).
    ziggy_fpu = 4,
    /// A second joystick reaches the cart's input2/inputRelease2 exports (otherwise merged into player 1).
    joy2 = 5,
};

/// The bits defined so far: the mask a host may set; everything else is dropped.
pub const ALL: u32 = (1 << 6) - 1;

pub fn bit(c: Cap) u32 {
    return @as(u32, 1) << @intFromEnum(c);
}

pub fn has(word: u32, c: Cap) bool {
    return word & bit(c) != 0;
}

const std = @import("std");

test "bit and has: every defined cap has its own bit inside ALL" {
    var seen: u32 = 0;
    inline for (@typeInfo(Cap).@"enum".fields) |f| {
        const c: Cap = @enumFromInt(f.value);
        try std.testing.expect(seen & bit(c) == 0);
        seen |= bit(c);
        try std.testing.expect(has(ALL, c));
        try std.testing.expect(!has(0, c));
    }
    try std.testing.expectEqual(ALL, seen);
}
