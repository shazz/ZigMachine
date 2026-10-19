// --------------------------------------------------------------------------
// EQUINOX — RVF Honda intro. CODEF wab screen 015 (prototypes/codef/15/screen.js).
//
// The canvas is 640x456 = ST 320x228: a low-res screen with the BOTTOM BORDER
// open (`400+(28*2)`). Every plane is an overscan plane with its top and bottom
// bands opened; ST row 0 is physical row 40 (the normal visible top), so rows
// 200..227 — the lower scroller background and the scrolltext — sit in the
// bottom border at physical 240..267.
//
// Layers, in go()'s drawing order (one plane since pass 3, equinox_plane.zig):
//   roads       black fill, road2 on the odd bands, road1 on the even
//   backdrop    backtop, backscroll, the fading logo (palette ALPHA)
//   dragons     seven sprites sharing one morph frame
//   scrolltext
// The picture is drawn by CHISEL: changed road rows and the scroll band are copied
// from a BASE buffer (the plane without dragons and letters, in the never-enabled
// plane 1) that also restores what the dragons covered.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const merged = @import("equinox_plane.zig");

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

const VIS = 0; // the plane on screen
const BASE = 1; // never enabled: the screen without dragons and letters

fn screenView(fb: *LogicalFB) blit.Dst {
    return blit.Dst.plane(fb).window(SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H);
}

/// [x, x + w) clipped to the screen's columns: (first column, source skip, width).
fn clipX(x: i32, w: usize) ?struct { at: usize, skip: usize, n: usize } {
    const lo = @max(x, 0);
    const hi = @min(x + @as(i32, @intCast(w)), @as(i32, SCREEN_W));
    if (hi <= lo) return null;
    return .{ .at = @intCast(lo), .skip = @intCast(lo - x), .n = @intCast(hi - lo) };
}

// The band's two pictures (road1 / road2 under the backdrop and the logo), built in init.
var band_pics: [2][merged.BAND_ROWS * SCREEN_W]u8 = undefined;

// --------------------------------------------------------------------------
// Plane 0: roads (screen.js:270-289)
// --------------------------------------------------------------------------
const ROAD_Y: usize = merged.BAND_Y; // offset_y 226
const ROAD_FRAMES = 18;

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

// The bands of every frame tile the same ROAD_ROWS rows exactly (each offsets row
// sums to 170 canvas rows), so the road area is rewritten whole by the bands and
// the black fill under it never shows: the plane is cleared and filled once.
const ROAD_ROWS = merged.BAND_ROWS;
comptime {
    for (road_offsets) |row| {
        var sum: usize = 0;
        for (row) |h| sum += h;
        std.debug.assert(sum == 2 * ROAD_ROWS);
    }
}

/// Which road image each road row shows this frame: 1 = road1 (even bands), 2 = road2.
fn roadWanted(i: usize) [ROAD_ROWS]u8 {
    var want: [ROAD_ROWS]u8 = undefined;
    for (0..9) |band| {
        const top = road_sum[i][band] / 2;
        for (top..top + road_offsets[i][band] / 2) |r| want[r] = if (band % 2 == 1) 2 else 1;
    }
    return want;
}

// --------------------------------------------------------------------------
// The logo (screen.js:190-214, 292-297)
// --------------------------------------------------------------------------
const LOGO_PERIOD = 400; // `if(frames % 400 == 0) timeToShowLogo = 1`
const LOGO_STEP_FRAMES = 10; // alphaTime == 10

// --------------------------------------------------------------------------
// The dragons (screen.js:152-185, 216-268, 301-306)
// --------------------------------------------------------------------------
const NB_DRAGONS = 7;
const DRAGON_W = 32;
const DRAGON_H = 26;
// dragon1..dragon8 (64x52, halved); frame 7 is the egg, frame 0 the full dragon
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
// fonts.raw is NOT the 320x156 sheet: it is a STRIP of the 60 glyphs, 32x26
// each, in tile order (glyph k = sheet tile k = character 32 + k).
const font_strip = &merged.font_strip;
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
const Box = struct { x: i32 = 0, y: i32 = 0, w: usize = 0, h: usize = 0 };

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    // Every field is assigned in init(): a scene's struct defaults never run.
    frames: u32 = 0, // screen.js `frames`, starts at 1
    road_frame: usize = 0, // screen.js `counter`
    // the logo
    logo_showing: bool = false, // timeToShowLogo
    // screen.js's logoAlpha moves in whole tenths (+0.1, then -0.2, then +0.2 a step,
    // with a 1e-7 floor that only ever rounds the same way), so it is kept in tenths.
    logo_alpha: u8 = 0,
    logo_inc: i8 = 0,
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
    // The road image (1/2) each road row holds now, 0 = not drawn yet: a row is
    // copied again only when the band over it changed parity.
    road_src: [ROAD_ROWS]u8 = undefined,
    // Where each dragon was drawn last render, to restore just those boxes.
    dragon_box: [NB_DRAGONS]Box = undefined,
    pairs_tenths: u8 = 0xff, // the alpha step the logo's palette entries hold
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        zg.requestSong(MUSIC);

        self.frames = 1;
        self.road_frame = 0;
        self.logo_showing = false;
        self.logo_alpha = 0;
        self.logo_inc = 1;
        self.logo_ticks = 0;
        self.tabpos = 0;
        self.drawn_tabpos = 0;
        self.morph_state = .in_egg;
        self.morph_frame = EGG_FRAME;
        self.alive_inc = 1;
        self.state_ticks = 0;
        self.scroffset = 0;
        @memset(&self.road_src, 0);
        self.dragon_box = [_]Box{.{}} ** NB_DRAGONS;
        for (&self.letters, 0..) |*l, i| {
            l.* = .{ .x = WIDE * FONT_W + @as(i32, @intCast(i)) * FONT_W, .char = SCROLL_TEXT[self.scroffset] };
            self.scroffset += 1;
        }

        self.blitter.init();
        self.pairs_tenths = 0xff;
        const vis = &zigos.lfbs[VIS];
        vis.is_enabled = true;
        vis.openBorders(.top_bottom);
        merged.setPalette(vis.palette);
        self.setLogoAlpha(vis);
        const base = &zigos.lfbs[BASE];
        base.setOverscanBuffer(); // the same 400x280 geometry, never enabled
        buildBase(base);
        self.blitter.blitCopy(vis, 0, 0, base, 0, 0, @intCast(base.fb_w), @intCast(base.fb_h));
    }

    // The screen's static picture into BASE (the band as road1: its rows are all
    // rewritten by the first frame, road_src being 0), and the band's two pictures.
    fn buildBase(base: *LogicalFB) void {
        @memset(blit.Dst.plane(base).buf, merged.CLEAR);
        const view = screenView(base);
        // The road plane's black fill ran from the screen's first pixel to its last
        // at the overscan stride, so it also blackened the side columns between
        // (shown in the open bottom band): the same span here.
        @memset(view.buf[0 .. (view.h - 1) * view.stride + view.w], merged.ROAD_BLACK);
        for (0..SCREEN_H) |y| for (0..SCREEN_W) |x| {
            view.buf[y * view.stride + x] = merged.pixel(x, y, 0);
        };
        for (0..2) |r| for (0..ROAD_ROWS) |y| for (0..SCREEN_W) |x| {
            band_pics[r][y * SCREEN_W + x] = merged.pixel(x, ROAD_Y + y, r);
        };
    }

    // go(), screen.js:276-316, minus the drawing
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.road_frame = (self.road_frame + 1) % ROAD_FRAMES;
        if (self.frames % LOGO_PERIOD == 0) self.logo_showing = true;
        self.tickLogo();
        self.setLogoAlpha(&zigos.lfbs[VIS]);
        if (self.frames % MORPH_TICK == 0) self.tickMorph();
        self.drawn_tabpos = self.tabpos;
        self.tabpos += 1;
        self.scrollStep();
        self.frames += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const vis = &zigos.lfbs[VIS];
        const base = &zigos.lfbs[BASE];
        self.drawRoads(vis, base);
        self.drawDragons(vis, base);
        self.drawScrolltext(vis, base);
    }

    // screen.js:280-289: road2 on the odd bands, road1 on the even ones. Only the
    // runs of rows whose road image changed since the last frame are copied, into
    // BASE and onto the screen.
    fn drawRoads(self: *Demo, vis: *LogicalFB, base: *LogicalFB) void {
        const want = roadWanted(self.road_frame);
        var r: usize = 0;
        while (r < ROAD_ROWS) {
            if (want[r] == self.road_src[r]) {
                r += 1;
                continue;
            }
            var end = r + 1;
            while (end < ROAD_ROWS and want[end] == want[r] and self.road_src[end] != want[r]) end += 1;
            const src: []const u8 = &band_pics[want[r] - 1];
            const y: i16 = @intCast(SCREEN_Y + ROAD_Y + r);
            const n: u16 = @intCast(end - r);
            self.blitter.blitImage(base, SCREEN_X, y, src, SCREEN_W, 0, @intCast(r), SCREEN_W, n, null);
            self.blitter.blitImage(vis, SCREEN_X, y, src, SCREEN_W, 0, @intCast(r), SCREEN_W, n, null);
            @memset(self.road_src[r..end], want[r]);
            r = end;
        }
    }

    // showLogo(), screen.js:190-214
    fn tickLogo(self: *Demo) void {
        if (!self.logo_showing) return;
        self.logo_ticks += 1;
        if (self.logo_ticks != LOGO_STEP_FRAMES) return;
        const next: i8 = @as(i8, @intCast(self.logo_alpha)) + self.logo_inc;
        self.logo_alpha = @intCast(@max(next, 0));
        if (next >= 10) {
            self.logo_inc = -2;
            self.logo_alpha = 10;
        } else if (next < 1) {
            self.logo_inc = 2;
            self.logo_alpha = 0;
            self.logo_showing = false;
        }
        self.logo_ticks = 0;
    }

    // The logo is drawn every frame with globalAlpha = alpha. On the merged plane the
    // blend over the road is in the palette (equinox_plane.zig): rewritten when the
    // alpha steps, not every frame.
    fn setLogoAlpha(self: *Demo, fb: *LogicalFB) void {
        if (self.pairs_tenths == self.logo_alpha) return;
        merged.setLogoPairs(fb.palette, self.logo_alpha);
        self.pairs_tenths = self.logo_alpha;
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

    // screen.js:301-304: seven dragons, one morph frame, 18 trajectory entries apart.
    // Last frame's boxes are restored from BASE first, then all seven drawn keyed.
    fn drawDragons(self: *Demo, vis: *LogicalFB, base: *LogicalFB) void {
        for (self.dragon_box) |b| {
            const cx = clipX(b.x, b.w) orelse continue;
            const top: usize = @intCast(@max(b.y, 0));
            const bot: usize = @intCast(@min(b.y + @as(i32, @intCast(b.h)), @as(i32, SCREEN_H)));
            if (bot <= top) continue;
            const sx: i16 = @intCast(SCREEN_X + cx.at);
            const sy: i16 = @intCast(SCREEN_Y + top);
            self.blitter.blitCopy(vis, sx, sy, base, sx, sy, @intCast(cx.n), @intCast(bot - top));
        }
        const img: []const u8 = &merged.dragon_frames[self.morph_frame];
        for (0..NB_DRAGONS) |n| {
            const idx = self.drawn_tabpos + n * TRAIL;
            const x = trajectory.x[idx % X_WRAP];
            const y = trajectory.y[idx % Y_WRAP];
            self.blitDragon(vis, img, x, y);
            self.dragon_box[n] = .{ .x = x, .y = y, .w = DRAGON_W, .h = DRAGON_H };
        }
    }

    fn blitDragon(self: *Demo, vis: *LogicalFB, img: []const u8, x: i32, y: i32) void {
        const cx = clipX(x, DRAGON_W) orelse return;
        const top = @max(y, 0);
        const bot = @min(y + DRAGON_H, @as(i32, SCREEN_H));
        if (bot <= top) return;
        self.blitter.blitImage(vis, @intCast(SCREEN_X + cx.at), @intCast(SCREEN_Y + @as(usize, @intCast(top))), img, DRAGON_W, @intCast(cx.skip), @intCast(top - y), @intCast(cx.n), @intCast(bot - top), 0);
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
    // they never overlap and the draw order by posx does not matter. The band is
    // restored from BASE (the backscroll under it), then each tile drawn keyed and
    // clipped to the screen's columns, as the old plane's view clipped it.
    fn drawScrolltext(self: *Demo, vis: *LogicalFB, base: *LogicalFB) void {
        const y: i16 = @intCast(SCREEN_Y + SCROLL_Y);
        self.blitter.blitCopy(vis, SCREEN_X, y, base, SCREEN_X, y, SCREEN_W, FONT_H);
        const glyph_size = GLYPH_W * FONT_H;
        for (self.letters) |l| {
            const nb: usize = l.char - FONT_FIRST;
            const cx = clipX(@divFloor(l.x, 2), GLYPH_W) orelse continue;
            self.blitter.blitImage(vis, @intCast(SCREEN_X + cx.at), y, font_strip[nb * glyph_size ..][0..glyph_size], GLYPH_W, @intCast(cx.skip), 0, @intCast(cx.n), FONT_H, 0);
        }
    }
};
