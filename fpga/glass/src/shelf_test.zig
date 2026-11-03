// The shelf's scan (shelf.zig): titles, the sort, and the category folders one level down.
const std = @import("std");
const zmd = @import("zmd.zig");
const meta = @import("meta.zig");
const shelf = @import("shelf.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;

fn put(dir: std.Io.Dir, path: []const u8, title: []const u8) !void {
    const disk = try zmd.testDisk(gpa, title, &.{});
    defer gpa.free(disk);
    try dir.writeFile(io, .{ .sub_path = path, .data = disk });
}

fn scanTmp(tmp: std.testing.TmpDir) !shelf.Shelf {
    const dir_path = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(dir_path);
    return shelf.scan(gpa, io, dir_path);
}

test "the shelf lists disks by title, titles from their descriptors" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try put(tmp.dir, "b-union.zmd", "Union Demo");
    try tmp.dir.writeFile(io, .{ .sub_path = "a-broken.ZMD", .data = "not a disk" });
    try tmp.dir.writeFile(io, .{ .sub_path = "notes.txt", .data = "ignored" });
    var s = try scanTmp(tmp);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 2), s.disks.len);
    try std.testing.expectEqualStrings("?a-broken.ZMD", s.titles[0]);
    try std.testing.expectEqualStrings("Union Demo", s.titles[1]);
    try std.testing.expect(s.table.missing and s.disks[1].meta == null);
    try tmp.dir.writeFile(io, .{ .sub_path = meta.FILE, .data = "b-union.zmd\tUNION DEMO\tThe Union\t1989\n" });
    var again = try scanTmp(tmp);
    defer again.deinit();
    try std.testing.expectEqualStrings("UNION DEMO", again.titles[1]);
    try std.testing.expectEqualStrings("1989", again.disks[1].meta.?.year);
    try std.testing.expectEqualStrings("?a-broken.ZMD", again.titles[0]); // not listed: its own name
}

test "the shelf sorts by the title shown, not the file name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][2][]const u8{ .{ "demo-a.zmd", "zebra" }, .{ "demo-b.zmd", "Apple" }, .{ "demo-c.zmd", "mango" } }) |d|
        try put(tmp.dir, d[0], d[1]);
    var s = try scanTmp(tmp);
    defer s.deinit();
    try std.testing.expectEqualStrings("Apple", s.titles[0]);
    try std.testing.expectEqualStrings("mango", s.titles[1]);
    try std.testing.expectEqualStrings("zebra", s.titles[2]);
    try std.testing.expectEqualStrings("demo-b.zmd", s.disks[0].file);
}

test "disks in category folders are listed with their folder; progs, kos and dot-dirs are not folders" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][]const u8{ "demos", "games", "progs/demo-x", "kos", ".Trash", "empty" }) |d| try tmp.dir.createDirPath(io, d);
    try put(tmp.dir, "demos/demo-stniccc.zmd", "STNICCC");
    try put(tmp.dir, "games/demo-joust.zmd", "JOUST");
    try put(tmp.dir, "demo-flat.zmd", "FLAT");
    try put(tmp.dir, "progs/demo-x/BOOT.WSM.zmd", "A PROGRAM"); // a data disk's program: never a cart
    try put(tmp.dir, "progs/stray.zmd", "STRAY");
    try put(tmp.dir, "kos/desk.zmd", "KOS");
    try put(tmp.dir, ".Trash/demo-gone.zmd", "GONE");
    try tmp.dir.writeFile(io, .{ .sub_path = meta.FILE, .data = "demos/demo-stniccc.zmd\tOXYGENE STNICCC 2000\tOxygene\t2000\n" });
    var s = try scanTmp(tmp);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 3), s.disks.len);
    try std.testing.expectEqualStrings("demo-flat.zmd", s.disks[0].file);
    try std.testing.expectEqualStrings("", s.disks[0].folder);
    try std.testing.expectEqualStrings("games", s.disks[1].folder);
    try std.testing.expectEqualStrings("OXYGENE STNICCC 2000", s.disks[2].title); // shelf.txt by its path
    try std.testing.expectEqualStrings("demos", s.disks[2].folder);
    const p = try s.path("/sd/zigmachine", 2);
    try std.testing.expectEqualStrings("/sd/zigmachine/demos/demo-stniccc.zmd", p);
    try std.testing.expectEqualStrings("/sd/zigmachine/demo-flat.zmd", try s.path("/sd/zigmachine", 0));
}

test "a flat copy of a disk that is also in a folder is dropped: one disk a name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "demos");
    try put(tmp.dir, "demos/demo-a.zmd", "NEW");
    try put(tmp.dir, "demo-a.zmd", "OLD"); // the card before the folders, not cleaned up
    try put(tmp.dir, "demo-b.zmd", "ONLY FLAT");
    var s = try scanTmp(tmp);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 2), s.disks.len);
    try std.testing.expectEqualStrings("NEW", s.disks[0].title);
    try std.testing.expectEqualStrings("demos", s.disks[0].folder);
    try std.testing.expectEqualStrings("ONLY FLAT", s.disks[1].title);
}

test "a shelf directory that is missing is an error, not an empty shelf" {
    try std.testing.expectError(error.FileNotFound, shelf.scan(gpa, io, ".zig-cache/tmp/no-such-shelf-dir"));
}
