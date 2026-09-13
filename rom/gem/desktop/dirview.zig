// --------------------------------------------------------------------------
// A directory as a window shows it: disk files (root only) then folders, on
// the window's frozen icon grid or as TOS text rows, in the View menu's sort
// order. Drawing and hit-testing share one set of layout functions, so a
// click always lands on what was drawn.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const icons = @import("../gem_icons.zig");
const icon_mod = @import("icon.zig");
const stamp = @import("stamp.zig");
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const desksel = @import("desksel.zig");
const Desktop = dt.Desktop;
const Rect = gui.Rect;
const Icon = icon_mod.Icon;

// A directory window's layout frame. `clip` is the real content rectangle (all
// that may be painted); `org` is where item (0,0) is placed — `clip` shifted by
// the window's scroll offset; `cols` is the icon grid's width in cells, FIXED
// when the window opened, so resizing the window SCROLLS the icons instead of
// re-wrapping them (GEM keeps a directory's layout put).
pub const View = struct { clip: Rect, org: Rect, cols: i16 };

pub const Hit = union(enum) { none, file: u8, folder: u8 };

// Icon BOTTOMS sit on this line inside a cell, so every label in a row lines
// up regardless of how tall (or how padded) the bitmap is.
const ICON_BASELINE: i16 = 4 + 30; // top margin + tallest icon
pub const TROW_H: i16 = 10;
pub const TOS_COLS: i16 = 37; // NAME(8) EXT(3) SIZE DATE TIME — see drawFileRow

pub fn fileBmp(d: *const Desktop, fidx: u8) icons.Icon {
    return if (d.dir.kind(fidx) == 0) icons.PROGRAM else icons.DOCUMENT;
}

// Lay an item on the icon grid by DISPLAY SLOT (so sorting reorders the layout),
// its ART (not the sometimes padded bitmap) centred in the cell on the baseline.
fn slotIcon(slot: usize, v: View, bmp: icons.Icon, label: []const u8, is_app: bool) Icon {
    const s: i16 = @intCast(slot);
    const a = icon_mod.artBox(bmp);
    return .{
        .x = v.org.x + @mod(s, v.cols) * icon_mod.CELL_W + @divTrunc(icon_mod.CELL_W - a.w, 2) - a.x,
        .y = v.org.y + @divTrunc(s, v.cols) * icon_mod.CELL_H + ICON_BASELINE - a.y - a.h,
        .bmp = bmp,
        .label = label,
        .is_app = is_app,
        .bounds = v.clip,
    };
}
pub fn fileIconSlot(d: *const Desktop, slot: usize, fidx: u8, v: View) Icon {
    return slotIcon(slot, v, fileBmp(d, fidx), d.dir.name(fidx), d.dir.kind(fidx) == 0);
}
pub fn folderIconSlot(d: *const Desktop, slot: usize, fidx: u8, v: View) Icon {
    return slotIcon(slot, v, icons.FOLDER, d.dir.folderName(fidx), false);
}
pub fn fileRowRect(slot: usize, v: View) Rect {
    const s: i16 = @intCast(slot);
    return .{ .x = v.clip.x, .y = v.org.y + s * TROW_H, .w = v.clip.w, .h = TROW_H };
}

// What a window's directory shows under (x,y): a file, a folder, or nothing.
pub fn dirHitAt(d: *const Desktop, dir: i16, v: View, x: i16, y: i16) Hit {
    const nf = d.dir.fileCount(dir);
    if (dir == dirmodel.ROOT) {
        const ord = d.dir.order(d.sort);
        var p: usize = 0;
        while (p < d.dir.n_disk) : (p += 1) {
            const a = ord[p];
            const hit = if (d.view == .icons) fileIconSlot(d, p, a, v).hitAt(x, y) else gui.inRect(fileRowRect(p, v), x, y);
            if (hit) return .{ .file = a };
        }
    }
    const fc = d.dir.folderCount(dir);
    var rank: usize = 0;
    while (rank < fc) : (rank += 1) {
        const fidx = d.dir.nthFolder(dir, rank);
        const hit = if (d.view == .icons) folderIconSlot(d, nf + rank, fidx, v).hitAt(x, y) else gui.inRect(fileRowRect(nf + rank, v), x, y);
        if (hit) return .{ .folder = fidx };
    }
    return .none;
}

pub fn drawDir(d: *const Desktop, g: *gui.Gui, dir: i16, v: View) void {
    const nf = d.dir.fileCount(dir);
    if (dir == dirmodel.ROOT) {
        const ord = d.dir.order(d.sort);
        var p: usize = 0;
        while (p < d.dir.n_disk) : (p += 1) {
            const a = ord[p];
            if (d.view == .icons) {
                var ic = fileIconSlot(d, p, a, v);
                ic.draw(g, desksel.fileSelected(d, a));
            } else drawFileRow(d, g, p, a, v);
        }
    }
    const fc = d.dir.folderCount(dir);
    var rank: usize = 0;
    while (rank < fc) : (rank += 1) {
        const fidx = d.dir.nthFolder(dir, rank);
        const sel = desksel.folderSelected(d, fidx);
        if (d.view == .icons) {
            var ic = folderIconSlot(d, nf + rank, fidx, v);
            ic.draw(g, sel);
        } else drawFolderRow(d, g, nf + rank, fidx, v, sel);
    }
}

fn drawFolderRow(d: *const Desktop, g: *gui.Gui, slot: usize, fidx: u8, v: View, sel: bool) void {
    const r = fileRowRect(slot, v);
    if (!rowVisible(r, v)) return;
    if (sel) g.rect(r, gui.BLACK);
    const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
    const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
    g.text(d.dir.folderName(fidx), v.clip.x + 4, r.y + 1, ink, paper);
    g.text("<DIR>", v.clip.x + v.clip.w - 6 * 8 - 2, r.y + 1, ink, paper);
}

// Is a text row inside the window? Rows scrolled off the top or bottom are
// simply not drawn (the row text itself is not pixel-clipped).
fn rowVisible(r: Rect, v: View) bool {
    return r.y >= v.clip.y and r.y + TROW_H <= v.clip.y + v.clip.h;
}

// One text-view row, TOS columns: NAME(8) EXT(3) SIZE DATE(MM-DD-YY) TIME.
// Columns sit at fixed cell offsets; each is drawn only if it fits the window,
// so a narrow window drops the right columns instead of overflowing.
fn drawFileRow(d: *const Desktop, g: *gui.Gui, slot: usize, fidx: u8, v: View) void {
    const r = fileRowRect(slot, v);
    if (!rowVisible(r, v)) return;
    const sel = desksel.fileSelected(d, fidx);
    if (sel) g.rect(r, gui.BLACK);
    const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
    const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
    const y = r.y + 1;
    const cx = v.org.x + 4; // column 0, scrolled

    const name = d.dir.name(fidx);
    var base = name;
    var ext: []const u8 = "";
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        base = name[0..dot];
        ext = name[dot + 1 ..];
    }
    var sb: [12]u8 = undefined;
    var db: [16]u8 = undefined;
    const size = std.fmt.bufPrint(&sb, "{d}", .{d.dir.size(fidx)}) catch "?";
    textCol(g, v, base[0..@min(base.len, 8)], cx, y, ink, paper); // NAME (8)
    textCol(g, v, ext[0..@min(ext.len, 3)], cx + 9 * 8, y, ink, paper); // EXT (3)
    textCol(g, v, size, cx + 20 * 8 - @as(i16, @intCast(size.len)) * 8, y, ink, paper); // SIZE, right-aligned
    textCol(g, v, stamp.date(&db, d.dir.date(fidx)), cx + 22 * 8, y, ink, paper); // DATE
    textCol(g, v, stamp.DEFAULT_TIME, cx + 31 * 8, y, ink, paper); // TIME (host FAT has none)
}

// One text-view column, clipped to the window's content span.
fn textCol(g: *gui.Gui, v: View, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
    g.textIn(s, x, y, ink, paper, v.clip.x, v.clip.x + v.clip.w);
}
