// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const readU16Array = zg.readU16Array;
const readI16Array = zg.readI16Array;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;
const Starfield = zg.Starfield;
const Sprite = zg.Sprite;
const StarfieldDirection = zg.StarfieldDirection;
const blit = zg.blit;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max's C64 conversion of "Scout" (1988).
const MUSIC = "scout.sndh";

const NB_STARS = 100;

// scrolltext
pub const NB_FONTS: u8 = WIDTH/SCROLL_CHAR_WIDTH + 1;
const fonts_b = @embedFile("../assets/screens/the_union/fonts.raw");
const SCROLL_TEXT = "            THE EXCEPTIONS PROUDLY PRESENT THIS NEW GAME CRACKED BY HOWDY FROM THE EXCEPTIONS MEMBER OF THE UNION     LET WRAP      ";
const SCROLL_CHAR_WIDTH = 32;
const SCROLL_CHAR_HEIGHT = 17;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SCROLL_POS: u16 = 142;
const BACK_POS: u16 = 200-87;

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/the_union/logo_pal.dat"));
const back_pal = convertU8ArraytoColors(@embedFile("../assets/screens/the_union/back_pal.dat"));
const blue_back_pal = convertU8ArraytoColors(@embedFile("../assets/screens/the_union/blue_back_pal.dat"));

// logo
const logo_b = @embedFile("../assets/screens/the_union/logo.raw");
const back_b = @embedFile("../assets/screens/the_union/back.raw");

// sprites — screen.js:51-75 and go() at 114-118: eleven 32x16 images (16x8 here)
// in one chain along x = 305 + 306*sin(p), y = 86 + 84*cos(1.5p), each 0.3 of
// phase behind the next and all advancing 0.04 per frame. Drawn in array order,
// after the logo and before the red font background, onto the logo's plane.
// Index 0 of each image is transparent (tools/private_tools/tex_assets.py).
const NB_SPRITES = 11;
const SPRITE_W = 16;
const SPRITE_PHASE_STEP: f64 = 0.3;
const SPRITE_PHASE_INC: f64 = 0.04;
const delta_img = blit.Image.init(@embedFile("../assets/screens/the_union/delta.raw"), SPRITE_W);
const sprite_imgs = [NB_SPRITES]blit.Image{
    delta_img, delta_img, delta_img,
    blit.Image.init(@embedFile("../assets/screens/the_union/h.raw"), SPRITE_W),
    blit.Image.init(@embedFile("../assets/screens/the_union/o.raw"), SPRITE_W),
    blit.Image.init(@embedFile("../assets/screens/the_union/w.raw"), SPRITE_W),
    blit.Image.init(@embedFile("../assets/screens/the_union/d.raw"), SPRITE_W),
    blit.Image.init(@embedFile("../assets/screens/the_union/y.raw"), SPRITE_W),
    delta_img, delta_img, delta_img,
};

/// A 640x400 canvas coordinate on the 320x200 screen. The browser draws an
/// unscaled image at the ROUNDED coordinate (measured against the original), so
/// a sprite covers 2x-pixels round(c)..; halving floors that onto the ST grid.
fn halve(canvas_coord: f64) i32 {
    return @divFloor(@as(i32, @intFromFloat(@round(canvas_coord))), 2);
}

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

pub const Demo = struct {

    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    back: Sprite = undefined,
    starfield: Starfield(NB_STARS) = undefined,
    // f64 like the JS numbers, so the chain keeps the original's phase however
    // long the screen runs (f32 drifts by 0.16 rad in ten minutes).
    sprite_phase: [NB_SPRITES]f64 = undefined,
    sprite_x: [NB_SPRITES]i32 = undefined,
    sprite_y: [NB_SPRITES]i32 = undefined,
    logo_sinx: f32 = 0,
    logo_inc: f32 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        self.starfield = Starfield(NB_STARS).init(fb.getRenderTarget(), WIDTH, 95, 0, 1, 3, StarfieldDirection.LEFT);

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(2, Color{ .r = 0xE0, .g = 0xE0, .b = 0xE0, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.logo.init(fb.getRenderTarget(), logo_b, 208, 97, WIDTH/2-104, 0, null, null);
        self.logo_sinx = 0;
        self.logo_inc = 0;

        for (0..NB_SPRITES) |i| {
            self.sprite_phase[i] = SPRITE_PHASE_STEP * @as(f64, @floatFromInt(i + 1));
            self.sprite_x[i] = 0;
            self.sprite_y[i] = 0;
        }

        // 3rd plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(back_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.back.init(fb.getRenderTarget(), back_b, 320, 87, 0, BACK_POS, null, null);

        // 4th plane
        fb = &zigos.lfbs[3];
        fb.is_enabled = true;
        fb.setPalette(blue_back_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, SCROLL_POS, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.update();
        self.scrolltext.update();

        self.logo_sinx += 0.13;
        self.logo_inc += 0.008;

        const x_pos: f32 = @sin(self.logo_sinx) * (50 * @sin(self.logo_inc));
        self.logo.update(52 + @as(i16, @intFromFloat(x_pos)), null, null, null);

        // go() advances each phase BEFORE drawing (screen.js:116-117)
        for (0..NB_SPRITES) |i| {
            self.sprite_phase[i] += SPRITE_PHASE_INC;
            const p = self.sprite_phase[i];
            self.sprite_x[i] = halve(305 + 306 * @sin(p));
            self.sprite_y[i] = halve(86 + 84 * @cos(p * 1.5));
        }

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.target.clearFrameBuffer(0);
        self.starfield.render();

        zigos.lfbs[1].clearFrameBuffer(0);
        self.logo.render(null);
        const sprites_dst = blit.Dst.plane(&zigos.lfbs[1]);
        for (sprite_imgs, self.sprite_x, self.sprite_y) |img, x, y| {
            blit.blit(sprites_dst, img, null, x, y, 0, .copy);
        }

        self.back.render(null);

        var fb = &zigos.lfbs[3];
        self.scrolltext.target.clearFrameBuffer(0);
        self.scrolltext.render();

        var i: usize = SCROLL_POS * WIDTH;
        var tx: usize = (SCROLL_POS - BACK_POS) * WIDTH;
        while(i < (SCROLL_POS * WIDTH) + (WIDTH * SCROLL_CHAR_HEIGHT)) : ( i += 1) {
            fb.fb[i] = fb.fb[i] & back_b[tx];
            tx += 1;
        }

        _ = elapsed_time;

    }
};
