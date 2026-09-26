// --------------------------------------------------------------------------
// THE CAREBEARS -- THE SPREADPOINT DEMO, from The Cuddly Demos (Atari STF,
// April 1989; demozoo 124142). Code, graphics and music: The Carebears.
//   CODEF HTML5 remake (wab.com screen 469) by Dyno, 2016, CODEF MIT-licensed.
//
// Ported from prototypes/codef/469/screen.js. Two parts, as the remake chains
// them, one step per frame:
//
//   intro   four pictures of white text (intro1..4.png). Each is shown for 180
//           frames of a colour fade -- black to white in 20, white to FF2222 in
//           140, FF2222 to black in 20 -- and a one-frame black gap starts the
//           next. That is ONE colour register rewritten per frame.
//   main    iteration counts from 0 (the frame after the fourth picture):
//             always       the TCB logo turning about a horizontal axis (logo.zig)
//             from 804     20 balls on a 5:8 Lissajous
//             from 1284    the "spread" scroller: 33 rows of the 8x6 font, each
//                          arriving at its own speed (12 down to 4 and back)
//             from 1952    the DNA scroller (dna.zig)
//           drawn in that order (scroll, balls, logo, DNA) over black.
//
// GEOMETRY. The remake's frame is 416x276 with the 320x200 screen at (52, 29):
// every layer lies inside it (scroller 0..319 x 0..197, balls 0..318 x 0..115,
// logo canvas 96..223 x 0..127, DNA 0..319 x 121..170), so this is a plain
// 320x200 plane, borders closed. The one exception is the intro text: its ink
// spans x 48..367 of the 416-wide frame, i.e. 4 px left of the screen the rest
// uses. A 320-wide text on a 320-wide ST screen, so it is shown at x 0..319
// (y 31..138): a 4 px shift from the remake's framing, assumed to be the remake's.
//
// RASTERS. The remake paints its three colour gradients as pixels; here they
// are colour-register writes from the plane's HBL (raster.zig), the ST way.
//
// MUSIC. The remake plays intro1..4.mp3 over the pictures and master.mp3 from
// the main part on. master.mp3 is AN Cool's digi tune, "Cuddly Demos -
// Spreadpoint" (sndh_lf/AN_Cool/Cuddly_Demos_Spreadpoint.sndh, 1 subtune, FLAG
// ~ay: timer A at 7680 Hz through the YM volume DAC, which the machine plays --
// apps/sndh_headless.mjs: peak 0.376). Matched by spectrogram against
// master.mp3: the same bar structure and the same silent gaps (~0.6 s, 2.2 s,
// 3.8 s, 5.4 s) within 0.1 s. It is requested when the main part starts, as the
// remake starts master.mp3. The four intro jingles are NOT in it (its one
// subtune -- subtune 2 renders identically -- is the song alone), no other SNDH
// carries them, and they are not cut from master.mp3 (sample correlation
// 0.12-0.14), so the intro is silent rather than an mp3.
//
// NOT PORTED: nothing on screen. The remake's AudioContext unlock (initHack)
// and fullscreen handlers are browser plumbing.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const pal = @import("tcb_spreadpoint/palette.zig");
const raster = @import("tcb_spreadpoint/raster.zig");
const logo = @import("tcb_spreadpoint/logo.zig");
const dna = @import("tcb_spreadpoint/dna.zig");
const texts = @import("tcb_spreadpoint/texts.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;

const MUSIC = "tcb_spreadpoint.sndh";
const PLANE = 0;
const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;

// Assets (tools/private_tools/tcb_spreadpoint_assets.py)
const palette = zg.convertU8ArraytoColors(@embedFile("../assets/screens/tcb_spreadpoint/palette.dat"));
const intro_b = @embedFile("../assets/screens/tcb_spreadpoint/intro.1bpp");
const font_b = @embedFile("../assets/screens/tcb_spreadpoint/font.raw");
const ball_b = @embedFile("../assets/screens/tcb_spreadpoint/ball.raw");

// --- the intro ------------------------------------------------------------
const PICTURES = 4;
const INTRO_W = 320;
const INTRO_H = 108;
const INTRO_Y = 31; // ink rows 60..167 of the frame, 29 above the screen
const INTRO_ROW_BYTES = INTRO_W / 8;
const INTRO_FRAMES = 180; // iteration 0..179 fades; 180 is the black gap

// --- the main part --------------------------------------------------------
const BALLS_FROM = 804; // if (iteration >= 804) draw_balls(804)
const SCROLL_FROM = 1284;
const DNA_FROM = 1952;
const BALL_W = 17;
const BALL_COUNT = 20;
const LOGO_X = 96; // logo_canvas.draw(main_canvas, 148, 29): 148 - 52

// draw_scroll: each 6-row line of the spread canvas moves at its own speed.
const SPEED = [_]u32{ 12, 11, 10, 9, 8, 7, 6, 5, 4, 5, 6, 7, 8, 9, 10, 11, 12, 11, 10, 9, 8, 7, 6, 5, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
const FONT_W = 8; // font.initTile(8, 6, 32)
const FONT_H = 6;
const FONT_COLS = 10; // font.png is 80 wide
const FIRST_CHAR = 32;

const font = blit.Image.init(font_b, FONT_COLS * FONT_W);
const ball = blit.Image.init(ball_b, BALL_W);

comptime {
    if (intro_b.len != PICTURES * INTRO_H * INTRO_ROW_BYTES) @compileError("intro.1bpp is not four 320x108 pictures");
    if (font_b.len != 80 * 36) @compileError("font.raw is not 80x36");
    if (ball_b.len != BALL_W * 16) @compileError("ball.raw is not 17x16");
    if (SPEED.len * FONT_H > H) @compileError("the spread scroller is taller than the screen");
    // Dst.window() clips silently, and logo.draw writes whole CANVAS-wide rows.
    if (LOGO_X + logo.CANVAS > W or logo.CANVAS > H) @compileError("the logo canvas leaves the screen");
    if (dna.W > W or raster.DNA_TOP + 2 * dna.STRIP_H > H) @compileError("the DNA canvas leaves the screen");
    @setEvalBranchQuota(10_000);
    for (texts.scroll) |c| if (c < FIRST_CHAR or c - FIRST_CHAR >= FONT_COLS * 6) @compileError("scroll text character outside the font");
}

const View = enum { picture, black, main };

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    view: View,
    picture: usize, // intro_pos
    intro_it: u32, // the intro's own iteration
    intro_colour: Color,
    iteration: u64, // the main part's, as drawn this frame
    next_iteration: u64,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.view = .picture;
        self.picture = 0;
        self.intro_it = 0;
        self.intro_colour = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
        self.iteration = 0;
        self.next_iteration = 0;

        logo.init();
        dna.init();

        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setFrameBufferHBLHandler(0, raster.hbl);
        @memset(fb.fb[0 .. W * H], 0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        switch (self.view) {
            .picture => self.introStep(),
            .black, .main => {
                self.view = .main;
                self.iteration = self.next_iteration;
                self.next_iteration += 1;
            },
        }
        zigos.lfbs[PLANE].setPaletteEntry(pal.INTRO_INK, self.intro_colour);
    }

    /// intro(): this frame's colour from the pre-increment iteration, then the
    /// step; at 180 the next picture starts black, and after the fourth the
    /// screen goes black for a frame and anim() takes over.
    fn introStep(self: *Demo) void {
        const it = self.intro_it;
        self.intro_colour = introColour(it);
        if (it < INTRO_FRAMES) {
            self.intro_it += 1;
            return;
        }
        self.intro_it = 0;
        self.picture += 1;
        if (self.picture < PICTURES) return;
        self.view = .black;
        zg.requestSong(MUSIC); // audio[4].play(): master.mp3
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const screen = blit.Dst.plane(fb);
        @memset(fb.fb[0 .. W * H], 0);
        switch (self.view) {
            .picture => drawPicture(screen, self.picture),
            .black => {},
            .main => {
                const it = self.iteration;
                if (it >= SCROLL_FROM) drawScroll(screen, it - SCROLL_FROM);
                if (it >= BALLS_FROM) drawBalls(screen, it - BALLS_FROM);
                logo.draw(screen.window(LOGO_X, 0, logo.CANVAS, logo.CANVAS), it);
                if (it >= DNA_FROM) dna.draw(screen.window(0, raster.DNA_TOP, dna.W, 2 * dna.STRIP_H), it - DNA_FROM + 1);
            },
        }
    }
};

/// The fade, as intro() writes it: '#' + red + green + blue.
fn introColour(it: u32) Color {
    if (it < 20) {
        const c: u8 = @intCast(it * 255 / 19);
        return .{ .r = c, .g = c, .b = c, .a = 255 };
    }
    if (it < 160) {
        const c: u8 = @intCast(0x22 + (159 - it) * 221 / 139);
        return .{ .r = 0xFF, .g = c, .b = c, .a = 255 };
    }
    if (it < 180) {
        const c = it - 160;
        return .{ .r = @intCast((19 - c) * 255 / 19), .g = @intCast((19 - c) * 0x22 / 19), .b = @intCast((19 - c) * 0x22 / 19), .a = 255 };
    }
    return .{ .r = 0, .g = 0, .b = 0, .a = 255 };
}

/// One intro picture in INTRO_INK: runs of set bits become spans.
fn drawPicture(screen: blit.Dst, picture: usize) void {
    const bits = intro_b[picture * INTRO_H * INTRO_ROW_BYTES ..][0 .. INTRO_H * INTRO_ROW_BYTES];
    for (0..INTRO_H) |row| {
        const dst = screen.buf[(INTRO_Y + row) * screen.stride ..][0..INTRO_W];
        const src = bits[row * INTRO_ROW_BYTES ..][0..INTRO_ROW_BYTES];
        for (src, 0..) |byte, b| {
            if (byte == 0) continue;
            for (0..8) |k| {
                if (byte & (@as(u8, 0x80) >> @intCast(k)) != 0) dst[b * 8 + k] = pal.INTRO_INK;
            }
        }
    }
}

/// draw_scroll: line `line` shows text pixel speed*ite - 320 + X at column X --
/// arriving from the right until it has moved 320 px, then wrapping through the
/// text (the canvas repeats its first 320 px after the end to make the wrap).
fn drawScroll(screen: blit.Dst, ite: u64) void {
    for (SPEED, 0..) |speed, line| {
        const first: i64 = @as(i64, @intCast(speed * ite)) - @as(i64, W); // text pixel at column 0
        var k: i64 = @divFloor(@max(first, 0), FONT_W);
        while (true) : (k += 1) {
            const x = k * FONT_W - first;
            if (x >= W) break;
            const tile: usize = texts.scroll[@intCast(@mod(k, texts.scroll.len))] - FIRST_CHAR;
            const part = blit.Rect{ .x = (tile % FONT_COLS) * FONT_W, .y = (tile / FONT_COLS) * FONT_H, .w = FONT_W, .h = FONT_H };
            blit.blit(screen, font, part, @intCast(x), @intCast(line * FONT_H), 0, .copy);
        }
    }
}

/// draw_balls: x = 151 + round(151 sin(5 (ite/71 + j/47))),
///             y =  50 + round( 50 sin(8 (ite/71 + j/47)))
fn drawBalls(screen: blit.Dst, ite: u64) void {
    const t = @as(f64, @floatFromInt(ite)) / 71.0;
    for (0..BALL_COUNT) |j| {
        const phase = t + @as(f64, @floatFromInt(j)) / 47.0;
        const x = 151 + jsRound(151.0 * @sin(5.0 * phase));
        const y = 50 + jsRound(50.0 * @sin(8.0 * phase));
        blit.blit(screen, ball, null, x, y, 0, .copy);
    }
}

fn jsRound(v: f64) i32 {
    return @intFromFloat(@floor(v + 0.5)); // Math.round
}
