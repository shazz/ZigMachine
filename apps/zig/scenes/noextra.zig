// --------------------------------------------------------------------------
// NOEXTRA — the NoExtra Team screen from the DHS Megademo 2005 (the "D.H.S.
// ST Demoscreen Competition" compilation). Ported from Mellowman's CODEF
// HTML5 remake, wab.com screen 198 (CODEF (c) 2011 Antoine Santo / NoNameNo,
// MIT). Code, graphics, music and scrolltext stay the originals' authors':
// NoExtra Team for the screen, "Mega 4" (a conversion of Jester/Elysium's mod)
// for the tune, Mellowman for the remake this was read from.
//
// What it does, in order:
//   * intro — the "D.H.S. ONLINE COMPO 2005" logo fades up, bounces six times
//     through the middle of the screen, then fades out;
//   * main  — a rainbow raster image is line-distorted horizontally by two
//     summed sines, framed top and bottom by a one-pixel gradient bar, with
//     the NOEXTRA logo above and the ZORRO 2 logo below; a 32x17 scroller
//     runs across the band, every column vertically displaced by a slow,
//     very-long-wavelength sine;
//   * once the ']' marker in the scrolltext comes up, the WHOLE screen starts
//     bobbing vertically for good.
//
// GEOMETRY — THIS IS A BORDER SCREEN. The original authors at 640x480 = an ST
// screen at 320x240: forty lines TALLER than the standard plane, because the
// real screen opened the BOTTOM border (the ZORRO 2 logo sits at layout rows
// 171..239, i.e. astride the border edge). So both planes are OVERSCAN planes
// (400x280, stride 400) and the layout is placed in PHYSICAL coordinates with
// its top row at the visible-window start, BY = 40:
//
//     physical y = BY + layout_row + bob      (clipped to [0, 280) — with all
//                                              borders open that is the screen)
//
// The borders are EARNED, not switched on: handler_overscan() flickers the
// resolution register at OVERSCAN_MAGIC_X on every scanline. At rest the layout
// needs only the bottom border (rows 240..279 hold the ZORRO 2 logo); the top
// border is opened too so the +/-40 bob slides content off the real screen edge
// instead of chopping it at the visible window's top.
//
// The band and the scroller are widened from the original's 320 to the full
// 400 physical columns (the extra content is the same rainbow and the same
// letters, further out — no invented artwork); the logos keep their original
// x, offset by BX so they sit where they did inside the visible window.
//
// ONE PLANE. Everything shares a single 256-colour palette (see the asset
// note below) and is painted into one buffer in the original's own order —
// which is what CODEF does too (one canvas), and which matters because the
// host copies and uploads a whole 800x280 RGBA canvas PER ENABLED PLANE every
// frame. That per-plane upload, not the cart, was the 20fps.
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
const BX: i32 = zg.HORIZONTAL_BORDERS_WIDTH; // 40 — visible window left edge
const BY: i32 = zg.VERTICAL_BORDERS_HEIGHT; // 40 — visible window top edge
const FB_LEN: usize = @as(usize, @intCast(PW)) * @as(usize, @intCast(PH));

// music — "Mega 4", the YM6! register dump the CODEF screen plays. Shipped as
// .ymraw because that is the extension the host's YM player is wired to; the
// .ym on wab.com is the same dump inside an LHA container.
// KEPT as .ymraw (checked 2026-09-13, per "prefer SNDH over YM"): the tune's
// own header says "Conversion of a Mod by Jester : Elysium" — a mod2ym dump of
// an Amiga module, not an ST-native replay. The local SNDH archive has no
// title/composer hit for "Mega 4"/Jester/Elysium; no SNDH is this recording.
const MUSIC = "mega4.ymraw";

// the rainbow distorter source: one row is enough, the image is vertically
// uniform (checked — every row of backraster.png is identical).
const RASTER_W: i32 = 640;
const raster_b = @embedFile("../assets/screens/noextra/raster.raw");
// ONE palette for the whole screen: 0 black, 1..160 the rainbow ramp,
// 161..184 the gradient bar, 185..254 the logos, 255 the scroller's white ink.
const screen_pal = convertU8ArraytoColors(@embedFile("../assets/screens/noextra/screen_pal.dat"));
const gradbar_b = @embedFile("../assets/screens/noextra/gradbar.raw");

const BAND_TOP: i32 = 50; // CODEF y=100
const BAND_H: i32 = 120; // CODEF height 240
const GRAD_TOP: i32 = 50; // CODEF y=100
const GRAD_BOTTOM: i32 = 169; // CODEF y=338

const INK: u8 = 255; // the scroller's white
// The logos' own slice of the shared palette, for the intro fade.
const LOGO_FIRST: usize = 185;
const LOGO_LAST: usize = 254;

const toplogo_b = @embedFile("../assets/screens/noextra/toplogo.raw");
const TOP_W: i32 = 208;
const TOP_H: i32 = 46;
const TOP_X: i32 = 55; // CODEF (110, 0)
const TOP_Y: i32 = 0;

const bottomlogo_b = @embedFile("../assets/screens/noextra/bottomlogo.raw");
const BOT_W: i32 = 192;
const BOT_H: i32 = 68;
const BOT_X: i32 = 62; // CODEF (125, 342)
const BOT_Y: i32 = 171;

const dhs_b = @embedFile("../assets/screens/noextra/dhs.raw");
const DHS_W: i32 = 117;
const DHS_H: i32 = 45;

// scroller — CODEF tiles are 64x34 starting at char 32; halved, 32x17.
const font_b = @embedFile("../assets/screens/noextra/font.raw");
const FONT_SHEET_W: usize = 320;
const FONT_COLS: u8 = 10;
const GW: i32 = 32;
const GH: i32 = 17;
const FIRST_CHAR: u8 = 32;
const LAST_CHAR: u8 = 91; // the sheet holds 60 tiles, ' '..'['

// CODEF's letter ring: wide = ceil(canvas_width / fontw) + 1, looped i <= wide.
// Widened from the original's 320 to the full 400 physical columns; the ring
// formula is the original's, so spacing and wrap are unchanged.
const WIDE: i32 = @divTrunc(PW + GW - 1, GW) + 1; // 14
const NB_LETTERS: usize = @intCast(WIDE + 1); // 15
const SCROLL_SPEED: f32 = 4.5; // CODEF 9 px/frame at 640
const SCROLL_START: f32 = @floatFromInt(WIDE * GW);

// The screen's own scrolltext, verbatim. ']' is the marker that starts the
// vertical bob; it is also outside the font sheet, so it draws as a gap —
// exactly as in the original.
const SCROLL_TEXT =
    "    1..........2..........3..........4..........5..........6..........7..........8.........9.........10..........         ]          " ++
    " HERE WE GO ! ! !         WELCOME ON THE GREAT COMPILATION OF D.H.S.  :  THE ST DEMOSCREEN COMPETITION. " ++
    "            THANK YOU MR EVIL FOR PUTTING FORWARD THIS EVENT AT THE END OF THE YEAR 2005 AND GOOD LUCK " ++
    "TO THE COMPETITORS. THE PRIZES ARE VERY INTERESTING!!!         I WANT TO THANK THE CREW NOEXTRA TO PERMIT " ++
    "ME TO CODE WITH THEM.  THANK YOU TO ATOMUS AND BIG DISQUE TO MISTER A WHO LIVE IN ITALY.         " ++
    "....THAT'S ENOUGH OF THAT..... THIS IS MELLOWMAN HERE, BRINGING YOU HIS REMAKE OF THIS 2005 MEGADEMO SCREEN " ++
    "BY NOEXTRA TEAM! PART OF THE DHS MEGADEMO 2005..... HOPE YOU LIKE IT! GREETZ GOTO: NONAMENO, TOTORMAN, SOLO, " ++
    "FLUTTERSHY, AYOROS-IMPACT, JOHN MINDFUL, SHAZZ-TRSI, NEW CORE, AND ALL THE OTHER CODEF DUDES OUT THERE!!........        ";

// --- the original's tables, halved where they are pixel amplitudes ---------
// myfxparam1: {amp 150, inc 0.04, offset -0.05} + {amp -100, inc 0.01, offset 0.08}
// The inc is per 640-space ROW, so a halved row costs two of them.
const DIST_AMP_A: f32 = 75.0;
const DIST_AMP_B: f32 = -50.0;
const DIST_INC_A: f32 = 0.08;
const DIST_INC_B: f32 = 0.02;
const DIST_OFF_A: f32 = -0.05;
const DIST_OFF_B: f32 = 0.08;

// scrollfxparam: {amp 100, inc 0.0005, offset 0.02} — inc is per 640-space
// COLUMN, so 0.001 per ST column. posy 100 + the scrollcanvas' own 100 = 100
// in the halved layout.
const WAVE_AMP: f32 = 50.0;
const WAVE_INC: f32 = 0.001;
const WAVE_OFF: f32 = 0.02;
const WAVE_MID: f32 = 100.0;

// distcanvas2 is drawn at CODEF x=-250 with an x zoom of 0.9, so a destination
// column maps back to source column (2*x + 250) / 0.9, i.e. (2*x + 250) / 1.8
// in halved source pixels. x here is measured from the ORIGINAL screen's left
// edge, so the side borders are simply x < 0 and x >= 320 — the mapping extends
// into them unchanged. Stepped in 16.16 fixed point (see renderBand).
const SRC_STEP_FX: i32 = @intFromFloat(2.0 / 1.8 * 65536.0);
fn srcStartFx(shift: f32) i32 {
    return @intFromFloat((((2.0 * @as(f32, @floatFromInt(-BX))) + 250.0) / 1.8 - shift) * 65536.0);
}

// --- the intro (prego1..prego3), in halved coordinates --------------------
const DHS_Y_MIN: i32 = 60; // CODEF 120
const DHS_Y_MAX: i32 = 160; // CODEF 320
const DHS_Y_MARK: i32 = 110; // CODEF 220 — counted crossing
const DHS_CROSSINGS: u8 = 6; // CODEF flag >= 6
const FADE_STEP: f32 = 0.01;

// --- the bob (fx == 1) ----------------------------------------------------
const BOB_LIMIT: f32 = 40.0; // CODEF 80
const BOB_STEP: f32 = 1.5; // CODEF 3

const Phase = enum { fade_in, bounce, fade_out, main };

// --------------------------------------------------------------------------
// The border-opening trick. Registered at zg.OVERSCAN_MAGIC_X on BOTH overscan
// planes (each plane's own FB_HBL_POS is what the machine checks, so one
// handler registration does not cover the other plane).
//
// `line` here is PHYSICAL, 0..279 — an OVERSCAN plane's per-plane HBL fires on
// every scanline including the border bands. (A NORMAL plane's per-plane HBL
// is the one that counts 0..199; do not carry that rule over.)
//
// Flicker on EVERY row: top border opens at row 0, both side borders on each
// visible row (sides must be re-opened per line, as on real hardware), bottom
// border at row 240. The layout only needs the bottom border at rest, but the
// bob walks it +/-40 — with the top open it slides off the real screen edge
// instead of being chopped at an invisible line 40 rows in.
// --------------------------------------------------------------------------
fn handler_overscan(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = line;
    _ = col;
    fb.flickerBorder();
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// NOTE: demo_main.zig holds the cart as `var cart: Cart = undefined`, so these
// default field values are NEVER applied — the struct starts as zero bytes.
// Every field that needs a non-zero start is set in init() below.
pub const Demo = struct {
    blitter: zg.Blitter = .{},
    phase: Phase = .fade_in,

    // intro
    fade: f32 = 0.0,
    fade_shown: f32 = -1.0, // last value written to the palette
    dhs_y: i32 = DHS_Y_MIN,
    dhs_inc: i32 = 1, // CODEF yinc = 2
    crossings: u8 = 0,

    // main
    dist_a: f32 = 0.0,
    dist_b: f32 = 0.0,
    wave: f32 = 0.0,
    ring: zg.scrollring.Ring(f32, NB_LETTERS) = undefined,
    bob_on: bool = false,
    bob_y: f32 = 0.0,
    bob_inc: f32 = -BOB_STEP, // CODEF yyinc = -3: it rises first

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("NOEXTRA init", .{});

        self.blitter.init();
        self.resetState();
        setupPlanes(zigos);

        // "Mega 4" — nothing plays until the user turns sound on.
        zg.requestSong(MUSIC);

        self.ring = zg.scrollring.Ring(f32, NB_LETTERS).init(SCROLL_TEXT, SCROLL_START, @as(f32, GW));
    }

    // Field-by-field (see the note above the struct; and `self.* = .{}` on a
    // struct this size emits a duplicate data segment).
    fn resetState(self: *Demo) void {
        self.phase = .fade_in;
        self.fade = 0.0;
        self.fade_shown = -1.0;
        self.dhs_y = DHS_Y_MIN;
        self.dhs_inc = 1;
        self.crossings = 0;
        self.dist_a = 0.0;
        self.dist_b = 0.0;
        self.wave = 0.0;
        self.bob_on = false;
        self.bob_y = 0.0;
        self.bob_inc = -BOB_STEP;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;

        switch (self.phase) {
            .fade_in => {
                self.fade += FADE_STEP;
                if (self.fade > 2.0) {
                    self.fade = 1.0;
                    self.phase = .bounce;
                }
            },
            .bounce => self.updateBounce(),
            .fade_out => {
                self.fade -= FADE_STEP;
                if (self.fade < 0.0) {
                    self.fade = 0.0;
                    self.phase = .main;
                }
            },
            .main => self.updateMain(),
        }
    }

    // prego2: bounce between 60 and 160, counting the crossings of 110.
    fn updateBounce(self: *Demo) void {
        self.dhs_y += self.dhs_inc;
        if (self.dhs_y >= DHS_Y_MAX) self.dhs_inc = -1;
        if (self.dhs_y <= DHS_Y_MIN) self.dhs_inc = 1;
        if (self.dhs_y == DHS_Y_MARK) self.crossings += 1;
        if (self.crossings >= DHS_CROSSINGS) {
            self.dhs_y = DHS_Y_MARK;
            self.phase = .fade_out;
        }
    }

    fn updateMain(self: *Demo) void {
        // the two distorter phases and the scroll wave advance once per frame
        self.dist_a += DIST_OFF_A;
        self.dist_b += DIST_OFF_B;
        self.wave += WAVE_OFF;

        _ = self.ring.step(SCROLL_SPEED);

        // the marker: once the next character to come up is ']', the whole
        // screen bobs — and never stops (CODEF sets fx = 1 and leaves it).
        if (self.ring.upcoming() == ']') self.bob_on = true;

        if (self.bob_on) {
            self.bob_y += self.bob_inc;
            if (self.bob_y >= BOB_LIMIT) self.bob_inc = -BOB_STEP;
            if (self.bob_y <= -BOB_LIMIT) self.bob_inc = BOB_STEP;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;

        // the layout's top row in physical coordinates
        const top: i32 = BY + @as(i32, @intFromFloat(self.bob_y));

        var fb: *LogicalFB = &zigos.lfbs[0];
        @memset(fb.fb[0..FB_LEN], 0);

        if (self.phase == .main) {
            // CODEF's own order: raster, gradient bars, logos, then the scroller
            // on top of everything.
            self.showFade(fb, 1.0);
            self.renderBand(fb, top);
            self.blitter.blitImage(fb, @intCast(BX), @intCast(top + GRAD_TOP), gradbar_b, 320, 0, 0, 320, 1, 0);
            self.blitter.blitImage(fb, @intCast(BX), @intCast(top + GRAD_BOTTOM), gradbar_b, 320, 0, 0, 320, 1, 0);
            self.blitter.blitImage(fb, @intCast(BX + TOP_X), @intCast(top + TOP_Y), toplogo_b, @intCast(TOP_W), 0, 0, @intCast(TOP_W), @intCast(TOP_H), 0);
            self.blitter.blitImage(fb, @intCast(BX + BOT_X), @intCast(top + BOT_Y), bottomlogo_b, @intCast(BOT_W), 0, 0, @intCast(BOT_W), @intCast(BOT_H), 0);
            self.renderScroll(fb, top);
        } else {
            // intro: the D.H.S. logo alone on black, mid-handled at x = 160.
            // The canvas alpha is reproduced by scaling the palette, which over
            // a black ground is the same composite.
            self.showFade(fb, @min(self.fade, 1.0));
            self.blitter.blitImage(fb, @intCast(BX + 160 - @divTrunc(DHS_W, 2)), @intCast(top + self.dhs_y - @divTrunc(DHS_H, 2)), dhs_b, @intCast(DHS_W), 0, 0, @intCast(DHS_W), @intCast(DHS_H), 0);
        }
    }

    // Re-writing the palette is pointless once the fade has settled, and `main`
    // holds it at 1.0 forever.
    fn showFade(self: *Demo, fb: *LogicalFB, k: f32) void {
        if (k == self.fade_shown) return;
        self.fade_shown = k;
        fadePalette(fb, k);
    }

    // myfx1.sinx: every line of the rainbow is shifted horizontally by the sum
    // of two sines, then the whole band is placed at x = -250 with a 0.9 x-zoom.
    // Written straight into the plane's buffer, row base hoisted, source column
    // stepped in 16.16 fixed point — see the frame-cost note in the report.
    fn renderBand(self: *Demo, fb: *LogicalFB, top: i32) void {
        var r: i32 = 0;
        while (r < BAND_H) : (r += 1) {
            const py = top + BAND_TOP + r;
            if (py < 0 or py >= PH) continue;
            const fr: f32 = @floatFromInt(r);
            const shift = DIST_AMP_A * @sin(self.dist_a + DIST_INC_A * fr) +
                DIST_AMP_B * @sin(self.dist_b + DIST_INC_B * fr);
            const row: usize = @as(usize, @intCast(py)) * @as(usize, @intCast(PW));
            var u: i32 = srcStartFx(shift);
            var px: usize = 0;
            while (px < @as(usize, @intCast(PW))) : (px += 1) {
                // Widening past the original's 320 runs off the ends of the
                // 640-wide source; hold the edge pixel rather than punch a
                // moving black wedge into the side border (see the report).
                const c: i32 = @min(@max(u >> 16, 0), RASTER_W - 1);
                fb.fb[row + px] = raster_b[@intCast(c)];
                u += SRC_STEP_FX;
            }
        }
    }

    // scrollfx.siny: each COLUMN of the scroll layer is displaced vertically by
    // one very long sine (0.001 rad per ST column — a third of a period across
    // the screen), the whole wave drifting by 0.02 rad per frame.
    fn renderScroll(self: *Demo, fb: *LogicalFB, top: i32) void {
        const font_img = zg.blit.Image.init(font_b, FONT_SHEET_W);
        const dst = zg.blit.Dst.plane(fb);
        var i: usize = 0;
        while (i < NB_LETTERS) : (i += 1) {
            const c = self.ring.c[i];
            if (c < FIRST_CHAR or c > LAST_CHAR) continue; // ']' and friends: a gap
            const tile: usize = c - FIRST_CHAR;
            const sx0: usize = (tile % FONT_COLS) * @as(usize, GW);
            const sy0: usize = (tile / FONT_COLS) * @as(usize, GH);
            const x0: i32 = @intFromFloat(@floor(self.ring.x[i]));
            // the wave's phase is measured from the ORIGINAL screen's left edge,
            // so the visible window is untouched and the borders simply continue it
            const sum = zg.wave.SineSum(f32, 1){ .base = WAVE_MID, .amp = .{WAVE_AMP}, .phase = .{self.wave}, .inc = .{WAVE_INC}, .step = .multiply };
            var it = sum.sweep(x0 - BX);
            zg.wave.siny(dst, font_img, .{ .x = sx0, .y = sy0, .w = @intCast(GW), .h = @intCast(GH) }, x0, top, 1, &it, 0, .{ .flat = INK });
        }
    }
};

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
// ONE overscan plane. Index 0 is opaque black — the screen's ground — and the
// HBL at the magic column is what earns the borders.
fn setupPlanes(zigos: *ZigOS) void {
    // The top border stays shut, so it shows the machine's background: on a real
    // ST that is the border colour, and this screen's is black (the CODEF canvas
    // is filled '#000000' every frame). The default is a dark grey.
    zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

    const fb: *LogicalFB = &zigos.lfbs[0];
    fb.is_enabled = true;
    fb.setOverscanBuffer();
    fb.setPalette(screen_pal);
    fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_overscan);
}

// CODEF fades an image by drawing it with a canvas alpha. On a paletted plane
// over black the equivalent is scaling the palette's RGB. Only the logos' slice
// of the shared palette is touched — the rainbow is not on screen during the
// intro, and entry 0 stays the black ground.
fn fadePalette(fb: *LogicalFB, k: f32) void {
    zg.palette.scaleRange(fb, screen_pal, @intCast(LOGO_FIRST), @intCast(LOGO_LAST), k, .{});
}
