// --------------------------------------------------------------------------
// The plane's per-line raster as a COPPER LIST (HW 1.9.0, machine/copper.zig): colour 0 is the
// line's C64 border colour, and the line FLICKs where the C64 opened its border (the top and
// bottom bands when the vertical border is open, a visible row's sides when a side border is).
// That was the plane's HBL handler's job, line by line; the machine now applies the record
// before the line, where the handler ran, so ZIGGY takes no 280 handler calls a frame and
// stores only the words that changed since the last C64 frame (the border colour is the same
// on most lines and most frames: a real raster coder rewrites only what changes).
// The closed borders' colour (and BEAM for part 2's mid-line switches) stays the global HBL's
// (c64_1988.zig): that is the machine's background, not a plane register.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const vic = @import("vic.zig");

const ROWS = vic.ROWS;
const REC = 4; // HEAD, FLICK, PAL(0, 1), the colour
pub const WORDS = ROWS * REC + 1;
const HEAD: u32 = 0xF000_0000;
const FLICK: u32 = 0x3000_0000;
const PAL0: u32 = 0x1000_0000 | 1 << 12; // entry 0, one word

/// Rebuild `list` from `out` (one C64 frame's border state). `rgba` maps a C64 colour to the
/// palette word. Rows that neither flicker nor change colour get no record.
pub fn build(list: []u32, out: *const vic.Out, comptime rgba: fn (u8) u32) void {
    var w: usize = 0;
    var last: u32 = 0;
    for (0..ROWS) |r| {
        const band = r < zg.VERTICAL_BORDERS_HEIGHT or r >= zg.VERTICAL_BORDERS_HEIGHT + zg.HEIGHT;
        const flick = if (band) out.vopen[r] else out.sides[r];
        const c = rgba(out.border[r]);
        const pal = r == 0 or c != last;
        last = c;
        const n: u32 = @as(u32, @intFromBool(flick)) + 2 * @as(u32, @intFromBool(pal));
        if (n == 0) continue;
        put(list, &w, HEAD | @as(u32, @intCast(r)) << 19 | n);
        if (flick) put(list, &w, FLICK);
        if (pal) {
            put(list, &w, PAL0);
            put(list, &w, c);
        }
    }
    put(list, &w, HEAD | 511 << 19);
}

inline fn put(l: []u32, w: *usize, v: u32) void {
    if (l[w.*] != v) l[w.*] = v; // a store only where the list changed
    w.* += 1;
}
