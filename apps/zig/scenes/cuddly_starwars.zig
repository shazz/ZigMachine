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
const STAR_Z_SIZE: f64 = (320.0 / 2.0 + 200.0 / 2.0) / 2.0; // 130
const STAR_Z_SPEED: f64 = 15;
const STAR_SPLIT: f64 = STAR_Z_SIZE / 3.0; // starcolsplit
const STAR_GREYS = [3]f32{ 0xff, 0xaa, 0x55 }; // near .. far
const ROT_START: f64 = 180;
const ROT_STEP: f64 = 0.02;
const STAR_FOCAL: f64 = 128;

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
const RASTER_STEP: f64 = 0.5;

// sprites
const SPRITES: usize = 8;
const SPRITE_W: usize = 16;
const SPRITE_H: usize = 10;
const SPRITE_STRIP_W: usize = 128;
const SPRITE_SPACING: usize = 5; // db
const SPRITE_GAP_FROM: usize = 3; // "THE" + gap + "UNION"
const WOBBLE_X: f64 = 10;
const WOBBLE_Y: f64 = 5;
const WOBBLE_X_RATE: f64 = 0.07;
const WOBBLE_Y_RATE: f64 = 0.09;

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

const palette: [256]Color = blk: {
    var p = base_pal;
    for (0..GREY_LEVELS) |k| {
        const g: u8 = @intFromFloat(@round(@as(f64, @floatFromInt(k)) * 255.0 / (GREY_LEVELS - 1)));
        p[GREY_BASE + k] = .{ .r = g, .g = g, .b = g, .a = 255 };
    }
    break :blk p;
};

inline fn greyOf(index: u8) f32 {
    return if (index >= GREY_BASE) @floatFromInt(palette[index].r) else 0;
}

inline fn greyIndex(value: f32) u8 {
    const level: u32 = @intFromFloat(@round(@min(value, 255) * (GREY_LEVELS - 1) / 255.0));
    return GREY_BASE + @as(u8, @intCast(level));
}

// --------------------------------------------------------------------------
// Module-scope state: scratch canvases and what the HBL reads. All of it is
// (re)written in init() or every frame before use.
// --------------------------------------------------------------------------
var star_x: [STARS]f64 = undefined;
var star_y: [STARS]f64 = undefined;
var raster_line: [H]Color = undefined;
var scroll_canvas: [SCROLL_H * W]u8 = undefined;
var text_canvas: [motion.TEXT_ROWS * W]u8 = undefined;
// Leftmost and rightmost inked column of each text row; an empty row has
// left > right. Most starwars lines are padded with spaces, so the perspective
// only samples the span between them.
var text_row_left: [motion.TEXT_ROWS]u16 = undefined;
var text_row_right: [motion.TEXT_ROWS]u16 = undefined;
var band_alpha: [motion.BAND_ROWS * W]f32 = undefined;

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
    rot: f64, // rotc
    star_z: f64, // staraddz
    sw_offset: i32, // ssspeed: 0..-16
    sw_line: usize, // addword
    raster_pos: f64, // rastc: 0..-72
    dist_index: usize, // dcount
    letter_x: [LETTERS]i32,
    letter_char: [LETTERS]u8,
    text_offset: usize, // scroffset
    sprite_step: usize, // sC

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed (or holding the previous cart's bytes):
        // every field is set here, never by a declared default.
        self.blitter.init();
        self.flash_counter = 0;
        self.fade = 0;
        self.rot = ROT_START;
        self.star_z = 0;
        self.sw_offset = 0;
        self.sw_line = 0;
        self.raster_pos = 0;
        self.dist_index = motion.DIST_RESET;
        self.sprite_step = 0;
        self.text_offset = 0;
        for (0..LETTERS) |i| {
            self.letter_x[i] = RING_BACK + @as(i32, @intCast(i)) * GLYPH_W;
            self.letter_char[i] = tables.scroll_text[self.text_offset];
            self.text_offset += 1;
        }

        // Math.random() in the original; any fixed sequence is as faithful.
        var seed: u32 = 12345;
        for (0..STARS) |i| {
            star_x[i] = @floor(nextRandom(&seed) * 320);
            star_y[i] = @floor(nextRandom(&seed) * 200);
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

        self.star_z += STAR_Z_SPEED * 0.1;
        self.rot -= ROT_STEP;

        self.sw_offset -= 1;
        if (self.sw_offset < -(SW_PITCH_Y - 1)) {
            self.sw_offset = 0;
            self.sw_line += 1;
            if (self.sw_line > tables.starwars_lines.len - SW_LINES) self.sw_line = 0;
        }

        self.raster_pos -= RASTER_STEP;
        if (self.raster_pos < -@as(f64, RASTER_PERIOD)) self.raster_pos = 0;

        self.dist_index += 1;
        if (self.dist_index > motion.DIST_LIMIT) self.dist_index = motion.DIST_RESET;

        self.stepScrolltext();

        self.sprite_step += 1;
        if (self.sprite_step > tables.sprite_x.len) self.sprite_step = 0;
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
        const cos = @cos(self.rot);
        const sin = @sin(self.rot);
        for (0..STARS) |i| {
            var z = @as(f64, @floatFromInt(i)) * (STAR_Z_SIZE / @as(f64, STARS)) - self.star_z;
            if (z > STAR_Z_SIZE) z -= STAR_Z_SIZE * @floor(z / STAR_Z_SIZE);
            if (z < 0) z -= STAR_Z_SIZE * @floor(z / STAR_Z_SIZE);
            if (z == 0) continue; // 128/0: the canvas ignores a non-finite rect
            const dx = star_x[i] - 160;
            const dy = star_y[i] - 100;
            const k = STAR_FOCAL / z;
            const sx = (dx * cos - dy * sin) * k + 160;
            const sy = (dx * sin + dy * cos) * k + 100;
            var grey = STAR_GREYS[0];
            for (1..STAR_GREYS.len) |c| {
                if (z > STAR_SPLIT * @as(f64, @floatFromInt(c))) grey = STAR_GREYS[c];
            }
            plotStar(screen, sx, sy, grey);
        }
    }

    fn drawStarwars(self: *Demo, screen: []u8) void {
        self.layoutText();

        // the perspective into a 100-row alpha band ('source-over' accumulation)
        @memset(&band_alpha, 0);
        for (motion.perspective) |p| {
            const upper_row = inkedRow(p.src_row);
            const lower_row = inkedRow(p.src_row + 1);
            if (upper_row == null and lower_row == null) continue;
            const ink = inkSpan(p.src_row);
            const band = band_alpha[@as(usize, p.band_row) * W ..][0..W];
            var x = firstInkedColumn(p, ink.left);
            while (x <= p.x_last) : (x += 1) {
                const fx = sourceX(p.zoom, x);
                const x0 = @floor(fx);
                const xi: i32 = @intFromFloat(x0);
                // sourceX never decreases with x: every column from here samples zeros
                if (xi > ink.right) break;
                const tx = fx - x0;
                const upper = sampleRow(upper_row, xi, tx);
                const lower = sampleRow(lower_row, xi, tx);
                const a: f32 = @floatCast((upper * (1 - p.src_frac) + lower * p.src_frac) * p.coverage);
                if (a > 0) band[x] = a + band[x] * (1 - a);
            }
        }

        // white text over what is already there (only stars reach these rows)
        for (0..motion.BAND_ROWS) |r| {
            const band = band_alpha[r * W ..][0..W];
            const dst = screen[(SW_BAND_Y + r) * W ..][0..W];
            for (band, dst) |a, *d| {
                if (a > 0) d.* = greyIndex(255 * a + greyOf(d.*) * (1 - a));
            }
        }
    }

    /// print() of 30 lines of the starwars text onto the (flat) text canvas.
    fn layoutText(self: *Demo) void {
        @memset(&text_canvas, 0);
        @memset(&text_row_left, W);
        @memset(&text_row_right, 0);
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
            const v = @as(f64, @floatFromInt(y)) - self.raster_pos;
            const row: usize = @intFromFloat(@floor(v));
            const c0 = raster[row % RASTER_PERIOD];
            if (v == @floor(v)) {
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
        @memset(&scroll_canvas, 0);
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
        const step = @as(f64, @floatFromInt(self.sprite_step));
        for (0..SPRITES) |i| {
            const gap: usize = if (i >= SPRITE_GAP_FROM) SPRITE_SPACING else 0;
            // the path array is pushed onto itself: indexing past its end wraps
            const at = (self.sprite_step + i * SPRITE_SPACING + gap) % tables.sprite_x.len;
            const fi = @as(f64, @floatFromInt(i));
            // drawn at sub-pixel positions in the original; nearest pixel here
            const x = motion.jsRound(@as(f64, @floatFromInt(tables.sprite_x[at])) + WOBBLE_X * @sin(step * WOBBLE_X_RATE + fi));
            const y = motion.jsRound(@as(f64, @floatFromInt(tables.sprite_y[at])) + WOBBLE_Y * @cos(step * WOBBLE_Y_RATE + fi));
            blitSprite(screen, (SPRITES - 1 - i) * SPRITE_W, @intFromFloat(x), @intFromFloat(y));
        }
    }
};

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
fn nextRandom(seed: *u32) f64 {
    seed.* = seed.* *% 1664525 +% 1013904223;
    return @as(f64, @floatFromInt(seed.*)) / 4294967296.0;
}

/// fillRect(x, y, 1, 1) at a sub-pixel position: each of the four pixels it
/// touches takes the star's grey by the area it covers.
fn plotStar(screen: []u8, x: f64, y: f64, grey: f32) void {
    if (!(x > -1 and x < W and y > -1 and y < H)) return;
    const x0 = @floor(x);
    const y0 = @floor(y);
    const fx: f32 = @floatCast(x - x0);
    const fy: f32 = @floatCast(y - y0);
    const xi: i32 = @intFromFloat(x0);
    const yi: i32 = @intFromFloat(y0);
    for (0..2) |dy| {
        for (0..2) |dx| {
            const px = xi + @as(i32, @intCast(dx));
            const py = yi + @as(i32, @intCast(dy));
            if (px < 0 or px >= W or py < 0 or py >= H) continue;
            const cover = (if (dx == 0) 1 - fx else fx) * (if (dy == 0) 1 - fy else fy);
            if (cover <= 0) continue;
            const d = &screen[@as(usize, @intCast(py)) * W + @as(usize, @intCast(px))];
            // the flashing logo is not grey: a star keeps it unless it mostly covers it
            if (d.* == BG_ORANGE or d.* == BG_GREY) {
                if (cover >= 0.5) d.* = greyIndex(grey * cover);
                continue;
            }
            d.* = greyIndex(grey * cover + greyOf(d.*) * (1 - cover));
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

/// The text-canvas x a screen column's centre samples through the stretch.
/// Division by a positive zoom keeps it monotonic in x, which the clipping
/// in drawStarwars relies on.
inline fn sourceX(zoom: f64, x: usize) f64 {
    return 160 + (@as(f64, @floatFromInt(x)) + 0.5 - 160) / zoom - 0.5;
}

/// The first screen column of `p` worth sampling: every column before it reads
/// columns xi, xi+1 both left of `ink_left`, so its alpha is exactly 0. The
/// inverse stretch is only a guess; it is kept only if the column just before
/// it really does sample clear of the ink, otherwise the scan starts at x_first.
fn firstInkedColumn(p: motion.PerspectiveRow, ink_left: i32) usize {
    const first: usize = p.x_first;
    const guess = (@as(f64, @floatFromInt(ink_left - 1)) + 0.5 - 160) * p.zoom + 160 - 0.5 - 2;
    if (!(guess >= @as(f64, @floatFromInt(first)) + 1)) return first;
    // ink_left <= 319 and zoom < 1.2 bound the guess well inside usize
    const start: usize = @intFromFloat(guess);
    const xi_before: i32 = @intFromFloat(@floor(sourceX(p.zoom, start - 1)));
    return if (xi_before + 1 < ink_left) start else first;
}

/// One row of the text canvas, linearly filtered between columns xi and xi+1.
fn sampleRow(row: ?*const [W]u8, xi: i32, tx: f64) f64 {
    const line = row orelse return 0;
    const left: f64 = if (xi >= 0 and xi < W) @floatFromInt(line[@intCast(xi)]) else 0;
    const right: f64 = if (xi + 1 >= 0 and xi + 1 < W) @floatFromInt(line[@intCast(xi + 1)]) else 0;
    return left * (1 - tx) + right * tx;
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
    for (0..SCROLL_H) |r| {
        const src = font_b[(ty + r) * FONT_W + tx ..][0..GLYPH_W];
        for (c0..c1) |c| {
            if (src[c] != 0) scroll_canvas[r * W + @as(usize, @intCast(x + @as(i32, @intCast(c))))] = src[c];
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
