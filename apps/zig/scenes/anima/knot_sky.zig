// --------------------------------------------------------------------------
// The knot's sky: a synthwave sunset that is nothing but a REAL raster, entry
// 0 rewritten every line (raster.zig): indigo to magenta to a burning horizon
// at HORIZON, then a dark floor crossed by neon lines rushing at the viewer,
// spaced in perspective (row = HORIZON + K / z, z falling every frame).
// --------------------------------------------------------------------------
const raster = @import("raster.zig");
const grade = @import("grade.zig");

const HORIZON = 176;
const LINES = 10;

// The sky's gradient, STE levels, top to the horizon.
const SKY = [_][3]u8{
    .{ 1, 0, 3 }, .{ 2, 0, 5 }, .{ 4, 0, 6 }, .{ 6, 0, 7 }, .{ 9, 1, 7 },
    .{ 12, 2, 6 }, .{ 14, 4, 5 }, .{ 15, 7, 3 }, .{ 15, 10, 2 }, .{ 15, 13, 6 },
};

pub fn build(lt: u32, white: u32) void {
    const bands = SKY.len;
    for (0..HORIZON) |r| {
        const i = r * bands / HORIZON;
        set(r, grade.lit(&SKY[i], 15, white));
    }
    // the floor: dark violet, and its lines
    const floor = grade.lit(&.{ 2, 0, 3 }, 15, white);
    const neon = grade.lit(&.{ 15, 3, 13 }, 15, white);
    for (HORIZON..raster.ROWS) |r| set(r, floor);
    const phase = (lt * 3) % 64; // z falls 3 units a frame, a line every 64
    for (0..LINES) |k| {
        const z = 64 * (LINES - k) - phase + 16;
        const row = HORIZON + 2 + 2600 / z;
        if (row < raster.ROWS) set(row, neon);
    }
}

fn set(r: usize, c: u32) void {
    if (raster.lines[r][0] != c) raster.lines[r][0] = c;
}
