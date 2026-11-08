// DESK TEST's picture (desk_test.zig): the bytes and the palette, as functions, so the cart and
// apps/desk_check.mjs (which re-derives them in JS) agree on every pixel.
pub const W: usize = 640;
pub const H: usize = 480;
pub const CELL_W: usize = 40; // 16 cells across
pub const CELL_H: usize = 30; // 16 cells down
pub const INK: u8 = 255;
pub const LOW_BG: u8 = 1;
pub const TITLE = "ZIGMACHINE DESK TEST 640X480";
pub const HELP = "KEY 1 DESK  KEY 2 LOW RES";
pub const TEXT_X: i16 = 168; // in cells 4..9 of row 15: clear of the checker and the frame
pub const TEXT_Y: i16 = 454;

/// Palette 0, entry i: R, G and B from its bits, all 256 different; alpha 255.
pub fn paletteWord(i: u8) u32 {
    const r: u32 = @as(u32, i & 7) * 36;
    const g: u32 = @as(u32, (i >> 3) & 7) * 36;
    const b: u32 = @as(u32, i >> 6) * 85;
    return r | g << 8 | b << 16 | 0xFF00_0000;
}

/// The index at (x, y), before the text.
pub fn index(x: usize, y: usize) u8 {
    if (x == 0 or y == 0 or x == W - 1 or y == H - 1) return INK; // the frame
    if (x < CELL_W and y < CELL_H) return if ((x ^ y) & 1 == 1) INK else 0; // the checker
    return @intCast(x / CELL_W + 16 * (y / CELL_H));
}

/// index() over the whole buffer, a cell row at a time (no divide a pixel: it runs on ZIGGY).
pub fn paint(fb: []u8) void {
    for (0..H) |y| {
        const row = fb[y * W ..][0..W];
        const base: usize = 16 * (y / CELL_H);
        for (0..W / CELL_W) |c| @memset(row[c * CELL_W ..][0..CELL_W], @intCast(base + c));
        if (y < CELL_H) for (0..CELL_W) |x| {
            row[x] = index(x, y);
        };
        row[0] = INK;
        row[W - 1] = INK;
        if (y == 0 or y == H - 1) @memset(row, INK);
    }
}

test "paint is index() everywhere" {
    var buf: [W * H]u8 = undefined;
    paint(&buf);
    for (0..H) |y| for (0..W) |x| try @import("std").testing.expectEqual(index(x, y), buf[y * W + x]);
}
