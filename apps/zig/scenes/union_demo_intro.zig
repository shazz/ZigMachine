// --------------------------------------------------------------------------
// The Union Demo (1989) INTRO SCREEN, ported from shazz's melonJS "Union Demo
// HTML5 Remake" 0.9.8, screens/intro/screen.js. Artwork, text and music belong
// to The Union (The Carebears: Nick, Jas, ES; music Mad Max).
//
// In the remake this is the splash the demo opens on (main.js:262-265): Space
// leaves it for the first TEX loader, then the menu. Here Space, Escape, Fire
// or Back boots the menu cart (union_demo).
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
//
// Space then leads to the remake's FIRST_LOADER, demoLoader (demoloader.js): a
// TEX loader panel of credits ("THIS SCREEN WAS DONE BY THE CAREBEARS ... PRESS
// ANY KEY TO CONTINUE") assembling on black, 140 ms of tween clock a frame
// (loader.js:184, ticked after each draw). Only Space once no tween is active,
// i.e. every letter landed, goes on (demoloader.js update), to the street.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const depackers = @import("depackers");
const tex = depackers.tex_loader;
const DepackFx = depackers.depack_fx.Runner(zg, null); // fx none: no tvnoise
const packed_intro = @import("packed_assets").union_demo_intro;

// Mad Max's "Union Demo LOADER" (ThinkTwice.ym holds U_LOADER.BIN). The archive's
// Mad_Max/Demos/Union_Demo/Ikari_Union.sndh subtune 1 matches that register dump
// at 95.7% (registers 0-5 exact, 8-10 masked to 5 bits, 800 frames, offset 0;
// 95.0% over 1800); the next best of 532 subtunes scored 26.5%.
const MUSIC = "ikari_union.sndh";
const MENU_TAG = "union_demo";

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
const LOGO_INC = 0.008;
const LOGO_SIN = 0.08;
const LOGO_CX = 320;
const LOGO_SWAY = 170;
const LOGO_CY = 32 + 6;
const LETTER_STEP = 0.06;
const LETTER_PHASE = 0.3;
const TEXT_X = 70;
const TEXT_Y = 136;
const TILE_W = 32;
const TILE_H = 16;
const TILES_X = 16; // for (x = 0; x < 512; x += 32)
const TILES_Y = 14; // for (y = 0; y < 224; y += 16)
const SWING_X = 32;
const SWING_Y = 16;

// demoLoader's panel, loaderText[0..22] (demoloader.js), as zx0pack reads it.
const CREDITS_COLS = 21;
const CREDITS_ROWS = 23;
const CREDITS_PANEL: [CREDITS_COLS * CREDITS_ROWS]u8 = blk: {
    const txt = @embedFile("../assets/screens/union_demo_intro/loader_demo.txt");
    var out: [CREDITS_COLS * CREDITS_ROWS]u8 = undefined;
    var rows: usize = 0;
    var it = std.mem.splitScalar(u8, txt, '\n');
    while (it.next()) |line| {
        if (line.len == 0 or line[0] != '"') continue;
        const row = line[1..std.mem.lastIndexOfScalar(u8, line, '"').?];
        if (row.len != CREDITS_COLS or rows == CREDITS_ROWS) @compileError("loader_demo.txt is not 23 rows of 21");
        @memcpy(out[rows * CREDITS_COLS ..][0..CREDITS_COLS], row);
        rows += 1;
    }
    if (rows != CREDITS_ROWS) @compileError("loader_demo.txt is not 23 rows of 21");
    break :blk out;
};
const TWEEN_TICK_MS = 140; // createjs.Tween.tick(140) (loader.js:184)
const CREDITS_LANDED_MS = tex.timelineEnd(CREDITS_COLS * CREDITS_ROWS);
const CREDITS_INK: u8 = 44; // first palette entry past intro_pal.dat's 43 colours

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = ' ';
const DIR_FIRE: u8 = 5;
const DIR_BACK: u8 = 6;

var ink_row: [zg.HEIGHT]u8 = undefined; // palette index per ST row for .row ink

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}

/// Canvas coordinate -> ST pixel, rounding to nearest (Math.round's tie rule).
fn half(v: f64) i32 {
    return @intFromFloat(@floor(v / 2 + 0.5));
}

pub const Demo = struct {
    data: []u8, // the depacked blob
    depacking: bool,
    bg_pos: i32, // bgposy
    logo_inc: f64, // logoInc
    logo_sin: f64, // logosin1
    letters: f64, // sinlettersx == sinlettersy after update()
    credits: bool, // FIRST_LOADER (demoloader.js) is on screen
    credits_ticks: u32, // Tween.tick calls so far
    credits_clock: u32, // ms of tween clock for this frame's draw
    leaving: bool,
    wants_quit: bool, // no way to run at all: back to the menu

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.bg_pos = BG_TOP;
        self.logo_inc = 0;
        self.logo_sin = 0;
        self.letters = 0;
        self.credits = false;
        self.credits_ticks = 0;
        self.credits_clock = 0;
        self.leaving = false;
        self.wants_quit = false;
        self.depacking = false;
        self.data = freeRam(BLOB_LEN) orelse return self.fail("no free RAM to depack into");
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
        fb.setPaletteEntry(CREDITS_INK, Color{ .r = tex.INK.r, .g = tex.INK.g, .b = tex.INK.b, .a = 255 });
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
        if (self.wants_quit) return;
        if (self.credits) { // this frame draws at the clock so far, then ticks
            self.credits_clock = self.credits_ticks * TWEEN_TICK_MS;
            self.credits_ticks += 1;
            return;
        }
        self.logo_inc += LOGO_INC;
        self.bg_pos += BG_STEP;
        if (self.bg_pos >= 0) self.bg_pos = BG_TOP;
        self.logo_sin += LOGO_SIN;
        self.letters += LETTER_STEP;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.depacking or self.wants_quit) return;
        const fb = &zigos.lfbs[0];
        if (self.credits) return tex.draw(fb, &CREDITS_PANEL, CREDITS_COLS, self.credits_clock, CREDITS_INK);
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
        const left = LOGO_CX + @sin(self.logo_sin) * (LOGO_SWAY * @sin(self.logo_inc)) - LOGO_W; // setmidhandle
        const column: i32 = @intFromFloat(@floor(left + 0.5)); // nearest canvas column
        const img = blit.Image.init(self.data[LOGO..][0 .. LOGO_W * LOGO_H], LOGO_W);
        blit.blit(blit.Dst.plane(fb), img, null, @divFloor(column, 2), (LOGO_CY - LOGO_H) / 2, 0, .copy);
    }

    /// The loop of screen.js:118-128, with its running phases: sy restarts from
    /// the frame's phase on every row and gains 0.3 a tile; sx gains 0.3 a row.
    fn drawLetters(self: *Demo, fb: *zg.LogicalFB) void {
        const dst = blit.Dst.plane(fb);
        const font = blit.Image.init(self.data[FONT..][0 .. FONT_W * FONT_H], FONT_W);
        var sx = self.letters;
        for (0..TILES_Y) |ty| {
            var sy = self.letters;
            for (0..TILES_X) |tx| {
                const x = @as(f64, @floatFromInt(TEXT_X + TILE_W * tx)) + @sin(sx) * SWING_X;
                const y = @as(f64, @floatFromInt(TEXT_Y + TILE_H * ty)) + @sin(sy) * SWING_Y;
                const part = blit.Rect{ .x = tx * TILE_W / 2, .y = ty * TILE_H / 2, .w = TILE_W / 2, .h = TILE_H / 2 };
                blit.blit(dst, font, part, half(x), half(y), 0, .{ .row = &ink_row });
                sy += LETTER_PHASE;
            }
            sx += LETTER_PHASE;
        }
    }

    // Escape and Back leave at any time. Space and Fire (the remake's Space) go
    // from the intro to FIRST_LOADER's panel, and from the panel, once every
    // letter has landed (no active tween), on to the street.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.leaving = true else if (cp == K_SPACE) self.next();
    }

    pub fn input(self: *Demo, dir: u8) void {
        if (dir == DIR_BACK) self.leaving = true else if (dir == DIR_FIRE) self.next();
    }

    fn next(self: *Demo) void {
        if (self.depacking or self.wants_quit) return;
        if (!self.credits) {
            self.credits = true; // onDestroyEvent of the intro, onResetEvent of demoLoader
            self.credits_ticks = 0;
            self.credits_clock = 0;
        } else if (self.credits_ticks * TWEEN_TICK_MS >= CREDITS_LANDED_MS) {
            self.leaving = true;
        }
    }

    // Cartridge swap (demo_main forwards these to the host): 1 boots MENU_TAG.
    pub fn pollCart(self: *Demo) i32 {
        if (self.wants_quit) return -1;
        if (!self.leaving) return 0;
        self.leaving = false;
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return MENU_TAG;
    }
};
