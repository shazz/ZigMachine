// --------------------------------------------------------------------------
// SUPPLEX FS2 — the static picture: the background and the text panel, drawn
// ONCE into the one shown plane, and the panel's raster as a palette animation.
//
// ONE PALETTE for the three layers the CODEF remake stacks (the background, the
// raster-coloured panel, the grey scroller), so they share one plane:
//   0..9     the background picture (main.raw only uses these: checked below)
//   10..169  panel line r takes entry PANEL_FIRST + r: the raster gradient is
//            the per-line colour of a static picture, so scrolling it is
//            rewriting these 160 entries (CODEF's 'source-atop' fill)
//   170      the scroller's flat grey (#AAAAAA)
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const packed_assets = @import("packed_assets");

const LogicalFB = zg.LogicalFB;
const DIR = "../../assets/screens/supplex_fs2/";

pub const PW: i32 = zg.PHYSICAL_WIDTH; // 400
pub const PH: i32 = zg.PHYSICAL_HEIGHT; // 280
pub const X_OFF: i32 = 20; // the 360-wide Amiga screen, centred in the plane

// background: main.png halved and already placed at X_OFF by the asset tool
// (assets/screens/supplex_fs2/main.raw). It ships ZX0-packed (build.zig): 73 KB
// of it is one black run, which raw was that many zeros in the cart binary.
const main_zx0 = packed_assets.supplex_fs2_main;
const MAIN_BYTES: usize = @intCast(PW * PH);
pub const main_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "main_pal.dat"));
const BG_COLOURS: u8 = 10;

// font: 20x3 tiles of 16x16 (CODEF initTile(32,32,32)), 1 = ink, 0 = field.
// The CODEF PNG's ink is the OPAQUE BLACK and the field is white with alpha 0 —
// the reverse of the usual P-mode font, checked before the mask was built.
pub const font_b = @embedFile(DIR ++ "font.raw");
pub const FONT_SHEET_W: usize = 320;
pub const FONT_COLS: usize = 20;
pub const GW: i32 = 16;
pub const GH: i32 = 16;
pub const FIRST_CHAR: u8 = 32;
pub const LAST_CHAR: u8 = 91; // 60 tiles, ' '..'['

// the raster gradient (raster.png, horizontally uniform), halved: 731 x RGB
const raster_b = @embedFile(DIR ++ "raster.dat");
const RASTER_LINES = 731; // comptime_int: an array length and a clamp bound
/// raster.dat's RGB triples as Colors, built at compile time, on a 4-byte
/// boundary: shiftRaster read each triple as a u16 + u8 at stride 3, a
/// misaligned access every other line (80 a frame, each a trap on the board).
const raster_colors: [RASTER_LINES]zg.Color align(4) = blk: {
    @setEvalBranchQuota(10_000);
    var out: [RASTER_LINES]zg.Color = undefined;
    for (&out, 0..) |*c, i| c.* = .{ .r = raster_b[i * 3], .g = raster_b[i * 3 + 1], .b = raster_b[i * 3 + 2], .a = 255 };
    break :blk out;
};

// the text panel: CODEF prints at x=56, y=216 stepping 32 — halved, x=28+X_OFF
// and y=108 stepping 16. Ten lines of 20 chars = a 320x160 block.
const TEXT_X: i32 = 28 + X_OFF;
const TEXT_TOP: i32 = 108;
const TEXT_STEP: i32 = 16;
const TEXT_H: i32 = 160;
const TEXT_LINES = [_][]const u8{
    "      PRESENTS      ",
    " FLIGHT SIMULATOR II",
    "    NEW DATA DISK   ",
    "   CALL OUR HQ AT   ",
    "  0039 40 57 54 24  ",
    "********************",
    "      SUPPLEX       ",
    "   POSTE RESTANTE   ",
    "    8450 HAMMEL     ",
    "      DENMARK       ",
};

pub const PANEL_FIRST: u8 = BG_COLOURS;
pub const GREY: u8 = PANEL_FIRST + TEXT_H;

comptime {
    if (@as(u32, GREY) > 255) @compileError("supplex_fs2: the shared palette is full");
}

// The background is drawn once, so it depacks straight into the plane: no
// working buffer at all. The pack is built from the asset at build time, so a
// failure here is a broken build, never a condition to run on through. The
// shared palette needs the picture to stay under PANEL_FIRST: checked here
// once, over the depacked pixels (a pack can't be read at comptime).
pub fn drawBackground(fb: *LogicalFB) void {
    if (zx0.depackedLen(main_zx0) != MAIN_BYTES) @panic("supplex_fs2: main.raw is not 400x280");
    if (zx0.depack(main_zx0, fb.fb[0..MAIN_BYTES]) == null) @panic("supplex_fs2: main.raw depack failed");
    for (fb.fb[0..MAIN_BYTES]) |v| {
        if (v >= BG_COLOURS) @panic("supplex_fs2: main.raw uses more than 10 colours");
    }
}

// font.print(textcanvas, line, 56, 216 + 32*n), drawn over the background: each
// of the panel's 160 lines takes its own palette entry so that the raster
// gradient can be scrolled through it as a palette animation.
pub fn drawTextPanel(fb: *LogicalFB) void {
    for (TEXT_LINES, 0..) |line, n| {
        const y = TEXT_TOP + @as(i32, @intCast(n)) * TEXT_STEP;
        for (line, 0..) |c, col| {
            if (c < FIRST_CHAR or c > LAST_CHAR) continue;
            drawGlyph(fb, c, TEXT_X + @as(i32, @intCast(col)) * GW, y);
        }
    }
}

fn drawGlyph(fb: *LogicalFB, c: u8, x: i32, y: i32) void {
    const tile: usize = c - FIRST_CHAR;
    const sx0: usize = (tile % FONT_COLS) * @as(usize, GW);
    const sy0: usize = (tile / FONT_COLS) * @as(usize, GH);
    var gy: i32 = 0;
    while (gy < GH) : (gy += 1) {
        const dy = y + gy;
        if (dy < 0 or dy >= PH) continue;
        var gx: i32 = 0;
        while (gx < GW) : (gx += 1) {
            const dx = x + gx;
            if (dx < 0 or dx >= PW) continue;
            const si = (sy0 + @as(usize, @intCast(gy))) * FONT_SHEET_W + sx0 + @as(usize, @intCast(gx));
            if (font_b[si] == 0) continue;
            fb.setPixelValue(@intCast(dx), @intCast(dy), @intCast(dy - TEXT_TOP + PANEL_FIRST));
        }
    }
}

// raster.draw(textcanvas, 0, rasterY, ...) under 'source-atop': screen line
// y takes gradient line y - rasterY. Panel line r uses entry PANEL_FIRST + r.
pub fn shiftRaster(fb: *LogicalFB, raster_y: i32) void {
    var r: i32 = 0;
    while (r < TEXT_H) : (r += 1) {
        const src = std.math.clamp(TEXT_TOP + r - raster_y, 0, RASTER_LINES - 1);
        fb.setPaletteEntry(@intCast(r + PANEL_FIRST), raster_colors[@intCast(src)]);
    }
}
