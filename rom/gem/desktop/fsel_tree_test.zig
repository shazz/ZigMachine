// fsel_tree.zig + fsel_geom.zig: the ITEM SELECTOR's tree, for the 8x8 font (low, medium) and the
// 8x16 one (400+ lines): the indices the hit tests use, the drives' states, and a layout where every
// row of text is one font height and nothing overlaps, flat or 3D.
const std = @import("std");
const obj = @import("../engine/obj.zig");
const L = @import("../engine/look.zig");
const rect_mod = @import("../engine/rect.zig");
const T = @import("fsel_tree.zig");
const G = @import("fsel_geom.zig");
const Id = T.Id;
const expect = std.testing.expect;

fn sample() T.View {
    return .{ .title = "C:\\NET\\*.TXT", .dir = "C:\\NET\\*.TXT", .sel = "NOTE    .TXT", .mask = "*.TXT", .rows = @splat("A"), .n = 3, .drives = 0b101, .drive = 2 };
}

const SCREENS = [_][2]i16{ .{ 320, 200 }, .{ 640, 200 }, .{ 640, 400 }, .{ 640, 480 } };

test "the indices the hit tests use name the objects they mean" {
    var s: T.Store = .{};
    const v = sample();
    const g = G.ours(8);
    const t = T.build(&s, &v, &g, 640, 200);
    try expect(t[Id.TITLE].spec.str.ptr == v.title.ptr);
    try expect(t[Id.DIR].spec.str.ptr == v.dir.ptr and t[Id.SEL].spec.str.ptr == v.sel.ptr);
    try expect(t[T.LIST].ty == obj.G_BOX and t[T.ROW0].ty == obj.G_STRING and obj.parentOf(t, T.ROW0) == T.LIST);
    try expect(t[Id.UP].ty == obj.G_BOX and t[Id.TRACK].flags & obj.TOUCHEXIT != 0 and obj.parentOf(t, Id.SLIDER) == Id.TRACK);
    try expect(t[Id.DRIVE0].spec.box >> 24 == 'A' and t[Id.DRIVE0 + 15].spec.box >> 24 == 'P');
    try expect(t[Id.DRIVE0 - 1].ty == obj.G_IBOX and obj.boxThickness(t[Id.DRIVE0 - 1].spec.box) == 0); // no frame round the drives
    try expect(t[Id.OK].flags & obj.DEFAULT != 0 and std.mem.eql(u8, t[Id.CANCEL].spec.str, "Cancel"));
    try expect(t.len <= T.MAX_OBJ and t[t.len - 1].flags & obj.LASTOB != 0);
}

test "absent drives are disabled, the spec's drive selected" {
    var s: T.Store = .{};
    const v = sample();
    const g = G.ours(8);
    const t = T.build(&s, &v, &g, 320, 200);
    try expect(t[Id.DRIVE0].state & obj.DISABLED == 0); // A:
    try expect(t[Id.DRIVE0 + 1].state & obj.DISABLED != 0); // B: absent
    try expect(t[Id.DRIVE0 + 2].state & obj.SELECTED != 0); // C: the spec's
}

test "the font height a screen draws in: 8 up to 399 lines, 16 from 400" {
    try expect(G.cellFor(200) == 8 and G.cellFor(399) == 8 and G.cellFor(400) == 16 and G.cellFor(480) == 16);
}

fn r(t: []const obj.Object, i: i16) rect_mod.Rect {
    return obj.offset(t, i).?;
}

// Every screen, flat and 3D: the box on the screen, the rows a font height apart, the text one font
// height tall, the list, the scroll column and the drives clear of each other, OK and Cancel below them.
test "the layout per screen: rows a font height apart, nothing overlapping, the box on screen" {
    var s: T.Store = .{};
    var v = sample();
    for (SCREENS) |sc| for ([_]bool{ false, true }) |td| {
        v.three_d = td;
        const g = G.ours(G.cellFor(sc[1]));
        const t = T.build(&s, &v, &g, sc[0], sc[1]);
        const box = r(t, 0);
        try expect(box.x >= 0 and box.y >= 0 and box.right() <= sc[0] and box.bottom() <= sc[1]);
        try expect(r(t, T.ROW0 + 1).y - r(t, T.ROW0).y == g.ch and r(t, T.ROW0).h == g.ch and r(t, Id.DIR).h == g.ch);
        try expect(r(t, T.ROW0 + T.ROWS - 1).bottom() <= r(t, T.LIST).bottom());
        const grow: i16 = if (td) L.ADJ3D else 0;
        const drives = rect_mod.unite(r(t, Id.DRIVE0).grow(grow), r(t, Id.DRIVE0 + 15).grow(grow));
        try expect(rect_mod.intersect(drives, r(t, Id.UP - 1)).empty()); // the scroll column
        // the title, Directory:, its field and Selection: one under the other, none overlapping (a 16-px
        // title once ran into Directory:)
        try expect(r(t, Id.TITLE).bottom() <= r(t, 2).y and r(t, 2).bottom() <= r(t, Id.DIR).y and r(t, Id.DIR).bottom() <= r(t, Id.SEL).y);
        try expect(r(t, Id.SEL).right() <= r(t, 6).x); // Selection: clear of DRIVE:
        try expect(r(t, 6).bottom() <= drives.y and r(t, Id.CLOSER).y >= r(t, Id.SEL).bottom());
        const low = @max(drives.bottom(), r(t, T.LIST).bottom());
        try expect(r(t, Id.OK).grow(grow).y > low and r(t, Id.CANCEL).grow(grow).bottom() < box.bottom());
        for (0..T.DRIVES) |a| for (a + 1..T.DRIVES) |c| {
            const ra = r(t, Id.DRIVE0 + @as(i16, @intCast(a))).grow(grow);
            const rc = r(t, Id.DRIVE0 + @as(i16, @intCast(c))).grow(grow);
            try expect(rect_mod.intersect(ra, rc).empty());
        };
        const col = r(t, Id.UP - 1);
        const sl = r(t, Id.SLIDER).grow(grow);
        try expect(sl.x >= col.x and sl.right() <= col.right());
    };
}

test "16-pixel cells: the same arrangement, every row of text twice as tall" {
    const a = G.ours(8);
    const b = G.ours(16);
    try expect(b.pitch == 16 and a.pitch == 8 and b.w == a.w and b.h > a.h and b.h < 2 * a.h);
    try expect(b.drive.x == a.drive.x and b.dx == a.dx and b.dy > a.dy);
}

test "a core geometry (a local asset build's) is not shrunk in 3D" {
    var s: T.Store = .{};
    var v = sample();
    v.three_d = true;
    var g = G.ours(8);
    g.core = true;
    const t = T.build(&s, &v, &g, 640, 200);
    try expect(r(t, Id.DRIVE0).w == g.drive.w);
    const col = r(t, Id.UP - 1); // the slider is ours, sized from the track: inside the column even drawn 3D
    const sl = r(t, Id.SLIDER).grow(L.ADJ3D);
    try expect(sl.x >= col.x and sl.right() <= col.right());
    g.core = false;
    const f = T.build(&s, &v, &g, 640, 200);
    try expect(r(f, Id.DRIVE0).w == g.drive.w - 2 * L.ADJ3D);
}
