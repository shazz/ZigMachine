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
// So this port EARNS THE BORDERS: the screen is a 400x280 overscan plane with
// the resolution-flicker trick run on every scanline, the Amiga screen is
// centred at x=20, and the bottom 3 Amiga lines (280..282, black — the lowest
// content is the red rule at y=273) are dropped. Nothing else is cropped or
// squashed; every coordinate below is the original's, halved.
//
// ONE PLANE (2026-10-23; it was three). The remake's three canvases need no
// plane of their own on this machine: nothing is hardware-scrolled, the only
// HBL is the border flicker (it races nothing), and the three layers' colours
// fit one palette (supplex_fs2/panel.zig). So they are painter's order in one
// plane, and every enabled plane costs FRESCO ~0.6 Mc a frame:
//
//   effect                         before            after
//   background (logo, red rules)   plane 0, 10 col   plane 0, entries 0..9
//   text panel + raster gradient   plane 1, 160 col  plane 0, entries 10..169
//   grey sine scroller             plane 2, 1 col    plane 0, entry 170
//   save-under of panel+background -                 plane 1, DISABLED
//
// The static picture (background + panel) is drawn once into plane 0 and
// copied once into plane 1, which is never enabled (no FRESCO, no HBL). Each
// frame the scroller's band is restored from it by ONE CHISEL copy (another
// plane, never within one) and the scroller is drawn over it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const panel = @import("supplex_fs2/panel.zig");
const scroller = @import("supplex_fs2/scroller.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;

// The raster scroll: CODEF rasterY starts at 0, -= 2 a frame, and snaps back to
// -44 once it reaches -741 (so it reaches -742, being always even). Halved: -1
// a frame, from 0 down to -371, back to -22. The gradient does NOT repeat over
// that window (checked: raster.png only repeats at its full 1462 rows), so the
// snap is a visible jump in the original too — kept.
const RASTER_RESET: i32 = -371;
const RASTER_BACK: i32 = -22;

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
    siny_a: zg.fixtrig.Angle = 0,
    siny_b: zg.fixtrig.Angle = 0,
    ring: scroller.Ring = undefined,
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("SUPPLEX FS2 init", .{});

        // demo_main.zig holds the cart as `undefined`, so no default applies.
        self.raster_y = 0;
        self.siny_a = 0;
        self.siny_b = 0;

        self.blitter.init();
        const shown: *LogicalFB = &zigos.lfbs[0];
        const saved: *LogicalFB = &zigos.lfbs[1];
        setupPlanes(shown, saved);
        panel.drawBackground(shown);
        panel.drawTextPanel(shown);
        self.blitter.blitCopy(saved, 0, 0, shown, 0, 0, @intCast(panel.PW), @intCast(panel.PH));

        self.ring = scroller.Ring.init(scroller.SCROLL_TEXT, scroller.SCROLL_START, panel.GW);
        // No music: the screen plays "shaolin title.hip" through UADE, an Amiga
        // Hippel/TFMX player binary the machine has no player for. See report.
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;

        self.raster_y -= 1;
        if (self.raster_y <= RASTER_RESET) self.raster_y = RASTER_BACK;

        self.siny_a +%= scroller.SINY_OFF_A;
        self.siny_b +%= scroller.SINY_OFF_B;

        _ = self.ring.step(scroller.SCROLL_SPEED);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        const shown: *LogicalFB = &zigos.lfbs[0];

        // The panel's pixels never move: only its per-line colours do, so the
        // 'source-atop' raster is exactly a palette animation here.
        panel.shiftRaster(shown, self.raster_y);

        // Erase last frame's scroller: the band the sine can reach, restored
        // from the disabled copy of the static picture by one CHISEL copy.
        const x: i16 = @intCast(scroller.SCROLL_X);
        const y: i16 = @intCast(scroller.BAND_TOP);
        self.blitter.blitCopy(shown, x, y, &zigos.lfbs[1], x, y, @intCast(scroller.STRIP_W), @intCast(scroller.BAND_H));
        scroller.buildStrip(&self.ring);
        scroller.blitStrip(shown, self.siny_a, self.siny_b);
    }
};

// Plane 0 is the screen; plane 1 holds the static picture for the save-under
// and is never enabled, so it needs neither a palette nor an HBL.
fn setupPlanes(shown: *LogicalFB, saved: *LogicalFB) void {
    shown.is_enabled = true;
    shown.setOverscanBuffer();
    shown.setPalette(panel.main_pal);
    shown.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_overscan);
    // distcanvas.fill('#AAAAAA') under 'source-atop': the scroller is flat grey.
    shown.setPaletteEntry(panel.GREY, .{ .r = 0xAA, .g = 0xAA, .b = 0xAA, .a = 255 });

    saved.is_enabled = false;
    saved.setOverscanBuffer();
}
