// --------------------------------------------------------------------------
// The line list: Mind Rewind's whole display.
//
// The demo's fullscreen kernel loads one record per scanline, 280 of them, and
// writes it in the border between lines: the STE video counter ($FF8205/07/09:
// which bytes the line shows), HSCROLL ($FF8264) and colour 0 ($FF8240). Every
// part is "fill this table" (ANALYSIS.md §2). Here a record is the VRAM byte
// offset of the line's first pixel (the STE's address plus its fine scroll:
// chunky, so one byte a pixel) and the colour-0 word, and the table becomes
// the plane's copper list (HW 1.10.0, machine/copper.zig): per line HEAD,
// FLICK (all four borders open, as the demo opens them), LBASE (the counter)
// and PAL 0 (the real raster: one colour-0 write a line, borders included).
//
// The ST's overscan line is 416 px, KESTREL's 400: LBASE skips the first 8.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const ROWS: usize = zg.PHYSICAL_HEIGHT; // 280, as the demo's 280 records
pub const CROP: u32 = 8; // ST px 8..407 -> KESTREL 0..399
pub const WORDS: usize = ROWS * 5 + 1;

pub const Line = struct {
    src: u32, // region offset of ST pixel 0 of the line (+ fine scroll)
    colour: u16, // STE colour word for colour 0
};

pub var table: [ROWS]Line = undefined;

/// An STE colour word to the plane's RGBA: each 4-bit STE level x 16 (as BEAM: $777 -> 224).
pub fn ste(w: u16) u32 {
    const lvl = struct {
        fn f(n: u16) u32 {
            return ((n & 7) << 1 | (n >> 3) & 1) * 16;
        }
    }.f;
    return 0xff00_0000 | lvl(w & 15) << 16 | lvl((w >> 4) & 15) << 8 | lvl((w >> 8) & 15);
}

pub fn fill(first: usize, n: usize, src: u32, colour: u16) void {
    for (table[first..][0..n]) |*l| l.* = .{ .src = src, .colour = colour };
}

pub fn setColour(first: usize, n: usize, colour: u16) void {
    for (table[first..][0..n]) |*l| l.colour = colour;
}

var list: []u32 = &.{};

/// The plane's list buffer in VRAM; false when the pool is full.
pub fn install(fb: *zg.LogicalFB) bool {
    list = fb.copperList(WORDS) orelse return false;
    return true;
}

/// This frame's table into the list: only the words that changed are stored.
pub fn build() void {
    if (list.len == 0) return;
    var w: usize = 0;
    for (table, 0..) |l, y| {
        put(&w, 0xF000_0000 | @as(u32, @intCast(y)) << 19 | 4);
        put(&w, 0x3000_0000); // FLICK
        put(&w, 0x5000_0000 | (l.src + CROP)); // LBASE
        put(&w, 0x1000_0000 | 1 << 12); // PAL entry 0, one word
        put(&w, ste(l.colour));
    }
    put(&w, 0xF000_0000 | 511 << 19);
}

inline fn put(w: *usize, v: u32) void {
    if (list[w.*] != v) list[w.*] = v;
    w.* += 1;
}
