// zg.bard.fm's local rules (bard_fm.zig): which channel a register is for (the device's own rule,
// libs/c/vgm/zm_vgm_own.c; apps/harness/fm_sfx_check.mjs holds the device to it) and the mask bits.
const std = @import("std");
const fm = @import("bard_fm.zig");

test "a register belongs to its channel; 0x28 by its value; the DAC is FM 6's; globals are the tune's" {
    try std.testing.expectEqual(@as(u32, 0), fm.ymOwner(0, 0x30, 0));
    try std.testing.expectEqual(@as(u32, 5), fm.ymOwner(1, 0xA2, 0));
    try std.testing.expectEqual(@as(u32, 4), fm.ymOwner(1, 0xB5, 0));
    try std.testing.expectEqual(@as(u32, 5), fm.ymOwner(0, 0x28, 0xF6));
    try std.testing.expectEqual(@as(u32, 2), fm.ymOwner(0, 0x28, 0x02));
    try std.testing.expectEqual(@as(u32, 5), fm.ymOwner(0, 0x2B, 0x80));
    try std.testing.expectEqual(fm.OWNER_TUNE, fm.ymOwner(0, 0x22, 8));
    try std.testing.expectEqual(fm.OWNER_TUNE, fm.ymOwner(0, 0x27, 0));
}

test "no register, or one the cart can never own, has no owner" {
    try std.testing.expectEqual(fm.OWNER_NOBODY, fm.ymOwner(0, 0x33, 0)); // slot 3: no channel
    try std.testing.expectEqual(fm.OWNER_NOBODY, fm.ymOwner(1, 0x28, 0xF6)); // key-on is port 0 only
    try std.testing.expectEqual(fm.OWNER_NOBODY, fm.ymOwner(0, 0x28, 0x03));
    try std.testing.expectEqual(fm.OWNER_NOBODY, fm.ymOwner(0, 0xA9, 0)); // channel 3's special frequencies
    try std.testing.expectEqual(fm.OWNER_NOBODY, fm.ymOwner(0, 0xB8, 0));
    try std.testing.expectEqual(fm.OWNER_NOBODY, fm.ymOwner(1, 0x22, 0));
}

test "the default effects mask is FM 5-6, PSG tone 3 and the noise, inside OWNABLE" {
    try std.testing.expectEqual(fm.fmBit(4) | fm.fmBit(5) | fm.psgBit(2) | fm.psgBit(3), fm.SFX_DEFAULT);
    try std.testing.expectEqual(@as(u32, 0), fm.SFX_DEFAULT & ~fm.OWNABLE);
}
