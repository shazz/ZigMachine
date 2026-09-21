// --------------------------------------------------------------------------
// The polka dots. pat.png is 70x7 and initTile(7,7) cuts it into TEN 7x7 dots
// (screen.js:44, 82): the dot grows from nothing to a full 7x7 block and
// brightens from (88,19,19) to (255,217,217) as it grows. Dot SIZE carries the
// intensity, which is what newsprint halftone does and what no fixed 1-bit
// pattern can do.
//
// The stamp is a real BLIT per cell — B = the sprite sheet in cart RAM
// (CON2.SRC_ABS), MINTERM = B, no colour key, because the original's tiles are
// fully opaque: a tile paints its own (7,7,7) field over whatever was there.
// One blit per lit cell is the honest cost of this effect on this machine; see
// the scene's header for the measurement.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Color = zg.Color;
const shade = @import("shade.zig");

pub const CELL = 7; // initTile(7, 7)

/// Palette index of the darkest dot ink; the ramp runs INK_BASE..INK_TOP, one
/// entry per intensity, and every render mode shades out of it.
pub const INK_BASE: u8 = 2;
pub const INK_TOP: u8 = 11;
pub const LABEL_INK: u8 = 12;
pub const TAP_INK: u8 = 13; // visually black, see readout.zig
const SHEET_W: u16 = 70;

/// What one frame of a render mode cost: blitter OPERATIONS issued, and the
/// pixels the blitter reported touching (BLIT_CYCLES, read after every op).
/// Counting them is the cheapest performance instrument this machine has.
pub const Cost = struct { ops: u32 = 0, px: u32 = 0 };

/// pat.png as palette indices: 1 is the tile field, 2 + t is tile t's ink.
/// tools/private_tools/polkadots_assets.py.
const PAT = @embedFile("../../assets/screens/polkadots/pat.raw");

/// The grid is centred on the 320x200 screen. The original hangs it at the
/// bottom of its 640x480 canvas (x*7+71, y*7+142) to leave room for the logo
/// and the letters; with only the torus on screen, centred is where it goes.
pub const GRID_W: usize = shade.CELLS_X * CELL;
pub const GRID_H: usize = shade.CELLS_Y * CELL;
pub const X_OFF: i16 = @intCast((@as(usize, zg.WIDTH) - GRID_W) / 2);
pub const Y_OFF: i16 = @intCast((@as(usize, zg.HEIGHT) - GRID_H) / 2);

/// Entry 0 is the canvas black the screen is filled with; 1 the (7,7,7) field
/// every tile carries; 2..11 the ten dot inks, read straight off pat.png.
pub fn palette() [256]Color {
    var p = [_]Color{.{ .r = 0, .g = 0, .b = 0, .a = 255 }} ** 256;
    p[0] = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    p[1] = .{ .r = 7, .g = 7, .b = 7, .a = 255 };
    p[2] = .{ .r = 7, .g = 7, .b = 7, .a = 255 }; // tile 0 has no dot
    p[3] = .{ .r = 88, .g = 19, .b = 19, .a = 255 };
    p[4] = .{ .r = 130, .g = 26, .b = 26, .a = 255 };
    p[5] = .{ .r = 167, .g = 32, .b = 32, .a = 255 };
    p[6] = .{ .r = 204, .g = 37, .b = 37, .a = 255 };
    p[7] = .{ .r = 245, .g = 44, .b = 44, .a = 255 };
    p[8] = .{ .r = 255, .g = 79, .b = 79, .a = 255 };
    p[9] = .{ .r = 255, .g = 115, .b = 115, .a = 255 };
    p[10] = .{ .r = 255, .g = 141, .b = 141, .a = 255 };
    p[11] = .{ .r = 255, .g = 217, .b = 217, .a = 255 };
    p[LABEL_INK] = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    p[TAP_INK] = .{ .r = 0, .g = 0, .b = 1, .a = 255 }; // black to the eye, a 1 to the harness
    return p;
}

/// MODE 1. Stamp every lit cell of `grid` and report what that cost — one
/// hardware blit per lit cell, the number the other modes are measured against.
pub fn stamp(fb: *zg.LogicalFB, bl: *zg.Blitter, grid: *const shade.Grid) Cost {
    var cost = Cost{};
    for (0..shade.CELLS_Y) |cy| {
        const dy = Y_OFF + @as(i16, @intCast(cy * CELL));
        for (0..shade.CELLS_X) |cx| {
            const cell = grid[cy * shade.CELLS_X + cx];
            if (cell == 0) continue; // red 0: screen.js draws no tile at all
            const sx: u16 = @as(u16, cell - 1) * CELL;
            const dx = X_OFF + @as(i16, @intCast(cx * CELL));
            bl.blitImage(fb, dx, dy, PAT, SHEET_W, sx, 0, CELL, CELL, null);
            cost.ops += 1;
            cost.px += bl.cycles();
        }
    }
    return cost;
}
