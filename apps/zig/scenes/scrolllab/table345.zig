const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

// --------------------------------------------------------------------------
// Mode 10: CODEF screen 345's own table (screen.js:203-245, precalc_scroll_x).
//
// Not a formula — a PLAYLIST. Segments of different character are concatenated
// into one table and read at (frame + row) % len, so the distortion CHANGES
// CHARACTER as the frame counter walks through it: a gentle double sine, then a
// 5-entry buzz, then a wide slow swing, and round again. No single-formula mode
// can do that however it is tuned. Amplitudes are canvas pixels, halved for ST;
// the step angles are per ENTRY and are unchanged.
//
// The fourth block of the original REWRITES entries 0..388 with segment A's own
// formula and constants — the same values that are already there. Every other
// appending block indexes `scroll_x_mod + i`; that one alone indexes a bare `i`,
// exactly as the first block legitimately does. It is a copy-paste leftover, and
// a genuine no-op: reproducing it would change nothing, so it is recorded here
// and not run. The table below is what 345 actually ends up with: 802 entries.
const Segment = struct { count: usize, amp: f64, step: f64, amp2: f64 = 0, step2: f64 = 0 };
const DEG = 3.141592653589793 / 180.0;
const SEGMENTS = [_]Segment{
    .{ .count = 389, .amp = 10, .step = 7 * DEG, .amp2 = 15, .step2 = 3 * DEG }, // the double sine
    .{ .count = 120, .amp = 2, .step = 72 * DEG }, // period 5: the shake
    .{ .count = 68, .amp = 20, .step = 8 * DEG }, // the big slow swing
    // (here the original rewrites segment A over itself: a no-op, see above)
    .{ .count = 36, .amp = 2, .step = 72 * DEG }, // the shake again, briefly
    .{ .count = 189, .amp = 15, .step = 8 * DEG }, // a long swing home
};
const TABLE_LEN = 802; // 389 + 120 + 68 + 36 + 189
var table: [TABLE_LEN]i16 = undefined;

pub fn buildTable() void {
    var at: usize = 0;
    for (SEGMENTS) |seg| {
        for (0..seg.count) |i| {
            const f: f64 = @floatFromInt(i);
            table[at] = @intFromFloat(@round(seg.amp * @sin(f * seg.step) + seg.amp2 * @cos(f * seg.step2)));
            at += 1;
        }
    }
}

/// 345 copies its band out in 2-pixel row slices because its canvas is doubled;
/// ours is native, so ROW_SLICE = 1 is the faithful equivalent.
const ROW_SLICE = 1;

pub fn draw(dst: blit.Dst, src: blit.Image, posy: i32, frame: u32) void {
    var j: usize = 0;
    while (j < src.h) : (j += ROW_SLICE) {
        const shift = table[(frame + j) % TABLE_LEN];
        const cell = blit.Rect{ .x = 0, .y = j, .w = src.w, .h = ROW_SLICE };
        blit.blit(dst, src, cell, shift, posy + @as(i32, @intCast(j)), 0, .copy);
    }
}
