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

var vertices_rectangle = [_]Vec4{
        Vec4.new(  -0.02,      -0.02,     0,  1.0),
        Vec4.new(  2.40,     -0.02,     0,  1.0),
        Vec4.new( 2.40,      0.60,     0,  1.0),
        Vec4.new( -0.02,       0.60,     0,  1.0),
};

const segments_rectangle = [_]Vec2{
        Vec2.new(0, 1),
        Vec2.new(1, 2),
        Vec2.new(2, 3),
		Vec2.new(3, 0),
};

var vertices_yellow = [_]Vec4{
        Vec4.new(  0, 0.58, -0.10, 1.0),
        Vec4.new(  0,  0, -0.10, 1.0),
        Vec4.new( 0.40,  0.0, -0.30, 1.0),
        Vec4.new( 0.40, 0.30, -0.30, 1.0),
        Vec4.new(  0.09, 0.30, -0.13, 1.0),
        Vec4.new(  0.20, 0.30, -0.19, 1.0),
		Vec4.new(  0.40,  0.58, -0.30, 1.0),
	
		Vec4.new(  0.45, 0.58, -0.10, 1.0),
		Vec4.new(  0.45, 0.0, -0.10, 1.0),
		Vec4.new(  0.85, 0.0, -0.30, 1.0),
		Vec4.new(  0.85, 0.30, -0.30, 1.0),
		Vec4.new(  0.54, 0.30, -0.13, 1.0),
	
		Vec4.new(  0.97-0.13, 0.0, -0.10, 1.0),
		Vec4.new(  1.20-0.13, 0.0, -0.20, 1.0),
		Vec4.new(  1.10-0.13, 0.0, -0.155, 1.0),
		Vec4.new(  1.10-0.13, 0.58, -0.155, 1.0),
		Vec4.new(  0.97-0.13, 0.58, -0.10, 1.0),
		Vec4.new(  1.20-0.13, 0.58, -0.20, 1.0),
	
		Vec4.new(  1.33-0.10, 0.58, -0.10, 1.0),
		Vec4.new(  1.53-0.10, 0.0, -0.15, 1.0),
		Vec4.new(  1.73-0.10, 0.58, -0.30, 1.0),
		Vec4.new(  1.43-0.10, 0.30, -0.125, 1.0),
		Vec4.new(  1.63-0.10, 0.30, -0.225, 1.0),
	
		Vec4.new(  1.81, 0.0, -0.10, 1.0),
		Vec4.new(  2.14, 0.0, -0.30, 1.0),
		Vec4.new(  1.98, 0.0, -0.205, 1.0),
		Vec4.new(  1.98, 0.58, -0.205, 1.0),
};

const segments_yellow = [_]Vec2{
        Vec2.new(0,  1 ),
        Vec2.new(1,  2 ),
        Vec2.new(2,  3 ),
        Vec2.new(3,  4 ),
		Vec2.new(5,  6 ),
	
		Vec2.new(7,  8 ),
		Vec2.new(8,  9 ),
		Vec2.new(9,  10 ),
		Vec2.new(10,  11 ),
	
		Vec2.new(12,  13 ),
		Vec2.new(14,  15 ),
		Vec2.new(16,  17 ),
	
		Vec2.new(18,  19 ),
		Vec2.new(19,  20 ),
		Vec2.new(21,  22 ),

		Vec2.new(23,  24 ),
		Vec2.new(25,  26 ),
};

var vertices_red = [_]Vec4{
        Vec4.new(  0.60,  0.58,  -0.30, 1.0),
        Vec4.new(  0.20,  0.58,  -0.10, 1.0),
        Vec4.new(  0.20,   0.0,  -0.10, 1.0),
        Vec4.new(  0.60,   0.0,  -0.30, 1.0),
        Vec4.new(  0.20,  0.30,  -0.10, 1.0),
		Vec4.new(  0.50,  0.30,  -0.25, 1.0),
	
	    Vec4.new(  1.05, 0.58,  -0.30, 1.0),
        Vec4.new(  0.65,  0.58,  -0.10, 1.0),
		Vec4.new(  0.65,   0.0,  -0.10, 1.0),
	
		Vec4.new(  1.48, 0.58,  -0.30, 1.0),
        Vec4.new(  1.10,  0.58,  -0.10, 1.0),
		Vec4.new(  1.10,   0.0,  -0.10, 1.0),
		Vec4.new(  1.48,   0.0,  -0.30, 1.0),
	
		Vec4.new(  1.53, 0.58,  -0.10, 1.0),
        Vec4.new(  1.53,  0.0,  -0.10, 1.0),
		Vec4.new(  1.93,   0.58,  -0.30, 1.0),
		Vec4.new(  1.93,   0.0,  -0.30, 1.0),
	
		Vec4.new(  1.98, 0.58,  -0.10, 1.0),
        Vec4.new(  2.38,  0.58,  -0.30, 1.0),
		Vec4.new(  2.38,   0.30,  -0.30, 1.0),
		Vec4.new(  1.98,   0.30,  -0.10, 1.0),
		Vec4.new(  1.98,   0.0,  -0.10, 1.0),
		Vec4.new(  2.38,   0.0,  -0.30, 1.0),	
};

const segments_red = [_]Vec2{
        Vec2.new(0,  1),
        Vec2.new(1,  2),
        Vec2.new(2,  3),
        Vec2.new(4,  5),
	
		Vec2.new(6,  7),
		Vec2.new(7,  8),
	
		Vec2.new(9,  10),
		Vec2.new(10,  11),
	    Vec2.new(11,  12),
	
		Vec2.new(13,  14),
		Vec2.new(14,  15),
	    Vec2.new(15,  16),
	
		Vec2.new(17,  18),
		Vec2.new(18,  19),
	    Vec2.new(19,  20),
		Vec2.new(20,  21),
		Vec2.new(21,  22),
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var overcan_buffer = [_]u8{0} ** (320 * 280);

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
        while(i < 40 * WIDTH) : (i += 1) {
            fb.fb[i] = overcan_buffer[i];
        }   
    }

    if(line == 40) {
        // copy text to fb
        var i: u16 = 0;
        const offset: u16 = 40 * WIDTH;
        while(i < WIDTH * HEIGHT) : ( i += 1){
            fb.fb[i] = overcan_buffer[i + offset];
        }
    }
    
    // Open low border and copy low buffer
    if(line == 240 and column == 40) {
        zigos.setResolution(Resolution.truecolor);

        // copy text to fb
        var i: u16 = WIDTH * (HEIGHT - 40);
        const offset: u16 = 80 * WIDTH;

        while(i < WIDTH * HEIGHT) : ( i += 1){
            fb.fb[i] = overcan_buffer[i + offset];
        }
    }

}

pub const Demo = struct {
  
    name: u8 = 0,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices_rectangle: [4]Coord = undefined,
    projected_vertices_yellow: [30]Coord = undefined,
    projected_vertices_red: [30]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,
    text: Text = undefined,
    render_target: RenderTarget = undefined,

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
        self.render_target = .{ .buffer = &overcan_buffer };        

        self.text.init(self.render_target, fonts_b, fonts_chars, 8, 8);

        var i: usize = 0;
        while(i < vertices_rectangle.len) : ( i += 1) {
		    vertices_rectangle[i] = vertices_rectangle[i].add(Vec4.new(-1.2, -0.4, -0.0, 0.0));
	    }
        i = 0;
        while(i < vertices_yellow.len) : ( i += 1) {
		    vertices_yellow[i] = vertices_yellow[i].add(Vec4.new(-1.2, -0.4, 0.3, 0.0));
	    }
        i = 0;
        while(i < vertices_red.len) : ( i += 1) {
		    vertices_red[i] = vertices_red[i].add(Vec4.new(-1.2, -0.4, 0.3, 0.0));
	    }                     

        // set lines colors
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(2, Color{ .r = 0xf0, .g = 0x10, .b = 0x10, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0xf0, .g = 0xf0, .b = 0x10, .a = 255 });
        fb.setPaletteEntry(4, Color{ .r = 0xf0, .g = 0xf0, .b = 0xf0, .a = 255 });

        self.projection = za.perspective(40.0, 200.0 / 320.0, 1, 1000);
        self.camera = za.camera(Vec3.new(0.0, 0.4, -4.5), 0, 0);
        self.screen = za.screen(320, 200);   

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        for(vertices_rectangle) |vertex, idx| {

            // const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            // const vertex_after_scale = rot_scale.vec4mulByMat4(vertex);

            const rot_matx = Mat4.fromEulerAngles(Vec3.new(self.angle_x, 0, 0));
            const vertex_after_rotx = rot_matx.vec4mulByMat4(vertex);

            const rot_maty = Mat4.fromEulerAngles(Vec3.new(0, self.angle_y, 0));
            const vertex_after_roty = rot_maty.vec4mulByMat4(vertex_after_rotx);

            const rot_matz = Mat4.fromEulerAngles(Vec3.new(0, 0, self.angle_z));
            const vertex_after_rotz = rot_matz.vec4mulByMat4(vertex_after_roty);            

            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_rotz);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            self.projected_vertices_rectangle[idx].x=coord_x;
            self.projected_vertices_rectangle[idx].y=coord_y;
        }        

        for(vertices_yellow) |vertex, idx| {

            // const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            // const vertex_after_scale = rot_scale.vec4mulByMat4(vertex);

            const rot_matx = Mat4.fromEulerAngles(Vec3.new(self.angle_x, 0, 0));
            const vertex_after_rotx = rot_matx.vec4mulByMat4(vertex);

            const rot_maty = Mat4.fromEulerAngles(Vec3.new(0, self.angle_y, 0));
            const vertex_after_roty = rot_maty.vec4mulByMat4(vertex_after_rotx);

            const rot_matz = Mat4.fromEulerAngles(Vec3.new(0, 0, self.angle_z));
            const vertex_after_rotz = rot_matz.vec4mulByMat4(vertex_after_roty);            

            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_rotz);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            self.projected_vertices_yellow[idx].x=coord_x;
            self.projected_vertices_yellow[idx].y=coord_y;
        }             

        for(vertices_red) |vertex, idx| {

            // const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            // const vertex_after_scale = rot_scale.vec4mulByMat4(vertex);

            const rot_matx = Mat4.fromEulerAngles(Vec3.new(self.angle_x, 0, 0));
            const vertex_after_rotx = rot_matx.vec4mulByMat4(vertex);

            const rot_maty = Mat4.fromEulerAngles(Vec3.new(0, self.angle_y, 0));
            const vertex_after_roty = rot_maty.vec4mulByMat4(vertex_after_rotx);

            const rot_matz = Mat4.fromEulerAngles(Vec3.new(0, 0, self.angle_z));
            const vertex_after_rotz = rot_matz.vec4mulByMat4(vertex_after_roty);            

            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_rotz);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            self.projected_vertices_red[idx].x=coord_x;
            self.projected_vertices_red[idx].y=coord_y;
        }              
   
        self.angle_x += 0.8;
        self.angle_y += 1.6;   
        self.angle_z += 3.2;   

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.render_target.clearFrameBuffer(0);
        self.render_text();

        for(segments_rectangle) |segment| {
            const v1: Coord = self.projected_vertices_rectangle[@floatToInt(usize, segment.x())];
            const v2: Coord = self.projected_vertices_rectangle[@floatToInt(usize, segment.y())];

            shapes.drawLine(self.render_target, v1, v2, 2);   
        }

        for(segments_yellow) |segment| {
            const v1: Coord = self.projected_vertices_yellow[@floatToInt(usize, segment.x())];
            const v2: Coord = self.projected_vertices_yellow[@floatToInt(usize, segment.y())];

            shapes.drawLine(self.render_target, v1, v2, 3);   
        }

        for(segments_red) |segment| {
            const v1: Coord = self.projected_vertices_red[@floatToInt(usize, segment.x())];
            const v2: Coord = self.projected_vertices_red[@floatToInt(usize, segment.y())];

            shapes.drawLine(self.render_target, v1, v2, 4);   
        }

        _ = elapsed_time;
        _ = zigos;

    }

    fn render_text(self: *Demo) void {

        self.text.render("****************************************",0, 0 * 8);
        self.text.render(" **   THE REPLICANTS AND ST AMIGOS   ** ",0, 1 * 8);
        self.text.render("    **   BRING YOU AN HOT STUFF   **    ",0, 2 * 8);
        self.text.render("       **************************       ",0, 3 * 8);
        
        self.text.render("   SAVAGELY BROKEN AN TRAINED BY MAXI",   0, 5 * 8);
        self.text.render("  ------------------------------------",  0, 6 * 8);
        self.text.render("  DIS BOOT WAS ALSO FAST CODED BY MAXI",  0, 7 * 8);
        self.text.render(" --------------------------------------", 0, 8 * 8);
        
        self.text.render("       COPY IN 2 SIDES 10 SECTORS",       0, 10 * 8);
        self.text.render("   THE MAGIC KEY FOR THE TRAINER IS *",   0, 11 * 8);
        self.text.render("SORRY FOR DIS LITTLE LAME CODE ,COZ THAT",0, 12 * 8);
        self.text.render("IS NOT MY BEST 3D LINE ROUT ,SO FAR NOT.",0, 13 * 8);
        self.text.render("THAT IS MY SHORTER ONE ! BUT IN 3 PLANES",0, 14 * 8);
        self.text.render("THE GOOD IS RATHER MY UPPER BORDER ROUT!",0, 15 * 8); 
        
        self.text.render("VERY SPECIAL REGARDS GO TO :",            0, 19 * 8);
        self.text.render(" THOR - AVB - ST WAIKIKI- MINIMAX - ZAE", 0, 20 * 8);
        self.text.render(" MAD VISION  - FUZION - LITTLESWAP -FOF", 0, 21 * 8);
        self.text.render("  BAD BOYS - MCA - ACB - THE REDUCTORS",  0, 22 * 8);
        self.text.render("  RCA AND ALL THE MEMBERS OF THE UNION",  0, 23 * 8);
        
        self.text.render("I SEND THE NORMAL GREETINGS TO :",       0, 25 * 8);
        self.text.render(" ST CONNEXION-IMAGINA-PHALANC-FF-TELLER",0, 26 * 8);
        self.text.render(" 2 LIVE CREW-PENDRAGONS-DRAGON-FRAISINE",0, 27 * 8);
        self.text.render(" DIMITRI-EQUINOX-TGE-SEWER SOFT-ACF-BMT",0, 28 * 8);
        self.text.render(" MEDWAY BOYS-OVR-MCS-TDA-LOST BOYS-NEXT",0, 29 * 8);
        self.text.render(" ULM-PARADOX-SYNC-OMEGA-INNER CIRCLE-MU",0, 30 * 8);

        self.text.render("ENJOY THE VIOLENCE..THE REPLICANTS RULEZ",0,32 * 8);
        self.text.render("****************************************",0,33 * 8);

    }
};
