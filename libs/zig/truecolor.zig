// --------------------------------------------------------------------------
// zg.tc: drawing into a TRUE-COLOUR plane (HW 1.15.0, FB_MODE_TRUECOLOR /
// FB_MODE_TRUECOLOR_FULL, docs/HW_API.md). A pixel is a little-endian u16
// R5 G6 B5 that the machine expands by bit replication; there is no palette.
// LogicalFB.setTruecolorPlane(.window | .full) turns a plane into one and
// returns its Fb; `alloc` gives a second buffer to draw the next frame in, and
// `show` points the plane at it (FB_BASE, latched at the frame's start).
//
// The plane's FB_STRIDE is in BYTES (640 / 800): HSCROLL, setScroll's x and a
// copper LBASE are byte offsets too, and bit 0 of a line's address is ignored
// (an odd one shows the even pixel below). LogicalFB's u8 methods (setPixelValue,
// printText, the blitter helpers) do not apply to it: draw through an Fb.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Size = enum { window, full };

/// 8-bit channels -> 565 (the top bits of each, the inverse of the machine's expansion on
/// every value it can show).
pub inline fn rgb565(r: u8, g: u8, b: u8) u16 {
    return (@as(u16, r >> 3) << 11) | (@as(u16, g >> 2) << 5) | (b >> 3);
}

pub fn width(size: Size) u16 {
    return if (size == .full) 400 else 320;
}
pub fn height(size: Size) u16 {
    return if (size == .full) 280 else 200;
}
pub fn bytes(size: Size) usize {
    return @as(usize, width(size)) * height(size) * 2;
}

/// A 565 buffer: `w` x `h` pixels, `stride` pixels a row, 4-aligned (put2 stores u32 pairs: a
/// misaligned word store traps on the board, ~210 cycles).
pub const Fb = struct {
    pixels: [*]align(4) u16,
    w: u16,
    h: u16,
    stride: u16,

    pub fn row(self: Fb, y: usize) []u16 {
        return self.pixels[y * self.stride ..][0..self.w];
    }

    pub fn put(self: Fb, x: usize, y: usize, c: u16) void {
        if (x < self.w and y < self.h) self.pixels[y * self.stride + x] = c;
    }

    /// Two pixels (x even) in one aligned 32-bit store: a u16 pair costs the same DDR time.
    pub fn put2(self: Fb, x: usize, y: usize, c0: u16, c1: u16) void {
        const at = y * self.stride + (x & ~@as(usize, 1));
        const w: *u32 = @ptrCast(@alignCast(self.pixels + at));
        w.* = @as(u32, c0) | (@as(u32, c1) << 16);
    }

    /// Every pixel one colour, two a store.
    pub fn fill(self: Fb, c: u16) void {
        const pair = @as(u32, c) | (@as(u32, c) << 16);
        for (0..self.h) |y| {
            const words: [*]u32 = @ptrCast(@alignCast(self.pixels + y * self.stride));
            @memset(words[0 .. self.w / 2], pair);
        }
    }

    /// `src` rows (w pixels each, `src_stride` apart) at (x, y), clipped to the buffer.
    pub fn copyRect(self: Fb, x: usize, y: usize, src: []const u16, src_stride: usize, w: usize, h: usize) void {
        if (x >= self.w or y >= self.h) return;
        const cw = @min(w, self.w - x);
        for (0..@min(h, self.h - y)) |r| @memcpy(self.row(y + r)[x..][0..cw], src[r * src_stride ..][0..cw]);
    }
};

/// An Fb over the buffer at `p` (a plane's own, or one from zg.truecolorBuffer).
pub fn view(p: [*]u8, size: Size) Fb {
    return .{ .pixels = @ptrCast(@alignCast(p)), .w = width(size), .h = height(size), .stride = width(size) };
}

test "rgb565 keeps each channel's top bits" {
    try std.testing.expectEqual(@as(u16, 0xFFFF), rgb565(255, 255, 255));
    try std.testing.expectEqual(@as(u16, 0xF800), rgb565(255, 0, 0));
    try std.testing.expectEqual(@as(u16, 0x07E0), rgb565(0, 255, 0));
    try std.testing.expectEqual(@as(u16, 0x001F), rgb565(0, 0, 255));
    try std.testing.expectEqual(@as(u16, 0x0000), rgb565(7, 3, 7)); // below one step: black
}

test "put2, fill, copyRect and the clip" {
    var buf: [8 * 3]u16 align(4) = .{0} ** 24;
    const fb = Fb{ .pixels = &buf, .w = 6, .h = 3, .stride = 8 };
    fb.fill(0x1234);
    try std.testing.expectEqual(@as(u16, 0x1234), buf[2 * 8 + 5]);
    try std.testing.expectEqual(@as(u16, 0), buf[6]); // the stride's tail is not the picture
    fb.put2(3, 1, 0xAAAA, 0xBBBB); // x odd: the pair at the even pixel below
    try std.testing.expectEqual(@as(u16, 0xAAAA), buf[8 + 2]);
    try std.testing.expectEqual(@as(u16, 0xBBBB), buf[8 + 3]);
    fb.put(6, 0, 0xFFFF); // outside: ignored
    try std.testing.expectEqual(@as(u16, 0), buf[6]);
    const src = [_]u16{ 1, 2, 3, 4 };
    fb.copyRect(4, 2, &src, 2, 2, 2); // clipped to one row
    try std.testing.expectEqual(@as(u16, 1), buf[2 * 8 + 4]);
    try std.testing.expectEqual(@as(u16, 2), buf[2 * 8 + 5]);
}
