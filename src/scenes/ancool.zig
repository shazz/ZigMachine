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

const Starfield3D = @import("../effects/starfield_3D.zig").Starfield3D;

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
const fonts_b = @embedFile("../assets/fonts/ancool_font_interlaced.raw");
const offset_table_b = readU16Array(@embedFile("../assets/screens/scrolltext/scroll_sin.dat"));
const SCROLL_TEXT = "    YO YO   -AN COOL- IS BACK TO BURN WITH A NEW CRACK........ AND THE NEW CRACK IS               THE GAMES......    THIS TIME -MEGA CRIBB- FROM -1 LIFE CREW- SITS BY MY SIDE AND EATS CANDY   THE INTRO IS MADE BY: -AN COOL- AND THE CRACKING IS MADE BY: -AN COOL- AND -MEGA CRIBB-          BELIVE IT OR NOT, THE MUSAXX IS MADE BY: -AN COOL-           THIS GAME IS THE BEST SPORT-GAME I'VE SEEN ON THE ATARI ST AND I HOPE YOU WILL HAVE A GREAT TIME PLAYING IT.          I'VE BEEN OF THE CRACKING MARKET FOR A WHILE, BUT IT'S BECAUSE OF THE NEW DEMO (SOWHAT) WE ARE CODING. THE DEMO WILL CONTAIN ABOUT 10 SCREENS AND ALMOST ALL IS GOOD (I THINK)...   YOU WILL SEE MORE 2D-OBJECTS AND MORE COMPLEX 2D-OBJECTS IN THE DEMO-LOADER. THE DEMO SHOULD HAVE BEEN RELEASED AT OUR COPYPARTY THE 3-6 AUG. BUT AS ALWAYS........  YEAH, YOU KNOW??????.........        A HELLO GOES TO NICK OF TCB (HE WORKS AS A SECRET AGENT FOR KREML NOW)  AND SNAKE THE  LITTLE YELLOW BIRD OF REPLICANTS.......        OK.  I THINK THAT THAT WAS ALL FOR THIS TIME.....................";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 16;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const g_y_offset_table_b = readI16Array(@embedFile("../assets/screens/ancool/scroller_sin.dat"));

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/fonts/ancool_font.pal"));
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/ancool/rasters.dat"));

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;


var vertices = [25]Vec4{
    // T
    Vec4.new(-1.0, 	 0.0, 0.0, 1.0),
    Vec4.new( 0.0, 	 0.0, 0.0, 1.0),
    Vec4.new( 0.0, 	-0.3, 0.0, 1.0),
    Vec4.new(-0.32, -0.3, 0.0, 1.0),
    Vec4.new(-0.32, -1.2, 0.0, 1.0),
    Vec4.new(-0.68, -1.2, 0.0, 1.0),
    Vec4.new(-0.68, -0.3, 0.0, 1.0),
    Vec4.new(-1.0, 	-0.3, 0.0, 1.0),
    Vec4.new(-1.0, 	 0.0, 0.0, 1.0),
    // C
    Vec4.new( 0.2, 	 0.0, 	0.0, 1.0),
    Vec4.new( 1.2, 	 0.0, 	0.0, 1.0),
    Vec4.new( 1.2, 	-0.3, 	0.0, 1.0),
    Vec4.new( 0.52, -0.3, 	0.0, 1.0),
    Vec4.new( 0.52, -0.90, 	0.0, 1.0),
    Vec4.new( 1.20, -0.90, 	0.0, 1.0),
    Vec4.new( 1.20, -1.20,	0.0, 1.0),
    Vec4.new( 0.20, -1.20,	0.0, 1.0),
    Vec4.new( 0.20,  0.0, 	0.0, 1.0),
    // B
    Vec4.new( 1.40, 0.0, 	0.0, 1.0),
    Vec4.new( 2.10, 0.0, 	0.0, 1.0),
    Vec4.new( 2.40, -0.30, 	0.0, 1.0),
    Vec4.new( 2.10, -0.60, 	0.0, 1.0),
    Vec4.new( 2.40, -0.90,	0.0, 1.0),
    Vec4.new( 2.10, -1.20,	0.0, 1.0),
    Vec4.new( 1.40, -1.20,	0.0, 1.0),
};

const segments = [24]Vec2{
    // T
    Vec2.new(0, 1),
    Vec2.new(1, 2),
    Vec2.new(2, 3),
    Vec2.new(3, 4),
    Vec2.new(4, 5),
    Vec2.new(5, 6),
    Vec2.new(6, 7),
    Vec2.new(7, 8),
    Vec2.new(8, 0),
    // C
    Vec2.new(0+9, 1+9),
    Vec2.new(1+9, 2+9),
    Vec2.new(2+9, 3+9),
    Vec2.new(3+9, 4+9),
    Vec2.new(4+9, 5+9),
    Vec2.new(5+9, 6+9),
    Vec2.new(6+9, 7+9),
    Vec2.new(7+9, 0+9),
    // B
    Vec2.new(0+9+9, 1+9+9),
    Vec2.new(1+9+9, 2+9+9),
    Vec2.new(2+9+9, 3+9+9),
    Vec2.new(3+9+9, 4+9+9),
    Vec2.new(4+9+9, 5+9+9),
    Vec2.new(5+9+9, 6+9+9),
    Vec2.new(6+9+9, 0+9+9)
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u16 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

fn handler(fb: *LogicalFB, line: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line > 40 and line < 240 ) {
        fb.setPaletteEntry(0, rasters_b[(raster_index + line - 40) % 152]);
    }
    if (line > 240) {
        fb.setPaletteEntry(0, back_color);
    }
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    starfield_3D: Starfield3D = undefined,
    scrolltext: Scrolltext = undefined,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices: [25]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,
    zoom: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];

        fb = &zigos.lfbs[0];
        self.starfield_3D.init(fb, WIDTH, HEIGHT, 5, false);

        // 2nd plane
        fb = &zigos.lfbs[1];
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        self.projection = za.perspective(60.0, 200.0 / 320.0, 0.1, 100.0);
        self.camera = za.camera(Vec3.new(0.0, 0.0, -10.0), 0, 0);
        self.screen = za.screen(320, 200);   
        self.zoom = 0.8;

        var i: u8 = 0;
        while(i < 25) : ( i+= 1) {
            vertices[i] = vertices[i].add(Vec4.new(0, 1.00, 2.8, 0));
        }
        
        i = 9;
        while(i < 17) : ( i+= 1) {
            vertices[i] = vertices[i].add(Vec4.new(-0.5, 0, -0.5, 0));        
        }
    
        i = 17;
        while(i < 25) : ( i+= 1) {
            vertices[i] = vertices[i].add(Vec4.new(-1.0, 0, -1.0, 0));
        }        

        // 3rd plane
        fb = &zigos.lfbs[2];
        fb.setPalette(font_pal);

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(handler);        

        // table
        // var i: u16 = 0;
        // var y_offset_table_b: [WIDTH*2]i16 = undefined;
        // while (i < WIDTH*2) : (i += 1) {
        //     y_offset_table_b[i] = -@intCast(i16, i / 6);
        // }

        self.scrolltext.init(fb, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 100, null, g_y_offset_table_b);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {

        self.starfield_3D.update();
        self.scrolltext.update();

        for(vertices) |vertex, idx| {

            const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            const vertex_after_scale = rot_scale.vec4mulByMat4(vertex);

            const rot_mat = Mat4.fromEulerAngles(Vec3.new(self.angle_x, self.angle_y, self.angle_z));
            const vertex_after_rot = rot_mat.vec4mulByMat4(vertex_after_scale);

            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_rot);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            self.projected_vertices[idx].x=coord_x;
            self.projected_vertices[idx].y=coord_y;
        }        
   
        self.angle_x += 3;
        self.angle_y += 3.5;    
        self.angle_z += 2;      

        if(raster_index < 150) {
            raster_index += 2;
        } else {
            raster_index = 0;
        }

        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {

        self.starfield_3D.fb.clearFrameBuffer(0);
        self.starfield_3D.render();

        const fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);
        for(segments) |segment| {
            const v1: Coord = self.projected_vertices[@floatToInt(usize, segment.x())];
            const v2: Coord = self.projected_vertices[@floatToInt(usize, segment.y())];

            shapes.drawLine(fb, v1, v2, 1);   
        }

        self.scrolltext.fb.clearFrameBuffer(1);
        self.scrolltext.render();

    }
};
