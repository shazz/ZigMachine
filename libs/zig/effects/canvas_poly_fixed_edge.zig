// --------------------------------------------------------------------------
// canvas_poly_fixed's edge stepper and span writer, shared by its general
// (any path, sorted crossings) and its y-monotone (two chains) fills.
//
// An edge (p0, p1) with p0.y <= sy < p1.y (or the reverse) crosses the sample
// row sy at x = x0 + n/d, n = (sy - y0)(x1 - x0), d = y1 - y0, and the first
// sample at or right of it is
//   k = ceil((x - HALF) / TWO) = ceil((d (x0 - HALF) + n) / (TWO d))   (d > 0)
// (sample 2k + 0.5 canvas px = TWO k + HALF). k is divided out once at the
// edge's first row; each row then adds the whole step (sq) and carries the
// remainder, exactly the numbers a divide per row would give.
// --------------------------------------------------------------------------
const std = @import("std");
const PX = @import("zig3d_fixed_math.zig").PX;
const HALF: i64 = 1 << (PX - 1); // 0.5 canvas px
const TWO: i64 = 2 << PX; // 2 canvas px: one ST pixel

/// One edge over the sample rows [y, end): k = ceil(num / den) on row y, held
/// as k and r = k den - num (0 <= r < den); a row adds step = sq den + sr.
///
/// k and sq are 32-bit and wrap: every k the edge's rows use is within
/// +-2^17 (coordinates within +-2^30, 2^15 to an ST pixel), so the sum taken
/// mod 2^32 is that k exactly even when sq (a nearly flat edge's) or the k
/// past the last row do not fit. Two registers fewer per edge on the rv32
/// cart CPU, and no 64-bit carries in the row loop's k.
pub const Edge = struct {
    y: i32,
    end: i32,
    k: i32,
    sq: i32,
    r: i64,
    sr: i64,
    den: i64,
    dir: i8,

    /// The next row: num += step, so k += sq and r -= sr, carrying one when r < 0.
    pub inline fn step(e: *Edge) void {
        e.k +%= e.sq;
        e.r -= e.sr;
        if (e.r < 0) {
            e.r += e.den;
            e.k +%= 1;
        }
    }
};

/// The edge p0 -> p1 on the rows whose sample it spans, clipped to 0..h;
/// null when it spans none (a horizontal edge spans none).
/// Inline: an Edge returned through memory is eight stores, each a blocking
/// DDR write on the board.
pub inline fn edge(p0: [2]i32, p1: [2]i32, h: i64) ?Edge {
    const down = p0[1] < p1[1];
    const a = if (down) p0 else p1;
    const b = if (down) p1 else p0;
    const y = @max(firstSample(a[1]), 0);
    const end = @min(firstSample(b[1]), h); // exclusive: sample < b.y
    if (y >= end) return null;
    const d: i64 = @as(i64, b[1]) - a[1];
    const dx: i64 = @as(i64, b[0]) - a[0];
    const den = TWO * d;
    const num = (y * TWO + HALF - a[1]) * dx + d * (@as(i64, a[0]) - HALF);
    const k = ceilDiv(num, den);
    // step / den = (TWO dx) / (TWO d): floor(dx / d), in 32 bits when both fit
    // (a 64-bit divide is a libgcc call on the rv32 cart CPU)
    const sq = floorDivFit(dx, d);
    return .{
        .y = @intCast(y),
        .end = @intCast(end),
        .k = @truncate(k),
        .sq = @truncate(sq),
        .r = k * den - num,
        .sr = TWO * (dx - sq * d),
        .den = den,
        .dir = if (down) 1 else -1,
    };
}

/// The first ST index whose sample TWO k + HALF is >= c, unclamped.
pub fn firstSample(c: i32) i64 {
    return ceilDiv(@as(i64, c) - HALF, TWO);
}

/// ceil(a / b) for b > 0.
fn ceilDiv(a: i64, b: i64) i64 {
    return -@divFloor(-a, b);
}

/// floor(a / b) for b > 0, the same number as @divFloor on i64.
fn floorDivFit(a: i64, b: i64) i64 {
    const lo = std.math.minInt(i32);
    const hi = std.math.maxInt(i32);
    if (a >= lo and a <= hi and b <= hi) return @divFloor(@as(i32, @intCast(a)), @as(i32, @intCast(b)));
    return @divFloor(a, b);
}

pub fn clampK(k: i32, limit: i32) usize {
    return @intCast(std.math.clamp(k, 0, limit));
}

/// line[a..b] = ink with aligned 32-bit stores between the odd ends: every
/// store is a blocking DDR write on the board, so four bytes go in one.
pub inline fn span(line: [*]u8, a: usize, b: usize, ink: u8) void {
    var i = a;
    while (i < b and (@intFromPtr(line + i) & 3) != 0) : (i += 1) line[i] = ink;
    const word: u32 = @as(u32, ink) * 0x01010101;
    while (i + 4 <= b) : (i += 4) @as(*u32, @ptrCast(@alignCast(line + i))).* = word;
    while (i < b) : (i += 1) line[i] = ink;
}
