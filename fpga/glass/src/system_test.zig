// The split load (system.zig, plan.zig; decisions.md 2026-10-15) against the simulated glass:
// the system at 0, the lean cart at CART_IMG_AT, its disk after its .bss; a cart for another
// table, or with no system on the card, refused before DDR or the CPU are touched.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const loader = @import("loader.zig");
const system = @import("system.zig");

const gpa = std.testing.allocator;
const WINDOW = 4 << 20; // past CART_IMG_AT, with room for a disk
const V1_0: u32 = 1 << 16;
const BSS: u32 = 0x100; // the fake cart's .bss, past its image

/// A lean cart image: the header (magic, version, ..., .bss end), then code-like bytes.
fn leanCart(buf: []u8, version: u32) void {
    for (buf, 0..) |*b, i| b.* = @truncate(i *% 29 +% 3);
    std.mem.writeInt(u32, buf[0..4], mc.CART_HDR_MAGIC, .little);
    std.mem.writeInt(u32, buf[mc.CART_HDR_VERSION_AT..][0..4], version, .little);
    const end: u32 = map.CART_CPU_BASE + mc.CART_IMG_AT + @as(u32, @intCast(buf.len)) + BSS;
    std.mem.writeInt(u32, buf[mc.CART_HDR_BSS_END_AT..][0..4], end, .little);
}

fn systemFile(image: []const u8, version: u32) ![]u8 {
    const n: u32 = @intCast(image.len);
    const head = [4]u32{ mc.SYS_MAGIC, version, n, ~(mc.SYS_MAGIC ^ version ^ n) };
    const raw = try std.mem.concat(gpa, u8, &.{ std.mem.sliceAsBytes(&head), image });
    defer gpa.free(raw);
    return zx0.pack(gpa, raw, .{});
}

fn fatDisk(cart: []const u8) ![]u8 {
    const packed_cart = try zx0.pack(gpa, cart, .{});
    defer gpa.free(packed_cart);
    return zmd.testDisk(gpa, "lean", &.{ .{ "BOOT.WSM", 0, "\x00asm" }, .{ "CART.RV32", map.ZMD_TYPE_RV32, packed_cart } });
}

const Rig = struct {
    glass: sim.Glass = .{},
    words: []u32,

    fn init() !Rig {
        const w = try gpa.alloc(u32, WINDOW / 4);
        @memset(w, 0xA5A5_A5A5);
        return .{ .words = w };
    }
    fn ddr(self: *Rig) bus.Ddr {
        return .{ .words = self.words };
    }
    fn deinit(self: *Rig) void {
        gpa.free(self.words);
    }
};

test "a lean cart lands at CART_IMG_AT over the system image, its disk after its .bss" {
    const sys_img = "SYSTEM:firmware+machine+rom+bard" ** 8;
    const file = try systemFile(sys_img, V1_0);
    defer gpa.free(file);
    const sys = try system.parse(gpa, file);
    defer sys.deinit(gpa);
    try std.testing.expectEqual(V1_0, sys.version);
    var cart: [3000]u8 = undefined;
    leanCart(&cart, V1_0);
    const disk = try fatDisk(&cart);
    defer gpa.free(disk);
    var rig = try Rig.init();
    defer rig.deinit();
    const rep = try loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .system = sys });
    const bytes = std.mem.sliceAsBytes(rig.words);
    try std.testing.expectEqualSlices(u8, sys_img, bytes[0..sys_img.len]);
    try std.testing.expectEqualSlices(u8, &cart, bytes[mc.CART_IMG_AT..][0..cart.len]);
    const disk_at = std.mem.alignForward(u32, mc.CART_IMG_AT + cart.len + BSS, map.DISK_ALIGN);
    try std.testing.expectEqual(disk_at, rep.disk_at);
    try std.testing.expectEqual(@as(u32, mc.CART_IMG_AT + cart.len), rig.glass.load_size);
    try std.testing.expectEqual(@as(u32, 0), rig.words[sys_img.len / 4 + 1]); // zeros between
    var p = try loader.planFor(gpa, disk, WINDOW, .{ .system = sys });
    defer p.deinit(gpa);
    const parts = p.parts();
    try std.testing.expectEqual(@as(?usize, null), rig.ddr().verifyParts(&parts));
}

test "a cart for another table, or no system on the card, is refused before anything is touched" {
    const file = try systemFile("SYS!" ** 16, V1_0 | 2);
    defer gpa.free(file);
    const sys = try system.parse(gpa, file);
    defer sys.deinit(gpa);
    var rig = try Rig.init();
    defer rig.deinit();
    rig.glass.ctrl = map.CTRL_RUN; // the old cart runs on
    var cart: [512]u8 = undefined;
    for ([_]u32{ 2 << 16, V1_0 | 3 }) |need| { // a newer major; a newer minor
        leanCart(&cart, need);
        const disk = try fatDisk(&cart);
        defer gpa.free(disk);
        try std.testing.expectError(error.CartAbi, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .system = sys }));
        try std.testing.expectEqual(need, system.last_abi.need);
        try std.testing.expectEqual(V1_0 | 2, system.last_abi.have);
        try std.testing.expectError(error.NoSystem, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{}));
    }
    try std.testing.expectEqual(map.CTRL_RUN, rig.glass.ctrl);
    try std.testing.expectEqual(@as(u32, 0xA5A5_A5A5), rig.words[0]);
    leanCart(&cart, V1_0 | 1); // an older minor runs
    const ok = try fatDisk(&cart);
    defer gpa.free(ok);
    _ = try loader.load(gpa, rig.glass.regs(), rig.ddr(), ok, .{ .system = sys });
}

test "the firmware's own refusal is named, and the CPU is held" {
    const file = try systemFile("SYS!", V1_0);
    defer gpa.free(file);
    const sys = try system.parse(gpa, file);
    defer sys.deinit(gpa);
    var cart: [256]u8 = undefined;
    leanCart(&cart, V1_0);
    const disk = try fatDisk(&cart);
    defer gpa.free(disk);
    var rig = try Rig.init();
    defer rig.deinit();
    rig.glass.cart = .traps;
    rig.glass.trap_code = mc.TRAP_CART_ABI;
    try std.testing.expectError(error.SystemRefused, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .system = sys }));
    try std.testing.expectEqual(@as(u32, 0), rig.glass.ctrl & map.CTRL_RUN);
    rig.glass.trap_code = mc.TRAP_NO_CART;
    try std.testing.expectError(error.NoCart, loader.load(gpa, rig.glass.regs(), rig.ddr(), disk, .{ .system = sys }));
}

test "a system file that does not check, and a cart header that lies, are refused" {
    const good = try systemFile("SYS!", V1_0);
    defer gpa.free(good);
    const raw = try gpa.alloc(u8, zx0.depackedLen(good).?);
    _ = zx0.depack(good, raw).?;
    defer gpa.free(raw);
    raw[12] ^= 1; // the check word
    try std.testing.expectError(error.BadSystem, system.parse(gpa, raw));
    raw[12] ^= 1;
    try std.testing.expectError(error.BadSystem, system.parse(gpa, raw[0 .. raw.len - 1])); // length
    try std.testing.expectError(error.BadSystem, system.parse(gpa, "ZMSY"));
    var cart: [64]u8 = undefined;
    leanCart(&cart, V1_0);
    std.mem.writeInt(u32, cart[mc.CART_HDR_BSS_END_AT..][0..4], map.CART_CPU_BASE + mc.CART_IMG_AT, .little);
    try std.testing.expectError(error.BadCart, system.cart(&cart)); // .bss ends inside the image
    try std.testing.expect(system.abiOk(V1_0, V1_0 | 1) and !system.abiOk(V1_0 | 1, V1_0) and !system.abiOk(2 << 16, V1_0));
}
