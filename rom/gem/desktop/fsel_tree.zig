// --------------------------------------------------------------------------
// The ITEM SELECTOR as TOS 4 lays it out, as an object tree for the GEM 5 engine
// (G21). Geometry measured on Matt's reconstruction (aes340 SELECTOR, 8x8 cells),
// our own tree: 312 x 178, the path centred as its title, Directory: over its
// 37-cell rule, Selection: with the 8.3 field, the file list as a little window
// (closer, the mask on its title, nine rows, a scroll column: up, track +
// slider, down), DRIVE: A..P in two columns (absent drives DISABLED, the
// current one SELECTED), OK (default) and Cancel under it all.
// Pure: no ZigOS, `zig test` covers it (rom/gem/gui_obj_test.zig); fsel_draw.zig
// draws it and hit-tests it by the indices below.
// --------------------------------------------------------------------------
const std = @import("std");
const obj = @import("../engine/obj.zig");
const L = @import("../engine/look.zig");
const rect_mod = @import("../engine/rect.zig");
const Builder = @import("../engine/tree.zig").Builder;
const glyphs = @import("../gem_glyphs.zig");

pub const W: i16 = 312;
pub const H: i16 = 178;
pub const ROWS = 9;
pub const DRIVES = 16;
pub const MAX_OBJ = 64;
pub const LIST: i16 = 10; // the list's box; its rows are ROW0 ..
pub const ROW0: i16 = 11;

// The objects hit-tested by index (fixed: added in this order).
pub const Id = struct {
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
    three_d: bool = false, // TOS 4's 3D look: indicators are drawn L.ADJ3D larger, so they're laid out smaller
};

// An indicator's box shrunk by the 3D outset on each side, so it's drawn at `r` (Matt, 10 Nov: the
// drive buttons and the slider overlapped in every resolution).
fn inset(v: *const View, x: i16, y: i16, w: i16, h: i16) [4]i16 {
    const a: i16 = if (v.three_d) L.ADJ3D else 0;
    return .{ x + a, y + a, w - 2 * a, h - 2 * a };
}

const FACE = obj.colorWord(L.BLACK, L.BLACK, true, 7, L.WHITE);
fn box(t: i8) obj.Spec {
    return .{ .box = obj.boxSpec(0, t, FACE) };
}
fn str(s: []const u8, x: i16, y: i16) obj.Object {
    return .{ .ty = obj.G_STRING, .spec = .{ .str = s }, .x = x, .y = y, .w = @intCast(s.len * 8), .h = 8 };
}

const GADGET = [3][glyphs.GH]u16{ glyphs.CLOSE, glyphs.UP, glyphs.DOWN };
const GADGET_BITS = blk: {
    var out: [3][glyphs.GH * 2]u8 = undefined;
    for (GADGET, 0..) |rows, g| for (rows, 0..) |r, i| {
        out[g][2 * i] = @intCast((r << 4) >> 8);
        out[g][2 * i + 1] = @intCast((r << 4) & 0xFF);
    };
    break :blk out;
};
const GADGET_BLK = blk: {
    var out: [3]obj.BitBlk = undefined;
    for (&out, 0..) |*b, g| b.* = .{ .data = &GADGET_BITS[g], .w = glyphs.GW, .h = glyphs.GH, .bpr = 2 };
    break :blk out;
};
const FOLDER_BITS = [7]u8{ 0x10, 0x38, 0x7C, 0xFE, 0x7C, 0x38, 0x10 }; // TOS's folder diamond
const FOLDER: obj.BitBlk = .{ .data = &FOLDER_BITS, .w = 8, .h = 7 };

// A gadget box with its glyph centred in it (the closer, the arrows).
fn gadget(b: *Builder, parent: i16, g: usize, x: i16, y: i16, w: i16, h: i16) void {
    const i = b.add(parent, .{ .ty = obj.G_BOX, .flags = obj.TOUCHEXIT | obj.FL3DBAK, .spec = box(1), .x = x, .y = y, .w = w, .h = h });
    _ = b.add(i, .{ .ty = obj.G_IMAGE, .spec = .{ .image = &GADGET_BLK[g] }, .x = @divTrunc(w - glyphs.GW, 2), .y = @divTrunc(h - glyphs.GH, 2), .w = glyphs.GW, .h = glyphs.GH });
}

/// Where a tree is built: its objects and the list title's TEDINFO.
pub const Store = struct {
    objs: [MAX_OBJ]obj.Object = undefined,
    mask: obj.Ted = .{ .text = "", .just = obj.JUST_CENTRE, .color = obj.colorWord(L.BLACK, L.BLACK, true, 2, L.BLACK), .thickness = 1 },
};

/// The selector's tree for `v`, centred on an `sw` x `sh` screen.
pub fn build(s: *Store, v: *const View, sw: i16, sh: i16) []obj.Object {
    s.mask.text = v.mask;
    var b = Builder.root(&s.objs,.{ .ty = obj.G_BOX, .flags = obj.FL3DBAK, .state = obj.OUTLINED, .spec = box(2), .x = @divTrunc(sw - W, 2), .y = @max(0, @divTrunc(sh - H, 2)), .w = W, .h = H });
    const title = v.title[v.title.len -| 36..];
    _ = b.add(0, .{ .ty = obj.G_STRING, .spec = .{ .str = title }, .x = @divTrunc(W - @as(i16, @intCast(title.len * 8)), 2), .y = 6, .w = @intCast(title.len * 8), .h = 8 }); // 1
    _ = b.add(0, str("Directory:", 8, 18)); // 2
    _ = b.add(0, str(v.dir, 8, 28)); // 3 DIR
    _ = b.add(0, str("Selection:", 8, 40)); // 4
    _ = b.add(0, str(v.sel, 96, 40)); // 5 SEL
    _ = b.add(0, str("DRIVE:", 232, 40)); // 6
    listWindow(&b, v, &s.mask);
    driveGroup(&b, v);
    _ = b.add(0, .{ .ty = obj.G_BUTTON, .flags = obj.SELECTABLE | obj.DEFAULT | obj.EXIT | obj.FL3DACT, .state = held(v, Id.OK), .spec = .{ .str = "OK" }, .x = 64, .y = 160, .w = 72, .h = 10 });
    _ = b.add(0, .{ .ty = obj.G_BUTTON, .flags = obj.SELECTABLE | obj.EXIT | obj.FL3DACT, .state = held(v, Id.CANCEL), .spec = .{ .str = "Cancel" }, .x = 176, .y = 160, .w = 72, .h = 10 });
    for (0..ROWS) |i| if (v.folder[i]) { // the folder marks last: the indices above stay fixed
        const r = ROW0 + @as(i16, @intCast(i));
        _ = b.add(r, .{ .ty = obj.G_IMAGE, .state = b.objs[@intCast(r)].state, .spec = .{ .image = &FOLDER }, .w = 8, .h = 7 });
    };
    return b.tree();
}

fn held(v: *const View, i: i16) u16 {
    return if (v.pressed == i) obj.SELECTED else 0;
}

// 7 the closer (8 its glyph), 9 the mask's title bar, 10 the list, 11.. its rows, the scroll column.
fn listWindow(b: *Builder, v: *const View, mask: *const obj.Ted) void {
    gadget(b, 0, 0, 24, 48, 16, 11);
    _ = b.add(0, .{ .ty = obj.G_BOXTEXT, .spec = .{ .ted = mask }, .x = 39, .y = 48, .w = 167, .h = 11 });
    _ = b.add(0, .{ .ty = obj.G_BOX, .spec = box(1), .x = 24, .y = 58, .w = 158, .h = 96 });
    for (0..ROWS) |i| {
        const idx = v.top + i;
        const on = idx < v.n and v.picked == @as(i16, @intCast(idx));
        _ = b.add(LIST, .{ .ty = obj.G_STRING, .flags = obj.TOUCHEXIT, .state = if (on) obj.SELECTED else 0, .spec = .{ .str = v.rows[i] }, .x = 8, .y = 4 + @as(i16, @intCast(i)) * 10, .w = 15 * 8, .h = 8 });
    }
    scroll(b, v);
}

fn scroll(b: *Builder, v: *const View) void {
    const col = b.add(0, .{ .ty = obj.G_BOX, .spec = box(1), .x = 181, .y = 58, .w = 24, .h = 96 });
    gadget(b, col, 1, 0, 0, 24, 16); // UP + its image
    const track = b.add(col, .{ .ty = obj.G_BOX, .flags = obj.TOUCHEXIT, .spec = .{ .box = obj.boxSpec(0, 1, obj.colorWord(L.BLACK, L.BLACK, true, 2, L.BLACK)) }, .x = 0, .y = 15, .w = 24, .h = 66 });
    const max = if (v.n > ROWS) v.n - ROWS else 0;
    const sh: i16 = if (max == 0) 66 else @max(12, @divTrunc(66 * @as(i16, ROWS), @as(i16, @intCast(v.n))));
    const at: i16 = if (max == 0) 0 else @intCast(@divTrunc(@as(i32, 66 - sh) * @as(i32, @intCast(v.top)), @as(i32, @intCast(max))));
    const sl = inset(v, 0, at, 24, sh);
    _ = b.add(track, .{ .ty = obj.G_BOX, .flags = obj.FL3DIND, .spec = box(1), .x = sl[0], .y = sl[1], .w = sl[2], .h = sl[3] });
    gadget(b, col, 2, 0, 80, 24, 16); // DOWN + its image
}

// The drive buttons A..P, two columns of eight; absent drives DISABLED.
fn driveGroup(b: *Builder, v: *const View) void {
    const grp = b.add(0, .{ .ty = obj.G_IBOX, .x = 220, .y = 52, .w = 80, .h = 104 });
    for (0..DRIVES) |k| {
        var st: u16 = 0;
        if (v.drives & (@as(u16, 1) << @intCast(k)) == 0) st |= obj.DISABLED;
        if (k == v.drive) st |= obj.SELECTED;
        const ch: u8 = 'A' + @as(u8, @intCast(k));
        // 3D: drawn 2 px larger all round: 28 x 8 drawn 32 x 12 on a 13 px pitch, a pixel between rows
        const r = inset(v, @as(i16, @intCast(k % 2)) * 40 + 4, @as(i16, @intCast(k / 2)) * 13 - @as(i16, if (v.three_d) 1 else 0), 32, if (v.three_d) 12 else 10);
        _ = b.add(grp, .{ .ty = obj.G_BOXCHAR, .flags = obj.SELECTABLE | obj.EXIT | obj.RBUTTON | obj.FL3DIND, .state = st, .spec = .{ .box = obj.boxSpec(ch, 1, FACE) }, .x = r[0], .y = r[1], .w = r[2], .h = r[3] });
    }
}

// --- native tests -------------------------------------------------------------
const expect = std.testing.expect;

fn sample() View {
    return .{ .title = "C:\\NET\\*.TXT", .dir = "C:\\NET\\*.TXT", .sel = "NOTE    .TXT", .mask = "*.TXT", .rows = @splat("A"), .n = 3, .drives = 0b101, .drive = 2 };
}

test "the indices the hit tests use name the objects they mean" {
    var s: Store = .{};
    const v = sample();
    const t = build(&s, &v, 640, 200);
    try expect(t[Id.DIR].spec.str.ptr == v.dir.ptr and t[Id.SEL].spec.str.ptr == v.sel.ptr);
    try expect(t[LIST].ty == obj.G_BOX and t[ROW0].ty == obj.G_STRING and obj.parentOf(t, ROW0) == LIST);
    try expect(t[Id.UP].ty == obj.G_BOX and t[Id.TRACK].flags & obj.TOUCHEXIT != 0 and obj.parentOf(t, Id.SLIDER) == Id.TRACK);
    try expect(t[Id.DOWN].y == 80 and t[Id.DRIVE0].spec.box >> 24 == 'A');
    try expect(t[Id.DRIVE0 + 15].spec.box >> 24 == 'P');
    try expect(t[Id.OK].flags & obj.DEFAULT != 0 and std.mem.eql(u8, t[Id.CANCEL].spec.str, "Cancel"));
    try expect(t.len <= MAX_OBJ and t[t.len - 1].flags & obj.LASTOB != 0);
}

test "absent drives are disabled, the spec's drive selected; the box fits 320 x 200" {
    var s: Store = .{};
    const v = sample();
    const t = build(&s, &v, 320, 200);
    try expect(t[Id.DRIVE0].state & obj.DISABLED == 0); // A:
    try expect(t[Id.DRIVE0 + 1].state & obj.DISABLED != 0); // B: absent
    try expect(t[Id.DRIVE0 + 2].state & obj.SELECTED != 0); // C: the spec's
    const r = obj.offset(t, 0).?;
    try expect(r.x >= 0 and r.right() <= 320 and r.bottom() <= 200);
    const ok = obj.offset(t, Id.CANCEL).?;
    try expect(ok.bottom() < r.bottom());
}

test "3D: the drive buttons and the slider, drawn ADJ3D larger, overlap nothing (Matt, 10 Nov)" {
    var s: Store = .{};
    var v = sample();
    v.three_d = true;
    const t = build(&s, &v, 640, 480);
    for (0..DRIVES) |a| for (a + 1..DRIVES) |c| {
        const ra = obj.offset(t, Id.DRIVE0 + @as(i16, @intCast(a))).?.grow(L.ADJ3D);
        const rc = obj.offset(t, Id.DRIVE0 + @as(i16, @intCast(c))).?.grow(L.ADJ3D);
        try expect(rect_mod.intersect(ra, rc).empty());
    };
    const col = obj.offset(t, Id.UP - 1).?; // the scroll column
    const sl = obj.offset(t, Id.SLIDER).?.grow(L.ADJ3D);
    try expect(sl.x >= col.x and sl.right() <= col.right());
    v.three_d = false; // flat: the boxes as laid out, nothing grows
    const f = build(&s, &v, 640, 480);
    try expect(obj.offset(f, Id.DRIVE0).?.w == 32 and obj.offset(f, Id.SLIDER).?.w == 24);
}
