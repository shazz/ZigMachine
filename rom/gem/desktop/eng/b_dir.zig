// --------------------------------------------------------------------------
// A directory in its window's work area (a CLIPKIDS box): the files, then the
// folders, in the View menu's sort order, as icons on the window's grid or as
// TOS text rows — the layout of dirview.zig (fileIconSlot / folderIconSlot /
// fileRowRect), so a click lands on what is drawn. A text row is one string,
// its columns at TOS's fixed cells (NAME EXT SIZE DATE TIME).
// --------------------------------------------------------------------------
const std = @import("std");
const eng = @import("../../engine/obj.zig");
const L = @import("../../engine/look.zig");
const dirview = @import("../dirview.zig");
const desksel = @import("../desksel.zig");
const deskwin = @import("../deskwin.zig");
const stamp = @import("../stamp.zig");
const b_desk = @import("b_desk.zig");
const ctx_mod = @import("ctx.zig");
const Ctx = ctx_mod.Ctx;
const Tree = ctx_mod.Tree;

pub fn build(c: *Ctx, t: *Tree, id: u8) void {
    const d = c.d;
    const v = deskwin.viewOf(d, id);
    const w = &d.wm.wins[id];
    const area = t.add(0, .{ .ty = eng.G_IBOX, .flags = eng.CLIPKIDS, .spec = ctx_mod.box(0, 1, L.WHITE, 0), .x = v.clip.x - w.r.x, .y = v.clip.y - w.r.y, .w = v.clip.w, .h = v.clip.h });
    const dir = d.win_dir[id];
    const nf = d.dir.fileCount(dir);
    const o = d.dir.orderIn(dir, d.sort);
    for (o.ord[0..o.n], 0..) |a, p| {
        const sel = desksel.fileSelected(d, a);
        if (d.view == .icons) {
            const ic = dirview.fileIconSlot(d, p, a, v);
            if (dirview.shown(d, &ic)) _ = t.add(area, b_desk.iconObject(c, &ic, d.g.screen.w, sel, v.clip.x, v.clip.y));
        } else _ = row(t, area, v, p, fileRow(c, a), sel);
    }
    const fc = d.dir.folderCount(dir);
    for (0..fc) |rank| {
        const f = d.dir.nthFolder(dir, rank);
        const sel = desksel.folderSelected(d, f);
        if (d.view == .icons) {
            const ic = dirview.folderIconSlot(d, nf + rank, f, v);
            if (dirview.shown(d, &ic)) _ = t.add(area, b_desk.iconObject(c, &ic, d.g.screen.w, sel, v.clip.x, v.clip.y));
        } else if (row(t, area, v, nf + rank, c.d.dir.folderName(f), sel)) |bar| {
            // <DIR> where the old path draws it (dirview.drawFolderRow): scrolled with the row.
            text(t, bar, v.org.x - v.clip.x + v.clip.w - 6 * 8 - 2, "<DIR>", sel);
        }
    }
}

// A text row: its bar (the whole width, inverted when selected) and its text from column 0,
// scrolled sideways by the window (the CLIPKIDS work area clips both). Null: not shown.
fn row(t: *Tree, area: i16, v: dirview.View, slot: usize, s: []const u8, sel: bool) ?i16 {
    const r = dirview.fileRowRect(slot, v);
    if (r.y < v.clip.y or r.y + dirview.TROW_H > v.clip.y + v.clip.h) return null; // TOS shows whole rows only
    const bar = t.add(area, .{ .ty = eng.G_BOX, .state = if (sel) eng.SELECTED else 0, .spec = ctx_mod.box(0, 1, L.WHITE, 7), .x = 0, .y = r.y - v.clip.y, .w = r.w, .h = r.h });
    text(t, bar, v.org.x - v.clip.x + 4, s, sel);
    return bar;
}

fn text(t: *Tree, bar: i16, x: i16, s: []const u8, sel: bool) void {
    _ = t.add(bar, .{ .ty = eng.G_STRING, .state = if (sel) eng.SELECTED else 0, .spec = .{ .str = s }, .x = x, .y = 0, .w = @intCast(s.len * 8), .h = dirview.TROW_H });
}

fn fileRow(c: *Ctx, fidx: u8) []const u8 {
    const d = c.d;
    var buf: [40]u8 = [_]u8{' '} ** 40;
    const name = d.dir.name(fidx);
    var base = name;
    var ext: []const u8 = "";
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        base = name[0..dot];
        ext = name[dot + 1 ..];
    }
    put(&buf, 0, base[0..@min(base.len, 8)]);
    put(&buf, 9, ext[0..@min(ext.len, 3)]);
    var sb: [12]u8 = undefined;
    const size = std.fmt.bufPrint(&sb, "{d}", .{d.dir.size(fidx)}) catch "?";
    put(&buf, 20 -| size.len, size);
    var db: [16]u8 = undefined;
    put(&buf, 22, stamp.date(&db, d.dir.date(fidx)));
    put(&buf, 31, stamp.DEFAULT_TIME);
    return c.str(trimRight(&buf));
}

fn put(buf: *[40]u8, at: usize, s: []const u8) void {
    if (at >= buf.len) return;
    const n = @min(s.len, buf.len - at);
    @memcpy(buf[at..][0..n], s[0..n]);
}

fn trimRight(buf: *const [40]u8) []const u8 {
    var n: usize = buf.len;
    while (n > 0 and buf[n - 1] == ' ') n -= 1;
    return buf[0..n];
}
