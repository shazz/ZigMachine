// --------------------------------------------------------------------------
// drawScroller: each of the first 160 slices is a 2-pixel column of its
// glyph's rotation frame, 33 rows of the filmstrip, drawn at
//
//   y = 67 + (t2 > 5*50 - i*0.0033 ? 80*cos(5*10.50 + t2/6) : 80)
//   t2 = t + i/6,  t = 0.30 a frame
//
// into cnvScroller, which lands on the canvas at y 156 with zoom (2, 1.5).
// So a slice is 4 canvas columns wide and the filmstrip is 24-25 port lines.
//
// Integer form: t2 in thirtieths is T = 9n + 5i, the threshold is
// 1000T > 7500000 - 99i (exact), and the angle 52.5 + T/180 rad is a fixtrig
// angle accumulated in 48-bit turns. The filmstrip itself is never stored
// (45 glyphs x 30 frames x 16 x 33 would be 700 KB): each pixel is the
// silver front if the glyph has ink there, else the red bar on rows 12..20,
// else the purple back, else the panel, which is cnvFrames' paint order.
//
// Only what moved is stored: each column remembers the lines it painted, and
// a frame clears just the lines it leaves, then paints the strip.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const G = @import("geom.zig");
const A = @import("assets.zig");
const T = @import("tables.zig");
const dna = @import("dna.zig");

const TURN48: f64 = 281474976710656.0; // 2^48
/// One thirtieth of t2 is 1/180 rad of the cosine.
const UNIT48: u64 = @intFromFloat(@round(TURN48 / (360.0 * std.math.pi)));
const PHASE48: u64 = @intFromFloat(@round(@mod(52.5 / (2.0 * std.math.pi), 1.0) * TURN48));
const MASK48: u64 = (1 << 48) - 1;

pub var lo: [G.COLUMNS]u8 = undefined; // lines each column painted: [lo, hi)
pub var hi: [G.COLUMNS]u8 = undefined;
pub var top_q16: [G.COLUMNS]i32 = undefined; // the strip's top in cnvScroller rows, Q16 (for the harness)
var sig: [G.COLUMNS]u32 = undefined; // glyph | frame << 8 | slice << 16 as last painted

pub fn reset() void {
    @memset(&lo, 0);
    @memset(&hi, 0);
    @memset(&top_q16, 0);
    @memset(&sig, 0xFFFF_FFFF);
}

/// The strip top of slice i at main frame n (t = 0.3n), cnvScroller rows Q16.
pub fn stripTop(n: u32, i: usize) i32 {
    const t2: i64 = 9 * @as(i64, n) + 5 * @as(i64, @intCast(i));
    const ii: i64 = @intCast(i);
    if (1000 * t2 <= 7_500_000 - 99 * ii) return (67 + 80) << 16;
    const a48 = (PHASE48 +% @as(u64, @intCast(t2)) *% UNIT48) & MASK48;
    const c = zg.fixtrig.cos(@truncate(a48 >> 16));
    return (67 << 16) + 80 * c;
}

/// The filmstrip row content line r shows for a strip at `top`, Q16 (floor).
inline fn stripRow(r: usize, top: i32) i32 {
    return ((@as(i32, T.SCROLL_ROW[r]) << 16) + 32768 - top) >> 16;
}

/// The first line whose filmstrip row is >= 0: SCROLL_ROW[r] >= ceil(top - 0.5),
/// and floor((4r - 310) / 3) >= b exactly when 4r >= 3b + 310.
fn firstLine(top: i32) usize {
    const b = -((32768 - top) >> 16);
    const r = @divFloor(3 * b + 310 + 3, 4);
    return @intCast(std.math.clamp(r, @as(i32, G.SCROLL_TOP), @as(i32, G.SCROLL_END)));
}

/// cnvFrames' pixel: glyph g, frame f, filmstrip row r, glyph column x.
inline fn pixel(g: u8, f: usize, r: usize, x: u4) u8 {
    const sr = T.SROW[f][r];
    if (sr >= 0 and (A.FONT[g][@intCast(sr)] >> x) & 1 != 0) return G.SILVER + @as(u8, @intCast(r));
    if (r >= G.RED_ROW0 and r < G.RED_ROW0 + G.RED_ROWS) return G.RED + @as(u8, @intCast(r - G.RED_ROW0));
    const pr = T.PROW[f][r];
    if (pr >= 0 and (A.FONT[g][@intCast(pr)] >> x) & 1 != 0) return G.PURPLE + @as(u8, @intCast(r));
    return G.PANEL;
}

inline fn quad(a: u8, b: u8) u32 {
    const aa: u32 = @as(u32, a) * 0x0101;
    const bb: u32 = @as(u32, b) * 0x0101;
    return aa | (bb << 16);
}

const PANEL4: u32 = @as(u32, G.PANEL) * 0x0101_0101;

/// Paint the 160 columns for main frame n. `rect_w` is the reveal quad's width
/// in canvas pixels (0 once it has gone): columns under it stop at RECT_TOP.
pub fn draw(fb: *zg.LogicalFB, n: u32, rect_w: i32) void {
    const px: [*]u32 = @ptrCast(@alignCast(fb.fb));
    for (0..G.COLUMNS) |i| {
        const top = stripTop(n, i);
        var r0: usize = firstLine(top);
        var r1: usize = r0;
        while (r1 < G.SCROLL_END and stripRow(r1, top) < G.STRIP_ROWS) r1 += 1;
        if (@as(i32, @intCast(4 * i)) < rect_w) {
            r1 = @min(r1, G.RECT_TOP);
            r0 = @min(r0, r1);
        }
        const k = dna.cell(i);
        const g = dna.chr[k];
        const f: usize = @intCast(@divTrunc(dna.frm[k], dna.ONE));
        const s: u32 = @as(u32, g) | (@as(u32, @intCast(f)) << 8) | (@as(u32, dna.slc[k]) << 16);
        // Nothing moved (the strip parked before the wave, a pause): no stores.
        if (top == top_q16[i] and s == sig[i] and r0 == lo[i] and r1 == hi[i]) continue;
        top_q16[i] = top;
        sig[i] = s;
        const word = (G.at(4 * i, 0)) / 4;
        // clear the lines this column leaves
        var r: usize = lo[i];
        while (r < hi[i]) : (r += 1) {
            if (r < r0 or r >= r1) px[word + r * (G.STRIDE / 4)] = PANEL4;
        }
        const x0: u4 = @intCast(dna.slc[k] * 2);
        r = r0;
        while (r < r1) : (r += 1) {
            const row: usize = @intCast(stripRow(r, top));
            px[word + r * (G.STRIDE / 4)] = quad(pixel(g, f, row, x0), pixel(g, f, row, x0 + 1));
        }
        lo[i] = @intCast(r0);
        hi[i] = @intCast(r1);
    }
}
