// --------------------------------------------------------------------------
// The hub's two rasters, as registers: nothing here paints a raster as pixels.
//
// The remake drew both as images: doorrasters.png (2 px wide, 2400 tall) as a
// scrolling 640x120 layer under the street, and scrollrasters.png (640x90)
// under the TEX scroller. Every row of both is ONE colour, and every colour is
// ST-legal (each channel a multiple of 32, at most 224: the 3-bit register as
// nibble * 32), so they are colour lists the real screen wrote per scanline,
// and only the mechanism was faked. The colours are kept.
//
// WHICH REGISTER, from demozoo's bordered capture of the 1989 original
// (media.demozoo.org/screens/o/3b/f4/33b3.18725.gif, 384x270, sampled):
//
//   scroll band   its purple and teal lines run from x = 1 to x = 382, through
//                 both side borders, while the border is black above and below
//                 it. So the band is COLOUR 0: the border is painted from it.
//   door rasters  seen only through the letters of the door plaques (the TEX
//                 plaque's ink changes colour line by line), and the border
//                 beside those lines stays black. So they are a NON-zero
//                 register and stop at the screen edge.
//
// So: DOOR_INK is the ink of the door band, one colour per line, and colour 0
// carries the scroll band on the plane AND the border (the plane is 320 wide,
// so the border is the machine background, driven from the same table by the
// global HBL). The border is black elsewhere, as in the capture.
//
// Per line that is at most ONE register change: the door band (lines 0..59)
// and the scroll band (159..199) never share a line. One move.w, 12 cycles.
//
// The scroll band never moves, so colour 0's table is written once, and the
// border (which the host paints before the cart's frame) cannot lag it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

pub const BG: u8 = 0; // colour 0: the scroll band, and the border
/// The door band's ink: past every index the hub's images and raster tables use
/// (the harness checks), so nothing else ever carries it.
pub const DOOR_INK: u8 = 68;
const BG_SLOT: zg.copper.Slot = 0;
const DOOR_SLOT: zg.copper.Slot = 1;

var tables: [2]zg.copper.Table = undefined;

/// Plays both registers on `fb`, and colour 0 on the border. `band_y` is the
/// scroll band's first visible line; `band` its colour indices, one a line to
/// the bottom of the screen. Call once the depack has handed the plane back.
pub fn install(zigos: *zg.ZigOS, fb: *zg.LogicalFB, band_y: usize, band: []const u8) void {
    fb.setPaletteEntry(BG, A.palette[A.colors.BLACK]); // opaque: a colour now, not a hole
    fb.setPaletteEntry(DOOR_INK, A.palette[A.colors.BLACK]);
    zg.copper.install(fb, &.{ BG, DOOR_INK }, &tables, .{});
    const bg = zg.copper.visible(fb, BG_SLOT);
    for (band, band_y..) |c, y| bg[y] = A.palette[c].toRGBA();
    zigos.setHBLHandler(borderHbl);
}

/// DOOR_INK for each visible line of this frame.
pub fn doorInk(fb: *const zg.LogicalFB) *[zg.HEIGHT]u32 {
    return zg.copper.visible(fb, DOOR_SLOT);
}

/// The global HBL: PHYSICAL lines 0..279, colour 0 in the border.
fn borderHbl(zigos: *zg.ZigOS, line: u16) void {
    const bg = zg.copper.table(&zigos.lfbs[0], BG_SLOT);
    if (line < bg.len) zigos.setBackgroundColor(zg.Color.fromRGBA(bg[line]));
}
