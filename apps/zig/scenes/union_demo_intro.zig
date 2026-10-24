// --------------------------------------------------------------------------
// The Union Demo (1989) INTRO SCREEN, ported from shazz's melonJS "Union Demo
// HTML5 Remake" 0.9.8, screens/intro/screen.js. Artwork, text and music belong
// to The Union (The Carebears: Nick, Jas, ES; music Mad Max).
//
// In the remake this is the splash the demo opens on (main.js:262-265): Space
// leaves it for the first TEX loader (demoLoader's credits panel), then the menu
// loader's panel, then the street. Here it opens the union_demo cart itself, and
// Space, Escape, Fire or Back go on to the ONE loader panel before the street:
// The Carebears' credits (demoLoader's text) assembling while the menu depacks,
// held until a key (Matt, 2026-10-23/24: one intro screen, no double panel, no
// cart swap -- the board's firmware swaps no cart). union_demo.zig drives it.
//
// Three things on a black 640x400 canvas, halved onto one 320x200 plane:
//   background  bg2.png, a 96-row tile scrolling down 3 canvas rows a frame,
//               from -96 back to -96 when it reaches 0 (screen.js:84, 109)
//   logo        logo.png from its centre at x = 320 + sin(a)*(170*sin(b)),
//               y = 38; a += 0.08, b += 0.008 a frame (screen.js:83-85, 112)
//   letters     text.png's 16x14 tiles of 32x16, each ROW r shifted in x by
//               sin(t + 0.3r)*32 and each COLUMN c in y by sin(t + 0.3c)*16,
//               t += 0.06 a frame (screen.js:87-128), coloured by rasters.png
//               drawn over them source-atop at y 120 (screen.js:131-133): one
//               colour per canvas row, i.e. a palette index per ST row.
//
// Halving (measured against Chrome frames of screen.js, not assumed): the
// system canvas has smoothing OFF (me.sys.scalingInterpolation false), so the
// logo lands on canvas column round(x) and on ST column floor(round(x)/2); the
// letter canvas is a CODEF canvas with smoothing ON, and its best whole-pixel
// fit is round(x/2), round(y/2). The background's odd canvas rows are averaged
// (tools/private_tools/union_demo_intro_assets.py).
//
// The graphics arrive ZX0-packed and depack with no effect, on a black screen,
// before the first frame: nothing loads before the remake's introScreen
// (main.js:262-265 clears the canvas black and changes state straight to it).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const depackers = @import("depackers");
const DepackFx = depackers.depack_fx.Runner(zg, null); // fx none: no tvnoise
const fx = @import("turns_fix.zig");
const packed_intro = @import("packed_assets").union_demo_intro;

// Mad Max's "Union Demo LOADER" (ThinkTwice.ym holds U_LOADER.BIN). The archive's
// Mad_Max/Demos/Union_Demo/Ikari_Union.sndh subtune 1 matches that register dump
// at 95.7% (registers 0-5 exact, 8-10 masked to 5 bits, 800 frames, offset 0;
// 95.0% over 1800); the next best of 532 subtunes scored 26.5%.
const MUSIC = "ikari_union.sndh";

// The whole 61,568-byte blob in one frame (280 lines x 220 = 61,600 bytes).
const DEPACK_BYTES_PER_LINE = 220;
var depack: DepackFx = undefined; // module scope: the runner must not move

// The depacked blob (union_demo_intro_assets.py), in this order.
const BG_W = 320;
const BG_ROWS = 48; // the 96-row canvas tile, halved
const LOGO_W = 64;
const LOGO_H = 32;
const FONT_W = 256;
const FONT_H = 112;
const INK_TOP = 60; // ST rows the letters can reach: 60..187
const INK_ROWS = 128;
const BG_EVEN = 0;
const BG_ODD = BG_EVEN + BG_W * BG_ROWS;
const LOGO = BG_ODD + BG_W * BG_ROWS;
const FONT = LOGO + LOGO_W * LOGO_H;
const INK = FONT + FONT_W * FONT_H;
const BLOB_LEN = INK + INK_ROWS;

const palette = zg.convertU8ArraytoColors(@embedFile("../assets/screens/union_demo_intro/intro_pal.dat"));

// screen.js's own numbers, in canvas units.
const BG_STEP = 3;
const BG_TOP = -96;
// The phases are u64 turns (turns_fix.zig): the doubles' sums without soft-float.
const LOGO_INC = fx.turns(0.008);
const LOGO_SIN = fx.turns(0.08);
const LOGO_CX = 320;
const LOGO_SWAY = 170;
const LOGO_CY = 32 + 6;
const LETTER_STEP = fx.turns(0.06);
const LETTER_PHASE = fx.turns(0.3);
const TEXT_X = 70;
const TEXT_Y = 136;
const TILE_W = 32;
const TILE_H = 16;
const TILES_X = 16; // for (x = 0; x < 512; x += 32)
const TILES_Y = 14; // for (y = 0; y < 224; y += 16)
const SWING_X = 32;
const SWING_Y = 16;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = ' ';
const DIR_FIRE: u8 = 5;
const DIR_BACK: u8 = 6;

var ink_row: [zg.HEIGHT]u8 = undefined; // palette index per ST row for .row ink

pub const Demo = struct {
    data: []u8, // the depacked blob
    depacking: bool,
    bg_pos: i32, // bgposy
    logo_inc: u64, // logoInc
    logo_sin: u64, // logosin1
    letters: u64, // sinlettersx == sinlettersy after update()
    done: bool, // Space (or Escape) was pressed: the street's loader takes over
    wants_quit: bool, // no way to run at all: back to the menu

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.bg_pos = BG_TOP;
        self.logo_inc = 0;
        self.logo_sin = 0;
        self.letters = 0;
        self.done = false;
        self.wants_quit = false;
        self.depacking = false;
        // On zg.mem, taken once: init runs once per cart load.
        self.data = zg.mem.alloc(u8, BLOB_LEN) orelse return self.fail("no free RAM to depack into");
        if (!depack.start(zigos, packed_intro, self.data, DEPACK_BYTES_PER_LINE))
            return self.fail("packed graphics unreadable");
        self.depacking = true;
    }

    fn fail(self: *Demo, why: []const u8) void {
        zg.Console.log("union_demo_intro: {s}", .{why});
        self.depacking = false;
        self.wants_quit = true;
    }

    /// onResetEvent: the screen proper starts once its graphics are in.
    fn start(self: *Demo, zigos: *ZigOS) void {
        self.depacking = false;
        @memset(&ink_row, 0);
        @memcpy(ink_row[INK_TOP..][0..INK_ROWS], self.data[INK..][0..INK_ROWS]);
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSong(MUSIC);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.depacking) {
            switch (depack.frame(zigos)) {
                .more => return,
                .done => self.start(zigos), // and this frame is its first update(), as in melonJS
                .failed => return self.fail("depack failed"),
            }
        }
        if (self.wants_quit or self.done) return;
        self.logo_inc +%= LOGO_INC;
        self.bg_pos += BG_STEP;
        if (self.bg_pos >= 0) self.bg_pos = BG_TOP;
        self.logo_sin +%= LOGO_SIN;
        self.letters +%= LETTER_STEP;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.depacking or self.wants_quit) return;
        const fb = &zigos.lfbs[0];
        self.drawBackground(fb);
        self.drawLogo(fb);
        self.drawLetters(fb);
    }

    /// Canvas rows 2r, 2r+1 show tile rows 2r - bg_pos and the next: a halved row
    /// on an even bg_pos, an averaged pair (2m+1, 2m+2) on an odd one.
    fn drawBackground(self: *Demo, fb: *zg.LogicalFB) void {
        const odd = @mod(self.bg_pos, 2) == 1;
        const table = self.data[if (odd) BG_ODD else BG_EVEN ..][0 .. BG_W * BG_ROWS];
        const px = fb.fb[0 .. @as(usize, fb.stride) * zg.HEIGHT];
        for (0..zg.HEIGHT) |r| {
            const canvas_row = 2 * @as(i32, @intCast(r)) - self.bg_pos - @intFromBool(odd);
            const m: usize = @intCast(@mod(@divFloor(canvas_row, 2), BG_ROWS));
            @memcpy(px[r * fb.stride ..][0..BG_W], table[m * BG_W ..][0..BG_W]);
        }
    }

    fn drawLogo(self: *Demo, fb: *zg.LogicalFB) void {
        // left = LOGO_CX + sin(a) * (LOGO_SWAY * sin(b)) - LOGO_W (setmidhandle), rounded
        const wave = (fx.sin(fx.hi(self.logo_sin)) * fx.sin(fx.hi(self.logo_inc))) >> 30;
        const column = fx.roundQ30(LOGO_CX - LOGO_W, LOGO_SWAY, wave); // nearest canvas column
        const img = blit.Image.init(self.data[LOGO..][0 .. LOGO_W * LOGO_H], LOGO_W);
        blit.blit(blit.Dst.plane(fb), img, null, @divFloor(column, 2), (LOGO_CY - LOGO_H) / 2, 0, .copy);
    }

    /// The loop of screen.js:118-128, with its running phases: sy restarts from
    /// the frame's phase on every row and gains 0.3 a tile; sx gains 0.3 a row.
    /// sin(sy) depends on the tile column only, so it is taken sixteen times, not 224.
    fn drawLetters(self: *Demo, fb: *zg.LogicalFB) void {
        const dst = blit.Dst.plane(fb);
        const font = blit.Image.init(self.data[FONT..][0 .. FONT_W * FONT_H], FONT_W);
        var swing_y: [TILES_X]i64 = undefined; // sin(sy) * SWING_Y, Q30
        var sy = self.letters;
        for (&swing_y) |*w| {
            w.* = fx.sin(fx.hi(sy)) * SWING_Y;
            sy +%= LETTER_PHASE;
        }
        var sx = self.letters;
        for (0..TILES_Y) |ty| {
            const swing_x = fx.sin(fx.hi(sx)) * SWING_X;
            for (0..TILES_X) |tx| {
                const part = blit.Rect{ .x = tx * TILE_W / 2, .y = ty * TILE_H / 2, .w = TILE_W / 2, .h = TILE_H / 2 };
                // half(v) = Math.round(v / 2) = floor((v + 1) / 2), v = tile origin + swing
                const hx: i32 = @intCast(((@as(i64, TEXT_X + TILE_W * tx + 1) << 30) + swing_x) >> 31);
                const hy: i32 = @intCast(((@as(i64, TEXT_Y + TILE_H * ty + 1) << 30) + swing_y[tx]) >> 31);
                blit.blit(dst, font, part, hx, hy, 0, .{ .row = &ink_row });
            }
            sx +%= LETTER_PHASE;
        }
    }

    // Escape, Back, Space and Fire (the remake's Space) end the intro: the street's
    // loader panel comes next. demoLoader stopped the intro tune; the panel stays
    // silent until the street asks for its own (Matt: silence for now).
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or cp == K_SPACE) self.next();
    }

    pub fn input(self: *Demo, dir: u8) void {
        if (dir == DIR_BACK or dir == DIR_FIRE) self.next();
    }

    fn next(self: *Demo) void {
        if (self.depacking or self.wants_quit or self.done) return;
        zg.stopSong();
        self.done = true;
    }
};
