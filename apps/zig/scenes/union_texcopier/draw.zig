// --------------------------------------------------------------------------
// TEX COPIER's draw() (screen.js:212-242) onto one 320x200 plane. The canvas is
// 640x400 and the ST pixel (X, Y) is the canvas pixel (2X, 2Y), resampled the way
// Chrome resamples it (assets.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const Copier = @import("copier.zig").Copier;
const text = @import("text.zig");

const W = zg.WIDTH;
const H = zg.HEIGHT;
/// rastersPos (screen.js:66): canvas rows of the six 32-row windows, i = 0..5.
const WINDOW_TOPS = [_]i32{ 225, 192, 160, 128, 96, 64 };
const WINDOW_H = 32;
const WINDOW_STEP2 = 8; // each window's source starts 4 rows (8 half-rows) higher
const DISPLAY_X = 160 / 2; // display.draw(maincanvas, 160, 74)
const DISPLAY_Y = 74 / 2;
const TEXT_Y = 360 / 2; // textcanvas.draw(maincanvas, 0, 360)

/// maincanvas.fill('#000000'). The whole view: dst must be the normal 320x200 plane.
pub fn clear(dst: blit.Dst) void {
    @memset(dst.buf, A.BLACK);
}

/// drawPart(maincanvas, 0, rastersPos[i], 0, rasterScrollY - 4i, 640, 32) for the
/// six windows. Each image row is uniform across its 640 columns, so every ST row
/// is one colour: the texel at source row v = rasterScrollY - 4i + (canvas row - top).
pub fn rasters(dst: blit.Dst, c: *const Copier) void {
    if (!c.time_to_raster) return;
    for (WINDOW_TOPS, 0..) |top, i| {
        const first = @divFloor(top + 1, 2); // the first ST row whose canvas row 2Y >= top
        const last = @divFloor(top + WINDOW_H - 1, 2);
        const base2 = c.raster_scroll2 - WINDOW_STEP2 * @as(i32, @intCast(i));
        var y = first;
        while (y <= last) : (y += 1) {
            const entry = rasterEntry(base2 + 2 * (2 * y - top));
            if (entry == A.BLACK) continue; // already filled
            const row: usize = @intCast(y);
            @memset(dst.buf[row * dst.stride ..][0..W], entry);
        }
    }
}

/// The palette entry at twice a raster source row: an even value is a texel, an
/// odd one the mix of the two around it. Rows 32..63 hold 16 doubled colours; the
/// rest of the image, and anything outside it, is transparent over black.
fn rasterEntry(v2: i32) u8 {
    if (v2 < 0) return A.BLACK;
    const row = @divFloor(v2, 2);
    if (@mod(v2, 2) == 0) return rasterTexel(row);
    return switch (row) {
        31 => A.RASTER_MIX, // transparent / colour 0
        63 => A.RASTER_MIX + A.RASTER_COLOURS, // colour 15 / transparent
        32...62 => if (@mod(row, 2) == 0) rasterTexel(row) // both rows of one colour
        else A.RASTER_MIX + @as(u8, @intCast(@divExact(row - 31, 2))),
        else => A.BLACK,
    };
}

fn rasterTexel(row: i32) u8 {
    if (row < 32 or row >= 32 + 2 * A.RASTER_COLOURS) return A.BLACK;
    return A.RASTER_BASE + @as(u8, @intCast(@divFloor(row - 32, 2)));
}

/// display.draw(maincanvas, 160, 74): opaque.
pub fn display(dst: blit.Dst, img: A.Images) void {
    blit.blit(dst, img.display, null, DISPLAY_X, DISPLAY_Y, null, .copy);
}

/// The texture at scrollerRastersPos, the font's black field over it, at canvas
/// row 360. A glyph pixel shows the texture at canvas column 2X - pos: with pos a
/// multiple of 0.5, twice that is the integer 4X - pos2, even on a texel, odd
/// between two.
pub fn textLine(dst: blit.Dst, c: *const Copier, img: A.Images) void {
    const line = c.line() orelse return; // text[29]: only the black fill
    const texels = img.textures[@intFromEnum(c.set)];
    const table = &A.pairs[@intFromEnum(c.set)];
    // the fade level's knock-out: ids up to `removed` are transparent
    var keep: [8]u8 = undefined;
    for (&keep, 0..) |*k, id| k.* = if (id > c.removed()) @intCast(id) else 0;
    const shift: usize = @intCast(-c.pos2);
    for (0..A.GLYPH_H) |y| {
        const out = dst.buf[(TEXT_Y + y) * dst.stride ..][0..W];
        const row = texels[y * A.TEXTURE_W ..][0..A.TEXTURE_W];
        for (out, 0..) |*px, x| {
            const g: usize = line[x / A.GLYPH_W] - text.FIRST_CHAR;
            const cell = (g / A.GLYPHS_PER_ROW * A.GLYPH_H + y) * A.FONT_W + g % A.GLYPHS_PER_ROW * A.GLYPH_W;
            if (img.font[cell + x % A.GLYPH_W] != 0) continue; // the black field, already filled
            const q = 4 * x + shift;
            px.* = table[keep[row[q >> 1]]][keep[row[(q + 1) >> 1]]];
        }
    }
}

comptime {
    // the texture always covers the line: 4*319 + 1280 + 1 half-texels < 2 * 1280
    if ((4 * (W - 1) + A.TEXTURE_W + 1) >> 1 >= A.TEXTURE_W) @compileError("texture too narrow");
    if (TEXT_Y + A.GLYPH_H > H) @compileError("text line off screen");
}
