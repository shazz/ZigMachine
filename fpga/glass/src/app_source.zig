// F on the shelf: the carts come from the SD card's shelf or from a floppy (Matt, 2026-10-31:
// KESTREL is a small Falcon, and a Falcon booted off a 1.44 MB disk). The floppy is a USB
// floppy drive (usb-storage: /dev/sdX) holding a FAT12 disk with .zmd files, the board's fat
// disks, copied there from a PC. It is mounted read-only at MOUNT; only the CART LIST moves:
// the system image, glass.cfg, KOS's desktop and data disks' programs stay on the SD card.
//
// A floppy is found by its size, not its name: a removable block device of at most FLOPPY_MAX
// sectors (a 2.88 MB disk; a USB stick or card reader is far bigger). F again goes back to the
// SD card and unmounts the floppy, so the disk can be swapped; Shift+F12 on the floppy mounts
// it afresh, which is how a new disk is read without leaving the floppy.
const std = @import("std");
const linux = std.os.linux;
const App = @import("app.zig").App;

pub const MOUNT = "/tmp/zm_floppy";
pub const FLOPPY_MAX = 5760; // 512-byte sectors: 2.88 MB, the biggest floppy there was

/// The first removable block device of floppy size under `<sys_root>/sys/block`, as "sda".
pub fn find(io: std.Io, sys_root: []const u8, buf: []u8) ?[]const u8 {
    var p: [256]u8 = undefined;
    const block = std.fmt.bufPrint(&p, "{s}/sys/block", .{std.mem.trimEnd(u8, sys_root, "/")}) catch return null;
    var dir = std.Io.Dir.cwd().openDir(io, block, .{ .iterate = true }) catch return null;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (!std.mem.startsWith(u8, e.name, "sd")) continue;
        if (readNum(io, dir, e.name, "removable") != 1) continue;
        const size = readNum(io, dir, e.name, "size") orelse continue;
        if (size == 0 or size > FLOPPY_MAX) continue;
        if (e.name.len > buf.len) continue;
        @memcpy(buf[0..e.name.len], e.name);
        return buf[0..e.name.len];
    }
    return null;
}

fn readNum(io: std.Io, dir: std.Io.Dir, dev: []const u8, file: []const u8) ?u64 {
    var p: [64]u8 = undefined;
    const rel = std.fmt.bufPrint(&p, "{s}/{s}", .{ dev, file }) catch return null;
    var b: [32]u8 = undefined;
    const got = dir.readFile(io, rel, &b) catch return null;
    return std.fmt.parseInt(u64, std.mem.trim(u8, got, " \n"), 10) catch null;
}

/// F: switch the cart list between the SD card and the floppy, then read it.
pub fn toggle(app: *App) void {
    if (app.floppy) return useSd(app);
    var name: [16]u8 = undefined;
    const dev = find(app.io, app.sys_root, &name) orelse return app.menu.setStatus("no floppy drive or disk", .{});
    mount(dev) catch |err| return app.menu.setStatus("floppy {s}: {t}", .{ dev, err });
    app.floppy = true;
    app.menu.floppy = true;
    app.disk_dir = MOUNT;
    @import("app_shelf.zig").rescan(app);
}

fn useSd(app: *App) void {
    unmount();
    app.floppy = false;
    app.menu.floppy = false;
    app.disk_dir = app.shelf_dir;
    @import("app_shelf.zig").rescan(app);
}

/// Shift+F12 while on the floppy: a disk swapped since F is read afresh.
pub fn remount(app: *App) !void {
    unmount();
    var name: [16]u8 = undefined;
    const dev = find(app.io, app.sys_root, &name) orelse return error.NoFloppy;
    try mount(dev);
}

fn mount(dev: []const u8) !void {
    _ = linux.mkdir(MOUNT, 0o755); // EEXIST is fine
    var p: [32:0]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&p, "/dev/{s}", .{dev});
    const rc = linux.mount(path, MOUNT, "vfat", linux.MS.RDONLY | linux.MS.NOSUID | linux.MS.NODEV | linux.MS.NOEXEC, 0);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        .NOMEDIUM => return error.NoDisk,
        .INVAL => return error.NotFat,
        else => |e| {
            std.log.warn("mount {s}: {t}", .{ path, e });
            return error.MountFailed;
        },
    }
}

fn unmount() void {
    _ = linux.umount2(MOUNT, 0); // not mounted is fine
}
