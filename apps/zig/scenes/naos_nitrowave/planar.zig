// --------------------------------------------------------------------------
// The shifter's planar -> chunky: four interleaved plane words per 16 pixels,
// bit 15 leftmost, plane k as bit k of the colour index.
// --------------------------------------------------------------------------
const std = @import("std");

/// Plane k's byte -> eight pixel bytes (bit 7 = leftmost), as a little-endian
/// u64, ALREADY shifted to bit k of each pixel: a group is then four lookups OR'd,
/// no run-time shifts (they are multi-word ops on a 32-bit CPU). 8 KB, built here.
const spread: [4][256]u64 = blk: {
    @setEvalBranchQuota(20000);
    var t: [4][256]u64 = undefined;
    for (0..4) |plane| for (0..256) |v| {
        var x: u64 = 0;
        for (0..8) |k| x |= @as(u64, (v >> (7 - k)) & 1) << @intCast(8 * k + plane);
        t[plane][v] = x;
    };
    break :blk t;
};

/// One 16-pixel group of four plane words -> 16 palette indices 0..15.
pub fn groupToChunky(q: *const [8]u8, out: *[16]u8) void {
    inline for (0..2) |half| {
        const v = spread[0][q[half]] | spread[1][q[2 + half]] | spread[2][q[4 + half]] | spread[3][q[6 + half]];
        std.mem.writeInt(u64, out[half * 8 ..][0..8], v, .little);
    }
}

/// `out.len` pixels of a planar line from pixel `first` on: the shifter reads
/// 16-pixel groups from the line's first byte, whatever the address mod 8.
/// Whole groups go straight into `out`; only the ragged first and last go
/// through a scratch group (a variable-length copy per group cost as much as
/// the conversion).
pub fn lineToChunky(line: []const u8, first: usize, out: []u8) void {
    var group: [16]u8 = undefined;
    var g: usize = first / 16;
    var k: usize = first % 16;
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
