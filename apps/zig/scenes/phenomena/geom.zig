// --------------------------------------------------------------------------
// Where the remake's 640x480 canvas lands, and the palette map.
//
// CODEF screen 560 draws on a 640x480 canvas whose art is NOT doubled: the
// logo and the photon carry single-pixel detail across x (measured: about 10%
// of their horizontal pixel pairs differ). So the port keeps x 1:1 on a MEDIUM
// overscan plane (800x280, the whole raster with its borders) and halves y:
//
//   port line r  =  canvas row 2r+1        (one parity for every element)
//   port column  =  canvas column          (content at x 80..719)
//
// The content is 240 lines, centred in the 280-line raster (20 above). A
// 12-row bar at canvas row 129 thus becomes six clean lines (64..69).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const STRIDE: usize = zg.RASTER_WIDTH; // 800: the medium overscan buffer
pub const ROWS: usize = zg.RASTER_HEIGHT; // 280
pub const CX: usize = 80; // canvas column 0
pub const CY: usize = 20; // content line 0 = physical row 20
pub const W: usize = 640;
pub const H: usize = 240;

/// The canvas row a content line shows.
pub inline fn canvasRow(line: usize) i32 {
    return @intCast(2 * line + 1);
}

/// Byte offset of content (x, line) in the plane.
pub inline fn at(x: usize, line: usize) usize {
    return (CY + line) * STRIDE + CX + x;
}

// --- palette ---------------------------------------------------------------
// One plane, one 256-entry palette, painted in screen.js's own order.
pub const BLACK: u8 = 0;
pub const LOGO: u8 = 1; // 1..25 = logo.png's entries 0..24 (logo.raw stores png index + 1)
pub const LOGO_N: usize = 25;
pub const BAR: u8 = 26; // the purple bars: a per-line register (copper slot 0)
pub const TEXT: u8 = 27; // the text pages' ink: a per-line register (copper slot 1)
pub const PANEL: u8 = 28; // #000111, behind the scroller
pub const PHOTON: u8 = 29; // the PHOTON name: white, then red, then the hue cycle
pub const SILVER: u8 = 32; // 32..64: the DNA's front side, one entry per filmstrip row
pub const PURPLE: u8 = 65; // 65..97: its back side
pub const RED: u8 = 98; // 98..106: the red bar through the filmstrip (rows 12..20)
pub const RED_ROW0: usize = 12;
pub const RED_ROWS: usize = 9;
pub const STRIP_ROWS: usize = 33;

// --- content lines ---------------------------------------------------------
pub const LOGO_LINES: usize = 64; // logo.png rows 1,3..127
pub const PANEL_TOP: usize = 65; // the quad 130..429 -> lines 65..214
pub const PANEL_END: usize = 215;
pub const BAR_TOP: usize = 64; // cnvRasterBar at 129: lines 64..69 = bar rows 0,2..10
pub const BAR_BOTTOM: usize = 215; // ...and at 430: lines 215..220 = bar rows 1,3..11
pub const BAR_LINES: usize = 6;
pub const SCROLL_TOP: usize = 78; // cnvScroller at 156, x1.5: canvas 156..425
pub const SCROLL_END: usize = 213;
pub const RECT_TOP: usize = 187; // the reveal quad from canvas row 375
pub const PHOTON_X: usize = 285;
pub const PHOTON_W: usize = 70;
pub const PHOTON_H: usize = 15;
pub const PHOTON_REST: i32 = 445; // canvas row of the photon at rest
pub const COLUMNS: usize = 160; // slices on screen: cnvScroller x2 shows its first 320 columns
