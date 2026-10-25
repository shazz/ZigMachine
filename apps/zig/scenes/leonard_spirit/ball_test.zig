// Native test of the generated ball code (ball.zig) and the path (path.zig):
// the store programs paint exactly a keyed blit of the sprite at every shift,
// over each other in painter's order, never touch a transparent pixel, are
// 52-60 stores at every shift (u64 where 8 pixels allow), the chain and the pan stay inside the overscan
// buffer, and the show opens each border and eases the scroll in.
const std = @import("std");
const ball = @import("ball.zig");
const path = @import("path.zig");
const show = @import("show.zig");
const lay = @import("layout.zig");

const W = 320;
const H = 200;

// leonard's ball.raw (16x16: 0 transparent, 1-3 the shades), spelled out
// because a native test cannot @embedFile outside its own directory.
const ROWS = [16]*const [16]u8{
    "0000011111100000", "0001111111111000", "0011111111111100", "0111111111111110",
    "0112221111111110", "1122222111111111", "1233322211111111", "1233322211111111",
    "1233322211111111", "1233322211111111", "1122222111111111", "0112221111111110",
    "0111111111111110", "0011111111111100", "0001111111111000", "0000011111100000",
};
const IMG: [256]u8 = blk: {
    var t: [256]u8 = undefined;
    for (ROWS, 0..) |r, y| for (r, 0..) |c, x| {
        t[y * 16 + x] = c - '0';
    };
    break :blk t;
};
// a sprite with holes in its rows: runs that start and end anywhere
const HOLES: [6 * 9]u8 = .{
    1, 0, 2, 2, 0, 3, 3, 3, 0,
    0, 1, 1, 1, 1, 1, 0, 0, 1,
    2, 0, 0, 0, 0, 0, 0, 0, 2,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    3, 3, 3, 3, 3, 3, 3, 3, 3,
    0, 2, 0, 2, 0, 2, 0, 2, 0,
};

fn keyed(plane: []u8, img: []const u8, w: u32, h: u32, ink: u8, x: u32, y: u32) void {
    for (0..h) |r| for (0..w) |c| {
        const v = img[r * w + c];
        if (v != 0) plane[(y + r) * W + x + c] = v + ink;
    };
}

fn check(comptime S: type, img: []const u8, ink: u8) !void {
    var a: [W * H]u8 align(4) = undefined;
    var b: [W * H]u8 align(4) = undefined;
    for (&a, 0..) |*p, i| p.* = @truncate(i *% 2654435761 >> 24);
    b = a;
    var rng = std.Random.DefaultPrng.init(0x312);
    for (0..3000) |_| {
        const x = rng.random().uintLessThan(u32, W - S.W + 1);
        const y = rng.random().uintLessThan(u32, H - S.H + 1);
        S.draw(&a, W, x, y);
        keyed(&b, img, S.W, S.H, ink, x, y);
    }
    try std.testing.expectEqualSlices(u8, &b, &a);
}

test "generated ball = keyed blit, painter's order, all four shifts" {
    try check(ball.Sprite(16, 16, IMG, 3), &IMG, 3);
}

test "generated code handles rows with several runs" {
    try check(ball.Sprite(9, 6, HOLES, 40), &HOLES, 40);
}

test "52-60 aligned stores a ball, 208 bytes, at every shift" {
    // Every wasm store costs ~10 cycles on the board (ball.zig), so the count
    // is the ball's price: 72 u8/u16/u32 stores before the u64s.
    const B = ball.Sprite(16, 16, IMG, 3);
    const want = [4]usize{ 52, 58, 60, 58 };
    inline for (0..4) |s| {
        const p = comptime B.program(s);
        try std.testing.expectEqual(want[s], p.len);
        var bytes: u32 = 0;
        inline for (p) |st| {
            try std.testing.expectEqual(@as(u32, 0), st.x % @min(st.width, 4)); // rv32: a u64 is two sw
            bytes += st.width;
        }
        try std.testing.expectEqual(@as(u32, 208), bytes);
    }
}

test "every ball of every frame of the period stays inside the overscan window" {
    for (0..path.PERIOD) |f| for (0..path.SNAKES) |k| {
        var c = path.Chain.start(@intCast(f), @intCast(k));
        for (0..path.SNAKE_LEN) |_| {
            try std.testing.expect(c.x() + 16 <= lay.WIN_W and c.y() + 16 <= lay.WIN_H);
            c.next();
        }
    };
}

test "every pan keeps the window inside the buffer" {
    for (path.SCROLL) |s| try std.testing.expect(s.x + lay.WIN_W <= lay.BUF_W and s.y + lay.WIN_H <= lay.BUF_H);
}

test "the show: still, then each side shakes open and stays, then the scroll eases in" {
    try std.testing.expectEqual(@as(u8, 0), show.openMask(show.STATIC_END - 1));
    try std.testing.expectEqual(@as(u8, 7), show.openMask(show.OPEN_END));
    try std.testing.expect(!show.isOpen(.bottom, show.stageStart(.bottom) - 1));
    var toggles: u32 = 0;
    var t: u32 = show.stageStart(.sides);
    while (t < show.stageStart(.bottom)) : (t += 1) {
        if (show.isOpen(.sides, t) != show.isOpen(.sides, t + 1)) toggles += 1;
    }
    try std.testing.expectEqual(@as(u32, show.SHAKE.len - 1), toggles); // closed first, open last
    try std.testing.expectEqual(@as(u32, 0), show.scrollSpeed(show.EASE_START));
    try std.testing.expect(show.scrollSpeed(show.CRUISE - 1) < 1 << 16);
    try std.testing.expectEqual(@as(u32, 1 << 16), show.scrollSpeed(show.CRUISE));
}

test "the sine table is Q15 and the degree table a u32 turn" {
    try std.testing.expectEqual(@as(i16, 32767), path.SIN[256]);
    try std.testing.expectEqual(@as(i16, -32767), path.SIN[768]);
    try std.testing.expectEqual(@as(u32, 1 << 31), path.DEG[180]);
}
