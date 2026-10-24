// --------------------------------------------------------------------------
// The 3D starfield behind the music screen, in integers (Matt, 2026-10-24:
// no float per frame). It is the library's Starfield3D (not line mode) run in
// Q4 fixed point: the same 200 stars (taken from Starfield3D.init, which also
// sets their greys 1..30 on the plane), the same speed 2 toward the viewer,
// the same projection centre (160, 100) * star ratio 100 / z, and the same
// rule: a star whose previous projection was on screen is plotted at its
// current one, in the grey of its depth.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const View = @import("view.zig").View;

const Q = 16; // Q4
const CX: i32 = zg.WIDTH / 2;
const CY: i32 = zg.HEIGHT / 2;
const ZMAX: i32 = (zg.WIDTH + zg.HEIGHT) / 2 * Q; // the library's z range, 260
const SPEED: i32 = 2 * Q;
const RATIO: i32 = 100; // the library's star_ratio
const STEPS: i32 = 29; // GRADIENT_STEPS - 1

const Star = struct { x: i32, y: i32, z: i32, px: i32 = -1, py: i32 = -1, ppx: i32 = -1, ppy: i32 = -1 };

pub fn Stars(comptime n: usize) type {
    return struct {
        star: [n]Star,
        const Self = @This();

        /// The library's stars, converted once (float at init only). It sets the greys.
        pub fn init(fb: *zg.LogicalFB) Self {
            const lib = zg.Starfield3D(n).init(fb.getRenderTarget(), zg.WIDTH, zg.HEIGHT, 2, false);
            var self: Self = undefined;
            for (&self.star, lib.starfield_table) |*s, l| {
                s.* = .{ .x = @intFromFloat(l.x * Q), .y = @intFromFloat(l.y * Q), .z = @intFromFloat(l.z * Q) };
            }
            return self;
        }

        pub fn update(self: *Self) void {
            for (&self.star) |*s| {
                s.ppx = s.px;
                s.ppy = s.py;
                s.z -= SPEED;
                if (s.z < 0) s.z += ZMAX;
                if (s.z == 0) { // on the eye: off every edge
                    s.px = -1;
                    continue;
                }
                s.px = CX + @divTrunc(s.x * RATIO, s.z);
                s.py = CY + @divTrunc(s.y * RATIO, s.z);
            }
        }

        pub fn draw(self: *const Self, v: View) void {
            for (&self.star) |*s| {
                if (!(s.ppx > 0 and s.ppx < zg.WIDTH and s.ppy > 0 and s.ppy < zg.HEIGHT)) continue;
                const pal = 1 + @divTrunc(s.z * STEPS * 12, ZMAX * 10); // 1 + z / zmax * 1.2 * 29
                v.put(s.px, s.py, @intCast(pal));
            }
        }
    };
}
