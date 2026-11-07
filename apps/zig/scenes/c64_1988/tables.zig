// --------------------------------------------------------------------------
// The intro's precalculated tables, regenerated at compile time. Shazz built 1988 with his
// Python cross-assembler (shazzam), so these were Python formulas once; each one below
// reproduces the original's bytes exactly (tables_test.zig compares them with
// tables_ref.bin, ripped by tools/c64_1988_rip.py). Float only here, at comptime: the
// frame code reads the tables with integers, as the 6510 did.
// --------------------------------------------------------------------------
const PAL_WRAP_SCROLL = 504; // X past the left edge wraps to $1F8 - n (part 1's scroller)
const PAL_WRAP_GRID = 503; // part 3's tables wrap one pixel earlier: kept, it IS the original

fn rounded(comptime n: usize, comptime mid: f64, comptime amp: f64, comptime period: f64) [n]u8 {
    @setEvalBranchQuota(100000);
    var t: [n]u8 = undefined;
    for (0..n) |i| t[i] = @intFromFloat(@round(mid + amp * @sin(2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / period)));
    return t;
}
const std = @import("std");

/// $6001: the logo's X, a sine of period 50 over 100 bytes.
pub const logo_x: [100]u8 = rounded(100, 80, 40, 50);
/// $6065: the logo's Y (its top row), a sine of period 20 over 40 bytes.
pub const logo_y: [40]u8 = rounded(40, 53, 7, 20);

/// $6397/$63FC: the scroller's X for position index i, 4 pixels a step (X-expanded glyphs).
pub const scroll_x: [101]u16 = blk: {
    var t: [101]u16 = undefined;
    for (0..101) |i| {
        const v: i32 = 4 * @as(i32, i) - 25;
        t[i] = @intCast(if (v < 0) v + PAL_WRAP_SCROLL else v);
    }
    break :blk t;
};

/// $51CF/$525F: part 3's column c X for scroll step s (0..17): 54 apart, 3 pixels a step.
pub const grid_x: [8][18]u16 = blk: {
    var t: [8][18]u16 = undefined;
    for (0..8) |c| for (0..18) |s| {
        const v: i32 = 54 * @as(i32, c) + 3 * @as(i32, s) - 24;
        t[c][s] = @intCast(if (v < 0) v + PAL_WRAP_GRID else v);
    };
    break :blk t;
};

/// $501F: part 3 variant B (balls), each column's bounce: |sin| of period 48, 12 x 18 bytes.
pub const bounce_b: [216]u8 = blk: {
    @setEvalBranchQuota(100000);
    var t: [216]u8 = undefined;
    for (0..216) |n| t[n] = @intFromFloat(@round(14.0 * @abs(@sin(std.math.pi * @as(f64, @floatFromInt(n)) / 24.0))));
    break :blk t;
};

/// $E359/$E39F: part 2's wipe, the raster line where blue ends on frame k: 4 lines a frame.
pub fn wipeLine(k: usize) u16 {
    return @intCast(12 + 4 * k);
}
