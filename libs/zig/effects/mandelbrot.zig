//
// Mandelbrot Zig implementation by Steve L (sleibrock)
// https://github.com/sleibrock/zigtoys
//

// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;

const io = std.io;
const math = std.math;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").PHYSICAL_HEIGHT;
const WIDTH: usize = @import("../zigos.zig").PHYSICAL_WIDTH;

const MAX_ITER: u8 = 255;
const F_WIDTH: f32 = @as(f32, @floatFromInt(WIDTH));
const F_HEIGHT: f32 = @as(f32, @floatFromInt(HEIGHT));
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Fixed-point twin (Q5.27, i32). The escape test only runs while |z|^2 < 4, so
// x, y < 2 going into a step, and the next x = x^2 - y^2 + x0 stays under ~5.7
// and y = 2xy + y0 under ~9: both inside Q5.27's +-16. The squares can reach
// ~81 and stay in i64 (only their SUM is compared with 4). One ulp is 7.5e-9,
// 16x finer than f32 near 1, so the fixed image is closer to the exact set than
// the f32 one; the two differ only where an orbit grazes the escape circle.
// The per-pixel start points come from comptime tables, the f32 formula's
// (px / W) * 2.51 - 1.67 evaluated in f64 and rounded once.
// --------------------------------------------------------------------------
const FRAC: u5 = 27;
const ONE: f64 = 1 << FRAC;
const X0_TAB: [WIDTH]i32 = blk: {
    var t: [WIDTH]i32 = undefined;
    for (&t, 0..) |*v, i| v.* = @intFromFloat(@round(((@as(f64, @floatFromInt(i)) / @as(f64, WIDTH)) * 2.51 - 1.67) * ONE));
    break :blk t;
};
const Y0_TAB: [HEIGHT]i32 = blk: {
    var t: [HEIGHT]i32 = undefined;
    for (&t, 0..) |*v, i| v.* = @intFromFloat(@round(((@as(f64, @floatFromInt(i)) / @as(f64, HEIGHT)) * 2.24 - 1.12) * ONE));
    break :blk t;
};
const FOUR: i64 = 4 << FRAC;

// --------------------------------------------------------------------------
// Mandelbrot
// --------------------------------------------------------------------------
pub const Mandelbrot = struct {
    pfb: *[HEIGHT][WIDTH]u32 = undefined,

    pub fn init(self: *Mandelbrot, fb: *[HEIGHT][WIDTH]u32) void {
        self.pfb = fb;

        Console.log("fb: {}", .{@intFromPtr(self.pfb)});
    }

    pub fn update(self: *Mandelbrot) void {
        _ = self;
    }

    pub fn render(self: *Mandelbrot) void {
        for (self.pfb, 0..) |*row, y| {
            for (row, 0..) |*pixel, x| {
                const iter: u8 = get_pixel_color(@as(i32, @intCast(x)), @as(i32, @intCast(y)));
                const color: Color = Color{ .r = iter, .g = iter, .b = iter, .a = iter };
                pixel.* = color.toRGBA();
            }
        }
    }

    /// Escape-time iteration count (0..MAX_ITER) for physical pixel (px, py) of
    /// the 400x280 frame. The sealed machine has no truecolor path — `render`
    /// above wrote the physical framebuffer directly, which the machine now
    /// clears and composites over — so a scene draws this into a plane as a
    /// palette index instead (see apps/zig/scenes/mandelbrot.zig).
    pub fn escapeTime(px: i32, py: i32) u8 {
        return get_pixel_color(px, py);
    }

    /// escapeTime in integers (see the Q5.27 note above): no float in the loop.
    pub fn escapeTimeFixed(px: i32, py: i32) u8 {
        const x0 = X0_TAB[@intCast(px)];
        const y0 = Y0_TAB[@intCast(py)];
        var x: i32 = 0;
        var y: i32 = 0;
        var xsq: i64 = 0;
        var ysq: i64 = 0;
        var iterations: u8 = 0;
        while (xsq + ysq < FOUR and iterations < MAX_ITER) : (iterations += 1) {
            const tmp: i32 = @intCast(xsq - ysq + x0);
            y = @intCast((@as(i64, x) * y >> (FRAC - 1)) + y0);
            x = tmp;
            xsq = @as(i64, x) * x >> FRAC;
            ysq = @as(i64, y) * y >> FRAC;
        }
        return iterations;
    }

    fn get_pixel_color(px: i32, py: i32) u8 {
        var iterations: u8 = 0;

        var x0 = @as(f32, @floatFromInt(px));
        var y0 = @as(f32, @floatFromInt(py));

        x0 = ((x0 / F_WIDTH) * 2.51) - 1.67;
        y0 = ((y0 / F_HEIGHT) * 2.24) - 1.12;

        var x: f32 = 0;
        var y: f32 = 0;
        var tmp: f32 = 0;
        var xsquare: f32 = 0;
        var ysquare: f32 = 0;

        while ((xsquare + ysquare < 4.0) and (iterations < MAX_ITER)) : (iterations += 1) {
            tmp = xsquare - ysquare + x0;
            y = 2 * x * y + y0;
            x = tmp;
            xsquare = x * x;
            ysquare = y * y;
        }

        return iterations;
    }
};
