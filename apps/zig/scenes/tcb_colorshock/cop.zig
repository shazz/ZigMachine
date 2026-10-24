// --------------------------------------------------------------------------
// COLORSHOCK 2's raster as a copper list (HW 1.9.0, machine/copper.zig): the
// same line as hbl.panHbl -- the border flicker, the tile row's field colours,
// the scroll strip row's -- but applied by the machine, so the CPU makes no
// palette store at all: on the board panHbl's ~86 words a line were 0.86 Mc a
// frame. The field's rows are copied once into VRAM; a line's PALREF names its
// row, so a frame's list changes by one word a line as the field pans.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const field = @import("field.zig");
const inkpal = @import("inkpal.zig");
const strip = @import("strip.zig");
const hbl = @import("hbl.zig");

const ROWS = zg.PHYSICAL_HEIGHT;
// A line: HEAD, FLICK, PALREF + offset, and the strip's PAL + its colours.
const WORDS = ROWS * 4 + strip.STRIP_H * (1 + inkpal.STRIP_ENTRIES) + 1;

var table_off: u32 = 0;

/// The field rows into VRAM and the plane's list buffer; false (the HBL handler stays) on a
/// machine without lists or with no VRAM left.
pub fn install(fb: *zg.LogicalFB) bool {
    const t = zg.vramWords(field.fond_words.len) orelse return false;
    if (fb.copperList(WORDS) == null) return false;
    @memcpy(t.words, &field.fond_words);
    table_off = t.off;
    fb.clearFrameBufferHBLHandler();
    return true;
}

/// This frame's list, after render() set pan_row and the strip (as panHbl reads them).
pub fn build(fb: *zg.LogicalFB) void {
    const l = fb.copperBuffer() orelse return;
    var w: usize = 0;
    var line: u32 = 0;
    while (line < ROWS) : (line += 1) {
        var row: u32 = field.pan_row + line;
        if (row >= field.TILE_H) row -= field.TILE_H;
        const gy = line -% hbl.strip_line;
        const k: u32 = if (gy < strip.STRIP_H) hbl.strip_pal.used[gy] else 0;
        const f: u32 = field.fond_used[row]; // a block of 0 entries would stop the list
        const n: u32 = 1 + (if (f == 0) @as(u32, 0) else 2) + (if (k == 0) @as(u32, 0) else 1 + k);
        put(l, &w, 0xF000_0000 | line << 19 | n);
        put(l, &w, 0x3000_0000);
        if (f != 0) {
            put(l, &w, 0x4000_0000 | f << 12);
            put(l, &w, table_off + row * field.ROW_COLOURS * 4);
        }
        if (k == 0) continue;
        put(l, &w, 0x1000_0000 | @as(u32, inkpal.STRIP_FIRST) << 20 | k << 12);
        for (hbl.strip_pal.colours[gy][0..k]) |c| put(l, &w, c);
    }
    put(l, &w, 0xF000_0000 | 511 << 19);
}

inline fn put(l: []u32, w: *usize, v: u32) void {
    if (l[w.*] != v) l[w.*] = v;
    w.* += 1;
}
