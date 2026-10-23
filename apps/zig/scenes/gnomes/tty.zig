// --------------------------------------------------------------------------
// The cyan TTY panel: the message typed one action a frame (a character, a CR
// or an LF), exactly as the dis drives it, then a 250-frame pause, a wipe, and
// again. update() steps it; render() draws at most one 8x8 glyph.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const text = @import("text.zig");
const draw = @import("draw.zig");

pub const STRIP_X = 0;
pub const STRIP_Y = 80;
const STRIP_W = 176;
const STRIP_COLS = 22; // 176 / 8
const STRIP_ROWS = 14; // the original's 117-row clear, rows of 8

pub var ptr: usize = 0;
pub var col: u8 = 0;
pub var row: u8 = 0;
pub var pause: u16 = 0; // 0 = no pause pending
var to_draw: u8 = 0xFF; // the character render() draws this frame (0xFF = none)
var wipe: bool = false; // render() wipes the strip panel this frame

pub fn reset() void {
    ptr = 0;
    col = 0;
    row = 0;
    pause = 0;
    to_draw = 0xFF;
    wipe = false;
}

fn nextRow() void {
    row += 1;
    if (row >= STRIP_ROWS) row = STRIP_ROWS - 1;
}

pub fn step() void {
    to_draw = 0xFF;
    wipe = false;
    if (pause > 0) {
        pause -= 1;
        if (pause == 0) {
            wipe = true;
            col = 0;
            row = 0;
            ptr = 0;
        }
        return;
    }
    const ch = text.CYAN_TEXT[ptr];
    ptr += 1;
    switch (ch) {
        '\r' => col = 0,
        '\n' => nextRow(),
        else => to_draw = ch, // drawn and column-advanced in render()
    }
    if (ptr >= text.CYAN_TEXT.len) pause = text.TTY_PAUSE;
}

pub fn render(whole: blit.Dst, ink: u8) void {
    const strip = whole.window(STRIP_X, STRIP_Y, STRIP_W, STRIP_ROWS * 8);
    if (wipe) strip.fill(0, 0, strip.w, strip.h, 0);
    if (to_draw == 0xFF) return;
    blit.blit(strip, draw.font_img, draw.glyphRect(to_draw), @as(i32, col) * 8, @as(i32, row) * 8, 0, .{ .flat = ink });
    col += 1;
    if (col >= STRIP_COLS) {
        col = 0;
        nextRow();
    }
}
