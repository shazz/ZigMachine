//! Tests for handoff.zig over a fake stack allocator: the producer records pictures, the consumer
//! reads them, a part outside the pair frees the store (the stack falls back), a reopen by the same
//! pair keeps it, and the failures (no room before the consumer's reserve, a full store).
const std = @import("std");
const handoff = @import("handoff.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Mem = struct {
    var arena: [4096]u8 align(8) = undefined;
    var top: usize = 0;
    var logs: u32 = 0;
    pub const Mark = usize;
    pub fn mark() Mark {
        return top;
    }
    pub fn release(m: Mark) void {
        top = m;
    }
    pub fn free() usize {
        return arena.len - top;
    }
    pub fn alloc(comptime T: type, n: usize) ?[]T {
        const bytes = n * @sizeOf(T);
        if (bytes > free()) return null;
        const p: [*]T = @ptrCast(@alignCast(&arena[top]));
        top += bytes;
        return p[0..n];
    }
    pub fn log(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
        logs += 1;
    }
};
const Store = handoff.Store([2]i32, Mem, 4);
const PAIR: handoff.Pair = .{ .from = 5, .to = 6, .bytes = 1024, .reserve = 1024 };

fn record(s: *Store, n: u32, v: i32) void {
    const room = s.next() orelse return;
    for (0..@min(n, room.len)) |i| room[i] = .{ v, @intCast(i) };
    s.commit(n);
}

test "the producer records, the consumer reads, a part outside the pair frees it" {
    Mem.top = 0;
    var s: Store = .{};
    s.open(PAIR);
    try expectEqual(@as(usize, 1024), Mem.top);
    record(&s, 10, 1);
    record(&s, 20, 2);
    try expectEqual(@as(usize, 20), s.picture(6, 1).?.len);
    try expectEqual(@as(i32, 2), s.picture(6, 1).?[19][0]);
    try expect(s.picture(7, 0) == null); // not this consumer
    try expect(s.picture(6, 2) == null); // not recorded
    s.enter(6); // the consumer starts: kept
    try expect(s.picture(6, 0) != null);
    s.open(PAIR); // a restart of the producer: kept
    try expectEqual(@as(u32, 2), s.ready);
    s.enter(9); // another part: freed
    try expectEqual(@as(usize, 0), Mem.top);
    try expect(s.picture(6, 0) == null);
}

test "no room for the store and the consumer's reserve: no store, nothing allocated" {
    Mem.top = 2500;
    var s: Store = .{};
    s.open(PAIR);
    try expect(s.mark == null);
    try expectEqual(@as(usize, 2500), Mem.top);
    try expect(s.next() == null);
}

test "a picture that does not fit fills the store; at most MAXP pictures" {
    Mem.top = 0;
    var s: Store = .{};
    s.open(PAIR); // 128 pairs
    record(&s, 100, 1);
    record(&s, 100, 2); // 200 > 128: full
    try expect(s.full);
    try expectEqual(@as(u32, 1), s.ready);
    try expect(s.next() == null);
    s.close();
    s.open(PAIR);
    for (0..5) |_| record(&s, 1, 3);
    try expectEqual(@as(u32, 4), s.ready);
    s.close();
}
