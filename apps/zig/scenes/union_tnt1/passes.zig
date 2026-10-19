// --------------------------------------------------------------------------
// TNT1's two ball passes (union_tnt1.zig): blue on the main canvas, then red
// landing 'source-atop' on the canvas that holds only the logo and the
// scroller. As palette work, the atop canvas's opaque pixels are exactly the ink
// and the red tiles' entries, so pass 1 draws blue only OUTSIDE that set and
// pass 2 draws red only INSIDE it (blit's .select ink), later balls on top.
//
// Board cost: the CPU's select loop stores each pixel (a blocking DDR write,
// ~27 cycles). Every pixel of that set lies in the logo's rectangle or the
// scroller's rows (the red tiles land only on ink), so a tile clear of both
// meets none of it: in pass 1 it is a plain keyed tile, which CHISEL cuts at
// ~2 clocks a pixel; in pass 2 it draws nothing at all.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const INK: u8 = 2;
pub const RED_FIRST: u8 = 11;
pub const RED_LAST: u8 = 17;
pub const LOGO_W = 78; // logo.png 156x80
pub const LOGO_H = 40;
pub const LOGO_X = 112; // logo.draw(maincanvas, 224, 8)
pub const LOGO_Y = 4;
pub const SCROLL_Y = 192; // scrollcanvas.draw(ballcanvas, 0, 384)
pub const SHEET_W = 272; // balls.png 544x32, initTile(32,32): 17 tiles
pub const TILE = 16;
pub const MAX_BALLS = 550;

/// The ballcanvas pixels 'source-atop' keeps: logo and scroller ink, red balls.
const atop_canvas: [256]bool = blk: {
    var s = [_]bool{false} ** 256;
    s[INK] = true;
    for (RED_FIRST..RED_LAST + 1) |i| s[i] = true;
    break :blk s;
};

/// One drawn tile, already on the ST grid.
pub const Spot = struct { x: i16, y: i16, tile: u8 };
pub const Pass = struct { spots: [MAX_BALLS]Spot, n: usize };

/// Does the tile at `s` reach the logo's rectangle or the scroller's rows?
fn nearAtop(s: Spot) bool {
    const in_logo = s.x < LOGO_X + LOGO_W and s.x + TILE > LOGO_X and s.y < LOGO_Y + LOGO_H and s.y + TILE > LOGO_Y;
    return in_logo or s.y + TILE > SCROLL_Y;
}

fn part(s: Spot) blit.Rect {
    return .{ .x = @as(usize, s.tile) * TILE, .y = 0, .w = TILE, .h = TILE };
}

/// Pass 1: blue only OUTSIDE the atop set.
pub fn drawBlue(blitter: *zg.Blitter, fb: *zg.LogicalFB, dst: blit.Dst, pass: *const Pass, sheet: blit.Image) void {
    const ink = blit.Ink{ .select = .{ .set = &atop_canvas, .inside = false } };
    for (pass.spots[0..pass.n]) |s| {
        if (nearAtop(s)) blit.blit(dst, sheet, part(s), s.x, s.y, 0, ink) else blitter.blitImage(fb, s.x, s.y, sheet.data, SHEET_W, @as(u16, s.tile) * TILE, 0, TILE, TILE, 0);
    }
}

/// Pass 2: red only INSIDE the atop set, so only near it.
pub fn drawRed(dst: blit.Dst, pass: *const Pass, sheet: blit.Image) void {
    const ink = blit.Ink{ .select = .{ .set = &atop_canvas, .inside = true } };
    for (pass.spots[0..pass.n]) |s| if (nearAtop(s)) blit.blit(dst, sheet, part(s), s.x, s.y, 0, ink);
}
