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

const shapes = @import("../effects/shapes.zig");
const Coord = shapes.Coord;


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
    // name: u8 = 0,
    // frame_counter: u32 = 0,
    // starfield: Starfield = undefined,
    // dots3D: Dots3D = undefined,
    // mandelbrot: Mandelbrot = undefined,
    // boot: Boot = undefined,
    // starfield_3D: Starfield3D = undefined,
    // polygon: [4]Coord = undefined,
    rnd: std.rand.DefaultPrng = undefined,
    colors: [2000]u8 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        self.rnd = RndGen.init(0);

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        var j: u8 = 1;
        while(j < 255) : ( j += 1) {
            fb.setPaletteEntry(j, Color{ .r = 0, .g = 0, .b = 255, .a = 255-j });   
        }
            
        // fb.setPaletteEntry(2, Color{ .r = 255, .g = 0, .b = 255, .a = 255 });   
        // fb.setPaletteEntry(3, Color{ .r = 255, .g = 255, .b = 0, .a = 255 });   
        // fb.setPaletteEntry(4, Color{ .r = 0, .g = 255, .b = 255, .a = 255 });   
        // fb.setPaletteEntry(5, Color{ .r = 255, .g = 0, .b = 255, .a = 255 });   
        // fb.setPaletteEntry(6, Color{ .r = 255, .g = 128, .b = 0, .a = 255 });   
        // fb.setPaletteEntry(7, Color{ .r = 0, .g = 255, .b = 255, .a = 255 });   
        // fb.setPaletteEntry(8, Color{ .r = 255, .g = 0, .b = 128, .a = 255 });   
        // fb.setPaletteEntry(9, Color{ .r = 128, .g = 255, .b = 255, .a = 255 });   
        // fb.setPaletteEntry(10, Color{ .r = 255, .g = 128, .b = 255, .a = 255 });   

        // const p1: Coord = .{ .x=10, .y=10 };
        // const p2: Coord = .{ .x=10, .y=150 };
        // const p3: Coord = .{ .x=100, .y=150 };
        // const p4: Coord = .{ .x=100, .y=10 };

        // self.polygon = [_]Coord{ p1, p2, p3, p4};
        // self.dots3D.init(fb);

        var i: usize = 0;
        while(i < 1000) : ( i += 1) {
            self.colors[i] = self.rnd.random().intRangeAtMost(u8, 0, 10);
        }
        

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
  
        // self.dots3D.update();
        _ = self;
        _ = zigos;
        _ = time_elapsed;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.clearFrameBuffer(0);

        // shapes.fillPolygon(fb, &self.polygon, 1);   

        const p1: Coord = .{ .x=160, .y=1 };
        const p2: Coord = .{ .x=0, .y=199 };
        const p3: Coord = .{ .x=319, .y=199 };   
        
        // const polygon: [3]Coord = [_]Coord{ p1, p2, p3 };

        // var i: usize = 0;
        var j: u8 = 1;
        while(j < 255) : ( j += 1 ) {
            // shapes.fillPolygon(fb, &polygon, self.rnd.random().intRangeAtMost(u8, 0, 255));   
            // shapes.fillFlatTriangle(fb, p1, p2, p3, j); 
            shapes.fillFlatTriangle(fb, p1, p2, p3, self.rnd.random().intRangeAtMost(u8, 0, 255)); 
            // j += 1;
        }


        
        // self.dots3D.fb.clearFrameBuffer(0);
        // self.dots3D.render();

        // _ = zigos;
        // _ = self;
        _ = time_elapsed;
    }
};
