// The shelf: every .zmd on the SD card's shelf directory, by file name, with
// the title its descriptor carries. Only the header is read here (the menu
// needs titles, not carts); the loader reads the whole disk when one is chosen.
// A file that is not a disk is listed under its file name, marked, so a bad
// copy is visible in the menu instead of silently missing.
const std = @import("std");
const zmd = @import("zmd.zig");

pub const MAX_DISK = 16 << 20; // the host's disk cap (docs/FLOPPY_DISK.md)
const HEADER = 0xC00; // v2's boot sector + descriptor + FAT; v1 needs less

pub const Disk = struct { file: []const u8, title: []const u8 };

pub const Shelf = struct {
    arena: std.heap.ArenaAllocator,
    disks: []Disk = &.{},
    titles: [][]const u8 = &.{},

    pub fn deinit(self: *Shelf) void {
        self.arena.deinit();
    }

    pub fn path(self: *Shelf, dir: []const u8, i: usize) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ dir, self.disks[i].file });
    }
};

fn lessByName(_: void, a: Disk, b: Disk) bool {
    return std.mem.lessThan(u8, a.file, b.file);
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
    std.mem.sort(Disk, list.items, {}, lessByName);
    shelf.disks = list.items;
    shelf.titles = try a.alloc([]const u8, list.items.len);
    for (list.items, shelf.titles) |d, *t| t.* = d.title;
    return shelf;
}

test "the shelf lists disks by file name, titles from their descriptors" {
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
}
