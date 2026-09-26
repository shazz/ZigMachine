// --------------------------------------------------------------------------
// ULM (Unlimited Matricks) — the 3615 GEN4 contest screen, by The Fate.
//
// Ported from the CODEF HTML5 remake (wab.com screen 539, MIT). Graphics by
// French Kiss, font by Grace Jones, the 3D logo curves by Gunstick, code,
// scrolltext and music by The Fate: all theirs. Music: "3615 Gen4 Demo (Thrust
// Remix)" by The Fate, the remake's own SNDH (docs/music/3615_gen4_demo.sndh).
//
// Reference: prototypes/codef/539/ (tools/fetch_codef.py 539). Assets:
// tools/private_tools/gen4_3615_assets.py and gen4_3615_tables.mjs.
//
// GEOMETRY. The remake's canvas is 768x540 = 384x270 ST pixels, doubled: a
// full-overscan screen ("ALL THIS SCREEN IS IN OVERSCAN", says the text) whose
// art starts 30 lines down and reaches line 264. The text also says the one
// border it keeps is the TOP one, so canvas line 30 (the GEN4 logo's top) is
// put on the first line of the normal display, physical row 40: the canvas
// then fills rows 10..279 exactly, nothing is drawn above row 40, and the
// bottom and side borders are open. Horizontally the 384 columns are centred
// in the 400-wide plane (x + 8). One overscan plane, borders opened by the
// copper's own HBL.
//
// What go() draws, back to front (screen.js:155-167):
//   1. damier(): a sky (a 45-colour pattern) and a 3D chessboard floor
//      (a 1280x512 board scrolled on a Lissajous, drawn a row at a time with a
//      growing zoom), darkened near the horizon by nine shadow bands.
//   2. dancingFate(): 113 slices of THE FATE's logo on one of six 3D curves.
//   3. scroller(): 'destination-in' with the big ULM font: all of the above
//      survives only inside the letters (gen4_3615/scroller.zig).
//   4. vueMeters(): three bars from the YM volumes (sc68_vumeter.js).
//   5. dancingUlm(): the ULM logo, each row shifted by initDistort()'s table.
//   6. motifMoche(): a 24x24 tile pattern behind WHO ELSE?, each line shifted
//      by mocheDist, the whole walked up and down by a sine.
//   7. potiches(): 3615 twice, GEN4, the two side bars, WHO ELSE?.
// The sky, the VU colours and the floor shading are REAL rasters here
// (gen4_3615/rasters.zig), their colours on the ST register grid rather than
// the browser's #RGB x17. Every table and increment is screen.js's own; the
// frame matches the remake run in Chrome at canvas (2X, 2Y), those colours
// aside — apps/gen4_3615_headless.mjs replays screen.js and compares.
//
// No depacker intro to skip: screen.js starts on the screen itself.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const blit = zg.blit;
const copper = zg.copper;

const A = @import("gen4_3615/assets.zig");
const rasters = @import("gen4_3615/rasters.zig");
const Fate = @import("gen4_3615/fate.zig").Fate;
const Scroller = @import("gen4_3615/scroller.zig").Scroller;

// The remake's own SNDH (ICE-packed; prototypes/sndh_lf/The_Fate/3615_Gen4_Demo.sndh
// is the same tune unpacked, identical YM registers after 1 s), FLAG ~y.
const MUSIC = "3615_gen4_demo.sndh";

const PLANE = 0;
// the 384x270 canvas inside the 400x280 plane
const CANVAS_X = 8;
const CANVAS_Y = 10;
const CANVAS_W = 384;
const CANVAS_H = 270;

// dancingUlm: ulmHeight, ulmWidth; logo row r lands at canvas y 140 + r, rows 1..121
const ULM_H = 122;
const ULM_TOP = 71; // ST line of logo row 2, the first on an even canvas row
const ULM_BOTTOM = 130; // logo row 120; row 0 is never drawn, 122 is outside the image
// motifMoche: mocheSpeed, 32 strips of 2 rows at (140, 466), 472 wide
const MOCHE_SPEED: f64 = 0.04;
const MOCHE_X = 70;
const MOCHE_Y = 233;
const MOCHE_W = 236;
const MOCHE_LINES = 32;
// vueMeters: bars 192 wide at vuPos = [0, 448, 224] from x 58; levels[0] is voice 3
const VU_X = [3]i32{ 29, 29 + 224, 29 + 112 };
const VU_W = 96;
const VU_VOICE = [3]usize{ 2, 1, 0 }; // YM channel (C, B, A) behind levels[id]
// potiches(): placement, halved
const Placed = struct { img: blit.Image, x: i32, y: i32 };
const placement = [_]Placed{
    .{ .img = A.minitel, .x = 81, .y = 41 },
    .{ .img = A.minitel, .x = 258, .y = 41 },
    .{ .img = A.gen4, .x = 130, .y = 30 },
    .{ .img = A.bord, .x = 0, .y = 134 },
    .{ .img = A.bord, .x = 364, .y = 134 },
    .{ .img = A.whoelse, .x = 70, .y = 233 },
};

const palette: [256]Color = blk: {
    var p = A.palette;
    p[A.VU_INK] = rasters.BLACK;
    p[A.SKY_INK] = rasters.BLACK;
    p[A.CHECK_DARK] = rasters.check_dark;
    p[A.CHECK_LIGHT] = rasters.check_light;
    p[A.SHADOW_BARE] = rasters.shadow_bare;
    for (p[1..A.ART_MAX]) |c| std.debug.assert(c.a == 255 or c.a == 0);
    break :blk p;
};

pub const Demo = struct {
    scroller: Scroller,
    fate: Fate,
    ulm_ctr: usize,
    ulm_drawn: usize,
    moche_ctr: f64,
    moche_y: f64,
    moche_dist_ctr: usize,
    moche_drawn: usize,
    last_vol: [3]f64, // sc68_vumeter.js _lastVol1..3
    levels: [3]i32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here.
        self.scroller.init();
        self.fate.init();
        self.ulm_ctr = 0;
        self.ulm_drawn = 0;
        self.moche_ctr = 0;
        self.moche_y = 0;
        self.moche_dist_ctr = 0;
        self.moche_drawn = 0;
        self.last_vol = @splat(0);
        self.levels = @splat(0);

        zg.requestSong(MUSIC);
        zigos.setBackgroundColor(rasters.BLACK);
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all);
        fb.setPalette(palette);
        // one HBL: the borders' flicker AND the four rasters
        copper.install(fb, &rasters.SLOTS, &rasters.tables, .{ .flicker = true });
        rasters.build(fb, CANVAS_Y);
        fb.clearFrameBuffer(0);
    }

    /// go()'s state, advanced in go()'s order, keeping what each part draws.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.scroller.stepFloor();
        self.fate.step();
        self.scroller.step(&self.fate);
        self.stepVu(&zigos.ym_regs);

        self.ulm_drawn = self.ulm_ctr;
        self.ulm_ctr += 2;
        if (self.ulm_ctr > A.ULM_DIST_LEN - ULM_H) self.ulm_ctr = 0;

        self.moche_y = @rem(84 + 84 * @sin(self.moche_ctr), 24);
        self.moche_drawn = self.moche_dist_ctr;
        self.moche_ctr += MOCHE_SPEED;
        self.moche_dist_ctr += 1;
        if (self.moche_dist_ctr > A.moche_dist.len - MOCHE_LINES) self.moche_dist_ctr = 0;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        fb.clearFrameBuffer(0);
        const canvas = blit.Dst.plane(fb).window(CANVAS_X, CANVAS_Y, CANVAS_W, CANVAS_H);
        self.scroller.render(canvas, &self.fate);
        self.drawVu(canvas);
        self.drawUlm(canvas);
        self.drawMoche(canvas);
        for (placement) |p| blit.blit(canvas, p.img, null, p.x, p.y, 0, .copy);
    }

    /// getVolumeVoiceN: max(vol * 100 / 15, last * 0.9), the volume register's
    /// low nibble; then levels fall 6 a frame (screen.js:351-365).
    fn stepVu(self: *Demo, regs: *const [16]u8) void {
        for (&self.last_vol, regs[8..11]) |*last, reg| {
            const v: f64 = @floatFromInt(reg & 0xf);
            last.* = @max(v * 100 / 0xf, last.* * 0.9);
        }
        for (&self.levels, VU_VOICE) |*level, voice| {
            const v: i32 = @intFromFloat(@trunc(self.last_vol[voice] * 1.8));
            level.* = if (level.* < v) v else @max(level.* - 6, 0);
        }
    }

    /// fillRect(x, 180, 192, -level) on the meter canvas: a bar grows up from
    /// its row 179. Every lit line is VU_INK; the copper colours it.
    fn drawVu(self: *const Demo, canvas: blit.Dst) void {
        for (self.levels, VU_X) |level, x| {
            for (0..rasters.VU_ROWS) |k| {
                if (@as(i32, @intCast(2 * k)) < 180 - level) continue;
                const row = (rasters.VU_TOP + k) * canvas.stride + @as(usize, @intCast(x));
                @memset(canvas.buf[row..][0..VU_W], A.VU_INK);
            }
        }
    }

    /// Canvas row 140 + r shows logo row r at x = ulmDistTable[ulmCtr + r]:
    /// halved, logo column (2X - x) >> 1 = X - ceil(x / 2).
    fn drawUlm(self: *const Demo, canvas: blit.Dst) void {
        for (ULM_TOP..ULM_BOTTOM + 1) |Y| {
            const r = 2 * Y - 140;
            const x = A.ulmDist(self.ulm_drawn + r);
            const part = blit.Rect{ .x = 0, .y = r >> 1, .w = A.ulm.w, .h = 1 };
            blit.blit(canvas, A.ulm, part, @divFloor(x + 1, 2), @intCast(Y), 0, .copy);
        }
    }

    /// Strip k (ST line 233 + k) samples the pattern at source row
    /// floor(y + 2k + 0.5) and column 2X - 140 + round(mocheDist[ctr - k]).
    fn drawMoche(self: *const Demo, canvas: blit.Dst) void {
        for (0..MOCHE_LINES) |k| {
            // mocheDistCtr reaches mocheDist.length - 32 (the wrap test is >), so
            // strip 0 reads one past the table once a lap: undefined in the JS,
            // and drawImage given NaN draws nothing. Skip it the same way.
            const at = self.moche_drawn + MOCHE_LINES - k;
            if (at >= A.moche_dist.len) continue;
            const fk: f64 = @floatFromInt(2 * k);
            const v: usize = @intFromFloat(@floor(self.moche_y + fk + 0.5));
            const src = A.moche.data[((v % 24) >> 1) * A.moche.w ..][0..A.moche.w];
            const shift: usize = A.moche_dist[at];
            const out = canvas.buf[(MOCHE_Y + k) * canvas.stride + MOCHE_X ..][0..MOCHE_W];
            for (out, 0..) |*p, i| p.* = src[((2 * i + shift) % 24) >> 1];
        }
    }
};
