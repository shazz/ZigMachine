// --------------------------------------------------------------------------
// grodan_kvack ZIG mode -- the green layer on its own HARDWARE-SCROLLED plane.
//
// An overscan scroll plane (setOverscanScrollPlane) 720 x 480: the 320 x 200
// green tile repeated so that a 400 x 280 window at any pan (0..319, 0..199)
// lies inside it.  It is drawn ONCE (row copies of the chunky tile, at the
// first Z press) and never touched again: every frame moves it
// with two registers only, FB_BASE for the row (setScroll) and HSCROLL for
// the column (setScrollFine, re-read per line in overscan mode since 1.10.0).
// The pan is the original's own green motion (moveX/moveY), taken modulo the
// tile, so the line-art moves exactly as the plain mode's does.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const model = @import("model.zig");
const L = @import("zig_layers.zig");

pub const BUF_W: u16 = A.BG_W + zg.PHYSICAL_WIDTH; // 720
pub const BUF_H: u16 = 200 + zg.PHYSICAL_HEIGHT; // 480: the tile's period is 200 rows

/// The pan the last frame set, for the harness (testapi).
pub var pan_x: u32 = 0;
pub var pan_y: u32 = 0;
/// How many times the plane was drawn (the harness pins it at 1).
pub var draws: u32 = 0;

/// Make `fb` the 720 x 480 overscan scroll plane and tile the green art into it,
/// a row copy at a time (once: ~86 K words).  Not CHISEL: a blit's destination is
/// clipped to the 280-row overscan window, and this buffer is 480 rows tall.
pub fn build(fb: *zg.LogicalFB, green: []const u8) void {
    fb.setOverscanScrollPlane(BUF_W, BUF_H);
    for (0..BUF_H) |y| {
        const row = fb.fb[y * BUF_W ..][0..BUF_W];
        const ty = y % 200;
        if (ty >= A.BG_H) continue; // the period's blank row (cleared by setOverscanScrollPlane)
        const src = green[ty * A.BG_W ..][0..A.BG_W];
        var x: usize = 0;
        while (x < BUF_W) : (x += A.BG_W) {
            const n = @min(A.BG_W, BUF_W - x);
            @memcpy(row[x..][0..n], src[0..n]);
        }
    }
    draws += 1;
}

/// The original puts tile pixel (wx - 40 - moveX/2, wy - 40 - moveY/2) at
/// window pixel (wx, wy): pan the window to that pixel of the repeated tile.
pub fn pan(fb: *zg.LogicalFB, st: *const model.State) void {
    pan_x = @intCast(@mod(-L.OX - @divFloor(st.moveX, 2), A.BG_W));
    pan_y = @intCast(@mod(-L.OY - @divFloor(st.moveY, 2), 200));
    fb.setScroll(0, pan_y);
    fb.setScrollFine(@intCast(pan_x));
}
