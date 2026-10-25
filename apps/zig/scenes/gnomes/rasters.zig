// --------------------------------------------------------------------------
// The two per-line colour registers, as REAL rasters. The original keeps a
// 276-line list of (colour 0, colour 1) longwords, played by a Timer-B handler
// ($13EA4: move.l (a6)+,$8240.w) at every line end. Here the same two
// registers are two copper slots on the plane (entries 0 and 1), written per
// physical row, borders included (colour 0 is what an ST border shows).
//
//   colour 0  $139DC: the 512-word background roll ($140A0), one word a frame,
//             then 16 bars of 15 lines ($13A24): bar i sits at line
//             BAR_POS[(c + 3i) & 511] and takes the next 15 words of the colour
//             stream ($1602C, 90 words); a bar cut by the bottom takes fewer, and
//             the stream wraps only on an exact match ($13A46), as in the code.
//   colour 1  written once by the init ($136EA): the logo fill, VU boxes, TTY
//             text, tag and scroller ramps (assets.COL1).
//
// The list is double-buffered: the one the VBL plays in frame n was built by
// loop n-1, so frame n shows counter c = n-1 (frame 1 plays an unwritten
// buffer: colour 0 black).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const copper = zg.copper;
const A = @import("assets.zig");

pub const SLOTS = [2]u8{ A.C0, A.C1 };
pub var tables: [SLOTS.len]copper.Table = undefined;
const BLACK = A.st(0);

/// After copper.install (it seeds every row with the entry's colour).
pub fn initTables() void {
    @memset(&tables[0], BLACK);
    @memset(&tables[1], BLACK);
    for (0..A.LINES) |l| tables[1][l + A.Y0] = A.COL1_RGBA[l];
}

/// Colour 0 of frame n (n >= 1).
pub fn build(n: u32) void {
    const t = &tables[0];
    if (n <= 1) {
        for (0..A.LINES) |l| t[l + A.Y0] = BLACK;
        return;
    }
    const c: usize = (n - 1) & 511;
    const base = c & 127;
    for (0..A.LINES) |l| t[l + A.Y0] = A.BG_RGBA[base + l];
    var a: usize = 0; // the colour stream's word index (a2 - $1602C) / 2
    for (0..16) |i| {
        var l: usize = A.BAR_POS[(c + 3 * i) & 511];
        var k: usize = 0;
        while (k < 15) : (k += 1) {
            t[l + A.Y0] = A.BAR_RGBA[a];
            a += 1;
            l += 1;
            if (l >= A.LINES) break;
        }
        if (a == 90) a = 0;
    }
}

/// The colour-0 word of line l in frame n, as the ST register holds it (testapi).
pub fn colour0(l: usize) u32 {
    return tables[0][l + A.Y0];
}
