// The shelf as the menu lists it (docs/FPGA_GLASS.md, "The menu"): at the top, the category
// folders first (shelf.zig), then any disk lying at the top (a flat, older card: then the list
// is exactly the disks, row = disk index); inside a folder, a ".." row, then its disks.
//
// The menu's cursor is a ROW; everything else (the load action, the 'A' and '*' marks, the
// running cart) holds a DISK index into the shelf. This is the one place that turns one into
// the other. Nothing is allocated: the shelf is a few dozen disks, a row is found by walking it.
const std = @import("std");
const shelf = @import("shelf.zig");

pub const Row = union(enum) { up, folder: []const u8, disk: usize };

pub const View = struct {
    disks: []const shelf.Disk,
    folder: []const u8 = "", // "": the top of the shelf

    pub fn len(v: View) usize {
        if (v.folder.len > 0) return 1 + count(v.disks, v.folder);
        return folderCount(v.disks) + count(v.disks, "");
    }

    pub fn at(v: View, row: usize) ?Row {
        var r = row;
        if (v.folder.len > 0) {
            if (r == 0) return .up;
            r -= 1;
        } else {
            var f: ?[]const u8 = null;
            while (nextFolder(v.disks, f)) |name| : (f = name) {
                if (r == 0) return .{ .folder = name };
                r -= 1;
            }
        }
        for (v.disks, 0..) |d, i| if (std.mem.eql(u8, d.folder, v.folder)) {
            if (r == 0) return .{ .disk = i };
            r -= 1;
        };
        return null;
    }

    /// The row showing disk `disk`, if it is in this view.
    pub fn rowOfDisk(v: View, disk: usize) ?usize {
        for (0..v.len()) |r| if (v.at(r)) |row| switch (row) {
            .disk => |i| if (i == disk) return r,
            else => {},
        };
        return null;
    }

    /// The row of folder `name`, if this is the top and the folder is on it.
    pub fn rowOfFolder(v: View, name: []const u8) ?usize {
        for (0..v.len()) |r| if (v.at(r)) |row| switch (row) {
            .folder => |f| if (std.mem.eql(u8, f, name)) return r,
            else => {},
        };
        return null;
    }
};

/// How many disks are in `folder` ("" the top).
pub fn count(disks: []const shelf.Disk, folder: []const u8) usize {
    var n: usize = 0;
    for (disks) |d| n += @intFromBool(std.mem.eql(u8, d.folder, folder));
    return n;
}

/// The first folder name after `after` (null: the first of all), in byte order.
pub fn nextFolder(disks: []const shelf.Disk, after: ?[]const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    for (disks) |d| {
        if (d.folder.len == 0) continue;
        if (after) |a| if (std.mem.order(u8, d.folder, a) != .gt) continue;
        if (best == null or std.mem.order(u8, d.folder, best.?) == .lt) best = d.folder;
    }
    return best;
}

pub fn folderCount(disks: []const shelf.Disk) usize {
    var n: usize = 0;
    var f: ?[]const u8 = null;
    while (nextFolder(disks, f)) |name| : (f = name) n += 1;
    return n;
}

/// The disk a name given from outside means (the control channel's `load`): the bare file
/// ("demo-joust.zmd"), or its path under the shelf ("games/demo-joust.zmd", even with a leading
/// "zigmachine/"). A path finds the disk in that folder, or the same file lying flat (an older
/// card); the exact case first, then any.
pub fn find(disks: []const shelf.Disk, name: []const u8) ?usize {
    const file = std.fs.path.basenamePosix(name);
    const dir = std.fs.path.dirnamePosix(name) orelse "";
    const folder = std.fs.path.basenamePosix(dir);
    for ([_]bool{ true, false }) |exact| for (disks, 0..) |d, i| {
        const same = if (exact) std.mem.eql(u8, d.file, file) else std.ascii.eqlIgnoreCase(d.file, file);
        if (same and (folder.len == 0 or d.folder.len == 0 or std.ascii.eqlIgnoreCase(d.folder, folder))) return i;
    };
    return null;
}

/// Whether disk `i` (if any) is in folder `name`: a folder row carries its disks' marks.
pub fn holds(disks: []const shelf.Disk, i: ?usize, name: []const u8) bool {
    const k = i orelse return false;
    return k < disks.len and std.mem.eql(u8, disks[k].folder, name);
}
