// What the menu's actions do to the console (docs/FPGA_GLASS.md): load a cart,
// cold and warm reset, the watchdog, the volume and its persistence, and the
// debug page's numbers. Free functions over the App, so app.zig stays the
// input path.
//
//   cold reset   = load the same disk again: re-read from the SD card, the window
//                  rewritten (image + zeros), the CPU booted cold
//   warm reset   = loader.warm: the CPU restarted over the memory it has
const std = @import("std");
const build_info = @import("build_info");
const map = @import("map.zig");
const menu = @import("menu.zig");
const shelf = @import("shelf.zig");
const loader = @import("loader.zig");
const config = @import("config.zig");
const board_info = @import("board_info.zig");
const page_debug = @import("page_debug.zig");
const App = @import("app.zig").App;

pub fn act(app: *App, action: menu.Action) void {
    switch (action) {
        .none => {},
        .close => if (app.current != null) app.setOpen(false),
        .load => |i| load(app, i),
        .cold => if (app.menu.loaded) |i| load(app, i) else app.menu.setStatus("no cart to reset", .{}),
        .warm => warm(app),
        .settings => applySettings(app),
        .save => saveSettings(app),
    }
    app.redraw();
}

/// Load disk `i`; on success the OSD closes on the running cart.
pub fn load(app: *App, i: usize) void {
    app.menu.setStatus("loading {s}...", .{app.disks.titles[i]});
    app.redraw();
    const t0 = app.clock();
    const rep = loadDisk(app, i) catch |err| {
        failed(app, i, err);
        app.menu.setStatus("{s}: {t}", .{ app.disks.disks[i].file, err });
        std.log.warn("load {s}: {t}", .{ app.disks.disks[i].file, err });
        return app.redraw();
    };
    app.stats.loaded(app.clock() - t0, rep.fw);
    app.current = i;
    app.menu.loaded = i;
    app.menu.setStatus("{s} running", .{app.disks.titles[i]});
    app.setOpen(false);
}

// A disk refused before the CPU was stopped leaves the old cart running and in
// the window (loader.zig, steps 1 to 3). Past that, the CPU is held; once the
// window was written it holds disk `i`, which is what R and W must then reset.
fn failed(app: *App, i: usize, err: anyerror) void {
    switch (err) {
        error.WontStop => app.current = null,
        error.DdrMismatch, error.CartTrapped, error.CartSilent => {
            app.current = null;
            app.menu.loaded = i;
        },
        else => {},
    }
}

fn loadDisk(app: *App, i: usize) !loader.Report {
    const path = try app.disks.path(app.shelf_dir, i);
    const disk = try std.Io.Dir.cwd().readFileAlloc(app.io, path, app.gpa, .limited(shelf.MAX_DISK));
    defer app.gpa.free(disk);
    const rep = try loader.load(app.gpa, app.regs, app.ddr, disk, app.opt);
    std.log.info("{s}: {d} bytes ({d} packed), up after {d} polls", .{ path, rep.image_bytes, rep.packed_bytes, rep.polls });
    return rep;
}

/// The ST's reset button: only for a cart that is in the window now.
fn warm(app: *App) void {
    const i = app.menu.loaded orelse return app.menu.setStatus("no cart to reset", .{});
    const rep = loader.warm(app.regs, app.opt) catch |err| {
        app.current = null;
        app.stats.last_trap = if (err == error.WarmLost) map.TRAP_WARM_LOST else app.stats.last_trap;
        if (err == error.WarmLost) return app.menu.setStatus("warm reset: memory lost, use R", .{});
        app.menu.setStatus("warm reset: {t}", .{err});
        return std.log.warn("warm reset: {t}", .{err});
    };
    app.stats.fw = rep.fw;
    app.current = i;
    app.menu.setStatus("{s} warm reset", .{app.disks.titles[i]});
    app.setOpen(false);
}

/// Called a few times a second: a cart that trapped brings the menu back.
pub fn watch(app: *App) void {
    if (app.current == null) return;
    app.stats.sample(app.clock(), app.regs.read(map.REG_CART_BEAT));
    const state = app.regs.read(map.REG_CART_STATE);
    if (state & map.CART_STATE_MASK != map.CART_TRAPPED) return;
    _ = loader.hold(app.regs) catch {};
    app.stats.last_trap = state >> map.CART_ARG_SHIFT;
    app.menu.setStatus("cart trapped (code {d})", .{state >> map.CART_ARG_SHIFT});
    app.current = null;
    app.setOpen(true);
}

pub fn loadSettings(app: *App) void {
    const got = config.load(app.io, app.shelf_dir);
    app.menu.settings = got.settings;
    app.regs.write(map.REG_AUDIO_VOL, got.settings.audioWord());
    if (got.bad_line != 0) {
        app.menu.setStatus("{s}: bad line {d}", .{ config.FILE, got.bad_line });
        std.log.warn("{s}: line {d} not understood, its setting keeps the default", .{ config.FILE, got.bad_line });
    } else if (app.disks.table.missing) {
        app.menu.setStatus("no shelf.txt: titles only", .{});
    } else if (app.disks.table.bad_lines != 0) {
        app.menu.setStatus("shelf.txt: {d} bad lines", .{app.disks.table.bad_lines});
    }
}

fn applySettings(app: *App) void {
    app.regs.write(map.REG_AUDIO_VOL, app.menu.settings.audioWord());
    app.settings_dirty = true;
}

/// Persist the settings if they changed (leaving the console page, or the OSD).
pub fn saveSettings(app: *App) void {
    if (!app.settings_dirty) return;
    if (app.sd_writable) |rw| if (!rw(true)) return app.menu.setStatus("not saved: card read-only", .{});
    const res = config.save(app.io, app.shelf_dir, app.menu.settings);
    if (app.sd_writable) |rw| _ = rw(false);
    res catch |err| {
        std.log.warn("{s}: {t}", .{ config.FILE, err });
        return app.menu.setStatus("not saved: {t}", .{err});
    };
    app.settings_dirty = false;
    app.menu.setStatus("settings saved", .{});
}

pub fn debugView(app: *App) page_debug.View {
    const r = app.regs;
    const now = app.clock();
    return .{
        .glass_version = build_info.version,
        .git = build_info.git,
        .pl_id = r.read(map.REG_ID),
        .pl_version = r.read(map.REG_VERSION),
        .fw = if (app.current != null) app.stats.fw else null,
        .cart_state = r.read(map.REG_CART_STATE),
        .beat = r.read(map.REG_CART_BEAT),
        .fps_x10 = app.stats.fps_x10,
        .last_trap = app.stats.last_trap,
        .loads = app.stats.loads,
        .last_load_ms = app.stats.last_load_ms,
        .uptime_s = app.stats.uptimeS(now),
        .load_base = r.read(map.REG_LOAD_BASE),
        .load_size = r.read(map.REG_LOAD_SIZE),
        .board = board_info.read(app.io, app.sys_root),
        .pad = app.pad_name[0..app.pad_name_len],
        .inputs = app.inputs,
    };
}
