// --------------------------------------------------------------------------
// zg.Text's glyph plot, as runs.
//
// Text.render walks a glyph's bytes one at a time and steps the destination by
// 1, or by `row_step` after every index that is a positive multiple of the font
// width (`idx % font_width`: a runtime divide per pixel on rv32im). So the bytes
// fall in contiguous RUNS: indices 0..fw (fw + 1 bytes), then fw at a time, each
// run ending on the index that takes the row step. Copying run by run (a
// @memcpy, or keyed word stores) writes the same bytes at the same places with
// no divide and a store per word. Kept apart from text.zig, which imports
// ZigOS, so it tests natively (text_plot_test.zig).
// --------------------------------------------------------------------------
const rows = @import("blit_rows.zig");

/// Write `data` into `dst` from `start` as Text.render's loop did: pixels equal
/// to `key` (when given) are skipped, and the position steps by `row_step` in
/// place of 1 after each index that is a positive multiple of `fw`.
pub fn plot(dst: [*]u8, start: u32, row_step: u32, data: []const u8, fw: u16, key: ?u8) void {
    if (fw == 0) return; // the loop's modulo by zero
    var pos: u32 = start;
    var i: usize = 0;
    while (i < data.len) {
        const end = @min(data.len, if (i == 0) @as(usize, fw) + 1 else i + fw);
        const len: u32 = @intCast(end - i);
        const out = dst[pos..][0..len];
        if (key) |k| rows.row(out, data[i..end], k, rows.keyedCopy, false) else @memcpy(out, data[i..end]);
        pos += len - 1 + row_step;
        i = end;
    }
}
