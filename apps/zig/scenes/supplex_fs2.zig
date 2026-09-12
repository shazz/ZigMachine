// --------------------------------------------------------------------------
// SUPPLEX — the cracktro for "FLIGHT SIMULATOR II NEW DATA DISK", released
// 26/02/90 (the release, the logo, the texts and the scrolltext are Supplex's).
// Ported from Mellowman's CODEF HTML5 remake, wab.com screen 525 (CODEF (c)
// 2011 Antoine Santo / NoNameNo, MIT). Nothing here is re-attributed: the
// screen is Supplex's, the remake read for this port is Mellowman's.
//
// What the screen does, per frame (screen.js go()):
//   * a static background picture: the SUPPLEX/GORDON logo and a red rule
//     across the very top and the very bottom of the screen;
//   * ten lines of 32x32 text (the release/contact panel) printed ONCE into
//     their own canvas, over which a 1462-line vertical raster gradient is
//     composited 'source-atop' — so only the glyph pixels take colour, and the
//     gradient scrolls UP by 2 (doubled) pixels a frame;
//   * a 22-letter horizontal scroller drawn into a 640x32 strip, then copied
//     column by column into the screen with each column displaced vertically by
//     sin(v0)*30 + sin(v1)*100 (CODEF myfxparam), and finally recoloured flat
//     grey (#AAAAAA) with another 'source-atop' fill.
// The CODEF screen also runs an AmigaDecrunch() loader gag before go() — see
// the report; it is NOT ported.
//
// GEOMETRY — the judgement call. The remake's canvas is 720x568: an AMIGA PAL
// OVERSCAN screen (360x284) authored doubled, not an ST 320x200, and the audio
// backend is UADE, which agrees. Halved, the design is 360 wide and 283 tall:
// wider than the 320 visible window (the text panel alone is 320 wide starting
// at x=28, so cropping to 320 would eat a column of glyphs) and taller than it.
// So this port EARNS THE BORDERS: all three planes are 400x280 overscan buffers
// with the resolution-flicker trick run on every scanline, the Amiga screen is
// centred at x=20, and the bottom 3 Amiga lines (280..282, black — the lowest
// content is the red rule at y=273) are dropped. Nothing else is cropped or
// squashed; every coordinate below is the original's, halved.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const PW: i32 = zg.PHYSICAL_WIDTH; // 400
const PH: i32 = zg.PHYSICAL_HEIGHT; // 280
const X_OFF: i32 = 20; // the 360-wide Amiga screen, centred in the plane

// background: main.png halved and already placed at X_OFF by the asset tool.
const main_b = @embedFile("../assets/screens/supplex_fs2/main.raw");
const main_pal = convertU8ArraytoColors(@embedFile("../assets/screens/supplex_fs2/main_pal.dat"));

// font: 20x3 tiles of 16x16 (CODEF initTile(32,32,32)), 1 = ink, 0 = field.
// The CODEF PNG's ink is the OPAQUE BLACK and the field is white with alpha 0 —
// the reverse of the usual P-mode font, checked before the mask was built.
const font_b = @embedFile("../assets/screens/supplex_fs2/font.raw");
const FONT_SHEET_W: usize = 320;
const FONT_COLS: usize = 20;
const GW: i32 = 16;
const GH: i32 = 16;
const FIRST_CHAR: u8 = 32;
const LAST_CHAR: u8 = 91; // 60 tiles, ' '..'['

// the raster gradient (raster.png, horizontally uniform), halved: 731 x RGB
const raster_b = @embedFile("../assets/screens/supplex_fs2/raster.dat");
const RASTER_LINES: i32 = 731;

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

// the raster scroll: CODEF rasterY starts at 0, -= 2 a frame, and snaps back to
// -44 once it reaches -741 (so it reaches -742, being always even). Halved: -1
// a frame, from 0 down to -371, back to -22. The gradient does NOT repeat over
// that window (checked: raster.png only repeats at its full 1462 rows), so the
// snap is a visible jump in the original too — kept.
const RASTER_RESET: i32 = -371;
const RASTER_BACK: i32 = -22;

// the scroller. CODEF: 640x32 strip, tiles 32 wide, speed 4, wide=21 and the
// loop runs i <= wide, so 22 letters, laid out at wide*fontw + i*fontw. Halved.
const STRIP_W: i32 = 320;
const STRIP_H: i32 = 16;
const NB_LETTERS: usize = 22;
const SCROLL_SPEED: f32 = 2.0;
const SCROLL_START: f32 = 21.0 * 16.0; // wide*fontw, halved

// FX.siny(0, 340) over the strip: every source COLUMN is drawn at
// y = 340 + sin(v0)*30 + sin(v1)*100, v0/v1 advancing 0.03/0.01 per doubled
// column and drifting -0.05/-0.04 per frame. Halved: amplitudes and the base y
// halve, the per-column incs double (an ST column is two CODEF columns), the
// per-frame drift is a phase and does not change.
const SINY_AMP_A: f32 = 15.0;
const SINY_AMP_B: f32 = 50.0;
const SINY_INC_A: f32 = 0.06;
const SINY_INC_B: f32 = 0.02;
const SINY_OFF_A: f32 = -0.05;
const SINY_OFF_B: f32 = -0.04;
const SINY_Y: f32 = 170.0; // CODEF posy 340
const SCROLL_X: i32 = 28 + X_OFF; // distcanvas is blitted at CODEF x=56

// The screen's own scrolltext, verbatim from screen.js.
const SCROLL_TEXT =
    "            ***   S U P P L E X   ***       IS PROUD TO PRESENT THEIR LATEST RELEASE CALLED    *** FLIGHT SIMULATOR II NEW DATA DISK ***      " ++
    "RELEASED ON 26/02/90              TO CONTACT US WRITE TO : (ONLY THESE 4 LINES) SUPPLEX, POSTE RESTANTE, 8450 HAMMEL, DENMARK   " ++
    "OR CALL OUR BBS IN ITALY AT 0039 40 57 54 24 OR CALL SUPPLEX WHQ AT 704 254 9142                GREETINGS TO ALL CONTACTS!!!    " ++
    "THEREFORE SEE YOU SOON AT THE CE-BIT !!!!!!!!     ---------------------------               ...CODEF REMAKE BY MELLOW MAN....          ";

// The scroll strip (CODEF's scrollcanvas), rebuilt every frame. Module scope:
// a buffer this size inside the Demo struct costs a duplicate data segment.
var strip = [_]u8{0} ** @as(usize, STRIP_W * STRIP_H);

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// Open every border: the Amiga screen fills all 400x280, so the trick runs on
// every scanline, at the magic column (see docs/HW_API.md).
fn handler_overscan(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = line;
    _ = col;
    fb.flickerBorder();
}

pub const Demo = struct {
    raster_y: i32 = 0,
    siny_a: f32 = 0.0,
    siny_b: f32 = 0.0,
    scroffset: usize = 0,
    ltr_x: [NB_LETTERS]f32 = undefined,
    ltr_c: [NB_LETTERS]u8 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("SUPPLEX FS2 init", .{});

        // demo_main.zig holds the cart as `undefined`, so no default applies.
        self.raster_y = 0;
        self.siny_a = 0.0;
        self.siny_b = 0.0;
        self.scroffset = 0;

        setupPlanes(zigos);
        drawBackground(&zigos.lfbs[0]);
        drawTextPanel(&zigos.lfbs[1]);

        var i: usize = 0;
        while (i < NB_LETTERS) : (i += 1) {
            self.ltr_x[i] = SCROLL_START + @as(f32, @floatFromInt(i)) * @as(f32, GW);
            self.ltr_c[i] = SCROLL_TEXT[self.scroffset];
            self.scroffset += 1;
        }
        // No music: the screen plays "shaolin title.hip" through UADE, an Amiga
        // Hippel/TFMX player binary the machine has no player for. See report.
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;

        self.raster_y -= 1;
        if (self.raster_y <= RASTER_RESET) self.raster_y = RASTER_BACK;

        self.siny_a += SINY_OFF_A;
        self.siny_b += SINY_OFF_B;

        var i: usize = 0;
        while (i < NB_LETTERS) : (i += 1) {
            self.ltr_x[i] -= SCROLL_SPEED;
            if (self.ltr_x[i] <= -@as(f32, GW)) {
                self.ltr_x[i] = SCROLL_START + (self.ltr_x[i] + @as(f32, GW));
                self.ltr_c[i] = SCROLL_TEXT[self.scroffset];
                self.scroffset += 1;
                if (self.scroffset > SCROLL_TEXT.len - 1) self.scroffset = 0;
            }
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;

        // The panel's pixels never move: only its per-line colours do, so the
        // 'source-atop' raster is exactly a palette animation here.
        self.shiftRaster(&zigos.lfbs[1]);

        var scroll: *LogicalFB = &zigos.lfbs[2];
        scroll.clearFrameBuffer(0);
        self.buildStrip();
        self.blitStrip(scroll);
    }

    // raster.draw(textcanvas, 0, rasterY, ...) under 'source-atop': screen line
    // y takes gradient line y - rasterY. Panel line r uses palette entry r+1.
    fn shiftRaster(self: *Demo, fb: *LogicalFB) void {
        var r: i32 = 0;
        while (r < TEXT_H) : (r += 1) {
            const src = std.math.clamp(TEXT_TOP + r - self.raster_y, 0, RASTER_LINES - 1);
            const o: usize = @intCast(src * 3);
            fb.setPaletteEntry(@intCast(r + 1), .{
                .r = raster_b[o],
                .g = raster_b[o + 1],
                .b = raster_b[o + 2],
                .a = 255,
            });
        }
    }

    // scrolltext_horizontal.draw(0) into the 640x32 (here 320x16) strip.
    fn buildStrip(self: *Demo) void {
        @memset(&strip, 0);
        var i: usize = 0;
        while (i < NB_LETTERS) : (i += 1) {
            const c = self.ltr_c[i];
            if (c < FIRST_CHAR or c > LAST_CHAR) continue;
            const x0: i32 = @intFromFloat(@floor(self.ltr_x[i]));
            blitGlyphToStrip(c, x0);
        }
    }

    // FX.siny + the flat grey fill: source column i goes to (SCROLL_X + i,
    // SINY_Y + sin(a)*15 + sin(b)*50), and every drawn pixel is index 1.
    fn blitStrip(self: *Demo, fb: *LogicalFB) void {
        var a = self.siny_a;
        var b = self.siny_b;
        var i: i32 = 0;
        while (i < STRIP_W) : (i += 1) {
            const y0: i32 = @intFromFloat(SINY_Y + SINY_AMP_A * @sin(a) + SINY_AMP_B * @sin(b));
            const dx = SCROLL_X + i;
            var gy: i32 = 0;
            while (gy < STRIP_H) : (gy += 1) {
                const dy = y0 + gy;
                if (dy < 0 or dy >= PH or dx < 0 or dx >= PW) continue;
                if (strip[@intCast(gy * STRIP_W + i)] == 0) continue;
                fb.setPixelValue(@intCast(dx), @intCast(dy), 1);
            }
            a += SINY_INC_A;
            b += SINY_INC_B;
        }
    }
};

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
// Three stacked overscan planes: background, raster-coloured text panel, and
// the grey scroller on top. Only the background's index 0 is opaque.
fn setupPlanes(zigos: *ZigOS) void {
    const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    var fb: *LogicalFB = &zigos.lfbs[0];
    fb.is_enabled = true;
    fb.setOverscanBuffer();
    fb.setPalette(main_pal);
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_overscan);

    // Every plane needs its OWN flicker handler: the machine replays a plane's
    // HBLs while rendering THAT plane, so a plane with no handler is drawn with
    // its borders closed and loses everything outside the 320x200 window
    // (measured: the panel's last two lines vanished below physical row 239).
    fb = &zigos.lfbs[1];
    fb.is_enabled = true;
    fb.setOverscanBuffer();
    fb.setPaletteEntry(0, transparent);
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_overscan);

    fb = &zigos.lfbs[2];
    fb.is_enabled = true;
    fb.setOverscanBuffer();
    fb.setPaletteEntry(0, transparent);
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_overscan);
    // distcanvas.fill('#AAAAAA') under 'source-atop': the scroller is flat grey.
    fb.setPaletteEntry(1, .{ .r = 0xAA, .g = 0xAA, .b = 0xAA, .a = 255 });
}

fn drawBackground(fb: *LogicalFB) void {
    comptime std.debug.assert(main_b.len == @as(usize, @intCast(PW * PH)));
    for (main_b, 0..) |v, idx| fb.fb[idx] = v;
}

// font.print(textcanvas, line, 56, 216 + 32*n): the panel is drawn once, each
// of its 160 lines taking its own palette entry (line + 1) so that the raster
// gradient can be scrolled through it as a palette animation.
fn drawTextPanel(fb: *LogicalFB) void {
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
            fb.setPixelValue(@intCast(dx), @intCast(dy), @intCast(dy - TEXT_TOP + 1));
        }
    }
}

fn blitGlyphToStrip(c: u8, x: i32) void {
    const tile: usize = c - FIRST_CHAR;
    const sx0: usize = (tile % FONT_COLS) * @as(usize, GW);
    const sy0: usize = (tile / FONT_COLS) * @as(usize, GH);
    var gy: i32 = 0;
    while (gy < GH) : (gy += 1) {
        var gx: i32 = 0;
        while (gx < GW) : (gx += 1) {
            const dx = x + gx;
            if (dx < 0 or dx >= STRIP_W) continue;
            const si = (sy0 + @as(usize, @intCast(gy))) * FONT_SHEET_W + sx0 + @as(usize, @intCast(gx));
            if (font_b[si] == 0) continue;
            strip[@intCast(gy * STRIP_W + dx)] = 1;
        }
    }
}
