// --------------------------------------------------------------------------
// Desktop icon interaction — select / drag / snap / open, as free functions
// over *Desktop. The icon itself (model + drawing + geometry + clamp/snap) is
// now the Icon object in icon.zig; this file only orchestrates how the desktop
// reacts to the pointer and drives those Icon methods.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const icon = @import("icon.zig");
const Desktop = dt.Desktop;
const Action = dt.Action;

pub const IC_FLOPPY = 0;
pub const IC_TRASH = 1;

// Disk windows: first one here, each further one cascaded right + down.
pub const WIN_X0: i16 = 24;
pub const WIN_Y0: i16 = 24;
pub const WIN_W: i16 = 320; // wide enough for the TOS text-view columns (name/ext/size/date/time)
pub const WIN_H: i16 = 120;
const CASCADE_DX: i16 = 16;
const CASCADE_DY: i16 = 12;

// Keep icons on-screen (called when the resolution/screen width changes).
pub fn clampIcons(d: *Desktop) void {
    for (&d.items) |*it| it.clampInto(d.g.screen_w, d.g.screen_h);
}

// Icon drag in progress (called from render). GEM drags a dotted GHOST, not the
// icon: the original stays put until the button is released, when the icon jumps
// to the ghost and magnet-snaps to the grid. The ghost itself is drawn in
// Desktop.drawScene from `drag` + the grab offset — see ghostAt below.
pub fn updateDrag(d: *Desktop, g: *gui.Gui, di: u8) void {
    const it = &d.items[di];
    const p = ghostAt(d, g);
    if (!g.down) { // release: the icon lands on the ghost, then snaps to the grid
        if (d.moved) {
            it.x = p.x;
            it.y = p.y;
            it.snap(d.g.screen_w, d.g.screen_h);
        }
        d.drag = null;
        return;
    }
    if (p.x != it.x or p.y != it.y) d.moved = true;
}

// Where the dragged icon's ghost sits this frame: the pointer, less the offset
// inside the icon at which it was grabbed (so the icon does not jump under the
// cursor when the drag starts).
pub fn ghostAt(d: *Desktop, g: *gui.Gui) struct { x: i16, y: i16 } {
    return .{
        .x = @intCast(@as(i32, g.px) - d.grab_dx),
        .y = @intCast(@as(i32, g.py) - d.grab_dy),
    };
}

// A press landed on the desktop (below the menu, no window busy): select the
// icon hit (GEM selects on the press) and arm a drag, or deselect on empty
// desktop. (Opening is a separate native double-click — see requestOpenAt.)
pub fn pressIcon(d: *Desktop, g: *gui.Gui) void {
    for (&d.items, 0..) |*it, i| {
        if (!it.hit(g)) continue;
        d.clearSel(); // GEM has ONE selection: taking a desktop icon drops the rest
        d.sel_icon = @intCast(i);
        d.drag = @intCast(i);
        d.moved = false;
        d.grab_dx = @intCast(@as(i32, g.px) - it.x);
        d.grab_dy = @intCast(@as(i32, g.py) - it.y);
        return;
    }
    d.clearSel(); // pressed empty desktop -> deselect everything
}

// The loader detected a native double-click at (x,y) (logical coords): open the
// icon under the cursor. Windows open here directly; launching an app needs an
// Action, so that is deferred to the next render via pending_open.
pub fn requestOpenAt(d: *Desktop, x: i32, y: i32) void {
    if (d.dlg.active) return;
    d.drag = null; // the double-click's presses armed a drag — a double-click is not a drag
    d.open_src = .{ .x = @as(i16, @intCast(x)) - 16, .y = @as(i16, @intCast(y)) - 12, .w = 32, .h = 24 }; // zoom-box origin
    // Windows sit above the desktop: an item inside the top FLOPPY/folder window
    // opens first. A program launches; a folder opens in its own window.
    if (d.topFloppy()) |w| {
        switch (d.dirHitAt(w.dir, w.view, @intCast(x), @intCast(y))) {
            .file => |a| {
                if (d.diskType(a) == 0) {
                    d.launch_file = @intCast(a); // the host launches it BY NAME
                    d.launch_req = true;
                }
                return;
            },
            .folder => |f| {
                d.openFolderWindow(f);
                return;
            },
            .none => {},
        }
    }
    for (&d.items, 0..) |*it, i| {
        if (!it.hitAt(x, y)) continue;
        d.clearSel();
        d.sel_icon = @intCast(i);
        // Route FLOPPY through render too, so openIcon can decide launch-vs-window
        // (an app-disk turns FLOPPY into the app launcher).
        if (it.is_app or i == IC_FLOPPY or i == IC_TRASH) {
            d.pending_open = @intCast(i); // resolved in render() -> openIcon()
        }
        return;
    }
}

pub fn openIcon(d: *Desktop, di: u8, action: *Action) void {
    if (d.items[di].is_app) {
        d.launch_file = -1; // no file named: launchName() picks the disk's first program
        action.* = .launch;
    } else if (di == IC_FLOPPY) {
        openFloppy(d); // opens a window listing the disk's FAT (files inside open the app)
    } else if (di == IC_TRASH) {
        // The trash is a drop target, not a container — TOS says so verbatim.
        d.dlg.alertLines(&.{
            "You cannot open the trash can",
            "icon into a window. To delete",
            "a folder, document or",
            "application, drag it to the",
            "trash can.",
        }, true);
    }
}

// GEM Desktop: every open of a disk spawns a NEW window (7 max), each one
// cascaded right + down from the previous, wrapping back when it would leave
// the screen. Over the cap, GEM raises the "no more windows" alert.
pub fn openFloppy(d: *Desktop) void {
    if (d.rootEmpty()) { // no disk/cart loaded -> GEM error alert
        d.dlg.alert("Drive A: is empty.", "Insert a disk and try again.");
        return;
    }
    d.addFloppyWindow("A:\\", -1); // opens the root window (cascade + one-icon min size)
}
