// --------------------------------------------------------------------------
// ZIG mode's hall of fame and its name entry (hiscore.zig, histable.zig):
// the picture scaled to fill the open frame, the text over it 1:1, in the
// game's font at its own size, the 320 x 200 layout kept whole and centred
// (screen_x, screen_y).
//
// The two layers are kept apart as the game makes them:
//   the picture  HIPIC.PAC as it stands on the physic screen at 2260, before
//                the table is pasted on (hooks.shows(.hall));
//   the text     every character cell the game draws from then on (text.zig's
//                PRINT, via hooks.textCell): its ink in the pen, its paper in
//                the paper -- except paper 0, which the table's paste (2274,
//                a transparent SCREEN$) leaves out. The name entry's cells
//                (paper 3, the cursor's paper 15) are opaque, as drawn.
// A text pixel is shown where the physic screen holds it, so the APPEAR that
// brings the table in (2280) brings it in here too, pixel by pixel.
// Nothing here writes game state.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const text = @import("text.zig");
const screens = @import("zig_screens.zig");
const set = @import("zig_settings.zig");

pub const CLEAR: u8 = 255;
const W: usize = 400;

/// The picture, and the text (CLEAR where there is none), 320 x 200 each.
pub var pic: []u8 = &.{};
pub var layer: []u8 = &.{};

/// Once per cart load, from zg.mem.
pub fn alloc() void {
    if (pic.len == 0) pic = zg.mem.mustAlloc(u8, scr.PIX);
    if (layer.len == 0) layer = zg.mem.mustAlloc(u8, scr.PIX);
}

/// hooks.shows(.hall): the physic screen is the bare picture.
pub fn shown() void {
    const p = scr.get(.physic);
    if (pic.len == 0 or p.len == 0) return;
    @memcpy(pic, p);
    @memset(layer, CLEAR);
}

/// Cell col, row as text.zig draws it now (pen, paper, UNDER).
pub fn cell(c: u8, col: i32, row: i32) void {
    if (layer.len == 0) return;
    const paper: u8 = if (text.paper == 0) CLEAR else text.paper;
    for (0..8) |j| {
        const bits = text.cellBits(c, j);
        const o: usize = @intCast((row * 8 + @as(i32, @intCast(j))) * 320 + col * 8);
        for (0..8) |i| layer[o + i] = if (bits >> @intCast(7 - i) & 1 != 0) text.pen else paper;
    }
}

pub fn draw(ov: []u8) void {
    if (pic.len == 0) return;
    screens.scaled(ov, pic);
    const p = scr.get(.physic);
    for (0..scr.H) |y| {
        const to = ov[(set.screen_y + y) * W + set.screen_x ..][0..scr.W];
        for (0..scr.W) |x| {
            const t = layer[y * scr.W + x];
            if (t != CLEAR and p[y * scr.W + x] == t) to[x] = t;
        }
    }
}
