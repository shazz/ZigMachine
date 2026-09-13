// --------------------------------------------------------------------------
// THE REPLICANTS — "Garfield" crack intro (cracked by Dom, member of The Union).
//
// Ported from the CODEF HTML5 remake by NoNameNo (wab.com screen 28, MIT).
// Graphics, scrolltext and the original ST intro belong to The Replicants;
// music: "Pro BMX Simulator" (docs/music/pro_bmx_simulator_a.sndh).
//
// Reference kept at prototypes/codef/28/ (tools/fetch_codef.py 28).
// Assets: tools/replicants_garfield_assets.py.
//
// The remake is 640x400 = ST 320x200 doubled. Every number below is quoted in
// the original's 640-space and halved only where a pixel is emitted, so the
// tables and increments stay exactly the source's.
//
// What go() draws, back to front, and where it lands here:
//
//   1. Four 22-row raster bars (blue, pink, yellow, gray — in that paint order),
//      each ping-ponging 1.5/frame between 50 and 270. The bars are uniform
//      per row, so they are a colour per LINE: every pixel the frame leaves
//      transparent is index 0, whose palette entry the copper rewrites every line.
//   2. background.png (red frame, open in the middle) and — drawn last in the
//      original — backgroundMask.png at y=294. Nothing ever lands on the
//      mask's opaque part except scroller pixels, which the mask would hide
//      anyway, so both are baked into frame.raw and the scroller is clipped to
//      the mask's hole.
//   3. The scroller: 32x32 font at y=26 of a 640x60 canvas, 'source-atop'
//      fontsMask3.png — the glyph keeps its SHAPE and takes the mask's COLOUR
//      at that pixel — blitted at (32,316). So a glyph pixel here is simply
//      fontmask[x, y]: zg.blit's .pattern ink.
//   4. The logo: logo.png at x=18 of a 640x326 offscreen, sine-shifted per row
//      by fx.sinx {amp 20, inc 0.06, offset -0.06}, recoloured 'source-in' by
//      six stacked copies of rasterFont4.png at y=rasterFontPos, then
//        drawPart(main, 50, logoPos, 0, logoPos-16, 640, 58)
//      Destination y minus source y is always 16, so the logo NEVER MOVES: it
//      sits at y=16 and a 58-row window onto it slides between 26 and 282.
//      The 'source-in' gradient depends only on the source row, i.e. on the
//      screen row, so the ink is one index recoloured per line by the copper.
//
// All of it is ONE plane. Every enabled plane costs the browser a full-screen
// RGBA copy and a composited layer per frame, which is what held earlier
// three-plane ports to 20fps. Each frame therefore restores frame.raw and draws
// the glyphs and the logo window over it, and one copper sets both per-line
// entries. This works because the frame's reds are the mask's reds, so a single
// 8-entry palette holds everything (checked at comptime below).
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const assert = std.debug.assert;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const blit = zg.blit;
const copper = zg.copper;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const WIDTH: u16 = zg.WIDTH;
const HEIGHT: u16 = zg.HEIGHT;

const MUSIC = "pro_bmx_simulator_a.sndh";

const PLANE = 0;

// palette indices (1..6 are frame_pal's reds, which the mask's colours reuse)
const RASTER_INK: u8 = 0; // frame.raw's transparent index: the bars show through
const LOGO_INK: u8 = 7; // the first index frame_pal leaves free

// copper slots, in the order of the entries handed to copper.install
const RASTER_SLOT: copper.Slot = 0;
const INK_SLOT: copper.Slot = 1;
// the copper's per-line tables, one per slot (module scope: the Demo arrives zeroed)
var copper_tables: [2]copper.Table = undefined;

// raster bars (640-space) — order is paint order: gray ends up on top
const BAR_ROWS: i32 = 22;
const RASTERS_TOP: f64 = 50;
const RASTERS_BOTTOM: f64 = 270;
const BAR_START = [4]f64{ RASTERS_TOP, RASTERS_TOP + 100, RASTERS_TOP + 200, 192 };
const BAR_INC = [4]f64{ 1.5, 1.5, 1.5, -1.5 };

// the logo window (640-space)
const LOGO_TOP: f64 = 16;
const LOGO_BOTTOM: f64 = 282;
const LOGO_STEP: f64 = 1.8;
const LOGO_WINDOW_ST: i32 = 58 / 2;
const LOGO_X_ST: i32 = (50 + 18) / 2; // drawPart x + where logo.png sits in the offscreen
const LOGO_Y_ST: i32 = 16 / 2;
const LOGO_W: usize = 268;
const LOGO_H: usize = 163;

// fx.sinx parameters, verbatim
const SIN_AMP: f64 = 20;
const SIN_INC: f64 = 0.06;
const SIN_OFFSET: f64 = -0.06;

// rasterFont4.png stacked six times, scrolled 3/frame, reset at +-60
const GRAD_ROWS: i32 = 60;
const GRAD_STEP: i32 = 3;

// scroller. Positions are kept in HALF 640-pixels (= quarter ST pixels) so the
// 3.5/frame speed is the exact integer 7.
const GLYPH: usize = 16; // ST size of the 32x32 tile
const FONT_COLS: usize = 10;
const FONT_ROWS: usize = 6; // fonts2.png is 320x192
const FONT_FIRST: u8 = 32;
const SCROLL_SPEED_Q: i32 = 7; // 3.5 * 2
const GLYPH_Q: i32 = 64; // 32 * 2
const SCROLL_LETTERS: usize = 22; // wide = ceil(640/32)+1 = 21, letters 0..21
const SCROLL_START_Q: i32 = 21 * 32 * 2; // first letter at wide*fontw = 672
const SCROLL_X_ST: u16 = 32 / 2; // scrollcanvas blitted at (32,316)
const SCROLL_Y_ST: u16 = 316 / 2;
const TEXT_Y_ST: usize = 26 / 2; // scrolltext.draw(26)
const MASK_W: usize = 288; // fontsMask3.png halved; also the mask hole's width
const MASK_H: usize = 34;

const SCROLL_TEXT = " THE UNION PRESENTS : - GARFIELD - CRACKED BY DOM FROM THE REPLICANTS MEMBER OF THE UNION. MEMBERS OF THE REPLICANTS ARE : ELWOOD(NEW MEMBER!!),DOM,<R.AL>,SNAKE,COBRA,KNIGHT 2OO1,GO HAINE,EXCALIBUR,RANK-XEROX,HANNIBAL,GOLDORAK...... HI TO : LOCKBUSTERS,THE BLADE RUNNERS,B.O.S.S,WAS (NOT WAS),MCA,THE PREDATORS     A SPECIAL HI TO ALL MEMBERS OF THE MICRO CLUB LILLOIS!!!!!!!!........BYE BYE.......SEE YOU A NEXT TIME....      ";

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const frame_b = @embedFile("../assets/screens/replicants_garfield/frame.raw");
const frame_pal = convertU8ArraytoColors(@embedFile("../assets/screens/replicants_garfield/frame_pal.dat"));
const logo_b = @embedFile("../assets/screens/replicants_garfield/logo.raw");
const font_b = @embedFile("../assets/screens/replicants_garfield/font.raw");
const fontmask_b = @embedFile("../assets/screens/replicants_garfield/fontmask.raw");
const text_pal = convertU8ArraytoColors(@embedFile("../assets/screens/replicants_garfield/text_pal.dat"));
// one colour per 640-space row: 4 bars of 22, then the 60-row logo gradient
const rows = convertU8ArraytoColors(@embedFile("../assets/screens/replicants_garfield/rows.dat"));
const GRAD_BASE: usize = 4 * BAR_ROWS;

const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

comptime {
    assert(frame_b.len == @as(usize, WIDTH) * HEIGHT);
    assert(logo_b.len == LOGO_W * LOGO_H);
    assert(font_b.len == FONT_COLS * GLYPH * FONT_ROWS * GLYPH);
    assert(fontmask_b.len == MASK_W * MASK_H);
    // every character has a glyph
    for (SCROLL_TEXT) |c| assert(c >= FONT_FIRST and c - FONT_FIRST < FONT_COLS * FONT_ROWS);
    // the glyph band stays inside the mask and the screen
    assert(TEXT_Y_ST + GLYPH <= MASK_H);
    assert(SCROLL_X_ST + MASK_W <= WIDTH and SCROLL_Y_ST + TEXT_Y_ST + GLYPH <= HEIGHT);
    // the sine-shifted logo never leaves the screen. drawScanline drops a run
    // whose end equals the width, hence the strict <
    const shift_max: i32 = @intFromFloat(SIN_AMP / 2.0);
    assert(LOGO_X_ST - shift_max >= 0 and LOGO_X_ST + shift_max + LOGO_W < WIDTH);
}

// --------------------------------------------------------------------------
// The one palette: frame_pal as-is, the mask's colours folded onto the frame's
// identical reds, and the logo ink in the first free slot.
// --------------------------------------------------------------------------
const palette: [256]Color = blk: {
    @setEvalBranchQuota(1_000_000);
    for (frame_b) |px| assert(px < LOGO_INK);
    var p = frame_pal;
    p[RASTER_INK] = BLACK;
    p[LOGO_INK] = text_pal[1];
    break :blk p;
};

/// text_pal index -> palette index, for fontmask.raw's pixels.
const mask_remap: [256]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var m = [_]u8{0} ** 256;
    for (fontmask_b) |ti| {
        const want = text_pal[ti];
        const found = for (1..LOGO_INK) |fi| {
            const c = frame_pal[fi];
            if (c.r == want.r and c.g == want.g and c.b == want.b and c.a == want.a) break fi;
        } else @compileError("fontmask colour missing from frame_pal: one shared palette no longer fits");
        m[ti] = @intCast(found);
    }
    break :blk m;
};

/// fontmask.raw already in palette indices: the 'source-atop' colouring image.
const fontmask_ink: [MASK_W * MASK_H]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var out: [MASK_W * MASK_H]u8 = undefined;
    for (fontmask_b, &out) |ti, *o| o.* = mask_remap[ti];
    break :blk out;
};

const font_img = blit.Image.init(font_b, FONT_COLS * GLYPH);
const mask_ink = blit.Ink{ .pattern = .{ .img = blit.Image.init(&fontmask_ink, MASK_W), .ox = 0, .oy = 0 } };

// --------------------------------------------------------------------------
// The logo as horizontal ink runs, built at comptime: a window row becomes a
// few drawScanline calls instead of 268 pixel writes.
// --------------------------------------------------------------------------
const logo = zg.spans.build(logo_b, LOGO_W, 0);

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    // f64, as JS numbers are: the 1.8 steps accumulate the same rounding.
    sin_phase: f64,
    sin_drawn: f64, // phase fx.sinx used this frame
    logo_pos: f64,
    logo_inc: f64,
    bar_pos: [4]f64,
    bar_inc: [4]f64,
    bar_drawn: [4]f64,
    grad_pos: i32,
    grad_drawn: i32,
    ring: zg.scrollring.Ring(i32, SCROLL_LETTERS), // scroll canvas x, quarter ST pixels

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here, never by default.
        self.sin_phase = 0;
        self.sin_drawn = 0;
        self.logo_pos = LOGO_TOP;
        self.logo_inc = LOGO_STEP;
        self.bar_pos = BAR_START;
        self.bar_inc = BAR_INC;
        self.bar_drawn = BAR_START;
        self.grad_pos = 0;
        self.grad_drawn = 0;
        self.ring = zg.scrollring.Ring(i32, SCROLL_LETTERS).init(SCROLL_TEXT, SCROLL_START_Q, GLYPH_Q);

        zg.requestSong(MUSIC);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(palette);
        @memcpy(fb.fb[0..frame_b.len], frame_b);
        // seeds every line with the palette's own black bars / logo ink
        copper.install(fb, &.{ RASTER_INK, LOGO_INK }, &copper_tables, .{});
    }

    /// Advances state in exactly go()'s order, recording the values go() DRAWS
    /// with where that differs from the value it leaves behind.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;

        self.sin_drawn = self.sin_phase;
        self.sin_phase += SIN_OFFSET;

        self.logo_pos += self.logo_inc;
        if (self.logo_pos <= LOGO_TOP + 10) self.logo_inc = LOGO_STEP;
        if (self.logo_pos >= LOGO_BOTTOM) self.logo_inc = -LOGO_STEP;

        for (0..4) |b| {
            self.bar_drawn[b] = self.bar_pos[b];
            self.bar_pos[b] += self.bar_inc[b];
            if (self.bar_pos[b] < RASTERS_TOP or self.bar_pos[b] > RASTERS_BOTTOM)
                self.bar_inc[b] = -self.bar_inc[b];
        }

        // scrolltext_horizontal: every letter moves 3.5; the one that reaches
        // -32 rejoins the back of the ring carrying the next character.
        _ = self.ring.step(SCROLL_SPEED_Q);

        // the gradient runs the way the logo window is travelling
        const dir: i32 = if (self.logo_inc > 0) -1 else 1;
        self.grad_drawn = self.grad_pos;
        self.grad_pos -= dir * GRAD_STEP;
        if (self.grad_pos >= GRAD_ROWS) self.grad_pos = 0;
        if (self.grad_pos <= -GRAD_ROWS) self.grad_pos = 0;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        self.buildRasterLines(copper.visible(fb, RASTER_SLOT));
        self.buildInkLines(copper.visible(fb, INK_SLOT));

        // paint order: bars (index 0) + frame, glyphs, logo
        @memcpy(fb.fb[0..frame_b.len], frame_b);
        self.drawScroller(fb);
        self.drawLogoWindow(fb);
    }

    /// Paint the bars into the per-line table in go()'s order. A bar at a
    /// fractional 640-space y covers ST line k with its row floor(2k - pos).
    fn buildRasterLines(self: *Demo, line: *[HEIGHT]u32) void {
        @memset(line, BLACK.toRGBA());
        for (self.bar_drawn, 0..) |pos, b| {
            var k: i32 = @intFromFloat(@ceil(pos / 2.0));
            while (k < HEIGHT) : (k += 1) {
                const r: i32 = @intFromFloat(@floor(@as(f64, @floatFromInt(2 * k)) - pos));
                if (r >= BAR_ROWS) break;
                if (k >= 0 and r >= 0) line[@intCast(k)] = rows[b * BAR_ROWS + @as(usize, @intCast(r))].toRGBA();
            }
        }
    }

    /// The 'source-in' gradient: screen row Y shows logo source row Y-16, which
    /// the stacked rasterFont4 copies colour with row (Y-16-rasterFontPos) mod 60.
    fn buildInkLines(self: *Demo, line: *[HEIGHT]u32) void {
        for (line, 0..) |*c, k| {
            const y: i32 = 2 * @as(i32, @intCast(k)) - 16 - self.grad_drawn;
            c.* = rows[GRAD_BASE + @as(usize, @intCast(@mod(y, GRAD_ROWS)))].toRGBA();
        }
    }

    /// Only the window's 29 ST rows are drawn; the logo itself never moves.
    fn drawLogoWindow(self: *Demo, fb: *LogicalFB) void {
        const top: i32 = @intFromFloat(@round(self.logo_pos / 2.0));
        // the window clipped to the logo; both ends are >= LOGO_Y_ST, so non-negative
        const first = @max(top, LOGO_Y_ST);
        const end = @min(top + LOGO_WINDOW_ST, LOGO_Y_ST + LOGO_H, HEIGHT);
        if (end <= first) return;
        for (@as(usize, @intCast(first))..@as(usize, @intCast(end))) |y| {
            const s = y - LOGO_Y_ST;
            // fx.sinx: source row i (640-space, = 2*s) shifted by sin(phase + i*0.06)*20
            const prov = SIN_AMP * @sin(self.sin_drawn + SIN_INC * @as(f64, @floatFromInt(2 * s)));
            // >= 0 and run ends < WIDTH: asserted at comptime above
            const x: i32 = LOGO_X_ST + @as(i32, @intFromFloat(@floor(prov / 2.0)));
            for (logo.row(s)) |span| {
                fb.drawScanline(@intCast(x + span.x0), @intCast(x + span.x1), @intCast(y), LOGO_INK);
            }
        }
    }

    /// Each 16x16 glyph takes fontsMask3's colour at the same scroll-canvas
    /// pixel ('source-atop'), clipped to the mask, which is also the hole
    /// backgroundMask leaves open.
    fn drawScroller(self: *Demo, fb: *LogicalFB) void {
        const hole = blit.Dst.plane(fb).window(SCROLL_X_ST, SCROLL_Y_ST, MASK_W, MASK_H);
        // the ring's array order is rotated (unlike the old head model, where
        // index order was left-to-right), so every letter is offered to blit,
        // which clips out anything past the mask on its own — no early exit.
        for (self.ring.x, self.ring.c) |q, c| {
            const gx = @divFloor(q, 4); // ST x within the scroll canvas
            const nb: usize = c - FONT_FIRST;
            const cell = blit.Rect{ .x = (nb % FONT_COLS) * GLYPH, .y = (nb / FONT_COLS) * GLYPH, .w = GLYPH, .h = GLYPH };
            blit.blit(hole, font_img, cell, gx, TEXT_Y_ST, 0, mask_ink);
        }
    }
};
