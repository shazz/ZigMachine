// --------------------------------------------------------------------------
// The shifter's planar -> chunky for the parts' per-frame capture: same pixels
// as swedish_newyear/st.zig's, but the four plane tables are PRE-SHIFTED to
// their bit (a group is four loads OR'd, no multi-word run-time shifts on a
// 32-bit CPU). 8 KB, built here at compile time from the plane/bit rule: plane
// k's byte (bit 7 leftmost) becomes bit k of eight pixel bytes.
// --------------------------------------------------------------------------
const std = @import("std");

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

/// One 16-pixel group of four plane words -> 16 palette indices.
pub fn groupToChunky(q: *const [8]u8, out: *[16]u8) void {
    inline for (0..2) |half| {
        const v = spread[0][q[half]] | spread[1][q[2 + half]] | spread[2][q[4 + half]] | spread[3][q[6 + half]];
        std.mem.writeInt(u64, out[half * 8 ..][0..8], v, .little);
    }
}

/// 20 groups of four plane words -> 320 palette indices.
pub fn lineToChunky(line: []const u8, out: *[320]u8) void {
    for (0..20) |g| groupToChunky(line[g * 8 ..][0..8], out[g * 16 ..][0..16]);
}

/// One 16-pixel group as four little-endian words of palette indices, in
/// registers: the shifter compares them with the plane and stores only the
/// words that differ (a store is a blocking bus write on the board).
pub inline fn groupWords(q: *const [8]u8) [4]u32 {
    var w: [4]u32 = undefined;
    inline for (0..2) |half| {
        const v = spread[0][q[half]] | spread[1][q[2 + half]] | spread[2][q[4 + half]] | spread[3][q[6 + half]];
        w[2 * half] = @truncate(v);
        w[2 * half + 1] = @truncate(v >> 32);
    }
    return w;
}

test "groupWords is groupToChunky's 16 bytes as words" {
    const q = [8]u8{ 0x81, 0x7E, 0x0F, 0xF0, 0xAA, 0x55, 0x01, 0x80 };
    var out: [16]u8 = undefined;
    groupToChunky(&q, &out);
    const w = groupWords(&q);
    for (0..4) |i| try std.testing.expectEqual(std.mem.readInt(u32, out[4 * i ..][0..4], .little), w[i]);
}
