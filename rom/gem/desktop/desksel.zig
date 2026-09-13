// --------------------------------------------------------------------------
// Pointer routing and selection. GEM has ONE selection and selects on the
// press: a desktop icon, a file or folder in a window (a file press also arms
// a drag), or — on empty window content — a rubber-band marquee. A file drag
// resolves on release: over the TRASH it deletes, over a folder it copies.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const dirview = @import("dirview.zig");
const deskwin = @import("deskwin.zig");
const desk_icons = @import("desk_icons.zig");
const Desktop = dt.Desktop;
const Rect = gui.Rect;
const View = dirview.View;

pub fn clearSel(d: *Desktop) void {
    d.sel_file = -1;
    d.sel_folder = -1;
    d.sel_icon = -1;
    d.sel_files = 0;
    d.sel_folders = 0;
}
pub fn fileSelected(d: *const Desktop, a: u8) bool {
    return d.sel_file == @as(i16, @intCast(a)) or (d.sel_files >> @intCast(a)) & 1 != 0;
}
pub fn folderSelected(d: *const Desktop, f: u8) bool {
    return d.sel_folder == @as(i16, @intCast(f)) or (d.sel_folders >> @intCast(f)) & 1 != 0;
}

// This frame's pointer, after the windows had first go at it. `busy` = something
// above the desktop (a dialog, a window, an open menu) owns the press.
pub fn routePointer(d: *Desktop, g: *gui.Gui, modal: bool, busy: bool) void {
    if (d.drag) |di| {
        desk_icons.updateDrag(d, g, di);
    } else if (!busy and g.edge and g.py > gui.MENU_H) {
        desk_icons.pressIcon(d, g);
    }
    // A press over a window selects the item under it; a double-click then
    // opens it (requestOpenAt -> launch).
    if (!modal and d.drag == null and g.edge and deskwin.overWindow(d)) {
        pressInWindow(d, @intCast(g.px), @intCast(g.py));
    }
    // Rubber-band: the marquee grows while dragging (drawn in deskdraw); on
    // release, every item it touches becomes selected.
    if (d.band and !g.down) {
        bandSelect(d);
        d.band = false;
    }
    if (!modal and d.file_drag >= 0) updateFileDrag(d, g);
}

// A press in a window: single-select the item under it (arming a file drag), or
// start a rubber-band on empty content.
fn pressInWindow(d: *Desktop, x: i16, y: i16) void {
    const w = deskwin.topFloppy(d) orelse return;
    switch (dirview.dirHitAt(d, w.dir, w.view, x, y)) {
        .file => |a| {
            clearSel(d);
            d.sel_file = a;
            d.file_drag = a; // arm a drag (TRASH = delete, folder = copy)
            d.file_moved = false;
            armFileGrab(d, a, w.view, x, y);
        },
        .folder => |f| {
            clearSel(d);
            d.sel_folder = f;
        },
        .none => {
            clearSel(d);
            if (gui.inRect(w.view.clip, x, y)) { // empty content -> rubber-band
                d.band = true;
                d.band_x = x;
                d.band_y = y;
            }
        },
    }
}

// Record where inside the dragged file's icon the pointer grabbed it, so the
// ghost keeps that offset (GEM never re-centres the outline on the cursor).
// In text view there is no icon box to grab, so fall back to centring.
fn armFileGrab(d: *Desktop, fidx: u8, v: View, x: i16, y: i16) void {
    if (d.view == .icons) {
        const ord = d.dir.order(d.sort);
        var p: usize = 0;
        while (p < d.dir.n_disk) : (p += 1) {
            if (ord[p] != fidx) continue;
            const ic = dirview.fileIconSlot(d, p, fidx, v);
            d.file_gx = x - ic.x;
            d.file_gy = y - ic.y;
            return;
        }
    }
    const bmp = dirview.fileBmp(d, fidx);
    d.file_gx = @divTrunc(@as(i16, @intCast(bmp.w)), 2);
    d.file_gy = @divTrunc(@as(i16, @intCast(bmp.h)), 2);
}

pub fn bandRect(d: *const Desktop) Rect {
    const px: i16 = @intCast(d.g.px);
    const py: i16 = @intCast(d.g.py);
    const x0 = @min(d.band_x, px);
    const y0 = @min(d.band_y, py);
    return .{ .x = x0, .y = y0, .w = @max(d.band_x, px) - x0, .h = @max(d.band_y, py) - y0 };
}

// On marquee release: select every item its rect overlaps.
fn bandSelect(d: *Desktop) void {
    const br = bandRect(d);
    const w = deskwin.topFloppy(d) orelse return;
    const nf = d.dir.fileCount(w.dir);
    if (w.dir == dirmodel.ROOT) {
        const ord = d.dir.order(d.sort);
        var p: usize = 0;
        while (p < d.dir.n_disk) : (p += 1) {
            const a = ord[p];
            const ir = if (d.view == .icons) dirview.fileIconSlot(d, p, a, w.view).rect() else dirview.fileRowRect(p, w.view);
            if (overlap(br, ir)) d.sel_files |= @as(u16, 1) << @intCast(a);
        }
    }
    const fc = d.dir.folderCount(w.dir);
    var rank: usize = 0;
    while (rank < fc) : (rank += 1) {
        const fidx = d.dir.nthFolder(w.dir, rank);
        const ir = if (d.view == .icons) dirview.folderIconSlot(d, nf + rank, fidx, w.view).rect() else dirview.fileRowRect(nf + rank, w.view);
        if (overlap(br, ir)) d.sel_folders |= @as(u16, 1) << @intCast(fidx);
    }
}

fn updateFileDrag(d: *Desktop, g: *gui.Gui) void {
    if (g.down) {
        if (!g.edge) d.file_moved = true;
        return;
    }
    dropFileDrag(d, @intCast(g.px), @intCast(g.py));
    d.file_drag = -1;
    d.file_moved = false;
}

// Resolve a file drag's drop: TRASH = delete, a folder = copy (COPY dialog).
fn dropFileDrag(d: *Desktop, x: i16, y: i16) void {
    if (d.items[desk_icons.IC_TRASH].hitAt(x, y)) {
        d.trash_target = d.file_drag;
        d.trash.open(0, 1);
        return;
    }
    const w = deskwin.topFloppy(d) orelse return;
    switch (dirview.dirHitAt(d, w.dir, w.view, x, y)) {
        .folder => d.copy.openCopy(0, 1), // COPY FOLDERS / ITEMS (cosmetic: disk read-only)
        else => {},
    }
}

fn overlap(a: Rect, b: Rect) bool {
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y;
}
