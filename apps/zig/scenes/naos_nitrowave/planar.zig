// --------------------------------------------------------------------------
// The shifter's planar -> chunky: four interleaved plane words per 16 pixels,
// bit 15 leftmost, plane k as bit k of the colour index.
// --------------------------------------------------------------------------
const std = @import("std");

/// Plane k's NIBBLE -> four pixel bytes (bit 3 = leftmost), as a little-endian u32, ALREADY
/// shifted to bit k of each pixel: eight pixels are four lookups OR'd, no run-time shifts. The
/// tables are 256 bytes in all: the byte->u64 ones (8 KB) did not fit the 4 KB data cache.
const nib: [4][16]u32 = blk: {
    var t: [4][16]u32 = undefined;
    for (0..4) |plane| for (0..16) |v| {
        var x: u32 = 0;
        for (0..4) |k| x |= @as(u32, (v >> (3 - k)) & 1) << @intCast(8 * k + plane);
        t[plane][v] = x;
    };
    break :blk t;
};

/// One 16-pixel group of four plane words -> 16 palette indices 0..15.
pub fn groupToChunky(q: *const [8]u8, out: *[16]u8) void {
    inline for (0..2) |half| {
        const a = q[half];
        const b = q[2 + half];
        const c = q[4 + half];
        const d = q[6 + half];
        std.mem.writeInt(u32, out[half * 8 ..][0..4], nib[0][a >> 4] | nib[1][b >> 4] | nib[2][c >> 4] | nib[3][d >> 4], .little);
        std.mem.writeInt(u32, out[half * 8 + 4 ..][0..4], nib[0][a & 15] | nib[1][b & 15] | nib[2][c & 15] | nib[3][d & 15], .little);
    }
}

/// Four pixels (quad `qd` of the line, pixel 4 qd..) as one u32.
inline fn quad(line: []const u8, qd: usize) u32 {
    const g = (qd >> 2) * 8 + ((qd >> 1) & 1);
    const hi = qd & 1 == 0;
    const a = line[g];
    const b = line[g + 2];
    const c = line[g + 4];
    const d = line[g + 6];
    return if (hi) nib[0][a >> 4] | nib[1][b >> 4] | nib[2][c >> 4] | nib[3][d >> 4] else nib[0][a & 15] | nib[1][b & 15] | nib[2][c & 15] | nib[3][d & 15];
}

/// `out.len` pixels of a planar line from pixel `first` on: the shifter reads
/// 16-pixel groups from the line's first byte, whatever the address mod 8.
/// Whole groups go straight into `out`; a ragged first or last group is written a
/// pixel quad at a time when `first` and `out.len` are multiples of 4 (a scratch group
/// and a variable-length copy cost more than the conversion).
pub fn lineToChunky(line: []const u8, first: usize, out: []u8) void {
    if (first % 4 == 0 and out.len % 4 == 0) {
        var x: usize = 0;
        var p: usize = first;
        while (x < out.len and p % 16 != 0) : ({
            x += 4;
            p += 4;
        }) std.mem.writeInt(u32, out[x..][0..4], quad(line, p / 4), .little);
        while (x + 16 <= out.len) : ({
            x += 16;
            p += 16;
        }) groupToChunky(line[p / 16 * 8 ..][0..8], out[x..][0..16]);
        while (x < out.len) : ({
            x += 4;
            p += 4;
        }) std.mem.writeInt(u32, out[x..][0..4], quad(line, p / 4), .little);
        return;
    }
    var group: [16]u8 = undefined;
    var g: usize = first / 16;
    const k: usize = first % 16;
    var x: usize = 0;
    if (k != 0 and out.len > 0) {
        groupToChunky(line[g * 8 ..][0..8], &group);
        const n = @min(16 - k, out.len);
        @memcpy(out[0..n], group[k..][0..n]);
        x = n;
        g += 1;
    }
    while (x + 16 <= out.len) : ({
        x += 16;
        g += 1;
    }) groupToChunky(line[g * 8 ..][0..8], out[x..][0..16]);
    if (x < out.len) {
        groupToChunky(line[g * 8 ..][0..8], &group);
        @memcpy(out[x..], group[0 .. out.len - x]);
    }
}

test "lineToChunky reads planes 0..3 as bits 0..3" {
    const line = [_]u8{ 0x80, 0, 0x80, 0, 0, 0, 0x80, 0 } ** 2;
    var out: [20]u8 = undefined;
    lineToChunky(&line, 0, &out);
    try std.testing.expectEqual(@as(u8, 0b1011), out[0]);
    try std.testing.expectEqual(@as(u8, 0), out[1]);
    try std.testing.expectEqual(@as(u8, 0b1011), out[16]);
}

test "the quad path equals the group path for every start and length" {
    var line: [64]u8 = undefined;
    for (&line, 0..) |*b, i| b.* = @truncate(i *% 73 +% 11);
    var a: [48]u8 = undefined;
    var b: [48]u8 = undefined;
    var first: usize = 0;
    while (first <= 32) : (first += 4) {
        var len: usize = 4;
        while (len <= 48) : (len += 4) {
            @memset(&a, 0);
            @memset(&b, 0);
            lineToChunky(&line, first, a[0..len]); // the quad path
            // the reference: whole groups into a scratch picture, then the window
            var pic: [96]u8 = undefined;
            for (0..6) |gi| groupToChunky(line[gi * 8 ..][0..8], pic[gi * 16 ..][0..16]);
            @memcpy(b[0..len], pic[first..][0..len]);
            try std.testing.expectEqualSlices(u8, b[0..len], a[0..len]);
        }
    }
}
