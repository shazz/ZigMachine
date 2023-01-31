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
const RenderTarget = @import("../zigos.zig").RenderTarget;
const Resolution = @import("../zigos.zig").Resolution;

const Text = @import("../effects/text.zig").Text;
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
const fonts_b = @embedFile("../assets/screens/reps/font.raw");
const fonts_chars = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps/font_pal.dat"));

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
var buffer_top = [_]u8{0} ** (320 * 40);
var buffer_middle = [_]u8{0} ** (320 * 200);
var buffer_bottom = [_]u8{0} ** (320 * 40);

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_vertical_borders(fb: *LogicalFB, zigos: *ZigOS, line: u16, column: u16) void {
    
    // _ = zigos;
    //_ = column;
    // _ = fb;    

    // -------------------------------------------------------------------------------
    // Top border part
    // -------------------------------------------------------------------------------

    // Open top border and use top buffer to fill the space
    if(line == 0 and column == 40) {
        // Console.log("opening top border!", .{});
        zigos.setResolution(Resolution.truecolor);

        var i: usize = 0;
        while(i < 40 * 320) : (i += 1) {
            fb.fb[i] = buffer_top[i];
        }   
    }

    if(line == 40) {
        // copy text to fb
        var i: u16 = 0;
        while(i < WIDTH * HEIGHT) : ( i += 1){
            fb.fb[i] = buffer_middle[i];
        }
    }
    
    // Open low border and copy low buffer
    if(line == 240 and column == 40) {
        // Console.log("Opening bottom border!", .{});
        zigos.setResolution(Resolution.truecolor);

        // copy text to fb
        var i: u16 = WIDTH * (HEIGHT - 40);
        var j: u16 = 0;
        while(i < WIDTH * HEIGHT) : ( i += 1){
            fb.fb[i] = buffer_bottom[j];
            j += 1;
        }
    }

}

pub const Demo = struct {
  
    name: u8 = 0,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices: [35]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    text: Text = undefined,
    text_target_top: RenderTarget = undefined,
    text_target_middle: RenderTarget = undefined,
    text_target_bottom: RenderTarget = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];

        fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        // fb.setPalette(font_pal);
        fb.setPaletteEntry(0, Color{ .r=0, .g=0, .b=0, .a=0});
        fb.setPaletteEntry(1, Color{ .r=0, .g=0, .b=255, .a=255});

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(40, handler_vertical_borders);         

        // create text buffer
        self.text_target_top = .{ .buffer = &buffer_top };        
        self.text_target_middle = .{ .buffer = &buffer_middle };  
        self.text_target_bottom = .{ .buffer = &buffer_bottom };  

        self.text.init(self.text_target_top, fonts_b, fonts_chars, 8, 8);

        self.text.render("****************************************",0, 0 * 8);
        self.text.render(" **   THE REPLICANTS AND ST AMIGOS   ** ",0, 1 * 8);
        self.text.render("    **   BRING YOU AN HOT STUFF   **    ",0, 2 * 8);
        self.text.render("       **************************       ",0, 3 * 8);
        
        self.text.init(self.text_target_middle, fonts_b, fonts_chars, 8, 8);

        self.text.render("   SAVAGELY BROKEN AN TRAINED BY MAXI",0, 0 * 8);
        self.text.render("  ------------------------------------",0, 1 * 8);
        self.text.render("  DIS BOOT WAS ALSO FAST CODED BY MAXI",0, 2 * 8);
        self.text.render(" --------------------------------------",0, 3 * 8);
        
        self.text.render("       COPY IN 2 SIDES 10 SECTORS",0, 5 * 8);
        self.text.render("   THE MAGIC KEY FOR THE TRAINER IS *",0, 6 * 8);
        self.text.render("SORRY FOR DIS LITTLE LAME CODE ,COZ THAT",0, 7 * 8);
        self.text.render("IS NOT MY BEST 3D LINE ROUT ,SO FAR NOT.",0, 8 * 8);
        self.text.render("THAT IS MY SHORTER ONE ! BUT IN 3 PLANES",0, 9 * 8);
        self.text.render("THE GOOD IS RATHER MY UPPER BORDER ROUT!",0, 10 * 8); 
        
        self.text.render("VERY SPECIAL REGARDS GO TO :",0, 14 * 8);
        self.text.render(" THOR - AVB - ST WAIKIKI- MINIMAX - ZAE",0, 15 * 8);
        self.text.render(" MAD VISION  - FUZION - LITTLESWAP -FOF",0, 16 * 8);
        self.text.render("  BAD BOYS - MCA - ACB - THE REDUCTORS",0, 17 * 8);
        self.text.render("  RCA AND ALL THE MEMBERS OF THE UNION",0, 18 * 8);
        
        self.text.render("I SEND THE NORMAL GREETINGS TO :",0, 20 * 8);
        self.text.render(" ST CONNEXION-IMAGINA-PHALANC-FF-TELLER",0, 21 * 8);
        self.text.render(" 2 LIVE CREW-PENDRAGONS-DRAGON-FRAISINE",0, 22 * 8);
        self.text.render(" DIMITRI-EQUINOX-TGE-SEWER SOFT-ACF-BMT",0, 23 * 8);
        self.text.render(" MEDWAY BOYS-OVR-MCS-TDA-LOST BOYS-NEXT",0, 24 * 8);

        self.text.init(self.text_target_bottom, fonts_b, fonts_chars, 8, 8);        
        self.text.render(" ULM-PARADOX-SYNC-OMEGA-INNER CIRCLE-MU",0, 1 * 8);
        self.text.render("ENJOY THE VIOLENCE..THE REPLICANTS RULEZ",0, 2 * 8);
        self.text.render("****************************************",0, 3 * 8);

        // 2nd plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        self.projection = za.perspective(40.0, 200.0 / 320.0, 20, 1800);
        self.camera = za.camera(Vec3.new(0.0, 0.0, -14.0), 0, 0);
        self.screen = za.screen(320, 200);   

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

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

        var fb: *LogicalFB = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);
        for(segments) |segment| {
            const v1: Coord = self.projected_vertices[@floatToInt(usize, segment.x())];
            const v2: Coord = self.projected_vertices[@floatToInt(usize, segment.y())];

            shapes.drawLine(fb.getRenderTarget(), v1, v2, 1);   
        }


        _ = elapsed_time;

    }
};
