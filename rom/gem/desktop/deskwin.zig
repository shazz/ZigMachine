// --------------------------------------------------------------------------
// Directory windows — A:\ and the folder windows. Opening one (cascade,
// remembered geometry, the zoom-box), closing one, and the per-frame chrome
// that depends on what it shows: the GEM info line and the scroll bars.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const icon_mod = @import("icon.zig");
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const dirview = @import("dirview.zig");
const desk_icons = @import("desk_icons.zig");
const deskdraw = @import("deskdraw.zig");
const Desktop = dt.Desktop;
const Rect = gui.Rect;
const View = dirview.View;

pub const WIN_NONE: i16 = -2; // win_dir sentinel: not a FLOPPY/folder window

pub const DirWin = struct { id: u8, dir: i16, view: View };

// win_geom is indexed by directory: ROOT (-1) first, then folder 0..N-1.
fn geomSlot(dir: i16) usize {
    return @intCast(dir + 1);
}

pub fn isFloppyWin(d: *const Desktop, id: u8) bool {
    return d.win_dir[id] != WIN_NONE;
}

// Nothing mounted and no folders yet -> opening A:\ is an error (no disk).
pub fn rootEmpty(d: *const Desktop) bool {
    return d.dir.n_disk == 0 and d.dir.folderCount(dirmodel.ROOT) == 0;
}

// The topmost open FLOPPY/folder window (the one a press just raised).
pub fn topFloppy(d: *Desktop) ?DirWin {
    var wi: usize = d.wm.n;
    while (wi > 0) {
        wi -= 1;
        const id = d.wm.order[wi];
        if (!d.wm.wins[id].open or !isFloppyWin(d, id)) continue;
        return .{ .id = id, .dir = d.win_dir[id], .view = viewOf(d, id) };
    }
    return null;
}

pub fn overWindow(d: *const Desktop) bool {
    for (d.wm.wins[0..d.wm.n]) |w| {
        if (w.open and d.g.px >= w.r.x and d.g.px < w.r.x + w.r.w and
            d.g.py >= w.r.y and d.g.py < w.r.y + w.r.h) return true;
    }
    return false;
}

// The layout frame for window `id`: its content rect, the same rect shifted
// by the scroll offset, and the icon grid width frozen at open time.
pub fn viewOf(d: *Desktop, id: u8) View {
    const c = d.wm.contentRect(id);
    const w = &d.wm.wins[id];
    return .{
        .clip = c,
        .org = .{ .x = c.x - w.hscroll * hStep(d), .y = c.y - w.vscroll * vStep(d), .w = c.w, .h = c.h },
        .cols = d.win_cols[id],
    };
}

// One click of a scroll arrow moves the content by exactly one ITEM: an icon
// cell in icon view, a row / a character cell in text view.
fn vStep(d: *const Desktop) i16 {
    return if (d.view == .icons) icon_mod.CELL_H else dirview.TROW_H;
}
fn hStep(d: *const Desktop) i16 {
    return if (d.view == .icons) icon_mod.CELL_W else gui.CELL;
}

// Open a NEW window on a folder (GEM opens each folder in its own window;
// closing it goes back to the parent).
pub fn openFolderWindow(d: *Desktop, fidx: u8) void {
    const f = &d.dir.folders[fidx];
    addFloppyWindow(d, f.title[0..f.tlen], @intCast(fidx));
}

// Shared open: a FLOPPY/folder window with cascade + the one-icon min size.
pub fn addFloppyWindow(d: *Desktop, title: []const u8, dir: i16) void {
    // A directory that has been open before reopens exactly where it was;
    // a new one takes the next cascade slot.
    const saved = d.win_geom[geomSlot(dir)];
    const remembered = saved.w > 0;
    var r = if (remembered) saved else d.next_win;
    // The default width is sized for the TOS text columns, which is as wide as
    // a 320px low-res screen — so pull the window LEFT before narrowing it.
    // Both edges (and the size gadget with them) must open on screen, and the
    // content must stay wide enough for the text view's last column.
    r.w = @min(r.w, d.g.screen_w - 4);
    r.x = @max(0, @min(r.x, d.g.screen_w - r.w - 2));
    const min_w = icon_mod.CELL_W + 2 + gui.SCROLL;
    const min_h = gui.TITLE_H + gui.INFO_H + icon_mod.CELL_H + gui.SCROLL;
    const id = d.wm.tryAdd(.{ .r = r, .title = title, .min_w = min_w, .min_h = min_h }) orelse {
        d.dlg.alert("The Desktop has no more windows.", "Please close a window first.");
        return;
    };
    d.win_dir[id] = dir;
    d.sel_icon = -1; // the window, not the icon, is now the selection
    // Freeze the icon grid at the width the window OPENS with; resizing then
    // scrolls the same layout instead of re-flowing it.
    d.win_cols[id] = @max(1, @divTrunc(d.wm.contentRect(id).w, icon_mod.CELL_W));
    d.sel_file = -1;
    d.sel_folder = -1;
    deskdraw.startGrow(d, d.open_src, r); // GEM zoom-box: dotted frame grows icon -> window
    if (!remembered) advanceCascade(d, r); // reusing a remembered spot does not consume one
}

fn advanceCascade(d: *Desktop, r: Rect) void {
    var nx = r.x + 16;
    var ny = r.y + 12;
    if (nx + r.w > d.g.screen_w or ny + r.h > 200) {
        nx = desk_icons.WIN_X0;
        ny = desk_icons.WIN_Y0;
    }
    d.next_win = .{ .x = nx, .y = ny, .w = r.w, .h = r.h };
}

// A window that just closed zooms back DOWN to the desktop icon it came from
// (the FLOPPY drive), the mirror of the box that grew when it opened.
pub fn shrinkClosed(d: *Desktop) void {
    const id = d.wm.takeClosed() orelse return;
    const r = d.wm.wins[id].r;
    // Remember where this directory's window was before it goes away.
    if (isFloppyWin(d, id)) d.win_geom[geomSlot(d.win_dir[id])] = r;
    const to = if (isFloppyWin(d, id)) d.items[desk_icons.IC_FLOPPY].rect() else Rect{ .x = r.x, .y = r.y, .w = 0, .h = 0 };
    deskdraw.startGrow(d, r, to);
}

pub fn closeTopWindow(d: *Desktop) void {
    const id = d.wm.topOpen() orelse return;
    d.wm.close(id);
    d.sel_file = -1;
}

// Refresh a directory window's chrome for THIS frame: the GEM info line, how
// much of each scroll track its slider fills, and how far it may scroll. All
// depend on the window's current size, so they are recomputed every frame
// rather than at open time — but the icon GRID is not, which is why resizing
// scrolls the icons instead of re-wrapping them (see View).
pub fn updateChrome(d: *Desktop, id: u8) void {
    const dir = d.win_dir[id];
    const n = d.dir.fileCount(dir) + d.dir.folderCount(dir);
    const used: u32 = if (dir == dirmodel.ROOT) d.dir.usedBytes() else 0;
    const w = &d.wm.wins[id];
    w.info = std.fmt.bufPrint(&d.win_info[id], "{d} bytes used in {d} items.", .{ used, n }) catch "";
    // The info line changes topBarsH, so measure the content AFTER setting it.
    const c = d.wm.contentRect(id);
    const shown = @divTrunc(c.h, vStep(d));
    const rows = contentRows(d, id, n);
    w.vslide = permille(shown, rows);
    w.vmax = @max(0, rows - shown);
    w.vscroll = @max(0, @min(w.vscroll, w.vmax));

    const width = contentWidth(d, id, n);
    w.hslide = permille(c.w, width);
    const hs = hStep(d);
    w.hmax = @max(0, @divTrunc(width - c.w + hs - 1, hs));
    w.hscroll = @max(0, @min(w.hscroll, w.hmax));
}

// Rows the window's content occupies — icon view wraps into the window's
// FIXED column count, text view is one row per item.
fn contentRows(d: *const Desktop, id: u8, n: usize) i16 {
    const items: i16 = @intCast(n);
    if (d.view != .icons) return items;
    const cols = d.win_cols[id];
    return @divTrunc(items + cols - 1, cols); // ceil
}
// Pixels the content is wide: the OCCUPIED part of the frozen icon grid (a
// half-empty grid is not something to scroll across), or the fixed TOS column
// layout of the text view.
fn contentWidth(d: *const Desktop, id: u8, n: usize) i16 {
    if (n == 0) return 0;
    if (d.view != .icons) return dirview.TOS_COLS * 8;
    return @min(d.win_cols[id], @as(i16, @intCast(n))) * icon_mod.CELL_W;
}

// What fraction of `total` is visible, in per mille, clamped to a full track.
fn permille(visible: i16, total: i16) i16 {
    if (total <= 0 or visible >= total) return 1000;
    return @intCast(@max(1, @divTrunc(@as(i32, visible) * 1000, @as(i32, total))));
}
