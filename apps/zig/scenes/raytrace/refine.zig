// Progressive refinement (the f32 cart only, float.zig's PASSES): once the
// one-sample picture is complete, every pixel is traced PASSES - 1 more times,
// each time through a different sub-pixel offset (anti-aliasing) and under a
// different point of a small disc of light around the sun (soft shadows), and
// the picture is redrawn from the running average.
//
// The palette is a set of ramps (palette.zig) with no entries between them, so
// the average cannot be a colour. It is kept per RAMP instead: each pixel holds
// up to two classes (sky, a floor tone, a sphere), each with its sample count
// and summed 0..256 intensities. The shown index dithers between the two classes
// by coverage, then along the chosen ramp by its mean intensity, both on Bayer
// thresholds: a silhouette becomes a coverage dither of its two sides, a shadow
// edge a ramp of shades, the far checker floor a cream/maroon mix instead of
// moire. A third class in one pixel (rare: corners) is dropped.
//
// Sums are integers, so the converged picture is the same whatever share of a
// pass a frame traced. After the first pass a pixel's state IS that pass's
// sample, so resolve() reproduces pass 1's index exactly (refine_test.zig).
const zg = @import("zigos");
const trace = @import("trace.zig");
const P = @import("palette.zig");
const samples = @import("samples.zig");
const A = @import("acc.zig");

const TOTAL = trace.IMG_W * trace.IMG_H;

pub fn Refine(comptime M: type) type {
    const Tracer = trace.Tracer(M);
    const S = samples.Samples(M, Tracer.Vec3);
    return struct {
        acc: []A.Acc,
        done: u32, // passes complete, 1..PASSES once the first picture is
        x: u32,
        y: u32,
        stats: trace.Stats, // refinement rays, kept out of the benchmark's

        const Self = @This();
        pub const PASSES = samples.N;

        pub fn init(self: *Self) void {
            self.acc = zg.mem.mustAlloc(A.Acc, TOTAL);
            self.restart();
        }

        pub fn restart(self: *Self) void {
            self.done = 0;
            self.x = 0;
            self.y = 0;
            self.stats = .{ .rays = 0 };
        }

        /// Pass 1's sample of (x, y): it overwrites the pixel's state.
        pub fn record(self: *Self, x: u32, y: u32, s: P.Shade) void {
            // As three word stores: a plain struct store let LLVM merge two
            // constant bytes into a half-word store at an odd address, which
            // traps on the board (frame_cost: 512 misaligned a frame).
            const w: [3]u32 = @bitCast(A.first(s));
            const d: *[3]u32 = @ptrCast(&self.acc[y * trace.IMG_W + x]);
            inline for (0..3) |i| d[i] = w[i];
        }

        pub fn converged(self: *const Self) bool {
            return self.done >= PASSES;
        }

        /// Samples in the passes so far, for the progress bar.
        pub fn progress(self: *const Self) u32 {
            return self.done * TOTAL + self.y * trace.IMG_W + self.x;
        }

        /// Up to `max` more samples; false once the running pass has ended
        /// (each pass ends its frame, as the first one does).
        pub fn step(self: *Self, fb: *zg.LogicalFB, max: u32) bool {
            var n: u32 = 0;
            while (n < max and !self.converged()) : (n += 1) {
                const x = self.x;
                const y = self.y;
                const j = S.pick(self.done, P.bayer(x, y) >> 4);
                const a = &self.acc[y * trace.IMG_W + x];
                A.add(a, Tracer.sample(&self.stats, x, y, S.JX[j], S.JY[j], S.LIGHTS[j]));
                fb.fb[y * fb.stride + x] = A.resolve(a.*, x, y);
                self.x += 1;
                if (self.x < trace.IMG_W) continue;
                self.x = 0;
                self.y += 1;
                if (self.y < trace.IMG_H) continue;
                self.y = 0;
                self.done += 1;
                return false;
            }
            return !self.converged();
        }
    };
}
