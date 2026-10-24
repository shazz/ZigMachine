// --------------------------------------------------------------------------
// NOEXTRA's scroller letter: CODEF's FX.siny with a one-column group, drawn as
// RUNS of columns (see noextra.zig, renderScroll).
//
// zg.wave.siny blits every column of a letter on its own (32 clipped blits a
// letter, 480 a frame). The wave moves 0.001 rad a column, so neighbouring
// columns nearly always land on the same y: a run of columns with one y is one
// wider blit, and since the ink is flat (every keyed-in pixel becomes INK) and
// no two columns share a pixel, the plane gets exactly the same bytes in any
// grouping and order. Columns outside the plane are skipped without evaluating
// their sine: a column's y depends only on its own index.
//
// `blit` is zg.blit; the sine is zg.fixtrig's table (Q16.16): no float.
// --------------------------------------------------------------------------
const fixtrig = @import("zigos").fixtrig;

/// CODEF's scrollfx.siny term in integers: column j of a letter is at
/// y = trunc(mid + amp * sin(phase + j * inc)), the phases in u64 turns.
pub const Wave = struct {
    phase: u64, // the letter's column 0
    inc: u64, // per column
    mid: i32,
    amp: i32,

    fn y(w: Wave, a: u64) i32 {
        // mid + amp*sin >= mid - amp > 0: the shift is the truncation
        return ((w.mid << 16) + w.amp * fixtrig.sin(@truncate(a >> 32))) >> 16;
    }
};

/// Letter columns sx0..sx0+gw-1 of `font` (rows sy0..sy0+gh-1) at x0 + j,
/// each at y = top + wave's value for column j.
pub fn letter(comptime blit: type, dst: blit.Dst, font: blit.Image, sx0: usize, sy0: usize, gw: i32, gh: usize, x0: i32, top: i32, wave: Wave, ink: u8) void {
    const j0: i32 = @max(0, -x0);
    const j1: i32 = @min(gw, @as(i32, @intCast(dst.w)) - x0);
    if (j1 <= j0) return;
    var ph = wave.phase +% wave.inc *% @as(u64, @intCast(j0));
    var start = j0;
    var y = wave.y(ph);
    var j = j0 + 1;
    while (j <= j1) : (j += 1) {
        ph +%= wave.inc;
        const ny = if (j < j1) wave.y(ph) else y;
        if (j < j1 and ny == y) continue;
        const a: usize = @intCast(start);
        const n: usize = @intCast(j - start);
        blit.blit(dst, font, .{ .x = sx0 + a, .y = sy0, .w = n, .h = gh }, x0 + start, top + y, 0, .{ .flat = ink });
        start = j;
        y = ny;
    }
}
