// --------------------------------------------------------------------------
// THE CAREBEARS + THE REPLICANTS — "WEIRD DREAM" crack intro, 19-07-89.
//   original: cracked by RATBOY, intro coded by NICK, JAS and AN COOL at the
//   first TCB - Replicants meeting; music ROLLOUT by MAD MAX (Jochen Hippel)
//   CODEF HTML5 remake: wab.com screen 345, MIT-licensed
//
// Ported from prototypes/codef/345/screen.js. An Atari ST screen: the backend
// is sc68 and the main canvas is 640x400 = 320x200 doubled; every drawn
// element sits inside 320x200 (stars 0..139, logos -6..147, scroller band
// 140..199, sprites 151..194), so no border is opened. The other canvases are
// offscreens: 190x2000 and 558x1540 are the 40 + 35 precalculated logo zooms,
// 768x50 the scroll strip, 640x50 its distorted copy, 640x280 the starfield,
// 8x50 the one-column `letter` the scrolltext is drawn into.
//
// PARTS
//  1. The splash (dosplash, screen.js:312): black text on colour 0 = $777 grey,
//     laid down 40 canvas rows more a frame, held 200 frames. The real intro
//     showed it while precalculating the zooms. Colour 0 is also the BORDER on
//     an ST, so the border is grey for the splash and black afterwards.
//  2. The main part (go(), screen.js:385), in its order: the REPLICANTS and TCB
//     logos zooming on their precalc frames (TCB drawn on top while its z is
//     in front), the 3-layer starfield over them, the scroller — 25 rows each
//     offset by the 802-entry table, then cut into 40 blocks of 8 pixels on a
//     cosine — and the two UNION sprites bouncing on |cos| and |sin|.
//
// DEPARTURES FROM THE REMAKE
//  - The fake AtariDecrunch depack screen (screen.js:275, :297-306) is NOT
//    ported: ZigMachine depacks for real (libs/zig/depackers/depack_fx.zig).
//  - Fractional canvas positions (the cosine band, the sprites) snap to the
//    nearest ST pixel; the canvas blends them. The logo zooms are Chrome's own
//    precalc, halved and kept to each logo's 3 colours.
//  - mergecanvas2 and myfx (an FX on it) are created and cleared every frame
//    but never drawn: dead offscreens, dropped.
//  - The stars are seeded from a fixed xorshift, not Math.random().
//
// ONE plane, one 24-colour palette (every colour ST-legal, nibble*32): the
// stars are the TCB logo's own three colours, as an ST palette would share.
// There is no raster on this screen: nothing changes colour per line.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const motion = @import("tcb_weirddream/motion.zig");
const draw = @import("tcb_weirddream/draw.zig");

const palette = zg.convertU8ArraytoColors(@embedFile("../assets/screens/tcb_weirddream/pal.dat"));

// MUSIC. screen.js:36-39 plays `Rollout.sndh;1` and `Rollout.sndh;2` (F1/F2,
// as the splash says). sndh_index "rollout": Mad_Max/Games/Rollout.sndh, TITL
// "Rollout", COMM "Mad Max", 1989, FLAG ~y, 2 subtunes (the ~abdy SID variant
// would play silence). The remake's own ICE-packed copy from wab.com (CONV
// "Grazey / PHF") leaves the YM in the SAME registers as this one after one
// second through apps/sndh_headless.mjs, subtune 1 and subtune 2 alike.
pub const MUSIC = "rollout.sndh";

pub const SPLASH_FRAMES: u32 = 200; // `if (splashtime >= 200)`: go() takes frame 201
const GREY = Color{ .r = 224, .g = 224, .b = 224, .a = 255 };
const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const K_F1: u32 = 0xE001;
const K_F2: u32 = 0xE002;
const K_ESC: u32 = 0xE012;

var stars: [motion.STARS]motion.Star = undefined;

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    frame: u32, // displayed frames since the start, splash included
    phase: motion.Phase,
    layout: motion.Layout,
    tune: u8, // 0 = no music yet (the splash), else the subtune playing
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("tcb_weirddream: TCB + REPLICANTS / WEIRD DREAM", .{});
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(palette);
        fb.setPaletteEntry(0, GREY); // the splash's colour 0
        zigos.setBackgroundColor(GREY); // ...which is the border too
        self.frame = 0;
        self.phase.reset();
        self.tune = 0;
        self.wants_quit = false;
        motion.seedStars(&stars);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.frame +%= 1;
        // The host paints the border in hwClear BEFORE the cart's frame, so the
        // border goes black one frame early: on the first main frame it is.
        if (self.frame == SPLASH_FRAMES) zigos.setBackgroundColor(BLACK);
        if (self.frame <= SPLASH_FRAMES) return;
        if (self.frame == SPLASH_FRAMES + 1) {
            zigos.lfbs[0].setPaletteEntry(0, BLACK);
            self.playTune(1); // dosplash: audio.playNextSong() as go() starts
        }
        // starfield2D_dot plots, THEN moves: last frame's move happens here.
        if (self.frame > SPLASH_FRAMES + 1) motion.moveStars(&stars);
        self.phase.layout(&self.layout);
        self.phase.step();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (self.frame <= SPLASH_FRAMES) return draw.splash(fb, self.frame);
        draw.clear(fb);
        draw.logos(fb, self.layout);
        draw.stars(fb, &stars);
        draw.scroller(fb, self.layout);
        draw.sprites(fb, self.layout);
    }

    fn playTune(self: *Demo, n: u8) void {
        self.tune = n;
        zg.requestSongTune(MUSIC, n);
    }

    /// F1 / F2 change the music, only once it plays and only to the other tune
    /// (screen.js:356-372). Escape leaves: a screen with key() owns it.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
        if (cp == K_F1 and self.tune == 2) self.playTune(1);
        if (cp == K_F2 and self.tune == 1) self.playTune(2);
    }
};
