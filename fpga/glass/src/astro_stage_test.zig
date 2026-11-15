// astro_stage.zig: each byte staged at most once a request, never over a kernel's result;
// astro_copy.zig's host path; the mailbox words astro_box.zig reads per op.
const std = @import("std");
const stage = @import("astro_stage.zig");
const copy = @import("astro_copy.zig");
const box = @import("astro_box.zig");
const abi = @import("astro_ops").abi;
const t = std.testing;

fn expectSet(s: *const stage.Set, want: []const [2]u32) !void {
    try t.expectEqual(want.len, s.len);
    for (want, 0..) |w, i| try t.expectEqual(w, [2]u32{ s.lo[i], s.hi[i] });
}

test "a set keeps its ranges sorted and merges what overlaps or touches" {
    var s = stage.Set{};
    s.add(100, 200);
    s.add(10, 20);
    s.add(300, 400);
    try expectSet(&s, &.{ .{ 10, 20 }, .{ 100, 200 }, .{ 300, 400 } });
    s.add(200, 210); // touches: one range
    try expectSet(&s, &.{ .{ 10, 20 }, .{ 100, 210 }, .{ 300, 400 } });
    s.add(15, 350); // swallows two and a half
    try expectSet(&s, &.{.{ 10, 400 }});
    s.add(20, 30); // inside: nothing changes
    try expectSet(&s, &.{.{ 10, 400 }});
}

// The window and the mirror as words; the copies counted, so "once" is checked, not assumed.
var win: [64]u32 = undefined;
var mirror: [64]u32 = undefined;
var loaded: [64]u32 = undefined; // per word: how many times read from the window
var stored: [64]u32 = undefined;

fn countLoad(dst: [*]u32, src: [*]const volatile u32, n: usize) void {
    const at = (@intFromPtr(src) - @intFromPtr(&win)) / 4;
    for (0..n) |i| loaded[at + i] += 1;
    copy.load(dst, src, n);
}

fn countStore(dst: [*]volatile u32, src: [*]const u32, n: usize) void {
    const at = (@intFromPtr(dst) - @intFromPtr(&win)) / 4;
    for (0..n) |i| stored[at + i] += 1;
    copy.store(dst, src, n);
}

fn fresh() stage.Stage {
    for (&win, 0..) |*w, i| w.* = 1000 + @as(u32, @intCast(i));
    @memset(&mirror, 0);
    @memset(&loaded, 0);
    @memset(&stored, 0);
    return .{ .load = countLoad, .store = countStore };
}

test "an array read by several descriptors is read from DDR once" {
    var st = fresh();
    st.begin();
    st.need(&win, &mirror, 16, 32); // words 4..11
    st.need(&win, &mirror, 16, 32);
    st.need(&win, &mirror, 24, 32); // words 6..13: only 12, 13 are new
    for (4..14) |w| try t.expectEqual(@as(u32, 1), loaded[w]);
    try t.expectEqual(@as(u32, 0), loaded[3]);
    try t.expectEqual(@as(u32, 1013), mirror[13]);
    st.flush(&win, &mirror); // nothing written: nothing stored
    for (stored) |n| try t.expectEqual(@as(u32, 0), n);
}

test "a kernel's result is never overwritten by DDR's older copy; written back once" {
    var st = fresh();
    st.begin();
    mirror[8] = 7; // a kernel wrote words 8, 9
    mirror[9] = 8;
    st.wrote(32, 8);
    st.need(&win, &mirror, 24, 24); // words 6..11 as the next descriptor's input
    try t.expectEqual(@as(u32, 7), mirror[8]);
    try t.expectEqual(@as(u32, 8), mirror[9]);
    try t.expectEqual(@as(u32, 0), loaded[8]);
    try t.expectEqual(@as(u32, 1), loaded[6]);
    try t.expectEqual(@as(u32, 1), loaded[10]);
    mirror[10] = 9; // and a third writes word 10
    st.wrote(40, 4);
    st.flush(&win, &mirror);
    try t.expectEqual([3]u32{ 7, 8, 9 }, win[8..11].*);
    for (stored, 0..) |n, i| try t.expectEqual(@as(u32, if (i >= 8 and i <= 10) 1 else 0), n);
    try t.expectEqual(@as(usize, 0), st.dirty.len); // the next request starts clean
}

test "a new request trusts nothing the last one staged" {
    var st = fresh();
    st.begin();
    st.need(&win, &mirror, 0, 16);
    st.flush(&win, &mirror);
    win[1] = 55; // the cart changed it between calls
    st.need(&win, &mirror, 0, 16);
    try t.expectEqual(@as(u32, 55), mirror[1]);
}

test "the bulk copies move every word, whole bursts and the tail" {
    var src: [37]u32 = undefined;
    var dst = [_]u32{0} ** 38;
    for (&src, 0..) |*w, i| w.* = @intCast(i * 3 + 1);
    copy.load(&dst, &src, src.len);
    try t.expectEqualSlices(u32, &src, dst[0..37]);
    try t.expectEqual(@as(u32, 0), dst[37]);
    var back = [_]u32{0} ** 38;
    copy.store(&back, &dst, 37);
    try t.expectEqualSlices(u32, &src, back[0..37]);
    try t.expectEqual(@as(u32, 0), back[37]);
}

test "glass reads a subset of the words ZIGGY copies, and every word a kernel needs" {
    const scalar = [_]u32{ 10, 11, 12, 13, 14, 15 }; // bastro_post.h bastro_copy_in
    const array = [_]u32{ 1, 2, 3, 4, 5, 6, 10, 11 };
    for (0..0x40) |op| {
        const copied: []const u32 = if (box.isScalar(@intCast(op))) &scalar else &array;
        for (box.inWords(@intCast(op))) |w| try t.expect(std.mem.indexOfScalar(u32, copied, w) != null);
    }
    try t.expectEqualSlices(u32, &.{ 10, 11, 12, 13 }, box.inWords(abi.OP_ADD));
    try t.expectEqualSlices(u32, &.{ 10, 11 }, box.inWords(abi.OP_SIN | abi.TYPE_F32));
    try t.expectEqualSlices(u32, &.{ 10, 11, 12, 13, 14, 15 }, box.inWords(abi.OP_FMA));
    try t.expectEqual(@as(usize, 0), box.inWords(abi.OP_NOP).len);
}
