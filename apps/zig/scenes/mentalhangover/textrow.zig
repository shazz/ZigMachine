// --------------------------------------------------------------------------
// The text's even-odd fill, one canvas row at a time, as a 352-bit mask.
//
// The production fills all eight glyphs in one Ebiten FillRuleEvenOdd batch;
// the first port tested every pixel of each glyph's box against every edge
// (a 64-bit inside() per pixel).  This is the same test turned around: each
// edge that crosses the row's pixel-centre line gives ONE integer threshold t
// (pixel x counts the crossing iff x < t, exactly inside()'s
// `xc2 * den < 2 * num`), so a glyph's mask over its clamped box [lo, hi] is
// parity(n) ^ parity(#{t <= x}).  That is a handful of toggle bits; the row
// mask is their prefix XOR.  The glyph masks XOR together (toggles XOR into
// one bitmap), so overlapping contours and glyphs cancel exactly as before.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const clockmod = @import("clock.zig");

pub const CANVAS_W: usize = 352;
pub const WORDS: usize = CANVAS_W / 32; // 11
pub const Row = [WORDS]u32;

const Path = struct {
    ncont: u8,
    npts: [A.MAX_CONTOURS]u8,
    pts: [A.MAX_CONTOURS][A.MAX_POINTS][2]i16,
    xmin: i32,
    xmax: i32,
    ymin: i32,
    ymax: i32,
    narrow: bool,
};

/// |x|, |y| <= NARROW and sy in 8..207 keep inside()'s products in an i32:
/// |2*num| <= 2*(2*4096*8192 + 8607*8192) < 2^31.
const NARROW: i32 = 4096;

var paths: [clockmod.SLOTS]Path = undefined;

/// Map the eight visible glyphs once a frame.  A letter outside 32..90 (only a
/// space can occur) is blank.
pub fn prepare(c: *const clockmod.Clock) void {
    for (0..clockmod.SLOTS) |slot| {
        const p = &paths[slot];
        p.ncont = 0;
        const ch = c.letters[slot];
        if (ch < 32 or ch > 90) continue;
        const g: usize = ch - 32;
        const gs: usize = A.TABLE.glyph_start[g];
        const gc: usize = A.TABLE.glyph_count[g];
        p.ncont = @intCast(gc);
        p.narrow = true;
        p.xmin = 0;
        p.xmax = -1;
        p.ymin = 0;
        p.ymax = -1;
        var first = true;
        for (0..gc) |ci| {
            const k = gs + ci;
            const start: usize = A.TABLE.contour_start[k];
            const n: usize = A.TABLE.contour_count[k];
            p.npts[ci] = @intCast(n);
            for (0..n) |pi| {
                const q = c.point(slot, A.TABLE.points[start + pi]);
                p.pts[ci][pi] = .{ q.x, q.y };
                if (@abs(q.x) > NARROW or @abs(q.y) > NARROW) p.narrow = false;
                if (first) {
                    p.xmin = q.x;
                    p.xmax = q.x;
                    p.ymin = q.y;
                    p.ymax = q.y;
                    first = false;
                } else {
                    p.xmin = @min(p.xmin, q.x);
                    p.xmax = @max(p.xmax, q.x);
                    p.ymin = @min(p.ymin, q.y);
                    p.ymax = @max(p.ymax, q.y);
                }
            }
        }
    }
}

/// Smallest integer x with (2x+1)*den >= 2*num (den > 0): the first pixel
/// whose centre is at or right of the crossing.
fn threshold(comptime T: type, num: T, den: T) i32 {
    const a = 2 * num - den;
    const b = 2 * den;
    return @intCast(@divFloor(a + b - 1, b));
}

inline fn toggle(out: *Row, x: i32) void {
    const ux: u32 = @intCast(x);
    out[ux >> 5] ^= @as(u32, 1) << @intCast(ux & 31);
}

/// One glyph's toggles for the row whose pixel centres are at yc2/2.
/// T is i32 when every point of the glyph is within +-NARROW (always, on this
/// screen: |x|, |y| < 800), so no product below can leave an i32; i64 otherwise.
fn glyphToggles(comptime T: type, p: *const Path, yc2: T, out: *Row) void {
    var ts: [2 * A.MAX_POINTS]i32 = undefined;
    var nt: usize = 0;
    var ci: usize = 0;
    while (ci < @as(usize, p.ncont)) : (ci += 1) {
        const n: usize = p.npts[ci];
        if (n < 3) continue;
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const a = p.pts[ci][i - 1];
            const b = p.pts[ci][i];
            const y1: T = a[1];
            const y2: T = b[1];
            if ((2 * y1 > yc2) == (2 * y2 > yc2)) continue;
            const x1: T = a[0];
            const dx = @as(T, b[0]) - x1;
            const dy = y2 - y1;
            var num = 2 * x1 * dy + (yc2 - 2 * y1) * dx;
            var den = 2 * dy;
            if (den < 0) {
                num = -num;
                den = -den;
            }
            ts[nt] = threshold(T, num, den);
            nt += 1;
        }
    }
    const lo: i32 = @max(p.xmin, 0);
    const hi: i32 = @min(p.xmax, @as(i32, CANVAS_W) - 1);
    if (lo > hi) return;
    var le_lo: u32 = 0;
    var le_hi: u32 = 0;
    for (ts[0..nt]) |t| {
        if (t <= lo) le_lo += 1;
        if (t <= hi) le_hi += 1;
        if (t > lo and t <= hi) toggle(out, t);
    }
    const n_odd: u32 = @intCast(nt & 1);
    if ((n_odd ^ le_lo) & 1 != 0) toggle(out, lo);
    if ((n_odd ^ le_hi) & 1 != 0 and hi + 1 < @as(i32, CANVAS_W)) toggle(out, hi + 1);
}

/// The XORed glyph mask of source row sy into `out` (bit x = pixel x).
/// Returns false, leaving `out` untouched, when no glyph spans the row.
pub fn build(sy: i32, out: *Row) bool {
    var any = false;
    for (0..clockmod.SLOTS) |slot| {
        const p = &paths[slot];
        if (p.ncont == 0 or sy < p.ymin or sy > p.ymax) continue;
        if (!any) {
            out.* = @splat(0);
            any = true;
        }
        if (p.narrow) glyphToggles(i32, p, 2 * sy + 1, out) else glyphToggles(i64, p, 2 * @as(i64, sy) + 1, out);
    }
    if (!any) return false;
    var carry: u32 = 0;
    for (out) |*w| {
        var m = w.*;
        m ^= m << 1;
        m ^= m << 2;
        m ^= m << 4;
        m ^= m << 8;
        m ^= m << 16;
        m ^= carry;
        carry = if (m >> 31 != 0) 0xFFFF_FFFF else 0;
        w.* = m;
    }
    return true;
}
