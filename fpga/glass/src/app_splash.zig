// The boot screen at power-on (docs/FPGA_GLASS.md, "Boot splash"; prototypes/boot_screen/STUDY.md):
// the first glass after a power cycle runs KESTREL BOOT (WINDHOVER, cart 131) before KOS, then
// powers KOS on as it always did (app_drive.powerOn). It is a plain cart load: no KOS boot words.
//
//   plays     glass.cfg splash=1 (the default), the first start since power-on, no cart already
//             running in the window, no --no-splash, and the shelf has DISK
//   ends      the cart asks to leave (it does at its black frame 290, 4.8 s; a request before MIN_MS
//             is logged and held until MIN_MS, so the picture cannot vanish at once), or it traps
//             (logged with its code), or a key / pad button (swallowed), or CAP_MS: then KOS powers on
//   yields    a load from elsewhere (glass ctl load) takes the window: the splash just stops
//   alone     no OSD while it plays, neither the menu nor the F11 overlay (`quiet`): from the
//             decision to play until it ends, then the OSD is as without a splash (Matt, 14 Nov:
//             "shows the OSD, then the KESTREL BOOT behind the OSD. The OSD should only appear after")
//
// "First start" is a mark in tmpfs (/tmp, MARK): a power cycle clears it, S99glass's restart loop
// (or a lead's killall glass) finds it. Anything odd (no mark possible, no cart, a failed load)
// means no splash: the boot screen never stands between the console and its menu.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const cart = @import("app_cart.zig");
const drive = @import("app_drive.zig");
const app_stats = @import("app_stats.zig");
const App = @import("app.zig").App;

pub const DISK = "demo-kestrel_boot.zmd";
pub const MARK = "/tmp/glass.splashed";
/// The cart is black and asks to leave 4.8 s in; past this a slow or stuck one is cut short.
pub const CAP_MS: i64 = 9000;
/// A request sooner than this is not the cart's own end (frame 290 is 4833 ms at 60 Hz): it is
/// logged, and the splash ends here instead. The log line says which way it went (MIN_MS, the board
/// test of 14 Nov: no splash seen after the OSD's Reboot, no log to say why).
pub const MIN_MS: i64 = 4000;

/// Why glass did (play) or did not run the splash; main.zig logs it.
pub const Why = enum { play, off, restart, running, asked, missing, failed };

pub const Inputs = struct {
    enabled: bool, // glass.cfg splash=
    first: bool, // the first glass since power-on (firstStart)
    running: bool, // a cart already runs in the window (CART_STATE RUNNING)
    asked: bool, // the command line asked for none (--no-splash): a tool wants the console at once
    disk: ?usize, // DISK's index on the shelf
};

/// The start policy (the top of this file), pure.
pub fn decide(in: Inputs) Why {
    if (!in.enabled) return .off;
    if (in.asked) return .asked;
    if (!in.first) return .restart;
    if (in.running) return .running;
    if (in.disk == null) return .missing;
    return .play;
}

/// The splash under way: `disk` the shelf index it was loaded from (null: none runs); `swallow`
/// the key that skipped it, whose release KOS must not get.
/// `early`: a request came before MIN_MS (logged once). `quiet`: the OSD stays hidden, from the
/// decision to play (before the cart's load) until the splash is over (app_stats.place, App.redraw).
pub const State = struct { disk: ?usize = null, since: i64 = 0, swallow: ?u16 = null, early: bool = false, quiet: bool = false };

/// The OSD must not show: a splash is loading or playing.
pub fn hidesOsd(app: *const App) bool {
    return app.splash.quiet;
}

/// True only for the first call since `path` was cleared (a power cycle, tmpfs): it creates it.
pub fn firstStart(io: std.Io, path: []const u8) bool {
    const f = std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true }) catch |err| {
        if (err != error.PathAlreadyExists) std.log.warn("boot splash: mark {s}: {t}, no splash", .{ path, err });
        return false;
    };
    f.close(io);
    return true;
}

fn find(app: *const App) ?usize {
    for (app.disks.disks, 0..) |d, i| if (std.mem.eql(u8, d.file, DISK)) return i;
    return null;
}

/// main.zig, in place of app_drive.powerOn: the splash if the policy says so, else KOS at once.
/// `no_splash`: glass run --no-splash.
pub fn startOrPowerOn(app: *App, no_splash: bool) Why {
    const state = app.regs.read(map.REG_CART_STATE) & map.CART_STATE_MASK;
    const why = decide(.{
        .enabled = app.menu.settings.splash,
        .asked = no_splash,
        .first = firstStart(app.io, app.splash_mark), // read (and marked) whatever the rest says
        .running = state == map.CART_RUNNING,
        .disk = find(app),
    });
    if (why != .play) {
        app.setOpen(true); // the menu over the KOS load, as App.init shows it (main.zig: initHidden)
        drive.powerOn(app);
        return why;
    }
    const i = find(app).?;
    const t0 = app.clock();
    app.splash.quiet = true;
    app_stats.place(app); // nothing shown yet (initHidden); after App.init's menu: off, before the load
    cart.load(app, i);
    if (!app.running or app.current != i) { // a failed load: KOS as before, the status says why
        std.log.warn("boot splash: {s} did not start, KOS powers on", .{DISK});
        app.splash.quiet = false;
        app.setOpen(true);
        drive.powerOn(app);
        return .failed;
    }
    app.splash = .{ .disk = i, .since = app.clock(), .quiet = true };
    std.log.info("boot splash: {s} up in {d} ms", .{ DISK, app.splash.since - t0 });
    return .play;
}

/// The splash is over: KOS's power-on (drive A, the POST), as glass does without one.
pub fn finish(app: *App, why: []const u8) void {
    if (app.splash.disk == null) return;
    const ms = app.clock() - app.splash.since;
    app.splash = .{};
    std.log.info("boot splash: {s} after {d} ms, KOS powers on", .{ why, ms });
    drive.powerOn(app);
}

/// App.tick, before the watchdog: false when no splash runs (the watchdog's turn). While one
/// runs, its requests and traps are the splash's end, not the watchdog's business.
pub fn tick(app: *App) bool {
    const i = app.splash.disk orelse return false;
    if (!app.running or app.current != i) { // something else was loaded over it
        app.splash = .{};
        app_stats.place(app); // the OSD as that load left it
        return false;
    }
    const word = app.regs.read(map.REG_CART_STATE);
    const state = word & map.CART_STATE_MASK;
    const ms = app.clock() - app.splash.since;
    if (state == mc.CART_REQUEST) {
        if (ms >= MIN_MS) {
            finish(app, if (app.splash.early) "the early request's hold is over" else "the cart is done");
        } else if (!app.splash.early) {
            app.splash.early = true;
            std.log.warn("boot splash: request 0x{x} after only {d} ms, held to {d} ms", .{ word >> map.CART_ARG_SHIFT, ms, MIN_MS });
        }
    } else if (state == map.CART_TRAPPED) {
        std.log.warn("boot splash: trap code 0x{x}", .{word >> map.CART_ARG_SHIFT});
        finish(app, "the cart trapped");
    } else if (ms > CAP_MS) finish(app, "time is up");
    return true;
}

/// A key (`code`, evdev) or a pad button (null) down while the splash runs: it ends, and the
/// press goes no further, nor does that key's release (KOS never saw it go down).
/// False: no splash, the event is the console's as usual.
pub fn skip(app: *App, code: ?u16, down: bool) bool {
    if (app.splash.swallow != null and app.splash.swallow == code and !down) {
        app.splash.swallow = null;
        return true;
    }
    if (app.splash.disk == null) return false;
    if (down) {
        finish(app, "skipped");
        app.splash.swallow = code;
    }
    return true;
}
