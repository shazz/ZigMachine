// The simulated glass keeps the RTL's rules (rtl/glass/zm_glass_regs.v).
const std = @import("std");
const map = @import("map.zig");
const Glass = @import("sim.zig").Glass;

test "the simulated block keeps the RTL's rules" {
    var g = Glass{};
    const r = g.regs();
    try std.testing.expectEqual(map.ID_VALUE, r.read(map.REG_ID));
    try std.testing.expectEqual(@as(u32, 0), r.read(map.REG_STATUS) & map.ST_RUNNING);
    for (0..map.KEY_DEPTH + 1) |i| r.write(map.REG_KEY_PUSH, @intCast(i));
    try std.testing.expect(r.read(map.REG_STATUS) & map.ST_KEY_OVERFLOW != 0);
    try std.testing.expectEqual(@as(?u32, 0), g.pop());
    r.write(map.REG_CTRL, map.CTRL_KEY_FLUSH);
    try std.testing.expectEqual(@as(u32, 0), r.read(map.REG_KEY_LEVEL));
    try std.testing.expectEqual(@as(u32, 0), r.read(map.REG_CTRL));
    r.write(map.REG_CTRL, map.CTRL_RUN);
    try std.testing.expectEqual(map.CART_BOOTING, r.read(map.REG_CART_STATE));
}

test "AUDIO_VOL keeps volume and mute; a warm boot needs marked memory" {
    var g = Glass{};
    const r = g.regs();
    try std.testing.expectEqual(map.AUDIO_VOL_RESET, r.read(map.REG_AUDIO_VOL));
    r.write(map.REG_AUDIO_VOL, 0xFFFF_FFFF);
    try std.testing.expectEqual(map.AUDIO_MUTE | map.AUDIO_VOL_MASK, r.read(map.REG_AUDIO_VOL));
    r.write(map.REG_CTRL, map.CTRL_RUN | map.CTRL_WARM); // warm, nothing ever marked
    for (0..3) |_| _ = r.read(map.REG_CART_STATE);
    try std.testing.expectEqual(map.CART_TRAPPED | map.TRAP_WARM_LOST << map.CART_ARG_SHIFT, r.read(map.REG_CART_STATE));
    r.write(map.REG_CTRL, map.CTRL_RUN); // cold: boots and marks
    for (0..3) |_| _ = r.read(map.REG_CART_STATE);
    try std.testing.expectEqual(map.CART_RUNNING, r.read(map.REG_CART_STATE) & map.CART_STATE_MASK);
    r.write(map.REG_CTRL, 0);
    r.write(map.REG_CTRL, map.CTRL_RUN | map.CTRL_WARM);
    for (0..3) |_| _ = r.read(map.REG_CART_STATE);
    try std.testing.expectEqual(@as(u32, 1), g.warm_boots);
}
