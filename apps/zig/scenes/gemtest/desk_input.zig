// --------------------------------------------------------------------------
// GEMTEST's desktop icons, a frame of input (G16): a press on the desk selects the
// icon under it (objc_find on the WF_NEWDESK tree; the others deselect, an empty
// spot deselects all), a release a few pixels away moves it there (its old and new
// places redrawn where the desk shows), the page's double-click pulse on an icon
// opens it: the Icons area comes up and names it. The drag ghost and the grid: desk_drag.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const O = rom.aes.obj;
const desk = @import("desk.zig");
const drag = @import("desk_drag.zig");
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
    if (app.btn and !edge) if (d.drag) |k| drag.follow(app, k); // the ghost (Mode > Drag ghost)
    if (up) if (d.drag) |k| {
        drag.erase(app);
        if (drag.moved(app)) move(app, k, drag.target(app, k));
        d.drag = null;
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

// Icon `k` moved to `to` (desk_drag.target: on the desk, on the grid if snapping): its old place
// and its new one redrawn.
fn move(app: *App, k: u8, to: [2]i16) void {
    const d = &app.desk;
    const old = d.box(k);
    const o = &d.objs[1 + k];
    o.x = to[0];
    o.y = to[1];
    desk.repaint(app.g, app.mode, old);
    desk.repaint(app.g, app.mode, d.box(k));
}

fn open(app: *App, k: u8) void {
    app.desk.opened = k;
    app.showArea(.icons);
}
