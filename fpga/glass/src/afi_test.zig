// The W64 switch's two halves: HP1's AFI width (afi.zig) and the firmware's word (loader.zig).
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const afi = @import("afi.zig");
const mc = @import("map_cart.zig");

test "the width follows --fw-opt, and a run without it goes back to 32-bit writes" {
    try std.testing.expectEqual(@as(?u32, null), try afi.want(mc.FW_OPT_W64, afi.WR64));
    try std.testing.expectEqual(@as(?u32, afi.WR32), try afi.want(mc.FW_OPT_PLANE_MAJOR, afi.WR64));
    try std.testing.expectEqual(@as(?u32, afi.WR32), try afi.want(null, afi.WR64));
    try std.testing.expectEqual(@as(?u32, null), try afi.want(null, afi.WR32));
}

test "W64 on a channel that is 32-bit now is refused, never switched 32 -> 64 at run time" {
    try std.testing.expectError(error.W64NeedsBoot, afi.want(mc.FW_OPT_W64, afi.WR32));
    var glass = sim.Glass{};
    glass.ctrl = map.CTRL_RUN;
    var a = Afi{};
    a.words[afi.WRCHAN_CTRL / 4] = afi.WR32;
    try std.testing.expectError(error.W64NeedsBoot, afi.forRun(glass.regs(), a.regs(), mc.FW_OPT_W64, pause));
    try std.testing.expectEqual(afi.WR32, a.words[afi.WRCHAN_CTRL / 4]);
    try std.testing.expect(glass.ctrl & map.CTRL_RUN != 0); // not even held
}

const Afi = struct {
    words: [afi.PAGE_BYTES / 4]u32 = [_]u32{0} ** (afi.PAGE_BYTES / 4),
    stuck: bool = false, // a register that ignores the write

    fn regs(self: *Afi) bus.Regs {
        return .{ .ctx = self, .read_fn = read, .write_fn = write };
    }
    fn read(ctx: *anyopaque, off: u32) u32 {
        const self: *Afi = @ptrCast(@alignCast(ctx));
        return self.words[off / 4];
    }
    fn write(ctx: *anyopaque, off: u32, v: u32) void {
        const self: *Afi = @ptrCast(@alignCast(ctx));
        if (!self.stuck) self.words[off / 4] = v;
    }
};

var paused = false;
fn pause() void {
    paused = true;
}

test "the width changes only with the cart CPU held and HP1 given time to drain" {
    var glass = sim.Glass{};
    glass.ctrl = map.CTRL_RUN | map.CTRL_OSD;
    var a = Afi{};
    paused = false;
    try afi.setHp1(glass.regs(), a.regs(), afi.WR64, pause);
    try std.testing.expect(glass.ctrl & map.CTRL_RUN == 0 and glass.ctrl & map.CTRL_OSD != 0 and paused);
    try std.testing.expectEqual(afi.WR64, a.words[afi.WRCHAN_CTRL / 4]);
}

test "a width that does not read back is an error, not a silent mismatch" {
    var glass = sim.Glass{};
    var a = Afi{ .stuck = true };
    try std.testing.expectError(error.AfiReadback, afi.setHp1(glass.regs(), a.regs(), afi.WR64, pause));
}

test "a CPU that will not stop never sees its port's width change" {
    var glass = sim.Glass{ .stuck = true };
    var a = Afi{};
    try std.testing.expectError(error.WontStop, afi.setHp1(glass.regs(), a.regs(), afi.WR64, pause));
    try std.testing.expectEqual(@as(u32, 0), a.words[afi.WRCHAN_CTRL / 4]);
}

test "--fw-opt takes only the switches the firmware knows" {
    try std.testing.expectEqual(@as(?u32, 0x12), afi.parseOpt("0x12"));
    try std.testing.expectEqual(@as(?u32, 2), afi.parseOpt("2"));
    try std.testing.expectEqual(@as(?u32, null), afi.parseOpt("0x1"));
    try std.testing.expectEqual(@as(?u32, null), afi.parseOpt("w64"));
}

test "a run on a PL that is not ours never touches the AFI" {
    var not_ours = Afi{}; // every register reads 0: no ID_VALUE
    var a = Afi{};
    a.words[afi.WRCHAN_CTRL / 4] = afi.WR64;
    try std.testing.expectError(error.NoGlass, afi.forRun(not_ours.regs(), a.regs(), null, pause));
    try std.testing.expectEqual(afi.WR64, a.words[afi.WRCHAN_CTRL / 4]);
}
