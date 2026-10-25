// --------------------------------------------------------------------------
// The TTY panel ($13BB4): the 13 pages of assets.TTY typed one action a frame
// (a character, a CR or an LF) in the 8x8 font at plane 0, so the ink is
// colour 1 and takes the per-line raster ramp (lines 80..207, the 128-word hue
// wheel at $144A0). A 0 byte ends a page: 250 frames of nothing, then the two
// frames that clear the 176x120 panel (one per screen buffer: here the first
// does it); a second 0 ends the list and the pointer goes back to page 1.
// step() advances it; render() draws at most one glyph or one clear.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const PANEL_X = 0;
pub const PANEL_Y = 80; // ST line of text row 10, the first
const PANEL_W = 176; // 11 words of plane 0
const PANEL_H = 120;
const ROW0 = 10;
pub const PAUSE = 250; // $13C50: move.w #$fa

pub var ptr: usize = 0;
pub var col: u16 = 0;
pub var row: u16 = ROW0;
pub var pause: u16 = 0;
pub var page: u16 = 0; // the page being typed, 0..12 (testapi)
const Glyph = struct { ch: u8, col: u16, row: u16 };
var to_draw: ?Glyph = null;
var wipe = false;

const font = blit.Image.init(A.font8, 8);

pub fn reset() void {
    ptr = 0;
    col = 0;
    row = ROW0;
    pause = 0;
    page = 0;
    to_draw = null;
    wipe = false;
}

pub fn step() void {
    to_draw = null;
    wipe = false;
    if (pause != 0) {
        pause -= 1;
        if (pause < 2) { // $13BC8: the two clearing frames
            wipe = pause == 1;
            col = 0;
            row = ROW0;
            if (A.TTY[ptr] == 0) {
                ptr = 0;
                page = 0;
            }
        }
        return;
    }
    const ch = A.TTY[ptr];
    ptr += 1;
    switch (ch) {
        0 => {
            pause = PAUSE;
            page += 1;
        },
        '\r' => col = 0,
        '\n' => row += 1,
        else => {
            to_draw = .{ .ch = ch, .col = col, .row = row };
            col += 1;
        },
    }
}

pub fn render(d: blit.Dst) void {
    const screen = d.window(A.X0, A.Y0, 320, A.LINES);
    if (wipe) screen.fill(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, A.C0);
    const g = to_draw orelse return;
    // The original writes the whole plane-0 byte: ink 1, paper 0, opaque.
    blit.blit(screen, font, .{ .x = 0, .y = @as(usize, g.ch) * 8, .w = 8, .h = 8 }, @as(i32, g.col) * 8, @as(i32, g.row) * 8, null, .copy);
}
