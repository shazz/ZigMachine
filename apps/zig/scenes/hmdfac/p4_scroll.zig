// --------------------------------------------------------------------------
// Phase 4's wave scroller, as the original draws it (RAM at load base $aa9a):
//   * the font ($148e2, font_machine.bin) is 32x16, one plane, a glyph = its
//     LEFT 16 columns as 16 big-endian words, then its right 16; charmap.bin
//     ($144a8) maps a text byte to a glyph;
//   * four pre-shifted 1-plane SLABS ($15562 + k * $540: 16 rows of 42 bytes,
//     mirrored at +42): each frame one glyph half is ORed into the next slab
//     at word column b0, shifted right 16/12/8/4, the word after it
//     overwritten with the bits shifted out; after four frames b0 moves on
//     one word (4 px a frame), and every second time the next half/glyph;
//   * $10d66: a 42-word ring of per-byte-column steps, shifted one on every
//     frame; the new head = (last wave row - this wave row) rows + 4 bytes,
//     the wave being the 189-word $13af2 table (wave.raw);
//   * $10e48's copy: 40 byte columns (8 px each) of the slab into BITPLANE 1
//     of the page from row wave - 3, each column 16 rows plus two zero rows
//     above and below, then the next column one ring step further — so every
//     8-pixel column rides the wave a frame behind its left neighbour.
// The text starts on a space ($1103a) and then runs from text[1]. All integer.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const Page = @import("p4_page.zig").Page;

const SLAB_ROW = 0x54; // 84 bytes: 42 + its mirror
const SLAB = 16 * SLAB_ROW; // $540
const ROW = 160;
const BASE_ROW = 100; // $13af0's value at load
const PAGE_BYTES = @import("p4_page.zig").BYTES;

/// The four slabs, contiguous as on the machine (a slab's last row spills
/// its overwritten word into the next slab's first bytes, as the 68000's
/// does), plus the 2 bytes the last slab spills into ($16a62, never read).
var slabs: [4 * SLAB + 2]u8 = undefined;
var steps: [42]u16 = undefined; // $16ac6
var wave_i: u16 = 0; // $13aea
var last: u16 = BASE_ROW; // $13af0
var base: i32 = 0; // $13aec, a page offset
var shift: u16 = 16; // $145aa
var glyph: usize = 0; // $145ac, a byte offset into the font
var col: u16 = 0; // $145b0
var slab: usize = 0; // ($145b2 - $15562) / $540
var half: u16 = 0; // $145bc
var ci: usize = 0; // $145b6

pub fn reset() void {
    @memset(&slabs, 0);
    @memset(&steps, 0);
    wave_i = 0;
    last = BASE_ROW;
    base = 0;
    shift = 16;
    glyph = @as(usize, A.charmap[0x20]) * 64;
    col = 0;
    slab = 0;
    half = 0;
    ci = 0;
}

/// $10d66: shift the step ring, add this frame's step, set the base row.
pub fn wave() void {
    var i: usize = steps.len - 1;
    while (i > 0) : (i -= 1) steps[i] = steps[i - 1];
    wave_i += 1;
    if (wave_i >= A.WAVE_N) wave_i = 0;
    const now = A.wave[wave_i];
    const d1: u16 = last -% now +% 100;
    last = now;
    steps[0] = d1 *% ROW -% 0x3e7c;
    base = @as(i32, now) * ROW - 0x320;
}

/// $10e48's head: one glyph half into the current slab at column `col`.
fn feed() void {
    var at = slab * SLAB + col;
    for (0..16) |r| {
        const w: u16 = (@as(u16, A.font[glyph + 2 * r]) << 8) | A.font[glyph + 2 * r + 1];
        const lo: u16 = if (shift < 16) w >> @intCast(shift) else 0;
        const hi: u16 = if (shift > 0) w << @intCast(16 - shift) else w;
        orWord(at, lo);
        orWord(at + 0x2a, lo);
        setWord(at + 2, hi);
        setWord(at + 0x2c, hi);
        at += SLAB_ROW;
    }
}

fn orWord(at: usize, v: u16) void {
    slabs[at] |= @truncate(v >> 8);
    slabs[at + 1] |= @truncate(v);
}

fn setWord(at: usize, v: u16) void {
    slabs[at] = @truncate(v >> 8);
    slabs[at + 1] = @truncate(v);
}

fn put(page: *const Page, at: i32, v: u8) void {
    if (at < 0 or at >= PAGE_BYTES) return; // never taken: rows stay 63..145
    page.set(@intCast(at), v);
}

/// One byte column: zero rows above at `z`, 16 slab rows from `src`, zero
/// rows below.
fn column(page: *const Page, at: i32, src: usize) void {
    put(page, at - ROW, 0);
    put(page, at - 2 * ROW, 0);
    for (0..16) |k| put(page, at + @as(i32, @intCast(k * ROW)), slabs[src + k * SLAB_ROW]);
    put(page, at + 16 * ROW, 0);
    put(page, at + 17 * ROW, 0);
}

/// $10e48: feed, the 40-column copy into plane 1, then the slab state step.
pub fn draw(page: *const Page) void {
    feed();
    var a5: i32 = 0x142 + base;
    var src = slab * SLAB + 4 + col;
    for (0..20) |j| {
        column(page, a5, src);
        a5 += @as(i16, @bitCast(steps[2 * j]));
        column(page, a5 - 3, src + 1);
        a5 += @as(i16, @bitCast(steps[2 * j + 1]));
        src += 2;
    }
    advance();
}

fn advance() void {
    slab += 1;
    shift -= 4;
    if (shift > 0) return;
    shift = 16;
    slab = 0;
    col += 2;
    if (col == 0x2a) col = 0;
    half ^= 0xffff;
    if (half != 0) {
        glyph += 0x20;
        return;
    }
    ci += 1;
    const c = A.text_data[ci];
    if (c == 0xff) ci = 0;
    glyph = @as(usize, A.charmap[c]) * 64;
}
