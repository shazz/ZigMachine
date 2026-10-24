// --------------------------------------------------------------------------
// dancingFate()'s sort of the slices by z (fate.zig), exact and cheap.
//
// The JS sorts with V8's stable Array.sort; the port reproduced that with an
// insertion sort that moved whole 24-byte entries, n^2 of them on the curves
// stored back to front (8-15 Mc a frame on the board). Here each z becomes a
// u64 with the same order as f64 `<` (sign-magnitude bits flipped), ties go
// to the earlier entry, so the order is a strict total one and any sort gives
// the stable order: pdq on indices, n log n integer compares.
// --------------------------------------------------------------------------
const std = @import("std");

/// order[k] = the index of the entry drawn k-th: z ascending, stable.
/// `pos` is an array of anything with an f64 field `z`.
pub fn sort(comptime n: usize, pos: anytype, order: *[n]u8) void {
    var keys: [n]u64 = undefined;
    for (&keys, pos) |*k, p| {
        const bits: u64 = @bitCast(p.z + 0.0); // + 0.0: -0.0 becomes +0.0, as == sees them
        k.* = if (bits >> 63 != 0) ~bits else bits | (1 << 63);
    }
    sortKeys(n, &keys, order);
}

/// order[k] = the index of the k-th smallest key, ties to the earlier index.
pub fn sortKeys(comptime n: usize, keys: *const [n]u64, order: *[n]u8) void {
    comptime std.debug.assert(n <= 256);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    std.sort.pdq(u8, order, keys, Less(n).less);
}

fn Less(comptime n: usize) type {
    return struct {
        fn less(keys: *const [n]u64, a: u8, b: u8) bool {
            return keys[a] < keys[b] or (keys[a] == keys[b] and a < b);
        }
    };
}
