// --------------------------------------------------------------------------
// SAP TEST: the credits scroller's raster. A REAL one: the plane's HBL handler
// rewrites one palette entry (the scroller's ink) on every scanline, so the
// colour bands are register writes, not pixels. Cycled one line a frame.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const SCROLL: u8 = 6; // the plane-0 palette entry the handler rewrites

pub const COPPER = blk: {
    var t: [32]zg.Color = undefined;
    for (&t, 0..) |*c, i| {
        const b: f32 = @sin(@as(f32, @floatFromInt(i)) / 32.0 * std.math.pi); // 0..1..0
        c.* = .{ .r = @intFromFloat(96 + 159 * b), .g = @intFromFloat(48 + 160 * b * b), .b = @intFromFloat(160 - 120 * b), .a = 255 };
    }
    break :blk t;
};

/// Advanced by one each frame (sap_test.zig update): the bands roll up the text.
pub var offset: u16 = 0;

pub fn handler(fb: *zg.LogicalFB, zigos: *zg.ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    fb.setPaletteEntry(SCROLL, COPPER[(line +% offset) % COPPER.len]);
}
