// --------------------------------------------------------------------------
// COPRO: the coprocessors. BARD (zg.bard.job), the sound CPU, runs the cart's
// integer jobs between its audio renders; ASTROLABE (zg.astro, env.hwAstro),
// the ARM's VFPv3, runs its f64 batches. Six pages, each one effect and its job:
//   1   ZX0 DEPACK   a slideshow: the next picture depacked while one shows
//   2   3D MORPH     4096 dots, sphere to torus: morph, rotate, project
//   3   PARTICLES    4096 sparks: gravity, bounces, respawns
//   4   CRC-32       a 64 KB buffer checked every frame, an integrity map
//   5   F64 ZOOM     a Mandelbrot zoom to 1e-13 in batched vector ops (ASTRO)
//   6   F64 CLOTH    a 16 x 16 cloth solved implicitly by LINPACK each frame (ASTRO)
//   Space           ZIGGY alone <-> the coprocessor (BARD / ASTROLABE on the
//                   board; on the page the loader serves BARD's jobs after the
//                   frame and the machine computes ASTROLABE's batches). Pages
//                   5-6 on ZIGGY are its soft f64 (copro/soft64.zig): the same bits
//   Esc             back to the menu
// The music (TEX's NEO SHOW tune, an SNDH) plays on BARD all along: music and
// jobs share it. The HUD gives the A/B (copro/hud.zig). Every pixel is the
// same on both sides (the jobs' kernels are one source: libs/zig/bard_jobs/);
// apps/copro_check.mjs proves it.
// Integers only, per frame and in every BARD job: BARD is rv32i + Zmmul (no
// divide, no FPU), and the reciprocal table is the cart's (copro/dots.zig).
// Pages 5-6 put f64 on ASTROLABE (or, for the A side, ZIGGY's soft f64 on
// purpose); ZIGGY's own per-frame work there reads the f64 bits as integers.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const job = zg.bard.job;
const C = @import("copro/common.zig");
const Hud = @import("copro/hud.zig").Hud;
const Slides = @import("copro/slides.zig").Slides;
const Dots = @import("copro/dots.zig").Dots;
const Sparks = @import("copro/sparks.zig").Sparks;
const CrcMap = @import("copro/crcmap.zig").CrcMap;
const Zoom = @import("copro/deepzoom.zig").Zoom;
const Cloth = @import("copro/cloth.zig").Cloth;

comptime {
    job.exportServer(); // bardJobServe: the page's loader serves the jobs through it
}

const K_ESC: u32 = 0xE012;
const MUSIC = "auf_weidersehen_monty_digi.sndh";
const NAMES = [_][]const u8{ @import("copro/slides.zig").NAME, @import("copro/dots.zig").NAME, @import("copro/sparks.zig").NAME,
    @import("copro/crcmap.zig").NAME, @import("copro/deepzoom.zig").NAME, @import("copro/cloth.zig").NAME };
const FIELDS = .{ "slides", "dots", "sparks", "crc", "zoom", "cloth" };
const ASTRO_PAGE: u32 = 4; // pages from here on are ASTROLABE's

pub const Demo = struct {
    ctx: C.Ctx = undefined,
    hud: Hud = .{},
    page: u32 = 0,
    want_page: u32 = 0,
    want_where: job.Where = .coprocessor,
    asked: job.Where = .coprocessor, // what the jobs were last opened for (ctx.where: what answered)
    slides: Slides = .{},
    dots: Dots = .{},
    sparks: Sparks = .{},
    crc: CrcMap = .{},
    zoom: Zoom = .{},
    cloth: Cloth = .{},
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        self.* = .{};
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(C.HUD_BG, .{ .r = 16, .g = 16, .b = 32, .a = 255 });
        fb.setPaletteEntry(C.HUD_INK, .{ .r = 150, .g = 170, .b = 200, .a = 255 });
        fb.setPaletteEntry(C.HUD_HI, .{ .r = 255, .g = 230, .b = 120, .a = 255 });
        fb.setPaletteEntry(C.HUD_DIM, .{ .r = 80, .g = 90, .b = 110, .a = 255 });
        @memset(fb.fb[C.ROWS * C.W .. 200 * C.W], C.HUD_BG);
        self.ctx = .{ .os = zigos, .fb = fb };
        self.ctx.where = job.open(.coprocessor);
        zg.requestSong(MUSIC);
        self.enter(0);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            '1'...'6' => self.want_page = cp - '1',
            ' ' => self.want_where = if (self.want_where == .ziggy) .coprocessor else .ziggy,
            else => {},
        }
    }

    /// The host's digit switch (loader, glass, harnesses): 0..5 the page, 6 ZIGGY alone, 7 the coprocessor.
    pub fn setShadeMode(self: *Demo, m: u32) void {
        switch (m) {
            0...5 => self.want_page = m,
            6 => self.want_where = .ziggy,
            7 => self.want_where = .coprocessor,
            else => {},
        }
    }

    /// The page's `method` (enter, frame, leave): every page is a field named in FIELDS.
    fn call(self: *Demo, comptime method: []const u8) void {
        inline for (FIELDS, 0..) |name, i| {
            if (self.page == i) {
                const pg = &@field(self, name);
                @field(@TypeOf(pg.*), method)(pg, &self.ctx);
            }
        }
    }

    fn enter(self: *Demo, p: u32) void {
        self.page = p;
        self.ctx.job_cycles = 0;
        self.ctx.astro_arm = false;
        self.call("enter");
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.hud.workStart();
        if (self.want_page != self.page or self.want_where != self.asked) {
            self.call("leave");
            if (self.want_where != self.asked) {
                self.asked = self.want_where;
                self.ctx.where = job.open(self.asked); // after every job in flight is answered
                self.ctx.asked = self.asked;
            }
            self.enter(self.want_page);
        }
        self.ctx.post_us = 0;
        self.ctx.wait_us = 0;
        self.call("frame");
        self.ctx.frame +%= 1;
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        const astro = self.page >= ASTRO_PAGE;
        const on_ziggy = if (astro) self.asked == .ziggy else self.ctx.where == .ziggy;
        self.hud.job(self.page, &self.ctx, on_ziggy);
        // ASTRO: the ARM served it; SOFT: a board without the ARM (hwAstro's fallback, ZIGGY's soft f64).
        const side = if (on_ziggy) "ZIGGY" else if (astro and self.ctx.astro_arm) "ARM" else if (self.ctx.job_cycles != 0)
            (if (astro) "SOFT" else "BARD") else "HOST";
        self.hud.draw(zigos, self.ctx.fb, self.page, NAMES[self.page], side, if (astro) "ASTRO" else "BARD");
        self.hud.workEnd();
    }
};
