// --------------------------------------------------------------------------
// CUDDLY STARWARS — one perspective draw (a motion.PerspectiveRow) walked column by
// column: the alpha its stretched text row puts on each screen column of its band row.
//
// The text canvas's pair codes (swtext.zig) give both bilinear taps of a row in one byte
// load; with the lower row's code shifted by 2, q is the column's 4-bit tap pattern.
// When both taps of each row agree (q = 0, 3, 12, 15) the alpha is a per-draw constant;
// only the other codes (ink edges) need the tx-weighted blend.
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const motion = @import("motion.zig");
const fixed = @import("fixed.zig");
const text = @import("swtext.zig");
const assert = std.debug.assert;

const W: usize = zg.WIDTH;
const ONE = fixed.ONE;

comptime {
    // every column x_first .. x_last samples xi and xi + 1 with a pair code (xi = -1 .. 319),
    // and both rows of the pair are view rows
    for (motion.perspective) |p| {
        assert((p.fx_base + p.fx_step * @as(i64, p.x_first)) >> 24 >= -1);
        assert((p.fx_base + p.fx_step * @as(i64, p.x_last)) >> 24 <= W - 1);
        assert(p.src_row >= 0 and p.src_row + 1 < motion.TEXT_ROWS);
        assert(p.step_i >= 0);
    }
}

const BY_TX = std.math.maxInt(u32); // never an alpha (<= ONE)

pub const Stepper = struct {
    up: *const [text.STRIDE]u8,
    lo: *const [text.STRIDE]u8,
    // The Q24 source x is walked as ci = xi + 1 (the pair-code index) + a 24-bit fraction
    // fr (carry on overflow): 32-bit only (a wasm i64 op is a libcall on ZIGGY).
    ci: u32,
    fr: u32,
    step_i: u32,
    step_f: u32,
    p: motion.PerspectiveRow,
    k: [16]u32, // alpha by tap pattern, or BY_TX
    start: usize, // the columns start .. end - 1 can be inked; every other is alpha 0
    end: usize,

    /// false when the draw puts no ink on any column (start == end).
    pub fn init(self: *Stepper, p: motion.PerspectiveRow) bool {
        if (!text.rowInked(p.src_row) and !text.rowInked(p.src_row + 1)) return false;
        const ink = text.inkSpan(p.src_row);
        self.start = firstInkedColumn(p, ink.left);
        self.end = columnsEnd(p, ink.right, self.start);
        if (self.start >= self.end) return false;
        self.p = p;
        self.up = text.codes(p.src_row);
        self.lo = text.codes(p.src_row + 1);
        const fx0: i64 = p.fx_base + p.fx_step * @as(i64, @intCast(self.start));
        self.ci = @intCast((fx0 >> 24) + 1);
        self.fr = @intCast(fx0 & 0xffffff);
        self.step_i = @intCast(p.step_i);
        self.step_f = p.step_f;
        self.k = [_]u32{BY_TX} ** 16;
        self.k[0] = 0;
        self.k[3] = alphaOf(p, ONE, 0);
        self.k[12] = alphaOf(p, 0, ONE);
        self.k[15] = alphaOf(p, ONE, ONE);
        return true;
    }

    /// The alpha on the current column, then one column on.
    pub inline fn next(self: *Stepper) u32 {
        const q: u32 = self.up[self.ci] | (@as(u32, self.lo[self.ci]) << 2);
        const tx: u32 = self.fr >> 8;
        self.fr += self.step_f;
        self.ci += self.step_i + (self.fr >> 24);
        self.fr &= 0xffffff;
        const a = self.k[q];
        if (a != BY_TX) return a;
        const tl = ONE - tx; // the taps differ along x: the bilinear weights matter
        return alphaOf(self.p, (tl & mask(q, 1)) + (tx & mask(q, 2)), (tl & mask(q, 4)) + (tx & mask(q, 8)));
    }
};

/// The draw's alpha over a column whose rows sample `upper` and `lower` (Q16).
inline fn alphaOf(p: motion.PerspectiveRow, upper: u32, lower: u32) u32 {
    const mix = mulShr16(upper, ONE - p.sf, lower, p.sf);
    return if (mix == ONE and p.cov == ONE) ONE else (mix * p.cov) >> 16;
}

/// All ones when bit `b` of q is set, else 0.
inline fn mask(q: u32, comptime b: u32) u32 {
    return 0 -% @as(u32, @intFromBool(q & b != 0));
}

/// The first screen column of `p` worth sampling: every column before it reads
/// columns xi, xi+1 both left of `ink_left`, so its alpha is exactly 0. The
/// inverse stretch is only a guess; it is kept only if the column just before
/// it really does sample clear of the ink, otherwise the scan starts at x_first.
fn firstInkedColumn(p: motion.PerspectiveRow, ink_left: i32) usize {
    const first: usize = p.x_first;
    // (ink_left - 1 + 0.5 - 160) * zoom + 160 - 0.5 - 2, Q16
    const guess = @divTrunc((2 * @as(i64, ink_left) - 321) * p.zoom_q16, 2) + 10321920;
    if (guess < (@as(i64, @intCast(first)) + 1) * ONE) return first;
    const start: usize = @intCast(guess >> 16);
    const xi_before = (p.fx_base + p.fx_step * @as(i64, @intCast(start - 1))) >> 24;
    return if (xi_before + 1 < ink_left) start else first;
}

/// One past the last screen column of `p` worth sampling: from it on, xi > `ink_right`
/// (sourceX never decreases with x), so both taps are right of the ink. Again a guess
/// of the inverse stretch, kept only when that column really samples clear; otherwise
/// x_last + 1 (the old scan's early break found the same columns, one test a column).
fn columnsEnd(p: motion.PerspectiveRow, ink_right: i32, start: usize) usize {
    const last: usize = @as(usize, p.x_last) + 1;
    // (ink_right + 1 - 159.5) * zoom + 159.5, Q16, then 2 columns of slack
    const guess = @divTrunc((2 * @as(i64, ink_right) - 317) * p.zoom_q16, 2) + 10452992;
    if (guess < 0) return last;
    const e: usize = @max(start, @as(usize, @intCast(guess >> 16)) + 2);
    if (e >= last) return last;
    const xi = (p.fx_base + p.fx_step * @as(i64, @intCast(e))) >> 24;
    return if (xi > ink_right) e else last;
}

/// (a * wa + b * wb) >> 16 for Q16 a, b <= 65536 and weights wa + wb = 65536, in u32:
/// the sum is a weighted mean times 65536, so it reaches 2^32 only for a = b = 65536
/// (wrapped to 0 here, hence the fix-up). Bit-identical to the u64 form.
fn mulShr16(a: u32, wa: u32, b: u32, wb: u32) u32 {
    const sum = a *% wa +% b *% wb;
    if (sum == 0 and a == ONE) return ONE;
    return sum >> 16;
}
