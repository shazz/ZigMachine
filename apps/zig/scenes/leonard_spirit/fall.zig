// --------------------------------------------------------------------------
// The scrolltext's fall (Matt, 2026-11-01): once the BOTTOM border is open
// for good, the scroller drops from the leonard cart's row (6 pixels above
// the closed screen's bottom edge, nothing below it) to the same place above
// 6 pixels above the OPEN screen's bottom edge, and bounces until it rests there.
//
// Integer physics in Q8 pixels, the whole fall a compile-time table (no
// float, no per-frame maths): gravity G a frame, each bounce keeps R/256 of
// the speed, and a bounce slower than STOP lands for good. The harness's
// model (apps/leonard_spirit_model.mjs) runs the same steps.
// --------------------------------------------------------------------------
const lay = @import("layout.zig");
const show = @import("show.zig");
const scroll = @import("scroll.zig");

pub const TOP: u32 = lay.SCROLL_Y; // the leonard cart's row 194
pub const MARGIN: u32 = 6; // Matt, 2026-11-01: 6 pixels between the letters and the open bottom
pub const LOW: u32 = lay.WIN_H - scroll.CW - MARGIN; // 268
pub const START: u32 = show.stageStart(.bottom) + show.SHAKE_LEN; // the bottom stays open from here
pub const G: i32 = 48; // 0.19 px a frame, a frame
pub const R: i32 = 128; // a bounce keeps half the speed
pub const STOP: i32 = 64; // slower than 0.25 px a frame: landed

/// The scroller's window row, frame by frame from START until it rests.
pub const ROWS = blk: {
    @setEvalBranchQuota(100_000);
    var rows: [256]u16 = undefined;
    var n: usize = 0;
    var y: i32 = TOP << 8;
    var v: i32 = 0;
    while (true) {
        v += G;
        y += v;
        if (y >= LOW << 8) {
            y = LOW << 8;
            v = -((v * R) >> 8);
            if (-v < STOP) break;
        }
        rows[n] = @intCast(y >> 8);
        n += 1;
    }
    break :blk rows[0..n].*;
};

/// The scroller's window row on show frame t.
pub fn row(t: u32) u32 {
    if (t < START) return TOP;
    const k = t - START;
    return if (k < ROWS.len) ROWS[k] else LOW;
}

comptime {
    if (LOW + scroll.CW > lay.WIN_H) @compileError("the scroller would leave the window");
}
