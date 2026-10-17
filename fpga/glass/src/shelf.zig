// The shelf: every .zmd on the SD card's shelf directory, in the order of the
// titles the menu shows (case ignored, then file name), with the title its
// descriptor carries. Only the header is read here (the menu
// needs titles, not carts); the loader reads the whole disk when one is chosen.
// A file that is not a disk is listed under its file name, marked, so a bad
// copy is visible in the menu instead of silently missing. shelf.txt (meta.zig)
// gives a disk its catalog title, group, year and description when it lists it.
const std = @import("std");
const zmd = @import("zmd.zig");
const meta = @import("meta.zig");

pub const MAX_DISK = 16 << 20; // the host's disk cap (docs/FLOPPY_DISK.md)
const HEADER = 0xC00; // v2's boot sector + descriptor + FAT; v1 needs less

pub const Disk = struct { file: []const u8, title: []const u8, meta: ?meta.Meta = null };

pub const Shelf = struct {
    arena: std.heap.ArenaAllocator,
    disks: []Disk = &.{},
    titles: [][]const u8 = &.{},
    table: meta.Table = .{},

    pub fn deinit(self: *Shelf) void {
        self.arena.deinit();
    }

    pub fn path(self: *Shelf, dir: []const u8, i: usize) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ dir, self.disks[i].file });
    }
};

// The menu shows titles, so it is sorted by them: by file name, "demo-c-fujiboink"
// landed among the C titles far from "FUJIBOINK (C)" (Matt, 2026-10-17).
fn lessByTitle(_: void, a: Disk, b: Disk) bool {
    return switch (std.ascii.orderIgnoreCase(a.title, b.title)) {
        .lt => true,
        .gt => false,
        .eq => std.mem.lessThan(u8, a.file, b.file),
    };
}

fn titleOf(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, name: []const u8) ![]const u8 {
    const f = try dir.openFile(io, name, .{});
    defer f.close(io);
    var head: [HEADER]u8 = undefined;
    const n = try f.readPositionalAll(io, &head, 0);
    const disk = zmd.parse(head[0..n]) catch return std.fmt.allocPrint(a, "?{s}", .{name});
    if (disk.title.len == 0) return a.dupe(u8, name);
    return a.dupe(u8, disk.title);
}

pub fn scan(gpa: std.mem.Allocator, io: std.Io, dir_path: []const u8) !Shelf {
    var shelf = Shelf{ .arena = .init(gpa) };
    errdefer shelf.deinit();
    const a = shelf.arena.allocator();
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var list: std.ArrayList(Disk) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !std.ascii.endsWithIgnoreCase(e.name, ".zmd")) continue;
        const name = try a.dupe(u8, e.name);
        try list.append(a, .{ .file = name, .title = try titleOf(a, io, dir, name) });
    }
    shelf.table = meta.load(a, io, dir) catch |err| blk: {
        std.log.warn("{s}: {t}", .{ meta.FILE, err });
        break :blk .{ .missing = true };
    };
    for (list.items) |*d| if (shelf.table.find(d.file)) |m| {
        d.meta = m;
        d.title = m.title;
    };
    std.mem.sort(Disk, list.items, {}, lessByTitle);
    shelf.disks = list.items;
    shelf.titles = try a.alloc([]const u8, list.items.len);
    for (list.items, shelf.titles) |d, *t| t.* = d.title;
    return shelf;
}

test "the shelf lists disks by title, titles from their descriptors" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const a = try zmd.testDisk(gpa, "Union Demo", &.{});
    defer gpa.free(a);
    try tmp.dir.writeFile(io, .{ .sub_path = "b-union.zmd", .data = a });
    try tmp.dir.writeFile(io, .{ .sub_path = "a-broken.ZMD", .data = "not a disk" });
    try tmp.dir.writeFile(io, .{ .sub_path = "notes.txt", .data = "ignored" });
    const dir_path = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(dir_path);
    var shelf = try scan(gpa, io, dir_path);
    defer shelf.deinit();
    try std.testing.expectEqual(@as(usize, 2), shelf.disks.len);
    try std.testing.expectEqualStrings("?a-broken.ZMD", shelf.titles[0]);
    try std.testing.expectEqualStrings("Union Demo", shelf.titles[1]);
    try std.testing.expect(shelf.table.missing and shelf.disks[1].meta == null);
    try tmp.dir.writeFile(io, .{ .sub_path = meta.FILE, .data = "b-union.zmd\tUNION DEMO\tThe Union\t1989\n" });
    var again = try scan(gpa, io, dir_path);
    defer again.deinit();
    try std.testing.expectEqualStrings("UNION DEMO", again.titles[1]);
    try std.testing.expectEqualStrings("1989", again.disks[1].meta.?.year);
    try std.testing.expectEqualStrings("?a-broken.ZMD", again.titles[0]); // not listed: its own name
}

test "the shelf sorts by the title shown, not the file name" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][2][]const u8{ .{ "demo-a.zmd", "zebra" }, .{ "demo-b.zmd", "Apple" }, .{ "demo-c.zmd", "mango" } }) |d| {
        const disk = try zmd.testDisk(gpa, d[1], &.{});
        defer gpa.free(disk);
        try tmp.dir.writeFile(io, .{ .sub_path = d[0], .data = disk });
    }
    const dir_path = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(dir_path);
    var shelf = try scan(gpa, io, dir_path);
    defer shelf.deinit();
    try std.testing.expectEqualStrings("Apple", shelf.titles[0]);
    try std.testing.expectEqualStrings("mango", shelf.titles[1]);
    try std.testing.expectEqualStrings("zebra", shelf.titles[2]);
    try std.testing.expectEqualStrings("demo-b.zmd", shelf.disks[0].file);
}
