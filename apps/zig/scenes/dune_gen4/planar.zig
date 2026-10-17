// --------------------------------------------------------------------------
// Planar <-> chunky helpers for the ST's bitplane words. Plane k's byte (bit 7
// leftmost) becomes bit k of eight pixel bytes, as a little-endian u64: a table,
// not a 16-step bit loop per word. One table per plane, ALREADY shifted to its
// bit, so a 16-pixel group is four lookups OR'd (multi-word shifts are slow on a
// 32-bit CPU). 8 KB, built here at compile time.
// --------------------------------------------------------------------------
const std = @import("std");

pub const spread: [4][256]u64 = blk: {
    @setEvalBranchQuota(20000);
    var t: [4][256]u64 = undefined;
    for (0..4) |plane| for (0..256) |v| {
        var x: u64 = 0;
        for (0..8) |k| x |= @as(u64, (v >> (7 - k)) & 1) << @intCast(8 * k + plane);
        t[plane][v] = x;
    };
    break :blk t;
};

/// One 16-pixel group: four big-endian plane words (8 bytes) -> 16 indices.
pub fn group(q: *const [8]u8, out: *[16]u8) void {
    inline for (0..2) |half| {
        const v = spread[0][q[half]] | spread[1][q[2 + half]] | spread[2][q[4 + half]] | spread[3][q[6 + half]];
        std.mem.writeInt(u64, out[half * 8 ..][0..8], v, .little);
    }
}
