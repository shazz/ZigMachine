// --------------------------------------------------------------------------
// THE LOST BOYS / TWIDDLE DEMO — drawing one scroller letter (screen.js:322-364)
// in Q16.16 integers: no float per frame on ZIGGY. Placement: place.zig.
//
// Walk the letter's screen bounding box, map each pixel back to glyph space
// through R(-(theta+letter_angle)), and — exactly as the remake's 400x200
// canvas does — reject anything that falls outside the scroll canvas. A glyph
// pixel does not paint the font's ink: it PUNCHES a hole, and the hole shows
// the raster band for that screen row.
//
// SPEED: when the bbox's four pixel-centre corners map inside the canvas with
// 1 px to spare, every pixel does (the map is affine), so that letter runs
// without the canvas accumulators. Along a row the pixels with gx and gy both
// in [0, 25) form ONE interval (the steps are constant): after the first miss
// that follows a hit the row is done.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const W = zg.WIDTH;
const H = zg.HEIGHT;

const font_b = @embedFile("../../assets/screens/tlb_spoon/font.raw");
const FONT_SHEET_W: usize = 250;
pub const GLYPH = 25;
const GLYPH_COLS: u16 = 10;
const RASTER_BASE: u8 = 6;
const ONE: i32 = 1 << 16;
const HALF: i32 = 1 << 15;
const G16: u32 = GLYPH << 16;
const SCROLL_W: u32 = 400 << 16;
const SCROLL_H: u32 = 200 << 16;
const MARGIN: i32 = ONE;

/// All Q16.16.
pub const Letter = struct {
    tile: u16, // GLYPH_TILES = "nothing to draw"
    ox: i32, // where the glyph's (0,0) lands on screen
    oy: i32,
    cb: i32, // R(theta + letter angle): glyph space -> screen
    sb: i32,
};

/// The scroll canvas -> screen affine (Q16): p_screen = (cx,cy) + R * (p - (sx,sy)).
/// ct/st are kept in Q30 too, to place the letters precisely.
pub const Frame = struct {
    ct: i32,
    st: i32,
    cx: i32,
    cy: i32,
    sx: i32,
    sy: i32,
    ct30: i32,
    st30: i32,
};

const Box = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

pub fn draw(fb: *LogicalFB, slot: Letter, f: Frame) void {
    const b = bbox(slot) orelse return;
    if (insideCanvas(f, b)) drawInside(fb, slot, b) else drawClipped(fb, slot, f, b);
}

inline fn mul16(a: i32, b: i32) i32 {
    return @intCast((@as(i64, a) * b) >> 16);
}

fn bbox(slot: Letter) ?Box {
    const g: i32 = GLYPH;
    var min_x: i32 = std.math.maxInt(i32);
    var min_y: i32 = std.math.maxInt(i32);
    var max_x: i32 = std.math.minInt(i32);
    var max_y: i32 = std.math.minInt(i32);
    for ([_][2]i32{ .{ 0, 0 }, .{ g, 0 }, .{ 0, g }, .{ g, g } }) |corner| {
        const cx = slot.ox + slot.cb * corner[0] - slot.sb * corner[1];
        const cy = slot.oy + slot.sb * corner[0] + slot.cb * corner[1];
        min_x = @min(min_x, cx);
        max_x = @max(max_x, cx);
        min_y = @min(min_y, cy);
        max_y = @max(max_y, cy);
    }
    const b = Box{
        .x0 = @max(0, min_x >> 16),
        .y0 = @max(0, min_y >> 16),
        .x1 = @min(W, ((max_x + ONE - 1) >> 16) + 1),
        .y1 = @min(H, ((max_y + ONE - 1) >> 16) + 1),
    };
    if (b.x0 >= b.x1 or b.y0 >= b.y1) return null;
    return b;
}

// Screen point (Q16) -> scroll canvas, through R(-theta).
inline fn toCanvas(f: Frame, px: i32, py: i32) [2]i32 {
    return .{
        f.sx + mul16(f.ct, px - f.cx) + mul16(f.st, py - f.cy),
        f.sy - mul16(f.st, px - f.cx) + mul16(f.ct, py - f.cy),
    };
}

// Screen point (Q16) -> glyph space, through R(-(theta + letter angle)).
inline fn toGlyph(slot: Letter, px: i32, py: i32) [2]i32 {
    return .{
        mul16(slot.cb, px - slot.ox) + mul16(slot.sb, py - slot.oy),
        mul16(slot.cb, py - slot.oy) - mul16(slot.sb, px - slot.ox),
    };
}

// Do the box's pixel centres all map inside the scroll canvas, MARGIN to
// spare? (An affine map's extremes are at the corners.)
fn insideCanvas(f: Frame, b: Box) bool {
    const xs = [2]i32{ (b.x0 << 16) + HALF, (b.x1 << 16) - HALF };
    const ys = [2]i32{ (b.y0 << 16) + HALF, (b.y1 << 16) - HALF };
    for (xs) |px| for (ys) |py| {
        const c = toCanvas(f, px, py);
        if (c[0] < MARGIN or c[0] >= (400 << 16) - MARGIN or c[1] < MARGIN or c[1] >= (200 << 16) - MARGIN) return false;
    };
    return true;
}

fn tileOrigin(slot: Letter) usize {
    return @as(usize, slot.tile / GLYPH_COLS) * GLYPH * FONT_SHEET_W + @as(usize, slot.tile % GLYPH_COLS) * GLYPH;
}

// 0 <= v < bound as one unsigned compare.
inline fn below(v: i32, bound: u32) bool {
    return @as(u32, @bitCast(v)) < bound;
}

inline fn texel(src: []const u8, g: [2]i32) u8 {
    return src[@as(usize, @intCast(g[1] >> 16)) * FONT_SHEET_W + @as(usize, @intCast(g[0] >> 16))];
}

fn drawInside(fb: *LogicalFB, slot: Letter, b: Box) void {
    const src = font_b[tileOrigin(slot)..];
    const fx0 = (b.x0 << 16) + HALF;
    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        var g = toGlyph(slot, fx0, (y << 16) + HALF);
        const ink = RASTER_BASE + @as(u8, @intCast(y >> 3));
        const dst = fb.fb[@as(usize, @intCast(y)) * W ..];
        var hit = false;
        var x = b.x0;
        while (x < b.x1) : ({
            x += 1;
            g[0] += slot.cb;
            g[1] -= slot.sb;
        }) {
            if (!(below(g[0], G16) and below(g[1], G16))) {
                if (hit) break;
                continue;
            }
            hit = true;
            if (texel(src, g) != 0) dst[@intCast(x)] = ink;
        }
    }
}

// The letters the canvas edge cuts: the same walk, plus the canvas test.
fn drawClipped(fb: *LogicalFB, slot: Letter, f: Frame, b: Box) void {
    const src = font_b[tileOrigin(slot)..];
    const fx0 = (b.x0 << 16) + HALF;
    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        const py = (y << 16) + HALF;
        var g = toGlyph(slot, fx0, py);
        var c = toCanvas(f, fx0, py);
        const ink = RASTER_BASE + @as(u8, @intCast(y >> 3));
        const dst = fb.fb[@as(usize, @intCast(y)) * W ..];
        var x = b.x0;
        while (x < b.x1) : ({
            x += 1;
            g[0] += slot.cb;
            g[1] -= slot.sb;
            c[0] += f.ct;
            c[1] -= f.st;
        }) {
            if (!(below(g[0], G16) and below(g[1], G16))) continue;
            if (!(below(c[0], SCROLL_W) and below(c[1], SCROLL_H))) continue;
            if (texel(src, g) != 0) dst[@intCast(x)] = ink;
        }
    }
}

comptime {
    if (font_b.len != FONT_SHEET_W * 7 * GLYPH) @compileError("font.raw is not a 10x7 grid of 25x25");
}
