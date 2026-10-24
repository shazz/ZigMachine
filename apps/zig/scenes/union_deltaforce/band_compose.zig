// --------------------------------------------------------------------------
// The merge canvas in one pass (band.zig): FX.siny of the text canvas and the
// gold backdrop drawn 'source-atop' over it, fused.
//
// screen.js clears the merge canvas, copies each text column to its sine row
// (1-wide copies), then recolours every merge pixel a letter landed on. Here
// each merge pixel is written ONCE: the rows a column's text lands on take
// COLOUR[gold][level] (a comptime table: 0 where the level is 0, so no branch),
// every other row of the shown columns is 0. Same bytes, about a third of the
// pixels visited, no per-column blit call.
//
// Rows are "logical" (the canvas as screen.js builds it) and "physical" (where
// they are stored): the same unless the view is flipped, which stores logical
// row r at MERGE_ROWS - 1 - r for a draw at scale -1 (band.zig draw).
// --------------------------------------------------------------------------
const std = @import("std");
const blit = @import("zigos").blit;
const A = @import("assets.zig");

pub const MERGE_ROWS = 55;

pub const View = struct { w: usize, strips: [2][]u8, merge: []u8, flip: bool };

/// COLOUR[gold << 4 | level]: A.textColour(gold, level) where a letter landed
/// (level 1..LEVELS), 0 where none did. Gold is 0..6, levels 0..LEVELS (assets.zig);
/// the entries past them are never read.
const COLOUR: [128]u8 = blk: {
    var t: [128]u8 = undefined;
    for (0..8) |g| for (0..16) |l| {
        t[g << 4 | l] = if (l == 0) 0 else if (l > A.LEVELS or g > 6) 0 else A.textColour(g, l);
    };
    break :blk t;
};

inline fn colour(tab: *const [128]u8, gold: u8, level: u8) u8 {
    return tab[@as(usize, gold & 7) << 4 | (level & 15)];
}

/// Where the text canvas lands for a siny of canvas y: its halving, the logical
/// merge row of its row 0, and the logical rows [r0, r1) it covers. A parity-0
/// halving has 16 rows: its strip's last row is never written, so it stays 0 (intro.zig).
const Place = struct { p: u1, top: i32, r0: usize, r1: usize };

fn place(y: i32) Place {
    const p: u1 = @intCast(y & 1);
    const top = @divFloor(y, 2);
    const h: i32 = @intCast(A.GLYPH_ROWS[p]);
    const r0: usize = @intCast(std.math.clamp(top, 0, MERGE_ROWS));
    const r1: usize = @intCast(std.math.clamp(top + h, 0, MERGE_ROWS));
    return .{ .p = p, .top = top, .r0 = r0, .r1 = @max(r0, r1) };
}

/// The physical rows of logical rows [r0, r1).
fn span(flip: bool, at: Place) [2]usize {
    return if (flip) .{ MERGE_ROWS - at.r1, MERGE_ROWS - at.r0 } else .{ at.r0, at.r1 };
}

/// The gold texture row under logical merge row `row`: goldY moves it down by goldY / 2
/// (goldY is even: the texture stays on its 2x grid).
fn goldRow(gold: blit.Image, gold_y: u32, row: usize) usize {
    return ((row + gold.h - gold_y / 2) % gold.h) * gold.w;
}

/// The gold texture by COLUMNS for wave(): a column's text rows walk down the
/// texture, so read along a row-major texture each pixel is a line apart and the
/// 4 KiB direct-mapped D$ thrashes. Column tx holds its h rows top to bottom, then
/// its first MAX_RUN rows again, so a run of rows never wraps. Built once (static art).
pub const GoldCols = struct {
    data: []const u8,
    h: usize,

    pub fn bytes(gold: blit.Image) usize {
        return gold.w * (gold.h + MAX_RUN);
    }

    pub fn build(gold: blit.Image, out: []u8) GoldCols {
        const stride = gold.h + MAX_RUN;
        for (0..gold.w) |tx| for (0..stride) |r| {
            out[tx * stride + r] = gold.data[(r % gold.h) * gold.w + tx];
        };
        return .{ .data = out[0 .. gold.w * stride], .h = gold.h };
    }
};

const MAX_RUN = A.GLYPH_ROWS[1];

/// Columns [c0, c1), one canvas y per column from `sweep.next()`, from text strips
/// stored by columns (band.zig `transposed`: column i's rows at i * MAX_RUN). Returns
/// the physical rows holding text (the union over the columns).
pub fn wave(v: View, sweep: anytype, gold: GoldCols, gold_y: u32, c0: usize, c1: usize) [2]usize {
    if (c1 <= c0) return .{ 0, 0 };
    for (0..MERGE_ROWS) |row| @memset(v.merge[row * v.w ..][c0..c1], 0);
    const gw = gold.data.len / (gold.h + MAX_RUN);
    var lo: usize = MERGE_ROWS;
    var hi: usize = 0;
    var tx = c0 % gw; // the texture column under merge column i, walked
    for (c0..c1) |i| {
        const at = place(sweep.next());
        if (at.r0 < at.r1) {
            const g0 = (at.r0 + gold.h - gold_y / 2) % gold.h; // as goldRow
            const gcol = gold.data[tx * (gold.h + MAX_RUN) + g0 ..];
            if (v.flip) column(v, true, i, at, gcol) else column(v, false, i, at, gcol);
            const s = span(v.flip, at);
            lo = @min(lo, s[0]);
            hi = @max(hi, s[1]);
        }
        tx += 1;
        if (tx == gw) tx = 0;
    }
    return if (hi > lo) .{ lo, hi } else .{ 0, 0 };
}

fn column(v: View, comptime flip: bool, i: usize, at: Place, gcol: []const u8) void {
    const tab = &COLOUR;
    const n = at.r1 - at.r0;
    const k0: usize = @intCast(@as(i32, @intCast(at.r0)) - at.top);
    const scol = v.strips[at.p][i * MAX_RUN + k0 ..][0..n];
    var d: usize = (if (flip) MERGE_ROWS - 1 - at.r0 else at.r0) * v.w + i;
    for (gcol[0..n], scol) |g, l| {
        v.merge[d] = colour(tab, g, l);
        if (flip) d -%= v.w else d += v.w;
    }
}

/// Columns [c0, c1) at one canvas y: the text rows row by row, the rest cleared.
pub fn flat(v: View, y: i32, gold: blit.Image, gold_y: u32, c0: usize, c1: usize) [2]usize {
    if (c1 <= c0) return .{ 0, 0 };
    const at = place(y);
    const s = span(v.flip, at);
    for (0..MERGE_ROWS) |row| {
        if (row < s[0] or row >= s[1]) @memset(v.merge[row * v.w ..][c0..c1], 0);
    }
    if (at.r0 >= at.r1) return .{ 0, 0 };
    const src = v.strips[at.p];
    for (at.r0..at.r1) |r| {
        const k: usize = @intCast(@as(i32, @intCast(r)) - at.top);
        const phys = if (v.flip) MERGE_ROWS - 1 - r else r;
        const tex = gold.data[goldRow(gold, gold_y, r)..][0..gold.w];
        recolourRow(v.merge[phys * v.w ..][0..v.w], src[k * v.w ..][0..v.w], tex, c0, c1);
    }
    return s;
}

/// out[x] = COLOUR[tex[x mod tex.len]][src[x]] for x in [c0, c1), in runs that need no wrap test.
fn recolourRow(out: []u8, src: []const u8, tex: []const u8, c0: usize, c1: usize) void {
    const tab = &COLOUR;
    var x = c0;
    var tx = c0 % tex.len;
    while (x < c1) {
        const n = @min(c1 - x, tex.len - tx);
        for (out[x..][0..n], src[x..][0..n], tex[tx..][0..n]) |*o, l, g| o.* = colour(tab, g, l);
        x += n;
        tx = 0;
    }
}
