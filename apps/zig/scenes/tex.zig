// --------------------------------------------------------------------------
// TEX — "The Exceptions" crack screen for The Union (CODEF screen 14).
// Every moving part follows screen.js's own formulas in 640x400 canvas units,
// halved onto the ST screen only when it is drawn.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Sprite = zg.Sprite;
const blit = zg.blit;
const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max's C64 conversion of "Scout" (1988).
const MUSIC = "scout.sndh";

const DIR = "../assets/screens/the_union/";

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile(DIR ++ "logo_pal.dat"));
const back_pal = convertU8ArraytoColors(@embedFile(DIR ++ "back_pal.dat"));
const blue_back_pal = convertU8ArraytoColors(@embedFile(DIR ++ "blue_back_pal.dat"));

const logo_b = @embedFile(DIR ++ "logo.raw");
const back_b = @embedFile(DIR ++ "back.raw");
const BACK_POS: u16 = 200 - 87;

/// A 640x400 canvas coordinate on the 320x200 screen. The browser draws an
/// unscaled image at the ROUNDED canvas coordinate (measured on the original),
/// so it covers 2x-pixels round(c)..; halving floors that onto the ST grid.
fn halve(canvas_coord: f64) i32 {
    return @divFloor(@as(i32, @intFromFloat(@round(canvas_coord))), 2);
}

// starfield — screen.js:36-39 and codef_starfield.js:99-121 (starfield2D_dot) on
// the 640x190 star canvas: each layer's stars start at random*640, random*190,
// are plotted as a 2x2 fillRect and THEN move by speedx, wrapping x < 0 to 640.
const STAR_CANVAS_W: f64 = 640;
const STAR_CANVAS_H: f64 = 190;
const STAR_ROWS: i32 = 95;
const StarLayer = struct { nb: usize, speedx: f64, color: u8 };
const STAR_LAYERS = [_]StarLayer{
    .{ .nb = 25, .speedx = -5.0, .color = 2 }, // #E0E0E0
    .{ .nb = 30, .speedx = -1.2, .color = 1 }, // #606060
};
const NB_STARS = 25 + 30;
/// Math.random cannot be replayed, so the stars are seeded from this xorshift32.
/// The Chrome reference page substitutes the same generator for Math.random.
const STAR_SEED: u32 = 0x2545F491;
const Star = struct { x: f64, y: f64, speedx: f64, color: u8 };

// logo — screen.js:91 and 110-112: mid-handled 416x194 image, so its top-left
// is 320 + sin(sinx)*(100*sin(inc)) - 208 across and 97 - 97 down.
const LOGO_SINX_INC: f64 = 0.13;
const LOGO_INC_INC: f64 = 0.008;

// sprites — screen.js:51-75 and go() at 114-118: eleven 32x16 images (16x8 here)
// in one chain along x = 305 + 306*sin(p), y = 86 + 84*cos(1.5p), each 0.3 of
// phase behind the next and all advancing 0.04 per frame. Drawn in array order,
// after the logo and before the red font background, onto the logo's plane.
// Index 0 of each image is transparent (tools/private_tools/tex_assets.py).
const NB_SPRITES = 11;
const SPRITE_W = 16;
const SPRITE_PHASE_STEP: f64 = 0.3;
const SPRITE_PHASE_INC: f64 = 0.04;
const delta_img = blit.Image.init(@embedFile(DIR ++ "delta.raw"), SPRITE_W);
const sprite_imgs = [NB_SPRITES]blit.Image{
    delta_img, delta_img, delta_img,
    blit.Image.init(@embedFile(DIR ++ "h.raw"), SPRITE_W),
    blit.Image.init(@embedFile(DIR ++ "o.raw"), SPRITE_W),
    blit.Image.init(@embedFile(DIR ++ "w.raw"), SPRITE_W),
    blit.Image.init(@embedFile(DIR ++ "d.raw"), SPRITE_W),
    blit.Image.init(@embedFile(DIR ++ "y.raw"), SPRITE_W),
    delta_img, delta_img, delta_img,
};

// scrolltext — screen.js:93-96 and codef_scrolltext.js:57-133
// (scrolltext_horizontal). 64x34 tiles from ASCII 32, speed 3 canvas px a frame.
// wide = ceil(640/64)+1 = 11, so letters 0..11 start at 704 + 64*i holding the
// text's first twelve characters; a letter at <= -64 re-enters at
// 704 + posx + 64 with the next character. Positions stay in canvas units and
// are halved when drawn, so the ST scroll steps 1,2,1,2 px: 1.5 px a frame.
const SCROLL_TEXT = "THE EXCEPTIONS PROUDLY PRESENT THIS NEW GAME CRACKED BY HOWDY FROM THE EXCEPTIONS MEMBER OF THE UNION     LET WRAP              ";
const SCROLL_SPEED: i32 = 3;
const SCROLL_TILE_W: i32 = 64;
const SCROLL_WIDE: i32 = 11;
const NB_LETTERS = SCROLL_WIDE + 1;
const SCROLL_FIRST_CHAR = 32;
const SCROLL_CHAR_W = 32;
const SCROLL_CHAR_H = 17;
const SCROLL_POS: u16 = 142;
const font_img = blit.Image.init(@embedFile(DIR ++ "fonts.raw"), SCROLL_CHAR_W); // one 32x17 tile per ASCII code
const Letter = struct { x: i32, ch: u8 };

comptime {
    std.debug.assert(SCROLL_TEXT.len >= NB_LETTERS);
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    logo: Sprite = undefined,
    back: Sprite = undefined,
    // f64 like the JS numbers, so every phase stays on the original's however
    // long the screen runs (f32 drifts by 0.16 rad in ten minutes).
    logo_sinx: f64 = undefined,
    logo_inc: f64 = undefined,
    sprite_phase: [NB_SPRITES]f64 = undefined,
    sprite_x: [NB_SPRITES]i32 = undefined,
    sprite_y: [NB_SPRITES]i32 = undefined,
    stars: [NB_STARS]Star = undefined,
    star_drawn_x: [NB_STARS]f64 = undefined,
    letters: [NB_LETTERS]Letter = undefined,
    text_offset: usize = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane: the stars
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(2, Color{ .r = 0xE0, .g = 0xE0, .b = 0xE0, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });
        self.initStars();

        // second plane: logo and sprites
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.logo.init(fb.getRenderTarget(), logo_b, 208, 97, 0, 0, null, null);
        self.logo_sinx = 0;
        self.logo_inc = 0;
        for (0..NB_SPRITES) |i| {
            self.sprite_phase[i] = SPRITE_PHASE_STEP * @as(f64, @floatFromInt(i + 1));
            self.sprite_x[i] = 0;
            self.sprite_y[i] = 0;
        }

        // 3rd plane: the red font background
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(back_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.back.init(fb.getRenderTarget(), back_b, 320, 87, 0, BACK_POS, null, null);

        // 4th plane: the scrolltext
        fb = &zigos.lfbs[3];
        fb.is_enabled = true;
        fb.setPalette(blue_back_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        for (&self.letters, 0..) |*letter, i| {
            letter.* = .{ .x = SCROLL_WIDE * SCROLL_TILE_W + @as(i32, @intCast(i)) * SCROLL_TILE_W, .ch = SCROLL_TEXT[i] };
        }
        self.text_offset = NB_LETTERS;

        Console.log("demo init done!", .{});
    }

    fn initStars(self: *Demo) void {
        var seed: u32 = STAR_SEED;
        var t: usize = 0;
        for (STAR_LAYERS) |layer| {
            for (0..layer.nb) |_| {
                const x = nextRandom(&seed) * STAR_CANVAS_W;
                const y = nextRandom(&seed) * STAR_CANVAS_H;
                self.stars[t] = .{ .x = x, .y = y, .speedx = layer.speedx, .color = layer.color };
                self.star_drawn_x[t] = x;
                t += 1;
            }
        }
    }

    /// xorshift32 in [0, 1): the stand-in for Math.random.
    fn nextRandom(seed: *u32) f64 {
        seed.* ^= seed.* << 13;
        seed.* ^= seed.* >> 17;
        seed.* ^= seed.* << 5;
        return @as(f64, @floatFromInt(seed.*)) / 4294967296.0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;

        // starfield2D_dot.draw(): plot where the star is, then move it
        for (&self.stars, &self.star_drawn_x) |*star, *drawn_x| {
            drawn_x.* = star.x;
            star.x += star.speedx;
            if (star.x > STAR_CANVAS_W) star.x = 0;
            if (star.x < 0) star.x = STAR_CANVAS_W;
        }

        self.logo_sinx += LOGO_SINX_INC;
        self.logo_inc += LOGO_INC_INC;
        self.logo.update(halve(320 + @sin(self.logo_sinx) * (100 * @sin(self.logo_inc)) - 208), null, null, null);

        // go() advances each phase BEFORE drawing (screen.js:116-117)
        for (0..NB_SPRITES) |i| {
            self.sprite_phase[i] += SPRITE_PHASE_INC;
            const p = self.sprite_phase[i];
            self.sprite_x[i] = halve(305 + 306 * @sin(p));
            self.sprite_y[i] = halve(86 + 84 * @cos(p * 1.5));
        }

        self.updateScroller();
    }

    fn updateScroller(self: *Demo) void {
        for (&self.letters) |*letter| {
            letter.x -= SCROLL_SPEED;
            if (letter.x <= -SCROLL_TILE_W) {
                letter.x = SCROLL_WIDE * SCROLL_TILE_W + (letter.x + SCROLL_TILE_W);
                letter.ch = SCROLL_TEXT[self.text_offset];
                self.text_offset += 1;
                if (self.text_offset > SCROLL_TEXT.len - 1) self.text_offset = 0;
            }
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        self.renderStars(&zigos.lfbs[0]);

        zigos.lfbs[1].clearFrameBuffer(0);
        self.logo.render(null);
        const sprites_dst = blit.Dst.plane(&zigos.lfbs[1]);
        for (sprite_imgs, self.sprite_x, self.sprite_y) |img, x, y| {
            blit.blit(sprites_dst, img, null, x, y, 0, .copy);
        }

        self.back.render(null);

        self.renderScroller(&zigos.lfbs[3]);
    }

    /// A 2x2 canvas dot is one ST pixel: the one holding the dot's centre.
    /// Later stars cover earlier ones, as they do on the canvas.
    fn renderStars(self: *Demo, fb: *LogicalFB) void {
        fb.clearFrameBuffer(0);
        for (self.stars, self.star_drawn_x) |star, drawn_x| {
            const x = @divFloor(@as(i32, @intFromFloat(@floor(drawn_x + 1))), 2);
            const y = @divFloor(@as(i32, @intFromFloat(@floor(star.y + 1))), 2);
            if (x < 0 or x >= WIDTH or y >= STAR_ROWS) continue;
            fb.setPixelValue(@intCast(x), @intCast(y), star.color);
        }
    }

    fn renderScroller(self: *Demo, fb: *LogicalFB) void {
        fb.clearFrameBuffer(0);
        const dst = blit.Dst.plane(fb);
        for (self.letters) |letter| {
            const tile: usize = if (letter.ch >= SCROLL_FIRST_CHAR) letter.ch - SCROLL_FIRST_CHAR else 0;
            const cell = blit.Rect{ .x = 0, .y = tile * SCROLL_CHAR_H, .w = SCROLL_CHAR_W, .h = SCROLL_CHAR_H };
            blit.blit(dst, font_img, cell, @divFloor(letter.x, 2), SCROLL_POS, 0, .copy);
        }

        // the font's colour mask against the font background, as before
        const row_start: usize = SCROLL_POS * WIDTH;
        const back_start: usize = (SCROLL_POS - BACK_POS) * WIDTH;
        const n: usize = WIDTH * SCROLL_CHAR_H;
        for (fb.fb[row_start..][0..n], back_b[back_start..][0..n]) |*d, m| d.* &= m;
    }
};
