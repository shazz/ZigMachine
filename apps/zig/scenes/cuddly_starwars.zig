// --------------------------------------------------------------------------
// THE CAREBEARS — "The Starwars Scroller", The Cuddly Demos (The Union).
//
// Ported from the CODEF HTML5 remake (wab.com screen 360, MIT, CODEF by
// NoNameNo). Graphics, texts and the original ST screen belong to The
// Carebears; UNION sprites Knight Hawks, font Amiga, music Mad Max.
// Music: the remake's "Cuddly - Star-Wars.ym" is, by its own YM header, Bangkok
// Knights (Hippel/Hubbard); played here from its SNDH, docs/music/bangkok_knights.sndh.
//
// Reference kept at prototypes/codef/360/. Assets and tables.zig:
// tools/cuddly_starwars_assets.py. Motion tables: cuddly_starwars/motion.zig.
//
// Geometry: every drawing call targets a 320x200 canvas (orgcanvas) that is
// zoomed 2x onto the 768x540 page at (64,64) — a plain ST 320x200 framed by a
// border. The PNGs are native 1x. So this is a NORMAL 320x200 plane, nothing
// halved and no overscan.
//
// go(), back to front, all on ONE plane (as the original is one canvas):
//   1. bg.png at (30,10), alpha fade*0.05: invisible except a 39-frame fade-out
//      every 301 frames. Two palette entries scaled per frame.
//   2. 400 stars rotating (rotc -= 0.02) and approaching (z -= 1.5), plotted as
//      1x1 rects at sub-pixel positions, which the canvas spreads over 4 pixels
//      by area. Greys live on a 128-level ramp so that blend is exact.
//   3. The starwars scroller: 30 lines of 17x11 glyphs on a text canvas, pushed
//      through the perspective table (motion.zig) into rows 100..199 as grey
//      coverage over the stars.
//   4. The distorted scroller, 20 columns of 16 each shifted by dist1: fontr
//      recoloured by the raster ('source-in'), then fontg on the SAME positions.
//      The two fonts' inks never overlap, so they are one merged font; the red
//      ink is palette index 1, rewritten per line by the HBL from the raster.
//   5. "THE UNION" as 8 sprites walking a recorded path with a sine wobble.
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const tables = @import("cuddly_starwars/tables.zig");
const motion = @import("cuddly_starwars/motion.zig");
const fixed = @import("cuddly_starwars/fixed.zig");
const assert = std.debug.assert;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

// --------------------------------------------------------------------------
// Constants (the original's numbers)
// --------------------------------------------------------------------------
const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;
const PLANE = 0;
const MUSIC = "bangkok_knights.sndh";

// palette (screen_pal.dat holds 0..15; the grey ramp is built below)
const BLACK: u8 = 0;
const RASTER_INK: u8 = 1;
const BG_ORANGE: u8 = 8;
const BG_GREY: u8 = 9;
const LOGO_FLASH_ENTRIES = [_]u8{ BG_ORANGE, BG_GREY };
const GREY_BASE: u8 = 128;
const GREY_LEVELS: usize = 128;

// logo flash
const FLASH_WRAP: u32 = 300;
const FLASH_AT: u32 = 280;
const FADE_START: f64 = 20;
const FADE_STEP: f64 = 0.5;
const FADE_ALPHA: f64 = 0.05;
const BG_X: usize = 30;
const BG_Y: usize = 10;
const BG_W: usize = 260;
const BG_H: usize = 73;

// starfield
const STARS: usize = 400;
// z runs in units of 25 milli (STAR_Z_SIZE = 130 = 5200 units, lattice spacing 0.325 = 13
// units, speed 1.5 per frame = 60 units); see fixed.zig for k = 128 / z.
const STAR_Z_UNITS: i32 = 5200;
const STAR_Z_PITCH: i32 = 13;
const STAR_Z_SPEED: i32 = 60;
const STAR_GREYS = [3]u32{ 0xff, 0xaa, 0x55 }; // near .. far
const ROT_START: f64 = 180;
const ROT_STEP_C = fixed.q30(@cos(0.02));
const ROT_STEP_S = fixed.q30(@sin(-0.02)); // rot -= 0.02

// starwars scroller
const SW_GLYPH_W: usize = 17;
const SW_GLYPH_H: usize = 11;
const SW_FONT_W: usize = 170;
const SW_FONT_H: usize = 69;
const SW_COLS: usize = 10;
const SW_LINES: usize = 30;
const SW_PITCH_X: usize = 20;
const SW_PITCH_Y: i32 = 17;
const SW_LINE_CHARS: usize = 12;
const SW_X: usize = (300 - SW_LINE_CHARS * 16) / 2 - 8; // letterpos = 46
const SW_BAND_Y: usize = 100;

// distorted scroller
const GLYPH_W: usize = 32;
const GLYPH_H: usize = 26;
const FONT_COLS: usize = 10;
const FONT_W: usize = 320;
const FONT_H: usize = 156;
const FIRST_CHAR: u8 = 32;
const SCROLL_H: usize = 25; // scrollcanvas is 25 tall: the glyphs' last row is cut
const SCROLL_SPEED: i32 = 8;
const LETTERS: usize = 12; // wide = ceil(320/32)+1 = 11, letters 0..wide
const RING_BACK: i32 = 11 * 32; // wide*fontw
const COLUMNS: usize = 20;
const COLUMN_W: usize = 16;
const COLUMN_Y: i32 = 26;
const RASTER_PERIOD: usize = 72;
const RASTER_STEP2: i32 = 1; // half rows: rastc -= 0.5

// sprites
const SPRITES: usize = 8;
const SPRITE_W: usize = 16;
const SPRITE_H: usize = 10;
const SPRITE_STRIP_W: usize = 128;
const SPRITE_SPACING: usize = 5; // db
const SPRITE_GAP_FROM: usize = 3; // "THE" + gap + "UNION"
const WOBBLE_X: i64 = 10;
const WOBBLE_Y: i64 = 5;
const WOBX_C = fixed.q30(@cos(0.07));
const WOBX_S = fixed.q30(@sin(0.07));
const WOBY_C = fixed.q30(@cos(0.09));
const WOBY_S = fixed.q30(@sin(0.09));
// sprite i adds a phase of i radians: sin(a + i) = sin a cos i + cos a sin i
const PHASE_C = blk: {
    var t: [SPRITES]i32 = undefined;
    for (0..SPRITES) |i| t[i] = fixed.q30(@cos(@as(f64, @floatFromInt(i))));
    break :blk t;
};
const PHASE_S = blk: {
    var t: [SPRITES]i32 = undefined;
    for (0..SPRITES) |i| t[i] = fixed.q30(@sin(@as(f64, @floatFromInt(i))));
    break :blk t;
};
const ROTOR_ZERO = fixed.Rotor{ .c = 1 << 30, .s = 0 };

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const font_b = @embedFile("../assets/screens/cuddly_starwars/font.raw");
const swfont_b = @embedFile("../assets/screens/cuddly_starwars/swfont.raw");
const sprite_b = @embedFile("../assets/screens/cuddly_starwars/sprite.raw");
const bg_b = @embedFile("../assets/screens/cuddly_starwars/bg.raw");
const raster = convertU8ArraytoColors(@embedFile("../assets/screens/cuddly_starwars/raster.dat"));
const base_pal = convertU8ArraytoColors(@embedFile("../assets/screens/cuddly_starwars/screen_pal.dat"));

comptime {
    @setEvalBranchQuota(100_000); // the 2899-character scrolltext is checked glyph by glyph
    assert(font_b.len == FONT_W * FONT_H);
    assert(swfont_b.len == SW_FONT_W * SW_FONT_H);
    assert(sprite_b.len == SPRITE_STRIP_W * SPRITE_H);
    assert(bg_b.len == BG_W * BG_H);
    assert(tables.sprite_x.len == tables.sprite_y.len);
    for (tables.scroll_text) |c| assert(c >= FIRST_CHAR and c - FIRST_CHAR < FONT_COLS * (FONT_H / GLYPH_H));
    for (tables.starwars_lines) |line| {
        // letterpos is only the integer 46 for full lines; empty lines draw nothing
        assert(line.len == 0 or line.len == SW_LINE_CHARS);
        for (line) |c| assert(c >= FIRST_CHAR and (c - FIRST_CHAR) / SW_COLS * SW_GLYPH_H + SW_GLYPH_H <= SW_FONT_H);
    }
    assert(SW_X + (SW_LINE_CHARS - 1) * SW_PITCH_X + SW_GLYPH_W <= W);
    // dcount + 19 never runs past the table
    assert(motion.DIST_LIMIT + COLUMNS - 1 < motion.dist.len);
    // the 1-wide raster reaches row 199 - rastc, and rastc never passes -72.5
    assert(RASTER_PERIOD * 4 >= H + 73);
}

const grey_lut = fixed.greyLut(GREY_BASE, GREY_LEVELS);

const palette: [256]Color = blk: {
    var p = base_pal;
    for (0..GREY_LEVELS) |k| {
        const g: u8 = grey_lut[GREY_BASE + k];
        p[GREY_BASE + k] = .{ .r = g, .g = g, .b = g, .a = 255 };
    }
    break :blk p;
};

/// The palette index of a Q16 grey (0..255 << 16), rounded to the 128 levels.
inline fn greyIndex(v: u32) u8 {
    return GREY_BASE + @as(u8, @intCast(fixed.levelOf(v, GREY_LEVELS)));
}

// --------------------------------------------------------------------------
// Module-scope state: scratch canvases and what the HBL reads. All of it is
// (re)written in init() or every frame before use.
//
// The large buffers come from the cart RAM arena (zg.mem) once, in init(): as
// module-scope arrays they were ~222 KB of zeros in the data segment (the cart
// imports its memory). raster_line stays static: the HBL reads it, and it is
// only 800 B.
// --------------------------------------------------------------------------
var star_x: *[STARS]i16 = undefined;
var star_y: *[STARS]i16 = undefined;
var raster_line: [H]Color = undefined;
var scroll_canvas: *[SCROLL_H * W]u8 = undefined;
var text_canvas: *[motion.TEXT_ROWS * W]u8 = undefined;
// Leftmost and rightmost inked column of each text row; an empty row has
// left > right. Most starwars lines are padded with spaces, so the perspective
// only samples the span between them.
var text_row_left: [motion.TEXT_ROWS]u16 = undefined;
var text_row_right: [motion.TEXT_ROWS]u16 = undefined;
var band_alpha: *[motion.BAND_ROWS * W]u32 = undefined; // Q16 coverage
// The columns of each band row the perspective visited this frame (lo > hi: none).
// Everything outside is still 0, so only these spans are cleared and composited.
var band_lo: [motion.BAND_ROWS]u16 = undefined;
var band_hi: [motion.BAND_ROWS]u16 = undefined;

fn allocBuffers() void {
    star_x = zg.mem.mustAlloc(i16, STARS)[0..STARS];
    star_y = zg.mem.mustAlloc(i16, STARS)[0..STARS];
    scroll_canvas = zg.mem.mustAlloc(u8, SCROLL_H * W)[0 .. SCROLL_H * W];
    text_canvas = zg.mem.mustAlloc(u8, motion.TEXT_ROWS * W)[0 .. motion.TEXT_ROWS * W];
    band_alpha = zg.mem.mustAlloc(u32, motion.BAND_ROWS * W)[0 .. motion.BAND_ROWS * W];
}

// A normal plane's HBL gets LOGICAL lines 0..199.
fn rasterHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line >= H) return;
    fb.setPaletteEntry(RASTER_INK, raster_line[line]);
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    blitter: zg.Blitter = .{},
    flash_counter: u32,
    fade: f64,
    star_rot: fixed.Rotor, // cos/sin of rotc
    star_base: i32, // staraddz in z units, mod STAR_Z_UNITS
    sw_offset: i32, // ssspeed: 0..-16
    sw_line: usize, // addword
    raster2: i32, // rastc in half rows: 0..-144
    dist_index: usize, // dcount
    letter_x: [LETTERS]i32,
    letter_char: [LETTERS]u8,
    text_offset: usize, // scroffset
    sprite_step: usize, // sC
    wob_x: fixed.Rotor, // sin/cos of sC * 0.07
    wob_y: fixed.Rotor, // sin/cos of sC * 0.09

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed (or holding the previous cart's bytes):
        // every field is set here, never by a declared default.
        self.blitter.init();
        self.flash_counter = 0;
        self.fade = 0;
        self.star_rot = fixed.Rotor.at(ROT_START); // init-time float
        self.star_base = 0;
        self.sw_offset = 0;
        self.sw_line = 0;
        self.raster2 = 0;
        self.dist_index = motion.DIST_RESET;
        self.sprite_step = 0;
        self.wob_x = ROTOR_ZERO;
        self.wob_y = ROTOR_ZERO;
        self.text_offset = 0;
        for (0..LETTERS) |i| {
            self.letter_x[i] = RING_BACK + @as(i32, @intCast(i)) * GLYPH_W;
            self.letter_char[i] = tables.scroll_text[self.text_offset];
            self.text_offset += 1;
        }

        allocBuffers();
        // Math.random() in the original; any fixed sequence is as faithful.
        var seed: u32 = 12345;
        for (0..STARS) |i| {
            star_x[i] = @intCast((@as(u64, nextRandom(&seed)) * 320) >> 32);
            star_y[i] = @intCast((@as(u64, nextRandom(&seed)) * 200) >> 32);
        }
        @memset(&raster_line, raster[0]);
        @memset(text_canvas, 0);
        @memset(&text_row_left, W);
        @memset(&text_row_right, 0);
        @memset(band_alpha, 0);
        @memset(&band_lo, W);
        @memset(&band_hi, 0);

        zg.requestSong(MUSIC);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(palette);
        @memset(fb.fb[0 .. W * H], BLACK);
        fb.setFrameBufferHBLHandler(0, rasterHbl);
    }

    /// Every step go() takes before it draws, in its order.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;

        self.flash_counter += 1;
        if (self.flash_counter > FLASH_WRAP) self.flash_counter = 0;
        if (self.flash_counter == FLASH_AT) self.fade = FADE_START;
        self.fade = if (self.fade > 0) self.fade - FADE_STEP else 0;

        self.star_base = @mod(self.star_base + STAR_Z_SPEED, STAR_Z_UNITS);
        self.star_rot.turn(ROT_STEP_C, ROT_STEP_S);

        self.sw_offset -= 1;
        if (self.sw_offset < -(SW_PITCH_Y - 1)) {
            self.sw_offset = 0;
            self.sw_line += 1;
            if (self.sw_line > tables.starwars_lines.len - SW_LINES) self.sw_line = 0;
        }

        self.raster2 -= RASTER_STEP2;
        if (self.raster2 < -@as(i32, RASTER_PERIOD) * 2) self.raster2 = 0;

        self.dist_index += 1;
        if (self.dist_index > motion.DIST_LIMIT) self.dist_index = motion.DIST_RESET;

        self.stepScrolltext();

        self.sprite_step += 1;
        self.wob_x.turn(WOBX_C, WOBX_S);
        self.wob_y.turn(WOBY_C, WOBY_S);
        if (self.sprite_step > tables.sprite_x.len) {
            self.sprite_step = 0;
            self.wob_x = ROTOR_ZERO;
            self.wob_y = ROTOR_ZERO;
        }
    }

    /// scrolltext_horizontal.draw: a ring of 12 letters; the one that reaches
    /// -32 rejoins the back carrying the next character.
    fn stepScrolltext(self: *Demo) void {
        for (0..LETTERS) |i| {
            self.letter_x[i] -= SCROLL_SPEED;
            if (self.letter_x[i] <= -@as(i32, GLYPH_W)) {
                self.letter_x[i] = RING_BACK + (self.letter_x[i] + GLYPH_W);
                self.letter_char[i] = tables.scroll_text[self.text_offset];
                self.text_offset += 1;
                if (self.text_offset > tables.scroll_text.len - 1) self.text_offset = 0;
            }
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const screen = fb.fb[0 .. W * H];
        @memset(screen, BLACK);
        self.drawLogoFlash(fb);
        self.drawStars(screen);
        self.drawStarwars(screen);
        self.buildRasterLines();
        self.drawScroller(screen);
        self.drawSprites(screen);
    }

    fn drawLogoFlash(self: *Demo, fb: *LogicalFB) void {
        const alpha = self.fade * FADE_ALPHA;
        if (alpha <= 0) return;
        // CODEF fades by canvas alpha; over black that is the palette's RGB
        // scaled from the base palette every frame, rounded (not truncated).
        zg.palette.scaleEntries(fb, base_pal, &LOGO_FLASH_ENTRIES, alpha, .{ .rounding = .round, .alpha = .{ .set = 255 } });
        self.blitter.blitImage(fb, @intCast(BG_X), @intCast(BG_Y), bg_b, @intCast(BG_W), 0, 0, @intCast(BG_W), @intCast(BG_H), 0);
    }

    fn drawStars(self: *Demo, screen: []u8) void {
        const cos: i64 = self.star_rot.c;
        const sin: i64 = self.star_rot.s;
        for (0..STARS) |i| {
            var z: i32 = @as(i32, @intCast(i)) * STAR_Z_PITCH - self.star_base;
            if (z < 0) z += STAR_Z_UNITS;
            if (z == 0) continue; // 128/0: the canvas ignores a non-finite rect
            const dx: i64 = @as(i64, star_x[i]) - 160;
            const dy: i64 = @as(i64, star_y[i]) - 100;
            const k: i64 = fixed.star_k[@intCast(z)];
            const rx = (dx * cos - dy * sin) >> 6; // Q24
            const ry = (dx * sin + dy * cos) >> 6;
            const sx = ((rx * k) >> 24) + (160 << 16); // Q16
            const sy = ((ry * k) >> 24) + (100 << 16);
            var grey = STAR_GREYS[0];
            for (1..STAR_GREYS.len) |c| {
                if (z * 3 > STAR_Z_UNITS * @as(i32, @intCast(c))) grey = STAR_GREYS[c];
            }
            plotStar(screen, sx, sy, grey);
        }
    }

    fn drawStarwars(self: *Demo, screen: []u8) void {
        self.layoutText();

        // the perspective into a 100-row alpha band ('source-over' accumulation)
        for (0..motion.BAND_ROWS) |r| {
            if (band_lo[r] <= band_hi[r]) @memset(band_alpha[r * W + band_lo[r] ..][0 .. @as(usize, band_hi[r]) + 1 - band_lo[r]], 0);
            band_lo[r] = W;
            band_hi[r] = 0;
        }
        for (motion.perspective) |p| {
            const upper_row = inkedRow(p.src_row);
            const lower_row = inkedRow(p.src_row + 1);
            if (upper_row == null and lower_row == null) continue;
            const ink = inkSpan(p.src_row);
            const band = band_alpha[@as(usize, p.band_row) * W ..][0..W];
            var x = firstInkedColumn(p, ink.left);
            const x_start = x;
            var fx: i64 = p.fx_base + p.fx_step * @as(i64, @intCast(x)); // Q24 source x
            const one = fixed.ONE;
            while (x <= p.x_last) : ({
                x += 1;
                fx += p.fx_step;
            }) {
                const xi: i32 = @intCast(fx >> 24);
                // sourceX never decreases with x: every column from here samples zeros
                if (xi > ink.right) break;
                const tx: u32 = @intCast((fx >> 8) & 0xffff);
                const upper = sampleRow(upper_row, xi, tx);
                const lower = sampleRow(lower_row, xi, tx);
                const mix = (@as(u64, upper) * (one - p.sf) + @as(u64, lower) * p.sf) >> 16;
                const a: u32 = @intCast((mix * p.cov) >> 16);
                if (a > 0) band[x] = a + @as(u32, @intCast((@as(u64, band[x]) * (one - a)) >> 16));
            }
            if (x > x_start) { // columns x_start .. x - 1 were visited
                band_lo[p.band_row] = @min(band_lo[p.band_row], @as(u16, @intCast(x_start)));
                band_hi[p.band_row] = @max(band_hi[p.band_row], @as(u16, @intCast(@min(x, W) - 1)));
            }
        }

        // white text over what is already there (only stars reach these rows)
        for (0..motion.BAND_ROWS) |r| {
            if (band_lo[r] > band_hi[r]) continue;
            const lo: usize = band_lo[r];
            const hi: usize = @as(usize, band_hi[r]) + 1;
            const band = band_alpha[r * W + lo ..][0 .. hi - lo];
            const dst = screen[(SW_BAND_Y + r) * W + lo ..][0 .. hi - lo];
            for (band, dst) |a, *d| {
                if (a > 0) d.* = greyIndex(255 * a + @as(u32, grey_lut[d.*]) * (fixed.ONE - a));
            }
        }
    }

    /// print() of 30 lines of the starwars text onto the (flat) text canvas.
    fn layoutText(self: *Demo) void {
        for (0..motion.TEXT_ROWS) |r| { // only the spans the last frame inked
            if (text_row_left[r] <= text_row_right[r]) {
                @memset(text_canvas[r * W + text_row_left[r] ..][0 .. text_row_right[r] - text_row_left[r] + 1], 0);
            }
            text_row_left[r] = W;
            text_row_right[r] = 0;
        }
        for (0..SW_LINES) |j| {
            const top = @as(i32, @intCast(j)) * SW_PITCH_Y + self.sw_offset;
            if (top >= motion.TEXT_ROWS) break;
            for (tables.starwars_lines[j + self.sw_line], 0..) |c, i| {
                blitTextGlyph(c - FIRST_CHAR, SW_X + i * SW_PITCH_X, top);
            }
        }
    }

    /// The raster behind the red ink: 'source-in' of scrollraster.png stretched
    /// at y = rastc. At a half position the canvas's bilinear filter averages
    /// the two rows it falls between (measured in Chrome).
    fn buildRasterLines(self: *Demo) void {
        for (0..H) |y| {
            const v2: usize = @intCast(@as(i32, @intCast(y)) * 2 - self.raster2);
            const row = v2 >> 1;
            const c0 = raster[row % RASTER_PERIOD];
            if (v2 & 1 == 0) {
                raster_line[y] = c0;
                continue;
            }
            const c1 = raster[(row + 1) % RASTER_PERIOD];
            raster_line[y] = .{
                .r = @intCast((@as(u16, c0.r) + c1.r) / 2),
                .g = @intCast((@as(u16, c0.g) + c1.g) / 2),
                .b = @intCast((@as(u16, c0.b) + c1.b) / 2),
                .a = 255,
            };
        }
    }

    fn drawScroller(self: *Demo, screen: []u8) void {
        @memset(scroll_canvas, 0);
        for (self.letter_x, self.letter_char) |x, c| {
            if (x >= W) continue; // letters waiting at the back of the ring
            blitScrollGlyph(c - FIRST_CHAR, x);
        }
        for (0..COLUMNS) |col| {
            const top = @as(i32, motion.dist[self.dist_index + col]) + COLUMN_Y;
            const x0 = col * COLUMN_W;
            for (0..SCROLL_H) |r| {
                const y = top + @as(i32, @intCast(r));
                if (y < 0 or y >= H) continue;
                const src = scroll_canvas[r * W + x0 ..][0..COLUMN_W];
                const dst = screen[@as(usize, @intCast(y)) * W + x0 ..][0..COLUMN_W];
                for (src, dst) |s, *d| {
                    if (s != 0) d.* = s;
                }
            }
        }
    }

    fn drawSprites(self: *Demo, screen: []u8) void {
        const sx: i64 = self.wob_x.s;
        const cx: i64 = self.wob_x.c;
        const sy: i64 = self.wob_y.s;
        const cy: i64 = self.wob_y.c;
        for (0..SPRITES) |i| {
            const gap: usize = if (i >= SPRITE_GAP_FROM) SPRITE_SPACING else 0;
            // the path array is pushed onto itself: indexing past its end wraps
            const at = (self.sprite_step + i * SPRITE_SPACING + gap) % tables.sprite_x.len;
            // drawn at sub-pixel positions in the original; nearest pixel here (Math.round)
            const pc: i64 = PHASE_C[i];
            const ps: i64 = PHASE_S[i];
            const wx = (sx * pc + cx * ps) >> 30; // sin(step * 0.07 + i), Q30
            const wy = (cy * pc - sy * ps) >> 30; // cos(step * 0.09 + i), Q30
            const x = ((@as(i64, tables.sprite_x[at]) << 30) + WOBBLE_X * wx + (1 << 29)) >> 30;
            const y = ((@as(i64, tables.sprite_y[at]) << 30) + WOBBLE_Y * wy + (1 << 29)) >> 30;
            blitSprite(screen, (SPRITES - 1 - i) * SPRITE_W, @intCast(x), @intCast(y));
        }
    }
};

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
fn nextRandom(seed: *u32) u32 {
    seed.* = seed.* *% 1664525 +% 1013904223;
    return seed.*;
}

/// fillRect(x, y, 1, 1) at a sub-pixel position (Q16): each of the four pixels it
/// touches takes the star's grey by the area it covers.
fn plotStar(screen: []u8, x: i64, y: i64, grey: u32) void {
    const one = fixed.ONE;
    if (!(x > -@as(i64, one) and x < @as(i64, W) * one and y > -@as(i64, one) and y < @as(i64, H) * one)) return;
    const xi: i32 = @intCast(x >> 16);
    const yi: i32 = @intCast(y >> 16);
    const fx: u32 = @intCast(x & 0xffff);
    const fy: u32 = @intCast(y & 0xffff);
    for (0..2) |dy| {
        for (0..2) |dx| {
            const px = xi + @as(i32, @intCast(dx));
            const py = yi + @as(i32, @intCast(dy));
            if (px < 0 or px >= W or py < 0 or py >= H) continue;
            const wx = if (dx == 0) one - fx else fx;
            const wy = if (dy == 0) one - fy else fy;
            const cover: u32 = @intCast((@as(u64, wx) * wy) >> 16);
            if (cover == 0) continue;
            const d = &screen[@as(usize, @intCast(py)) * W + @as(usize, @intCast(px))];
            // the flashing logo is not grey: a star keeps it unless it mostly covers it
            if (d.* == BG_ORANGE or d.* == BG_GREY) {
                if (cover >= one / 2) d.* = greyIndex(grey * cover);
                continue;
            }
            d.* = greyIndex(grey * cover + @as(u32, grey_lut[d.*]) * (one - cover));
        }
    }
}

fn rowInked(row: i32) bool {
    return row >= 0 and row < motion.TEXT_ROWS and text_row_left[@intCast(row)] <= text_row_right[@intCast(row)];
}

/// A text-canvas row, or null when it is off the canvas or holds no ink.
fn inkedRow(row: i32) ?*const [W]u8 {
    if (!rowInked(row)) return null;
    return text_canvas[@as(usize, @intCast(row)) * W ..][0..W];
}

/// The inked columns of the bilinear pair `row`, `row + 1`, inclusive.
/// At least one of the two rows must be inked.
fn inkSpan(row: i32) struct { left: i32, right: i32 } {
    var left: i32 = W;
    var right: i32 = -1;
    for ([_]i32{ row, row + 1 }) |r| {
        if (!rowInked(r)) continue;
        left = @min(left, text_row_left[@intCast(r)]);
        right = @max(right, text_row_right[@intCast(r)]);
    }
    return .{ .left = left, .right = right };
}

/// The first screen column of `p` worth sampling: every column before it reads
/// columns xi, xi+1 both left of `ink_left`, so its alpha is exactly 0. The
/// inverse stretch is only a guess; it is kept only if the column just before
/// it really does sample clear of the ink, otherwise the scan starts at x_first.
fn firstInkedColumn(p: motion.PerspectiveRow, ink_left: i32) usize {
    const first: usize = p.x_first;
    // (ink_left - 1 + 0.5 - 160) * zoom + 160 - 0.5 - 2, Q16
    const guess = @divTrunc((2 * @as(i64, ink_left) - 321) * p.zoom_q16, 2) + 10321920;
    if (guess < (@as(i64, @intCast(first)) + 1) * fixed.ONE) return first;
    const start: usize = @intCast(guess >> 16);
    const xi_before = (p.fx_base + p.fx_step * @as(i64, @intCast(start - 1))) >> 24;
    return if (xi_before + 1 < ink_left) start else first;
}

/// One row of the text canvas (ink is 0 or 1), linearly filtered between columns
/// xi and xi+1 by tx (Q16); the result is Q16.
fn sampleRow(row: ?*const [W]u8, xi: i32, tx: u32) u32 {
    const line = row orelse return 0;
    const left: u32 = if (xi >= 0 and xi < W) line[@intCast(xi)] else 0;
    const right: u32 = if (xi + 1 >= 0 and xi + 1 < W) line[@intCast(xi + 1)] else 0;
    return left * (fixed.ONE - tx) + right * tx;
}

fn blitTextGlyph(nb: usize, x: usize, top: i32) void {
    const tx = (nb % SW_COLS) * SW_GLYPH_W;
    const ty = (nb / SW_COLS) * SW_GLYPH_H;
    for (0..SW_GLYPH_H) |r| {
        const y = top + @as(i32, @intCast(r));
        if (y < 0 or y >= motion.TEXT_ROWS) continue;
        const row: usize = @intCast(y);
        const src = swfont_b[(ty + r) * SW_FONT_W + tx ..][0..SW_GLYPH_W];
        const dst = text_canvas[row * W + x ..][0..SW_GLYPH_W];
        for (src, dst, 0..) |s, *d, c| {
            if (s == 0) continue;
            d.* = 1;
            const col: u16 = @intCast(x + c);
            text_row_left[row] = @min(text_row_left[row], col);
            text_row_right[row] = @max(text_row_right[row], col);
        }
    }
}

fn blitScrollGlyph(nb: usize, x: i32) void {
    const tx = (nb % FONT_COLS) * GLYPH_W;
    const ty = (nb / FONT_COLS) * GLYPH_H;
    const c0: usize = @intCast(@max(0, -x));
    const c1: usize = @intCast(@min(@as(i32, GLYPH_W), @as(i32, W) - x));
    const canvas = scroll_canvas;
    for (0..SCROLL_H) |r| {
        const src = font_b[(ty + r) * FONT_W + tx ..][0..GLYPH_W];
        for (c0..c1) |c| {
            if (src[c] != 0) canvas[r * W + @as(usize, @intCast(x + @as(i32, @intCast(c))))] = src[c];
        }
    }
}

fn blitSprite(screen: []u8, part_x: usize, x: i32, y: i32) void {
    for (0..SPRITE_H) |r| {
        const py = y + @as(i32, @intCast(r));
        if (py < 0 or py >= H) continue;
        const src = sprite_b[r * SPRITE_STRIP_W + part_x ..][0..SPRITE_W];
        for (src, 0..) |s, c| {
            const px = x + @as(i32, @intCast(c));
            if (s == 0 or px < 0 or px >= W) continue;
            screen[@as(usize, @intCast(py)) * W + @as(usize, @intCast(px))] = s;
        }
    }
}
