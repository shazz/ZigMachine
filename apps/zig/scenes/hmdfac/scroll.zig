// --------------------------------------------------------------------------
// Phase 4: the 9-glyph wave scroller over band B (the certified model's
// timing, hmdfac.zig departure 5) in the rebuilt 32x16 font (THE FONT
// BLOCKER). Art-local coordinates throughout; the caller hands the plate.
//
// The plane is cleared and band B pasted ONCE, at phase entry (enter()); a
// frame then erases only last frame's nine glyph boxes, re-pastes band B only
// if one of those boxes reached into it, and draws the new nine as runs. That
// is pixel for pixel the full clear + paste + draw the machine's $6710 did.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const GLYPHS = 9; // the walk draws a 9-column strip per frame
pub const ADV = 40; // the glyph advance in px
pub const GLYPH_W = 32;
pub const GLYPH_H = 16;
pub const INK = 4; // pal4 word 4 = $0594: the magenta the real glyphs show

const NONE: i32 = -1000; // an empty box slot

/// The boxes drawn last frame (x, y), art-local; x = NONE for none.
var last: [GLYPHS][2]i32 = undefined;

/// Glyph i's character index and position at scroller time t, or null.
pub fn place(t: usize, i: usize) ?struct { ci: usize, x: i32, y: i32 } {
    const ci = t / 10 + i;
    if (ci >= A.TEXT_LEN) return null;
    const x0: i32 = @as(i32, @intCast(i * ADV)) - @as(i32, @intCast(4 * (t % 10)));
    if (x0 <= -ADV or x0 >= A.ART_W) return null;
    var y0: i32 = @intCast(A.rows[(t + i) % A.ROWS_N]);
    const wv = A.wave[(t + i) % A.WAVE_N];
    y0 += (@as(i32, wv) - 100) >> 1;
    if (y0 < -2) y0 = -2;
    return .{ .ci = ci, .x = x0, .y = y0 };
}

/// The rebuilt 32x16 glyph: 64 B, 16 rows of 4 B, MSB = leftmost pixel,
/// glyph = char - 0x20; drawn as horizontal runs.
fn drawGlyph(d: blit.Dst, ch: u8, x: i32, y: i32) void {
    if (ch < 0x20 or ch >= 0x60) return;
    const base: usize = (@as(usize, ch) - 0x20) * GLYPH_H;
    for (0..GLYPH_H) |py| {
        const bits = A.font_rows[base + py];
        var px: u6 = 0;
        while (px < GLYPH_W) {
            if (bits & (@as(u32, 0x8000_0000) >> @intCast(px)) == 0) {
                px += 1;
                continue;
            }
            const x0 = px;
            while (px < GLYPH_W and bits & (@as(u32, 0x8000_0000) >> @intCast(px)) != 0) px += 1;
            d.fill(x + @as(i32, x0), y + @as(i32, @intCast(py)), px - x0, 1, INK);
        }
    }
}

fn pasteBandB(whole: blit.Dst) void {
    blit.blit(whole, blit.Image.init(A.band_b_data, A.ART_W), null, A.ART_X, A.ART_Y + A.BAND_B_Y, null, .copy);
}

/// Phase entry: the plane cleared to color0 and band B pasted, once.
pub fn enter(whole: blit.Dst) void {
    whole.fill(0, 0, whole.w, whole.h, 0);
    pasteBandB(whole);
    for (&last) |*b| b.* = .{ NONE, 0 };
}

/// Does a glyph box at plate row y cover a laser row (plate rows 2, 3, 196)?
fn onLaser(y: i32) bool {
    return (y <= 3 and y + GLYPH_H > 2) or (y <= 196 and y + GLYPH_H > 196);
}

/// One frame at scroller time t; true when a box drawn or erased covered a
/// laser row (the caller re-lays the stripes there).
pub fn frame(whole: blit.Dst, t: usize) bool {
    const plate = whole.window(A.ART_X, A.ART_Y, A.ART_W, A.ART_H);
    var touched_band = false;
    var lasers = false;
    for (last) |b| {
        if (b[0] == NONE) continue;
        plate.fill(b[0], b[1], GLYPH_W, GLYPH_H, 0);
        if (b[1] + GLYPH_H > A.BAND_B_Y) touched_band = true;
        if (onLaser(b[1])) lasers = true;
    }
    if (touched_band) pasteBandB(whole);
    for (0..GLYPHS) |i| {
        last[i] = .{ NONE, 0 };
        const g = place(t, i) orelse continue;
        drawGlyph(plate, A.text_data[g.ci], g.x, g.y);
        last[i] = .{ g.x, g.y };
        if (onLaser(g.y)) lasers = true;
    }
    return lasers;
}
