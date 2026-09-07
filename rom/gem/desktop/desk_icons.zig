// --------------------------------------------------------------------------
// Desktop icon interaction — select / drag / snap / open, as free functions
// over *Desktop. The icon itself (model + drawing + geometry + clamp/snap) is
// now the Icon object in icon.zig; this file only orchestrates how the desktop
// reacts to the pointer and drives those Icon methods.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const Desktop = dt.Desktop;
const Action = dt.Action;

pub const IC_FLOPPY = 0;
pub const IC_TRASH = 1;

// Disk windows: first one here, each further one cascaded right + down.
pub const WIN_X0: i16 = 24;
pub const WIN_Y0: i16 = 24;
pub const WIN_W: i16 = 213; // the reference low-res disk window is 213x99
pub const WIN_H: i16 = 99;
const CASCADE_DX: i16 = 16;
const CASCADE_DY: i16 = 12;

// Keep icons on-screen (called when the resolution/screen width changes).
pub fn clampIcons(d: *Desktop) void {
    for (&d.items) |*it| it.clampInto(d.g.screen_w, d.g.screen_h);
}

// Icon drag in progress (called from render): move the grabbed icon, or on
// release snap it to the grid. A press selected + armed the drag in pressIcon.
pub fn updateDrag(d: *Desktop, g: *gui.Gui, di: u8) void {
    const it = &d.items[di];
    if (!g.down) { // release: magnet-snap to the nearest grid cell
        if (d.moved) it.snap(d.g.screen_w, d.g.screen_h);
        d.drag = null;
        return;
    }
    const nx: i16 = @intCast(@as(i32, g.px) - d.grab_dx);
    const ny: i16 = @intCast(@as(i32, g.py) - d.grab_dy);
    if (nx != it.x or ny != it.y) d.moved = true;
    if (d.moved) {
        it.x = nx;
        it.y = ny;
        it.clampInto(d.g.screen_w, d.g.screen_h); // keep the unit inside the desktop while dragging
    }
}

// A press landed on the desktop (below the menu, no window busy): select the
// icon hit (GEM selects on the press) and arm a drag, or deselect on empty
// desktop. (Opening is a separate native double-click — see requestOpenAt.)
pub fn pressIcon(d: *Desktop, g: *gui.Gui) void {
    for (&d.items, 0..) |*it, i| {
        if (!it.hit(g)) continue;
        d.sel_icon = @intCast(i);
        d.drag = @intCast(i);
        d.moved = false;
        d.grab_dx = @intCast(@as(i32, g.px) - it.x);
        d.grab_dy = @intCast(@as(i32, g.py) - it.y);
        return;
    }
    d.sel_icon = -1; // pressed empty desktop → deselect
}

// The loader detected a native double-click at (x,y) (logical coords): open the
// icon under the cursor. Windows open here directly; launching an app needs an
// Action, so that is deferred to the next render via pending_open.
pub fn requestOpenAt(d: *Desktop, x: i32, y: i32) void {
    if (d.dlg.active) return;
    d.drag = null; // the double-click's presses armed a drag — a double-click is not a drag
    for (&d.items, 0..) |*it, i| {
        if (!it.hitAt(x, y)) continue;
        d.sel_icon = @intCast(i);
        // Route FLOPPY through render too, so openIcon can decide launch-vs-window
        // (an app-disk turns FLOPPY into the app launcher).
        if (it.is_app or i == IC_FLOPPY) {
            d.pending_open = @intCast(i); // resolved in render() -> openIcon()
        }
        return;
    }
}

pub fn openIcon(d: *Desktop, di: u8, action: *Action) void {
    if (d.items[di].is_app or (di == IC_FLOPPY and d.disk_app)) {
        action.* = .launch; // an app icon, or FLOPPY with an app-disk inserted
    } else if (di == IC_FLOPPY) {
        openFloppy(d); // no disk -> the usual FLOPPY window
    }
}

// GEM Desktop: every open of a disk spawns a NEW window (7 max), each one
// cascaded right + down from the previous, wrapping back when it would leave
// the screen. Over the cap, GEM raises the "no more windows" alert.
pub fn openFloppy(d: *Desktop) void {
    const r = d.next_win;
    if (d.wm.tryAdd(.{ .r = r, .title = "FLOPPY DISK", .info = "0 bytes used in 0 items." }) == null) {
        d.dlg.alert("The Desktop has no more windows.", "Please close a window first.");
        return;
    }
    var nx = r.x + CASCADE_DX;
    var ny = r.y + CASCADE_DY;
    if (nx + r.w > d.g.screen_w or ny + r.h > 200) {
        nx = WIN_X0;
        ny = WIN_Y0;
    }
    d.next_win = .{ .x = nx, .y = ny, .w = r.w, .h = r.h };
}
