// --------------------------------------------------------------------------
// The 48-row scroller ($BB5C, run from the VBL): a ring 448 px wide written
// twice into 896-px rows, one 16-px font column a time, shown on 47 lines
// through the line list at (ring x + fine scroll) -- the STE hardware scroll,
// as the demo uses it. 4 px a frame; text bytes 1..8 are speed commands
// (a pair, the second one for when the text is read backwards).
// After the rewind the scroller runs BACKWARDS ($BFD0), reading the text from
// its end towards its start. The font is chunky in RAM, colours 16..31.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const data = @import("data.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");

const COL_ROWS: usize = 48;
const COL_BYTES: u16 = 0x180; // one planar column in the font
const LINES: usize = 47;

pub var on: bool = false; // $16A2E
var font: []u8 = &.{}; // 16 px x 48 rows per planar column, in font order
var text: usize = 1; // $2(a6), an index into data.scrolltext
var restart: usize = 1; // $6(a6)
pub var row: u16 = 0x64; // $A(a6): the first line
var speed: u8 = 4; // $D(a6)
var col: u16 = 0; // d0: byte offset of the column inside the character
var ring_g: u16 = 0; // d1: byte offset of the ring's left edge ($E0 wraps)
var fine: u16 = 0; // d2: hardware fine scroll
var chr: u16 = 0; // d3: character x 4
var backwards: bool = false; // $1A(a6)

const FONT_COLS: usize = data.font.len / COL_BYTES;
comptime {
    if (data.font.len % COL_BYTES != 0) @compileError("mindwind: font.bin is not whole $180-byte columns");
}

pub fn init() void {
    font = zg.mem.mustAlloc(u8, FONT_COLS * 16 * COL_ROWS);
    for (0..FONT_COLS) |c| {
        const out = font[c * 16 * COL_ROWS ..][0 .. 16 * COL_ROWS];
        vram.planarRows(data.font[c * COL_BYTES ..][0..COL_BYTES], 8, COL_ROWS, out, 16, 0);
        for (out) |*p| {
            if (p.* != 0) p.* += 16;
        }
    }
}

/// $BA90: from the end of the text, backwards, on line 210.
pub fn reverse() void {
    restart = 0xc84c - 0xc5d6; // the text's trailing spaces, read leftwards
    text = restart;
    row = 0xd2;
    speed = 4;
    col = 0x300;
    ring_g = 0;
    fine = 0;
    chr = 0;
    backwards = true;
}

fn forwardStep() void {
    fine = (fine + speed) & 15;
    if (fine != 0) return;
    ring_g += 8;
    if (ring_g == 0xe0) ring_g = 0;
    col += COL_BYTES;
    if (col != 0x480) return;
    var b = data.scrolltext[text];
    text += 1;
    if (b == 0) text = restart;
    if (b <= 8) {
        speed = b;
        text += 1;
        b = data.scrolltext[text];
        text += 1;
    }
    chr = @as(u16, b) * 4;
    col = 0;
}

fn backwardStep() void {
    const f: i16 = @as(i16, @intCast(fine)) - speed;
    if (f >= 0) {
        fine = @intCast(f);
        return;
    }
    fine = @intCast(f + 16);
    ring_g = if (ring_g < 8) 0xd8 else ring_g - 8;
    if (col >= COL_BYTES) {
        col -= COL_BYTES;
        return;
    }
    text -= 1;
    var b = data.scrolltext[text];
    if (b == 0) text = restart;
    if (b <= 8) {
        speed = b;
        text -= 2;
        b = data.scrolltext[text];
    }
    chr = @as(u16, b) * 4;
    col = 0x300;
}

/// One VBL: move, draw the current column into the ring (twice), point the 47 lines at it.
pub fn step() void {
    if (!on) return;
    if (backwards) backwardStep() else forwardStep();
    const glyph: usize = data.le16(data.font_ptrs, chr / 4) + col;
    const src = font[glyph / COL_BYTES * 16 * COL_ROWS ..][0 .. 16 * COL_ROWS];
    const x: u32 = @as(u32, ring_g) * 2; // planar bytes -> px
    for (0..COL_ROWS) |r| {
        const base = vram.ring + @as(u32, @intCast(r)) * vram.RING_W + x;
        @memcpy(vram.bytes(base + 432, 16), src[r * 16 ..][0..16]); // $D8(a1)
        @memcpy(vram.bytes(base - 16, 16), src[r * 16 ..][0..16]); // -8(a1)
    }
    for (0..LINES) |j| {
        lines.table[row + j] = .{ .src = vram.ring + @as(u32, @intCast(j)) * vram.RING_W + x + fine, .colour = 0 };
    }
}
