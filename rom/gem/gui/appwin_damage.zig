// --------------------------------------------------------------------------
// A program's windows: what must be redrawn, as the AES's WM_REDRAW rectangle
// lists (G17). Matt on the board (9 Nov): moving a window flashed the screen,
// because GEMTEST repainted EVERY window back to front, unclipped, after any
// change. Now the ROM keeps the frame's DAMAGE (screen rectangles whose picture
// is stale) and answers, per window, the damage it must redraw: the damage cut
// to what of that window is visible (wind_get WF_FIRSTXYWH / WF_NEXTXYWH's list),
// and for the desk (no window: id null) what no window covers.
//
//   moved / sized  its old cover and its new one (the windows and the desk under
//                  the old place redraw only what it uncovered)
//   topped         only the parts of it the windows above it hid
//   opened         its cover; closed: its old cover
//
// A cover is the window's box plus its 2-px drop shadow. Pure: windows come in as
// their covers in stack order (back to front, null = closed), so `zig test` covers
// it (rom/gem/gui_obj_test.zig); appwin.zig adapts its Wm.
// --------------------------------------------------------------------------
const std = @import("std");
const R = @import("../engine/rect.zig");
pub const Rect = R.Rect;
pub const RectList = R.RectList;

pub const SHADOW: i16 = 2;
pub const MAX = 8; // >= types.MAX_WIN

/// The windows as the frame found or left them: covers by id, and the stack (ids, back to front).
pub const Stack = struct {
    cover: [MAX]?Rect = @splat(null),
    order: [MAX]u8 = undefined,
    n: u8 = 0,

    fn pos(self: *const Stack, id: u8) ?usize {
        for (self.order[0..self.n], 0..) |o, k| if (o == id) return k;
        return null;
    }
};

pub fn cover(x: i16, y: i16, w: i16, h: i16) Rect {
    return .{ .x = x, .y = y, .w = w + SHADOW, .h = h + SHADOW };
}

/// The damage between `was` and `now` added to `out`.
pub fn damage(was: *const Stack, now: *const Stack, out: *RectList) void {
    for (0..MAX) |i| {
        const a = was.cover[i];
        const b = now.cover[i];
        if (!same(a, b)) {
            if (a) |r| out.add(r);
            if (b) |r| out.add(r);
            continue;
        }
        const r = b orelse continue;
        const p0 = was.pos(@intCast(i)) orelse continue;
        const p1 = now.pos(@intCast(i)) orelse continue;
        if (p1 <= p0) continue; // not raised: nothing of it was hidden that is not still hidden
        for (was.order[p0 + 1 .. was.n]) |above| if (was.cover[above]) |c| out.add(R.intersect(r, c));
    }
}

fn same(a: ?Rect, b: ?Rect) bool {
    if (a == null or b == null) return a == null and b == null;
    return a.?.eql(b.?);
}

/// What of window `id` is visible (its cover minus every cover above it); the desk (null):
/// `screen` minus every cover. Into `out`, emptied first.
pub fn visible(s: *const Stack, id: ?u8, screen: Rect, out: *RectList) void {
    out.* = .{};
    const p = if (id) |i| s.pos(i) orelse return else null;
    const base = if (id) |i| s.cover[i] orelse return else screen;
    out.add(R.intersect(base, screen));
    const from = if (p) |k| k + 1 else 0;
    for (s.order[from..s.n]) |above| if (s.cover[above]) |c| {
        for (shape(c)) |piece| _ = out.subtract(piece);
    };
}

/// What a window really paints of its cover: its box and the two shadow strips, offset 2 px
/// (the cover's bottom-left and top-right 2 x 2 corners stay what is under it).
pub fn shape(c: Rect) [3]Rect {
    return .{
        .{ .x = c.x, .y = c.y, .w = c.w - SHADOW, .h = c.h - SHADOW },
        .{ .x = c.x + c.w - SHADOW, .y = c.y + SHADOW, .w = SHADOW, .h = c.h - SHADOW },
        .{ .x = c.x + SHADOW, .y = c.y + c.h - SHADOW, .w = c.w - SHADOW, .h = SHADOW },
    };
}

/// The damage window `id` (null: the desk) must redraw: `dmg` cut to what of it is visible.
pub fn redraw(s: *const Stack, id: ?u8, screen: Rect, dmg: *const RectList, out: *RectList) void {
    var vis: RectList = .{};
    visible(s, id, screen, &vis);
    out.* = .{};
    for (dmg.slice()) |d| for (vis.slice()) |v| out.add(R.intersect(d, v));
    if (out.overflow) out.* = vis; // too many pieces: all of what is visible (coarser, never wrong)
}

// --- native tests -------------------------------------------------------------
const expect = std.testing.expect;
const SCREEN: Rect = .{ .x = 0, .y = 0, .w = 640, .h = 400 };

fn two() Stack {
    var s: Stack = .{};
    s.cover[0] = cover(10, 20, 200, 100);
    s.cover[1] = cover(100, 60, 200, 100);
    s.order[0] = 0;
    s.order[1] = 1;
    s.n = 2;
    return s;
}

test "a move damages the old cover and the new; the desk redraws only what it uncovered" {
    const was = two();
    var now = was;
    now.cover[1] = cover(300, 200, 200, 100);
    var dmg: RectList = .{};
    damage(&was, &now, &dmg);
    try expect(dmg.area() > 0 and dmg.meets(was.cover[1].?) and dmg.meets(now.cover[1].?));
    var desk: RectList = .{};
    redraw(&now, null, SCREEN, &dmg, &desk);
    try expect(!desk.meets(shape(now.cover[0].?)[0]) and !desk.meets(shape(now.cover[1].?)[0])); // never under a window
    try expect(desk.meets(.{ .x = 300, .y = 300, .w = 2, .h = 2 })); // a cover's corner the shadow leaves: the desk's
    var low: RectList = .{};
    redraw(&now, 0, SCREEN, &dmg, &low);
    try expect(low.area() > 0 and low.bounds().right() <= now.cover[0].?.right());
}

test "topping redraws only what the windows above hid; nothing else is damaged" {
    const was = two();
    var now = was;
    now.order[0] = 1;
    now.order[1] = 0; // window 0 comes to the front
    var dmg: RectList = .{};
    damage(&was, &now, &dmg);
    const hidden = R.intersect(was.cover[0].?, was.cover[1].?);
    try expect(dmg.area() == @as(u32, @intCast(hidden.w)) * @as(u32, @intCast(hidden.h)));
    var under: RectList = .{};
    redraw(&now, 1, SCREEN, &dmg, &under);
    try expect(under.area() == 0); // the window now below has nothing to redraw
}

test "an idle frame damages nothing; a closed window's place goes to what is under it" {
    const was = two();
    var dmg: RectList = .{};
    damage(&was, &was, &dmg);
    try expect(dmg.area() == 0);
    var now = was;
    now.cover[1] = null;
    now.n = 1;
    damage(&was, &now, &dmg);
    var low: RectList = .{};
    redraw(&now, 0, SCREEN, &dmg, &low);
    const k = R.intersect(was.cover[0].?, was.cover[1].?);
    try expect(low.area() == @as(u32, @intCast(k.w)) * @as(u32, @intCast(k.h)));
}
