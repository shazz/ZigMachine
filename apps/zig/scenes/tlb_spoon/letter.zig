// --------------------------------------------------------------------------
// THE LOST BOYS / TWIDDLE DEMO — one scroller letter (screen.js:322-364).
// Walk the letter's screen bounding box, map each pixel back to glyph space
// through R(-(theta+letter_angle)), and — exactly as the remake's 400x200
// canvas does — reject anything that falls outside the scroll canvas. A glyph
// pixel does not paint the font's ink: it PUNCHES a hole, and the hole shows
// the raster band for that screen row.
//
// SPEED, pixel-exact (0.94 Mc a frame before). Two things are proved, not hoped:
//  * The canvas test only fails on the letters entering and leaving the
//    canvas. When the bbox's four pixel-centre corners map inside it with a
//    1 px margin, every pixel does (the map is affine, and ~40 f32 steps of
//    values < 512 drift by ~2e-3 px), so that letter runs the loop without the
//    canvas accumulators and their four compares. Other letters run the
//    original loop unchanged.
//  * Adding a constant to an f32 is monotone, so along a row the pixels with
//    gx and gy both in [0, 25) form ONE interval: after the first miss that
//    follows a hit the row is done.
// The glyph accumulators stay f32 and start where they always did (x0 + 0.5):
// fixed point or a different start would round differently and flip pixels.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const W = zg.WIDTH;
const H = zg.HEIGHT;

const font_b = @embedFile("../../assets/screens/tlb_spoon/font.raw");
const FONT_SHEET_W: usize = 250;
pub const GLYPH = 25;
const GLYPH_COLS: u16 = 10;
const RASTER_BASE: u8 = 6;
const SCROLL_W: f32 = 400;
const SCROLL_H: f32 = 200;
const MARGIN: f32 = 1;

pub const Letter = struct {
    tile: u16, // GLYPH_TILES = "nothing to draw"
    ox: f32, // where the glyph's (0,0) lands on screen
    oy: f32,
    cb: f32, // R(theta + letter angle): glyph space -> screen
    sb: f32,
};

// The scroll canvas -> screen affine, and its inverse (used to clip a pixel
// against the 400x200 canvas exactly as the remake's canvas bounds do).
pub const Frame = struct {
    ct: f32,
    st: f32,
    cx: f32,
    cy: f32,
    sx: f32,
    sy: f32,
};

const Box = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

pub fn draw(fb: *LogicalFB, slot: Letter, f: Frame) void {
    const b = bbox(slot) orelse return;
    if (insideCanvas(f, b)) drawInside(fb, slot, b) else drawClipped(fb, slot, f, b);
}

fn bbox(slot: Letter) ?Box {
    var min_x: f32 = 1.0e9;
    var min_y: f32 = 1.0e9;
    var max_x: f32 = -1.0e9;
    var max_y: f32 = -1.0e9;
    const g: f32 = @floatFromInt(GLYPH);
    for ([_][2]f32{ .{ 0, 0 }, .{ g, 0 }, .{ 0, g }, .{ g, g } }) |corner| {
        const cx = slot.ox + slot.cb * corner[0] - slot.sb * corner[1];
        const cy = slot.oy + slot.sb * corner[0] + slot.cb * corner[1];
        min_x = @min(min_x, cx);
        max_x = @max(max_x, cx);
        min_y = @min(min_y, cy);
        max_y = @max(max_y, cy);
    }
    const b = Box{
        .x0 = @max(0, @as(i32, @intFromFloat(@floor(min_x)))),
        .y0 = @max(0, @as(i32, @intFromFloat(@floor(min_y)))),
        .x1 = @min(W, @as(i32, @intFromFloat(@ceil(max_x))) + 1),
        .y1 = @min(H, @as(i32, @intFromFloat(@ceil(max_y))) + 1),
    };
    if (b.x0 >= b.x1 or b.y0 >= b.y1) return null;
    return b;
}

// Do the pixel centres x0+0.5 .. x1-0.5, y0+0.5 .. y1-0.5 all map inside the
// scroll canvas, MARGIN to spare? (An affine map's extremes are at the corners.)
fn insideCanvas(f: Frame, b: Box) bool {
    const xs = [2]f32{ @as(f32, @floatFromInt(b.x0)) + 0.5, @as(f32, @floatFromInt(b.x1)) - 0.5 };
    const ys = [2]f32{ @as(f32, @floatFromInt(b.y0)) + 0.5, @as(f32, @floatFromInt(b.y1)) - 0.5 };
    for (xs) |px| for (ys) |py| {
        const cx = f.sx + f.ct * (px - f.cx) + f.st * (py - f.cy);
        const cy = f.sy - f.st * (px - f.cx) + f.ct * (py - f.cy);
        if (!(cx >= MARGIN and cx < SCROLL_W - MARGIN and cy >= MARGIN and cy < SCROLL_H - MARGIN)) return false;
    };
    return true;
}

fn tileOrigin(slot: Letter) usize {
    return @as(usize, slot.tile / GLYPH_COLS) * GLYPH * FONT_SHEET_W + @as(usize, slot.tile % GLYPH_COLS) * GLYPH;
}

fn drawInside(fb: *LogicalFB, slot: Letter, b: Box) void {
    const g: f32 = @floatFromInt(GLYPH);
    const src = font_b[tileOrigin(slot)..];
    const fx0 = @as(f32, @floatFromInt(b.x0)) + 0.5;
    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        var gx = slot.cb * (fx0 - slot.ox) + slot.sb * (py - slot.oy);
        var gy = -slot.sb * (fx0 - slot.ox) + slot.cb * (py - slot.oy);
        const ink = RASTER_BASE + @as(u8, @intCast(@divTrunc(y, 8)));
        const dst = fb.fb[@as(usize, @intCast(y)) * W ..];
        var hit = false;
        var x = b.x0;
        while (x < b.x1) : ({
            x += 1;
            gx += slot.cb;
            gy -= slot.sb;
        }) {
            if (gx < 0 or gy < 0 or gx >= g or gy >= g) {
                if (hit) break;
                continue;
            }
            hit = true;
            const sxi = @as(usize, @intFromFloat(gx));
            const syi = @as(usize, @intFromFloat(gy));
            if (src[syi * FONT_SHEET_W + sxi] != 0) dst[@intCast(x)] = ink;
        }
    }
}

// The original loop, for the letters the canvas edge cuts.
fn drawClipped(fb: *LogicalFB, slot: Letter, f: Frame, b: Box) void {
    const g: f32 = @floatFromInt(GLYPH);
    const src = font_b[tileOrigin(slot)..];
    var y = b.y0;
    while (y < b.y1) : (y += 1) {
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        // Screen -> glyph, and screen -> scroll canvas; both advance by a
        // constant vector along the row, so each row costs two rotations.
        var gx = slot.cb * (@as(f32, @floatFromInt(b.x0)) + 0.5 - slot.ox) + slot.sb * (py - slot.oy);
        var gy = -slot.sb * (@as(f32, @floatFromInt(b.x0)) + 0.5 - slot.ox) + slot.cb * (py - slot.oy);
        var canvas_x = f.sx + f.ct * (@as(f32, @floatFromInt(b.x0)) + 0.5 - f.cx) + f.st * (py - f.cy);
        var canvas_y = f.sy - f.st * (@as(f32, @floatFromInt(b.x0)) + 0.5 - f.cx) + f.ct * (py - f.cy);
        const ink = RASTER_BASE + @as(u8, @intCast(@divTrunc(y, 8)));
        const dst = fb.fb[@as(usize, @intCast(y)) * W ..];

        var x = b.x0;
        while (x < b.x1) : ({
            x += 1;
            gx += slot.cb;
            gy -= slot.sb;
            canvas_x += f.ct;
            canvas_y -= f.st;
        }) {
            if (gx < 0 or gy < 0 or gx >= g or gy >= g) continue;
            if (canvas_x < 0 or canvas_y < 0 or canvas_x >= SCROLL_W or canvas_y >= SCROLL_H) continue;
            const sxi = @as(usize, @intFromFloat(gx));
            const syi = @as(usize, @intFromFloat(gy));
            if (src[syi * FONT_SHEET_W + sxi] != 0) dst[@intCast(x)] = ink;
        }
    }
}

comptime {
    if (font_b.len != FONT_SHEET_W * 7 * GLYPH) @compileError("font.raw is not a 10x7 grid of 25x25");
}
