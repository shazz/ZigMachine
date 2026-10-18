// --------------------------------------------------------------------------
// ELITE — "Jimmy White Snooker" crack intro, cracked by Dr. Trap, intro coded
// by Marsupilami, music by Mad Max.
//
// Ported from the CODEF HTML5 remake by Ayoros / Hemoroids (wab.com screen 422,
// MIT). Graphics, scrolltext and the original ST intro belong to their
// authors; music: Mad Max's "Master Blazer", docs/music/Masterblazer.sndh,
// subtune 10 — the remake's playNextSong2(songs, zic_choice[0].duration) hands
// duration (10) to sc68 as the track number.
//
// Reference kept at prototypes/codef/422/. Assets:
// tools/private_tools/elite_snooker_assets.py.
//
// The canvas is 640x400 = ST 320x200 doubled; every number below is the
// original's, in canvas pixels, halved at emission. Phases, frame-counted as
// the original's requestAnimFrame chain:
//   (skipped) the remake opens with AtariDecrunch(0, 30, 0, 100), a FAKE
//             Automation depack screen (bars, packer logo, busy bee). Ports
//             start where the demo starts: a real depack look belongs in
//             libs/zig/depackers/depack_fx.zig, never in a scene.
//   1..98     intro()/intro2(): the canvas is filled black, then a white and
//             a black canvas are drawn over it at alpha 0, .002, .004 ...
//             while <= .1. That is a flat grey, played here from a table
//             MEASURED in Chrome. The music starts on frame 1.
//   99..      go(): two 64x64 tiles wrapped over the screen and swapped every 7
//             frames, sliding on a sin/cos path; five lines of 32x32 text
//             waving through a raster (source-in); an 8x6-cell scroller
//             under a green raster.
//
// ONE plane, one shared palette (see the asset script).
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const hp = @import("hp_trig.zig");
const assert = std.debug.assert;

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const MUSIC = "Masterblazer.sndh";
const MUSIC_TUNE: u8 = 10; // zic_choice[0].duration, passed to sc68 as the track

const PLANE = 0;
const W: usize = 320;
const H: usize = 200;

// palette (see the asset script)
const TRANSPARENT: u8 = 0;
const BLACK: u8 = 1;
const FADE: u8 = 2; // rewritten every fade frame

// phases
const FADE_FIRST_FRAME: u32 = 1;
const MAIN_FIRST_FRAME: u32 = FADE_FIRST_FRAME + FADE_GREYS.len;

/// intro() then intro2(), one entry per frame: the canvas grey Chrome shows
/// after `mycanvaswhite.draw(mycanvas, 0, 0, fade)` (fade 0, .002 ... .098)
/// then `mycanvasblack.draw(mycanvas, 0, 0, fade2)`. Measured, not derived:
/// the browser quantizes every low-alpha composite to 8 bits.
const FADE_GREYS = [_]u8{
    0,   1,   2,   4,   6,   9,   12,  16,  20,  25,  30,  36,  41,  47,  53,  60,  66,  73,  80,  87,
    94,  101, 108, 115, 122, 129, 135, 142, 148, 154, 160, 166, 171, 176, 181, 186, 191, 196, 200, 204,
    208, 212, 215, 218, 221, 224, 226, 228, 230, 232, 230, 228, 225, 222, 218, 214, 209, 204, 199, 194,
    188, 182, 176, 170, 164, 158, 151, 145, 138, 132, 125, 119, 112, 106, 100, 94,  88,  82,  76,  71,
    66,  61,  56,  52,  48,  44,  40,  36,  33,  30,  27,  24,  21,  19,  17,  15,  13,  11,
};

// go(): mycanvas_calc (1920x960 of 64x64 tiles, midhandled at 960,480) drawn
// into the 640x380 mycanvas_fond at (280 - sin(vbl*PI/200)*80,
// 180 - cos(vbl*PI/200)*180). Every sampled point stays inside the tiled
// area, so it is a plain wrap of one tile.
const TILE: usize = 32;
const BG_ROWS: usize = 190; // mycanvas_fond is 380 tall; below it the fill stays black
const BG_PERIOD: f64 = 200; // vbl*PI/200
// tile grid x = (280 - sin*80 - 960)/2, y = (180 - cos*180 - 480)/2 (canvas 640x320 x3 handle)
// text px = 160 + 32j - indice*sin(a)*1.25, py = y - 24*sin(a - j*0.5), then /2
const TILE_FRAMES: u32 = 7; // vbl_head 0..6 elite1, 7..13 elite2

// write_text(mycanvas_rasters, 160, y, screens[n], font, 1, indice): one line
// per call, so the per-line terms (i*0.15, i*42, -i) are all zero.
const TextLine = struct { y: i32, indice: i32, text: []const u8 };
const TEXT_X: i32 = 160;
const TEXT = [_]TextLine{
    .{ .y = 70, .indice = 32, .text = "   JIMMY  " },
    .{ .y = 106, .indice = 48, .text = "   WHITE  " },
    .{ .y = 138, .indice = 64, .text = "  SNOOKER  " },
    .{ .y = 220, .indice = 80, .text = "CRACKED BY" },
    .{ .y = 256, .indice = 96, .text = " DR. TRAP " },
};
const TEXT_ANGLE_STEP: f64 = 0.002; // textAngle += 0.002 per character
const TEXT_CHAR_PHASE: f64 = 0.5;
const FONT: usize = 16; // the 32x32 tiles halved
const FONT_COLS: usize = 10;
const FONT_FIRST: u8 = 32;
const TEXT_GLYPHS: usize = blk: {
    var n: usize = 0;
    for (TEXT) |line| n += line.text.len;
    break :blk n;
};
// rasters.png (640x280) drawn at canvas y 40 with source-in: ST rows 20..159
const RASTER_TOP: usize = 20;
const RASTER_ROWS: usize = 140;

// scrolltext_horizontal on the 640x12 mycanvas_scroll: font2.initTile(16,12,32),
// init(..., 4), draw(0); the canvas is drawn at (0, 384)
const SCROLL_TEXT = @embedFile(DIR ++ "scrolltext.txt");
const SCROLL_GLYPH: i32 = 16;
const SCROLL_SPEED: i32 = 4;
const SCROLL_WIDE: i32 = 41; // ceil(640/16)+1
const SCROLL_LETTERS: usize = SCROLL_WIDE + 1; // letters 0..wide
const SCROLL_TOP: usize = 192; // 384 / 2
const SCROLL_ROWS: usize = 6;
const QTX_W: usize = 8;
const QTX_FIRST: u8 = 32;

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const DIR = "../assets/screens/elite_snooker/";
const palette = zg.convertU8ArraytoColors(@embedFile(DIR ++ "palette.dat"));
const tiles = [2]*const [TILE * TILE]u8{ @embedFile(DIR ++ "elite1.raw"), @embedFile(DIR ++ "elite2.raw") };
const font_img = blit.Image.init(@embedFile(DIR ++ "font.raw"), FONT_COLS * FONT);
const qtx_img = blit.Image.init(@embedFile(DIR ++ "qtxfont.raw"), 59 * QTX_W);
const raster_rows: *const [RASTER_ROWS]u8 = @embedFile(DIR ++ "raster_rows.dat");
const scroll_rows: *const [SCROLL_ROWS]u8 = @embedFile(DIR ++ "scroll_rows.dat");

comptime {
    @setEvalBranchQuota(20_000);
    assert(font_img.h == 6 * FONT and qtx_img.h == SCROLL_ROWS);
    assert(SCROLL_TEXT.len > SCROLL_LETTERS);
    // letter x stays a multiple of both, so drawMain's @divExact(x, 2) holds;
    // an odd constant would make it undefined behaviour in ReleaseSmall
    assert(@rem(SCROLL_SPEED, 2) == 0 and @rem(SCROLL_GLYPH, 2) == 0);
    for (SCROLL_TEXT) |c| assert(c >= QTX_FIRST and c - QTX_FIRST < 59);
    for (TEXT) |line| {
        for (line.text) |c| assert(c >= FONT_FIRST and c - FONT_FIRST < FONT_COLS * 6);
    }
}

// The scrolling background is one CHISEL blit a frame, not 190 rows of 32-pixel CPU copies:
// each tile repeated over BIG_W x BIG_H, so any (bg_x, bg_y) is a 320x190 window of it.
// Screen (x, y) shows tile ((x - bg_x) mod 32, (y - bg_y) mod 32) = big (x + start_x, y + off_y),
// start_x and off_y being the offsets mod 32 (at most 31): 319 + 31 < BIG_W, 189 + 31 < BIG_H.
const BIG_W: usize = 11 * TILE;
const BIG_H: usize = 7 * TILE;
var bigs: [2][]u8 = undefined; // from zg.mem, once per cart load

fn buildBigTiles() void {
    for (&bigs, tiles) |*big, tile| {
        big.* = zg.mem.mustAlloc(u8, BIG_W * BIG_H);
        for (0..TILE) |r| {
            const row = big.*[r * BIG_W ..][0..BIG_W];
            for (0..BIG_W / TILE) |k| @memcpy(row[k * TILE ..][0..TILE], tile[r * TILE ..][0..TILE]);
        }
        for (1..BIG_H / TILE) |k| @memcpy(big.*[k * TILE * BIG_W ..][0 .. TILE * BIG_W], big.*[0 .. TILE * BIG_W]);
    }
}

const ONE30: i64 = 1 << 30;

const Phase = enum { fade, main };
const Glyph = struct { x: i32, y: i32, cell: blit.Rect };

/// JS Math.round, the original float expression: only for values the integer
/// sine leaves within a hair of a .5 tie, where the float's own rounding decides.
fn jsRound(x: f64) i32 {
    return @intFromFloat(@floor(x + 0.5));
}

// Constant phases (u64 turns), folded at compile time (float is fine there).
const BG_STEP = hp.phase(std.math.pi / BG_PERIOD);
const TEXT_STEP = hp.phase(TEXT_ANGLE_STEP);
const TEXT_CHAR = hp.phase(TEXT_CHAR_PHASE);

fn fillRows(dst: blit.Dst, first: usize, end: usize, index: u8) void {
    for (first..end) |k| @memset(dst.buf[k * dst.stride ..][0..dst.w], index);
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    frame: u32, // requestAnimFrame calls so far, 1-based once running
    vbl: u32, // go()'s vbl for the frame being shown
    bg_x: i32, // ST offset of the tile grid
    bg_y: i32,
    text_phase: u64, // textAngle, one turn = 2^64
    glyphs: [TEXT_GLYPHS]Glyph,
    letter_x: [SCROLL_LETTERS]i32, // canvas x
    letter_ch: [SCROLL_LETTERS]u8,
    scroll_offset: usize,
    blitter: zg.Blitter,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here, never by default.
        self.frame = 0;
        self.vbl = 0;
        self.bg_x = 0;
        self.bg_y = 0;
        self.text_phase = 0;
        @memset(&self.glyphs, .{ .x = 0, .y = 0, .cell = .{ .x = 0, .y = 0, .w = 0, .h = 0 } });
        // letters[i] = (ceil(wide*fontw + i*fontw), scrtxt[scroffset++])
        for (0..SCROLL_LETTERS) |i| {
            self.letter_x[i] = SCROLL_WIDE * SCROLL_GLYPH + @as(i32, @intCast(i)) * SCROLL_GLYPH;
            self.letter_ch[i] = SCROLL_TEXT[i];
        }
        self.scroll_offset = SCROLL_LETTERS;
        self.blitter.init();
        buildBigTiles();

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(palette);
        fb.setPaletteEntry(TRANSPARENT, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fillRows(blit.Dst.plane(fb), 0, H, BLACK);
    }

    fn phase(self: *const Demo) Phase {
        if (self.frame < MAIN_FIRST_FRAME) return .fade;
        return .main;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        // saturating: a wrap would restart the fades and re-request the song
        self.frame +|= 1;
        switch (self.phase()) {
            .fade => if (self.frame == FADE_FIRST_FRAME) zg.requestSongTune(MUSIC, MUSIC_TUNE),
            .main => self.advanceMain(),
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const screen = blit.Dst.plane(fb);
        switch (self.phase()) {
            .fade => {
                const grey = FADE_GREYS[self.frame - FADE_FIRST_FRAME];
                fb.setPaletteEntry(FADE, Color{ .r = grey, .g = grey, .b = grey, .a = 255 });
                if (self.frame == FADE_FIRST_FRAME) fillRows(screen, 0, H, FADE);
            },
            .main => self.drawMain(fb, screen),
        }
    }

    /// go()'s state for this frame, in its order. Integer maths (zig3d_fixed's
    /// Q30 sine on u64 phases), so the pixel offsets are the float original's:
    /// a value within a hair of a rounding tie is redone with the original
    /// f64 expression, so a tie falls as the float fell.
    fn advanceMain(self: *Demo) void {
        self.vbl = self.frame - MAIN_FIRST_FRAME;
        const tp = BG_STEP *% @as(u64, self.vbl);
        const ta = hp.top(tp);
        // canvas offset of the tile grid: (280 - sin*80 - 960)/2, (180 - cos*180 - 480)/2
        self.bg_x = hp.roundQ(-340 * ONE30 - 40 * @as(i64, hp.sinQ(ta)), 30) orelse
            jsRound((280 - @sin(hp.rad(tp)) * 80 - 960) / 2);
        self.bg_y = hp.roundQ(-150 * ONE30 - 90 * @as(i64, hp.cosQ(ta)), 30) orelse
            jsRound((180 - @cos(hp.rad(tp)) * 180 - 480) / 2);

        var g: usize = 0;
        for (TEXT) |line| {
            for (line.text, 0..) |c, j| {
                self.text_phase +%= TEXT_STEP;
                const jj: i64 = @intCast(j);
                const pa = self.text_phase;
                const pb = pa -% TEXT_CHAR *% @as(u64, @intCast(j));
                // px/2 = 80 + 16j - indice*5/8*sin (Q33), py/2 = y/2 - 12*sin (Q30)
                const sa: i64 = hp.sinQ(hp.top(pa));
                const sb: i64 = hp.sinQ(hp.top(pb));
                const n: usize = c - FONT_FIRST;
                self.glyphs[g] = .{
                    .x = hp.roundQ(((80 + 16 * jj) << 33) - line.indice * 5 * sa, 33) orelse
                        jsRound((160 + 32 * @as(f64, @floatFromInt(j)) - @as(f64, @floatFromInt(line.indice)) * @sin(hp.rad(pa)) * 1.25) / 2),
                    .y = hp.roundQ((@as(i64, line.y) << 29) - 12 * sb, 30) orelse
                        jsRound((@as(f64, @floatFromInt(line.y)) - 24 * @sin(hp.rad(pb))) / 2),
                    .cell = .{ .x = (n % FONT_COLS) * FONT, .y = (n / FONT_COLS) * FONT, .w = FONT, .h = FONT },
                };
                g += 1;
            }
        }

        // scrolltext_horizontal.draw: each letter reaching -16 rejoins the back
        // of the ring with the next character (no ^P/^S/^C codes in this text)
        for (&self.letter_x, &self.letter_ch) |*x, *ch| {
            x.* -= SCROLL_SPEED;
            if (x.* <= -SCROLL_GLYPH) {
                x.* = SCROLL_WIDE * SCROLL_GLYPH + (x.* + SCROLL_GLYPH);
                ch.* = SCROLL_TEXT[self.scroll_offset];
                self.scroll_offset += 1;
                if (self.scroll_offset > SCROLL_TEXT.len - 1) self.scroll_offset = 0;
            }
        }
    }

    fn drawMain(self: *Demo, fb: *zg.LogicalFB, screen: blit.Dst) void {
        self.drawBackground(fb);
        fillRows(screen, BG_ROWS, H, BLACK);

        const raster = screen.window(0, RASTER_TOP, W, RASTER_ROWS);
        for (self.glyphs) |glyph| {
            blit.blit(raster, font_img, glyph.cell, glyph.x, glyph.y - @as(i32, RASTER_TOP), 0, .{ .row = raster_rows });
        }

        const scroll = screen.window(0, SCROLL_TOP, W, SCROLL_ROWS);
        for (self.letter_x, self.letter_ch) |x, ch| {
            const n: usize = ch - QTX_FIRST;
            const cell = blit.Rect{ .x = n * QTX_W, .y = 0, .w = QTX_W, .h = SCROLL_ROWS };
            blit.blit(scroll, qtx_img, cell, @divExact(x, 2), 0, 0, .{ .row = scroll_rows });
        }
    }

    /// Screen pixel (x, y) shows tile pixel ((x - bg_x) mod 32, (y - bg_y) mod 32).
    fn drawBackground(self: *Demo, fb: *zg.LogicalFB) void {
        const big = bigs[(self.vbl % (2 * TILE_FRAMES)) / TILE_FRAMES];
        const start_x: u16 = @intCast(@mod(-self.bg_x, @as(i32, TILE)));
        const off_y: u16 = @intCast(@mod(-self.bg_y, @as(i32, TILE)));
        self.blitter.blitImage(fb, 0, 0, big, BIG_W, start_x, off_y, W, BG_ROWS, null);
    }
};
