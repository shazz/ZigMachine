// --------------------------------------------------------------------------
// GEM 5 engine: rectangles and rectangle lists (the AES's GRECT and the rectangle
// lists wind_get(WF_FIRSTXYWH / WF_NEXTXYWH) hands an application, our way).
//
// A RectList is a fixed-capacity set of disjoint-or-overlapping rectangles: the
// damage of a frame, or what of a window is still exposed after the windows above
// it are cut out (subtract). Fixed capacity because the ROM has no allocator in the
// frame path; a list that would overflow says so (`overflow`), and the caller then
// falls back to something coarser but still correct (compose.zig paints without
// the occlusion cut). Pure integer code, no ZigOS import: `zig test` covers it.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Rect = struct {
    x: i16 = 0,
    y: i16 = 0,
    w: i16 = 0,
    h: i16 = 0,

    pub fn empty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }
    pub fn right(self: Rect) i32 {
        return @as(i32, self.x) + self.w;
    }
    pub fn bottom(self: Rect) i32 {
        return @as(i32, self.y) + self.h;
    }
    pub fn contains(self: Rect, px: i32, py: i32) bool {
        return px >= self.x and py >= self.y and px < self.right() and py < self.bottom();
    }
    /// Every pixel of `o` is inside this one (an empty `o` is inside anything).
    pub fn covers(self: Rect, o: Rect) bool {
        if (o.empty()) return true;
        return o.x >= self.x and o.y >= self.y and o.right() <= self.right() and o.bottom() <= self.bottom();
    }
    pub fn grow(self: Rect, by: i16) Rect {
        return .{ .x = self.x - by, .y = self.y - by, .w = self.w + 2 * by, .h = self.h + 2 * by };
    }
    pub fn eql(self: Rect, o: Rect) bool {
        return self.x == o.x and self.y == o.y and self.w == o.w and self.h == o.h;
    }
};

/// The overlap of two rectangles; empty (w or h 0) when they do not meet.
pub fn intersect(a: Rect, b: Rect) Rect {
    const x0 = @max(@as(i32, a.x), b.x);
    const y0 = @max(@as(i32, a.y), b.y);
    const x1 = @min(a.right(), b.right());
    const y1 = @min(a.bottom(), b.bottom());
    if (x1 <= x0 or y1 <= y0) return .{};
    return .{ .x = @intCast(x0), .y = @intCast(y0), .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

/// The smallest rectangle holding both (an empty one adds nothing).
pub fn unite(a: Rect, b: Rect) Rect {
    if (a.empty()) return b;
    if (b.empty()) return a;
    const x0 = @min(a.x, b.x);
    const y0 = @min(a.y, b.y);
    const x1 = @max(a.right(), b.right());
    const y1 = @max(a.bottom(), b.bottom());
    return .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

/// `a` minus `b` as at most four rectangles (above, below, left, right of the cut).
pub fn minus(a: Rect, b: Rect, out: *[4]Rect) usize {
    const c = intersect(a, b);
    if (c.empty()) {
        out[0] = a;
        return 1;
    }
    var n: usize = 0;
    const parts = [4]Rect{
        .{ .x = a.x, .y = a.y, .w = a.w, .h = c.y - a.y }, // above
        .{ .x = a.x, .y = @intCast(c.bottom()), .w = a.w, .h = @intCast(a.bottom() - c.bottom()) }, // below
        .{ .x = a.x, .y = c.y, .w = c.x - a.x, .h = c.h }, // left
        .{ .x = @intCast(c.right()), .y = c.y, .w = @intCast(a.right() - c.right()), .h = c.h }, // right
    };
    for (parts) |p| {
        if (p.empty()) continue;
        out[n] = p;
        n += 1;
    }
    return n;
}

pub const CAP = 96;

pub const RectList = struct {
    r: [CAP]Rect = undefined,
    n: usize = 0,
    overflow: bool = false, // a rectangle was dropped: the list is NOT the whole area

    pub fn slice(self: *const RectList) []const Rect {
        return self.r[0..self.n];
    }

    /// Add `a` (nothing when it is empty or already covered by a member; a member
    /// it covers is replaced).
    pub fn add(self: *RectList, a: Rect) void {
        if (a.empty()) return;
        var i: usize = 0;
        while (i < self.n) {
            if (self.r[i].covers(a)) return;
            if (a.covers(self.r[i])) {
                self.n -= 1;
                self.r[i] = self.r[self.n];
                continue;
            }
            i += 1;
        }
        if (self.n == CAP) {
            self.overflow = true;
            return;
        }
        self.r[self.n] = a;
        self.n += 1;
    }

    /// Keep only the parts inside `c`.
    pub fn clipTo(self: *RectList, c: Rect) void {
        var i: usize = 0;
        while (i < self.n) {
            const k = intersect(self.r[i], c);
            if (k.empty()) {
                self.n -= 1;
                self.r[i] = self.r[self.n];
                continue;
            }
            self.r[i] = k;
            i += 1;
        }
    }

    /// Cut `b` out of every member. False (and the list left as it was) when the
    /// pieces would not fit: the caller must not rely on the cut then.
    pub fn subtract(self: *RectList, b: Rect) bool {
        if (b.empty()) return true;
        var out: RectList = .{};
        var pieces: [4]Rect = undefined;
        for (self.slice()) |a| {
            const k = minus(a, b, &pieces);
            for (pieces[0..k]) |p| {
                if (out.n == CAP) return false;
                out.r[out.n] = p;
                out.n += 1;
            }
        }
        self.r = out.r;
        self.n = out.n;
        return true;
    }

    /// The area the members cover, counting overlaps twice (a cost measure).
    pub fn area(self: *const RectList) u32 {
        var s: u32 = 0;
        for (self.slice()) |a| s += @as(u32, @intCast(a.w)) * @as(u32, @intCast(a.h));
        return s;
    }

    pub fn bounds(self: *const RectList) Rect {
        var b: Rect = .{};
        for (self.slice()) |a| b = unite(b, a);
        return b;
    }
};

// --- native tests -------------------------------------------------------------
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

test "intersect and unite, including rectangles that do not meet" {
    const a: Rect = .{ .x = 0, .y = 0, .w = 10, .h = 10 };
    const b: Rect = .{ .x = 5, .y = 6, .w = 10, .h = 10 };
    try expectEqual(Rect{ .x = 5, .y = 6, .w = 5, .h = 4 }, intersect(a, b));
    try expect(intersect(a, .{ .x = 10, .y = 0, .w = 4, .h = 4 }).empty()); // touching edges: no overlap
    try expectEqual(Rect{ .x = 0, .y = 0, .w = 15, .h = 16 }, unite(a, b));
    try expectEqual(a, unite(a, .{}));
}

test "minus cuts a hole into at most four pieces of the same area" {
    var out: [4]Rect = undefined;
    const a: Rect = .{ .x = 0, .y = 0, .w = 10, .h = 10 };
    const n = minus(a, .{ .x = 3, .y = 3, .w = 4, .h = 4 }, &out);
    try expectEqual(@as(usize, 4), n);
    var s: i32 = 0;
    for (out[0..n]) |p| s += @as(i32, p.w) * p.h;
    try expectEqual(@as(i32, 100 - 16), s);
    try expectEqual(@as(usize, 0), minus(a, a.grow(2), &out)); // covered whole: nothing left
    try expectEqual(@as(usize, 1), minus(a, .{ .x = 50, .y = 50, .w = 1, .h = 1 }, &out)); // apart: itself
    try expectEqual(a, out[0]);
}

test "a list drops empties and covered members, clips and subtracts" {
    var l: RectList = .{};
    l.add(.{ .x = 0, .y = 0, .w = 0, .h = 9 });
    try expectEqual(@as(usize, 0), l.n);
    l.add(.{ .x = 2, .y = 2, .w = 2, .h = 2 });
    l.add(.{ .x = 0, .y = 0, .w = 8, .h = 8 }); // covers the first: replaces it
    l.add(.{ .x = 1, .y = 1, .w = 2, .h = 2 }); // covered: dropped
    try expectEqual(@as(usize, 1), l.n);
    l.add(.{ .x = 20, .y = 0, .w = 4, .h = 4 });
    l.clipTo(.{ .x = 0, .y = 0, .w = 10, .h = 10 }); // the second is outside: gone
    try expectEqual(@as(usize, 1), l.n);
    try expect(l.subtract(.{ .x = 0, .y = 0, .w = 8, .h = 4 }));
    try expectEqual(@as(u32, 32), l.area());
    try expectEqual(Rect{ .x = 0, .y = 4, .w = 8, .h = 4 }, l.bounds());
}

test "a full list says it overflowed instead of growing" {
    var l: RectList = .{};
    var i: i16 = 0;
    while (i < CAP + 5) : (i += 1) l.add(.{ .x = i * 4, .y = 0, .w = 3, .h = 3 });
    try expectEqual(@as(usize, CAP), l.n);
    try expect(l.overflow);
    // A strip through the middle row splits every member in two: that does not fit, so the
    // subtract refuses and leaves the list as it was.
    const area0 = l.area();
    try expect(!l.subtract(.{ .x = -10, .y = 1, .w = 2000, .h = 1 }));
    try expectEqual(@as(usize, CAP), l.n);
    try expectEqual(area0, l.area());
}
