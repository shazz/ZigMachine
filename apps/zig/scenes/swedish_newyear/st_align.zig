// --------------------------------------------------------------------------
// st.zig's accesses where the 68000's alignment is not ZIGGY's: the 68000 moves
// a long (or a 6-byte plane run) at any even address, and on KESTREL a 32-bit
// load or store that is not 4-aligned TRAPS (~700 cycles, emulated). The common
// aligned case stays inline in st.zig; these take the rest, out of line (inlined
// at every access they made F4's replay loops outgrow ZIGGY's 16 KB I$).
// --------------------------------------------------------------------------
const std = @import("std");

/// Four bytes as a little-endian word, read without a misaligned 32-bit load
/// (it traps on KESTREL): two halves at an address that is only even.
pub inline fn le32(p: *const [4]u8) u32 {
    if (@intFromPtr(p) & 3 == 0) return std.mem.readInt(u32, @as(*align(4) const [4]u8, @alignCast(p)), .little);
    return le32Split(p);
}

// The rare misaligned case out of line: inlined at every long access it made
// F4's replay loops outgrow ZIGGY's 16 KB I$.
pub noinline fn le32Split(p: *const [4]u8) u32 {
    if (@intFromPtr(p) & 1 == 0) return @as(u32, half16(p[2..4])) << 16 | half16(p[0..2]);
    return std.mem.readInt(u32, p, .little);
}

pub noinline fn setLe32Split(p: *[4]u8, v: u32) void {
    if (@intFromPtr(p) & 1 == 0) {
        setHalf16(p[0..2], @truncate(v));
        setHalf16(p[2..4], @truncate(v >> 16));
        return;
    }
    std.mem.writeInt(u32, p, v, .little);
}

pub noinline fn copySplit(d: []u8, s: []const u8) void {
    if ((@intFromPtr(d.ptr) | @intFromPtr(s.ptr) | d.len) & 1 != 0) {
        for (d, s) |*x, y| @as(*volatile u8, x).* = y;
        return;
    }
    var k: usize = 0;
    while (k < d.len) : (k += 2) setHalf16(d[k..][0..2], half16(s[k..][0..2]));
}

pub noinline fn zeroSplit(d: []u8) void {
    if ((@intFromPtr(d.ptr) | d.len) & 1 != 0) {
        for (d) |*x| @as(*volatile u8, x).* = 0;
        return;
    }
    var k: usize = 0;
    while (k < d.len) : (k += 2) setHalf16(d[k..][0..2], 0);
}

// One aligned 16-bit access, as the native (little-endian) u16. Volatile so that
// LLVM cannot merge the two halves of a long back into one 32-bit access (its
// load/store combining assumes the misaligned word is cheap; on KESTREL it traps).
inline fn half16(p: *const [2]u8) u16 {
    return @as(*align(2) const volatile u16, @ptrCast(@alignCast(p))).*;
}

inline fn setHalf16(p: *[2]u8, v: u16) void {
    @as(*align(2) volatile u16, @ptrCast(@alignCast(p))).* = v;
}


test "the split accesses at 2 mod 4 read and write what the plain ones do" {
    var buf: [16]u8 align(4) = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    try std.testing.expectEqual(std.mem.readInt(u32, buf[2..6], .little), le32Split(buf[2..6]));
    setLe32Split(buf[6..10], 0xAABBCCDD);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), std.mem.readInt(u32, buf[6..10], .little));
    copySplit(buf[10..16], buf[0..6]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5 }, buf[10..16]);
    zeroSplit(buf[2..8]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 0, 0, 0, 0, 0, 0, 0xBB }, buf[0..9]);
}
