// KOS's drive A and resets (docs/ZIGTOS_BOOT.md: KOS, the KESTREL Operating System, is its
// "ZigTOS"). The shelf is the box of disks next to the drive, not a launcher:
//
//   power-on  ZIGGY starts at once, the OSD closed, drive A holding glass.cfg's drive_a=
//   Enter     insert the disk under the cursor and reset (what a demoscener did with the button)
//   I / E     insert / eject without a reset: the running cart sees a media change
//   R / W     reset cold / warm over what drive A holds
//
// A reset boots drive A as KOS's boot program decides (stages 7-12): a disk with a board image
// runs it (a bootable disk, or an older card's data disk that still carries GEM's image); a data
// disk with none gets the desktop over it; an empty drive the desktop alone. The desktop is the
// card's kos/desktop.rv32 (tools/glass_shelf.py stages GEM's board image there). Each reset
// writes the KOS boot words (map_cart.zig): the POST runs, unless glass.cfg says post=0 or a
// Shift key is held. A load that is no reset (a program off the disk, back to the desktop, a
// door's cart: app_request.zig) writes none, so no POST runs, as the browser's swaps show none.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const zmd = @import("zmd.zig");
const plan = @import("plan.zig");
const loader = @import("loader.zig");
const shelf = @import("shelf.zig");
const config = @import("config.zig");
const cart = @import("app_cart.zig");
const App = @import("app.zig").App;

pub const DESKTOP = "kos/desktop.rv32";
pub const Error = error{NoDesktop};

/// main.zig, once the App is up: drive A from glass.cfg, then a cold reset with the OSD closed.
pub fn powerOn(app: *App) void {
    const name = app.menu.settings.drive_a.slice();
    app.drive = find(app, name);
    reset(app, false);
    if (name.len > 0 and app.drive == null) app.menu.setStatus("drive A: no {s} on the card", .{name});
}

fn find(app: *App, file: []const u8) ?usize {
    for (app.disks.disks, 0..) |d, i| if (file.len > 0 and std.mem.eql(u8, d.file, file)) return i;
    return null;
}

/// The reset's KOS flags: the kind, and the POST's frames (none with post=0 or Shift held).
pub fn flags(app: *const App, warm: bool) u32 {
    const skip = !app.menu.settings.post or app.mods.shift_l or app.mods.shift_r;
    const post: u32 = if (skip) 0 else mc.KOS_POST_FRAMES;
    return (if (warm) mc.KOS_WARM else 0) | post << mc.KOS_POST_SHIFT;
}

/// R (cold): drive A booted afresh, as a power cycle.
pub fn reset(app: *App, warm: bool) void {
    if (warm) return cart.warmReset(app, flags(app, true));
    boot(app, flags(app, false), false);
}

/// Enter on the shelf: disk `i` into drive A, then a cold reset.
pub fn insertAndReset(app: *App, i: usize) void {
    setDrive(app, i);
    reset(app, false);
}

/// The control channel's `load DISK` (app_ctl.zig): disk `i` into drive A and a cold boot with no
/// POST, so a remote measurement starts on the cart at once.
pub fn insertAndBoot(app: *App, i: usize) void {
    setDrive(app, i);
    boot(app, 0, false);
}

/// Load what drive A boots. `kos`: the reset's flags (null: no reset, a program quitting back to
/// the desktop over the disk, whose boot sector then does not run again: `skip_sector`).
pub fn boot(app: *App, kos: ?u32, skip_sector: bool) void {
    const what = if (app.drive) |i| app.disks.titles[i] else "the desktop";
    app.menu.setStatus("loading {s}...", .{what});
    app.redraw();
    var opt = app.opt;
    opt.kos = kos;
    opt.skip_boot_sector = skip_sector;
    const t0 = app.clock();
    const rep = bootDrive(app, opt) catch |err| return failed(app, err);
    app.stats.loaded(app.clock() - t0, rep.fw);
    app.current = app.drive;
    app.running = true;
    app.disk_from = rep.disk_from;
    app.menu.loaded = app.drive;
    app.menu.setStatus("{s} running", .{what});
    app.setOpen(false);
}

fn failed(app: *App, err: anyerror) void {
    if (app.drive) |i| cart.failed(app, i, err) else {
        app.stats.failed(err);
        switch (err) { // past loader step 3 the CPU was held: the desktop is gone (cart.failed's rule)
            error.WontStop, error.DdrMismatch, error.CartTrapped, error.CartSilent, error.SystemRefused, error.NoCart => {
                app.current = null;
                app.running = false;
            },
            else => {},
        }
    }
    const name = if (app.drive) |i| app.disks.disks[i].file else "desktop";
    if (err == error.NoDesktop) app.menu.setStatus("no {s} on the card", .{DESKTOP}) else app.menu.setStatus("{s}: {t}", .{ name, err });
    std.log.warn("boot drive A: {s}: {t}", .{ name, err });
    app.setOpen(true);
}

fn bootDrive(app: *App, opt: loader.Options) !loader.Report {
    try loader.checkGlass(app.regs);
    const disk = if (app.drive) |i| try readDisk(app, i) else null;
    defer if (disk) |d| app.gpa.free(d);
    var p = try planBoot(app, disk, opt);
    defer p.deinit(app.gpa);
    return loader.start(app.regs, app.ddr, &p, opt);
}

pub fn readDisk(app: *App, i: usize) ![]u8 {
    const path = try app.disks.path(app.shelf_dir, i);
    return std.Io.Dir.cwd().readFileAlloc(app.io, path, app.gpa, .limited(shelf.MAX_DISK));
}

/// What drive A boots (the top of this file); touches nothing.
pub fn planBoot(app: *App, disk: ?[]const u8, opt: loader.Options) !plan.Plan {
    if (disk) |d| {
        const z = try zmd.parse(d);
        if (z.boardImage()) |_| return loader.planFor(app.gpa, d, app.ddr.bytes(), opt) else |err| if (err != error.NoBoardImage) return err;
        if (z.bootable()) return error.NoBoardImage; // a cart the board has no image of
    }
    const path = try std.fs.path.join(app.gpa, &.{ app.shelf_dir, DESKTOP });
    defer app.gpa.free(path);
    const desk = std.Io.Dir.cwd().readFileAlloc(app.io, path, app.gpa, .limited(shelf.MAX_DISK)) catch |err|
        return if (err == error.FileNotFound) error.NoDesktop else err;
    defer app.gpa.free(desk);
    return plan.planDesktop(app.gpa, desk, disk, app.ddr.bytes(), opt.system);
}

/// Drive A takes disk `i` (null: ejected); glass.cfg keeps it for the next power-on.
fn setDrive(app: *App, i: ?usize) void {
    app.drive = i;
    app.menu.settings.drive_a = config.DiskName.of(if (i) |k| app.disks.disks[k].file else "") orelse .{};
    app.settings_dirty = true;
}

/// I on the shelf: disk `i` into drive A, no reset; a running cart sees the media change.
pub fn insert(app: *App, i: usize) void {
    setDrive(app, i);
    change(app);
}

/// E on the shelf: drive A emptied, no reset.
pub fn eject(app: *App) void {
    setDrive(app, null);
    change(app);
}

fn change(app: *App) void {
    const what = if (app.drive) |i| app.disks.titles[i] else "empty";
    if (!app.running) return app.menu.setStatus("drive A: {s}", .{what});
    @import("app_media.zig").change(app) catch |err| return app.menu.setStatus("drive A: {t}", .{err});
    app.menu.setStatus("drive A: {s} (media change)", .{what});
}
