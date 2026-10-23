// --------------------------------------------------------------------------
// Union main -- the sky: a real raster on plane 0 (colour 0 rewritten per
// scanline from the plane's HBL), which also flickers P0's borders open.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;

const PH: usize = zg.PHYSICAL_HEIGHT; // 280

// Sky gradient: background.png horizontal bands (efmain.js). Physical row ->
// original row = (r-5)*2; the machine re-reads palette[0] per scanline via an
// HBL handler, so the gradient costs zero pixels.
const Band = struct { max_orig: i32, r: u8, g: u8, b: u8 };
const BANDS = [_]Band{
    .{ .max_orig = 21, .r = 0, .g = 0, .b = 0 },     .{ .max_orig = 23, .r = 0, .g = 0, .b = 32 },
    .{ .max_orig = 25, .r = 0, .g = 0, .b = 0 },     .{ .max_orig = 59, .r = 0, .g = 0, .b = 32 },
    .{ .max_orig = 61, .r = 0, .g = 0, .b = 64 },    .{ .max_orig = 63, .r = 0, .g = 0, .b = 32 },
    .{ .max_orig = 91, .r = 0, .g = 0, .b = 64 },    .{ .max_orig = 93, .r = 0, .g = 0, .b = 96 },
    .{ .max_orig = 95, .r = 0, .g = 0, .b = 64 },    .{ .max_orig = 123, .r = 0, .g = 0, .b = 96 },
    .{ .max_orig = 125, .r = 0, .g = 0, .b = 128 },  .{ .max_orig = 127, .r = 0, .g = 0, .b = 96 },
    .{ .max_orig = 155, .r = 0, .g = 0, .b = 128 },  .{ .max_orig = 157, .r = 0, .g = 32, .b = 160 },
    .{ .max_orig = 159, .r = 0, .g = 0, .b = 128 },  .{ .max_orig = 187, .r = 0, .g = 32, .b = 160 },
    .{ .max_orig = 189, .r = 0, .g = 64, .b = 192 }, .{ .max_orig = 191, .r = 0, .g = 32, .b = 160 },
    .{ .max_orig = 219, .r = 0, .g = 64, .b = 192 }, .{ .max_orig = 221, .r = 0, .g = 96, .b = 224 },
    .{ .max_orig = 223, .r = 0, .g = 64, .b = 192 }, .{ .max_orig = 283, .r = 0, .g = 96, .b = 224 },
};

// Per-physical-row sky colour, resolved at comptime from BANDS, as the plane stores it
// (a u32 table: an array of 4-byte Colors may sit unaligned, and a misaligned load traps on the board).
pub const SKY: [PH]u32 = blk: {
    @setEvalBranchQuota(20000);
    var t: [PH]u32 = undefined;
    for (0..PH) |r| {
        var orig: i32 = (@as(i32, @intCast(r)) - 5) * 2;
        if (orig < 0) orig = 0;
        for (BANDS) |b| {
            if (orig <= b.max_orig) {
                t[r] = (Color{ .r = b.r, .g = b.g, .b = b.b, .a = 255 }).toRGBA();
                break;
            }
        } else t[r] = (Color{ .r = 0, .g = 96, .b = 224, .a = 255 }).toRGBA();
    }
    break :blk t;
};

// Merged with the overscan trick: the parallax/tile world spans the full
// 400-wide plane, so borders must stay open every line too. Both effects are
// per-scanline palette/latch writes with no pixel-column sensitivity, so they
// share one HBL handler registered at OVERSCAN_MAGIC_X (a single per-plane
// handler slot — see docs/HW_API.md "Opening the borders").
pub fn handler(fb: *LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    // Only where the band changes (line 0 restores the top band for the new frame).
    if (line < PH and (line == 0 or SKY[line] != SKY[line - 1])) fb.palette[0] = SKY[line];
    fb.flickerBorder();
}
