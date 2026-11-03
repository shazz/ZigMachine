// The shelf: every .zmd on the SD card's shelf directory, in the order of the
// titles the menu shows (case ignored, then file name), with the title its
// descriptor carries. Only the header is read here (the menu
// needs titles, not carts); the loader reads the whole disk when one is chosen.
// A file that is not a disk is listed under its file name, marked, so a bad
// copy is visible in the menu instead of silently missing. shelf.txt (meta.zig)
// gives a disk its catalog title, group, year and description when it lists it.
//
// Folders (docs/FPGA_GLASS.md, "The menu"): a disk sits at the shelf's top (a flat,
// older card) or one level down, in a category folder (demos/, games/, ...:
// fpga/tools/shelf_category.py). The menu shows the folders first (shelf_view.zig).
// A disk is still known by its bare FILE name everywhere (the control channel,
// glass.cfg's drive A, a cart's REQ_LOAD_CART, progs/demo-<tag>/): its folder only
// says where it is read from. progs/ and kos/ are the shelf's own, never folders.
const std = @import("std");
const zmd = @import("zmd.zig");
const meta = @import("meta.zig");

pub const MAX_DISK = 16 << 20; // the host's disk cap (docs/FLOPPY_DISK.md)
const HEADER = 0xC00; // v2's boot sector + descriptor + FAT; v1 needs less
pub const MAX_FOLDER = 24; // a longer directory name is not a category folder
const NOT_FOLDERS = [_][]const u8{ "progs", "kos" }; // a data disk's programs, KOS's desktop

pub const Disk = struct { file: []const u8, title: []const u8, folder: []const u8 = "", meta: ?meta.Meta = null };

pub const Shelf = struct {
    arena: std.heap.ArenaAllocator,
    disks: []Disk = &.{},
    titles: [][]const u8 = &.{},
    table: meta.Table = .{},

    pub fn deinit(self: *Shelf) void {
        self.arena.deinit();
    }

    pub fn path(self: *Shelf, dir: []const u8, i: usize) ![]const u8 {
        const d = self.disks[i];
        const a = self.arena.allocator();
        if (d.folder.len == 0) return std.fs.path.join(a, &.{ dir, d.file });
        return std.fs.path.join(a, &.{ dir, d.folder, d.file });
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

fn isFolder(e: std.Io.Dir.Entry) bool {
    if (e.kind != .directory or e.name.len == 0 or e.name.len > MAX_FOLDER or e.name[0] == '.') return false;
    for (NOT_FOLDERS) |n| if (std.ascii.eqlIgnoreCase(e.name, n)) return false;
    return true;
}

fn isDisk(e: std.Io.Dir.Entry) bool {
    return e.kind == .file and std.ascii.endsWithIgnoreCase(e.name, ".zmd");
}

/// Every disk directly in `dir`, listed as in `folder`; with `sub`, every folder's too.
fn collect(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, folder: []const u8, sub: bool, list: *std.ArrayList(Disk)) !void {
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (isDisk(e)) {
            const name = try a.dupe(u8, e.name);
            try list.append(a, .{ .file = name, .title = try titleOf(a, io, dir, name), .folder = folder });
        } else if (sub and isFolder(e)) {
            var child = dir.openDir(io, e.name, .{ .iterate = true }) catch |err| {
                std.log.warn("shelf: folder {s}: {t}", .{ e.name, err });
                continue;
            };
            defer child.close(io);
            try collect(a, io, child, try a.dupe(u8, e.name), false, list);
        }
    }
}

/// A disk left at the top of a card that also carries it in a folder (an old flat copy
/// nobody deleted) is dropped: the bare name must name ONE disk.
fn dropFlatCopies(list: *std.ArrayList(Disk)) void {
    var i: usize = 0;
    while (i < list.items.len) {
        const d = list.items[i];
        const folder = foldered(list.items, d) orelse {
            i += 1;
            continue;
        };
        std.log.warn("shelf: {s} is in {s}/ too: the flat copy is ignored", .{ d.file, folder });
        _ = list.orderedRemove(i);
    }
}

/// The folder that also holds flat disk `d`, if any.
fn foldered(disks: []const Disk, d: Disk) ?[]const u8 {
    if (d.folder.len > 0) return null;
    for (disks) |o| if (o.folder.len > 0 and std.mem.eql(u8, o.file, d.file)) return o.folder;
    return null;
}

pub fn scan(gpa: std.mem.Allocator, io: std.Io, dir_path: []const u8) !Shelf {
    var shelf = Shelf{ .arena = .init(gpa) };
    errdefer shelf.deinit();
    const a = shelf.arena.allocator();
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var list: std.ArrayList(Disk) = .empty;
    try collect(a, io, dir, "", true, &list);
    dropFlatCopies(&list);
    shelf.table = meta.load(a, io, dir) catch |err| blk: {
        std.log.warn("{s}: {t}", .{ meta.FILE, err });
        break :blk .{ .missing = true };
    };
    for (list.items) |*d| if (shelf.table.find(d.folder, d.file)) |m| {
        d.meta = m;
        d.title = m.title;
    };
    std.mem.sort(Disk, list.items, {}, lessByTitle);
    shelf.disks = list.items;
    shelf.titles = try a.alloc([]const u8, list.items.len);
    for (list.items, shelf.titles) |d, *t| t.* = d.title;
    return shelf;
}
