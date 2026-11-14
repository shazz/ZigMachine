// --------------------------------------------------------------------------
// SysInfo — input: the keyboard, the pad, the board's digits and the menu's
// actions, all ending in the same few state changes on the App (which page,
// menu open, alert up, tests running, quit). The App's hooks (sysinfo.zig)
// hand their events here; nothing here draws.
//
//   Space / Return / a click   open the SysInfo Menu (HWAM: right button or Space)
//   F1..F5, 1..5               a page;  Left / Right walk the pages
//   Help                       Program Info;  R  run the speed tests again;  Q  quit
//   L / M / D, F6              low, medium, the desk; F6 the next one (view.zig); Tab: low res's other half
//   on the SOUND page          Up / Down select a file on the disk, P (or Fire) plays it, S stops
//   on the SPEED page          Up / Down or C: the reference machine (refs.zig), the results kept
// --------------------------------------------------------------------------
const App = @import("../sysinfo.zig").App;
const pages = @import("pages.zig");
const menu = @import("menu.zig");
const refs = @import("refs.zig");
const view = @import("view.zig");

const K_TAB: u32 = 0xE019; // docs/sealed-loader.js OWNER_KEY_CODES: a cart that owns the keyboard gets Tab
const INFO = "SysInfo for ZigMachine, after HWAM's SysInfo 8.34";

pub fn key(app: *App, cp: u32) void {
    if (app.dialog.active()) return; // the alert owns input while it is up
    if (app.menu_open) {
        if (menu.key(cp)) |a| act(app, a);
        return;
    }
    if (cp == ' ' or cp == 13) return openMenu(app);
    if (cp >= '1' and cp < '1' + pages.COUNT) return show(app, @enumFromInt(cp - '1'));
    if (app.page == .sound and app.snd.key(cp)) {
        app.dirty = true;
        return;
    }
    if (screenKey(app, cp)) return;
    if (app.page == .speed and (cp == 'c' or cp == 'C')) return nextRef(app, 1);
    const a = menu.key(cp) orelse return;
    if (a != .cancel) act(app, a);
}

/// Left / Right walk the pages, as the board's pad can.
pub fn input(app: *App, dir: u32) void {
    if (app.dialog.active() or app.menu_open) return;
    if (app.page == .sound and app.snd.input(dir)) {
        app.dirty = true;
        return;
    }
    if (app.page == .speed and dir <= 1) return nextRef(app, if (dir == 0) -1 else 1);
    const p: u8 = @intFromEnum(app.page);
    switch (dir) {
        2 => show(app, @enumFromInt((p + pages.COUNT - 1) % pages.COUNT)),
        3 => show(app, @enumFromInt((p + 1) % pages.COUNT)),
        else => {},
    }
}

/// Digits from the board's glass (mode = digit - 1) pick a page too.
pub fn digit(app: *App, mode: u32) void {
    if (mode < pages.COUNT and !app.menu_open and !app.dialog.active()) show(app, @enumFromInt(mode));
}

/// A press this frame: on the menu's buttons while it is up, else it opens it.
pub fn click(app: *App) void {
    if (app.menu_open) {
        if (menu.click(app.g, app.mode)) |a| act(app, a);
    } else if (app.g.edge()) openMenu(app);
}

fn openMenu(app: *App) void {
    app.menu_open = true;
    app.menu_drawn = false;
}

fn act(app: *App, a: menu.Action) void {
    if (app.menu_open) {
        app.menu_open = false;
        app.covered = true; // the dialog drew over the page
    }
    switch (a) {
        .system, .video, .sound, .disk, .speed => show(app, @enumFromInt(@intFromEnum(a))),
        .info => app.dialog.alert("SysInfo", INFO),
        .run => {
            app.bench.start();
            show(app, .speed);
        },
        .rez => nextMode(app),
        .quit => app.wants_quit = true,
        .cancel => {},
    }
}

/// Another screen mode (Setscreen, the ROM's): the desk only where the machine has it.
pub fn setMode(app: *App, m: view.Mode) void {
    if (m == .desk and !app.id.desk_ok) return;
    const desk_off: u32 = @intCast(app.os.lfbs[@import("../sysinfo.zig").PLANE].desk_off);
    const got = @import("rom_sdk").aes.setscreen(app.g, @enumFromInt(@intFromEnum(m)), desk_off) orelse return;
    app.mode = @enumFromInt(@intFromEnum(got));
    app.right = false;
    app.covered = true;
    app.dirty = true;
}

/// L / M / D pick the mode, Tab the other half of a low-res page. True when taken.
fn screenKey(app: *App, cp: u32) bool {
    switch (cp) {
        'l', 'L' => setMode(app, .low),
        'm', 'M' => setMode(app, .medium),
        'd', 'D' => setMode(app, .desk),
        K_TAB => {
            if (app.mode != .low) return false;
            app.right = !app.right;
            app.dirty = true;
        },
        else => return false,
    }
    return true;
}

/// F6: the next mode, low -> medium -> desk (where the machine has it) -> low.
fn nextMode(app: *App) void {
    const next: view.Mode = switch (app.mode) {
        .low => .medium,
        .medium => if (app.id.desk_ok) .desk else .low,
        .desk => .low,
    };
    setMode(app, next);
}

/// The reference machine, a step either way: only the percentages change (pages.compose).
fn nextRef(app: *App, by: i8) void {
    app.ref = refs.step(app.ref, by);
    app.dirty = true;
}

/// A new page; the speed tests start the first time their page is shown.
fn show(app: *App, p: pages.Page) void {
    app.page = p;
    app.dirty = true;
    if (p == .speed and !app.bench.running() and app.bench.results[0].reps == 0) app.bench.start();
}
