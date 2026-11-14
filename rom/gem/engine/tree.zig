// --------------------------------------------------------------------------
// GEM 5 engine: building an object tree in a caller's array, a child at a time
// (what an RSC editor does once, done here per frame for the ROM's own dialogs:
// the ITEM SELECTOR, a program's alert). add() appends `o` as the LAST child of
// `parent`, so siblings draw in the order they were added (later on top). A full
// array drops the object (NIL) and says so (`full`), it never writes past the end.
// --------------------------------------------------------------------------
const std = @import("std");
const obj = @import("obj.zig");
const Object = obj.Object;
const NIL = obj.NIL;

pub const Builder = struct {
    objs: []Object,
    n: usize = 0,
    full: bool = false,

    /// Start the tree: `o` is its root (index 0).
    pub fn root(objs: []Object, o: Object) Builder {
        var b: Builder = .{ .objs = objs };
        var r = o;
        r.next = NIL;
        r.head = NIL;
        r.tail = NIL;
        _ = b.push(r);
        return b;
    }

    fn push(self: *Builder, o: Object) i16 {
        if (self.n == self.objs.len) {
            self.full = true;
            return NIL;
        }
        self.objs[self.n] = o;
        self.n += 1;
        return @intCast(self.n - 1);
    }

    pub fn add(self: *Builder, parent: i16, o: Object) i16 {
        if (parent < 0 or parent >= self.n) return NIL;
        var c = o;
        c.next = parent;
        c.head = NIL;
        c.tail = NIL;
        const i = self.push(c);
        if (i == NIL) return NIL;
        const p = &self.objs[@intCast(parent)];
        if (p.head == NIL) p.head = i else self.objs[@intCast(p.tail)].next = i;
        p.tail = i;
        return i;
    }

    /// The tree so far, LASTOB on its last object.
    pub fn tree(self: *Builder) []Object {
        if (self.n > 0) self.objs[self.n - 1].flags |= obj.LASTOB;
        return self.objs[0..self.n];
    }
};

const expectEqual = std.testing.expectEqual;

test "children chain in the order added, the last back to its parent" {
    var a: [5]Object = undefined;
    var b = Builder.root(&a, .{ .w = 100, .h = 50 });
    const x = b.add(0, .{ .x = 1 });
    const y = b.add(0, .{ .x = 2 });
    const z = b.add(y, .{ .x = 3 });
    const t = b.tree();
    var it = obj.children(t, 0);
    try expectEqual(@as(?i16, x), it.next());
    try expectEqual(@as(?i16, y), it.next());
    try expectEqual(@as(?i16, null), it.next());
    try expectEqual(y, obj.parentOf(t, z));
    try expectEqual(@as(i16, 3 + 2), obj.offset(t, z).?.x);
    try std.testing.expect(t[t.len - 1].flags & obj.LASTOB != 0);
}

test "a full array drops the object and says so; a bad parent adds nothing" {
    var a: [2]Object = undefined;
    var b = Builder.root(&a, .{});
    _ = b.add(0, .{});
    try expectEqual(NIL, b.add(0, .{}));
    try std.testing.expect(b.full);
    try expectEqual(NIL, b.add(7, .{}));
    try expectEqual(@as(usize, 2), b.tree().len);
}
