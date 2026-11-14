// The screenshot's file on the card (shot_file.zig): its 8.3 name, the numbering (after the
// highest, gaps left, past 9999 the lowest free, then full), the folder made, nothing overwritten.
const std = @import("std");
const f = @import("shot_file.zig");

const io = std.testing.io;

test "names are 8.3 and upper case; only SHOT0001..SHOT9999.PNG count, in any case" {
    try std.testing.expectEqualStrings("SHOT0007.PNG", &f.name(7, "PNG"));
    try std.testing.expectEqualStrings("SHOT9999.TMP", &f.name(9999, "TMP"));
    try std.testing.expectEqual(@as(?u16, 12), f.number("SHOT0012.PNG"));
    try std.testing.expectEqual(@as(?u16, 12), f.number("shot0012.png")); // a card written elsewhere
    for ([_][]const u8{ "SHOT0000.PNG", "SHOT12.PNG", "SHOTABCD.PNG", "SHOT0012.TMP", "SHOT00012.PNG", "SNAP0001.PNG", "SHOT+012.PNG" }) |n|
        try std.testing.expectEqual(@as(?u16, null), f.number(n));
}

test "the next number follows the highest; gaps stay gaps; past 9999 the lowest free; then full" {
    var p = f.Picker{};
    try std.testing.expectEqual(@as(u16, 1), try p.pick()); // an empty folder
    for ([_][]const u8{ "SHOT0001.PNG", "SHOT0002.PNG", "SHOT0005.PNG", "README.TXT" }) |n| p.seen(n);
    try std.testing.expectEqual(@as(u16, 6), try p.pick()); // 3 and 4 were deleted: left alone
    p.seen("SHOT9999.PNG");
    try std.testing.expectEqual(@as(u16, 3), try p.pick()); // nothing above 9999: the first gap
    var full = f.Picker{};
    for (1..f.MAX + 1) |i| full.seen(&f.name(@intCast(i), "PNG"));
    try std.testing.expectError(error.Full, full.pick());
}

test "saved under screenshots/ (made when missing), after what is there, never over it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const card = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(card);
    try std.testing.expectEqual(@as(u16, 1), try f.save(io, card, "first"));
    try tmp.dir.writeFile(io, .{ .sub_path = "screenshots/SHOT0041.PNG", .data = "keep me" });
    try std.testing.expectEqual(@as(u16, 42), try f.save(io, card, "second"));
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("first", try tmp.dir.readFile(io, "screenshots/SHOT0001.PNG", &buf));
    try std.testing.expectEqualStrings("keep me", try tmp.dir.readFile(io, "screenshots/SHOT0041.PNG", &buf));
    try std.testing.expectEqualStrings("second", try tmp.dir.readFile(io, "screenshots/SHOT0042.PNG", &buf));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, "screenshots/SHOT0042.TMP", .{})); // renamed
}

test "no card, and a card that refuses the folder, are said as such" {
    try std.testing.expectError(error.NoCard, f.save(io, ".zig-cache/tmp/no-such-card-here", "x"));
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const card = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(card);
    try tmp.dir.writeFile(io, .{ .sub_path = f.DIR, .data = "a file where the folder goes" });
    try std.testing.expectError(error.WriteFailed, f.save(io, card, "x"));
}
