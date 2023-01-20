// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Resolution = @import("../zigos.zig").Resolution;

const Boot = @import("../effects/boot.zig").Boot;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    boot: Boot = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("hello init", .{});

        // Use first logical framebuffer and enable it
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;

        // add the Boot effect on this framebuffer
        self.boot.init(fb);

        Console.log("hello init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {

        // update the boot effect
        self.boot.update();

        _ = zigos;
        _ = time_elapsed;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {

        // render the Boot effect
        self.boot.render(zigos);

        _ = time_elapsed;
    }
};




