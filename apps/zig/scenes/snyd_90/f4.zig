// --------------------------------------------------------------------------
// F4 -- THE CAREBEARS (part 4: track 29 side 0, stored, a PRG at $7FE4;
// code by An Cool, music by Mad Max): the TCB letters in red blocks drifting
// over three layers of stars, a ring of white balls, and a magenta scroller
// distorted along its columns below line 183.
//
// The set-up ($F130..$F1A6: tables, the scroller's generated code, the ball
// animation) ran once on the original code (the Musashi oracle) and its
// memory is the asset ($7000..$80000). Then, each VBL:
//   VBL    $F2BE: swap the screens ($70000 / $78000: the one drawn is shown
//          next), their line tables and star lists; colours 4..15 red;
//          Timer B at line 183 ($F39E: colours 4..11 magenta)
//   loop   $F1B8: clear the balls (f4_bobs.zig), the stars (f4_stars.zig)
//          and the letters (f4_logo.zig) this screen showed, move and draw
//          them again, then the scroller (f4_scroll.zig).
// Best effort: on the ST about one pass in six overruns its frame, and the
// VBL then swaps screens and lists in the middle of it (frames drop, a few
// stars or balls are left behind for a frame). Here every VBL runs one whole
// pass: the same motion, without the dropped frames.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const stars = @import("f4_stars.zig");
const logo = @import("f4_logo.zig");
const bobs = @import("f4_bobs.zig");
const scroll = @import("f4_scroll.zig");

pub const BASE: u32 = 0x7000;
pub const TOP: u32 = 0x80000;
/// Timer B's line: from here colours 4..11 are magenta.
pub const SCROLL_LINE: usize = 183;

/// One VBL; returns the screen it drew, shown from the next.
pub fn vbl(r: *const st.Ram) u32 {
    handler(r);
    pass(r);
    return r.l(logo.SHOWN);
}

/// $F2BE (the music, $17FC8, is the SNDH's).
fn handler(r: *const st.Ram) void {
    r.sw(0xF3C0, r.w(0xF3C0) ^ 1);
    for ([_]u32{ 0xF3E2, 0xF3DA, 0xF3C2, 0xF3CA, 0xF3D2 }) |a| {
        const v = r.l(a);
        r.sl(a, r.l(a + 4));
        r.sl(a + 4, v);
    }
}

/// The main loop's body ($F1B8..$F26C).
pub fn pass(r: *const st.Ram) void {
    bobs.clear(r);
    stars.drift(r);
    stars.clear(r);
    stars.move(r);
    logo.clear(r);
    logo.move(r);
    logo.draw(r);
    bobs.place(r);
    bobs.draw(r);
    scroll.frame(r, r.l(logo.SHOWN));
}

/// The colour registers on line y: the part's palette ($F3EA, colour 0
/// black), 4..15 red from the VBL, 4..11 magenta from line 183.
pub fn colours(r: *const st.Ram, y: usize) [16]u16 {
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = r.w(0xF3EA + 2 * @as(u32, @intCast(i)));
    pal[0] = 0;
    const lo: u16 = if (y >= SCROLL_LINE) 0x707 else 0x700;
    const mid: u16 = if (y >= SCROLL_LINE) 0x505 else 0x500;
    for (4..8) |i| pal[i] = lo;
    for (8..12) |i| pal[i] = mid;
    for (12..16) |i| pal[i] = 0x300;
    return pal;
}
