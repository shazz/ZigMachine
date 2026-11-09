// --------------------------------------------------------------------------
// GEM 5 engine: objc_find and fm_button, our way.
//
// objc_find(tree, start, depth, x, y): the object under (x, y) — the deepest one,
// and among siblings the LAST hit, since later siblings are drawn on top; a
// HIDETREE subtree is neither drawn nor found; `depth` 0 tests `start` only.
// fm_button: what a click does to a selectable object — a radio button
// (RBUTTON) is selected and its RBUTTON siblings cleared, anything else
// SELECTABLE toggles; DISABLED objects ignore the click. It returns whether the
// click ends the dialog (EXIT / TOUCHEXIT), as form_do needs. Mouse tracking
// (the AES's graf_watchbox while the button is held) is the caller's: the desk
// runs one frame at a time.
// --------------------------------------------------------------------------
const std = @import("std");
const obj = @import("obj.zig");
const Object = obj.Object;
const NIL = obj.NIL;

pub const MAX_DEPTH = 8;

/// The object under (x, y) at or below `start` (whose parents' offset is `ox, oy`),
/// NIL when (x, y) is outside `start`.
pub fn find(tree: []const Object, start: i16, depth: u8, x: i32, y: i32) i16 {
    const at = obj.offset(tree, start) orelse return NIL;
    return findAt(tree, start, depth, @as(i32, at.x) - tree[@intCast(start)].x, @as(i32, at.y) - tree[@intCast(start)].y, x, y);
}

fn findAt(tree: []const Object, start: i16, depth: u8, ox: i32, oy: i32, x: i32, y: i32) i16 {
    const o = tree[@intCast(start)];
    if (o.flags & obj.HIDETREE != 0) return NIL;
    const ax = ox + o.x;
    const ay = oy + o.y;
    if (x < ax or y < ay or x >= ax + o.w or y >= ay + o.h) return NIL;
    if (depth == 0) return start;
    var best = start;
    var it = obj.children(tree, start);
    while (it.next()) |c| {
        const hit = findAt(tree, c, @min(depth - 1, MAX_DEPTH), ax, ay, x, y);
        if (hit != NIL) best = hit; // later siblings are on top
    }
    return best;
}

pub const Click = struct {
    changed: bool = false, // some object's SELECTED bit moved: redraw it (and its radio siblings)
    exit: bool = false, // EXIT / TOUCHEXIT: the dialog ends with this object
};

/// fm_button for one click on `i` (no mouse tracking: the click is already decided).
pub fn button(tree: []Object, i: i16) Click {
    if (!obj.valid(tree, i)) return .{};
    const o = &tree[@intCast(i)];
    if (o.state & obj.DISABLED != 0) return .{};
    var out: Click = .{ .exit = o.flags & (obj.EXIT | obj.TOUCHEXIT) != 0 };
    if (o.flags & obj.SELECTABLE == 0) return out;
    if (o.flags & obj.RBUTTON != 0) {
        out.changed = o.state & obj.SELECTED == 0;
        clearRadios(tree, i);
        o.state |= obj.SELECTED;
    } else {
        o.state ^= obj.SELECTED;
        out.changed = true;
    }
    return out;
}

fn clearRadios(tree: []Object, i: i16) void {
    const p = obj.parentOf(tree, i);
    if (p == NIL) return;
    var it = obj.children(tree, p);
    while (it.next()) |c| {
        const s = &tree[@intCast(c)];
        if (c != i and s.flags & obj.RBUTTON != 0) s.state &= ~obj.SELECTED;
    }
}

// --- native tests -------------------------------------------------------------
const expectEqual = std.testing.expectEqual;

test "find: the deepest object, the last sibling on top, nothing outside" {
    const t = obj.sample; // root (10,20 100x50); child 2 at (40,25 40x30); its child 3 at (44,29 10x10)
    try expectEqual(@as(i16, 3), find(&t, 0, MAX_DEPTH, 45, 30));
    try expectEqual(@as(i16, 2), find(&t, 0, MAX_DEPTH, 70, 50));
    try expectEqual(@as(i16, 0), find(&t, 0, MAX_DEPTH, 12, 60));
    try expectEqual(@as(i16, 0), find(&t, 0, 0, 45, 30)); // depth 0: the start only
    try expectEqual(NIL, find(&t, 0, MAX_DEPTH, 5, 5)); // outside the root
    try expectEqual(@as(i16, 3), find(&t, 2, MAX_DEPTH, 45, 30)); // from a subtree: its offset counts
    var two = [_]Object{
        .{ .head = 1, .tail = 2, .w = 50, .h = 50 },
        .{ .next = 2, .w = 20, .h = 20 },
        .{ .next = 0, .x = 10, .y = 10, .w = 20, .h = 20 }, // overlaps 1, drawn after it
    };
    try expectEqual(@as(i16, 2), find(&two, 0, MAX_DEPTH, 15, 15));
    two[2].flags = obj.HIDETREE;
    try expectEqual(@as(i16, 1), find(&two, 0, MAX_DEPTH, 15, 15)); // hidden: not found
}

test "button: toggle, radio group, disabled, exit" {
    var t = [_]Object{
        .{ .head = 1, .tail = 4, .w = 99, .h = 99 },
        .{ .next = 2, .flags = obj.SELECTABLE | obj.RBUTTON, .state = obj.SELECTED },
        .{ .next = 3, .flags = obj.SELECTABLE | obj.RBUTTON },
        .{ .next = 4, .flags = obj.SELECTABLE },
        .{ .next = 0, .flags = obj.SELECTABLE | obj.EXIT, .state = obj.DISABLED },
    };
    const r = button(&t, 2);
    try expectEqual(true, r.changed);
    try expectEqual(@as(u16, 0), t[1].state & obj.SELECTED); // its radio sibling cleared
    try expectEqual(obj.SELECTED, t[2].state & obj.SELECTED);
    try expectEqual(false, button(&t, 2).changed); // already on: a radio stays on
    _ = button(&t, 3);
    try expectEqual(obj.SELECTED, t[3].state & obj.SELECTED);
    _ = button(&t, 3);
    try expectEqual(@as(u16, 0), t[3].state & obj.SELECTED); // a plain one toggles
    try expectEqual(Click{}, button(&t, 4)); // disabled: nothing, not even the exit
    t[4].state = 0;
    try expectEqual(true, button(&t, 4).exit);
    try expectEqual(Click{}, button(&t, 77)); // outside the tree
}
