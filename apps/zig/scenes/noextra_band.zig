// --------------------------------------------------------------------------
// NOEXTRA's distorted rainbow band, one row at a time (see noextra.zig, renderBand).
//
// The source row (raster.raw) is the ramp 1,1,1,1,2,2,2,2,...,160,160,160,160:
// column n holds n/4 + 1 (checked at comptime below, so a changed asset cannot
// silently break this). So the colour of Q16 source position u is
// raster[clamp(u >> 16)] = (u >> 18) + 1 inside the row, with no table load and
// no clamp: only the few words that run off either end of the 640-wide source
// take the clamped per-pixel path. Same bytes as the table version, 4 px a store.
//
// No ZigOS import: it tests natively (noextra_test.zig).
// --------------------------------------------------------------------------

fn checkRamp(comptime raster: []const u8) void {
    @setEvalBranchQuota(10 * raster.len + 1000);
    for (raster, 0..) |b, n| {
        if (b != n / 4 + 1) @compileError("noextra_band: raster.raw is no longer the 4-px ramp n/4 + 1");
    }
}

/// One band row: words[g] holds destination columns 4g..4g+3, whose source
/// positions are start + k * step (Q16) for k = 4g..4g+3.
pub fn row(words: []u32, start: i32, comptime step: i32, comptime raster: []const u8) void {
    comptime checkRamp(raster);
    const lim: i32 = @as(i32, @intCast(raster.len)) << 16; // first u past the last column
    var u = start;
    var g: usize = 0;
    // left edge (source column < 0), the inner run, right edge (column > last)
    while (g < words.len and u < 0) : (g += 1) {
        words[g] = edgeWord(u, step, raster);
        u += 4 * step;
    }
    // inner words: u + 3 step < lim (no overflow: |start| stays far below 2^30
    // for any row the band can reach); a division by a constant, i.e. a multiply
    const room: i32 = lim - 3 * step - u;
    const fit: usize = if (room > 0) @intCast(@divTrunc(room + 4 * step - 1, 4 * step)) else 0;
    const n = @min(fit, words.len - g);
    inner(words[g..][0..n], u, step);
    g += n;
    u += @as(i32, @intCast(n)) * 4 * step;
    while (g < words.len) : (g += 1) {
        words[g] = edgeWord(u, step, raster);
        u += 4 * step;
    }
}

// The zoom repeats every 36 columns: 36 * step = 10 colours (40 source px) - d,
// d = 28 (periodDrift). So a column 36b to the right shows its colour + 10b,
// unless its Q18 fraction is below d * b (then it borrows). The first 9 words
// are computed and the lowest fraction among their 36 columns noted; each
// following block of 9 is that one + 0x0A0A0A0A a block for as long as no
// column can borrow; whatever is left is computed.
fn inner(words: []u32, start: i32, comptime step: i32) void {
    const d = comptime periodDrift(step);
    var blk: [9]u32 = undefined;
    var low: i32 = FRAC; // lowest Q18 fraction of the first block's 36 columns
    const head: usize = @min(words.len, blk.len);
    var u = start;
    for (0..head) |j| {
        blk[j] = innerWord(u, step, &low);
        words[j] = blk[j];
        u += 4 * step;
    }
    var g: usize = head;
    if (head == blk.len) {
        var add: u32 = 0;
        var need: i32 = d; // block b needs low >= d * b
        while (g < words.len and low >= need) : (need += d) {
            add +%= 0x0A0A0A0A;
            const m: usize = @min(blk.len, words.len - g);
            for (words[g..][0..m], blk[0..m]) |*w, b| w.* = b +% add;
            g += m;
            u += @as(i32, @intCast(m)) * 4 * step;
        }
    }
    while (g < words.len) : (g += 1) {
        var unused: i32 = FRAC;
        words[g] = innerWord(u, step, &unused);
        u += 4 * step;
    }
}

const FRAC: i32 = 1 << 18;

/// Q18 by which 36 columns fall short of 10 colours (exactly 40 source px).
fn periodDrift(comptime step: i32) i32 {
    const d = 10 * FRAC - 36 * step;
    if (d <= 0 or d * 12 >= FRAC) @compileError("noextra_band: the zoom no longer repeats every 36 columns");
    return d;
}

// A word wholly inside the source: colour (u >> 18) + 1 per column; notes the
// lowest Q18 fraction seen.
inline fn innerWord(u: i32, comptime step: i32, low: *i32) u32 {
    var w: u32 = 0;
    inline for (0..4) |k| {
        const v = u + @as(i32, k) * step;
        low.* = @min(low.*, v & (FRAC - 1));
        w |= @as(u32, @intCast(v >> 18)) << (8 * k);
    }
    // every byte <= 159 before the +1: no carry between them
    return w +% 0x01010101;
}

// The table version's own rule, for the words that leave the source: widening past the
// original's 320 runs off the ends of the 640-wide source, so hold the edge pixel rather
// than punch a moving black wedge into the side border.
fn edgeWord(u: i32, comptime step: i32, comptime raster: []const u8) u32 {
    var w: u32 = 0;
    inline for (0..4) |k| {
        const c: i32 = @min(@max((u + @as(i32, k) * step) >> 16, 0), @as(i32, @intCast(raster.len)) - 1);
        w |= @as(u32, raster[@intCast(c)]) << (8 * k);
    }
    return w;
}
