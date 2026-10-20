// --------------------------------------------------------------------------
// The screen: contour-filled outline text over a mountain silhouette, with the
// 49-band copper raster as REAL per-scanline palette writes.
//
// The Go composites at 352x272:
//
//   palette.Draw(dst, raster, PaletteScaled32, level)   // rows 102..199
//   if active { layer.Clear(); text.Draw(layer view y=8..208);
//               dst.DrawImage(layer, -2, shadow); dst.DrawImage(layer, 0) }
//   dst.DrawImage(mountain, +8)
//
// The canvas sits 1:1 in the centre of the 400x280 overscan plane at (24,4);
// the visible 320x200 window is untouched.  Index 0 is the raster/background,
// 1 the text blue, 2 its shadow, 3 the mountain's black.  Because index 0 is
// the raster on rows 106..203, the plane's side margins carry the same colour
// as the content -- a real ST raster runs edge to edge -- and its background
// above and below the raster is black.  The canvas's own content may spill
// into the open border bands, which is what the 400x280 plane is for.
//
// The text fill is the production's Ebiten FillRuleEvenOdd over all eight
// glyphs in one pass.  Each row is evaluated at pixel centres with integer
// ray crossings; the 8 glyph masks XOR together, so overlapping contours and
// glyphs cancel exactly as they do in the batch.  Rows are walked DOWNWARD so
// the full-colour pass (source row y) is written after the shadow pass (source
// row y+2) has already put its pixel at y: the Go's shadow-then-text order.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const clockmod = @import("clock.zig");

pub const PHYS_W: usize = zg.PHYSICAL_WIDTH; // 400
pub const PHYS_H: usize = zg.PHYSICAL_HEIGHT; // 280
pub const CANVAS_W: usize = 352;
pub const CANVAS_H: usize = 272;
pub const CANVAS_X: usize = 24;
pub const CANVAS_Y: usize = 4; // (280-272)/2

pub const IDX_BG: u8 = 0;
pub const IDX_TEXT: u8 = 1;
pub const IDX_SHADOW: u8 = 2;
pub const IDX_MOUNTAIN: u8 = 3;

/// Raster rows in the canvas: y=102..199, two lines a colour.
const RASTER_Y0: usize = 102;
const RASTER_Y1: usize = 200;

pub var raster_level: u8 = 0;

const Path = struct {
    ncont: u8,
    npts: [A.MAX_CONTOURS]u8,
    pts: [A.MAX_CONTOURS][A.MAX_POINTS][2]i16,
    xmin: i32,
    xmax: i32,
    ymin: i32,
    ymax: i32,
};

var paths: [clockmod.SLOTS]Path = undefined;
var mask: [CANVAS_W]u8 = undefined;

fn emptyPath() Path {
    var p: Path = undefined;
    p.ncont = 0;
    p.npts = @splat(0);
    var ci: usize = 0;
    while (ci < A.MAX_CONTOURS) : (ci += 1) {
        var pi: usize = 0;
        while (pi < A.MAX_POINTS) : (pi += 1) p.pts[ci][pi] = .{ 0, 0 };
    }
    p.xmin = 0;
    p.xmax = -1;
    p.ymin = 0;
    p.ymax = -1;
    return p;
}

/// Map the eight visible glyphs once a frame.  A letter outside 32..90 (only a
/// space can occur) is blank.
fn prepare(c: *const clockmod.Clock) void {
    for (0..clockmod.SLOTS) |slot| {
        const ch = c.letters[slot];
        var path = emptyPath();
        if (ch >= 32 and ch <= 90) {
            const g: usize = ch - 32;
            const gs: usize = A.TABLE.glyph_start[g];
            const gc: usize = A.TABLE.glyph_count[g];
            path.ncont = @intCast(gc);
            var ci: usize = 0;
            while (ci < gc) : (ci += 1) {
                const k = gs + ci;
                const start: usize = A.TABLE.contour_start[k];
                const n: usize = A.TABLE.contour_count[k];
                path.npts[ci] = @intCast(n);
                var pi: usize = 0;
                while (pi < n) : (pi += 1) {
                    const p = A.TABLE.points[start + pi];
                    const q = c.point(slot, p);
                    path.pts[ci][pi] = .{ q.x, q.y };
                    if (path.xmin > path.xmax) {
                        path.xmin = q.x;
                        path.xmax = q.x;
                        path.ymin = q.y;
                        path.ymax = q.y;
                    } else {
                        if (q.x < path.xmin) path.xmin = q.x;
                        if (q.x > path.xmax) path.xmax = q.x;
                        if (q.y < path.ymin) path.ymin = q.y;
                        if (q.y > path.ymax) path.ymax = q.y;
                    }
                }
            }
        }
        paths[slot] = path;
    }
}

/// Even-odd point-in-polygon at the pixel centre (px+0.5, py+0.5), over every
/// contour of the glyph.  The repeated closing vertex is harmless.
fn inside(p: *const Path, px: i32, py: i32) bool {
    const yc2: i64 = 2 * @as(i64, py) + 1;
    const xc2: i64 = 2 * @as(i64, px) + 1;
    var parity: u32 = 0;
    var ci: usize = 0;
    while (ci < @as(usize, p.ncont)) : (ci += 1) {
        const n: usize = p.npts[ci];
        if (n < 3) continue;
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const a = p.pts[ci][i - 1];
            const b = p.pts[ci][i];
            const y1: i64 = a[1];
            const y2: i64 = b[1];
            if ((2 * y1 > yc2) == (2 * y2 > yc2)) continue;
            const x1: i64 = a[0];
            const x2: i64 = b[0];
            const dx = x2 - x1;
            const dy = y2 - y1;
            var num = 2 * x1 * dy + (yc2 - 2 * y1) * dx;
            var den = 2 * dy;
            if (den < 0) {
                num = -num;
                den = -den;
            }
            // xc < num/den, xc = xc2/2, den > 0.
            if (xc2 * den < 2 * num) parity ^= 1;
        }
    }
    return parity != 0;
}

/// XOR this frame's glyph masks into one row.  A glyph outside the row's
/// vertical span contributes nothing; its contour is not even tested.
fn rowMask(c: *const clockmod.Clock, sy: i32) void {
    _ = c;
    @memset(mask[0..], 0);
    for (0..clockmod.SLOTS) |slot| {
        const p = &paths[slot];
        if (p.ncont == 0 or sy < p.ymin or sy > p.ymax) continue;
        var x = p.xmin;
        if (x < 0) x = 0;
        var xmax = p.xmax;
        if (xmax >= @as(i32, @intCast(CANVAS_W))) xmax = @as(i32, @intCast(CANVAS_W)) - 1;
        while (x <= xmax) : (x += 1) {
            if (inside(p, x, sy)) mask[@intCast(x)] ^= 1;
        }
    }
}

fn putMask(fb: *zg.LogicalFB, row: i32, idx: u8) void {
    if (row < 0 or row >= @as(i32, @intCast(CANVAS_H))) return;
    const base = (CANVAS_Y + @as(usize, @intCast(row))) * PHYS_W + CANVAS_X;
    var x: usize = 0;
    while (x < CANVAS_W) : (x += 1) {
        if (mask[x] != 0) fb.fb[base + x] = idx;
    }
}

pub fn drawText(fb: *zg.LogicalFB, c: *const clockmod.Clock) void {
    prepare(c);
    // The layer's text lives only in the Go's clipped view, rows 8..207.  Walk
    // down: shadow at sy-2 first, then full at sy; full wins at a shared row.
    var sy: i32 = 207;
    while (sy >= 8) : (sy -= 1) {
        rowMask(c, sy);
        putMask(fb, sy - 2, IDX_SHADOW);
        putMask(fb, sy, IDX_TEXT);
    }
}

pub fn drawMountain(fb: *zg.LogicalFB) void {
    var my: usize = 0;
    while (my < 200) : (my += 1) {
        const row = (CANVAS_Y + 8 + my) * PHYS_W + CANVAS_X;
        var x: usize = 0;
        while (x < CANVAS_W) : (x += 1) {
            if (A.mountainPixel(x, my)) fb.fb[row + x] = IDX_MOUNTAIN;
        }
    }
}

// --- the per-line copper ---------------------------------------------------
var last0: u32 = 0xFFFF_FFFF;

pub fn install(fb: *zg.LogicalFB) void {
    last0 = 0xFFFF_FFFF;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    // Every line, so the top, sides and bottom all reopen: this is the same
    // flickerAllHbl openBorders(.all) installs, with the copper added.
    fb.flickerBorder();
    const c = lineColor(line);
    if (c != last0) {
        fb.palette[@as(usize, IDX_BG)] = c;
        last0 = c;
    }
}

pub fn lineColor(phys: u16) u32 {
    const y: usize = phys;
    const top = CANVAS_Y + RASTER_Y0;
    const bottom = CANVAS_Y + RASTER_Y1;
    if (y < top or y >= bottom) return A.BLACK;
    return A.rasterColor((y - top) / 2, raster_level);
}
