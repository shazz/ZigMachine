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
//
// NO FLOAT PER FRAME (2026-10-24): the scroller wave runs in fixed point (no
// per-frame float on ZIGGY); edge pixels may differ by 1 px from the old f32
// wave. The wave's phase is now u64 turns advanced by exactly 0.02 rad a frame
// (the original's JS doubles), where the old f32 accumulator had drifted
// 0.06 rad by frame 20,000, so late in a long run the letters sit further
// from where the f32 cart put them: <= 1 px up to frame ~17,000 (4.7 min),
// 2-3 px by frame 20,000, and growing with the old drift. The sines
// (wave and band) are zg.fixtrig's table, the ring counts half pixels (exact),
// and the intro fades are f32 replayed at comptime (noextra_fade.zig, exact).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const fx = @import("turns_fix.zig");
const band = @import("noextra_band.zig");
const scroll = @import("noextra_scroll.zig");
const fade = @import("noextra_fade.zig");
const trig = zg.fixtrig;
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
// The ring runs in HALF pixels (integers): CODEF's 9 px/frame at 640 is 4.5 here,
// and every position the f32 ring held was a multiple of 0.5, so this is exact.
const SCROLL_SPEED_H: i32 = 9;
const SCROLL_START_H: i32 = 2 * WIDE * GW;
const Ring = zg.scrollring.Ring(i32, NB_LETTERS);

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
// The phases are u64 turns (turns_fix.zig) and the two sines zg.fixtrig Q16.16: no libm per row.
const DIST_AMP_A: i32 = 75;
const DIST_AMP_B: i32 = -50;
const DIST_INC_A = fx.turns(0.08);
const DIST_INC_B = fx.turns(0.02);
const DIST_OFF_A = fx.turns(-0.05);
const DIST_OFF_B = fx.turns(0.08);

// scrollfxparam: {amp 100, inc 0.0005, offset 0.02} — inc is per 640-space
// COLUMN, so 0.001 per ST column. posy 100 + the scrollcanvas' own 100 = 100
// in the halved layout.
// In u64 turns and zg.fixtrig (Q16.16), like the band: no float per frame.
const WAVE_AMP: i32 = 50;
const WAVE_INC = fx.turns(0.001);
const WAVE_OFF = fx.turns(0.02);
const WAVE_MID: i32 = 100;

// distcanvas2 is drawn at CODEF x=-250 with an x zoom of 0.9, so a destination
// column maps back to source column (2*x + 250) / 0.9, i.e. (2*x + 250) / 1.8
// in halved source pixels. x here is measured from the ORIGINAL screen's left
// edge, so the side borders are simply x < 0 and x >= 320 — the mapping extends
// into them unchanged. Stepped in 16.16 fixed point (see renderBand).
const SRC_STEP_FX: i32 = @intFromFloat(2.0 / 1.8 * 65536.0);
/// Q16 start column for a row whose sine sum is `shift` (Q16 source pixels).
const SRC_START_FX: i32 = @intFromFloat((((2.0 * @as(f32, -BX)) + 250.0) / 1.8) * 65536.0);
fn srcStartFx(shift: i32) i32 {
    return SRC_START_FX - shift;
}

// --- the intro (prego1..prego3), in halved coordinates --------------------
const DHS_Y_MIN: i32 = 60; // CODEF 120
const DHS_Y_MAX: i32 = 160; // CODEF 320
const DHS_Y_MARK: i32 = 110; // CODEF 220 — counted crossing
const DHS_CROSSINGS: u8 = 6; // CODEF flag >= 6

// --- the bob (fx == 1) ----------------------------------------------------
// kept doubled (half pixels): the 1.5 step is whole there
const BOB_LIMIT: i32 = 80; // 40 px, CODEF 80
const BOB_STEP: i32 = 3; // 1.5 px, CODEF 3

const NO_FADE: u32 = 0xFFFF_FFFF; // no Q23 factor is this: the first fade always writes

const Shown = enum { nothing, intro, main };
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
    fade_n: u16 = 0, // updates into the current fade (noextra_fade.zig's tables)
    fade_shown: u32 = NO_FADE, // last Q23 factor written to the palette
    dhs_y: i32 = DHS_Y_MIN,
    dhs_inc: i32 = 1, // CODEF yinc = 2
    crossings: u8 = 0,

    // main. The distorter and wave phases are u64 turns: f32 accumulators drift (the old
    // distorter's ~9e-4 rad by frame 900, the old wave's 0.06 rad by frame 20,000).
    dist_a: u64 = 0,
    dist_b: u64 = 0,
    wave: u64 = 0, // u64 turns, as the distorter's
    ring: Ring = undefined,
    bob_on: bool = false,
    bob_y: i32 = 0, // doubled
    bob_inc: i32 = -BOB_STEP, // CODEF yyinc = -3: it rises first

    // what the plane holds, so a frame repaints only what changed
    shown: Shown = .nothing,
    logo_x: i32 = 0, // where the intro's D.H.S. logo was drawn
    logo_y: i32 = 0,
    main_top: i32 = 0, // the layout top the logos were last drawn at, in `main`

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("NOEXTRA init", .{});

        self.blitter.init();
        self.resetState();
        setupPlanes(zigos);

        // "Mega 4" — nothing plays until the user turns sound on.
        zg.requestSong(MUSIC);

        self.ring = Ring.init(SCROLL_TEXT, SCROLL_START_H, 2 * GW);
    }

    // Field-by-field (see the note above the struct; and `self.* = .{}` on a
    // struct this size emits a duplicate data segment).
    fn resetState(self: *Demo) void {
        self.phase = .fade_in;
        self.fade_n = 0;
        self.fade_shown = NO_FADE;
        self.dhs_y = DHS_Y_MIN;
        self.dhs_inc = 1;
        self.crossings = 0;
        self.dist_a = 0;
        self.dist_b = 0;
        self.wave = 0;
        self.bob_on = false;
        self.bob_y = 0;
        self.bob_inc = -BOB_STEP;
        self.shown = .nothing;
        self.logo_x = 0;
        self.logo_y = 0;
        self.main_top = 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;

        switch (self.phase) {
            .fade_in => {
                self.fade_n += 1;
                if (self.fade_n >= fade.IN.len) {
                    self.fade_n = 0;
                    self.phase = .bounce;
                }
            },
            .bounce => self.updateBounce(),
            .fade_out => {
                self.fade_n += 1;
                if (self.fade_n >= fade.OUT.len) self.phase = .main;
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
        self.dist_a +%= DIST_OFF_A;
        self.dist_b +%= DIST_OFF_B;
        self.wave +%= WAVE_OFF;

        _ = self.ring.step(SCROLL_SPEED_H);

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
        const top: i32 = BY + @divTrunc(self.bob_y, 2); // trunc, as the float cast was

        const fb: *LogicalFB = &zigos.lfbs[0];

        if (self.phase == .main) {
            self.showFade(fb, fade.ONE);
            // CODEF's own order is raster, gradient bars, logos, scroller. The logos
            // (layout rows 0..45 and 171..238) share no row with the band, its bars
            // and the scroller (50..169), so they can go first, and only when they move.
            self.renderLogos(fb, top);
            self.renderBand(fb, top);
            self.blitter.blitImage(fb, @intCast(BX), @intCast(top + GRAD_TOP), gradbar_b, 320, 0, 0, 320, 1, 0);
            self.blitter.blitImage(fb, @intCast(BX), @intCast(top + GRAD_BOTTOM), gradbar_b, 320, 0, 0, 320, 1, 0);
            self.renderScroll(fb, top);
        } else {
            // intro: the D.H.S. logo alone on black, mid-handled at x = 160.
            // The canvas alpha is reproduced by scaling the palette, which over
            // a black ground is the same composite.
            self.showFade(fb, switch (self.phase) {
                .fade_in => fade.IN[self.fade_n],
                .fade_out => fade.OUT[self.fade_n],
                else => fade.ONE,
            });
            self.drawLogo(fb, BX + 160 - @divTrunc(DHS_W, 2), top + self.dhs_y - @divTrunc(DHS_H, 2));
        }
    }

    fn fillRows(self: *Demo, fb: *LogicalFB, from: i32, to: i32) void {
        if (to > from) self.blitter.fill(fb, 0, @intCast(from), @intCast(PW), @intCast(to - from), 0);
    }

    /// Black where a rect (layout rows y..y+h, columns x..x+w) was at `old` and is
    /// not at `top`: the rows the move uncovered, clipped to the plane.
    fn eraseVacated(self: *Demo, fb: *LogicalFB, x: i32, y: i32, w: i32, h: i32, old: i32, top: i32) void {
        const from = if (top > old) old + y else @max(top + y + h, old + y);
        const to = if (top > old) @min(old + y + h, top + y) else old + y + h;
        const y0 = std.math.clamp(from, 0, PH);
        const y1 = std.math.clamp(to, 0, PH);
        if (y1 > y0) self.blitter.fill(fb, @intCast(x), @intCast(y0), @intCast(w), @intCast(y1 - y0), 0);
    }

    // Outside the band the plane holds only black and the two logos (the band
    // repaints its own rows edge to edge every frame). On entering `main` the
    // CHISEL blackens every row the band does not cover; afterwards, when the bob
    // moves the layout, it blackens only the rows the logos and the band left.
    // The logos are then copied UNKEYED: their own black (index 0, the key they
    // were drawn with) lands on a ground that is black or the old logo, so the
    // bytes are the keyed draw's. When the layout does not move, nothing is drawn.
    fn renderLogos(self: *Demo, fb: *LogicalFB, top: i32) void {
        if (self.shown != .main) {
            self.fillRows(fb, 0, std.math.clamp(top + BAND_TOP, 0, PH));
            self.fillRows(fb, std.math.clamp(top + BAND_TOP + BAND_H, 0, PH), PH);
            self.shown = .main;
        } else if (top == self.main_top) {
            return;
        } else {
            const old = self.main_top;
            self.eraseVacated(fb, BX + TOP_X, TOP_Y, TOP_W, TOP_H, old, top);
            self.eraseVacated(fb, BX + BOT_X, BOT_Y, BOT_W, BOT_H, old, top);
            self.eraseVacated(fb, 0, BAND_TOP, PW, BAND_H, old, top);
        }
        self.main_top = top;
        self.blitter.blitImage(fb, @intCast(BX + TOP_X), @intCast(top + TOP_Y), toplogo_b, @intCast(TOP_W), 0, 0, @intCast(TOP_W), @intCast(TOP_H), null);
        self.blitter.blitImage(fb, @intCast(BX + BOT_X), @intCast(top + BOT_Y), bottomlogo_b, @intCast(BOT_W), 0, 0, @intCast(BOT_W), @intCast(BOT_H), null);
    }

    /// The logo is keyed on black: moving it means blackening where it was, not the plane.
    /// It sits still through the fades, and then nothing is repainted at all.
    fn drawLogo(self: *Demo, fb: *LogicalFB, x: i32, y: i32) void {
        if (self.shown == .intro) {
            if (x == self.logo_x and y == self.logo_y) return;
            self.blitter.fill(fb, @intCast(self.logo_x), @intCast(self.logo_y), @intCast(DHS_W), @intCast(DHS_H), 0);
        } else {
            self.fillRows(fb, 0, PH);
        }
        self.shown = .intro;
        self.logo_x = x;
        self.logo_y = y;
        self.blitter.blitImage(fb, @intCast(x), @intCast(y), dhs_b, @intCast(DHS_W), 0, 0, @intCast(DHS_W), @intCast(DHS_H), 0);
    }

    // Re-writing the palette is pointless once the fade has settled, and `main`
    // holds it at 1.0 forever.
    fn showFade(self: *Demo, fb: *LogicalFB, k: u32) void {
        if (k == self.fade_shown) return;
        self.fade_shown = k;
        fadePalette(fb, k);
    }

    // myfx1.sinx: every line of the rainbow is shifted horizontally by the sum
    // of two sines, then the whole band is placed at x = -250 with a 0.9 x-zoom.
    // Written straight into the plane's buffer, row base hoisted, source column
    // stepped in 16.16 fixed point; the colour is computed, not looked up (noextra_band.zig).
    fn renderBand(self: *Demo, fb: *LogicalFB, top: i32) void {
        var pa = self.dist_a; // row r's phases: dist + r * inc, stepped
        var pb = self.dist_b;
        var r: i32 = 0;
        while (r < BAND_H) : ({
            r += 1;
            pa +%= DIST_INC_A;
            pb +%= DIST_INC_B;
        }) {
            const py = top + BAND_TOP + r;
            if (py < 0 or py >= PH) continue;
            const shift = DIST_AMP_A * trig.sin(fx.hi(pa)) + DIST_AMP_B * trig.sin(fx.hi(pb)); // Q16 px
            // 400 columns and every row start are multiples of 4
            const words: [*]u32 = @ptrCast(@alignCast(fb.fb + @as(usize, @intCast(py)) * @as(usize, @intCast(PW))));
            band.row(words[0 .. @as(usize, @intCast(PW)) / 4], srcStartFx(shift), SRC_STEP_FX, raster_b);
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
            const x0: i32 = self.ring.x[i] >> 1; // floor of the half-pixel position
            // the wave's phase is measured from the ORIGINAL screen's left edge,
            // so the visible window is untouched and the borders simply continue it
            const wave = scroll.Wave{ .phase = self.wave +% WAVE_INC *% @as(u64, @bitCast(@as(i64, x0 - BX))), .inc = WAVE_INC, .mid = WAVE_MID, .amp = WAVE_AMP };
            scroll.letter(zg.blit, dst, font_img, sx0, sy0, GW, @intCast(GH), x0, top, wave, INK);
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
fn fadePalette(fb: *LogicalFB, k: u32) void {
    for (LOGO_FIRST..LOGO_LAST + 1) |i| fb.setPaletteEntry(@intCast(i), fade.scale(screen_pal[i], k));
}
