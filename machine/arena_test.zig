// Tests for machine/arena.zig, the RAM arena behind hwRamAlloc: alignment,
// zeroing, exhaustion (returns 0 AND counts), release to a mark, refused marks,
// the undeclared high-water, and what hwRamFree/hwRamUsed report around it.
const std = @import("std");
const arena = @import("arena.zig");
const expectEqual = std.testing.expectEqual;

const BASE: u32 = 0x100000; // memmap.CART_RAM_BASE
var buf: [4096]u8 = undefined;

fn setup(fill: u8) arena.Window {
    @memset(&buf, fill);
    return .{ .base = BASE, .mem = &buf };
}
const HIGH: u32 = BASE + 1001; // an odd high-water, so alignment has work to do

test "an allocation starts at the high-water, aligned, and is zeroed" {
    const w = setup(0xAA);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    const a = arena.alloc(&s, w, HIGH, 100, 16);
    try expectEqual(@as(u32, BASE + 1008), a);
    for (buf[1008..1108]) |b| try expectEqual(@as(u8, 0), b);
    try expectEqual(@as(u8, 0xAA), buf[1108]); // not one byte more
    try expectEqual(@as(u8, 0xAA), buf[1007]); // nor the padding
    try expectEqual(@as(u32, 0), s.failures);
}

test "each alignment is honoured, and alignment 1 packs tight" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    try expectEqual(@as(u32, HIGH), arena.alloc(&s, w, HIGH, 3, 1));
    for ([_]u32{ 2, 4, 8, 64, 256, 1024 }) |al| {
        const a = arena.alloc(&s, w, HIGH, 5, al);
        try expectEqual(@as(u32, 0), a % al);
    }
    try expectEqual(@as(u32, 0), s.failures);
}

test "bad requests fail, return 0 and are counted" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, HIGH, 0, 4)); // zero bytes
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, HIGH, 8, 0)); // zero alignment
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, HIGH, 8, 12)); // not a power of two
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, HIGH, 8, arena.MAX_ALIGN * 2));
    try expectEqual(@as(u32, 4), s.failures);
    try expectEqual(@as(u32, 0), s.top); // nothing was taken
}

test "exhaustion returns 0, counts, and leaves the arena as it was" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    const room = arena.free(s, w, HIGH);
    try expectEqual(@as(u32, 4096 - 1001), room);
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, HIGH, room + 1, 1));
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, HIGH, 0xFFFF_FFFF, 1)); // no u32 wrap
    try expectEqual(@as(u32, 2), s.failures);
    try expectEqual(room, arena.free(s, w, HIGH));
    // exactly what is left still fits, and then the window is full
    try expectEqual(@as(u32, HIGH), arena.alloc(&s, w, HIGH, room, 1));
    try expectEqual(@as(u32, 0), arena.free(s, w, HIGH));
    try expectEqual(@as(u32, 4096), arena.used(s, w, HIGH));
}

test "release to a mark frees what came after it, and the memory is zeroed again" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    _ = arena.alloc(&s, w, HIGH, 10, 1);
    const m = arena.mark(s, w, HIGH);
    const a = arena.alloc(&s, w, HIGH, 200, 4);
    @memset(buf[a - BASE ..][0..200], 0x55); // the part scribbles on its buffer
    arena.release(&s, w, HIGH, m);
    try expectEqual(m, arena.mark(s, w, HIGH));
    const b = arena.alloc(&s, w, HIGH, 200, 4); // the next part gets the same RAM...
    try expectEqual(a, b);
    for (buf[b - BASE ..][0..200]) |x| try expectEqual(@as(u8, 0), x); // ...clean
    try expectEqual(@as(u32, 0), s.failures);
}

test "releasing to the high-water empties the arena" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    const m = arena.mark(s, w, HIGH);
    try expectEqual(HIGH, m);
    _ = arena.alloc(&s, w, HIGH, 64, 8);
    arena.release(&s, w, HIGH, m);
    try expectEqual(@as(u32, 0), s.top);
    try expectEqual(@as(u32, 4096 - 1001), arena.free(s, w, HIGH));
}

test "a mark outside [high-water, top] is refused and counted" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    _ = arena.alloc(&s, w, HIGH, 64, 1);
    const top = s.top;
    arena.release(&s, w, HIGH, HIGH - 1); // into the cart's own statics
    arena.release(&s, w, HIGH, top + 4); // above what was ever allocated
    arena.release(&s, w, HIGH, 0);
    try expectEqual(@as(u32, 3), s.failures);
    try expectEqual(top, s.top);
}

test "no declared high-water: no arena, free/used 0, everything fails loudly" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, 0, 16, 4));
    try expectEqual(@as(u32, 0), arena.alloc(&s, w, BASE + 4096, 16, 4)); // at the top = outside
    try expectEqual(@as(u32, 0), arena.mark(s, w, 0));
    arena.release(&s, w, 0, 0);
    try expectEqual(@as(u32, 3), s.failures);
    try expectEqual(@as(u32, 0), arena.free(s, w, 0));
    try expectEqual(@as(u32, 0), arena.used(s, w, 0));
}

test "free + used always add up to the window, before and after allocating" {
    const w = setup(0);
    var s: arena.State = .{ .top = 0, .failures = 0 };
    try expectEqual(@as(u32, 4096), arena.free(s, w, HIGH) + arena.used(s, w, HIGH));
    try expectEqual(@as(u32, 1001), arena.used(s, w, HIGH));
    _ = arena.alloc(&s, w, HIGH, 777, 32);
    try expectEqual(@as(u32, 4096), arena.free(s, w, HIGH) + arena.used(s, w, HIGH));
    try expectEqual(s.top - BASE, arena.used(s, w, HIGH));
}
