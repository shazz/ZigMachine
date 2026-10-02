// --------------------------------------------------------------------------
// F6 -- SYNC: "VECTORBALLS II" (part 6: track 0 side 1, ByteKiller-packed,
// to $C000): shaded balls morphing between shapes, turning and gliding to a
// script, reflected into the lower border under the sparkling SYNC logo, a
// line of text typed below them, two raster lines sweeping through the
// borders. The music is a ProTracker module ("Wasteland", Mahoney &
// Kaktus) played as samples from Timer C.
//
// The set-up ($12872: tables, the ball routines it generates, the logo) ran
// once on the original code (the Musashi oracle) and its memory is the
// asset ($C000..$80000). Its random pick among four ball colour sets
// ($FA23, Timer C's counter) is the oracle's: the first. Each VBL from
// there ($127FE): sparkles on the logo (f6_logo.zig), and every second VBL
// ($12AEC >= 2: 25 Hz) a pass of the main loop ($12A1C): swap screens,
// erase, turn and draw the balls (f6_balls.zig), reflect them, morph and
// script (f6_morph.zig), type; the screen drawn is shown from the next VBL.
// The display (f6_screen.zig) is the Timer B chain's.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const balls = @import("f6_balls.zig");
const morph = @import("f6_morph.zig");
const logo = @import("f6_logo.zig");

pub const BASE: u32 = 0xC000;
pub const TOP: u32 = 0x80000;
const COUNT: u32 = 0x12AEC;
const RASTER: u32 = 0x127FA;

/// The screen on display: the last pass's (its `movep` to $FF8201).
var shown: u32 = 0;

pub fn enter(r: *const st.Ram) void {
    shown = r.l(balls.DRAW);
}

/// One VBL; returns the screen on display after it.
pub fn vbl(r: *const st.Ram) u32 {
    r.sw(COUNT, r.w(COUNT) + 1);
    logo.sparkle(r);
    raster(r);
    if (r.w(COUNT) >= 2) {
        r.sw(COUNT, 0);
        pass(r);
        shown = r.l(balls.DRAW);
    }
    return shown;
}

/// The raster lines' colours step on one entry a frame ($1258C, Timer B).
fn raster(r: *const st.Ram) void {
    var p = r.l(RASTER) + 2;
    if (p >= 0x12DB8) p = 0x12BD6;
    r.sl(RASTER, p);
}

/// The main loop's body ($12A1C..$12A3C).
pub fn pass(r: *const st.Ram) void {
    const a = r.l(0x12AF2);
    r.sl(0x12AF2, r.l(0x12AEE));
    r.sl(0x12AEE, a);
    balls.erase(r);
    balls.turn(r);
    balls.draw(r);
    logo.reflect(r);
    morph.morph(r);
    logo.text(r);
    morph.script(r);
}
