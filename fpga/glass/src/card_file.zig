// A write to the SD card's FAT that is on the card when the OSD says so (Matt, 14 Nov: board users
// power-cycle freely). The card is mounted read-only and made writable for one change (main.zig
// sdWritable); every change (a screenshot, glass.cfg, wifi.conf) goes:
//
//   replace   the bytes into NAME.tmp, fsync it, rename it over NAME, fsync the directory
//             (a cut mid-write keeps the old file, and the new name is in the FAT once it returns)
//   release   sync(2) (anything else the change left in the cache), then the card read-only again
//
// and only then the status line or the toast says "saved". `sync` is App.reboot.sync_fn, the one
// the Reboot item uses, which the tests replace (the host is never synced by a test).
const std = @import("std");
const App = @import("app.zig").App;

/// `data` as `final` in `d`, through `tmp`: written, fsynced, renamed, the directory fsynced.
pub fn replace(io: std.Io, d: std.Io.Dir, tmp: []const u8, final: []const u8, data: []const u8) !void {
    writeSynced(io, d, tmp, data) catch |e| {
        d.deleteFile(io, tmp) catch {};
        return e;
    };
    d.rename(tmp, d, final, io) catch |e| {
        d.deleteFile(io, tmp) catch {};
        return e;
    };
    try syncDir(io, d);
}

fn writeSynced(io: std.Io, d: std.Io.Dir, name: []const u8, data: []const u8) !void {
    const f = try d.createFile(io, name, .{});
    defer f.close(io);
    try f.writeStreamingAll(io, data);
    try f.sync(io);
}

/// The directory's entries (a rename, a delete) onto the card: fsync(2) on the directory itself.
/// Its own descriptor, opened for reading: a Dir opened without `iterate` is O_PATH, which fsync
/// refuses (EBADF).
pub fn syncDir(io: std.Io, d: std.Io.Dir) !void {
    var own = try d.openDir(io, ".", .{ .iterate = true });
    defer own.close(io);
    const f = std.Io.File{ .handle = own.handle, .flags = .{ .nonblocking = false } };
    try f.sync(io);
}

/// The change is over: sync(2), then the card read-only. False when it stayed writable (logged);
/// the data is on the card either way, the sync came first.
pub fn release(app: *App) bool {
    app.reboot.sync_fn();
    const ro = if (app.sd_writable) |f| f(false) else true;
    if (!ro) std.log.warn("card: synced, but it stayed read-write", .{});
    return ro;
}

test "replace: the new bytes under the final name, no temporary left; an old file replaced whole" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "glass.cfg", .data = "old, longer than the new one\n" });
    try replace(io, tmp.dir, "glass.cfg.new", "glass.cfg", "new\n");
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("new\n", try tmp.dir.readFile(io, "glass.cfg", &buf));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, "glass.cfg.new", .{}));
}

test "replace: a temporary that cannot be made leaves the old file and no temporary" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "wifi.conf", .data = "kept\n" });
    try std.testing.expectError(error.FileNotFound, replace(io, tmp.dir, "no/such/dir.tmp", "wifi.conf", "lost\n"));
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("kept\n", try tmp.dir.readFile(io, "wifi.conf", &buf));
}
