// --------------------------------------------------------------------------
// THE LOST BOYS — "THE TWIDDLE DEMO", from the ULM Megademo
// (a.k.a. Dark Side of the Spoon).
//   original: code OXYGENE and MANIKIN of TLB, graphics SPAZ,
//             music MAD MAX of TEX. Scrolltext theirs, 1990.
//   CODEF HTML5 remake (screen 122) by NoNameNo / Antoine Santo, MIT-licensed.
//
// Ported from prototypes/codef/122/screen.js.
//
// GEOMETRY: no halving. The remake draws everything into a 320x200 `orgcanvas`
// and only at the very end (screen.js:211) blits it into the 640x400 display
// canvas with a 2x zoom — that 2x is CODEF's display doubling, not the screen.
// All five PNGs are already ST-scale. So this is a native 320x200 screen with
// no borders open, on ONE plane, painted in the original's own order.
//
// TWO PHASES (screen.js:200-216, `go()`):
//   counter <  INTRO_FRAMES : intro()      — a sine-warped strip scroller
//   counter >= INTRO_FRAMES : starballs() + logo() + scroller()
//
// HOW THE MAIN PHASE COMPOSITES (screen.js:357-363). The remake fills orgcanvas
// opaque black, draws the starballs and the logo, then punches the scroller's
// letters OUT of it ('destination-out'), then paints TLBraster.png UNDERNEATH
// ('destination-over'). So the letters are not drawn: they are holes, and the
// rainbow shows through them. TLBraster.png is 25 solid bands of exactly 8 rows,
// so here a hole simply writes palette index RASTER_BASE + y/8 — the palette
// lookup the composite amounts to, with no second buffer and no blend.
//
// DELIBERATE DEPARTURES
//  1. The fake AtariDecrunch depack intro (screen.js:155, init2) is NOT ported:
//     ZigMachine has that look as a REAL depack effect (zx0.Fx.automation).
//  2. Hard edges. Chrome antialiases the rotated glyphs and the fractional
//     slice/ball/logo positions, so the remake has grey fringes; an indexed ST
//     screen does not, and neither did the original. Positions are rounded and
//     the rotated glyph is point-sampled.
//  3. The two rotations the remake applies to a letter (per-letter, then the
//     whole scroll plane) are COMPOSED into one affine, so the glyph is
//     resampled once instead of twice. Same geometry, no double blur.
//  4. NO HARDWARE SCROLL. Assessed and rejected — see the note above scroller().
//  5. Star positions come from a xorshift, because the original seeds them from
//     Math.random() (screen.js:187-190); nothing else here is random.
//
// Everything else is the original's own numbers: the 0.02/0.03/0.015/0.004
// increments, the 50-pixel bend amplitudes, the three 15-entry star-drift
// tables, the 0.0000003/0.0000005 ramps and the 300-frame table step.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const trig = @import("tlb_spoon/trig.zig");
const letter = @import("tlb_spoon/letter.zig");

const W = zg.WIDTH; // 320
const H = zg.HEIGHT; // 200

// --------------------------------------------------------------------------
// Assets (tools/private_tools/tlb_spoon_assets.py)
// --------------------------------------------------------------------------
// One shared palette, because there is one plane: index 0 is the OPAQUE black
// field (`orgcanvas.fill('#000000')`), 1..3 the ball's three blues, 4 the logo
// ink, 5 the intro font ink, 6..30 the raster's 25 bands top to bottom.
const pal = convertU8ArraytoColors(@embedFile("../assets/screens/tlb_spoon/pal.dat"));
const BALL_BASE: u8 = 1;
const LOGO_INK: u8 = 4;
// RASTER_BASE (6) is used by tlb_spoon/letter.zig, the only code that writes it.

const ball_b = @embedFile("../assets/screens/tlb_spoon/ball.raw");
const BALL_SIZE = 8;

const logo_runs = @import("tlb_spoon/logo_runs.zig");
const LOGO_W = logo_runs.LOGO_W;
const LOGO_H = logo_runs.LOGO_H;

// scrollimage.initTile(25,25,25): 25x25 tiles, tile index = charcode - 25.
// The glyphs are drawn by tlb_spoon/letter.zig, which embeds font.raw.
const GLYPH_TILES: u16 = 70; // 10x7
const GLYPH_FIRST: u8 = 25;

// introimage.initTile(32,16,32): 32x16 tiles, tile index = charcode - 32.
const introfont_b = @embedFile("../assets/screens/tlb_spoon/introfont.raw");
const INTRO_SHEET_W: usize = 320;
const INTRO_GW = 32;
const INTRO_GH = 16;
const INTRO_COLS: u16 = 10;
const INTRO_TILES: u16 = 120; // 10 cols x 12 usable rows of the 320x200 sheet
const INTRO_FIRST: u8 = 32;

// MUSIC. The original plays a YM register dump, 'Dark Side of the Spoon 1.ym'
// (screen.js:161) — deprecated here. Best SNDH by tools/private_tools/
// sndh_index.py: Mad_Max/Demos/DSOTS-The_Lost_Boys.sndh, "Dark Side Of The
// Spoon - TLB" by MAD MAX — exact title and composer match, FLAG ~y, 2 subtunes;
// subtune 1 is the "1" of the .ym filename. Verified on the sealed YM (peak
// 0.4695, all three voices). Spaz/Dark_Side_Spoon_TLB.sndh (~ay) and the SID
// variant (~abdy) are STE DMA and would play SILENCE: deliberately not used.
const MUSIC = "DSOTS-The_Lost_Boys.sndh";
const MUSIC_TUNE: u8 = 1;

// --------------------------------------------------------------------------
// The two texts (screen.js:65-67 and :151), verbatim
// --------------------------------------------------------------------------
const INTRO_TEXT = "          IN THE BEGINNING THERE WAS NOTHING BUT BLACKNESS AND A LAME DISTING SCROLLER, BUT THEN OUT OF THE DARKNESS CAME TLB";
const STRIP_W: i32 = @as(i32, INTRO_TEXT.len) * INTRO_GW;

// go() switches phase at counter == introtext.length*10 + 80 (screen.js:203).
const INTRO_FRAMES: u32 = @as(u32, INTRO_TEXT.len) * 10 + 80;

const SCROLL_TEXT = "             " ++
    "THE LOST BOYS IMMENSELY PROUDLY PRESENT THE TWIDDLE DEMO, WELL WHAT THE FUCK SHOULD WE CALL IT!!!  ORIGINALLY CODED FOR OUR MEGA DEMO BUT DUE TO POPULAR DEMAND RELEASED IN THE ULM MEGADEMO. FIRST I HAVE BEEN INSTRUCTED TO WISH FABIANS MOTHER A VERY HAPPY BIRTH DAY FOR TODAY THE TWENTY THIRD OF DECEMBER. HAPPY BIRTHDAY FRAU HAMMER!  OK NOW FOR THE REST OF THE BULLSHIT.  THIS SCREEN WAS CODED BY OXYGENE AND MANIKIN OF THE LOST BOYS WITH GRAPHIX AS USUAL BY SPAZ. TANIS DID A FONT FOR US BUT IT WAS TOO DETAILED FOR US TO ROTATE, CHEERS ANYWAY DUDE! WE WERE GOING TO KEEP THIS FOR OUR MEGA DEMO BUT ALAS WE HEARD THAT SOME OTHER PEOPLE WERE GOING TO CODE SOME STARBALLS SO WE DECIDED WE HAD BETTER RELEASE IT PRONTO.  NOW A WORD ABOUT OUR MATES THE INNER CIRCLE.  I SAID TO GRIFF THAT WE WOULD NOT BE SLAGGING HIM OFF ANY FURTHER AS IT WAS TOO JUVENILE, HE ALSO SAID THAT HE WOULD QUIT THIS RATHER STUPID BATTLE THAT THEY SEEM TO BE WAGING ON US. BUT THEY HAVE NOT STOPPED SO I MUST CLEAR MY HEAD A LITTLE. WE DID NOT, HAVE NOT, NOR EVER WILL STEAL, BORROW OR COPY ANY OF THEIR CODE. THE THREE D ROUTINES THAT I ALLEGEDLY STOLE FROM GRIFF ARE BASED UPON ROUTINES FROM ST WORLD A MAGAZINE PUBLISHED IN ENGLAND. GRIFF SEEMS TO HAVE A MAJOR CHIP ON HIS SHOULDER ABOUT THIS, MOST PEOPLE SEEM TO AGREE THAT HE IS BASICALLY AN OBNOXIOUS LITTLE TWAT. NOBODY DENIES THAT HE IS A TALENTED CODER BUT HE SHOULD IN OBTAIN A PERSONALITY OF HIS OWN FROM SOME PLACE OR OTHER. ANYWAY ENOUGH OF THIS, THAT IS THE END OF MY RANTING. WELL IT IS NOW JUST PAST MIDNIGHT ON THE MONDAY OF THE STNICCC AND IT HAS BEEN AN AMAZING EXPERIENCE FOR EVERYONE CONCERNED. SO I MUST GREET A FEW OF THE PEOPLE WHO HAVE BEEN HERE SO IN NO PARTICULAR ORDER HERE GOES:  THE CAREBEARS, A MEGA YO TO NICK, JAS, TANIS, AN COOL AND GOGO. DELTA FORCE, NEW MODE IS CURRENTLY STANDING APPROXIMATELY THREE FEET BEHIND ME SMOKING, ALSO HI TO CHAOS INC, QUESTLORD AND SLIME.. MEGA GREAT DEMO GUYS!!!, A GREETING TO ALL OF THE OVERLANDERS WHO I THINK MORE THAN PROVED THAT THEY DO NOT EARN THERE NAME OF THE OVERLAMERS. THE EUROPEAN DEMOS ARE REALLY GREAT ESPECIALLY THE THREE D SCREEN. THIS GREETING GOES PARTICULARLY TO MR.BEE AND ZIGGY. ALSO HI TO M CODER. AND NOW SUPER MEGA GIGA GREETS TO GUNSTICK AND FATE OF ULM AND ALSO TO THE RECTAL ERECTABLES ALSO KNOWN AS THE RESPECTA TESTICLES. TO KIMI, STEFAN AND DER GROSSE DUMME. MORE HELLOS TO CHRIS AND IAN OF THE WANKMEN. GREETS TO THE SPIRITS OF DOOM.  A HAPPY HI TO ALCOHOLICA THE MOST DISGUSTING REPULSIVE VOMITABLE GROUP EVER TO APPEAR ON THE ST SCENE. YO TO THE DYNAMIC DUO, NEXT, DICKY CARCRASHERS.  THANKS MUST GO TO MAD MAX OF TEX FOR A GREAT PIECE OF MUSIC WRITTEN ESPECIALLY FOR THIS DEMO WHILE BEING VICIOUSLY BEATEN BY FABIAN. ALSO HI TO ES AND THE REST OF THE GANG AND ESPECIALLY TO BITTNER! AND THAT, AS THEY SAY IN FILMS, IS A WRAP!!!!!!" ++
    "            ";

// --------------------------------------------------------------------------
// Starfield (screen.js:96-130)
// --------------------------------------------------------------------------
const FIELD_X: f32 = 320;
const FIELD_Y: f32 = 200;
const FIELD_Z: f32 = 200;
const STAR_NR: usize = 200;

// The drift state is Q40 fixed point in i64: the remake's f64 accumulators step
// 200 times a frame and a soft-float add costs ~100 cycles. Q40 keeps the
// 0.0000003 ramp to 1.5e-6 of itself. Float below is comptime-only.
const Q40: f64 = 1099511627776.0;
fn q40(v: f64) i64 {
    return @intFromFloat(@round(v * Q40));
}
const RAMP_XY: i64 = q40(0.0000003);
const RAMP_Z: i64 = q40(0.0000005);
const FIELD_X_Q16: i64 = 320 << 16;
const FIELD_Y_Q16: i64 = 200 << 16;
const FIELD_Z_Q16: i64 = 200 << 16;

// The three drift tables the field steers towards, one triple every 300 frames.
// They hold FIFTEEN entries and the remake's wrap is `if (nextdata>15)`, so on
// the sixteenth step it reads xnextdata[15] === undefined: every comparison
// against it is false and xadd/yadd/zadd simply FREEZE for that period. That
// off-by-one is the sixteenth "entry" here, and DRIFT_FREEZE reproduces it.
const DRIFT_X = driftQ40(.{ 0.02, 0.01, 0.00, 0.00, -0.01, 0.00, 0.00, 0.00, 0.00, 0.00, 0.01, 0.01, -0.01, -0.01, 0.02 });
const DRIFT_Y = driftQ40(.{ 0.00, 0.00, 0.00, 0.00, -0.01, -0.01, 0.00, 0.00, 0.01, 0.01, 0.02, 0.01, 0.00, 0.00, 0.00 });
const DRIFT_Z = driftQ40(.{ 0.00, 0.01, 0.01, 0.01, -0.01, -0.01, -0.02, -0.02, -0.02, 0.00, 0.01, 0.02, 0.00, 0.01, 0.00 });
fn driftQ40(v: [15]f64) [15]i64 {
    var out: [15]i64 = undefined;
    for (v, 0..) |x, i| out[i] = q40(x);
    return out;
}

// The intro's wave: slice j of frame n reads sin(0.02 * (j + 1 - n)) -- the
// angle gains 0.02 per slice and loses 81 * 0.02 a frame -- so the whole wave
// is one table indexed by (j + 1 - n), built here at comptime.
const INTRO_Y: [INTRO_FRAMES + 81]i8 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [INTRO_FRAMES + 81]i8 = undefined;
    for (&t, 0..) |*y, i| {
        const m: f64 = @as(f64, @floatFromInt(i)) - @as(f64, INTRO_FRAMES);
        y.* = @intFromFloat(@round(30 * @sin(0.02 * m)));
    }
    break :blk t;
};

// The scroller's phase and rotation advance by constants; see tlb_spoon/trig.zig.
const LETTER_STEP = trig.Step.of(10 * 0.04 + 0.004); // next letter: 0.4 + one 0.004 scfx step
const FRAME_STEP = trig.Step.of(0.03 + 14 * 0.004); // c * 0.03 and 14 scfx steps
const JUMP_STEP = trig.Step.of(44 * 0.008);
const THETA_STEP = trig.Step.of(-0.015);
const LOGO1_STEP = trig.Step.of(0.03);
const LOGO2_STEP = trig.Step.of(0.06);
const LETTER_ANGLE_SCALE: f32 = -50.0 * 0.5 * (std.math.pi / 180.0);
const DRIFT_FREEZE: usize = 15;

// --------------------------------------------------------------------------
// The scroller's two-stage geometry (screen.js:322-364)
// --------------------------------------------------------------------------
// Stage 1: fourteen 25x25 glyphs go onto a 400x200 canvas, each rotated about
// its own TOP-LEFT corner (lettercanvas has no handle, so `draw(...,scx,scy,1,
// scr)` translates to (scx,scy) then rotates there).
// Stage 2: that canvas is blitted through
//     translate(200,100); rotate(theta); translate(-200,-120)
// and then drawn at (-40,0). Composed: a scroll-canvas point p becomes
//     (160,100) + R(theta) * (p - (200,120)).
// Note translate(-width/2, -width/2+80) uses WIDTH twice, hence 120 and not 20.
//
// ONE FRAME OF LAG, and it is real: `scrollcanvas.draw(testcanvas,0,0,1,0)`
// copies the letters BEFORE the frame's own transform is installed, so what
// reaches the screen at frame n is frame n's letters under frame n-1's theta.
// The 400x200 scroll canvas bounds live in tlb_spoon/letter.zig.
const NB_LETTERS: usize = 14;

// --------------------------------------------------------------------------
// Per-frame placements, computed in update() and painted in render()
// --------------------------------------------------------------------------
const Ball = struct { x: f32, y: f32, s: f32 };

const Letter = letter.Letter;
const Frame = letter.Frame;

pub const Demo = struct {
    counter: u32,

    // intro()
    introx: i32,
    draw_introx: i32, // the pan THIS frame draws with: intro() blits, THEN advances
    slice_y: [80]i16,

    // starballs()
    starx: [STAR_NR]i16,
    stary: [STAR_NR]i16, // starz[i] = i
    startimer: u32,
    nextdata: usize,
    xnext: i64, // Q40
    ynext: i64,
    znext: i64,
    drift_frozen: bool,
    xadd: i64,
    yadd: i64,
    zadd: i64,
    xaddspeed: i64,
    yaddspeed: i64,
    zaddspeed: i64,
    balls: [STAR_NR]Ball,

    // logo()
    lo1: trig.Rotor, // loangle1
    lo2: trig.Rotor, // loangle2
    logo_x: i32,
    logo_y: i32,

    // scroller()
    sm: i32,
    ph: trig.Rotor, // phase of letter 0: c * 0.03 + scfx + 0.004
    th: trig.Rotor, // the scroll plane's theta
    letternext: usize,
    letters: [NB_LETTERS]Letter,
    frame: Frame,
    first_main: bool,

    rng: u32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("tlb_spoon: THE LOST BOYS / THE TWIDDLE DEMO", .{});

        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(pal);
        // Index 0 is OPAQUE black on purpose: this is the only plane and the
        // original fills its canvas with solid black every frame.
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        // Struct defaults never run (demo_main holds the cart as `undefined`),
        // so every field is assigned here.
        self.counter = 0;
        self.introx = 0;
        self.draw_introx = 0;
        self.slice_y = [_]i16{0} ** 80;

        self.rng = 0x1d872b41;
        for (0..STAR_NR) |i| {
            self.starx[i] = @intFromFloat(@floor(self.random() * 320.0)); // init-time float
            self.stary[i] = @intFromFloat(@floor(self.random() * 200.0));
            self.balls[i] = .{ .x = 0, .y = 0, .s = 0 };
        }
        self.startimer = 0;
        self.nextdata = 0;
        self.xnext = q40(0.02);
        self.ynext = 0;
        self.znext = 0;
        self.drift_frozen = false;
        self.xadd = q40(0.02);
        self.yadd = 0;
        self.zadd = 0;
        self.xaddspeed = q40(0.02);
        self.yaddspeed = q40(0.01);
        self.zaddspeed = q40(0.01);

        self.lo1 = trig.Rotor.at(0);
        self.lo2 = trig.Rotor.at(0);
        self.logo_x = 0;
        self.logo_y = 0;

        self.sm = 0;
        self.ph = trig.Rotor.at(@as(f64, INTRO_FRAMES) * 0.03 + 0.004); // init-time float
        self.th = trig.Rotor.at(std.math.pi / 180.0 - @as(f64, INTRO_FRAMES) * 0.015);
        self.letternext = 0;
        self.letters = [_]Letter{.{ .tile = GLYPH_TILES, .ox = 0, .oy = 0, .cb = 1, .sb = 0 }} ** NB_LETTERS;
        self.frame = .{ .ct = 1, .st = 0, .cx = 0, .cy = 0, .sx = 0, .sy = 0 };
        self.first_main = true;

        zg.requestSongTune(MUSIC, MUSIC_TUNE);
    }

    // The stars' only randomness: the remake seeds them from Math.random().
    fn random(self: *Demo) f64 {
        var x = self.rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng = x;
        return @as(f64, @floatFromInt(x >> 8)) / 16777216.0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.counter < INTRO_FRAMES) {
            self.updateIntro();
        } else {
            self.updateStars();
            self.updateLogo();
            self.updateScroller();
        }
        self.counter += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        @memset(fb.fb[0 .. W * H], 0);
        if (self.counter <= INTRO_FRAMES) {
            self.drawIntro(fb);
        } else {
            self.drawStars(fb);
            self.drawLogo(fb);
            self.drawScroller(fb);
        }
    }

    // ----------------------------------------------------------------------
    // intro() — screen.js:218-227
    // ----------------------------------------------------------------------
    // The text is one long pre-rendered strip (INTRO_TEXT.len * 32 x 16) that is
    // read back in EIGHTY 4-pixel-wide slices, each at its own height from a
    // running sine. `angle` gains 0.02 per slice and then loses 81*0.02, so the
    // wave's phase walks backwards by 0.02 a frame while the strip pans by 3.
    //
    // The strip itself is never materialised here: a strip column maps straight
    // back to a glyph column of introfont.raw, which saves 64 KB and a blit.
    fn updateIntro(self: *Demo) void {
        const base: i32 = 1 - @as(i32, @intCast(self.counter)) + INTRO_FRAMES;
        for (&self.slice_y, 0..) |*y, j| y.* = INTRO_Y[@intCast(base + @as(i32, @intCast(j)))];
        self.draw_introx = self.introx;
        self.introx += 3;
    }

    fn drawIntro(self: *Demo, fb: *LogicalFB) void {
        for (self.slice_y, 0..) |dy, i| {
            const dst_x: i32 = @as(i32, @intCast(i)) * 4;
            const src_x: i32 = dst_x + self.draw_introx;
            // drawPart clamps partw to what is left of the source and gives up
            // when nothing is (codef_core.js:558-575).
            const cols = @min(4, STRIP_W - src_x);
            if (cols <= 0) continue;
            const dst_y: i32 = dy + 92;
            var c: i32 = 0;
            while (c < cols) : (c += 1) {
                drawStripColumn(fb, src_x + c, dst_x + c, dst_y);
            }
        }
    }

    // ----------------------------------------------------------------------
    // starballs() — screen.js:229-297
    // ----------------------------------------------------------------------
    // The drift ramps and the speed accumulators live INSIDE the per-star loop
    // in the original, so they step 200 times a frame, not once. That is what
    // makes the field accelerate the way it does; it is kept exactly.
    fn updateStars(self: *Demo) void {
        self.startimer += 1;
        if (self.startimer > 30 * 10) {
            self.drift_frozen = self.nextdata == DRIFT_FREEZE;
            if (!self.drift_frozen) {
                self.xnext = DRIFT_X[self.nextdata];
                self.ynext = DRIFT_Y[self.nextdata];
                self.znext = DRIFT_Z[self.nextdata];
            }
            self.nextdata += 1;
            self.startimer = 0;
            if (self.nextdata > 15) self.nextdata = 0;
        }

        for (0..STAR_NR) |i| {
            if (!self.drift_frozen) {
                if (self.xnext > self.xadd) self.xadd += RAMP_XY;
                if (self.xnext < self.xadd) self.xadd -= RAMP_XY;
                if (self.ynext > self.yadd) self.yadd += RAMP_XY;
                if (self.ynext < self.yadd) self.yadd -= RAMP_XY;
                if (self.znext > self.zadd) self.zadd += RAMP_Z;
                if (self.znext < self.zadd) self.zadd -= RAMP_Z;
            }
            self.xaddspeed += self.xadd;
            self.yaddspeed += self.yadd;
            self.zaddspeed += self.zadd;

            const px = wrapQ16((@as(i64, self.starx[i]) << 16) + (self.xaddspeed >> 24), 320);
            const py = wrapQ16((@as(i64, self.stary[i]) << 16) + (self.yaddspeed >> 24), 200);
            const pz = wrapQ16((@as(i64, @intCast(i)) << 16) - (self.zaddspeed >> 24), 200);
            if (pz == 0) {
                self.balls[i] = .{ .x = 1.0e6, .y = 1.0e6, .s = 1 }; // z = 0 projects to infinity
                continue;
            }

            const pzf = q16f(pz);
            const k = 128 / pzf;
            self.balls[i] = .{
                .x = clampPlot((q16f(px) - FIELD_X / 2) * k + FIELD_X / 2),
                .y = clampPlot((q16f(py) - FIELD_Y / 2) * k + FIELD_Y / 2),
                .s = 1 - pzf / FIELD_Z,
            };
        }
        // The speeds only matter modulo the field (stars start on whole units),
        // and an unbounded Q40 would overflow after hours.
        self.xaddspeed = wrapQ40(self.xaddspeed, FIELD_X_Q16);
        self.yaddspeed = wrapQ40(self.yaddspeed, FIELD_Y_Q16);
        self.zaddspeed = wrapQ40(self.zaddspeed, FIELD_Z_Q16);
    }

    fn drawStars(self: *Demo, fb: *LogicalFB) void {
        for (self.balls) |b| {
            if (!(b.s > 0)) continue; // also rejects the NaN a zero z produces
            drawScaledBall(fb, b);
        }
    }

    // ----------------------------------------------------------------------
    // logo() — screen.js:299-306
    // ----------------------------------------------------------------------
    fn updateLogo(self: *Demo) void {
        self.lo1.turn(LOGO1_STEP);
        self.lo2.turn(LOGO2_STEP);
        // round(80 sin + 80) and round(55 - 50 cos): both positive, so floor(v + 0.5)
        self.logo_x = @intCast(((@as(i64, 80) * self.lo1.s + (@as(i64, 80) << 30)) + (1 << 29)) >> 30);
        self.logo_y = @intCast((((@as(i64, 55) << 30) - @as(i64, 50) * self.lo2.c) + (1 << 29)) >> 30);
    }

    // The logo's ink as comptime runs (tlb_spoon/logo_runs.zig): the same pixels
    // the byte-by-byte test painted, without testing the 80 % that are holes.
    fn drawLogo(self: *Demo, fb: *LogicalFB) void {
        // Every row is clipped the same way, so the x range is found once.
        const x0 = @max(0, -self.logo_x);
        const x1 = @min(LOGO_W, W - self.logo_x);
        const t = &logo_runs.table;
        var y: i32 = 0;
        while (y < LOGO_H) : (y += 1) {
            const dy = self.logo_y + y;
            if (dy < 0 or dy >= H) continue;
            const dst = fb.fb[@as(usize, @intCast(dy)) * W ..];
            const ry: usize = @intCast(y);
            for (t.runs[t.row_start[ry]..t.row_start[ry + 1]]) |run| {
                const a = @max(x0, @as(i32, run.x));
                const b = @min(x1, @as(i32, run.x) + run.len);
                if (a >= b) continue;
                @memset(dst[@intCast(self.logo_x + a)..@intCast(self.logo_x + b)], LOGO_INK);
            }
        }
    }

    // ----------------------------------------------------------------------
    // scroller() — screen.js:308-366
    // ----------------------------------------------------------------------
    // NO HARDWARE SCROLL, and not for want of looking. setScroll pans a window
    // over a buffer by whole pixels; every moving thing on this screen moves in
    // a way that window cannot express:
    //   * the intro's strip DOES pan horizontally (introx += 3), but each of its
    //     eighty columns has its OWN vertical offset from the sine. HSCROLL is a
    //     per-SCANLINE HORIZONTAL offset — a shear the other way round — so a
    //     scroll plane would buy the pan and still leave every column to be
    //     redrawn for the sine. No saving, one more plane to composite.
    //   * the starballs are a 3D projection and the scroller is two composed
    //     rotations; neither has a scroll-register analogue at all.
    // So this screen paints, and it paints into ONE plane.
    fn updateScroller(self: *Demo) void {
        if (self.sm < -31) {
            self.ph.turn(JUMP_STEP);
            self.sm = 0;
            self.letternext += 1;
            if (self.letternext > SCROLL_TEXT.len - 12) self.letternext = 0;
        }
        self.sm -= 1;

        // The transform the frame is SHOWN through is the previous frame's (see
        // the note above NB_LETTERS). Before there is one, the letters go up 1:1 at
        // (-40,0) — the identity testcanvas the remake starts with.
        const first = self.first_main;
        const ct: f32 = if (first) 1 else self.th.cosF();
        const st: f32 = if (first) 0 else self.th.sinF();
        self.frame = if (first)
            Frame{ .ct = 1, .st = 0, .cx = -40, .cy = 0, .sx = 0, .sy = 0 }
        else
            Frame{ .ct = ct, .st = st, .cx = 160, .cy = 100, .sx = 200, .sy = 120 };
        self.first_main = false;

        var phase = self.ph;
        for (&self.letters, 0..) |*slot, i| {
            if (i > 0) phase.turn(LETTER_STEP);
            slot.* = .{ .tile = GLYPH_TILES, .ox = 0, .oy = 0, .cb = 1, .sb = 0 };
            const idx = i + self.letternext;
            if (idx >= SCROLL_TEXT.len) continue; // charAt() past the end draws nothing
            const ch = SCROLL_TEXT[idx];
            if (ch < GLYPH_FIRST or ch - GLYPH_FIRST >= GLYPH_TILES) continue;

            const scx: f32 = @floatFromInt(self.sm + 32 * @as(i32, @intCast(i)));
            const scy: f32 = 50 * phase.cosF() + 90;
            const la = trig.sinCosSmall(phase.sinF() * LETTER_ANGLE_SCALE);

            // Glyph point g lands at O + R(theta + letter_angle) * g, where O is
            // the image of the glyph's own (scx,scy) origin.
            const dx = scx - self.frame.sx;
            const dy = scy - self.frame.sy;
            slot.* = .{
                .tile = ch - GLYPH_FIRST,
                .ox = self.frame.cx + ct * dx - st * dy,
                .oy = self.frame.cy + st * dx + ct * dy,
                .cb = ct * la.c - st * la.s,
                .sb = st * la.c + ct * la.s,
            };
        }
        self.ph.turn(FRAME_STEP);
        if (!first) self.th.turn(THETA_STEP);
    }

    fn drawScroller(self: *Demo, fb: *LogicalFB) void {
        for (self.letters) |slot| {
            if (slot.tile >= GLYPH_TILES) continue;
            letter.draw(fb, slot, self.frame);
        }
    }
};

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
// `if(p>size) p-=size*floor(p/size); if(p<0) p-=size*floor(p/size);` on a Q16
// value. The speeds are wrapped into [0, size) every frame and drift at most a
// few units inside one (200 steps of |add| <= 0.02), so p lies in about
// (-size, 2 * size) Q16: it fits an i32. A floored modulo by a COMPTIME size is
// the old add/subtract loops' exact result, and it lowers to a multiply; the
// loops on an i64 with a run-time size had become a soft i64 divide (0.37 Mc).
inline fn wrapQ16(p: i64, comptime size: i32) i32 {
    const v: i32 = @intCast(p);
    return @mod(v, size << 16);
}

fn wrapQ40(v: i64, size_q16: i64) i64 {
    var r = v;
    const size = size_q16 << 24;
    while (r >= size) r -= size;
    while (r < 0) r += size;
    return r;
}

inline fn q16f(v: i32) f32 {
    return @as(f32, @floatFromInt(v)) * (1.0 / 65536.0);
}

// A star at z -> 0 projects arbitrarily far away; keep the value representable
// so the blit's bounding box arithmetic cannot overflow.
fn clampPlot(v: f32) f32 {
    if (!(v > -1.0e6) or !(v < 1.0e6)) return 1.0e6;
    return v;
}

// One column of the intro's virtual strip: strip x -> glyph column of the sheet.
fn drawStripColumn(fb: *LogicalFB, src_x: i32, dst_x: i32, dst_y: i32) void {
    if (dst_x < 0 or dst_x >= W) return;
    const ch = INTRO_TEXT[@intCast(@divFloor(src_x, INTRO_GW))];
    if (ch < INTRO_FIRST or ch - INTRO_FIRST >= INTRO_TILES) return;
    const tile: usize = ch - INTRO_FIRST;
    const col = tile % INTRO_COLS;
    const row = tile / INTRO_COLS;
    const sx = col * INTRO_GW + @as(usize, @intCast(@mod(src_x, INTRO_GW)));
    var gy: i32 = 0;
    while (gy < INTRO_GH) : (gy += 1) {
        const dy = dst_y + gy;
        if (dy < 0 or dy >= H) continue;
        const v = introfont_b[(row * INTRO_GH + @as(usize, @intCast(gy))) * INTRO_SHEET_W + sx];
        if (v != 0) fb.fb[@as(usize, @intCast(dy)) * W + @as(usize, @intCast(dst_x))] = v;
    }
}

// `ballimage.draw(org, x, y, 1, 0, s, s)` puts the 8x8 sprite's top-left at
// (x,y) and scales it by s about that corner, so it covers [x, x+8s) x [y, y+8s).
// Point-sampled: the remake gets Chrome's bilinear blur, an ST would not.
fn drawScaledBall(fb: *LogicalFB, b: Ball) void {
    const span = @as(f32, BALL_SIZE) * b.s;
    const x0 = @max(0, @as(i32, @intFromFloat(@ceil(b.x - 0.5))));
    const y0 = @max(0, @as(i32, @intFromFloat(@ceil(b.y - 0.5))));
    const x1 = @min(W, @as(i32, @intFromFloat(@ceil(b.x + span - 0.5))));
    const y1 = @min(H, @as(i32, @intFromFloat(@ceil(b.y + span - 0.5))));
    if (x0 >= x1 or y0 >= y1) return;

    // A ball is at most 8 px wide: its source columns are worked out once, not per row.
    const inv = 1.0 / b.s;
    var cols: [BALL_SIZE + 1]u8 = undefined;
    const nx: usize = @intCast(@min(BALL_SIZE + 1, x1 - x0));
    for (0..nx) |i| cols[i] = sampleIndex(@as(f32, @floatFromInt(x0 + @as(i32, @intCast(i)))) + 0.5 - b.x, inv);

    var y = y0;
    while (y < y1) : (y += 1) {
        const sy = sampleIndex(@as(f32, @floatFromInt(y)) + 0.5 - b.y, inv);
        const src = ball_b[sy * BALL_SIZE ..];
        const dst = fb.fb[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x0)) ..];
        for (cols[0..nx], 0..) |c, i| {
            const v = src[c];
            if (v != 0) dst[i] = v;
        }
    }
}

fn sampleIndex(offset: f32, inv_scale: f32) u8 {
    const i = @as(i32, @intFromFloat(@floor(offset * inv_scale)));
    return @intCast(@min(BALL_SIZE - 1, @max(0, i)));
}

comptime {
    if (ball_b.len != BALL_SIZE * BALL_SIZE) @compileError("ball.raw is not 8x8");
    if (introfont_b.len != INTRO_SHEET_W * 200) @compileError("introfont.raw is not 320x200");
}
