// --------------------------------------------------------------------------
// Where a file or folder dragged out of a window lands (TOS 1.00): on the TRASH it is deleted;
// on a folder (in the top window, or in another window of the same drive), into a drive icon
// (its root), or into another open window (the directory it shows) it is copied there, or
// moved with Control held. A drag of an item that is part of the rubber-band selection carries
// the whole selection. Drive A is write-protected: a copy onto it raises TOS's alert, and its
// own TRASH delete stays the in-memory one (deskops.removeFile). Everything aimed at C: becomes
// a file operation (fileop.zig).
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const dirview = @import("dirview.zig");
const deskwin = @import("deskwin.zig");
const deskdrive = @import("deskdrive.zig");
const desk_icons = @import("desk_icons.zig");
const desksel = @import("desksel.zig");
const fileop = @import("fileop.zig");
const deskbreak = @import("deskbreak.zig");
const Desktop = dt.Desktop;

// A press becomes a drag only once the pointer has moved past this many pixels while held (TOS:
// a few). Below it, a click, or a double-click's presses, stay a click, however long the button
// is held (Matt on the board, 10 Nov: a click on BOOT.WSM in A: became a drop and an alert).
const SLOP = 3;

/// The press of a window item has become a drag.
pub fn started(d: *const Desktop, g: *const gui.Gui) bool {
    if (d.breaks & deskbreak.CLICK != 0) return true; // the mutant: any held frame is a drag
    return @abs(g.px - d.fop.press_x) > SLOP or @abs(g.py - d.fop.press_y) > SLOP;
}

const Target = struct { drv: u1, dir: i16 };

/// The drag of item `d.file_drag` (a folder when d.fop.drag_folder) out of the top window ended at (x, y).
pub fn drop(d: *Desktop, x: i16, y: i16) void {
    const w = deskwin.topFloppy(d) orelse return;
    const it = items(d, w.dir);
    if (onIcon(d, desk_icons.IC_TRASH, x, y)) return toTrash(d, it);
    const t = target(d, w, x, y) orelse return;
    if (t.drv == it.drv and t.dir == it.dir) return; // its own directory: nothing (TOS)
    if (t.drv == deskdrive.A) {
        d.dlg.alert("The disk in drive A: is", "write-protected.");
        return;
    }
    if (it.folders != 0 and t.drv == it.drv and intoItself(d, it, t.dir)) {
        d.dlg.alert("A folder cannot be copied", "into itself.");
        return;
    }
    fileop.copy(d, it, t.drv, t.dir, d.fop.ctrl);
}

// The dragged item, or the whole selection when it is part of it.
fn items(d: *const Desktop, dir: i16) fileop.Items {
    var it = fileop.Items{ .drv = d.drv.cur, .dir = dir };
    const i: u5 = @intCast(d.file_drag);
    const picked = if (d.fop.drag_folder) desksel.folderSelected(d, @intCast(i)) else desksel.fileSelected(d, @intCast(i));
    if (picked and (d.sel_files | d.sel_folders) != 0) {
        it.files = d.sel_files;
        it.folders = d.sel_folders;
    }
    if (d.fop.drag_folder) it.folders |= @as(u16, 1) << @intCast(i) else it.files |= @as(u32, 1) << i;
    return it;
}

fn toTrash(d: *Desktop, it: fileop.Items) void {
    if (it.drv == deskdrive.C) return fileop.delete(d, it);
    if (d.fop.drag_folder) return; // drive A's folders are the model's own: no in-memory delete
    d.trash_target = d.file_drag; // drive A: the in-memory delete, as before
    d.trash.open(0, 1);
}

// What (x, y) is: a folder of the top window, another window's folder or directory, or (on the
// bare desktop only: a window above an icon hides it) a drive icon.
fn target(d: *Desktop, w: deskwin.DirWin, x: i16, y: i16) ?Target {
    switch (dirview.dirHitAt(d, w.dir, w.view, x, y)) {
        .folder => |f| if (!(d.fop.drag_folder and f == d.file_drag)) return .{ .drv = d.drv.cur, .dir = f },
        else => {},
    }
    if (d.breaks & deskbreak.CLICK != 0) if (iconTarget(d, x, y)) |t| return t; // the mutant: icons first
    if (windowAt(d, x, y)) |id| {
        if (id == w.id) return null; // dropped back into its own window: nothing (TOS)
        return windowTarget(d, id, x, y);
    }
    return iconTarget(d, x, y);
}

fn iconTarget(d: *const Desktop, x: i16, y: i16) ?Target {
    if (onIcon(d, desk_icons.IC_FLOPPY, x, y)) return .{ .drv = deskdrive.A, .dir = dirmodel.ROOT };
    if (onIcon(d, desk_icons.IC_HARD, x, y)) return .{ .drv = deskdrive.C, .dir = dirmodel.ROOT };
    return null;
}

// Desktop icon `i` is under (x, y) and not hidden by a window.
fn onIcon(d: *const Desktop, i: usize, x: i16, y: i16) bool {
    if (!desk_icons.shown(d, i) or !d.items[i].hitAt(x, y)) return false;
    return d.breaks & deskbreak.CLICK != 0 or !overAnyWindow(d, x, y);
}

fn overAnyWindow(d: *const Desktop, x: i16, y: i16) bool {
    for (d.wm.wins[0..d.wm.n]) |w| if (w.open and gui.inRect(w.r, x, y)) return true;
    return false;
}

// A folder under the pointer in window `id` (read through its drive's model), else its directory.
fn windowTarget(d: *Desktop, id: u8, x: i16, y: i16) Target {
    const drv = d.drv.win[id];
    const keep = d.drv.cur;
    deskdrive.use(d, drv);
    defer deskdrive.use(d, keep);
    const hit = dirview.dirHitAt(d, d.win_dir[id], deskwin.viewOf(d, id), x, y);
    return switch (hit) {
        .folder => |f| .{ .drv = drv, .dir = f },
        else => .{ .drv = drv, .dir = d.win_dir[id] },
    };
}

// The topmost open directory window under (x, y).
fn windowAt(d: *const Desktop, x: i16, y: i16) ?u8 {
    var i: usize = d.wm.n;
    while (i > 0) {
        i -= 1;
        const id = d.wm.order[i];
        const w = &d.wm.wins[id];
        if (w.open and gui.inRect(w.r, x, y)) return if (deskwin.isFloppyWin(d, id)) id else null;
    }
    return null;
}

// `dir` is one of the dragged folders or inside one.
fn intoItself(d: *const Desktop, it: fileop.Items, dir: i16) bool {
    const m = &d.drives[it.drv];
    var at = dir;
    while (at != dirmodel.ROOT) : (at = m.folders[@intCast(at)].parent) {
        if ((it.folders >> @intCast(at)) & 1 != 0) return true;
    }
    return false;
}
