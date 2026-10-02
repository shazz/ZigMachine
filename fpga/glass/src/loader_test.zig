// The load path end to end against the simulated glass and a fake DDR.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const loader = @import("loader.zig");

const gpa = std.testing.allocator;
const WINDOW_WORDS = 4096; // 16 KiB: the real 32 MiB adds nothing but time

const Rig = struct {
    glass: sim.Glass = .{},
    words: [WINDOW_WORDS]u32 = [_]u32{0xA5A5_A5A5} ** WINDOW_WORDS,

    fn ddr(self: *Rig) bus.Ddr {
        return .{ .words = &self.words };
    }
};

/// A fake board image: code-like bytes, then a long zero run as .bss leaves.
fn fakeImage(buf: []u8) void {
    for (buf, 0..) |*b, i| b.* = if (i < buf.len / 3) @truncate(i *% 37 +% 11) else 0;
}

fn diskWith(image: []const u8) ![]u8 {
    return zmd.testDisk(gpa, "fat", &.{ .{ "BOOT.WSM", 0, "\x00asm" }, .{ "CART.RV32", map.ZMD_TYPE_RV32, image } });
}

test "a packed board image lands in DDR exactly and the cart runs" {
    var raw: [5000]u8 = undefined;
    fakeImage(&raw);
    const packed_image = try zx0.pack(gpa, &raw, .{});
    defer gpa.free(packed_image);
    const disk = try diskWith(packed_image);
    defer gpa.free(disk);
    var rig = Rig{};
    rig.glass.ctrl = map.CTRL_OSD | map.CTRL_RUN; // a cart was running, the menu open
    rig.glass.push(0xE012);
    const rep = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{});
    try std.testing.expectEqual(@as(?usize, null), rig.ddr().verify(&raw));
    try std.testing.expectEqualSlices(u8, &raw, std.mem.sliceAsBytes(rig.words[0..1250]));
    try std.testing.expectEqual(@as(u32, 5000), rep.image_bytes);
    try std.testing.expectEqual(@as(u32, 5000), rig.glass.load_size);
    try std.testing.expectEqual(map.DDR_CART_BASE, rig.glass.load_base);
    try std.testing.expectEqual(@as(u32, 1), rig.glass.resets); // held before the write
    try std.testing.expectEqual(@as(u32, 0), rig.glass.key_len); // old keys flushed
    try std.testing.expectEqual(map.CTRL_OSD | map.CTRL_RUN, rig.glass.ctrl);
}

test "an unpacked image loads as is" {
    var rig = Rig{};
    const disk = try diskWith("RAWIMAGE");
    defer gpa.free(disk);
    _ = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{});
    try std.testing.expectEqual(@as(?usize, null), rig.ddr().verify("RAWIMAGE"));
}

test "failures leave the cart CPU held in reset" {
    var raw = [_]u8{1} ** 64;
    const disk = try diskWith(&raw);
    defer gpa.free(disk);
    var rig = Rig{ .glass = .{ .cart = .traps } };
    try std.testing.expectError(error.CartTrapped, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{}));
    try std.testing.expectEqual(@as(u32, 0), rig.glass.ctrl & map.CTRL_RUN);
    rig = Rig{ .glass = .{ .cart = .silent } };
    try std.testing.expectError(error.CartSilent, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .boot_polls = 10 }));
    try std.testing.expectEqual(@as(u32, 0), rig.glass.ctrl & map.CTRL_RUN);
}

test "bad disks and images are refused before the cart CPU is touched" {
    var rig = Rig{};
    rig.glass.ctrl = map.CTRL_RUN;
    var too_big = [_]u8{0} ** (WINDOW_WORDS * 4 + 1);
    const big = try diskWith(&too_big);
    defer gpa.free(big);
    try std.testing.expectError(error.TooBig, loader.load(gpa, rig.glass.regs(), rig.ddr(), big, .{}));
    var raw: [300]u8 = undefined;
    fakeImage(&raw);
    const packed_image = try zx0.pack(gpa, &raw, .{});
    defer gpa.free(packed_image);
    const cut = try diskWith(packed_image[0 .. packed_image.len - 4]);
    defer gpa.free(cut);
    try std.testing.expectError(error.BadImage, loader.load(gpa, rig.glass.regs(), rig.ddr(), cut, .{}));
    const wasm_only = try zmd.testDisk(gpa, "old", &.{.{ "BOOT.WSM", 0, "\x00asm" }});
    defer gpa.free(wasm_only);
    try std.testing.expectError(error.NoBoardImage, loader.load(gpa, rig.glass.regs(), rig.ddr(), wasm_only, .{}));
    try std.testing.expectEqual(map.CTRL_RUN, rig.glass.ctrl); // the old cart still runs
    try std.testing.expectEqual(@as(u32, 0xA5A5_A5A5), rig.words[0]); // and DDR is untouched
}

test "no glass, no load" {
    const Dead = struct {
        fn read(_: *anyopaque, _: u32) u32 {
            return 0xFFFF_FFFF; // what an unconfigured PL's bus answers
        }
        fn write(_: *anyopaque, _: u32, _: u32) void {}
    };
    var dummy: u8 = 0;
    const regs = bus.Regs{ .ctx = &dummy, .read_fn = Dead.read, .write_fn = Dead.write };
    var rig = Rig{};
    try std.testing.expectError(error.NoGlass, loader.load(gpa, regs, rig.ddr(), "", .{}));
}
