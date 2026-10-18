// --------------------------------------------------------------------------
// The spread scroller (screen.js draw_scroll), on the CHISEL blitter.
//
// 33 lines of the 8x6 font, line k showing the text pixel speed*ite - 320 + X at
// column X. The text is one fixed strip of 8-px glyphs, so it is laid out ONCE
// (init) as a 6-row picture and a line is the window of it at its offset: one
// keyed copy a line (two where it wraps past the text's end), instead of
// 33 x 41 tile blits through the CPU's keyed row copies. A glyph is the picture's
// pixels, colour 0 clear, so the pixels are the tile blits' (index 0 never drawn).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const texts = @import("texts.zig");

pub const FONT_W = 8; // font.initTile(8, 6, 32)
pub const FONT_H = 6;
const FONT_COLS = 10; // font.png is 80 wide
const FIRST_CHAR = 32;
const STRIP_W = texts.scroll.len * FONT_W; // the whole text, one glyph after another

var strip: []u8 = &.{};

/// Lay the text out as a STRIP_W x FONT_H picture from the font sheet `font_b` (80 wide).
/// On zg.mem, once per cart load (init runs again when the cart restarts).
pub fn init(font_b: []const u8) void {
    if (strip.len != 0) return;
    strip = zg.mem.mustAlloc(u8, STRIP_W * FONT_H);
    for (texts.scroll, 0..) |c, k| {
        const tile: usize = c - FIRST_CHAR;
        const sx = (tile % FONT_COLS) * FONT_W;
        const sy = (tile / FONT_COLS) * FONT_H;
        for (0..FONT_H) |r| {
            @memcpy(strip[r * STRIP_W + k * FONT_W ..][0..FONT_W], font_b[(sy + r) * (FONT_COLS * FONT_W) + sx ..][0..FONT_W]);
        }
    }
}

/// One line: the text pixel `first` (negative: the text has not arrived) at column 0 of
/// a `width`-wide plane, drawn at row `y`.
pub fn line(blitter: *zg.Blitter, fb: *zg.LogicalFB, width: i64, first: i64, y: u16) void {
    var dx: i64 = @max(0, -first);
    var p: usize = @intCast(@mod(@max(first, 0), STRIP_W));
    while (dx < width) {
        const w: usize = @min(@as(usize, @intCast(width - dx)), STRIP_W - p);
        blitter.blitImage(fb, @intCast(dx), @intCast(y), strip, STRIP_W, @intCast(p), 0, @intCast(w), FONT_H, 0);
        dx += @intCast(w);
        p = 0;
    }
}
