// --------------------------------------------------------------------------
// The distorted scroller (cuddly_starwars.zig, go() step 4): a ring of 12
// letters, cut into 20 columns of 16 each shifted by dist1 (motion.zig). fontr is
// recoloured by the raster ('source-in'), then fontg drawn on the SAME positions;
// the two fonts' inks never overlap, so they are one merged font whose red ink is
// palette index 1, set per line by the copper from the raster lines built here.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const tables = @import("tables.zig");
const motion = @import("motion.zig");
const assert = std.debug.assert;

const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;

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

const font_b = @embedFile("../../assets/screens/cuddly_starwars/font.raw");
// align(4): a Color is 4 bytes of align 1, read as one word; at an odd address that
// load traps on the board (~210 cycles). Its place in the data segment is luck otherwise.
const raster align(4) = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/cuddly_starwars/raster.dat"));

comptime {
    @setEvalBranchQuota(100_000); // the 2899-character scrolltext is checked glyph by glyph
    assert(font_b.len == FONT_W * FONT_H);
    for (tables.scroll_text) |c| assert(c >= FIRST_CHAR and c - FIRST_CHAR < FONT_COLS * (FONT_H / GLYPH_H));
    // dcount + 19 never runs past the table
    assert(motion.DIST_LIMIT + COLUMNS - 1 < motion.dist.len);
    // the 1-wide raster reaches row 199 - rastc, and rastc never passes -72.5
    assert(RASTER_PERIOD * 4 >= H + 73);
}

pub const Distort = struct {
    raster2: i32, // rastc in half rows: 0..-144
    dist_index: usize, // dcount
    letter_x: [LETTERS]i32,
    letter_char: [LETTERS]u8,
    text_offset: usize, // scroffset

    pub fn init(self: *Distort) void {
        self.raster2 = 0;
        self.dist_index = motion.DIST_RESET;
        self.text_offset = 0;
        for (0..LETTERS) |i| {
            self.letter_x[i] = RING_BACK + @as(i32, @intCast(i)) * GLYPH_W;
            self.letter_char[i] = tables.scroll_text[self.text_offset];
            self.text_offset += 1;
        }
    }

    pub fn step(self: *Distort) void {
        self.raster2 -= RASTER_STEP2;
        if (self.raster2 < -@as(i32, RASTER_PERIOD) * 2) self.raster2 = 0;

        self.dist_index += 1;
        if (self.dist_index > motion.DIST_LIMIT) self.dist_index = motion.DIST_RESET;

        self.stepScrolltext();
    }

    /// scrolltext_horizontal.draw: a ring of 12 letters; the one that reaches
    /// -32 rejoins the back carrying the next character.
    fn stepScrolltext(self: *Distort) void {
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

    /// The raster behind the red ink: 'source-in' of scrollraster.png stretched
    /// at y = rastc. At a half position the canvas's bilinear filter averages
    /// the two rows it falls between (measured in Chrome).
    pub fn buildRasterLines(self: *const Distort, rows: *[H]u32) void {
        for (0..H) |y| {
            const v2: usize = @intCast(@as(i32, @intCast(y)) * 2 - self.raster2);
            const row = v2 >> 1;
            const c0 = raster[row % RASTER_PERIOD];
            if (v2 & 1 == 0) {
                rows[y] = c0.toRGBA();
                continue;
            }
            const c1 = raster[(row + 1) % RASTER_PERIOD];
            rows[y] = Color.toRGBA(.{
                .r = @intCast((@as(u16, c0.r) + c1.r) / 2),
                .g = @intCast((@as(u16, c0.g) + c1.g) / 2),
                .b = @intCast((@as(u16, c0.b) + c1.b) / 2),
                .a = 255,
            });
        }
    }

    /// The glyph ring through the wave: each letter is cut at the 16-px column
    /// boundaries and keyed-blitted (CHISEL) straight onto the plane at that
    /// column's height. Letters are GLYPH_W apart, so none overlaps another and the
    /// result equals drawing them all on a canvas and copying the columns across.
    pub fn draw(self: *const Distort, fb: *LogicalFB, blitter: *zg.Blitter) void {
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
                blitter.blitImage(fb, @intCast(xs), @intCast(top + r0), font_b, FONT_W, @intCast(@as(i32, @intCast(tx)) + xs - x), @intCast(@as(i32, @intCast(ty)) + r0), @intCast(xe - xs), @intCast(r1 - r0), 0);
            }
        }
    }
};
