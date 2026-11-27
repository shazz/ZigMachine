// --------------------------------------------------------------------------
// AURORA BOOT: the aurora's containers read off the disk, one 60 Hz frame's at a time.
//
// At 400x280 the change masks are ~3 MB, more than the cart's 3 MiB RAM window holds with the rest, so the cart
// keeps them on the floppy as AURORA.MSK (aurora.msk's format, tools/boot/aurora_mask.py) and only the u32
// offsets in the cart. Each frame reads the 512-byte blocks that cover its container straight into one buffer (no
// scratch copy) and hands the container's bytes to the player. On the board the disk sits in DDR inside the cart
// window (fpga/glass/src/map.zig "The disk in the cart window"), so a block is a copy, not an SD access. No ZigOS
// import: the block reader is a parameter, so it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const BLOCK: u32 = 512;

/// The disk reader: block `b` into `dst` (512 bytes), the bytes read (<= 0: none).
pub const ReadBlock = *const fn (b: u32, dst: []u8) i32;

pub const Stream = struct {
    start: u32, // the file's byte offset on the disk
    len: u32, // its bytes
    buf: []u8, // at least the largest container + 2 blocks (blocksFor)
    read_block: ReadBlock,

    /// Bytes [o, e) of the file, or null when they leave it, the buffer is too small or the drive comes up short.
    pub fn read(self: *const Stream, o: u32, e: u32) ?[]const u8 {
        if (o >= e or e > self.len) return null;
        const a = self.start + o;
        const b = self.start + e;
        const first = a / BLOCK;
        const last = (b - 1) / BLOCK;
        if ((last - first + 1) * BLOCK > self.buf.len) return null;
        var k = first;
        while (k <= last) : (k += 1) {
            const at = (k - first) * BLOCK;
            const need: i32 = @intCast(@min(BLOCK, b - k * BLOCK)); // the last block may be short on the disk
            if (self.read_block(k, self.buf[at .. at + BLOCK]) < need) return null;
        }
        const skip = a - first * BLOCK;
        return self.buf[skip .. skip + (e - o)];
    }
};

/// The buffer a container of `n` bytes needs at any alignment: its blocks plus one.
pub fn blocksFor(n: u32) u32 {
    return (n / BLOCK + 2) * BLOCK;
}

/// The largest container named by `idx` (u32 LE offsets), or null when they go backwards.
pub fn largest(idx: []const u8) ?u32 {
    var best: u32 = 0;
    var k: usize = 0;
    while (k + 8 <= idx.len) : (k += 4) {
        const o = std.mem.readInt(u32, idx[k..][0..4], .little);
        const e = std.mem.readInt(u32, idx[k + 4 ..][0..4], .little);
        if (e < o) return null;
        best = @max(best, e - o);
    }
    return best;
}

// A fake drive: 4 blocks of a counting pattern, the last one 100 bytes short.
var fake: [4 * BLOCK - 100]u8 = undefined;
fn fakeRead(b: u32, dst: []u8) i32 {
    if (b * BLOCK >= fake.len) return 0;
    const n = @min(BLOCK, fake.len - b * BLOCK);
    @memcpy(dst[0..n], fake[b * BLOCK ..][0..n]);
    return @intCast(n);
}

test "a span across blocks comes back whole, from a file that does not start on a block" {
    for (&fake, 0..) |*v, i| v.* = @truncate(i *% 7);
    var buf: [blocksFor(700)]u8 = undefined;
    const s = Stream{ .start = 300, .len = fake.len - 300, .buf = &buf, .read_block = fakeRead };
    const got = s.read(100, 800).?; // disk bytes 400..1100: blocks 0..2
    try std.testing.expectEqualSlices(u8, fake[400..1100], got);
    const tail = s.read(fake.len - 300 - 10, fake.len - 300).?; // the file's last bytes, in the short block
    try std.testing.expectEqualSlices(u8, fake[fake.len - 10 ..], tail);
}

test "out of the file, a buffer too small or a short drive is refused" {
    var buf: [blocksFor(100)]u8 = undefined;
    const s = Stream{ .start = 0, .len = 4 * BLOCK, .buf = &buf, .read_block = fakeRead };
    try std.testing.expect(s.read(10, 10) == null);
    try std.testing.expect(s.read(0, 4 * BLOCK + 1) == null);
    try std.testing.expect(s.read(0, 3 * BLOCK) == null); // 3 blocks in a 2-block buffer
    try std.testing.expect(s.read(4 * BLOCK - 50, 4 * BLOCK) == null); // the drive ends 100 bytes early
}

test "the largest container, and offsets that go backwards" {
    const idx = [_]u8{ 0, 0, 0, 0, 10, 0, 0, 0, 40, 0, 0, 0, 45, 0, 0, 0 };
    try std.testing.expectEqual(@as(?u32, 30), largest(&idx));
    const bad = [_]u8{ 10, 0, 0, 0, 5, 0, 0, 0 };
    try std.testing.expectEqual(@as(?u32, null), largest(&bad));
}
