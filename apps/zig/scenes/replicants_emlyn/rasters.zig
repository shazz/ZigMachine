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
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const c3 = zg.zig3d;
const A = @import("assets.zig");

const PLANE_W: usize = zg.PHYSICAL_WIDTH; // 400: the ramp covers the side borders too
const PLANE_WF: f64 = PLANE_W;
const CX = 320.0; // the canvas centre, where the group's origin projects
const CY = 240.0;
const BAR_ROWS = 64; // bar.png's source rows; the halved table has BANDS
const BANDS = 32;
const BLACK = BANDS; // the 33rd ink: no bar over this point

pub const MAX_BUCKETS = 256 - @as(usize, A.FIRST_BUCKET); // 149, what the palette has left
const LINE_CYCLES = 400.0; // an open line displays 400 pixels, one a cycle
const CYCLES_PER_ENTRY = 4.5; // movem.l d0-d7,(a0): 72 cycles, 16 registers

/// The ink of every bucket of every PHYSICAL row: a band 0..31, or BLACK.
/// Scene-scope, so it weighs this cart only.
var table: [zg.PHYSICAL_HEIGHT][MAX_BUCKETS]u8 = undefined;
var ink: [BANDS + 1]u32 = undefined;
/// The background pattern, painted under everything: plane column x shows
/// bucket x * count / 400, and all the motion is in the palette.
pub var row: [PLANE_W]u8 = undefined;
var count: usize = 0;
/// Bands that fall inside one bucket, per particle (see MERGING).
var merge: [16]usize = undefined;

/// Replace openBorders()'s handler with one that ALSO opens the borders: the
/// machine gives a plane one HBL, and this screen needs both.
pub fn install(fb: *zg.LogicalFB) void {
    for (&ink, 0..) |*c, i| c.* = if (i == BLACK) A.BLACK_RGBA else A.bar_rgba[i];
    for (&table) |*r| @memset(r, BLACK);
    for (0..MAX_BUCKETS) |b| fb.palette[A.FIRST_BUCKET + b] = A.BLACK_RGBA;
    setCount(1);
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

/// This plane is OVERSCAN, so `line` is PHYSICAL 0..279 (machine/video.zig's
/// renderPlaneOverscan) — the table is indexed by it directly.
fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    // zigos's flickerAllHbl, which openBorders(.all) installed and this handler
    // replaces: EVERY line, so the sides reopen on the visible ones and the
    // rasters run edge to edge. That per-line cost is the trick's real price.
    fb.flickerBorder();
    if (line >= zg.PHYSICAL_HEIGHT) return;
    for (table[line][0..count], 0..) |b, i| fb.palette[A.FIRST_BUCKET + i] = ink[b];
}

/// The colours every scanline of the content window shows this frame.
/// `particles` come back from projectParticles far to near.
pub fn build(particles: []const c3.Particle, theta: f64) void {
    const sin = @sin(theta);
    const cos = @cos(theta);
    const band = typicalBand(particles); // one colour band, in canvas pixels
    setCount(bucketCount(@abs(sin), @abs(cos), band));
    const width = 2.0 * PLANE_WF / @as(f64, @floatFromInt(count)); // a bucket, in canvas pixels
    setMerge(particles, @abs(width * sin));
    const du = width * sin;
    for (0..A.CONTENT_H) |y| {
        // the ST row's canvas pixel centre, as the sprite port sampled it
        const yc = 2.0 * @as(f64, @floatFromInt(y)) + 0.5;
        // plane column 0 is CONTENT_X to the left of canvas 0
        var u = (-2.0 * @as(f64, A.CONTENT_X) + 0.5 - CX) * sin + (yc - CY) * cos + CY;
        for (table[A.CONTENT_Y + y][0..count]) |*b| {
            b.* = inkAt(particles, u);
            u += du;
        }
    }
}

/// How fine the ramp may be: no finer than one band needs (there is nothing to
/// show between two), and no finer than a line can rewrite.
fn bucketCount(sin: f64, cos: f64, band: f64) usize {
    const need = 2.0 * PLANE_WF * sin / band;
    const churn = @min(1.0, 2.0 * cos / band); // entries changing per line
    const budget = if (churn <= 0) @as(f64, MAX_BUCKETS) else LINE_CYCLES / (CYCLES_PER_ENTRY * churn);
    return @intFromFloat(std.math.clamp(@round(@min(need, budget)), 1, MAX_BUCKETS));
}

fn setCount(n: usize) void {
    if (n == count) return;
    count = n;
    for (&row, 0..) |*p, x| p.* = A.FIRST_BUCKET + @as(u8, @intCast(x * count / PLANE_W));
}

/// The mean colour band, in canvas pixels: a bar's 32 bands over 64*sy rows.
fn typicalBand(particles: []const c3.Particle) f64 {
    if (particles.len == 0) return 2.0;
    var sum: f64 = 0;
    for (particles) |p| sum += 2.0 * p.sy;
    return sum / @as(f64, @floatFromInt(particles.len));
}

fn setMerge(particles: []const c3.Particle, step: f64) void {
    for (particles, 0..) |p, i| {
        const k = @round(step / (2.0 * p.sy));
        merge[i] = if (k < 1) 1 else @intFromFloat(k);
    }
}

/// The nearest bar covering `u` wins, so scan near to far and stop at the first:
/// the far-to-near painting order with no painting.
fn inkAt(particles: []const c3.Particle, u: f64) u8 {
    var i = particles.len;
    while (i > 0) {
        i -= 1;
        const p = particles[i];
        // bar.png's row under u. The CanvasRenderer never undoes its y flip for
        // a ParticleCanvasMaterial, so the table reads backwards — measured
        // against the browser, and kept.
        const r = @floor((p.y - u) / p.sy) + BAR_ROWS / 2;
        if (r < 0 or r >= BAR_ROWS) continue;
        const m = @as(usize, @intFromFloat(r)) / 2;
        return @intCast(m / merge[i] * merge[i]);
    }
    return BLACK;
}
