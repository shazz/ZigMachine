// The W64 switch's two halves: HP1's AFI width (afi.zig) and the firmware's word (loader.zig).
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const afi = @import("afi.zig");
const mc = @import("map_cart.zig");

fn plan(width: ?u32, opt: ?u32) afi.Plan {
    return .{ .width = width, .opt = opt };
}

test "without --fw-opt the channel decides: 0xF00 from boot runs W64, 0xF01 runs as before" {
    try std.testing.expectEqual(plan(null, mc.FW_OPT_W64), try afi.resolve(null, afi.WR64));
    try std.testing.expectEqual(plan(null, null), try afi.resolve(null, afi.WR32));
    try std.testing.expectEqual(plan(afi.WR32, null), try afi.resolve(null, 0)); // never set: 32-bit
}

test "--fw-opt overrides the default: W64 keeps 0xF00, the W32 arm goes 64 -> 32" {
    try std.testing.expectEqual(plan(null, mc.FW_OPT_W64), try afi.resolve(mc.FW_OPT_W64, afi.WR64));
    try std.testing.expectEqual(plan(afi.WR32, 0), try afi.resolve(0, afi.WR64));
    const old_order = mc.FW_OPT_PLANE_MAJOR | mc.FW_OPT_KEEP_PFB; // 0x30: never gains W64
    try std.testing.expectEqual(plan(afi.WR32, old_order), try afi.resolve(old_order, afi.WR64));
    try std.testing.expectEqual(plan(null, old_order), try afi.resolve(old_order, afi.WR32));
}

test "a default run on a 0xF00 channel leaves it and hands every load the W64 word" {
    var glass = sim.Glass{};
    glass.ctrl = map.CTRL_RUN;
    var a = Afi{};
    a.words[afi.WRCHAN_CTRL / 4] = afi.WR64;
    paused = false;
    try std.testing.expectEqual(@as(?u32, mc.FW_OPT_W64), try afi.forRun(glass.regs(), a.regs(), null, pause));
    try std.testing.expectEqual(afi.WR64, a.words[afi.WRCHAN_CTRL / 4]);
    try std.testing.expect(glass.ctrl & map.CTRL_RUN != 0 and !paused); // nothing held, nothing switched
}

test "the W32 arm on a 0xF00 channel holds the CPU and sets 0xF01, and a later default run stays W32" {
    var glass = sim.Glass{};
    glass.ctrl = map.CTRL_RUN;
    var a = Afi{};
    a.words[afi.WRCHAN_CTRL / 4] = afi.WR64;
    try std.testing.expectEqual(@as(?u32, 0), try afi.forRun(glass.regs(), a.regs(), 0, pause));
    try std.testing.expectEqual(afi.WR32, a.words[afi.WRCHAN_CTRL / 4]);
    try std.testing.expectEqual(@as(?u32, null), try afi.forRun(glass.regs(), a.regs(), null, pause));
    try std.testing.expectEqual(afi.WR32, a.words[afi.WRCHAN_CTRL / 4]);
}

test "W64 on a channel that is 32-bit now is refused, never switched 32 -> 64 at run time" {
    try std.testing.expectError(error.W64NeedsBoot, afi.resolve(mc.FW_OPT_W64, afi.WR32));
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
