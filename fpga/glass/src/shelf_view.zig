// The shelf as the menu lists it (docs/FPGA_GLASS.md, "The menu"): in a folder (the top is the
// folder ""), a ".." row unless at the top, then the folders right under it, then its own disks.
// A flat, older card has no folder rows: the list is exactly the disks, row = disk index.
//
// Folders nest (Matt, 7 Nov: CARTS/demos/atari_st/, demos/amiga/, ...): a disk's folder is its
// PATH under the shelf, "demos/atari_st", and a folder row carries the full path of the folder
// it opens; the OSD shows its last part only (label()). ".." goes up ONE level (parent()).
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
        return @intFromBool(v.folder.len > 0) + folderCount(v.disks, v.folder) + direct(v.disks, v.folder);
    }

    pub fn at(v: View, row: usize) ?Row {
        var r = row;
        if (v.folder.len > 0) {
            if (r == 0) return .up;
            r -= 1;
        }
        var f: ?[]const u8 = null;
        while (nextFolder(v.disks, v.folder, f)) |name| : (f = name) {
            if (r == 0) return .{ .folder = name };
            r -= 1;
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

    /// The row of folder `path` (its full path), if it is right under this view's folder.
    pub fn rowOfFolder(v: View, path: []const u8) ?usize {
        for (0..v.len()) |r| if (v.at(r)) |row| switch (row) {
            .folder => |f| if (std.mem.eql(u8, f, path)) return r,
            else => {},
        };
        return null;
    }
};

/// Whether folder path `folder` is `up` or inside it ("" holds everything).
pub fn within(folder: []const u8, up: []const u8) bool {
    if (up.len == 0) return true;
    return std.mem.startsWith(u8, folder, up) and (folder.len == up.len or folder[up.len] == '/');
}

/// The folder right under `up` that holds `folder` (its full path), or null when
/// `folder` is not strictly inside `up`.
pub fn childOf(folder: []const u8, up: []const u8) ?[]const u8 {
    if (folder.len == up.len or !within(folder, up)) return null;
    const from = if (up.len == 0) 0 else up.len + 1;
    const end = std.mem.indexOfScalarPos(u8, folder, from, '/') orelse folder.len;
    return folder[0..end];
}

/// The folder one level up ("" from a top folder).
pub fn parent(folder: []const u8) []const u8 {
    return folder[0 .. std.mem.lastIndexOfScalar(u8, folder, '/') orelse 0];
}

/// A folder path's last part, as the OSD names it.
pub fn leaf(folder: []const u8) []const u8 {
    return std.fs.path.basenamePosix(folder);
}

/// `folder`'s last part upper-cased into `buf`, cut to `max`, '_' shown as a space: the card
/// says "atari_st" (a space would split `glass ctl load`'s path), the OSD "ATARI ST".
pub fn label(buf: []u8, folder: []const u8, max: usize) []const u8 {
    const name = leaf(folder);
    const n = @min(name.len, max, buf.len);
    for (buf[0..n], name[0..n]) |*o, c| o.* = if (c == '_') ' ' else std.ascii.toUpper(c);
    return buf[0..n];
}

/// How many disks are in `folder` itself ("" the top), not in the folders under it.
pub fn direct(disks: []const shelf.Disk, folder: []const u8) usize {
    var n: usize = 0;
    for (disks) |d| n += @intFromBool(std.mem.eql(u8, d.folder, folder));
    return n;
}

/// How many disks are in `folder` or any folder under it: a folder row's count.
pub fn count(disks: []const shelf.Disk, folder: []const u8) usize {
    var n: usize = 0;
    for (disks) |d| n += @intFromBool(within(d.folder, folder));
    return n;
}

/// The first folder right under `in` after `after` (null: the first of all), in byte order.
pub fn nextFolder(disks: []const shelf.Disk, in: []const u8, after: ?[]const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    for (disks) |d| {
        const c = childOf(d.folder, in) orelse continue;
        if (after) |a| if (std.mem.order(u8, c, a) != .gt) continue;
        if (best == null or std.mem.order(u8, c, best.?) == .lt) best = c;
    }
    return best;
}

pub fn folderCount(disks: []const shelf.Disk, in: []const u8) usize {
    var n: usize = 0;
    var f: ?[]const u8 = null;
    while (nextFolder(disks, in, f)) |name| : (f = name) n += 1;
    return n;
}

/// The disk a name given from outside means (the control channel's `load`): the bare file
/// ("demo-joust.zmd"), or a path ending in it ("demos/atari_st/demo-x.zmd", "atari_st/demo-x.zmd",
/// even with a leading "zigmachine/"). A path finds the disk whose folder it names, or the same
/// file lying flat (an older card); the exact case first, then any.
pub fn find(disks: []const shelf.Disk, name: []const u8) ?usize {
    const file = std.fs.path.basenamePosix(name);
    const dir = std.fs.path.dirnamePosix(name) orelse "";
    for ([_]bool{ true, false }) |exact| for (disks, 0..) |d, i| {
        const same = if (exact) std.mem.eql(u8, d.file, file) else std.ascii.eqlIgnoreCase(d.file, file);
        if (same and (dir.len == 0 or d.folder.len == 0 or names(dir, d.folder))) return i;
    };
    return null;
}

/// Whether path `dir` names folder `folder`: one ends the other at a '/' ("zigmachine/demos/atari_st"
/// or "atari_st" for "demos/atari_st"), case ignored. "demos" does not: the disk is not there.
fn names(dir: []const u8, folder: []const u8) bool {
    return endsAt(dir, folder) or endsAt(folder, dir);
}

fn endsAt(long: []const u8, short: []const u8) bool {
    if (!std.ascii.endsWithIgnoreCase(long, short)) return false;
    return long.len == short.len or long[long.len - short.len - 1] == '/';
}

/// Whether disk `i` (if any) is in folder `path` or under it: a folder row carries its disks' marks.
pub fn holds(disks: []const shelf.Disk, i: ?usize, path: []const u8) bool {
    const k = i orelse return false;
    return k < disks.len and within(disks[k].folder, path);
}
