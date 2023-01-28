// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const readI16Array = @import("../utils/loaders.zig").readI16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Starfield = @import("../effects/starfield.zig").Starfield;
const StarfieldDirection = @import("../effects/starfield.zig").StarfieldDirection;

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const za = @import("../utils/zalgebra.zig");
const shapes = @import("../effects/shapes.zig");
const Coord = shapes.Coord;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext
pub const NB_FONTS: u8 = 11;
const fonts_b = @embedFile("../assets/screens/empire/fonts2_pal.raw");
const SCROLL_TEXT = "             THE EMPIRE PRESENTS A NEW LITTLE INTRO FROM THE FALLEN ANGELS. CODE BY STEF, FONTS BY STARFIX, AND MUSEXX BY JOCHEN HIPPEL. THE GREETINGS GO TO: ST-CONNEXION, TECHNOCRATS AND....   AND....   ZE WATSIT.      OK, THAT'S ALL FOLKS!      BYE FREAKS.....";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 32;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/empire/fonts2_pal.dat"));

// Stars
const NB_STARS = 150;

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;


var vertices = [_]Vec4{

    // E
    Vec4.new(   0, 	0, 	 0, 1.0 ),
    Vec4.new(  1.0, 	0, 	 0, 1.0 ),
    Vec4.new(  1.0, 	-0.5, 	 0, 1.0 ),
    Vec4.new(   0, 	-0.5, 	 0, 1.0 ),
    Vec4.new(	  0, 	-1.0,   0, 1.0 ),
    Vec4.new(	 1.0, 	-1.0, 	 0, 1.0 ),
    // M
    Vec4.new(  1.2, 	-1.0, 	 0, 1.0 ),
    Vec4.new(  1.2, 	0, 	 0, 1.0 ),
    Vec4.new(  1.7, 	0, 	 0, 1.0 ),
    Vec4.new(  1.7, 	-1.0, 	 0, 1.0 ),
    Vec4.new(	 2.0, 	 0, 	 0, 1.0 ),
    Vec4.new(	 2.2, 	-0.2, 	 0, 1.0 ),
    Vec4.new(	 2.2, 	-1.0,	 0, 1.0 ),
    // P
    Vec4.new(  2.4, 	-1.0, 	 0, 1.0 ),
    Vec4.new(  2.4, 	0, 	 0, 1.0 ),
    Vec4.new(  3.2, 	0, 	 0, 1.0 ),
    Vec4.new(  3.4, 	-0.2, 	 0, 1.0 ),
    Vec4.new(	 3.4, 	-0.5,	 0, 1.0 ),
    Vec4.new(	 2.4, 	-0.5,	 0, 1.0 ),
    // I
    Vec4.new(	 3.6, 	0,	 0, 1.0 ),
    Vec4.new(	 3.6, 	-1.0,	 0, 1.0 ),
    // R
    Vec4.new(  3.8, 	-1.0, 	 0, 1.0 ),
    Vec4.new(  3.8, 	0, 	 0, 1.0 ),
    Vec4.new(  4.6, 	0, 	 0, 1.0 ),
    Vec4.new(  4.8, 	-0.2, 	 0, 1.0 ),
    Vec4.new(	 4.8, 	-0.5,	 0, 1.0 ),
    Vec4.new(	 3.8, 	-0.5,	 0, 1.0 ),
    Vec4.new(	 4.4, 	-0.5,	 0, 1.0 ),
    Vec4.new(	 4.8, 	-1.0,	 0, 1.0 ),
    // E
    Vec4.new(  5.0, 	0, 	 0, 1.0 ),
    Vec4.new(  6.0, 	0, 	 0, 1.0 ),
    Vec4.new(  6.0, 	-0.5, 	 0, 1.0 ),
    Vec4.new(  5.0, 	-0.5, 	 0, 1.0 ),
    Vec4.new(	 5.0, 	-1.0,   0, 1.0 ),
    Vec4.new(	 6.0, 	-1.0, 	 0, 1.0 ),    
};

const segments = [_]Vec2{

	// E
    Vec2.new(0, 1),
    Vec2.new(2, 3),
    Vec2.new(3, 4),
    Vec2.new(4, 5),
    // M
    Vec2.new(6, 7),
    Vec2.new(7, 8),
    Vec2.new(8, 9),
    Vec2.new(8, 10),
    Vec2.new(10, 11),
    Vec2.new(11, 12),
    // P
    Vec2.new(13, 14),
    Vec2.new(14, 15),
    Vec2.new(15, 16),
    Vec2.new(16, 17),
    Vec2.new(17, 18),
    // I
    Vec2.new(19, 20),
    // R
    Vec2.new(21, 22),
    Vec2.new(22, 23),
    Vec2.new(23, 24),
    Vec2.new(24, 25),
    Vec2.new(25, 26),
    Vec2.new(26, 27),
    Vec2.new(27, 28),
    // E
    Vec2.new(29, 30),
    Vec2.new(31, 32),
    Vec2.new(32, 33),
    Vec2.new(33, 34),    
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    starfield: Starfield(NB_STARS) = undefined,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices: [35]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];

        fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        self.starfield = Starfield(NB_STARS).init(fb.getRenderTarget(), WIDTH, HEIGHT-64, 32, 1, 4, StarfieldDirection.LEFT);

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(4, Color{ .r = 0xF0, .g = 0xF0, .b = 0xF0, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0xA0, .g = 0xA0, .b = 0xA0, .a = 255 });
        fb.setPaletteEntry(2, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0x40, .g = 0x40, .b = 0x40, .a = 255 });

        // 2nd plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        self.projection = za.perspective(40.0, 200.0 / 320.0, 20, 1800);
        self.camera = za.camera(Vec3.new(0.0, 0.0, -14.0), 0, 0);
        self.screen = za.screen(320, 200);   

        var i: u8 = 0;
        while(i < 35) : ( i+= 1) {
            vertices[i] = vertices[i].add(Vec4.new(-3.0, 0.50, 0.0, 0));
        }

        // 3rd plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(font_pal);

        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.update();
        self.scrolltext.update();

        for(vertices) |vertex, idx| {

            // const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            // const vertex_after_scale = rot_scale.vec4mulByMat4(vertex);

            const rot_matx = Mat4.fromEulerAngles(Vec3.new(self.angle_x, 0, 0));
            const vertex_after_rotx = rot_matx.vec4mulByMat4(vertex);

            const rot_maty = Mat4.fromEulerAngles(Vec3.new(0, self.angle_y, 0));
            const vertex_after_roty = rot_maty.vec4mulByMat4(vertex_after_rotx);


            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_roty);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            self.projected_vertices[idx].x=coord_x;
            self.projected_vertices[idx].y=coord_y;
        }        
   
        self.angle_x += 3.50;
        self.angle_y += 3.50;   

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.target.clearFrameBuffer(0);
        self.starfield.render();

        var fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);
        for(segments) |segment| {
            const v1: Coord = self.projected_vertices[@floatToInt(usize, segment.x())];
            const v2: Coord = self.projected_vertices[@floatToInt(usize, segment.y())];

            shapes.drawLine(fb.getRenderTarget(), v1, v2, 1);   
        }

        fb = &zigos.lfbs[2];
        fb.clearFrameBuffer(0);
        self.scrolltext.render();

        // copy scrolltext at the bottom
        var i: u16 = 0;
        while(i < WIDTH*SCROLL_CHAR_HEIGHT) : ( i += 1){
            fb.fb[i + ((HEIGHT-SCROLL_CHAR_HEIGHT) * WIDTH)] = fb.fb[i];
        }

        _ = elapsed_time;

    }
};
