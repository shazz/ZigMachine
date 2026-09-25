// --------------------------------------------------------------------------
// COPIER TEX's raster windows, as a register: nothing here paints them as pixels.
//
// The remake drew raster1..8.png (640x96) through six 32-row drawPart windows.
// Every row of those images is ONE colour, and every channel sits on one of
// EIGHT levels (0, 32|33, 65|66, 97|99, 130|132, 162|165, 195|198, 227|231: the
// ST's 3-bit register, rendered by two slightly different nibble * ~32.5
// scalings), so they are colour lists the real copier wrote per scanline; only the
// mechanism was faked. The colours are kept, and so are the 50/50 mixes Chrome
// makes at the windows' half-row source offsets: they are what the remake shows,
// and a per-line register holds any colour.
//
// COLOUR 0. The bars run the full width behind the display panel (demozoo's
// capture of the original, media.demozoo.org/screens/o/75/be/56ab.18737.gif,
// shows them edge to edge of its 320x200), i.e. they are the background, and on
// the ST the border is painted from colour 0 as well. The copier's own text says
// it uses no border ("EXCUSE US FOR NOT USING ANY BORDER"), so the sides stay
// closed and the bars reach them anyway: the plane is 320 wide, so the border is
// the machine background, driven per physical line by the global HBL. No
// bordered capture of this screen exists, so the border's colour is inferred
// from the mechanism, not measured.
//
// Budget: ONE register, colour 0, rewritten only where a line's colour differs
// from the line above: at most one move.w, 12 cycles, a line.
//
// The host paints the border (hwClear, the global HBL) BEFORE the cart's frame,
// so the border's table is the NEXT frame's colour 0: the raster state does not
// depend on the keys (copier.zig), so a copy stepped once is exact.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

pub const BG: u8 = 0; // colour 0
const BG_SLOT: zg.copper.Slot = 0;
const TOP = (zg.PHYSICAL_HEIGHT - zg.HEIGHT) / 2; // the first visible physical row

var tables: [1]zg.copper.Table = undefined;
var border: [zg.PHYSICAL_HEIGHT]u32 = undefined;

/// Plays colour 0 on `fb` and on the border. Colour 0 becomes opaque black: it
/// is the background now, not a hole.
pub fn install(zigos: *zg.ZigOS, fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(BG, A.palette[A.BLACK]);
    zg.copper.install(fb, &.{BG}, &tables, .{});
    @memset(&border, A.palette[A.BLACK].toRGBA()); // the top and bottom borders stay black
    zigos.setHBLHandler(borderHbl);
}

/// Colour 0 for each visible line of this frame.
pub fn background(fb: *const zg.LogicalFB) *[zg.HEIGHT]u32 {
    return zg.copper.visible(fb, BG_SLOT);
}

/// Colour 0 for each visible line of the NEXT frame, as the border shows it.
pub fn nextBorder() *[zg.HEIGHT]u32 {
    return border[TOP..][0..zg.HEIGHT];
}

/// The global HBL: PHYSICAL lines 0..279, the border's colour 0.
fn borderHbl(zigos: *zg.ZigOS, line: u16) void {
    if (line < border.len) zigos.setBackgroundColor(zg.Color.fromRGBA(border[line]));
}
