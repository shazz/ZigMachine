// --------------------------------------------------------------------------
// GEMTEST's desktop icons, a frame of input (G16): a press on the desk selects the
// icon under it (objc_find on the WF_NEWDESK tree; the others deselect, an empty
// spot deselects all), a release a few pixels away moves it there (its old and new
// places redrawn where the desk shows), the page's double-click pulse on an icon
// opens it: the Icons area comes up and names it.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const O = rom.aes.obj;
const desk = @import("desk.zig");
const App = @import("../gemtest.zig").App;

pub fn frame(app: *App) void {
    const edge = app.btn and !app.desk.prev;
    const up = !app.btn and app.desk.prev;
    app.desk.prev = app.btn;
    const d = &app.desk;
    const tr = O.Tree{ .g = app.g, .objs = &d.objs };
    const on = desk.onDesk(app.g, app.px, app.py);
    const hit: ?u8 = if (!on) null else if (tr.find(0, app.px, app.py)) |i| (if (i >= 1) @intCast(i - 1) else null) else null;
    if (app.dbl) {
        app.dbl = false;
        if (hit) |k| return open(app, k);
    }
    if (edge and on) {
        select(app, hit);
        d.drag = hit;
        d.from = .{ app.px, app.py };
    }
    if (up) if (d.drag) |k| {
        d.drag = null;
        const dx = app.px - d.from[0];
        const dy = app.py - d.from[1];
        if (@abs(dx) + @abs(dy) > 3) move(app, k, dx, dy);
    };
}

fn select(app: *App, hit: ?u8) void {
    const d = &app.desk;
    for (0..desk.N) |k| {
        const o = &d.objs[1 + k];
        const want = hit != null and hit.? == k;
        if ((o.state & O.SELECTED != 0) == want) continue;
        o.state ^= O.SELECTED;
        desk.repaint(app.g, app.mode, d.box(k));
    }
}

// Icon `k` moved by (dx, dy), kept on the desk: its old place and its new one redrawn.
fn move(app: *App, k: u8, dx: i32, dy: i32) void {
    const d = &app.desk;
    const old = d.box(k);
    const o = &d.objs[1 + k];
    const root = d.objs[0];
    o.x = @intCast(std.math.clamp(o.x + dx, 0, root.w - o.w));
    o.y = @intCast(std.math.clamp(o.y + dy, 0, root.h - o.h));
    desk.repaint(app.g, app.mode, old);
    desk.repaint(app.g, app.mode, d.box(k));
}

fn open(app: *App, k: u8) void {
    app.desk.opened = k;
    app.showArea(.icons);
}
