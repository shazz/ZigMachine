// --------------------------------------------------------------------------
// Parallax — reusable horizontally-wrapping scroll layers (zigos library).
// Each layer is an indexed strip (w*h) drawn tiled across a destination width,
// shifted left by its own speed. Layers with `transparent` skip index 0.
//
// Palette-agnostic: it copies indices, so all layers on the same plane must
// already share that plane's palette (the asset pipeline merges them). Faithful
// to Codef's codef_parallax.js `parallax2` (pos += speed; wrap at width).
//
// No ZigOS import: `fb` is anything with fb/fb_w/fb_h/stride (a LogicalFB), so
// it tests natively (parallax_test.zig).
// --------------------------------------------------------------------------
const rows = @import("blit_rows.zig");

pub const Layer = struct {
    raw: []const u8, // w*h indexed pixels
    w: u16,
    h: u16,
    y: i16, // destination top (physical coords on a fullscreen plane)
    speed: f32, // leftward pixels per frame (fractional ok)
    transparent: bool = false, // skip index 0
    pos: f32 = 0,
};

pub fn Parallax(comptime n: usize) type {
    return struct {
        const Self = @This();
        layers: [n]Layer,

        // `scale` multiplies every layer's advance this frame (1.0 = nominal
        // speed); a host can slow/accelerate the whole parallax with it.
        pub fn update(self: *Self, scale: f32) void {
            for (&self.layers) |*l| {
                l.pos += l.speed * scale;
                const w: f32 = @floatFromInt(l.w);
                while (l.pos >= w) l.pos -= w;
                while (l.pos < 0) l.pos += w;
            }
        }

        // Draw every layer into `fb`, filling destination columns [x0, x0+dst_w).
        pub fn draw(self: *Self, fb: anytype, x0: i16, dst_w: u16) void {
            for (&self.layers) |*l| drawLayer(l, fb, x0, dst_w);
        }

        // Row by row, the source row as at most a few contiguous runs (it wraps
        // every w pixels): a @memcpy each, or a keyed word-store row
        // (blit_rows) when the layer is transparent. The old loop walked the
        // layer COLUMN by column through setPixelValue -- a bounds test, a
        // multiply, a modulo and a byte store per pixel, each one a different
        // line of the plane. Same pixels: a pixel is drawn where its column is
        // >= 0 and inside the plane and its row inside the plane.
        pub fn drawLayer(l: *const Layer, fb: anytype, x0: i16, dst_w: u16) void {
            if (l.w == 0) return;
            const posi: usize = @intFromFloat(l.pos);
            const lo: i32 = @max(0, -@as(i32, x0)); // first dx with px >= 0
            const hi: i32 = @min(@as(i32, dst_w), @as(i32, fb.fb_w) - x0); // px < fb_w
            if (hi <= lo) return;
            const dx0: usize = @intCast(lo);
            const cols: usize = @intCast(hi - lo);
            const w: usize = l.w;
            var ry: u16 = 0;
            while (ry < l.h) : (ry += 1) {
                const y: i32 = @as(i32, l.y) + ry;
                if (y < 0 or y >= fb.fb_h) continue;
                const out = fb.fb[@as(usize, @intCast(y)) * fb.stride + @as(usize, @intCast(@as(i32, x0) + lo)) ..][0..cols];
                const src = l.raw[@as(usize, ry) * w ..][0..w];
                var srcx = (dx0 + posi) % w;
                var done: usize = 0;
                while (done < cols) {
                    const len = @min(cols - done, w - srcx);
                    const o = out[done..][0..len];
                    const in = src[srcx..][0..len];
                    if (l.transparent) rows.row(o, in, @as(u8, 0), rows.keyedCopy, false) else @memcpy(o, in);
                    done += len;
                    srcx = 0;
                }
            }
        }
    };
}
