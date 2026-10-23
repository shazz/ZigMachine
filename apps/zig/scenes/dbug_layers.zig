// --------------------------------------------------------------------------
// D-BUG screen — what goes onto the overscan plane besides the zoomed scroller:
// the raster HBL, the logo and the credit panel.
//
// The credit panel used to be plane 1, over the overscan plane 0. Every enabled
// plane costs FRESCO ~1.09 Mc a frame on the board, so plane 1 is now DISABLED:
// the panel still writes itself into plane 1's memory, one cell a frame
// (charpanel), and one cookie-cut CHISEL blit (key 0) puts it on top of plane 0
// each frame, after the scroller and the logo. The composed picture is the same:
//   - the panel's colours 1..3 move to PANEL_BASE + c (201..203) at compile
//     time; plane 0's pixels are 0..7 (scroller) and 100..103 (logo), so none
//     collide, and entries 201..203 hold the panel's palette, never rewritten;
//   - plane 1's colour 0 was transparent: key 0 leaves plane 0's pixel there;
//   - the panel's rows (overscan 72..239) are always in the dirty rows, so each
//     frame they are repainted (the band) or cleared (CHISEL fill) before the
//     panel goes back on: a cell the panel erased never leaves a stale letter.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const draw = @import("dbug_draw.zig");
const credits = @import("dbug_credits.zig");

const LogicalFB = zg.LogicalFB;
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const Blitter = zg.Blitter;

// --- the raster bars behind the scroller -----------------------------------

/// As the RGBA words the palette holds: a [256]Color is byte-aligned, and its
/// 4-byte loads in this HBL trapped on the board (~700 cycles each, 191 a frame).
const rasters: [256]u32 = blk: {
    @setEvalBranchQuota(10_000);
    const pal = zg.convertU8ArraytoColors(@embedFile("../assets/screens/dbug/rasters.dat"));
    var out: [256]u32 = undefined;
    for (pal, 0..) |c, i| out[i] = c.toRGBA();
    break :blk out;
};

/// The scroller's top line (physical), set by the scene each frame.
pub var start_raster_line: u16 = 0;
// What entry 7 holds (null after init): a raster coder never rewrites a colour
// register with the colour it holds, and 126 of the 191 writes a frame did.
var held7: ?u32 = null;

pub fn reset() void {
    held7 = null;
}

pub fn hbl(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    // Overscan plane: this per-plane HBL fires on PHYSICAL lines 0..279. The zoomed
    // scroller fills the whole 400-wide buffer, so open ALL borders by flickering the
    // resolution register every line (the authentic trick; see docs/HW_API.md).
    fb.flickerBorder();
    // Raster bars behind the scroller (physical line numbering).
    if (line > start_raster_line and line < start_raster_line + 192) {
        const c = rasters[line - start_raster_line];
        if (held7 != c) {
            fb.palette[7] = c;
            held7 = c;
        }
    }
}

// --- the logo ----------------------------------------------------------------

const logo_px = @embedFile("../assets/screens/dbug/logo.raw");
const LOGO_W: u16 = 253;
const LOGO_H: u16 = 38;
/// Centred in the 400-wide overscan.
const LOGO_X: i16 = zg.PHYSICAL_WIDTH / 2 - 126;
/// Its see-through colour: entry 100 (a Sprite skipped it, plane 0's entry 0 being transparent).
const LOGO_KEY: u8 = 100;

pub fn logoRows(y: i32) draw.Dirty {
    return draw.Dirty.rows(y, y + LOGO_H);
}

/// One cookie-cut blit from cart RAM (it was a CPU plot: ~5,600 byte stores).
pub fn drawLogo(c: *Blitter, dst: *LogicalFB, y: i32) void {
    c.blitImage(dst, LOGO_X, @intCast(y), logo_px, LOGO_W, 0, 0, LOGO_W, LOGO_H, LOGO_KEY);
}

// --- the credit panel --------------------------------------------------------

pub const PANEL_BASE: u8 = 200;
const font_raw = @embedFile("../assets/screens/dbug/fonts_16x14.raw");
/// The panel's glyphs with colours 1..3 at 201..203, built at compile time.
pub const panel_font: [font_raw.len]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var out: [font_raw.len]u8 = undefined;
    for (font_raw, 0..) |p, i| {
        if (p > 3) @compileError("panel font pixel > 3");
        out[i] = if (p == 0) 0 else PANEL_BASE + p;
    }
    break :blk out;
};

/// Plane 0's entries 201..203 = the panel font's colours 1..3.
pub fn panelPalette(fb: *LogicalFB, pal: [256]Color) void {
    for (1..4) |i| fb.setPaletteEntry(@intCast(PANEL_BASE + i), pal[i]);
}

const PANEL_X: i16 = zg.HORIZONTAL_BORDERS_WIDTH + credits.X;
const PANEL_TOP: u16 = zg.VERTICAL_BORDERS_HEIGHT + credits.Y;
const PANEL_H: u16 = zg.HEIGHT - credits.Y;

pub fn panelRows() draw.Dirty {
    return draw.Dirty.rows(PANEL_TOP, PANEL_TOP + PANEL_H);
}

/// The panel (plane 1's memory, a disabled plane) over plane 0: one keyed blit.
pub fn composePanel(c: *Blitter, dst: *LogicalFB, panel: *LogicalFB) void {
    c.bob(dst, PANEL_X, PANEL_TOP, panel, 0, credits.Y, zg.WIDTH, PANEL_H, 0);
}
