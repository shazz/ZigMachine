// --------------------------------------------------------------------------
// The ITEM SELECTOR as TOS 4 arranges it, as an object tree for the GEM 5 engine
// (G21): the path centred as its title, Directory: over its field, Selection:
// with the 8.3 field, the file list as a little window (closer, the mask on its
// title, nine rows a font height apart, a scroll column: up, track + slider,
// down), DRIVE: A..P in two columns (absent drives DISABLED, the current one
// SELECTED), OK (default) and Cancel under it all. Where each piece goes is a
// Geom (fsel_geom.zig: our layout for the 8x8 or the 8x16 font, or a local
// asset build's). Pure: no ZigOS, `zig test` covers it (fsel_tree_test.zig);
// fsel_draw.zig draws it and hit-tests it by the indices below.
// --------------------------------------------------------------------------
const obj = @import("../engine/obj.zig");
const L = @import("../engine/look.zig");
const Builder = @import("../engine/tree.zig").Builder;
const sym = @import("fsel_sym.zig");
pub const geom = @import("fsel_geom.zig");
const Geom = geom.Geom;
const R = geom.R;
pub const ROWS = 9;
pub const DRIVES = 16;
pub const MAX_OBJ = 64;
pub const LIST: i16 = 10; // the list's box; its rows are ROW0 ..
pub const ROW0: i16 = 11;

// The objects hit-tested by index (fixed: added in this order).
pub const Id = struct {
    pub const TITLE: i16 = 1;
    pub const DIR: i16 = 3;
    pub const SEL: i16 = 5;
    pub const CLOSER: i16 = 7;
    pub const UP: i16 = ROW0 + ROWS + 1; // 21: after the scroll column's box
    pub const TRACK: i16 = UP + 2;
    pub const SLIDER: i16 = TRACK + 1;
    pub const DOWN: i16 = SLIDER + 1;
    pub const DRIVE0: i16 = DOWN + 3; // after DOWN's image and the drive group
    pub const OK: i16 = DRIVE0 + DRIVES;
    pub const CANCEL: i16 = OK + 1;
};

pub const View = struct {
    title: []const u8, // the path spec, the box's title
    dir: []const u8, // the Directory: line, 37 cells (underscores where empty)
    sel: []const u8, // the Selection: field's 12 cells
    mask: []const u8, // the list window's title
    rows: [ROWS][]const u8, // each row's cells
    folder: [ROWS]bool = @splat(false),
    picked: i16 = -1, // the selected row, -1 none
    top: usize = 0, // the first row shown
    n: usize = 0, // names in the list
    drives: u16 = 1, // present drives, bit 0 = A:
    drive: u8 = 0, // the spec's drive
    pressed: i16 = obj.NIL, // the object held down (drawn SELECTED)
    three_d: bool = false, // TOS 4's 3D look: indicators are drawn L.ADJ3D larger
    glyphs: bool = false, // the font has TOS's gadget characters (CHARS)
};

// An indicator as laid out: our Geom gives the size it is DRAWN, so in 3D it is shrunk by the outset
// on each side (Matt, 10 Nov: the drive buttons and the slider overlapped); a core rect (TOS 4's own
// tree) stays in 3D and is drawn that much larger flat, so TOS's packing holds in both looks.
fn inset(v: *const View, g: *const Geom, r: R) R {
    if (g.core and !v.three_d) return .{ .x = r.x - L.ADJ3D, .y = r.y - L.ADJ3D, .w = r.w + 2 * L.ADJ3D, .h = r.h + 2 * L.ADJ3D };
    return shrink(v, r, !g.core);
}
fn shrink(v: *const View, r: R, on: bool) R {
    const a: i16 = if (v.three_d and on) L.ADJ3D else 0;
    return .{ .x = r.x + a, .y = r.y + a, .w = r.w - 2 * a, .h = r.h - 2 * a };
}

const FACE = obj.colorWord(L.BLACK, L.BLACK, true, 7, L.WHITE);
const BLACKFILL = obj.colorWord(L.BLACK, L.BLACK, true, 7, L.BLACK);
const HOLLOW = obj.colorWord(L.BLACK, L.BLACK, false, 0, L.WHITE); // TOS 4's 0x1100: the paper (or the 3D face) shows
fn box(t: i8) obj.Spec {
    return .{ .box = obj.boxSpec(0, t, FACE) };
}
fn str(s: []const u8, r: R) obj.Object {
    return .{ .ty = obj.G_STRING, .spec = .{ .str = s }, .x = r.x, .y = r.y, .w = @intCast(s.len * 8), .h = r.h };
}
fn at(o: obj.Object, r: R) obj.Object {
    var c = o;
    c.x = r.x;
    c.y = r.y;
    c.w = r.w;
    c.h = r.h;
    return c;
}
// `r` relative to `p`, as a child's.
fn rel(r: R, p: R) R {
    return .{ .x = r.x - p.x, .y = r.y - p.y, .w = r.w, .h = r.h };
}

pub const CHARS = sym.CHARS;
const FOLDER = sym.FOLDER;

// A gadget as TOS 4's: a G_BOXCHAR (white, a black border `thick`, an activator in 3D) with its
// character, and no frame inside it; the symbol image under it shows only when the font has no such
// character (Matt on the board, 14 Nov: "the arrows with useless frames around").
fn gadget(b: *Builder, parent: i16, v: *const View, g: *const Geom, k: usize, thick: i8, r: R) void {
    const in = inset(v, g, r);
    const ch: u8 = if (v.glyphs) CHARS[k] else ' ';
    const i = b.add(parent, at(.{ .ty = obj.G_BOXCHAR, .flags = obj.TOUCHEXIT | obj.FL3DACT, .spec = .{ .box = obj.boxSpec(ch, thick, FACE) } }, in));
    const blk = sym.symbol(k, g.ch == 16);
    const fl: u16 = if (v.glyphs) obj.HIDETREE else 0;
    _ = b.add(i, .{ .ty = obj.G_IMAGE, .flags = fl, .spec = .{ .image = blk }, .x = @divTrunc(in.w - blk.w + 1, 2), .y = @divTrunc(in.h - blk.h + 1, 2), .w = blk.w, .h = blk.h });
}

/// Where a tree is built: its objects and the list title's TEDINFO.
pub const Store = struct {
    objs: [MAX_OBJ]obj.Object = undefined,
    // TOS 4's: the 50 % pattern, the mask written in replace mode (paper behind it), framed outside
    mask: obj.Ted = .{ .text = "", .just = obj.JUST_CENTRE, .color = obj.colorWord(L.BLACK, L.BLACK, true, 4, L.BLACK), .thickness = -1 },
};

/// The selector's tree for `v` laid out by `g`, centred on an `sw` x `sh` screen.
pub fn build(s: *Store, v: *const View, g: *const Geom, sw: i16, sh: i16) []obj.Object {
    s.mask.text = v.mask;
    const root: R = .{ .x = @divTrunc(sw - g.w, 2), .y = @max(0, @divTrunc(sh - g.h, 2)), .w = g.w, .h = g.h };
    var b = Builder.root(&s.objs, at(.{ .ty = obj.G_BOX, .flags = obj.FL3DBAK, .state = obj.OUTLINED, .spec = box(2) }, root));
    const title = v.title[v.title.len -| 36..];
    const tw: i16 = @intCast(title.len * 8);
    _ = b.add(0, str(title, .{ .x = @divTrunc(g.w - tw, 2), .y = g.title_y, .w = tw, .h = g.ch })); // 1
    _ = b.add(0, str("Directory:", g.dir_label)); // 2
    _ = b.add(0, str(v.dir, g.dir)); // 3 DIR
    _ = b.add(0, str("Selection:", g.sel_label)); // 4
    _ = b.add(0, str(v.sel, g.sel)); // 5 SEL
    _ = b.add(0, str("DRIVE:", g.drive_label)); // 6
    listWindow(&b, v, g, &s.mask);
    driveGroup(&b, v, g);
    const fl = obj.SELECTABLE | obj.EXIT | obj.FL3DACT;
    _ = b.add(0, at(.{ .ty = obj.G_BUTTON, .flags = fl | obj.DEFAULT, .state = held(v, Id.OK), .spec = .{ .str = "OK" } }, g.ok));
    _ = b.add(0, at(.{ .ty = obj.G_BUTTON, .flags = fl, .state = held(v, Id.CANCEL), .spec = .{ .str = "Cancel" } }, g.cancel));
    for (0..ROWS) |i| if (v.folder[i]) { // the folder marks last: the indices above stay fixed
        const r = ROW0 + @as(i16, @intCast(i));
        _ = b.add(r, .{ .ty = obj.G_IMAGE, .state = b.objs[@intCast(r)].state, .spec = .{ .image = &FOLDER }, .y = @divTrunc(g.row.h - 7, 2), .w = 8, .h = 7 });
    };
    return b.tree();
}

fn held(v: *const View, i: i16) u16 {
    return if (v.pressed == i) obj.SELECTED else 0;
}

// 7 the closer (8 its glyph), 9 the mask's title bar, 10 the list, 11.. its rows, the scroll column.
fn listWindow(b: *Builder, v: *const View, g: *const Geom, mask: *const obj.Ted) void {
    gadget(b, 0, v, g, 0, -1, g.closer);
    _ = b.add(0, at(.{ .ty = obj.G_BOXTEXT, .flags = obj.TOUCHEXIT | obj.FL3DBAK, .spec = .{ .ted = mask } }, g.mask));
    _ = b.add(0, at(.{ .ty = obj.G_BOX, .spec = box(1) }, g.list));
    const row0 = rel(g.row, g.list);
    for (0..ROWS) |i| {
        const idx = v.top + i;
        const on = idx < v.n and v.picked == @as(i16, @intCast(idx));
        const r: R = .{ .x = row0.x, .y = row0.y + @as(i16, @intCast(i)) * g.pitch, .w = row0.w, .h = row0.h };
        _ = b.add(LIST, at(.{ .ty = obj.G_STRING, .flags = obj.TOUCHEXIT, .state = if (on) obj.SELECTED else 0, .spec = .{ .str = v.rows[i] } }, r));
    }
    scroll(b, v, g);
}

fn scroll(b: *Builder, v: *const View, g: *const Geom) void {
    const col = b.add(0, at(.{ .ty = obj.G_BOX, .spec = .{ .box = obj.boxSpec(0, 0, BLACKFILL) } }, g.scroll)); // TOS 4's: black between the pieces
    gadget(b, col, v, g, 1, 1, rel(g.up, g.scroll)); // UP + its image
    const tr = rel(g.track, g.scroll);
    const grey = obj.boxSpec(0, 1, obj.colorWord(L.BLACK, L.BLACK, false, 4, L.BLACK)); // TOS 4's: the 50 % pattern
    const track = b.add(col, at(.{ .ty = obj.G_BOX, .flags = obj.TOUCHEXIT, .spec = .{ .box = grey } }, tr));
    const max = if (v.n > ROWS) v.n - ROWS else 0;
    const sh: i16 = if (max == 0) tr.h else @max(g.ch + 4, @divTrunc(tr.h * @as(i16, ROWS), @as(i16, @intCast(v.n))));
    const y: i16 = if (max == 0) 0 else @intCast(@divTrunc(@as(i32, tr.h - sh) * @as(i32, @intCast(v.top)), @as(i32, @intCast(max))));
    // the slider is sized here from the track, never a core rect: always shrunk in 3D, so it stays in the column
    _ = b.add(track, at(.{ .ty = obj.G_BOX, .flags = obj.TOUCHEXIT | obj.FL3DACT, .spec = box(1) }, shrink(v, .{ .x = 0, .y = y, .w = tr.w, .h = sh }, true)));
    gadget(b, col, v, g, 2, 1, rel(g.down, g.scroll)); // DOWN + its image
}

// The drive buttons A..P, two columns of eight; absent drives DISABLED.
fn driveGroup(b: *Builder, v: *const View, g: *const Geom) void {
    // TOS 4's DRVBOX: no frame of its own; the buttons' outside borders, one pixel shared, are the grid
    const grp = b.add(0, at(.{ .ty = obj.G_BOX, .flags = obj.FL3DBAK, .spec = .{ .box = obj.boxSpec(0, 0, HOLLOW) } }, g.drives));
    const d0 = rel(g.drive, g.drives);
    for (0..DRIVES) |k| {
        var st: u16 = 0;
        if (v.drives & (@as(u16, 1) << @intCast(k)) == 0) st |= obj.DISABLED;
        if (k == v.drive) st |= obj.SELECTED;
        const ch: u8 = 'A' + @as(u8, @intCast(k));
        const r: R = .{ .x = d0.x + @as(i16, @intCast(k % 2)) * g.dx, .y = d0.y + @as(i16, @intCast(k / 2)) * g.dy, .w = d0.w, .h = d0.h };
        const fl = obj.SELECTABLE | obj.EXIT | obj.RBUTTON | obj.FL3DIND;
        _ = b.add(grp, at(.{ .ty = obj.G_BOXCHAR, .flags = fl, .state = st, .spec = .{ .box = obj.boxSpec(ch, -1, FACE) } }, inset(v, g, r)));
    }
}
