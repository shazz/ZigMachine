// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

// Migrated to the named `zigos` module (was pre-reorg relative imports).
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Resolution = zg.Resolution;

const Boot = zg.Boot;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

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

        zigos.setBackgroundColor(Color{ .r = 255, .g = 255, .b = 255, .a = 255 });

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
