// --------------------------------------------------------------------------
// F5 -- SYNC: "the best scroller around" (part 5: track 70 side 0,
// ByteKiller-packed, to $C000; Redhead, July 1989): a giant scroller over a
// moving texture, in a FULL overscan screen (every border open, 230-byte
// lines), scrolled by moving the screen's start (sync-scrolling, as the
// part's patched line routines do on the ST: the eight lines at the top of
// the frame take the lengths that put the start on any even byte).
//
// The set-up ($17D8E: screens, the 32 preshifts of the tile, the patched
// fullscreen code, the cells) ran once on the original code (the Musashi
// oracle) and its memory is the asset ($C000..$80000). Each VBL from there,
// the main loop ($17EDC):
//   music  its YM stream ($1380C: 8 bytes a frame from $C006) -- the cart
//          plays snyd90_f5.sndh instead, but the pointer moves as on the ST
//   flip   $17900: swap the screen pairs; the start is the screen + scroll
//   tile   f5_texture.zig: its walkers and colours
//   column f5_scroll.zig: clear the column left behind, the next one in
// then what the fullscreen routine ($1525E, from Timer A) does between its
// border switches: the texture over the whole picture and the column into
// both screens. What it shows: 252 lines of 230 bytes from the start + 78
// (measured on Hatari: a RAM dump against its screenshot), the top border
// opened 16 lines above the window, picture to its line 235.
// Best effort: the line routines' timing (which only keeps the borders open)
// is not modelled; the order of the main loop and Timer A is assumed fixed.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const texture = @import("f5_texture.zig");
const scroll = @import("f5_scroll.zig");

pub const BASE: u32 = 0xC000;
pub const TOP: u32 = 0x80000;
pub const PALETTE: u32 = 0x195DA; // the picture's; $1807E the borders'
pub const LINES: usize = 252;
pub const FIRST_LINE: i32 = -16; // the picture's first line (ST window = 0)
/// The picture's line 0 starts this far past the screen start.
pub const SKEW: u32 = 78;

const MUSIC: u32 = 0x13808;
const PREV: u32 = 0x18DBE;

pub fn enter(r: *const st.Ram) void {
    texture.enter(r);
}

/// One VBL: the main loop, then the fullscreen routine's writes. Returns
/// the start of the picture shown next.
pub fn vbl(r: *const st.Ram) u32 {
    mainLoop(r);
    fullscreen(r);
    return r.l(texture.SHOWN) + SKEW;
}

/// The main loop's pass ($17EDC..$17F52).
pub fn mainLoop(r: *const st.Ram) void {
    var p = r.l(MUSIC) + 8;
    if (p >= 0x13806) p = 0xC006;
    r.sl(MUSIC, p);
    flip(r);
    texture.move(r);
    texture.colours(r);
    r.cp(r.l(scroll.SCREEN) + r.l(scroll.SCROLL) + 0x10, 0x1807E, 32);
    scroll.clear(r, r.l(scroll.OTHER));
    scroll.clear(r, r.l(scroll.SCREEN));
    scroll.advance(r);
}

/// What the fullscreen routine ($15A68..) writes between its border switches.
pub fn fullscreen(r: *const st.Ram) void {
    texture.draw(r);
    scroll.column(r);
}

/// $17900: both pairs swap; the start, and the line routines' patch ($17890:
/// eight jsr targets from $1CC6A by the low byte of the start, kept so the
/// memory stays the original's).
fn flip(r: *const st.Ram) void {
    swap(r, scroll.OTHER);
    swap(r, scroll.SCREEN);
    r.sl(texture.SHOWN, r.l(scroll.SCREEN) + r.l(scroll.SCROLL));
    const low: u32 = (r.l(PREV) -% 0x780) & 0xFE;
    for (0..8) |k| {
        const kk: u32 = @intCast(k);
        r.sl(0x1530E + 6 * kk, r.l(0x1CC6A + (low << 4) + 4 * kk));
    }
    r.sl(PREV, r.l(texture.SHOWN));
}

fn swap(r: *const st.Ram, a: u32) void {
    const v = r.l(a);
    r.sl(a, r.l(a + 4));
    r.sl(a + 4, v);
}
