// The ray-traced scene as a cart: Demo(M) for a number back-end M.
//
// Music: none, on purpose. This screen is also the FPGA CPU benchmark, and an
// SNDH would add the 68000 player's work to the number it is there to measure.
//
// Frame budget: PIXELS_PER_FRAME pixels are traced per frame, in the order of
// progress.zig, so the cart keeps its frame rate on a fast machine and the
// picture simply takes more frames on a slow one. Keys: none; the host's
// Escape/Space leave the screen like on any scene without key().
const zg = @import("zigos");
const trace = @import("trace.zig");
const P = @import("palette.zig");
const hud = @import("hud.zig");
const Progress = @import("progress.zig").Progress;

const ZigOS = zg.ZigOS;

pub const PIXELS_PER_FRAME = 512;
const TOTAL_PIXELS = trace.IMG_W * trace.IMG_H;

pub fn Demo(comptime M: type) type {
    const Tracer = trace.Tracer(M);
    return struct {
        progress: Progress,
        stats: trace.Stats,
        frames: u32,
        pixels: u32,
        done: bool,

        const Self = @This();

        pub fn init(self: *Self, zigos: *ZigOS) void {
            self.progress.start();
            self.stats = .{ .rays = 0 };
            self.frames = 0;
            self.pixels = 0;
            self.done = false;
            zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
            const fb = &zigos.lfbs[0];
            fb.is_enabled = true;
            P.install(fb);
            fb.clearFrameBuffer(P.PANEL);
            hud.draw(zigos, fb, M.NAME, self.counters());
        }

        pub fn update(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = self;
            _ = zigos;
            _ = dt;
        }

        pub fn render(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = dt;
            if (self.done) return;
            const fb = &zigos.lfbs[0];
            self.frames += 1;
            var n: u32 = 0;
            while (n < PIXELS_PER_FRAME) : (n += 1) {
                const cell = self.progress.next() orelse {
                    self.done = true;
                    break;
                };
                paint(fb, cell, Tracer.pixel(&self.stats, cell.x, cell.y));
                self.pixels += 1;
            }
            if (self.pixels == TOTAL_PIXELS) self.done = true; // the last pixel ends the render on its own frame
            hud.draw(zigos, fb, M.NAME, self.counters());
        }

        fn counters(self: *const Self) hud.Counters {
            return .{ .frames = self.frames, .rays = self.stats.rays, .pixels = self.pixels, .total_pixels = TOTAL_PIXELS, .done = self.done };
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
