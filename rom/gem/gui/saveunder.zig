// --------------------------------------------------------------------------
// Save-under for what the AES draws OVER a program's window and takes away again:
// a menu's drop-down, a window's dotted move/size outline, the mouse arrow in the
// desk. TOS kept the screen under a drop-down in a buffer and put it back when the
// menu closed; the program never saw it. The ROM does the same for a program's
// GUI context (rom/rom_app.zig): the program redraws nothing for them.
//
// A Plane is the bytes of one 8 bpp plane. A Box saves a rectangle, an Outline
// the pixels of GEM's dotted outline (every other pixel of a rectangle's edges).
// Both clip to the plane and restore exactly what they saved, in reverse order of
// drawing being the caller's rule (LIFO: the arrow last on, first off).
// Pure integer code over bytes: `zig test` covers it.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Plane = struct { pix: [*]u8, stride: u32, w: i32, h: i32 };
pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

fn clipped(p: Plane, r: Rect) ?Rect {
    const x0 = @max(r.x, 0);
    const y0 = @max(r.y, 0);
    const x1 = @min(r.x + r.w, p.w);
    const y1 = @min(r.y + r.h, p.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

/// A rectangle of pixels saved into `buf` (borrowed: a program lends it, rom_app.zig, so the
/// ROM image carries no buffer of zeros); restore() puts them back.
pub const Box = struct {
    buf: []u8 = &.{},
    at: ?Rect = null,

    const Self = @This();

    /// Save `r` (clipped). False, saving nothing, when it does not fit the buffer.
    pub fn save(self: *Self, p: Plane, r: Rect) bool {
        self.at = null;
        const c = clipped(p, r) orelse return true;
        const n: usize = @intCast(c.w * c.h);
        if (n > self.buf.len) return false;
        var k: usize = 0;
        var y = c.y;
        while (y < c.y + c.h) : (y += 1) {
            const row = p.pix + @as(usize, @intCast(y)) * p.stride + @as(usize, @intCast(c.x));
            @memcpy(self.buf[k .. k + @as(usize, @intCast(c.w))], row[0..@intCast(c.w)]);
            k += @intCast(c.w);
        }
        self.at = c;
        return true;
    }

    pub fn restore(self: *Self, p: Plane) void {
        const c = self.at orelse return;
        var k: usize = 0;
        var y = c.y;
        while (y < c.y + c.h) : (y += 1) {
            const row = p.pix + @as(usize, @intCast(y)) * p.stride + @as(usize, @intCast(c.x));
            @memcpy(row[0..@intCast(c.w)], self.buf[k .. k + @as(usize, @intCast(c.w))]);
            k += @intCast(c.w);
        }
        self.at = null;
    }
};

/// GEM's dotted outline drawn over the screen with the pixels it covers kept: each dot's
/// offset and old value, restored newest first (a corner dot is visited twice).
pub const Outline = struct {
    off: []u32 = &.{},
    old: []u8 = &.{},
    n: usize = 0,
    at: ?Rect = null,

    const Self = @This();

    fn dot(self: *Self, p: Plane, x: i32, y: i32, ink: u8) void {
        if (x < 0 or y < 0 or x >= p.w or y >= p.h) return;
        const o: u32 = @intCast(@as(usize, @intCast(y)) * p.stride + @as(usize, @intCast(x)));
        self.off[self.n] = o;
        self.old[self.n] = p.pix[o];
        self.n += 1;
        p.pix[o] = ink;
    }

    /// Draw the outline of `r` in `ink` (Gui.dotted's dots), keeping what it covers. False,
    /// drawing nothing, when it has more dots than the buffer holds.
    pub fn draw(self: *Self, p: Plane, r: Rect, ink: u8) bool {
        self.at = null;
        self.n = 0;
        const dots: usize = @intCast(@max(0, r.w + 1) + @max(0, r.h + 1));
        if (dots + 4 > @min(self.off.len, self.old.len)) return false;
        var x = r.x;
        while (x < r.x + r.w) : (x += 2) {
            self.dot(p, x, r.y, ink);
            self.dot(p, x, r.y + r.h - 1, ink);
        }
        var y = r.y;
        while (y < r.y + r.h) : (y += 2) {
            self.dot(p, r.x, y, ink);
            self.dot(p, r.x + r.w - 1, y, ink);
        }
        self.at = r;
        return true;
    }

    pub fn restore(self: *Self, p: Plane) void {
        if (self.at == null) return;
        while (self.n > 0) {
            self.n -= 1;
            p.pix[self.off[self.n]] = self.old[self.n];
        }
        self.at = null;
    }
};

// --- native tests ------------------------------------------------------------
const testing = std.testing;
const W = 24;
const H = 16;

fn plane(buf: *[W * H]u8) Plane {
    for (buf, 0..) |*b, i| b.* = @intCast(i % 251);
    return .{ .pix = buf, .stride = W, .w = W, .h = H };
}

test "a box saved, drawn over and restored is the screen it was" {
    var buf: [W * H]u8 = undefined;
    const p = plane(&buf);
    const before = buf;
    var mem: [64]u8 = undefined;
    var b: Box = .{ .buf = &mem };
    try testing.expect(b.save(p, .{ .x = 20, .y = 12, .w = 8, .h = 8 })); // clipped to 4x4
    @memset(&buf, 9);
    b.restore(p);
    for (0..H) |y| for (0..W) |x| {
        const inside = x >= 20 and y >= 12;
        if (inside) try testing.expectEqual(before[y * W + x], buf[y * W + x]);
    };
    try testing.expect(!b.save(p, .{ .x = 0, .y = 0, .w = 10, .h = 10 })); // 100 > 64: refused
    try testing.expect(b.at == null);
}

test "an outline restores every pixel it covered, corners and clipped edges included" {
    var buf: [W * H]u8 = undefined;
    const p = plane(&buf);
    const before = buf;
    var off: [256]u32 = undefined;
    var old: [256]u8 = undefined;
    var o: Outline = .{ .off = &off, .old = &old };
    try testing.expect(o.draw(p, .{ .x = -3, .y = 2, .w = 15, .h = 20 }, 0xEE));
    try testing.expect(!std.mem.eql(u8, &before, &buf));
    o.restore(p);
    try testing.expectEqualSlices(u8, &before, &buf);
    try testing.expect(!o.draw(p, .{ .x = 0, .y = 0, .w = 300, .h = 300 }, 1)); // too long for 256
}
