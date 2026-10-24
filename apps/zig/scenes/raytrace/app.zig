// The ray-traced scene as a cart: Demo(M) for a number back-end M.
//
// Music: none, on purpose. This screen is also the FPGA CPU benchmark, and an
// SNDH would add the 68000 player's work to the number it is there to measure.
//
// Frame budget: bench.zig. With the host's clock a frame traces for a fixed
// TIME, in the order of progress.zig, and the HUD reports pixels per second;
// without one it traces a fixed number of pixels. Either way the picture
// simply takes more frames on a slower machine.
//
// Refinement: a back-end that declares REFINE (float.zig: the FPU cart) keeps
// going once the picture is complete, PASSES - 1 more samples a pixel, each
// pass sliced over frames on the same budget (refine.zig). The benchmark
// counters (rays, rate, the DONE bit) stay those of the first picture.
//
// Keys: Fire (Space/Enter) restarts the run. No key() and no ownsKeyboard() on
// purpose: Escape then falls through to demo_main.zig's way out for a scene
// that handles no keys, back to the menu.
const zg = @import("zigos");
const trace = @import("trace.zig");
const P = @import("palette.zig");
const hud = @import("hud.zig");
const bench = @import("bench.zig");
const Progress = @import("progress.zig").Progress;
const refine = @import("refine.zig");

const ZigOS = zg.ZigOS;

const TOTAL_PIXELS = trace.IMG_W * trace.IMG_H;
const DIR_FIRE: u8 = 5;

pub fn Demo(comptime M: type) type {
    const Tracer = trace.Tracer(M);
    const REFINE = @hasDecl(M, "REFINE") and M.REFINE;
    const Ref = if (REFINE) refine.Refine(M) else void;
    const PASSES: u32 = if (REFINE) Ref.PASSES else 1;
    return struct {
        progress: Progress,
        ref: Ref,
        stats: trace.Stats,
        bench: bench.Bench,
        frames: u32,
        pixels: u32,
        done: bool,
        restart_pending: bool, // Fire arrived (input() has no ZigOS to redraw with)

        const Self = @This();

        pub fn init(self: *Self, zigos: *ZigOS) void {
            self.bench.clocked = false;
            self.restart_pending = false;
            zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
            const fb = &zigos.lfbs[0];
            fb.is_enabled = true;
            P.install(fb);
            if (REFINE) self.ref.init();
            self.restart(zigos);
        }

        fn restart(self: *Self, zigos: *ZigOS) void {
            self.progress.start();
            self.stats = .{ .rays = 0 };
            self.bench.reset();
            self.frames = 0;
            self.pixels = 0;
            self.done = false;
            if (REFINE) self.ref.restart();
            const fb = &zigos.lfbs[0];
            fb.clearFrameBuffer(P.PANEL);
            hud.draw(zigos, fb, M.NAME, self.counters());
        }

        pub fn input(self: *Self, dir: u8) void {
            if (dir == DIR_FIRE) self.restart_pending = true;
        }

        pub fn update(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = dt;
            if (!self.restart_pending) return;
            self.restart_pending = false;
            self.restart(zigos);
        }

        pub fn render(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = dt;
            if (self.done and (!REFINE or self.ref.converged())) return;
            const fb = &zigos.lfbs[0];
            self.frames += 1;
            if (self.done) {
                if (REFINE) self.refineSome(fb);
            } else if (self.bench.begin()) |t0| {
                while (self.traceSome(fb, bench.CHECK_EVERY)) {
                    if (self.bench.spent(t0)) break;
                } else self.bench.finish(t0);
            } else _ = self.traceSome(fb, bench.FIXED_PIXELS);
            hud.draw(zigos, fb, M.NAME, self.counters());
        }

        /// One frame's share of the refinement, on the tracing budget but
        /// booked outside the benchmark's time.
        fn refineSome(self: *Self, fb: *zg.LogicalFB) void {
            if (self.bench.begin()) |t0| {
                while (self.ref.step(fb, bench.CHECK_EVERY)) {
                    if (bench.over(t0)) break;
                }
            } else _ = self.ref.step(fb, bench.FIXED_PIXELS);
        }

        /// Traces up to `max` pixels; false once the picture is complete.
        fn traceSome(self: *Self, fb: *zg.LogicalFB, max: u32) bool {
            var n: u32 = 0;
            while (n < max) : (n += 1) {
                const cell = self.progress.next() orelse break;
                const s = Tracer.centre(&self.stats, cell.x, cell.y);
                paint(fb, cell, P.index(s, P.bayer(cell.x, cell.y)));
                if (REFINE) self.ref.record(cell.x, cell.y, s);
                self.pixels += 1;
            }
            // The last pixel ends the render on its own frame.
            if (self.pixels == TOTAL_PIXELS) {
                self.done = true;
                if (REFINE) self.ref.done = 1;
            }
            return !self.done;
        }

        fn counters(self: *const Self) hud.Counters {
            return .{
                .frames = self.frames,
                .rays = self.stats.rays,
                .pixels = self.pixels,
                .total_pixels = TOTAL_PIXELS,
                .done = self.done,
                .passes_done = if (REFINE) self.ref.done else @intFromBool(self.done),
                .passes = PASSES,
                .samples = if (REFINE) self.ref.progress() + self.pixels * @intFromBool(!self.done) else self.pixels,
                .clocked = self.bench.clocked,
                .px_per_s = self.bench.pixelsPerSecond(self.pixels),
                .ns_per_px = self.bench.nanosPerPixel(self.pixels),
            };
        }
    };
}

fn paint(fb: *zg.LogicalFB, cell: @import("progress.zig").Cell, index: u8) void {
    const y1 = @min(cell.y + cell.size, trace.IMG_H);
    var y = cell.y;
    while (y < y1) : (y += 1) {
        const row = fb.fb[y * fb.stride + cell.x ..][0..cell.size];
        @memset(row, index);
    }
}
