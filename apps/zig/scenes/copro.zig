// --------------------------------------------------------------------------
// COPRO: BARD as a coprocessor (zg.bard.job, system table 1.24). BARD is the
// sound CPU; between its audio renders it runs the cart's jobs, so ZIGGY's
// frame keeps only the drawing. Four pages, each one effect and its job:
//   1   ZX0 DEPACK   a slideshow: the next picture depacked while one shows
//   2   3D MORPH     4096 dots, sphere to torus: morph, rotate, project
//   3   PARTICLES    4096 sparks: gravity, bounces, respawns
//   4   CRC-32       a 64 KB buffer checked every frame, an integrity map
//   Space           ZIGGY alone <-> the coprocessor (BARD on the board; on
//                   the page the loader serves the jobs after the frame)
//   Esc             back to the menu
// The music (TEX's NEO SHOW tune, an SNDH) plays on BARD all along: music and
// jobs share it. The HUD gives the A/B (copro/hud.zig). Every pixel is the
// same on both sides (the jobs' kernels are one source: libs/zig/bard_jobs/);
// apps/copro_check.mjs proves it.
// Integers only, per frame and in every job: BARD is rv32i + Zmmul (no
// divide, no FPU), and the reciprocal table is the cart's (copro/dots.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const job = zg.bard.job;
const C = @import("copro/common.zig");
const Hud = @import("copro/hud.zig").Hud;
const Slides = @import("copro/slides.zig").Slides;
const Dots = @import("copro/dots.zig").Dots;
const Sparks = @import("copro/sparks.zig").Sparks;
const CrcMap = @import("copro/crcmap.zig").CrcMap;

comptime {
    job.exportServer(); // bardJobServe: the page's loader serves the jobs through it
}

const K_ESC: u32 = 0xE012;
const MUSIC = "auf_weidersehen_monty_digi.sndh";
const NAMES = [_][]const u8{ @import("copro/slides.zig").NAME, @import("copro/dots.zig").NAME, @import("copro/sparks.zig").NAME, @import("copro/crcmap.zig").NAME };

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
            '1'...'4' => self.want_page = cp - '1',
            ' ' => self.want_where = if (self.want_where == .ziggy) .coprocessor else .ziggy,
            else => {},
        }
    }

    /// The host's digit switch (loader, glass, harnesses): 0..3 the page, 4 ZIGGY alone, 5 the coprocessor.
    pub fn setShadeMode(self: *Demo, m: u32) void {
        switch (m) {
            0...3 => self.want_page = m,
            4 => self.want_where = .ziggy,
            5 => self.want_where = .coprocessor,
            else => {},
        }
    }

    fn enter(self: *Demo, p: u32) void {
        self.page = p;
        switch (p) {
            0 => self.slides.enter(&self.ctx),
            1 => self.dots.enter(&self.ctx),
            2 => self.sparks.enter(&self.ctx),
            else => self.crc.enter(&self.ctx),
        }
    }

    fn leave(self: *Demo) void {
        switch (self.page) {
            0 => self.slides.leave(&self.ctx),
            1 => self.dots.leave(&self.ctx),
            2 => self.sparks.leave(&self.ctx),
            else => self.crc.leave(&self.ctx),
        }
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.hud.workStart();
        if (self.want_page != self.page or self.want_where != self.asked) {
            self.leave();
            if (self.want_where != self.asked) {
                self.asked = self.want_where;
                self.ctx.where = job.open(self.asked); // after every job in flight is answered
            }
            self.enter(self.want_page);
        }
        self.ctx.post_us = 0;
        self.ctx.wait_us = 0;
        switch (self.page) {
            0 => self.slides.frame(&self.ctx),
            1 => self.dots.frame(&self.ctx),
            2 => self.sparks.frame(&self.ctx),
            else => self.crc.frame(&self.ctx),
        }
        self.ctx.frame +%= 1;
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        const on_ziggy = self.ctx.where == .ziggy;
        self.hud.job(self.page, &self.ctx, on_ziggy);
        const side = if (on_ziggy) "ZIGGY" else if (self.ctx.job_cycles != 0) "BARD" else "HOST";
        self.hud.draw(zigos, self.ctx.fb, self.page, NAMES[self.page], side);
        self.hud.workEnd();
    }
};
