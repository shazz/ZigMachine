// --------------------------------------------------------------------------
// The two REAL raster bars, done the ST way: a palette register changed per
// scanline, nothing in the framebuffer.
//
// The Go remake blits rep_ik+_rast1.png and rep_ik+_rast2.png as sprites.  They
// are not pixel art: each row of each is ONE solid colour (measured in
// ikplus_assets.py), i.e. a table for the colour registers.  So here:
//
//   index 0  is the background: the backRast rainbow of blue/green/red/cyan
//            bands scrolling up one line a frame (game.go's 11 back slices)
//   index 1  is the scrolltext: a 200-row rainbow wrapped around (game.go's
//            mergeCanvas, three copies of the 200-row rast1 at posY2-200/0/+200)
//
// Both run the full 400-column raster, borders included: on an ST the border
// is the same colour register, so a bar cannot stop at the content edge.  The
// plane is overscan and this handler — installed in place of openBorders()'s —
// flickers EVERY line so the sides open too (replicants_emlyn/rasters.zig is
// the worked example; vex/intro.zig says the same in words).
//
// WHAT A LINE COSTS.  A real raster coder never rewrites a register that
// already holds the right colour.  The background moves a line a frame, so its
// colour genuinely changes on most content lines and is written; the border
// bands are black and are written once, when the first black line is met.  The
// rainbow changes every line the text is on.  Two entries a line at most, well
// under an open line's ~88-entry budget (movem.l, 4.5 cycles an entry).
//
// The two scroll positions are 2x units, exactly as the remake counts them:
// posY steps 2 to 654 (so the background crawls one ST line a frame) and posY2
// steps down from 200 to 1 (so the rainbow crawls half a line a frame).  That
// is why the tables are kept at their 2x row counts and indexed by 2*t.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

/// The content window in physical coordinates, as u32 (assets.zig keeps the
/// same numbers as usize for the framebuffer index arithmetic).
const OY: u32 = @intCast(A.CONTENT_Y);
const OH: u32 = @intCast(A.CONTENT_H);

/// game.go's g.posY: 0..652, even, +2 a frame.
pub var pos_y: u16 = 0;
/// game.go's g.posY2: 1..200, -1 a frame.
pub var pos_y2: u16 = 200;

const BAND_STEP: u32 = 36; // 2x rows between back slices
const BAND_H: u32 = 36; // 2x rows in one slice
const BAND_COUNT: usize = 11;
/// len(backSlices) in the remake: (690 - 36) / 2 + 1.  An index at or past it
/// is a slice the remake SKIPS (its bottom band goes black for a few frames of
/// each 327-frame cycle); kept so the port matches.
const MAX_SLICE: u32 = 328;

var last0: u32 = 0xFFFF_FFFF;
var last1: u32 = 0xFFFF_FFFF;

/// Replace openBorders()'s flicker-all handler with one that also paints the
/// two per-line registers.
pub fn install(fb: *zg.LogicalFB) void {
    last0 = 0xFFFF_FFFF;
    last1 = 0xFFFF_FFFF;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    // zigos's flickerAllHbl, which openBorders(.all) installed and this
    // handler replaces: EVERY line, so the sides reopen on the visible ones
    // and the rasters run edge to edge.
    fb.flickerBorder();
    const c0 = bg(line);
    if (c0 != last0) {
        fb.palette[A.IDX_BG] = c0;
        last0 = c0;
    }
    const c1 = rainbow(line);
    if (c1 != last1) {
        fb.palette[A.IDX_TEXT] = c1;
        last1 = c1;
    }
}

/// game.go Draw()'s back-slice loop, in ST rows: content row t (1..198) shows
/// slice j = (2t-2)/36 sampled at pos_y + (2t-2) - 32j, and slice index
/// pos_y/2 + 2j; row 0 and row 199 are above/below the slices and stay black,
/// as do the borders.
fn bg(phys: u16) u32 {
    if (phys < OY or phys >= OY + OH) return A.BLACK;
    const t: u32 = phys - OY;
    if (t == 0 or t + 1 == OH) return A.BLACK;
    const y2: u32 = 2 * t; // the remake's 2x content row
    if (y2 < 2 or y2 >= 2 + BAND_STEP * BAND_COUNT) return A.BLACK;
    const j: u32 = (y2 - 2) / BAND_STEP;
    const index: u32 = @as(u32, pos_y) / 2 + 2 * j;
    if (index >= MAX_SLICE) return A.BLACK;
    const src: u32 = @as(u32, pos_y) + y2 - 2 - 32 * j; // == index*2 + (y2 - 2 - 36j)
    return A.rast2[src];
}

/// mergeCanvas: rast1 repeated every 200 2x rows.  An ST line's colour is the
/// 2x row 2t - posY2, so the rainbow crawls half a line a frame and its 200-row
/// period covers the content twice over.
fn rainbow(phys: u16) u32 {
    if (phys < OY or phys >= OY + OH) return A.BLACK;
    const t: i32 = @as(i32, phys) - @as(i32, @intCast(OY));
    const idx: u32 = @intCast(@mod(2 * t - @as(i32, pos_y2), 200));
    return A.rast1[idx];
}
