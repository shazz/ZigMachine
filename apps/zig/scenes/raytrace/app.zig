// The ray-traced scene as a cart: one true-colour picture, three maths.
//
//   key 1  FIXED  Q16.16 integers on ZIGGY (fixed.zig): the board CPU's own speed
//   key 2  F32    f32 on ZIGGY (float.zig): soft-float on the board, the FPU on its FPU build
//   key 3  ASTRO  f64 on ASTROLABE, the ARM's VFPv3 on the board (astro/): rays in
//                 batches, every step of the march one call of vector descriptors
// Each key restarts the render in that mode; Fire (Space/Enter) restarts the current one.
// No key() and no ownsKeyboard(): Escape falls through to demo_main.zig's way out.
//
// Every mode takes the same 16 samples a pixel (work.zig: the first picture coarse to
// fine, then 15 refinement passes of sub-pixel jitter and a soft-shadow light disc),
// sums them per pixel as integer RGB (colour.zig: the converged picture does not depend
// on how the work was sliced into frames) and shows the running mean in RGB565.
//
// Music: none, on purpose. This screen is the FPGA CPU benchmark, and an SNDH would
// add the 68000 player's work to the number it is there to measure.
//
// Frame budget: bench.zig. With the host's clock a frame works for a fixed TIME and
// the HUD reports the first picture's pixels per second and the time to converge;
// without one it takes a fixed number of samples.
const zg = @import("zigos");
const trace = @import("trace.zig");
const hud = @import("hud.zig");
const bench = @import("bench.zig");
const colour = @import("colour.zig");
const work = @import("work.zig");
const astro = @import("astro/engine.zig");
const Shade = @import("shade.zig").Shade;

const ZigOS = zg.ZigOS;
const DIR_FIRE: u8 = 5;
const Fixed = trace.Tracer(@import("fixed.zig"));
const Float = trace.Tracer(@import("float.zig"));

pub const Mode = enum(u8) { fixed, f32, astro };
const ZIGGY_CHUNK: u32 = 16; // samples between clock reads on ZIGGY

pub const Demo = struct {
    fb: zg.tc.Fb,
    acc: []colour.Acc,
    work: work.Work,
    eng: astro.Engine,
    mode: Mode,
    pending: ?Mode, // a key arrived (setShadeMode/input() have no ZigOS to redraw with)
    stats: trace.Stats, // the first picture's rays
    more: trace.Stats, // the refinement's, kept out of the benchmark's
    bench: bench.Bench,
    frames: u32,
    items: [astro.BATCH]work.Item,
    shades: [astro.BATCH]Shade,

    const Self = @This();

    pub fn init(self: *Self, zigos: *ZigOS) void {
        self.bench.clocked = false;
        self.pending = null;
        self.mode = .fixed;
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        for (&zigos.lfbs) |*p| p.is_enabled = false;
        const plane = &zigos.lfbs[0];
        self.fb = plane.setTruecolorPlane(.window);
        plane.is_enabled = true;
        self.acc = zg.mem.mustAlloc(colour.Acc, work.TOTAL);
        self.eng.init();
        self.restart(zigos);
    }

    fn restart(self: *Self, zigos: *ZigOS) void {
        self.work.start();
        self.stats = .{ .rays = 0 };
        self.more = .{ .rays = 0 };
        self.bench.reset();
        self.frames = 0;
        self.fb.fill(hud.PANEL);
        hud.draw(zigos, self.fb, self.counters());
    }

    /// Keys 1..3 (the host's setShadeMode 0..2): that mode, from the start.
    pub fn setShadeMode(self: *Self, m: u32) void {
        if (m <= @intFromEnum(Mode.astro)) self.pending = @enumFromInt(m);
    }

    pub fn input(self: *Self, dir: u8) void {
        if (dir == DIR_FIRE) self.pending = self.mode;
    }

    pub fn update(self: *Self, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const m = self.pending orelse return;
        self.pending = null;
        self.mode = m;
        self.restart(zigos);
    }

    pub fn render(self: *Self, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.work.converged()) return;
        self.frames += 1;
        const first = self.work.pass == 0;
        if (self.bench.begin()) |t0| {
            while (self.chunk()) {
                if (self.bench.spent(t0, first)) break;
            } else self.bench.finish(t0, first);
        } else {
            var n: u32 = 0;
            while (n < bench.FIXED_PIXELS and self.chunk()) n += self.chunkLen();
        }
        hud.draw(zigos, self.fb, self.counters());
    }

    fn chunkLen(self: *const Self) u32 {
        return if (self.mode == .astro) astro.BATCH else ZIGGY_CHUNK;
    }

    /// One chunk of samples, traced and shown; false once its pass has ended.
    fn chunk(self: *Self) bool {
        const p = self.work.pass;
        const n = self.work.take(self.items[0..self.chunkLen()]);
        const items = self.items[0..n];
        const st = if (p == 0) &self.stats else &self.more;
        switch (self.mode) {
            .fixed => for (items, 0..) |it, i| {
                self.shades[i] = Fixed.sample(st, it.x, it.y, it.j);
            },
            .f32 => for (items, 0..) |it, i| {
                self.shades[i] = Float.sample(st, it.x, it.y, it.j);
            },
            .astro => self.eng.trace(items, self.shades[0..n], st),
        }
        for (items, self.shades[0..n]) |it, s| self.show(p, it, colour.of(s));
        return self.work.pass == p;
    }

    /// Sums a sample into its pixel and shows the pixel's mean (pass 0: over its cell).
    fn show(self: *Self, pass: u32, it: work.Item, c: colour.Rgb) void {
        const a = &self.acc[@as(u32, it.y) * trace.IMG_W + it.x];
        if (pass == 0) a.* = colour.first(c) else colour.add(a, c);
        const l = colour.level(a.*, pass + 1);
        const y1 = @min(@as(u32, it.y) + it.size, trace.IMG_H);
        var y: u32 = it.y;
        while (y < y1) : (y += 1) {
            const row = self.fb.row(y);
            var x: u32 = it.x;
            while (x < @as(u32, it.x) + it.size) : (x += 1) row[x] = colour.pixel(l, x, y);
        }
    }

    fn counters(self: *const Self) hud.Counters {
        const first_px = if (self.work.pass == 0) self.work.first else work.TOTAL;
        return .{
            .name = self.name(),
            .frames = self.frames,
            .rays = self.stats.rays,
            .done = self.work.pass > 0,
            .passes_done = self.work.pass,
            .passes = work.PASSES,
            .samples = self.work.taken(),
            .total = work.PASSES * work.TOTAL,
            .clocked = self.bench.clocked,
            .px_per_s = self.bench.pixelsPerSecond(first_px),
            .conv_ms = @intCast(@min(self.bench.totalMicros() / 1000, 0xFF_FFFF)),
        };
    }

    fn name(self: *const Self) []const u8 {
        return switch (self.mode) {
            .fixed => "1 FIXED Q16.16 ON ZIGGY",
            .f32 => "2 F32 FLOAT ON ZIGGY",
            .astro => switch (self.eng.side()) {
                .arm => "3 F64 MATHS ON THE ARM",
                .soft => "3 F64 ASTRO: ZIGGY (NO ARM)",
                .host => "3 F64 ASTROLABE (HOST)",
                .failed => "3 F64 ASTROLABE FAILED",
            },
        };
    }
};
