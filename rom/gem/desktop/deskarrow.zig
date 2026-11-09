// --------------------------------------------------------------------------
// GEM's own mouse pointer in the desk mode (Matt on the board, 8 Nov 2026: no pointer in the
// desk). In LOW and MEDIUM the hosts draw the arrow over the composited picture (the board's
// fpga/cycles/bcursor.c, the browser's cursor); the desk has no composited picture, so the board
// firmware draws nothing there (bmain.c returns from bdesk_frame before bcursor_draw), and there
// is no LUT left for a hardware pointer (GEM_DESK_MODE.md §4 option 3). So the desktop draws
// TOS's ARROW form itself, last in a drawn frame. Double buffering (deskflip.zig) makes that
// free of save-under: a pointer move is a touch, which redraws the whole frame anyway.
//
// The form is bcursor.c's (TOS's ARROW, 16x16, hot spot 0,0): the mask in white, the data in
// black, one bit a pixel (the desk is 1:1). Clipped to the screen, as the arrow at the right or
// bottom edge is on an ST.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MASK = [16]u16{ 0xC000, 0xE000, 0xF000, 0xF800, 0xFC00, 0xFE00, 0xFF00, 0xFF80, 0xFFC0, 0xFFE0, 0xFE00, 0xEF00, 0xCF00, 0x8780, 0x0780, 0x0380 };
pub const DATA = [16]u16{ 0x0000, 0x4000, 0x6000, 0x7000, 0x7800, 0x7C00, 0x7E00, 0x7F00, 0x7F80, 0x7C00, 0x6C00, 0x4600, 0x0600, 0x0300, 0x0300, 0x0000 };

pub const Colors = struct { mask: u8, data: u8 };
pub const Plane = struct { pix: [*]u8, stride: u32, w: i32, h: i32 };

/// Where the arrow goes before the host has sent a pointer (px < 0): mid-screen, as TOS and
/// the board's glass start it (bcursor.c's g_x, g_y).
pub fn at(px: i32, py: i32, w: i32, h: i32) [2]i32 {
    if (px < 0 or py < 0) return .{ @divTrunc(w, 2), @divTrunc(h, 2) };
    return .{ px, py };
}

/// The arrow with its hot spot at (x, y).
pub fn draw(p: Plane, x: i32, y: i32, c: Colors) void {
    for (0..16) |r| {
        const yy = y + @as(i32, @intCast(r));
        if (yy < 0 or yy >= p.h) continue;
        const row = p.pix + @as(usize, @intCast(yy)) * p.stride;
        for (0..16) |i| {
            const bit = @as(u16, 0x8000) >> @intCast(i);
            const xx = x + @as(i32, @intCast(i));
            if (MASK[r] & bit == 0 or xx < 0 or xx >= p.w) continue;
            row[@intCast(xx)] = if (DATA[r] & bit != 0) c.data else c.mask;
        }
    }
}

const expectEqual = std.testing.expectEqual;
const W = 40;
const H = 24;
const BG: u8 = 5;
const C: Colors = .{ .mask = 1, .data = 0 };

fn plane(buf: *[W * H]u8) Plane {
    @memset(buf, BG);
    return .{ .pix = buf, .stride = W, .w = W, .h = H };
}

test "the ARROW form: white outline, black body, nothing outside the mask" {
    var buf: [W * H]u8 = undefined;
    draw(plane(&buf), 3, 2, C);
    const px = struct {
        fn f(b: *const [W * H]u8, x: usize, y: usize) u8 {
            return b[y * W + x];
        }
    }.f;
    try expectEqual(@as(u8, 1), px(&buf, 3, 2)); // row 0: the hot spot, white
    try expectEqual(@as(u8, 1), px(&buf, 4, 2));
    try expectEqual(BG, px(&buf, 5, 2));
    try expectEqual(@as(u8, 1), px(&buf, 3, 3)); // row 1: white, then black
    try expectEqual(@as(u8, 0), px(&buf, 4, 3));
    try expectEqual(@as(u8, 0), px(&buf, 11, 10)); // row 8: 0x7F80's last black, under 0xFFC0
    try expectEqual(@as(u8, 1), px(&buf, 12, 10));
    try expectEqual(BG, px(&buf, 3, 17)); // row 15: 0x0380, columns 6..8 white only
    try expectEqual(@as(u8, 1), px(&buf, 9, 17));
    try expectEqual(BG, px(&buf, 2, 2)); // left of the hot spot
    var n: usize = 0;
    for (buf) |v| n += @intFromBool(v != BG);
    var bits: usize = 0;
    for (MASK) |m| bits += @popCount(m);
    try expectEqual(bits, n); // exactly the mask's pixels changed
}

test "clipped at every edge, no write outside the plane" {
    var buf: [W * H]u8 = undefined;
    const p = plane(&buf);
    draw(p, W - 1, H - 1, C); // only the hot spot's pixel is on screen
    try expectEqual(@as(u8, 1), buf[(H - 1) * W + W - 1]);
    var n: usize = 0;
    for (buf) |v| n += @intFromBool(v != BG);
    try expectEqual(@as(usize, 1), n);
    draw(plane(&buf), -3, -5, C); // above and left: what is left of it, in place
    try expectEqual(@as(u8, 0), buf[0]); // row 5's column 3 (mask 0xFE00, data 0x7C00: black) lands at 0
    try expectEqual(@as(u8, 1), buf[3]); // its column 6, the white edge
}

test "before any pointer, the arrow is mid-screen" {
    try expectEqual([2]i32{ 320, 240 }, at(-1, -1, 640, 480));
    try expectEqual([2]i32{ 7, 9 }, at(7, 9, 640, 480));
}
