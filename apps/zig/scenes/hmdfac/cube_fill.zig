// --------------------------------------------------------------------------
// The cube's solid face fill, as the original's two routines do it (RAM
// addresses at load base $aa9a; subtract it for the depacked offset):
//   * $1047e, one edge into a per-row x table: an edge whose second vertex is
//     lower goes to the LEFT table, else it is turned round into the RIGHT
//     one; clipped to rows 0..199 with divs.w; x is kept *8 and stepped in a
//     split 16.16 register by addx.l, so the 68k's X flag and the low word's
//     carry into the fraction are part of the result (X starts at 1: the
//     neg.w d7 before the jump into the unrolled loop sets it);
//   * $bc08, the span fill: rows [ymin, ymax), pixels [left, right) — left
//     inclusive, right exclusive (the $cc5e/$ea5e mask tables) — and a row
//     whose right 16-pixel group lies before its left one ends the face.
// Both tables persist across faces and frames, as the machine's do.
// Checked pixel for pixel against four of the original's drawn pages
// (apps/hmdfac_original.json). All integer.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

pub const ROWS = 200; // the original clips the cube to page rows 0..199
const LAST = 199;

pub const Tables = struct { l: [ROWS]i16 = [_]i16{0} ** ROWS, r: [ROWS]i16 = [_]i16{0} ** ROWS };

pub fn s16(v: i64) i16 {
    return @bitCast(@as(u16, @truncate(@as(u64, @bitCast(v)))));
}

/// divs.w: the quotient truncates; a zero divisor or an out-of-range
/// quotient leaves the destination register (the dividend) untouched.
pub fn divs(a: i64, b: i64) struct { v: i64, ok: bool } {
    if (b == 0) return .{ .v = a, .ok = false };
    const q = @divTrunc(a, b);
    if (q < -32768 or q > 32767) return .{ .v = a, .ok = false };
    return .{ .v = q, .ok = true };
}

/// $1047e for (d0,d1) = vertex b, (d2,d3) = vertex a.
pub fn edge(t: *Tables, bx: i32, by: i32, ax: i32, ay: i32) void {
    var x0: i64 = bx;
    var y0: i64 = by;
    var x1: i64 = ax;
    var y1: i64 = ay;
    if (y1 == y0) return;
    var rows: *[ROWS]i16 = &t.l;
    if (y1 < y0) {
        std.mem.swap(i64, &x0, &x1);
        std.mem.swap(i64, &y0, &y1);
        rows = &t.r;
    }
    if (y0 > LAST) return;
    if (y0 < 0) {
        if (y1 < 0) return;
        x0 = s16(-(@as(i64, s16(divs((x1 - x0) * y1, y1 - y0).v)) - x1));
        y0 = 0;
    }
    if (y1 >= LAST) {
        x1 = s16(divs((x1 - x0) * (LAST - y0), y1 - y0).v + x0);
        y1 = LAST;
    }
    step(rows, s16(x0 * 8), s16(x1 * 8), @intCast(y0), @intCast(y1));
}

/// The x*8 walk down rows [y0, y1): the slope is (dx*8 << 5) / dy, sign
/// extended and shifted to 16.16 (a divs overflow keeps the dividend).
fn step(rows: *[ROWS]i16, x0: i16, x1: i16, y0: usize, y1: usize) void {
    const dx: i64 = s16(@as(i64, x1) - x0);
    if (y1 <= y0) return;
    const q = divs(dx << 5, @intCast(y1 - y0));
    const d4: u32 = @bitCast(@as(i32, s16(q.v)) *% 2048);
    const frac: u32 = d4 & 0xffff;
    const ip: u32 = d4 >> 16;
    if (frac == 0) {
        var v: i16 = x0;
        for (y0..y1) |y| {
            rows[y] = v;
            v +%= @bitCast(@as(u16, @truncate(ip)));
        }
        return;
    }
    var d0: u32 = (((frac + 0x8000) & 0xffff) << 16) | @as(u16, @bitCast(x0));
    const add: u32 = (frac << 16) | ip;
    var x: u64 = 1; // neg.w d7 set X
    for (y0..y1) |y| {
        rows[y] = @bitCast(@as(u16, @truncate(d0)));
        const r = @as(u64, d0) + add + x;
        x = r >> 32;
        d0 = @truncate(r);
    }
}

/// $bc08 over rows [ylo, yhi) of `d` (the plate) in ink `col`; returns the
/// rows written, lo > hi = none. x is clamped to the plate (the original
/// never needs it: its vertices stay on screen).
pub fn fill(d: blit.Dst, t: *const Tables, ylo_in: i32, yhi_in: i32, col: u8) [2]i32 {
    const ylo = @max(ylo_in, 0);
    if (ylo > LAST - 1 or yhi_in < 1) return .{ 0, -1 };
    const yhi = @min(yhi_in, LAST);
    var y = ylo;
    while (y < yhi) : (y += 1) {
        const i: usize = @intCast(y);
        const xl: i32 = t.l[i] >> 3;
        const xr: i32 = t.r[i] >> 3;
        if ((xr >> 4) < (xl >> 4)) return .{ ylo, y - 1 };
        const a = @max(xl, 0);
        const b = @min(xr, @as(i32, @intCast(d.w)));
        if (b > a) d.fill(a, y, @intCast(b - a), 1, col);
    }
    return .{ ylo, yhi - 1 };
}
