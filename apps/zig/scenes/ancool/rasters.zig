// --------------------------------------------------------------------------
// AN Cool's scroller rasters: a REAL raster, the scroller's ink register
// (palette entry INK) rewritten per scanline from the plane's HBL handler.
//
// The colours are packed to RGBA words at comptime: the handler used to read
// rasters.dat as byte-aligned Color structs and pack them on every line, and
// ZIGGY traps on the misaligned word load that came out of it (159 traps a
// frame, ~210 cycles each). Same colours, same lines, same writes.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const INK = 1; // the font's ink index (fonts_pal.raw holds only 0 and 1)
const LEN = 152; // raster colours in the cycle

const table: [LEN]u32 = blk: {
    const colors = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/ancool/rasters.dat"));
    var out: [LEN]u32 = undefined;
    for (&out, 0..) |*o, i| o.* = colors[i].toRGBA();
    break :blk out;
};
const BACK: u32 = 0; // clear (r = g = b = a = 0) below the picture

/// The cycle position, stepped once a frame by step().
pub var index: u16 = 0;

pub fn step() void {
    if (index < 150) index += 2 else index = 0;
}

fn setInk(fb: *zg.LogicalFB, rgba: u32) void {
    // Only a CHANGE is written, as a raster coder would.
    if (fb.palette[INK] != rgba) fb.palette[INK] = rgba;
}

pub fn handler(fb: *zg.LogicalFB, zigos: *zg.ZigOS, line: u16, col: u16) void {
    if (line > 40 and line < 240) setInk(fb, table[(index + line - 40) % LEN]);
    if (line > 240) setInk(fb, BACK);
    _ = zigos;
    _ = col;
}
