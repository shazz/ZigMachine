// whichpart 1 -- SYNC SCREEN #1 (screen.js do_sync1), back to front:
//   rasters.png at y 181; five redraster.png bars at 150-130*sin(y1 + c*0.044),
//     c = 0.6 3.6 6.6 9.9 13.2, squashed 0.5 0.6 0.7 0.8 1; whiteraster.png at y 40
//     -- all ST-legal colours, uniform rows: REAL rasters here, colour 0 per line
//     (frame.zig), running into the borders as colour 0 does on an ST;
//   the banner (SYNC logo / the four faces) squashing on XX, tile flipping at XX <= 0;
//   the scroller: a sine scroller, or (on the text's '\' / ']' codes) the same
//     text flipping on `flip`, and bouncing (fx 2); '_' goes back to the sine;
//   the Redhead logo, FX sinx then siny (sync1_draw.zig).
// Every constant is screen.js's; the state persists across visits, as its globals do.
const frame = @import("frame.zig");
const gen = @import("assets_gen.zig");
const texts = @import("texts.zig");
const sc = @import("scroller.zig");
const fx = @import("fx.zig");
const draw = @import("sync1_draw.zig");

const DELTA_OFFSETBARS: f64 = 0.044;
const BAR_PHASE = [5]f64{ 0.6, 3.6, 6.6, 9.9, 13.2 };
const BAR_SQUASH = [5]f64{ 0.5, 0.6, 0.7, 0.8, 1 };

pub const Sync1 = struct {
    y1: f64,
    xx: f64, // XX
    size: f64,
    tile: i32,
    flip: f64,
    flipinc: f64,
    bounce: f64,
    bounceinc: f64,
    fx_mode: u8, // `fx`
    scroll: sc.Scroller, // myscrolltext (sine), into sscrollcanvas
    scroll2: sc.Scroller, // myscrolltext2, into sscrollcanvas2
    fx1: fx.Fx(2),
    fx2: fx.Fx(2),

    pub fn init(self: *Sync1) void {
        self.y1 = 100;
        self.xx = 1;
        self.size = 0.05;
        self.tile = 0;
        self.flip = 1;
        self.flipinc = -0.5;
        self.bounce = 0;
        self.bounceinc = 2;
        self.fx_mode = 0;
        self.scroll.init(texts.sync1, 32, 520, 4, .{ .value = 0, .amp = 45, .inc = 0.6, .offset = 0.08 });
        self.scroll2.init(texts.sync1, 32, 520, 4, null);
        self.fx1 = .{ .p = .{ .{ .value = 0, .amp = -20, .inc = 0.03, .offset = -0.05 }, .{ .value = 0, .amp = 10, .inc = 0.01, .offset = 0.08 } } };
        self.fx2 = .{ .p = .{ .{ .value = 0, .amp = 10, .inc = 0.03, .offset = -0.05 }, .{ .value = 0, .amp = 10, .inc = 0.01, .offset = 0.08 } } };
    }

    /// One do_sync1(): draw with the current state, then advance it.
    pub fn step(self: *Sync1) void {
        // the rasters are colour 0: colour0() drew them from this y1 last frame
        draw.banner(self.tile, self.xx);
        self.xx = self.xx - self.size;
        if (self.xx <= 0) {
            self.size = -0.05;
            self.tile += 1;
        }
        if (self.xx >= 1) self.size = 0.05;
        if (self.tile >= 2) self.tile = 0;

        self.scroll.advance();
        self.scroll2.advance();
        switch (self.scroll.current()) {
            '\\' => self.fx_mode = 1,
            ']' => self.fx_mode = 2,
            '_' => self.fx_mode = 0,
            else => {},
        }
        self.drawScroll();
        draw.logo(&self.fx1, &self.fx2);
        self.y1 += DELTA_OFFSETBARS;
    }

    fn drawScroll(self: *Sync1) void {
        switch (self.fx_mode) {
            0 => draw.scroller(&self.scroll, .{ .y = 220, .flip = 1, .plain = true }),
            1 => {
                draw.scroller(&self.scroll, .{ .y = 215, .flip = self.flip, .plain = false });
                self.stepFlip();
            },
            else => {
                draw.scroller(&self.scroll2, .{ .y = 200 + self.bounce, .flip = self.flip, .plain = false });
                self.stepFlip();
                self.bounce += self.bounceinc;
                if (self.bounce >= 40) self.bounceinc = -2;
                if (self.bounce <= 0) self.bounceinc = 2;
            },
        }
    }

    fn stepFlip(self: *Sync1) void {
        self.flip += self.flipinc;
        if (self.flip <= -1) self.flipinc = 0.05;
        if (self.flip >= 1) self.flipinc = -0.05;
    }

    /// Colour 0 per line for the frame the CURRENT state draws: the rasters,
    /// back to front, sampled at 640-row 2Y (+0.5, nearest).
    pub fn colour0(self: *const Sync1, table: *[frame.PH]u32) void {
        @memset(table, frame.BLACK);
        var y: i32 = 0;
        while (y < 225) : (y += 1) frame.setC0(table, y, self.rasterAt(y));
    }

    fn rasterAt(self: *const Sync1, y: i32) u32 {
        const r: i32 = 2 * y;
        const rc: f64 = @as(f64, @floatFromInt(r)) + 0.5;
        var c: u32 = frame.BLACK;
        if (r >= 181 and r < 181 + gen.rasters_rows.len) c = gen.rasters_rows[@intCast(r - 181)];
        for (BAR_PHASE, BAR_SQUASH) |ph, h| {
            const yc = 150 - 130 * @sin(self.y1 + ph * DELTA_OFFSETBARS);
            const s = @floor((rc - yc) / h + 13);
            if (s >= 0 and s < 26) c = gen.redraster_rows[@intFromFloat(s)];
        }
        if (r >= 40 and r < 40 + gen.whiteraster_rows.len) c = gen.whiteraster_rows[@intCast(r - 40)];
        return c;
    }
};
