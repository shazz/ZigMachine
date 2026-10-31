// --------------------------------------------------------------------------
// The line list: Mind Rewind's whole display.
//
// The demo's fullscreen kernel loads one record per scanline, 280 of them, and
// writes it in the border between lines: the STE video counter ($FF8205/07/09:
// which bytes the line shows), HSCROLL ($FF8264) and colour 0 ($FF8240). Every
// part is "fill this table" (ANALYSIS.md §2). Here a record is the VRAM byte
// offset of the line's first pixel (the STE's address plus its fine scroll:
// chunky, so one byte a pixel) and the colour-0 word; zg.linelist turns the
// table into the plane's copper list (HW 1.10.0): FLICK on every line (all
// four borders open, as the demo opens them), LBASE (the counter) where a line
// does not run on from the one above, and PAL 0 (the real raster: one
// colour-0 write a line, borders included) where colour 0 changes.
//
// The ST's overscan line is 416 px, KESTREL's 400: each base skips the first 8.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const ROWS: usize = zg.PHYSICAL_HEIGHT; // 280, as the demo's 280 records
pub const CROP: u32 = 8; // ST px 8..407 -> KESTREL 0..399

pub const Line = struct {
    src: u32, // region offset of ST pixel 0 of the line (+ fine scroll)
    colour: u16, // STE colour word for colour 0
};

pub var table: [ROWS]Line = undefined;
var out: [ROWS]zg.linelist.Line = undefined;
var list: ?[]u32 = null;
var plane: u8 = 0;

/// An STE colour word to the plane's RGBA: each 4-bit STE level x 16 (as BEAM: $777 -> 224).
pub fn ste(w: u16) u32 {
    const lvl = struct {
        fn f(n: u16) u32 {
            return (((n & 7) << 1) | ((n >> 3) & 1)) * 16;
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

/// The plane's list in VRAM, published, borders opened by its FLICKs; false when VRAM is full.
pub fn install(fb: *zg.LogicalFB) bool {
    plane = fb.id;
    list = zg.linelist.install(fb, ROWS, true);
    return list != null;
}

/// This frame's table into the list (zg.linelist stores only the words that changed).
pub fn build() void {
    const l = list orelse return;
    for (table, &out) |t, *o| o.* = .{ .base = t.src + CROP, .hscroll = 0, .colour = ste(t.colour) };
    _ = zg.linelist.build(l, &out, .{ .plane = plane, .stride = zg.PHYSICAL_WIDTH, .flicker = true }) catch {};
}
