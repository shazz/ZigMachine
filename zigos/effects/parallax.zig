// --------------------------------------------------------------------------
// Parallax — reusable horizontally-wrapping scroll layers (zigos library).
// Each layer is an indexed strip (w*h) drawn tiled across a destination width,
// shifted left by its own speed. Layers with `transparent` skip index 0.
//
// Palette-agnostic: it copies indices, so all layers on the same plane must
// already share that plane's palette (the asset pipeline merges them). Faithful
// to Codef's codef_parallax.js `parallax2` (pos += speed; wrap at width).
// --------------------------------------------------------------------------
const zsrc = @import("../zigos.zig");
const LogicalFB = zsrc.LogicalFB;

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
        pub fn draw(self: *Self, fb: *LogicalFB, x0: i16, dst_w: u16) void {
            for (&self.layers) |*l| drawLayer(l, fb, x0, dst_w);
        }

        fn drawLayer(l: *const Layer, fb: *LogicalFB, x0: i16, dst_w: u16) void {
            const posi: usize = @intFromFloat(l.pos);
            var dx: u16 = 0;
            while (dx < dst_w) : (dx += 1) {
                const px: i16 = x0 + @as(i16, @intCast(dx));
                if (px < 0) continue;
                const srcx: usize = (@as(usize, dx) + posi) % l.w;
                var ry: u16 = 0;
                while (ry < l.h) : (ry += 1) {
                    const idx = l.raw[@as(usize, ry) * l.w + srcx];
                    if (l.transparent and idx == 0) continue;
                    fb.setPixelValue(@intCast(px), @intCast(l.y + @as(i16, @intCast(ry))), idx);
                }
            }
        }
    };
}
