// Tests for libs/zig/mem.zig (zg.mem), over a native stand-in for the machine's
// arena with hwRamAlloc's contract: aligned, zeroed, 0 + a counted failure when
// it cannot. The machine side of that contract is proven by machine/arena_test.zig;
// these prove the adapter: typed alloc, std.mem.Allocator, mark/release, and
// that the Allocator's resize/free never lose or leak arena space.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const Fake = struct {
    var buf: [4096]u8 align(64) = undefined;
    var top: usize = 0; // offset into buf
    var fails: u32 = 0;

    fn reset() void {
        @memset(&buf, 0xAA); // the previous cart's garbage
        top = 3; // an odd high-water
        fails = 0;
    }
    fn base() usize {
        return @intFromPtr(&buf);
    }
    pub fn alloc(bytes: usize, alignment: usize) usize {
        if (bytes == 0 or alignment == 0 or !std.math.isPowerOfTwo(alignment)) return fail();
        const at = std.mem.alignForward(usize, base() + top, alignment);
        if (bytes > buf.len or at + bytes > base() + buf.len) return fail();
        @memset(@as([*]u8, @ptrFromInt(at))[0..bytes], 0);
        top = at + bytes - base();
        return at;
    }
    pub fn mark() usize {
        return base() + top;
    }
    pub fn release(m: usize) void {
        if (m < base() + 3 or m > base() + top) {
            _ = fail();
            return;
        }
        top = m - base();
    }
    pub fn failures() u32 {
        return fails;
    }
    pub fn free() usize {
        return buf.len - top;
    }
    fn fail() usize {
        fails += 1;
        return 0;
    }
};

const mem = @import("mem.zig").Mem(Fake);

test "alloc(T, n) is aligned for T and zeroed" {
    Fake.reset();
    _ = mem.alloc(u8, 1).?; // knock the cursor off alignment
    const a = mem.alloc(u64, 10).?;
    try expectEqual(@as(usize, 10), a.len);
    try expectEqual(@as(usize, 0), @intFromPtr(a.ptr) % @alignOf(u64));
    for (a) |x| try expectEqual(@as(u64, 0), x);
    const v = mem.alloc(@Vector(4, u32), 2).?;
    try expectEqual(@as(usize, 0), @intFromPtr(v.ptr) % @alignOf(@Vector(4, u32)));
    try expectEqual(@as(u32, 0), mem.failures());
}

test "a full window returns null and the machine counts it" {
    Fake.reset();
    try expect(mem.alloc(u8, 5000) == null);
    try expect(mem.alloc(u32, std.math.maxInt(usize) / 2) == null); // size overflows usize
    try expectEqual(@as(u32, 2), mem.failures());
    try expect(mem.alloc(u8, 16) != null); // and the arena is untouched
}

test "zero items is an empty slice, not a failure" {
    Fake.reset();
    try expectEqual(@as(usize, 0), mem.alloc(u32, 0).?.len);
    try expectEqual(@as(u32, 0), mem.failures());
}

test "release to a mark hands the same RAM, zeroed, to the next part" {
    Fake.reset();
    const m = mem.mark();
    const part1 = mem.mustAlloc(u16, 100);
    @memset(part1, 0xBEEF);
    mem.release(m);
    const part2 = mem.mustAlloc(u16, 100);
    try expectEqual(@intFromPtr(part1.ptr), @intFromPtr(part2.ptr));
    for (part2) |x| try expectEqual(@as(u16, 0), x);
}

test "std containers run on zg.mem.allocator, growing in place at the top" {
    Fake.reset();
    var list: std.ArrayList(u32) = .empty;
    var i: u32 = 0;
    while (i < 300) : (i += 1) try list.append(mem.allocator, i);
    try expectEqual(@as(u32, 299), list.items[299]);
    // Growing the topmost block bumps the arena instead of copying: the arena
    // holds the list's capacity and a little alignment, not every old buffer.
    try expect(Fake.top < 3 + 4 * list.capacity + 8);
    const buffer = @intFromPtr(list.items.ptr);
    list.deinit(mem.allocator); // topmost: popped back
    try expectEqual(buffer, mem.mark());
    try expectEqual(@as(u32, 0), mem.failures());
}

test "the Allocator refuses loudly when the window is full" {
    Fake.reset();
    try std.testing.expectError(error.OutOfMemory, mem.allocator.alloc(u8, 8192));
    try expectEqual(@as(u32, 1), mem.failures());
}

test "freeing a block that is not the topmost keeps it (no corruption)" {
    Fake.reset();
    const a = try mem.allocator.alloc(u8, 32);
    const b = try mem.allocator.alloc(u8, 32);
    const top = Fake.top;
    mem.allocator.free(a); // not the top: a no-op
    try expectEqual(top, Fake.top);
    mem.allocator.free(b); // the top: popped
    try expectEqual(@intFromPtr(b.ptr) - Fake.base(), Fake.top);
}
