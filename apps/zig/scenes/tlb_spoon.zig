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
const RASTER_BASE: u8 = 6;

const ball_b = @embedFile("../assets/screens/tlb_spoon/ball.raw");
const BALL_SIZE = 8;

const logo_b = @embedFile("../assets/screens/tlb_spoon/logo.raw");
const LOGO_W = 158;
const LOGO_H = 91;

// scrollimage.initTile(25,25,25): 25x25 tiles, tile index = charcode - 25.
const font_b = @embedFile("../assets/screens/tlb_spoon/font.raw");
const FONT_SHEET_W: usize = 250;
const GLYPH = 25;
const GLYPH_COLS: u16 = 10;
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
const FIELD_X: f64 = 320;
const FIELD_Y: f64 = 200;
const FIELD_Z: f64 = 200;
const STAR_NR: usize = 200;

// The three drift tables the field steers towards, one triple every 300 frames.
// They hold FIFTEEN entries and the remake's wrap is `if (nextdata>15)`, so on
// the sixteenth step it reads xnextdata[15] === undefined: every comparison
// against it is false and xadd/yadd/zadd simply FREEZE for that period. That
// off-by-one is the sixteenth "entry" here, and DRIFT_FREEZE reproduces it.
const DRIFT_X = [_]f64{ 0.02, 0.01, 0.00, 0.00, -0.01, 0.00, 0.00, 0.00, 0.00, 0.00, 0.01, 0.01, -0.01, -0.01, 0.02 };
const DRIFT_Y = [_]f64{ 0.00, 0.00, 0.00, 0.00, -0.01, -0.01, 0.00, 0.00, 0.01, 0.01, 0.02, 0.01, 0.00, 0.00, 0.00 };
const DRIFT_Z = [_]f64{ 0.00, 0.01, 0.01, 0.01, -0.01, -0.01, -0.02, -0.02, -0.02, 0.00, 0.01, 0.02, 0.00, 0.01, 0.00 };
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
const SCROLL_W: f64 = 400;
const SCROLL_H: f64 = 200;
const NB_LETTERS: usize = 14;

// --------------------------------------------------------------------------
// Per-frame placements, computed in update() and painted in render()
// --------------------------------------------------------------------------
const Ball = struct { x: f32, y: f32, s: f32 };

const Letter = struct {
    tile: u16, // GLYPH_TILES = "nothing to draw"
    ox: f32, // where the glyph's (0,0) lands on screen
    oy: f32,
    cb: f32, // R(theta + letter angle): glyph space -> screen
    sb: f32,
};

// The scroll canvas -> screen affine, and its inverse (used to clip a pixel
// against the 400x200 canvas exactly as the remake's canvas bounds do).
const Frame = struct {
    ct: f32,
    st: f32,
    cx: f32,
    cy: f32,
    sx: f32,
    sy: f32,
};

pub const Demo = struct {
    counter: u32,

    // intro()
    angle: f64,
    introx: i32,
    draw_introx: i32, // the pan THIS frame draws with: intro() blits, THEN advances
    slice_y: [80]i16,

    // starballs()
    starx: [STAR_NR]f64,
    stary: [STAR_NR]f64,
    starz: [STAR_NR]f64,
    startimer: u32,
    nextdata: usize,
    xnext: f64,
    ynext: f64,
    znext: f64,
    drift_frozen: bool,
    xadd: f64,
    yadd: f64,
    zadd: f64,
    xaddspeed: f64,
    yaddspeed: f64,
    zaddspeed: f64,
    balls: [STAR_NR]Ball,

    // logo()
    loangle1: f64,
    loangle2: f64,
    logo_x: i32,
    logo_y: i32,

    // scroller()
    sm: i32,
    scfx: f64,
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
        self.angle = 0;
        self.introx = 0;
        self.draw_introx = 0;
        self.slice_y = [_]i16{0} ** 80;

        self.rng = 0x1d872b41;
        for (0..STAR_NR) |i| {
            self.starx[i] = @floor(self.random() * FIELD_X);
            self.stary[i] = @floor(self.random() * FIELD_Y);
            self.starz[i] = @as(f64, @floatFromInt(i)) * (FIELD_Z / @as(f64, STAR_NR));
            self.balls[i] = .{ .x = 0, .y = 0, .s = 0 };
        }
        self.startimer = 0;
        self.nextdata = 0;
        self.xnext = 0.02;
        self.ynext = 0.00;
        self.znext = 0.00;
        self.drift_frozen = false;
        self.xadd = 0.02;
        self.yadd = 0;
        self.zadd = 0;
        self.xaddspeed = 0.02;
        self.yaddspeed = 0.01;
        self.zaddspeed = 0.01;

        self.loangle1 = 0;
        self.loangle2 = 0;
        self.logo_x = 0;
        self.logo_y = 0;

        self.sm = 0;
        self.scfx = 0;
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
        for (&self.slice_y) |*y| {
            self.angle += 0.02;
            y.* = @intFromFloat(@round(30 * @sin(self.angle)));
        }
        self.angle -= 81 * 0.02;
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
                if (self.xnext > self.xadd) self.xadd += 0.0000003;
                if (self.xnext < self.xadd) self.xadd -= 0.0000003;
                if (self.ynext > self.yadd) self.yadd += 0.0000003;
                if (self.ynext < self.yadd) self.yadd -= 0.0000003;
                if (self.znext > self.zadd) self.zadd += 0.0000005;
                if (self.znext < self.zadd) self.zadd -= 0.0000005;
            }
            self.xaddspeed += self.xadd;
            self.yaddspeed += self.yadd;
            self.zaddspeed += self.zadd;

            const px = wrapField(self.starx[i] + self.xaddspeed, FIELD_X);
            const py = wrapField(self.stary[i] + self.yaddspeed, FIELD_Y);
            const pz = wrapField(self.starz[i] - self.zaddspeed, FIELD_Z);

            const k = 128 / pz;
            self.balls[i] = .{
                .x = clampPlot((px - FIELD_X / 2) * k + FIELD_X / 2),
                .y = clampPlot((py - FIELD_Y / 2) * k + FIELD_Y / 2),
                .s = @floatCast(1 - pz / FIELD_Z),
            };
        }
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
        self.loangle1 += 0.03;
        self.loangle2 += 0.06;
        self.logo_x = @intFromFloat(@round(80 * @sin(self.loangle1) + 80));
        self.logo_y = @intFromFloat(@round(-50 * @cos(self.loangle2) + 55));
    }

    fn drawLogo(self: *Demo, fb: *LogicalFB) void {
        // Every row is clipped the same way, so the x range is found once.
        const x0 = @max(0, -self.logo_x);
        const x1 = @min(LOGO_W, W - self.logo_x);
        var y: i32 = 0;
        while (y < LOGO_H) : (y += 1) {
            const dy = self.logo_y + y;
            if (dy < 0 or dy >= H) continue;
            const row = @as(usize, @intCast(y)) * LOGO_W;
            const dst = fb.fb[@as(usize, @intCast(dy)) * W ..];
            var x = x0;
            while (x < x1) : (x += 1) {
                if (logo_b[row + @as(usize, @intCast(x))] != 0) {
                    dst[@intCast(self.logo_x + x)] = LOGO_INK;
                }
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
            self.scfx += 44 * 0.008;
            self.sm = 0;
            self.letternext += 1;
            if (self.letternext > SCROLL_TEXT.len - 12) self.letternext = 0;
        }
        self.sm -= 1;

        // The transform the frame is SHOWN through is the previous frame's (see
        // the note by SCROLL_W). Before there is one, the letters go up 1:1 at
        // (-40,0) — the identity testcanvas the remake starts with.
        const c: f64 = @floatFromInt(self.counter);
        const theta: f64 = if (self.first_main) 0 else std.math.pi / 180.0 - (c - 1) * 0.015;
        const ct = @cos(theta);
        const st = @sin(theta);
        self.frame = if (self.first_main)
            Frame{ .ct = 1, .st = 0, .cx = -40, .cy = 0, .sx = 0, .sy = 0 }
        else
            Frame{ .ct = @floatCast(ct), .st = @floatCast(st), .cx = 160, .cy = 100, .sx = 200, .sy = 120 };
        self.first_main = false;

        for (&self.letters, 0..) |*slot, i| {
            self.scfx += 0.004;
            const phase = c * 0.03 + self.scfx + @as(f64, @floatFromInt(i)) * (10 * 0.04);
            const scx: f64 = @floatFromInt(self.sm + 32 * @as(i32, @intCast(i)));
            const scy: f64 = 50 * @cos(phase) + 90;
            const letter_angle = (-50 * @sin(phase) * 0.5) * std.math.pi / 180.0;

            slot.* = .{ .tile = GLYPH_TILES, .ox = 0, .oy = 0, .cb = 1, .sb = 0 };
            const idx = i + self.letternext;
            if (idx >= SCROLL_TEXT.len) continue; // charAt() past the end draws nothing
            const ch = SCROLL_TEXT[idx];
            if (ch < GLYPH_FIRST or ch - GLYPH_FIRST >= GLYPH_TILES) continue;

            // Glyph point g lands at O + R(theta + letter_angle) * g, where O is
            // the image of the glyph's own (scx,scy) origin.
            const dx = scx - @as(f64, self.frame.sx);
            const dy = scy - @as(f64, self.frame.sy);
            const b = theta + letter_angle;
            slot.* = .{
                .tile = ch - GLYPH_FIRST,
                .ox = @floatCast(@as(f64, self.frame.cx) + ct * dx - st * dy),
                .oy = @floatCast(@as(f64, self.frame.cy) + st * dx + ct * dy),
                .cb = @floatCast(@cos(b)),
                .sb = @floatCast(@sin(b)),
            };
        }
    }

    fn drawScroller(self: *Demo, fb: *LogicalFB) void {
        for (self.letters) |slot| {
            if (slot.tile >= GLYPH_TILES) continue;
            drawLetter(fb, slot, self.frame);
        }
    }
};

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
// `if(p>size) p-=size*floor(p/size); if(p<0) p-=size*floor(p/size);` — the two
// branches are exclusive and both are a modulo; p == size is left alone, which
// is why this is not simply @mod (a star that landed exactly on the far z plane
// would flip from size to 0 and project to infinity).
fn wrapField(p: f64, size: f64) f64 {
    if (p > size or p < 0) return p - size * @floor(p / size);
    return p;
}

// A star at z -> 0 projects arbitrarily far away; keep the value representable
// so the blit's bounding box arithmetic cannot overflow.
fn clampPlot(v: f64) f32 {
    if (!(v > -1.0e6) or !(v < 1.0e6)) return 1.0e6;
    return @floatCast(v);
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

    var y = y0;
    while (y < y1) : (y += 1) {
        const sy = sampleIndex(@as(f32, @floatFromInt(y)) + 0.5 - b.y, b.s);
        const src = ball_b[sy * BALL_SIZE ..];
        const dst = fb.fb[@as(usize, @intCast(y)) * W ..];
        var x = x0;
        while (x < x1) : (x += 1) {
            const v = src[sampleIndex(@as(f32, @floatFromInt(x)) + 0.5 - b.x, b.s)];
            if (v != 0) dst[@intCast(x)] = v;
        }
    }
}

fn sampleIndex(offset: f32, scale: f32) usize {
    const i = @as(i32, @intFromFloat(@floor(offset / scale)));
    return @intCast(@min(BALL_SIZE - 1, @max(0, i)));
}

// One scroller letter: walk its screen bounding box, map each pixel back to
// glyph space through R(-(theta+letter_angle)), and — exactly as the remake's
// 400x200 canvas does — reject anything that falls outside the scroll canvas.
// A glyph pixel does not paint the font's ink: it PUNCHES a hole, and the hole
// shows the raster band for that screen row.
fn drawLetter(fb: *LogicalFB, slot: Letter, f: Frame) void {
    var min_x: f32 = 1.0e9;
    var min_y: f32 = 1.0e9;
    var max_x: f32 = -1.0e9;
    var max_y: f32 = -1.0e9;
    const g: f32 = @floatFromInt(GLYPH);
    for ([_][2]f32{ .{ 0, 0 }, .{ g, 0 }, .{ 0, g }, .{ g, g } }) |corner| {
        const cx = slot.ox + slot.cb * corner[0] - slot.sb * corner[1];
        const cy = slot.oy + slot.sb * corner[0] + slot.cb * corner[1];
        min_x = @min(min_x, cx);
        max_x = @max(max_x, cx);
        min_y = @min(min_y, cy);
        max_y = @max(max_y, cy);
    }
    const x0 = @max(0, @as(i32, @intFromFloat(@floor(min_x))));
    const y0 = @max(0, @as(i32, @intFromFloat(@floor(min_y))));
    const x1 = @min(W, @as(i32, @intFromFloat(@ceil(max_x))) + 1);
    const y1 = @min(H, @as(i32, @intFromFloat(@ceil(max_y))) + 1);
    if (x0 >= x1 or y0 >= y1) return;

    const tile_x = @as(usize, slot.tile % GLYPH_COLS) * GLYPH;
    const tile_y = @as(usize, slot.tile / GLYPH_COLS) * GLYPH;

    var y = y0;
    while (y < y1) : (y += 1) {
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        // Screen -> glyph, and screen -> scroll canvas; both advance by a
        // constant vector along the row, so each row costs two rotations.
        var gx = slot.cb * (@as(f32, @floatFromInt(x0)) + 0.5 - slot.ox) + slot.sb * (py - slot.oy);
        var gy = -slot.sb * (@as(f32, @floatFromInt(x0)) + 0.5 - slot.ox) + slot.cb * (py - slot.oy);
        var canvas_x = f.sx + f.ct * (@as(f32, @floatFromInt(x0)) + 0.5 - f.cx) + f.st * (py - f.cy);
        var canvas_y = f.sy - f.st * (@as(f32, @floatFromInt(x0)) + 0.5 - f.cx) + f.ct * (py - f.cy);
        const ink = RASTER_BASE + @as(u8, @intCast(@divTrunc(y, 8)));
        const dst = fb.fb[@as(usize, @intCast(y)) * W ..];

        var x = x0;
        while (x < x1) : ({
            x += 1;
            gx += slot.cb;
            gy -= slot.sb;
            canvas_x += f.ct;
            canvas_y -= f.st;
        }) {
            if (gx < 0 or gy < 0 or gx >= g or gy >= g) continue;
            if (canvas_x < 0 or canvas_y < 0 or canvas_x >= SCROLL_W or canvas_y >= SCROLL_H) continue;
            const sxi = tile_x + @as(usize, @intFromFloat(gx));
            const syi = tile_y + @as(usize, @intFromFloat(gy));
            if (font_b[syi * FONT_SHEET_W + sxi] != 0) dst[@intCast(x)] = ink;
        }
    }
}

comptime {
    if (ball_b.len != BALL_SIZE * BALL_SIZE) @compileError("ball.raw is not 8x8");
    if (logo_b.len != LOGO_W * LOGO_H) @compileError("logo.raw is not 158x91");
    if (font_b.len != FONT_SHEET_W * 7 * GLYPH) @compileError("font.raw is not a 10x7 grid of 25x25");
    if (introfont_b.len != INTRO_SHEET_W * 200) @compileError("introfont.raw is not 320x200");
}
