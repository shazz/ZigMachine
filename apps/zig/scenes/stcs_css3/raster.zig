// --------------------------------------------------------------------------
// The raster ($3AA VBL + $7C4 Timer B): the whole 16-colour palette swapped at
// 17 line positions. The VBL installs the top palette ($D3FE) and arms Timer B
// in event-count mode with byte $D658 (40); interrupt i loads the next count,
// waits for the next line end and installs block $D41E + 32 i. So block i is
// live from line E_i + 2, E_0 = 39, E_i = E_(i-1) + count_i.
//
// The bar: counts c2 ($D65A) and c12 ($D664) trade 2 lines a frame over 96
// frames, and its nine 2-line blocks P2..P10 take a 9-entry window of the
// 28-word ring at $D620, rotated one entry a frame.
// --------------------------------------------------------------------------
const Machine = @import("machine.zig").Machine;

const C2: u16 = 0xD65A;
const C12: u16 = 0xD664;
const RING: u16 = 0xD620;
const RING_WORDS: usize = 28;
const BAR_BLOCKS: u16 = 0xD45E; // P2
const TOP: u16 = 0xD3FE;
const BLOCKS: u16 = 0xD41E;
const COUNTS: u16 = 0xD658;
pub const NBLOCKS: usize = 16;
const PURPLE_GREEN: u16 = 0x171;

/// $3AA's motion part: runs first thing every VBL.
pub fn vbl(m: *Machine) void {
    var t: [RING_WORDS]u16 = undefined;
    for (&t, 0..) |*w, i| w.* = m.rasterWord(RING + 2 * @as(u16, @intCast(i)));
    if (!m.bar_up) {
        m.raster[C2 - 0xD3FE] +%= 2;
        m.raster[C12 - 0xD3FE] -%= 2;
        // move.w -(a1),-(a0) x27 then move.w $D656,$D620
        var n: [RING_WORDS]u16 = undefined;
        for (0..RING_WORDS - 1) |i| n[i + 1] = t[i];
        n[0] = n[RING_WORDS - 1];
        storeRing(m, &n);
        paintBar(m, &n, &.{ 0, 1, 4, 5, 8, 9, 12, 13 });
        if (m.rasterByte(C2) == 98) m.bar_up = true;
    } else {
        m.raster[C2 - 0xD3FE] -%= 2;
        m.raster[C12 - 0xD3FE] +%= 2;
        // (a0)+ -> (a1)+ starting one word low: t[0] lands on $D61E, just past
        // P15, and $D61E is then copied to $D654 (ring[26]); ring[27] stays.
        m.setRasterWord(RING - 2, t[0]);
        for (1..RING_WORDS) |i| m.setRasterWord(RING + 2 * @as(u16, @intCast(i - 1)), t[i]);
        m.setRasterWord(RING + 2 * 26, m.rasterWord(RING - 2));
        var n: [RING_WORDS]u16 = undefined;
        for (&n, 0..) |*w, i| w.* = m.rasterWord(RING + 2 * @as(u16, @intCast(i)));
        paintBar(m, &n, &.{ 0, 1, 8, 9 });
        // going up, the letters' colours (plane 2) show in front of the bar
        for (0..9) |k| for ([_]u16{ 4, 5, 12, 13 }) |c| m.setRasterWord(barEntry(k, c), PURPLE_GREEN);
        if (m.rasterByte(C2) == 2) m.bar_up = false;
    }
}

fn storeRing(m: *Machine, n: *const [RING_WORDS]u16) void {
    for (n, 0..) |w, i| m.setRasterWord(RING + 2 * @as(u16, @intCast(i)), w);
}

fn barEntry(k: usize, c: u16) u16 {
    return BAR_BLOCKS + 32 * @as(u16, @intCast(k)) + 2 * c;
}

/// Block P(2+k) takes ring entry k in the given colour registers.
fn paintBar(m: *Machine, n: *const [RING_WORDS]u16, regs: []const u16) void {
    for (0..9) |k| for (regs) |c| m.setRasterWord(barEntry(k, c), n[k]);
}

/// The palette each line shows: 0 = the top palette, i + 1 = block i.
pub fn lineBlocks(m: *const Machine, out: *[200]u8) void {
    var starts: [NBLOCKS]u32 = undefined;
    var e: u32 = @as(u32, m.rasterByte(COUNTS)) -% 1;
    for (0..NBLOCKS) |i| {
        starts[i] = e + 2;
        e += m.rasterByte(COUNTS + 1 + @as(u16, @intCast(i)));
    }
    var blk: usize = 0;
    for (out, 0..) |*b, y| {
        while (blk < NBLOCKS and starts[blk] <= y) blk += 1;
        b.* = @intCast(blk);
    }
}

/// Colour register `c` of palette `p` (0 = top, i + 1 = block i), $0RGB.
pub fn colour(m: *const Machine, p: usize, c: usize) u16 {
    const base: u16 = if (p == 0) TOP else BLOCKS + 32 * @as(u16, @intCast(p - 1));
    return m.rasterWord(base + 2 * @as(u16, @intCast(c)));
}
