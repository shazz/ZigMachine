// --------------------------------------------------------------------------
// The raster bars, done the way the ST cracktro did them: NOT pixels.
//
// The CODEF remake draws bar.png as a sprite per vectorball. That was the
// remake faking it — bar.png's 64 rows are each ONE solid colour (measured), so
// what it is really carrying is a colour TABLE, and the real screen changed the
// palette per scanline. Here the background is a ramp of palette INDICES across
// the whole 400-column raster and their colours are rewritten for every
// line (the copper list below), so a bar IS a palette change on a scanline, as on hardware. The
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
// THE COPPER PLAYS IT (HW 1.9.0, machine/copper.zig, fpga/review/COPPER_LIST.md).
// The table holds every physical line's bucket colours as the palette words
// themselves, a row a line, in VRAM; the plane's copper list says on every
// line FLICK (the border trick openBorders(.all)'s handler did) and PALREF
// (that line's row into the buckets). The machine applies the record before
// the line, where the HBL handler used to run, so the CPU runs no handler: no
// 280 interrupts, no compare, no palette store. The registers hold the same
// colours on every line as the handler left them (scene_hash --composite,
// every mode). The list itself is static: only PALREF's count follows
// setCount(). The compositor reloads an entry that did not change (a burst
// read, not a CPU store, as mpp_truecolor and tcb_colorshock do); what the ST
// could afford still sets the ramp, through bucketCount()'s change budget.
//
// THIS FILE is what both carts share: the table, its list, and the ramp. What
// FILLS the table each frame is the cart's number back-end: fill_fixed.zig
// (the default cart: integers, one span per bar per line, the way an ST coder
// would) or fill_f32.zig (replicants_emlyn_f32: the CODEF port's per-bucket
// search, in f32, for the FPU test).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

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

/// A table row: MAX_BUCKETS palette words, padded to 16 bytes.
pub const ROW = (MAX_BUCKETS + 3) / 4 * 4; // 152
const LINES = zg.PHYSICAL_HEIGHT;

/// The colour of every bucket of every PHYSICAL row, as the palette word the
/// copper loads: 280 x 152 words = 170,240 B of VRAM, taken by install().
pub var table: *[LINES][ROW]u32 = undefined;
var table_off: u32 = 0; // its region offset, what a PALREF names
var list: []u32 = &.{};

/// A band 0..31 (or BLACK) as its palette word: what the fills store.
pub const ink: [BANDS + 1]u32 = blk: {
    var t: [BANDS + 1]u32 = undefined;
    for (&t, 0..) |*c, i| c.* = if (i == BLACK) A.BLACK_RGBA else A.bar_rgba[i];
    break :blk t;
};

/// The background pattern, painted under everything: plane column x shows
/// bucket x * count / 400, and all the motion is in the palette.
pub var row: [PLANE_W]u8 = undefined;
pub var count: usize = 0;

// A line's record: HEAD (3 body words), FLICK, PALREF(FIRST_BUCKET, count), the row.
const REC = 4;
const LIST_WORDS = LINES * REC + 1;
const PALREF = 0x4000_0000 | @as(u32, A.FIRST_BUCKET) << 20;

/// The table and the list, on the plane openBorders(.all) made overscan: the
/// list replaces its flicker handler (FLICK, at the HBL position the handler
/// was registered at, OVERSCAN_MAGIC_X, which clearing it keeps). Once per
/// cart load (Demo.init). False when VRAM has no room for them.
pub fn install(fb: *zg.LogicalFB) bool {
    const t = zg.vramWords(LINES * ROW) orelse return false;
    list = fb.copperList(LIST_WORDS) orelse return false;
    table = @ptrCast(t.words.ptr);
    table_off = t.off;
    for (table) |*r| @memset(r, A.BLACK_RGBA);
    lit = false;
    for (0..MAX_BUCKETS) |b| fb.palette[A.FIRST_BUCKET + b] = A.BLACK_RGBA;
    for (0..LINES) |y| {
        const at = y * REC;
        list[at] = 0xF000_0000 | @as(u32, @intCast(y)) << 19 | (REC - 1);
        list[at + 1] = 0x3000_0000; // FLICK
        list[at + 3] = table_off + @as(u32, @intCast(y * ROW * 4));
    }
    list[LINES * REC] = 0xF000_0000 | 511 << 19;
    count = 0;
    setCount(1); // ... and PALREF's count
    fb.clearFrameBufferHBLHandler();
    return true;
}

/// The physical rows a frame fills: the content window's 240, or with the top
/// and bottom borders `open` (ZIG mode) all 280, so the bars run on through
/// them from the same u as the window's lines. Closing puts them back to
/// BLACK, once.
pub const Rows = struct { first: usize, n: usize };
var lit = false; // the border rows hold rasters

pub fn rows(open: bool) Rows {
    if (lit and !open) {
        for (table[0..A.CONTENT_Y]) |*r| @memset(r, A.BLACK_RGBA);
        for (table[A.CONTENT_Y + A.CONTENT_H ..]) |*r| @memset(r, A.BLACK_RGBA);
    }
    lit = open;
    if (open) return .{ .first = 0, .n = LINES };
    return .{ .first = A.CONTENT_Y, .n = A.CONTENT_H };
}

/// The ramp's bucket count: the background pattern, and how many entries
/// every line's PALREF loads (a word a line, only when the count changes).
pub fn setCount(n: usize) void {
    if (n == count) return;
    count = n;
    for (&row, 0..) |*p, x| p.* = A.FIRST_BUCKET + @as(u8, @intCast(x * count / PLANE_W));
    const op = PALREF | @as(u32, @intCast(count)) << 12;
    for (0..LINES) |y| list[y * REC + 2] = op;
}
