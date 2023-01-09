// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Color = @import("zigos.zig").Color;

const Starfield = @import("effects/starfield.zig").Starfield;
const StarfieldDirection = @import("effects/starfield.zig").StarfieldDirection;

const Fade = @import("effects/fade.zig").Fade;
const Sprite = @import("effects/sprite.zig").Sprite;
const Background = @import("effects/background.zig").Background;
const Scrolltext = @import("effects/scrolltext.zig").Scrolltext;
const Dots3D = @import("effects/dots3d.zig").Dots3D;

const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("zigos.zig").HEIGHT;
const WIDTH: u16 = @import("zigos.zig").WIDTH;


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
   
    name: u8 = 0,
    frame_counter: u32 = 0,
    starfield: Starfield = undefined,
    dots3D: Dots3D = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];

        // Set palette
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(2, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0, .g = 255, .b = 0, .a = 255 });
        fb.setPaletteEntry(4, Color{ .r = 0, .g = 0, .b = 255, .a = 255 });

        self.dots3D.init(fb);
        self.dots3D.render();

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {

        self.dots3D.update();

        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {

        self.dots3D.render();
        _ = zigos;
    }
};
