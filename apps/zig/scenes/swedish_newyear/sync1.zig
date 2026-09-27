// --------------------------------------------------------------------------
// SYNC SCREEN #1, from the disk: the part the loader reads from tracks 45..55
// to $20000 on F1 (prototypes/snyd_re/NOTES.md). Its main loop ($20022), once
// a VBL, in order:
//   $204B4  the raster table: colour 0 for all 200 lines, which Timer B (event
//           count 1, $202E6) writes to $FF8240 at the END of every line -- so
//           line y shows entry y-1. A fixed rainbow at 115, five bars riding a
//           sine table ($2BEF2) and a white bar at 20, in that order.
//   the frame palette from ($286C0), for lines 0..54; after writing entry 54
//           the Timer B handler sets colours 1..15 once more for the rest.
//   $2045C  the banner: the SYNC logo / the four faces, squashed by copying a
//           list of source lines (42 lists, $2B678), drawn into the SHOWN buffer
//           early in the frame.
//   $213D4  flip the two screens, then the nine-letter scroller (sync1_letters.zig).
//   $20660  the "Redhead" logo, a vertical wave of 16-pixel columns.
// Space (scancode $39) goes to SYNC #2.
//
// The remake had the bars, the banner and the scroller, but re-derived all
// of them from sine formulas and PNGs; it invented the flipping/bouncing
// scroller modes and dropped the logo's per-column wave, the squash lists and
// the scroller's own distortion lists. None of that is used here.
//
// Checked: every routine below reproduces Hatari's RAM of the running demo byte
// for byte -- both screens, the raster table and every variable -- after 100
// and after 1500 iterations from the part's first (prototypes/snyd_re/
// sync1_model.py is the same code in Python, run against the dumps).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const letters = @import("sync1_letters.zig");
pub const init = @import("sync1_init.zig").init;

const Ram = st.Ram;

pub const BASE: u32 = 0x20000; // where the loader puts the part
pub const TOP: u32 = 0x80000; // the screens at $70000 / $78000 end here

pub const DRAW: u32 = 0x21656; // .l the buffer being drawn
pub const SCR_A: u32 = 0x2165C; // .l
pub const SCR_B: u32 = 0x21660; // .l
pub const FLIP: u32 = 0x2165A; // .b which of the two was set last
pub const BAND: u32 = 0x21676; // .l the draw buffer's line 100
pub const LINE_TAB: u32 = 0x216B8; // .w line * 160, 201 entries
pub const RASTERS: u32 = 0x2BD32; // .w colour 0 per line, 200 entries
const SINE: u32 = 0x2BEF2; // .w byte offsets into RASTERS, stepped by 4
const PAL_PTR: u32 = 0x286C0; // .l the frame palette
const IMAGE: u32 = 0x2854E; // .l the banner picture, 80 bytes a line
const IMAGE_PAIR: u32 = 0x28552; // .l -> (picture, palette) at $28534 / $2853C
const SQUASH: u32 = 0x2B674; // .l -> the next of the 42 line lists
const LOGO_ROWS: u32 = 0x207BE; // .l -> this frame's 24 row offsets ($207C6..)
const LOGO_COLS: u32 = 0x207C2; // .l -> this frame's 6 column heights ($20846..)
const LOGO_WORK: u32 = 0x208C6; // 24 rows of 48 bytes

/// Colours 1..15 from line 55 down (Timer B, $202F6).
pub const LOWER = [15]u16{ 0x300, 0x500, 0x700, 0x777, 0x752, 0x003, 0x005, 0x111, 0x222, 0x333, 0x000, 0x444, 0x555, 0x666, 0x333 };
pub const PAL_SWITCH_LINE = 55;

/// What a frame shows, captured as the iteration starts (see swedish_newyear.zig).
pub const Shown = struct { screen: u32, palette: u32 };

/// One pass of the main loop, $2003A..$2007E (the music plays from its SNDH).
pub fn iteration(r: *const Ram) Shown {
    rasters(r);
    const shown = Shown{ .screen = r.l(DRAW), .palette = r.l(PAL_PTR) };
    banner(r);
    letters.scroller(r);
    logo(r);
    return shown;
}

/// $204B4.
pub fn rasters(r: *const Ram) void {
    r.zero(RASTERS, 400);
    r.cp(RASTERS + 0xE6, 0x28600, 40); // the rainbow, lines 115..134
    r.cp(RASTERS + 0x10E, 0x28628, 40); // and 135..154
    const bars = [5][3]u32{
        .{ 0x28544, 0x285CA, 16 }, .{ 0x28546, 0x285B6, 16 }, .{ 0x28548, 0x2859E, 20 },
        .{ 0x2854A, 0x2857E, 28 }, .{ 0x2854C, 0x28556, 40 },
    };
    for (bars) |bar| {
        var v = r.w(bar[0]) + 4;
        if (v == 0x2D0) v = 0;
        r.sw(bar[0], v);
        r.cp(st.add(RASTERS, st.sx(r.w(SINE + v))), bar[1], bar[2]);
    }
    r.cp(RASTERS + 0x28, 0x285DA, 28); // the white bar, lines 20..33
}

/// $2045C / $2034E.
fn banner(r: *const Ram) void {
    var a2 = r.l(r.l(SQUASH));
    var a0 = r.l(DRAW) + 0x168 + r.w(LINE_TAB + 2 * @as(u32, r.b(a2)));
    a2 += 1;
    for ([_]i32{ -0xA0, -0x78, 0, 0x28, 0xA0, 0xC8, 0x140, 0x168 }) |off| r.zero(st.add(a0, off), 44);
    a0 += 0x140;
    while (true) : (a0 += st.LINE) {
        const line = r.b(a2);
        a2 += 1;
        if (line == 0xFF) break;
        r.cp(a0, r.l(IMAGE) + @as(u32, line) * 0x50, 0x50);
    }
    for ([_]u32{ 0, 0x28, 0xA0, 0xC8, 0x140, 0x168 }) |off| r.zero(a0 + off, 44);
    if (r.l(SQUASH) == 0x2B720) { // the last list: the other picture
        r.sl(SQUASH, 0x2B678);
        var p = r.l(IMAGE_PAIR) + 8;
        if (p == 0x28544) p = 0x28534;
        r.sl(IMAGE_PAIR, p);
        r.sl(IMAGE, r.l(p));
        r.sl(PAL_PTR, r.l(p + 4));
    }
    r.sl(SQUASH, r.l(SQUASH) + 4);
}

/// $20660: 24 rows picked from the logo's 16 preshifts (a horizontal wave),
/// then 6 columns of 16 pixels, planes 0-1 only, each at its own height.
fn logo(r: *const Ram) void {
    var rows = r.l(LOGO_ROWS) + 2;
    if (rows == 0x20806) rows = 0x207C6;
    r.sl(LOGO_ROWS, rows);
    for (0..24) |i| {
        const src = st.add(0x37B30 + 0x30 * @as(u32, @intCast(i)), st.sx(r.w(rows + 2 * @as(u32, @intCast(i)))));
        const dst = LOGO_WORK + 0x30 * @as(u32, @intCast(i));
        r.cp(dst, src, 20);
        r.cp(dst + 0x18, src + 0x18, 20);
    }
    var cols = r.l(LOGO_COLS) + 2;
    if (cols == 0x20886) cols = 0x20846;
    r.sl(LOGO_COLS, cols);
    for (0..6) |c| {
        const cu: u32 = @intCast(c);
        const top = st.add(r.l(DRAW) + 0x2298 + 8 * cu, st.sx(r.w(cols + 2 * cu)));
        for (0..4) |k| {
            const a2 = top + @as(u32, @intCast(k));
            r.sb(a2 - 0xA0, 0);
            r.sb(a2 - 0x140, 0);
            for (0..24) |row| r.sb(a2 + @as(u32, @intCast(row)) * 0xA0, r.b(LOGO_WORK + 8 * cu + @as(u32, @intCast(k)) + @as(u32, @intCast(row)) * 0x30));
            r.sb(a2 + 0xF00, 0);
            r.sb(a2 + 0xFA0, 0);
        }
    }
}

/// Colour-register state of ST line `y` (0..199) for the frame `shown` describes.
pub fn lineColour0(r: *const Ram, shown: Shown, y: usize) u16 {
    if (y == 0) return r.w(shown.palette);
    return r.w(RASTERS + 2 * @as(u32, @intCast(y - 1)));
}

/// Colours 1..15 of ST line `y`.
pub fn lineColour(r: *const Ram, shown: Shown, y: usize, i: usize) u16 {
    if (y >= PAL_SWITCH_LINE) return LOWER[i - 1];
    return r.w(shown.palette + 2 * @as(u32, @intCast(i)));
}
