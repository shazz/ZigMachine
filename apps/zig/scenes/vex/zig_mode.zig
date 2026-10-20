// --------------------------------------------------------------------------
// ZIG MODE, switched by Z at any moment (vex.zig's key()); ORIGINAL is the
// default and is the ST's screen exactly.
//
//   ORIGINAL  both scrollers stop at the 320-px window, borders closed
//   ZIG       the big scroller and Metallinos' bottom one run on through the
//             LEFT and RIGHT borders, 400 px edge to edge
//
// The borders are earned the ST way: the plane's own HBL (raster.rasterHbl)
// flickers the resolution at OVERSCAN_MAGIC_X, and only on the lines a
// scroller can reach -- the big one's wave range and the eight bottom rows.
// Every other line, and the top and bottom bands, stay closed.  The window is
// the same in both modes (the scroller layers are always kept 26 words wide,
// see scroller.zig / small.zig), so the switch only adds the side words.
//
// The open sides carry the raster on: a side pixel with no ink is SIDE_BG,
// which rasterHbl sets per line to the colour the closed border is painted
// (that line's colour 0), so the raster still runs the full width.
// --------------------------------------------------------------------------
const P = @import("planes.zig");
const big = @import("scroller.zig");
const raster = @import("raster.zig");

/// The mode the keyboard asked for; sync() applies it at the intro's next
/// update. `live` is the mode applied (raster.rasterHbl opens the sides while
/// it is set), `repaint` that the side words still need their first full one.
pub var wanted = false;
pub var live = false;
var repaint = false;

pub fn reset() void {
    wanted = false;
    live = false;
    repaint = false;
}

/// Apply a Z press. Only the intro has scrollers, so only it opens borders.
pub fn sync() void {
    if (wanted == live) return;
    live = wanted;
    if (!live) return; // closing needs nothing: the window never changed
    // row_pal is not rebuilt until render, so it still holds what borderHbl
    // painted this frame's border with; from now on borderHbl records it.
    for (&raster.side_bg, raster.row_pal) |*c, r| c.* = r[0];
    clearSides();
    repaint = true;
}

/// The side words into the buffer, after the window's own recompose.
pub fn compose(fb: []u8, stride: usize, sc: *const big.Scroller) void {
    if (!live) return;
    composeBig(fb, stride, sc, repaint);
    composeSmall(fb, stride);
    repaint = false;
}

pub fn isToggle(cp: u32) bool {
    return cp == 'Z' or cp == 'z';
}

/// The buffer words outside the window: 0..2 on the left, 23..25 on the right.
const SIDE = blk: {
    var t: [2 * P.WIN_WORD]usize = undefined;
    for (0..P.WIN_WORD) |i| {
        t[i] = i;
        t[P.WIN_WORD + i] = P.WIN_WORD + P.WORDS + i;
    }
    break :blk t;
};

/// Does window row `y` get its side borders opened?
pub fn sideRow(y: usize) bool {
    return (y >= big.INK_TOP and y < big.INK_END) or
        (y >= P.SMALL_TOP and y < P.SMALL_TOP + P.SMALL_ROWS);
}

/// Entering ZIG MODE: the side words of the big scroller's layer were not drawn
/// while the mode was off, so blank them before the first draw.
fn clearSides() void {
    for (P.scroll) |*row| for (SIDE) |k| {
        row[k] = 0;
    };
}

fn sideRows(fb: []u8, stride: usize, s: usize, y_top: usize, y_end: usize) void {
    const k = SIDE[s];
    var y = y_top;
    while (y < y_end) : (y += 1) {
        const out = fb[(P.ORG_Y + y) * stride + 16 * k ..][0..16];
        P.inkWord(out, P.scroll[y][k], P.SCROLL_INK);
    }
}

/// The big scroller's side words into the buffer. `full` repaints every row they
/// can reach (the first frame of the mode); otherwise only the rows draw() just
/// painted, which are the only ones that changed.
fn composeBig(fb: []u8, stride: usize, sc: *const big.Scroller, full: bool) void {
    for (0..SIDE.len) |s| {
        if (full) {
            sideRows(fb, stride, s, big.REACH_TOP, big.REACH_END);
        } else {
            const y0 = sc.side_y0[s] - 4;
            sideRows(fb, stride, s, y0, y0 + big.COLUMN_ROWS);
        }
    }
}

/// Metallinos' side words: every one moves a pixel a frame.
fn composeSmall(fb: []u8, stride: usize) void {
    for (P.small, 0..) |*bits, r| {
        for (SIDE) |k| {
            const out = fb[(P.ORG_Y + P.SMALL_TOP + r) * stride + 16 * k ..][0..16];
            P.inkWord(out, bits[k], P.PANEL_INK);
        }
    }
}
