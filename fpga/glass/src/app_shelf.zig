// Shift+F12: read the shelf again (docs/FPGA_GLASS.md, "The menu"), so a cart copied to
// the card since glass started (scp, or the card moved to a PC and back) is listed without
// restarting glass, which would kill the running cart.
//
// The shelf is indexed by position, so everything holding an index is carried over BY FILE
// NAME: the running cart (app.current), the disk in the window (menu.loaded) and the cursor
// (a row: its cart's file or its folder's name, keepCursor).
// A running cart whose disk vanished stays listed, copied from the old shelf: the cart is
// still in the window, the watchdog and a cart's requests still need its entry, and R then
// says FileNotFound, which is the truth. A vanished disk that is not running simply goes.
const std = @import("std");
const shelf = @import("shelf.zig");
const page_shelf = @import("page_shelf.zig");
const sv = @import("shelf_view.zig");
const App = @import("app.zig").App;

pub fn rescan(app: *App) void {
    var next = shelf.scan(app.gpa, app.io, app.disk_dir) catch |err| {
        std.log.warn("shelf rescan: {t}", .{err});
        return app.menu.setStatus("shelf: {t}", .{err});
    };
    const old = app.disks.disks;
    const running = if (app.current) |i| old[i] else null;
    if (running) |d| if (find(next.disks, d.file) == null) keep(&next, d) catch |err| {
        next.deinit();
        return app.menu.setStatus("shelf: {t}", .{err});
    };
    app.current = remap(old, next.disks, app.current);
    app.menu.loaded = remap(old, next.disks, app.menu.loaded);
    app.drive = remap(old, next.disks, app.drive); // drive A keeps its disk by name, or empties
    keepCursor(&app.menu.list, old, next.disks);
    app.disks.deinit();
    app.disks = next;
    app.menu.disks = next.disks;
    app.menu.setStatus("{s}: {d} carts", .{ if (app.floppy) "floppy" else "shelf", next.disks.len });
    std.log.info("shelf rescan: {d} carts", .{next.disks.len});
}

/// The cursor stays on its row's cart or folder (rows are positions too); out of a folder
/// that is gone (its last disk removed, or the floppy has none), up to the nearest folder
/// still holding a disk, the top at worst.
fn keepCursor(list: *page_shelf.State, old: []const shelf.Disk, new: []const shelf.Disk) void {
    const was = if (old.len > 0) list.view(old).at(list.cursor) else null;
    while (list.folder_len > 0 and sv.count(new, list.folder()) == 0) list.folder_len = sv.parent(list.folder()).len;
    const v = list.view(new);
    const row: ?usize = if (was) |w| switch (w) {
        .disk => |i| if (find(new, old[i].file)) |k| v.rowOfDisk(k) else null,
        .folder => |f| v.rowOfFolder(f),
        .up => if (list.folder_len > 0) 0 else null,
    } else null;
    list.cursor = row orelse @min(list.cursor, v.len() -| 1);
    list.top = (list.cursor + 1) -| page_shelf.SHOWN; // the cursor's row on screen
}

fn find(disks: []const shelf.Disk, file: []const u8) ?usize {
    for (disks, 0..) |d, i| if (std.mem.eql(u8, d.file, file)) return i;
    return null;
}

fn remap(old: []const shelf.Disk, new: []const shelf.Disk, i: ?usize) ?usize {
    return find(new, old[i orelse return null].file);
}

/// Append the running cart's vanished disk to the new shelf, in the new shelf's arena.
fn keep(s: *shelf.Shelf, d: shelf.Disk) !void {
    const a = s.arena.allocator();
    const disks = try a.alloc(shelf.Disk, s.disks.len + 1);
    const titles = try a.alloc([]const u8, s.disks.len + 1);
    @memcpy(disks[0..s.disks.len], s.disks);
    @memcpy(titles[0..s.disks.len], s.titles);
    disks[s.disks.len] = .{ .file = try a.dupe(u8, d.file), .title = try a.dupe(u8, d.title), .folder = try a.dupe(u8, d.folder) };
    titles[s.disks.len] = disks[s.disks.len].title;
    s.disks = disks;
    s.titles = titles;
}
