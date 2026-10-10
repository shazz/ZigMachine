// --------------------------------------------------------------------------
// The raster table, filled the way an ST coder would: integers, and the bars
// painted ONCE into a strip that every line then reads, instead of a search
// per bucket.
//
// The CODEF port (fill_f32.zig) asks, for every bucket of every line, which bar
// is nearest at that point: up to 12 bars x 149 buckets x 240 lines, each try a
// float divide and a floor. But the colour at a point depends on one number
// only, u = (x - CX) sin + (y - CY) cos + CY, the position along the axis the
// balls are strung on. So the bars are painted into a strip indexed by u, far
// to near so nearer ones overwrite (the search's answer, with no searching),
// at 1/16 canvas pixel — far finer than a bucket, so no band moves by more
// than a thirty-second of a pixel. Each line is then a walk along the strip from
// its own start, one add and one load a bucket: the raster coder's
// precomputed colour list, read at a per-line offset.
//
// 1/sy comes from the projection for free (balls_fixed.zig), so painting a
// bar is a multiply per strip entry and nothing here divides at all.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const R = @import("rasters.zig");
const A = @import("assets.zig");
const Part = @import("balls_fixed.zig").Part;

const ONE: i32 = 1 << 16;
const HALF_ROWS: i32 = R.BAR_ROWS / 2;
const RES = 4; // the strip has 2^RES entries per canvas pixel
const STEP = 16 - RES; // a Q16 u >> STEP is a strip index

/// The bars along u, 1/16 px an entry; the frame's u span is at most
/// 800 |sin| + 480 |cos| < 934 canvas pixels, so 14,944 entries.
var strip: [16384]u8 = undefined;

/// The colours every scanline of the content window shows this frame.
/// `parts` come far to near.
pub fn build(parts: []const Part, theta: trig.Angle) void {
    const sn = trig.sin(theta);
    const cs = trig.cos(theta);
    R.setCount(bucketCount(@abs(sn), @abs(cs), typicalBand(parts)));
    const width: i32 = @intCast(@divFloor(@as(i64, 2 * R.PLANE_W) << 16, @as(i64, @intCast(R.count))));
    const du = trig.mul(width, sn); // per bucket
    const dy = 2 * cs; // per line
    // plane column 0 of content row 0, as a canvas u: (-2*CONTENT_X + 0.5 - CX)
    // * sin + (0.5 - CY) * cos + CY, the ST row's pixel centre as the port sampled it
    const u_origin = ((1 - 4 * @as(i32, A.CONTENT_X) - 2 * R.CX) * sn + (1 - 2 * R.CY) * cs >> 1) + R.CY * ONE;
    if (du == 0) return horizontal(parts, u_origin, dy);
    // u is linear in the bucket and the line, so its extremes are corners
    const across = @as(i32, @intCast(R.count - 1)) * du;
    const down = @as(i32, A.CONTENT_H - 1) * dy;
    const u_min = u_origin + @min(0, across) + @min(0, down);
    const u_max = u_origin + @max(0, across) + @max(0, down);
    const n: usize = @intCast(((u_max - u_min) >> STEP) + 1);
    @memset(strip[0..n], R.BLACK);
    for (parts) |p| paint(p, u_min, n, du);
    const t = R.table; // one load of the arena pointer, not one a row
    var u_line = u_origin - u_min; // >= 0 on every line and bucket
    for (0..A.CONTENT_H) |y| {
        var u = u_line;
        for (t[A.CONTENT_Y + y][0..R.count]) |*b| {
            b.* = strip[@intCast(u >> STEP)];
            u += du;
        }
        u_line += dy;
    }
}

/// ORIGINAL's bars, theta = 0: every line is ONE colour (one register, the
/// classic raster bar), so each line asks the bars directly, exactly, near to
/// far — twelve multiplies a line, and no strip whose 1/8 px grid could move
/// a band edge onto the neighbouring line.
fn horizontal(parts: []const Part, u_origin: i32, dy: i32) void {
    const t = R.table;
    var u = u_origin;
    for (0..A.CONTENT_H) |y| {
        var ink: u8 = R.BLACK;
        var i = parts.len;
        while (i > 0) {
            i -= 1;
            const row = (trig.mul(parts[i].y - u, parts[i].inv) >> 16) + HALF_ROWS;
            if (row < 0 or row >= R.BAR_ROWS) continue;
            ink = @intCast(row >> 1); // nothing merges when nothing is tilted
            break;
        }
        t[A.CONTENT_Y + y][0] = ink;
        u += dy;
    }
}

/// One bar into the strip: bar.png's row at the centre of every entry it
/// covers, merged as rasters.zig's MERGING says (bands per bucket, round(B/2)).
fn paint(p: Part, u_min: i32, n: usize, du: i32) void {
    var map: [R.BANDS]u8 = undefined;
    const k: u8 = @intCast(@max(1, @min(R.BANDS, (@as(i64, @abs(trig.mul(du, p.inv))) + ONE) >> 17)));
    for (&map, 0..) |*m, band| m.* = @as(u8, @intCast(band)) / k * k;
    // the bar covers |u - y| <= 32 sy; one entry of slack each side, and the
    // row test below decides
    const half = HALF_ROWS * p.sy;
    const lo = @max(0, ((p.y - half - u_min) >> STEP) - 1);
    const hi = @min(@as(i32, @intCast(n)) - 1, ((p.y + half - u_min) >> STEP) + 1);
    var i = lo;
    while (i <= hi) : (i += 1) {
        const u = u_min + (i << STEP) + (1 << (STEP - 1)); // the entry's centre
        // bar.png's row under u, read backwards as the port measured
        const row = (trig.mul(p.y - u, p.inv) >> 16) + HALF_ROWS;
        if (row >= 0 and row < R.BAR_ROWS) strip[@intCast(i)] = map[@intCast(row >> 1)];
    }
}

/// How fine the ramp may be (fill_f32.zig's bucketCount, in Q16): no finer
/// than one band needs, and no finer than a line can rewrite.
fn bucketCount(sin: u32, cos: u32, band: i32) usize {
    const b: i64 = @max(1, band);
    const need = @divFloor(@as(i64, 2 * R.PLANE_W) * sin << 16, b);
    const churn = @min(ONE, @divFloor(@as(i64, 2) * cos << 16, b)); // entries changing per line
    const budget: i64 = if (churn <= 0)
        @as(i64, R.MAX_BUCKETS) << 16
    else
        @divFloor(@as(i64, 2 * R.LINE_CYCLES) << 32, R.CYCLES_PER_ENTRY_X2 * churn);
    const n = (@min(need, budget) + (ONE >> 1)) >> 16;
    return @intCast(@max(1, @min(n, R.MAX_BUCKETS)));
}

/// The mean colour band, Q16 canvas pixels: a bar's 32 bands over 64*sy rows.
fn typicalBand(parts: []const Part) i32 {
    if (parts.len == 0) return 2 * ONE;
    var sum: i32 = 0;
    for (parts) |p| sum += 2 * p.sy;
    return @divFloor(sum, @as(i32, @intCast(parts.len)));
}
