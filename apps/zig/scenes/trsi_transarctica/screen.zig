// --------------------------------------------------------------------------
// The Falcon screen, laid out in one overscan scroll plane.
//
// The original runs 320x240 at 8 bpp: VsetMode 8 bpp / 40 columns, then
// VDB -= 60 and VDE += 20 half-lines open the RGB display to 240 lines. Here
// those 240 lines are physical rows 20..259 of the 280-line frame (centred),
// x 40..359 (side borders closed), and the top and bottom borders are opened
// with the resolution flicker, as MAXI does it.
//
// Screen memory is a buffer of 400 x 340: Falcon screen line m is buffer row
// TOP + m, at x LEFT. The logo slide moves the screen BASE, 320 bytes a VBL,
// exactly as $3C6 does, so here it is the plane's own base register
// (setScroll): with base line s, physical row y shows buffer row s + y, i.e.
// display line d = y - TOP is screen line s + d. The open bands show screen
// lines s-20..s-1 and s+240..s+259: nothing is drawn there (the logo is at
// 65..166, and the text at 162..297 only appears once s = 60), so they are
// colour 0, which is also what the Falcon paints its border with.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const assets = @import("assets.zig");
const intro = @import("intro.zig");

pub const BUF_W: u16 = zg.PHYSICAL_WIDTH; // 400
pub const TOP = (zg.PHYSICAL_HEIGHT - DISPLAY_H) / 2; // 20
pub const LEFT = (zg.PHYSICAL_WIDTH - assets.W) / 2; // 40
pub const DISPLAY_H = 240;

pub const LOGO_LINE = 65; // $3AC: screen + $5140
pub const TEXT_DISPLAY_LINE = 102; // the window, after the slide
pub const TEXT_LINE = TEXT_DISPLAY_LINE + intro.SLIDE_LINES; // screen + $CA80, 162
pub const MEM_LINES = TEXT_LINE + assets.BG_H; // 298: the lowest line anything is drawn on
pub const BUF_H: u16 = intro.SLIDE_LINES + zg.PHYSICAL_HEIGHT; // 340

comptime {
    // renderPlaneOverscan reads rows base .. base+279, 400 wide, and the
    // base never passes SLIDE_LINES: the window stays inside the buffer.
    if (intro.SLIDE_LINES + zg.PHYSICAL_HEIGHT > BUF_H) @compileError("the slid window leaves the buffer");
    if (TOP + MEM_LINES > BUF_H) @compileError("the text window leaves the buffer");
    // The logo (screen lines 65..166) is inside the display before the slide,
    // and the text window (162..297) inside it after.
    if (LOGO_LINE + assets.LOGO_H > DISPLAY_H) @compileError("the logo runs below the display");
    if (MEM_LINES > intro.SLIDE_LINES + DISPLAY_H) @compileError("the text runs below the display");
    if (LOGO_LINE < intro.SLIDE_LINES) @compileError("the logo would reach the top band");
}

pub fn line(buf: [*]u8, m: usize) [*]u8 {
    return buf + (TOP + m) * BUF_W + LEFT;
}

/// $3AC: the logo's 102 lines to screen line 65 (planes 0-4 only, so the
/// indices are 0..31 and the pixels under them are overwritten).
pub fn drawLogo(buf: [*]u8) void {
    for (0..assets.LOGO_H) |y| {
        @memcpy(line(buf, LOGO_LINE + y)[0..assets.W], assets.logo[y * assets.W ..][0..assets.W]);
    }
}

/// A Falcon palette long (RRRRRRxx GGGGGGxx 00 BBBBBBxx) as the machine's
/// RGBA: each 6-bit channel c becomes c<<2 | c>>4, the full 0..255 range.
pub fn rgba(v: u32) u32 {
    const r = ch(v >> 24);
    const g = ch(v >> 16);
    const b = ch(v);
    return 0xFF00_0000 | b << 16 | g << 8 | r;
}
fn ch(x: u32) u32 {
    const c = x & 0xFC;
    return c | c >> 6;
}
