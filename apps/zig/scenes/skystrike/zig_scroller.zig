// --------------------------------------------------------------------------
// ZIG mode's bottom border under the title-style screen (zig_intro.zig), and
// in it, while the title runs, its credits scroller: the full 400 columns
// wide, in the game's 8X8 font, in white (scroller_rgb), at scroller_y.
//
// The scroller is the original's (2005-2006, title.zig), only drawn
// elsewhere. The original writes the next letter of mes$ every 24 passes at
// 30,5 (x 240) and moves the zone 80-255 one pixel left every 3 passes, the
// letter just written moving in the same pass. So what the zone shows is a
// function of the pass counter ti and of mes$ (rotated once a letter): the
// letter k (1, 2, ...) stands at 240 - (ti / 3 - 8k + 1). Here the same
// letters stand 153 px further right, so each one comes in at the frame's
// right edge (392-399) and goes on to its left edge. Nothing is kept from
// frame to frame: the picture is the game's state, drawn.
// --------------------------------------------------------------------------
const flow = @import("flow.zig");
const pal = @import("pal.zig");
const text = @import("text.zig");
const set = @import("zig_settings.zig");
const V = @import("vars.zig");
const v = &V.v;

const W: usize = 400;
/// The overlay palette's index for the scroller's colour (zig_view.zig).
pub const INK: u8 = 16;
/// The original's cadence: a letter (and a rotation of mes$) every 24 passes.
const PASSES_PER_LETTER: i32 = 24;
/// The column a letter is written at, the frame's last 8.
const RIGHT: i32 = @as(i32, W) - 8 + 1;

comptime {
    if (set.scroller_y < set.screen_y + 200) @compileError("the scroller must be in the bottom border");
    if (set.scroller_y + 8 > 280 - set.hud_bottom_margin) @compileError("the scroller must clear the monitor's frame");
}

/// The title's scroller loop is running (2005-2006).
pub fn running() bool {
    return flow.pc == .l2005 or flow.pc == .l2006;
}

/// The scroller's colour as an ST word, faded with the screen: no channel
/// brighter than the brightest in the colour registers now (a STOS fade
/// moves every channel one step a time, so a white would stand there).
pub fn ink() u16 {
    var top: u16 = 0;
    for (pal.hw) |c| top = @max(top, @max(c >> 8 & 7, @max(c >> 4 & 7, c & 7)));
    const want: u16 = set.scroller_rgb;
    const r: u16 = @min(want >> 8 & 7, top);
    const g: u16 = @min(want >> 4 & 7, top);
    const b: u16 = @min(want & 7, top);
    return r << 8 | g << 4 | b;
}

/// The bottom border (lines `y0` to the frame's end) in `band`, the
/// scroller over it while the title's loop counts. Not at 2005: ti is only
/// zeroed once the mouse key is up, so while it is held (a click that left
/// the hall of fame) ti is still the last loop's, and the zone the ST shows
/// is the scene's, no letter in it yet.
pub fn draw(ov: []u8, y0: usize, band: u8) void {
    @memset(ov[y0 * W ..], band);
    if (flow.pc == .l2006) letters(ov[set.scroller_y * W ..][0 .. 8 * W]);
}

fn letters(rows: []u8) void {
    const m = v.mes_s.get();
    if (m.len == 0 or v.ti < 0) return;
    const len: i32 = @intCast(m.len);
    const step = set.scroller_passes_per_px;
    const px = @divFloor(v.ti, step);
    const n = @divFloor(v.ti, 8 * step);
    const turns = @divFloor(v.ti, PASSES_PER_LETTER);
    var k: i32 = @max(1, n - @as(i32, W / 8) - 2);
    while (k <= n) : (k += 1) {
        const c = m[@intCast(@mod(k - 1 - turns, len))];
        letter(rows, c, RIGHT - (px - 8 * k + 1));
    }
}

/// One glyph's ink pixels at column x; its paper is left as the band.
fn letter(rows: []u8, c: u8, x: i32) void {
    if (x <= -8 or x >= W) return;
    const g = text.glyph(c);
    for (0..8) |j| {
        for (0..8) |i| {
            const tx = x + @as(i32, @intCast(i));
            if (tx < 0 or tx >= W) continue;
            if (g[j] >> @intCast(7 - i) & 1 != 0) rows[j * W + @as(usize, @intCast(tx))] = INK;
        }
    }
}
