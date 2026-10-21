// --------------------------------------------------------------------------
// ZIG's key 3: the ramp held to SIXTEEN palette changes a line.
//
// The full gradient is sized on the ST's movem (rasters.zig: up to 88 entries
// a line). The board's FRESCO snoops palette writes through a 16-entry queue
// per HBL, and every write past it costs (apps/perf/cost_model.mjs). So this
// ramp is sized on 16 instead: buckets() picks the finest ramp whose lines
// NEED about 16 changes, counting how the coarser buckets merge their bands
// (rasters.zig: MERGING), which is also what keeps the bars reading as solid,
// continuous ramps rather than aliasing. Integers, from bucketCount()'s own
// numbers (the f32 cart: the same formula in f32).
//
// "About" is not "at most", so the HBL also holds the line to 16 writes, as a
// raster coder with a fixed budget would: what does not fit is written on the
// next line (the entry shows one line late, never a wrong colour for longer).
// While such a debt is owed the palette is no longer the line above, so that
// line compares against the palette itself instead of the table row above.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const R = @import("rasters.zig");

pub const LIMIT = 16; // palette writes a line: FRESCO's snoop queue
pub const AIM = 8; // the ramp is sized for this many a line on average

/// The capped ramp's bucket count, Q16, from bucketCount()'s own numbers:
/// `need` (buckets one band each would take) and `churn` (the share of
/// buckets a line moves across a band, Q16). At `need` or more buckets a band
/// spans a bucket at most, a line changes count * churn of them, and the
/// count is LIMIT / churn. Below `need`, MERGING widens every colour group to
/// a bucket, so a bucket changes with churn * count / need, a line changes
/// count^2 * churn / need of them, and the count is sqrt(LIMIT / churn * need).
pub fn buckets(need: i64, churn: i64) i64 {
    const lone = @divFloor(@as(i64, AIM) << 32, churn); // AIM / churn, Q16
    if (lone >= need) return need;
    return @intCast(std.math.sqrt(@as(u64, @intCast(lone * need)))); // Q32 -> Q16
}

/// buckets() for the f32 cart, the same formula in its numbers.
pub fn bucketsF32(need: f32, churn: f32) f32 {
    const lone = AIM / churn;
    return if (lone >= need) need else @sqrt(lone * need);
}

/// The capped ramp is on (motion.zig sets it every frame, before the fill).
pub var on = false;
/// Some entry of the line above was not written: the palette lags the table.
var debt = false;

/// Line 0 starts square: loadFirstLine() wrote it whole before the beam.
pub fn reset() void {
    debt = false;
}

/// One line's writes, at most LIMIT of them.
pub fn line(fb: *zg.LogicalFB, y: usize) void {
    const pal = fb.palette + A.FIRST_BUCKET;
    const now: *const [R.ROW]u8 = &R.table[y];
    var left: usize = LIMIT;
    if (debt) {
        // the palette is the truth: every entry that differs from this line
        for (now[0..R.count], 0..) |b, i| {
            if (pal[i] == R.ink[b]) continue;
            if (left == 0) return; // still owed: debt stays set
            pal[i] = R.ink[b];
            left -= 1;
        }
        debt = false;
        return;
    }
    const was: *const [R.ROW]u8 = &R.table[y - 1];
    const now_w: *const [R.WORDS]u32 = @ptrCast(@alignCast(now));
    const was_w: *const [R.WORDS]u32 = @ptrCast(@alignCast(was));
    for (0..(R.count + 3) / 4) |w| {
        if (now_w[w] == was_w[w]) continue;
        for (w * 4..@min(w * 4 + 4, R.count)) |i| {
            if (now[i] == was[i]) continue;
            if (left == 0) {
                debt = true;
                return;
            }
            pal[i] = R.ink[now[i]];
            left -= 1;
        }
    }
}
