// --------------------------------------------------------------------------
// TEX — "The Exceptions" crack screen for The Union (CODEF screen 14).
// Every moving part follows screen.js's own formulas in 640x400 canvas units,
// halved onto the ST screen only when it is drawn.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const fx = @import("turns_fix.zig");
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
const LOGO_W = 208;
const back_b = @embedFile(DIR ++ "back.raw");
const BACK_POS: u16 = 200 - 87;

/// A 640x400 canvas coordinate (already rounded) on the 320x200 screen: the browser
/// draws an unscaled image at the ROUNDED canvas coordinate (measured on the
/// original), so halving floors that onto the ST grid.
fn half(canvas_coord: i32) i32 {
    return canvas_coord >> 1;
}

// starfield — screen.js:36-39 and codef_starfield.js:99-121 (starfield2D_dot) on
// the 640x190 star canvas: each layer's stars start at random*640, random*190,
// are plotted as a 2x2 fillRect and THEN move by speedx, wrapping x < 0 to 640.
// Integers: x in Q32 canvas pixels (random*640 is just seed*640 in Q32), the row a
// star is plotted on is fixed at birth (y never moves).
const Q32: i64 = 1 << 32;
const STAR_CANVAS_W: i64 = 640 * Q32;
const STAR_ROWS: i32 = 95;
const StarLayer = struct { nb: usize, speedx: i64, color: u8 };
const STAR_LAYERS = [_]StarLayer{
    .{ .nb = 25, .speedx = -5 * Q32, .color = 2 }, // #E0E0E0
    .{ .nb = 30, .speedx = -5153960755, .color = 1 }, // #606060, speed round(-1.2 * 2^32)
};
const NB_STARS = 25 + 30;
/// Math.random cannot be replayed, so the stars are seeded from this xorshift32.
/// The Chrome reference page substitutes the same generator for Math.random.
const STAR_SEED: u32 = 0x2545F491;
const Star = struct { x: i64, row: i32, speedx: i64, color: u8 };

// logo — screen.js:91 and 110-112: mid-handled 416x194 image, so its top-left
// is 320 + sin(sinx)*(100*sin(inc)) - 208 across and 97 - 97 down.
const LOGO_SINX_INC = fx.turns(0.13);
const LOGO_INC_INC = fx.turns(0.008);

// sprites — screen.js:51-75 and go() at 114-118: eleven 32x16 images (16x8 here)
// in one chain along x = 305 + 306*sin(p), y = 86 + 84*cos(1.5p), each 0.3 of
// phase behind the next and all advancing 0.04 per frame. Drawn in array order,
// after the logo and before the red font background, onto the logo's plane.
// Index 0 of each image is transparent (tools/private_tools/tex_assets.py).
const NB_SPRITES = 11;
const SPRITE_W = 16;
const SPRITE_PHASE_STEP = fx.turns(0.3); // phases are u64 turns (turns_fix.zig)
const SPRITE_PHASE_INC = fx.turns(0.04);
// cos(1.5 p) is its own accumulator: halving a phase already reduced mod a turn
// would lose the turn count.
const SPRITE_PHASE15_STEP = fx.turns(0.45);
const SPRITE_PHASE15_INC = fx.turns(0.06);
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
const font_b = @embedFile(DIR ++ "fonts.raw"); // one 32x17 tile per ASCII code, ink 255
const Letter = struct { x: i32, ch: u8 };
const Box = struct { x: i32 = 0, y: i32 = 0, w: usize = 0, h: usize = 0 };
const STAR_NONE: u32 = 0xFFFF_FFFF;

// --------------------------------------------------------------------------
// One plane, not four. The cart stacked stars < logo+sprites < red font background
// < scrolltext; FRESCO paints every enabled plane (~1.09 Mc each). The stars, logo
// and sprites live in rows 0..96, the background and the scroller in rows 113..199,
// so the layers only ever cover each other inside those two groups:
//   rows 0..96:    stars drawn, then the logo and the sprites keyed over them
//   rows 113..199: the background (drawn once); in the scroller band the font's ink
//                  shows the background's colour from blue_back_pal (the old plane
//                  ANDed the ink with the background's indices)
// Palette: 1..15 the logo's, 16/17 the stars', 32+b the background's colour b,
// 40+b its blue twin, so an ink pixel is its background pixel | 8.
// --------------------------------------------------------------------------
const STAR_IDX = [3]u8{ 0, 16, 17 };
const BACK = 32;
const INK = 8;
/// `raw` with index `from` moved to `to` and every other non-zero index up by `base`.
fn remap(comptime raw: []const u8, comptime from: u8, comptime to: u8, comptime base: u8) [raw.len]u8 {
    @setEvalBranchQuota(1_000_000);
    var out: [raw.len]u8 = undefined;
    for (raw, 0..) |v, i| out[i] = if (v == from) to else if (v == 0) 0 else v + base;
    return out;
}
// the logo's field (255) was transparent too: it becomes the key, 0
const logo_m = remap(logo_b, 255, 0, 0);
const back_m = remap(back_b, 0, 0, BACK);

comptime {
    std.debug.assert(SCROLL_TEXT.len >= NB_LETTERS);
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    logo: Sprite = undefined,
    back: Sprite = undefined,
    // u64 turns: exact to ~1e-19 of a revolution, so every phase stays on the
    // original's doubles however long the screen runs.
    logo_sinx: u64 = undefined,
    logo_inc: u64 = undefined,
    sprite_phase: [NB_SPRITES]u64 = undefined,
    sprite_phase15: [NB_SPRITES]u64 = undefined,
    sprite_x: [NB_SPRITES]i32 = undefined,
    sprite_y: [NB_SPRITES]i32 = undefined,
    stars: [NB_STARS]Star = undefined,
    star_drawn_x: [NB_STARS]i64 = undefined,
    // The plane index each star's dot was written at last render (STAR_NONE: not
    // drawn). Only these dots are erased, where the plane used to be cleared whole.
    star_px: [NB_STARS]u32 = undefined,
    // Where the logo and each sprite were drawn last render (a w == 0 box is
    // nothing): only those boxes are cleared before the next draw.
    dirty: [1 + NB_SPRITES]Box = undefined,
    letters: [NB_LETTERS]Letter = undefined,
    text_offset: usize = undefined,
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        self.blitter.init();
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(logo_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(STAR_IDX[2], Color{ .r = 0xE0, .g = 0xE0, .b = 0xE0, .a = 255 });
        fb.setPaletteEntry(STAR_IDX[1], Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });
        for (1..8) |b| {
            fb.setPaletteEntry(@intCast(BACK + b), back_pal[b]);
            fb.setPaletteEntry(@intCast(BACK + INK + b), blue_back_pal[b]);
        }
        self.initStars();
        fb.clearFrameBuffer(0);
        @memset(&self.star_px, STAR_NONE);
        self.dirty = [_]Box{.{}} ** (1 + NB_SPRITES);
        self.logo.init(fb.getRenderTarget(), logo_b, 208, 97, 0, 0, null, null);
        self.logo_sinx = 0;
        self.logo_inc = 0;
        for (0..NB_SPRITES) |i| {
            self.sprite_phase[i] = SPRITE_PHASE_STEP *% (i + 1);
            self.sprite_phase15[i] = SPRITE_PHASE15_STEP *% (i + 1);
            self.sprite_x[i] = 0;
            self.sprite_y[i] = 0;
        }
        // The red font background never moves: drawn once, not every frame.
        @memcpy(fb.fb[@as(usize, BACK_POS) * WIDTH ..][0..back_m.len], &back_m);

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
                const x: i64 = @as(i64, nextRandom(&seed)) * 640;
                const y: u64 = @as(u64, nextRandom(&seed)) * 190; // y in Q32
                // floor(floor(y + 1) / 2): the ST row of the 2x2 dot
                const row: i32 = @intCast((y + Q32) >> 33);
                self.stars[t] = .{ .x = x, .row = row, .speedx = layer.speedx, .color = layer.color };
                self.star_drawn_x[t] = x;
                t += 1;
            }
        }
    }

    /// xorshift32, the raw 32 bits (random = bits / 2^32): the stand-in for Math.random.
    fn nextRandom(seed: *u32) u32 {
        seed.* ^= seed.* << 13;
        seed.* ^= seed.* >> 17;
        seed.* ^= seed.* << 5;
        return seed.*;
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

        self.logo_sinx +%= LOGO_SINX_INC;
        self.logo_inc +%= LOGO_INC_INC;
        // halve(320 + sin(sinx) * (100 * sin(inc)) - 208), the canvas coordinate rounded
        const wave = (fx.sin(fx.hi(self.logo_sinx)) * fx.sin(fx.hi(self.logo_inc))) >> 30;
        self.logo.update(half(fx.roundQ30(112, 100, wave)), null, null, null);

        // go() advances each phase BEFORE drawing (screen.js:116-117)
        for (0..NB_SPRITES) |i| {
            self.sprite_phase[i] +%= SPRITE_PHASE_INC;
            self.sprite_phase15[i] +%= SPRITE_PHASE15_INC;
            const p = self.sprite_phase[i];
            self.sprite_x[i] = half(fx.roundQ30(305, 306, fx.sin(fx.hi(p))));
            self.sprite_y[i] = half(fx.roundQ30(86, 84, fx.cos(fx.hi(self.sprite_phase15[i]))));
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
        const fb = &zigos.lfbs[0];
        self.eraseBoxes(fb);
        self.renderStars(fb);
        self.renderLogo(fb);
        self.renderScroller(fb);
    }

    /// x..x+w clipped to the screen: (first column, source skip, width).
    fn clipX(x: i32, w: usize) ?struct { at: u16, skip: u16, n: u16 } {
        const lo = @max(x, 0);
        const hi = @min(x + @as(i32, @intCast(w)), @as(i32, WIDTH));
        if (hi <= lo) return null;
        return .{ .at = @intCast(lo), .skip = @intCast(lo - x), .n = @intCast(hi - lo) };
    }

    /// Last frame's logo and sprite boxes back to 0 (CHISEL), before the stars.
    fn eraseBoxes(self: *Demo, fb: *LogicalFB) void {
        for (self.dirty) |b| {
            const cx = clipX(b.x, b.w) orelse continue;
            self.blitter.fill(fb, @intCast(cx.at), @intCast(b.y), cx.n, @intCast(b.h), 0);
        }
    }

    /// The logo, then the sprites in order, keyed over the stars by CHISEL (key 0:
    /// palette 0 and the logo's field both had alpha 0).
    fn renderLogo(self: *Demo, fb: *LogicalFB) void {
        const logo_x = self.logo.x_position;
        self.blitKeyed(fb, &logo_m, LOGO_W, logo_x, 0, 97);
        self.dirty[0] = .{ .x = logo_x, .y = 0, .w = LOGO_W, .h = 97 };
        for (sprite_imgs, self.sprite_x, self.sprite_y, self.dirty[1..]) |img, x, y, *box| {
            self.blitKeyed(fb, img.data, SPRITE_W, x, y, img.h);
            box.* = .{ .x = x, .y = y, .w = img.w, .h = img.h };
        }
    }

    fn blitKeyed(self: *Demo, fb: *LogicalFB, data: []const u8, w: usize, x: i32, y: i32, h: usize) void {
        const cx = clipX(x, w) orelse return;
        self.blitter.blitImage(fb, @intCast(cx.at), @intCast(y), data, @intCast(w), cx.skip, 0, cx.n, @intCast(h), 0);
    }

    /// A 2x2 canvas dot is one ST pixel: the one holding the dot's centre.
    /// Later stars cover earlier ones, as they do on the canvas.
    fn renderStars(self: *Demo, fb: *LogicalFB) void {
        for (self.star_px) |at| {
            if (at != STAR_NONE and fb.fb[at] != 0) fb.fb[at] = 0; // a box erase may have done it
        }
        for (self.stars, self.star_drawn_x, &self.star_px) |star, drawn_x, *at| {
            const x: i32 = @intCast((drawn_x + Q32) >> 33);
            const y = star.row;
            at.* = STAR_NONE;
            if (x < 0 or x >= WIDTH or y >= STAR_ROWS) continue;
            at.* = @as(u32, @intCast(y)) * fb.stride + @as(u32, @intCast(x));
            fb.fb[at.*] = STAR_IDX[star.color];
        }
    }

    /// The band back to the background (CHISEL), then each letter's ink as its
    /// background pixel's blue twin. Letters are 32 px apart and never overlap.
    fn renderScroller(self: *Demo, fb: *LogicalFB) void {
        const band_row = SCROLL_POS - BACK_POS;
        self.blitter.blitImage(fb, 0, SCROLL_POS, &back_m, WIDTH, 0, band_row, WIDTH, SCROLL_CHAR_H, null);
        for (self.letters) |letter| {
            const tile: usize = if (letter.ch >= SCROLL_FIRST_CHAR) letter.ch - SCROLL_FIRST_CHAR else 0;
            const cx = clipX(@divFloor(letter.x, 2), SCROLL_CHAR_W) orelse continue;
            for (0..SCROLL_CHAR_H) |r| {
                const src = font_b[(tile * SCROLL_CHAR_H + r) * SCROLL_CHAR_W + cx.skip ..][0..cx.n];
                const at = (band_row + r) * WIDTH + cx.at;
                const dst = fb.fb[(SCROLL_POS + r) * WIDTH + cx.at ..][0..cx.n];
                for (src, dst, back_m[at..][0..cx.n]) |ink, *d, b| {
                    if (ink != 0) d.* = b | INK;
                }
            }
        }
    }
};
