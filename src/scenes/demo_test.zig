// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Starfield = @import("../effects/starfield.zig").Starfield;
const StarfieldDirection = @import("../effects/starfield.zig").StarfieldDirection;
const Starfield3D = @import("../effects/starfield_3D.zig").Starfield3D;
const Fade = @import("../effects/fade.zig").Fade;
const Sprite = @import("../effects/sprite.zig").Sprite;
const Background = @import("../effects/background.zig").Background;
const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Dots3D = @import("../effects/dots3d.zig").Dots3D;
const Mandelbrot = @import("../effects/mandelbrot.zig").Mandelbrot;
const Boot = @import("../effects/boot.zig").Boot;
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
    starfield: Starfield = undefined,
    dots3D: Dots3D = undefined,
    mandelbrot: Mandelbrot = undefined,
    boot: Boot = undefined,
    starfield_3D: Starfield3D = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        self.starfield_3D.init(fb, WIDTH, HEIGHT, 2);


        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {
  
        self.starfield_3D.update();
        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {

        self.starfield_3D.fb.clearFrameBuffer(0);
        self.starfield_3D.render();
        _ = zigos;
    }
};
