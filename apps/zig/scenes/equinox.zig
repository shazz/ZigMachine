// --------------------------------------------------------------------------
// EQUINOX — RVF Honda intro. CODEF wab screen 015 (prototypes/codef/15/screen.js).
//
// The canvas is 640x456 = ST 320x228: a low-res screen with the BOTTOM BORDER
// open (`400+(28*2)`). Every plane is an overscan plane with its top and bottom
// bands opened; ST row 0 is physical row 40 (the normal visible top), so rows
// 200..227 — the lower scroller background and the scrolltext — sit in the
// bottom border at physical 240..267.
//
// Planes, in go()'s drawing order:
//   0 roads       black fill, road2 on the odd bands, road1 on the even
//   1 backdrop    backtop, backscroll, the fading logo (palette ALPHA)
//   2 dragons     seven sprites sharing one morph frame
//   3 scrolltext
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max's "Cybernoid 2" (1989).
const MUSIC = "cybernoid2.sndh";

const DIR = "../assets/screens/equinox/";

// --------------------------------------------------------------------------
// Screen geometry
// --------------------------------------------------------------------------
const SCREEN_W: usize = 320;
const SCREEN_H: usize = 228; // 400+(28*2) halved
const SCREEN_X: usize = 40; // ST column 0 in the 400-wide overscan buffer
const SCREEN_Y: usize = 40; // ST row 0 = the first normally-visible row

fn screenView(fb: *LogicalFB) blit.Dst {
    return blit.Dst.plane(fb).window(SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H);
}

// --------------------------------------------------------------------------
// Plane 0: roads (screen.js:270-289)
// --------------------------------------------------------------------------
const road_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "road_pal.dat"));
const road1_img = blit.Image.init(@embedFile(DIR ++ "road1.raw"), SCREEN_W);
const road2_img = blit.Image.init(@embedFile(DIR ++ "road2.raw"), SCREEN_W);
const ROAD_Y: usize = 113; // offset_y 226
const ROAD_FRAMES = 18;
const ROAD_CLEAR: u8 = 255; // outside the screen: transparent
const BLACK: u8 = 5; // road_pal[5] is opaque black: mycanvas.fill('#000000')

// Both tables are in canvas rows; every value is even, so halving is exact.
const road_offsets = [ROAD_FRAMES][9]u8{
    .{ 0, 2, 4, 6, 14, 20, 28, 38, 58 },  .{ 0, 2, 4, 8, 14, 22, 28, 40, 52 },
    .{ 0, 2, 6, 8, 14, 22, 30, 42, 46 },  .{ 0, 4, 4, 8, 16, 24, 30, 44, 40 },
    .{ 0, 4, 4, 10, 16, 24, 32, 46, 34 }, .{ 0, 4, 6, 10, 16, 26, 32, 48, 28 },
    .{ 0, 4, 6, 12, 16, 26, 34, 52, 20 }, .{ 0, 6, 4, 12, 20, 26, 34, 54, 14 },
    .{ 0, 6, 6, 12, 20, 26, 36, 56, 8 },  .{ 2, 4, 6, 14, 20, 28, 38, 58, 0 },
    .{ 2, 4, 8, 14, 22, 28, 40, 52, 0 },  .{ 2, 6, 8, 14, 22, 30, 42, 46, 0 },
    .{ 4, 4, 8, 16, 24, 30, 44, 40, 0 },  .{ 4, 4, 10, 16, 24, 32, 46, 34, 0 },
    .{ 4, 6, 10, 16, 26, 32, 48, 28, 0 }, .{ 4, 6, 12, 16, 26, 34, 52, 20, 0 },
    .{ 6, 4, 12, 20, 26, 34, 54, 14, 0 }, .{ 6, 6, 12, 20, 26, 36, 56, 8, 0 },
};
const road_sum = [ROAD_FRAMES][10]u8{
    .{ 0, 0, 2, 6, 12, 26, 46, 74, 112, 170 },  .{ 0, 0, 2, 6, 14, 28, 50, 78, 118, 170 },
    .{ 0, 0, 2, 8, 16, 30, 52, 82, 124, 170 },  .{ 0, 0, 4, 8, 16, 32, 56, 86, 130, 170 },
    .{ 0, 0, 4, 8, 18, 34, 58, 90, 136, 170 },  .{ 0, 0, 4, 10, 20, 36, 62, 94, 142, 170 },
    .{ 0, 0, 4, 10, 22, 38, 64, 98, 150, 170 }, .{ 0, 0, 6, 10, 22, 42, 68, 102, 156, 170 },
    .{ 0, 0, 6, 12, 24, 44, 70, 106, 162, 170 }, .{ 0, 2, 6, 12, 26, 46, 74, 112, 170, 0 },
    .{ 0, 2, 6, 14, 28, 50, 78, 118, 170, 0 },  .{ 0, 2, 8, 16, 30, 52, 82, 124, 170, 0 },
    .{ 0, 4, 8, 16, 32, 56, 86, 130, 170, 0 },  .{ 0, 4, 8, 18, 34, 58, 90, 136, 170, 0 },
    .{ 0, 4, 10, 20, 36, 62, 94, 142, 170, 0 }, .{ 0, 4, 10, 22, 38, 64, 98, 150, 170, 0 },
    .{ 0, 6, 10, 22, 42, 68, 102, 156, 170, 0 }, .{ 0, 6, 12, 24, 44, 70, 106, 162, 170, 0 },
};

// drawRoad(): band `band` of animation frame `i`, copied row-for-row.
fn drawRoadBand(view: blit.Dst, road: blit.Image, i: usize, band: usize) void {
    const h = road_offsets[i][band] / 2;
    if (h == 0) return;
    const top = road_sum[i][band] / 2;
    const part = blit.Rect{ .x = 0, .y = top, .w = SCREEN_W, .h = h };
    blit.blit(view, road, part, 0, @intCast(ROAD_Y + top), null, .copy);
}

// --------------------------------------------------------------------------
// Plane 1: backtop, backscroll and the logo (screen.js:190-214, 292-297)
// --------------------------------------------------------------------------
const backtop_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "backtop_pal.dat"));
const logo_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "logo_pal.dat"));
const backtop_img = blit.Image.init(@embedFile(DIR ++ "backtop.raw"), SCREEN_W);
const backscroll_img = blit.Image.init(@embedFile(DIR ++ "backscroll.raw"), SCREEN_W);
const logo_img = blit.Image.init(@embedFile(DIR ++ "logo.raw"), 203);
const BACKDROP_CLEAR: u8 = 5; // backtop_pal's transparent entry
// backscroll.png is 640x79 drawn at canvas y 377: its row 0 is a lone row, then
// pairs, so halved row 0 lands on ST row 188 and the art ends on row 226.
const BACKSCROLL_Y: i32 = 188;
const LOGO_X: i32 = 55; // logocanvas.drawPart(mycanvas, 110, 290, ...)
const LOGO_Y: i32 = 145;
const LOGO_FIELD: u8 = 1;
const LOGO_BASE: u8 = 32; // logo colours live after backtop's 24 entries
const LOGO_COLOURS = 5;
const LOGO_PERIOD = 400; // `if(frames % 400 == 0) timeToShowLogo = 1`
const LOGO_STEP_FRAMES = 10; // alphaTime == 10

// --------------------------------------------------------------------------
// Plane 2: the dragons (screen.js:152-185, 216-268, 301-306)
// --------------------------------------------------------------------------
const bob_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "bobs_pal.dat"));
const NB_DRAGONS = 7;
const DRAGON_W = 32;
// dragon1..dragon8 (64x52, halved); frame 7 is the egg, frame 0 the full dragon
const dragon_frames = [8][]const u8{
    @embedFile(DIR ++ "bob1.raw"), @embedFile(DIR ++ "bob2.raw"), @embedFile(DIR ++ "bob3.raw"),
    @embedFile(DIR ++ "bob4.raw"), @embedFile(DIR ++ "bob5.raw"), @embedFile(DIR ++ "bob6.raw"),
    @embedFile(DIR ++ "bob7.raw"), @embedFile(DIR ++ "bob8.raw"),
};
const EGG_FRAME = 7;

// The precalculated trajectory. Each dragon trails the previous one by 18
// entries; x wraps at 940 and y at 964, so the two tables drift against each
// other. Computed on the 640-wide canvas, then halved to ST pixels.
const TRAIL = 18;
const X_WRAP = 940;
const Y_WRAP = 964;
const trajectory = blk: {
    @setEvalBranchQuota(20000);
    var xs: [X_WRAP]i16 = undefined;
    var ys: [Y_WRAP]i16 = undefined;
    var fac_x: f64 = 0;
    var fac_y: f64 = 0;
    for (0..Y_WRAP) |i| {
        // the increments, per range of i, exactly as screen.js:157-181
        if (i < 125 or i >= 950) {
            fac_x += 0.05;
            fac_y += 0.05;
        } else if (i < 220) {
            fac_x += 0.03;
            fac_y += 0.035;
        } else if (i < 480) {
            fac_x += 0.06;
            fac_y += 0.03;
        } else if (i < 630) {
            fac_x += 0.045;
            fac_y += 0.035;
        } else {
            fac_x += 0.02;
            fac_y += 0.045;
        }
        const x = 320.0 - 64.0 / 2.0 + ((256.0 - 64.0 / 2.0 - 5.0) * @cos(fac_x));
        const y = 200.0 - 52.0 / 2.0 + 30.0 + ((128.0 - 52.0 / 2.0 - 10.0) * @sin(fac_y));
        if (i < X_WRAP) xs[i] = @intFromFloat(@floor(x / 2.0));
        ys[i] = @intFromFloat(@floor(y / 2.0));
    }
    break :blk .{ .x = xs, .y = ys };
};

// The morph machine ticks once every 10 frames; each state lasts a fixed number of ticks.
const MorphState = enum { in_egg, morphing, alive, demorphing };
const MORPH_TICK = 10;
const SLEEP_TICKS = 60;
const MORPH_TICKS = 20;
const ALIVE_TICKS = 70;
const DEMORPH_TICKS = 20;
const ALIVE_TOP_FRAME = 3; // alive ping-pongs frames 0..3

// --------------------------------------------------------------------------
// Plane 3: scrolltext_horizontal (codef_scrolltext.js:47-175)
// --------------------------------------------------------------------------
const font_pal = zg.convertU8ArraytoColors(@embedFile(DIR ++ "fonts_pal.dat"));
// fonts.raw is NOT the 320x156 sheet: it is a STRIP of the 60 glyphs, 32x26
// each, in tile order (glyph k = sheet tile k = character 32 + k).
const font_strip = @embedFile(DIR ++ "fonts.raw");
const SCROLL_TEXT = @embedFile(DIR ++ "scrolltext.txt"); // scrtxt, verbatim
// esfont.initTile(32*2, 26*2, 32), scrolltext.init(mycanvas, esfont, 13).
// Letter x is kept in CANVAS pixels (1 fractional bit of an ST pixel), so the
// 13 px/frame step is 6.5 ST px exactly: drawn at floor(x/2), it moves 6, 7, 6, 7.
const FONT_W: i32 = 64; // canvas units
const GLYPH_W: usize = 32; // ST pixels
const FONT_H: usize = 26; // ST rows
const FONT_FIRST: u8 = 32;
const SCROLL_SPEED: i32 = 13;
const WIDE: i32 = (640 + FONT_W - 1) / FONT_W + 1; // ceil(640/64)+1 = 11
const LETTERS: usize = WIDE + 1; // `for(i=0;i<=this.wide;i++)`
const SCROLL_Y: i32 = 201; // scrolltext.draw(400+(28*2)-(26*2)-2) = 402

const Letter = struct { x: i32, char: u8 };

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    // Every field is assigned in init(): a scene's struct defaults never run.
    frames: u32 = 0, // screen.js `frames`, starts at 1
    road_frame: usize = 0, // screen.js `counter`
    // the logo
    logo_showing: bool = false, // timeToShowLogo
    logo_alpha: f64 = 0,
    logo_inc: f64 = 0,
    logo_ticks: u32 = 0, // alphaTime
    // the dragons
    tabpos: usize = 0, // trajectory index of the lead dragon for the NEXT frame
    drawn_tabpos: usize = 0, // the index this frame's render draws
    morph_state: MorphState = .in_egg,
    morph_frame: u8 = 0, // morphType
    alive_inc: i8 = 0, // aliveInc
    state_ticks: u32 = 0, // sleepingTime / morphTime / aliveTime / demorphTime
    // the scrolltext
    letters: [LETTERS]Letter = undefined,
    scroffset: usize = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        zg.requestSong(MUSIC);

        self.frames = 1;
        self.road_frame = 0;
        self.logo_showing = false;
        self.logo_alpha = 0.00000001;
        self.logo_inc = 0.1;
        self.logo_ticks = 0;
        self.tabpos = 0;
        self.drawn_tabpos = 0;
        self.morph_state = .in_egg;
        self.morph_frame = EGG_FRAME;
        self.alive_inc = 1;
        self.state_ticks = 0;
        self.scroffset = 0;
        for (&self.letters, 0..) |*l, i| {
            l.* = .{ .x = WIDE * FONT_W + @as(i32, @intCast(i)) * FONT_W, .char = SCROLL_TEXT[self.scroffset] };
            self.scroffset += 1;
        }

        var fb: *LogicalFB = &zigos.lfbs[0];
        openPlane(fb, road_pal);
        fb.setPaletteEntry(ROAD_CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        fb = &zigos.lfbs[1];
        openPlane(fb, backtop_pal);
        fb.setPaletteEntry(BACKDROP_CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.setLogoAlpha(fb);

        fb = &zigos.lfbs[2];
        openPlane(fb, bob_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        fb = &zigos.lfbs[3];
        openPlane(fb, font_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    }

    fn openPlane(fb: *LogicalFB, palette: [256]Color) void {
        fb.is_enabled = true;
        fb.openBorders(.top_bottom);
        fb.setPalette(palette);
    }

    // go(), screen.js:276-316, minus the drawing
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.road_frame = (self.road_frame + 1) % ROAD_FRAMES;
        if (self.frames % LOGO_PERIOD == 0) self.logo_showing = true;
        self.tickLogo();
        self.setLogoAlpha(&zigos.lfbs[1]);
        if (self.frames % MORPH_TICK == 0) self.tickMorph();
        self.drawn_tabpos = self.tabpos;
        self.tabpos += 1;
        self.scrollStep();
        self.frames += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.drawRoads(&zigos.lfbs[0]);
        drawBackdrop(&zigos.lfbs[1]);
        self.drawDragons(&zigos.lfbs[2]);
        self.drawScrolltext(&zigos.lfbs[3]);
    }

    // screen.js:280-289: road2 on the odd bands first, then road1 on the even ones
    fn drawRoads(self: *Demo, fb: *LogicalFB) void {
        const all = blit.Dst.plane(fb);
        @memset(all.buf, ROAD_CLEAR);
        const view = screenView(fb);
        @memset(view.buf[0 .. (view.h - 1) * view.stride + view.w], BLACK);
        for (0..9) |band| drawRoadBand(view, if (band % 2 == 1) road2_img else road1_img, self.road_frame, band);
    }

    fn drawBackdrop(fb: *LogicalFB) void {
        @memset(blit.Dst.plane(fb).buf, BACKDROP_CLEAR);
        const view = screenView(fb);
        blit.blit(view, backtop_img, null, 0, 0, null, .copy);
        blit.blit(view, backscroll_img, null, 0, BACKSCROLL_Y, null, .copy);
        blit.blit(view, logo_img, null, LOGO_X, LOGO_Y, LOGO_FIELD, .{ .offset = LOGO_BASE });
    }

    // showLogo(), screen.js:190-214
    fn tickLogo(self: *Demo) void {
        if (!self.logo_showing) return;
        self.logo_ticks += 1;
        if (self.logo_ticks != LOGO_STEP_FRAMES) return;
        self.logo_alpha += self.logo_inc;
        if (self.logo_alpha >= 1.0) {
            self.logo_inc = -0.2;
            self.logo_alpha = 1.0;
        } else if (self.logo_alpha < 0.1) {
            self.logo_inc = 0.2;
            self.logo_alpha = 0.0000001;
            self.logo_showing = false;
        }
        self.logo_ticks = 0;
    }

    // The logo is drawn every frame with globalAlpha = alpha. Plane 1 is its own
    // canvas layer, so the same composite is the palette ALPHA of the logo's
    // entries, blended by the host over the road beneath.
    fn setLogoAlpha(self: *Demo, fb: *LogicalFB) void {
        const a: u8 = @intFromFloat(@round(@max(0.0, @min(1.0, self.logo_alpha)) * 255.0));
        for (0..LOGO_COLOURS) |i| {
            if (i == LOGO_FIELD) continue;
            var c = logo_pal[i];
            c.a = a;
            fb.setPaletteEntry(LOGO_BASE + @as(u8, @intCast(i)), c);
        }
    }

    // morphSprite(), screen.js:216-268: egg (frame 7) for 60 ticks, hatch
    // 7 -> 0 over 20 ticks, ping-pong 0..3 for 70 ticks, back to 7 over 20.
    fn tickMorph(self: *Demo) void {
        self.state_ticks += 1;
        switch (self.morph_state) {
            .in_egg => {
                self.morph_frame = EGG_FRAME;
                if (self.state_ticks == SLEEP_TICKS) self.enter(.morphing);
            },
            .morphing => {
                if (self.morph_frame > 0) self.morph_frame -= 1;
                if (self.state_ticks == MORPH_TICKS) self.enter(.alive);
            },
            .alive => {
                if (self.morph_frame == 0) self.alive_inc = 1 else if (self.morph_frame == ALIVE_TOP_FRAME) self.alive_inc = -1;
                self.morph_frame = @intCast(@as(i8, @intCast(self.morph_frame)) + self.alive_inc);
                if (self.state_ticks == ALIVE_TICKS) self.enter(.demorphing);
            },
            .demorphing => {
                if (self.morph_frame < EGG_FRAME) self.morph_frame += 1;
                if (self.state_ticks == DEMORPH_TICKS) self.enter(.in_egg);
            },
        }
    }

    fn enter(self: *Demo, state: MorphState) void {
        self.morph_state = state;
        self.state_ticks = 0;
    }

    // screen.js:301-304: seven dragons, one morph frame, 18 trajectory entries apart
    fn drawDragons(self: *Demo, fb: *LogicalFB) void {
        @memset(blit.Dst.plane(fb).buf, 0);
        const view = screenView(fb);
        const img = blit.Image.init(dragon_frames[self.morph_frame], DRAGON_W);
        for (0..NB_DRAGONS) |n| {
            const idx = self.drawn_tabpos + n * TRAIL;
            blit.blit(view, img, null, trajectory.x[idx % X_WRAP], trajectory.y[idx % Y_WRAP], 0, .copy);
        }
    }

    // scrolltext_horizontal.draw's movement: a letter that has left recycles to
    // the right, keeping its overshoot, and takes the next character.
    fn scrollStep(self: *Demo) void {
        for (&self.letters) |*l| {
            l.x -= SCROLL_SPEED;
            if (l.x > -FONT_W) continue;
            l.x = WIDE * FONT_W + (l.x + FONT_W);
            l.char = SCROLL_TEXT[self.scroffset];
            self.scroffset += 1;
            if (self.scroffset > SCROLL_TEXT.len - 1) self.scroffset = 0;
        }
    }

    // drawTile(dst, ltr - 32, posx, posy): letters are 64 canvas px apart, so
    // they never overlap and the draw order by posx does not matter.
    fn drawScrolltext(self: *Demo, fb: *LogicalFB) void {
        @memset(blit.Dst.plane(fb).buf, 0);
        const view = screenView(fb);
        const glyph_size = GLYPH_W * FONT_H;
        for (self.letters) |l| {
            const nb: usize = l.char - FONT_FIRST;
            const glyph = blit.Image.init(font_strip[nb * glyph_size ..][0..glyph_size], GLYPH_W);
            blit.blit(view, glyph, null, @divFloor(l.x, 2), SCROLL_Y, 0, .copy);
        }
    }
};
