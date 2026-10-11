// The fat disk undone (zmd.Disk.shelfDisk): what ZWINDOW places in the cart window
// for the drive must be, byte for byte, the disk the browser mounts.
const std = @import("std");
const map = @import("map.zig");
const zmd = @import("zmd.zig");

/// zmd_fat.py's fatten, for the tests: pad, append `board`, one more FAT entry,
/// and a v1 boot sector re-tuned to the sum it had.
fn testFatten(gpa: std.mem.Allocator, disk: []const u8, board: []const u8) ![]u8 {
    const l = try zmd.layout(disk);
    var img: std.ArrayList(u8) = .empty;
    errdefer img.deinit(gpa);
    try img.appendSlice(gpa, disk);
    try img.appendNTimes(gpa, 0, (zmd.BLOCK - img.items.len % zmd.BLOCK) % zmd.BLOCK);
    const start: u32 = @intCast(img.items.len);
    try img.appendSlice(gpa, board);
    try img.appendNTimes(gpa, 0, (zmd.BLOCK - img.items.len % zmd.BLOCK) % zmd.BLOCK);
    const count = std.mem.readInt(u16, img.items[l.count..][0..2], .little);
    const e = img.items[l.fat + count * zmd.FAT_ENTRY ..][0..zmd.FAT_ENTRY];
    @memcpy(e[0..9], "CART.RV32");
    std.mem.writeInt(u32, e[0x10..0x14], start, .little);
    std.mem.writeInt(u32, e[0x14..0x18], @intCast(board.len), .little);
    e[0x18] = map.ZMD_TYPE_RV32;
    std.mem.writeInt(u16, img.items[l.count..][0..2], count + 1, .little);
    if (l.version == 1) {
        const sum = zmd.beSum(img.items[0..zmd.BLOCK]);
        std.mem.writeInt(u32, img.items[0x0A..0x0E], @intCast(img.items.len / zmd.BLOCK), .little);
        std.mem.writeInt(u16, img.items[0x1FE..0x200], 0, .big);
        std.mem.writeInt(u16, img.items[0x1FE..0x200], sum -% zmd.beSum(img.items[0..zmd.BLOCK]), .big);
    }
    return img.toOwnedSlice(gpa);
}

test "the shelf disk comes back byte for byte from a fat disk" {
    const gpa = std.testing.allocator;
    const shelf = try zmd.testDisk(gpa, "Stream", &.{ .{ "SCENE1.BIN", 1, "x" ** 700 }, .{ "B.RAW", 1, "yz" } });
    defer gpa.free(shelf);
    std.mem.writeInt(u32, shelf[0x0A..0x0E], @intCast(shelf.len / zmd.BLOCK), .little);
    std.mem.writeInt(u16, shelf[0x1FE..0x200], 0x1234 -% zmd.beSum(shelf[0..zmd.BLOCK]), .big); // bootable
    const fat = try testFatten(gpa, shelf, "rv32 image" ** 100);
    defer gpa.free(fat);
    const back = try (try zmd.parse(fat)).shelfDisk(gpa);
    defer gpa.free(back);
    try std.testing.expectEqualSlices(u8, shelf, back);
    try std.testing.expectEqual(@as(u16, 0x1234), zmd.beSum(back[0..zmd.BLOCK]));
}

test "a disk whose board image is not zmd_fat's last file is refused" {
    const gpa = std.testing.allocator;
    const img = try zmd.testDisk(gpa, "odd", &.{ .{ "CART.RV32", 3, "rv32" }, .{ "SAMPLE.RAW", 1, "abc" } });
    defer gpa.free(img);
    try std.testing.expectError(error.BadFat, (try zmd.parse(img)).shelfDisk(gpa));
    const plain = try zmd.testDisk(gpa, "plain", &.{.{ "SAMPLE.RAW", 1, "abc" }});
    defer gpa.free(plain);
    try std.testing.expectError(error.BadFat, (try zmd.parse(plain)).shelfDisk(gpa));
    const fat = try testFatten(gpa, plain, "rv32" ** 200);
    defer gpa.free(fat);
    try std.testing.expectError(error.Truncated, (try zmd.parse(fat[0 .. fat.len - zmd.BLOCK])).shelfDisk(gpa));
}
