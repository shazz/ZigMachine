// --------------------------------------------------------------------------
// CUDDLY STARWARS — the starwars text canvas: print() of 30 lines of 17x11 glyphs,
// read back by the perspective (starwars.zig).
//
// The canvas holds PAIR CODES, not pixels: byte c + 1 of a row is
// ink(c) | ink(c + 1) << 1 for source column c = -1..319 (ink off the canvas is 0).
// One byte load per row then gives both taps of the bilinear sample with no bounds
// tests (the perspective samples xi = -1..319, starwars.zig checks it).
//
// The text is laid out once per starwars line (every PITCH_Y frames); between those,
// the 1-row-a-frame scroll only moves the view's first row on the canvas.
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const tables = @import("tables.zig");
const motion = @import("motion.zig");
const assert = std.debug.assert;

const W: usize = zg.WIDTH;
const swfont_b = @embedFile("../../assets/screens/cuddly_starwars/swfont.raw");

const GLYPH_W: usize = 17;
const GLYPH_H: usize = 11;
const FONT_W: usize = 170;
const FONT_H: usize = 69;
const COLS: usize = 10;
pub const LINES: usize = 30;
const PITCH_X: usize = 20;
pub const PITCH_Y: i32 = 17;
const LINE_CHARS: usize = 12;
const X0: usize = (300 - LINE_CHARS * 16) / 2 - 8; // letterpos = 46
const FIRST_CHAR: u8 = 32;
pub const STRIDE: usize = W + 4; // pair codes for c = -1..319 at 0..320, padded to a word

comptime {
    @setEvalBranchQuota(100_000);
    assert(swfont_b.len == FONT_W * FONT_H);
    for (tables.starwars_lines) |line| {
        // letterpos is only the integer 46 for full lines; empty lines draw nothing
        assert(line.len == 0 or line.len == LINE_CHARS);
        for (line) |c| assert(c >= FIRST_CHAR and (c - FIRST_CHAR) / COLS * GLYPH_H + GLYPH_H <= FONT_H);
    }
    assert(X0 + (LINE_CHARS - 1) * PITCH_X + GLYPH_W <= W);
}

// The view's rows TEXT_ROWS plus the scroll within a line (up to PITCH_Y - 1) reach into
// SLOTS line slots. Line g of the text lives in slot g % SLOTS of a RING of rows, so a
// new sw_line moves the ring's base and redraws only the slot whose line changed (the
// old code relaid the whole canvas: ~0.9 Mc in that one frame).
const SLOTS: usize = (motion.TEXT_ROWS - 1 + @as(usize, @intCast(PITCH_Y)) - 1) / @as(usize, @intCast(PITCH_Y)) + 1;
const RING: usize = SLOTS * @as(usize, @intCast(PITCH_Y));
comptime {
    assert(SLOTS <= LINES); // the slots hold lines the original prints
    assert(GLYPH_H <= @as(usize, @intCast(PITCH_Y))); // a line stays inside its slot
}
var pairs: *[RING * STRIDE]u8 = undefined;
var base: usize = 0; // the ring row of view row 0
var text_laid: usize = std.math.maxInt(usize); // the sw_line the ring holds (none yet)
var slot_text: [SLOTS]?[]const u8 = undefined; // the line each slot holds (null: none)
// Leftmost and rightmost inked column of each ring row; an empty row has left > right.
var row_left: [RING]u16 = undefined;
var row_right: [RING]u16 = undefined;

pub fn init() void {
    pairs = zg.mem.mustAlloc(u8, RING * STRIDE)[0 .. RING * STRIDE];
    @memset(pairs, 0);
    @memset(&row_left, W);
    @memset(&row_right, 0);
    @memset(&slot_text, null);
    text_laid = std.math.maxInt(usize);
}

/// The ring row of view row `row` (0 .. TEXT_ROWS - 1).
inline fn ringRow(row: i32) usize {
    const t = base + @as(usize, @intCast(row));
    return if (t >= RING) t - RING else t;
}

/// The pair codes of view row `row` (0 .. TEXT_ROWS - 1). A row with no ink is all 0.
pub fn codes(row: i32) *const [STRIDE]u8 {
    return pairs[ringRow(row) * STRIDE ..][0..STRIDE];
}

/// print() of the starwars text from line sw_line, scrolled up sw_offset rows (0..-16).
pub fn layout(sw_line: usize, sw_offset: i32) void {
    const pitch: usize = @intCast(PITCH_Y);
    base = ((sw_line % SLOTS) * pitch + @as(usize, @intCast(-sw_offset))) % RING;
    if (text_laid == sw_line) return;
    text_laid = sw_line;
    for (0..SLOTS) |j| {
        const g = sw_line + j;
        const slot = g % SLOTS;
        const line = tables.starwars_lines[g];
        if (slot_text[slot]) |held| {
            if (sameText(held, line)) continue; // same text, same pixels
        }
        clearSlot(slot);
        for (line, 0..) |c, i| blitGlyph(c - FIRST_CHAR, X0 + i * PITCH_X, slot * pitch);
        slot_text[slot] = line;
    }
}

/// The same line of the table, or both empty (most of the text's padding). Not
/// std.mem.eql: it compares words, and a string's address in the data segment is
/// any byte, so those loads would trap on the board.
fn sameText(a: []const u8, b: []const u8) bool {
    return a.len == b.len and (a.len == 0 or a.ptr == b.ptr);
}

/// Zero the codes the slot's rows hold: columns left - 1 .. right of each row.
fn clearSlot(slot: usize) void {
    const pitch: usize = @intCast(PITCH_Y);
    for (slot * pitch..(slot + 1) * pitch) |r| {
        if (row_left[r] <= row_right[r]) {
            @memset(pairs[r * STRIDE + row_left[r] ..][0 .. row_right[r] - row_left[r] + 2], 0);
        }
        row_left[r] = W;
        row_right[r] = 0;
    }
}

fn blitGlyph(nb: usize, x: usize, top: usize) void {
    const tx = (nb % COLS) * GLYPH_W;
    const ty = (nb / COLS) * GLYPH_H;
    for (0..GLYPH_H) |r| {
        const row = top + r;
        const src = swfont_b[(ty + r) * FONT_W + tx ..][0..GLYPH_W];
        const dst = pairs[row * STRIDE + x ..][0 .. GLYPH_W + 1]; // codes of c = x - 1 .. x + 16
        for (src, 0..) |s, c| {
            if (s == 0) continue;
            dst[c] |= 2; // ink(x + c) is the right tap of column x + c - 1 ...
            dst[c + 1] |= 1; // ... and the left tap of column x + c
            const col: u16 = @intCast(x + c);
            row_left[row] = @min(row_left[row], col);
            row_right[row] = @max(row_right[row], col);
        }
    }
}

pub fn rowInked(row: i32) bool {
    if (row < 0 or row >= motion.TEXT_ROWS) return false;
    const t = ringRow(row);
    return row_left[t] <= row_right[t];
}

/// The inked columns of the bilinear pair `row`, `row + 1`, inclusive.
/// At least one of the two rows must be inked.
pub fn inkSpan(row: i32) struct { left: i32, right: i32 } {
    var left: i32 = W;
    var right: i32 = -1;
    for ([_]i32{ row, row + 1 }) |r| {
        if (!rowInked(r)) continue;
        left = @min(left, row_left[ringRow(r)]);
        right = @max(right, row_right[ringRow(r)]);
    }
    return .{ .left = left, .right = right };
}
