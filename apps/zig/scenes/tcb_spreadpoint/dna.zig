// --------------------------------------------------------------------------
// The DNA scroller (screen.js draw_scroller_dna / draw_scroller_dna_part).
//
// A scrolltext_horizontal of the 32x25 font at 3 px a frame fills a 320x25
// strip (scroll_dna_canvas). Two strands are cut from it, pos 0 and pos 1
// (decal 0 and PI), each a 2-pixel column every 2 pixels, stretched vertically
// into the 320x50 dna_canvas between two points of a sine:
//
//   angle1 = (x * 0.026 + pos * PI) % 2PI,  angle2 = (angle1 + 1.12) % 2PI
//   from = round(25 sin angle1),  to = round(25 sin angle2)
//   drawn only where angle1 > 3.6 or angle1 < 1.5; from = -25 on (3.6, 4.6),
//   to = 25 on (0.5, 1.5); height = (to - from) / 25 + 0.0001
//
// None of that moves: pos is 0 or 1, so the strands' geometry is fixed and only
// the text slides through it. It is computed once, in init(). The strip's rows
// are sampled nearest (the canvas smooths; an ST does not).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const texts = @import("texts.zig");

pub const W = 320;
pub const STRIP_H = 25; // scroll_dna_canvas height, the font's
const AMPLITUDE = 25;
const COLUMNS = W / 2;
const GLYPH_W = 32;
const FONT_COLS = 10; // font_dna.png is 320 wide
const FIRST_CHAR = 32; // font_dna.initTile(32, 25, 32)
const SPEED = 3; // scroll_dna.init(scroll_dna_canvas, font_dna, 3)
// scrolltext_horizontal.init: wide = ceil(320/32) + 1 = 11, letters 0..wide,
// letter i starting at wide*32 + i*32.
const WIDE = 11;
const START_X = WIDE * GLYPH_W; // 352

const font_b = @embedFile("../../assets/screens/tcb_spreadpoint/font_dna.raw");
const font = blit.Image.init(font_b, W);

comptime {
    if (font_b.len != W * 150) @compileError("font_dna.raw is not 320x150");
    @setEvalBranchQuota(10_000);
    for (texts.dna) |c| if (c < FIRST_CHAR or c - FIRST_CHAR >= FONT_COLS * 6) @compileError("DNA text character outside the font");
}

const Column = struct { top: u8, h: u8 }; // dna_canvas rows top .. top+h-1; h 0 = not drawn

var strands: [2][COLUMNS]Column = undefined;
/// source_row[h][r]: the strip row a column h rows tall shows on its row r.
/// Depends only on h (to - from is at most 2 * AMPLITUDE), so it is built once.
const MAX_H = 2 * AMPLITUDE;
var source_row: [MAX_H + 1][MAX_H]u8 = undefined;
var strip: [W * STRIP_H]u8 = undefined;

fn jsRound(v: f64) i32 {
    return @intFromFloat(@floor(v + 0.5)); // Math.round
}

pub fn init() void {
    const pi2 = 2.0 * std.math.pi;
    for (0..2) |pos| {
        const decal = @as(f64, @floatFromInt(pos)) * std.math.pi;
        for (0..COLUMNS) |c| {
            const x: f64 = @floatFromInt(c * 2);
            const angle1 = @rem(x * 0.026 + decal, pi2);
            const angle2 = @rem(angle1 + 1.12, pi2);
            var from = jsRound(AMPLITUDE * @sin(angle1));
            var to = jsRound(AMPLITUDE * @sin(angle2));
            strands[pos][c] = .{ .top = 0, .h = 0 };
            if (!(3.6 < angle1 or angle1 < 1.5)) continue;
            if (3.6 < angle1 and angle1 < 4.6) from = -AMPLITUDE;
            if (0.5 < angle1 and angle1 < 1.5) to = AMPLITUDE;
            // to >= from on every drawn column (measured: h is 0..27), so the
            // canvas never flips a column.
            strands[pos][c] = .{ .top = @intCast(AMPLITUDE + from), .h = @intCast(@max(to - from, 0)) };
        }
    }
    // height = h/25 + 0.0001; dest row r takes strip row (r + 0.5) / height
    for (&source_row, 0..) |*rows, h| {
        const height = @as(f64, @floatFromInt(h)) / AMPLITUDE + 0.0001;
        for (rows, 0..) |*sy, r| {
            sy.* = @intCast(@min(STRIP_H - 1, @as(usize, @intFromFloat((@as(f64, @floatFromInt(r)) + 0.5) / height))));
        }
    }
}

/// The scrolltext on its `calls`-th draw (1 = the first frame it is shown).
/// Letter n of the endless text sits at START_X + 32n - 3*calls: the eleven +1
/// letters of scrolltext_horizontal are a window onto that stream.
fn fillStrip(calls: u64) void {
    @memset(&strip, 0);
    const shift: i64 = @intCast(calls * SPEED);
    const dst = blit.Dst.buffer(&strip, W);
    // first letter still overlapping the strip: START_X + 32n - shift > -32
    var n: i64 = @max(0, @divFloor(shift - START_X - GLYPH_W, GLYPH_W) + 1);
    while (true) : (n += 1) {
        const x = START_X + GLYPH_W * n - shift;
        if (x >= W) break;
        const tile: usize = texts.dna[@intCast(@mod(n, texts.dna.len))] - FIRST_CHAR;
        const part = blit.Rect{ .x = (tile % FONT_COLS) * GLYPH_W, .y = (tile / FONT_COLS) * STRIP_H, .w = GLYPH_W, .h = STRIP_H };
        blit.blit(dst, font, part, @intCast(x), 0, 0, .copy);
    }
}

/// draw_scroller_dna into `view`, the 320x50 dna_canvas window of the plane.
pub fn draw(view: blit.Dst, calls: u64) void {
    fillStrip(calls);
    for (&strands) |*strand| {
        for (strand, 0..) |col, c| {
            if (col.h == 0) continue;
            for (source_row[col.h][0..col.h], 0..) |sy, r| {
                const y = @as(usize, col.top) + r;
                if (y >= view.h) break;
                const src = strip[@as(usize, sy) * W + c * 2 ..][0..2];
                const dst = view.buf[y * view.stride + c * 2 ..][0..2];
                for (src, dst) |s, *d| {
                    if (s != 0) d.* = s;
                }
            }
        }
    }
}
