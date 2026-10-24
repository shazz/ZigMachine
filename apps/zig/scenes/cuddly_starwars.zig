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
//      coverage over the stars (cuddly_starwars/starwars.zig).
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
const starwars = @import("cuddly_starwars/starwars.zig");
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
const GREY_BASE = fixed.GREY_BASE;
const GREY_LEVELS = fixed.GREY_LEVELS;

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
const sprite_b = @embedFile("../assets/screens/cuddly_starwars/sprite.raw");
const bg_b = @embedFile("../assets/screens/cuddly_starwars/bg.raw");
// align(4): a Color is 4 bytes of align 1, read as one word; at an odd address that
// load traps on the board (~210 cycles). Their place in the data segment is luck otherwise.
const raster align(4) = convertU8ArraytoColors(@embedFile("../assets/screens/cuddly_starwars/raster.dat"));
const base_pal align(4) = convertU8ArraytoColors(@embedFile("../assets/screens/cuddly_starwars/screen_pal.dat"));

comptime {
    @setEvalBranchQuota(100_000); // the 2899-character scrolltext is checked glyph by glyph
    assert(font_b.len == FONT_W * FONT_H);
    assert(sprite_b.len == SPRITE_STRIP_W * SPRITE_H);
    assert(bg_b.len == BG_W * BG_H);
    assert(tables.sprite_x.len == tables.sprite_y.len);
    for (tables.scroll_text) |c| assert(c >= FIRST_CHAR and c - FIRST_CHAR < FONT_COLS * (FONT_H / GLYPH_H));
    // dcount + 19 never runs past the table
    assert(motion.DIST_LIMIT + COLUMNS - 1 < motion.dist.len);
    // the 1-wide raster reaches row 199 - rastc, and rastc never passes -72.5
    assert(RASTER_PERIOD * 4 >= H + 73);
}

const grey_lut = fixed.grey_lut;
const greyIndex = fixed.greyIndex;

const palette: [256]Color = blk: {
    var p = base_pal;
    for (0..GREY_LEVELS) |k| {
        const g: u8 = grey_lut[GREY_BASE + k];
        p[GREY_BASE + k] = .{ .r = g, .g = g, .b = g, .a = 255 };
    }
    break :blk p;
};

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

fn allocBuffers() void {
    star_x = zg.mem.mustAlloc(i16, STARS)[0..STARS];
    star_y = zg.mem.mustAlloc(i16, STARS)[0..STARS];
    starwars.init();
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
        if (self.sw_offset < -(starwars.PITCH_Y - 1)) {
            self.sw_offset = 0;
            self.sw_line += 1;
            if (self.sw_line > tables.starwars_lines.len - starwars.LINES) self.sw_line = 0;
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
        self.blitter.fill(fb, 0, 0, W, H, BLACK); // CHISEL: a CPU memset is ~60 cycles a word
        self.drawLogoFlash(fb);
        self.drawStars(screen);
        starwars.draw(screen, self.sw_line, self.sw_offset);
        self.buildRasterLines();
        self.drawScroller(fb);
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

    /// The glyph ring through the wave: each letter is cut at the 16-px column
    /// boundaries and keyed-blitted (CHISEL) straight onto the plane at that
    /// column's height. Letters are GLYPH_W apart, so none overlaps another and the
    /// result equals drawing them all on a canvas and copying the columns across.
    fn drawScroller(self: *Demo, fb: *LogicalFB) void {
        const CW: i32 = COLUMN_W;
        for (self.letter_x, self.letter_char) |x, c| {
            if (x >= W) continue; // letters waiting at the back of the ring
            const nb = c - FIRST_CHAR;
            const tx = (nb % FONT_COLS) * GLYPH_W;
            const ty = (nb / FONT_COLS) * GLYPH_H;
            const x0: i32 = @max(0, x);
            const x1: i32 = @min(@as(i32, W), x + @as(i32, GLYPH_W));
            var col: i32 = @divFloor(x0, CW);
            while (col * CW < x1) : (col += 1) {
                const xs = @max(x0, col * CW);
                const xe = @min(x1, (col + 1) * CW);
                const top = @as(i32, motion.dist[self.dist_index + @as(usize, @intCast(col))]) + COLUMN_Y;
                const r0 = @max(0, -top);
                const r1 = @min(@as(i32, SCROLL_H), @as(i32, H) - top);
                if (r0 >= r1) continue;
                self.blitter.blitImage(fb, @intCast(xs), @intCast(top + r0), font_b, FONT_W, @intCast(@as(i32, @intCast(tx)) + xs - x), @intCast(@as(i32, @intCast(ty)) + r0), @intCast(xe - xs), @intCast(r1 - r0), 0);
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
