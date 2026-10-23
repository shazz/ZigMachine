// --------------------------------------------------------------------------
// The intro's 8x8 font and the static art. font8.bin is glyph-major: 256
// glyphs x 8 rows x 8 bytes, one byte a pixel, 1 = ink, index = ASCII code.
//
// A scaled glyph is drawn as horizontal ink RUNS (one Dst.fill per run, a
// `scale`-tall box), never pixel by pixel: on the board every store is a
// blocking DDR write, and a run is one memset (or one CHISEL fill when big).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

const DIR = "../../assets/screens/gnomes/";
pub const font_data = @embedFile(DIR ++ "font8.bin");
const sbob_data = @embedFile(DIR ++ "sbob.raw");

comptime {
    if (font_data.len != 256 * 64) @compileError("font8.bin must be 256 glyphs x 64 B");
    if (sbob_data.len != 144 * 158) @compileError("sbob.raw must be 144x158");
}

/// The font as an 8-pixel-wide image, glyph c at rows c*8..c*8+7.
pub const font_img = blit.Image.init(font_data, 8);
const sbob_img = blit.Image.init(sbob_data, 144);

pub fn glyphRect(ch: u8) blit.Rect {
    return .{ .x = 0, .y = @as(usize, ch) * 8, .w = 8, .h = 8 };
}

/// Glyph `ch` at (x, y), every font pixel a scale x scale block of `ink`.
pub fn drawGlyph(d: blit.Dst, ch: u8, x: i32, y: i32, comptime scale: usize, ink: u8) void {
    const base = @as(usize, ch) * 64;
    for (0..8) |py| {
        const row = font_data[base + py * 8 ..][0..8];
        const yy = y + @as(i32, @intCast(py * scale));
        var px: usize = 0;
        while (px < 8) {
            if (row[px] == 0) {
                px += 1;
                continue;
            }
            const x0 = px;
            while (px < 8 and row[px] != 0) px += 1;
            d.fill(x + @as(i32, @intCast(x0 * scale)), yy, (px - x0) * scale, scale, ink);
        }
    }
}

// --- the static art, drawn once at init -----------------------------------
pub const LOGO_Y = 12;
const LOGO_X0 = 8;
const LOGO_SCALE = 3;
const LOGO_ADV = 24;
const LOGO_TEXT = "THE GNOMES GROUP";

const BOX_Y = 44;
const BOX_W = 40;
const BOX_H = 26;
const BOX_XS = [3]i32{ 26, 80, 134 };

const SBOB_X = 248;
const SBOB_Y = 84; // bottom at 242: above the band's redraw zone (244..)

const RIM_DX = [8]i32{ -1, -1, -1, 0, 0, 1, 1, 1 };
const RIM_DY = [8]i32{ -1, 0, 1, -1, 1, -1, 0, 1 };

pub fn drawLogo(d: blit.Dst, rim: u8, fill: u8) void {
    for (LOGO_TEXT, 0..) |ch, i| {
        if (ch == ' ') continue;
        const x: i32 = LOGO_X0 + @as(i32, @intCast(i * LOGO_ADV));
        for (RIM_DX, RIM_DY) |dx, dy|
            drawGlyph(d, ch, x + dx, LOGO_Y + dy, LOGO_SCALE, rim);
        drawGlyph(d, ch, x, LOGO_Y, LOGO_SCALE, fill);
    }
}

pub fn drawBoxes(d: blit.Dst, ink: u8) void {
    for (BOX_XS) |bx| d.fill(bx, BOX_Y, BOX_W, BOX_H, ink);
}

/// SpongeBob: colour 0 is left out (the raster behind shows, as colour 0 did
/// on the ST), colour 1 takes the plane's `one` (a raster entry too), and
/// colours 2..15 go to base+2..base+15, the sprite's own registers.
pub fn drawSprite(d: blit.Dst, base: u8, one: u8) void {
    const lut = comptime blk: {
        var t: [256]u8 = undefined;
        for (&t, 0..) |*e, i| e.* = @truncate(i);
        break :blk t;
    };
    var map = lut;
    map[1] = one;
    for (2..16) |i| map[i] = base + @as(u8, @intCast(i));
    blit.blit(d, sbob_img, null, SBOB_X, SBOB_Y, 0, .{ .lut = &map });
}
