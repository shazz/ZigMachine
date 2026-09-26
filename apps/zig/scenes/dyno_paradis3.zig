// --------------------------------------------------------------------------
// Dyno — "ParaDis3 - Parallax Distorter" (Atari STF, STNICCC 2015, 2nd in the
// 128 Kb compo; demozoo 151594). A homage to ULM's Parallax Distorter
// (scenes/ulm_spoon_distorter.zig).
//
// Ported from the CODEF HTML5 remake by Dyno (wab.com screen 470, 2016, CODEF MIT).
// Code and sample: Dyno. Font: Oxar. Background: Agent-T of Cream. Intro music:
// DMA-SC of Sector One. Main-part music in the remake: boris.xm.
//
// Reference kept at prototypes/codef/470/. Assets, music and the verbatim tables
// in dyno_paradis3/tables.zig: tools/private_tools/dyno_paradis3_assets.py.
//
// Three phases, as the remake chains them:
//   intro  (animIntro, one step per frame): a 464x36 canvas scrolls left 4 px a
//          frame, the current letter is redrawn at 416 + intro_x, and the canvas
//          is shown at y 170 on black. The intro tune plays.
//   splash (animSplash): 90 black frames, the tune stopped.
//   main   (animDemo): every one of the 276 rows is two copies from offscreens:
//          back:   back.png (8x64) tiled into 424x64, row (line + bounce_back) % 64,
//                  column (80 + floor(back_wave(back_pos + line) / 2)) % 8;
//          scroll: a 665x36 canvas holding the scrolltext from letter letter_num,
//                  row (line + bounce_front) % 36, column
//                  front_wave(front_pos + line) - letter_decal, keyed over the back.
//          The clock is useDeltaTime = 1: iteration = floor(ms * 60 / 1000) since
//          the main part started, back_pos = 5 * iteration, front_pos = 10 * iteration.
//
// The waves are running sums of createCurve's deltas (doPrecalcWave): the intro
// sequence once, then the main sequence repeated, each repeat offset by its own
// total (getSum). That growing offset is what moves the text forward.
//
// Geometry: the remake's screen is 416x276, wider than the 400x280 overscan plane.
// It is centred: columns 0..7 and 408..415 of the original are cropped (the
// background and the distorted text both cover them), and it sits at rows 2..277,
// the 2+2 spare rows transparent over black. Every border is opened (openBorders(.all)).
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const t = @import("dyno_paradis3/tables.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;

const MUSIC_INTRO = "dyno_paradis3_dmasc.sndh"; // player_sc68.js: song = ['dmasc.snd']
const MUSIC_SPLASH = "dyno_paradis3_silence.raw"; // stop_sndh()
const MUSIC_MAIN = "dyno_paradis3_boris.raw"; // boris.xm, rendered to PCM
const PLANE = 0;

// screen_width, screen_height, back_height, font_height; back.png is 8 wide
const SCREEN_W: usize = 416;
const SCREEN_H: usize = 276;
const BACK_W: usize = 8;
const BACK_H: usize = 64;
const FONT_H: usize = 36;
const FONT_W: usize = 480;
const BACK_CANVAS_W: usize = SCREEN_W + BACK_W; // canvas(screen_width + 8, back_height)
const INTRO_W: usize = SCREEN_W + 48; // canvas(screen_width + 48, font_height)
const SCROLL_W: usize = 665; // canvas(screen_width * 1.6): the element truncates 665.6
const INTRO_Y: i32 = 170;
const INTRO_SPEED: i32 = 4;
const SPLASH_FRAMES: u32 = 90;
const BACK_X_BIAS: i64 = 80;
const BACK_STEP: u64 = 5; // "6 for 50 FPS"
const FRONT_STEP: u64 = 10; // "12 for 50 FPS"

const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const CROP_X: usize = (SCREEN_W - PW) / 2; // 8 columns cut on each side
const Y0: usize = (PH - SCREEN_H) / 2; // 2
const BLACK: u8 = 1; // screen_pal.dat: opaque black, main_canvas.fill('#000000')

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const back_b = @embedFile("../assets/screens/dyno_paradis3/back.raw");
const font_b = @embedFile("../assets/screens/dyno_paradis3/font.raw");
const screen_pal = zg.convertU8ArraytoColors(@embedFile("../assets/screens/dyno_paradis3/screen_pal.dat"));

const font_img = blit.Image.init(font_b, FONT_W);

comptime {
    if (back_b.len != BACK_W * BACK_H) @compileError("back.raw is not 8x64");
    if (font_b.len != FONT_W * 216) @compileError("font.raw is not 480x216");
    for (t.letter) |g| {
        if (@as(usize, g.x) + g.w > FONT_W or @as(usize, g.y) + FONT_H > 216)
            @compileError("glyph outside font.raw");
        // buildScrollCanvas and the letter search both advance by glyph width
        if (g.w == 0) @compileError("zero-width glyph: the letter loops would never end");
    }
    // the front table's repeats must move forward, or the letter search runs off
    if (t.front_main_wave[t.front_main_wave.len - 1] <= 0) @compileError("front wave does not advance");
}

/// character -> index into t.letter (getLetter)
const glyph_of: [256]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var m = [_]u8{0xFF} ** 256;
    for (t.letter, 0..) |g, j| m[g.c] = j;
    for (t.text ++ t.intro_text) |c| if (m[c] == 0xFF) @compileError("text character without a glyph");
    break :blk m;
};

/// doPrecalcPosition: position[i] = x just past letter i of the text
const position: [t.text.len]i32 = blk: {
    @setEvalBranchQuota(100_000);
    var out: [t.text.len]i32 = undefined;
    var count: i32 = 0;
    for (t.text, 0..) |c, i| {
        count += t.letter[glyph_of[c]].w;
        out[i] = count;
    }
    break :blk out;
};

/// getSum: the table repeats, each repeat offset by its last value.
fn getSum(comptime T: type, array: []const T, index: u64, decal: i64) i64 {
    const n: u64 = array.len;
    const repeats: i64 = @intCast(index / n);
    const last: i64 = array[array.len - 1];
    return decal + repeats * last + @as(i64, array[@intCast(index % n)]);
}

/// getWave: the intro once, then the main table from the intro's last value.
fn getWave(intro: []const i16, main: []const i16, i: u64) i64 {
    if (i < intro.len) return getSum(i16, intro, i, 0);
    return getSum(i16, main, i - intro.len, intro[intro.len - 1]);
}

/// getPosition: x where letter i starts
fn getPosition(i: i64) i64 {
    if (i <= 0) return 0;
    return getSum(i32, &position, @intCast(i - 1), 0);
}

// --------------------------------------------------------------------------
// Offscreens: taken from the machine's RAM arena (zg.mem) at init. As module-
// scope arrays they were 68 KB of zeros the link wrote into the cart binary
// (imported memory is not known to be zero) and into the 2 MiB window; from the
// arena they cost nothing until the cart runs, and come back zeroed.
// --------------------------------------------------------------------------
var back_canvas: []u8 = &.{};
var intro_canvas: []u8 = &.{};
var scroll_canvas: []u8 = &.{};
var front_row: []i64 = &.{};

// Once per cart load: a new cart gets a fresh instance (empty slices) AND an
// empty arena, so a re-init of the same instance keeps its buffers.
fn allocOffscreens() void {
    if (back_canvas.len != 0) return;
    back_canvas = zg.mem.mustAlloc(u8, BACK_CANVAS_W * BACK_H);
    intro_canvas = zg.mem.mustAlloc(u8, INTRO_W * FONT_H);
    scroll_canvas = zg.mem.mustAlloc(u8, SCROLL_W * FONT_H);
    front_row = zg.mem.mustAlloc(i64, SCREEN_H);
}

const Phase = enum { intro, splash, main };

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    phase: Phase,
    // intro
    intro_x: i32,
    intro_next: usize, // index of the next intro letter to start
    intro_tile: ?usize, // glyph being drawn, null before the first
    // splash
    splash_frame: u32,
    // main
    elapsed_ms: f64,
    iteration: i64,
    back_pos: u64,
    front_pos: u64,
    letter_num: i64,
    letter_decal: i64,
    scroll_built_for: i64, // letter_num the scroll canvas currently holds

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here.
        self.phase = .intro;
        self.intro_x = -1;
        self.intro_next = 0;
        self.intro_tile = null;
        self.splash_frame = 0;
        self.elapsed_ms = 0;
        self.iteration = 0;
        self.back_pos = 0;
        self.front_pos = 0;
        self.letter_num = 0;
        self.letter_decal = 0;
        self.scroll_built_for = -1;

        allocOffscreens();
        for (0..BACK_H) |y| for (0..BACK_CANVAS_W) |x| {
            back_canvas[y * BACK_CANVAS_W + x] = back_b[y * BACK_W + x % BACK_W];
        };
        @memset(intro_canvas, 0);
        @memset(scroll_canvas, 0);
        @memset(front_row, 0);

        zg.requestSong(MUSIC_INTRO);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all);
        fb.setPalette(screen_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        switch (self.phase) {
            .intro => if (!self.introStep()) {
                // animIntro -> initSplash(); animSplash() in the same frame
                self.phase = .splash;
                self.splash_frame = 0;
                zg.requestSong(MUSIC_SPLASH);
                self.splashStep();
            },
            .splash => self.splashStep(),
            .main => {
                // animDemo sets the clock AFTER drawing, from the time taken at
                // the end of the previous frame: frame k draws with (k-1) frames
                // of elapsed time. A NaN, infinite or negative dt is ignored: it
                // would poison the clock for good, and @intFromFloat of an
                // infinite clock is silent garbage in ReleaseSmall.
                self.setClock(@floor(self.elapsed_ms * 60.0 / 1000.0));
                if (std.math.isFinite(dt) and dt > 0) self.elapsed_ms += dt;
                self.findFirstLetter();
            },
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const view = blit.Dst.plane(fb).window(0, Y0, PW, SCREEN_H);
        const view_len = (SCREEN_H - 1) * view.stride + PW;
        switch (self.phase) {
            .intro => {
                @memset(view.buf[0..view_len], BLACK);
                const intro_img = blit.Image.init(intro_canvas, INTRO_W);
                blit.blit(view, intro_img, null, -@as(i32, CROP_X), INTRO_Y, 0, .copy);
            },
            .splash => @memset(view.buf[0..view_len], BLACK),
            .main => self.renderMain(view),
        }
    }

    /// animIntro's state step: next letter, scroll the canvas, redraw the letter.
    /// Returns false once the intro text is exhausted.
    fn introStep(self: *Demo) bool {
        if (self.intro_x < 0) {
            if (self.intro_tile) |g| self.intro_x += t.letter[g].w;
            if (self.intro_next >= t.intro_text.len) return false;
            self.intro_tile = glyph_of[t.intro_text[self.intro_next]];
            self.intro_next += 1;
        }
        self.intro_x -= INTRO_SPEED;

        const speed: usize = @intCast(INTRO_SPEED);
        for (0..FONT_H) |y| {
            const row = intro_canvas[y * INTRO_W ..][0..INTRO_W];
            std.mem.copyForwards(u8, row[0 .. INTRO_W - speed], row[speed..]);
            @memset(row[INTRO_W - speed ..], 0);
        }
        const g = t.letter[self.intro_tile.?];
        const canvas = blit.Dst.buffer(intro_canvas, INTRO_W);
        const part = blit.Rect{ .x = g.x, .y = g.y, .w = g.w, .h = FONT_H };
        blit.blit(canvas, font_img, part, @as(i32, SCREEN_W) + self.intro_x, 0, 0, .copy);
        return true;
    }

    /// animSplash: 90 black frames, then initDemo(); animDemo() in the same frame.
    fn splashStep(self: *Demo) void {
        if (self.splash_frame < SPLASH_FRAMES) {
            self.splash_frame += 1;
            return;
        }
        self.phase = .main;
        self.elapsed_ms = 0;
        self.setClock(0);
        zg.requestSong(MUSIC_MAIN);
        self.findFirstLetter();
    }

    fn setClock(self: *Demo, iteration: f64) void {
        self.iteration = @intFromFloat(iteration);
        const it: u64 = @intCast(self.iteration);
        self.back_pos = it * BACK_STEP;
        self.front_pos = it * FRONT_STEP;
    }

    /// animDemo's "Calc decal_x" and "Calc first letter".
    fn findFirstLetter(self: *Demo) void {
        var decal_x: i64 = std.math.maxInt(i64);
        for (front_row, 0..) |*v, line| {
            v.* = getWave(&t.front_intro_wave, &t.front_main_wave, self.front_pos + line);
            if (v.* < decal_x) decal_x = @max(v.*, 0);
        }

        var dir: i64 = 0;
        if (decal_x > self.letter_decal) dir = 1;
        if (decal_x < self.letter_decal) dir = -1;
        var i: i64 = 0;
        while (decal_x < getPosition(self.letter_num + i) or getPosition(self.letter_num + i + 1) <= decal_x) i += dir;
        self.letter_num += i;
        self.letter_decal = getPosition(self.letter_num);
    }

    fn renderMain(self: *Demo, view: blit.Dst) void {
        if (self.scroll_built_for != self.letter_num) buildScrollCanvas(self.letter_num);
        self.scroll_built_for = self.letter_num;

        const bounce: usize = @intCast(@mod(self.iteration, t.bounce_back.len));
        const bounce_back: usize = t.bounce_back[bounce];
        const bounce_front: usize = t.bounce_front[bounce];
        const scroll_img = blit.Image.init(scroll_canvas, SCROLL_W);

        for (0..SCREEN_H) |line| {
            const back_wave = getWave(&t.back_intro_wave, &t.back_main_wave, self.back_pos + line);
            // The back main table ends at -23, so the wave drifts down on every
            // repeat and after ~2 repeats (~2.5 min) the remake's JS % goes
            // negative. drawPart then draws the row from x = -back_x: original
            // column x still shows tile column (x + back_x) mod 8, with up to 7
            // stale/transparent columns at x 0..6. Those lie inside the 8-column
            // crop, so for every VISIBLE column the mathematical @mod is exact.
            const back_x: usize = @intCast(@mod(BACK_X_BIAS + @divFloor(back_wave, 2), BACK_W));
            const back_y = (line + bounce_back) % BACK_H;
            @memcpy(view.buf[line * view.stride ..][0..PW],back_canvas[back_y * BACK_CANVAS_W + back_x + CROP_X ..][0..PW]);

            // Original column x shows scroll column x + scroll_x, clipped to the
            // canvas on both sides; that covers drawPart's negative-partx branch
            // (a front value below 0 while decal_x is clamped to 0). The plane
            // shows original columns 8..407.
            const scroll_x = front_row[line] - self.letter_decal;
            const row = blit.Rect{ .x = 0, .y = (line + bounce_front) % FONT_H, .w = SCROLL_W, .h = 1 };
            blit.blit(view, scroll_img, row, @intCast(-(scroll_x + CROP_X)), @intCast(line), 0, .copy);
        }
    }
};

/// displayText: letters from `first` until the 665-pixel canvas is full.
fn buildScrollCanvas(first: i64) void {
    @memset(scroll_canvas, 0);
    const canvas = blit.Dst.buffer(scroll_canvas, SCROLL_W);
    var x: usize = 0;
    var i: usize = @intCast(first);
    while (x < SCROLL_W) : (i += 1) {
        const g = t.letter[glyph_of[t.text[i % t.text.len]]];
        blit.blit(canvas, font_img, .{ .x = g.x, .y = g.y, .w = g.w, .h = FONT_H }, @intCast(x), 0, 0, .copy);
        x += g.w;
    }
}
