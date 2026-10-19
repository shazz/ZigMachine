// --------------------------------------------------------------------------
// SysInfo — input: the keyboard, the pad, the board's digits and the menu's
// actions, all ending in the same few state changes on the App (which page,
// menu open, alert up, tests running, quit). The App's hooks (sysinfo.zig)
// hand their events here; nothing here draws.
//
//   Space / Return / a click   open the SysInfo Menu (HWAM: right button or Space)
//   F1..F5, 1..5               a page;  Left / Right walk the pages
//   Help                       Program Info;  R  run the speed tests again;  Q  quit
// --------------------------------------------------------------------------
const App = @import("../sysinfo.zig").App;
const pages = @import("pages.zig");
const menu = @import("menu.zig");

const INFO = "SysInfo for ZigMachine, after HWAM's SysInfo 8.34";

pub fn key(app: *App, cp: u32) void {
    if (app.dialog.active()) return; // the alert owns input while it is up
    if (app.menu_open) {
        if (menu.key(cp)) |a| act(app, a);
        return;
    }
    if (cp == ' ' or cp == 13) return openMenu(app);
    if (cp >= '1' and cp < '1' + pages.COUNT) return show(app, @enumFromInt(cp - '1'));
    const a = menu.key(cp) orelse return;
    if (a != .cancel) act(app, a);
}

/// Left / Right walk the pages, as the board's pad can.
pub fn input(app: *App, dir: u32) void {
    if (app.dialog.active() or app.menu_open) return;
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
        if (menu.click(app.g)) |a| act(app, a);
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
        .quit => app.wants_quit = true,
        .cancel => {},
    }
}

/// A new page; the speed tests start the first time their page is shown.
fn show(app: *App, p: pages.Page) void {
    app.page = p;
    app.dirty = true;
    if (p == .speed and !app.bench.running() and app.bench.results[0].reps == 0) app.bench.start();
}
