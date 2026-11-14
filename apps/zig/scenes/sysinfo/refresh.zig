// --------------------------------------------------------------------------
// SysInfo — a refresh: the host's frame period measured, the page composed from
// what the app holds (pages.Ctx) and projected onto the screen mode's glass
// (view.zig). sysinfo.zig's render() calls these; nothing here draws.
// --------------------------------------------------------------------------
const App = @import("../sysinfo.zig").App;
const bench = @import("bench.zig");
const pages = @import("pages.zig");
const view = @import("view.zig");

/// The host's real frame period, averaged since the last tick.
pub fn tick(app: *App) void {
    const now = bench.micros();
    const n = app.frames -% app.last_frames;
    if (now != 0 and app.last_us != 0 and n != 0) app.frame_us = (now -% app.last_us) / n;
    app.last_us = now;
    app.last_frames = app.frames;
}

pub fn compose(app: *App) void {
    const c = pages.Ctx{
        .os = app.os,
        .bench = &app.bench,
        .blit = app.blit_probe,
        .disk = app.disk,
        .files = app.files[0..app.nfiles],
        .snd = &app.snd.files,
        .gem_ok = app.g.h != 0,
        .dialog_ok = app.dialog.h != 0,
        .frame_us = app.frame_us,
        .id = &app.id,
        .ref = app.ref,
    };
    pages.compose(&app.text, app.page, &c);
    view.project(&app.text, &app.want, app.mode, app.right);
}
