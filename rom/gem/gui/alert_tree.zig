// --------------------------------------------------------------------------
// A PROGRAM's form_alert as an object tree for the GEM 5 engine, laid out as
// TOS 4's form_alert lays it (measured on Matt's
// reconstruction, components/st_medium/alerts): the icon one character cell in
// from the top-left, the lines beside it a cell apart, a row of equal buttons
// (the widest label plus a cell each side) centred under them, a cell of margin
// round it all. The root is an OUTLINED 3D background (FL3DBAK), the buttons are
// activators (FL3DACT): the flat look draws TOS 1's alert, the 3D look TOS 4's,
// from the same tree (proglook.zig picks the look and the icon art). Pure: no
// ZigOS, so `zig test` covers it (engine_test.zig); alert_obj.zig draws it.
// --------------------------------------------------------------------------
const std = @import("std");
const obj = @import("../engine/obj.zig");
const L = @import("../engine/look.zig");
const Rect = @import("../engine/rect.zig").Rect;

pub const MAX_LINES = 5; // form_alert's (formalert.zig)
pub const MAX_OBJ = 2 + 1 + MAX_LINES + 3;
/// TOS 4's rim round the alert: 3 px black, 2 px white, then the box's own 1 px line.
pub const RIM: i16 = 5;
pub const ICON: i16 = 32; // the icon's box (every set's alert art is 32 x 32)

pub const Tree = struct {
    objs: [MAX_OBJ]obj.Object = undefined,
    n: usize = 0,
    first_btn: i16 = 0,
    nbtn: u8 = 0,
    image: obj.BitBlk = .{ .data = &.{}, .w = 0, .h = 0 },

    fn add(self: *Tree, o: obj.Object) i16 {
        const i: i16 = @intCast(self.n);
        self.objs[self.n] = o;
        self.objs[self.n].next = 0; // the last child's next is the root; fixed up by link()
        self.n += 1;
        return i;
    }
    // Chain the root's children 1..n-1 in order, the last back to the root.
    fn link(self: *Tree) void {
        self.objs[0].head = if (self.n > 1) 1 else obj.NIL;
        self.objs[0].tail = if (self.n > 1) @intCast(self.n - 1) else obj.NIL;
        for (1..self.n) |i| self.objs[i].next = if (i + 1 < self.n) @intCast(i + 1) else 0;
        self.objs[self.n - 1].flags |= obj.LASTOB;
    }
    pub fn buttonBox(self: *const Tree, k: usize) Rect {
        return obj.offset(self.objs[0..self.n], self.first_btn + @as(i16, @intCast(k))).?;
    }
};

/// What the tree is built from (dialog.zig's copies of the program's strings).
pub const Spec = struct {
    icon: u8,
    lines: []const []const u8,
    buttons: []const []const u8,
    default: u8, // 1-based, 0 none
};

/// The alert's tree for a `sw` x `sh` screen in `look`'s font, `art` its icon (null: none).
pub fn build(t: *Tree, s: Spec, look: *const L.Look, art: ?obj.BitBlk, sw: i16, sh: i16) void {
    const cw: i16 = look.font.w;
    const ch: i16 = look.font.h;
    var widest: usize = 0;
    for (s.lines) |l| widest = @max(widest, l.len);
    var bwidest: usize = 0;
    for (s.buttons) |b| bwidest = @max(bwidest, b.len);
    const tx: i16 = if (art != null) 2 * cw + ICON else 2 * cw;
    const text_h: i16 = ch * @as(i16, @intCast(s.lines.len));
    const ty = @divTrunc(ch, 2) - 1; // the first line a little above the icon's top (TOS 4)
    const by = @max(ty + text_h, if (art != null) ch + ICON else 0) + 4;
    const bw: i16 = @as(i16, @intCast(bwidest + 2)) * cw;
    const bh: i16 = ch + 6;
    const nb: i16 = @intCast(s.buttons.len);
    const row = nb * bw + (nb - 1) * cw;
    const w = @min(@max(tx + @as(i16, @intCast(widest)) * cw + 2 * cw, row + 4 * cw), sw - 8 - 2 * RIM);
    const h = by + bh + ch;
    t.* = .{};
    const rim = obj.boxSpec(0, 3, obj.colorWord(L.BLACK, L.BLACK, true, 7, L.WHITE));
    const line = obj.boxSpec(0, 1, obj.colorWord(L.BLACK, L.BLACK, false, 0, L.WHITE));
    _ = t.add(.{ .ty = obj.G_BOX, .flags = obj.FL3DBAK, .spec = .{ .box = rim }, .x = @divTrunc(sw - w, 2) - RIM, .y = @divTrunc(sh - h, 2) - RIM, .w = w + 2 * RIM, .h = h + 2 * RIM });
    _ = t.add(.{ .ty = obj.G_BOX, .spec = .{ .box = line }, .x = RIM, .y = RIM, .w = w, .h = h });
    if (art) |a| {
        t.image = a;
        _ = t.add(.{ .ty = obj.G_IMAGE, .spec = .{ .image = &t.image }, .x = RIM + cw, .y = RIM + ch, .w = a.w, .h = a.h });
    }
    for (s.lines, 0..) |l, i| {
        const y = RIM + ty + ch * @as(i16, @intCast(i));
        _ = t.add(.{ .ty = obj.G_STRING, .spec = .{ .str = l }, .x = RIM + tx, .y = y, .w = @as(i16, @intCast(l.len)) * cw, .h = ch });
    }
    t.first_btn = @intCast(t.n);
    t.nbtn = @intCast(s.buttons.len);
    var x = RIM + @divTrunc(w - row, 2);
    for (s.buttons, 0..) |b, i| {
        var fl: u16 = obj.SELECTABLE | obj.EXIT | obj.FL3DACT;
        if (s.default == i + 1) fl |= obj.DEFAULT;
        _ = t.add(.{ .ty = obj.G_BUTTON, .flags = fl, .spec = .{ .str = b }, .x = x, .y = RIM + by, .w = bw, .h = bh });
        x += bw + cw;
    }
    t.link();
}

// --- native tests -------------------------------------------------------------
const expect = std.testing.expect;

test "TOS 4's layout: icon, lines beside it, the buttons centred under them" {
    var f = L.Font{ .w = 8, .h = 8, .data = &.{} };
    const lk: L.Look = .{ .pal = @splat(0), .font = &f, .small = &f };
    var t: Tree = .{};
    const art: obj.BitBlk = .{ .data = &.{}, .w = 32, .h = 32 };
    build(&t, .{ .icon = 1, .lines = &.{ "The disk is", "write-protected." }, .buttons = &.{ "Cancel", "Retry" }, .default = 2 }, &lk, art, 640, 400);
    try expect(t.n == 2 + 1 + 2 + 2);
    const root = t.objs[0];
    try expect(t.objs[3].x == RIM + 48 and t.objs[3].y == RIM + 3); // the first line beside the icon, above its top
    try expect(t.objs[1].x == RIM and t.objs[0].w == t.objs[1].w + 2 * RIM); // the rim round the box's line
    const a = t.buttonBox(0);
    const b = t.buttonBox(1);
    try expect(a.w == b.w and a.w == 64); // equal: the widest label + a cell each side
    try expect(b.x - (a.x + a.w) == 8); // a cell apart
    try expect(a.x - root.x == root.x + root.w - (b.x + b.w)); // centred in the rim
    try expect(t.objs[t.n - 1].flags & obj.DEFAULT != 0 and t.objs[t.n - 1].flags & obj.LASTOB != 0);
    try expect(a.y == root.y + RIM + 8 + 32 + 4); // just under the icon
}

test "no icon, one long line: the box is clamped to the screen" {
    var f = L.Font{ .w = 8, .h = 8, .data = &.{} };
    const lk: L.Look = .{ .pal = @splat(0), .font = &f, .small = &f };
    var t: Tree = .{};
    const long = "x" ** 40;
    build(&t, .{ .icon = 0, .lines = &.{long}, .buttons = &.{"OK"}, .default = 1 }, &lk, null, 320, 200);
    try expect(t.objs[0].w == 312 and t.objs[0].x == 4); // clamped, the rim included
    try expect(t.objs[2].ty == obj.G_STRING and t.objs[2].x == RIM + 16);
    var it = obj.children(t.objs[0..t.n], 0);
    var kids: usize = 0;
    while (it.next()) |_| kids += 1;
    try expect(kids == 3);
}
