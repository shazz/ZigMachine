// --------------------------------------------------------------------------
// COLORSHOCK 2 — one palette per scanline: the ST trick this screen is named
// for. The plane's HBL opens the borders (it replaces flickerAllHbl rather than
// fighting it), installs the field's colours for the tile row on this line,
// and on the scroll strip's 26 lines also that strip row's colours.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const field = @import("field.zig");
const inkpal = @import("inkpal.zig");
const strip = @import("strip.zig");

const LogicalFB = zg.LogicalFB;
const ZigOS = zg.ZigOS;

pub const StripPal = inkpal.StripPal(strip.STRIP_H);

/// The strip's colours by row, and the plane line its row 0 is on this frame.
/// Module state: HBL handlers take no user pointer.
pub var strip_pal: StripPal = .{};
pub var strip_line: u16 = 0;

pub fn panHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    var row: u32 = field.pan_row + line;
    if (row >= field.TILE_H) row -= field.TILE_H; // pan_row < 288, line < 280
    const dst: [*]volatile u32 = fb.palette;
    copyWords(dst, field.fond_words[row * field.ROW_COLOURS ..].ptr, field.fond_used[row]);
    const gy = line -% strip_line;
    if (gy < strip.STRIP_H) {
        copyWords(dst + inkpal.STRIP_FIRST, &strip_pal.colours[gy], strip_pal.used[gy]);
    }
}

// Word stores into the palette registers, four at a time: a memcpy costs ~60
// cycles a word on the board (picolibc), and this runs ~86 words on each of
// 280 lines.
inline fn copyWords(dst: [*]volatile u32, src: [*]const u32, n: usize) void {
    var i: usize = 0;
    while (i + 4 <= n) : (i += 4) {
        dst[i] = src[i];
        dst[i + 1] = src[i + 1];
        dst[i + 2] = src[i + 2];
        dst[i + 3] = src[i + 3];
    }
    while (i < n) : (i += 1) dst[i] = src[i];
}
