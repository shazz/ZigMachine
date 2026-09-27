// --------------------------------------------------------------------------
// ZIG mode's music credits on the title: a ticker in the band under the
// scaled title screen (zig_screens.zig leaves 15 lines there), in the game's
// 8x8 font, moving a pixel a frame while the title's own scroller runs
// (2005-2006). The pen is the palette's colour furthest in brightness from
// the band's, so it reads whatever the band is painted in. Overlay only:
// no game state, and ORIGINAL never shows it.
// --------------------------------------------------------------------------
const flow = @import("flow.zig");
const pal = @import("pal.zig");
const scr = @import("scr.zig");
const assets = @import("assets.zig");
const scroll = @import("zig_scroll.zig");
const screens = @import("zig_screens.zig");
const zm = @import("zig_music.zig");

const W: usize = @intCast(scroll.WIN_W);
const H: usize = @intCast(scroll.WIN_H);
const SEP = "   -   ";
const TEXT = "MUSIC FROM THE MOD ARCHIVE:   " ++ zm.CREDITS[0] ++ SEP ++ zm.CREDITS[1] ++ SEP ++ zm.CREDITS[2] ++ SEP;
const TEXT_W: usize = TEXT.len * 8;

/// The band's first line, and the ticker's (centred in it).
pub const BAND_Y: usize = screens.Y0 + screens.SH;
pub const Y: usize = if (H >= BAND_Y + 8) BAND_Y + (H - BAND_Y - 8) / 2 else 0;
comptime {
    for (TEXT) |c| if (c < 32) @compileError("the ticker's text has a control character");
}

var pos: usize = 0;
pub var shown: bool = false;

/// While the title's scroller runs, over the frame zig_screens.draw made.
pub fn draw(ov: []u8) void {
    // Checked at run time, not comptime: zig_screens.zig owns the band's
    // height, and a layout without one must not stop the cart building
    // (apps/skystrike_zig_music.mjs fails if the ticker goes missing).
    shown = (flow.pc == .l2005 or flow.pc == .l2006) and H >= BAND_Y + 8;
    if (!shown) return;
    const p = scr.get(.physic);
    if (p.len == 0) return;
    const pen = contrast(screens.mostly(p, scr.H - 1));
    pos = (pos + 1) % TEXT_W;
    for (0..W) |x| {
        const t = (pos + x) % TEXT_W;
        const c = TEXT[t / 8];
        const g = assets.FONT[@as(usize, c - 32) * 8 ..][0..8];
        const bit: u3 = @intCast(7 - t % 8);
        for (0..8) |j| {
            if (g[j] >> bit & 1 != 0) ov[(Y + j) * W + x] = pen;
        }
    }
}

fn brightness(c: u8) i32 {
    const w = pal.hw[c & 15];
    return @as(i32, w >> 8 & 7) * 3 + @as(i32, w >> 4 & 7) * 6 + @as(i32, w & 7);
}

/// The palette index furthest in brightness from colour `band`.
fn contrast(band: u8) u8 {
    const b = brightness(band);
    var best: u8 = 0;
    var far: i32 = -1;
    for (0..16) |i| {
        const d = @as(i32, @intCast(@abs(brightness(@intCast(i)) - b)));
        if (d > far) {
            far = d;
            best = @intCast(i);
        }
    }
    return best;
}
