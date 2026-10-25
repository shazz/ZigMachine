// The B.I.G. Demo jukebox's frame, drawn the way a coder with a real screen
// would: the page ONCE, then only the rows whose pixels can change.
//
// go() (screen.js:390-492) repaints the whole canvas every frame: three colour
// bands, main.png over them, the scroller, two shadow strips, the five list rows
// and the two rules. Every one of those layers is a function of its row alone,
// so a row's pixels change only when the state that row reads changes:
//   the HOLED rows of the bands       -> the cycle tile (every 2-3 frames)
//   the scroller band, 222..237       -> every frame (the letters move)
//   the list block, 92..131           -> the cursor or the highlight
//   everything else                   -> never: main.png and its shadows
// Each zone is rebuilt in go()'s own layer order, from main.png up, so the
// rebuilt row is the row go() would have painted. The 50% shadow is a LUT on
// what is underneath (not idempotent), so a shadowed row is always rebuilt from
// the picture first and shaded exactly once. The board measured the whole-canvas
// version at 1.26 Mc of cart a frame; the rows that change are ~5 KB of it.
// `Drawn.page = false` (first go(), coming back from a sub-screen) repaints all.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const paint = @import("paint.zig");
const row = paint.row;

/// What is on the plane now, so a frame can tell what it has to redraw.
pub const Drawn = struct {
    page: bool = false, // the jukebox's whole page is on the plane
    wait: bool = false, // the instruction screen is
    tile: usize = 0, // the cycle tile in the bands
    curent: usize = 0, // the list block's cursor...
    playing: usize = 0, // ...and highlight

    /// Something else painted the plane (a sub-screen, restore()).
    pub fn invalidate(self: *Drawn) void {
        self.page = false;
        self.wait = false;
    }
};

/// The scroller's state, as Screen holds it.
pub const Scroller = struct { bgscrposx: i32, posx: []const i32, ltr: []const u8 };

/// The current cycle tile, already repeated across the screen: a band costs 5
/// row builds and 20 row copies, not a per-pixel fill of 6,400.
/// align(8), like A.cycle: the row copies go out as u64s, and on the board a
/// misaligned one traps (~210 cycles; it was 400 traps a frame).
var band_rows: [A.CYCLE_H][A.W]u8 align(8) = undefined;

/// Repeat cycle tile `t`'s 5 rows across the full width.
fn expandBand(t: usize) void {
    const tile = A.cycle[t * A.CYCLE_H * A.CYCLE_W ..][0 .. A.CYCLE_H * A.CYCLE_W];
    for (&band_rows, 0..) |*dst, y| {
        const line = tile[y * A.CYCLE_W ..][0..A.CYCLE_W];
        var x: usize = 0;
        while (x < A.W) : (x += A.CYCLE_W) @memcpy(dst[x..][0..A.CYCLE_W], line);
    }
}

/// mymain.draw(mycanvas,0,0) for one row: opaque everywhere but the windows.
fn mainRow(fb: *LogicalFB, holed: []const bool, y: usize) void {
    const src = A.main_img[y * A.W ..][0..A.W];
    const dst = row(fb, y);
    if (!holed[y]) return @memcpy(dst, src);
    for (src, dst) |s, *d| {
        if (s != A.TRANSPARENT) d.* = s;
    }
}

/// Band rows (all, or only the holed ones: the rest end as main.png whatever
/// the tile), each rebuilt band -> main -> shadow, as go() layers them.
fn bands(fb: *LogicalFB, holed: []const bool, tile: usize, all: bool) void {
    expandBand(tile);
    for (A.BAND_Y) |by| {
        for (0..A.BAND_H) |i| {
            const y = by + i;
            if (!all and !holed[y]) continue;
            @memcpy(row(fb, y), &band_rows[i % A.CYCLE_H]);
            if (!all) {
                mainRow(fb, holed, y);
                paint.shadowRow(fb, y);
            }
        }
    }
}

/// The scroller band from the picture up: main, letters, shadow.
fn scrollZone(fb: *LogicalFB, holed: []const bool, s: Scroller) void {
    for (SCROLL_LO..SCROLL_HI) |y| mainRow(fb, holed, y);
    paint.scroller(fb, A.SCROLL_Y, s.bgscrposx, s.posx, s.ltr);
    for (SCROLL_LO..SCROLL_HI) |y| paint.shadowRow(fb, y);
}

/// The list block from the picture up: main, the five rows, the two rules.
fn listZone(fb: *LogicalFB, holed: []const bool, curent: usize, playing: usize) void {
    for (LIST_LO..LIST_HI) |y| mainRow(fb, holed, y);
    paint.listRows(fb, curent, playing);
    // The rules are one live pen (A.PULSE): the per-frame palette write moves them.
    for (A.RULE_Y) |ry| @memset(row(fb, ry), A.PULSE);
}

/// One go() frame's pixels. `holed` is main.png's rows with a transparent hole.
pub fn draw(d: *Drawn, fb: *LogicalFB, holed: []const bool, tile: usize, curent: usize, playing: usize, s: Scroller) void {
    if (!d.page) {
        // go()'s whole canvas, in its order: bands, main, scroller, shadows, list.
        bands(fb, holed, tile, true);
        for (0..A.H) |y| mainRow(fb, holed, y);
        paint.scroller(fb, A.SCROLL_Y, s.bgscrposx, s.posx, s.ltr);
        paint.shadows(fb);
        paint.listRows(fb, curent, playing);
        for (A.RULE_Y) |ry| @memset(row(fb, ry), A.PULSE);
        d.* = .{ .page = true, .tile = tile, .curent = curent, .playing = playing };
        return;
    }
    if (tile != d.tile) bands(fb, holed, tile, false);
    scrollZone(fb, holed, s);
    if (curent != d.curent or playing != d.playing) listZone(fb, holed, curent, playing);
    d.tile = tile;
    d.curent = curent;
    d.playing = playing;
}

/// wait(): the instruction screen is a still picture, drawn once.
pub fn drawWait(d: *Drawn, fb: *LogicalFB) void {
    if (d.wait) return;
    for (0..A.H) |y| @memcpy(row(fb, y), A.wait_img[y * A.W ..][0..A.W]);
    d.wait = true;
}

const SCROLL_LO: usize = A.SCROLL_Y;
const SCROLL_HI: usize = A.SCROLL_Y + A.SCROLL_H;
const LIST_LO: usize = A.LIST_Y;
const LIST_HI: usize = A.LIST_Y + (A.LIST_INK.len - 1) * A.LIST_STEP + A.PH;

fn overlaps(lo: usize, hi: usize, a: usize, b: usize) bool {
    return lo < b and a < hi;
}

// What makes the zones exact: they share no row, so rebuilding one never
// disturbs another; the scroller's 16 rows and the list's five are inside their
// zone; every shadow strip lies in the scroller zone or in one band (a band row
// that is not rebuilt keeps its shaded picture, which no tile changes); the
// rules sit inside the list block.
comptime {
    for (A.BAND_Y) |by| {
        if (overlaps(SCROLL_LO, SCROLL_HI, by, by + A.BAND_H)) @compileError("a band crosses the scroller zone");
        if (overlaps(LIST_LO, LIST_HI, by, by + A.BAND_H)) @compileError("a band crosses the list zone");
    }
    if (overlaps(SCROLL_LO, SCROLL_HI, LIST_LO, LIST_HI)) @compileError("the scroller and list zones overlap");
    for (A.RULE_Y) |ry| if (ry < LIST_LO or ry >= LIST_HI) @compileError("a rule is outside the list zone");
    for (A.SHADOW_Y) |sy| {
        const lo: usize = sy;
        const hi: usize = sy + A.SHADOW_TONE.len;
        var inside = lo >= SCROLL_LO and hi <= SCROLL_HI;
        for (A.BAND_Y) |by| inside = inside or (lo >= by and hi <= by + A.BAND_H);
        if (!inside) @compileError("a shadow strip is outside every rebuilt zone");
    }
}
