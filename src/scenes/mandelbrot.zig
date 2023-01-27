// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Mandelbrot = @import("../effects/mandelbrot.zig").Mandelbrot;
const Resolution = @import("../zigos.zig").Resolution;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

pub const PHYSICAL_WIDTH: u16 = @import("../zigos.zig").PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = @import("../zigos.zig").PHYSICAL_HEIGHT;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    name: u8 = 0,
    frame_counter: u32 = 0,
    mandelbrot: Mandelbrot = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        var lfb: *LogicalFB = &zigos.lfbs[0];
        lfb.is_enabled = true;

        var pfb: *[PHYSICAL_HEIGHT][PHYSICAL_WIDTH]u32 = &zigos.physical_framebuffer;

        zigos.setResolution(Resolution.truecolor);
        self.mandelbrot.init(pfb);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.mandelbrot.update();

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.mandelbrot.render();

        _ = zigos;
        _ = elapsed_time;
    }
};
