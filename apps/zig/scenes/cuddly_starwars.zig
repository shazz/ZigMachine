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
// The parts: cuddly_starwars/stars.zig (2), starwars.zig (3), distort.zig (4),
// sprites.zig (5), flash.zig (the logo, 1).
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

const zg = @import("zigos");
const tables = @import("cuddly_starwars/tables.zig");
const starwars = @import("cuddly_starwars/starwars.zig");
const fixed = @import("cuddly_starwars/fixed.zig");
const Stars = @import("cuddly_starwars/stars.zig").Stars;
const Distort = @import("cuddly_starwars/distort.zig").Distort;
const Sprites = @import("cuddly_starwars/sprites.zig").Sprites;

const ZigOS = zg.ZigOS;
const Color = zg.Color;

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;
const PLANE = 0;
const MUSIC = "bangkok_knights.sndh";

// palette (screen_pal.dat holds 0..15; the grey ramp is built below)
const BLACK: u8 = 0;
const RASTER_INK: u8 = 1;

// align(4): a Color is 4 bytes of align 1, read as one word; at an odd address that
// load traps on the board (~210 cycles). Its place in the data segment is luck otherwise.
const base_pal align(4) = zg.convertU8ArraytoColors(@embedFile("../assets/screens/cuddly_starwars/screen_pal.dat"));

const Flash = @import("cuddly_starwars/flash.zig").Flash(base_pal);

const palette: [256]Color = blk: {
    var p = base_pal;
    for (0..fixed.GREY_LEVELS) |k| {
        const g: u8 = fixed.grey_lut[fixed.GREY_BASE + k];
        p[fixed.GREY_BASE + k] = .{ .r = g, .g = g, .b = g, .a = 255 };
    }
    break :blk p;
};

// The red ink's colour per line: a copper table (zg.copper), which HW 1.9.0
// plays as a list the machine applies itself. It was an HBL handler setting
// entry 1 on each of the 200 lines: the same register writes, but each one an
// interrupt the CPU served between FRESCO's line passes. It stays static: the
// machine reads it, and it is only 1,120 B.
var raster_tbl: [1]zg.copper.Table = undefined;
const RASTER_SLOT: zg.copper.Slot = 0;

pub const Demo = struct {
    blitter: zg.Blitter = .{},
    flash: Flash, // the logo flash (cuddly_starwars/flash.zig)
    stars: Stars,
    sw_offset: i32, // ssspeed: 0..-16
    sw_line: usize, // addword
    distort: Distort,
    sprites: Sprites,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed (or holding the previous cart's bytes):
        // every field is set here, never by a declared default.
        self.blitter.init();
        self.flash = Flash.init;
        self.sw_offset = 0;
        self.sw_line = 0;
        self.distort.init();
        self.sprites = Sprites.init;
        // The large buffers come from the cart RAM arena (zg.mem), in this order.
        self.stars = Stars.init();
        starwars.init();

        zg.requestSong(MUSIC);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(palette);
        @memset(fb.fb[0 .. W * H], BLACK);
        zg.copper.install(fb, &.{RASTER_INK}, &raster_tbl, .{});
    }

    /// Every step go() takes before it draws, in its order.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.flash.step();
        self.stars.step();
        self.sw_offset -= 1;
        if (self.sw_offset < -(starwars.PITCH_Y - 1)) {
            self.sw_offset = 0;
            self.sw_line += 1;
            if (self.sw_line > tables.starwars_lines.len - starwars.LINES) self.sw_line = 0;
        }
        self.distort.step();
        self.sprites.step();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const screen = fb.fb[0 .. W * H];
        // A CPU memset: ~2.3 cycles a word since posted stores (0.04 Mc), where the
        // CHISEL fill waited ~0.12 Mc for its 64,000 units.
        @memset(screen, BLACK);
        self.flash.draw(fb, &self.blitter);
        self.stars.draw(screen);
        starwars.draw(screen, self.sw_line, self.sw_offset);
        self.distort.buildRasterLines(zg.copper.visible(fb, RASTER_SLOT));
        self.distort.draw(fb, &self.blitter);
        self.sprites.draw(screen);
    }
};
