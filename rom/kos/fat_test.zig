// rom/kos/fat.zig over hand-built images: an Atari 720 KB floppy (TOS's BPB, no 55 AA), its root
// and a subfolder, a fragmented file, the entries GEMDOS hides, and every way a disk can lie.
// tools/tests/test_kos_fat.py holds the same reader against mkfs.fat + mtools on FAT12/16/32.
const std = @import("std");
const fat = @import("fat.zig");

const S = fat.SECTOR;
const TOTAL = 1440; // 720 KB: 80 tracks, 2 sides, 9 sectors
// TOS's 720 KB layout: 2 sectors a cluster, 1 reserved, 2 FATs of 3 sectors, 112 root entries.
const FAT0 = 1;
const ROOT0 = 7;
const DATA0 = 14;

const Image = struct {
    b: [TOTAL * S]u8 = [_]u8{0} ** (TOTAL * S),
    fail_at: u32 = 0xFFFF_FFFF, // a sector the "drive" cannot read

    fn init(self: *Image) void {
        const h = self.b[0..S];
        h[0] = 0x60; // TOS: a BRA.S, not 0xEB; a serial at 8..10, no 55 AA
        put16(h, 11, S);
        h[13] = 2;
        put16(h, 14, 1);
        h[16] = 2;
        put16(h, 17, 112);
        put16(h, 19, TOTAL);
        h[21] = 0xF9;
        put16(h, 22, 3);
        self.setFat(0, 0xFF9);
        self.setFat(1, 0xFFF);
    }

    fn setFat(self: *Image, c: u32, val: u32) void {
        for ([_]u32{ FAT0, FAT0 + 3 }) |f| {
            const off = f * S + c + c / 2;
            var w = std.mem.readInt(u16, self.b[off..][0..2], .little);
            w = if (c & 1 != 0) (w & 0x000F) | @as(u16, @intCast(val << 4)) else (w & 0xF000) | @as(u16, @intCast(val));
            std.mem.writeInt(u16, self.b[off..][0..2], w, .little);
        }
    }

    fn entry(self: *Image, at: usize, name: *const [11]u8, attr: u8, first: u16, size: u32) void {
        const r = self.b[at..][0..32];
        @memcpy(r[0..11], name);
        r[11] = attr;
        put16(r, 24, (2026 - 1980) << 9 | 10 << 5 | 31);
        put16(r, 26, first);
        std.mem.writeInt(u32, r[28..32], size, .little);
    }

    fn cluster(c: u32) usize {
        return (DATA0 + (c - 2) * 2) * S;
    }

    fn read(ctx: *anyopaque, n: u32, dst: *[S]u8) bool {
        const self: *Image = @ptrCast(@alignCast(ctx));
        if (n >= TOTAL or n == self.fail_at) return false;
        @memcpy(dst, self.b[n * S ..][0..S]);
        return true;
    }
};

fn put16(b: []u8, at: usize, v: u16) void {
    std.mem.writeInt(u16, b[at..][0..2], v, .little);
}

/// README.TXT over clusters 2 -> 5 -> 3 (fragmented), a folder GAMES with SAVE.DAT in it.
fn atari(img: *Image) void {
    img.init();
    img.entry(ROOT0 * S, "MYDISK     ", fat.ATTR_VOLUME, 0, 0);
    img.b[ROOT0 * S + 32] = 0xE5; // a deleted file
    img.entry(ROOT0 * S + 64, "\x41\x00\x62\x00\x63\x00\x2E\x00\x74\x00\x78", 0x0F, 0, 0); // a long-name piece
    img.entry(ROOT0 * S + 96, "README  TXT", 0x20, 2, 2 * 1024 + 100);
    img.entry(ROOT0 * S + 128, "GAMES      ", fat.ATTR_DIR, 4, 0);
    img.setFat(2, 5);
    img.setFat(5, 3);
    img.setFat(3, 0xFFF);
    img.setFat(4, 0xFFF);
    for ([_]u32{ 2, 5, 3 }, 0..) |c, k| @memset(img.b[Image.cluster(c)..][0..1024], @intCast('a' + k));
    const g = Image.cluster(4);
    img.entry(g, ".          ", fat.ATTR_DIR, 4, 0);
    img.entry(g + 32, "..         ", fat.ATTR_DIR, 0, 0);
    img.entry(g + 64, "SAVE    DAT", 0x20, 0, 0);
}

test "an Atari 720 KB floppy: FAT12 from its cluster count, the root as GEMDOS lists it" {
    var img = Image{};
    atari(&img);
    var v = try fat.Volume.mount(Image.read, &img);
    try std.testing.expectEqual(fat.Kind.fat12, v.kind);
    try std.testing.expectEqual(@as(u32, (TOTAL - DATA0) / 2), v.clusters);
    var out: [8]fat.Entry = undefined;
    const n = try v.list(v.root(), &out);
    try std.testing.expectEqual(@as(usize, 2), n); // no label, deleted file or long-name piece
    try std.testing.expectEqualStrings("README.TXT", out[0].nameSlice());
    try std.testing.expectEqual(@as(u32, 20261031), out[0].date);
    try std.testing.expectEqualStrings("GAMES", out[1].nameSlice());
    try std.testing.expect(out[1].isDir());
    const m = try v.list(.{ .cluster = out[1].cluster }, &out);
    try std.testing.expectEqual(@as(usize, 1), m); // no . or ..
    try std.testing.expectEqualStrings("SAVE.DAT", out[0].nameSlice());
}

test "a fragmented file reads in chain order, from any offset, and stops at its size" {
    var img = Image{};
    atari(&img);
    var v = try fat.Volume.mount(Image.read, &img);
    var out: [8]fat.Entry = undefined;
    _ = try v.list(v.root(), &out);
    var buf: [3000]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2 * 1024 + 100), try v.read(&out[0], 0, &buf));
    try std.testing.expectEqual(@as(u8, 'a'), buf[1023]);
    try std.testing.expectEqual(@as(u8, 'b'), buf[1024]); // cluster 5, the chain's second
    try std.testing.expectEqual(@as(u8, 'c'), buf[2048 + 99]);
    try std.testing.expectEqual(@as(usize, 50), try v.read(&out[0], 2048 + 50, &buf));
    try std.testing.expectEqual(@as(u8, 'c'), buf[0]);
    try std.testing.expectEqual(@as(usize, 0), try v.read(&out[0], 5000, &buf));
}

test "a disk that lies is refused: bad BPB fields, a looping chain, a chain shorter than its file, a dead sector" {
    var img = Image{};
    atari(&img);
    img.b[13] = 3; // sectors a cluster: not a power of 2
    try std.testing.expectError(error.Corrupt, fat.Volume.mount(Image.read, &img));
    img.b[13] = 2;
    put16(&img.b, 11, 1024);
    try std.testing.expectError(error.Unsupported, fat.Volume.mount(Image.read, &img));
    put16(&img.b, 11, S);
    put16(&img.b, 22, 0);
    try std.testing.expectError(error.Corrupt, fat.Volume.mount(Image.read, &img));
    put16(&img.b, 22, 3);
    var v = try fat.Volume.mount(Image.read, &img);
    var out: [8]fat.Entry = undefined;
    _ = try v.list(v.root(), &out);
    var buf: [3000]u8 = undefined;
    img.setFat(3, 2); // 2 -> 5 -> 3 -> 2: a loop, read past its own length
    var big = out[0];
    big.size = 1 << 20;
    var huge: [1 << 20]u8 = undefined;
    try std.testing.expectError(error.Corrupt, v.read(&big, 0, &huge));
    img.setFat(5, 0xFFF); // 2 -> 5, end: shorter than the 2148 bytes it says
    v.buf_sector = 0xFFFF_FFFF;
    try std.testing.expectError(error.Corrupt, v.read(&out[0], 0, &buf));
    img.fail_at = ROOT0;
    v.buf_sector = 0xFFFF_FFFF;
    try std.testing.expectError(error.Io, v.list(v.root(), &out));
}
