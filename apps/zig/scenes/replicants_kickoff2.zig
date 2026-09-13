// --------------------------------------------------------------------------
// THE REPLICANTS — "Kick Off 2" crack intro (broken by R.AL and Snake; intro
// written by The ST Connexion: coding Marlon, artwork Krazy Rex, music Mad Max).
//
// Ported from the CODEF HTML5 remake (wab.com screen 168, MIT).
// Graphics, scrolltext and the original ST intro belong to their authors;
// music: "Rings of Medusa" title track, Jochen Hippel (Mad Max), subtune 2 of
// docs/music/rings_of_medusa.sndh — its periods match the remake's medusa.ym
// frame for frame.
//
// Reference kept at prototypes/codef/168/ (tools/fetch_codef.py 168).
// Assets: tools/private_tools/replicants_kickoff2_assets.py.
//
// The remake canvas is 640x480 = ST 320x240 doubled. Halved, the content fills
// all 240 rows — picture 0..215, black bar 215..240, scroller 217..230 — so
// this ST screen ran with the BOTTOM BORDER OPEN: an overscan plane whose
// content window is 320x240 at (40,40), borders opened with the flicker trick.
// Every number below is the original's, in canvas pixels, halved at emission.
//
// Three phases, frame-counted as the original's requestAnimFrame chain:
//   1..200    AtariDecrunch(0, 100, 0, 200): random bars in 12 colours under
//             the Automation packer logo and the busy bee
//   201..500  prego(): the credits page, until time>=300
//   501..     go(): music starts; picture, two vertical chrome strips, the
//             black bar, a 55x26 font scroller and 11 sprites on a Lissajous
//             orbit whose sprite set changes every 1000 frames
//
// The PNGs are smoothly resampled 2x art drawn at both parities, so the asset
// script box-halves each one for every parity it lands on; drawHalved() picks
// the variant from the canvas coordinate. ONE plane, one shared palette.
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const assert = std.debug.assert;

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const MUSIC = "rings_of_medusa.sndh";
const MUSIC_TUNE: u8 = 2; // the title track (subtune 1 is a different song)

const PLANE = 0;

// the 320x240 content window inside the 400x280 overscan buffer
const CONTENT_X: usize = 40;
const CONTENT_Y: usize = 40;
const CONTENT_W: usize = 320;
const CONTENT_H: usize = 240;

// palette (see the asset script)
const TRANSPARENT: u8 = 0;
const BLACK: u8 = 1;
const FONT_GREY: u8 = 2;
const DECRUNCH_BASE: u8 = 3;

// phases
const DECRUNCH_FRAMES: u32 = 200; // DecrunchMaxVBL
const TITLE_FRAMES: u32 = 300; // prego: time>=300
const MAIN_FIRST_FRAME: u32 = DECRUNCH_FRAMES + TITLE_FRAMES + 1;

// AtariDecrunch
const CANVAS_H: usize = 480;
const DECRUNCH_BAR_MAX: f64 = 100; // MaxBarHeight
const DECRUNCH_COLOURS: f64 = 12; // round(random*12) can give 12: no such colour, fillStyle kept
const AUTOMATION_X: i32 = (320 - 364 / 2) / 2; // drawImage(automation, 320-w1/2, 7)
const AUTOMATION_Y: i32 = 7 / 2; // odd: the script halved it on a row-shifted grid
const BEE_X: i32 = 320 / 2;
const BEE_Y: i32 = 50 / 2;
const RNG_SEED: u64 = 0x9E3779B97F4A7C15;

// prego()'s font1.print(mycanvas, text, x, y, 1, 0, 2, 2): 8x8 tiles at zoom 2
const TitleLine = struct { x: i32, y: i32, text: []const u8 };
const TITLE = [_]TitleLine{
    .{ .x = 90, .y = 42, .text = "  THE REPLICANTS AND ST-AMIGOS" },
    .{ .x = 90, .y = 60, .text = "            PRESENT" },
    .{ .x = 90, .y = 78, .text = "        ANOTHER RELEASE:" },
    .{ .x = 90, .y = 106, .text = "    --- KICK OFF 2 100 % ---" },
    .{ .x = 90, .y = 134, .text = "     BROKEN BY R.AL & SNAKE" },
    .{ .x = 90, .y = 274, .text = "INTRO WRITTEN BY THE ST CONNEXION" },
    .{ .x = 90, .y = 302, .text = "CODING:  " },
    .{ .x = 236, .y = 302, .text = "MARLON" },
    .{ .x = 90, .y = 320, .text = "ARTWORK: KRAZY REX" },
    .{ .x = 92, .y = 338, .text = "MUSIC:   MAD MAX" },
};
const FONT8: usize = 8;
const FONT8_COLS: usize = 40;
const FONT8_FIRST: u8 = 32;

// go()
const MAIN_X: i32 = 110;
const MAIN_W: usize = 205; // main_new.png halved
const VSCROLL_LEFT_X: i32 = 10;
const VSCROLL_RIGHT_X: i32 = 535;
const VSCROLL_START: i32 = 450;
const VSCROLL_STEP: i32 = 8;
const VSCROLL_WRAP: i32 = -3400;
const VSCROLL_W: usize = 43; // per parity variant
const VSCROLL_H: usize = 1963;
const BAR_Y: usize = 430; // bar.png: solid black to the bottom, over the picture and both strips

// scrolltext_horizontal with lowerfont.initTile(55,26,32), init(..., 12), draw(435)
const GLYPH_W: i32 = 55;
const GLYPH_CELL_W: usize = 28;
const GLYPH_CELL_H: usize = 14;
const FONT_COLS: usize = 10;
const FONT_VARIANT_STEP: usize = FONT_COLS * GLYPH_CELL_W;
const FONT_FIRST: u8 = 32;
const SCROLL_SPEED: i32 = 12;
const SCROLL_Y: i32 = 435;
const SCROLL_WIDE: usize = 13; // scrolltext_horizontal's wide = ceil(640/55)+1
const SCROLL_LETTERS: usize = SCROLL_WIDE + 1; // letters 0..wide
const SCROLL_START_X: i32 = @as(i32, SCROLL_WIDE) * GLYPH_W; // letter i starts at wide*fontw + i*fontw

const SCROLL_TEXT = "     THE FUCKING BEST REPLICANTS STRIKE AGAIN WITH KICK OFF TWO, BROKEN BY R.AL AND SNAKE!  CERTIFIED ONE HUNDRED PERCENT " ++
    "WITHOUT ANY CHECKSUM LEFT,   THANKS TO THE STCNX FOR THIS GREAT INTRO... NOW OUR GREETINGS TO: AVR AND THOR, SCOTT AND " ++
    "TWISO TWENTY ONE, ZAE (SPREAD THIS CONNARD), MCA (HOWDY! DO YOU THINK THAT THE COULES DE VIEILLE WAS HOT ENOUGH FOR YOU), " ++
    "DELIGHT (A MEGA, GIGA, THANKS TO AXE FOR THE BIG DELIRIOUS AT THE PARTY), STCNX, DELTAFORCE (ALSO MEGA THANX FOR THIS REALLY " ++
    "GREAT PARTY), TEX (GREAT MIDI MAZE PLAYING), AUTOMATION (VAPOUR A REAL FRIEND IN THE BUSINESS), HOTLINE, CHRIS OF TGE (JE NE PARLE " ++
    "PAS FRANCAIS), TCB (FUCKING GREAT DEMO FOR THE COMPETITION NICK...), SAMPLE MASTER OF TNT CREW (THE BIGGEST BEER DRINKER), " ++
    "TDA, FOF (GREAT COMPACTS, BUT SEND US SOMETIMES), LOST BOYS, OMEGA, SYNC, SEWER SOFTWARE, ULM, FIRE CRACKERS, TRB " ++
    "(GREAT DEMO), STEPH, DEREK AD, BBB, LCM FROM YUGOSLAVIA, JOHN FROM GREECE, THE BROD, ACU AND YOU! BYE BYE AND SEE YOU SOON!           ";

// the 11 sprites: x = 299 + 264*sin(p), y = 186 + 84*cos(p*1.5), p += 0.06
const SPRITES: usize = 11;
const ORBIT_CX: f64 = 299;
const ORBIT_RX: f64 = 264;
const ORBIT_CY: f64 = 186;
const ORBIT_RY: f64 = 84;
const ORBIT_Y_FREQ: f64 = 1.5;
const ORBIT_STEP: f64 = 0.06;
const SPACING_SETS: f64 = 0.1; // spritesPos[k] = 0.1*(k+1): skulls, balls
const SPACING_LETTERS: f64 = 0.2; // spritesPos1[k] = 0.2*(k+1): the letters
const CLOCK_LETTERS_LAST: u32 = 1000;
const CLOCK_SKULLS_LAST: u32 = 2000;
const CLOCK_CYCLE: u32 = 3000;

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const DIR = "../assets/screens/replicants_kickoff2/";
const palette = zg.convertU8ArraytoColors(@embedFile(DIR ++ "palette.dat"));
const main_img = blit.Image.init(@embedFile(DIR ++ "main.raw"), MAIN_W);
const vscroll_img = blit.Image.init(@embedFile(DIR ++ "vscroll.raw"), 2 * VSCROLL_W);
const font_img = blit.Image.init(@embedFile(DIR ++ "lowerfont.raw"), 2 * FONT_VARIANT_STEP);
const font8_img = blit.Image.init(@embedFile(DIR ++ "font8.raw"), FONT8_COLS * FONT8);
const automation_img = blit.Image.init(@embedFile(DIR ++ "automation.raw"), 182);
const bee_img = blit.Image.init(@embedFile(DIR ++ "bee.raw"), 16);

/// A sprite halved for all four parities: variant (ox, oy) at (ox*vw, oy*vh).
const Sprite = struct { img: blit.Image, vw: usize, vh: usize };

fn sprite(comptime name: []const u8, comptime w: usize, comptime h: usize) Sprite {
    const vw = (w + 2) / 2;
    const vh = (h + 2) / 2;
    const data = @embedFile(DIR ++ "spr_" ++ name ++ ".raw");
    comptime assert(data.len == 4 * vw * vh);
    return .{ .img = blit.Image.init(data, 2 * vw), .vw = vw, .vh = vh };
}

const BALL1 = sprite("ball1", 32, 32);
const BALL2 = sprite("ball2", 32, 32);
const SKULL = sprite("skull", 53, 58);
// sprite[0..10]: s t n a c i l p e r the
const LETTERS = [SPRITES]Sprite{
    sprite("s", 40, 40), sprite("t", 40, 40), sprite("n", 40, 40), sprite("a", 40, 40),
    sprite("c", 40, 40), sprite("i", 40, 40), sprite("l", 40, 40), sprite("p", 40, 40),
    sprite("e", 40, 40), sprite("r", 40, 40), sprite("the", 40, 40),
};
// sprite2: ball2 on even slots, ball1 on odd ones, the snake last
const BALLS = [SPRITES]Sprite{ BALL2, BALL1, BALL2, BALL1, BALL2, BALL1, BALL2, BALL1, BALL2, BALL1, sprite("snake", 51, 40) };

comptime {
    @setEvalBranchQuota(10_000);
    assert(main_img.w * main_img.h == MAIN_W * 215 and main_img.h == BAR_Y / 2);
    assert(vscroll_img.h == VSCROLL_H);
    assert(font_img.h == 6 * GLYPH_CELL_H);
    assert(font8_img.h == 3 * FONT8 and automation_img.h == 8 and bee_img.h == 16);
    // the scroller and the strips are only halved for the parity they are drawn at
    assert(@mod(SCROLL_Y, 2) == 1 and @mod(VSCROLL_START, 2) == 0 and @mod(VSCROLL_STEP, 2) == 0);
    for (SCROLL_TEXT) |c| assert(c >= FONT_FIRST and c - FONT_FIRST < FONT_COLS * 6);
    for (TITLE) |line| {
        for (line.text) |c| assert(c >= FONT8_FIRST and c - FONT8_FIRST < FONT8_COLS * 3);
    }
}

const SpriteSet = enum { letters, skulls, balls };
const Phase = enum { decrunch, title, main };

/// JS Math.round for the non-negative values it sees here.
fn jsRound(x: f64) f64 {
    return @floor(x + 0.5);
}

/// Blit an image the asset script halved per canvas parity. (cx, cy) is the
/// canvas position; `cell` is the variant for even x and y, and the odd
/// variants sit `step_x` right / `step_y` down (0 where only one parity exists).
fn drawHalved(dst: blit.Dst, img: blit.Image, cell: blit.Rect, step_x: usize, step_y: usize, cx: i32, cy: i32) void {
    var part = cell;
    part.x += @as(usize, @intCast(@mod(cx, 2))) * step_x;
    part.y += @as(usize, @intCast(@mod(cy, 2))) * step_y;
    blit.blit(dst, img, part, @divFloor(cx, 2), @divFloor(cy, 2), TRANSPARENT, .copy);
}

fn fillRows(dst: blit.Dst, first: usize, end: usize, index: u8) void {
    for (first..end) |k| @memset(dst.buf[k * dst.stride ..][0..dst.w], index);
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    frame: u32, // requestAnimFrame calls so far, 1-based once running
    rng: u64,
    bar_fill: u8, // the decrunch canvas's fillStyle, which persists across frames
    bar_rows: [CONTENT_H]u8,
    title_drawn: bool,
    vscroll_pos: i32,
    vscroll_drawn: i32,
    scroll_head: usize, // text index of the leftmost letter
    scroll_x: i32, // its canvas x
    orbit_sets: [SPRITES]f64, // spritesPos
    orbit_letters: [SPRITES]f64, // spritesPos1
    sprite_clock: u32, // time1
    sprite_set: SpriteSet,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here, never by default.
        self.frame = 0;
        self.rng = RNG_SEED;
        self.bar_fill = BLACK;
        @memset(&self.bar_rows, BLACK);
        self.title_drawn = false;
        self.vscroll_pos = VSCROLL_START;
        self.vscroll_drawn = VSCROLL_START;
        self.scroll_head = 0;
        self.scroll_x = SCROLL_START_X;
        for (0..SPRITES) |k| {
            const n: f64 = @floatFromInt(k + 1);
            self.orbit_sets[k] = SPACING_SETS * n;
            self.orbit_letters[k] = SPACING_LETTERS * n;
        }
        self.sprite_clock = 0;
        self.sprite_set = .letters;

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(palette);
        fb.setPaletteEntry(TRANSPARENT, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.openBorders(.top_bottom); // content reaches physical row 279: the bottom border
        const whole = blit.Dst.plane(fb);
        fillRows(whole, 0, whole.h, BLACK);
    }

    fn phase(self: *const Demo) Phase {
        if (self.frame <= DECRUNCH_FRAMES) return .decrunch;
        if (self.frame < MAIN_FIRST_FRAME) return .title;
        return .main;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        // saturating: a wrap would be UB in ReleaseSmall and would restart the
        // decrunch and re-request the song; pinned at the top it stays in go()
        self.frame +|= 1;
        switch (self.phase()) {
            .decrunch => self.decrunchBars(),
            .title => {},
            .main => self.advanceMain(),
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const screen = blit.Dst.plane(fb).window(CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H);
        switch (self.phase()) {
            .decrunch => self.drawDecrunch(screen),
            .title => if (!self.title_drawn) {
                drawTitle(screen); // prego() redraws the same page every frame
                self.title_drawn = true;
            },
            .main => self.drawMain(screen),
        }
    }

    /// Math.random stand-in: xorshift64*, 53 bits into [0, 1).
    fn random(self: *Demo) f64 {
        self.rng ^= self.rng >> 12;
        self.rng ^= self.rng << 25;
        self.rng ^= self.rng >> 27;
        const bits = (self.rng *% 0x2545F4914F6CDD1D) >> 11;
        return @as(f64, @floatFromInt(bits)) * 0x1.0p-53;
    }

    /// doDecrunch's bar loop over the 480 canvas rows; ST row k shows canvas row 2k.
    fn decrunchBars(self: *Demo) void {
        var canvas_rows: [CANVAS_H]u8 = undefined;
        const tallest = 10 + jsRound(self.random() * DECRUNCH_BAR_MAX);
        var y: usize = 0;
        while (y <= CANVAS_H) {
            const barh: usize = @intFromFloat(jsRound(self.random() * tallest));
            const col = jsRound(self.random() * DECRUNCH_COLOURS);
            if (col < DECRUNCH_COLOURS) self.bar_fill = DECRUNCH_BASE + @as(u8, @intFromFloat(col));
            const end = @min(y + barh, CANVAS_H);
            if (end > y) @memset(canvas_rows[y..end], self.bar_fill);
            y += barh;
        }
        for (&self.bar_rows, 0..) |*row, k| row.* = canvas_rows[2 * k];
    }

    fn drawDecrunch(self: *const Demo, screen: blit.Dst) void {
        for (self.bar_rows, 0..) |index, k| fillRows(screen, k, k + 1, index);
        blit.blit(screen, automation_img, null, AUTOMATION_X, AUTOMATION_Y, 0, .{ .flat = BLACK });
        blit.blit(screen, bee_img, null, BEE_X, BEE_Y, 0, .{ .flat = BLACK });
    }

    fn drawTitle(screen: blit.Dst) void {
        fillRows(screen, 0, CONTENT_H, BLACK);
        for (TITLE) |line| {
            for (line.text, 0..) |c, i| {
                const n: usize = c - FONT8_FIRST;
                const cell = blit.Rect{ .x = (n % FONT8_COLS) * FONT8, .y = (n / FONT8_COLS) * FONT8, .w = FONT8, .h = FONT8 };
                const x = @divFloor(line.x, 2) + @as(i32, @intCast(i * FONT8));
                blit.blit(screen, font8_img, cell, x, @divFloor(line.y, 2), 0, .{ .flat = FONT_GREY });
            }
        }
    }

    /// go()'s state, in its order, keeping what it DRAWS where that differs.
    fn advanceMain(self: *Demo) void {
        if (self.frame == MAIN_FIRST_FRAME) zg.requestSongTune(MUSIC, MUSIC_TUNE);

        self.vscroll_drawn = self.vscroll_pos;
        self.vscroll_pos -= VSCROLL_STEP;
        if (self.vscroll_pos <= VSCROLL_WRAP) self.vscroll_pos = VSCROLL_START;

        // every letter moves 12; the one reaching -55 rejoins the back of the
        // ring carrying the next character
        self.scroll_x -= SCROLL_SPEED;
        if (self.scroll_x <= -GLYPH_W) {
            self.scroll_x += GLYPH_W;
            self.scroll_head = (self.scroll_head + 1) % SCROLL_TEXT.len;
        }

        for (&self.orbit_sets, &self.orbit_letters) |*a, *b| {
            a.* += ORBIT_STEP;
            b.* += ORBIT_STEP;
        }
        self.sprite_set = if (self.sprite_clock <= CLOCK_LETTERS_LAST)
            .letters
        else if (self.sprite_clock <= CLOCK_SKULLS_LAST)
            .skulls
        else
            .balls;
        self.sprite_clock += 1;
        if (self.sprite_clock >= CLOCK_CYCLE) self.sprite_clock = 0;
    }

    fn drawMain(self: *const Demo, screen: blit.Dst) void {
        fillRows(screen, 0, CONTENT_H, BLACK);
        blit.blit(screen, main_img, null, @divFloor(MAIN_X, 2), 0, TRANSPARENT, .copy);

        const above_bar = screen.window(0, 0, CONTENT_W, BAR_Y / 2);
        const strip = blit.Rect{ .x = 0, .y = 0, .w = VSCROLL_W, .h = VSCROLL_H };
        drawHalved(above_bar, vscroll_img, strip, VSCROLL_W, 0, VSCROLL_LEFT_X, self.vscroll_drawn);
        drawHalved(above_bar, vscroll_img, strip, VSCROLL_W, 0, VSCROLL_RIGHT_X, self.vscroll_drawn);

        self.drawScroller(screen);
        self.drawSprites(screen);
    }

    /// Letters are drawn left to right, as scrolltext_horizontal sorts them.
    fn drawScroller(self: *const Demo, screen: blit.Dst) void {
        for (0..SCROLL_LETTERS) |i| {
            const x = self.scroll_x + GLYPH_W * @as(i32, @intCast(i));
            const n: usize = SCROLL_TEXT[(self.scroll_head + i) % SCROLL_TEXT.len] - FONT_FIRST;
            const cell = blit.Rect{ .x = (n % FONT_COLS) * GLYPH_CELL_W, .y = (n / FONT_COLS) * GLYPH_CELL_H, .w = GLYPH_CELL_W, .h = GLYPH_CELL_H };
            drawHalved(screen, font_img, cell, FONT_VARIANT_STEP, 0, x, SCROLL_Y);
        }
    }

    /// drawImage lands at fractional canvas positions; they are rounded to the
    /// nearest canvas pixel, whose parity picks the halved variant.
    fn drawSprites(self: *const Demo, screen: blit.Dst) void {
        for (0..SPRITES) |k| {
            const spr, const p = switch (self.sprite_set) {
                .letters => .{ LETTERS[k], self.orbit_letters[k] },
                .skulls => .{ SKULL, self.orbit_sets[k] },
                .balls => .{ BALLS[k], self.orbit_sets[k] },
            };
            const cx: i32 = @intFromFloat(jsRound(ORBIT_CX + ORBIT_RX * @sin(p)));
            const cy: i32 = @intFromFloat(jsRound(ORBIT_CY + ORBIT_RY * @cos(p * ORBIT_Y_FREQ)));
            drawHalved(screen, spr.img, .{ .x = 0, .y = 0, .w = spr.vw, .h = spr.vh }, spr.vw, spr.vh, cx, cy);
        }
    }
};
