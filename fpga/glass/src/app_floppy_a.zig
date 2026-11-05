// The real floppy in KOS's drive A (docs/KOS_FAT.md F3): D on the shelf takes the USB floppy as it
// is, a FAT12 disk (an Atari or a PC one, any files), not its .zmd carts (F, app_source.zig, lists
// those). glass reads the whole device raw in one sequential pass (a 1.44 MB disk is 2,880
// sectors) and drive A holds that image: a reset boots the desktop over it, a running cart sees
// a media change; the desktop reads its FAT itself (insertDisk(2)), as the browser does with an .ST.
// The firmware tells a FAT image from a .zmd by its content (host/disk_app.h disk_app_fat_image),
// so the descriptor and DISK_MAGIC are a disk's as ever.
const std = @import("std");
const source = @import("app_source.zig");
const shelf = @import("shelf.zig");
const App = @import("app.zig").App;

pub const Error = error{ NoFloppy, NotFat };

pub const isFat = @import("plan.zig").fatImage;

/// The floppy, read raw from /dev/<dev> (app.dev_dir in tests).
pub fn read(app: *App) ![]u8 {
    var name_buf: [32]u8 = undefined;
    const dev = source.find(app.io, app.sys_root, &name_buf) orelse return error.NoFloppy;
    const path = try std.fs.path.join(app.gpa, &.{ app.dev_dir, dev });
    defer app.gpa.free(path);
    const img = try std.Io.Dir.cwd().readFileAlloc(app.io, path, app.gpa, .limited(source.FLOPPY_MAX * 512));
    if (!isFat(img)) {
        app.gpa.free(img);
        return error.NotFat;
    }
    return img;
}

/// D on the shelf: the floppy into drive A; no reset (a running cart sees a media change).
pub fn insert(app: *App) void {
    const img = read(app) catch |err| return app.menu.setStatus("floppy: {t}", .{err});
    const n = carts(img);
    app.gpa.free(img); // read again at the media change or the reset: the disk may be swapped
    @import("app_drive.zig").setFloppy(app);
    // A cart floppy (Matt's first board run, 4 Nov): the desktop shows its .zmd as data files, which
    // is not what a user pressing D on it wants; say where its carts are (the OSD row is short).
    if (n > 0 and app.floppy_a) app.menu.setStatus("A: {d} .zmd carts, F lists them", .{n});
}

/// The .zmd files in a FAT image's root (0 for none, or a disk the reader does not mount).
pub fn carts(img: []const u8) usize {
    const fat = @import("kos_fat");
    var src = img;
    var v = fat.Volume.mount(@import("app_floppy_prog.zig").read, @ptrCast(&src)) catch return 0;
    var entries: [64]fat.Entry = undefined;
    const got = v.list(v.root(), &entries) catch return 0;
    var n: usize = 0;
    for (entries[0..got]) |*e| {
        if (!e.isDir() and std.mem.endsWith(u8, e.nameSlice(), ".ZMD")) n += 1;
    }
    return n;
}
