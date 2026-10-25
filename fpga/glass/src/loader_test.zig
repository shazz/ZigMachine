// The load path end to end against the simulated glass and a fake DDR.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const loader = @import("loader.zig");
const mc = @import("map_cart.zig");

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

/// The window against the load's plan (image, disk, descriptor, zeros): the first word that differs.
fn landed(rig: *Rig, disk: []const u8) !?usize {
    var p = try loader.plan(gpa, disk, WINDOW_WORDS * 4);
    defer p.deinit(gpa);
    const parts = p.parts();
    return rig.ddr().verifyParts(&parts);
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
    try std.testing.expectEqual(@as(?usize, null), try landed(&rig, disk));
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
    try std.testing.expectEqual(@as(?usize, null), try landed(&rig, disk));
    try std.testing.expectEqualStrings("RAWIMAGE", std.mem.sliceAsBytes(rig.words[0..2]));
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

test "a warm reset restarts the cart over its memory; a cold load leaves none to keep" {
    var raw = [_]u8{7} ** 64;
    const disk = try diskWith(&raw);
    defer gpa.free(disk);
    var rig = Rig{};
    _ = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{});
    rig.words[100] = 0x1234_5678; // the cart wrote its memory
    rig.glass.push(map.KEY_DOWN | 'x'); // a key typed for the menu
    const rep = try loader.warm(rig.glass.regs(), rig.ddr(), .{});
    try std.testing.expectEqual(@as(u32, 0x1234_5678), rig.words[100]); // DDR untouched
    try std.testing.expectEqual(@as(u32, 1), rig.glass.warm_boots);
    try std.testing.expectEqual(@as(u32, 0), rig.glass.key_len);
    try std.testing.expectEqual(sim.FW_VERSION, rep.fw);
    try std.testing.expectEqual(map.CTRL_RUN, rig.glass.ctrl); // WARM dropped once up
    rig.glass.marked = false; // as if the cold boot never got as far as marking
    try std.testing.expectError(error.WarmLost, loader.warm(rig.glass.regs(), rig.ddr(), .{}));
    try std.testing.expectEqual(@as(u32, 0), rig.glass.ctrl & (map.CTRL_RUN | map.CTRL_WARM));
}

test "a CPU that will not stop is never written to" {
    var rig = Rig{ .glass = .{ .stuck = true } };
    try std.testing.expectError(error.WontStop, loader.warm(rig.glass.regs(), rig.ddr(), .{}));
    try std.testing.expectEqual(@as(u32, 0), rig.glass.ctrl & map.CTRL_RUN);
}

test "a PL older than 1.3.0 ignores LOAD_BASE, so it gets no cart (it would run over the initramfs)" {
    const Old = struct {
        writes: u32 = 0,
        fn read(_: *anyopaque, reg: u32) u32 {
            return switch (reg) {
                map.REG_ID => map.ID_VALUE,
                map.REG_VERSION => 0x0001_0200,
                else => 0,
            };
        }
        fn write(ctx: *anyopaque, _: u32, _: u32) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.writes += 1;
        }
    };
    var old = Old{};
    const regs = bus.Regs{ .ctx = &old, .read_fn = Old.read, .write_fn = Old.write };
    var rig = Rig{};
    try std.testing.expectError(error.OldGlass, loader.load(gpa, regs, rig.ddr(), "", .{}));
    try std.testing.expectEqual(@as(u32, 0), old.writes); // not even CTRL: the running cart is left alone
}

test "the shelf disk lands after the image, and the descriptor says where" {
    var raw: [5000]u8 = undefined;
    fakeImage(&raw);
    const disk = try diskWith(&raw);
    defer gpa.free(disk);
    var rig = Rig{};
    const rep = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{});
    const shelf = try (try zmd.parse(disk)).shelfDisk(gpa);
    defer gpa.free(shelf);
    try std.testing.expectEqual(@as(u32, 0x2000), rep.disk_at); // 5000 rounded up to DISK_ALIGN
    try std.testing.expectEqual(@as(u32, @intCast(shelf.len)), rep.disk_bytes);
    const bytes = std.mem.sliceAsBytes(&rig.words);
    try std.testing.expectEqualSlices(u8, shelf, bytes[0x2000..][0..shelf.len]);
    const top = WINDOW_WORDS - map.DISK_DESC_FROM_TOP / 4;
    const size: u32 = @intCast(shelf.len);
    try std.testing.expectEqualSlices(u32, &.{ map.DISK_MAGIC, 0x2000, size, ~(map.DISK_MAGIC ^ 0x2000 ^ size) }, rig.words[top..][0..4]);
    try std.testing.expectEqual(@as(u32, 1), (try zmd.parse(shelf)).file_count); // the board image is gone
}

test "a disk that does not fit below the descriptor is refused before the cart CPU is touched" {
    var rig = Rig{};
    rig.glass.ctrl = map.CTRL_RUN;
    var raw = [_]u8{0x55} ** (WINDOW_WORDS * 4 - 0x800); // fits the window, but leaves no room for the disk
    const disk = try diskWith(&raw);
    defer gpa.free(disk);
    try std.testing.expectError(error.DiskTooBig, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{}));
    try std.testing.expectEqual(map.CTRL_RUN, rig.glass.ctrl);
    try std.testing.expectEqual(@as(u32, 0xA5A5_A5A5), rig.words[0]);
    try std.testing.expectError(error.DiskTooBig, loader.diskAt(0x10, map.DISK_END, 32 << 20)); // past the pictures
    try std.testing.expectEqual(@as(u32, 0x0020_0000), try loader.diskAt(0x1F_F001, map.DISK_END - 0x20_0000, 32 << 20)); // exactly fills
}

test "--fw-opt's word lands for the firmware after the window is verified, and only with it" {
    var raw: [3000]u8 = undefined;
    fakeImage(&raw);
    const disk = try diskWith(&raw);
    defer gpa.free(disk);
    const at = (WINDOW_WORDS * 4 - mc.FW_OPT_FROM_TOP) / 4;
    var rig = Rig{};
    _ = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .fw_opt = mc.FW_OPT_W64 | 0x100 });
    try std.testing.expectEqual(mc.FW_OPT_TAG | mc.FW_OPT_W64, rig.words[at]); // unknown bits dropped
    var plain = Rig{};
    _ = try loader.load(gpa, plain.glass.regs(), plain.ddr(), disk, .{});
    try std.testing.expectEqual(@as(u32, 0), plain.words[at]);
}

test "the boot-sector skip word lands only for a load that asks for it" {
    var raw: [3000]u8 = undefined;
    fakeImage(&raw);
    const disk = try diskWith(&raw);
    defer gpa.free(disk);
    const at = (WINDOW_WORDS * 4 - mc.BOOTSEC_SKIP_FROM_TOP) / 4;
    var rig = Rig{};
    _ = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .skip_boot_sector = true });
    try std.testing.expectEqual(mc.BOOTSEC_SKIP, rig.words[at]);
    _ = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{}); // the next load rewrites the window whole
    try std.testing.expectEqual(@as(u32, 0), rig.words[at]);
}
