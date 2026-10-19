// --------------------------------------------------------------------------
// SysInfo — what the mounted disk says about itself: the ZMDISK descriptor
// (docs/FLOPPY_DISK.md) and its boot sector's kind. The drive hands blocks
// over (zg.readBlock); this file only reads bytes, so it is tested natively.
//
//   v1  magic $000, total blocks $00A, boot block $00E, boot length $012,
//       title $200, author $240, date $2E0, file count $2E4
//   v2  magic $400, cart block $408, cart length $40C, title $410,
//       author $450, date $4F0, file count $4F4 (block 0 is a boot program)
//
// Either way the 256 big-endian words of block 0 sum to $1234 on a bootable
// disk; anything else is a data disk (GEM boots and the disk is its to open).
// --------------------------------------------------------------------------
const std = @import("std");

pub const BLOCK: usize = 512;
const MAGIC = "ZMDISK";
pub const BOOT_SUM: u16 = 0x1234;

pub const Info = struct {
    version: u8, // 1 or 2
    bootable: bool,
    total_blocks: u32, // v1 only (0: the v2 descriptor does not carry it)
    cart_block: u32,
    cart_len: u32,
    date: u32, // YYYYMMDD, 0 = none stamped
    files: u16,
    title: [64]u8,
    author: [32]u8,

    pub fn titleText(self: *const Info) []const u8 {
        return trim(&self.title);
    }
    pub fn authorText(self: *const Info) []const u8 {
        return trim(&self.author);
    }
};

/// The sum of block 0's big-endian words: $1234 = an executable boot sector.
pub fn bootSum(b0: *const [BLOCK]u8) u16 {
    var s: u16 = 0;
    var i: usize = 0;
    while (i < BLOCK) : (i += 2) s +%= std.mem.readInt(u16, b0[i..][0..2], .big);
    return s;
}

/// Parse the disk from its first three blocks (0, 1, 2), or null: no ZigMachine disk.
pub fn parse(b0: *const [BLOCK]u8, b1: *const [BLOCK]u8, b2: *const [BLOCK]u8) ?Info {
    const boot = bootSum(b0) == BOOT_SUM;
    if (std.mem.eql(u8, b2[0..MAGIC.len], MAGIC)) return v2(b2, boot);
    if (std.mem.eql(u8, b0[0..MAGIC.len], MAGIC)) return v1(b0, b1, boot);
    return null;
}

fn v1(b0: *const [BLOCK]u8, b1: *const [BLOCK]u8, boot: bool) Info {
    var i = Info{
        .version = 1,
        .bootable = boot,
        .total_blocks = u32At(b0, 0x0A),
        .cart_block = u32At(b0, 0x0E),
        .cart_len = u32At(b0, 0x12),
        .date = u32At(b1, 0xE0),
        .files = std.mem.readInt(u16, b1[0xE4..][0..2], .little),
        .title = undefined,
        .author = undefined,
    };
    @memcpy(&i.title, b1[0x00..0x40]);
    @memcpy(&i.author, b1[0x40..0x60]);
    return i;
}

fn v2(b2: *const [BLOCK]u8, boot: bool) Info {
    var i = Info{
        .version = 2,
        .bootable = boot,
        .total_blocks = 0,
        .cart_block = u32At(b2, 0x08),
        .cart_len = u32At(b2, 0x0C),
        .date = u32At(b2, 0xF0),
        .files = std.mem.readInt(u16, b2[0xF4..][0..2], .little),
        .title = undefined,
        .author = undefined,
    };
    @memcpy(&i.title, b2[0x10..0x50]);
    @memcpy(&i.author, b2[0x50..0x70]);
    return i;
}

fn u32At(b: *const [BLOCK]u8, off: usize) u32 {
    return std.mem.readInt(u32, b[off..][0..4], .little);
}

/// A NUL-padded field, up to its first NUL, with only printable bytes kept
/// out of it: a disk is not trusted to hold text the font can draw.
pub fn trim(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, 0) orelse raw.len;
    var n: usize = 0;
    while (n < end and raw[n] >= 0x20 and raw[n] < 0x7F) n += 1;
    return raw[0..n];
}

// --- native tests ------------------------------------------------------------
fn blank() [BLOCK]u8 {
    return [_]u8{0} ** BLOCK;
}

/// Tune the last word so block 0 sums to $1234, as tools/mkdisk.py does.
fn makeBootable(b0: *[BLOCK]u8) void {
    std.mem.writeInt(u16, b0[BLOCK - 2 ..][0..2], 0, .big);
    std.mem.writeInt(u16, b0[BLOCK - 2 ..][0..2], BOOT_SUM -% bootSum(b0), .big);
}

test "a v1 disk reads its title, date, cart and files" {
    var b0 = blank();
    var b1 = blank();
    const b2 = blank();
    @memcpy(b0[0..6], MAGIC);
    std.mem.writeInt(u32, b0[0x0E..0x12], 3, .little);
    std.mem.writeInt(u32, b0[0x12..0x16], 9000, .little);
    @memcpy(b1[0..7], "sysinfo");
    @memcpy(b1[0x40..0x4A], "ZigMachine");
    std.mem.writeInt(u32, b1[0xE0..0xE4], 20261018, .little);
    makeBootable(&b0);
    const i = parse(&b0, &b1, &b2).?;
    try std.testing.expectEqual(@as(u8, 1), i.version);
    try std.testing.expect(i.bootable);
    try std.testing.expectEqualStrings("sysinfo", i.titleText());
    try std.testing.expectEqualStrings("ZigMachine", i.authorText());
    try std.testing.expectEqual(@as(u32, 20261018), i.date);
    try std.testing.expectEqual(@as(u32, 9000), i.cart_len);
    try std.testing.expectEqual(@as(u16, 0), i.files);
}

test "a disk whose boot sector does not sum to $1234 is a data disk" {
    var b0 = blank();
    const b1 = blank();
    const b2 = blank();
    @memcpy(b0[0..6], MAGIC);
    b0[0x100] = 1; // the sum is no longer $1234
    try std.testing.expect(!parse(&b0, &b1, &b2).?.bootable);
}

test "a v2 disk is read from its descriptor at block 2" {
    var b0 = blank();
    const b1 = blank();
    var b2 = blank();
    @memcpy(b2[0..6], MAGIC);
    @memcpy(b2[0x10..0x14], "REPS");
    std.mem.writeInt(u16, b2[0xF4..0xF6], 2, .little);
    makeBootable(&b0);
    const i = parse(&b0, &b1, &b2).?;
    try std.testing.expectEqual(@as(u8, 2), i.version);
    try std.testing.expectEqualStrings("REPS", i.titleText());
    try std.testing.expectEqual(@as(u16, 2), i.files);
}

test "no magic, no disk" {
    const b = blank();
    try std.testing.expectEqual(@as(?Info, null), parse(&b, &b, &b));
}

test "a title with a control byte stops before it" {
    try std.testing.expectEqualStrings("AB", trim("AB\x07CD"));
}
