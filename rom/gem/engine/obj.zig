// --------------------------------------------------------------------------
// GEM 5 engine: the object tree, as the AES has it (OBJECT: ob_next / ob_head /
// ob_tail links in one array, a type, flags, state, a spec and a box relative to
// the parent). Our own definitions, in our own words: the numbers are the AES's
// public binding (types 20..33, the flag and state bits), which every GEM
// resource file and binding shares.
//
// Links: a parent's children run from ob_head along ob_next; the last child's
// ob_next points BACK to the parent (its ob_tail), the root's is NIL. A malformed
// tree (a chain that never returns) must not hang the ROM, so every walk here is
// bounded by the tree's length.
// --------------------------------------------------------------------------
const std = @import("std");
const rect = @import("rect.zig");
pub const Rect = rect.Rect;

pub const NIL: i16 = -1;

// Object types (AES binding).
pub const G_BOX: u8 = 20;
pub const G_TEXT: u8 = 21;
pub const G_BOXTEXT: u8 = 22;
pub const G_IMAGE: u8 = 23;
pub const G_IBOX: u8 = 25;
pub const G_BUTTON: u8 = 26;
pub const G_BOXCHAR: u8 = 27;
pub const G_STRING: u8 = 28;
pub const G_FTEXT: u8 = 29;
pub const G_FBOXTEXT: u8 = 30;
pub const G_ICON: u8 = 31;
pub const G_TITLE: u8 = 32;
pub const G_CICON: u8 = 33;
/// Ours: a dotted outline (box spec: colour word's border colour), the shape of
/// GEM's pending gestures (window move / resize, a drag, the zoom-box).
pub const G_DOTS: u8 = 0x7F;

// ob_flags.
pub const SELECTABLE: u16 = 0x0001;
pub const DEFAULT: u16 = 0x0002;
pub const EXIT: u16 = 0x0004;
pub const EDITABLE: u16 = 0x0008;
pub const RBUTTON: u16 = 0x0010;
pub const LASTOB: u16 = 0x0020;
pub const TOUCHEXIT: u16 = 0x0040;
pub const HIDETREE: u16 = 0x0080;
pub const FL3DIND: u16 = 0x0200; // TOS 4 3D: an indicator (radio, check, gadget)
pub const FL3DBAK: u16 = 0x0400; // TOS 4 3D: background (dialog face)
pub const FL3DACT: u16 = 0x0600; // TOS 4 3D: an activator (a button that presses in)
pub const FL3DMASK: u16 = 0x0600;
/// Ours, not the AES's: children are clipped to this object's box (a window's
/// work area holds its directory; the AES leaves that to the application's clip).
pub const CLIPKIDS: u16 = 0x8000;

// ob_state.
pub const SELECTED: u16 = 0x0001;
pub const CROSSED: u16 = 0x0002;
pub const CHECKED: u16 = 0x0004;
pub const DISABLED: u16 = 0x0008;
pub const OUTLINED: u16 = 0x0010;
pub const SHADOWED: u16 = 0x0020;

// TEDINFO te_font / te_just.
pub const FONT_SYSTEM: u8 = 3; // GEM's IBM font: the system font
pub const FONT_SMALL: u8 = 5;
pub const JUST_LEFT: u8 = 0;
pub const JUST_RIGHT: u8 = 1;
pub const JUST_CENTRE: u8 = 2;

/// TEDINFO: the text, its font, justification, colour word (as a box's low word)
/// and border thickness (positive: inside the box, negative: outside).
pub const Ted = struct {
    text: []const u8,
    font: u8 = FONT_SYSTEM,
    just: u8 = JUST_LEFT,
    color: u16 = 0x1180,
    thickness: i8 = 0,
};

/// ICONBLK: a 1 bpp image + mask, its label under it, all relative to the object.
pub const IconBlk = struct {
    mask: []const u8, // rows of rowBytes() bytes, MSB first
    data: []const u8,
    w: i16,
    h: i16,
    bpr: i16 = 0, // bytes a row; 0: (w + 7) / 8 (GEM's own are word-padded: say so)
    text: []const u8 = "",
    ix: i16 = 0, // the image's top-left in the object
    iy: i16 = 0,
    tx: i16 = 0, // the label's box in the object
    ty: i16 = 0,
    tw: i16 = 0,
    th: i16 = 0,
    color: u16 = 0x1000, // ib_char's high byte: data colour (high nibble), mask colour (low)

    pub fn rowBytes(self: *const IconBlk) usize {
        return if (self.bpr > 0) @intCast(self.bpr) else (@as(usize, @intCast(self.w)) + 7) / 8;
    }
};

/// CICONBLK, ours: the mono icon plus a chunky image (one palette index a pixel,
/// drawn where the mono mask is set), and an optional selected image.
pub const CIconBlk = struct {
    mono: IconBlk,
    col: []const u8,
    sel: ?[]const u8 = null,
};

/// BITBLK: a 1 bpp image drawn in one colour.
pub const BitBlk = struct { data: []const u8, w: i16, h: i16, bpr: i16 = 0, color: u8 = 1 };

pub const Spec = union(enum) {
    none,
    box: u32, // G_BOX / G_IBOX / G_BOXCHAR: char, thickness, colour word
    str: []const u8, // G_STRING / G_BUTTON / G_TITLE
    ted: *const Ted,
    icon: *const IconBlk,
    cicon: *const CIconBlk,
    image: *const BitBlk,
};

pub const Object = struct {
    next: i16 = NIL,
    head: i16 = NIL,
    tail: i16 = NIL,
    ty: u8 = G_IBOX,
    flags: u16 = 0,
    state: u16 = 0,
    spec: Spec = .none,
    x: i16 = 0,
    y: i16 = 0,
    w: i16 = 0,
    h: i16 = 0,
};

/// A G_BOX-family spec: the character (G_BOXCHAR), the border thickness, and the
/// colour word (border colour 15..12, text colour 11..8, replace mode 7,
/// pattern 6..4, interior colour 3..0).
pub fn boxSpec(char: u8, thickness: i8, color: u16) u32 {
    return @as(u32, char) << 24 | @as(u32, @as(u8, @bitCast(thickness))) << 16 | color;
}
pub fn colorWord(border: u4, text: u4, replace: bool, pattern: u3, interior: u4) u16 {
    return @as(u16, border) << 12 | @as(u16, text) << 8 | @as(u16, @intFromBool(replace)) << 7 | @as(u16, pattern) << 4 | interior;
}
pub const Colors = struct { border: u4, text: u4, replace: bool, pattern: u3, interior: u4 };
pub fn colors(word: u16) Colors {
    return .{
        .border = @intCast(word >> 12),
        .text = @intCast((word >> 8) & 15),
        .replace = (word & 0x80) != 0,
        .pattern = @intCast((word >> 4) & 7),
        .interior = @intCast(word & 15),
    };
}
pub fn boxChar(spec: u32) u8 {
    return @intCast(spec >> 24);
}
pub fn boxThickness(spec: u32) i8 {
    return @bitCast(@as(u8, @intCast((spec >> 16) & 0xFF)));
}

/// The children of `parent`, in drawing order, bounded by the tree's length.
pub const Children = struct {
    tree: []const Object,
    parent: i16,
    cur: i16,
    left: usize,

    pub fn next(self: *Children) ?i16 {
        if (self.cur == NIL or self.cur == self.parent or self.left == 0) return null;
        if (self.cur < 0 or self.cur >= self.tree.len) return null;
        const c = self.cur;
        self.cur = self.tree[@intCast(c)].next;
        self.left -= 1;
        return c;
    }
};

pub fn children(tree: []const Object, parent: i16) Children {
    const head = if (valid(tree, parent)) tree[@intCast(parent)].head else NIL;
    return .{ .tree = tree, .parent = parent, .cur = head, .left = tree.len };
}

pub fn valid(tree: []const Object, i: i16) bool {
    return i >= 0 and i < tree.len;
}

/// The object whose child `i` is, NIL for the root (or a broken chain).
pub fn parentOf(tree: []const Object, i: i16) i16 {
    var cur = i;
    var left = tree.len;
    while (valid(tree, cur) and left > 0) : (left -= 1) {
        const n = tree[@intCast(cur)].next;
        if (!valid(tree, n)) return NIL;
        if (tree[@intCast(n)].tail == cur) return n;
        cur = n;
    }
    return NIL;
}

/// objc_offset: the object's box on screen (the parents' offsets added), the root
/// placed at its own x, y. Null for an index outside the tree.
pub fn offset(tree: []const Object, i: i16) ?Rect {
    if (!valid(tree, i)) return null;
    const o = tree[@intCast(i)];
    var x: i32 = o.x;
    var y: i32 = o.y;
    var p = parentOf(tree, i);
    var left = tree.len;
    while (p != NIL and left > 0) : (left -= 1) {
        x += tree[@intCast(p)].x;
        y += tree[@intCast(p)].y;
        p = parentOf(tree, p);
    }
    return .{ .x = @intCast(x), .y = @intCast(y), .w = o.w, .h = o.h };
}

// --- native tests -------------------------------------------------------------
const expectEqual = std.testing.expectEqual;

// root(0) -> a(1) -> b(2) ; b has child c(3)
pub const sample = [_]Object{
    .{ .head = 1, .tail = 2, .ty = G_BOX, .x = 10, .y = 20, .w = 100, .h = 50 },
    .{ .next = 2, .ty = G_STRING, .x = 1, .y = 2, .w = 8, .h = 8 },
    .{ .next = 0, .head = 3, .tail = 3, .ty = G_BOX, .x = 30, .y = 5, .w = 40, .h = 30 },
    .{ .next = 2, .ty = G_BUTTON, .flags = LASTOB, .x = 4, .y = 4, .w = 10, .h = 10 },
};

test "children run from head along next back to the parent" {
    var it = children(&sample, 0);
    try expectEqual(@as(?i16, 1), it.next());
    try expectEqual(@as(?i16, 2), it.next());
    try expectEqual(@as(?i16, null), it.next());
    var leaf = children(&sample, 1);
    try expectEqual(@as(?i16, null), leaf.next());
    var bad = children(&sample, 9); // outside the tree: no children, no trap
    try expectEqual(@as(?i16, null), bad.next());
}

test "parents and offsets add up, root at its own x, y" {
    try expectEqual(@as(i16, 2), parentOf(&sample, 3));
    try expectEqual(@as(i16, 0), parentOf(&sample, 1));
    try expectEqual(NIL, parentOf(&sample, 0));
    try expectEqual(Rect{ .x = 44, .y = 29, .w = 10, .h = 10 }, offset(&sample, 3).?);
    try expectEqual(@as(?Rect, null), offset(&sample, -1));
}

test "a chain that never returns to its parent ends anyway" {
    var loop = [_]Object{
        .{ .head = 1, .tail = 2, .w = 9, .h = 9 },
        .{ .next = 2 },
        .{ .next = 1 }, // should point at 0: 1 -> 2 -> 1 -> ... forever
    };
    var it = children(&loop, 0);
    var n: usize = 0;
    while (it.next()) |_| n += 1;
    try expectEqual(loop.len, n);
    _ = parentOf(&loop, 1); // bounded too
    loop[2].next = 0;
    try expectEqual(@as(i16, 0), parentOf(&loop, 2));
}

test "box spec and colour word round trip" {
    const s = boxSpec(5, -2, colorWord(1, 2, true, 4, 3));
    try expectEqual(@as(u8, 5), boxChar(s));
    try expectEqual(@as(i8, -2), boxThickness(s));
    const c = colors(@truncate(s));
    try expectEqual(@as(u4, 1), c.border);
    try expectEqual(@as(u4, 2), c.text);
    try expectEqual(true, c.replace);
    try expectEqual(@as(u3, 4), c.pattern);
    try expectEqual(@as(u4, 3), c.interior);
}
