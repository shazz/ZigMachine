// The generators against the original: tables_ref.bin holds the bytes 1988.prg carries at
// the addresses tools/c64_1988_rip.py lists (REF), in that order.
//   zig test apps/zig/scenes/c64_1988/tables_test.zig   (from the repo root)
const std = @import("std");
const T = @import("tables.zig");

const REF = "apps/zig/assets/screens/c64_1988/tables_ref.bin";

fn ref(a: std.mem.Allocator) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, REF, a, .limited(4096));
}

test "logo sines are the original's $6001 and $6065" {
    const r = try ref(std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualSlices(u8, r[0..100], &T.logo_x);
    try std.testing.expectEqualSlices(u8, r[100..140], &T.logo_y);
}

test "scroller X and its MSB are $6397 and $63FC" {
    const r = try ref(std.testing.allocator);
    defer std.testing.allocator.free(r);
    for (0..101) |i| {
        try std.testing.expectEqual(r[140 + i], @as(u8, @truncate(T.scroll_x[i])));
        try std.testing.expectEqual(r[241 + i], @as(u8, @intCast(T.scroll_x[i] >> 8)));
    }
}

test "part 3 column X and MSB are $51CF and $525F" {
    const r = try ref(std.testing.allocator);
    defer std.testing.allocator.free(r);
    for (0..8) |c| for (0..18) |s| {
        try std.testing.expectEqual(r[342 + 18 * c + s], @as(u8, @truncate(T.grid_x[c][s])));
        try std.testing.expectEqual(r[486 + 18 * c + s], @as(u8, @intCast(T.grid_x[c][s] >> 8)));
    };
}

test "ball bounce is $501F and the wipe lines are $E359/$E39F" {
    const r = try ref(std.testing.allocator);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualSlices(u8, r[630..846], &T.bounce_b);
    for (0..70) |k| {
        try std.testing.expectEqual(r[846 + k], @as(u8, @truncate(T.wipeLine(k))));
        try std.testing.expectEqual(r[916 + k], @as(u8, @intCast(T.wipeLine(k) >> 8)));
    }
}

test "a generator off by one is caught" {
    const r = try ref(std.testing.allocator);
    defer std.testing.allocator.free(r);
    var bad = T.logo_x;
    bad[7] +%= 1;
    try std.testing.expect(!std.mem.eql(u8, r[0..100], &bad));
}
