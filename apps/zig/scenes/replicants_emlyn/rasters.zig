// --------------------------------------------------------------------------
// The raster bars, done the way the ST cracktro did them: NOT pixels.
//
// The CODEF remake draws bar.png as a sprite per vectorball. That was the
// remake faking it — bar.png's 64 rows are each ONE solid colour (measured), so
// what it is really carrying is a colour TABLE, and the real screen changed the
// palette per scanline. Here the background is a ramp of palette INDICES across
// the whole 400-column raster and this module's HBL writes their colours for
// every line, so a bar IS a palette change on a scanline, as on hardware. The
// ramp spans the side borders too, because the ST's border is a colour register
// like any other: a raster bar runs edge to edge (vex/intro.zig says the same).
//
// WHAT THE BUDGET IS ON. A palette write costs cycles, and low res paints one
// pixel per cycle, so the writes must keep ahead of the beam. But the budget is
// on the writes a line NEEDS, and a line only needs to rewrite an entry whose
// colour CHANGED since the line above:
//
//   theta = 0    the colour depends on y alone. One entry, one write a line —
//                the classic raster bar, and the cheapest case there is.
//   theta = 90   the colour depends on x alone, so the palette is the same on
//                every line: load it once a frame, spend NOTHING per line, and
//                a very fine ramp is free.
//   in between   an entry changes when a line's 2*|cos theta| canvas-pixel shift
//                crosses a colour band, so the per-line cost goes with cos and
//                the ramp fineness you must afford goes with sin.
//
// WHAT A WRITE COSTS. Not 12 cycles: that is `move.w Dn,(xxx).W`, the wrong
// instruction, and 400 / 12 = 33 entries is all a full open line would buy.
// ST raster code uses movem, and MOVEM.L d0-d7,(a0) is 8 + 8n = 72 cycles for
// 16 registers — 4.5 cycles, so 4.5 pixels, an entry. (The bundled cycle table
// prints MOVEM r>m as t=5; its own m>r row uses t=4, and only t=4 reproduces
// the MC68000 manual for both, so t=5 is an error there.) An open 400-pixel
// line therefore affords 400 / 4.5 = 88 entries that change, and more where
// fewer of them do.
//
// So bucketCount() picks the ramp from theta every frame: 1 entry at theta = 0,
// ~88 through the diagonals where every entry changes, and up to the palette's
// limit near vertical where almost none do.
//
// AND THE COLOURS ARE THE REAL SCREEN'S. bar.png holds exactly 16 colours and
// every channel of every one is a multiple of 32 and at most 224 — the canonical
// 3-bits-per-channel Atari ST colour register, rendered as nibble * 32. One ST
// palette, in other words, so these ARE the registers the cracktro wrote (the
// logo and the font are not on that grid: they went through a paint program).
// The 64 rows pair up into a 16-colour ramp run up and back down, which is what
// a raster bar's colour list looks like.
//
// MERGING. Where a bucket is wider than a colour band, the band cannot be shown
// — two of them would need the same entry at the same moment — so bands merge
// into groups of `merge[]`, which is why a steeply tilted bar shows a coarse
// ramp cleanly instead of a fine one aliased into chequerboard. At theta = 0 the
// step is zero, every group is one band, and the content window comes out
// bit-identical to the remake-verified port (measured, still true).
//
// Colour at canvas (x, y) = bar(u), u = (x - CX)*sin(theta) + (y - CY)*cos(theta) + CY.
// The group's origin projects to exactly (CX, CY), so turning the sampling axis
// about that point IS turning the group about the camera's z axis: the bars stay
// perpendicular to the axis the twelve balls are strung along, and widening the
// ramp over the borders does not shift them.
//
// THIS FILE is what both carts share: the table, the HBL that replays it, and
// the ramp. What FILLS the table each frame is the cart's number back-end:
// fill_fixed.zig (the default cart: integers, one span per bar per line, the
// way an ST coder would) or fill_f32.zig (replicants_emlyn_f32: the CODEF port's
// per-bucket search, in f32, for the FPU test).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const cap16 = @import("cap16.zig");

pub const PLANE_W: usize = zg.PHYSICAL_WIDTH; // 400: the ramp covers the side borders too
pub const CX = 320; // the canvas centre, where the group's origin projects
pub const CY = 240;
pub const BAR_ROWS = 64; // bar.png's source rows; the halved table has BANDS
pub const BANDS = 32;
pub const BLACK = BANDS; // the 33rd ink: no bar over this point

pub const MAX_BUCKETS = 256 - @as(usize, A.FIRST_BUCKET); // 149, what the palette has left
pub const LINE_CYCLES = 400; // an open line displays 400 pixels, one a cycle
/// movem.l d0-d7,(a0): 72 cycles, 16 registers, so 4.5 cycles an entry; kept as
/// the fraction 9/2 so the fixed-point cart never needs a float for it.
pub const CYCLES_PER_ENTRY_X2 = 9;

/// A table row: MAX_BUCKETS inks padded to whole words, so the HBL compares
/// a line with the one above four buckets at a time.
pub const ROW = (MAX_BUCKETS + 3) / 4 * 4; // 152
pub const WORDS = ROW / 4;

/// The ink of every bucket of every PHYSICAL row: a band 0..31, or BLACK.
/// 42,560 B on zg.mem, taken by install() before the HBL that reads it goes in.
pub var table: *align(4) [zg.PHYSICAL_HEIGHT][ROW]u8 = undefined;
pub var ink: [BANDS + 1]u32 = undefined;
/// The background pattern, painted under everything: plane column x shows
/// bucket x * count / 400, and all the motion is in the palette.
pub var row: [PLANE_W]u8 = undefined;
pub var count: usize = 0;

/// Replace openBorders()'s handler with one that ALSO opens the borders: the
/// machine gives a plane one HBL, and this screen needs both. Runs once per
/// cart load (Demo.init), so the table is allocated once.
pub fn install(fb: *zg.LogicalFB) void {
    table = @ptrCast(zg.mem.mustAlloc(u32, zg.PHYSICAL_HEIGHT * WORDS).ptr);
    for (&ink, 0..) |*c, i| c.* = if (i == BLACK) A.BLACK_RGBA else A.bar_rgba[i];
    for (table) |*r| @memset(r, BLACK);
    lit = false;
    for (0..MAX_BUCKETS) |b| fb.palette[A.FIRST_BUCKET + b] = A.BLACK_RGBA;
    setCount(1);
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

/// This plane is OVERSCAN, so `line` is PHYSICAL 0..279 (machine/video.zig's
/// renderPlaneOverscan) — the table is indexed by it directly, the top and
/// bottom border lines included: they are open, and ZIG mode fills them too.
fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    // zigos's flickerAllHbl, which openBorders(.all) installed and this handler
    // replaces: EVERY line, so every border opens and the rasters run edge to
    // edge. That per-line cost is the trick's real price.
    fb.flickerBorder();
    if (line >= zg.PHYSICAL_HEIGHT) return;
    if (line == 0) {
        cap16.reset();
        return loadFirstLine(fb); // render() did it: nothing left
    }
    if (cap16.on) return cap16.line(fb, line); // key 3: 16 writes a line
    // Only the entries whose colour CHANGED since the line above are written —
    // the raster coder's rule, and the budget bucketCount() was sized on. The
    // palette always holds the line above (line 0's: loadFirstLine).
    const now: *const [ROW]u8 = &table[line];
    const was: *const [ROW]u8 = &table[line - 1];
    const now_w: *const [WORDS]u32 = @ptrCast(@alignCast(now)); // ROW is whole words
    const was_w: *const [WORDS]u32 = @ptrCast(@alignCast(was));
    const pal = fb.palette + A.FIRST_BUCKET;
    for (0..(count + 3) / 4) |w| {
        if (now_w[w] == was_w[w]) continue;
        for (w * 4..@min(w * 4 + 4, count)) |i| {
            if (now[i] != was[i]) pal[i] = ink[now[i]];
        }
    }
}

/// Line 0's colours, written only where the palette holds another: the VBL's
/// palette load on an ST, before the beam starts. render() calls it once the
/// table is built, so line 0's HBL (which calls it again, for a frame that is
/// composited twice) finds nothing to write. With the top border closed, line
/// 0 is BLACK, as line 279 left the palette, and nothing is written at all.
pub fn loadFirstLine(fb: *zg.LogicalFB) void {
    const pal = fb.palette + A.FIRST_BUCKET;
    for (table[0][0..count], 0..) |b, i| {
        if (pal[i] != ink[b]) pal[i] = ink[b];
    }
}

/// The physical rows a frame fills: the content window's 240, or with the top
/// and bottom borders `open` (ZIG mode) all 280, so the bars run on through
/// them from the same u as the window's lines. Closing puts them back to
/// BLACK, once.
pub const Rows = struct { first: usize, n: usize };
var lit = false; // the border rows hold rasters

pub fn rows(open: bool) Rows {
    if (lit and !open) {
        for (table[0..A.CONTENT_Y]) |*r| @memset(r, BLACK);
        for (table[A.CONTENT_Y + A.CONTENT_H ..]) |*r| @memset(r, BLACK);
    }
    lit = open;
    if (open) return .{ .first = 0, .n = zg.PHYSICAL_HEIGHT };
    return .{ .first = A.CONTENT_Y, .n = A.CONTENT_H };
}

pub fn setCount(n: usize) void {
    if (n == count) return;
    count = n;
    for (&row, 0..) |*p, x| p.* = A.FIRST_BUCKET + @as(u8, @intCast(x * count / PLANE_W));
}
