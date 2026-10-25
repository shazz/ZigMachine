// Reading a .zmd disk (docs/FLOPPY_DISK.md) on the board: its title for the
// menu, and the files the loader needs. v1 (descriptor + FAT at $200) and v2
// (an executable wasm boot sector, descriptor at $400, FAT at $800) are both
// read; every offset and length is checked against the image, so a truncated
// or corrupt disk is refused here instead of reading past its end.
const std = @import("std");
const map = @import("map.zig");

pub const Error = error{ NotADisk, Truncated, BadFat, NoBoardImage };

pub const BLOCK = 512;
pub const FAT_ENTRY = 32;
const FAT_MAX = 24;

pub const File = struct {
    name: []const u8,
    start: u32,
    length: u32,
    kind: u8,
};

pub const Disk = struct {
    version: u16,
    title: []const u8,
    file_count: u16,
    fat: []const u8, // FAT_MAX entries of FAT_ENTRY bytes
    image: []const u8,

    pub fn file(self: Disk, i: usize) Error!File {
        if (i >= self.file_count) return error.BadFat;
        const e = self.fat[i * FAT_ENTRY ..][0..FAT_ENTRY];
        const f = File{
            .name = cstr(e[0..16]),
            .start = std.mem.readInt(u32, e[0x10..0x14], .little),
            .length = std.mem.readInt(u32, e[0x14..0x18], .little),
            .kind = e[0x18],
        };
        if (@as(u64, f.start) + f.length > self.image.len) return error.Truncated;
        return f;
    }

    pub fn bytes(self: Disk, f: File) []const u8 {
        return self.image[f.start..][0..f.length];
    }

    /// The disk boots a cart of its own (docs/zmdisk.js parseDisk, host/zmd_dir_fat.h): a v1 boot
    /// sector summing to $1234, or a v2 wasm sector summing to $1234 whose descriptor names a cart
    /// (one naming none, sysinfo's, runs and hands over to the OS: a data disk).
    pub fn bootable(self: Disk) bool {
        if (self.version == 1) return beSum(self.image[0..BLOCK]) == 0x1234;
        if (self.image.len < 0x410) return false;
        return beSum(self.image[0 .. 2 * BLOCK]) == 0x1234 and std.mem.readInt(u32, self.image[0x40C..][0..4], .little) != 0;
    }

    /// The cart's rv32 board image: the FAT file of type ZMD_TYPE_RV32.
    pub fn boardImage(self: Disk) Error![]const u8 {
        for (0..self.file_count) |i| {
            const f = try self.file(i);
            if (f.kind == map.ZMD_TYPE_RV32) return self.bytes(f);
        }
        return error.NoBoardImage;
    }

    /// The disk the browser mounts: this fat disk with fpga/tools/zmd_fat.py
    /// undone, byte for byte. The board image is cut off (zmd_fat appends it,
    /// block-aligned, after the shelf disk's last byte), its FAT entry zeroed
    /// and the count put back, and a v1 boot sector gets its total-blocks field
    /// and the checksum word that keeps the sum it has. A disk zmd_fat did not
    /// write that way (the board image not last) is refused: a drive must not
    /// hand a cart a disk the browser would not.
    pub fn shelfDisk(self: Disk, gpa: std.mem.Allocator) (Error || error{OutOfMemory})![]u8 {
        if (self.file_count == 0) return error.NoBoardImage;
        const last = self.file_count - 1;
        const f = try self.file(last);
        if (f.kind != map.ZMD_TYPE_RV32) return error.BadFat;
        const end = std.mem.alignForward(usize, @as(usize, f.start) + f.length, BLOCK);
        if (f.start % BLOCK != 0 or end != self.image.len) return error.BadFat;
        const l = try layout(self.image);
        if (f.start < l.fat + FAT_MAX * FAT_ENTRY) return error.BadFat;
        const out = try gpa.dupe(u8, self.image[0..f.start]);
        @memset(out[l.fat + last * FAT_ENTRY ..][0..FAT_ENTRY], 0);
        std.mem.writeInt(u16, out[l.count..][0..2], last, .little);
        if (l.version == 1) {
            const sum = beSum(self.image[0..BLOCK]);
            std.mem.writeInt(u32, out[0x0A..0x0E], f.start / BLOCK, .little);
            std.mem.writeInt(u16, out[0x1FE..0x200], 0, .big);
            std.mem.writeInt(u16, out[0x1FE..0x200], sum -% beSum(out[0..BLOCK]), .big);
        }
        return out;
    }
};

/// The boot sector's checksum: its big-endian words summed mod 2^16 (zmd_fat.py _be_sum).
pub fn beSum(buf: []const u8) u16 {
    var s: u16 = 0;
    var i: usize = 0;
    while (i + 1 < buf.len) : (i += 2) s +%= std.mem.readInt(u16, buf[i..][0..2], .big);
    return s;
}

const Layout = struct { version: u16, title: usize, count: usize, fat: usize };

pub fn layout(image: []const u8) Error!Layout {
    if (image.len >= 6 and std.mem.eql(u8, image[0..6], "ZMDISK"))
        return .{ .version = 1, .title = 0x200, .count = 0x2E4, .fat = 0x300 };
    if (image.len >= 0x406 and std.mem.eql(u8, image[0..4], "\x00asm") and std.mem.eql(u8, image[0x400..0x406], "ZMDISK"))
        return .{ .version = 2, .title = 0x410, .count = 0x4F4, .fat = 0x800 };
    return error.NotADisk;
}

/// Parse the header; the returned Disk borrows `image`.
pub fn parse(image: []const u8) Error!Disk {
    const l = try layout(image);
    if (image.len < l.fat + FAT_MAX * FAT_ENTRY) return error.Truncated;
    const count = std.mem.readInt(u16, image[l.count..][0..2], .little);
    if (count > FAT_MAX) return error.BadFat;
    return .{
        .version = l.version,
        .title = cstr(image[l.title..][0..64]),
        .file_count = count,
        .fat = image[l.fat..][0 .. FAT_MAX * FAT_ENTRY],
        .image = image,
    };
}

fn cstr(field: []const u8) []const u8 {
    return field[0 .. std.mem.indexOfScalar(u8, field, 0) orelse field.len];
}

// --- tests -------------------------------------------------------------------

/// A v1 disk with the given FAT files (no boot cart: the FAT is what we read).
pub fn testDisk(gpa: std.mem.Allocator, title: []const u8, files: []const struct { []const u8, u8, []const u8 }) ![]u8 {
    var img: std.ArrayList(u8) = .empty;
    errdefer img.deinit(gpa);
    try img.appendNTimes(gpa, 0, 0x600);
    @memcpy(img.items[0..6], "ZMDISK");
    @memcpy(img.items[0x200..][0..title.len], title);
    std.mem.writeInt(u16, img.items[0x2E4..][0..2], @intCast(files.len), .little);
    for (files, 0..) |f, i| {
        const start: u32 = @intCast(img.items.len);
        try img.appendSlice(gpa, f[2]);
        try img.appendNTimes(gpa, 0, (BLOCK - img.items.len % BLOCK) % BLOCK);
        const e = img.items[0x300 + i * FAT_ENTRY ..][0..FAT_ENTRY];
        @memcpy(e[0..f[0].len], f[0]);
        std.mem.writeInt(u32, e[0x10..0x14], start, .little);
        std.mem.writeInt(u32, e[0x14..0x18], @intCast(f[2].len), .little);
        e[0x18] = f[1];
    }
    return img.toOwnedSlice(gpa);
}

test "a v1 disk's title and board image" {
    const gpa = std.testing.allocator;
    const img = try testDisk(gpa, "Union Demo", &.{ .{ "SAMPLE.RAW", 1, "abc" }, .{ "CART.RV32", 3, "rv32!" } });
    defer gpa.free(img);
    const d = try parse(img);
    try std.testing.expectEqualStrings("Union Demo", d.title);
    try std.testing.expectEqualStrings("rv32!", try d.boardImage());
    try std.testing.expectEqualStrings("SAMPLE.RAW", (try d.file(0)).name);
}

test "a disk without a board image, a foreign file and a lying FAT are refused" {
    const gpa = std.testing.allocator;
    const img = try testDisk(gpa, "wasm only", &.{.{ "SAMPLE.RAW", 1, "abc" }});
    defer gpa.free(img);
    try std.testing.expectError(error.NoBoardImage, (try parse(img)).boardImage());
    try std.testing.expectError(error.NotADisk, parse("PK\x03\x04 not a disk"));
    try std.testing.expectError(error.Truncated, parse(img[0..0x400]));
    std.mem.writeInt(u32, img[0x314..0x318], 0x7FFF_FFFF, .little); // length past the end
    try std.testing.expectError(error.Truncated, (try parse(img)).file(0));
    std.mem.writeInt(u16, img[0x2E4..0x2E6], 25, .little);
    try std.testing.expectError(error.BadFat, parse(img));
}

test "a v2 disk is found by its descriptor" {
    var img = [_]u8{0} ** 0xC00;
    @memcpy(img[0..4], "\x00asm");
    @memcpy(img[0x400..0x406], "ZMDISK");
    @memcpy(img[0x410..0x414], "REPL");
    const d = try parse(&img);
    try std.testing.expectEqual(@as(u16, 2), d.version);
    try std.testing.expectEqualStrings("REPL", d.title);
}
