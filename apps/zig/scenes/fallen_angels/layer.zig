// --------------------------------------------------------------------------
// FALLEN ANGELS on ONE plane: the scroller, the logo and the 3D grid were three
// FRESCO planes (scroller under logo under grid), ~0.4 Mc of compositing each a
// frame even where empty. Painter's order in one plane gives the same picture:
//
//   1. clear the 25 gap rows (row 7 of each 8-row text line, which the scroller
//      never draws): that is where last frame's logo and grid can still be, the
//      other rows are rewritten whole by step 2;
//   2. the 25 scroller row blits (fallen_angels.zig), full width;
//   3. the logo, its see-through index 1 keyed out, so the scroller shows there
//      as it did through the logo plane's transparent entry;
//   4. the grid edges in red.
//
// One palette: the scroller's two entries (0 transparent, 1 the ink the copper
// recolours per line), the logo's three greys, the grid's red. No index is
// shared, so the copper raster on entry 1 still touches only the scroller ink.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const shapes = zg.shapes;
const Coord = shapes.Coord;
const Color = zg.Color;

pub const SCROLL_INK: u8 = 1;
const LOGO_FIRST: u8 = 2; // logo indices 0, 2, 3 -> 2, 3, 4
const RED: u8 = 5;
const LOGO_KEY: u8 = 1; // the logo's see-through index (its plane made entry 1 transparent)

pub const LOGO_W = 89;
pub const LOGO_H = 16;
const TEXT_PITCH = 8; // a text line every 8 rows: 7 drawn, 1 gap
const GAP_ROW = 7;

const logo_pal = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/fallen_angels/logo_pal.dat"));

/// logo.raw remapped into the shared palette at compile time; index 1 stays 1, the key.
const logo_pixels = blk: {
    @setEvalBranchQuota(10_000);
    const raw = @embedFile("../../assets/screens/fallen_angels/logo.raw");
    var out: [raw.len]u8 = undefined;
    for (raw, &out) |p, *o| o.* = switch (p) {
        0 => LOGO_FIRST,
        LOGO_KEY => LOGO_KEY,
        2, 3 => LOGO_FIRST + p - 1,
        else => @compileError("logo.raw: index outside its 4-colour palette"),
    };
    break :blk out;
};
const logo = blit.Image.init(&logo_pixels, LOGO_W);

/// The logo's greys and the grid's red, after the scroller's own entries.
pub fn setPalette(fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(LOGO_FIRST, logo_pal[0]);
    fb.setPaletteEntry(LOGO_FIRST + 1, logo_pal[2]);
    fb.setPaletteEntry(LOGO_FIRST + 2, logo_pal[3]);
    fb.setPaletteEntry(RED, Color{ .r = 0xff, .g = 0x00, .b = 0x00, .a = 255 });
}

/// Step 1: row 7 of every text line back to 0, one strided fill.
pub fn clearGapRows(fb: *zg.LogicalFB) void {
    const plane = blit.Dst.plane(fb);
    const gaps = blit.Dst{
        .buf = plane.buf[GAP_ROW * plane.stride ..],
        .stride = plane.stride * TEXT_PITCH,
        .w = plane.w,
        .h = plane.h / TEXT_PITCH,
    };
    gaps.fill(0, 0, gaps.w, gaps.h, 0);
}

/// Step 3.
pub fn drawLogo(fb: *zg.LogicalFB, x: i32, y: i32) void {
    blit.blit(blit.Dst.plane(fb), logo, null, x, y, LOGO_KEY, .copy);
}

/// Step 4: every distinct edge once (the quads share their inner edges).
pub fn drawGrid(fb: *zg.LogicalFB, edges: []const [2]u16, pts: []const Coord) void {
    for (edges) |e| line(fb, pts[e[0]], pts[e[1]], RED);
}

/// The edge list without repeats: a shared edge comes back reversed, and
/// shapes.drawLine draws (a, b) and (b, a) as the same pixels (it starts from
/// the upper end; a level edge is the same run of pixels either way).
pub fn uniqueEdges(comptime edges: []const [2]u16) []const [2]u16 {
    comptime {
        @setEvalBranchQuota(100_000);
        var out: [edges.len][2]u16 = undefined;
        var n: usize = 0;
        for (edges) |e| {
            const seen = for (out[0..n]) |o| {
                if ((o[0] == e[0] and o[1] == e[1]) or (o[0] == e[1] and o[1] == e[0])) break true;
            } else false;
            if (!seen) {
                out[n] = e;
                n += 1;
            }
        }
        const final = out[0..n].*;
        return &final;
    }
}

/// shapes.drawLine's Bresenham, pixel for pixel, storing straight into the
/// plane instead of a RenderTarget call per pixel. Its four branches are one
/// loop here: from the upper end (the first point on a tie), dp decides.
fn line(fb: *zg.LogicalFB, a: Coord, b: Coord, c: u8) void {
    const p0 = if (b.y < a.y) b else a;
    const p1 = if (b.y < a.y) a else b;
    const sx: i16 = if (p1.x >= p0.x) 1 else -1;
    const dx: i16 = if (p1.x >= p0.x) p1.x - p0.x else p0.x - p1.x;
    const dy: i16 = p1.y - p0.y;
    var x = p0.x;
    var y = p0.y;
    plot(fb, x, y, c);
    if (dx >= dy) {
        var dp: i16 = 2 * dy - dx;
        while (x != p1.x) {
            if (dp > 0) y += 1;
            dp += if (dp <= 0) 2 * dy else 2 * (dy - dx);
            x += sx;
            plot(fb, x, y, c);
        }
    } else {
        var dp: i16 = 2 * dx - dy;
        while (y < p1.y) {
            if (dp > 0) x += sx;
            dp += if (dp <= 0) 2 * dx else 2 * (dx - dy);
            y += 1;
            plot(fb, x, y, c);
        }
    }
}

/// setPixelValue's clip (x, y below the plane's size; the grid never goes negative).
inline fn plot(fb: *zg.LogicalFB, x: i16, y: i16, c: u8) void {
    const ux: u16 = @bitCast(x);
    const uy: u16 = @bitCast(y);
    if (ux < fb.fb_w and uy < fb.fb_h) fb.fb[@as(u32, uy) * fb.stride + ux] = c;
}
