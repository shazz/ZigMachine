// --------------------------------------------------------------------------
// The screen's one bitmap: the demo's $0168 text printer, run at COMPILE time
// over its own text ($06D8, every byte nibble-swapped) and its 8x8 font ($1286),
// into the 256x200 1-bit plane it prints at startup (32-byte rows). Pure.
//
// The printer's control bytes: $0A new line (the next character row PLUS one
// spacing row, twice in a tall mode), $0B mode, $0C position (a byte offset into
// the bitmap, low byte first). Modes: 0 = 8x8; 4 = double height; 1 = double
// width (each bit doubled into a word, word-aligned); 2 = double width + height.
//
// On the Amiga the same bitmap is shown TWICE, as a dual playfield (BPLCON0
// $2600): PF1 = bitmap+$20 in COLOR01 (the text, in front) and PF2 = bitmap in
// COLOR09 $888, delayed one pixel (BPLCON1 $0010) -- so line n shows the text's
// row n+1 and, one pixel right, the shadow's row n: a drop shadow one down, one
// right, for nothing. Here that is composed once into the indices of plane 1.
// --------------------------------------------------------------------------
const C = @import("amiga_copper.zig");

pub const FONT = @embedFile("../../assets/screens/hippel_musicdisk/font.bin");
const TEXT_AT = 0x60; // $06D8 - $0678 in tables.bin
pub const W = 256; // DDFSTRT $48..DDFSTOP $C0: 16 words a line
pub const H = 200; // $1900 bytes
pub const LINES = 199; // DIWSTRT $40 .. DIWSTOP $107
pub const STRIDE = W / 8;

pub const Bitmap = [H * STRIDE]u8;

fn ch(i: usize) u8 {
    const b = C.TABLES[TEXT_AT + i];
    return (b >> 4) | (b << 4); // ror.b #4
}

fn glyph(c: u8, r: usize) u8 {
    return FONT[(@as(usize, c) - 0x20) * 8 + r];
}

/// Each font bit doubled: the double-width modes' word.
fn wide(b: u8) u16 {
    var w: u16 = 0;
    for (0..8) |k| w = (w << 2) | (if ((b >> @intCast(7 - k)) & 1 != 0) @as(u16, 3) else 0);
    return w;
}

fn print() Bitmap {
    @setEvalBranchQuota(500_000);
    var bm: Bitmap = @splat(0);
    var mode: u8 = 2; // moveq #2,d1 before the bsr
    var at: usize = 0;
    var i: usize = 0;
    while (ch(i) != 0) {
        const c = ch(i);
        i += 1;
        switch (c) {
            0x0A => for (0..@as(usize, if (mode & 6 != 0) 2 else 1)) |_| {
                at = ((at + 0x20) & 0xFFE0) + 0x100;
            },
            0x0B => {
                mode = ch(i);
                i += 1;
            },
            0x0C => {
                at = @as(usize, ch(i + 1)) << 8 | ch(i);
                i += 2;
            },
            else => if (mode == 0 or mode == 4) narrow(&bm, &at, c, mode) else broad(&bm, &at, c, mode),
        }
    }
    return bm;
}

/// Modes 0 and 4 ($01A8): one byte a row, each row twice in mode 4.
fn narrow(bm: *Bitmap, at: *usize, c: u8, mode: u8) void {
    var a = at.*;
    for (0..8) |r| for (0..@as(usize, if (mode & 4 != 0) 2 else 1)) |_| {
        bm[a] = glyph(c, r);
        a += STRIDE;
    };
    at.* += 1;
}

/// Modes 1 and 2 ($01D2): word-aligned, every bit doubled, each row twice in mode 2.
fn broad(bm: *Bitmap, at: *usize, c: u8, mode: u8) void {
    at.* = (at.* + 1) & ~@as(usize, 1);
    var a = at.*;
    for (0..8) |r| for (0..@as(usize, if (mode & 2 != 0) 2 else 1)) |_| {
        const w = wide(glyph(c, r));
        bm[a] = @truncate(w >> 8);
        bm[a + 1] = @truncate(w);
        a += STRIDE;
    };
    at.* += 2;
}

pub const BITMAP = print();

pub fn bit(row: usize, x: usize) bool {
    if (row >= H or x >= W) return false;
    return (BITMAP[row * STRIDE + x / 8] >> @intCast(7 - x % 8)) & 1 != 0;
}

/// Display line n (0 = Amiga line $40) shows playfield 1's bitmap row n+1.
pub fn hasText(n: usize) bool {
    for (0..W) |x| if (bit(n + 1, x)) return true;
    return false;
}

/// The lines whose COLOR01 is ever seen: only their colours need writing.
pub const TEXT_LINE_COUNT = blk: {
    @setEvalBranchQuota(200_000);
    var k: usize = 0;
    for (0..LINES) |n| if (hasText(n)) {
        k += 1;
    };
    break :blk k;
};

pub const TEXT_LINES: [TEXT_LINE_COUNT]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [TEXT_LINE_COUNT]u8 = undefined;
    var k: usize = 0;
    for (0..LINES) |n| if (hasText(n)) {
        t[k] = n;
        k += 1;
    };
    break :blk t;
};
