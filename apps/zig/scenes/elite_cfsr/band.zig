// --------------------------------------------------------------------------
// The scroller band: CLEAR / PLOT_EDGES / FILL_XOR_BUFFER / WRAP_XOR_BUFFER /
// COPY_XOR_BUFFER (TEXT $782, $808, $e12, $ea6, $f00), the five calls MAIN makes
// in that order every frame.
//
// XOR_BUFFER is 10 blocks of 32 columns; a block row is one long, so the whole
// thing is 320 longs = the 1280 bytes CLEAR_XOR_BUFFER wipes. PLOT_EDGES toggles
// one bit per edge at row ysin[column] + edge, 32 rows deep; FILL runs a
// cumulative XOR straight down all 320 longs (blocks included — with six edges a
// column always closes, so nothing leaks from one block into the next); WRAP ORs
// rows 16..31 back onto 0..15, which is what makes the vertical wobble wrap
// instead of sliding off.
//
// COPY_XOR_BUFFER's move.l is the whole reason the band is two-toned: it writes
// a long at screen offset $1b86, which is PLANE 3 of pixels 0..15 followed by
// PLANE 0 of pixels 16..31. So the high word of a block inks colour 8 and the low
// word colour 1 — and that is why TIMER_B_1 writes the same raster value to both
// $ffff8250 and $ffff8242. Here it is just two palette indices.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

/// The XOR buffer, block-major so the FILL sweep is a flat walk.
var plot: [A.BLOCKS][A.PLOT_ROWS]u32 = undefined;
/// The 16 finished rows, one palette index a pixel, ready to memcpy.
var rows: [A.BAND_ROWS][A.COLUMNS]u8 = undefined;

/// Rebuild this frame's 16-row pattern from `edges` (320 columns x 6 edges) and
/// the frame counter, which is all the vertical wobble depends on.
pub fn build(edges: []const u8, frame: u32) void {
    plotEdges(edges, frame);
    fill();
    wrap();
    expand();
}

/// Paint the band into `dst` (an 8-bit plane `stride` wide), 10 copies of the
/// 16 rows every 16 lines, clipped to the `visible_lines` the screen shows.
pub fn draw(dst: []u8, stride: usize, visible_lines: usize) void {
    for (0..A.BAND_REPEATS) |k| {
        for (&rows, 0..) |*row, r| {
            const line = A.BAND_TOP + k * A.BAND_ROWS + r;
            if (line >= visible_lines) return; // the original trims the same way
            const at = (A.CONTENT_Y + line) * stride + A.CONTENT_X;
            @memcpy(dst[at..][0..A.COLUMNS], row);
        }
    }
}

fn plotEdges(edges: []const u8, frame: u32) void {
    for (&plot) |*block| @memset(block, 0);
    // d4 = FRAME * 16 masked to $1fff, then +2 a column: a word index of
    // frame * 8 + column, and the table is 4096 words long.
    var s: usize = (@as(usize, frame) * 8) % A.YSIN_LEN;
    var e: usize = 0;
    for (0..A.COLUMNS) |x| {
        const block = &plot[x / 32];
        const bit = @as(u32, 0x8000_0000) >> @intCast(x % 32);
        const y0: usize = A.ysin[s];
        for (0..A.EDGES) |_| {
            block[y0 + edges[e]] ^= bit;
            e += 1;
        }
        s += 1;
        if (s == A.YSIN_LEN) s = 0;
    }
}

/// The running XOR down the whole buffer that turns edges into filled spans.
fn fill() void {
    const flat: *[A.BLOCKS * A.PLOT_ROWS]u32 = @ptrCast(&plot);
    for (1..flat.len) |i| flat[i] ^= flat[i - 1];
}

/// Fold the lower 16 rows back onto the upper 16 — the wobble's wrap-around.
fn wrap() void {
    for (&plot) |*block| {
        for (0..A.BAND_ROWS) |r| block[r] |= block[r + A.BAND_ROWS];
    }
}

fn expand() void {
    for (&rows, 0..) |*row, r| {
        for (plot, 0..) |block, b| {
            var bits = block[r];
            for (0..32) |c| {
                const set = (bits & 0x8000_0000) != 0;
                bits <<= 1;
                row[b * 32 + c] = if (!set) 0 else if (c < 16) A.INK_HI else A.INK_LO;
            }
        }
    }
}
