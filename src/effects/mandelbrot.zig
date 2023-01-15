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
const F_WIDTH: f32 = @intToFloat(f32, WIDTH);
const F_HEIGHT: f32 = @intToFloat(f32, HEIGHT);
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Mandelbrot
// --------------------------------------------------------------------------
pub const Mandelbrot = struct {
    pfb: *[HEIGHT][WIDTH]u32 = undefined,

    pub fn init(self: *Mandelbrot, fb: *[HEIGHT][WIDTH]u32) void {
        self.pfb = fb;

        Console.log("fb: {}", .{@ptrToInt(self.pfb)});
    }

    pub fn update(self: *Mandelbrot) void {
        _ = self;
    }

    pub fn render(self: *Mandelbrot) void {
        for (self.pfb) |*row, y| {
            for (row) |*pixel, x| {
                const iter: u8 = get_pixel_color(@intCast(i32, x), @intCast(i32, y));
                const color: Color = Color{ .r = iter, .g = iter, .b = iter, .a = iter };
                pixel.* = color.toRGBA();
            }
        }
    }

    fn get_pixel_color(px: i32, py: i32) u8 {
        var iterations: u8 = 0;

        var x0 = @intToFloat(f32, px);
        var y0 = @intToFloat(f32, py);

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
