// --------------------------------------------------------------------------
// Part D, the rewind itself ($16EB8): all 280 lines blank, colour 0 rising
// to white over 16 frames ($16F78); then 70 frames of four bands of the
// "<<<<" image (42 rows + 1, on lines 10, 70, 130, 190) sliding left at
// 3, 1, 4 and 2 px a frame through an 896-px ring ($16F20, wrap at 448), on
// a white colour 0; then the white fades back to black ($16FE8).
// The grey ramp is built STE-style: level n of 0..15 is the nibble
// (n >> 1) | (n & 1) << 3, repeated in r, g and b.
// --------------------------------------------------------------------------
const lines = @import("lines.zig");
const vram = @import("vram.zig");

const Band = struct { x: u16, line: u16, speed: u16 };
const INIT = [4]Band{
    .{ .x = 0, .line = 0x0a, .speed = 3 }, .{ .x = 0, .line = 0x46, .speed = 1 },
    .{ .x = 0, .line = 0x82, .speed = 4 }, .{ .x = 0, .line = 0xbe, .speed = 2 },
};
var band: [4]Band = INIT;
const H: usize = 0x2a + 1;

pub fn grey(level: u16) u16 {
    const n = (level >> 1) | (level & 1) << 3;
    return n << 8 | n << 4 | n;
}

pub fn reset() void {
    band = INIT;
}

pub fn flat(colour: u16) void {
    lines.fill(0, lines.ROWS, vram.blank, colour);
}

/// $16F20 for the four bands.
pub fn step() void {
    for (&band) |*b| {
        b.x += b.speed;
        if (b.x >= 0x1c0) b.x -= 0x1c0;
        for (0..H) |j| {
            lines.table[b.line + j] = .{
                .src = vram.band + @as(u32, @intCast(j)) * vram.RING_W + b.x,
                .colour = 0xffff, // moveq #-1 left in the record's colour word: white
            };
        }
    }
}
