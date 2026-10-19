// --------------------------------------------------------------------------
// The chessboard floor's rows (screen.js damier, 183-216), for scroller.zig.
//
// Floor row y = 2Y - 360 of damierCan is drawn with drawPart(main, -16y,
// 360+y, 0, y*corr, 704, 1, 1, 0, 1+0.04y, 1): source x at canvas x cx is
// floor((cx + 0.5 + 16y) / zoom), the source row floor(y*corr + 0.5). Neither
// depends on the frame: only the board's translation (tx, ty) does. So the
// source x of every box pixel, and each row's source row, are worked out HERE
// at compile time, with the f64 maths the frame used to run (the generator is
// `sourceX` below), and the frame only finds where the 16-pixel checks change
// colour along each row.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");

pub const ROWS = 42; // ST rows 180..221: floor rows y = 0, 2, .. 82 inside the box
pub const W = 352; // the box's width, from ST x 12
const BOX_X = 12;
const FLOOR_W = 704; // drawPart's partw: source x 704 and on is not drawn
const DAMIER_W = 16; // damierWidth: the tile is 32x128, light at (0..15, 0..63) and (16..31, 64..127)
const SHADOW_ROWS = 70; // damierShadow's heights: 4+4+6+6+8+8+10+12+12
/// floor row y comes from source row y*corr, corr walking down from 10
const CORR_START: f64 = 10;
const CORR_STEP: f64 = 0.051;
const ZOOM_STEP: f64 = 0.04;
const NEVER: u16 = 0xFFFF;

/// The source x of box pixel bx on floor row y, as the frame computed it:
/// zoom = 1 + y/25 to within an f64 ulp, so the quotient is the exact rational
/// (4bx + 49 + 32y) * 25 / (2 * (25 + y)); only where that is a whole number
/// can the ulp decide the floor, and there the original f64 expression runs.
fn sourceX(y: u32, bx: u32) u32 {
    const num: u32 = (4 * bx + 49 + 32 * y) * 25;
    const den: u32 = 2 * (25 + y);
    if (num % den != 0) return num / den;
    const fy: f64 = @floatFromInt(y);
    const x0: f64 = 0 - fy * 16;
    const zoom: f64 = 1 + fy * ZOOM_STEP;
    const cx: f64 = @floatFromInt(2 * (bx + BOX_X));
    return @intFromFloat(@floor((cx + 0.5 - x0) / zoom));
}

const Tables = struct {
    ubase: [ROWS]u16, // the source x of the row's first pixel
    first: [ROWS]u16, // where the row's run in `bx_of` starts
    len: [ROWS]u16, // source x ubase + len and on lie past the row's last pixel
    v: [ROWS]i16, // the row's source row floor(y*corr + 0.5)
    /// bx_of[first + (u - ubase)]: the first box pixel whose source x is >= u
    bx_of: [13400]u16,
    used: usize,
};

const tables: Tables = blk: {
    @setEvalBranchQuota(2_000_000);
    var t: Tables = undefined;
    var corr: f64 = CORR_START; // damier()'s float walk, one step per canvas row
    var n: usize = 0;
    for (0..2 * ROWS) |y| {
        if (y % 2 == 0) {
            const k = y / 2;
            const fy: f64 = @floatFromInt(y);
            t.v[k] = @intFromFloat(@floor(fy * corr + 0.5));
            const ubase = sourceX(y, 0);
            const ulast = sourceX(y, W - 1);
            t.ubase[k] = ubase;
            t.first[k] = n;
            t.len[k] = ulast - ubase + 1;
            var bx: u32 = 0;
            for (ubase..ulast + 1) |u| {
                while (sourceX(y, bx) < u) bx += 1;
                t.bx_of[n] = bx;
                n += 1;
            }
        }
        corr -= CORR_STEP;
    }
    t.used = n;
    break :blk t;
};

comptime {
    @setEvalBranchQuota(1_000_000);
    std.debug.assert(tables.used <= tables.bx_of.len);
    // the source x steps at most 2 a pixel: at most one check edge a pixel
    for (0..ROWS) |k| for (1..W) |bx| std.debug.assert(sourceX(2 * k, bx) - sourceX(2 * k, bx - 1) <= 2);
}

/// Paint floor row k (ST row 180 + k) of the box, a word at a time. The check
/// colour flips at every source x u with (u - tx) % 16 == 0; on row 0 alone
/// the board stops at source x 704, where only the shadow is.
pub fn row(k: usize, tx: i32, ty: i32, out: *align(4) [W]u8) void {
    const top_half = ((tables.v[k] - ty) & (8 * DAMIER_W - 1)) < 4 * DAMIER_W;
    const ubase: i32 = tables.ubase[k];
    const len: i32 = tables.len[k];
    const bx_of = tables.bx_of[tables.first[k]..][0..@intCast(len)];
    const left_half = ((ubase - tx) & (2 * DAMIER_W - 1)) < DAMIER_W;
    var c: u32 = if (left_half == top_half) A.CHECK_LIGHT else A.CHECK_DARK;
    const flip: u32 = A.CHECK_LIGHT ^ A.CHECK_DARK;
    // b: the next source x where the colour changes, as an offset from ubase
    var b: i32 = 1 + @mod(tx - ubase - 1, DAMIER_W);
    const end: i32 = @min(len, FLOOR_W - ubase); // the board's end (row 0) or the row's
    var nb: u32 = if (b < end) bx_of[@intCast(b)] else if (end < len) bx_of[@intCast(end)] else NEVER;
    var bx: u32 = 0;
    const words: *[W / 4]u32 = @ptrCast(out);
    for (words) |*w| {
        var word: u32 = 0;
        inline for (0..4) |byte| {
            while (bx == nb) { // a check edge and the board's end can share a pixel
                if (b < end) {
                    c ^= flip;
                    b += DAMIER_W;
                    nb = if (b < end) bx_of[@intCast(b)] else if (end < len) bx_of[@intCast(end)] else NEVER;
                } else {
                    c = if (2 * k < SHADOW_ROWS) A.SHADOW_BARE else 0;
                    nb = NEVER;
                }
            }
            word |= c << (8 * byte);
            bx += 1;
        }
        w.* = word;
    }
}
