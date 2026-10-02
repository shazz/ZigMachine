// --------------------------------------------------------------------------
// F2 -- OMEGA: "Liesen dist" logo, "HAQ scroll", Red's logos (part 2: track
// 11 side 1, ByteKiller-packed, to $1000). Its set-up ($1174) depacks two
// blobs with its own unpacker ($6852), preshifts the logo 16 times and the
// font 4 times, and builds tables: that ran once on the original 68000 code
// (prototypes/snyd90_re/m68run, a Musashi oracle that reproduces Hatari's RAM
// of the running part) and the memory it leaves is this part's asset. Every
// VBL from there is ported here, on that memory ($1600):
//   flip      the drawn screen $70000 <-> $78000 (shown from the next VBL)
//   colour 0  black
//   logo      f2_logo.zig (with the music's play call first: the SNDH's job)
//   scroller  f2_scroll.zig
// What the shifter shows during a VBL is the screen the previous VBL drew,
// under the palette this VBL's script leaves (it runs before the display
// starts); the scroller's clear touches that screen only after the beam has
// passed it. So a frame is captured between the logo and the scroller.
// Space (released: $B9) returns to the menu ($6828).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const logo = @import("f2_logo.zig");
const scroll = @import("f2_scroll.zig");

pub const BASE: u32 = 0x1000;
pub const TOP: u32 = 0x80000;
/// The palette its set-up leaves ($6908).
pub const PALETTE: u32 = 0x6908;

/// The first half of a VBL: returns the screen on display during it.
pub fn top(r: *const st.Ram, pal: *[16]u16) u32 {
    const d = r.l(logo.DRAW) ^ 0x8000;
    r.sl(logo.DRAW, d);
    pal[0] = 0;
    logo.frame(r, pal);
    return d ^ 0x8000;
}

/// The second half: the scroller.
pub fn bottom(r: *const st.Ram) void {
    scroll.frame(r);
}
